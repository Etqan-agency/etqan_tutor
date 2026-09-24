# Plan 4 — Subscriptions & Scheduling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An academy admin turns a student's package into a running timetable: a subscription (student, course, teacher, package) with weekly slots and pauses generates its sessions ahead of time, an hourly job per academy moves subscriptions in and out of pauses, expires them after their grace period and keeps the horizon generated, and the admin sees today's slots on a Today board, generates any range on demand and renews a subscription with its extra sessions carried over.

**Architecture:** One new tenant app, `etqan.scheduling`, owns `Subscription`, `SubscriptionPause`, `ScheduleSlot` and `Session`. Its public API is the `etqan.scheduling.services` package: `rules.py` holds the one rule set (untouched sessions, term dates, derived values and carry-over, pause status), with `subscriptions.py` (admin actions and renewal), `generation.py`, `board.py` (Today) and `lifecycle.py` (the job's steps) on top; every date and time rule sits in `etqan.scheduling.dates`. The hourly Celery task loops academies through a new platform helper, `for_each_academy`, one transaction per academy. Endpoints live at `/api/v1/subscriptions/…`, `/pauses/…`, `/slots/…` and `/schedule/…`; the dashboard gets a Scheduling nav group with Today and Subscriptions, and Settings → Academy gains the horizon and grace days.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18, Celery 5.6 + django-celery-beat; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next, `Intl` for time zones; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-09-24-subscriptions-scheduling-design.md` (Phase B0 milestone 4 of `2026-09-24-parity-roadmap-design.md`; builds on `2026-09-23-etqan-tutor-v1-design.md` §4.4–4.6, §5.1, §5.3, §6 and on Plan 3, `2026-09-24-people-catalogue-design.md`). Where this spec and the v1 spec differ (expiry after grace, not at zero sessions; generation for `paused` subscriptions too), this spec wins.

**Verified:** the code in Tasks 1–15 was applied in order to copies of `backend@7658a56` and `dashboard@3c34c13` (the current `main` of each); after every task its format, lint, import-contract, test and coverage commands passed (backend 564 → 686 tests; dashboard 383 → 418 tests, coverage ≥ 89% lines, ≥ 75% functions), and the Task 16 e2e spec passed against Django + the Vite preview on a freshly seeded database. Migrations are generated in Tasks 1 and 2 with `makemigrations`, so only their timestamps will differ.

## Global Constraints

- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), meta repo (trunk `master`). Feature branch `feat/subscriptions-scheduling` in every touched repo. The meta branch already exists; create it in `backend/` (Task 1) and `dashboard/` (Task 10) before their first task: `git -C backend switch -c feat/subscriptions-scheduling`, same for `dashboard`. Nothing is merged without the user's approval. After merge, bump the submodule pointers in meta.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Backend commands run from `backend/` with the virtualenv `backend/.venv` and this environment exported once per shell:
  `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`
  Tests: `.venv/bin/pytest …` (add `--create-db` once after any task that adds migrations: Tasks 1 and 2). Format: `.venv/bin/ruff check --fix . && .venv/bin/ruff format .` (sorts the imports a step adds). Verify: `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`. Watch `PLR0911`/`PLR0913`: keyword-only service signatures that mirror an API body carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)`, like `tenants.services.create_academy`.
- Dashboard commands run from `dashboard/` through `npx pnpm@10`. Format: `npx pnpm@10 exec biome check --write src` (formats and organises imports). Verify: `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`. `pnpm lint` = `biome ci . && node scripts/check-colors.mjs`: no hex colour literals and no Tailwind palette utilities anywhere in `src/`, comments included; semantic tokens only (`bg-primary`, `text-muted-foreground`, `bg-secondary`, `text-destructive`, …). `tsc` has `noUnusedLocals`/`noUnusedParameters`.
- New route files are picked up by the TanStack Router plugin; regenerate `src/routeTree.gen.ts` with `npx pnpm@10 exec vite build` before `tsc`.
- Coverage gates: backend ≥ 80% (`pytest --cov=etqan`); dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; academies `demo` (`admin@demo.test`, timezone UTC) and `other` (`admin@other.test`).
- Tenancy: `etqan.scheduling` goes in `TENANT_APPS` only; migrate with `migrate_schemas`; background work loops academies with `tenant_context` (here through `etqan.platform.tenancy.for_each_academy`); no user-facing URL is built in this plan.
- Business logic lives in `etqan/scheduling/services/` (and `etqan.scheduling.dates`); views parse, call one service and arrange a payload; payloads call services, never recompute a rule. Other apps import only `etqan.scheduling.services`; scheduling reaches identity, catalogue and academy only through their `services`; models reference other apps' models by string. `lint-imports` enforces both directions.
- All API routes are under `/api/v1/`. Money is integer minor units + ISO 4217 currency. Stored instants (`Session.starts_at`) are UTC; `occurs_on`, `start_time` and every date on a subscription are the academy's wall calendar (`AcademySettings.timezone`).
- Spec values: `generation_horizon_days` 1–60 (default 14); `renewal_grace_days` 0–60 (default 7); subscription status `active · paused · expired · cancelled`; session status `scheduled · completed · cancelled`; attendance `not_set · present · absent · excused`; weekday `0 = Monday … 6 = Sunday`; slot minutes 15–240, default the subscription's `session_minutes`; `UNIQUE(slot, occurs_on)` where `slot` is not null; two active slots of one subscription never share weekday + start time; generate-for-range at most 62 days; the hourly Celery beat entry is `scheduling.run_daily`.
- Untouched session (P4-7): `status = scheduled`, both attendances `not_set`, `starts_at` in the future. Nothing automatic ever deletes any other session. Consuming session (Plan 4): `status = completed` and student attendance `present` or `absent`.
- Errors: rule violations are `409` with `{"detail": "<English sentence>", "code": "<rule>"}` (D10); field problems are `400` with Plan 3's shape `{"<field>": ["<message>"]}`; out-of-scope objects are `404`.
- Access: admin everything; teacher reads the subscriptions (and their slots, pauses, sessions) they teach; student reads their own; parent reads their children's; generate, Today, renew, cancel, delete and every write are admin-only. `scope_for(user, queryset)` is the one scoping function.
- No emails in this plan. A side effect after a database write that can roll back goes through `transaction.on_commit`.
- Lists `select_related`/`prefetch_related` what a row shows and derive values in bulk; the subscriptions list and the Today board have query-count tests.
- Every dashboard string exists in `src/locales/en/common.json` and `src/locales/ar/common.json`; zod messages are i18n keys (`scheduling.errors.…`) rendered through `useFieldError`; server rule codes render as `errors.<code>`. Required fields render `*` inside the `<label>`, so tests query `getByLabelText(/^Student/)`. Screens work RTL and at phone width. Reuse `Pager`, `clean`/`csvUrl`/`Paginated` (`@/lib/api`), `applyServerErrors`/`errorText` (`@/lib/form-errors`), `useFieldError`; no copies of generic helpers inside a feature. Detail pages handle a non-numeric id, a 404 and a load error with translated messages.
- Tests are non-vacuous: each assertion fails without the code under test; duplicate matches are scoped (`within(table)`, `within(dialog)`); cross-academy tests hold data in BOTH academies and prove the other academy's never appears.

### Decisions this plan makes where the spec is silent or conflicts with the code

- **D1 — The hourly job.** `etqan.platform.tenancy.for_each_academy(job, name=…)` loads the tenant model through `django_tenants.utils.get_tenant_model()` (so `etqan.platform` still imports no business module), skips the public schema and suspended academies, and runs `job` for each academy inside `tenant_context` and its own `transaction.atomic()`. An exception is logged with `logger.exception`, that academy's writes roll back, and the loop continues; it returns `{schema_name: "ok" | "failed"}`. The Celery task `etqan.scheduling.tasks.run_daily` (name `scheduling.run_daily`) calls it with `services.run_lifecycle`; beat runs it at minute 5 of every hour (`crontab(minute=5)`).
- **D2 — The clock and "today".** `etqan.scheduling.dates.now()` is the only clock the services read; "today" is `now()` on the academy's timezone (`dates.local_today(AcademySettings.timezone)`). Tests pin time with a `clock` fixture that monkeypatches `dates.now` (no new test dependency).
- **D3 — Month terms use the standard library.** `python-dateutil` is installed only as a Celery dependency, so `term_ends_on` uses `calendar.monthrange`: add n months; if the start day exists in that month, step back one day, else end on the month's last day (31 Jan + 1 → 28 or 29 Feb; 1 Mar + 1 → 31 Mar; 15 Jan + 2 → 14 Mar).
- **D4 — Local time → UTC.** `dates.to_utc` is `datetime.combine(day, start, tzinfo=ZoneInfo(tz)).astimezone(UTC)`. With the default `fold=0` this is exactly spec §4.1: a time in a spring-forward gap uses the offset before the change and so lands one gap later (02:30 → 03:30), and an ambiguous autumn time takes its first occurrence. The dashboard's `zonedInstant` exists only to display a student's local time.
- **D5 — The term that was sold is copied too.** A subscription also copies the package's `duration_value` and `duration_unit`, so editing `starts_on` recomputes `term_ends_on` from what was sold, not from a package edited since (P4-5). The spec lists the other copies but not these.
- **D6 — Course and package deletes.** Subscriptions and sessions `PROTECT` their course, package, student and teacher. `catalogue_services.delete_course`/`delete_package` turn Django's `ProtectedError` into a 409 `catalogue.in_use` ("deactivate it instead"), the delete guard STATE.md asked Plan 4 for, without catalogue importing scheduling.
- **D7 — One rule set.** `services/rules.py` holds `untouched_sessions()`, `CONSUMING`, `MARKED`, `term()`, `derive()`, `sync_pause_status()`, `renewal_starts_on()` and the API read models, each once. `derive(subscriptions)` computes every derived value of §3.2 in a constant number of queries: pauses are prefetched, and one aggregate over all subscriptions of the rows' students returns `(sessions_total, renewed_from_id, sessions_used)`; a renewal chain never changes student (D17), so carry-over is computed oldest-first in memory. `progress` is capped at 1.0 in the payload; the list shows extras as a "+N extra" badge. `Derived` also carries `in_grace` (`ends_on < today ≤ grace_ends_on` while live) and `freeze_days_left`.
- **D8 — Subscription payloads.** A list row is `{id, status, student: {id, full_name, timezone}, teacher: {id, full_name}, course: {id, name_ar, name_en}, package: {id, name_ar, name_en}, starts_on, term_ends_on, ends_on, grace_ends_on, in_grace, sessions_total, sessions_used, carried_over_sessions, sessions_remaining, extra_sessions, progress, price_minor, currency, renewed_from, renewal}` (people by User id). The detail adds `duration_value, duration_unit, session_minutes, freeze_days_allowed, paused_days, freeze_days_left, notes, renewal_starts_on, slots: [{id, weekday, start_time "HH:MM", minutes, meeting_url, is_active, has_sessions}], pauses: [{id, from_date, to_date, reason, days, state: upcoming|current|past}]`. Every write on a subscription, its pauses or slots answers with the subscription's detail (`201` for creates and renewals — the renewal answers with the NEW subscription), deletes answer `204`.
- **D9 — Today and generation payloads.** `GET /schedule/today/` → `{date, rows: [{slot_id, subscription_id, session_id, date, start_time, starts_at, minutes, state, student: {id, full_name, timezone}, teacher, course, sessions_total, sessions_used, carried_over_sessions, extra_sessions, progress}]}`, ordered by start time; `starts_at` is the session's, or the computed UTC instant for a `missing` row. `POST /schedule/generate/` takes `{from, to, subscription?}`: the optional `subscription` is how the Today board's "Generate" runs "for that subscription and date" (§4.3), which §5's body leaves out. It returns `{created, skipped_existing, skipped_paused, skipped_out_of_term, conflicts: [{session, other}]}` with full session rows.
- **D10 — Coded conflicts.** `ConflictError(message, code="conflict")`; the exception handler adds `"code"` to every 409 body. The dashboard's `parseApiError` keeps `code` apart from field errors, `applyServerErrors` turns it into the form-level i18n key `errors.<code>`, and `errorText(error, t)` does the same for toasts, falling back to the server's message.
- **D11 — Codes beyond the spec's five.** Besides `scheduling.not_allowed_in_status`, `already_renewed`, `freeze_days_exceeded`, `pause_overlaps` and `has_marked_sessions`, the rules the spec states without naming a code get one: `scheduling.pause_not_current` (end early a pause that does not cover today), `scheduling.pause_started` (delete a pause that has started), `scheduling.slot_has_sessions` (delete a slot that produced sessions), and `catalogue.in_use` (D6).
- **D12 — Double-booking detection.** After inserting, one query loads every non-cancelled session of the created sessions' teachers from the earliest start minus 240 minutes to the latest end; overlap is `a.start < b.end and b.start < a.end` in Python, so back-to-back sessions are not a conflict. Each pair is listed once; cancelled sessions never count. Created rows are re-read by `(slot, date)` because `bulk_create(ignore_conflicts=True)` returns no primary keys.
- **D13 — What generation creates.** Today's session is created even when its start time has passed (the Today board shows it; it is past, so never deleted automatically). An admin range may include past dates (a backfill). A subscription starting beyond the horizon gets its sessions when the job reaches them.
- **D14 — The student's local time (SCHED-017).** The payloads carry `student.timezone` (`User.timezone`). `@/lib/zoned-time.studentTime` turns the academy wall time into an instant with `Intl` (two-pass offset, so a clock change resolves correctly) and formats it on the student's clock, only when that reads differently. The new-subscription form uses its start date, the slots panel today, and Today each row's date.
- **D15 — Seeds.** `seed_subscriptions` runs only when the academy has no subscription, with dates relative to the academy's today. Demo: Yusuf Omar / Tajweed / Bilal / monthly (active, started 10 days ago); Aisha Omar / Quran Memorisation / Maryam / monthly with a pause from yesterday to +3 (paused); Zaid Huda / two-week intensive started 17 days ago (ended 4 days ago, in grace until +3); Yusuf Omar / Quran Memorisation / two-week intensive from today. Other: Layla Nabil / Arabic Grammar / Kareem / monthly. The demo monthly package gains `freeze_days_allowed: 7`; a database seeded before Plan 4 (0 freeze days) gets no paused subscription rather than an error. Seeding generates the normal horizon and sends nothing.
- **D16 — Navigation.** A new `NavGroup` `"scheduling"` holds Today (`/scheduling/today`) and Subscriptions (`/scheduling/subscriptions`), placed first after Home because it is the daily screen; admin-only like the other groups. `/scheduling` redirects to Today.
- **D17 — Renewal details.** The student never changes: §5's renew body has no `student`, although §4.2 says "all of them can be changed"; carry-over also assumes one student per chain. The price defaults to the old price (P4-10) unless the chosen package has another currency, then to that package's price. Active slots are copied; a slot on the old package length follows the new package's minutes, a custom length is kept. The default start (`renewal_starts_on`: day after `ends_on`, or today if later) is in the detail payload, so the dialog pre-fills from the one server rule. Renewal locks the old row (`select_for_update`), so a double submit gets one renewal and one `already_renewed`.
- **D18 — Editing.** §6 lists no edit screen, but §4.2 and §5 allow PATCH of teacher, price, notes and start date, so the detail page has an Edit dialog. A new teacher must be active and, when the course lists teachers, one of them. Moving `starts_on` past an existing pause's start is a field error (it would break "a pause starts on or after `starts_on`").
- **D19 — Pauses move the term.** Adding a pause regenerates the horizon (the term grew). Ending a pause early or deleting a future one first deletes untouched sessions after the new grace end, then regenerates.
- **D20 — Choosing people and catalogue.** Creating needs an active student, an active course and package, and an active teacher (on the course's list when it has one); each failure is a field error on `student`, `course`, `package` or `teacher`. The dashboard pickers load active rows with `page_size: 100`, with a "Find a student" search that narrows the student list by name.

## Review Focus

- **Clock changes and time zones.** An academy in a daylight-saving zone must get sessions at the right UTC instant on the changeover days (a spring-forward 02:30 slot lands at 03:30, an autumn 01:30 slot takes the first 01:30), half-hour zones must not drift, and a student in another zone must see their own clock. Tests: Task 2 (`test_to_utc`: New York gap and overlap, Kolkata), Task 4 (`test_clock_change_times_move_forward`, `test_starts_at_is_read_in_the_academy_timezone`, `test_missing_rows_use_the_academy_timezone`), Task 10 (`zoned-time.test.ts`).
- **Sessions someone relies on are never deleted.** A teacher change, a new start date, a pause, a slot edit or stop, a cancel, a renewal and expiry must each remove only untouched sessions, never past, marked or completed ones. Tests: Task 4 (`test_untouched_means_scheduled_unmarked_and_in_the_future`), Task 5 (`test_a_new_teacher_replaces_only_untouched_sessions`, `test_cancel_keeps_past_and_marked_sessions`, `test_a_pause_covering_today_pauses_at_once`, `test_editing_a_slot_replaces_its_untouched_sessions`), Task 6 (`test_old_untouched_sessions_from_the_new_start_are_removed`, `test_expiry_after_grace_deletes_untouched_sessions`).
- **Carry-over after renewal.** Grace sessions taught on the old subscription and marked after the renewal must still reduce the new term, and extras larger than a whole package must roll through a chain of renewals. Tests: Task 3 (`test_extras_carry_into_the_renewal_live`, `test_carry_over_chains_and_goes_negative`), Task 6 (`test_grace_sessions_taught_after_renewal_are_carried_over`).
- **The hourly job over many academies.** Running it twice changes nothing, and one academy's failure leaves the others done and its own writes rolled back. Tests: Task 1 (`test_runs_in_every_academy_and_survives_one_failing`, `test_skips_suspended_academies`), Task 6 (`test_pauses_start_and_end_with_the_calendar`, `test_expiry_after_grace_deletes_untouched_sessions`, `test_the_hourly_job_runs_every_academy_and_survives_one_failing`).
- **Month ends and leap years.** A term starting on the 29th–31st, in February of a leap year or crossing a year must end on the date the spec gives. Tests: Task 2 (`test_term_ends_on`: 31 Jan → 28 Feb 2026 and 29 Feb 2028, 30 Jan 2028, 31 Mar, 15 Nov + 3 months, 29 Feb 2028 + 12 months).

---

## File Structure

```
backend/
  config/settings/base.py          TENANT_APPS += etqan.scheduling; CELERY_BEAT_SCHEDULE["scheduling.run_daily"]
  config/api_router.py             + "" → etqan.scheduling.api.urls
  pyproject.toml                   import-linter: platform/academy forbid scheduling; scheduling ↔ other apps via services
  etqan/platform/
    exceptions.py drf.py           ConflictError(code); 409 bodies carry "code"
    tenancy.py                     NEW for_each_academy
  etqan/academy/                   generation_horizon_days, renewal_grace_days (+ migration 0003, API, tests)
  etqan/catalogue/services.py      get_course, get_package, find_course, find_package; 409 catalogue.in_use on delete
  etqan/scheduling/                NEW tenant app
    models.py                      Subscription, SubscriptionPause, ScheduleSlot, Session
    dates.py                       now, local_today, term_ends_on, to_utc, inclusive_days, days_between
    scopes.py                      scope_for(user, queryset, via="")
    tasks.py                       run_daily (Celery, "scheduling.run_daily")
    services/__init__.py           the public API (re-exports)
    services/rules.py              untouched_sessions, term, derive/derived, sync_pause_status, renewal_starts_on, read models
    services/subscriptions.py      create, update, cancel, delete, pauses, slots, renew
    services/generation.py         generate, generate_horizon, double-bookings
    services/board.py              today_board
    services/lifecycle.py          run_lifecycle (job steps 1–3)
    api/{payloads,serializers,views,urls}.py
    migrations/0001_initial.py
    tests/conftest.py test_dates.py test_subscriptions.py test_rules.py test_generation.py test_today.py
          test_actions.py test_renewal.py test_lifecycle.py test_api_subscriptions.py test_api_schedule.py
  etqan/tenants/management/commands/seed_dev.py   seed_subscriptions
dashboard/
  src/lib/api.ts form-errors.ts zoned-time.ts     Paginated; errorText + rule codes; time-zone and date helpers
  src/features/identity/api.ts     parseApiError: code, nested lists
  src/features/academy/…           horizon and grace fields
  src/features/scheduling/         NEW schemas api queries bits choices TermFields SlotFields SubscriptionsList
                                   SubscriptionForm SubscriptionDetail SubscriptionActions RenewDialog EditDialog
                                   SlotsPanel PausesPanel SessionsPanel TodayBoard GenerateDialog index
  src/test/scheduling-fixtures.ts  API-shaped rows for tests
  src/routes/_authed/scheduling{,.index,.today,.subscriptions.index,.subscriptions.new,.subscriptions.$subscriptionId}.tsx
  src/features/shell/nav.ts        "scheduling" group
  src/locales/{en,ar}/common.json
  e2e/subscriptions.spec.ts
meta: STATE.md, submodule pointers
```

---

### Task 1: Groundwork: coded 409s, `for_each_academy`, horizon and grace settings

**Files:**
- Create: `backend/etqan/platform/tenancy.py`, `backend/etqan/platform/tests/test_tenancy.py`
- Create (generated): `backend/etqan/academy/migrations/0003_scheduling_settings.py`
- Modify: `backend/etqan/platform/exceptions.py`, `backend/etqan/platform/drf.py`, `backend/etqan/platform/tests/test_drf.py`
- Modify: `backend/etqan/academy/models.py`, `backend/etqan/academy/services.py`, `backend/etqan/academy/api/serializers.py`, `backend/etqan/academy/tests/test_services.py`, `backend/etqan/academy/tests/test_api.py`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ConflictError(message: str, code: str = "conflict")`; every 409 body is `{"detail": str, "code": str}` (D10).
- Produces: `etqan.platform.tenancy.for_each_academy(job: Callable[[], object], *, name: str) -> dict[str, str]` — runs `job` in every active academy (not public, not suspended), each inside `tenant_context` + its own `transaction.atomic()`; returns `{schema_name: "ok" | "failed"}`; a failure is logged with `logger.exception` and rolled back (D1).
- Produces: `AcademySettings.generation_horizon_days` (1–60, default 14) and `.renewal_grace_days` (0–60, default 7); `academy_services.update_settings(..., generation_horizon_days=None, renewal_grace_days=None)` raises `ValidationError(field=…)` out of range; `GET/PATCH /api/v1/academy/settings/` carries both.

- [ ] **Step 1: Branch**

Both submodules are on `main`. Create the feature branch in `backend/` now and in `dashboard/` before Task 10:

```bash
git -C backend switch -c feat/subscriptions-scheduling
```

- [ ] **Step 2: Write the failing tests**

In `backend/etqan/platform/tests/test_drf.py`, replace:

```python
    assert response.data == {"detail": "Already taken."}
    assert ConflictError("x").code == "conflict"
```

with:

```python
    assert response.data == {"detail": "Already taken.", "code": "conflict"}
    assert ConflictError("x").code == "conflict"


def test_a_conflict_names_its_rule_in_the_body():
    response = exception_handler(
        ConflictError("Renewed already.", code="scheduling.already_renewed"), {}
    )
    assert response.status_code == status.HTTP_409_CONFLICT
    assert response.data == {
        "detail": "Renewed already.",
        "code": "scheduling.already_renewed",
    }
```

Create `backend/etqan/platform/tests/test_tenancy.py`:

```python
import logging

from django.contrib.auth.models import Group
from django.db import connection
from django_tenants.utils import get_tenant_model
from django_tenants.utils import tenant_context

from etqan.platform.tenancy import for_each_academy


def test_runs_in_every_academy_and_survives_one_failing(tenants, caplog):
    main, other = tenants.main.schema_name, tenants.other.schema_name
    seen = []

    def job():
        seen.append(connection.schema_name)
        Group.objects.create(name="job-ran")
        if connection.schema_name == other:
            raise RuntimeError("boom")

    with caplog.at_level(logging.ERROR, logger="etqan.platform.tenancy"):
        results = for_each_academy(job, name="test-job")

    assert results[main] == "ok"
    assert results[other] == "failed"
    assert tenants.public.schema_name not in results
    assert {main, other} <= set(seen)
    assert f"test-job failed for academy {other}" in caplog.text
    # The failing academy's write is rolled back; the healthy one's is kept.
    assert Group.objects.filter(name="job-ran").exists()
    with tenant_context(tenants.other):
        assert not Group.objects.filter(name="job-ran").exists()
    # The caller's schema is restored afterwards.
    assert connection.schema_name == main


def test_skips_suspended_academies(tenants):
    get_tenant_model().objects.filter(pk=tenants.other.pk).update(status="suspended")
    results = for_each_academy(lambda: None, name="test-job")
    assert tenants.other.schema_name not in results
    assert results[tenants.main.schema_name] == "ok"
```

Append to the end of `backend/etqan/academy/tests/test_services.py`:

```python
def test_scheduling_defaults_and_bounds():
    s = services.get_settings()
    assert (s.generation_horizon_days, s.renewal_grace_days) == (14, 7)
    s = services.update_settings(generation_horizon_days=60, renewal_grace_days=0)
    assert (s.generation_horizon_days, s.renewal_grace_days) == (60, 0)
    for field, value in (
        ("generation_horizon_days", 0),
        ("generation_horizon_days", 61),
        ("renewal_grace_days", -1),
        ("renewal_grace_days", 61),
    ):
        with pytest.raises(ValidationError) as exc:
            services.update_settings(**{field: value})
        assert exc.value.field == field
```

Append to the end of `backend/etqan/academy/tests/test_api.py`:

```python
def test_admin_sets_horizon_and_grace(api_for):
    admin = api_for("admin")
    assert admin.get(URL).json()["generation_horizon_days"] == 14
    resp = admin.patch(
        URL, {"generation_horizon_days": 30, "renewal_grace_days": 0}, format="json"
    )
    body = resp.json()
    assert resp.status_code == 200, body
    assert (body["generation_horizon_days"], body["renewal_grace_days"]) == (30, 0)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("generation_horizon_days", 0),
        ("generation_horizon_days", 61),
        ("renewal_grace_days", 61),
    ],
)
def test_horizon_and_grace_bounds(api_for, field, value):
    resp = api_for("admin").patch(URL, {field: value}, format="json")
    assert resp.status_code == 400
    assert field in resp.json()
```

- [ ] **Step 3: Run them to verify they fail**

Every backend command runs with the environment from Global Constraints exported once per shell: `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`.

Run (from `backend/`): `.venv/bin/pytest -q etqan/platform/tests/test_drf.py etqan/platform/tests/test_tenancy.py etqan/academy`
Expected: FAIL — `ModuleNotFoundError: No module named 'etqan.platform.tenancy'`, the 409 body has no `code`, and `update_settings()` rejects `generation_horizon_days`.

- [ ] **Step 4: Implement**

In `backend/etqan/platform/exceptions.py`, replace:

```python
    def __init__(self, message: str):
        super().__init__(message=message, code="conflict")
```

with:

```python
    def __init__(self, message: str, code: str = "conflict"):
        # `code` names the rule that refused the request (for example
        # "scheduling.already_renewed"). The API returns it next to `detail` so
        # clients can show their own translated wording.
        super().__init__(message=message, code=code)
```

In `backend/etqan/platform/drf.py`, replace:

```python
        body = {field: [exc.message]} if field else {"detail": exc.message}
        return Response(body, status=http_status)
```

with:

```python
        body = {field: [exc.message]} if field else {"detail": exc.message}
        if isinstance(exc, ConflictError):
            body["code"] = exc.code
        return Response(body, status=http_status)
```

Create `backend/etqan/platform/tenancy.py`:

```python
"""Background work runs once per academy (CLAUDE.md: never assume one schema)."""

import logging
from collections.abc import Callable

from django.db import transaction
from django_tenants.utils import get_public_schema_name
from django_tenants.utils import get_tenant_model
from django_tenants.utils import tenant_context

logger = logging.getLogger(__name__)


def for_each_academy(job: Callable[[], object], *, name: str) -> dict[str, str]:
    """Run ``job`` inside every active academy's schema, one transaction each.

    A failing academy is logged and rolled back, and the loop moves on to the
    next one. Suspended academies are skipped. Returns
    ``{schema_name: "ok" | "failed"}``.
    """
    academies = (
        get_tenant_model()
        .objects.exclude(schema_name=get_public_schema_name())
        .filter(status="active")
        .order_by("schema_name")
    )
    results: dict[str, str] = {}
    for academy in academies:
        try:
            with tenant_context(academy), transaction.atomic():
                job()
        except Exception:
            logger.exception("%s failed for academy %s", name, academy.schema_name)
            results[academy.schema_name] = "failed"
        else:
            results[academy.schema_name] = "ok"
    return results
```

In `backend/etqan/academy/models.py`, replace:

```python
from django.core.validators import RegexValidator
```

with:

```python
from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
```

In `backend/etqan/academy/models.py`, replace:

```python
    default_language = models.CharField(
        max_length=2, choices=Language.choices, default=Language.AR
    )
    created_at
```

with:

```python
    default_language = models.CharField(
        max_length=2, choices=Language.choices, default=Language.AR
    )
    # Plan 4 (spec §3.1): how many days ahead sessions are generated, and how
    # long a subscription keeps generating after its end date before it expires.
    generation_horizon_days = models.PositiveSmallIntegerField(
        default=14, validators=[MinValueValidator(1), MaxValueValidator(60)]
    )
    renewal_grace_days = models.PositiveSmallIntegerField(
        default=7, validators=[MinValueValidator(0), MaxValueValidator(60)]
    )
    created_at
```

In `backend/etqan/academy/services.py`, replace:

```python
from etqan.academy.models import AcademySettings
```

with:

```python
from etqan.academy.models import AcademySettings
from etqan.platform.exceptions import ValidationError
```

In `backend/etqan/academy/services.py`, replace:

```python
def update_settings(
    *,
    timezone: str | None = None,
    default_currency: str | None = None,
    default_language: str | None = None,
) -> AcademySettings:
```

with:

```python
HORIZON_DAYS = (1, 60)
GRACE_DAYS = (0, 60)


def _days(value: int, bounds: tuple[int, int], field: str) -> int:
    low, high = bounds
    if not low <= value <= high:
        raise ValidationError(f"Choose a number from {low} to {high}.", field=field)
    return value


def update_settings(
    *,
    timezone: str | None = None,
    default_currency: str | None = None,
    default_language: str | None = None,
    generation_horizon_days: int | None = None,
    renewal_grace_days: int | None = None,
) -> AcademySettings:
```

In `backend/etqan/academy/services.py`, replace:

```python
    settings_row.save()
    return settings_row
```

with:

```python
    if generation_horizon_days is not None:
        settings_row.generation_horizon_days = _days(
            generation_horizon_days, HORIZON_DAYS, "generation_horizon_days"
        )
    if renewal_grace_days is not None:
        settings_row.renewal_grace_days = _days(
            renewal_grace_days, GRACE_DAYS, "renewal_grace_days"
        )
    settings_row.save()
    return settings_row
```

In `backend/etqan/academy/api/serializers.py`, replace:

```python
    default_language = serializers.ChoiceField(choices=["ar", "en"], required=False)
```

with:

```python
    default_language = serializers.ChoiceField(choices=["ar", "en"], required=False)
    generation_horizon_days = serializers.IntegerField(
        min_value=1, max_value=60, required=False
    )
    renewal_grace_days = serializers.IntegerField(
        min_value=0, max_value=60, required=False
    )
```

Generate the migration (the academy app has two already):

Run (from `backend/`): `.venv/bin/python manage.py makemigrations academy --name scheduling_settings --settings=config.settings.test`
Expected: `etqan/academy/migrations/0003_scheduling_settings.py` with `+ Add field generation_horizon_days to academysettings` and `+ Add field renewal_grace_days to academysettings`.

- [ ] **Step 5: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q --create-db etqan/platform etqan/academy`
Expected: PASS. `--create-db` because of the new migration.

- [ ] **Step 6: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 7: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(platform): coded conflicts, per-academy job runner, horizon and grace settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `etqan.scheduling` app: models, migration and the one date module

**Files:**
- Create: `backend/etqan/scheduling/__init__.py`, `backend/etqan/scheduling/apps.py`, `backend/etqan/scheduling/models.py`, `backend/etqan/scheduling/dates.py`, `backend/etqan/scheduling/migrations/__init__.py`, `backend/etqan/scheduling/migrations/0001_initial.py` (generated), `backend/etqan/scheduling/tests/__init__.py`, `backend/etqan/scheduling/tests/test_dates.py`
- Modify: `backend/config/settings/base.py` (`TENANT_APPS`), `backend/pyproject.toml` (import-linter)

**Interfaces:**
- Consumes: nothing.
- Produces models (`etqan.scheduling.models`): `Subscription` (`Status`: `active · paused · expired · cancelled`; `DurationUnit`: `day · month`; FKs `student`→`identity.StudentProfile`, `teacher`→`identity.TeacherProfile`, `course`→`catalogue.Course`, `package`→`catalogue.Package`, all `PROTECT`, reverse names `+` on identity models, `subscriptions` on catalogue; `renewed_from` one-to-one `SET_NULL`, reverse `renewal`), `SubscriptionPause` (reverse `pauses`), `ScheduleSlot` (reverse `slots`), `Session` (`Status`: `scheduled · completed · cancelled`; `Attendance`: `not_set · present · absent · excused`; `slot` and `subscription` nullable `PROTECT`, reverse `sessions`).
- Produces `etqan.scheduling.dates`: `now() -> datetime` (the only clock; tests monkeypatch it), `local_today(tz_name) -> date`, `term_ends_on(starts_on, duration_value, duration_unit) -> date`, `to_utc(day, start: time, tz_name) -> datetime`, `inclusive_days(first, last) -> int`, `days_between(first, last)` (inclusive generator).

- [ ] **Step 1: Write the failing test**

Create `backend/etqan/scheduling/tests/__init__.py`:

```python

```

Create `backend/etqan/scheduling/tests/test_dates.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest

from etqan.scheduling import dates


def utc(*parts):
    return datetime(*parts, tzinfo=UTC)


@pytest.mark.parametrize(
    ("starts_on", "value", "unit", "expected"),
    [
        (date(2026, 3, 1), 1, "month", date(2026, 3, 31)),
        (date(2026, 1, 31), 1, "month", date(2026, 2, 28)),
        (date(2028, 1, 31), 1, "month", date(2028, 2, 29)),  # leap year
        (date(2028, 1, 30), 1, "month", date(2028, 2, 29)),
        (date(2026, 1, 15), 2, "month", date(2026, 3, 14)),
        (date(2026, 3, 31), 1, "month", date(2026, 4, 30)),
        (date(2026, 11, 15), 3, "month", date(2027, 2, 14)),  # crosses the year
        (date(2026, 12, 1), 1, "month", date(2026, 12, 31)),
        (date(2028, 2, 29), 12, "month", date(2029, 2, 28)),
        (date(2026, 5, 10), 1, "day", date(2026, 5, 10)),
        (date(2026, 5, 10), 14, "day", date(2026, 5, 23)),
        (date(2026, 12, 25), 10, "day", date(2027, 1, 3)),
    ],
)
def test_term_ends_on(starts_on, value, unit, expected):
    assert dates.term_ends_on(starts_on, value, unit) == expected


def test_term_ends_on_rejects_an_unknown_unit():
    with pytest.raises(ValueError, match="week"):
        dates.term_ends_on(date(2026, 1, 1), 1, "week")


@pytest.mark.parametrize(
    ("day", "start", "tz", "expected"),
    [
        (date(2026, 6, 1), time(18, 0), "UTC", utc(2026, 6, 1, 18, 0)),
        (date(2026, 6, 1), time(18, 0), "Asia/Riyadh", utc(2026, 6, 1, 15, 0)),
        (date(2026, 1, 5), time(9, 0), "Africa/Cairo", utc(2026, 1, 5, 7, 0)),
        (date(2026, 1, 5), time(9, 0), "America/New_York", utc(2026, 1, 5, 14, 0)),
        (date(2026, 7, 6), time(9, 0), "America/New_York", utc(2026, 7, 6, 13, 0)),
        # Spring forward, 8 Mar 2026: 02:30 does not exist, so it moves to 03:30.
        (date(2026, 3, 8), time(2, 30), "America/New_York", utc(2026, 3, 8, 7, 30)),
        # Fall back, 1 Nov 2026: 01:30 happens twice; the first one (EDT) wins.
        (date(2026, 11, 1), time(1, 30), "America/New_York", utc(2026, 11, 1, 5, 30)),
        # A half-hour zone, across midnight UTC.
        (date(2026, 6, 1), time(3, 0), "Asia/Kolkata", utc(2026, 5, 31, 21, 30)),
    ],
)
def test_to_utc(day, start, tz, expected):
    assert dates.to_utc(day, start, tz) == expected


def test_local_today_follows_the_academy_timezone(monkeypatch):
    monkeypatch.setattr(dates, "now", lambda: utc(2026, 6, 1, 22, 30))
    assert dates.local_today("UTC") == date(2026, 6, 1)
    assert dates.local_today("Asia/Riyadh") == date(2026, 6, 2)
    assert dates.local_today("America/New_York") == date(2026, 6, 1)


def test_days_between_is_inclusive():
    days = list(dates.days_between(date(2026, 2, 27), date(2026, 3, 2)))
    assert days == [
        date(2026, 2, 27),
        date(2026, 2, 28),
        date(2026, 3, 1),
        date(2026, 3, 2),
    ]
    assert dates.inclusive_days(date(2026, 1, 1), date(2026, 1, 1)) == 1
```

- [ ] **Step 2: Run it to verify it fails**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_dates.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'etqan.scheduling'`.

- [ ] **Step 3: Create the app**

Create `backend/etqan/scheduling/__init__.py`:

```python

```

Create `backend/etqan/scheduling/migrations/__init__.py`:

```python

```

Create `backend/etqan/scheduling/apps.py`:

```python
from django.apps import AppConfig


class SchedulingConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.scheduling"
    label = "scheduling"
```

Create `backend/etqan/scheduling/models.py`:

```python
"""Subscriptions, their pauses and weekly slots, and the sessions they produce.

Other apps' models are referenced by string: scheduling never imports them
(CLAUDE.md, plan D2). Business rules live in `etqan.scheduling.services`.
"""

from django.core.validators import MaxValueValidator
from django.core.validators import MinValueValidator
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import F
from django.db.models import Q

MINUTES = [MinValueValidator(15), MaxValueValidator(240)]


class Subscription(models.Model):
    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        PAUSED = "paused", "Paused"
        EXPIRED = "expired", "Expired"
        CANCELLED = "cancelled", "Cancelled"

    class DurationUnit(models.TextChoices):
        DAY = "day", "Day"
        MONTH = "month", "Month"

    # PROTECT: people are deactivated, never deleted, and a course or package
    # with subscriptions must be deactivated instead of deleted (plan D6).
    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    course = models.ForeignKey(
        "catalogue.Course", on_delete=models.PROTECT, related_name="subscriptions"
    )
    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    package = models.ForeignKey(
        "catalogue.Package", on_delete=models.PROTECT, related_name="subscriptions"
    )
    starts_on = models.DateField()
    term_ends_on = models.DateField()
    # Copied from the package at creation (P4-5); later package edits never
    # reach an existing subscription. The duration is copied too, so editing
    # `starts_on` recomputes the term that was sold (plan D5).
    duration_value = models.PositiveSmallIntegerField()
    duration_unit = models.CharField(max_length=5, choices=DurationUnit.choices)
    sessions_total = models.PositiveIntegerField()
    session_minutes = models.PositiveSmallIntegerField(validators=MINUTES)
    freeze_days_allowed = models.PositiveSmallIntegerField()
    price_minor = models.BigIntegerField(validators=[MinValueValidator(0)])
    currency = models.CharField(
        max_length=3, validators=[RegexValidator(r"^[A-Z]{3}$")]
    )
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.ACTIVE
    )
    renewed_from = models.OneToOneField(
        "self",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="renewal",
    )
    notes = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-starts_on", "-id"]
        indexes = [models.Index(fields=["status"])]

    def __str__(self):
        return f"Subscription<{self.pk}, {self.status}>"


class SubscriptionPause(models.Model):
    subscription = models.ForeignKey(
        Subscription, on_delete=models.CASCADE, related_name="pauses"
    )
    from_date = models.DateField()
    to_date = models.DateField()
    reason = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["from_date", "id"]
        constraints = [
            models.CheckConstraint(
                condition=Q(from_date__lte=F("to_date")),
                name="scheduling_pause_dates_in_order",
            )
        ]

    def __str__(self):
        return f"Pause<{self.from_date}..{self.to_date}>"


class ScheduleSlot(models.Model):
    subscription = models.ForeignKey(
        Subscription, on_delete=models.CASCADE, related_name="slots"
    )
    weekday = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(0), MaxValueValidator(6)]
    )  # 0 = Monday … 6 = Sunday, like date.weekday()
    start_time = models.TimeField()  # wall-clock time in the academy's timezone
    minutes = models.PositiveSmallIntegerField(validators=MINUTES)
    meeting_url = models.URLField(blank=True, default="")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["weekday", "start_time", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["subscription", "weekday", "start_time"],
                condition=Q(is_active=True),
                name="scheduling_slot_active_unique",
            )
        ]

    def __str__(self):
        return f"Slot<{self.weekday} {self.start_time}>"


class Session(models.Model):
    class Status(models.TextChoices):
        SCHEDULED = "scheduled", "Scheduled"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"

    class Attendance(models.TextChoices):
        NOT_SET = "not_set", "Not set"
        PRESENT = "present", "Present"
        ABSENT = "absent", "Absent"
        EXCUSED = "excused", "Excused"

    slot = models.ForeignKey(
        ScheduleSlot,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="sessions",
    )
    subscription = models.ForeignKey(
        Subscription,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="sessions",
    )
    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    course = models.ForeignKey(
        "catalogue.Course", on_delete=models.PROTECT, related_name="sessions"
    )
    occurs_on = models.DateField()  # local date in the academy's timezone
    starts_at = models.DateTimeField()  # UTC
    minutes = models.PositiveSmallIntegerField(validators=MINUTES)
    meeting_url = models.URLField(blank=True, default="")
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.SCHEDULED
    )
    student_attendance = models.CharField(
        max_length=8, choices=Attendance.choices, default=Attendance.NOT_SET
    )
    teacher_attendance = models.CharField(
        max_length=8, choices=Attendance.choices, default=Attendance.NOT_SET
    )
    cancel_reason = models.TextField(blank=True, default="")
    notes = models.TextField(blank=True, default="")
    generated = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["starts_at", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["slot", "occurs_on"],
                condition=Q(slot__isnull=False),
                name="scheduling_session_slot_day_unique",
            )
        ]
        indexes = [
            models.Index(fields=["teacher", "starts_at"]),
            models.Index(fields=["occurs_on"]),
        ]

    def __str__(self):
        return f"Session<{self.occurs_on} {self.status}>"
```

Create `backend/etqan/scheduling/dates.py`:

```python
"""Every date and time rule of scheduling, in one place (spec §3.2, §4.1, §9).

`now()` is the only clock the scheduling services read, so tests pin time by
monkeypatching `etqan.scheduling.dates.now`.
"""

import calendar
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.utils import timezone

DAY = "day"
MONTH = "month"
MONTHS_PER_YEAR = 12


def now() -> datetime:
    """The current instant, timezone-aware UTC."""
    return timezone.now()


def local_today(tz_name: str) -> date:
    """Today's date on the academy's wall calendar."""
    return now().astimezone(ZoneInfo(tz_name)).date()


def term_ends_on(starts_on: date, duration_value: int, duration_unit: str) -> date:
    """The last day of a term (spec §3.2).

    A ``day`` term of n days ends n - 1 days after the start. A ``month`` term
    adds n calendar months and steps back one day; when the start day does not
    exist in the target month (31 Jan + 1 month), the term ends on that month's
    last day instead.
    """
    if duration_unit == DAY:
        return starts_on + timedelta(days=duration_value - 1)
    if duration_unit == MONTH:
        months = starts_on.month - 1 + duration_value
        year = starts_on.year + months // MONTHS_PER_YEAR
        month = months % MONTHS_PER_YEAR + 1
        last_day = calendar.monthrange(year, month)[1]
        if starts_on.day > last_day:
            return date(year, month, last_day)
        return date(year, month, starts_on.day) - timedelta(days=1)
    raise ValueError(f"Unknown duration unit: {duration_unit!r}")


def to_utc(day: date, start: time, tz_name: str) -> datetime:
    """The UTC instant of wall-clock ``start`` on ``day`` in ``tz_name``.

    ``fold=0`` (the default) gives both clock-change rules of spec §4.1: a
    local time that falls in a spring-forward gap is read with the offset
    before the change, so it lands one gap later (02:30 → 03:30), and an
    ambiguous autumn time takes its first occurrence.
    """
    local = datetime.combine(day, start, tzinfo=ZoneInfo(tz_name))
    return local.astimezone(UTC)


def inclusive_days(first: date, last: date) -> int:
    return (last - first).days + 1


def days_between(first: date, last: date):
    """Every date from ``first`` to ``last``, both included."""
    for offset in range(inclusive_days(first, last)):
        yield first + timedelta(days=offset)
```

In `backend/config/settings/base.py`, replace:

```python
    "etqan.catalogue",
]
INSTALLED_APPS
```

with:

```python
    "etqan.catalogue",
    "etqan.scheduling",
]
INSTALLED_APPS
```

In `backend/pyproject.toml` (the `platform imports no business modules` contract), replace:

```toml
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue"]
```

with:

```toml
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling"]
```

In `backend/pyproject.toml` (the `academy imports no other business module` contract), replace:

```toml
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.catalogue"]
```

with:

```toml
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.catalogue", "etqan.scheduling"]
```

Append to the end of `backend/pyproject.toml`:

```toml
[[tool.importlinter.contracts]]
name = "scheduling reaches other apps only through their services"
type = "forbidden"
source_modules = ["etqan.scheduling"]
forbidden_modules = [
    "etqan.identity.models", "etqan.identity.api",
    "etqan.catalogue.models", "etqan.catalogue.api",
    "etqan.academy.models", "etqan.academy.api",
    "etqan.tenants", "etqan.site",
]
# scheduling.services -> identity.services -> identity.models is the allowed path.
allow_indirect_imports = true
```

Run (from `backend/`): `.venv/bin/python manage.py makemigrations scheduling --settings=config.settings.test`
Expected: `etqan/scheduling/migrations/0001_initial.py`: `Create model ScheduleSlot`, `Subscription`, `Session`, `SubscriptionPause`, three indexes and the constraints `scheduling_session_slot_day_unique`, `scheduling_slot_active_unique`, `scheduling_pause_dates_in_order`.

- [ ] **Step 4: Format, then run the test**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q --create-db etqan/scheduling`
Expected: PASS (23 tests: 12 term ends including 31 Jan → 28 Feb and 31 Jan 2028 → 29 Feb, 8 UTC conversions including the New York spring-forward gap and fall-back overlap).

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass; `lint-imports` reports the new contract KEPT.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): subscriptions, pauses, slots and sessions models with the date rules

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Create a subscription; derived values and carry-over; scopes; the catalogue delete guard

**Files:**
- Create: `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/services/rules.py`, `backend/etqan/scheduling/services/subscriptions.py`, `backend/etqan/scheduling/scopes.py`
- Create: `backend/etqan/scheduling/tests/conftest.py`, `backend/etqan/scheduling/tests/test_subscriptions.py`, `backend/etqan/scheduling/tests/test_rules.py`
- Modify: `backend/etqan/catalogue/services.py` (`get_course`, `get_package`, deletes refused with 409 `catalogue.in_use`)

**Interfaces:**
- Consumes: `dates` (Task 2); `identity_services.get_student_profile(user_id)`, `get_teacher_profile(user_id)`, `get_children(parent_user_id)`; `catalogue_services.sessions_total(package)`, `teacher_user_ids_for_course(course_id)`; `academy_services.get_settings()`.
- Produces `etqan.scheduling.services.rules`: `LIVE`, `CONSUMING` (dict of lookups), `MARKED` (Q), `settings()`, `today() -> date` (academy-local), `untouched_sessions(**filters) -> QuerySet[Session]` (the only deletable sessions, P4-7), `has_marked_sessions(sub) -> bool`, `require_status(sub, allowed=LIVE)` (409 `scheduling.not_allowed_in_status`), `covering_pause(sub, day)`, `Term(paused_days, ends_on, grace_ends_on)`, `term(sub, grace_days) -> Term`, `Derived` (fields `paused_days, freeze_days_left, ends_on, grace_ends_on, in_grace, sessions_used, carried_over_sessions, sessions_remaining, extra_sessions, progress`), `derive(subs) -> dict[int, Derived]` (constant queries), `derived(sub) -> Derived`.
- Produces `services.create_subscription(*, student_id, course_id, teacher_id, package_id, starts_on, price_minor=None, notes="", slots=(), renewed_from=None) -> Subscription`; slot dicts are `{weekdays, start_time, minutes?, meeting_url?}`; field errors use the body names `student`, `course`, `teacher`, `package`, `price_minor`, `slots`.
- Produces `etqan.scheduling.scopes.scope_for(user, queryset, *, via="")` — admin all, teacher `teacher__user`, student `student__user`, parent children, others none; `via="subscription"` for slots and pauses.
- Produces `catalogue_services.get_course(id) -> Course | None`, `get_package(id) -> Package | None`; `delete_course`/`delete_package` raise `ConflictError(code="catalogue.in_use")` when subscriptions or sessions hold them.
- Test fixtures (`etqan/scheduling/tests/conftest.py`): `clock` (`clock.set(datetime)`; starts Monday 1 June 2026 08:00 UTC), `world` (Bilal teaching Tajweed, Yusuf in Asia/Riyadh, a monthly 2×45-minute package with 10 freeze days), `subscribe(**overrides)`, and plain helpers `build_world()`, `subscription_for(world, **overrides)`, `make_teacher`, `make_student`, `two_slots(start=time(18))`, `MONDAY`, `WEDNESDAY`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/conftest.py`:

```python
"""Shared scheduling fixtures. Time is pinned: the services read only
`etqan.scheduling.dates.now`, and the `clock` fixture replaces it."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from types import SimpleNamespace

import pytest

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.scheduling import dates
from etqan.scheduling import services

# Monday 1 June 2026, 08:00 UTC. The academy's timezone defaults to UTC.
START = datetime(2026, 6, 1, 8, 0, tzinfo=UTC)
MONDAY, WEDNESDAY = 0, 2


class Clock:
    def __init__(self, monkeypatch):
        self._monkeypatch = monkeypatch
        self.set(START)

    def set(self, when: datetime) -> None:
        self._monkeypatch.setattr(dates, "now", lambda: when)


@pytest.fixture
def clock(monkeypatch):
    return Clock(monkeypatch)


def make_teacher(name="Bilal", **profile):
    return identity_services.create_person(
        "teacher", full_name=name, profile={"gender": "male", **profile}
    )


def make_student(name="Yusuf", **user):
    return identity_services.create_person("student", full_name=name, **user)


def build_world():
    """A student, a teacher listed on the course, and a monthly package of
    2 x 45 minutes a week (8 sessions) with 10 freeze days, in the current
    academy."""
    teacher = make_teacher(default_meeting_url="https://meet.test/bilal")
    course = catalogue_services.create_course(
        name_ar="تجويد", name_en="Tajweed", teacher_ids=[teacher.id]
    )
    package = catalogue_services.create_package(
        name_ar="شهري",
        name_en="Monthly",
        sessions_per_week=2,
        session_minutes=45,
        duration_value=1,
        duration_unit="month",
        freeze_days_allowed=10,
        price_minor=150000,
        currency="EGP",
    )
    return SimpleNamespace(
        teacher=teacher,
        student=make_student(timezone="Asia/Riyadh"),
        course=course,
        package=package,
    )


def two_slots(start=time(18, 0)):
    return [{"weekdays": [MONDAY, WEDNESDAY], "start_time": start}]


def subscription_for(world, **overrides):
    """A subscription for ``world`` from Monday 1 June 2026."""
    fields = {
        "student_id": world.student.id,
        "course_id": world.course.id,
        "teacher_id": world.teacher.id,
        "package_id": world.package.id,
        "starts_on": date(2026, 6, 1),
        **overrides,
    }
    return services.create_subscription(**fields)


@pytest.fixture
def world(clock):
    return build_world()


@pytest.fixture
def subscribe(world):
    """`subscribe(**overrides)` → a subscription for `world`."""
    return lambda **overrides: subscription_for(world, **overrides)
```

Create `backend/etqan/scheduling/tests/test_subscriptions.py`:

```python
from datetime import date
from datetime import time

import pytest

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import WEDNESDAY
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots


def test_create_copies_the_package(subscribe, world):
    sub = subscribe()
    assert (sub.status, sub.term_ends_on) == ("active", date(2026, 6, 30))
    assert (sub.sessions_total, sub.session_minutes, sub.freeze_days_allowed) == (
        8,
        45,
        10,
    )
    assert (sub.price_minor, sub.currency) == (150000, "EGP")
    assert (sub.duration_value, sub.duration_unit) == (1, "month")
    # P4-5: editing the package later changes nothing on the subscription.
    catalogue_services.update_package(
        world.package, sessions_per_week=5, price_minor=1, duration_unit="day"
    )
    sub.refresh_from_db()
    assert (sub.sessions_total, sub.price_minor, sub.duration_unit) == (
        8,
        150000,
        "month",
    )


def test_price_can_be_set_at_creation(subscribe):
    assert subscribe(price_minor=120000).price_minor == 120000
    with pytest.raises(ValidationError) as exc:
        subscribe(price_minor=-1)
    assert exc.value.field == "price_minor"


def test_slots_one_per_weekday_with_the_package_minutes(subscribe):
    sub = subscribe(slots=two_slots())
    slots = ScheduleSlot.objects.filter(subscription=sub)
    assert [(s.weekday, s.start_time, s.minutes) for s in slots] == [
        (MONDAY, time(18, 0), 45),
        (WEDNESDAY, time(18, 0), 45),
    ]


def test_two_active_slots_never_share_a_time(subscribe):
    with pytest.raises(ValidationError) as exc:
        subscribe(
            slots=[
                {"weekdays": [MONDAY], "start_time": time(18, 0)},
                {"weekdays": [MONDAY], "start_time": time(18, 0), "minutes": 30},
            ]
        )
    assert exc.value.field == "slots"


@pytest.mark.parametrize("field", ["student", "course", "teacher", "package"])
def test_create_refuses_the_wrong_people_and_inactive_catalogue(
    subscribe, world, field
):
    if field == "student":
        overrides = {"student_id": world.teacher.id}
    elif field == "course":
        catalogue_services.update_course(world.course, is_active=False)
        overrides = {}
    elif field == "teacher":
        overrides = {"teacher_id": make_teacher("Not listed").id}
    else:
        catalogue_services.update_package(world.package, is_active=False)
        overrides = {}
    with pytest.raises(ValidationError) as exc:
        subscribe(**overrides)
    assert exc.value.field == field


def test_inactive_people_are_refused(subscribe, world):
    identity_services.deactivate(world.teacher, by=None)
    with pytest.raises(ValidationError) as exc:
        subscribe()
    assert exc.value.field == "teacher"
    identity_services.activate(world.teacher)
    identity_services.deactivate(world.student, by=None)
    with pytest.raises(ValidationError) as exc:
        subscribe()
    assert exc.value.field == "student"


def test_a_course_without_teachers_takes_any_active_teacher(subscribe, world):
    catalogue_services.update_course(world.course, teacher_ids=[])
    other = make_teacher("Maryam")
    assert subscribe(teacher_id=other.id).teacher.user_id == other.id


def test_a_course_or_package_with_subscriptions_is_deactivated_not_deleted(
    subscribe, world
):
    subscribe(student_id=make_student("Aisha").id)
    for delete, obj in (
        (catalogue_services.delete_course, world.course),
        (catalogue_services.delete_package, world.package),
    ):
        with pytest.raises(ConflictError) as exc:
            delete(obj)
        assert exc.value.code == "catalogue.in_use"
```

Create `backend/etqan/scheduling/tests/test_rules.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import timedelta

from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.identity import services as identity_services
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.scopes import scope_for
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher


def add_session(sub, day, *, status="scheduled", attendance="not_set", hour=18):
    return Session.objects.create(
        subscription=sub,
        student=sub.student,
        teacher=sub.teacher,
        course=sub.course,
        occurs_on=day,
        starts_at=datetime(day.year, day.month, day.day, hour, tzinfo=UTC),
        minutes=45,
        status=status,
        student_attendance=attendance,
    )


def consume(sub, count, first=date(2026, 6, 1)):
    for n in range(count):
        add_session(
            sub, first + timedelta(days=n), status="completed", attendance="present"
        )


def test_plain_subscription(subscribe):
    d = services.derived(subscribe())
    assert (d.paused_days, d.ends_on, d.grace_ends_on) == (
        0,
        date(2026, 6, 30),
        date(2026, 7, 7),
    )
    assert (d.sessions_used, d.carried_over_sessions, d.sessions_remaining) == (
        0,
        0,
        8,
    )
    assert (d.extra_sessions, d.progress, d.in_grace, d.freeze_days_left) == (
        0,
        0.0,
        False,
        10,
    )


def test_pauses_push_the_end_and_grace_uses_the_current_setting(subscribe):
    sub = subscribe()
    SubscriptionPause.objects.create(
        subscription=sub, from_date=date(2026, 6, 10), to_date=date(2026, 6, 12)
    )
    SubscriptionPause.objects.create(
        subscription=sub, from_date=date(2026, 6, 20), to_date=date(2026, 6, 20)
    )
    academy_services.update_settings(renewal_grace_days=0)
    d = services.derived(sub)
    assert (d.paused_days, d.freeze_days_left) == (4, 6)
    assert (d.ends_on, d.grace_ends_on) == (date(2026, 7, 4), date(2026, 7, 4))


def test_only_completed_present_or_absent_sessions_are_used(subscribe):
    sub = subscribe()
    add_session(sub, date(2026, 6, 1), status="completed", attendance="present")
    add_session(sub, date(2026, 6, 2), status="completed", attendance="absent")
    add_session(sub, date(2026, 6, 3), status="completed", attendance="excused")
    add_session(sub, date(2026, 6, 4), status="cancelled", attendance="absent")
    add_session(sub, date(2026, 6, 5))
    d = services.derived(sub)
    assert (d.sessions_used, d.sessions_remaining, d.progress) == (2, 6, 0.25)


def test_extras_carry_into_the_renewal_live(subscribe):
    old = subscribe()
    consume(old, 10)  # 2 beyond the package's 8
    new = subscribe(starts_on=date(2026, 7, 8))
    Subscription.objects.filter(pk=new.pk).update(renewed_from=old)
    new.refresh_from_db()
    assert services.derived(old).extra_sessions == 2
    d = services.derived(new)
    assert (d.carried_over_sessions, d.sessions_remaining, d.progress) == (
        2,
        6,
        0.25,
    )
    # A grace session marked on the old subscription after the renewal.
    add_session(old, date(2026, 7, 6), status="completed", attendance="present", hour=9)
    assert services.derived(new).carried_over_sessions == 3


def test_carry_over_chains_and_goes_negative(subscribe):
    first = subscribe()
    consume(first, 20)  # 12 extra
    second = subscribe(starts_on=date(2026, 7, 8))
    third = subscribe(starts_on=date(2026, 8, 8))
    Subscription.objects.filter(pk=second.pk).update(renewed_from=first)
    Subscription.objects.filter(pk=third.pk).update(renewed_from=second)
    second.refresh_from_db()
    third.refresh_from_db()
    found = services.derive([second, third])
    # 12 carried into an 8-session term leaves it 4 over, carried again.
    assert (found[second.pk].sessions_remaining, found[second.pk].extra_sessions) == (
        -4,
        4,
    )
    assert found[second.pk].progress == 1.0  # shown capped
    assert found[third.pk].carried_over_sessions == 4


def test_in_grace_between_the_end_and_the_grace_end(subscribe, clock):
    sub = subscribe()
    clock.set(datetime(2026, 7, 3, 9, tzinfo=UTC))
    assert services.derived(sub).in_grace is True
    clock.set(datetime(2026, 6, 30, 9, tzinfo=UTC))
    assert services.derived(sub).in_grace is False


def test_derive_costs_the_same_queries_for_one_or_many(subscribe, world):
    subs = [subscribe(student_id=make_student(f"S{n}").id) for n in range(4)]
    for sub in subs:
        consume(sub, 1)

    def queries(batch):
        fresh = list(Subscription.objects.filter(pk__in=[s.pk for s in batch]))
        with CaptureQueriesContext(connection) as ctx:
            services.derive(fresh)
        return len(ctx.captured_queries)

    assert queries(subs[:1]) == queries(subs)


def test_scope_for_each_role(subscribe, world):
    mine = subscribe()
    other_student = make_student("Aisha")
    other_teacher = make_teacher("Maryam")
    theirs = subscribe(student_id=other_student.id)
    parent = identity_services.create_person("parent", full_name="Omar")
    identity_services.link_guardian(parent, world.student)
    stranger = identity_services.create_person("parent", full_name="Huda")
    admin = identity_services.create_person(
        "admin", full_name="Boss", email="boss@x.test", invite=False
    )
    everything = Subscription.objects.all()

    def ids(user):
        return set(scope_for(user, everything).values_list("pk", flat=True))

    assert ids(admin) == {mine.pk, theirs.pk}
    assert ids(world.teacher) == {mine.pk, theirs.pk}
    assert ids(other_teacher) == set()
    assert ids(world.student) == {mine.pk}
    assert ids(parent) == {mine.pk}
    assert ids(stranger) == set()
    pauses = SubscriptionPause.objects.all()
    SubscriptionPause.objects.create(
        subscription=theirs, from_date=date(2026, 6, 2), to_date=date(2026, 6, 2)
    )
    assert not scope_for(world.student, pauses, via="subscription").exists()
    assert scope_for(other_student, pauses, via="subscription").count() == 1
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: FAIL — `ImportError: cannot import name 'services' from 'etqan.scheduling'`.

- [ ] **Step 3: Implement the rules, create and scopes**

Create `backend/etqan/scheduling/services/rules.py`:

```python
"""The rules subscriptions and sessions share (P4-1). One implementation each."""

from dataclasses import dataclass
from datetime import date
from datetime import timedelta

from django.db.models import Count
from django.db.models import Q
from django.db.models import QuerySet
from django.db.models import prefetch_related_objects

from etqan.academy import services as academy_services
from etqan.platform.exceptions import ConflictError
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause

LIVE = (Subscription.Status.ACTIVE, Subscription.Status.PAUSED)
NOT_SET = Session.Attendance.NOT_SET
# Plan 4's consumption rule (spec §3.2); Plan 5 may add academy switches.
CONSUMING = {
    "status": Session.Status.COMPLETED,
    "student_attendance__in": (Session.Attendance.PRESENT, Session.Attendance.ABSENT),
}
# A session someone has acted on: attendance marked or completed.
MARKED = (
    Q(status=Session.Status.COMPLETED)
    | ~Q(student_attendance=NOT_SET)
    | ~Q(teacher_attendance=NOT_SET)
)


def settings():
    return academy_services.get_settings()


def today() -> date:
    """The academy's local date."""
    return dates.local_today(settings().timezone)


def untouched_sessions(**filters) -> QuerySet[Session]:
    """The only sessions automatic changes may delete (P4-7): scheduled, no
    attendance marked, and starting in the future."""
    return Session.objects.filter(
        status=Session.Status.SCHEDULED,
        student_attendance=NOT_SET,
        teacher_attendance=NOT_SET,
        starts_at__gt=dates.now(),
        **filters,
    )


def has_marked_sessions(subscription: Subscription) -> bool:
    return Session.objects.filter(MARKED, subscription=subscription).exists()


def require_status(subscription: Subscription, allowed=LIVE) -> None:
    if subscription.status not in allowed:
        raise ConflictError(
            f"Not allowed while the subscription is {subscription.status}.",
            code="scheduling.not_allowed_in_status",
        )


def covering_pause(subscription: Subscription, day: date) -> SubscriptionPause | None:
    """The pause that includes ``day``. Reads the (prefetched) pauses."""
    for pause in subscription.pauses.all():
        if pause.from_date <= day <= pause.to_date:
            return pause
    return None


@dataclass(frozen=True)
class Term:
    paused_days: int
    ends_on: date
    grace_ends_on: date


def term(subscription: Subscription, grace_days: int) -> Term:
    """``ends_on`` and ``grace_ends_on`` (spec §3.2). Reads the pauses."""
    paused = sum(
        dates.inclusive_days(p.from_date, p.to_date) for p in subscription.pauses.all()
    )
    ends_on = subscription.term_ends_on + timedelta(days=paused)
    return Term(paused, ends_on, ends_on + timedelta(days=grace_days))


@dataclass(frozen=True)
class Derived:
    paused_days: int
    freeze_days_left: int
    ends_on: date
    grace_ends_on: date
    in_grace: bool
    sessions_used: int
    carried_over_sessions: int
    sessions_remaining: int
    extra_sessions: int
    progress: float


def _usage(student_ids) -> dict[int, tuple[int, int | None, int]]:
    """``{id: (sessions_total, renewed_from_id, sessions_used)}`` for every
    subscription of these students, in one query. A renewal chain never
    changes student, so this holds every link of every chain."""
    consuming = Q(**{f"sessions__{key}": value for key, value in CONSUMING.items()})
    rows = (
        Subscription.objects.filter(student_id__in=student_ids)
        .annotate(used=Count("sessions", filter=consuming))
        .values_list("id", "sessions_total", "renewed_from_id", "used")
    )
    return {row[0]: row[1:] for row in rows}


def _carried_over(usage) -> dict[int, int]:
    """Each subscription's carried-over sessions: its predecessor's extras,
    computed live so a grace session marked after renewal still counts."""
    carried: dict[int, int] = {}
    extra: dict[int, int] = {}
    # A renewal is always created after what it renews, so ids go oldest first.
    for sub_id in sorted(usage):
        total, previous, used = usage[sub_id]
        carried[sub_id] = extra.get(previous, 0) if previous else 0
        extra[sub_id] = max(0, carried[sub_id] + used - total)
    return carried


def derive(subscriptions) -> dict[int, Derived]:
    """Every derived value of spec §3.2 for these subscriptions, keyed by id.

    The one implementation: payloads, the Today board and the job all call it.
    A constant number of queries however many subscriptions are passed.
    """
    subscriptions = list(subscriptions)
    if not subscriptions:
        return {}
    prefetch_related_objects(subscriptions, "pauses")
    academy = settings()
    local_today = dates.local_today(academy.timezone)
    usage = _usage({s.student_id for s in subscriptions})
    carried = _carried_over(usage)
    result = {}
    for sub in subscriptions:
        span = term(sub, academy.renewal_grace_days)
        used = usage[sub.pk][2]
        remaining = sub.sessions_total - carried[sub.pk] - used
        consumed = carried[sub.pk] + used
        result[sub.pk] = Derived(
            paused_days=span.paused_days,
            freeze_days_left=max(0, sub.freeze_days_allowed - span.paused_days),
            ends_on=span.ends_on,
            grace_ends_on=span.grace_ends_on,
            in_grace=sub.status in LIVE
            and span.ends_on < local_today <= span.grace_ends_on,
            sessions_used=used,
            carried_over_sessions=carried[sub.pk],
            sessions_remaining=remaining,
            extra_sessions=max(0, -remaining),
            progress=min(1.0, consumed / sub.sessions_total)
            if sub.sessions_total
            else 1.0,
        )
    return result


def derived(subscription: Subscription) -> Derived:
    return derive([subscription])[subscription.pk]
```

Create `backend/etqan/scheduling/services/subscriptions.py`:

```python
"""Subscriptions and everything an admin does to them (spec §4.2)."""

from collections.abc import Iterable
from datetime import date
from datetime import time

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import from_django
from etqan.scheduling import dates
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Subscription

WEEKDAYS = range(7)


def _save(obj) -> None:
    try:
        # Constraints are checked first, with a readable message, by the caller.
        obj.full_clean(validate_constraints=False)
    except DjangoValidationError as exc:
        raise from_django(exc) from None
    obj.save()


# ── Who and what a subscription is for ───────────────────────────────────────


def _student(user_id: int):
    profile = identity_services.get_student_profile(user_id)
    if profile is None or profile.user.role != "student" or not profile.user.is_active:
        raise ValidationError("Choose an active student.", field="student")
    return profile


def _course(course_id: int):
    course = catalogue_services.get_course(course_id)
    if course is None or not course.is_active:
        raise ValidationError("Choose an active course.", field="course")
    return course


def _package(package_id: int):
    package = catalogue_services.get_package(package_id)
    if package is None or not package.is_active:
        raise ValidationError("Choose an active package.", field="package")
    return package


def _teacher(user_id: int, course):
    """An active teacher, and one of the course's teachers when it lists any."""
    profile = identity_services.get_teacher_profile(user_id)
    if profile is None or profile.user.role != "teacher" or not profile.user.is_active:
        raise ValidationError("Choose an active teacher.", field="teacher")
    allowed = catalogue_services.teacher_user_ids_for_course(course.pk)
    if allowed and user_id not in allowed:
        raise ValidationError(
            "This teacher does not teach the course.", field="teacher"
        )
    return profile


def _copy_package(subscription: Subscription, package) -> None:
    """P4-5: the package's numbers are copied; later package edits never reach
    this subscription."""
    subscription.package = package
    subscription.duration_value = package.duration_value
    subscription.duration_unit = package.duration_unit
    subscription.sessions_total = catalogue_services.sessions_total(package)
    subscription.session_minutes = package.session_minutes
    subscription.freeze_days_allowed = package.freeze_days_allowed
    subscription.currency = package.currency
    subscription.term_ends_on = dates.term_ends_on(
        subscription.starts_on, package.duration_value, package.duration_unit
    )


# ── Slots ─────────────────────────────────────────────────────────────────────


def _slot_taken(subscription: Subscription, weekday: int, start: time, *, exclude=None):
    slots = ScheduleSlot.objects.filter(
        subscription=subscription, weekday=weekday, start_time=start, is_active=True
    )
    if exclude is not None:
        slots = slots.exclude(pk=exclude.pk)
    return slots.exists()


def _add_slots(  # noqa: PLR0913 -- keyword-only; mirrors the slot body (spec §5)
    subscription: Subscription,
    *,
    weekdays: Iterable[int],
    start_time: time,
    minutes: int | None = None,
    meeting_url: str = "",
    field: str = "start_time",
) -> list[ScheduleSlot]:
    """One active slot per weekday; two active slots never share a time."""
    created = []
    for weekday in sorted(set(weekdays)):
        if weekday not in WEEKDAYS:
            raise ValidationError("Choose days from Monday to Sunday.", field=field)
        if _slot_taken(subscription, weekday, start_time):
            raise ValidationError("There is already a slot at this time.", field=field)
        slot = ScheduleSlot(
            subscription=subscription,
            weekday=weekday,
            start_time=start_time,
            minutes=minutes or subscription.session_minutes,
            meeting_url=meeting_url or "",
        )
        _save(slot)
        created.append(slot)
    return created


# ── Create ────────────────────────────────────────────────────────────────────


@transaction.atomic
def create_subscription(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    *,
    student_id: int,
    course_id: int,
    teacher_id: int,
    package_id: int,
    starts_on: date,
    price_minor: int | None = None,
    notes: str = "",
    slots: Iterable[dict] = (),
    renewed_from: Subscription | None = None,
) -> Subscription:
    """Spec §4.2 Create: copy the package, add the slots, generate the horizon."""
    course = _course(course_id)
    package = _package(package_id)
    subscription = Subscription(
        student=_student(student_id),
        course=course,
        teacher=_teacher(teacher_id, course),
        starts_on=starts_on,
        notes=notes,
        renewed_from=renewed_from,
    )
    _copy_package(subscription, package)
    subscription.price_minor = (
        package.price_minor if price_minor is None else price_minor
    )
    _save(subscription)
    for slot in slots:
        _add_slots(subscription, **slot, field="slots")
    return subscription
```

Create `backend/etqan/scheduling/services/__init__.py`:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import today
from etqan.scheduling.services.rules import untouched_sessions
from etqan.scheduling.services.subscriptions import create_subscription

__all__ = [
    "Derived",
    "create_subscription",
    "derive",
    "derived",
    "has_marked_sessions",
    "today",
    "untouched_sessions",
]
```

Create `backend/etqan/scheduling/scopes.py`:

```python
"""Who sees which subscriptions and sessions (spec §4.4). Out of scope → 404."""

from etqan.identity import services as identity_services
from etqan.platform.permissions import role_of


def scope_for(user, queryset, *, via: str = ""):
    """Filter a Subscription or Session queryset (``via=""``), or a queryset
    that reaches one through ``via`` (``"subscription"`` for slots and pauses)."""
    role = role_of(user)
    prefix = f"{via}__" if via else ""
    if role == "admin":
        return queryset
    if role == "teacher":
        return queryset.filter(**{f"{prefix}teacher__user": user})
    if role == "student":
        return queryset.filter(**{f"{prefix}student__user": user})
    if role == "parent":
        children = identity_services.get_children(user.pk)
        return queryset.filter(**{f"{prefix}student__in": children})
    return queryset.none()
```

- [ ] **Step 4: Refuse deleting a course or package that has subscriptions**

Subscriptions and sessions `PROTECT` their course and package, so Django raises `ProtectedError` before deleting anything; the service turns it into a 409 (the STATE.md follow-up from Plan 3).

In `backend/etqan/catalogue/services.py`, replace:

```python
from django.db import transaction
```

with:

```python
from django.db import transaction
from django.db.models import ProtectedError
```

In `backend/etqan/catalogue/services.py`, replace:

```python
from etqan.platform.exceptions import ValidationError
```

with:

```python
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
```

In `backend/etqan/catalogue/services.py`, replace:

```python
def delete_course(course: Course) -> None:
    # P3-5: in Plan 3 nothing references a course yet; Plan 4 refuses deleting
    # a course that has subscriptions and asks the admin to deactivate it.
    course.delete()
```

with:

```python
def _delete(obj, noun: str) -> None:
    """Subscriptions and sessions PROTECT what they sold: deactivate instead."""
    try:
        obj.delete()
    except ProtectedError:
        raise ConflictError(
            f"This {noun} has subscriptions. Deactivate it instead.",
            code="catalogue.in_use",
        ) from None


def get_course(course_id: int) -> Course | None:
    return Course.objects.filter(pk=course_id).first()


def delete_course(course: Course) -> None:
    _delete(course, "course")
```

In `backend/etqan/catalogue/services.py`, replace:

```python
def delete_package(package: Package) -> None:
    package.delete()
```

with:

```python
def get_package(package_id: int) -> Package | None:
    return Package.objects.filter(pk=package_id).first()


def delete_package(package: Package) -> None:
    _delete(package, "package")
```

- [ ] **Step 5: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling etqan/catalogue`
Expected: PASS. `test_derive_costs_the_same_queries_for_one_or_many` proves `derive` is N+1-free; `test_extras_carry_into_the_renewal_live` proves a grace session marked after renewal still reaches the new term.

- [ ] **Step 6: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): create subscriptions, derived values with live carry-over, role scopes

Courses and packages with subscriptions are deactivated, not deleted (409 catalogue.in_use).

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Generation, double-bookings and the Today board service

**Files:**
- Create: `backend/etqan/scheduling/services/generation.py`, `backend/etqan/scheduling/services/board.py`, `backend/etqan/scheduling/tests/test_generation.py`, `backend/etqan/scheduling/tests/test_today.py`
- Modify: `backend/etqan/scheduling/services/rules.py` (append `SESSION_RELATED`), `backend/etqan/scheduling/services/subscriptions.py` (create generates the horizon), `backend/etqan/scheduling/services/__init__.py`

**Interfaces:**
- Consumes: Task 3 rules, `dates.to_utc`, `dates.local_today`.
- Produces `services.GenerationResult(created, skipped_existing, skipped_paused, skipped_out_of_term, conflicts: list[tuple[Session, Session]])`, `services.generate(first: date, last: date, *, subscription=None) -> GenerationResult`, `services.generate_horizon(subscription=None) -> GenerationResult` (today … today + `generation_horizon_days`, inclusive).
- Produces `services.TodayRow(day, slot, subscription, starts_at, session, state, derived)` and `services.today_board(day=None) -> list[TodayRow]`; `state` is `generated · missing · completed · cancelled`.
- Produces `rules.SESSION_RELATED` — the `select_related` for a session row.
- Changes: `create_subscription` now generates its horizon.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/test_generation.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta

from etqan.academy import services as academy_services
from etqan.scheduling import services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import two_slots

JUNE_1 = date(2026, 6, 1)


def days(sub):
    return list(
        Session.objects.filter(subscription=sub).values_list("occurs_on", flat=True)
    )


def test_creating_a_subscription_generates_the_horizon(subscribe, world):
    sub = subscribe(slots=two_slots())
    # Today (Mon 1 June) through today + 14 days, Mondays and Wednesdays.
    assert days(sub) == [
        date(2026, 6, 1),
        date(2026, 6, 3),
        date(2026, 6, 8),
        date(2026, 6, 10),
        date(2026, 6, 15),
    ]
    first = Session.objects.filter(subscription=sub).first()
    assert first.starts_at == datetime(2026, 6, 1, 18, 0, tzinfo=UTC)
    assert (first.minutes, first.meeting_url, first.generated) == (
        45,
        "https://meet.test/bilal",
        True,
    )
    assert (first.status, first.student_attendance, first.teacher_attendance) == (
        "scheduled",
        "not_set",
        "not_set",
    )
    assert (first.student_id, first.teacher_id, first.course_id) == (
        sub.student_id,
        sub.teacher_id,
        sub.course_id,
    )


def test_generation_is_idempotent(subscribe):
    sub = subscribe(slots=two_slots())
    again = services.generate_horizon(sub)
    assert (again.created, again.skipped_existing) == (0, 5)
    assert len(days(sub)) == 5


def test_window_boundaries_and_grace(subscribe):
    sub = subscribe(starts_on=date(2026, 6, 3), slots=two_slots())
    # Term 3 Jun - 2 Jul, grace 7 days -> 9 Jul.
    result = services.generate(JUNE_1, date(2026, 7, 31), subscription=sub)
    assert (result.created, result.skipped_existing) == (7, 4)
    assert result.skipped_out_of_term == 7
    assert days(sub)[0] == date(2026, 6, 3)
    assert days(sub)[-1] == date(2026, 7, 8)


def test_zero_grace_stops_at_the_end_date(subscribe):
    academy_services.update_settings(renewal_grace_days=0)
    sub = subscribe(slots=two_slots())
    services.generate(JUNE_1, date(2026, 7, 31), subscription=sub)
    assert days(sub)[-1] == date(2026, 6, 29)


def test_pauses_are_skipped_and_extend_the_term(subscribe):
    sub = subscribe()
    SubscriptionPause.objects.create(
        subscription=sub, from_date=date(2026, 6, 8), to_date=date(2026, 6, 10)
    )
    ScheduleSlot.objects.create(
        subscription=sub, weekday=MONDAY, start_time=time(18), minutes=45
    )
    result = services.generate(JUNE_1, date(2026, 7, 31), subscription=sub)
    assert result.skipped_paused == 1
    assert date(2026, 6, 8) not in days(sub)
    # Ends 3 Jul after 3 paused days; grace to 10 Jul.
    assert days(sub)[-1] == date(2026, 7, 6)


def test_the_slot_link_wins_over_the_teacher_default(subscribe):
    sub = subscribe(
        slots=[
            {
                "weekdays": [MONDAY],
                "start_time": time(9),
                "meeting_url": "https://meet.test/room",
            }
        ]
    )
    assert Session.objects.get(subscription=sub, occurs_on=JUNE_1).meeting_url == (
        "https://meet.test/room"
    )


def test_starts_at_is_read_in_the_academy_timezone(subscribe):
    academy_services.update_settings(timezone="Asia/Riyadh")
    sub = subscribe(slots=two_slots())
    first = Session.objects.filter(subscription=sub).first()
    assert first.starts_at == datetime(2026, 6, 1, 15, 0, tzinfo=UTC)


def test_clock_change_times_move_forward(subscribe, clock):
    academy_services.update_settings(timezone="America/New_York")
    clock.set(datetime(2026, 3, 1, 12, tzinfo=UTC))
    sub = subscribe(starts_on=date(2026, 3, 1))
    ScheduleSlot.objects.create(  # Sundays 02:30: gone on 8 March
        subscription=sub, weekday=6, start_time=time(2, 30), minutes=45
    )
    services.generate(date(2026, 3, 1), date(2026, 3, 8), subscription=sub)
    starts = list(
        Session.objects.filter(subscription=sub).values_list("starts_at", flat=True)
    )
    assert starts == [
        datetime(2026, 3, 1, 7, 30, tzinfo=UTC),  # 02:30 EST
        datetime(2026, 3, 8, 7, 30, tzinfo=UTC),  # 03:30 EDT
    ]


def test_only_live_subscriptions_generate(subscribe):
    sub = subscribe(slots=two_slots())
    Session.objects.filter(subscription=sub).delete()
    for status, generates in (
        ("paused", True),
        ("expired", False),
        ("cancelled", False),
    ):
        Subscription.objects.filter(pk=sub.pk).update(status=status)
        result = services.generate(JUNE_1, JUNE_1)
        assert (result.created > 0) is generates, status
        Session.objects.filter(subscription=sub).delete()


def test_teacher_double_bookings_are_reported_not_blocked(subscribe):
    first = subscribe(slots=two_slots())
    second = subscribe(student_id=make_student("Aisha").id)
    for start in (time(18, 30), time(18, 45)):  # overlaps, then back-to-back
        ScheduleSlot.objects.create(
            subscription=second, weekday=MONDAY, start_time=start, minutes=45
        )
    Session.objects.filter(subscription=first, occurs_on=JUNE_1).update(
        status="cancelled"
    )
    result = services.generate(JUNE_1, date(2026, 6, 15), subscription=second)
    assert result.created == 6
    # 18:30 overlaps the 18:00 session on 8 and 15 June (1 June's is cancelled)
    # and the new 18:45 session on every Monday; 18:45 touches 18:00 only.
    pairs = sorted(
        (a.occurs_on, a.starts_at.time(), b.starts_at.time())
        for a, b in result.conflicts
    )
    assert pairs == [
        (date(2026, 6, 1), time(18, 30), time(18, 45)),
        (date(2026, 6, 8), time(18, 30), time(18, 0)),
        (date(2026, 6, 8), time(18, 30), time(18, 45)),
        (date(2026, 6, 15), time(18, 30), time(18, 0)),
        (date(2026, 6, 15), time(18, 30), time(18, 45)),
    ]


def test_untouched_means_scheduled_unmarked_and_in_the_future(subscribe, clock):
    sub = subscribe(slots=two_slots())
    sessions = list(Session.objects.filter(subscription=sub))
    Session.objects.filter(pk=sessions[1].pk).update(student_attendance="present")
    Session.objects.filter(pk=sessions[2].pk).update(teacher_attendance="absent")
    Session.objects.filter(pk=sessions[3].pk).update(status="cancelled")
    clock.set(sessions[0].starts_at + timedelta(minutes=1))  # the first is past
    untouched = services.untouched_sessions(subscription=sub)
    assert list(untouched) == [sessions[4]]
```

Create `backend/etqan/scheduling/tests/test_today.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.scheduling import services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import two_slots

JUNE_1 = date(2026, 6, 1)


def states():
    return [(r.slot.start_time, r.state) for r in services.today_board()]


def test_rows_for_today_in_time_order(subscribe):
    generated = subscribe(slots=two_slots())
    missing = subscribe(student_id=make_student("Aisha").id)
    ScheduleSlot.objects.create(
        subscription=missing, weekday=MONDAY, start_time=time(9), minutes=30
    )
    rows = services.today_board()
    assert [(r.subscription, r.state) for r in rows] == [
        (missing, "missing"),
        (generated, "generated"),
    ]
    assert rows[0].session is None
    assert rows[0].starts_at == datetime(2026, 6, 1, 9, tzinfo=UTC)
    assert (rows[1].derived.sessions_remaining, rows[1].derived.progress) == (8, 0)
    services.generate(JUNE_1, JUNE_1, subscription=missing)
    assert states() == [(time(9), "generated"), (time(18), "generated")]


def test_completed_and_cancelled_states(subscribe):
    sub = subscribe(slots=two_slots())
    session = Session.objects.get(subscription=sub, occurs_on=JUNE_1)
    Session.objects.filter(pk=session.pk).update(
        status="completed", student_attendance="present"
    )
    assert states() == [(time(18), "completed")]
    Session.objects.filter(pk=session.pk).update(status="cancelled")
    assert states() == [(time(18), "cancelled")]


def test_skips_slots_that_would_not_generate_today(subscribe):
    subscribe(starts_on=date(2026, 6, 2), slots=two_slots())
    paused = subscribe(student_id=make_student("Aisha").id, slots=two_slots())
    SubscriptionPause.objects.create(
        subscription=paused, from_date=JUNE_1, to_date=JUNE_1
    )
    Subscription.objects.filter(pk=paused.pk).update(status="paused")
    expired = subscribe(student_id=make_student("Zaid").id, slots=two_slots())
    Subscription.objects.filter(pk=expired.pk).update(status="expired")
    assert services.today_board() == []


def test_missing_rows_use_the_academy_timezone(subscribe):
    academy_services.update_settings(timezone="Asia/Riyadh")
    sub = subscribe()
    ScheduleSlot.objects.create(
        subscription=sub, weekday=MONDAY, start_time=time(9), minutes=45
    )
    [row] = services.today_board()
    assert row.starts_at == datetime(2026, 6, 1, 6, tzinfo=UTC)


def test_the_board_costs_the_same_queries_for_one_or_many(subscribe):
    subscribe(slots=two_slots())

    def queries():
        with CaptureQueriesContext(connection) as ctx:
            services.today_board()
        return len(ctx.captured_queries)

    one = queries()
    for name in ("Aisha", "Zaid", "Huda"):
        subscribe(student_id=make_student(name).id, slots=two_slots(time(9)))
    assert queries() == one
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_generation.py etqan/scheduling/tests/test_today.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'generate_horizon'` (and `today_board`).

- [ ] **Step 3: Implement**

Append to the end of `backend/etqan/scheduling/services/rules.py`:

```python
# ── Session rows ─────────────────────────────────────────────────────────────

SESSION_RELATED = ("student__user", "teacher__user", "course")
```

Create `backend/etqan/scheduling/services/generation.py`:

```python
"""Turning weekly slots into sessions (spec §4.1). Idempotent (P4-8)."""

from collections import defaultdict
from dataclasses import dataclass
from dataclasses import field
from datetime import date
from datetime import timedelta

from django.db.models import prefetch_related_objects

from etqan.scheduling import dates
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.services import rules

MAX_SESSION = timedelta(minutes=240)


@dataclass
class GenerationResult:
    created: int = 0
    skipped_existing: int = 0
    skipped_paused: int = 0
    skipped_out_of_term: int = 0
    conflicts: list[tuple[Session, Session]] = field(default_factory=list)


def ends_at(session: Session):
    return session.starts_at + timedelta(minutes=session.minutes)


def _dates_for(slot: ScheduleSlot, first: date, last: date):
    day = first + timedelta(days=(slot.weekday - first.weekday()) % 7)
    while day <= last:
        yield day
        day += timedelta(days=7)


def _new_session(slot: ScheduleSlot, day: date, tz_name: str) -> Session:
    sub = slot.subscription
    return Session(
        slot=slot,
        subscription=sub,
        student_id=sub.student_id,
        teacher_id=sub.teacher_id,
        course_id=sub.course_id,
        occurs_on=day,
        starts_at=dates.to_utc(day, slot.start_time, tz_name),
        minutes=slot.minutes,
        # Resolved now (spec §3.5): the slot's link, else the teacher's default.
        meeting_url=slot.meeting_url or sub.teacher.default_meeting_url,
        generated=True,
    )


def _conflicts(created: list[Session]) -> list[tuple[Session, Session]]:
    """Each created session that overlaps another non-cancelled session of the
    same teacher (P4-9: reported, never blocked). Each pair is listed once."""
    if not created:
        return []
    others = (
        Session.objects.exclude(status=Session.Status.CANCELLED)
        .filter(
            teacher_id__in={s.teacher_id for s in created},
            starts_at__gte=min(s.starts_at for s in created) - MAX_SESSION,
            starts_at__lt=max(ends_at(s) for s in created),
        )
        .select_related(*rules.SESSION_RELATED)
    )
    by_teacher = defaultdict(list)
    for other in others:
        by_teacher[other.teacher_id].append(other)
    created_ids = {s.pk for s in created}
    pairs = []
    for session in created:
        for other in by_teacher[session.teacher_id]:
            if other.pk == session.pk or (
                other.pk in created_ids and other.pk < session.pk
            ):
                continue
            if other.starts_at < ends_at(session) and session.starts_at < ends_at(
                other
            ):
                pairs.append((session, other))
    return pairs


def generate(
    first: date, last: date, *, subscription: Subscription | None = None
) -> GenerationResult:
    """Create the missing sessions of every active slot of every active or
    paused subscription (or just ``subscription``) from ``first`` to ``last``."""
    academy = rules.settings()
    slots = ScheduleSlot.objects.filter(
        is_active=True, subscription__status__in=rules.LIVE
    ).select_related("subscription__teacher")
    if subscription is not None:
        slots = slots.filter(subscription=subscription)
    slots = list(slots)
    prefetch_related_objects([s.subscription for s in slots], "pauses")
    existing = set(
        Session.objects.filter(
            slot__in=slots, occurs_on__range=(first, last)
        ).values_list("slot_id", "occurs_on")
    )
    result = GenerationResult()
    new = []
    for slot in slots:
        sub = slot.subscription
        grace_ends_on = rules.term(sub, academy.renewal_grace_days).grace_ends_on
        for day in _dates_for(slot, first, last):
            if day < sub.starts_on or day > grace_ends_on:
                result.skipped_out_of_term += 1
            elif rules.covering_pause(sub, day) is not None:
                result.skipped_paused += 1
            elif (slot.pk, day) in existing:
                result.skipped_existing += 1
            else:
                new.append(_new_session(slot, day, academy.timezone))
    # The unique (slot, date) constraint makes a concurrent run harmless.
    Session.objects.bulk_create(new, ignore_conflicts=True)
    attempted = {(s.slot_id, s.occurs_on) for s in new}
    created = [
        s
        for s in Session.objects.filter(
            slot__in=slots, occurs_on__range=(first, last)
        ).select_related(*rules.SESSION_RELATED)
        if (s.slot_id, s.occurs_on) in attempted
    ]
    result.created = len(created)
    result.skipped_existing += len(new) - len(created)
    result.conflicts = _conflicts(created)
    return result


def generate_horizon(subscription: Subscription | None = None) -> GenerationResult:
    """Today through today + the academy's horizon (spec §4.1)."""
    today = rules.today()
    horizon = rules.settings().generation_horizon_days
    return generate(today, today + timedelta(days=horizon), subscription=subscription)
```

Create `backend/etqan/scheduling/services/board.py`:

```python
"""The Today board (spec §4.3): every slot due on the academy's local date."""

from dataclasses import dataclass
from datetime import date
from datetime import datetime

from etqan.scheduling import dates
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.services import rules

STATES = {
    Session.Status.SCHEDULED: "generated",
    Session.Status.COMPLETED: "completed",
    Session.Status.CANCELLED: "cancelled",
}


@dataclass(frozen=True)
class TodayRow:
    day: date
    slot: ScheduleSlot
    subscription: Subscription
    starts_at: datetime
    session: Session | None
    state: str  # generated · missing · completed · cancelled
    derived: rules.Derived


def today_board(day: date | None = None) -> list[TodayRow]:
    """One row per active slot whose subscription would generate on ``day``
    (default: the academy's today), in start-time order."""
    academy = rules.settings()
    day = day or dates.local_today(academy.timezone)
    slots = list(
        ScheduleSlot.objects.filter(
            is_active=True,
            weekday=day.weekday(),
            subscription__status__in=rules.LIVE,
        )
        .select_related(
            "subscription__student__user",
            "subscription__teacher__user",
            "subscription__course",
        )
        .order_by("start_time", "id")
    )
    derived = rules.derive(s.subscription for s in slots)
    sessions = {
        s.slot_id: s for s in Session.objects.filter(slot__in=slots, occurs_on=day)
    }
    rows = []
    for slot in slots:
        sub = slot.subscription
        values = derived[sub.pk]
        if (
            day < sub.starts_on
            or day > values.grace_ends_on
            or rules.covering_pause(sub, day) is not None
        ):
            continue
        session = sessions.get(slot.pk)
        rows.append(
            TodayRow(
                day=day,
                slot=slot,
                subscription=sub,
                starts_at=session.starts_at
                if session
                else dates.to_utc(day, slot.start_time, academy.timezone),
                session=session,
                state=STATES[session.status] if session else "missing",
                derived=values,
            )
        )
    return rows
```

Add these imports to `backend/etqan/scheduling/services/subscriptions.py` (`ruff check --fix` in the format step puts them in order):

```python
from etqan.scheduling.services import generation
```

In `backend/etqan/scheduling/services/subscriptions.py`, replace:

```python
    for slot in slots:
        _add_slots(subscription, **slot, field="slots")
    return subscription
```

with:

```python
    for slot in slots:
        _add_slots(subscription, **slot, field="slots")
    generation.generate_horizon(subscription)
    return subscription
```

Replace the whole of `backend/etqan/scheduling/services/__init__.py` with:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.board import TodayRow
from etqan.scheduling.services.board import today_board
from etqan.scheduling.services.generation import GenerationResult
from etqan.scheduling.services.generation import generate
from etqan.scheduling.services.generation import generate_horizon
from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import today
from etqan.scheduling.services.rules import untouched_sessions
from etqan.scheduling.services.subscriptions import create_subscription

__all__ = [
    "Derived",
    "GenerationResult",
    "TodayRow",
    "create_subscription",
    "derive",
    "derived",
    "generate",
    "generate_horizon",
    "has_marked_sessions",
    "today",
    "today_board",
    "untouched_sessions",
]
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS — window boundaries, zero grace, pauses, the academy timezone, the New York clock change, only live subscriptions, reported (not blocked) double-bookings, the untouched rule, and a constant-query Today board.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): idempotent generation with double-booking reports and the Today board

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Admin actions: edit, cancel, delete, pauses and slots

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (append `sync_pause_status`), `backend/etqan/scheduling/services/subscriptions.py` (append three sections), `backend/etqan/scheduling/services/__init__.py`
- Create: `backend/etqan/scheduling/tests/test_actions.py`

**Interfaces:**
- Consumes: Tasks 3–4.
- Produces `rules.sync_pause_status(subscriptions_qs, today) -> (paused, resumed)` — the one implementation of §4.2 step 1, used by pauses here and by the job in Task 6.
- Produces services: `update_subscription(sub, *, teacher_id=None, price_minor=None, notes=None, starts_on=None)`, `cancel_subscription(sub)`, `delete_subscription(sub)`, `add_pause(sub, *, from_date, to_date, reason="") -> SubscriptionPause`, `end_pause(pause)`, `delete_pause(pause)`, `add_slots(sub, *, weekdays, start_time, minutes=None, meeting_url="") -> list[ScheduleSlot]`, `update_slot(slot, *, start_time=None, minutes=None, meeting_url=None, is_active=None) -> ScheduleSlot`, `delete_slot(slot)`.
- 409 codes: `scheduling.not_allowed_in_status`, `scheduling.has_marked_sessions`, `scheduling.pause_overlaps`, `scheduling.freeze_days_exceeded`, `scheduling.pause_not_current`, `scheduling.pause_started`, `scheduling.slot_has_sessions` (D11). Field errors: `teacher`, `starts_on`, `from_date`, `to_date`, `start_time`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/test_actions.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest

from etqan.academy import services as academy_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots

JUNE = {day: date(2026, 6, day) for day in range(1, 31)}


def sessions(sub):
    return Session.objects.filter(subscription=sub).order_by("starts_at")


def on(sub, day):
    return Session.objects.get(subscription=sub, occurs_on=day)


def mark(session):
    Session.objects.filter(pk=session.pk).update(student_attendance="present")


def code(exc_info):
    return exc_info.value.code


# ── Edit ─────────────────────────────────────────────────────────────────────


def test_a_new_teacher_replaces_only_untouched_sessions(subscribe, world, clock):
    sub = subscribe(slots=two_slots())
    past, marked = on(sub, JUNE[1]), on(sub, JUNE[8])
    mark(marked)
    clock.set(datetime(2026, 6, 2, 9, tzinfo=UTC))  # 1 June is now past
    maryam = make_teacher("Maryam")
    world.course.teachers.add(maryam.teacher_profile)
    services.update_subscription(sub, teacher_id=maryam.id)
    kept = {past.pk: world.teacher.id, marked.pk: world.teacher.id}
    for session in sessions(sub).select_related("teacher"):
        expected = kept.get(session.pk, maryam.id)
        assert session.teacher.user_id == expected, session.occurs_on
    assert sessions(sub).count() == 5


def test_teacher_must_teach_the_course(subscribe):
    sub = subscribe()
    with pytest.raises(ValidationError) as exc:
        services.update_subscription(sub, teacher_id=make_teacher("Other").id)
    assert exc.value.field == "teacher"


def test_price_and_notes_do_not_touch_sessions(subscribe):
    sub = subscribe(slots=two_slots())
    before = list(sessions(sub).values_list("pk", flat=True))
    services.update_subscription(sub, price_minor=99, notes="Discount")
    sub.refresh_from_db()
    assert (sub.price_minor, sub.notes) == (99, "Discount")
    assert list(sessions(sub).values_list("pk", flat=True)) == before


def test_moving_the_start_recomputes_the_term(subscribe):
    sub = subscribe(slots=two_slots())
    services.update_subscription(sub, starts_on=JUNE[3])
    sub.refresh_from_db()
    assert sub.term_ends_on == date(2026, 7, 2)
    assert sessions(sub).first().occurs_on == JUNE[3]


def test_start_is_fixed_once_attendance_is_marked(subscribe):
    sub = subscribe(slots=two_slots())
    mark(on(sub, JUNE[1]))
    with pytest.raises(ConflictError) as exc:
        services.update_subscription(sub, starts_on=JUNE[3])
    assert code(exc) == "scheduling.has_marked_sessions"


def test_start_cannot_pass_a_pause(subscribe):
    sub = subscribe()
    services.add_pause(sub, from_date=JUNE[5], to_date=JUNE[6])
    with pytest.raises(ValidationError) as exc:
        services.update_subscription(sub, starts_on=JUNE[8])
    assert exc.value.field == "starts_on"


# ── Cancel and delete ────────────────────────────────────────────────────────


def test_cancel_keeps_past_and_marked_sessions(subscribe, clock):
    sub = subscribe(slots=two_slots())
    mark(on(sub, JUNE[10]))
    clock.set(datetime(2026, 6, 2, 9, tzinfo=UTC))
    services.cancel_subscription(sub)
    sub.refresh_from_db()
    assert sub.status == "cancelled"
    assert [s.occurs_on for s in sessions(sub)] == [JUNE[1], JUNE[10]]
    with pytest.raises(ConflictError) as exc:
        services.cancel_subscription(sub)
    assert code(exc) == "scheduling.not_allowed_in_status"
    with pytest.raises(ConflictError):
        services.update_subscription(sub, notes="late")


def test_delete_undoes_a_mistake_until_attendance_is_marked(subscribe):
    sub = subscribe(slots=two_slots())
    mark(on(sub, JUNE[1]))
    with pytest.raises(ConflictError) as exc:
        services.delete_subscription(sub)
    assert code(exc) == "scheduling.has_marked_sessions"
    Session.objects.filter(subscription=sub).update(student_attendance="not_set")
    services.delete_subscription(sub)
    assert not Subscription.objects.filter(pk=sub.pk).exists()
    assert not Session.objects.exists()


# ── Pauses ───────────────────────────────────────────────────────────────────


def test_a_pause_covering_today_pauses_at_once(subscribe):
    sub = subscribe(slots=two_slots())
    mark(on(sub, JUNE[3]))
    services.add_pause(sub, from_date=JUNE[1], to_date=JUNE[8], reason="Travel")
    sub.refresh_from_db()
    assert sub.status == "paused"
    # 1 and 8 June are gone; 3 June was marked, so it stays.
    assert [s.occurs_on for s in sessions(sub)] == [JUNE[3], JUNE[10], JUNE[15]]


def test_a_future_pause_leaves_the_status_alone(subscribe):
    sub = subscribe(slots=two_slots())
    services.add_pause(sub, from_date=JUNE[8], to_date=JUNE[8])
    sub.refresh_from_db()
    assert sub.status == "active"
    assert JUNE[8] not in [s.occurs_on for s in sessions(sub)]


@pytest.mark.parametrize(
    ("from_day", "to_day", "field"),
    [(10, 9, "to_date"), (None, 2, "from_date")],
)
def test_pause_dates_are_checked(subscribe, from_day, to_day, field):
    sub = subscribe()
    start = date(2026, 5, 31) if from_day is None else JUNE[from_day]
    with pytest.raises(ValidationError) as exc:
        services.add_pause(sub, from_date=start, to_date=JUNE[to_day])
    assert exc.value.field == field


def test_a_pause_must_start_by_the_end_date(subscribe):
    sub = subscribe()
    with pytest.raises(ValidationError) as exc:
        services.add_pause(sub, from_date=date(2026, 7, 1), to_date=date(2026, 7, 1))
    assert exc.value.field == "from_date"
    services.add_pause(sub, from_date=date(2026, 6, 30), to_date=date(2026, 7, 2))


def test_pauses_never_overlap_or_exceed_the_freeze_days(subscribe):
    sub = subscribe()
    services.add_pause(sub, from_date=JUNE[10], to_date=JUNE[15])
    with pytest.raises(ConflictError) as exc:
        services.add_pause(sub, from_date=JUNE[15], to_date=JUNE[16])
    assert code(exc) == "scheduling.pause_overlaps"
    with pytest.raises(ConflictError) as exc:
        services.add_pause(sub, from_date=JUNE[20], to_date=JUNE[24])  # 6 + 5 > 10
    assert code(exc) == "scheduling.freeze_days_exceeded"
    services.add_pause(sub, from_date=JUNE[20], to_date=JUNE[23])  # exactly 10


def test_end_a_pause_early(subscribe, clock):
    sub = subscribe(slots=two_slots())
    pause = services.add_pause(sub, from_date=JUNE[1], to_date=JUNE[10])
    clock.set(datetime(2026, 6, 8, 9, tzinfo=UTC))
    services.end_pause(pause)
    pause.refresh_from_db()
    sub.refresh_from_db()
    assert (pause.to_date, sub.status) == (JUNE[7], "active")
    assert on(sub, JUNE[8])
    assert on(sub, JUNE[10])


def test_ending_a_pause_on_its_first_day_deletes_it(subscribe):
    sub = subscribe(slots=two_slots())
    pause = services.add_pause(sub, from_date=JUNE[1], to_date=JUNE[3])
    services.end_pause(pause)
    sub.refresh_from_db()
    assert not SubscriptionPause.objects.exists()
    assert sub.status == "active"
    assert on(sub, JUNE[1])


def test_only_a_current_pause_ends_and_only_a_future_one_is_deleted(subscribe, clock):
    sub = subscribe(slots=two_slots())
    future = services.add_pause(sub, from_date=JUNE[8], to_date=JUNE[10])
    with pytest.raises(ConflictError) as exc:
        services.end_pause(future)
    assert code(exc) == "scheduling.pause_not_current"
    services.delete_pause(future)
    assert on(sub, JUNE[8])
    assert on(sub, JUNE[10])
    started = services.add_pause(sub, from_date=JUNE[1], to_date=JUNE[2])
    with pytest.raises(ConflictError) as exc:
        services.delete_pause(started)
    assert code(exc) == "scheduling.pause_started"


def test_ending_a_pause_drops_sessions_past_the_new_grace_end(subscribe, clock):
    academy_services.update_settings(generation_horizon_days=30)
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 25, 9, tzinfo=UTC))
    pause = services.add_pause(sub, from_date=JUNE[25], to_date=date(2026, 7, 4))
    # The term now ends 10 Jul with grace to 17 Jul, so 13 and 15 Jul exist.
    assert on(sub, date(2026, 7, 15))
    clock.set(datetime(2026, 6, 26, 9, tzinfo=UTC))
    services.end_pause(pause)  # 1 paused day: ends 1 Jul, grace to 8 Jul
    assert not sessions(sub).filter(occurs_on__gt=date(2026, 7, 8)).exists()


# ── Slots ────────────────────────────────────────────────────────────────────


def test_add_slots_generates_and_refuses_a_taken_time(subscribe):
    sub = subscribe()
    slots = services.add_slots(sub, weekdays=[MONDAY], start_time=time(9))
    assert [s.weekday for s in slots] == [MONDAY]
    assert on(sub, JUNE[1]).starts_at.hour == 9
    with pytest.raises(ValidationError) as exc:
        services.add_slots(sub, weekdays=[MONDAY, 1], start_time=time(9))
    assert exc.value.field == "start_time"
    assert ScheduleSlot.objects.filter(subscription=sub).count() == 1


def test_editing_a_slot_replaces_its_untouched_sessions(subscribe):
    sub = subscribe(slots=two_slots())
    monday = ScheduleSlot.objects.get(subscription=sub, weekday=MONDAY)
    mark(on(sub, JUNE[8]))
    services.update_slot(monday, start_time=time(19), minutes=60)
    got = {s.occurs_on: (s.starts_at.hour, s.minutes) for s in sessions(sub)}
    assert got[JUNE[1]] == (19, 60)
    assert got[JUNE[8]] == (18, 45)  # marked: kept as it was
    assert got[JUNE[3]] == (18, 45)  # another slot


def test_deactivate_anytime_reactivate_only_when_live(subscribe):
    sub = subscribe(slots=two_slots())
    monday = ScheduleSlot.objects.get(subscription=sub, weekday=MONDAY)
    services.cancel_subscription(sub)
    sub.refresh_from_db()
    services.update_slot(monday, is_active=False)
    assert not monday.sessions.exists()
    with pytest.raises(ConflictError) as exc:
        services.update_slot(monday, is_active=True)
    assert code(exc) == "scheduling.not_allowed_in_status"


def test_reactivating_a_slot_regenerates(subscribe):
    sub = subscribe(slots=two_slots())
    monday = ScheduleSlot.objects.get(subscription=sub, weekday=MONDAY)
    services.update_slot(monday, is_active=False)
    assert not monday.sessions.exists()
    services.update_slot(monday, is_active=True)
    assert monday.sessions.count() == 3


def test_a_slot_that_produced_sessions_is_not_deleted(subscribe):
    sub = subscribe(slots=two_slots())
    monday = ScheduleSlot.objects.get(subscription=sub, weekday=MONDAY)
    with pytest.raises(ConflictError) as exc:
        services.delete_slot(monday)
    assert code(exc) == "scheduling.slot_has_sessions"
    services.update_slot(monday, is_active=False)
    services.delete_slot(monday)
    assert not ScheduleSlot.objects.filter(pk=monday.pk).exists()
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_actions.py`
Expected: FAIL — `AttributeError: … has no attribute 'update_subscription'` (and the other actions).

- [ ] **Step 3: Implement**

Add these imports to `backend/etqan/scheduling/services/rules.py` (`ruff check --fix` in the format step puts them in order):

```python
from django.db.models import Exists
from django.db.models import OuterRef
```

Append to the end of `backend/etqan/scheduling/services/rules.py`:

```python
# ── Status ───────────────────────────────────────────────────────────────────


def sync_pause_status(subscriptions: QuerySet[Subscription], today: date):
    """Spec §4.2 step 1: a live subscription is `paused` exactly while one of
    its pauses covers ``today``. Returns ``(paused, resumed)`` counts."""
    covering = SubscriptionPause.objects.filter(
        subscription=OuterRef("pk"), from_date__lte=today, to_date__gte=today
    )
    stamp = {"updated_at": dates.now()}
    paused = (
        subscriptions.filter(status=Subscription.Status.ACTIVE)
        .filter(Exists(covering))
        .update(status=Subscription.Status.PAUSED, **stamp)
    )
    resumed = (
        subscriptions.filter(status=Subscription.Status.PAUSED)
        .exclude(Exists(covering))
        .update(status=Subscription.Status.ACTIVE, **stamp)
    )
    return paused, resumed
```

Add these imports to `backend/etqan/scheduling/services/subscriptions.py` (`ruff check --fix` in the format step puts them in order):

```python
from datetime import timedelta

from etqan.platform.exceptions import ConflictError
from etqan.scheduling.models import Session
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.services import rules
```

Append to the end of `backend/etqan/scheduling/services/subscriptions.py`:

```python
# ── Edit, cancel, delete ─────────────────────────────────────────────────────


def _regenerate(subscription: Subscription) -> None:
    """Replace the untouched sessions (P4-7) and fill the horizon again."""
    rules.untouched_sessions(subscription=subscription).delete()
    generation.generate_horizon(subscription)


def _refill(subscription: Subscription) -> None:
    """After the term moved: drop untouched sessions past the new grace end,
    then fill the horizon."""
    fresh = Subscription.objects.get(pk=subscription.pk)
    span = rules.term(fresh, rules.settings().renewal_grace_days)
    rules.untouched_sessions(
        subscription=subscription, occurs_on__gt=span.grace_ends_on
    ).delete()
    generation.generate_horizon(subscription)


def _refuse_if_marked(subscription: Subscription) -> None:
    if rules.has_marked_sessions(subscription):
        raise ConflictError(
            "Attendance is already marked on this subscription.",
            code="scheduling.has_marked_sessions",
        )


@transaction.atomic
def update_subscription(
    subscription: Subscription,
    *,
    teacher_id: int | None = None,
    price_minor: int | None = None,
    notes: str | None = None,
    starts_on: date | None = None,
) -> Subscription:
    """Spec §4.2: a new teacher or start date replaces the untouched sessions."""
    rules.require_status(subscription)
    regenerate = False
    if teacher_id is not None and teacher_id != subscription.teacher.user_id:
        subscription.teacher = _teacher(teacher_id, subscription.course)
        regenerate = True
    if starts_on is not None and starts_on != subscription.starts_on:
        _refuse_if_marked(subscription)
        if subscription.pauses.filter(from_date__lt=starts_on).exists():
            raise ValidationError(
                "Delete the pauses before this date first.", field="starts_on"
            )
        subscription.starts_on = starts_on
        subscription.term_ends_on = dates.term_ends_on(
            starts_on, subscription.duration_value, subscription.duration_unit
        )
        regenerate = True
    if price_minor is not None:
        subscription.price_minor = price_minor
    if notes is not None:
        subscription.notes = notes
    _save(subscription)
    if regenerate:
        _regenerate(subscription)
    return subscription


@transaction.atomic
def cancel_subscription(subscription: Subscription) -> None:
    rules.require_status(subscription)
    subscription.status = Subscription.Status.CANCELLED
    subscription.save(update_fields=["status", "updated_at"])
    rules.untouched_sessions(subscription=subscription).delete()


@transaction.atomic
def delete_subscription(subscription: Subscription) -> None:
    """For undoing mistakes: only while nobody has marked any of its sessions."""
    _refuse_if_marked(subscription)
    Session.objects.filter(subscription=subscription).delete()
    subscription.delete()


# ── Pauses ───────────────────────────────────────────────────────────────────


@transaction.atomic
def add_pause(
    subscription: Subscription, *, from_date: date, to_date: date, reason: str = ""
) -> SubscriptionPause:
    rules.require_status(subscription)
    if from_date > to_date:
        raise ValidationError("End the pause on or after its start.", field="to_date")
    span = rules.term(subscription, 0)
    if not subscription.starts_on <= from_date <= span.ends_on:
        raise ValidationError(
            "Start the pause between the start and end dates.", field="from_date"
        )
    if subscription.pauses.filter(
        from_date__lte=to_date, to_date__gte=from_date
    ).exists():
        raise ConflictError(
            "This pause overlaps another one.", code="scheduling.pause_overlaps"
        )
    length = dates.inclusive_days(from_date, to_date)
    if span.paused_days + length > subscription.freeze_days_allowed:
        raise ConflictError(
            "That is more than the freeze days allowed.",
            code="scheduling.freeze_days_exceeded",
        )
    pause = SubscriptionPause.objects.create(
        subscription=subscription,
        from_date=from_date,
        to_date=to_date,
        reason=reason,
    )
    rules.untouched_sessions(
        subscription=subscription, occurs_on__range=(from_date, to_date)
    ).delete()
    rules.sync_pause_status(
        Subscription.objects.filter(pk=subscription.pk), rules.today()
    )
    # The term grew by the pause: the horizon may reach new dates.
    generation.generate_horizon(subscription)
    return pause


@transaction.atomic
def end_pause(pause: SubscriptionPause) -> None:
    """Spec §4.2: yesterday becomes the pause's last day (or it goes, if it
    began today); the subscription is active again."""
    subscription = pause.subscription
    rules.require_status(subscription)
    today = rules.today()
    if not pause.from_date <= today <= pause.to_date:
        raise ConflictError(
            "Only a pause that covers today can be ended early.",
            code="scheduling.pause_not_current",
        )
    if pause.from_date == today:
        pause.delete()
    else:
        pause.to_date = today - timedelta(days=1)
        pause.save(update_fields=["to_date"])
    rules.sync_pause_status(Subscription.objects.filter(pk=subscription.pk), today)
    _refill(subscription)


@transaction.atomic
def delete_pause(pause: SubscriptionPause) -> None:
    subscription = pause.subscription
    rules.require_status(subscription)
    if pause.from_date <= rules.today():
        raise ConflictError(
            "Only a pause that has not started can be deleted.",
            code="scheduling.pause_started",
        )
    pause.delete()
    _refill(subscription)


# ── Slot actions ─────────────────────────────────────────────────────────────


@transaction.atomic
def add_slots(
    subscription: Subscription,
    *,
    weekdays: Iterable[int],
    start_time: time,
    minutes: int | None = None,
    meeting_url: str = "",
) -> list[ScheduleSlot]:
    rules.require_status(subscription)
    slots = _add_slots(
        subscription,
        weekdays=weekdays,
        start_time=start_time,
        minutes=minutes,
        meeting_url=meeting_url,
    )
    generation.generate_horizon(subscription)
    return slots


@transaction.atomic
def update_slot(
    slot: ScheduleSlot,
    *,
    start_time: time | None = None,
    minutes: int | None = None,
    meeting_url: str | None = None,
    is_active: bool | None = None,
) -> ScheduleSlot:
    """Edit, re-activate (active or paused subscriptions only) or deactivate
    (any status). The slot's untouched sessions are replaced."""
    wanted = {
        "start_time": start_time,
        "minutes": minutes,
        "meeting_url": meeting_url,
        "is_active": is_active,
    }
    changes = {
        key: value
        for key, value in wanted.items()
        if value is not None and getattr(slot, key) != value
    }
    if not changes:
        return slot
    subscription = slot.subscription
    if changes.get("is_active") is not False:
        rules.require_status(subscription)
    for key, value in changes.items():
        setattr(slot, key, value)
    if slot.is_active and _slot_taken(
        subscription, slot.weekday, slot.start_time, exclude=slot
    ):
        raise ValidationError(
            "There is already a slot at this time.", field="start_time"
        )
    _save(slot)
    rules.untouched_sessions(slot=slot).delete()
    if slot.is_active:
        generation.generate_horizon(subscription)
    return slot


def delete_slot(slot: ScheduleSlot) -> None:
    if slot.sessions.exists():
        raise ConflictError(
            "This slot has sessions. Deactivate it instead.",
            code="scheduling.slot_has_sessions",
        )
    slot.delete()
```

Replace the whole of `backend/etqan/scheduling/services/__init__.py` with:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.board import TodayRow
from etqan.scheduling.services.board import today_board
from etqan.scheduling.services.generation import GenerationResult
from etqan.scheduling.services.generation import generate
from etqan.scheduling.services.generation import generate_horizon
from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import today
from etqan.scheduling.services.rules import untouched_sessions
from etqan.scheduling.services.subscriptions import add_pause
from etqan.scheduling.services.subscriptions import add_slots
from etqan.scheduling.services.subscriptions import cancel_subscription
from etqan.scheduling.services.subscriptions import create_subscription
from etqan.scheduling.services.subscriptions import delete_pause
from etqan.scheduling.services.subscriptions import delete_slot
from etqan.scheduling.services.subscriptions import delete_subscription
from etqan.scheduling.services.subscriptions import end_pause
from etqan.scheduling.services.subscriptions import update_slot
from etqan.scheduling.services.subscriptions import update_subscription

__all__ = [
    "Derived",
    "GenerationResult",
    "TodayRow",
    "add_pause",
    "add_slots",
    "cancel_subscription",
    "create_subscription",
    "delete_pause",
    "delete_slot",
    "delete_subscription",
    "derive",
    "derived",
    "end_pause",
    "generate",
    "generate_horizon",
    "has_marked_sessions",
    "today",
    "today_board",
    "untouched_sessions",
    "update_slot",
    "update_subscription",
]
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS. Every action is checked against past and marked sessions: they are never deleted (P4-7).

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): edit, cancel, delete, pauses and slots that only touch untouched sessions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Renewal, the lifecycle job and the hourly Celery task

**Files:**
- Create: `backend/etqan/scheduling/services/lifecycle.py`, `backend/etqan/scheduling/tasks.py`, `backend/etqan/scheduling/tests/test_renewal.py`, `backend/etqan/scheduling/tests/test_lifecycle.py`
- Modify: `backend/etqan/scheduling/services/rules.py` (append `renewal_starts_on`), `backend/etqan/scheduling/services/subscriptions.py` (append renewal), `backend/etqan/scheduling/services/__init__.py`, `backend/config/settings/base.py` (`CELERY_BEAT_SCHEDULE`)

**Interfaces:**
- Consumes: `for_each_academy` (Task 1), Tasks 3–5.
- Produces `rules.renewal_starts_on(sub) -> date` (day after `ends_on`, or today if later) and `services.renew_subscription(sub, *, starts_on=None, teacher_id=None, package_id=None, price_minor=None, course_id=None) -> Subscription` (the new one); 409 `scheduling.already_renewed`.
- Produces `services.run_lifecycle() -> {"paused", "resumed", "expired", "created"}` for the current academy, and the Celery task `etqan.scheduling.tasks.run_daily` named `scheduling.run_daily`, scheduled hourly at minute 5.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/test_renewal.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest

from etqan.catalogue import services as catalogue_services
from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots


def test_renewal_starts_after_the_end_with_the_old_price_and_slots(subscribe, world):
    old = subscribe(price_minor=120000, slots=two_slots())
    services.add_pause(old, from_date=date(2026, 6, 10), to_date=date(2026, 6, 11))
    new = services.renew_subscription(old)
    old.refresh_from_db()
    assert old.status == "expired"
    assert new.renewed_from == old
    # Term 30 Jun + 2 paused days = 2 Jul; the renewal starts 3 Jul.
    assert (new.starts_on, new.term_ends_on) == (date(2026, 7, 3), date(2026, 8, 2))
    assert (new.price_minor, new.sessions_total, new.status) == (120000, 8, "active")
    assert [
        (s.weekday, s.start_time, s.minutes)
        for s in ScheduleSlot.objects.filter(subscription=new)
    ] == [(0, time(18), 45), (2, time(18), 45)]


def test_renewal_never_starts_in_the_past(subscribe, clock):
    old = subscribe()
    clock.set(datetime(2026, 7, 5, 9, tzinfo=UTC))  # in grace
    assert services.renew_subscription(old).starts_on == date(2026, 7, 5)


def test_old_untouched_sessions_from_the_new_start_are_removed(subscribe):
    old = subscribe(slots=two_slots())
    Session.objects.filter(subscription=old, occurs_on=date(2026, 6, 8)).update(
        student_attendance="present", status="completed"
    )
    new = services.renew_subscription(old, starts_on=date(2026, 6, 8))
    left = Session.objects.filter(subscription=old).values_list("occurs_on", flat=True)
    # 10 and 15 June moved to the renewal; the marked 8 June session stayed.
    assert list(left) == [date(2026, 6, 1), date(2026, 6, 3), date(2026, 6, 8)]
    renewed = Session.objects.filter(subscription=new).values_list(
        "occurs_on", flat=True
    )
    assert list(renewed) == [date(2026, 6, 8), date(2026, 6, 10), date(2026, 6, 15)]


def test_changes_in_the_renew_dialog(subscribe, world):
    old = subscribe(
        slots=[{"weekdays": [MONDAY], "start_time": time(9), "minutes": 30}]
    )
    package = catalogue_services.create_package(
        name_ar="مكثف",
        name_en="Intensive",
        sessions_per_week=3,
        session_minutes=60,
        duration_value=14,
        duration_unit="day",
        price_minor=5000,
        currency="USD",
    )
    maryam = make_teacher("Maryam")
    world.course.teachers.add(maryam.teacher_profile)
    new = services.renew_subscription(
        old, package_id=package.id, teacher_id=maryam.id, starts_on=date(2026, 7, 1)
    )
    assert (new.sessions_total, new.session_minutes, new.term_ends_on) == (
        6,
        60,
        date(2026, 7, 14),
    )
    # A new currency means the old amount no longer applies.
    assert (new.price_minor, new.currency) == (5000, "USD")
    assert new.teacher.user_id == maryam.id
    # A custom slot length is kept; package-length slots follow the package.
    assert ScheduleSlot.objects.get(subscription=new).minutes == 30


def test_renew_once_and_only_from_allowed_statuses(subscribe):
    old = subscribe()
    services.renew_subscription(old)
    with pytest.raises(ConflictError) as exc:
        services.renew_subscription(old)
    assert exc.value.code == "scheduling.already_renewed"
    cancelled = subscribe(starts_on=date(2026, 9, 1))
    services.cancel_subscription(cancelled)
    with pytest.raises(ConflictError) as exc:
        services.renew_subscription(cancelled)
    assert exc.value.code == "scheduling.not_allowed_in_status"


def test_grace_sessions_taught_after_renewal_are_carried_over(subscribe, clock):
    old = subscribe(slots=two_slots())
    services.generate(date(2026, 6, 1), date(2026, 7, 31), subscription=old)
    done = {"status": "completed", "student_attendance": "present"}
    # The package's 8 sessions: 1 to 24 June.
    Session.objects.filter(subscription=old, occurs_on__lte=date(2026, 6, 24)).update(
        **done
    )
    clock.set(datetime(2026, 7, 2, 9, tzinfo=UTC))  # in grace
    new = services.renew_subscription(old, starts_on=date(2026, 7, 10))
    assert services.derived(new).carried_over_sessions == 0
    # 29 June and 1 July were taught but marked only after the renewal.
    Session.objects.filter(
        subscription=old, occurs_on__in=[date(2026, 6, 29), date(2026, 7, 1)]
    ).update(**done)
    old_values, new_values = services.derived(old), services.derived(new)
    assert (old_values.sessions_used, old_values.extra_sessions) == (10, 2)
    assert (new_values.carried_over_sessions, new_values.sessions_remaining) == (
        2,
        6,
    )
```

Create `backend/etqan/scheduling/tests/test_lifecycle.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime

from django.conf import settings
from django.db import connection
from django_tenants.utils import tenant_context

from etqan.academy import services as academy_services
from etqan.scheduling import services
from etqan.scheduling import tasks
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.services import generation
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots


def status(sub):
    sub.refresh_from_db()
    return sub.status


def test_pauses_start_and_end_with_the_calendar(subscribe, clock):
    sub = subscribe(slots=two_slots())
    SubscriptionPause.objects.create(
        subscription=sub, from_date=date(2026, 6, 8), to_date=date(2026, 6, 9)
    )
    clock.set(datetime(2026, 6, 8, 0, 30, tzinfo=UTC))
    assert services.run_lifecycle()["paused"] == 1
    assert status(sub) == "paused"
    assert services.run_lifecycle()["paused"] == 0  # repeatable
    clock.set(datetime(2026, 6, 10, 0, 30, tzinfo=UTC))
    assert services.run_lifecycle()["resumed"] == 1
    assert status(sub) == "active"


def test_expiry_after_grace_deletes_untouched_sessions(subscribe, clock):
    sub = subscribe(slots=two_slots())
    services.generate(date(2026, 6, 1), date(2026, 7, 31), subscription=sub)
    # Generated with 7 grace days: Mondays and Wednesdays up to 6 July.
    assert Session.objects.filter(subscription=sub).count() == 11
    Session.objects.filter(subscription=sub, occurs_on=date(2026, 7, 6)).update(
        teacher_attendance="present"
    )
    academy_services.update_settings(renewal_grace_days=0)
    clock.set(datetime(2026, 6, 30, 20, tzinfo=UTC))  # the last day
    services.run_lifecycle()
    assert status(sub) == "active"
    clock.set(datetime(2026, 7, 1, 0, 30, tzinfo=UTC))
    assert services.run_lifecycle()["expired"] == 1
    assert status(sub) == "expired"
    assert services.run_lifecycle()["expired"] == 0
    left = set(
        Session.objects.filter(subscription=sub).values_list("occurs_on", flat=True)
    )
    # 1 July was untouched and goes; 6 July is marked and stays.
    assert date(2026, 7, 1) not in left
    assert date(2026, 7, 6) in left
    assert len(left) == 10


def test_the_job_generates_the_horizon(subscribe, clock):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 10, 1, tzinfo=UTC))
    assert services.run_lifecycle()["created"] == 3  # 17, 22, 24 June
    assert services.run_lifecycle()["created"] == 0
    assert Session.objects.filter(subscription=sub).count() == 8


def test_the_job_is_scheduled_hourly():
    entry = settings.CELERY_BEAT_SCHEDULE["scheduling.run_daily"]
    assert entry["task"] == tasks.run_daily.name == "scheduling.run_daily"
    assert entry["schedule"].minute == {5}
    assert entry["schedule"].hour == set(range(24))


def test_the_hourly_job_runs_every_academy_and_survives_one_failing(
    subscribe, tenants, clock, monkeypatch
):
    here = subscribe()
    with tenant_context(tenants.other):
        there = subscription_for(build_world())
    clock.set(datetime(2026, 8, 1, 9, tzinfo=UTC))  # both are past grace
    real = generation.generate_horizon

    def fails_in_other(subscription=None):
        if connection.schema_name == tenants.other.schema_name:
            raise RuntimeError("boom")
        return real(subscription)

    monkeypatch.setattr(generation, "generate_horizon", fails_in_other)
    results = tasks.run_daily()
    assert results[tenants.main.schema_name] == "ok"
    assert results[tenants.other.schema_name] == "failed"
    assert status(here) == "expired"
    with tenant_context(tenants.other):
        # Its expiry ran before the failure and was rolled back with it.
        assert Subscription.objects.get(pk=there.pk).status == "active"
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_renewal.py etqan/scheduling/tests/test_lifecycle.py`
Expected: FAIL — `ImportError: cannot import name 'tasks'` and no `renew_subscription`.

- [ ] **Step 3: Implement**

Append to the end of `backend/etqan/scheduling/services/rules.py`:

```python
# ── Renewal ──────────────────────────────────────────────────────────────────


def renewal_starts_on(subscription: Subscription) -> date:
    """Spec §4.2: a renewal starts the day after the current end date, or
    today if that is later. Reads the pauses."""
    next_day = term(subscription, 0).ends_on + timedelta(days=1)
    return max(next_day, today())
```

Append to the end of `backend/etqan/scheduling/services/subscriptions.py`:

```python
# ── Renewal ──────────────────────────────────────────────────────────────────


@transaction.atomic
def renew_subscription(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §5)
    subscription: Subscription,
    *,
    starts_on: date | None = None,
    teacher_id: int | None = None,
    package_id: int | None = None,
    price_minor: int | None = None,
    course_id: int | None = None,
) -> Subscription:
    """Spec §4.2 Renewal. Extras reach the new term through its live
    `carried_over_sessions`; grace sessions stay on the old subscription."""
    # Locked, so two admins renewing at once get one renewal and one 409.
    old = Subscription.objects.select_for_update().get(pk=subscription.pk)
    rules.require_status(
        old,
        (
            Subscription.Status.ACTIVE,
            Subscription.Status.PAUSED,
            Subscription.Status.EXPIRED,
        ),
    )
    if Subscription.objects.filter(renewed_from=old).exists():
        raise ConflictError(
            "This subscription was already renewed.",
            code="scheduling.already_renewed",
        )
    starts_on = starts_on or rules.renewal_starts_on(old)
    package = _package(package_id or old.package_id)
    if price_minor is None:
        # P4-10: renew at the amount paid, unless the currency changed.
        same_currency = package.currency == old.currency
        price_minor = old.price_minor if same_currency else package.price_minor
    slots = [
        {
            "weekdays": [slot.weekday],
            "start_time": slot.start_time,
            # A slot on the old package length follows the new package.
            "minutes": None if slot.minutes == old.session_minutes else slot.minutes,
            "meeting_url": slot.meeting_url,
        }
        for slot in old.slots.filter(is_active=True)
    ]
    old.status = Subscription.Status.EXPIRED
    old.save(update_fields=["status", "updated_at"])
    rules.untouched_sessions(subscription=old, occurs_on__gte=starts_on).delete()
    return create_subscription(
        student_id=old.student.user_id,
        course_id=course_id or old.course_id,
        teacher_id=teacher_id or old.teacher.user_id,
        package_id=package.pk,
        starts_on=starts_on,
        price_minor=price_minor,
        slots=slots,
        renewed_from=old,
    )
```

Create `backend/etqan/scheduling/services/lifecycle.py`:

```python
"""The hourly job's work for one academy (spec §4.2). Every step is safe to repeat."""

from etqan.scheduling.models import Subscription
from etqan.scheduling.services import generation
from etqan.scheduling.services import rules


def _expire_due(today) -> int:
    """Step 2: live subscriptions past their grace end expire; their untouched
    sessions go."""
    grace = rules.settings().renewal_grace_days
    live = Subscription.objects.filter(status__in=rules.LIVE).prefetch_related("pauses")
    due = [s.pk for s in live if today > rules.term(s, grace).grace_ends_on]
    Subscription.objects.filter(pk__in=due).update(status=Subscription.Status.EXPIRED)
    rules.untouched_sessions(subscription_id__in=due).delete()
    return len(due)


def run_lifecycle() -> dict[str, int]:
    """Pauses, then expiry, then the horizon, for the current academy."""
    today = rules.today()
    paused, resumed = rules.sync_pause_status(Subscription.objects.all(), today)
    expired = _expire_due(today)
    created = generation.generate_horizon().created
    return {
        "paused": paused,
        "resumed": resumed,
        "expired": expired,
        "created": created,
    }
```

Create `backend/etqan/scheduling/tasks.py`:

```python
from celery import shared_task

from etqan.platform.tenancy import for_each_academy
from etqan.scheduling import services

RUN_DAILY = "scheduling.run_daily"


@shared_task(name=RUN_DAILY)
def run_daily() -> dict[str, str]:
    """Hourly (spec §7): pauses, expiry and generation in every academy. One
    academy's failure is logged and rolled back; the others still run."""
    return for_each_academy(services.run_lifecycle, name=RUN_DAILY)
```

Replace the whole of `backend/etqan/scheduling/services/__init__.py` with:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.board import TodayRow
from etqan.scheduling.services.board import today_board
from etqan.scheduling.services.generation import GenerationResult
from etqan.scheduling.services.generation import generate
from etqan.scheduling.services.generation import generate_horizon
from etqan.scheduling.services.lifecycle import run_lifecycle
from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import renewal_starts_on
from etqan.scheduling.services.rules import today
from etqan.scheduling.services.rules import untouched_sessions
from etqan.scheduling.services.subscriptions import add_pause
from etqan.scheduling.services.subscriptions import add_slots
from etqan.scheduling.services.subscriptions import cancel_subscription
from etqan.scheduling.services.subscriptions import create_subscription
from etqan.scheduling.services.subscriptions import delete_pause
from etqan.scheduling.services.subscriptions import delete_slot
from etqan.scheduling.services.subscriptions import delete_subscription
from etqan.scheduling.services.subscriptions import end_pause
from etqan.scheduling.services.subscriptions import renew_subscription
from etqan.scheduling.services.subscriptions import update_slot
from etqan.scheduling.services.subscriptions import update_subscription

__all__ = [
    "Derived",
    "GenerationResult",
    "TodayRow",
    "add_pause",
    "add_slots",
    "cancel_subscription",
    "create_subscription",
    "delete_pause",
    "delete_slot",
    "delete_subscription",
    "derive",
    "derived",
    "end_pause",
    "generate",
    "generate_horizon",
    "has_marked_sessions",
    "renew_subscription",
    "renewal_starts_on",
    "run_lifecycle",
    "today",
    "today_board",
    "untouched_sessions",
    "update_slot",
    "update_subscription",
]
```

In `backend/config/settings/base.py`, replace:

```python
import environ
```

with:

```python
import environ
from celery.schedules import crontab
```

In `backend/config/settings/base.py`, replace:

```python
# Periodic jobs are declared here as they are built (none yet).
CELERY_BEAT_SCHEDULE: dict = {}
```

with:

```python
# Periodic jobs are declared here as they are built. Each loops over every
# academy itself (etqan.platform.tenancy.for_each_academy).
CELERY_BEAT_SCHEDULE: dict = {
    # Spec §7: hourly, so each academy's "today" turns over within the hour.
    "scheduling.run_daily": {
        "task": "scheduling.run_daily",
        "schedule": crontab(minute=5),
    },
}
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS — including the job across both test academies with the other one failing: its expiry is rolled back while the main academy's sticks.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): renewal with live carry-over and the hourly per-academy lifecycle job

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: API: subscriptions list, CSV, create, detail, edit, delete, renew, cancel

**Files:**
- Create: `backend/etqan/scheduling/api/__init__.py`, `backend/etqan/scheduling/api/payloads.py`, `backend/etqan/scheduling/api/serializers.py`, `backend/etqan/scheduling/api/views.py`, `backend/etqan/scheduling/api/urls.py`, `backend/etqan/scheduling/tests/test_api_subscriptions.py`
- Modify: `backend/etqan/scheduling/services/rules.py` (append the read models), `backend/etqan/scheduling/services/__init__.py`, `backend/config/api_router.py`, `backend/pyproject.toml`

**Interfaces:**
- Consumes: Tasks 3–6; `CSVExportMixin`, `IsAdmin`, `ReadOnly`, `StandardPagination`.
- Produces read models: `services.subscriptions_queryset()` (select_related student/teacher/course/package, annotated `renewal_id`, pauses prefetched), `services.slots_of(sub)` (annotated `has_sessions`), `services.sessions_of(sub, when="")`, `services.pause_state(pause, day) -> "upcoming" | "current" | "past"`.
- Produces payloads (D8): `subscription_row(sub, derived)`, `subscription_rows(subs)`, `slot_row(slot)`, `pause_row(pause, today)`, `subscription_detail(sub)` — see D8 for the keys.
- Produces routes: `GET, POST /api/v1/subscriptions/` (filters `status`, `student`, `teacher`, `course`, `q`; `?format=csv`), `GET, PATCH, DELETE /api/v1/subscriptions/<id>/` (PUT → 405), `POST …/renew/` → 201 with the NEW subscription's detail, `POST …/cancel/` → 200 detail.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/test_api_subscriptions.py`:

```python
import csv
import io
from datetime import date
from datetime import time

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.identity import services as identity_services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots

URL = "/api/v1/subscriptions/"


def body(world, **overrides):
    return {
        "student": world.student.id,
        "course": world.course.id,
        "teacher": world.teacher.id,
        "package": world.package.id,
        "starts_on": "2026-06-01",
        **overrides,
    }


def test_admin_creates_with_slots_and_gets_every_derived_value(api_for, world):
    resp = api_for("admin").post(
        URL,
        body(
            world,
            price_minor=120000,
            slots=[{"weekdays": [0, 2], "start_time": "18:00"}],
        ),
        format="json",
    )
    data = resp.json()
    assert resp.status_code == 201, data
    assert data["student"] == {
        "id": world.student.id,
        "full_name": "Yusuf",
        "timezone": "Asia/Riyadh",
    }
    assert data["course"]["name_en"] == "Tajweed"
    assert (data["status"], data["starts_on"], data["term_ends_on"]) == (
        "active",
        "2026-06-01",
        "2026-06-30",
    )
    assert (data["ends_on"], data["grace_ends_on"], data["in_grace"]) == (
        "2026-06-30",
        "2026-07-07",
        False,
    )
    assert {
        key: data[key]
        for key in (
            "sessions_total",
            "sessions_used",
            "carried_over_sessions",
            "sessions_remaining",
            "extra_sessions",
            "progress",
            "price_minor",
            "currency",
            "freeze_days_left",
            "renewed_from",
            "renewal",
            "renewal_starts_on",
        )
    } == {
        "sessions_total": 8,
        "sessions_used": 0,
        "carried_over_sessions": 0,
        "sessions_remaining": 8,
        "extra_sessions": 0,
        "progress": 0.0,
        "price_minor": 120000,
        "currency": "EGP",
        "freeze_days_left": 10,
        "renewed_from": None,
        "renewal": None,
        "renewal_starts_on": "2026-07-01",
    }
    assert [(s["weekday"], s["start_time"], s["minutes"]) for s in data["slots"]] == [
        (0, "18:00", 45),
        (2, "18:00", 45),
    ]
    assert all(s["has_sessions"] for s in data["slots"])
    assert Session.objects.filter(subscription_id=data["id"]).count() == 5


@pytest.mark.parametrize(
    ("overrides", "field"),
    [
        ({"starts_on": "not-a-date"}, "starts_on"),
        ({"price_minor": -1}, "price_minor"),
        ({"slots": [{"weekdays": [7], "start_time": "18:00"}]}, "slots"),
        ({"slots": [{"weekdays": [], "start_time": "18:00"}]}, "slots"),
    ],
)
def test_bad_bodies_are_field_errors(api_for, world, overrides, field):
    resp = api_for("admin").post(URL, body(world, **overrides), format="json")
    assert resp.status_code == 400
    assert field in resp.json()


def test_service_field_errors_use_the_body_names(api_for, world):
    resp = api_for("admin").post(
        URL, body(world, teacher=world.student.id), format="json"
    )
    assert resp.status_code == 400
    assert "teacher" in resp.json()


def test_patch_teacher_price_notes_and_start(api_for, subscribe):
    sub = subscribe(slots=two_slots())
    admin = api_for("admin")
    resp = admin.patch(
        f"{URL}{sub.pk}/",
        {"price_minor": 99, "notes": "Sibling discount", "starts_on": "2026-06-03"},
        format="json",
    )
    data = resp.json()
    assert resp.status_code == 200, data
    assert (data["price_minor"], data["notes"], data["term_ends_on"]) == (
        99,
        "Sibling discount",
        "2026-07-02",
    )
    assert admin.put(f"{URL}{sub.pk}/", {}, format="json").status_code == 405


def test_renew_cancel_and_delete(api_for, subscribe):
    admin = api_for("admin")
    sub = subscribe(slots=two_slots())
    resp = admin.post(f"{URL}{sub.pk}/renew/", {"price_minor": 1000}, format="json")
    renewal = resp.json()
    assert resp.status_code == 201, renewal
    assert (renewal["renewed_from"], renewal["starts_on"], renewal["price_minor"]) == (
        sub.pk,
        "2026-07-01",
        1000,
    )
    assert admin.get(f"{URL}{sub.pk}/").json()["renewal"] == renewal["id"]
    again = admin.post(f"{URL}{sub.pk}/renew/", {}, format="json")
    assert again.status_code == 409
    assert again.json()["code"] == "scheduling.already_renewed"
    cancelled = admin.post(f"{URL}{renewal['id']}/cancel/")
    assert cancelled.json()["status"] == "cancelled"
    assert admin.delete(f"{URL}{renewal['id']}/").status_code == 204
    assert admin.get(f"{URL}{renewal['id']}/").status_code == 404


def test_delete_is_refused_once_attendance_is_marked(api_for, subscribe):
    sub = subscribe(slots=two_slots())
    Session.objects.filter(subscription=sub, occurs_on=date(2026, 6, 1)).update(
        student_attendance="present"
    )
    resp = api_for("admin").delete(f"{URL}{sub.pk}/")
    assert resp.status_code == 409
    assert resp.json()["code"] == "scheduling.has_marked_sessions"


def test_catalogue_items_with_subscriptions_are_not_deleted(api_for, subscribe, world):
    subscribe()
    admin = api_for("admin")
    for path in (
        f"/api/v1/catalogue/courses/{world.course.id}/",
        f"/api/v1/catalogue/packages/{world.package.id}/",
    ):
        resp = admin.delete(path)
        assert resp.status_code == 409
        assert resp.json()["code"] == "catalogue.in_use"


def test_filters_and_search(api_for, subscribe, world):
    aisha = make_student("Aisha")
    mine = subscribe()
    theirs = subscribe(student_id=aisha.id)
    admin = api_for("admin")
    admin.post(f"{URL}{theirs.pk}/cancel/")

    def ids(query):
        return [row["id"] for row in admin.get(f"{URL}{query}").json()["results"]]

    assert set(ids("")) == {mine.pk, theirs.pk}
    assert ids("?status=cancelled") == [theirs.pk]
    assert ids("?status=active") == [mine.pk]
    assert ids(f"?student={aisha.id}") == [theirs.pk]
    assert ids("?q=yus") == [mine.pk]
    assert set(ids(f"?teacher={world.teacher.id}&course={world.course.id}")) == {
        mine.pk,
        theirs.pk,
    }


def test_csv_has_the_filtered_rows(api_for, subscribe):
    subscribe()
    resp = api_for("admin").get(f"{URL}?status=active&format=csv")
    assert resp.status_code == 200
    rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert rows[0][:5] == ["ID", "Student", "Course", "Teacher", "Status"]
    assert rows[1][1:5] == ["Yusuf", "Tajweed", "Bilal", "active"]
    assert "Carried over" in rows[0]


def test_the_list_costs_the_same_queries_for_two_or_six_rows(api_for, subscribe):
    admin = api_for("admin")

    def queries():
        with CaptureQueriesContext(connection) as ctx:
            assert admin.get(URL).status_code == 200
        return len(ctx.captured_queries)

    subscribe(slots=two_slots())
    subscribe(student_id=make_student("S1").id, slots=two_slots(time(9)))
    two = queries()
    for n in range(2, 6):
        subscribe(student_id=make_student(f"S{n}").id)
    assert queries() == two


def as_user(user):
    client = APIClient()
    client.force_login(user)
    return client


def test_each_role_reads_only_its_own_and_writes_nothing(subscribe, world):
    mine = subscribe(slots=two_slots())
    other = subscribe(student_id=make_student("Aisha").id)
    parent = identity_services.create_person("parent", full_name="Omar")
    identity_services.link_guardian(parent, world.student)
    cases = [
        (world.student, {mine.pk}),
        (parent, {mine.pk}),
        (world.teacher, {mine.pk, other.pk}),
        (make_teacher("Maryam"), set()),
    ]
    for user, visible in cases:
        client = as_user(user)
        rows = client.get(URL).json()["results"]
        assert {row["id"] for row in rows} == visible, user.full_name
        for sub in (mine, other):
            expected = 200 if sub.pk in visible else 404
            assert client.get(f"{URL}{sub.pk}/").status_code == expected
        assert client.post(URL, body(world), format="json").status_code == 403
        assert client.patch(f"{URL}{mine.pk}/", {}, format="json").status_code == 403
        assert client.delete(f"{URL}{mine.pk}/").status_code == 403
        assert client.post(f"{URL}{mine.pk}/renew/", {}).status_code == 403
        assert client.post(f"{URL}{mine.pk}/cancel/").status_code == 403


def test_another_academy_never_leaks(api_for, subscribe, tenants):
    with tenant_context(tenants.other):
        world = build_world()
        identity_services.update_person(
            world.student, fields={"full_name": "Layla Other"}
        )
        theirs = subscription_for(world, slots=two_slots())
    mine = subscribe(slots=two_slots())
    admin = api_for("admin")
    listing = admin.get(URL)
    assert [r["id"] for r in listing.json()["results"]] == [mine.pk]
    for path in (
        URL,
        f"{URL}?format=csv",
        f"{URL}{theirs.pk}/",
    ):
        resp = admin.get(path)
        assert b"Layla Other" not in resp.content, path
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_api_subscriptions.py`
Expected: FAIL — 404 on `/api/v1/subscriptions/`.

- [ ] **Step 3: Implement**

Add these imports to `backend/etqan/scheduling/services/rules.py` (`ruff check --fix` in the format step puts them in order):

```python
from django.db.models import F
from etqan.scheduling.models import ScheduleSlot
```

Append to the end of `backend/etqan/scheduling/services/rules.py`:

```python
# ── API reads ────────────────────────────────────────────────────────────────


def subscriptions_queryset() -> QuerySet[Subscription]:
    """Subscriptions with everything a row shows, in a fixed number of queries."""
    return (
        Subscription.objects.select_related(
            "student__user", "teacher__user", "course", "package"
        )
        .annotate(renewal_id=F("renewal__id"))
        .prefetch_related("pauses")
    )


def slots_of(subscription: Subscription) -> QuerySet[ScheduleSlot]:
    produced = Session.objects.filter(slot=OuterRef("pk"))
    return subscription.slots.annotate(has_sessions=Exists(produced))


def sessions_of(subscription: Subscription, when: str = "") -> QuerySet[Session]:
    """``when``: ``upcoming`` (soonest first), ``past`` (latest first) or all."""
    sessions = Session.objects.filter(subscription=subscription).select_related(
        *SESSION_RELATED
    )
    if when == "upcoming":
        return sessions.filter(starts_at__gte=dates.now()).order_by("starts_at", "id")
    if when == "past":
        return sessions.filter(starts_at__lt=dates.now()).order_by("-starts_at", "-id")
    return sessions.order_by("starts_at", "id")


def pause_state(pause: SubscriptionPause, day: date) -> str:
    if day < pause.from_date:
        return "upcoming"
    return "current" if day <= pause.to_date else "past"
```

Replace the whole of `backend/etqan/scheduling/services/__init__.py` with:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.board import TodayRow
from etqan.scheduling.services.board import today_board
from etqan.scheduling.services.generation import GenerationResult
from etqan.scheduling.services.generation import generate
from etqan.scheduling.services.generation import generate_horizon
from etqan.scheduling.services.lifecycle import run_lifecycle
from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import pause_state
from etqan.scheduling.services.rules import renewal_starts_on
from etqan.scheduling.services.rules import sessions_of
from etqan.scheduling.services.rules import slots_of
from etqan.scheduling.services.rules import subscriptions_queryset
from etqan.scheduling.services.rules import today
from etqan.scheduling.services.rules import untouched_sessions
from etqan.scheduling.services.subscriptions import add_pause
from etqan.scheduling.services.subscriptions import add_slots
from etqan.scheduling.services.subscriptions import cancel_subscription
from etqan.scheduling.services.subscriptions import create_subscription
from etqan.scheduling.services.subscriptions import delete_pause
from etqan.scheduling.services.subscriptions import delete_slot
from etqan.scheduling.services.subscriptions import delete_subscription
from etqan.scheduling.services.subscriptions import end_pause
from etqan.scheduling.services.subscriptions import renew_subscription
from etqan.scheduling.services.subscriptions import update_slot
from etqan.scheduling.services.subscriptions import update_subscription

__all__ = [
    "Derived",
    "GenerationResult",
    "TodayRow",
    "add_pause",
    "add_slots",
    "cancel_subscription",
    "create_subscription",
    "delete_pause",
    "delete_slot",
    "delete_subscription",
    "derive",
    "derived",
    "end_pause",
    "generate",
    "generate_horizon",
    "has_marked_sessions",
    "pause_state",
    "renew_subscription",
    "renewal_starts_on",
    "run_lifecycle",
    "sessions_of",
    "slots_of",
    "subscriptions_queryset",
    "today",
    "today_board",
    "untouched_sessions",
    "update_slot",
    "update_subscription",
]
```

Create `backend/etqan/scheduling/api/__init__.py`:

```python

```

Create `backend/etqan/scheduling/api/payloads.py`:

```python
"""JSON shapes for scheduling (plan D9). Derived values come from the one
`derive` service; these functions only arrange them."""

from etqan.scheduling import dates
from etqan.scheduling import services


def _person(profile) -> dict:
    return {"id": profile.user_id, "full_name": profile.user.full_name}


def _student(profile) -> dict:
    return {**_person(profile), "timezone": profile.user.timezone}


def _named(obj) -> dict:
    return {"id": obj.pk, "name_ar": obj.name_ar, "name_en": obj.name_en}


def _hhmm(value) -> str:
    return value.strftime("%H:%M")


def subscription_row(sub, values: services.Derived) -> dict:
    return {
        "id": sub.pk,
        "status": sub.status,
        "student": _student(sub.student),
        "teacher": _person(sub.teacher),
        "course": _named(sub.course),
        "package": _named(sub.package),
        "starts_on": sub.starts_on,
        "term_ends_on": sub.term_ends_on,
        "ends_on": values.ends_on,
        "grace_ends_on": values.grace_ends_on,
        "in_grace": values.in_grace,
        "sessions_total": sub.sessions_total,
        "sessions_used": values.sessions_used,
        "carried_over_sessions": values.carried_over_sessions,
        "sessions_remaining": values.sessions_remaining,
        "extra_sessions": values.extra_sessions,
        "progress": round(values.progress, 4),
        "price_minor": sub.price_minor,
        "currency": sub.currency,
        "renewed_from": sub.renewed_from_id,
        "renewal": getattr(sub, "renewal_id", None),
    }


def subscription_rows(subs) -> list[dict]:
    subs = list(subs)
    values = services.derive(subs)
    return [subscription_row(sub, values[sub.pk]) for sub in subs]


def slot_row(slot) -> dict:
    return {
        "id": slot.pk,
        "weekday": slot.weekday,
        "start_time": _hhmm(slot.start_time),
        "minutes": slot.minutes,
        "meeting_url": slot.meeting_url,
        "is_active": slot.is_active,
        "has_sessions": getattr(slot, "has_sessions", True),
    }


def pause_row(pause, today) -> dict:
    return {
        "id": pause.pk,
        "from_date": pause.from_date,
        "to_date": pause.to_date,
        "reason": pause.reason,
        "days": dates.inclusive_days(pause.from_date, pause.to_date),
        "state": services.pause_state(pause, today),
    }


def subscription_detail(sub) -> dict:
    values = services.derived(sub)
    today = services.today()
    return {
        **subscription_row(sub, values),
        "duration_value": sub.duration_value,
        "duration_unit": sub.duration_unit,
        "session_minutes": sub.session_minutes,
        "freeze_days_allowed": sub.freeze_days_allowed,
        "paused_days": values.paused_days,
        "freeze_days_left": values.freeze_days_left,
        "notes": sub.notes,
        "renewal_starts_on": services.renewal_starts_on(sub),
        "slots": [slot_row(slot) for slot in services.slots_of(sub)],
        "pauses": [pause_row(pause, today) for pause in sub.pauses.all()],
    }
```

Create `backend/etqan/scheduling/api/serializers.py`:

```python
"""Request bodies (spec §5). Responses are built in `payloads`."""

from rest_framework import serializers


def _id(**kwargs):
    return serializers.IntegerField(min_value=1, **kwargs)


class SlotInput(serializers.Serializer):
    weekdays = serializers.ListField(
        child=serializers.IntegerField(min_value=0, max_value=6),
        allow_empty=False,
        max_length=7,
    )
    start_time = serializers.TimeField()
    minutes = serializers.IntegerField(min_value=15, max_value=240, required=False)
    meeting_url = serializers.URLField(required=False, allow_blank=True)


class SubscriptionCreateInput(serializers.Serializer):
    student = _id()
    course = _id()
    teacher = _id()
    package = _id()
    starts_on = serializers.DateField()
    price_minor = serializers.IntegerField(min_value=0, required=False)
    notes = serializers.CharField(required=False, allow_blank=True)
    slots = SlotInput(many=True, required=False)


class SubscriptionUpdateInput(serializers.Serializer):
    teacher = _id(required=False)
    price_minor = serializers.IntegerField(min_value=0, required=False)
    notes = serializers.CharField(required=False, allow_blank=True)
    starts_on = serializers.DateField(required=False)


class RenewInput(serializers.Serializer):
    starts_on = serializers.DateField(required=False)
    teacher = _id(required=False)
    package = _id(required=False)
    course = _id(required=False)
    price_minor = serializers.IntegerField(min_value=0, required=False)
```

Create `backend/etqan/scheduling/api/views.py`:

```python
"""Scheduling endpoints (spec §5). Thin: parse, call a service, arrange a payload."""

from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import IsAdmin
from etqan.platform.permissions import ReadOnly
from etqan.scheduling import services
from etqan.scheduling.api import payloads
from etqan.scheduling.api.serializers import RenewInput
from etqan.scheduling.api.serializers import SubscriptionCreateInput
from etqan.scheduling.api.serializers import SubscriptionUpdateInput
from etqan.scheduling.models import Subscription
from etqan.scheduling.scopes import scope_for

STATUSES = set(Subscription.Status.values)
CSV_COLUMNS = (
    ("id", "ID"),
    ("student", "Student"),
    ("course", "Course"),
    ("teacher", "Teacher"),
    ("status", "Status"),
    ("starts_on", "Starts on"),
    ("ends_on", "Ends on"),
    ("grace_ends_on", "Grace ends on"),
    ("sessions_total", "Sessions total"),
    ("sessions_used", "Sessions used"),
    ("carried_over_sessions", "Carried over"),
    ("sessions_remaining", "Remaining"),
    ("price_minor", "Price (minor units)"),
    ("currency", "Currency"),
)
# Body keys (spec §5) → service keyword arguments.
ID_FIELDS = {
    "student": "student_id",
    "course": "course_id",
    "teacher": "teacher_id",
    "package": "package_id",
}


def _ids(data: dict) -> dict:
    return {ID_FIELDS.get(key, key): value for key, value in data.items()}


def subscriptions_in_scope(request):
    return scope_for(request.user, services.subscriptions_queryset())


def subscription_or_404(request, pk) -> Subscription:
    return get_object_or_404(subscriptions_in_scope(request), pk=pk)


def filter_subscriptions(queryset, params):
    if (value := params.get("status")) in STATUSES:
        queryset = queryset.filter(status=value)
    for key, lookup in (
        ("student", "student__user_id"),
        ("teacher", "teacher__user_id"),
        ("course", "course_id"),
    ):
        if (value := params.get(key, "")).isdigit():
            queryset = queryset.filter(**{lookup: int(value)})
    if q := params.get("q", "").strip():
        queryset = queryset.filter(Q(student__user__full_name__icontains=q))
    return queryset


def detail(pk, *, code=status.HTTP_200_OK) -> Response:
    sub = services.subscriptions_queryset().get(pk=pk)
    return Response(payloads.subscription_detail(sub), status=code)


class SubscriptionListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = [IsAdmin | ReadOnly]
    csv_filename = "subscriptions"
    csv_columns = CSV_COLUMNS

    def get(self, request):
        queryset = filter_subscriptions(
            subscriptions_in_scope(request), request.query_params
        )
        if self.wants_csv():
            return self.csv_response(payloads.subscription_rows(queryset))
        page = self.paginate_queryset(queryset)
        return self.get_paginated_response(payloads.subscription_rows(page))

    def post(self, request):
        body = SubscriptionCreateInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = _ids(body.validated_data)
        sub = services.create_subscription(**data)
        return detail(sub.pk, code=status.HTTP_201_CREATED)


class SubscriptionDetailView(APIView):
    permission_classes = [IsAdmin | ReadOnly]

    def get(self, request, pk):
        return Response(payloads.subscription_detail(subscription_or_404(request, pk)))

    def patch(self, request, pk):
        sub = subscription_or_404(request, pk)
        body = SubscriptionUpdateInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_subscription(sub, **_ids(body.validated_data))
        return detail(sub.pk)

    def delete(self, request, pk):
        services.delete_subscription(subscription_or_404(request, pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class RenewView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        sub = subscription_or_404(request, pk)
        body = RenewInput(data=request.data)
        body.is_valid(raise_exception=True)
        new = services.renew_subscription(sub, **_ids(body.validated_data))
        return detail(new.pk, code=status.HTTP_201_CREATED)


class CancelView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        services.cancel_subscription(subscription_or_404(request, pk))
        return detail(pk)
```

Create `backend/etqan/scheduling/api/urls.py`:

```python
from django.urls import path

from etqan.scheduling.api import views

app_name = "scheduling"
urlpatterns = [
    path("subscriptions/", views.SubscriptionListView.as_view(), name="list"),
    path(
        "subscriptions/<int:pk>/",
        views.SubscriptionDetailView.as_view(),
        name="detail",
    ),
    path("subscriptions/<int:pk>/renew/", views.RenewView.as_view(), name="renew"),
    path("subscriptions/<int:pk>/cancel/", views.CancelView.as_view(), name="cancel"),
]
```

In `backend/config/api_router.py`, replace:

```python
    path("people/", include("etqan.identity.api.people_urls")),
```

with:

```python
    path("people/", include("etqan.identity.api.people_urls")),
    # subscriptions/, pauses/, slots/, schedule/ (spec §5).
    path("", include("etqan.scheduling.api.urls")),
```

Now that `scopes`, `tasks` and `api` exist, forbid other apps from reaching past `etqan.scheduling.services`:

Append to the end of `backend/pyproject.toml`:

```toml
[[tool.importlinter.contracts]]
name = "other apps reach scheduling only through its services"
type = "forbidden"
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants"]
forbidden_modules = [
    "etqan.scheduling.models", "etqan.scheduling.api", "etqan.scheduling.dates",
    "etqan.scheduling.scopes", "etqan.scheduling.tasks",
]
allow_indirect_imports = true
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS — including `test_the_list_costs_the_same_queries_for_two_or_six_rows` and `test_another_academy_never_leaks` (both academies hold a subscription; the other academy's student name never appears in list, CSV or detail).

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass; `test_api_docs` still builds the OpenAPI schema.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): subscriptions API with derived values, filters, CSV, renew and cancel

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: API: pauses, slots, sessions, generate and Today

**Files:**
- Modify: `backend/etqan/scheduling/api/payloads.py`, `backend/etqan/scheduling/api/serializers.py`, `backend/etqan/scheduling/api/views.py` (append), `backend/etqan/scheduling/api/urls.py` (replace)
- Create: `backend/etqan/scheduling/tests/test_api_schedule.py`

**Interfaces:**
- Consumes: Task 7's `subscription_or_404`, `detail`, payloads.
- Produces routes: `GET, POST /subscriptions/<id>/pauses/` (POST → 201 subscription detail), `DELETE /pauses/<id>/` (204), `POST /pauses/<id>/end/` (200 detail), `GET, POST /subscriptions/<id>/slots/` (POST `{weekdays, start_time, minutes?, meeting_url?}` → 201 detail), `PATCH, DELETE /slots/<id>/` (PUT → 405), `GET /subscriptions/<id>/sessions/?when=upcoming|past` (paginated), `POST /schedule/generate/` `{from, to, subscription?}` (≤ 62 days) → the run result, `GET /schedule/today/` → `{date, rows}` (D9).
- Produces payloads: `session_row(session)`, `generation_result(result)`, `today_row(row)`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/test_api_schedule.py`:

```python
from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.identity import services as identity_services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots

SUBS = "/api/v1/subscriptions/"
GENERATE = "/api/v1/schedule/generate/"
TODAY = "/api/v1/schedule/today/"


# ── Pauses ───────────────────────────────────────────────────────────────────


def test_pauses_add_list_end_and_delete(api_for, subscribe, clock):
    admin = api_for("admin")
    sub = subscribe(slots=two_slots())
    resp = admin.post(
        f"{SUBS}{sub.pk}/pauses/",
        {"from_date": "2026-06-01", "to_date": "2026-06-05", "reason": "Travel"},
        format="json",
    )
    data = resp.json()
    assert resp.status_code == 201, data
    assert (data["status"], data["paused_days"], data["freeze_days_left"]) == (
        "paused",
        5,
        5,
    )
    [pause] = data["pauses"]
    assert (pause["days"], pause["state"], pause["reason"]) == (5, "current", "Travel")
    future = admin.post(
        f"{SUBS}{sub.pk}/pauses/",
        {"from_date": "2026-06-20", "to_date": "2026-06-21"},
        format="json",
    ).json()["pauses"][1]
    assert future["state"] == "upcoming"
    listed = admin.get(f"{SUBS}{sub.pk}/pauses/").json()
    assert [p["id"] for p in listed] == [pause["id"], future["id"]]
    clock.set(datetime(2026, 6, 3, 9, tzinfo=UTC))
    ended = admin.post(f"/api/v1/pauses/{pause['id']}/end/").json()
    assert (ended["status"], ended["pauses"][0]["to_date"]) == ("active", "2026-06-02")
    assert admin.delete(f"/api/v1/pauses/{future['id']}/").status_code == 204
    assert admin.delete(f"/api/v1/pauses/{pause['id']}/").status_code == 409


def test_pause_errors(api_for, subscribe):
    sub = subscribe()
    admin = api_for("admin")
    backwards = admin.post(
        f"{SUBS}{sub.pk}/pauses/",
        {"from_date": "2026-06-05", "to_date": "2026-06-01"},
        format="json",
    )
    assert (backwards.status_code, list(backwards.json())) == (400, ["to_date"])
    too_long = admin.post(
        f"{SUBS}{sub.pk}/pauses/",
        {"from_date": "2026-06-01", "to_date": "2026-06-30"},
        format="json",
    )
    assert too_long.status_code == 409
    assert too_long.json()["code"] == "scheduling.freeze_days_exceeded"


# ── Slots ────────────────────────────────────────────────────────────────────


def test_slots_add_edit_deactivate_delete(api_for, subscribe):
    admin = api_for("admin")
    sub = subscribe()
    resp = admin.post(
        f"{SUBS}{sub.pk}/slots/",
        {"weekdays": [0, 3], "start_time": "17:30", "minutes": 60},
        format="json",
    )
    assert resp.status_code == 201, resp.json()
    monday, thursday = resp.json()["slots"]
    assert (monday["weekday"], monday["start_time"], monday["minutes"]) == (
        0,
        "17:30",
        60,
    )
    assert admin.get(f"{SUBS}{sub.pk}/slots/").json()[1]["weekday"] == 3
    taken = admin.post(
        f"{SUBS}{sub.pk}/slots/",
        {"weekdays": [0], "start_time": "17:30"},
        format="json",
    )
    assert (taken.status_code, list(taken.json())) == (400, ["start_time"])
    edited = admin.patch(
        f"/api/v1/slots/{monday['id']}/", {"start_time": "08:15"}, format="json"
    )
    assert edited.json()["slots"][0]["start_time"] == "08:15"
    assert Session.objects.get(
        slot_id=monday["id"], occurs_on=date(2026, 6, 1)
    ).starts_at == (datetime(2026, 6, 1, 8, 15, tzinfo=UTC))
    refused = admin.delete(f"/api/v1/slots/{monday['id']}/")
    assert refused.json()["code"] == "scheduling.slot_has_sessions"
    admin.patch(f"/api/v1/slots/{monday['id']}/", {"is_active": False}, format="json")
    assert admin.delete(f"/api/v1/slots/{monday['id']}/").status_code == 204
    assert admin.put(f"/api/v1/slots/{thursday['id']}/", {}).status_code == 405


# ── Sessions ─────────────────────────────────────────────────────────────────


def test_sessions_upcoming_and_past(api_for, subscribe, clock):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 8, 12, tzinfo=UTC))
    admin = api_for("admin")
    upcoming = admin.get(f"{SUBS}{sub.pk}/sessions/?when=upcoming").json()
    past = admin.get(f"{SUBS}{sub.pk}/sessions/?when=past").json()
    assert [s["occurs_on"] for s in upcoming["results"]] == [
        "2026-06-08",
        "2026-06-10",
        "2026-06-15",
    ]
    assert [s["occurs_on"] for s in past["results"]] == ["2026-06-03", "2026-06-01"]
    first = upcoming["results"][0]
    assert (first["status"], first["minutes"], first["meeting_url"]) == (
        "scheduled",
        45,
        "https://meet.test/bilal",
    )
    assert first["teacher"]["full_name"] == "Bilal"
    assert admin.get(f"{SUBS}{sub.pk}/sessions/").json()["count"] == 5


# ── Generate and Today ───────────────────────────────────────────────────────


def test_generate_a_range_reports_conflicts(api_for, subscribe):
    subscribe(slots=two_slots())
    second = subscribe(student_id=make_student("Aisha").id)
    ScheduleSlot.objects.create(
        subscription=second, weekday=MONDAY, start_time=time(18, 30), minutes=45
    )
    resp = api_for("admin").post(
        GENERATE, {"from": "2026-06-01", "to": "2026-06-07"}, format="json"
    )
    data = resp.json()
    assert resp.status_code == 200, data
    assert (data["created"], data["skipped_existing"]) == (1, 2)
    [conflict] = data["conflicts"]
    assert conflict["session"]["student"]["full_name"] == "Aisha"
    assert conflict["other"]["student"]["full_name"] == "Yusuf"
    assert conflict["session"]["starts_at"] == "2026-06-01T18:30:00Z"


@pytest.mark.parametrize(
    "bounds",
    [
        {"from": "2026-06-10", "to": "2026-06-09"},
        {"from": "2026-06-01", "to": "2026-08-02"},  # 63 days
    ],
)
def test_generate_range_limits(api_for, bounds):
    resp = api_for("admin").post(GENERATE, bounds, format="json")
    assert resp.status_code == 400
    assert "to" in resp.json()


def test_generate_62_days_for_one_subscription(api_for, subscribe):
    sub = subscribe(slots=two_slots())
    other = subscribe(student_id=make_student("Aisha").id, slots=two_slots(time(9)))
    resp = api_for("admin").post(
        GENERATE,
        {"from": "2026-06-01", "to": "2026-08-01", "subscription": sub.pk},
        format="json",
    )
    assert resp.status_code == 200
    assert resp.json()["created"] == 6  # 17 June .. 6 July
    assert Session.objects.filter(subscription=other).count() == 5


def test_today_board(api_for, subscribe):
    sub = subscribe(slots=two_slots())
    missing = subscribe(student_id=make_student("Aisha").id)
    ScheduleSlot.objects.create(
        subscription=missing, weekday=MONDAY, start_time=time(9), minutes=30
    )
    data = api_for("admin").get(TODAY).json()
    assert data["date"] == "2026-06-01"
    first, second = data["rows"]
    assert (first["state"], first["start_time"], first["session_id"]) == (
        "missing",
        "09:00",
        None,
    )
    assert (first["starts_at"], first["minutes"]) == ("2026-06-01T09:00:00Z", 30)
    assert first["student"] == {
        "id": missing.student.user_id,
        "full_name": "Aisha",
        "timezone": "UTC",
    }
    assert (second["state"], second["subscription_id"]) == ("generated", sub.pk)
    assert (second["sessions_used"], second["sessions_total"]) == (0, 8)


def test_nested_reads_follow_the_subscription_scope(subscribe, world):
    mine = subscribe(slots=two_slots())
    other = subscribe(student_id=make_student("Aisha").id)
    parent = identity_services.create_person("parent", full_name="Omar")
    identity_services.link_guardian(parent, world.student)
    cases = [
        (world.student, {mine.pk}),
        (parent, {mine.pk}),
        (world.teacher, {mine.pk, other.pk}),
        (make_teacher("Maryam"), set()),
    ]
    for user, visible in cases:
        client = APIClient()
        client.force_login(user)
        for sub in (mine, other):
            expected = 200 if sub.pk in visible else 404
            for suffix in ("sessions/", "pauses/", "slots/"):
                path = f"{SUBS}{sub.pk}/{suffix}"
                assert client.get(path).status_code == expected, path


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_schedule_endpoints_are_admin_only(api_for, subscribe, role):
    sub = subscribe(slots=two_slots())
    pause = SubscriptionPause.objects.create(
        subscription=sub, from_date=date(2026, 6, 20), to_date=date(2026, 6, 20)
    )
    slot = ScheduleSlot.objects.filter(subscription=sub).first()
    client = api_for(role)
    assert client.get(TODAY).status_code == 403
    assert client.post(GENERATE, {}, format="json").status_code == 403
    assert client.post(f"{SUBS}{sub.pk}/pauses/", {}).status_code == 403
    assert client.post(f"{SUBS}{sub.pk}/slots/", {}).status_code == 403
    assert client.post(f"/api/v1/pauses/{pause.pk}/end/").status_code == 403
    assert client.delete(f"/api/v1/pauses/{pause.pk}/").status_code == 403
    assert client.patch(f"/api/v1/slots/{slot.pk}/", {}).status_code == 403
    assert client.delete(f"/api/v1/slots/{slot.pk}/").status_code == 403


def test_another_academy_never_reaches_today_or_generate(api_for, subscribe, tenants):
    with tenant_context(tenants.other):
        world = build_world()
        identity_services.update_person(
            world.student, fields={"full_name": "Layla Other"}
        )
        theirs = subscription_for(world, slots=two_slots())
        pause = SubscriptionPause.objects.create(
            subscription=theirs, from_date=date(2026, 6, 20), to_date=date(2026, 6, 20)
        )
    subscribe(slots=two_slots())
    admin = api_for("admin")
    for suffix in ("sessions/", "pauses/", "slots/"):
        nested = admin.get(f"{SUBS}{theirs.pk}/{suffix}")
        assert b"Layla Other" not in nested.content, suffix
    today = admin.get(TODAY)
    assert [r["student"]["full_name"] for r in today.json()["rows"]] == ["Yusuf"]
    generated = admin.post(
        GENERATE,
        {"from": "2026-06-01", "to": "2026-06-30", "subscription": theirs.pk},
        format="json",
    )
    assert b"Layla Other" not in generated.content
    ended = admin.post(f"/api/v1/pauses/{pause.pk}/end/")
    assert b"Layla Other" not in ended.content
    with tenant_context(tenants.other):
        assert SubscriptionPause.objects.filter(pk=pause.pk).exists()
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling/tests/test_api_schedule.py`
Expected: FAIL — 404 on the nested routes and `/api/v1/schedule/…`.

- [ ] **Step 3: Implement**

Append to the end of `backend/etqan/scheduling/api/payloads.py`:

```python
def session_row(session) -> dict:
    return {
        "id": session.pk,
        "subscription_id": session.subscription_id,
        "slot_id": session.slot_id,
        "occurs_on": session.occurs_on,
        "starts_at": session.starts_at,
        "minutes": session.minutes,
        "status": session.status,
        "student_attendance": session.student_attendance,
        "teacher_attendance": session.teacher_attendance,
        "meeting_url": session.meeting_url,
        "generated": session.generated,
        "student": _person(session.student),
        "teacher": _person(session.teacher),
        "course": _named(session.course),
    }


def generation_result(result: services.GenerationResult) -> dict:
    return {
        "created": result.created,
        "skipped_existing": result.skipped_existing,
        "skipped_paused": result.skipped_paused,
        "skipped_out_of_term": result.skipped_out_of_term,
        "conflicts": [
            {"session": session_row(session), "other": session_row(other)}
            for session, other in result.conflicts
        ],
    }


def today_row(row: services.TodayRow) -> dict:
    sub, values = row.subscription, row.derived
    return {
        "slot_id": row.slot.pk,
        "subscription_id": sub.pk,
        "session_id": row.session.pk if row.session else None,
        "date": row.day,
        "start_time": _hhmm(row.slot.start_time),
        "starts_at": row.starts_at,
        "minutes": row.slot.minutes,
        "state": row.state,
        "student": _student(sub.student),
        "teacher": _person(sub.teacher),
        "course": _named(sub.course),
        "sessions_total": sub.sessions_total,
        "sessions_used": values.sessions_used,
        "carried_over_sessions": values.carried_over_sessions,
        "extra_sessions": values.extra_sessions,
        "progress": round(values.progress, 4),
    }
```

Append to the end of `backend/etqan/scheduling/api/serializers.py`:

```python
class PauseInput(serializers.Serializer):
    from_date = serializers.DateField()
    to_date = serializers.DateField()
    reason = serializers.CharField(required=False, allow_blank=True)


class SlotUpdateInput(serializers.Serializer):
    start_time = serializers.TimeField(required=False)
    minutes = serializers.IntegerField(min_value=15, max_value=240, required=False)
    meeting_url = serializers.URLField(required=False, allow_blank=True)
    is_active = serializers.BooleanField(required=False)


# Spec §5: an on-demand run covers at most 62 days.
MAX_GENERATE_DAYS = 62


class GenerateInput(serializers.Serializer):
    to = serializers.DateField()
    subscription = _id(required=False)

    def get_fields(self):
        # `from` is a Python keyword, so it cannot be a class attribute.
        fields = super().get_fields()
        fields["from"] = serializers.DateField()
        return fields

    def validate(self, attrs):
        days = (attrs["to"] - attrs["from"]).days + 1
        if days < 1:
            raise serializers.ValidationError({"to": ["End on or after the start."]})
        if days > MAX_GENERATE_DAYS:
            raise serializers.ValidationError(
                {"to": [f"Choose at most {MAX_GENERATE_DAYS} days."]}
            )
        return attrs
```

Add these imports to `backend/etqan/scheduling/api/views.py` (`ruff check --fix` in the format step puts them in order):

```python
from etqan.scheduling.api.serializers import GenerateInput
from etqan.scheduling.api.serializers import PauseInput
from etqan.scheduling.api.serializers import SlotInput
from etqan.scheduling.api.serializers import SlotUpdateInput
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import SubscriptionPause
```

Append to the end of `backend/etqan/scheduling/api/views.py`:

```python
class PauseListView(APIView):
    permission_classes = [IsAdmin | ReadOnly]

    def get(self, request, pk):
        sub = subscription_or_404(request, pk)
        today = services.today()
        return Response([payloads.pause_row(p, today) for p in sub.pauses.all()])

    def post(self, request, pk):
        sub = subscription_or_404(request, pk)
        body = PauseInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.add_pause(sub, **body.validated_data)
        return detail(sub.pk, code=status.HTTP_201_CREATED)


def pause_or_404(request, pk) -> SubscriptionPause:
    pauses = SubscriptionPause.objects.select_related("subscription")
    return get_object_or_404(scope_for(request.user, pauses, via="subscription"), pk=pk)


class PauseDetailView(APIView):
    permission_classes = [IsAdmin]

    def delete(self, request, pk):
        services.delete_pause(pause_or_404(request, pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class PauseEndView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        pause = pause_or_404(request, pk)
        services.end_pause(pause)
        return detail(pause.subscription_id)


class SlotListView(APIView):
    permission_classes = [IsAdmin | ReadOnly]

    def get(self, request, pk):
        sub = subscription_or_404(request, pk)
        return Response([payloads.slot_row(s) for s in services.slots_of(sub)])

    def post(self, request, pk):
        sub = subscription_or_404(request, pk)
        body = SlotInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.add_slots(sub, **body.validated_data)
        return detail(sub.pk, code=status.HTTP_201_CREATED)


def slot_or_404(request, pk) -> ScheduleSlot:
    slots = ScheduleSlot.objects.select_related("subscription")
    return get_object_or_404(scope_for(request.user, slots, via="subscription"), pk=pk)


class SlotDetailView(APIView):
    permission_classes = [IsAdmin]

    def patch(self, request, pk):
        slot = slot_or_404(request, pk)
        body = SlotUpdateInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_slot(slot, **body.validated_data)
        return detail(slot.subscription_id)

    def delete(self, request, pk):
        services.delete_slot(slot_or_404(request, pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class SessionListView(generics.GenericAPIView):
    permission_classes = [IsAdmin | ReadOnly]

    def get(self, request, pk):
        sub = subscription_or_404(request, pk)
        when = request.query_params.get("when", "")
        page = self.paginate_queryset(services.sessions_of(sub, when))
        return self.get_paginated_response([payloads.session_row(s) for s in page])


class GenerateView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request):
        body = GenerateInput(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        sub = None
        if "subscription" in data:
            sub = subscription_or_404(request, data["subscription"])
        result = services.generate(data["from"], data["to"], subscription=sub)
        return Response(payloads.generation_result(result))


class TodayView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        rows = services.today_board()
        return Response(
            {
                "date": services.today(),
                "rows": [payloads.today_row(row) for row in rows],
            }
        )
```

Replace the whole of `backend/etqan/scheduling/api/urls.py` with:

```python
from django.urls import path

from etqan.scheduling.api import views

app_name = "scheduling"
urlpatterns = [
    path("subscriptions/", views.SubscriptionListView.as_view(), name="list"),
    path(
        "subscriptions/<int:pk>/",
        views.SubscriptionDetailView.as_view(),
        name="detail",
    ),
    path("subscriptions/<int:pk>/renew/", views.RenewView.as_view(), name="renew"),
    path("subscriptions/<int:pk>/cancel/", views.CancelView.as_view(), name="cancel"),
    path(
        "subscriptions/<int:pk>/pauses/", views.PauseListView.as_view(), name="pauses"
    ),
    path("subscriptions/<int:pk>/slots/", views.SlotListView.as_view(), name="slots"),
    path(
        "subscriptions/<int:pk>/sessions/",
        views.SessionListView.as_view(),
        name="sessions",
    ),
    path("pauses/<int:pk>/", views.PauseDetailView.as_view(), name="pause"),
    path("pauses/<int:pk>/end/", views.PauseEndView.as_view(), name="pause-end"),
    path("slots/<int:pk>/", views.SlotDetailView.as_view(), name="slot"),
    path("schedule/generate/", views.GenerateView.as_view(), name="generate"),
    path("schedule/today/", views.TodayView.as_view(), name="today"),
]
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/scheduling`
Expected: PASS — every nested read follows the subscription's scope, schedule endpoints are admin-only, and the other academy's pause can't be ended from this host.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(scheduling): pauses, slots, sessions, generate-for-range and Today endpoints

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dev seeds: four demo subscriptions, one in `other`

**Files:**
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py`, `backend/etqan/tenants/tests/test_seed_dev.py`
- Modify: `backend/etqan/catalogue/services.py` (`find_course`, `find_package`), `backend/etqan/scheduling/services/rules.py` (append `has_subscriptions`), `backend/etqan/scheduling/services/__init__.py`

**Interfaces:**
- Consumes: `create_subscription`, `add_pause`, `today`, `derive`, `subscriptions_queryset`, `sessions_of`.
- Produces: `catalogue_services.find_course(name_en)`, `find_package(name_en)`, `scheduling_services.has_subscriptions() -> bool`; `seed_dev` gives demo four subscriptions (one paused, one in grace) and other one; a second run changes nothing (D15).

- [ ] **Step 1: Write the failing test**

Append to the end of `backend/etqan/tenants/tests/test_seed_dev.py`:

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_adds_subscriptions_once():
    from etqan.scheduling import services as scheduling  # noqa: PLC0415

    def seeded():
        subs = list(scheduling.subscriptions_queryset().order_by("id"))
        return subs, sum(scheduling.sessions_of(s).count() for s in subs)

    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        subs, sessions = seeded()
        assert sorted(s.status for s in subs) == [
            "active",
            "active",
            "active",
            "paused",
        ]
        values = scheduling.derive(subs)
        assert [values[s.pk].in_grace for s in subs] == [False, False, True, False]
        assert sessions > 0
    with tenant_context(other):
        assert len(seeded()[0]) == 1
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert (len(seeded()[0]), seeded()[1]) == (4, sessions)
```

- [ ] **Step 2: Run it to verify it fails**

Run (from `backend/`): `.venv/bin/pytest -q etqan/tenants/tests/test_seed_dev.py`
Expected: FAIL — `test_seed_dev_adds_subscriptions_once`: no subscriptions (`[] == ['active', …]`).

- [ ] **Step 3: Implement**

Append to the end of `backend/etqan/scheduling/services/rules.py`:

```python
# ── Seeds ────────────────────────────────────────────────────────────────────


def has_subscriptions() -> bool:
    return Subscription.objects.exists()
```

Replace the whole of `backend/etqan/scheduling/services/__init__.py` with:

```python
"""Public API of the scheduling module. Other apps import only this package."""

from etqan.scheduling.services.board import TodayRow
from etqan.scheduling.services.board import today_board
from etqan.scheduling.services.generation import GenerationResult
from etqan.scheduling.services.generation import generate
from etqan.scheduling.services.generation import generate_horizon
from etqan.scheduling.services.lifecycle import run_lifecycle
from etqan.scheduling.services.rules import Derived
from etqan.scheduling.services.rules import derive
from etqan.scheduling.services.rules import derived
from etqan.scheduling.services.rules import has_marked_sessions
from etqan.scheduling.services.rules import has_subscriptions
from etqan.scheduling.services.rules import pause_state
from etqan.scheduling.services.rules import renewal_starts_on
from etqan.scheduling.services.rules import sessions_of
from etqan.scheduling.services.rules import slots_of
from etqan.scheduling.services.rules import subscriptions_queryset
from etqan.scheduling.services.rules import today
from etqan.scheduling.services.rules import untouched_sessions
from etqan.scheduling.services.subscriptions import add_pause
from etqan.scheduling.services.subscriptions import add_slots
from etqan.scheduling.services.subscriptions import cancel_subscription
from etqan.scheduling.services.subscriptions import create_subscription
from etqan.scheduling.services.subscriptions import delete_pause
from etqan.scheduling.services.subscriptions import delete_slot
from etqan.scheduling.services.subscriptions import delete_subscription
from etqan.scheduling.services.subscriptions import end_pause
from etqan.scheduling.services.subscriptions import renew_subscription
from etqan.scheduling.services.subscriptions import update_slot
from etqan.scheduling.services.subscriptions import update_subscription

__all__ = [
    "Derived",
    "GenerationResult",
    "TodayRow",
    "add_pause",
    "add_slots",
    "cancel_subscription",
    "create_subscription",
    "delete_pause",
    "delete_slot",
    "delete_subscription",
    "derive",
    "derived",
    "end_pause",
    "generate",
    "generate_horizon",
    "has_marked_sessions",
    "has_subscriptions",
    "pause_state",
    "renew_subscription",
    "renewal_starts_on",
    "run_lifecycle",
    "sessions_of",
    "slots_of",
    "subscriptions_queryset",
    "today",
    "today_board",
    "untouched_sessions",
    "update_slot",
    "update_subscription",
]
```

In `backend/etqan/catalogue/services.py`, replace:

```python
def get_course(course_id: int) -> Course | None:
    return Course.objects.filter(pk=course_id).first()
```

with:

```python
def get_course(course_id: int) -> Course | None:
    return Course.objects.filter(pk=course_id).first()


def find_course(name_en: str) -> Course | None:
    return Course.objects.filter(name_en=name_en).first()
```

In `backend/etqan/catalogue/services.py`, replace:

```python
def get_package(package_id: int) -> Package | None:
    return Package.objects.filter(pk=package_id).first()
```

with:

```python
def get_package(package_id: int) -> Package | None:
    return Package.objects.filter(pk=package_id).first()


def find_package(name_en: str) -> Package | None:
    return Package.objects.filter(name_en=name_en).first()
```

Add these imports to `backend/etqan/tenants/management/commands/seed_dev.py` (`ruff check --fix` in the format step puts them in order):

```python
from datetime import time
from datetime import timedelta

from etqan.scheduling import services as scheduling_services
```

In `backend/etqan/tenants/management/commands/seed_dev.py` (the demo `Monthly, 2 a week` package), replace:

```python
                "duration_value": 1,
                "duration_unit": "month",
                "price_minor": 150000,
                "currency": "EGP",
```

with:

```python
                "duration_value": 1,
                "duration_unit": "month",
                "freeze_days_allowed": 7,
                "price_minor": 150000,
                "currency": "EGP",
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
def seed_people(spec: dict) -> None:
```

with:

```python
# Plan 4: dates are days from the academy's today; weekdays 0 = Monday.
# One is paused and one is in its grace period (spec §7).
SUBSCRIPTIONS = {
    "demo": [
        {
            "student": "Yusuf Omar",
            "course": "Tajweed",
            "teacher": "Ustadh Bilal",
            "package": "Monthly, 2 a week",
            "starts": -10,
            "slots": [{"weekdays": [0, 2], "start_time": time(17, 0)}],
        },
        {
            "student": "Aisha Omar",
            "course": "Quran Memorisation",
            "teacher": "Ustadha Maryam",
            "package": "Monthly, 2 a week",
            "starts": -5,
            "slots": [{"weekdays": [1, 6], "start_time": time(16, 0)}],
            "pause": (-1, 3),
        },
        {
            "student": "Zaid Huda",
            "course": "Quran Memorisation",
            "teacher": "Ustadha Maryam",
            "package": "Two-week intensive",
            "starts": -17,
            "slots": [{"weekdays": [0, 1, 2, 3, 6], "start_time": time(18, 0)}],
        },
        {
            "student": "Yusuf Omar",
            "course": "Quran Memorisation",
            "teacher": "Ustadha Maryam",
            "package": "Two-week intensive",
            "starts": 0,
            "slots": [{"weekdays": [0, 1, 2, 3, 4], "start_time": time(15, 0)}],
        },
    ],
    "other": [
        {
            "student": "Layla Nabil",
            "course": "Arabic Grammar",
            "teacher": "Ustadh Kareem",
            "package": "Monthly",
            "starts": 0,
            "slots": [{"weekdays": [5], "start_time": time(10, 0)}],
        }
    ],
}


def seed_people(spec: dict) -> None:
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
class Command(BaseCommand):
```

with:

```python
def _person(role: str, full_name: str):
    return identity_services.people_queryset(role).filter(full_name=full_name).first()


def seed_subscriptions(specs: list[dict]) -> None:
    """Idempotent: an academy that already has subscriptions is left alone."""
    if scheduling_services.has_subscriptions():
        return
    today = scheduling_services.today()
    for spec in specs:
        student = _person("student", spec["student"])
        teacher = _person("teacher", spec["teacher"])
        course = catalogue_services.find_course(spec["course"])
        package = catalogue_services.find_package(spec["package"])
        if None in (student, teacher, course, package):
            continue  # a dev database whose seeded people were edited
        subscription = scheduling_services.create_subscription(
            student_id=student.id,
            course_id=course.id,
            teacher_id=teacher.id,
            package_id=package.id,
            starts_on=today + timedelta(days=spec["starts"]),
            slots=spec["slots"],
        )
        pause = spec.get("pause")
        # A dev database seeded before Plan 4 has no freeze days on its
        # packages: it simply gets no paused subscription.
        if pause and pause[1] - pause[0] + 1 <= subscription.freeze_days_allowed:
            first, last = pause
            scheduling_services.add_pause(
                subscription,
                from_date=today + timedelta(days=first),
                to_date=today + timedelta(days=last),
            )


class Command(BaseCommand):
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
                seed_people(PEOPLE[subdomain])
```

with:

```python
                seed_people(PEOPLE[subdomain])
                seed_subscriptions(SUBSCRIPTIONS[subdomain])
```

- [ ] **Step 4: Format, then run the tests**

Run (from `backend/`): `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`

Run (from `backend/`): `.venv/bin/pytest -q etqan/tenants/tests/test_seed_dev.py`
Expected: PASS.

- [ ] **Step 5: Full suite and linters**

Run (from `backend/`): `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
Expected: all pass, coverage ≥ 80%.

- [ ] **Step 6: Commit**

```bash
git -C backend add -A
git -C backend commit -m "feat(seed): demo subscriptions with slots, one paused and one in grace

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dashboard groundwork: shared helpers, rule-code errors, horizon and grace settings

**Files:**
- Create: `dashboard/src/lib/zoned-time.ts`, `dashboard/src/lib/zoned-time.test.ts`, `dashboard/src/lib/form-errors.test.ts`
- Modify: `dashboard/src/lib/api.ts` (`Paginated`), `dashboard/src/lib/form-errors.ts` (`errorText`, rule codes), `dashboard/src/features/identity/api.ts` + `api.test.ts` (`code`, nested lists)
- Modify: `dashboard/src/features/people/schemas.ts`, `dashboard/src/features/catalogue/schemas.ts` (re-export `Paginated` instead of a copy)
- Modify: `dashboard/src/features/academy/api.ts`, `dashboard/src/features/academy/AcademySettingsForm.tsx`, `dashboard/src/features/academy/AcademySettingsForm.test.tsx`
- Modify (the `AcademySettings` type grows, so their mocks must too): `dashboard/src/features/catalogue/PackageForm.test.tsx`, `dashboard/src/features/people/AdminsList.test.tsx`, `dashboard/src/features/people/ParentForm.test.tsx`, `dashboard/src/features/people/StudentForm.test.tsx`, `dashboard/src/features/people/TeacherForm.test.tsx`
- Modify: `dashboard/src/features/catalogue/CourseForm.tsx` + `CourseForm.test.tsx` (409 `catalogue.in_use` in words)
- Modify: `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`

**Interfaces:**
- Consumes: the backend's 409 body `{detail, code}` (Task 1) and the academy settings fields.
- Produces `@/lib/api`: `Paginated<T>`.
- Produces `parseApiError(error).code?: string`; nested list errors flatten to `slots.1.weekdays`.
- Produces `@/lib/form-errors`: `codeKey(code) -> "errors.<code>"`, `applyServerErrors` (a rule code becomes `root.server` as an i18n key — render it through `useFieldError`), `errorText(error, t) -> string` for toasts.
- Produces `@/lib/zoned-time`: `zonedInstant(date, time, timeZone) -> Date`, `wallTime(instant, timeZone, language) -> "HH:MM"`, `studentTime({date, time, academyZone, studentZone?, language}) -> string | null`, `formatDay(date, language)`, `todayIn(timeZone, now?) -> "YYYY-MM-DD"`, `weekdayName(weekday, language, width?)` (0 = Monday).
- Produces `AcademySettings.generation_horizon_days`, `.renewal_grace_days`; the form edits both.
- i18n: `errors.generic`, `errors.conflict`, `errors.catalogue.in_use`, `errors.scheduling.<code>` for every code in D11.

- [ ] **Step 1: Branch**

```bash
git -C dashboard switch -c feat/subscriptions-scheduling
```

- [ ] **Step 2: Write the failing tests**

Create `dashboard/src/lib/zoned-time.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
	formatDay,
	studentTime,
	todayIn,
	wallTime,
	weekdayName,
	zonedInstant,
} from "./zoned-time";

describe("zonedInstant", () => {
	it("reads a wall-clock time in a zone", () => {
		expect(zonedInstant("2026-06-01", "18:00", "UTC").toISOString()).toBe(
			"2026-06-01T18:00:00.000Z",
		);
		expect(
			zonedInstant("2026-06-01", "18:00", "Asia/Riyadh").toISOString(),
		).toBe("2026-06-01T15:00:00.000Z");
		expect(
			zonedInstant("2026-06-01", "03:00", "Asia/Kolkata").toISOString(),
		).toBe("2026-05-31T21:30:00.000Z");
	});

	it("follows daylight saving on each side of a change", () => {
		expect(
			zonedInstant("2026-01-05", "09:00", "America/New_York").toISOString(),
		).toBe("2026-01-05T14:00:00.000Z");
		expect(
			zonedInstant("2026-07-06", "09:00", "America/New_York").toISOString(),
		).toBe("2026-07-06T13:00:00.000Z");
	});
});

describe("studentTime", () => {
	const base = { date: "2026-06-01", time: "18:00", language: "en" };

	it("shows the student's clock when it differs", () => {
		expect(
			studentTime({ ...base, academyZone: "UTC", studentZone: "Asia/Riyadh" }),
		).toBe("21:00");
		expect(
			studentTime({
				...base,
				academyZone: "Asia/Riyadh",
				studentZone: "America/New_York",
			}),
		).toBe("11:00");
		expect(wallTime(new Date("2026-06-01T00:00:00Z"), "UTC", "en")).toBe(
			"00:00",
		);
	});

	it("is null for the same zone, the same clock, or no zone", () => {
		expect(
			studentTime({ ...base, academyZone: "UTC", studentZone: "UTC" }),
		).toBeNull();
		expect(
			studentTime({
				...base,
				academyZone: "Asia/Riyadh",
				studentZone: "Asia/Baghdad",
			}),
		).toBeNull();
		expect(studentTime({ ...base, academyZone: "UTC" })).toBeNull();
	});
});

describe("formatDay and todayIn", () => {
	it("formats a calendar date without shifting it", () => {
		expect(formatDay("2026-06-01", "en")).toBe("Jun 1, 2026");
	});

	it("reads today on the zone's calendar", () => {
		const late = new Date("2026-06-01T22:30:00Z");
		expect(todayIn("UTC", late)).toBe("2026-06-01");
		expect(todayIn("Asia/Riyadh", late)).toBe("2026-06-02");
	});
});

describe("weekdayName", () => {
	it("numbers the week from Monday", () => {
		expect(weekdayName(0, "en")).toBe("Mon");
		expect(weekdayName(6, "en", "long")).toBe("Sunday");
	});
});
```

Create `dashboard/src/lib/form-errors.test.ts`:

```ts
import { AxiosError } from "axios";
import i18n from "i18next";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { applyServerErrors, errorText } from "./form-errors";

function httpError(status: number, data: unknown) {
	return new AxiosError("x", String(status), undefined, undefined, {
		status,
		data,
	} as never);
}

const t = i18n.t.bind(i18n);

describe("errorText", () => {
	it("translates a known rule code", () => {
		const error = httpError(409, {
			detail: "This subscription was already renewed.",
			code: "scheduling.already_renewed",
		});
		expect(errorText(error, t)).toBe(
			"This subscription has already been renewed.",
		);
	});

	it("falls back to the server message for an unknown code", () => {
		const error = httpError(409, { detail: "Server words.", code: "x.y" });
		expect(errorText(error, t)).toBe("Server words.");
	});

	it("uses the first field error, then a generic line", () => {
		expect(errorText(httpError(400, { to_date: ["Too early."] }), t)).toBe(
			"Too early.",
		);
		expect(errorText(new Error("offline"), t)).toBe(
			"Something went wrong. Please try again.",
		);
	});
});

describe("applyServerErrors", () => {
	it("sets fields, and a rule code as the form-level i18n key", () => {
		const setError = vi.fn();
		applyServerErrors(
			httpError(409, { detail: "Nope.", code: "scheduling.pause_overlaps" }),
			setError,
		);
		expect(setError).toHaveBeenCalledWith("root.server", {
			message: "errors.scheduling.pause_overlaps",
		});
		setError.mockClear();
		applyServerErrors(httpError(400, { from_date: ["Too early."] }), setError);
		expect(setError).toHaveBeenCalledWith("from_date", {
			message: "Too early.",
		});
		expect(setError).toHaveBeenCalledTimes(1);
	});
});
```

In `dashboard/src/features/identity/api.test.ts`, replace:

```ts
describe("identityApi.verifyEmail", () => {
```

with:

```ts
describe("parseApiError for rule conflicts and nested lists", () => {
	it("keeps a 409's rule code apart from its message", () => {
		const error = new AxiosError("Conflict", "409", undefined, undefined, {
			status: 409,
			data: {
				detail: "This subscription was already renewed.",
				code: "scheduling.already_renewed",
			},
		} as never);
		const parsed = parseApiError(error);
		expect(parsed.code).toBe("scheduling.already_renewed");
		expect(parsed.message).toBe("This subscription was already renewed.");
		expect(parsed.fieldErrors).toEqual({});
	});

	it("indexes a nested list's errors by item", () => {
		const error = new AxiosError("Bad", "400", undefined, undefined, {
			status: 400,
			data: { slots: [{}, { weekdays: ["Choose a day."] }] },
		} as never);
		expect(parseApiError(error).fieldErrors).toEqual({
			"slots.1.weekdays": "Choose a day.",
		});
	});
});

describe("identityApi.verifyEmail", () => {
```

Replace the whole of `dashboard/src/features/academy/AcademySettingsForm.test.tsx` with:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { Toaster } from "@/ui";
import { AcademySettingsForm } from "./AcademySettingsForm";
import { academyApi } from "./api";

vi.mock("./api", () => ({ academyApi: { get: vi.fn(), update: vi.fn() } }));

function renderForm() {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	render(
		<QueryClientProvider client={client}>
			<AcademySettingsForm />
			<Toaster />
		</QueryClientProvider>,
	);
}

describe("AcademySettingsForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({
			timezone: "Africa/Cairo",
			default_currency: "EGP",
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
	});

	it("loads and saves timezone, currency and language", async () => {
		vi.mocked(academyApi.update).mockResolvedValue({
			timezone: "Asia/Riyadh",
			default_currency: "SAR",
			default_language: "en",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
		const user = userEvent.setup();
		renderForm();
		expect(await screen.findByDisplayValue("Africa/Cairo")).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText("Time zone"), "Asia/Riyadh");
		await user.selectOptions(screen.getByLabelText("Default currency"), "SAR");
		await user.selectOptions(screen.getByLabelText("Default language"), "en");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(academyApi.update).toHaveBeenCalledWith({
				timezone: "Asia/Riyadh",
				default_currency: "SAR",
				default_language: "en",
				generation_horizon_days: 14,
				renewal_grace_days: 7,
			}),
		);
		expect(await screen.findByText("Saved.")).toBeInTheDocument();
	});

	it("saves the horizon and grace days and checks their range", async () => {
		vi.mocked(academyApi.update).mockImplementation(async (body) => ({
			timezone: "Africa/Cairo",
			default_currency: "EGP",
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
			...body,
		}));
		const user = userEvent.setup();
		renderForm();
		const horizon = await screen.findByLabelText(
			"Generate sessions ahead (days)",
		);
		expect(horizon).toHaveValue(14);
		await user.clear(horizon);
		await user.type(horizon, "61");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText("Choose 1 to 60 days.")).toBeInTheDocument();
		expect(academyApi.update).not.toHaveBeenCalled();
		await user.clear(horizon);
		await user.type(horizon, "30");
		await user.clear(screen.getByLabelText("Renewal grace (days)"));
		await user.type(screen.getByLabelText("Renewal grace (days)"), "0");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(academyApi.update).toHaveBeenCalledWith(
				expect.objectContaining({
					generation_horizon_days: 30,
					renewal_grace_days: 0,
				}),
			),
		);
	});
});
```

In `dashboard/src/features/catalogue/CourseForm.test.tsx`, replace:

```tsx
	it("shows a translated not-found state for a 404", async () => {
```

with:

```tsx
	it("explains why a course with subscriptions is not deleted", async () => {
		vi.mocked(catalogueApi.get).mockResolvedValue({
			id: 4,
			name_ar: "تجويد",
			name_en: "Tajweed",
			description_ar: "",
			description_en: "",
			language: "ar",
			is_active: true,
			teacher_ids: [],
		});
		vi.mocked(catalogueApi.remove).mockRejectedValue(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { detail: "In use.", code: "catalogue.in_use" },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<CourseForm courseId="4" />);
		await user.click(await screen.findByRole("button", { name: "Delete" }));
		await user.click(
			await screen.findByRole("button", { name: "Delete course" }),
		);
		expect(
			await screen.findByText(
				"This has subscriptions, so it can't be deleted. Deactivate it instead.",
				{ exact: true },
			),
		).toBeInTheDocument();
	});

	it("shows a translated not-found state for a 404", async () => {
```

- [ ] **Step 3: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/lib src/features/identity src/features/academy src/features/catalogue`
Expected: FAIL — `zoned-time` and `errorText` don't exist, `parsed.code` is undefined, the form has no horizon field, and the course delete shows the generic error.

- [ ] **Step 4: Implement the shared helpers**

In `dashboard/src/lib/api.ts`, replace:

```ts
export type QueryParams = Record<string, string | number | undefined>;
```

with:

```ts
export type QueryParams = Record<string, string | number | undefined>;

/** One page of a DRF list (`StandardPagination`: 25 rows unless `page_size`). */
export interface Paginated<T> {
	count: number;
	next: string | null;
	previous: string | null;
	results: T[];
}
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
export interface Paginated<T> {
	count: number;
	next: string | null;
	previous: string | null;
	results: T[];
}
```

with:

```ts
export type { Paginated } from "@/lib/api";
```

In `dashboard/src/features/catalogue/schemas.ts`, replace:

```ts
export interface Paginated<T> {
	count: number;
	next: string | null;
	previous: string | null;
	results: T[];
}
```

with:

```ts
export type { Paginated } from "@/lib/api";
```

In `dashboard/src/features/identity/api.ts`, replace:

```ts
export interface ParsedApiError {
	fieldErrors: Record<string, string>;
	message?: string;
	throttled: boolean;
}

// Recursively flatten a DRF error body into dotted field paths, e.g.
// {"user": {"email": ["Taken."]}} -> fieldErrors["user.email"] = "Taken.".
function collect(path: string, value: unknown, out: ParsedApiError): void {
	if (value && typeof value === "object" && !Array.isArray(value)) {
		for (const [key, nested] of Object.entries(value)) {
			collect(path ? `${path}.${key}` : key, nested, out);
		}
		return;
	}
	const msg = Array.isArray(value) ? String(value[0]) : String(value);
	if (path === "non_field_errors" || path === "detail") out.message = msg;
	else out.fieldErrors[path] = msg;
}
```

with:

```ts
export interface ParsedApiError {
	fieldErrors: Record<string, string>;
	message?: string;
	/** The rule a 409 names, e.g. `scheduling.already_renewed` (plan 4 D10). */
	code?: string;
	throttled: boolean;
}

const isObject = (value: unknown): value is Record<string, unknown> =>
	Boolean(value) && typeof value === "object" && !Array.isArray(value);

// Recursively flatten a DRF error body into dotted field paths, e.g.
// {"user": {"email": ["Taken."]}} -> fieldErrors["user.email"] = "Taken.".
// A list of objects is a nested list serializer, one entry per item:
// {"slots": [{}, {"weekdays": ["Bad."]}]} -> fieldErrors["slots.1.weekdays"].
function collect(path: string, value: unknown, out: ParsedApiError): void {
	if (isObject(value)) {
		for (const [key, nested] of Object.entries(value)) {
			collect(path ? `${path}.${key}` : key, nested, out);
		}
		return;
	}
	if (Array.isArray(value) && value.some(isObject)) {
		value.forEach((item, index) => {
			collect(`${path}.${index}`, item, out);
		});
		return;
	}
	const msg = Array.isArray(value) ? String(value[0]) : String(value);
	if (path === "code") out.code = msg;
	else if (path === "non_field_errors" || path === "detail") out.message = msg;
	else out.fieldErrors[path] = msg;
}
```

Replace the whole of `dashboard/src/lib/form-errors.ts` with:

```ts
import type { TFunction } from "i18next";
import type { FieldValues, Path, UseFormSetError } from "react-hook-form";
import { type ParsedApiError, parseApiError } from "@/features/identity/api";

/** The i18n key for a 409's rule code: `errors.<code>` (plan 4 D10). */
export const codeKey = (code: string) => `errors.${code}`;

/** Put nested DRF errors (`user.email`, `profile.gender`) on their fields. A
 * 409's rule code becomes the form-level error as an i18n key, so render
 * `errors.root.server.message` through `useFieldError`. */
export function applyServerErrors<T extends FieldValues>(
	error: unknown,
	setError: UseFormSetError<T>,
): ParsedApiError {
	const parsed = parseApiError(error);
	for (const [field, message] of Object.entries(parsed.fieldErrors)) {
		setError(field as Path<T>, { message });
	}
	const root = parsed.code ? codeKey(parsed.code) : parsed.message;
	if (root) setError("root.server", { message: root });
	return parsed;
}

/** A failed action as one sentence for a toast: the translated rule code of a
 * 409, else the server's message, else its first field error, else a generic
 * line. */
export function errorText(error: unknown, t: TFunction): string {
	const parsed = parseApiError(error);
	const translated = parsed.code
		? t(codeKey(parsed.code), { defaultValue: "" })
		: "";
	return (
		translated ||
		parsed.message ||
		Object.values(parsed.fieldErrors)[0] ||
		t("errors.generic")
	);
}
```

Create `dashboard/src/lib/zoned-time.ts`:

```ts
/**
 * Wall-clock arithmetic across time zones with nothing but `Intl`
 * (plan 4 D14). Slot times are the academy's wall clock (P4-6); the student
 * sees their own.
 */

function offsetMinutes(instant: Date, timeZone: string): number {
	const parts = new Intl.DateTimeFormat("en-US", {
		timeZone,
		hourCycle: "h23",
		year: "numeric",
		month: "2-digit",
		day: "2-digit",
		hour: "2-digit",
		minute: "2-digit",
		second: "2-digit",
	}).formatToParts(instant);
	const part = (type: Intl.DateTimeFormatPartTypes) =>
		Number(parts.find((p) => p.type === type)?.value);
	const wall = Date.UTC(
		part("year"),
		part("month") - 1,
		part("day"),
		part("hour"),
		part("minute"),
		part("second"),
	);
	return Math.round((wall - instant.getTime()) / 60_000);
}

/** The instant when `timeZone`'s clock reads `time` ("HH:MM") on `date`
 * ("YYYY-MM-DD"). */
export function zonedInstant(
	date: string,
	time: string,
	timeZone: string,
): Date {
	const [year, month, day] = date.split("-").map(Number);
	const [hour, minute] = time.split(":").map(Number);
	const wall = Date.UTC(year, month - 1, day, hour, minute);
	const guess = wall - offsetMinutes(new Date(wall), timeZone) * 60_000;
	// Second pass: the offset at the guess wins across a clock change.
	return new Date(wall - offsetMinutes(new Date(guess), timeZone) * 60_000);
}

/** `instant` on `timeZone`'s clock, as 24-hour "HH:MM" in `language`. */
export function wallTime(
	instant: Date,
	timeZone: string,
	language: string,
): string {
	return new Intl.DateTimeFormat(language, {
		timeZone,
		hour: "2-digit",
		minute: "2-digit",
		hourCycle: "h23",
	}).format(instant);
}

/** The student's time for a slot, or null when their clock reads the same. */
export function studentTime({
	date,
	time,
	academyZone,
	studentZone,
	language,
}: {
	date: string;
	time: string;
	academyZone: string;
	studentZone?: string;
	language: string;
}): string | null {
	if (!studentZone || studentZone === academyZone || !time) return null;
	const instant = zonedInstant(date, time, academyZone);
	const theirs = wallTime(instant, studentZone, language);
	return theirs === wallTime(instant, academyZone, language) ? null : theirs;
}

/** A calendar date ("YYYY-MM-DD") for people, e.g. "Jun 1, 2026" in English. */
export function formatDay(date: string, language: string): string {
	return new Intl.DateTimeFormat(language, {
		dateStyle: "medium",
		timeZone: "UTC",
	}).format(new Date(`${date}T00:00:00Z`));
}

/** Today's date ("YYYY-MM-DD") on `timeZone`'s calendar. */
export function todayIn(timeZone: string, now: Date = new Date()): string {
	return new Intl.DateTimeFormat("en-CA", {
		timeZone,
		year: "numeric",
		month: "2-digit",
		day: "2-digit",
	}).format(now);
}

/** A weekday's name, 0 = Monday … 6 = Sunday (the API's numbering). */
export function weekdayName(
	weekday: number,
	language: string,
	width: "short" | "long" = "short",
): string {
	// 1 June 2026 was a Monday.
	return new Intl.DateTimeFormat(language, {
		weekday: width,
		timeZone: "UTC",
	}).format(new Date(Date.UTC(2026, 5, 1 + weekday)));
}
```

- [ ] **Step 5: Horizon and grace in Settings → Academy**

In `dashboard/src/features/academy/api.ts`, replace:

```ts
	default_language: Language;
	updated_at?: string;
```

with:

```ts
	default_language: Language;
	generation_horizon_days: number;
	renewal_grace_days: number;
	updated_at?: string;
```

Replace the whole of `dashboard/src/features/academy/AcademySettingsForm.tsx` with:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { CURRENCIES } from "@/lib/currencies";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { timezoneOptions } from "@/lib/timezones";
import { Field, Input, Select, Spinner, SubmitButton, toast } from "@/ui";
import { useAcademySettings, useUpdateAcademySettings } from "./queries";

const days = (min: number, max: number, message: string) =>
	z.number({ error: message }).int(message).min(min, message).max(max, message);

const schema = z.object({
	timezone: z.string().min(1),
	default_currency: z.string().regex(/^[A-Z]{3}$/),
	default_language: z.enum(["ar", "en"]),
	generation_horizon_days: days(1, 60, "academySettings.errors.horizonRange"),
	renewal_grace_days: days(0, 60, "academySettings.errors.graceRange"),
});
type Values = z.infer<typeof schema>;

export function AcademySettingsForm() {
	const { t } = useTranslation();
	const { data } = useAcademySettings();
	const update = useUpdateAcademySettings();
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<Values>({
		resolver: zodResolver(schema),
		values: data
			? {
					timezone: data.timezone,
					default_currency: data.default_currency,
					default_language: data.default_language,
					generation_horizon_days: data.generation_horizon_days,
					renewal_grace_days: data.renewal_grace_days,
				}
			: undefined,
	});
	const fieldError = useFieldError();

	async function onSubmit(values: Values) {
		try {
			await update.mutateAsync(values);
			toast({ description: t("people.saved"), variant: "success" });
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	if (!data) return <Spinner />;
	const currencies = CURRENCIES.includes(
		data.default_currency as (typeof CURRENCIES)[number],
	)
		? [...CURRENCIES]
		: [data.default_currency, ...CURRENCIES];

	return (
		<form
			onSubmit={handleSubmit(onSubmit)}
			className="flex max-w-md flex-col gap-4"
			noValidate
		>
			<Field
				id="timezone"
				label={t("academySettings.timezone")}
				error={errors.timezone?.message}
			>
				<Select dir="ltr" {...register("timezone")}>
					{timezoneOptions(data.timezone).map((zone) => (
						<option key={zone} value={zone}>
							{zone}
						</option>
					))}
				</Select>
			</Field>
			<Field
				id="default_currency"
				label={t("academySettings.currency")}
				error={errors.default_currency?.message}
			>
				<Select dir="ltr" {...register("default_currency")}>
					{currencies.map((c) => (
						<option key={c} value={c}>
							{c}
						</option>
					))}
				</Select>
			</Field>
			<Field
				id="default_language"
				label={t("academySettings.language")}
				error={errors.default_language?.message}
			>
				<Select {...register("default_language")}>
					<option value="ar">العربية</option>
					<option value="en">English</option>
				</Select>
			</Field>
			<p className="text-sm text-muted-foreground">
				{t("academySettings.hint")}
			</p>
			<Field
				id="generation_horizon_days"
				label={t("academySettings.horizon")}
				error={fieldError(errors.generation_horizon_days?.message)}
			>
				<Input
					type="number"
					min={1}
					max={60}
					{...register("generation_horizon_days", { valueAsNumber: true })}
				/>
			</Field>
			<Field
				id="renewal_grace_days"
				label={t("academySettings.grace")}
				error={fieldError(errors.renewal_grace_days?.message)}
			>
				<Input
					type="number"
					min={0}
					max={60}
					{...register("renewal_grace_days", { valueAsNumber: true })}
				/>
			</Field>
			<p className="text-sm text-muted-foreground">
				{t("academySettings.schedulingHint")}
			</p>
			<SubmitButton pending={isSubmitting} className="self-start">
				{t("people.save")}
			</SubmitButton>
		</form>
	);
}
```

In `dashboard/src/features/catalogue/PackageForm.test.tsx` (the `academyApi.get` mock), replace:

```tsx
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "ar",
		});
```

with:

```tsx
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
```

In `dashboard/src/features/people/AdminsList.test.tsx` (the `academyApi.get` mock), replace:

```tsx
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "ar",
		});
```

with:

```tsx
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
```

In `dashboard/src/features/people/ParentForm.test.tsx` (the `academyApi.get` mock), replace:

```tsx
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "ar",
		});
```

with:

```tsx
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
```

In `dashboard/src/features/people/StudentForm.test.tsx` (the `academyApi.get` mock), replace:

```tsx
			timezone: "Africa/Cairo",
			default_currency: "EGP",
			default_language: "ar",
		});
```

with:

```tsx
			timezone: "Africa/Cairo",
			default_currency: "EGP",
			default_language: "ar",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
```

In `dashboard/src/features/people/TeacherForm.test.tsx` (the `academyApi.get` mock), replace:

```tsx
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "en",
		});
```

with:

```tsx
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "en",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
```

- [ ] **Step 6: Say why a course with subscriptions is not deleted**

In `dashboard/src/features/catalogue/CourseForm.tsx`, replace:

```tsx
import { applyServerErrors } from "@/lib/form-errors";
```

with:

```tsx
import { applyServerErrors, errorText } from "@/lib/form-errors";
```

In `dashboard/src/features/catalogue/CourseForm.tsx`, replace:

```tsx
												onError: () =>
													toast({
														description: t("people.genericError"),
```

with:

```tsx
												onError: (error) =>
													toast({
														description: errorText(error, t),
```

- [ ] **Step 7: Translations**

Merge these keys into `dashboard/src/locales/en/common.json` (nested objects merge into the existing ones; keep the file's tab indentation):

```json
{
	"errors": {
		"generic": "Something went wrong. Please try again.",
		"conflict": "Someone else changed this. Reload and try again.",
		"catalogue": {
			"in_use": "This has subscriptions, so it can't be deleted. Deactivate it instead."
		},
		"scheduling": {
			"not_allowed_in_status": "That isn't possible in the subscription's current status.",
			"already_renewed": "This subscription has already been renewed.",
			"freeze_days_exceeded": "That is more than the freeze days left.",
			"pause_overlaps": "This pause overlaps another one.",
			"has_marked_sessions": "Attendance is already marked on this subscription.",
			"pause_not_current": "Only a pause that covers today can be ended early.",
			"pause_started": "Only a pause that hasn't started can be deleted.",
			"slot_has_sessions": "This slot has sessions. Deactivate it instead."
		}
	},
	"academySettings": {
		"horizon": "Generate sessions ahead (days)",
		"grace": "Renewal grace (days)",
		"schedulingHint": "Sessions are created this many days ahead. After its end date a subscription keeps generating sessions for the grace days, then expires.",
		"errors": {
			"horizonRange": "Choose 1 to 60 days.",
			"graceRange": "Choose 0 to 60 days."
		}
	}
}
```

and these into `dashboard/src/locales/ar/common.json`:

```json
{
	"errors": {
		"generic": "حدث خطأ ما. حاول مرة أخرى.",
		"conflict": "غيّر شخص آخر هذا. أعد التحميل وحاول مرة أخرى.",
		"catalogue": {
			"in_use": "لهذا العنصر اشتراكات، فلا يمكن حذفه. عطّله بدلًا من ذلك."
		},
		"scheduling": {
			"not_allowed_in_status": "لا يمكن ذلك في حالة الاشتراك الحالية.",
			"already_renewed": "جُدّد هذا الاشتراك من قبل.",
			"freeze_days_exceeded": "هذا أكثر من أيام التجميد المتبقية.",
			"pause_overlaps": "يتداخل هذا الإيقاف مع إيقاف آخر.",
			"has_marked_sessions": "سُجّل الحضور بالفعل في هذا الاشتراك.",
			"pause_not_current": "لا يمكن إنهاء إلا الإيقاف الجاري اليوم.",
			"pause_started": "لا يمكن حذف إلا إيقاف لم يبدأ بعد.",
			"slot_has_sessions": "لهذا الموعد حصص. عطّله بدلًا من ذلك."
		}
	},
	"academySettings": {
		"horizon": "توليد الحصص مسبقًا (أيام)",
		"grace": "مهلة التجديد (أيام)",
		"schedulingHint": "تُنشأ الحصص لهذا العدد من الأيام القادمة. بعد تاريخ انتهائه يستمر الاشتراك في توليد الحصص طوال أيام المهلة، ثم ينتهي.",
		"errors": {
			"horizonRange": "اختر من 1 إلى 60 يومًا.",
			"graceRange": "اختر من 0 إلى 60 يومًا."
		}
	}
}
```

- [ ] **Step 8: Format, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src`

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/lib src/features/identity src/features/academy src/features/catalogue src/features/people`
Expected: PASS.

- [ ] **Step 9: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: tsc clean, biome + colour check clean, coverage above the gates, build OK.

- [ ] **Step 10: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): rule-code errors, time-zone helpers, horizon and grace settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Dashboard: scheduling data layer, Scheduling nav group, subscriptions list and summary

**Files:**
- Create: `dashboard/src/features/scheduling/schemas.ts`, `dashboard/src/features/scheduling/api.ts`, `dashboard/src/features/scheduling/api.test.ts`, `dashboard/src/features/scheduling/queries.ts`, `dashboard/src/features/scheduling/bits.tsx`, `dashboard/src/features/scheduling/SubscriptionsList.tsx`, `dashboard/src/features/scheduling/SubscriptionsList.test.tsx`, `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx`, `dashboard/src/features/scheduling/index.ts`, `dashboard/src/test/scheduling-fixtures.ts`
- Create: `dashboard/src/routes/_authed/scheduling.tsx`, `dashboard/src/routes/_authed/scheduling.index.tsx`, `dashboard/src/routes/_authed/scheduling.subscriptions.index.tsx`, `dashboard/src/routes/_authed/scheduling.subscriptions.$subscriptionId.tsx`
- Modify: `dashboard/src/features/shell/nav.ts`, `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/features/shell/AppSidebar.test.tsx`, locales

**Interfaces:**
- Consumes: Task 10 helpers; `usePeople` (`@/features/people`), `useCatalogue`, `Course` (`@/features/catalogue`); the Task 7 payloads.
- Produces types `Subscription`, `SubscriptionDetail`, `Slot`, `Pause`, `Session`, `GenerationResult`, `TodayRow`, `TodayBoard` and request bodies `SubscriptionBody`, `SubscriptionPatch`, `RenewBody`, `PauseBody`, `SlotBody`, `SlotPatch`, `GenerateBody`; `SUBSCRIPTION_STATUSES`, `WEEKDAYS`, `isLive(status)` (active or paused: the statuses that still accept changes).
- Produces `schedulingApi` (`list, get, create, update, remove, renew, cancel, addPause, endPause, deletePause, addSlots, updateSlot, deleteSlot, sessions, generate, today`) and `subscriptionsCsvUrl(params)`.
- Produces hooks `schedulingKey`, `useSubscriptions(params)`, `useSubscription(id?)`, `useSessions(id, params)`, `useToday()`, `useSchedulingMutation(write)` (one argument only; invalidates every scheduling query).
- Produces components `SubscriptionStatusChip`, `SubscriptionProgress`, `useLocalName()` (bits), `SubscriptionsList`, `SubscriptionDetail({subscriptionId})`; test fixtures `subscriptionRow`, `subscriptionDetail`, `sessionRow`, `todayRow`, `page`.
- Nav: group `scheduling` first after Home (D16).

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/test/scheduling-fixtures.ts`:

```ts
import type {
	Session,
	Subscription,
	SubscriptionDetail,
	TodayRow,
} from "@/features/scheduling/schemas";

/** API-shaped scheduling rows for feature tests. */
export function subscriptionRow(
	overrides: Partial<Subscription> = {},
): Subscription {
	return {
		id: 7,
		status: "active",
		student: { id: 11, full_name: "Yusuf", timezone: "Asia/Riyadh" },
		teacher: { id: 21, full_name: "Bilal" },
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		package: { id: 5, name_ar: "شهري", name_en: "Monthly" },
		starts_on: "2026-06-01",
		term_ends_on: "2026-06-30",
		ends_on: "2026-06-30",
		grace_ends_on: "2026-07-07",
		in_grace: false,
		sessions_total: 8,
		sessions_used: 3,
		carried_over_sessions: 0,
		sessions_remaining: 5,
		extra_sessions: 0,
		progress: 0.375,
		price_minor: 150000,
		currency: "EGP",
		renewed_from: null,
		renewal: null,
		...overrides,
	};
}

export function subscriptionDetail(
	overrides: Partial<SubscriptionDetail> = {},
): SubscriptionDetail {
	return {
		...subscriptionRow(),
		duration_value: 1,
		duration_unit: "month",
		session_minutes: 45,
		freeze_days_allowed: 10,
		paused_days: 0,
		freeze_days_left: 10,
		notes: "",
		slots: [
			{
				id: 31,
				weekday: 0,
				start_time: "18:00",
				minutes: 45,
				meeting_url: "",
				is_active: true,
				has_sessions: true,
			},
		],
		pauses: [],
		...overrides,
	};
}

export function sessionRow(overrides: Partial<Session> = {}): Session {
	return {
		id: 41,
		subscription_id: 7,
		slot_id: 31,
		occurs_on: "2026-06-01",
		starts_at: "2026-06-01T18:00:00Z",
		minutes: 45,
		status: "scheduled",
		student_attendance: "not_set",
		teacher_attendance: "not_set",
		meeting_url: "https://meet.test/bilal",
		generated: true,
		student: { id: 11, full_name: "Yusuf" },
		teacher: { id: 21, full_name: "Bilal" },
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		...overrides,
	};
}

export function todayRow(overrides: Partial<TodayRow> = {}): TodayRow {
	return {
		slot_id: 31,
		subscription_id: 7,
		session_id: 41,
		date: "2026-06-01",
		start_time: "18:00",
		starts_at: "2026-06-01T18:00:00Z",
		minutes: 45,
		state: "generated",
		student: { id: 11, full_name: "Yusuf", timezone: "Asia/Riyadh" },
		teacher: { id: 21, full_name: "Bilal" },
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		sessions_total: 8,
		sessions_used: 3,
		carried_over_sessions: 0,
		extra_sessions: 0,
		progress: 0.375,
		...overrides,
	};
}

export function page<T>(results: T[]) {
	return { count: results.length, next: null, previous: null, results };
}
```

Create `dashboard/src/features/scheduling/api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { schedulingApi, subscriptionsCsvUrl } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
	const ok = () => Promise.resolve({ data: { id: 1 } });
	return {
		...actual,
		api: {
			defaults: { baseURL: "/api/v1/" },
			get: vi.fn(ok),
			post: vi.fn(ok),
			patch: vi.fn(ok),
			delete: vi.fn(ok),
		},
	};
});

describe("schedulingApi", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads lists, details, sessions and today with clean params", async () => {
		await schedulingApi.list({ status: "paused", q: "", page: 2 });
		expect(api.get).toHaveBeenCalledWith("subscriptions/", {
			params: { status: "paused", page: "2" },
		});
		await schedulingApi.get(7);
		expect(api.get).toHaveBeenLastCalledWith("subscriptions/7/");
		await schedulingApi.sessions(7, { when: "past", page: 1 });
		expect(api.get).toHaveBeenLastCalledWith("subscriptions/7/sessions/", {
			params: { when: "past", page: "1" },
		});
		await schedulingApi.today();
		expect(api.get).toHaveBeenLastCalledWith("schedule/today/");
	});

	it("writes to the spec §5 routes", async () => {
		await schedulingApi.create({
			student: 1,
			course: 2,
			teacher: 3,
			package: 4,
			starts_on: "2026-06-01",
		});
		expect(api.post).toHaveBeenLastCalledWith(
			"subscriptions/",
			expect.objectContaining({ student: 1 }),
		);
		await schedulingApi.update(7, { notes: "x" });
		expect(api.patch).toHaveBeenLastCalledWith("subscriptions/7/", {
			notes: "x",
		});
		await schedulingApi.renew(7, {});
		expect(api.post).toHaveBeenLastCalledWith("subscriptions/7/renew/", {});
		await schedulingApi.cancel(7);
		expect(api.post).toHaveBeenLastCalledWith("subscriptions/7/cancel/");
		await schedulingApi.addPause(7, {
			from_date: "2026-06-01",
			to_date: "2026-06-02",
		});
		expect(api.post).toHaveBeenLastCalledWith(
			"subscriptions/7/pauses/",
			expect.anything(),
		);
		await schedulingApi.endPause(5);
		expect(api.post).toHaveBeenLastCalledWith("pauses/5/end/");
		await schedulingApi.addSlots(7, { weekdays: [0], start_time: "18:00" });
		expect(api.post).toHaveBeenLastCalledWith(
			"subscriptions/7/slots/",
			expect.anything(),
		);
		await schedulingApi.updateSlot(9, { is_active: false });
		expect(api.patch).toHaveBeenLastCalledWith("slots/9/", {
			is_active: false,
		});
		await schedulingApi.generate({ from: "2026-06-01", to: "2026-06-02" });
		expect(api.post).toHaveBeenLastCalledWith("schedule/generate/", {
			from: "2026-06-01",
			to: "2026-06-02",
		});
		await schedulingApi.remove(7);
		await schedulingApi.deletePause(5);
		await schedulingApi.deleteSlot(9);
		expect(vi.mocked(api.delete).mock.calls).toEqual([
			["subscriptions/7/"],
			["pauses/5/"],
			["slots/9/"],
		]);
	});
});

describe("subscriptionsCsvUrl", () => {
	it("keeps the filters and drops the page", () => {
		expect(subscriptionsCsvUrl({ status: "active", page: 3 })).toBe(
			"/api/v1/subscriptions/?status=active&format=csv",
		);
	});
});
```

Create `dashboard/src/features/scheduling/SubscriptionsList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { page, subscriptionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SubscriptionsList } from "./SubscriptionsList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, list: vi.fn() },
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, list: vi.fn() },
	};
});

function lastParams() {
	return vi.mocked(schedulingApi.list).mock.calls.at(-1)?.[0];
}

describe("SubscriptionsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 21, user: { full_name: "Bilal" } }]) as never,
		);
		vi.mocked(catalogueApi.list).mockResolvedValue(
			page([{ id: 3, name_ar: "تجويد", name_en: "Tajweed" }]) as never,
		);
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([
				subscriptionRow(),
				subscriptionRow({
					id: 8,
					student: { id: 12, full_name: "Aisha", timezone: "UTC" },
					sessions_used: 8,
					carried_over_sessions: 2,
					sessions_remaining: -2,
					extra_sessions: 2,
					in_grace: true,
				}),
			]),
		);
	});

	it("shows progress, extras, status and the grace end", async () => {
		renderWithRouter(<SubscriptionsList />, {
			extraPaths: ["/scheduling/subscriptions/$subscriptionId"],
		});
		const table = await screen.findByRole("table");
		const yusuf = within(table).getByRole("row", { name: /Yusuf/ });
		expect(within(yusuf).getByText("3 of 8 sessions")).toBeInTheDocument();
		expect(within(yusuf).getByText("Jun 30, 2026")).toBeInTheDocument();
		expect(within(yusuf).getByText("Active")).toBeInTheDocument();
		expect(within(yusuf).queryByText(/extra/)).toBeNull();
		const aisha = within(table).getByRole("row", { name: /Aisha/ });
		expect(within(aisha).getByText("10 of 8 sessions")).toBeInTheDocument();
		expect(within(aisha).getByText("+2 extra")).toBeInTheDocument();
		expect(
			within(aisha).getByText("In grace until Jul 7, 2026"),
		).toBeInTheDocument();
		expect(within(yusuf).getByRole("link", { name: "Yusuf" })).toHaveAttribute(
			"href",
			"/scheduling/subscriptions/7",
		);
	});

	it("filters by status, teacher, course and name, and exports them", async () => {
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionsList />);
		await screen.findByRole("table");
		await user.click(screen.getByRole("tab", { name: "Paused" }));
		await waitFor(() =>
			expect(lastParams()).toMatchObject({ status: "paused", page: 1 }),
		);
		await user.selectOptions(screen.getByLabelText("Teacher"), "21");
		await user.selectOptions(screen.getByLabelText("Course"), "3");
		await user.type(screen.getByRole("searchbox"), "yu");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				status: "paused",
				teacher: "21",
				course: "3",
				q: "yu",
			}),
		);
		const csv = screen.getByRole("link", { name: "Export CSV" });
		expect(csv.getAttribute("href")).toContain("teacher=21");
		expect(csv.getAttribute("href")).toContain("format=csv");
		await user.click(screen.getByRole("tab", { name: "All" }));
		await waitFor(() => expect(lastParams()?.status).toBeUndefined());
	});

	it("shows an empty state and a load error", async () => {
		vi.mocked(schedulingApi.list).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<SubscriptionsList />);
		expect(
			await screen.findByText("No subscriptions yet."),
		).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.list).mockRejectedValueOnce(new Error("offline"));
		renderWithRouter(<SubscriptionsList />);
		expect(
			await screen.findByText("Couldn't load subscriptions."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { subscriptionDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SubscriptionDetail } from "./SubscriptionDetail";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, get: vi.fn() },
	};
});
describe("SubscriptionDetail", () => {
	beforeEach(() => vi.clearAllMocks());

	it("summarises dates, sessions and money", async () => {
		vi.mocked(schedulingApi.get).mockResolvedValue(
			subscriptionDetail({
				ends_on: "2026-07-03",
				paused_days: 3,
				carried_over_sessions: 2,
				sessions_remaining: 3,
				in_grace: true,
			}),
		);
		renderWithRouter(<SubscriptionDetail subscriptionId="7" />);
		expect(await screen.findByText("Monthly")).toBeInTheDocument();
		expect(schedulingApi.get).toHaveBeenCalledWith(7);
		expect(screen.getByText("Jul 3, 2026")).toBeInTheDocument();
		expect(screen.getByText("Includes 3 paused days")).toBeInTheDocument();
		expect(screen.getByText("5 of 8 sessions")).toBeInTheDocument();
		expect(screen.getByText("In grace until Jul 7, 2026")).toBeInTheDocument();
		expect(screen.getByText(/EGP|E£/)).toBeInTheDocument();
	});

	it("shows not-found for a 404 and for a non-numeric id", async () => {
		vi.mocked(schedulingApi.get).mockRejectedValue(
			new AxiosError("Not Found", "404", undefined, undefined, {
				status: 404,
			} as never),
		);
		const { unmount } = renderWithRouter(
			<SubscriptionDetail subscriptionId="99" />,
		);
		expect(
			await screen.findByText("This subscription couldn't be found."),
		).toBeInTheDocument();
		unmount();
		renderWithRouter(<SubscriptionDetail subscriptionId="abc" />);
		expect(
			await screen.findByText("This subscription couldn't be found."),
		).toBeInTheDocument();
		expect(schedulingApi.get).toHaveBeenCalledTimes(1);
	});

	it("shows a load error on a network failure", async () => {
		vi.mocked(schedulingApi.get).mockRejectedValue(new Error("offline"));
		renderWithRouter(<SubscriptionDetail subscriptionId="7" />);
		expect(
			await screen.findByText("Couldn't load this subscription."),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
		expect(NAV_ITEMS.map((i) => i.to)).toEqual([
			"/",
			"/people/students",
```

with:

```ts
		expect(NAV_ITEMS.map((i) => i.to)).toEqual([
			"/",
			"/scheduling/subscriptions",
			"/people/students",
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
		expect(groups.map((g) => g.group)).toEqual([
			undefined,
			"people",
			"catalogue",
			"settings",
			undefined,
		]);
		expect(groups[1]?.items).toHaveLength(4);
```

with:

```ts
		expect(groups.map((g) => g.group)).toEqual([
			undefined,
			"scheduling",
			"people",
			"catalogue",
			"settings",
			undefined,
		]);
		expect(groups[2]?.items).toHaveLength(4);
```

In `dashboard/src/features/shell/AppSidebar.test.tsx`, replace:

```tsx
		expect(await screen.findByText("People")).toBeInTheDocument();
```

with:

```tsx
		expect(await screen.findByText("Scheduling")).toBeInTheDocument();
		expect(screen.getByText("People")).toBeInTheDocument();
```

In `dashboard/src/features/shell/AppSidebar.test.tsx`, replace:

```tsx
		expect(screen.getByRole("link", { name: "Students" })).toBeInTheDocument();
```

with:

```tsx
		expect(screen.getByRole("link", { name: "Students" })).toBeInTheDocument();
		expect(
			screen.getByRole("link", { name: "Subscriptions" }),
		).toBeInTheDocument();
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling src/features/shell`
Expected: FAIL — `./api`, `./SubscriptionsList`, `./SubscriptionDetail` don't exist and the nav has no Scheduling group.

- [ ] **Step 3: Data layer**

Create `dashboard/src/features/scheduling/schemas.ts`:

```ts
export const SUBSCRIPTION_STATUSES = [
	"active",
	"paused",
	"expired",
	"cancelled",
] as const;
export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];

/** Active and paused subscriptions can still be changed (spec §4.2). */
export const isLive = (status: SubscriptionStatus) =>
	status === "active" || status === "paused";

/** 0 = Monday … 6 = Sunday, as the API sends them. */
export const WEEKDAYS = [0, 1, 2, 3, 4, 5, 6] as const;

export interface PersonRef {
	id: number;
	full_name: string;
}
export interface StudentRef extends PersonRef {
	timezone: string;
}
export interface NamedRef {
	id: number;
	name_ar: string;
	name_en: string;
}

export interface Subscription {
	id: number;
	status: SubscriptionStatus;
	student: StudentRef;
	teacher: PersonRef;
	course: NamedRef;
	package: NamedRef;
	starts_on: string;
	term_ends_on: string;
	ends_on: string;
	grace_ends_on: string;
	in_grace: boolean;
	sessions_total: number;
	sessions_used: number;
	carried_over_sessions: number;
	sessions_remaining: number;
	extra_sessions: number;
	progress: number;
	price_minor: number;
	currency: string;
	renewed_from: number | null;
	renewal: number | null;
}

export interface Slot {
	id: number;
	weekday: number;
	start_time: string;
	minutes: number;
	meeting_url: string;
	is_active: boolean;
	has_sessions: boolean;
}

export type PauseState = "upcoming" | "current" | "past";
export interface Pause {
	id: number;
	from_date: string;
	to_date: string;
	reason: string;
	days: number;
	state: PauseState;
}

export interface SubscriptionDetail extends Subscription {
	duration_value: number;
	duration_unit: "day" | "month";
	session_minutes: number;
	freeze_days_allowed: number;
	paused_days: number;
	freeze_days_left: number;
	notes: string;
	slots: Slot[];
	pauses: Pause[];
}

export type Attendance = "not_set" | "present" | "absent" | "excused";
export interface Session {
	id: number;
	subscription_id: number | null;
	slot_id: number | null;
	occurs_on: string;
	starts_at: string;
	minutes: number;
	status: "scheduled" | "completed" | "cancelled";
	student_attendance: Attendance;
	teacher_attendance: Attendance;
	meeting_url: string;
	generated: boolean;
	student: PersonRef;
	teacher: PersonRef;
	course: NamedRef;
}

export interface GenerationResult {
	created: number;
	skipped_existing: number;
	skipped_paused: number;
	skipped_out_of_term: number;
	conflicts: { session: Session; other: Session }[];
}

export type TodayState = "generated" | "missing" | "completed" | "cancelled";
export interface TodayRow {
	slot_id: number;
	subscription_id: number;
	session_id: number | null;
	date: string;
	start_time: string;
	starts_at: string;
	minutes: number;
	state: TodayState;
	student: StudentRef;
	teacher: PersonRef;
	course: NamedRef;
	sessions_total: number;
	sessions_used: number;
	carried_over_sessions: number;
	extra_sessions: number;
	progress: number;
}
export interface TodayBoard {
	date: string;
	rows: TodayRow[];
}

// Request bodies (spec §5). People are User ids, as in Plan 3.
export interface SlotBody {
	weekdays: number[];
	start_time: string;
	minutes?: number;
	meeting_url?: string;
}
export interface SubscriptionBody {
	student: number;
	course: number;
	teacher: number;
	package: number;
	starts_on: string;
	price_minor?: number;
	notes?: string;
	slots?: SlotBody[];
}
export interface SubscriptionPatch {
	teacher?: number;
	price_minor?: number;
	notes?: string;
	starts_on?: string;
}
export interface RenewBody {
	starts_on?: string;
	teacher?: number;
	package?: number;
	course?: number;
	price_minor?: number;
}
export interface PauseBody {
	from_date: string;
	to_date: string;
	reason?: string;
}
export interface SlotPatch {
	start_time?: string;
	minutes?: number;
	meeting_url?: string;
	is_active?: boolean;
}
export interface GenerateBody {
	from: string;
	to: string;
	subscription?: number;
}
```

Create `dashboard/src/features/scheduling/api.ts`:

```ts
import {
	api,
	clean,
	csvUrl,
	type Paginated,
	type QueryParams,
} from "@/lib/api";
import type {
	GenerateBody,
	GenerationResult,
	PauseBody,
	RenewBody,
	Session,
	SlotBody,
	SlotPatch,
	Subscription,
	SubscriptionBody,
	SubscriptionDetail,
	SubscriptionPatch,
	TodayBoard,
} from "./schemas";

const S = "subscriptions/";
const detail = async (request: Promise<{ data: SubscriptionDetail }>) =>
	(await request).data;

export const schedulingApi = {
	list: async (params: QueryParams) =>
		(await api.get<Paginated<Subscription>>(S, { params: clean(params) })).data,
	get: (id: number) => detail(api.get(`${S}${id}/`)),
	create: (body: SubscriptionBody) => detail(api.post(S, body)),
	update: (id: number, body: SubscriptionPatch) =>
		detail(api.patch(`${S}${id}/`, body)),
	remove: async (id: number) => {
		await api.delete(`${S}${id}/`);
	},
	renew: (id: number, body: RenewBody) =>
		detail(api.post(`${S}${id}/renew/`, body)),
	cancel: (id: number) => detail(api.post(`${S}${id}/cancel/`)),
	addPause: (id: number, body: PauseBody) =>
		detail(api.post(`${S}${id}/pauses/`, body)),
	endPause: (pauseId: number) => detail(api.post(`pauses/${pauseId}/end/`)),
	deletePause: async (pauseId: number) => {
		await api.delete(`pauses/${pauseId}/`);
	},
	addSlots: (id: number, body: SlotBody) =>
		detail(api.post(`${S}${id}/slots/`, body)),
	updateSlot: (slotId: number, body: SlotPatch) =>
		detail(api.patch(`slots/${slotId}/`, body)),
	deleteSlot: async (slotId: number) => {
		await api.delete(`slots/${slotId}/`);
	},
	sessions: async (id: number, params: QueryParams) =>
		(
			await api.get<Paginated<Session>>(`${S}${id}/sessions/`, {
				params: clean(params),
			})
		).data,
	generate: async (body: GenerateBody) =>
		(await api.post<GenerationResult>("schedule/generate/", body)).data,
	today: async () => (await api.get<TodayBoard>("schedule/today/")).data,
};

/** The subscriptions list's CSV export, with the list's filters. */
export function subscriptionsCsvUrl(params: QueryParams): string {
	return csvUrl(S, params);
}
```

Create `dashboard/src/features/scheduling/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import type { QueryParams } from "@/lib/api";
import { schedulingApi } from "./api";

/** Every scheduling query lives under this key: one change (a pause, a slot,
 * a renewal) can move lists, details, sessions and Today, so a successful
 * mutation refreshes them all. */
export const schedulingKey = ["scheduling"] as const;

export function useSubscriptions(params: QueryParams) {
	return useQuery({
		queryKey: [...schedulingKey, "subscriptions", params],
		queryFn: () => schedulingApi.list(params),
		placeholderData: keepPreviousData,
	});
}

export function useSubscription(id: number | undefined) {
	return useQuery({
		queryKey: [...schedulingKey, "subscription", id],
		queryFn: () => schedulingApi.get(id as number),
		enabled: id !== undefined,
	});
}

export function useSessions(id: number, params: QueryParams) {
	return useQuery({
		queryKey: [...schedulingKey, "sessions", id, params],
		queryFn: () => schedulingApi.sessions(id, params),
		placeholderData: keepPreviousData,
	});
}

export function useToday() {
	return useQuery({
		queryKey: [...schedulingKey, "today"],
		queryFn: schedulingApi.today,
	});
}

/** A scheduling write that refreshes every scheduling query on success.
 * `write` gets the mutation's one argument only (not TanStack's context). */
export function useSchedulingMutation<A, R>(write: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (args: A) => write(args),
		onSuccess: () => qc.invalidateQueries({ queryKey: schedulingKey }),
	});
}
```

- [ ] **Step 4: List, summary, routes and nav**

Create `dashboard/src/features/scheduling/bits.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Meter, StatusChip } from "@/ui";
import type { NamedRef, SubscriptionStatus } from "./schemas";

const TONE: Record<SubscriptionStatus, "live" | "neutral" | "warning"> = {
	active: "live",
	paused: "neutral",
	expired: "neutral",
	cancelled: "warning",
};

export function SubscriptionStatusChip({
	status,
}: {
	status: SubscriptionStatus;
}) {
	const { t } = useTranslation();
	return (
		<StatusChip tone={TONE[status]}>
			{t(`scheduling.status.${status}`)}
		</StatusChip>
	);
}

/** A course or package name in the reader's language. */
export function useLocalName() {
	const { i18n } = useTranslation();
	return (ref: NamedRef) =>
		i18n.language === "ar" ? ref.name_ar : ref.name_en;
}

/** Sessions taken (carried-over plus used) of the total, capped at a full bar
 * (spec §3.2), with the extras beyond the package as a badge. */
export function SubscriptionProgress({
	name,
	used,
	carried,
	total,
	extra,
}: {
	name: string;
	used: number;
	carried: number;
	total: number;
	extra: number;
}) {
	const { t } = useTranslation();
	const taken = used + carried;
	return (
		<div className="flex min-w-32 flex-col gap-1">
			<Meter
				role="progressbar"
				label={t("scheduling.progressLabel", { name })}
				value={Math.min(taken, total)}
				max={total}
				tone={extra > 0 ? "destructive" : "primary"}
			/>
			<span className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
				{t("scheduling.progress", { used: taken, total })}
				{extra > 0 ? (
					<StatusChip tone="warning">
						{t("scheduling.extra", { count: extra })}
					</StatusChip>
				) : null}
			</span>
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/SubscriptionsList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { CalendarClock } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { type Course, useCatalogue } from "@/features/catalogue";
import { usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	EmptyState,
	Input,
	Select,
	Spinner,
} from "@/ui";
import { subscriptionsCsvUrl } from "./api";
import {
	SubscriptionProgress,
	SubscriptionStatusChip,
	useLocalName,
} from "./bits";
import { useSubscriptions } from "./queries";
import { SUBSCRIPTION_STATUSES, type Subscription } from "./schemas";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
const TABS = ["all", ...SUBSCRIPTION_STATUSES] as const;

export function SubscriptionsList() {
	const { t, i18n } = useTranslation();
	const [params, setParams] = useState<QueryParams>({ page: 1 });
	const { data, isPending, isError } = useSubscriptions(params);
	const { data: teachers } = usePeople("teachers", { page_size: 100 });
	const { data: courses } = useCatalogue<Course>("courses", {
		page_size: 100,
	});
	const localName = useLocalName();
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const current = String(params.status ?? "all");
	const update = (patch: QueryParams) =>
		setParams({ ...params, page: 1, ...patch });

	function ends(sub: Subscription) {
		const day = formatDay(
			sub.in_grace ? sub.grace_ends_on : sub.ends_on,
			i18n.language,
		);
		return sub.in_grace ? t("scheduling.inGraceUntil", { date: day }) : day;
	}

	return (
		<div className="flex flex-col gap-4">
			<div
				role="tablist"
				aria-label={t("scheduling.columns.status")}
				className="flex flex-wrap gap-2 border-b border-border pb-2"
			>
				{TABS.map((tab) => (
					<button
						key={tab}
						type="button"
						role="tab"
						aria-selected={current === tab}
						onClick={() => update({ status: tab === "all" ? undefined : tab })}
						className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
					>
						{tab === "all"
							? t("scheduling.tabs.all")
							: t(`scheduling.status.${tab}`)}
					</button>
				))}
			</div>
			<div className="flex flex-wrap items-end gap-3">
				<div className="min-w-48 flex-1">
					<label htmlFor="subscriptions-search" className="sr-only">
						{t("scheduling.search")}
					</label>
					<Input
						id="subscriptions-search"
						type="search"
						placeholder={t("scheduling.search")}
						value={String(params.q ?? "")}
						onChange={(e) => update({ q: e.target.value })}
					/>
				</div>
				<Select
					aria-label={t("scheduling.columns.teacher")}
					className="w-auto"
					value={String(params.teacher ?? "")}
					onChange={(e) => update({ teacher: e.target.value })}
				>
					<option value="">{t("scheduling.anyTeacher")}</option>
					{teachers?.results.map((p) => (
						<option key={p.id} value={p.id}>
							{p.user.full_name}
						</option>
					))}
				</Select>
				<Select
					aria-label={t("scheduling.columns.course")}
					className="w-auto"
					value={String(params.course ?? "")}
					onChange={(e) => update({ course: e.target.value })}
				>
					<option value="">{t("scheduling.anyCourse")}</option>
					{courses?.results.map((c) => (
						<option key={c.id} value={c.id}>
							{localName(c)}
						</option>
					))}
				</Select>
				<Button asChild variant="outline" size="sm">
					<a href={subscriptionsCsvUrl(params)} download>
						{t("people.exportCsv")}
					</a>
				</Button>
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("scheduling.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={CalendarClock} title={t("scheduling.empty")} />
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{(
									[
										"student",
										"course",
										"teacher",
										"progress",
										"status",
										"ends",
									] as const
								).map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(`scheduling.columns.${key}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((sub) => (
								<tr key={sub.id} className="border-t border-border">
									<td className="p-3">
										<Link
											to="/scheduling/subscriptions/$subscriptionId"
											params={{ subscriptionId: String(sub.id) }}
											className="font-medium text-primary-text underline-offset-4 hover:underline"
										>
											{sub.student.full_name}
										</Link>
									</td>
									<td className="p-3">{localName(sub.course)}</td>
									<td className="p-3">{sub.teacher.full_name}</td>
									<td className="p-3">
										<SubscriptionProgress
											name={sub.student.full_name}
											used={sub.sessions_used}
											carried={sub.carried_over_sessions}
											total={sub.sessions_total}
											extra={sub.extra_sessions}
										/>
									</td>
									<td className="p-3">
										<SubscriptionStatusChip status={sub.status} />
									</td>
									<td className="p-3">{ends(sub)}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => setParams({ ...params, page: next })}
			/>
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/SubscriptionDetail.tsx`:

```tsx
import { isAxiosError } from "axios";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { formatMoney } from "@/lib/money";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import {
	SubscriptionProgress,
	SubscriptionStatusChip,
	useLocalName,
} from "./bits";
import { useSubscription } from "./queries";
import type { SubscriptionDetail as Detail } from "./schemas";

function Fact({ label, children }: { label: string; children: ReactNode }) {
	return (
		<div className="flex flex-col gap-0.5">
			<dt className="text-xs text-muted-foreground">{label}</dt>
			<dd className="font-medium">{children}</dd>
		</div>
	);
}

function Summary({ sub }: { sub: Detail }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const day = (value: string) => formatDay(value, i18n.language);
	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
				<CardTitle>{t("scheduling.summary.title")}</CardTitle>
				<SubscriptionStatusChip status={sub.status} />
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
					<Fact label={t("scheduling.columns.student")}>
						{sub.student.full_name}
					</Fact>
					<Fact label={t("scheduling.columns.course")}>
						{localName(sub.course)}
					</Fact>
					<Fact label={t("scheduling.columns.teacher")}>
						{sub.teacher.full_name}
					</Fact>
					<Fact label={t("scheduling.summary.package")}>
						{localName(sub.package)}
					</Fact>
					<Fact label={t("scheduling.summary.startsOn")}>
						{day(sub.starts_on)}
					</Fact>
					<Fact label={t("scheduling.summary.endsOn")}>
						{day(sub.ends_on)}
						{sub.paused_days > 0 ? (
							<span className="block text-xs font-normal text-muted-foreground">
								{t("scheduling.summary.pausedDays", {
									count: sub.paused_days,
								})}
							</span>
						) : null}
					</Fact>
					<Fact label={t("scheduling.summary.graceEndsOn")}>
						{day(sub.grace_ends_on)}
					</Fact>
					<Fact label={t("scheduling.summary.price")}>
						<span dir="ltr">
							{formatMoney(sub.price_minor, sub.currency, i18n.language)}
						</span>
					</Fact>
					<Fact label={t("scheduling.summary.remaining")}>
						{sub.sessions_remaining}
					</Fact>
					<Fact label={t("scheduling.summary.used")}>{sub.sessions_used}</Fact>
					<Fact label={t("scheduling.summary.carried")}>
						{sub.carried_over_sessions}
					</Fact>
					<Fact label={t("scheduling.summary.extra")}>
						{sub.extra_sessions}
					</Fact>
				</dl>
				<SubscriptionProgress
					name={sub.student.full_name}
					used={sub.sessions_used}
					carried={sub.carried_over_sessions}
					total={sub.sessions_total}
					extra={sub.extra_sessions}
				/>
				{sub.in_grace ? (
					<p className="text-sm text-muted-foreground">
						{t("scheduling.inGraceUntil", { date: day(sub.grace_ends_on) })}
					</p>
				) : null}
			</CardContent>
		</Card>
	);
}

export function SubscriptionDetail({
	subscriptionId,
}: {
	subscriptionId: string;
}) {
	const { t } = useTranslation();
	const parsed = Number(subscriptionId);
	// `/scheduling/subscriptions/abc` is never a subscription: no request.
	const invalidId = !Number.isInteger(parsed) || parsed < 1;
	const {
		data: sub,
		isError,
		error,
	} = useSubscription(invalidId ? undefined : parsed);
	const status = isAxiosError(error) ? error.response?.status : undefined;
	if (invalidId || status === 404 || isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{invalidId || status === 404
						? t("scheduling.notFound")
						: t("scheduling.detailLoadError")}
				</AlertDescription>
			</Alert>
		);
	}
	if (!sub) return <Spinner />;
	return (
		<div className="flex flex-col gap-6">
			<Summary sub={sub} />
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/index.ts`:

```ts
export { schedulingApi, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SubscriptionDetail } from "./SubscriptionDetail";
export { SubscriptionsList } from "./SubscriptionsList";
export * from "./schemas";
```

Create `dashboard/src/routes/_authed/scheduling.tsx`:

```tsx
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { requireAdmin } from "@/features/identity/require-admin";
import { PageContainer } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling")({
	beforeLoad: ({ context }) => requireAdmin(context),
	component: () => (
		<PageContainer>
			<Outlet />
		</PageContainer>
	),
});
```

Create `dashboard/src/routes/_authed/scheduling.index.tsx`:

```tsx
import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/_authed/scheduling/")({
	beforeLoad: () => {
		throw redirect({ to: "/scheduling/subscriptions" });
	},
});
```

Create `dashboard/src/routes/_authed/scheduling.subscriptions.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SubscriptionsList } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling/subscriptions/")({
	component: function SubscriptionsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.subscriptions"));
		return (
			<>
				<PageHeader title={t("nav.subscriptions")} />
				<SubscriptionsList />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/scheduling.subscriptions.$subscriptionId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SubscriptionDetail } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute(
	"/_authed/scheduling/subscriptions/$subscriptionId",
)({
	component: function SubscriptionRoute() {
		const { t } = useTranslation();
		const { subscriptionId } = Route.useParams();
		usePageTitle(t("scheduling.detailTitle"));
		return (
			<>
				<PageHeader title={t("scheduling.detailTitle")} />
				<SubscriptionDetail subscriptionId={subscriptionId} />
			</>
		);
	},
});
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	Presentation,
	Settings,
```

with:

```ts
	Presentation,
	Repeat,
	Settings,
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
export type NavGroup = "people" | "catalogue" | "settings";
```

with:

```ts
export type NavGroup = "scheduling" | "people" | "catalogue" | "settings";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	{ to: "/", labelKey: "auth.home", icon: Home },
```

with:

```ts
	{ to: "/", labelKey: "auth.home", icon: Home },
	admin("/scheduling/subscriptions", "nav.subscriptions", Repeat, "scheduling"),
```

Merge these keys into `dashboard/src/locales/en/common.json` (nested objects merge into the existing ones; keep the file's tab indentation):

```json
{
	"nav": {
		"subscriptions": "Subscriptions",
		"group": {
			"scheduling": "Scheduling"
		}
	},
	"scheduling": {
		"status": {
			"active": "Active",
			"paused": "Paused",
			"expired": "Expired",
			"cancelled": "Cancelled"
		},
		"tabs": {
			"all": "All"
		},
		"search": "Search by student",
		"anyTeacher": "Any teacher",
		"anyCourse": "Any course",
		"columns": {
			"student": "Student",
			"course": "Course",
			"teacher": "Teacher",
			"progress": "Progress",
			"status": "Status",
			"ends": "Ends"
		},
		"progress": "{{used}} of {{total}} sessions",
		"progressLabel": "Sessions taken by {{name}}",
		"extra": "+{{count}} extra",
		"inGraceUntil": "In grace until {{date}}",
		"empty": "No subscriptions yet.",
		"loadError": "Couldn't load subscriptions.",
		"detailTitle": "Subscription",
		"notFound": "This subscription couldn't be found.",
		"detailLoadError": "Couldn't load this subscription.",
		"summary": {
			"title": "Summary",
			"package": "Package",
			"startsOn": "Starts",
			"endsOn": "Ends",
			"pausedDays": "Includes {{count}} paused days",
			"graceEndsOn": "Grace ends",
			"price": "Price",
			"remaining": "Sessions remaining",
			"used": "Sessions used",
			"carried": "Carried over",
			"extra": "Extra sessions"
		}
	}
}
```

and these into `dashboard/src/locales/ar/common.json`:

```json
{
	"nav": {
		"subscriptions": "الاشتراكات",
		"group": {
			"scheduling": "الجدولة"
		}
	},
	"scheduling": {
		"status": {
			"active": "نشط",
			"paused": "موقوف مؤقتًا",
			"expired": "منتهٍ",
			"cancelled": "ملغى"
		},
		"tabs": {
			"all": "الكل"
		},
		"search": "ابحث باسم الطالب",
		"anyTeacher": "كل المعلمين",
		"anyCourse": "كل الدورات",
		"columns": {
			"student": "الطالب",
			"course": "الدورة",
			"teacher": "المعلم",
			"progress": "التقدم",
			"status": "الحالة",
			"ends": "ينتهي"
		},
		"progress": "{{used}} من {{total}} حصة",
		"progressLabel": "الحصص التي حضرها {{name}}",
		"extra": "+{{count}} إضافية",
		"inGraceUntil": "في المهلة حتى {{date}}",
		"empty": "لا توجد اشتراكات بعد.",
		"loadError": "تعذّر تحميل الاشتراكات.",
		"detailTitle": "الاشتراك",
		"notFound": "تعذّر العثور على هذا الاشتراك.",
		"detailLoadError": "تعذّر تحميل بيانات هذا الاشتراك.",
		"summary": {
			"title": "الملخص",
			"package": "الباقة",
			"startsOn": "يبدأ",
			"endsOn": "ينتهي",
			"pausedDays": "يشمل {{count}} يوم إيقاف",
			"graceEndsOn": "تنتهي المهلة",
			"price": "السعر",
			"remaining": "الحصص المتبقية",
			"used": "الحصص المستخدمة",
			"carried": "المرحّلة",
			"extra": "الحصص الإضافية"
		}
	}
}
```

- [ ] **Step 5: Format, regenerate the route tree, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src`

Run (from `dashboard/`): `npx pnpm@10 exec vite build`
Expected: `src/routeTree.gen.ts` now has the three `/scheduling` routes.

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling src/features/shell`
Expected: PASS. Rows are found `within(table)` so the filter selects' option text never matches twice.

- [ ] **Step 6: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): subscriptions list and summary under a Scheduling nav group

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Dashboard: new subscription form with the slot editor

**Files:**
- Create: `dashboard/src/features/scheduling/choices.ts`, `dashboard/src/features/scheduling/TermFields.tsx`, `dashboard/src/features/scheduling/SlotFields.tsx`, `dashboard/src/features/scheduling/SubscriptionForm.tsx`, `dashboard/src/features/scheduling/SubscriptionForm.test.tsx`, `dashboard/src/routes/_authed/scheduling.subscriptions.new.tsx`
- Modify: `dashboard/src/features/scheduling/schemas.ts`, `dashboard/src/features/scheduling/SubscriptionsList.tsx`, `dashboard/src/features/scheduling/SubscriptionsList.test.tsx` (New button), `dashboard/src/features/scheduling/index.ts`, locales

**Interfaces:**
- Consumes: `studentTime`, `todayIn`, `weekdayName`, `toMajor`/`toMinor`, `applyServerErrors`, `useFieldError`; `useAcademySettings`; `schedulingApi.create`.
- Produces schemas `isoDate`, `price`, `slotGroupSchema` (`{weekdays: number[] ≥ 1, start_time: "HH:MM", minutes 15–240}`), `subscriptionFormSchema`; messages are `scheduling.errors.*` keys.
- Produces `useChoices()` → `{courses, packages, packageById(id), teachersFor(courseId)}` (active only; a course's own teachers when it lists any).
- Produces `TermFields({idPrefix?, onPackage?})` (course → teacher → package → start → price, in a `FormProvider`; choosing a package fills the price) and `SlotFields({prefix, studentTime?})`; Task 14 adds `days` and `meetingUrl` props.
- Produces `SubscriptionForm` at `/scheduling/subscriptions/new`; on success it opens the new detail page.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/scheduling/SubscriptionForm.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { page, subscriptionDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SubscriptionForm } from "./SubscriptionForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, create: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, list: vi.fn() },
	};
});

const person = (id: number, full_name: string, timezone = "UTC") => ({
	id,
	user: { full_name, timezone },
});
const monthly = {
	id: 5,
	name_ar: "شهري",
	name_en: "Monthly",
	sessions_total: 8,
	session_minutes: 45,
	duration_value: 1,
	duration_unit: "month",
	price_minor: 150000,
	currency: "EGP",
};

describe("SubscriptionForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "en",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
		vi.mocked(peopleApi.list).mockImplementation(
			async (kind) =>
				(kind === "students"
					? page([person(11, "Yusuf", "Asia/Riyadh")])
					: page([person(21, "Bilal"), person(22, "Maryam")])) as never,
		);
		vi.mocked(catalogueApi.list).mockImplementation(
			async (kind) =>
				(kind === "courses"
					? page([
							{
								id: 3,
								name_ar: "تجويد",
								name_en: "Tajweed",
								teacher_ids: [21],
							},
						])
					: page([monthly])) as never,
		);
	});

	async function fillIn(user: ReturnType<typeof userEvent.setup>) {
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		await user.selectOptions(screen.getByLabelText(/^Course/), "3");
		await user.selectOptions(screen.getByLabelText(/^Teacher/), "21");
		await user.selectOptions(screen.getByLabelText(/^Package/), "5");
		await user.clear(screen.getByLabelText(/^Starts/));
		await user.type(screen.getByLabelText(/^Starts/), "2026-06-01");
	}

	it("creates a subscription with its slots and opens it", async () => {
		vi.mocked(schedulingApi.create).mockResolvedValue(
			subscriptionDetail({ id: 9 }),
		);
		const user = userEvent.setup();
		const { router } = renderWithRouter(<SubscriptionForm />, {
			extraPaths: ["/scheduling/subscriptions/$subscriptionId"],
		});
		await fillIn(user);
		// The course lists only Bilal.
		expect(
			screen.queryByRole("option", { name: "Maryam" }),
		).not.toBeInTheDocument();
		expect(screen.getByLabelText(/^Price/)).toHaveValue("1500.00");
		expect(
			screen.getByText("8 sessions of 45 minutes over 1 months"),
		).toBeInTheDocument();
		await user.click(screen.getByLabelText("Mon"));
		await user.click(screen.getByLabelText("Wed"));
		await user.type(screen.getByLabelText(/^Start time/), "18:00");
		expect(screen.getByText("Student's time: 21:00")).toBeInTheDocument();
		await user.click(
			screen.getByRole("button", { name: "Create subscription" }),
		);
		await waitFor(() =>
			expect(schedulingApi.create).toHaveBeenCalledWith({
				student: 11,
				course: 3,
				teacher: 21,
				package: 5,
				starts_on: "2026-06-01",
				price_minor: 150000,
				slots: [{ weekdays: [0, 2], start_time: "18:00", minutes: 45 }],
			}),
		);
		await waitFor(() =>
			expect(router.state.location.pathname).toBe(
				"/scheduling/subscriptions/9",
			),
		);
	});

	it("checks required choices and each slot group before sending", async () => {
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionForm />);
		await user.click(
			await screen.findByRole("button", { name: "Create subscription" }),
		);
		expect(await screen.findAllByText("Choose one.")).toHaveLength(4);
		expect(screen.getByText("Pick at least one day.")).toBeInTheDocument();
		expect(screen.getByText("Enter a start time.")).toBeInTheDocument();
		expect(schedulingApi.create).not.toHaveBeenCalled();
	});

	it("adds and removes slot groups", async () => {
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionForm />);
		await user.click(
			await screen.findByRole("button", { name: "Add slot times" }),
		);
		expect(screen.getAllByLabelText(/^Start time/)).toHaveLength(2);
		await user.click(
			screen.getAllByRole("button", { name: "Remove these slot times" })[0],
		);
		expect(screen.getAllByLabelText(/^Start time/)).toHaveLength(1);
	});

	it("puts server errors on their fields", async () => {
		vi.mocked(schedulingApi.create).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { teacher: ["This teacher does not teach the course."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionForm />);
		await fillIn(user);
		await user.click(screen.getByLabelText("Mon"));
		await user.type(screen.getByLabelText(/^Start time/), "18:00");
		await user.click(
			screen.getByRole("button", { name: "Create subscription" }),
		);
		expect(
			await screen.findByText("This teacher does not teach the course."),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/features/scheduling/SubscriptionsList.test.tsx`, replace:

```tsx
			"/scheduling/subscriptions/7",
		);
	});
```

with:

```tsx
			"/scheduling/subscriptions/7",
		);
		expect(
			screen.getByRole("link", { name: "New subscription" }),
		).toHaveAttribute("href", "/scheduling/subscriptions/new");
	});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling`
Expected: FAIL — no `./SubscriptionForm`, and the list has no New subscription link.

- [ ] **Step 3: Form schemas**

Add these imports to `dashboard/src/features/scheduling/schemas.ts` (`biome check --write` in the format step puts them in order):

```ts
import { z } from "zod";
```

Append to the end of `dashboard/src/features/scheduling/schemas.ts`:

```ts
// Form schemas. Messages are i18n keys, translated by `useFieldError`.
const minutes = z
	.number({ error: "scheduling.errors.minutesRange" })
	.int("scheduling.errors.minutesRange")
	.min(15, "scheduling.errors.minutesRange")
	.max(240, "scheduling.errors.minutesRange");
const pick = z.string().min(1, "scheduling.errors.required");
export const isoDate = z
	.string()
	.regex(/^\d{4}-\d{2}-\d{2}$/, "scheduling.errors.dateRequired");
export const price = z
	.string()
	.regex(/^\d+(\.\d{1,3})?$/, "scheduling.errors.priceInvalid");

export const slotGroupSchema = z.object({
	weekdays: z.array(z.number()).min(1, "scheduling.errors.pickDay"),
	start_time: z
		.string()
		.regex(/^\d{2}:\d{2}$/, "scheduling.errors.timeRequired"),
	minutes,
});
export type SlotGroupValues = z.infer<typeof slotGroupSchema>;

export const subscriptionFormSchema = z.object({
	student: pick,
	course: pick,
	teacher: pick,
	package: pick,
	starts_on: isoDate,
	price,
	slots: z.array(slotGroupSchema),
});
export type SubscriptionFormValues = z.infer<typeof subscriptionFormSchema>;
```

- [ ] **Step 4: Choices, term fields, slot fields and the form**

Create `dashboard/src/features/scheduling/choices.ts`:

```ts
import { type Course, type Package, useCatalogue } from "@/features/catalogue";
import { usePeople } from "@/features/people";

const ACTIVE = { is_active: "true", page_size: 100 } as const;

/** Active courses, packages and teachers for the subscription forms. */
export function useChoices() {
	const teachers = usePeople("teachers", ACTIVE).data?.results ?? [];
	const courses = useCatalogue<Course>("courses", ACTIVE).data?.results ?? [];
	const packages =
		useCatalogue<Package>("packages", ACTIVE).data?.results ?? [];
	return {
		courses,
		packages,
		packageById: (id: string) => packages.find((p) => String(p.id) === id),
		/** Spec §6: only the course's teachers, when it lists any. */
		teachersFor: (courseId: string) => {
			const course = courses.find((c) => String(c.id) === courseId);
			return teachers.filter(
				(p) => !course?.teacher_ids.length || course.teacher_ids.includes(p.id),
			);
		},
	};
}
```

Create `dashboard/src/features/scheduling/TermFields.tsx`:

```tsx
import { useFormContext } from "react-hook-form";
import { useTranslation } from "react-i18next";
import type { Package } from "@/features/catalogue";
import { useFieldError } from "@/lib/field-error";
import { toMajor } from "@/lib/money";
import { Field, Input, Select } from "@/ui";
import { useLocalName } from "./bits";
import { useChoices } from "./choices";

type TermValues = {
	course: string;
	teacher: string;
	package: string;
	starts_on: string;
	price: string;
};

/**
 * Course, then teacher (the course's own when it lists any), then package,
 * start date and price (spec §6). Shared by the new-subscription form and the
 * renew dialog; lives in a `FormProvider`. Choosing a package fills in its
 * price and tells `onPackage`.
 */
export function TermFields({
	idPrefix = "",
	onPackage,
}: {
	idPrefix?: string;
	onPackage?: (pkg: Package) => void;
}) {
	const { t } = useTranslation();
	const localName = useLocalName();
	const fieldError = useFieldError();
	const { courses, packages, packageById, teachersFor } = useChoices();
	const {
		register,
		setValue,
		watch,
		formState: { errors },
	} = useFormContext<TermValues>();
	const pkg = packageById(watch("package"));
	const id = (name: string) => `${idPrefix}${name}`;

	return (
		<div className="flex flex-col gap-4">
			<div className="grid gap-4 sm:grid-cols-2">
				<Field
					id={id("course")}
					label={t("scheduling.columns.course")}
					error={fieldError(errors.course?.message)}
					required
				>
					<Select
						{...register("course", {
							// A new course may not list the chosen teacher.
							onChange: () => setValue("teacher", ""),
						})}
					>
						<option value="">—</option>
						{courses.map((c) => (
							<option key={c.id} value={c.id}>
								{localName(c)}
							</option>
						))}
					</Select>
				</Field>
				<Field
					id={id("teacher")}
					label={t("scheduling.columns.teacher")}
					error={fieldError(errors.teacher?.message)}
					required
				>
					<Select {...register("teacher")}>
						<option value="">—</option>
						{teachersFor(watch("course")).map((p) => (
							<option key={p.id} value={p.id}>
								{p.user.full_name}
							</option>
						))}
					</Select>
				</Field>
				<Field
					id={id("package")}
					label={t("scheduling.summary.package")}
					error={fieldError(errors.package?.message)}
					required
				>
					<Select
						{...register("package", {
							onChange: (e) => {
								const chosen = packageById(e.target.value);
								if (!chosen) return;
								setValue("price", toMajor(chosen.price_minor, chosen.currency));
								onPackage?.(chosen);
							},
						})}
					>
						<option value="">—</option>
						{packages.map((p) => (
							<option key={p.id} value={p.id}>
								{localName(p)}
							</option>
						))}
					</Select>
				</Field>
				<Field
					id={id("starts_on")}
					label={t("scheduling.summary.startsOn")}
					error={fieldError(errors.starts_on?.message)}
					required
				>
					<Input type="date" dir="ltr" {...register("starts_on")} />
				</Field>
				<Field
					id={id("price")}
					label={t("scheduling.form.price", { currency: pkg?.currency ?? "" })}
					error={fieldError(errors.price?.message)}
					required
				>
					<Input inputMode="decimal" dir="ltr" {...register("price")} />
				</Field>
			</div>
			{pkg ? (
				<p aria-live="polite" className="rounded-md bg-secondary p-3 text-sm">
					{t("scheduling.form.packageFacts", {
						sessions: pkg.sessions_total,
						minutes: pkg.session_minutes,
						duration: t(
							pkg.duration_unit === "month"
								? "scheduling.form.months"
								: "scheduling.form.days",
							{ count: pkg.duration_value },
						),
					})}
				</p>
			) : null}
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/SlotFields.tsx`:

```tsx
import { Controller, get, useFormContext } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { weekdayName } from "@/lib/zoned-time";
import { Checkbox, Field, FormError, Input } from "@/ui";
import { WEEKDAYS } from "./schemas";

/**
 * Weekdays, a start time and minutes for one slot group (spec §6). Lives in a
 * `FormProvider`; `prefix` is the group's path, e.g. `slots.0.` or `""`.
 * `studentTime` turns a start time into the student's clock, or null.
 */
export function SlotFields({
	prefix,
	studentTime,
}: {
	prefix: string;
	studentTime?: (time: string) => string | null;
}) {
	const { t, i18n } = useTranslation();
	const {
		control,
		register,
		watch,
		formState: { errors },
	} = useFormContext();
	const fieldError = useFieldError();
	const error = (name: string) =>
		fieldError(get(errors, `${prefix}${name}`)?.message);
	const theirs = studentTime?.(watch(`${prefix}start_time`) ?? "");
	const id = (name: string) => `${prefix}${name}`;

	return (
		<div className="flex flex-col gap-3">
			<fieldset className="flex flex-col gap-2">
				<legend className="mb-1 text-sm font-medium">
					{t("scheduling.slots.days")}
				</legend>
				<Controller
					control={control}
					name={`${prefix}weekdays`}
					render={({ field }) => (
						<div className="flex flex-wrap gap-3">
							{WEEKDAYS.map((day) => {
								const checked = (field.value as number[]).includes(day);
								return (
									<label
										key={day}
										htmlFor={id(`day-${day}`)}
										className="flex items-center gap-2 text-sm"
									>
										<Checkbox
											id={id(`day-${day}`)}
											checked={checked}
											onCheckedChange={(on) =>
												field.onChange(
													on
														? [...field.value, day].sort((a, b) => a - b)
														: field.value.filter((d: number) => d !== day),
												)
											}
										/>
										{weekdayName(day, i18n.language)}
									</label>
								);
							})}
						</div>
					)}
				/>
				{error("weekdays") ? <FormError>{error("weekdays")}</FormError> : null}
			</fieldset>
			<div className="grid gap-4 sm:grid-cols-2">
				<Field
					id={id("start_time")}
					label={t("scheduling.slots.startTime")}
					error={error("start_time")}
					required
				>
					<Input type="time" dir="ltr" {...register(`${prefix}start_time`)} />
				</Field>
				<Field
					id={id("minutes")}
					label={t("scheduling.slots.minutes")}
					error={error("minutes")}
					required
				>
					<Input
						type="number"
						min={15}
						max={240}
						{...register(`${prefix}minutes`, { valueAsNumber: true })}
					/>
				</Field>
			</div>
			{theirs ? (
				<p className="text-sm text-muted-foreground">
					{t("scheduling.slots.studentTime", { time: theirs })}
				</p>
			) : null}
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/SubscriptionForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useNavigate } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState } from "react";
import { FormProvider, useFieldArray, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { usePeople } from "@/features/people";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { toMinor } from "@/lib/money";
import { studentTime, todayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Field,
	Input,
	Select,
	Spinner,
	SubmitButton,
} from "@/ui";
import { schedulingApi } from "./api";
import { useChoices } from "./choices";
import { useSchedulingMutation } from "./queries";
import { SlotFields } from "./SlotFields";
import { type SubscriptionFormValues, subscriptionFormSchema } from "./schemas";
import { TermFields } from "./TermFields";

export function SubscriptionForm() {
	const { t, i18n } = useTranslation();
	const navigate = useNavigate();
	const fieldError = useFieldError();
	const [query, setQuery] = useState("");
	const { data: academy } = useAcademySettings();
	const { data: students } = usePeople("students", {
		is_active: "true",
		page_size: 100,
		q: query.trim(),
	});
	const { packageById } = useChoices();
	const create = useSchedulingMutation(schedulingApi.create);
	const methods = useForm<SubscriptionFormValues>({
		resolver: zodResolver(subscriptionFormSchema),
		values: academy
			? {
					student: "",
					course: "",
					teacher: "",
					package: "",
					starts_on: todayIn(academy.timezone),
					price: "",
					slots: [{ weekdays: [], start_time: "", minutes: 45 }],
				}
			: undefined,
	});
	const {
		register,
		handleSubmit,
		setError,
		setValue,
		watch,
		control,
		formState: { errors, isSubmitting },
	} = methods;
	const groups = useFieldArray({ control, name: "slots" });
	const pkg = packageById(watch("package"));
	const student = students?.results.find(
		(s) => String(s.id) === watch("student"),
	);

	const timeForStudent = (time: string) =>
		academy
			? studentTime({
					date: watch("starts_on"),
					time,
					academyZone: academy.timezone,
					studentZone: student?.user.timezone,
					language: i18n.language,
				})
			: null;

	async function onSubmit(values: SubscriptionFormValues) {
		try {
			const created = await create.mutateAsync({
				student: Number(values.student),
				course: Number(values.course),
				teacher: Number(values.teacher),
				package: Number(values.package),
				starts_on: values.starts_on,
				price_minor: toMinor(values.price, pkg?.currency ?? "USD"),
				slots: values.slots,
			});
			navigate({
				to: "/scheduling/subscriptions/$subscriptionId",
				params: { subscriptionId: String(created.id) },
			});
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.price_minor) {
				setError("price", { message: parsed.fieldErrors.price_minor });
			}
		}
	}

	if (!academy) return <Spinner />;

	return (
		<FormProvider {...methods}>
			<form
				onSubmit={handleSubmit(onSubmit)}
				className="flex flex-col gap-6"
				noValidate
			>
				<div className="grid gap-4 sm:grid-cols-2">
					<Field id="student-search" label={t("scheduling.form.findStudent")}>
						<Input
							type="search"
							value={query}
							onChange={(e) => setQuery(e.target.value)}
						/>
					</Field>
					<Field
						id="student"
						label={t("scheduling.columns.student")}
						error={fieldError(errors.student?.message)}
						required
					>
						<Select {...register("student")}>
							<option value="">—</option>
							{students?.results.map((p) => (
								<option key={p.id} value={p.id}>
									{p.user.full_name}
								</option>
							))}
						</Select>
					</Field>
				</div>
				<TermFields
					onPackage={(chosen) =>
						groups.fields.forEach((_, index) => {
							setValue(`slots.${index}.minutes`, chosen.session_minutes);
						})
					}
				/>
				<section className="flex flex-col gap-4">
					<h2 className="font-semibold">{t("scheduling.slots.title")}</h2>
					{groups.fields.map((group, index) => (
						<div
							key={group.id}
							className="flex flex-col gap-3 rounded-lg border border-border p-4"
						>
							<SlotFields
								prefix={`slots.${index}.`}
								studentTime={timeForStudent}
							/>
							<Button
								type="button"
								variant="outline"
								size="sm"
								className="self-start"
								onClick={() => groups.remove(index)}
							>
								{t("scheduling.slots.removeGroup")}
							</Button>
						</div>
					))}
					<Button
						type="button"
						variant="outline"
						size="sm"
						className="self-start"
						onClick={() =>
							groups.append({
								weekdays: [],
								start_time: "",
								minutes: pkg?.session_minutes ?? 45,
							})
						}
					>
						<Plus className="size-4" />
						{t("scheduling.slots.addGroup")}
					</Button>
					{errors.slots?.message ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.slots.message)}
							</AlertDescription>
						</Alert>
					) : null}
				</section>
				{errors.root?.server ? (
					<Alert variant="destructive">
						<AlertDescription>
							{fieldError(errors.root.server.message)}
						</AlertDescription>
					</Alert>
				) : null}
				<SubmitButton pending={isSubmitting} className="self-start">
					{t("scheduling.form.create")}
				</SubmitButton>
			</form>
		</FormProvider>
	);
}
```

Create `dashboard/src/routes/_authed/scheduling.subscriptions.new.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SubscriptionForm } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling/subscriptions/new")({
	component: function NewSubscriptionRoute() {
		const { t } = useTranslation();
		usePageTitle(t("scheduling.new"));
		return (
			<>
				<PageHeader title={t("scheduling.new")} />
				<SubscriptionForm />
			</>
		);
	},
});
```

In `dashboard/src/features/scheduling/SubscriptionsList.tsx`, replace:

```tsx
import { CalendarClock } from "lucide-react";
```

with:

```tsx
import { CalendarClock, Plus } from "lucide-react";
```

In `dashboard/src/features/scheduling/SubscriptionsList.tsx`, replace:

```tsx
				</Button>
			</div>
			{isError ? (
```

with:

```tsx
				</Button>
				<Button asChild size="sm">
					<Link to="/scheduling/subscriptions/new">
						<Plus className="size-4" />
						{t("scheduling.new")}
					</Link>
				</Button>
			</div>
			{isError ? (
```

Replace the whole of `dashboard/src/features/scheduling/index.ts` with:

```ts
export { schedulingApi, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SubscriptionDetail } from "./SubscriptionDetail";
export { SubscriptionForm } from "./SubscriptionForm";
export { SubscriptionsList } from "./SubscriptionsList";
export * from "./schemas";
```

Merge these keys into `dashboard/src/locales/en/common.json` (nested objects merge into the existing ones; keep the file's tab indentation):

```json
{
	"scheduling": {
		"new": "New subscription",
		"form": {
			"findStudent": "Find a student",
			"price": "Price ({{currency}})",
			"packageFacts": "{{sessions}} sessions of {{minutes}} minutes over {{duration}}",
			"days": "{{count}} days",
			"months": "{{count}} months",
			"create": "Create subscription"
		},
		"slots": {
			"title": "Weekly slots",
			"days": "Days",
			"startTime": "Start time",
			"minutes": "Minutes",
			"studentTime": "Student's time: {{time}}",
			"addGroup": "Add slot times",
			"removeGroup": "Remove these slot times"
		},
		"errors": {
			"required": "Choose one.",
			"dateRequired": "Enter a date.",
			"timeRequired": "Enter a start time.",
			"pickDay": "Pick at least one day.",
			"minutesRange": "Use 15 to 240 minutes.",
			"priceInvalid": "Enter an amount, like 150 or 150.50."
		}
	}
}
```

and these into `dashboard/src/locales/ar/common.json`:

```json
{
	"scheduling": {
		"new": "اشتراك جديد",
		"form": {
			"findStudent": "ابحث عن طالب",
			"price": "السعر ({{currency}})",
			"packageFacts": "{{sessions}} حصة، مدة كل منها {{minutes}} دقيقة، خلال {{duration}}",
			"days": "{{count}} يوم",
			"months": "{{count}} شهر",
			"create": "أنشئ الاشتراك"
		},
		"slots": {
			"title": "المواعيد الأسبوعية",
			"days": "الأيام",
			"startTime": "وقت البدء",
			"minutes": "الدقائق",
			"studentTime": "بتوقيت الطالب: {{time}}",
			"addGroup": "أضف مواعيد",
			"removeGroup": "احذف هذه المواعيد"
		},
		"errors": {
			"required": "اختر واحدًا.",
			"dateRequired": "أدخل تاريخًا.",
			"timeRequired": "أدخل وقت البدء.",
			"pickDay": "اختر يومًا واحدًا على الأقل.",
			"minutesRange": "من 15 إلى 240 دقيقة.",
			"priceInvalid": "أدخل مبلغًا، مثل 150 أو 150.50."
		}
	}
}
```

- [ ] **Step 5: Format, regenerate the route tree, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src`

Run (from `dashboard/`): `npx pnpm@10 exec vite build`

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling`
Expected: PASS. Required labels end in `*`, so the tests query `/^Student/`, `/^Start time/` and so on.

- [ ] **Step 6: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): new subscription form with course-limited teachers and a slot editor

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Dashboard: renew, edit, cancel and delete on the detail page

**Files:**
- Create: `dashboard/src/features/scheduling/RenewDialog.tsx`, `dashboard/src/features/scheduling/EditDialog.tsx`, `dashboard/src/features/scheduling/SubscriptionActions.tsx`, `dashboard/src/features/scheduling/SubscriptionActions.test.tsx`
- Modify: `dashboard/src/features/scheduling/schemas.ts`, `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx`, `dashboard/src/test/scheduling-fixtures.ts`, locales

**Interfaces:**
- Consumes: `TermFields`, `useChoices`, `isLive`, `errorText`, `schedulingApi.renew/update/cancel/remove`; the detail's `renewal_starts_on` (Tasks 6–7).
- Produces `renewFormSchema`, `editFormSchema`; `SubscriptionDetail.renewal_starts_on: string`.
- Produces `SubscriptionActions({sub})`: Renew (active, paused, expired; not once renewed — then a link to the renewal), Edit and Cancel (active, paused), Delete (always offered; the server refuses with a translated reason).

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/scheduling/SubscriptionActions.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { page, subscriptionDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SubscriptionActions } from "./SubscriptionActions";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			renew: vi.fn(),
			cancel: vi.fn(),
			remove: vi.fn(),
			update: vi.fn(),
		},
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, list: vi.fn() },
	};
});

function conflict(code: string) {
	return new AxiosError("Conflict", "409", undefined, undefined, {
		status: 409,
		data: { detail: "Refused.", code },
	} as never);
}

const DETAIL = "/scheduling/subscriptions/$subscriptionId";

describe("SubscriptionActions", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([
				{ id: 21, user: { full_name: "Bilal" } },
				{ id: 22, user: { full_name: "Maryam" } },
			]) as never,
		);
		vi.mocked(catalogueApi.list).mockImplementation(
			async (kind) =>
				(kind === "courses"
					? page([
							{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [] },
						])
					: page([
							{
								id: 5,
								name_ar: "شهري",
								name_en: "Monthly",
								sessions_total: 8,
								session_minutes: 45,
								duration_value: 1,
								duration_unit: "month",
								price_minor: 150000,
								currency: "EGP",
							},
						])) as never,
		);
	});

	it("renews with pre-filled values and opens the renewal", async () => {
		vi.mocked(schedulingApi.renew).mockResolvedValue(
			subscriptionDetail({ id: 12 }),
		);
		const user = userEvent.setup();
		const { router } = renderWithRouter(
			<SubscriptionActions
				sub={subscriptionDetail({ price_minor: 120000, extra_sessions: 2 })}
			/>,
			{ extraPaths: [DETAIL] },
		);
		await user.click(await screen.findByRole("button", { name: "Renew" }));
		const dialog = await screen.findByRole("dialog");
		expect(
			within(dialog).getByText(
				"2 extra sessions from this term will be carried into the renewal and subtracted from it.",
			),
		).toBeInTheDocument();
		expect(within(dialog).getByLabelText(/^Starts/)).toHaveValue("2026-07-01");
		expect(within(dialog).getByLabelText(/^Price/)).toHaveValue("1200.00");
		await waitFor(() =>
			expect(within(dialog).getByLabelText(/^Teacher/)).toHaveValue("21"),
		);
		await user.click(within(dialog).getByRole("button", { name: "Renew" }));
		await waitFor(() =>
			expect(schedulingApi.renew).toHaveBeenCalledWith(7, {
				course: 3,
				teacher: 21,
				package: 5,
				starts_on: "2026-07-01",
				price_minor: 120000,
			}),
		);
		await waitFor(() =>
			expect(router.state.location.pathname).toBe(
				"/scheduling/subscriptions/12",
			),
		);
	});

	it("shows a refused renewal in words", async () => {
		vi.mocked(schedulingApi.renew).mockRejectedValue(
			conflict("scheduling.already_renewed"),
		);
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionActions sub={subscriptionDetail()} />);
		await user.click(await screen.findByRole("button", { name: "Renew" }));
		const dialog = await screen.findByRole("dialog");
		await waitFor(() =>
			expect(within(dialog).getByLabelText(/^Teacher/)).toHaveValue("21"),
		);
		await user.click(within(dialog).getByRole("button", { name: "Renew" }));
		expect(
			await within(dialog).findByText(
				"This subscription has already been renewed.",
			),
		).toBeInTheDocument();
	});

	it("links to the renewal instead of renewing twice", () => {
		renderWithRouter(
			<SubscriptionActions
				sub={subscriptionDetail({ renewal: 12, status: "expired" })}
			/>,
		);
		return screen
			.findByRole("link", { name: "Open the renewal" })
			.then((link) => {
				expect(link).toHaveAttribute("href", "/scheduling/subscriptions/12");
				expect(screen.queryByRole("button", { name: "Renew" })).toBeNull();
				// Expired: no edit or cancel either.
				expect(screen.queryByRole("button", { name: "Edit" })).toBeNull();
				expect(
					screen.queryByRole("button", { name: "Cancel subscription" }),
				).toBeNull();
			});
	});

	it("cancels after confirmation", async () => {
		vi.mocked(schedulingApi.cancel).mockResolvedValue(
			subscriptionDetail({ status: "cancelled" }),
		);
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionActions sub={subscriptionDetail()} />);
		await user.click(
			await screen.findByRole("button", { name: "Cancel subscription" }),
		);
		const confirm = await screen.findByRole("alertdialog");
		await user.click(
			within(confirm).getByRole("button", { name: "Cancel subscription" }),
		);
		await waitFor(() => expect(schedulingApi.cancel).toHaveBeenCalledWith(7));
		expect(
			await screen.findByText("Subscription cancelled.", { exact: true }),
		).toBeInTheDocument();
	});

	it("deletes, or says why it cannot", async () => {
		vi.mocked(schedulingApi.remove).mockRejectedValueOnce(
			conflict("scheduling.has_marked_sessions"),
		);
		vi.mocked(schedulingApi.remove).mockResolvedValueOnce(undefined);
		const user = userEvent.setup();
		const { router } = renderWithRouter(
			<SubscriptionActions sub={subscriptionDetail()} />,
			{ extraPaths: ["/scheduling/subscriptions"] },
		);
		const deleteOnce = async () => {
			await user.click(await screen.findByRole("button", { name: "Delete" }));
			const confirm = await screen.findByRole("alertdialog");
			await user.click(
				within(confirm).getByRole("button", { name: "Delete subscription" }),
			);
		};
		await deleteOnce();
		expect(
			await screen.findByText(
				"Attendance is already marked on this subscription.",
				{ exact: true },
			),
		).toBeInTheDocument();
		await deleteOnce();
		await waitFor(() =>
			expect(router.state.location.pathname).toBe("/scheduling/subscriptions"),
		);
	});

	it("edits teacher, start, price and notes", async () => {
		vi.mocked(schedulingApi.update).mockResolvedValue(subscriptionDetail());
		const user = userEvent.setup();
		renderWithRouter(<SubscriptionActions sub={subscriptionDetail()} />);
		await user.click(await screen.findByRole("button", { name: "Edit" }));
		const dialog = await screen.findByRole("dialog");
		await waitFor(() =>
			expect(
				within(dialog).getByRole("option", { name: "Maryam" }),
			).toBeInTheDocument(),
		);
		await user.selectOptions(within(dialog).getByLabelText(/^Teacher/), "22");
		await user.clear(within(dialog).getByLabelText(/^Price/));
		await user.type(within(dialog).getByLabelText(/^Price/), "999");
		await user.type(within(dialog).getByLabelText("Notes"), "Sibling discount");
		await user.click(within(dialog).getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(schedulingApi.update).toHaveBeenCalledWith(7, {
				teacher: 22,
				starts_on: "2026-06-01",
				price_minor: 99900,
				notes: "Sibling discount",
			}),
		);
	});
});
```

Replace the whole of `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx` with:

```tsx
import { screen } from "@testing-library/react";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { page, subscriptionDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SubscriptionDetail } from "./SubscriptionDetail";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, get: vi.fn() },
	};
});
// The action dialogs load their choices; this suite does not open them.
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, list: vi.fn() },
	};
});

describe("SubscriptionDetail", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(page([]));
		vi.mocked(catalogueApi.list).mockResolvedValue(page([]));
	});

	it("summarises dates, sessions and money", async () => {
		vi.mocked(schedulingApi.get).mockResolvedValue(
			subscriptionDetail({
				ends_on: "2026-07-03",
				paused_days: 3,
				carried_over_sessions: 2,
				sessions_remaining: 3,
				in_grace: true,
			}),
		);
		renderWithRouter(<SubscriptionDetail subscriptionId="7" />);
		expect(await screen.findByText("Monthly")).toBeInTheDocument();
		expect(schedulingApi.get).toHaveBeenCalledWith(7);
		expect(screen.getByText("Jul 3, 2026")).toBeInTheDocument();
		expect(screen.getByText("Includes 3 paused days")).toBeInTheDocument();
		expect(screen.getByText("5 of 8 sessions")).toBeInTheDocument();
		expect(screen.getByText("In grace until Jul 7, 2026")).toBeInTheDocument();
		expect(screen.getByText(/EGP|E£/)).toBeInTheDocument();
	});

	it("shows not-found for a 404 and for a non-numeric id", async () => {
		vi.mocked(schedulingApi.get).mockRejectedValue(
			new AxiosError("Not Found", "404", undefined, undefined, {
				status: 404,
			} as never),
		);
		const { unmount } = renderWithRouter(
			<SubscriptionDetail subscriptionId="99" />,
		);
		expect(
			await screen.findByText("This subscription couldn't be found."),
		).toBeInTheDocument();
		unmount();
		renderWithRouter(<SubscriptionDetail subscriptionId="abc" />);
		expect(
			await screen.findByText("This subscription couldn't be found."),
		).toBeInTheDocument();
		expect(schedulingApi.get).toHaveBeenCalledTimes(1);
	});

	it("shows a load error on a network failure", async () => {
		vi.mocked(schedulingApi.get).mockRejectedValue(new Error("offline"));
		renderWithRouter(<SubscriptionDetail subscriptionId="7" />);
		expect(
			await screen.findByText("Couldn't load this subscription."),
		).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling`
Expected: FAIL — no `./SubscriptionActions`.

- [ ] **Step 3: Implement**

In `dashboard/src/features/scheduling/schemas.ts`, replace:

```ts
	notes: string;
	slots: Slot[];
	pauses: Pause[];
}
```

with:

```ts
	notes: string;
	/** Where a renewal would start by default (spec §4.2). */
	renewal_starts_on: string;
	slots: Slot[];
	pauses: Pause[];
}
```

Append to the end of `dashboard/src/features/scheduling/schemas.ts`:

```ts
export const renewFormSchema = z.object({
	course: pick,
	teacher: pick,
	package: pick,
	starts_on: isoDate,
	price,
});
export type RenewFormValues = z.infer<typeof renewFormSchema>;

export const editFormSchema = z.object({
	teacher: pick,
	starts_on: isoDate,
	price,
	notes: z.string(),
});
export type EditFormValues = z.infer<typeof editFormSchema>;
```

In `dashboard/src/test/scheduling-fixtures.ts`, replace:

```ts
		notes: "",
		slots: [
```

with:

```ts
		notes: "",
		renewal_starts_on: "2026-07-01",
		slots: [
```

Create `dashboard/src/features/scheduling/RenewDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { FormProvider, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { toMajor, toMinor } from "@/lib/money";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	SubmitButton,
} from "@/ui";
import { schedulingApi } from "./api";
import { useChoices } from "./choices";
import { useSchedulingMutation } from "./queries";
import {
	type RenewFormValues,
	renewFormSchema,
	type SubscriptionDetail,
} from "./schemas";
import { TermFields } from "./TermFields";

function defaults(sub: SubscriptionDetail): RenewFormValues {
	return {
		course: String(sub.course.id),
		teacher: String(sub.teacher.id),
		package: String(sub.package.id),
		starts_on: sub.renewal_starts_on,
		// P4-10: the amount paid last time.
		price: toMajor(sub.price_minor, sub.currency),
	};
}

/** Spec §4.2 Renewal, pre-filled; opens the new subscription. */
export function RenewDialog({ sub }: { sub: SubscriptionDetail }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const { packageById } = useChoices();
	const renew = useSchedulingMutation((values: RenewFormValues) =>
		schedulingApi.renew(sub.id, {
			course: Number(values.course),
			teacher: Number(values.teacher),
			package: Number(values.package),
			starts_on: values.starts_on,
			price_minor: toMinor(
				values.price,
				packageById(values.package)?.currency ?? sub.currency,
			),
		}),
	);
	const methods = useForm<RenewFormValues>({
		resolver: zodResolver(renewFormSchema),
		values: defaults(sub),
	});
	const {
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = methods;

	async function onSubmit(values: RenewFormValues) {
		try {
			const renewed = await renew.mutateAsync(values);
			setOpen(false);
			navigate({
				to: "/scheduling/subscriptions/$subscriptionId",
				params: { subscriptionId: String(renewed.id) },
			});
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.price_minor) {
				setError("price", { message: parsed.fieldErrors.price_minor });
			}
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm">{t("scheduling.renew.action")}</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("scheduling.renew.title")}</DialogTitle>
				<DialogDescription>
					{sub.extra_sessions > 0
						? t("scheduling.renew.carries", { count: sub.extra_sessions })
						: t("scheduling.renew.body")}
				</DialogDescription>
				<FormProvider {...methods}>
					<form
						onSubmit={handleSubmit(onSubmit)}
						className="mt-4 flex flex-col gap-4"
						noValidate
					>
						<TermFields idPrefix="renew-" />
						{errors.root?.server ? (
							<Alert variant="destructive">
								<AlertDescription>
									{fieldError(errors.root.server.message)}
								</AlertDescription>
							</Alert>
						) : null}
						<DialogFooter className="mt-0">
							<DialogClose asChild>
								<Button type="button" variant="outline">
									{t("people.cancel")}
								</Button>
							</DialogClose>
							<SubmitButton pending={isSubmitting}>
								{t("scheduling.renew.confirm")}
							</SubmitButton>
						</DialogFooter>
					</form>
				</FormProvider>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/scheduling/EditDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { toMajor, toMinor } from "@/lib/money";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	Select,
	SubmitButton,
	Textarea,
	toast,
} from "@/ui";
import { schedulingApi } from "./api";
import { useChoices } from "./choices";
import { useSchedulingMutation } from "./queries";
import {
	type EditFormValues,
	editFormSchema,
	type SubscriptionDetail,
} from "./schemas";

/** Spec §4.2 Edit: teacher, price, notes and (until attendance) start date. */
export function EditDialog({ sub }: { sub: SubscriptionDetail }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const { teachersFor } = useChoices();
	const save = useSchedulingMutation((values: EditFormValues) =>
		schedulingApi.update(sub.id, {
			teacher: Number(values.teacher),
			starts_on: values.starts_on,
			price_minor: toMinor(values.price, sub.currency),
			notes: values.notes,
		}),
	);
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<EditFormValues>({
		resolver: zodResolver(editFormSchema),
		values: {
			teacher: String(sub.teacher.id),
			starts_on: sub.starts_on,
			price: toMajor(sub.price_minor, sub.currency),
			notes: sub.notes,
		},
	});

	async function onSubmit(values: EditFormValues) {
		try {
			await save.mutateAsync(values);
			setOpen(false);
			toast({ description: t("people.saved"), variant: "success" });
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.price_minor) {
				setError("price", { message: parsed.fieldErrors.price_minor });
			}
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("scheduling.edit.action")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("scheduling.edit.title")}</DialogTitle>
				<DialogDescription>{t("scheduling.edit.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<div className="grid gap-4 sm:grid-cols-2">
						<Field
							id="edit-teacher"
							label={t("scheduling.columns.teacher")}
							error={fieldError(errors.teacher?.message)}
							required
						>
							<Select {...register("teacher")}>
								{teachersFor(String(sub.course.id)).map((p) => (
									<option key={p.id} value={p.id}>
										{p.user.full_name}
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="edit-starts_on"
							label={t("scheduling.summary.startsOn")}
							error={fieldError(errors.starts_on?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("starts_on")} />
						</Field>
						<Field
							id="edit-price"
							label={t("scheduling.form.price", { currency: sub.currency })}
							error={fieldError(errors.price?.message)}
							required
						>
							<Input inputMode="decimal" dir="ltr" {...register("price")} />
						</Field>
					</div>
					<Field
						id="edit-notes"
						label={t("people.field.notes")}
						error={fieldError(errors.notes?.message)}
					>
						<Textarea rows={3} {...register("notes")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>
							{t("people.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/scheduling/SubscriptionActions.tsx`:

```tsx
import { Link, useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { errorText } from "@/lib/form-errors";
import {
	AlertDialog,
	AlertDialogAction,
	AlertDialogCancel,
	AlertDialogContent,
	AlertDialogDescription,
	AlertDialogFooter,
	AlertDialogTitle,
	AlertDialogTrigger,
	Button,
	toast,
} from "@/ui";
import { schedulingApi } from "./api";
import { EditDialog } from "./EditDialog";
import { useSchedulingMutation } from "./queries";
import { RenewDialog } from "./RenewDialog";
import { isLive, type SubscriptionDetail } from "./schemas";

function Confirm({
	action,
	title,
	body,
	onConfirm,
}: {
	action: string;
	title: string;
	body: string;
	onConfirm: () => void;
}) {
	const { t } = useTranslation();
	return (
		<AlertDialog>
			<AlertDialogTrigger asChild>
				<Button size="sm" variant="destructive">
					{action}
				</Button>
			</AlertDialogTrigger>
			<AlertDialogContent>
				<AlertDialogTitle>{title}</AlertDialogTitle>
				<AlertDialogDescription>{body}</AlertDialogDescription>
				<AlertDialogFooter>
					<AlertDialogCancel asChild>
						<Button type="button" variant="outline">
							{t("people.cancel")}
						</Button>
					</AlertDialogCancel>
					<AlertDialogAction asChild>
						<Button type="button" variant="destructive" onClick={onConfirm}>
							{title}
						</Button>
					</AlertDialogAction>
				</AlertDialogFooter>
			</AlertDialogContent>
		</AlertDialog>
	);
}

/** Renew, edit, cancel and delete (spec §6), each shown only when allowed. */
export function SubscriptionActions({ sub }: { sub: SubscriptionDetail }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const cancel = useSchedulingMutation(schedulingApi.cancel);
	const remove = useSchedulingMutation(schedulingApi.remove);
	const live = isLive(sub.status);
	const fail = (error: unknown) =>
		toast({ description: errorText(error, t), variant: "destructive" });

	return (
		<section
			aria-label={t("scheduling.actions")}
			className="flex flex-wrap items-center gap-2"
		>
			{sub.renewal !== null ? (
				<Button asChild size="sm" variant="outline">
					<Link
						to="/scheduling/subscriptions/$subscriptionId"
						params={{ subscriptionId: String(sub.renewal) }}
					>
						{t("scheduling.renew.open")}
					</Link>
				</Button>
			) : sub.status !== "cancelled" ? (
				<RenewDialog sub={sub} />
			) : null}
			{sub.renewed_from !== null ? (
				<Button asChild size="sm" variant="outline">
					<Link
						to="/scheduling/subscriptions/$subscriptionId"
						params={{ subscriptionId: String(sub.renewed_from) }}
					>
						{t("scheduling.renew.previous")}
					</Link>
				</Button>
			) : null}
			{live ? <EditDialog sub={sub} /> : null}
			{live ? (
				<Confirm
					action={t("scheduling.cancel.action")}
					title={t("scheduling.cancel.title")}
					body={t("scheduling.cancel.body")}
					onConfirm={() =>
						cancel.mutate(sub.id, {
							onSuccess: () =>
								toast({
									description: t("scheduling.cancel.done"),
									variant: "success",
								}),
							onError: fail,
						})
					}
				/>
			) : null}
			<Confirm
				action={t("scheduling.delete.action")}
				title={t("scheduling.delete.title")}
				body={t("scheduling.delete.body")}
				onConfirm={() =>
					remove.mutate(sub.id, {
						onSuccess: () => navigate({ to: "/scheduling/subscriptions" }),
						onError: fail,
					})
				}
			/>
		</section>
	);
}
```

In `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, replace:

```tsx
import { useSubscription } from "./queries";
```

with:

```tsx
import { useSubscription } from "./queries";
import { SubscriptionActions } from "./SubscriptionActions";
```

In `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, replace:

```tsx
		<div className="flex flex-col gap-6">
			<Summary sub={sub} />
```

with:

```tsx
		<div className="flex flex-col gap-6">
			<SubscriptionActions sub={sub} />
			<Summary sub={sub} />
```

Merge these keys into `dashboard/src/locales/en/common.json` (nested objects merge into the existing ones; keep the file's tab indentation):

```json
{
	"scheduling": {
		"actions": "Subscription actions",
		"renew": {
			"action": "Renew",
			"title": "Renew subscription",
			"body": "A new term with fresh package numbers and the same weekly slots.",
			"carries": "{{count}} extra sessions from this term will be carried into the renewal and subtracted from it.",
			"confirm": "Renew",
			"open": "Open the renewal",
			"previous": "Open the previous term"
		},
		"edit": {
			"action": "Edit",
			"title": "Edit subscription",
			"body": "A new teacher or start date replaces the sessions nobody has marked yet."
		},
		"cancel": {
			"action": "Cancel subscription",
			"title": "Cancel subscription",
			"body": "Future sessions nobody has marked are removed. Past and marked sessions stay.",
			"done": "Subscription cancelled."
		},
		"delete": {
			"action": "Delete",
			"title": "Delete subscription",
			"body": "Only for mistakes: it goes with its sessions. Not possible once attendance is marked."
		}
	}
}
```

and these into `dashboard/src/locales/ar/common.json`:

```json
{
	"scheduling": {
		"actions": "إجراءات الاشتراك",
		"renew": {
			"action": "جدّد",
			"title": "تجديد الاشتراك",
			"body": "مدة جديدة بأرقام الباقة الحالية والمواعيد الأسبوعية نفسها.",
			"carries": "ستُرحَّل {{count}} حصة إضافية من هذه المدة إلى التجديد وتُخصم منه.",
			"confirm": "جدّد",
			"open": "افتح التجديد",
			"previous": "افتح المدة السابقة"
		},
		"edit": {
			"action": "تعديل",
			"title": "تعديل الاشتراك",
			"body": "تغيير المعلم أو تاريخ البدء يستبدل الحصص التي لم يُسجَّل فيها شيء بعد."
		},
		"cancel": {
			"action": "ألغِ الاشتراك",
			"title": "إلغاء الاشتراك",
			"body": "تُحذف الحصص القادمة التي لم يُسجَّل فيها شيء. تبقى الحصص الماضية والمسجَّلة.",
			"done": "أُلغي الاشتراك."
		},
		"delete": {
			"action": "حذف",
			"title": "حذف الاشتراك",
			"body": "للأخطاء فقط: يُحذف مع حصصه. لا يمكن ذلك بعد تسجيل الحضور."
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src`

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling`
Expected: PASS. Dialog and alert-dialog buttons are found `within(dialog)`, since the trigger and the confirm button share a name.

- [ ] **Step 5: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): renew, edit, cancel and delete a subscription

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Dashboard: slots, pauses and sessions panels

**Files:**
- Create: `dashboard/src/features/scheduling/SlotsPanel.tsx`, `dashboard/src/features/scheduling/PausesPanel.tsx`, `dashboard/src/features/scheduling/SessionsPanel.tsx`, `dashboard/src/features/scheduling/SlotsPanel.test.tsx`, `dashboard/src/features/scheduling/PausesPanel.test.tsx`, `dashboard/src/features/scheduling/SessionsPanel.test.tsx`
- Modify: `dashboard/src/features/scheduling/schemas.ts`, `dashboard/src/features/scheduling/SlotFields.tsx`, `dashboard/src/features/scheduling/SubscriptionDetail.tsx`, `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx`, locales

**Interfaces:**
- Consumes: `SlotFields`, `isLive`, `weekdayName`, `formatDay`, `wallTime`, `studentTime`, `todayIn`, `useAcademySettings`, `useSessions`.
- Produces `slotFormSchema` (`slotGroupSchema` + `meeting_url`: URL or empty) and `pauseFormSchema` (`to_date ≥ from_date`).
- Produces `SlotFields` props `days?: boolean` (false hides the weekday picker for an existing slot) and `meetingUrl?: boolean`.
- Produces `SlotsPanel({sub, studentTime})`, `PausesPanel({sub})`, `SessionsPanel({subscriptionId, academyZone})`; the detail page renders them under the summary.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/scheduling/SlotsPanel.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { subscriptionDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SlotsPanel } from "./SlotsPanel";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			addSlots: vi.fn(),
			updateSlot: vi.fn(),
			deleteSlot: vi.fn(),
		},
	};
});

const riyadh = (time: string) => (time === "18:00" ? "21:00" : null);
const slot = (overrides = {}) => ({
	id: 31,
	weekday: 0,
	start_time: "18:00",
	minutes: 45,
	meeting_url: "",
	is_active: true,
	has_sessions: true,
	...overrides,
});

describe("SlotsPanel", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.updateSlot).mockResolvedValue(subscriptionDetail());
		vi.mocked(schedulingApi.addSlots).mockResolvedValue(subscriptionDetail());
	});

	it("lists slots with the student's time and edits one", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<SlotsPanel sub={subscriptionDetail()} studentTime={riyadh} />,
		);
		expect(
			await screen.findByText("Monday at 18:00, 45 minutes"),
		).toBeInTheDocument();
		expect(screen.getByText("Student's time: 21:00")).toBeInTheDocument();
		// It produced sessions, so it can be stopped but not deleted.
		expect(
			screen.queryByRole("button", { name: "Delete the Monday slot" }),
		).toBeNull();
		await user.click(
			screen.getByRole("button", { name: "Edit the Monday slot" }),
		);
		const dialog = await screen.findByRole("dialog");
		const time = within(dialog).getByLabelText(/^Start time/);
		await user.clear(time);
		await user.type(time, "19:30");
		await user.click(within(dialog).getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(schedulingApi.updateSlot).toHaveBeenCalledWith(31, {
				start_time: "19:30",
				minutes: 45,
				meeting_url: "",
			}),
		);
	});

	it("adds slots for several days", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<SlotsPanel sub={subscriptionDetail()} studentTime={riyadh} />,
		);
		await user.click(await screen.findByRole("button", { name: "Add slots" }));
		const dialog = await screen.findByRole("dialog");
		await user.click(within(dialog).getByLabelText("Tue"));
		await user.click(within(dialog).getByLabelText("Thu"));
		await user.type(within(dialog).getByLabelText(/^Start time/), "18:00");
		expect(
			within(dialog).getByText("Student's time: 21:00"),
		).toBeInTheDocument();
		await user.click(within(dialog).getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(schedulingApi.addSlots).toHaveBeenCalledWith(7, {
				weekdays: [1, 3],
				start_time: "18:00",
				minutes: 45,
				meeting_url: "",
			}),
		);
	});

	it("shows a taken time on the field", async () => {
		vi.mocked(schedulingApi.addSlots).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { start_time: ["There is already a slot at this time."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(
			<SlotsPanel sub={subscriptionDetail()} studentTime={riyadh} />,
		);
		await user.click(await screen.findByRole("button", { name: "Add slots" }));
		const dialog = await screen.findByRole("dialog");
		await user.click(within(dialog).getByLabelText("Mon"));
		await user.type(within(dialog).getByLabelText(/^Start time/), "18:00");
		await user.click(within(dialog).getByRole("button", { name: "Save" }));
		expect(
			await within(dialog).findByText("There is already a slot at this time."),
		).toBeInTheDocument();
	});

	it("stops, restarts and deletes", async () => {
		vi.mocked(schedulingApi.deleteSlot).mockResolvedValue(undefined);
		const user = userEvent.setup();
		renderWithRouter(
			<SlotsPanel
				sub={subscriptionDetail({
					slots: [
						slot(),
						slot({ id: 32, weekday: 2, is_active: false, has_sessions: false }),
					],
				})}
				studentTime={() => null}
			/>,
		);
		// The Wednesday slot is stopped and never produced a session.
		expect(await screen.findByText("Stopped")).toBeInTheDocument();
		await user.click(
			screen.getByRole("button", { name: "Stop the Monday slot" }),
		);
		await waitFor(() =>
			expect(schedulingApi.updateSlot).toHaveBeenCalledWith(31, {
				is_active: false,
			}),
		);
		await user.click(
			screen.getByRole("button", { name: "Restart the Wednesday slot" }),
		);
		await waitFor(() =>
			expect(schedulingApi.updateSlot).toHaveBeenCalledWith(32, {
				is_active: true,
			}),
		);
		await user.click(
			screen.getByRole("button", { name: "Delete the Wednesday slot" }),
		);
		await waitFor(() =>
			expect(schedulingApi.deleteSlot).toHaveBeenCalledWith(32),
		);
	});

	it("offers no changes but stopping on a cancelled subscription", async () => {
		renderWithRouter(
			<SlotsPanel
				sub={subscriptionDetail({ status: "cancelled" })}
				studentTime={() => null}
			/>,
		);
		expect(
			await screen.findByRole("button", { name: "Stop the Monday slot" }),
		).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Add slots" })).toBeNull();
		expect(
			screen.queryByRole("button", { name: "Edit the Monday slot" }),
		).toBeNull();
	});
});
```

Create `dashboard/src/features/scheduling/PausesPanel.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { subscriptionDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { PausesPanel } from "./PausesPanel";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			addPause: vi.fn(),
			endPause: vi.fn(),
			deletePause: vi.fn(),
		},
	};
});

const withPauses = subscriptionDetail({
	status: "paused",
	freeze_days_left: 3,
	pauses: [
		{
			id: 51,
			from_date: "2026-06-01",
			to_date: "2026-06-05",
			reason: "Travel",
			days: 5,
			state: "current",
		},
		{
			id: 52,
			from_date: "2026-06-20",
			to_date: "2026-06-21",
			reason: "",
			days: 2,
			state: "upcoming",
		},
	],
});

describe("PausesPanel", () => {
	beforeEach(() => vi.clearAllMocks());

	it("shows freeze days left, ends the current pause and deletes a future one", async () => {
		vi.mocked(schedulingApi.endPause).mockResolvedValue(subscriptionDetail());
		vi.mocked(schedulingApi.deletePause).mockResolvedValue(undefined);
		const user = userEvent.setup();
		renderWithRouter(<PausesPanel sub={withPauses} />);
		expect(
			await screen.findByText("3 of 10 freeze days left"),
		).toBeInTheDocument();
		expect(screen.getByText("Travel")).toBeInTheDocument();
		await user.click(
			screen.getByRole("button", {
				name: "End the pause Jun 1, 2026 to Jun 5, 2026 (5 days) early",
			}),
		);
		expect(schedulingApi.endPause).toHaveBeenCalledWith(51);
		await user.click(
			screen.getByRole("button", {
				name: "Delete the pause Jun 20, 2026 to Jun 21, 2026 (2 days)",
			}),
		);
		expect(schedulingApi.deletePause).toHaveBeenCalledWith(52);
	});

	it("adds a pause, checking the dates first", async () => {
		vi.mocked(schedulingApi.addPause).mockResolvedValue(subscriptionDetail());
		const user = userEvent.setup();
		renderWithRouter(<PausesPanel sub={subscriptionDetail()} />);
		await user.click(await screen.findByRole("button", { name: "Add pause" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^From/), "2026-06-10");
		await user.type(within(dialog).getByLabelText(/^To/), "2026-06-08");
		await user.click(within(dialog).getByRole("button", { name: "Add pause" }));
		expect(
			await within(dialog).findByText(
				"End the pause on or after its first day.",
			),
		).toBeInTheDocument();
		expect(schedulingApi.addPause).not.toHaveBeenCalled();
		await user.clear(within(dialog).getByLabelText(/^To/));
		await user.type(within(dialog).getByLabelText(/^To/), "2026-06-12");
		await user.type(within(dialog).getByLabelText("Reason"), "Exams");
		await user.click(within(dialog).getByRole("button", { name: "Add pause" }));
		await waitFor(() =>
			expect(schedulingApi.addPause).toHaveBeenCalledWith(7, {
				from_date: "2026-06-10",
				to_date: "2026-06-12",
				reason: "Exams",
			}),
		);
	});

	it("explains a refused pause", async () => {
		vi.mocked(schedulingApi.addPause).mockRejectedValue(
			new AxiosError("Conflict", "409", undefined, undefined, {
				status: 409,
				data: { detail: "Too long.", code: "scheduling.freeze_days_exceeded" },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<PausesPanel sub={subscriptionDetail()} />);
		await user.click(await screen.findByRole("button", { name: "Add pause" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^From/), "2026-06-10");
		await user.type(within(dialog).getByLabelText(/^To/), "2026-06-30");
		await user.click(within(dialog).getByRole("button", { name: "Add pause" }));
		expect(
			await within(dialog).findByText(
				"That is more than the freeze days left.",
			),
		).toBeInTheDocument();
	});

	it("has no actions once the freeze days are used or the term is over", async () => {
		renderWithRouter(
			<PausesPanel sub={{ ...withPauses, status: "expired" }} />,
		);
		expect(await screen.findByText("Travel")).toBeInTheDocument();
		expect(screen.queryByRole("button")).toBeNull();
	});
});
```

Create `dashboard/src/features/scheduling/SessionsPanel.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { page, sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SessionsPanel } from "./SessionsPanel";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, sessions: vi.fn() },
	};
});

describe("SessionsPanel", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.sessions).mockResolvedValue(
			page([
				sessionRow(),
				sessionRow({ id: 42, occurs_on: "2026-06-03", meeting_url: "" }),
			]),
		);
	});

	it("lists upcoming sessions in the academy's clock, then past ones", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<SessionsPanel subscriptionId={7} academyZone="Asia/Riyadh" />,
		);
		const table = await screen.findByRole("table");
		const first = within(table).getAllByRole("row")[1];
		expect(within(first).getByText("Jun 1, 2026")).toBeInTheDocument();
		expect(within(first).getByText("21:00")).toBeInTheDocument();
		expect(
			within(first).getByRole("link", { name: "Meeting link" }),
		).toHaveAttribute("href", "https://meet.test/bilal");
		expect(schedulingApi.sessions).toHaveBeenCalledWith(7, {
			when: "upcoming",
			page: 1,
		});
		await user.click(screen.getByRole("tab", { name: "Past" }));
		await waitFor(() =>
			expect(schedulingApi.sessions).toHaveBeenLastCalledWith(7, {
				when: "past",
				page: 1,
			}),
		);
	});

	it("says when there are none, and when loading failed", async () => {
		vi.mocked(schedulingApi.sessions).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(
			<SessionsPanel subscriptionId={7} academyZone="UTC" />,
		);
		expect(await screen.findByText("No sessions here.")).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.sessions).mockRejectedValueOnce(new Error("x"));
		renderWithRouter(<SessionsPanel subscriptionId={7} academyZone="UTC" />);
		expect(
			await screen.findByText("Couldn't load the sessions."),
		).toBeInTheDocument();
	});
});
```

Replace the whole of `dashboard/src/features/scheduling/SubscriptionDetail.test.tsx` with:

```tsx
import { screen } from "@testing-library/react";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { page, subscriptionDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { SubscriptionDetail } from "./SubscriptionDetail";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, get: vi.fn(), sessions: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
// The action dialogs load their choices; this suite does not open them.
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, list: vi.fn() },
	};
});

describe("SubscriptionDetail", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(page([]));
		vi.mocked(catalogueApi.list).mockResolvedValue(page([]));
		vi.mocked(schedulingApi.sessions).mockResolvedValue(page([]));
		vi.mocked(academyApi.get).mockResolvedValue({
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "en",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
	});

	it("summarises dates, sessions and money", async () => {
		vi.mocked(schedulingApi.get).mockResolvedValue(
			subscriptionDetail({
				ends_on: "2026-07-03",
				paused_days: 3,
				carried_over_sessions: 2,
				sessions_remaining: 3,
				in_grace: true,
			}),
		);
		renderWithRouter(<SubscriptionDetail subscriptionId="7" />);
		expect(await screen.findByText("Monthly")).toBeInTheDocument();
		expect(schedulingApi.get).toHaveBeenCalledWith(7);
		expect(screen.getByText("Jul 3, 2026")).toBeInTheDocument();
		expect(screen.getByText("Includes 3 paused days")).toBeInTheDocument();
		expect(screen.getByText("5 of 8 sessions")).toBeInTheDocument();
		expect(screen.getByText("In grace until Jul 7, 2026")).toBeInTheDocument();
		expect(screen.getByText(/EGP|E£/)).toBeInTheDocument();
		// The panels come with the summary.
		expect(screen.getByText("Monday at 18:00, 45 minutes")).toBeInTheDocument();
		expect(screen.getByText("Student's time: 21:00")).toBeInTheDocument();
		expect(screen.getByText("10 of 10 freeze days left")).toBeInTheDocument();
		expect(await screen.findByText("No sessions here.")).toBeInTheDocument();
	});

	it("shows not-found for a 404 and for a non-numeric id", async () => {
		vi.mocked(schedulingApi.get).mockRejectedValue(
			new AxiosError("Not Found", "404", undefined, undefined, {
				status: 404,
			} as never),
		);
		const { unmount } = renderWithRouter(
			<SubscriptionDetail subscriptionId="99" />,
		);
		expect(
			await screen.findByText("This subscription couldn't be found."),
		).toBeInTheDocument();
		unmount();
		renderWithRouter(<SubscriptionDetail subscriptionId="abc" />);
		expect(
			await screen.findByText("This subscription couldn't be found."),
		).toBeInTheDocument();
		expect(schedulingApi.get).toHaveBeenCalledTimes(1);
	});

	it("shows a load error on a network failure", async () => {
		vi.mocked(schedulingApi.get).mockRejectedValue(new Error("offline"));
		renderWithRouter(<SubscriptionDetail subscriptionId="7" />);
		expect(
			await screen.findByText("Couldn't load this subscription."),
		).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling`
Expected: FAIL — the panels don't exist and the detail page shows no slots.

- [ ] **Step 3: Implement**

Append to the end of `dashboard/src/features/scheduling/schemas.ts`:

```ts
export const slotFormSchema = slotGroupSchema.extend({
	meeting_url: z.union([z.url("scheduling.errors.urlInvalid"), z.literal("")]),
});
export type SlotFormValues = z.infer<typeof slotFormSchema>;

export const pauseFormSchema = z
	.object({ from_date: isoDate, to_date: isoDate, reason: z.string() })
	.refine((p) => p.to_date >= p.from_date, {
		path: ["to_date"],
		message: "scheduling.errors.pauseOrder",
	});
export type PauseFormValues = z.infer<typeof pauseFormSchema>;
```

Replace the whole of `dashboard/src/features/scheduling/SlotFields.tsx` with:

```tsx
import { Controller, get, useFormContext } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { weekdayName } from "@/lib/zoned-time";
import { Checkbox, Field, FormError, Input } from "@/ui";
import { WEEKDAYS } from "./schemas";

/**
 * Weekdays, a start time and minutes for one slot group (spec §6), and the
 * meeting link when `meetingUrl` is set. Lives in a `FormProvider`; `prefix`
 * is the group's path, e.g. `slots.0.` or `""`. `days={false}` hides the
 * weekday picker (an existing slot keeps its day). `studentTime` turns a
 * start time into the student's clock, or null.
 */
export function SlotFields({
	prefix,
	studentTime,
	days = true,
	meetingUrl = false,
}: {
	prefix: string;
	studentTime?: (time: string) => string | null;
	days?: boolean;
	meetingUrl?: boolean;
}) {
	const { t, i18n } = useTranslation();
	const {
		control,
		register,
		watch,
		formState: { errors },
	} = useFormContext();
	const fieldError = useFieldError();
	const error = (name: string) =>
		fieldError(get(errors, `${prefix}${name}`)?.message);
	const theirs = studentTime?.(watch(`${prefix}start_time`) ?? "");
	const id = (name: string) => `${prefix}${name}`;

	return (
		<div className="flex flex-col gap-3">
			<fieldset className={days ? "flex flex-col gap-2" : "hidden"}>
				<legend className="mb-1 text-sm font-medium">
					{t("scheduling.slots.days")}
				</legend>
				<Controller
					control={control}
					name={`${prefix}weekdays`}
					render={({ field }) => (
						<div className="flex flex-wrap gap-3">
							{WEEKDAYS.map((day) => {
								const checked = (field.value as number[]).includes(day);
								return (
									<label
										key={day}
										htmlFor={id(`day-${day}`)}
										className="flex items-center gap-2 text-sm"
									>
										<Checkbox
											id={id(`day-${day}`)}
											checked={checked}
											onCheckedChange={(on) =>
												field.onChange(
													on
														? [...field.value, day].sort((a, b) => a - b)
														: field.value.filter((d: number) => d !== day),
												)
											}
										/>
										{weekdayName(day, i18n.language)}
									</label>
								);
							})}
						</div>
					)}
				/>
				{error("weekdays") ? <FormError>{error("weekdays")}</FormError> : null}
			</fieldset>
			<div className="grid gap-4 sm:grid-cols-2">
				<Field
					id={id("start_time")}
					label={t("scheduling.slots.startTime")}
					error={error("start_time")}
					required
				>
					<Input type="time" dir="ltr" {...register(`${prefix}start_time`)} />
				</Field>
				<Field
					id={id("minutes")}
					label={t("scheduling.slots.minutes")}
					error={error("minutes")}
					required
				>
					<Input
						type="number"
						min={15}
						max={240}
						{...register(`${prefix}minutes`, { valueAsNumber: true })}
					/>
				</Field>
			</div>
			{meetingUrl ? (
				<Field
					id={id("meeting_url")}
					label={t("scheduling.slots.meetingUrl")}
					error={error("meeting_url")}
				>
					<Input type="url" dir="ltr" {...register(`${prefix}meeting_url`)} />
				</Field>
			) : null}
			{theirs ? (
				<p className="text-sm text-muted-foreground">
					{t("scheduling.slots.studentTime", { time: theirs })}
				</p>
			) : null}
		</div>
	);
}
```

Create `dashboard/src/features/scheduling/SlotsPanel.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { Plus } from "lucide-react";
import { type ReactNode, useState } from "react";
import { FormProvider, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors, errorText } from "@/lib/form-errors";
import { weekdayName } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	StatusChip,
	SubmitButton,
	toast,
} from "@/ui";
import { schedulingApi } from "./api";
import { useSchedulingMutation } from "./queries";
import { SlotFields } from "./SlotFields";
import {
	isLive,
	type Slot,
	type SlotFormValues,
	type SubscriptionDetail,
	slotFormSchema,
} from "./schemas";

type StudentClock = (time: string) => string | null;

function SlotDialog({
	title,
	trigger,
	values,
	days,
	studentTime,
	save,
}: {
	title: string;
	trigger: ReactNode;
	values: SlotFormValues;
	days: boolean;
	studentTime: StudentClock;
	save: (values: SlotFormValues) => Promise<unknown>;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const methods = useForm<SlotFormValues>({
		resolver: zodResolver(slotFormSchema),
		values,
	});
	const {
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = methods;

	async function onSubmit(next: SlotFormValues) {
		try {
			await save(next);
			setOpen(false);
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>{trigger}</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{title}</DialogTitle>
				<DialogDescription>
					{t("scheduling.slots.dialogBody")}
				</DialogDescription>
				<FormProvider {...methods}>
					<form
						onSubmit={handleSubmit(onSubmit)}
						className="mt-4 flex flex-col gap-4"
						noValidate
					>
						<SlotFields
							prefix=""
							days={days}
							meetingUrl
							studentTime={studentTime}
						/>
						{errors.root?.server ? (
							<Alert variant="destructive">
								<AlertDescription>
									{fieldError(errors.root.server.message)}
								</AlertDescription>
							</Alert>
						) : null}
						<DialogFooter className="mt-0">
							<DialogClose asChild>
								<Button type="button" variant="outline">
									{t("people.cancel")}
								</Button>
							</DialogClose>
							<SubmitButton pending={isSubmitting}>
								{t("people.save")}
							</SubmitButton>
						</DialogFooter>
					</form>
				</FormProvider>
			</DialogContent>
		</Dialog>
	);
}

/** Spec §6 Slots panel: add, edit, stop (deactivate), restart, delete. */
export function SlotsPanel({
	sub,
	studentTime,
}: {
	sub: SubscriptionDetail;
	studentTime: StudentClock;
}) {
	const { t, i18n } = useTranslation();
	const live = isLive(sub.status);
	const add = useSchedulingMutation((values: SlotFormValues) =>
		schedulingApi.addSlots(sub.id, values),
	);
	const edit = useSchedulingMutation(
		({ slot, values }: { slot: Slot; values: SlotFormValues }) =>
			schedulingApi.updateSlot(slot.id, {
				start_time: values.start_time,
				minutes: values.minutes,
				meeting_url: values.meeting_url,
			}),
	);
	const toggle = useSchedulingMutation((slot: Slot) =>
		schedulingApi.updateSlot(slot.id, { is_active: !slot.is_active }),
	);
	const remove = useSchedulingMutation(schedulingApi.deleteSlot);
	const fail = (error: unknown) =>
		toast({ description: errorText(error, t), variant: "destructive" });

	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
				<CardTitle>{t("scheduling.slots.title")}</CardTitle>
				{live ? (
					<SlotDialog
						title={t("scheduling.slots.add")}
						trigger={
							<Button size="sm" variant="outline">
								<Plus className="size-4" />
								{t("scheduling.slots.add")}
							</Button>
						}
						values={{
							weekdays: [],
							start_time: "",
							minutes: sub.session_minutes,
							meeting_url: "",
						}}
						days
						studentTime={studentTime}
						save={(values) => add.mutateAsync(values)}
					/>
				) : null}
			</CardHeader>
			<CardContent>
				{sub.slots.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("scheduling.slots.none")}
					</p>
				) : (
					<ul className="flex flex-col divide-y divide-border">
						{sub.slots.map((slot) => {
							const day = weekdayName(slot.weekday, i18n.language, "long");
							const theirs = studentTime(slot.start_time);
							return (
								<li
									key={slot.id}
									className="flex flex-wrap items-center justify-between gap-2 py-3"
								>
									<div className="flex flex-col">
										<span className="font-medium">
											{t("scheduling.slots.when", {
												day,
												time: slot.start_time,
												minutes: slot.minutes,
											})}
										</span>
										{theirs ? (
											<span className="text-xs text-muted-foreground">
												{t("scheduling.slots.studentTime", { time: theirs })}
											</span>
										) : null}
									</div>
									<div className="flex flex-wrap items-center gap-2">
										{slot.is_active ? null : (
											<StatusChip>{t("scheduling.slots.stopped")}</StatusChip>
										)}
										{live && slot.is_active ? (
											<SlotDialog
												title={t("scheduling.slots.edit")}
												trigger={
													<Button
														size="sm"
														variant="outline"
														aria-label={t("scheduling.slots.editName", { day })}
													>
														{t("scheduling.slots.edit")}
													</Button>
												}
												values={{
													weekdays: [slot.weekday],
													start_time: slot.start_time,
													minutes: slot.minutes,
													meeting_url: slot.meeting_url,
												}}
												days={false}
												studentTime={studentTime}
												save={(values) => edit.mutateAsync({ slot, values })}
											/>
										) : null}
										{slot.is_active || live ? (
											<Button
												size="sm"
												variant="outline"
												aria-label={t(
													slot.is_active
														? "scheduling.slots.stopName"
														: "scheduling.slots.restartName",
													{ day },
												)}
												onClick={() => toggle.mutate(slot, { onError: fail })}
											>
												{slot.is_active
													? t("scheduling.slots.stop")
													: t("scheduling.slots.restart")}
											</Button>
										) : null}
										{slot.has_sessions ? null : (
											<Button
												size="sm"
												variant="destructive"
												aria-label={t("scheduling.slots.deleteName", { day })}
												onClick={() =>
													remove.mutate(slot.id, { onError: fail })
												}
											>
												{t("scheduling.slots.delete")}
											</Button>
										)}
									</div>
								</li>
							);
						})}
					</ul>
				)}
			</CardContent>
		</Card>
	);
}
```

Create `dashboard/src/features/scheduling/PausesPanel.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { Plus } from "lucide-react";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors, errorText } from "@/lib/form-errors";
import { formatDay } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	StatusChip,
	SubmitButton,
	toast,
} from "@/ui";
import { schedulingApi } from "./api";
import { useSchedulingMutation } from "./queries";
import {
	isLive,
	type PauseFormValues,
	pauseFormSchema,
	type SubscriptionDetail,
} from "./schemas";

function AddPauseDialog({ sub }: { sub: SubscriptionDetail }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const add = useSchedulingMutation((values: PauseFormValues) =>
		schedulingApi.addPause(sub.id, values),
	);
	const {
		register,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<PauseFormValues>({
		resolver: zodResolver(pauseFormSchema),
		defaultValues: { from_date: "", to_date: "", reason: "" },
	});

	async function onSubmit(values: PauseFormValues) {
		try {
			await add.mutateAsync(values);
			reset();
			setOpen(false);
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					<Plus className="size-4" />
					{t("scheduling.pauses.add")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("scheduling.pauses.add")}</DialogTitle>
				<DialogDescription>
					{t("scheduling.pauses.dialogBody")}
				</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="pause-from"
						label={t("scheduling.pauses.from")}
						error={fieldError(errors.from_date?.message)}
						required
					>
						<Input type="date" dir="ltr" {...register("from_date")} />
					</Field>
					<Field
						id="pause-to"
						label={t("scheduling.pauses.to")}
						error={fieldError(errors.to_date?.message)}
						required
					>
						<Input type="date" dir="ltr" {...register("to_date")} />
					</Field>
					<Field
						id="pause-reason"
						label={t("scheduling.pauses.reason")}
						error={fieldError(errors.reason?.message)}
					>
						<Input {...register("reason")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>
							{t("scheduling.pauses.add")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

/** Spec §6 Pauses panel: freeze days left, add, end early, delete. */
export function PausesPanel({ sub }: { sub: SubscriptionDetail }) {
	const { t, i18n } = useTranslation();
	const live = isLive(sub.status);
	const end = useSchedulingMutation(schedulingApi.endPause);
	const remove = useSchedulingMutation(schedulingApi.deletePause);
	const fail = (error: unknown) =>
		toast({ description: errorText(error, t), variant: "destructive" });
	const day = (value: string) => formatDay(value, i18n.language);

	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
				<div className="flex flex-col gap-1">
					<CardTitle>{t("scheduling.pauses.title")}</CardTitle>
					<p className="text-sm text-muted-foreground">
						{t("scheduling.pauses.left", {
							left: sub.freeze_days_left,
							allowed: sub.freeze_days_allowed,
						})}
					</p>
				</div>
				{live && sub.freeze_days_left > 0 ? <AddPauseDialog sub={sub} /> : null}
			</CardHeader>
			<CardContent>
				{sub.pauses.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("scheduling.pauses.none")}
					</p>
				) : (
					<ul className="flex flex-col divide-y divide-border">
						{sub.pauses.map((pause) => {
							const range = t("scheduling.pauses.range", {
								from: day(pause.from_date),
								to: day(pause.to_date),
								count: pause.days,
							});
							return (
								<li
									key={pause.id}
									className="flex flex-wrap items-center justify-between gap-2 py-3"
								>
									<div className="flex flex-col">
										<span className="font-medium">{range}</span>
										{pause.reason ? (
											<span className="text-sm text-muted-foreground">
												{pause.reason}
											</span>
										) : null}
									</div>
									<div className="flex items-center gap-2">
										<StatusChip
											tone={pause.state === "current" ? "live" : "neutral"}
										>
											{t(`scheduling.pauses.state.${pause.state}`)}
										</StatusChip>
										{live && pause.state === "current" ? (
											<Button
												size="sm"
												variant="outline"
												aria-label={t("scheduling.pauses.endName", { range })}
												onClick={() => end.mutate(pause.id, { onError: fail })}
											>
												{t("scheduling.pauses.end")}
											</Button>
										) : null}
										{live && pause.state === "upcoming" ? (
											<Button
												size="sm"
												variant="destructive"
												aria-label={t("scheduling.pauses.deleteName", {
													range,
												})}
												onClick={() =>
													remove.mutate(pause.id, { onError: fail })
												}
											>
												{t("scheduling.pauses.delete")}
											</Button>
										) : null}
									</div>
								</li>
							);
						})}
					</ul>
				)}
			</CardContent>
		</Card>
	);
}
```

Create `dashboard/src/features/scheduling/SessionsPanel.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { formatDay, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import { useSessions } from "./queries";

const PAGE_SIZE = 25;
const TABS = ["upcoming", "past"] as const;

/** Spec §6 Sessions panel: upcoming and past, read-only (attendance is Plan 5). */
export function SessionsPanel({
	subscriptionId,
	academyZone,
}: {
	subscriptionId: number;
	academyZone: string;
}) {
	const { t, i18n } = useTranslation();
	const [when, setWhen] = useState<(typeof TABS)[number]>("upcoming");
	const [page, setPage] = useState(1);
	const { data, isPending, isError } = useSessions(subscriptionId, {
		when,
		page,
	});
	const rows = data?.results ?? [];
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));

	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
				<CardTitle>{t("scheduling.sessions.title")}</CardTitle>
				<div role="tablist" className="flex gap-2">
					{TABS.map((tab) => (
						<button
							key={tab}
							type="button"
							role="tab"
							aria-selected={when === tab}
							onClick={() => {
								setWhen(tab);
								setPage(1);
							}}
							className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
						>
							{t(`scheduling.sessions.${tab}`)}
						</button>
					))}
				</div>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				{isError ? (
					<Alert variant="destructive">
						<AlertDescription>
							{t("scheduling.sessions.loadError")}
						</AlertDescription>
					</Alert>
				) : isPending ? (
					<Spinner />
				) : rows.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						{t("scheduling.sessions.none")}
					</p>
				) : (
					<div className="overflow-x-auto">
						<table className="w-full text-sm">
							<thead className="text-muted-foreground">
								<tr>
									{(["date", "time", "minutes", "status", "link"] as const).map(
										(key) => (
											<th
												key={key}
												scope="col"
												className="p-2 text-start font-medium"
											>
												{t(`scheduling.sessions.columns.${key}`)}
											</th>
										),
									)}
								</tr>
							</thead>
							<tbody>
								{rows.map((session) => (
									<tr key={session.id} className="border-t border-border">
										<td className="p-2">
											{formatDay(session.occurs_on, i18n.language)}
										</td>
										<td className="p-2" dir="ltr">
											{wallTime(
												new Date(session.starts_at),
												academyZone,
												i18n.language,
											)}
										</td>
										<td className="p-2">{session.minutes}</td>
										<td className="p-2">
											{t(`scheduling.sessions.status.${session.status}`)}
										</td>
										<td className="p-2">
											{session.meeting_url ? (
												<a
													href={session.meeting_url}
													target="_blank"
													rel="noreferrer"
													className="text-primary-text underline-offset-4 hover:underline"
												>
													{t("scheduling.sessions.join")}
												</a>
											) : (
												"—"
											)}
										</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
				)}
				<Pager page={page} pages={pages} onChange={setPage} />
			</CardContent>
		</Card>
	);
}
```

Replace the whole of `dashboard/src/features/scheduling/SubscriptionDetail.tsx` with:

```tsx
import { isAxiosError } from "axios";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { formatMoney } from "@/lib/money";
import { formatDay, studentTime, todayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import {
	SubscriptionProgress,
	SubscriptionStatusChip,
	useLocalName,
} from "./bits";
import { PausesPanel } from "./PausesPanel";
import { useSubscription } from "./queries";
import { SessionsPanel } from "./SessionsPanel";
import { SlotsPanel } from "./SlotsPanel";
import { SubscriptionActions } from "./SubscriptionActions";
import type { SubscriptionDetail as Detail } from "./schemas";

function Fact({ label, children }: { label: string; children: ReactNode }) {
	return (
		<div className="flex flex-col gap-0.5">
			<dt className="text-xs text-muted-foreground">{label}</dt>
			<dd className="font-medium">{children}</dd>
		</div>
	);
}

function Summary({ sub }: { sub: Detail }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const day = (value: string) => formatDay(value, i18n.language);
	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
				<CardTitle>{t("scheduling.summary.title")}</CardTitle>
				<SubscriptionStatusChip status={sub.status} />
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
					<Fact label={t("scheduling.columns.student")}>
						{sub.student.full_name}
					</Fact>
					<Fact label={t("scheduling.columns.course")}>
						{localName(sub.course)}
					</Fact>
					<Fact label={t("scheduling.columns.teacher")}>
						{sub.teacher.full_name}
					</Fact>
					<Fact label={t("scheduling.summary.package")}>
						{localName(sub.package)}
					</Fact>
					<Fact label={t("scheduling.summary.startsOn")}>
						{day(sub.starts_on)}
					</Fact>
					<Fact label={t("scheduling.summary.endsOn")}>
						{day(sub.ends_on)}
						{sub.paused_days > 0 ? (
							<span className="block text-xs font-normal text-muted-foreground">
								{t("scheduling.summary.pausedDays", {
									count: sub.paused_days,
								})}
							</span>
						) : null}
					</Fact>
					<Fact label={t("scheduling.summary.graceEndsOn")}>
						{day(sub.grace_ends_on)}
					</Fact>
					<Fact label={t("scheduling.summary.price")}>
						<span dir="ltr">
							{formatMoney(sub.price_minor, sub.currency, i18n.language)}
						</span>
					</Fact>
					<Fact label={t("scheduling.summary.remaining")}>
						{sub.sessions_remaining}
					</Fact>
					<Fact label={t("scheduling.summary.used")}>{sub.sessions_used}</Fact>
					<Fact label={t("scheduling.summary.carried")}>
						{sub.carried_over_sessions}
					</Fact>
					<Fact label={t("scheduling.summary.extra")}>
						{sub.extra_sessions}
					</Fact>
				</dl>
				<SubscriptionProgress
					name={sub.student.full_name}
					used={sub.sessions_used}
					carried={sub.carried_over_sessions}
					total={sub.sessions_total}
					extra={sub.extra_sessions}
				/>
				{sub.in_grace ? (
					<p className="text-sm text-muted-foreground">
						{t("scheduling.inGraceUntil", { date: day(sub.grace_ends_on) })}
					</p>
				) : null}
			</CardContent>
		</Card>
	);
}

export function SubscriptionDetail({
	subscriptionId,
}: {
	subscriptionId: string;
}) {
	const { t, i18n } = useTranslation();
	const { data: academy } = useAcademySettings();
	const parsed = Number(subscriptionId);
	// `/scheduling/subscriptions/abc` is never a subscription: no request.
	const invalidId = !Number.isInteger(parsed) || parsed < 1;
	const {
		data: sub,
		isError,
		error,
	} = useSubscription(invalidId ? undefined : parsed);
	const status = isAxiosError(error) ? error.response?.status : undefined;
	if (invalidId || status === 404 || isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{invalidId || status === 404
						? t("scheduling.notFound")
						: t("scheduling.detailLoadError")}
				</AlertDescription>
			</Alert>
		);
	}
	if (!sub || !academy) return <Spinner />;
	// P4-6: slot times are the academy's clock; show the student's too.
	const timeForStudent = (time: string) =>
		studentTime({
			date: todayIn(academy.timezone),
			time,
			academyZone: academy.timezone,
			studentZone: sub.student.timezone,
			language: i18n.language,
		});
	return (
		<div className="flex flex-col gap-6">
			<SubscriptionActions sub={sub} />
			<Summary sub={sub} />
			<SlotsPanel sub={sub} studentTime={timeForStudent} />
			<PausesPanel sub={sub} />
			<SessionsPanel subscriptionId={sub.id} academyZone={academy.timezone} />
		</div>
	);
}
```

Merge these keys into `dashboard/src/locales/en/common.json` (nested objects merge into the existing ones; keep the file's tab indentation):

```json
{
	"scheduling": {
		"slots": {
			"add": "Add slots",
			"none": "No weekly slots yet.",
			"when": "{{day}} at {{time}}, {{minutes}} minutes",
			"meetingUrl": "Meeting link (empty uses the teacher's)",
			"stopped": "Stopped",
			"edit": "Edit",
			"editName": "Edit the {{day}} slot",
			"stop": "Stop",
			"stopName": "Stop the {{day}} slot",
			"restart": "Restart",
			"restartName": "Restart the {{day}} slot",
			"delete": "Delete",
			"deleteName": "Delete the {{day}} slot",
			"dialogBody": "Times are the academy's clock. Changing a slot replaces its sessions nobody has marked yet."
		},
		"pauses": {
			"title": "Pauses",
			"left": "{{left}} of {{allowed}} freeze days left",
			"none": "No pauses.",
			"add": "Add pause",
			"from": "From",
			"to": "To",
			"reason": "Reason",
			"range": "{{from}} to {{to}} ({{count}} days)",
			"state": {
				"upcoming": "Upcoming",
				"current": "Now",
				"past": "Past"
			},
			"end": "End early",
			"endName": "End the pause {{range}} early",
			"delete": "Delete",
			"deleteName": "Delete the pause {{range}}",
			"dialogBody": "Sessions inside the pause are removed, and the end date moves later by the paused days."
		},
		"sessions": {
			"title": "Sessions",
			"upcoming": "Upcoming",
			"past": "Past",
			"none": "No sessions here.",
			"loadError": "Couldn't load the sessions.",
			"join": "Meeting link",
			"columns": {
				"date": "Date",
				"time": "Time",
				"minutes": "Minutes",
				"status": "Status",
				"link": "Link"
			},
			"status": {
				"scheduled": "Scheduled",
				"completed": "Completed",
				"cancelled": "Cancelled"
			}
		},
		"errors": {
			"urlInvalid": "Enter a full link, like https://meet.example/room.",
			"pauseOrder": "End the pause on or after its first day."
		}
	}
}
```

and these into `dashboard/src/locales/ar/common.json`:

```json
{
	"scheduling": {
		"slots": {
			"add": "أضف مواعيد",
			"none": "لا توجد مواعيد أسبوعية بعد.",
			"when": "{{day}} الساعة {{time}}، {{minutes}} دقيقة",
			"meetingUrl": "رابط اللقاء (فارغ يعني رابط المعلم)",
			"stopped": "متوقف",
			"edit": "تعديل",
			"editName": "عدّل موعد {{day}}",
			"stop": "أوقف",
			"stopName": "أوقف موعد {{day}}",
			"restart": "أعد التشغيل",
			"restartName": "أعد تشغيل موعد {{day}}",
			"delete": "حذف",
			"deleteName": "احذف موعد {{day}}",
			"dialogBody": "الأوقات بتوقيت الأكاديمية. تغيير الموعد يستبدل حصصه التي لم يُسجَّل فيها شيء بعد."
		},
		"pauses": {
			"title": "الإيقافات",
			"left": "متبقٍ {{left}} من {{allowed}} يوم تجميد",
			"none": "لا توجد إيقافات.",
			"add": "أضف إيقافًا",
			"from": "من",
			"to": "إلى",
			"reason": "السبب",
			"range": "من {{from}} إلى {{to}} ({{count}} يوم)",
			"state": {
				"upcoming": "قادم",
				"current": "الآن",
				"past": "منتهٍ"
			},
			"end": "أنهِ مبكرًا",
			"endName": "أنهِ الإيقاف {{range}} مبكرًا",
			"delete": "حذف",
			"deleteName": "احذف الإيقاف {{range}}",
			"dialogBody": "تُحذف الحصص داخل فترة الإيقاف، ويتأخر تاريخ الانتهاء بعدد أيام الإيقاف."
		},
		"sessions": {
			"title": "الحصص",
			"upcoming": "القادمة",
			"past": "الماضية",
			"none": "لا توجد حصص هنا.",
			"loadError": "تعذّر تحميل الحصص.",
			"join": "رابط اللقاء",
			"columns": {
				"date": "التاريخ",
				"time": "الوقت",
				"minutes": "الدقائق",
				"status": "الحالة",
				"link": "الرابط"
			},
			"status": {
				"scheduled": "مجدولة",
				"completed": "مكتملة",
				"cancelled": "ملغاة"
			}
		},
		"errors": {
			"urlInvalid": "أدخل رابطًا كاملًا، مثل https://meet.example/room.",
			"pauseOrder": "اجعل نهاية الإيقاف في يوم بدايته أو بعده."
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src`

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling`
Expected: PASS.

- [ ] **Step 5: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): slots, pauses and sessions panels with the student's local time

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: Dashboard: Today board and Generate for range

**Files:**
- Create: `dashboard/src/features/scheduling/TodayBoard.tsx`, `dashboard/src/features/scheduling/GenerateDialog.tsx`, `dashboard/src/features/scheduling/TodayBoard.test.tsx`, `dashboard/src/features/scheduling/GenerateDialog.test.tsx`, `dashboard/src/routes/_authed/scheduling.today.tsx`
- Modify: `dashboard/src/features/scheduling/schemas.ts`, `dashboard/src/features/scheduling/index.ts`, `dashboard/src/routes/_authed/scheduling.index.tsx`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/features/shell/nav.test.ts`, `dashboard/src/features/shell/AppSidebar.test.tsx`, locales

**Interfaces:**
- Consumes: `useToday`, `schedulingApi.generate`, `SubscriptionProgress`, `studentTime`, `wallTime`.
- Produces `MAX_GENERATE_DAYS = 62`, `generateFormSchema`; `TodayBoard` at `/scheduling/today` (the Scheduling index now redirects there); `GenerateDialog({today, academyZone})`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/scheduling/TodayBoard.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { renderWithRouter } from "@/test/render";
import { todayRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { TodayBoard } from "./TodayBoard";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			today: vi.fn(),
			generate: vi.fn(),
		},
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

describe("TodayBoard", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue({
			timezone: "UTC",
			default_currency: "EGP",
			default_language: "en",
			generation_horizon_days: 14,
			renewal_grace_days: 7,
		});
		vi.mocked(schedulingApi.today).mockResolvedValue({
			date: "2026-06-01",
			rows: [
				todayRow({
					slot_id: 30,
					subscription_id: 8,
					session_id: null,
					state: "missing",
					start_time: "09:00",
					starts_at: "2026-06-01T09:00:00Z",
					student: { id: 12, full_name: "Aisha", timezone: "UTC" },
				}),
				todayRow({ extra_sessions: 1, sessions_used: 9 }),
			],
		});
	});

	it("lists today's slots with the student's time and state", async () => {
		renderWithRouter(<TodayBoard />, {
			extraPaths: ["/scheduling/subscriptions/$subscriptionId"],
		});
		const table = await screen.findByRole("table");
		expect(
			screen.getByText("Slots for Jun 1, 2026, in the academy's time"),
		).toBeInTheDocument();
		const yusuf = within(table).getByRole("row", { name: /Yusuf/ });
		expect(within(yusuf).getByText("18:00")).toBeInTheDocument();
		expect(
			within(yusuf).getByText("Student's time: 21:00"),
		).toBeInTheDocument();
		expect(within(yusuf).getByText("Generated")).toBeInTheDocument();
		expect(within(yusuf).getByText("+1 extra")).toBeInTheDocument();
		expect(within(yusuf).queryByRole("button")).toBeNull();
		const aisha = within(table).getByRole("row", { name: /Aisha/ });
		expect(within(aisha).getByText("Missing")).toBeInTheDocument();
		// Same clock as the academy: no second time.
		expect(within(aisha).queryByText(/Student's time/)).toBeNull();
		expect(within(aisha).getByRole("link", { name: "Aisha" })).toHaveAttribute(
			"href",
			"/scheduling/subscriptions/8",
		);
	});

	it("generates a missing row for its subscription and date", async () => {
		vi.mocked(schedulingApi.generate).mockResolvedValue({
			created: 1,
			skipped_existing: 0,
			skipped_paused: 0,
			skipped_out_of_term: 0,
			conflicts: [],
		});
		const user = userEvent.setup();
		renderWithRouter(<TodayBoard />);
		await user.click(
			await screen.findByRole("button", {
				name: "Generate today's session for Aisha",
			}),
		);
		await waitFor(() =>
			expect(schedulingApi.generate).toHaveBeenCalledWith({
				from: "2026-06-01",
				to: "2026-06-01",
				subscription: 8,
			}),
		);
		await waitFor(() => expect(schedulingApi.today).toHaveBeenCalledTimes(2));
	});

	it("shows an empty day and a load error", async () => {
		vi.mocked(schedulingApi.today).mockResolvedValueOnce({
			date: "2026-06-01",
			rows: [],
		});
		const { unmount } = renderWithRouter(<TodayBoard />);
		expect(await screen.findByText("No slots today.")).toBeInTheDocument();
		unmount();
		vi.mocked(schedulingApi.today).mockRejectedValueOnce(new Error("x"));
		renderWithRouter(<TodayBoard />);
		expect(
			await screen.findByText("Couldn't load today's board."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/scheduling/GenerateDialog.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { sessionRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { GenerateDialog } from "./GenerateDialog";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, generate: vi.fn() },
	};
});

async function open(user: ReturnType<typeof userEvent.setup>) {
	await user.click(
		await screen.findByRole("button", { name: "Generate for range" }),
	);
	return screen.findByRole("dialog");
}

describe("GenerateDialog", () => {
	beforeEach(() => vi.clearAllMocks());

	it("runs a range and lists the double-bookings", async () => {
		vi.mocked(schedulingApi.generate).mockResolvedValue({
			created: 3,
			skipped_existing: 2,
			skipped_paused: 1,
			skipped_out_of_term: 4,
			conflicts: [
				{
					session: sessionRow({
						student: { id: 12, full_name: "Aisha" },
						starts_at: "2026-06-01T18:30:00Z",
					}),
					other: sessionRow(),
				},
			],
		});
		const user = userEvent.setup();
		renderWithRouter(<GenerateDialog today="2026-06-01" academyZone="UTC" />);
		const dialog = await open(user);
		await user.clear(within(dialog).getByLabelText(/^To/));
		await user.type(within(dialog).getByLabelText(/^To/), "2026-06-14");
		await user.click(within(dialog).getByRole("button", { name: "Generate" }));
		await waitFor(() =>
			expect(schedulingApi.generate).toHaveBeenCalledWith({
				from: "2026-06-01",
				to: "2026-06-14",
			}),
		);
		expect(
			await within(dialog).findByText(
				"Created 3. Already there 2. Paused 1. Outside the term 4.",
			),
		).toBeInTheDocument();
		expect(
			within(dialog).getByText(
				"Bilal on Jun 1, 2026: Aisha at 18:30 overlaps Yusuf at 18:00",
			),
		).toBeInTheDocument();
	});

	it("refuses a backwards or too long range before sending", async () => {
		const user = userEvent.setup();
		renderWithRouter(<GenerateDialog today="2026-06-01" academyZone="UTC" />);
		const dialog = await open(user);
		const to = within(dialog).getByLabelText(/^To/);
		await user.clear(to);
		await user.type(to, "2026-05-31");
		await user.click(within(dialog).getByRole("button", { name: "Generate" }));
		expect(
			await within(dialog).findByText("End on or after the start."),
		).toBeInTheDocument();
		await user.clear(to);
		await user.type(to, "2026-08-02"); // 63 days
		await user.click(within(dialog).getByRole("button", { name: "Generate" }));
		expect(
			await within(dialog).findByText("Choose at most 62 days."),
		).toBeInTheDocument();
		await user.clear(to);
		await user.type(to, "2026-08-01"); // exactly 62
		await user.click(within(dialog).getByRole("button", { name: "Generate" }));
		await waitFor(() =>
			expect(schedulingApi.generate).toHaveBeenCalledTimes(1),
		);
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"/",
			"/scheduling/subscriptions",
```

with:

```ts
			"/",
			"/scheduling/today",
			"/scheduling/subscriptions",
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
		expect(groups[2]?.items).toHaveLength(4);
```

with:

```ts
		expect(groups[1]?.items).toHaveLength(2);
		expect(groups[2]?.items).toHaveLength(4);
```

In `dashboard/src/features/shell/AppSidebar.test.tsx`, replace:

```tsx
			screen.getByRole("link", { name: "Subscriptions" }),
		).toBeInTheDocument();
```

with:

```tsx
			screen.getByRole("link", { name: "Subscriptions" }),
		).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "Today" })).toBeInTheDocument();
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling src/features/shell`
Expected: FAIL — no `./TodayBoard`, `./GenerateDialog`, and no Today link.

- [ ] **Step 3: Implement**

Append to the end of `dashboard/src/features/scheduling/schemas.ts`:

```ts
/** Spec §5: an on-demand run covers at most 62 days. */
export const MAX_GENERATE_DAYS = 62;
const DAY_MS = 86_400_000;

export const generateFormSchema = z
	.object({ from: isoDate, to: isoDate })
	.refine((r) => r.to >= r.from, {
		path: ["to"],
		message: "scheduling.errors.rangeOrder",
	})
	.refine(
		(r) =>
			(Date.parse(r.to) - Date.parse(r.from)) / DAY_MS + 1 <= MAX_GENERATE_DAYS,
		{ path: ["to"], message: "scheduling.errors.rangeTooLong" },
	);
export type GenerateFormValues = z.infer<typeof generateFormSchema>;
```

Create `dashboard/src/features/scheduling/GenerateDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { formatDay, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	SubmitButton,
} from "@/ui";
import { schedulingApi } from "./api";
import { useSchedulingMutation } from "./queries";
import {
	type GenerateFormValues,
	type GenerationResult,
	generateFormSchema,
} from "./schemas";

/** Spec §6: generate any range of up to 62 days and show what happened,
 * double-bookings included (P4-9: reported, never blocked). */
export function GenerateDialog({
	today,
	academyZone,
}: {
	today: string;
	academyZone: string;
}) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const [result, setResult] = useState<GenerationResult | null>(null);
	const generate = useSchedulingMutation(schedulingApi.generate);
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<GenerateFormValues>({
		resolver: zodResolver(generateFormSchema),
		values: { from: today, to: today },
	});
	const time = (iso: string) =>
		wallTime(new Date(iso), academyZone, i18n.language);

	async function onSubmit(values: GenerateFormValues) {
		try {
			setResult(await generate.mutateAsync(values));
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog
			open={open}
			onOpenChange={(next) => {
				setOpen(next);
				if (!next) setResult(null);
			}}
		>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("scheduling.generate.action")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("scheduling.generate.title")}</DialogTitle>
				<DialogDescription>{t("scheduling.generate.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<div className="grid gap-4 sm:grid-cols-2">
						<Field
							id="generate-from"
							label={t("scheduling.pauses.from")}
							error={fieldError(errors.from?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("from")} />
						</Field>
						<Field
							id="generate-to"
							label={t("scheduling.pauses.to")}
							error={fieldError(errors.to?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("to")} />
						</Field>
					</div>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					{result ? (
						<section
							aria-live="polite"
							aria-label={t("scheduling.generate.result")}
							className="flex flex-col gap-2 rounded-md bg-secondary p-3 text-sm"
						>
							<p className="font-medium">
								{t("scheduling.generate.summary", {
									created: result.created,
									existing: result.skipped_existing,
									paused: result.skipped_paused,
									outside: result.skipped_out_of_term,
								})}
							</p>
							{result.conflicts.length > 0 ? (
								<>
									<p>
										{t("scheduling.generate.conflicts", {
											count: result.conflicts.length,
										})}
									</p>
									<ul className="list-disc ps-5">
										{result.conflicts.map(({ session, other }) => (
											<li key={`${session.id}-${other.id}`}>
												{t("scheduling.generate.conflict", {
													teacher: session.teacher.full_name,
													date: formatDay(session.occurs_on, i18n.language),
													student: session.student.full_name,
													time: time(session.starts_at),
													other: other.student.full_name,
													otherTime: time(other.starts_at),
												})}
											</li>
										))}
									</ul>
								</>
							) : null}
						</section>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("scheduling.generate.close")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>
							{t("scheduling.generate.run")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/scheduling/TodayBoard.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { CalendarClock } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { errorText } from "@/lib/form-errors";
import { formatDay, studentTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	EmptyState,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { schedulingApi } from "./api";
import { SubscriptionProgress, useLocalName } from "./bits";
import { GenerateDialog } from "./GenerateDialog";
import { useSchedulingMutation, useToday } from "./queries";
import type { TodayRow, TodayState } from "./schemas";

const TONE: Record<TodayState, "live" | "neutral" | "warning"> = {
	generated: "live",
	completed: "neutral",
	cancelled: "neutral",
	missing: "warning",
};

/** Spec §4.3 / §6: today's slots in the academy's clock, with "Generate" on
 * the missing ones. */
export function TodayBoard() {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const { data: academy } = useAcademySettings();
	const { data: board, isPending, isError } = useToday();
	const generate = useSchedulingMutation((row: TodayRow) =>
		schedulingApi.generate({
			from: row.date,
			to: row.date,
			subscription: row.subscription_id,
		}),
	);

	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("scheduling.today.loadError")}</AlertDescription>
			</Alert>
		);
	}
	if (isPending || !academy) return <Spinner />;

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-center justify-between gap-2">
				<p className="text-sm text-muted-foreground">
					{t("scheduling.today.date", {
						date: formatDay(board.date, i18n.language),
					})}
				</p>
				<GenerateDialog today={board.date} academyZone={academy.timezone} />
			</div>
			{board.rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState
							icon={CalendarClock}
							title={t("scheduling.today.empty")}
						/>
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{(
									[
										"time",
										"student",
										"teacher",
										"course",
										"progress",
										"state",
									] as const
								).map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(`scheduling.today.columns.${key}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{board.rows.map((row) => {
								const theirs = studentTime({
									date: row.date,
									time: row.start_time,
									academyZone: academy.timezone,
									studentZone: row.student.timezone,
									language: i18n.language,
								});
								return (
									<tr key={row.slot_id} className="border-t border-border">
										<td className="p-3">
											<span dir="ltr" className="font-medium">
												{row.start_time}
											</span>
											{theirs ? (
												<span className="block text-xs text-muted-foreground">
													{t("scheduling.slots.studentTime", { time: theirs })}
												</span>
											) : null}
										</td>
										<td className="p-3">
											<Link
												to="/scheduling/subscriptions/$subscriptionId"
												params={{ subscriptionId: String(row.subscription_id) }}
												className="font-medium text-primary-text underline-offset-4 hover:underline"
											>
												{row.student.full_name}
											</Link>
										</td>
										<td className="p-3">{row.teacher.full_name}</td>
										<td className="p-3">{localName(row.course)}</td>
										<td className="p-3">
											<SubscriptionProgress
												name={row.student.full_name}
												used={row.sessions_used}
												carried={row.carried_over_sessions}
												total={row.sessions_total}
												extra={row.extra_sessions}
											/>
										</td>
										<td className="p-3">
											<div className="flex flex-wrap items-center gap-2">
												<StatusChip tone={TONE[row.state]}>
													{t(`scheduling.today.state.${row.state}`)}
												</StatusChip>
												{row.state === "missing" ? (
													<Button
														size="sm"
														aria-label={t("scheduling.today.generateName", {
															name: row.student.full_name,
														})}
														disabled={generate.isPending}
														onClick={() =>
															generate.mutate(row, {
																onError: (error) =>
																	toast({
																		description: errorText(error, t),
																		variant: "destructive",
																	}),
															})
														}
													>
														{t("scheduling.today.generate")}
													</Button>
												) : null}
											</div>
										</td>
									</tr>
								);
							})}
						</tbody>
					</table>
				</div>
			)}
		</div>
	);
}
```

Create `dashboard/src/routes/_authed/scheduling.today.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { TodayBoard } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling/today")({
	component: function TodayRoute() {
		const { t } = useTranslation();
		usePageTitle(t("nav.today"));
		return (
			<>
				<PageHeader title={t("nav.today")} />
				<TodayBoard />
			</>
		);
	},
});
```

In `dashboard/src/routes/_authed/scheduling.index.tsx`, replace:

```tsx
throw redirect({ to: "/scheduling/subscriptions" });
```

with:

```tsx
throw redirect({ to: "/scheduling/today" });
```

Replace the whole of `dashboard/src/features/scheduling/index.ts` with:

```ts
export { schedulingApi, subscriptionsCsvUrl } from "./api";
export * from "./queries";
export { SubscriptionDetail } from "./SubscriptionDetail";
export { SubscriptionForm } from "./SubscriptionForm";
export { SubscriptionsList } from "./SubscriptionsList";
export * from "./schemas";
export { TodayBoard } from "./TodayBoard";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
import {
	BookOpen,
```

with:

```ts
import {
	BookOpen,
	CalendarClock,
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	admin("/scheduling/subscriptions", "nav.subscriptions", Repeat, "scheduling"),
```

with:

```ts
	admin("/scheduling/today", "nav.today", CalendarClock, "scheduling"),
	admin("/scheduling/subscriptions", "nav.subscriptions", Repeat, "scheduling"),
```

Merge these keys into `dashboard/src/locales/en/common.json` (nested objects merge into the existing ones; keep the file's tab indentation):

```json
{
	"nav": {
		"today": "Today"
	},
	"scheduling": {
		"today": {
			"date": "Slots for {{date}}, in the academy's time",
			"empty": "No slots today.",
			"loadError": "Couldn't load today's board.",
			"generate": "Generate",
			"generateName": "Generate today's session for {{name}}",
			"columns": {
				"time": "Time",
				"student": "Student",
				"teacher": "Teacher",
				"course": "Course",
				"progress": "Progress",
				"state": "Session"
			},
			"state": {
				"generated": "Generated",
				"missing": "Missing",
				"completed": "Completed",
				"cancelled": "Cancelled"
			}
		},
		"generate": {
			"action": "Generate for range",
			"title": "Generate sessions",
			"body": "Creates the missing sessions of every active slot in these dates, at most 62 days. Existing sessions are left as they are.",
			"run": "Generate",
			"close": "Close",
			"result": "Result",
			"summary": "Created {{created}}. Already there {{existing}}. Paused {{paused}}. Outside the term {{outside}}.",
			"conflicts": "{{count}} double-bookings:",
			"conflict": "{{teacher}} on {{date}}: {{student}} at {{time}} overlaps {{other}} at {{otherTime}}"
		},
		"errors": {
			"rangeOrder": "End on or after the start.",
			"rangeTooLong": "Choose at most 62 days."
		}
	}
}
```

and these into `dashboard/src/locales/ar/common.json`:

```json
{
	"nav": {
		"today": "اليوم"
	},
	"scheduling": {
		"today": {
			"date": "مواعيد {{date}}، بتوقيت الأكاديمية",
			"empty": "لا توجد مواعيد اليوم.",
			"loadError": "تعذّر تحميل لوحة اليوم.",
			"generate": "ولّد",
			"generateName": "ولّد حصة اليوم لـ {{name}}",
			"columns": {
				"time": "الوقت",
				"student": "الطالب",
				"teacher": "المعلم",
				"course": "الدورة",
				"progress": "التقدم",
				"state": "الحصة"
			},
			"state": {
				"generated": "مولَّدة",
				"missing": "ناقصة",
				"completed": "مكتملة",
				"cancelled": "ملغاة"
			}
		},
		"generate": {
			"action": "ولّد لفترة",
			"title": "توليد الحصص",
			"body": "ينشئ الحصص الناقصة لكل موعد نشط في هذه التواريخ، بحد أقصى 62 يومًا. تبقى الحصص الموجودة كما هي.",
			"run": "ولّد",
			"close": "إغلاق",
			"result": "النتيجة",
			"summary": "أُنشئ {{created}}. موجود مسبقًا {{existing}}. موقوف {{paused}}. خارج المدة {{outside}}.",
			"conflicts": "{{count}} تعارضات في المواعيد:",
			"conflict": "{{teacher}} في {{date}}: {{student}} الساعة {{time}} يتداخل مع {{other}} الساعة {{otherTime}}"
		},
		"errors": {
			"rangeOrder": "اجعل النهاية في يوم البداية أو بعده.",
			"rangeTooLong": "اختر 62 يومًا على الأكثر."
		}
	}
}
```

- [ ] **Step 4: Format, regenerate the route tree, then run the tests**

Run (from `dashboard/`): `npx pnpm@10 exec biome check --write src`

Run (from `dashboard/`): `npx pnpm@10 exec vite build`

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/scheduling src/features/shell`
Expected: PASS.

- [ ] **Step 5: Full checks**

Run (from `dashboard/`): `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
Expected: all pass; scheduling files are ≥ 80% lines.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add -A
git -C dashboard commit -m "feat(dashboard): Today board with Generate, and generate-for-range with double-bookings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 16: End-to-end through Caddy, CI, STATE.md

**Files:**
- Create: `dashboard/e2e/subscriptions.spec.ts`
- Modify: `STATE.md` (meta), submodule pointers (meta, after merge)
- CI: no change. The `e2e` job already migrates a fresh database, runs `seed_dev` and then `pnpm e2e`, which picks up every spec in `e2e/`; this flow sends no email and needs no new setting.

**Interfaces:**
- Consumes: the existing `login`, `expectLoggedIn`, `DEMO_URL`, `DEMO_ADMIN` from `e2e/fixtures.ts`; the seeded demo course `Tajweed` taught by `Ustadh Bilal` (Plan 3 seeds); the labels and texts of Tasks 10–15.
- Produces: the spec §8 journey. It makes its own student and a package with 7 freeze days, so it also passes on a dev database seeded before Plan 4.

- [ ] **Step 1: Write the e2e spec**

The demo academy keeps UTC, so the spec reads "today" as the UTC date. Required labels end in `*`, hence the anchored regex queries; dialog buttons that share a name with their trigger are found inside the dialog.

Create `dashboard/e2e/subscriptions.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";

// Spec §8: an admin creates a subscription with two slots, the sessions appear
// on the detail page and on Today, the admin adds a pause, then renews.
// The demo academy keeps UTC (seed_dev), so "today" here is the UTC date.
const DAY_MS = 86_400_000;
const isoDay = (offset: number) =>
	new Date(Date.now() + offset * DAY_MS).toISOString().slice(0, 10);
const weekday = (offset: number) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(Date.now() + offset * DAY_MS),
	);

test("an admin schedules a subscription, pauses it and renews it", async ({
	page,
}) => {
	const stamp = Date.now();
	const student = `E2E Pupil ${stamp}`;
	const pkg = `E2E Monthly ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// A fresh student, and a package with freeze days (required labels end in *)
	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByRole("button", { name: "Save" }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);

	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`شهري ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(pkg);
	await page.getByLabel("Sessions per week").fill("2");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await page.getByLabel("Freeze days allowed").fill("7");
	await page.getByLabel("Price").fill("600");
	await page.getByRole("button", { name: "Save" }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/packages$/);

	// Today's weekday and three days later, late in the day
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new`);
	await page.getByLabel("Find a student").fill(student);
	await page.getByLabel(/^Student/).selectOption({ label: student });
	await page.getByLabel(/^Course/).selectOption({ label: "Tajweed" });
	await page.getByLabel(/^Teacher/).selectOption({ label: "Ustadh Bilal" });
	await page.getByLabel(/^Package/).selectOption({ label: pkg });
	await expect(page.getByLabel(/^Price/)).toHaveValue(/^600/);
	await page.getByLabel(weekday(0), { exact: true }).click();
	await page.getByLabel(weekday(3), { exact: true }).click();
	await page.getByLabel(/^Start time/).fill("23:45");
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);
	const first = page.url();

	// The sessions are on the detail page (a header row plus at least two)...
	await expect(page.getByRole("table").getByRole("row").nth(2)).toBeVisible();

	// ...and today's slot is on the Today board
	await page.goto(`${DEMO_URL}/app/scheduling/today`);
	await expect(
		page.getByRole("row", { name: new RegExp(student) }),
	).toContainText("Generated");

	// A two-day pause from tomorrow
	await page.goto(first);
	await page.getByRole("button", { name: "Add pause" }).click();
	const pause = page.getByRole("dialog");
	await pause.getByLabel(/^From/).fill(isoDay(1));
	await pause.getByLabel(/^To/).fill(isoDay(2));
	await pause.getByRole("button", { name: "Add pause" }).click();
	await expect(page.getByText("5 of 7 freeze days left")).toBeVisible();

	// Renew: the new term opens, linked back to this one
	await page.getByRole("button", { name: "Renew" }).click();
	await page
		.getByRole("dialog")
		.getByRole("button", { name: "Renew" })
		.click();
	await expect(page).not.toHaveURL(first);
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);
	await expect(
		page.getByRole("link", { name: "Open the previous term" }),
	).toBeVisible();
});
```

- [ ] **Step 2: Run it against the local stack**

```bash
just migrate && just seed
just dev-backend
cd dashboard && npx pnpm@10 e2e
```

Expected: `subscriptions.spec.ts` passes together with `people-catalogue.spec.ts`, `academy-sites.spec.ts`, `tenant-login.spec.ts` and `design-preview.spec.ts`. To run only this spec without the Docker stack: start Django on the host (`python manage.py runserver 127.0.0.1:8000` with `DJANGO_SETTINGS_MODULE=config.settings.local`) and `npx pnpm@10 preview --port 4173`, then `E2E_APP_URL=http://demo.etqan.localhost:4173 E2E_DEMO_URL=http://demo.etqan.localhost:4173 npx pnpm@10 exec playwright test e2e/subscriptions.spec.ts` (Vite's preview proxies `/api` to Django with the host header intact).

- [ ] **Step 3: Update `STATE.md`**

Replace the "Where we are" and "Next" sections with:

```markdown
## Where we are

Plan 4 (subscriptions & scheduling, B0 milestone 4) in review: branch `feat/subscriptions-scheduling`
in backend, dashboard and meta (spec `docs/superpowers/specs/2026-09-24-subscriptions-scheduling-design.md`,
plan `docs/superpowers/plans/2026-09-24-plan-4-subscriptions-scheduling.md`). Admins create
subscriptions with weekly slots and pauses, sessions generate ahead, an hourly job per academy
pauses, resumes and expires them, and renewals carry extra sessions over. Today board and
generate-for-range are live; teacher/student/parent screens are Plan 5.

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 5: attendance, session reports and the teacher, student and parent screens. It must use
`scheduling.services` (the `CONSUMING` rule and `untouched_sessions`) rather than re-deriving them.
```

- [ ] **Step 4: Commit (dashboard, then meta) and open PRs**

```bash
git -C dashboard add e2e/subscriptions.spec.ts
git -C dashboard commit -m "test(e2e): subscription with two slots, Today, a pause and a renewal

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C backend push -u origin feat/subscriptions-scheduling
git -C dashboard push -u origin feat/subscriptions-scheduling
git add STATE.md
git commit -m "chore: state for Plan 4 — subscriptions & scheduling

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/subscriptions-scheduling
```

Open one PR per repo: backend → `main`, dashboard → `main`, meta → `master`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Nothing merges without the user's approval. After the submodule PRs merge, bump the meta pointers (`git add backend dashboard`) to the merge commits, commit `chore: bump backend and dashboard for Plan 4 — subscriptions & scheduling` with the trailer above, and push.
