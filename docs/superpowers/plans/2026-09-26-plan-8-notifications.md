# Plan 8 — Notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Students, parents, teachers and admins are told what matters to them without having to look: sessions about to start, lateness, absences, subscriptions running low or expired, invoices issued or overdue, and missing session reports. Every notification shows in the app under a bell with an unread count, is emailed when the recipient has an email address, and is written in the recipient's language and time zone.

**Architecture:** A new tenant app, `etqan.notifications` (N8-1), owns `Notification` and `NotificationSetting`. A Celery beat job, `notifications.scan`, runs every minute (N8-2). In every academy (`for_each_academy`) it:
- runs one finder per enabled type (`finders.py`) against state it reads through new read-only services in scheduling (`services/notices.py`), billing (`services/notices.py`) and identity (`guardians_by_student`, `active_admins`);
- resolves the recipients in bulk (`recipients.py`) and renders each new row once (`text.py`, the one renderer);
- inserts the rows with `bulk_create(ignore_conflicts=True)` on a unique `dedupe_key`;
- queues one `notifications.deliver_email` task per new row after commit (`channels/email.py`, N8-6).

The email task re-reads its row under its own lock, so it never sends twice, and retries three times with backoff. No other app imports notifications (`lint-imports`). The API (`/api/v1/notifications/`) serves each user their own notifications, the unread count, mark-read and read-all, plus admin-only settings. On the dashboard (`features/notifications`):
- a bell in the top bar polls the unread count every 60 s;
- a Notifications page lists everything, with an All/Unread filter;
- a Notifications section on the academy settings page holds the switches and numbers.

A management command, `scan_notifications`, runs the scan on demand (the e2e suite uses it).

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14 / Celery 5.6, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next, Radix DropdownMenu; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-09-26-notifications-design.md` (Phase B0 milestone 8 of `2026-09-24-parity-roadmap-design.md`). It builds on:
- v1 spec `2026-09-23-etqan-tutor-v1-design.md` §4.9 and §6.5;
- Plan 5, `2026-09-25-sessions-attendance-design.md` (attendance, `marked_at`, `missing_reports`), and Plan 4, `2026-09-24-subscriptions-scheduling-design.md` (sessions, `rules.expire`, `derive`);
- Plan 6, `2026-09-25-billing-design.md` (invoices, the `overdue` rule, payers);
- Plan 3, `2026-09-24-people-catalogue-design.md` (roles, guardians, `preferred_language`, `timezone`, the invite);
- Plan 2, `2026-09-23-academy-sites-design.md` (the branded ar/en email layout, `brand_email`).

Where this plan fills a gap in the spec, the Decisions below say so.

**Verified:** the code in Tasks 1–13 was applied by script, in this plan's order and exactly as written here (every `Create`, `replace … with` and `Merge into` block, and the `makemigrations` commands), to fresh copies of `backend@1ca0c80` and `dashboard@7c9bac3` (the current `main` of each). After every task its format, lint, import-contract, type, test and coverage commands passed, and `ruff format --check` found the plan's Python already formatted:
- backend: 1122 → 1245 tests, coverage 97.7% → 97.9%;
- dashboard: 621 → 643 tests, lines 94.1%, branches 87.2%, functions 81.0%.

The e2e suite then passed through Caddy, run the way the CI `e2e` job runs it: Django (`config.settings.local`, the file email backend, eager Celery) and the Vite preview on a freshly migrated and seeded database, plus the marketing server on `:4321` and a `caddy:2.11.4-alpine` edge. That was 17 of 17, `notifications.spec.ts` included (it runs `scan_notifications` through `e2e/manage.ts`), twice on the same database, with no retry. Without the language toggle's change in Task 11, the spec's 320 px check fails at 345 px wide. Migrations are generated with `makemigrations`, so only their timestamps will differ.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), meta repo (trunk `master`).
- The branch `feat/notifications` already exists in the meta repo, `backend/` and `dashboard/`, so do not create it. Check with `git -C backend branch --show-current` and `git -C dashboard branch --show-current` before Task 1 and Task 10.
- Nothing is merged without the user's approval. After merge, bump the submodule pointers in meta.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

**Backend commands**
- Run from `backend/` with the virtualenv `backend/.venv`. Export this environment once per shell:
  `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`
- Tests: `.venv/bin/pytest …`. Add `--create-db` once after each task that adds migrations (Tasks 1, 2 and 3).
- Format: `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`
- Verify: `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE` and `E501` (88 columns): datetimes carry `tzinfo`, booleans are passed by keyword, and only `OSError` is caught for a failed send.

**Dashboard commands**
- Run from `dashboard/` through `npx pnpm@10`.
- Format: `npx pnpm@10 exec biome check --write src e2e`
- New route files are picked up by the TanStack Router plugin. Regenerate `src/routeTree.gen.ts` with `npx pnpm@10 exec vite build` before `tsc`.
- Verify: `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: no hex colour literals and no Tailwind palette utilities anywhere in `src/`, `e2e/` or `scripts/`, comments included. Semantic tokens only.
- `tsc` has `noUnusedLocals`/`noUnusedParameters`.

**Coverage and dev data**
- Coverage gates: backend ≥ 80% (`pytest --cov=etqan`); dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`.
- Academies: `demo` (`admin@demo.test`, timezone UTC, default language Arabic) and `other` (`admin@other.test`).

**Tenancy and module boundaries**
- `etqan.notifications` goes in `TENANT_APPS`. Migrate with `migrate_schemas`.
- The background job loops over academies with `for_each_academy`. The email task enters its academy by schema name (`academy_context`, new in `etqan.platform.tenancy`).
- User-facing URLs come from `etqan.platform.frontend.app_url` (the one `frontend_url` path).
- Business logic lives in `etqan/notifications/services/` and its modules (`finders`, `recipients`, `text`, `links`, `channels/email`). Views parse, call one service, re-read and arrange a payload.
- Notifications reads identity, academy, scheduling and billing only through their `services`, plus `etqan.site.emails` (the branded layout). **No other app imports notifications** (N8-1); the one exception is the dev seed command. `lint-imports` enforces all of this (Tasks 1 and 9).
- Keyword-only flags with no default: `inbox(user, *, unread)`, `notification_row(n, *, role)`, `path_for(*, type_, target_kind, target_id, role)`.

**API and data rules**
- All routes are under `/api/v1/notifications/`.
- Stored instants are UTC. Money is integer minor units plus an ISO 4217 currency; the text shows it as `1,500.00 EGP`.
- Spec values, verbatim:
  - the ten types and their defaults and ranges (§4.2);
  - `email_status` `pending · sent · failed · skipped`;
  - `dedupe_key` `<type>:<object>:<id>[:<occurrence>]:<recipient_id>`;
  - look-back 24 h for event types; `report.missing` 7 days; lateness gives up after 60 min;
  - overdue week `n = (today − due_on − 1) // 7`.
- Errors:
  - a value outside its range, or a value for a type with no number, is `400 {"<type>.value": [...]}` (D11);
  - another user's notification is `404`; settings routes are `403` for non-admins; every route is `403` for anonymous callers.
- `email_status`, `email_error`, `dedupe_key` and `language` never appear in the API.
- Every write answers with a fresh read. Views define only the methods the spec lists, so there is no PUT.
- The list and the unread count have query-count tests; the scanner's query count stays flat as the rows it creates grow.

**Dashboard strings and helpers**
- Every dashboard string is in `src/locales/en/common.json` and `src/locales/ar/common.json`, with no English literal in components. Each task lists the keys it adds; merge them into the existing objects.
- zod messages are i18n keys rendered through `useFieldError`. Server field errors land through `applyServerErrors`.
- Where one accessible name is a substring of another (`Notifications` inside `Notifications, 2 unread`; the toast region is also named `Notifications`), tests match exactly or by role.
- Screens work RTL and at phone width.
- Reuse the shared helpers: `Pager`, `clean`/`Paginated`, `applyServerErrors`/`errorText`, `useFieldError`, `dayIn`/`wallTime` from `@/lib/zoned-time`. No copies inside a feature.
- Pages handle a load error with a translated message.

**Tests**
- Each assertion fails without the code under test.
- Duplicate matches are scoped (`within(item)`, the dropdown menu, the row).
- Cross-academy tests hold data in BOTH academies, with the other academy's pk forced above this one's (`until_pk_exceeds`), and assert this academy's own data.
- Timezone tests put the recipient in a zone whose date or offset differs from UTC's (Asia/Riyadh, Africa/Cairo, Pacific/Auckland) and in a language that differs from the academy's.
- Clocks are pinned together (scheduling's, billing's and notifications' own) to Monday 1 June 2026, 08:00 UTC, except invoices' `created_at`, which is the database's real time (D17).

### Decisions this plan makes where the spec is silent or conflicts with the code

- **D1 — Lock order: notifications locks nothing but its own row.**
  - The scanner only reads other apps and inserts its own rows (`bulk_create(ignore_conflicts=True)`).
  - The settings PATCH writes its own rows without a lock (the last save wins).
  - The email task locks only the one row it sends, with `select_for_update(skip_locked=True, of=("self",))`, so the recipient's user row stays unlocked.
  - Plans 4–7 lock subscriptions, then sessions, invoices, counters and payslips. None of those is ever locked here, so no cycle can form with them.
- **D2 — Reading the other apps.** New read-only services, each taking the scan's one instant, so a scan never mixes two moments. Each is one query with the joins a notice names:
  - scheduling (`services/notices.py`): `sessions_starting(now, within)`, `sessions_running_late(now, after, give_up)`, `absences_marked(since)`, `reports_missing(ended_since)` (on top of Plan 5's `missing_reports`), `subscriptions_running_low(threshold)`, `subscriptions_expired(since)`;
  - billing (`services/notices.py`): `invoices_issued(since)`, and `invoices_overdue(today)` on the one `rules.overdue`;
  - identity: `guardians_by_student(ids)` and `active_admins()`.
  Each finder filters by the spec's window in SQL; notifications never reads another app's models.
- **D3 — `expired_at` and indexes.** `Subscription.expired_at` is set only by `rules.expire`, in the same `UPDATE` as the status, so existing expired subscriptions keep a null and are never announced. New indexes serve the scan's windows: `Session.starts_at`, `Session.marked_at`, `Subscription.expired_at`, `Invoice.created_at`.
- **D4 — `sessions_remaining` for the low finder.** It comes from scheduling's `rules.derive`, the one implementation:
  - the sessions used are counted in SQL, in one grouped query for every active subscription's student;
  - carry-over along renewal chains is chained in memory from that same result.
  The query count is constant (a test pins it). Rewriting carry-over as a recursive SQL expression would restate the rule a second time.
- **D5 — Recipients in bulk.** `recipients.resolve(hits)` makes one guardians query for every hit of the scan and at most one admins query. Only active users are told.
  - "A student with no login (an inactive `User`)": in this code a student without an email address is active, so the rule is that a *student* needs an email address to be told. Guardians of such a student still are.
  - Anyone else without an address gets the in-app row with `email_status = skipped`.
  - A user appears once per hit.
- **D6 — One renderer, one link builder, the branded email.**
  - `text.render(type, facts, *, language, timezone)` fills per-type ar/en templates. Times read `2026-06-01 21:00 (Asia/Riyadh)` on the recipient's clock, money reads `1,500.00 EGP` from minor units (ISO digits), and the title is capped at 200 characters.
  - The language is `preferred_language`, else the academy's `default_language`, and is stored on the row (`language`, not in the API) so the email matches the frozen text.
  - The email body is `templates/email/notifications/message.<lang>.txt` (greeting, body, link) wrapped by Plan 2's `brand_email`. `etqan.site.emails` is the one site module notifications may import.
- **D7 — The email task.** `notifications.deliver_email(schema_name, notification_id)` enters the academy with `academy_context(schema_name)`, new in `etqan.platform.tenancy`. It needs the real academy row: `frontend_url` and `brand_email` read `connection.tenant`.
  - It re-reads the row pending under its own lock, sends through the platform's `send_email_message` (called in-process), and stamps `sent`.
  - "3 tries" means three attempts: the first and two retries (`max_retries=2`), 60 s then 120 s apart. Only `OSError` (SMTP errors are OSErrors) is retried; after the third try the row is `failed` with the error.
  - Emails are queued with `transaction.on_commit`, one per new pending row.
- **D8 — The scan's writes.** `dedupe_key` is `<type>:<target_kind>:<id>[:<occurrence>]:<recipient_id>`; the occurrence is the overdue week `n`. The scan runs a fixed number of queries whatever the number of rows:
  - it reads which candidate keys exist;
  - it renders only the new ones and inserts them with `ignore_conflicts`;
  - it re-reads the new pending ids to queue.
  Rows carry the scan's instant as `created_at`. Two overlapping scans may both queue a row the other inserted; the task's locked re-read sends it once.
- **D9 — Link per role.** `link` is computed when read, from `(type, target_kind, target_id)` and the reader's role (the recipient is the reader). The email uses the same path through `app_url`. The dashboard has no teacher session page and no family subscription page, so:
  - **sessions:** admin `/scheduling/sessions/<id>`; teacher `/teaching/sessions`, or `/teaching/reports` for `report.missing`; student and parent `/learning/sessions`;
  - **subscriptions:** admin `/scheduling/subscriptions/<id>`; student and parent `/learning/subscriptions`;
  - **invoices:** admin `/billing/invoices/<id>`; student and parent `/learning/invoices/<id>`;
  - anything else `/`.
- **D10 — Payloads.** A row is `{id, type, title, body, link, read_at, created_at}`, newest first, 25 a page, with `?unread=1`. `unread-count/` is `{count}`, and `read-all/` is `{count}` marked. `<id>/read/` answers with the fresh row and keeps the first `read_at`. Settings are `[{type, enabled, value}]` in spec order; the PATCH answers with all ten.
- **D11 — Settings defaults and validation.** One catalogue, `kinds.KINDS`, holds each type's default and range (spec §4.2). Missing rows are created with their defaults on first read.
  - PATCH checks every change before writing any.
  - A value outside its range, a null value for a numbered type, or any value for a type with no number is a 400 on `<type>.value` (for example `{"session.late.value": ["Choose a number from 1 to 55."]}`). That is the spec's "400 on value", named per type so the dashboard field gets it.
  - An unknown type is a 400 on `type`.
- **D12 — Beat.** `notifications.scan` runs every minute (`crontab()`), with its own limits: soft 240 s, hard 270 s (like `scheduling.run_daily`'s own limits). A run longer than a minute overlaps the next one harmlessly, and generous limits keep the last academies from starving.
- **D13 — On-demand scans: `manage.py scan_notifications`.** It runs the beat job's function now, prints `ok|failed: <schema>` and exits non-zero on a failure. The e2e test calls it through `child_process` (`e2e/manage.ts`) from the CI job, which has the backend checked out and its environment exported. There is no HTTP endpoint, so nothing test-only is reachable in production.
- **D14 — Boundaries.** A contract forbids every app importing `etqan.notifications`, except the dev seed command (`seed_dev`) and its test. Notifications reaches identity, academy, scheduling and billing only through their services (and `site.emails`).
- **D15 — Seeds.** `seed_notifications` runs only in the demo academy, and only if it has no notification yet.
  - It creates the default settings and runs one scan. The seeded data yields an overdue invoice to Huda, absences to guardians, new invoices and a low subscription.
  - It adds one read and one unread reminder (`add_samples`) for `admin@`, `bilal@`, `yusuf@` and `omar@demo.test`, about the latest session each can see.
  - Their emails go through the dev backend: mailpit locally, files in the e2e job. Under pytest nothing is sent (no commit).
- **D16 — The bell.** It sits in the top bar after the theme toggle, for every role.
  - The unread count polls every 60 s (`refetchInterval`) and on focus.
  - The dropdown reads the latest ten (`page_size=10`) only while open. It offers "Mark all read" (the menu stays open) and "See all" (`/notifications`).
  - Every mark invalidates `["notifications"]`, the one key over the list, the bell and the count.
  - Below `sm` the language toggle shows only its icon, so the top bar still fits 320 px (the e2e test measures it).
- **D17 — Page and settings placement.** `/notifications` is one route for every role, reached from the bell's "See all". It is not in the sidebar, so no role's nav changes. The settings are their own form under the academy settings form, on the same page, because the API is separate. Field names are the types (`session.late.value`), so server errors land on their field. Invoices' `created_at` is the database's real time, not billing's clock, so invoice tests compare against `timezone.now()`.
- **D18 — `mail.ts`.** `latestLink` now searches every email to the address, newest first. An invite followed by a notification (Plan 8) then still yields each link, whatever arrives last.

## Review Focus

- **Double sends.** Overlapping scans, a re-queued email task, or a scan after a delivery must never send a notice twice. Tests:
  - Task 7: `test_repeated_scans_create_and_email_each_notice_once` (on-commit callbacks counted);
  - Task 6: `test_a_requeued_task_never_sends_twice`, `test_a_transient_failure_is_retried`, `test_after_three_tries_the_email_is_failed`;
  - Task 1: `test_one_row_per_dedupe_key`.
- **A flood on first enable.** Turning notifications on for an academy with history must announce nothing old. That covers absences and invoices older than 24 h, subscriptions that expired before Plan 8, and reports missing more than 7 days. Tests:
  - Task 7: `test_enabling_on_an_academy_with_history_sends_no_flood`;
  - Task 5: the look-back edges in `test_an_absence_is_told_to_the_guardians_for_a_day`, `test_an_expiry_is_told_for_a_day`, `test_a_new_invoice_is_told_to_its_payer_for_a_day`, `test_a_missing_report_is_told_to_the_teacher_for_a_week`;
  - Task 2: `test_expired_subscriptions_since_their_expiry`.
- **The wrong recipient.** Another family's guardian, another academy, a deactivated user, a student without a login, or another user reading a notice by id must never receive or see it. Tests:
  - Task 5: `test_another_familys_session_reaches_only_its_own_family`, `test_deactivated_people_are_not_told`, `test_a_student_without_a_login_gets_nothing_but_the_guardians_do`;
  - Task 7: `test_a_scan_writes_only_to_its_own_academy`;
  - Task 8: `test_another_users_notification_is_a_404`, `test_another_academys_notification_is_a_404`, `test_each_role_reads_only_its_own_newest_first`;
  - Task 3: `test_guardians_of_many_students_in_one_query` (inactive guardians left out).
- **A reminder after the start, or for a cancelled session.** A scanner that was down through the window, a session already marked, or one cancelled before its moment must get no reminder, and lateness must stop after an hour or once attendance is marked. Tests:
  - Task 7: `test_a_reminder_never_comes_after_the_start`;
  - Task 5: `test_a_reminder_fires_at_its_moment_and_not_a_minute_early`, `test_a_cancelled_session_gets_no_reminder`, `test_lateness_while_unmarked_and_only_in_the_first_hour`;
  - Task 2: `test_a_reminder_window_opens_at_its_moment_and_closes_at_the_start`.
- **The wrong language or time zone in the text.** A recipient whose language and zone differ from the academy's must read their own language and their own clock, even when the date differs. Tests:
  - Task 7: `test_a_scan_writes_each_recipients_notice_in_their_language_and_zone` (English/Riyadh, Arabic/Cairo, the academy's Arabic/UTC);
  - Task 4: `test_a_session_notice_in_the_recipients_language_and_time_zone` (Auckland, the next day);
  - Task 6: `test_an_arabic_notice_is_emailed_in_arabic`;
  - Task 10: `NotificationsPage` "lists the notifications, the unread ones marked, on the reader's clock".

---

## File Structure

```
backend/
  config/settings/base.py            TENANT_APPS += etqan.notifications; beat notifications.scan every minute
  config/api_router.py               notifications/ → etqan.notifications.api.urls
  pyproject.toml                     contracts: notifications via services only; no app imports notifications
  etqan/platform/tenancy.py          academy_context(schema_name) (+ tests/test_tenancy.py)
  etqan/identity/services.py         guardians_by_student, active_admins (+ tests/test_recipients.py)
  etqan/scheduling/
    models.py                        Subscription.expired_at; indexes (+ migration 0004_notices)
    services/rules.py                expire() stamps expired_at
    services/notices.py              NEW: sessions_starting, sessions_running_late, absences_marked,
                                     reports_missing, subscriptions_running_low, subscriptions_expired
    services/__init__.py             re-exports them
    tests/test_notices.py            NEW; tests/test_lifecycle.py (expired_at)
  etqan/billing/
    models.py                        Invoice created_at index (+ migration 0002_invoice_created_at_index)
    services/notices.py              NEW: invoices_issued, invoices_overdue (+ tests/test_notices.py)
  etqan/notifications/               NEW app
    apps.py clock.py models.py       Notification, NotificationSetting (+ migrations/0001_initial.py)
    kinds.py                         the ten types, targets, defaults and ranges
    text.py                          Facts, render, language_for, money, when (the one renderer)
    links.py                         path_for (the one link builder)
    finders.py                       Hit, FINDERS (one per type), session_hit, overdue_week
    recipients.py                    eligible, resolve (the one resolver)
    channels/email.py                compose, send, give_up, deliver_email (Celery), queue
    services/settings.py             current, update
    services/scan.py                 dedupe_key, store, scan, scan_now, has_notifications, add_samples
    services/inbox.py                inbox, unread_count, get, mark_read, mark_all_read
    services/__init__.py             the public API
    tasks.py                         notifications.scan (beat)
    management/commands/scan_notifications.py
    api/serializers.py payloads.py views.py urls.py
    tests/conftest.py                Clock (three clocks), family, person, subscribe, lesson, notice
    tests/test_settings.py test_text.py test_finders.py test_email.py test_scan.py test_api.py
    tests/test_samples.py
  etqan/templates/email/notifications/message.{en,ar}.txt
  etqan/tenants/management/commands/seed_dev.py   NOTIFIED, seed_notifications (+ tests/test_seed_dev.py)
dashboard/
  src/features/notifications/
    schemas api queries bits          types, TYPE_INFO, calls, hooks, NotificationText
    NotificationsPage                 the full list
    NotificationBell                  the top bar's bell
    NotificationSettingsForm          the academy settings section
    index.ts                          (was empty)
  src/features/shell/AppTopbar.tsx    the bell (+ AppTopbar.test.tsx, AppShell.test.tsx)
  src/ui/locale-toggle.tsx            icon only below sm
  src/routes/_authed/notifications.tsx, settings.academy.tsx
  src/test/notifications-fixtures.ts
  src/locales/{en,ar}/common.json
  e2e/manage.ts, e2e/mail.ts, e2e/notifications.spec.ts
meta: STATE.md, submodule pointers
```

---

### Task 1: Data: the notifications app, its models, the ten kinds, the settings and the import contracts

**Files:**
- Create: `backend/etqan/notifications/__init__.py`, `apps.py`, `clock.py`, `kinds.py`, `models.py`, `migrations/__init__.py`, `services/__init__.py`, `services/settings.py`, and `migrations/0001_initial.py` (generated in Step 4), all under `backend/etqan/notifications/`
- Modify: `backend/config/settings/base.py`, `backend/pyproject.toml`
- Test: `backend/etqan/notifications/tests/__init__.py` (new), `backend/etqan/notifications/tests/conftest.py` (new), `backend/etqan/notifications/tests/test_settings.py` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `etqan.notifications.kinds`: the type names (`EARLY_REMINDER` … `REPORT_MISSING`), the targets `SESSION`, `SUBSCRIPTION`, `INVOICE`, `Kind(type, target, default, low, high)`, `KINDS` (in spec order), `BY_TYPE`, `TYPES`;
  - models `Notification` (`EmailStatus.PENDING/SENT/FAILED/SKIPPED`) and `NotificationSetting` in `etqan.notifications.models`;
  - `etqan.notifications.clock.now() -> datetime`;
  - `etqan.notifications.services.current_settings() -> dict[str, NotificationSetting]` (every type, `KINDS` order, missing rows created with defaults) and `update_settings(changes: list[dict]) -> dict[str, NotificationSetting]` (400 on `<type>.value` or `type`).
- Produces (tests): `etqan.notifications.tests.conftest` with `Clock` (pins scheduling's, billing's and notifications' clocks to Monday 1 June 2026 08:00 UTC), `START`, fixture `family`, and helpers `person(role, name, email=None, **fields)`, `build_family()`, `subscribe(family, *, day, start, student, **overrides)`, `lesson(family, *, day, start, student) -> Session` and `notice(recipient, *, type_, target_id, **fields) -> Notification`.

- [ ] **Step 1: Write the failing tests**

The settings hold one row per type, created with the spec's defaults on first read; a value outside its range changes nothing and is a 400 on that type's value; the database refuses a second row with the same `dedupe_key`.

Create `backend/etqan/notifications/tests/__init__.py`:

```python
"""Notifications tests."""
```

Create `backend/etqan/notifications/tests/conftest.py`:

```python
"""Notifications fixtures. Every clock is pinned together: scheduling's
(sessions), billing's (invoices) and notifications' own (the scan), to Monday
1 June 2026, 08:00 UTC, unless a test moves them. The academy is on UTC and
defaults to Arabic; the family below reads English or lives elsewhere, so a
text test can tell the recipient's language and time zone from the academy's."""

from datetime import date
from datetime import time
from types import SimpleNamespace

import pytest

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.notifications import clock as notifications_clock
from etqan.notifications.models import Notification
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import START
from etqan.scheduling.tests.conftest import Clock as SchedulingClock
from etqan.scheduling.tests.conftest import make_admin

__all__ = ["START"]


class Clock(SchedulingClock):
    def set(self, when) -> None:
        super().set(when)
        # By dotted path: notifications imports only billing's services.
        self._monkeypatch.setattr("etqan.billing.clock.now", lambda: when)
        self._monkeypatch.setattr(notifications_clock, "now", lambda: when)


@pytest.fixture
def clock(monkeypatch):
    return Clock(monkeypatch)


def person(role, name, email=None, **fields):
    return identity_services.create_person(
        role, full_name=name, email=email, invite=False, **fields
    )


def build_family():
    """Teacher Bilal (English, UTC), student Yusuf (English, Asia/Riyadh,
    with a login), his parents Omar (Arabic, Africa/Cairo) and Huda (no email
    address), admin Amina, course Tajweed and a weekly package of 4 x 45
    minutes."""
    teacher = person(
        "teacher",
        "Bilal",
        "bilal@family.test",
        preferred_language="en",
        profile={"gender": "male"},
    )
    student = person(
        "student",
        "Yusuf",
        "yusuf@family.test",
        preferred_language="en",
        timezone="Asia/Riyadh",
    )
    omar = person("parent", "Omar", "omar@family.test", timezone="Africa/Cairo")
    huda = person("parent", "Huda")
    for parent in (omar, huda):
        identity_services.link_guardian(parent, student)
    course = catalogue_services.create_course(
        name_ar="تجويد", name_en="Tajweed", teacher_ids=[teacher.id]
    )
    package = catalogue_services.create_package(
        name_ar="أسبوعي",
        name_en="Weekly",
        sessions_per_week=1,
        session_minutes=45,
        duration_value=28,
        duration_unit="day",
        freeze_days_allowed=0,
        price_minor=150000,
        currency="EGP",
    )
    return SimpleNamespace(
        teacher=teacher,
        student=student,
        omar=omar,
        huda=huda,
        admin=make_admin(),
        course=course,
        package=package,
    )


@pytest.fixture
def family(clock):
    return build_family()


def subscribe(
    family, *, day=date(2026, 6, 1), start=time(10, 0), student=None, **overrides
):
    """A subscription (for ``student``, Yusuf by default) from ``day`` with
    one weekly slot on its weekday at ``start`` (the academy is on UTC)."""
    return scheduling_services.create_subscription(
        student_id=(student or family.student).id,
        course_id=family.course.id,
        teacher_id=family.teacher.id,
        package_id=family.package.id,
        starts_on=day,
        slots=[{"weekdays": [day.weekday()], "start_time": start}],
        **overrides,
    )


def lesson(family, *, day=date(2026, 6, 1), start=time(10, 0), student=None):
    """The session on ``day`` at ``start`` UTC, from a new subscription."""
    subscription = subscribe(family, day=day, start=start, student=student)
    scheduling_services.generate(day, day, subscription=subscription)
    return scheduling_services.sessions_of(subscription).get(occurs_on=day)


def notice(recipient, *, type_="session.reminder", target_id=1, **fields):
    """A stored notification for ``recipient``, as the scanner would leave
    it (pending email), about session ``target_id`` unless told otherwise."""
    kind = "invoice" if type_.startswith("invoice") else type_.split(".")[0]
    kind = "session" if kind == "report" else kind
    values = {
        "recipient": recipient,
        "type": type_,
        "dedupe_key": f"{type_}:{kind}:{target_id}:{recipient.pk}",
        "target_kind": kind,
        "target_id": target_id,
        "language": "en",
        "title": "Starting soon: Tajweed",
        "body": "Tajweed with Yusuf starts at 2026-06-01 10:00 (UTC).",
        **fields,
    }
    return Notification.objects.create(**values)
```

Create `backend/etqan/notifications/tests/test_settings.py`:

```python
import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.notifications import services
from etqan.notifications.models import Notification
from etqan.notifications.models import NotificationSetting
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import make_admin

DEFAULTS = {
    "session.early_reminder": 120,
    "session.reminder": 60,
    "session.teacher_reminder": 30,
    "session.late": 5,
    "session.student_absent": None,
    "subscription.low": 2,
    "subscription.expired": None,
    "invoice.issued": None,
    "invoice.overdue": None,
    "report.missing": None,
}


def as_values(rows):
    return {t: (row.enabled, row.value) for t, row in rows.items()}


def test_the_first_read_creates_every_type_with_its_default():
    assert not NotificationSetting.objects.exists()
    rows = services.current_settings()
    assert list(rows) == list(DEFAULTS)
    assert as_values(rows) == {t: (True, v) for t, v in DEFAULTS.items()}
    assert NotificationSetting.objects.count() == 10
    services.current_settings()
    assert NotificationSetting.objects.count() == 10


def test_a_missing_row_is_created_and_the_others_are_kept():
    services.update_settings([{"type": "session.late", "value": 9}])
    NotificationSetting.objects.filter(type="invoice.issued").delete()
    rows = services.current_settings()
    assert (rows["invoice.issued"].enabled, rows["session.late"].value) == (True, 9)


def test_switches_and_numbers_are_saved():
    rows = services.update_settings(
        [
            {"type": "session.reminder", "enabled": False},
            {"type": "subscription.low", "value": 0},
            {"type": "session.early_reminder", "enabled": True, "value": 1440},
        ]
    )
    assert (rows["session.reminder"].enabled, rows["session.reminder"].value) == (
        False,
        60,
    )
    assert rows["subscription.low"].value == 0
    assert rows["session.early_reminder"].value == 1440


@pytest.mark.parametrize(
    ("type_", "bad", "message"),
    [
        ("session.early_reminder", 29, "Choose a number from 30 to 1440."),
        ("session.early_reminder", 1441, "Choose a number from 30 to 1440."),
        ("session.reminder", 4, "Choose a number from 5 to 720."),
        ("session.teacher_reminder", 721, "Choose a number from 5 to 720."),
        ("session.late", 0, "Choose a number from 1 to 55."),
        ("session.late", 56, "Choose a number from 1 to 55."),
        ("subscription.low", 11, "Choose a number from 0 to 10."),
        ("session.reminder", None, "Choose a number from 5 to 720."),
        ("invoice.overdue", 3, "This notice has no number to set."),
    ],
)
def test_a_value_outside_its_range_changes_nothing(type_, bad, message):
    with pytest.raises(ValidationError) as caught:
        services.update_settings(
            [
                {"type": "session.late", "enabled": False},
                {"type": type_, "value": bad},
            ]
        )
    assert (caught.value.field, caught.value.message) == (f"{type_}.value", message)
    assert services.current_settings()["session.late"].enabled is True


def test_an_unknown_type_is_refused():
    with pytest.raises(ValidationError) as caught:
        services.update_settings([{"type": "session.party", "enabled": False}])
    assert caught.value.field == "type"


def test_one_row_per_dedupe_key():
    user = make_admin()
    fields = {
        "recipient": user,
        "type": "invoice.issued",
        "dedupe_key": f"invoice.issued:invoice:1:{user.pk}",
        "target_kind": "invoice",
        "target_id": 1,
        "language": "en",
        "title": "New invoice",
        "body": "…",
    }
    first = Notification.objects.create(**fields)
    assert (first.email_status, first.read_at) == ("pending", None)
    assert str(first) == f"Notification<invoice.issued, {user.pk}>"
    with pytest.raises(IntegrityError), transaction.atomic():
        Notification.objects.create(**fields)
    assert str(NotificationSetting(type="session.late", value=5)).startswith(
        "NotificationSetting<session.late"
    )
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/notifications -q`

Expected: FAIL — collection errors: `No module named 'etqan.notifications.models'` (the app does not exist yet).

- [ ] **Step 3: Implement**

Create `backend/etqan/notifications/__init__.py`:

```python
"""In-app and email notifications (Plan 8)."""
```

Create `backend/etqan/notifications/apps.py`:

```python
from django.apps import AppConfig


class NotificationsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.notifications"
    label = "notifications"
```

Create `backend/etqan/notifications/clock.py`:

```python
"""The only clock notifications reads, so tests pin it by monkeypatching `now`.

The scanner reads it once per academy and hands that one instant to every
finder, so one scan never mixes two moments."""

from datetime import datetime

from django.utils import timezone


def now() -> datetime:
    """The current instant, timezone-aware UTC."""
    return timezone.now()
```

Create `backend/etqan/notifications/kinds.py`:

```python
"""The ten notices (spec §4.2), in one catalogue: what each is about, its
default number and the range an admin may set. Everything else reads this."""

from dataclasses import dataclass

SESSION = "session"
SUBSCRIPTION = "subscription"
INVOICE = "invoice"
TARGETS = (SESSION, SUBSCRIPTION, INVOICE)

EARLY_REMINDER = "session.early_reminder"
REMINDER = "session.reminder"
TEACHER_REMINDER = "session.teacher_reminder"
LATE = "session.late"
STUDENT_ABSENT = "session.student_absent"
SUBSCRIPTION_LOW = "subscription.low"
SUBSCRIPTION_EXPIRED = "subscription.expired"
INVOICE_ISSUED = "invoice.issued"
INVOICE_OVERDUE = "invoice.overdue"
REPORT_MISSING = "report.missing"


@dataclass(frozen=True)
class Kind:
    type: str
    target: str
    # Minutes for the timed types, sessions for `subscription.low`; None for
    # a type with no number.
    default: int | None
    low: int | None = None
    high: int | None = None


KINDS = (
    Kind(EARLY_REMINDER, SESSION, 120, 30, 1440),
    Kind(REMINDER, SESSION, 60, 5, 720),
    Kind(TEACHER_REMINDER, SESSION, 30, 5, 720),
    Kind(LATE, SESSION, 5, 1, 55),
    Kind(STUDENT_ABSENT, SESSION, None),
    Kind(SUBSCRIPTION_LOW, SUBSCRIPTION, 2, 0, 10),
    Kind(SUBSCRIPTION_EXPIRED, SUBSCRIPTION, None),
    Kind(INVOICE_ISSUED, INVOICE, None),
    Kind(INVOICE_OVERDUE, INVOICE, None),
    Kind(REPORT_MISSING, SESSION, None),
)
BY_TYPE = {kind.type: kind for kind in KINDS}
TYPES = tuple(BY_TYPE)
```

Create `backend/etqan/notifications/models.py`:

```python
"""Notifications (spec §3). Business rules live in
`etqan.notifications.services`; the other apps' data is read only through
their services, so no other app's model is referenced here but the user."""

from django.conf import settings
from django.db import models
from django.utils import timezone

from etqan.notifications.kinds import TARGETS
from etqan.notifications.kinds import TYPES

TYPE_CHOICES = [(value, value) for value in TYPES]


class Notification(models.Model):
    """One per recipient per occurrence (N8-4): the in-app item and the
    record of its email. Title and body are rendered once, in the recipient's
    language, and never change."""

    class EmailStatus(models.TextChoices):
        PENDING = "pending", "Pending"
        SENT = "sent", "Sent"
        FAILED = "failed", "Failed"
        # The recipient has no email address.
        SKIPPED = "skipped", "Skipped"

    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+"
    )
    type = models.CharField(max_length=32, choices=TYPE_CHOICES)
    # `<type>:<object>:<id>[:<occurrence>]:<recipient_id>`: overlapping scans
    # and re-runs never create a second row (N8-2).
    dedupe_key = models.CharField(max_length=200, unique=True)
    target_kind = models.CharField(
        max_length=12, choices=[(value, value) for value in TARGETS]
    )
    target_id = models.BigIntegerField()
    # The language the title and body were rendered in; the email uses it too.
    language = models.CharField(max_length=2)
    title = models.CharField(max_length=200)
    body = models.TextField()
    read_at = models.DateTimeField(null=True, blank=True)
    email_status = models.CharField(
        max_length=7, choices=EmailStatus.choices, default=EmailStatus.PENDING
    )
    email_sent_at = models.DateTimeField(null=True, blank=True)
    email_error = models.TextField(blank=True, default="")
    # The scanner stamps its own instant, so one scan's rows share it.
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [models.Index(fields=["recipient", "read_at", "created_at"])]

    def __str__(self):
        return f"Notification<{self.type}, {self.recipient_id}>"


class NotificationSetting(models.Model):
    """An academy's switch and number for one type (N8-5). Missing rows are
    created with the defaults of `kinds.KINDS` on first read."""

    type = models.CharField(max_length=32, choices=TYPE_CHOICES, unique=True)
    enabled = models.BooleanField(default=True)
    value = models.PositiveSmallIntegerField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"NotificationSetting<{self.type}, {self.enabled}, {self.value}>"
```

Create `backend/etqan/notifications/migrations/__init__.py`:

```python

```

Create `backend/etqan/notifications/services/settings.py`:

```python
"""The academy's notification settings (spec §3.2, §4.2 value ranges)."""

from django.db import transaction

from etqan.notifications.kinds import BY_TYPE
from etqan.notifications.kinds import KINDS
from etqan.notifications.models import NotificationSetting
from etqan.platform.exceptions import ValidationError


def current() -> dict[str, NotificationSetting]:
    """Every type's row, keyed by type, in `KINDS` order. Rows an academy does
    not have yet are created with their defaults first (a concurrent first
    read creates nothing twice: the type is unique)."""
    rows = {row.type: row for row in NotificationSetting.objects.all()}
    missing = [
        NotificationSetting(type=kind.type, enabled=True, value=kind.default)
        for kind in KINDS
        if kind.type not in rows
    ]
    if missing:
        NotificationSetting.objects.bulk_create(missing, ignore_conflicts=True)
        rows = {row.type: row for row in NotificationSetting.objects.all()}
    return {kind.type: rows[kind.type] for kind in KINDS}


def _checked_value(type_: str, value: int | None) -> int:
    kind = BY_TYPE[type_]
    field = f"{type_}.value"
    if kind.default is None:
        raise ValidationError("This notice has no number to set.", field=field)
    if value is None or not kind.low <= value <= kind.high:
        raise ValidationError(
            f"Choose a number from {kind.low} to {kind.high}.", field=field
        )
    return value


@transaction.atomic
def update(changes: list[dict]) -> dict[str, NotificationSetting]:
    """Apply ``[{type, enabled?, value?}]``. Every change is checked before
    any is written, so a bad value changes nothing; a value outside its range,
    or for a type with no number, is a 400 on ``<type>.value``. Plain writes
    of its own rows, no lock: the last save wins. Returns a fresh
    `current()`."""
    rows = current()
    for change in changes:
        if change["type"] not in BY_TYPE:
            raise ValidationError("Unknown notice.", field="type")
        if "value" in change:
            _checked_value(change["type"], change["value"])
    for change in changes:
        fields = {key: change[key] for key in ("enabled", "value") if key in change}
        if fields:
            row = rows[change["type"]]
            for key, value in fields.items():
                setattr(row, key, value)
            row.save(update_fields=[*fields, "updated_at"])
    return current()
```

Create `backend/etqan/notifications/services/__init__.py`:

```python
"""Public API of the notifications module. No other app imports it (N8-1)."""

from etqan.notifications.services.settings import current as current_settings
from etqan.notifications.services.settings import update as update_settings

__all__ = ["current_settings", "update_settings"]
```

In `backend/config/settings/base.py`, replace:

```python
    "etqan.payroll",
]
INSTALLED_APPS = SHARED_APPS + [a for a in TENANT_APPS if a not in SHARED_APPS]
```

with:

```python
    "etqan.payroll",
    "etqan.notifications",
]
INSTALLED_APPS = SHARED_APPS + [a for a in TENANT_APPS if a not in SHARED_APPS]
```

In `backend/pyproject.toml` (1 of 5), replace:

```toml
source_modules = ["etqan.platform"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling", "etqan.billing", "etqan.payroll"]
```

with:

```toml
source_modules = ["etqan.platform"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications"]
```

In `backend/pyproject.toml` (2 of 5), replace:

```toml
source_modules = ["etqan.academy"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.catalogue", "etqan.scheduling", "etqan.billing", "etqan.payroll"]
```

with:

```toml
source_modules = ["etqan.academy"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.catalogue", "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications"]
```

In `backend/pyproject.toml` (3 of 5), replace:

```toml
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.billing", "etqan.payroll"]
forbidden_modules = [
    "etqan.scheduling.models", "etqan.scheduling.api", "etqan.scheduling.dates",
```

with:

```toml
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.billing", "etqan.payroll", "etqan.notifications"]
forbidden_modules = [
    "etqan.scheduling.models", "etqan.scheduling.api", "etqan.scheduling.dates",
```

In `backend/pyproject.toml` (4 of 5), replace:

```toml
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.scheduling"]
forbidden_modules = ["etqan.billing.models", "etqan.billing.api", "etqan.billing.scopes", "etqan.billing.clock"]
```

with:

```toml
source_modules = ["etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants", "etqan.scheduling", "etqan.notifications"]
forbidden_modules = ["etqan.billing.models", "etqan.billing.api", "etqan.billing.scopes", "etqan.billing.clock"]
```

In `backend/pyproject.toml` (5 of 5), replace:

```toml
forbidden_modules = ["etqan.payroll.models", "etqan.payroll.api", "etqan.payroll.scopes", "etqan.payroll.clock"]
allow_indirect_imports = true
```

with:

```toml
forbidden_modules = ["etqan.payroll.models", "etqan.payroll.api", "etqan.payroll.scopes", "etqan.payroll.clock"]
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "notifications reaches other apps only through their services"
type = "forbidden"
source_modules = ["etqan.notifications"]
forbidden_modules = [
    "etqan.identity.models", "etqan.identity.api",
    "etqan.catalogue.models", "etqan.catalogue.api",
    "etqan.academy.models", "etqan.academy.api",
    "etqan.payroll",
    "etqan.tenants",
    # site.emails (the branded layout, Plan 2) is the one site module it uses.
    "etqan.site.models", "etqan.site.api", "etqan.site.services",
]
# notifications.services -> identity.services -> identity.models is the allowed path.
allow_indirect_imports = true

[[tool.importlinter.contracts]]
name = "no app imports notifications"
type = "forbidden"
# N8-1: notifications reads the other apps; none of them calls it.
source_modules = [
    "etqan.platform", "etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site",
    "etqan.tenants", "etqan.scheduling", "etqan.billing", "etqan.payroll",
]
forbidden_modules = ["etqan.notifications"]
```

- [ ] **Step 4: Generate the migration**

Run (from `backend/`):

```bash
.venv/bin/python manage.py makemigrations notifications --settings=config.settings.test
```

Expected: `etqan/notifications/migrations/0001_initial.py` creating `NotificationSetting` and `Notification` (with the unique `dedupe_key` and the index on `recipient, read_at, created_at`).

- [ ] **Step 5: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/notifications -q --create-db
```

Expected: 14 passed.

- [ ] **Step 6: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1136 tests, coverage 97.7% (the gate is 80%).

- [ ] **Step 7: Commit**

```bash
git -C backend add config/settings/base.py pyproject.toml etqan/notifications
git -C backend commit -m "feat(notifications): the notifications app, its models and settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Scheduling: `expired_at`, the notice windows' indexes, and read-only services for notifications

**Files:**
- Create: `backend/etqan/scheduling/services/notices.py`, and `backend/etqan/scheduling/migrations/0004_notices.py` (generated in Step 4)
- Modify: `backend/etqan/scheduling/models.py`, `backend/etqan/scheduling/services/rules.py`, `backend/etqan/scheduling/services/__init__.py`
- Test: `backend/etqan/scheduling/tests/test_notices.py` (new), `backend/etqan/scheduling/tests/test_lifecycle.py` (`test_expiry_stamps_updated_at` becomes `test_expiry_stamps_updated_at_and_expired_at`)

**Interfaces:**
- Consumes: scheduling's own `rules.derive`, `rules.NOT_SET`, `rules.ABSENT`, `reports.missing_reports`, `dates.now`.
- Produces (re-exported from `etqan.scheduling.services`, all read-only):
  - `sessions_starting(*, now: datetime, within: timedelta) -> QuerySet[Session]`;
  - `sessions_running_late(*, now: datetime, after: timedelta, give_up: timedelta) -> QuerySet[Session]`;
  - `absences_marked(*, since: datetime) -> QuerySet[Session]`;
  - `reports_missing(*, ended_since: datetime) -> QuerySet[Session]`;
  - `subscriptions_running_low(threshold: int) -> list[tuple[Subscription, int]]`;
  - `subscriptions_expired(*, since: datetime) -> QuerySet[Subscription]`.
  Session rows come with `student__user`, `teacher__user` and `course`; subscription rows with `student__user` and `course`.
- `Subscription.expired_at` (UTC, nullable), set only by `rules.expire`.

- [ ] **Step 1: Write the failing tests**

Each window opens at its moment and not a minute early, and closes when the spec says. The low read costs the same queries for one subscription or three, and an expiry is stamped.

Create `backend/etqan/scheduling/tests/test_notices.py`:

```python
"""What notifications reads (Plan 8 spec §4.2). The world's Monday and
Wednesday slots start at 18:00 UTC; the clock starts on Monday 1 June 2026,
08:00 UTC."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import timedelta

from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.scheduling import services
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import two_slots

SIX_PM = datetime(2026, 6, 1, 18, 0, tzinfo=UTC)
TWO_HOURS = timedelta(hours=2)
FIVE_MINUTES = timedelta(minutes=5)
HOUR = timedelta(hours=1)
DAY = timedelta(hours=24)


def first_session(subscription):
    return services.sessions_of(subscription).first()


def ids(rows):
    return [row.pk for row in rows]


def test_a_reminder_window_opens_at_its_moment_and_closes_at_the_start(
    subscribe, clock
):
    session = first_session(subscribe(slots=two_slots()))
    assert session.starts_at == SIX_PM

    def starting(now):
        return ids(services.sessions_starting(now=now, within=TWO_HOURS))

    assert starting(SIX_PM - TWO_HOURS - timedelta(minutes=1)) == []
    assert starting(SIX_PM - TWO_HOURS) == [session.pk]
    assert starting(SIX_PM - timedelta(seconds=1)) == [session.pk]
    assert starting(SIX_PM) == []


def test_a_cancelled_session_gets_no_reminder(subscribe, clock):
    session = first_session(subscribe(slots=two_slots()))
    services.cancel_session(session, by=make_admin(), reason="Holiday")
    assert not services.sessions_starting(now=SIX_PM - HOUR, within=TWO_HOURS)


def test_lateness_needs_both_attendances_unmarked_and_gives_up_after_an_hour(
    subscribe, clock
):
    session = first_session(subscribe(slots=two_slots()))

    def late(now):
        return ids(
            services.sessions_running_late(now=now, after=FIVE_MINUTES, give_up=HOUR)
        )

    assert late(SIX_PM + timedelta(minutes=4, seconds=59)) == []
    assert late(SIX_PM + FIVE_MINUTES) == [session.pk]
    assert late(SIX_PM + HOUR - timedelta(seconds=1)) == [session.pk]
    assert late(SIX_PM + HOUR) == []
    clock.set(SIX_PM + timedelta(minutes=6))
    services.mark_attendance(session, by=make_admin(), teacher_attendance="present")
    assert late(SIX_PM + timedelta(minutes=7)) == []


def test_absences_are_read_from_when_they_were_marked(subscribe, clock):
    sub = subscribe(slots=two_slots())
    absent, present = list(services.sessions_of(sub))[:2]
    admin = make_admin()
    clock.set(datetime(2026, 6, 3, 19, 0, tzinfo=UTC))  # both have started
    services.mark_attendance(absent, by=admin, student_attendance="absent")
    services.mark_attendance(present, by=admin, student_attendance="present")
    marked = datetime(2026, 6, 3, 19, 0, tzinfo=UTC)
    assert ids(services.absences_marked(since=marked - DAY)) == [absent.pk]
    assert ids(services.absences_marked(since=marked + timedelta(seconds=1))) == []


def test_missing_reports_only_for_sessions_that_ended_since(subscribe, clock):
    sub = subscribe(slots=two_slots())
    first, second = list(services.sessions_of(sub))[:2]
    admin = make_admin()
    clock.set(datetime(2026, 6, 3, 19, 0, tzinfo=UTC))
    for session in (first, second):
        services.mark_attendance(session, by=admin, student_attendance="present")
    clock.set(datetime(2026, 6, 5, 9, 0, tzinfo=UTC))  # both over a day ago
    # 1 June's ended at 18:45 and 3 June's at 18:45 two days later.
    since = datetime(2026, 6, 2, 0, 0, tzinfo=UTC)
    assert ids(services.reports_missing(ended_since=since)) == [second.pk]
    assert ids(services.reports_missing(ended_since=since - DAY)) == [
        first.pk,
        second.pk,
    ]


def test_subscriptions_running_low_with_their_remaining_sessions(subscribe, clock):
    sub = subscribe(slots=two_slots())
    paused = subscribe(slots=two_slots())
    services.add_pause(paused, from_date=date(2026, 6, 1), to_date=date(2026, 6, 2))
    services.run_lifecycle()  # the pause covers today: `paused` is paused
    assert services.subscriptions_running_low(7) == []
    assert services.subscriptions_running_low(8) == [(sub, 8)]
    clock.set(SIX_PM + HOUR)
    services.mark_attendance(
        first_session(sub), by=make_admin(), student_attendance="present"
    )
    assert services.subscriptions_running_low(7) == [(sub, 7)]


def test_the_low_read_costs_the_same_queries_for_any_number(subscribe, clock):
    subscribe(slots=two_slots())

    def count():
        with CaptureQueriesContext(connection) as ctx:
            services.subscriptions_running_low(8)
        return len(ctx.captured_queries)

    one = count()
    subscribe(slots=two_slots())
    subscribe(slots=two_slots())
    assert count() == one


def test_expired_subscriptions_since_their_expiry(subscribe, clock):
    sub = subscribe()
    old = subscribe()
    job_ran = datetime(2026, 8, 1, 9, tzinfo=UTC)
    clock.set(job_ran)
    services.run_lifecycle()
    # One that expired before Plan 8 has no `expired_at`.
    type(old).objects.filter(pk=old.pk).update(expired_at=None)
    assert ids(services.subscriptions_expired(since=job_ran - DAY)) == [sub.pk]
    assert ids(services.subscriptions_expired(since=job_ran + timedelta(1))) == []
```

In `backend/etqan/scheduling/tests/test_lifecycle.py`, replace:

```python
def test_expiry_stamps_updated_at(subscribe, clock):
    sub = subscribe()
    job_ran = datetime(2026, 8, 1, 9, tzinfo=UTC)
    clock.set(job_ran)
    services.run_lifecycle()
    sub.refresh_from_db()
    assert (sub.status, sub.updated_at) == ("expired", job_ran)
```

with:

```python
def test_expiry_stamps_updated_at_and_expired_at(subscribe, clock):
    sub = subscribe()
    cancelled = subscribe()
    services.cancel_subscription(cancelled)
    job_ran = datetime(2026, 8, 1, 9, tzinfo=UTC)
    clock.set(job_ran)
    services.run_lifecycle()
    sub.refresh_from_db()
    assert (sub.status, sub.updated_at, sub.expired_at) == (
        "expired",
        job_ran,
        job_ran,
    )
    # Plan 8: only an expiry sets it; a cancelled subscription keeps none.
    cancelled.refresh_from_db()
    assert (cancelled.status, cancelled.expired_at) == ("cancelled", None)
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/scheduling/tests/test_notices.py etqan/scheduling/tests/test_lifecycle.py -q`

Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'sessions_starting'` and, in the lifecycle test, `'Subscription' object has no attribute 'expired_at'`.

- [ ] **Step 3: Implement**

In `backend/etqan/scheduling/models.py` (1 of 2), replace:

```python
    notes = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-starts_on", "-id"]
        indexes = [models.Index(fields=["status"])]
```

with:

```python
    notes = models.TextField(blank=True, default="")
    # Plan 8 (spec §3.3): when `rules.expire` ended it, so notifications can
    # announce a recent expiry. Null on subscriptions that expired before.
    expired_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-starts_on", "-id"]
        indexes = [
            models.Index(fields=["status"]),
            # Plan 8: notifications' look-back window on recent expiries.
            models.Index(fields=["expired_at"]),
        ]
```

In `backend/etqan/scheduling/models.py` (2 of 2), replace:

```python
            models.Index(fields=["teacher", "starts_at"]),
            models.Index(fields=["occurs_on"]),
        ]
```

with:

```python
            models.Index(fields=["teacher", "starts_at"]),
            models.Index(fields=["occurs_on"]),
            # Plan 8: notifications' windows on start times and absences.
            models.Index(fields=["starts_at"]),
            models.Index(fields=["marked_at"]),
        ]
```

In `backend/etqan/scheduling/services/rules.py`, replace:

```python
    """End these subscriptions if still live (an admin's cancel in the
    meantime stands); their untouched sessions go (P4-7). Returns how many
    expired."""
    expired = Subscription.objects.filter(
        pk__in=subscription_ids, status__in=LIVE
    ).update(status=Subscription.Status.EXPIRED, updated_at=dates.now())
```

with:

```python
    """End these subscriptions if still live (an admin's cancel in the
    meantime stands); their untouched sessions go (P4-7). ``expired_at``
    records the instant, for notifications (Plan 8 spec §3.3). Returns how
    many expired."""
    now = dates.now()
    expired = Subscription.objects.filter(
        pk__in=subscription_ids, status__in=LIVE
    ).update(status=Subscription.Status.EXPIRED, updated_at=now, expired_at=now)
```

Create `backend/etqan/scheduling/services/notices.py`:

```python
"""What notifications reads about sessions and subscriptions (Plan 8 spec
§4.2). Read-only: each returns rows and changes nothing. Scheduling never
imports notifications; the caller passes the scan's one instant."""

from datetime import datetime
from datetime import timedelta

from django.db.models import QuerySet

from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.services import rules
from etqan.scheduling.services.reports import missing_reports

# What a notice names: the people and the course, joined in the one query.
NOTICE_RELATED = ("student__user", "teacher__user", "course")
SCHEDULED = Session.Status.SCHEDULED


def sessions_starting(*, now: datetime, within: timedelta) -> QuerySet[Session]:
    """Scheduled sessions starting after ``now`` and at most ``within`` later:
    a reminder's window (spec §4.2 types 1 to 3). A session created or moved
    into the window is in it; a started, completed or cancelled one never is."""
    return (
        Session.objects.filter(
            status=SCHEDULED, starts_at__gt=now, starts_at__lte=now + within
        )
        .select_related(*NOTICE_RELATED)
        .order_by("starts_at", "id")
    )


def sessions_running_late(
    *, now: datetime, after: timedelta, give_up: timedelta
) -> QuerySet[Session]:
    """Scheduled sessions that started at least ``after`` and less than
    ``give_up`` ago with neither attendance marked (spec §4.2 type 4)."""
    return (
        Session.objects.filter(
            status=SCHEDULED,
            student_attendance=rules.NOT_SET,
            teacher_attendance=rules.NOT_SET,
            starts_at__lte=now - after,
            starts_at__gt=now - give_up,
        )
        .select_related(*NOTICE_RELATED)
        .order_by("starts_at", "id")
    )


def absences_marked(*, since: datetime) -> QuerySet[Session]:
    """Completed sessions the student missed, last marked at ``since`` or
    later (spec §4.2 type 5)."""
    return (
        Session.objects.filter(
            status=Session.Status.COMPLETED,
            student_attendance=rules.ABSENT,
            marked_at__gte=since,
        )
        .select_related(*NOTICE_RELATED)
        .order_by("marked_at", "id")
    )


def reports_missing(*, ended_since: datetime) -> QuerySet[Session]:
    """`missing_reports` (Plan 5 §4.5) for sessions that ended at
    ``ended_since`` or later (spec §4.2 type 10)."""
    return missing_reports().filter(ends_at__gte=ended_since)


def subscriptions_running_low(threshold: int) -> list[tuple[Subscription, int]]:
    """Active subscriptions with ``sessions_remaining`` at or below
    ``threshold``, with that number, oldest first (spec §4.2 type 6). The
    number comes from `rules.derive`, the one implementation: the sessions
    used are counted in SQL in one query for them all, and carry-over is
    chained in memory from that same result, so the query count does not grow
    with the number of subscriptions."""
    active = list(
        Subscription.objects.filter(status=Subscription.Status.ACTIVE)
        .select_related("student__user", "course")
        .order_by("pk")
    )
    derived = rules.derive(active)
    return [
        (subscription, derived[subscription.pk].sessions_remaining)
        for subscription in active
        if derived[subscription.pk].sessions_remaining <= threshold
    ]


def subscriptions_expired(*, since: datetime) -> QuerySet[Subscription]:
    """Subscriptions the lifecycle expired at ``since`` or later (spec §4.2
    type 7). One expired before Plan 8 has no ``expired_at`` and never
    shows."""
    return (
        Subscription.objects.filter(
            status=Subscription.Status.EXPIRED, expired_at__gte=since
        )
        .select_related("student__user", "course")
        .order_by("expired_at", "id")
    )
```

In `backend/etqan/scheduling/services/__init__.py` (1 of 5), replace:

```python
from etqan.scheduling.services.lifecycle import run_lifecycle
```

with:

```python
from etqan.scheduling.services.lifecycle import run_lifecycle
from etqan.scheduling.services.notices import absences_marked
from etqan.scheduling.services.notices import reports_missing
from etqan.scheduling.services.notices import sessions_running_late
from etqan.scheduling.services.notices import sessions_starting
from etqan.scheduling.services.notices import subscriptions_expired
from etqan.scheduling.services.notices import subscriptions_running_low
```

In `backend/etqan/scheduling/services/__init__.py` (2 of 5), replace:

```python
    "TodayRow",
    "add_pause",
```

with:

```python
    "TodayRow",
    "absences_marked",
    "add_pause",
```

In `backend/etqan/scheduling/services/__init__.py` (3 of 5), replace:

```python
    "renewal_starts_on",
```

with:

```python
    "renewal_starts_on",
    "reports_missing",
```

In `backend/etqan/scheduling/services/__init__.py` (4 of 5), replace:

```python
    "sessions_queryset",
```

with:

```python
    "sessions_queryset",
    "sessions_running_late",
    "sessions_starting",
```

In `backend/etqan/scheduling/services/__init__.py` (5 of 5), replace:

```python
    "subscriptions_queryset",
```

with:

```python
    "subscriptions_expired",
    "subscriptions_queryset",
    "subscriptions_running_low",
```

- [ ] **Step 4: Generate the migration**

Run (from `backend/`):

```bash
.venv/bin/python manage.py makemigrations scheduling --name notices --settings=config.settings.test
```

Expected: `etqan/scheduling/migrations/0004_notices.py`: one `AddField` (`expired_at`) and three `AddIndex` (`Session.starts_at`, `Session.marked_at`, `Subscription.expired_at`).

- [ ] **Step 5: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/scheduling -q --create-db
```

Expected: all pass (8 new in `test_notices.py`).

- [ ] **Step 6: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1144 tests, coverage 97.7% (the gate is 80%).

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/scheduling
git -C backend commit -m "feat(scheduling): expired_at and read-only notice windows for notifications

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Billing and identity: read-only services for notifications

**Files:**
- Create: `backend/etqan/billing/services/notices.py`, and `backend/etqan/billing/migrations/0002_invoice_created_at_index.py` (generated in Step 4)
- Modify: `backend/etqan/billing/models.py`, `backend/etqan/billing/services/__init__.py`, `backend/etqan/identity/services.py`
- Test: `backend/etqan/billing/tests/test_notices.py` (new), `backend/etqan/identity/tests/test_recipients.py` (new)

**Interfaces:**
- Consumes: billing's `rules.overdue` and `rules.VOID`; identity's `Guardianship`.
- Produces:
  - `etqan.billing.services.invoices_issued(*, since: datetime) -> QuerySet[Invoice]` (not void, `created_at >= since`, with `payer` and `student__user`);
  - `etqan.billing.services.invoices_overdue(*, today: date) -> QuerySet[Invoice]` (the one `overdue` rule, same joins);
  - `etqan.identity.services.guardians_by_student(student_profile_ids) -> dict[int, list[User]]` (active guardians, earliest-linked first, one query);
  - `etqan.identity.services.active_admins() -> list[User]`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/billing/tests/test_notices.py`:

```python
"""What notifications reads about invoices (Plan 8 spec §4.2)."""

from datetime import date
from datetime import timedelta

from django.utils import timezone

from etqan.billing import services
from etqan.billing.tests.conftest import make_parent
from etqan.billing.tests.test_invoices import invoice_for
from etqan.billing.tests.test_invoices import pay


def ids(rows):
    return [row.pk for row in rows]


def test_new_invoices_are_read_by_when_they_were_created(world, admin):
    make_parent("Omar", world.student)
    kept = invoice_for(world, admin)
    voided = invoice_for(world, admin)
    services.void_invoice(voided, by=admin)
    # `created_at` is the database's real time, not the pinned clock.
    created = timezone.now()
    rows = services.invoices_issued(since=created - timedelta(hours=24))
    assert ids(rows) == [kept.pk]
    assert rows[0].payer.full_name == "Omar"
    assert rows[0].student.user.full_name == "Yusuf"
    assert not services.invoices_issued(since=created + timedelta(minutes=1))


def test_overdue_invoices_follow_the_one_rule(world, admin):
    due = invoice_for(world, admin, due_on=date(2026, 6, 8))
    partial = invoice_for(world, admin, due_on=date(2026, 6, 8))
    paid = invoice_for(world, admin, due_on=date(2026, 6, 8))
    later = invoice_for(world, admin, due_on=date(2026, 6, 9))
    pay(partial, admin, 400)
    pay(paid, admin, 1000)
    assert not services.invoices_overdue(today=date(2026, 6, 8))
    assert ids(services.invoices_overdue(today=date(2026, 6, 9))) == [
        due.pk,
        partial.pk,
    ]
    assert later.pk in ids(services.invoices_overdue(today=date(2026, 6, 10)))
```

Create `backend/etqan/identity/tests/test_recipients.py`:

```python
"""The bulk reads Plan 8's notifications use to find recipients."""

from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.identity import services
from etqan.identity.models import User


def person(role, name, **fields):
    return services.create_person(role, full_name=name, invite=False, **fields)


def test_guardians_of_many_students_in_one_query():
    yusuf, aisha, zaid = (person("student", n) for n in ("Yusuf", "Aisha", "Zaid"))
    omar, huda, gone = (person("parent", n) for n in ("Omar", "Huda", "Gone"))
    services.link_guardian(huda, yusuf)
    services.link_guardian(omar, yusuf)
    services.link_guardian(omar, aisha)
    services.link_guardian(gone, zaid)
    services.deactivate(gone, by=None)
    profiles = {u.full_name: u.student_profile.pk for u in (yusuf, aisha, zaid)}
    with CaptureQueriesContext(connection) as ctx:
        guardians = services.guardians_by_student(profiles.values())
        names = {
            student: [user.full_name for user in guardians.get(pk, [])]
            for student, pk in profiles.items()
        }
    # One SELECT (django-tenants may first reset the search path).
    selects = [q for q in ctx.captured_queries if q["sql"].startswith("SELECT")]
    assert len(selects) == 1
    # Earliest-linked first; a deactivated guardian is left out.
    assert names == {"Yusuf": ["Huda", "Omar"], "Aisha": ["Omar"], "Zaid": []}


def test_active_admins_only():
    first = User.objects.create_user(email="a1@x.test", role="admin")
    second = User.objects.create_user(email="a2@x.test", role="admin")
    User.objects.create_user(email="a3@x.test", role="admin", is_active=False)
    User.objects.create_user(email="t1@x.test", role="teacher")
    assert services.active_admins() == [first, second]
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/billing/tests/test_notices.py etqan/identity/tests/test_recipients.py -q`

Expected: FAIL — `AttributeError: module 'etqan.billing.services' has no attribute 'invoices_issued'`, and the same for `guardians_by_student` and `active_admins`.

- [ ] **Step 3: Implement**

Create `backend/etqan/billing/services/notices.py`:

```python
"""What notifications reads about invoices (Plan 8 spec §4.2 types 8 and 9).
Read-only; billing never imports notifications."""

from datetime import date
from datetime import datetime

from django.db.models import QuerySet

from etqan.billing.models import Invoice
from etqan.billing.services import rules

# What a notice names: the payer and the student, joined in the one query.
NOTICE_RELATED = ("payer", "student__user")


def invoices_issued(*, since: datetime) -> QuerySet[Invoice]:
    """Invoices created at ``since`` or later that are not void, oldest
    first."""
    return (
        Invoice.objects.filter(created_at__gte=since)
        .exclude(status=rules.VOID)
        .select_related(*NOTICE_RELATED)
        .order_by("created_at", "id")
    )


def invoices_overdue(*, today: date) -> QuerySet[Invoice]:
    """Invoices overdue on the academy's ``today``: `rules.overdue`, the one
    rule (unpaid or partly paid, due before today), soonest due first."""
    return (
        Invoice.objects.filter(rules.overdue(today))
        .select_related(*NOTICE_RELATED)
        .order_by("due_on", "id")
    )
```

In `backend/etqan/billing/services/__init__.py` (1 of 2), replace:

```python
from etqan.billing.services.invoices import void_invoice
```

with:

```python
from etqan.billing.services.invoices import void_invoice
from etqan.billing.services.notices import invoices_issued
from etqan.billing.services.notices import invoices_overdue
```

In `backend/etqan/billing/services/__init__.py` (2 of 2), replace:

```python
    "invoice_subscription",
    "invoices_queryset",
```

with:

```python
    "invoice_subscription",
    "invoices_issued",
    "invoices_overdue",
    "invoices_queryset",
```

In `backend/etqan/billing/models.py`, replace:

```python
        indexes = [models.Index(fields=["status", "due_on"])]
```

with:

```python
        indexes = [
            models.Index(fields=["status", "due_on"]),
            # Plan 8: notifications' look-back window on new invoices.
            models.Index(fields=["created_at"]),
        ]
```

In `backend/etqan/identity/services.py`, replace:

```python
def children_of(parent: User) -> list[User]:
```

with:

```python
def guardians_by_student(student_profile_ids) -> dict[int, list[User]]:
    """Every listed student's active guardians, keyed by StudentProfile id,
    the earliest-linked first, in ONE query (Plan 8's recipients). A student
    with none is absent from the mapping."""
    links = (
        Guardianship.objects.filter(
            student_id__in=list(student_profile_ids), parent__user__is_active=True
        )
        .select_related("parent__user")
        .order_by("created_at", "id")
    )
    guardians: dict[int, list[User]] = {}
    for link in links:
        guardians.setdefault(link.student_id, []).append(link.parent.user)
    return guardians


def active_admins() -> list[User]:
    """The academy's active admins, oldest first (Plan 8's recipients)."""
    return list(
        User.objects.filter(role=User.Role.ADMIN, is_active=True).order_by("id")
    )


def children_of(parent: User) -> list[User]:
```

- [ ] **Step 4: Generate the migration**

Run (from `backend/`):

```bash
.venv/bin/python manage.py makemigrations billing --name invoice_created_at_index --settings=config.settings.test
```

Expected: `etqan/billing/migrations/0002_invoice_created_at_index.py` with one `AddIndex` on `created_at`.

- [ ] **Step 5: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/billing etqan/identity -q --create-db
```

Expected: all pass (4 new).

- [ ] **Step 6: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1148 tests, coverage 97.7% (the gate is 80%).

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/billing etqan/identity
git -C backend commit -m "feat(billing,identity): read-only invoice windows and bulk recipients for notifications

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The one renderer and the one link builder

**Files:**
- Create: `backend/etqan/notifications/text.py`, `backend/etqan/notifications/links.py`
- Test: `backend/etqan/notifications/tests/test_text.py` (new)

**Interfaces:**
- Consumes: Task 1's `kinds`.
- Produces:
  - `etqan.notifications.text.Facts(student, course_ar="", course_en="", starts_at=None, remaining=None, number="", amount_minor=None, currency="", due_on=None)`;
  - `text.render(type_: str, facts: Facts, *, language: str, timezone: str) -> tuple[str, str]` (title ≤ 200 characters, body);
  - `text.language_for(preferred: str, default: str) -> str`, `text.money(amount_minor: int, currency: str) -> str`, `text.when(instant, timezone) -> str`, `text.TEMPLATES`;
  - `etqan.notifications.links.path_for(*, type_: str, target_kind: str, target_id: int, role: str) -> str` (a dashboard path under `/app`).

- [ ] **Step 1: Write the failing tests**

Every type has both languages. Times are on the recipient's clock with the zone named, money comes from minor units, and each role's link is its own page.

Create `backend/etqan/notifications/tests/test_text.py`:

```python
"""The renderer and the links (spec §4.3)."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest

from etqan.notifications import kinds
from etqan.notifications.links import path_for
from etqan.notifications.text import TEMPLATES
from etqan.notifications.text import Facts
from etqan.notifications.text import language_for
from etqan.notifications.text import money
from etqan.notifications.text import render

SIX_PM = datetime(2026, 6, 1, 18, 0, tzinfo=UTC)
SESSION = Facts(
    student="Yusuf", course_ar="تجويد", course_en="Tajweed", starts_at=SIX_PM
)
INVOICE = Facts(
    student="Yusuf",
    number="INV-000042",
    amount_minor=150000,
    currency="EGP",
    due_on=date(2026, 6, 8),
)


def test_every_type_has_both_languages():
    assert set(TEMPLATES) == set(kinds.TYPES)
    assert all(set(texts) == {"ar", "en"} for texts in TEMPLATES.values())


def test_a_session_notice_in_the_recipients_language_and_time_zone():
    # 18:00 UTC is 21:00 in Riyadh, and the next day in Auckland.
    assert render(kinds.REMINDER, SESSION, language="en", timezone="Asia/Riyadh") == (
        "Starting soon: Tajweed",
        "Tajweed with Yusuf starts at 2026-06-01 21:00 (Asia/Riyadh).",
    )
    assert render(
        kinds.STUDENT_ABSENT, SESSION, language="ar", timezone="Pacific/Auckland"
    ) == (
        "غياب: Yusuf",
        "غاب Yusuf عن حصة تجويد في 2026-06-02 06:00 (Pacific/Auckland).",
    )


def test_an_invoice_notice_names_its_number_and_amount():
    assert render(kinds.INVOICE_OVERDUE, INVOICE, language="en", timezone="UTC") == (
        "Invoice INV-000042 is overdue",
        "Invoice INV-000042 for Yusuf (1,500.00 EGP) was due on 2026-06-08.",
    )
    title, body = render(kinds.INVOICE_ISSUED, INVOICE, language="ar", timezone="UTC")
    assert title == "فاتورة جديدة INV-000042"
    assert "1,500.00 EGP" in body


def test_the_low_notice_names_the_sessions_left():
    facts = Facts(student="Yusuf", course_en="Tajweed", remaining=2)
    _, body = render(kinds.SUBSCRIPTION_LOW, facts, language="en", timezone="UTC")
    assert body == "Yusuf has 2 sessions left in Tajweed."


def test_a_long_course_name_keeps_the_title_within_its_column():
    facts = Facts(student="Yusuf", course_en="x" * 300)
    title, _ = render(kinds.SUBSCRIPTION_EXPIRED, facts, language="en", timezone="UTC")
    assert len(title) == 200


@pytest.mark.parametrize(
    ("amount", "currency", "text"),
    [
        (150000, "EGP", "1,500.00 EGP"),
        (5, "USD", "0.05 USD"),
        (1500, "JPY", "1,500 JPY"),
        (12345, "KWD", "12.345 KWD"),
        (-250, "USD", "-2.50 USD"),
    ],
)
def test_money_from_minor_units(amount, currency, text):
    assert money(amount, currency) == text


def test_the_language_falls_back_to_the_academys_then_english():
    assert language_for("en", "ar") == "en"
    assert language_for("", "ar") == "ar"
    assert language_for("fr", "de") == "en"


@pytest.mark.parametrize(
    ("type_", "kind", "role", "path"),
    [
        (kinds.REMINDER, "session", "admin", "/scheduling/sessions/7"),
        (kinds.TEACHER_REMINDER, "session", "teacher", "/teaching/sessions"),
        (kinds.REPORT_MISSING, "session", "teacher", "/teaching/reports"),
        (kinds.LATE, "session", "student", "/learning/sessions"),
        (kinds.STUDENT_ABSENT, "session", "parent", "/learning/sessions"),
        (
            kinds.SUBSCRIPTION_LOW,
            "subscription",
            "admin",
            "/scheduling/subscriptions/7",
        ),
        (
            kinds.SUBSCRIPTION_EXPIRED,
            "subscription",
            "parent",
            "/learning/subscriptions",
        ),
        (kinds.INVOICE_OVERDUE, "invoice", "admin", "/billing/invoices/7"),
        (kinds.INVOICE_ISSUED, "invoice", "student", "/learning/invoices/7"),
        (kinds.INVOICE_ISSUED, "invoice", "teacher", "/"),
        (kinds.SUBSCRIPTION_LOW, "subscription", "teacher", "/"),
        (kinds.REMINDER, "session", "", "/"),
    ],
)
def test_links_per_role(type_, kind, role, path):
    assert path_for(type_=type_, target_kind=kind, target_id=7, role=role) == path
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/notifications/tests/test_text.py -q`

Expected: FAIL — `No module named 'etqan.notifications.links'`.

- [ ] **Step 3: Implement**

Create `backend/etqan/notifications/text.py`:

```python
"""The one renderer (spec §4.3): every type's title and short body, in Arabic
and English, filled in the recipient's language and time zone. What is
rendered is stored and never re-translated (N8-4)."""

from dataclasses import dataclass
from datetime import date
from datetime import datetime
from zoneinfo import ZoneInfo

from etqan.notifications import kinds

LANGUAGES = ("ar", "en")
TITLE_LENGTH = 200  # `Notification.title`
_SESSION_BODY = {
    "en": "{course} with {student} starts at {time}.",
    "ar": "تبدأ حصة {course} مع {student} في {time}.",
}
# type -> language -> (title, body)
TEMPLATES: dict[str, dict[str, tuple[str, str]]] = {
    kinds.EARLY_REMINDER: {
        "en": ("Coming up: {course}", _SESSION_BODY["en"]),
        "ar": ("حصة قادمة: {course}", _SESSION_BODY["ar"]),
    },
    kinds.REMINDER: {
        "en": ("Starting soon: {course}", _SESSION_BODY["en"]),
        "ar": ("تبدأ قريبًا: {course}", _SESSION_BODY["ar"]),
    },
    kinds.TEACHER_REMINDER: {
        "en": ("Your session starts soon", _SESSION_BODY["en"]),
        "ar": ("حصتك تبدأ قريبًا", _SESSION_BODY["ar"]),
    },
    kinds.LATE: {
        "en": (
            "Session not started: {course}",
            "{course} with {student} was due at {time} and no attendance is "
            "marked yet.",
        ),
        "ar": (
            "لم تبدأ الحصة: {course}",
            "كان موعد حصة {course} مع {student} في {time} ولم يُسجَّل الحضور بعد.",
        ),
    },
    kinds.STUDENT_ABSENT: {
        "en": ("Absent: {student}", "{student} missed {course} at {time}."),
        "ar": ("غياب: {student}", "غاب {student} عن حصة {course} في {time}."),
    },
    kinds.SUBSCRIPTION_LOW: {
        "en": (
            "Few sessions left: {course}",
            "{student} has {remaining} sessions left in {course}.",
        ),
        "ar": (
            "حصص قليلة متبقية: {course}",
            "بقي لـ{student} {remaining} من حصص {course}.",
        ),
    },
    kinds.SUBSCRIPTION_EXPIRED: {
        "en": (
            "Subscription ended: {course}",
            "{student}'s {course} subscription has ended.",
        ),
        "ar": ("انتهى الاشتراك: {course}", "انتهى اشتراك {student} في {course}."),
    },
    kinds.INVOICE_ISSUED: {
        "en": (
            "New invoice {number}",
            "Invoice {number} for {student}: {amount}, due on {due_on}.",
        ),
        "ar": (
            "فاتورة جديدة {number}",
            "الفاتورة {number} لـ{student}: {amount}، تستحق في {due_on}.",
        ),
    },
    kinds.INVOICE_OVERDUE: {
        "en": (
            "Invoice {number} is overdue",
            "Invoice {number} for {student} ({amount}) was due on {due_on}.",
        ),
        "ar": (
            "الفاتورة {number} متأخرة",
            "كانت الفاتورة {number} لـ{student} ({amount}) مستحقة في {due_on}.",
        ),
    },
    kinds.REPORT_MISSING: {
        "en": (
            "Report missing: {student}",
            "The report for {course} with {student} at {time} is still missing.",
        ),
        "ar": (
            "تقرير ناقص: {student}",
            "لم يُكتب بعد تقرير حصة {course} مع {student} في {time}.",
        ),
    },
}
# ISO 4217 currencies whose minor unit is not a hundredth.
_NO_MINOR = frozenset(
    {
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG",
        "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF",
    }
)  # fmt: skip
_THOUSANDTHS = frozenset({"BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"})


@dataclass(frozen=True)
class Facts:
    """What a notice names. Only the fields its type uses are set."""

    student: str
    course_ar: str = ""
    course_en: str = ""
    starts_at: datetime | None = None
    remaining: int | None = None
    number: str = ""
    amount_minor: int | None = None
    currency: str = ""
    due_on: date | None = None


def language_for(preferred: str, default: str) -> str:
    """The recipient's language, else the academy's, else English."""
    if preferred in LANGUAGES:
        return preferred
    return default if default in LANGUAGES else "en"


def money(amount_minor: int, currency: str) -> str:
    """``150000, "EGP"`` → ``1,500.00 EGP``, from integer minor units."""
    digits = 0 if currency in _NO_MINOR else 3 if currency in _THOUSANDTHS else 2
    whole, fraction = divmod(abs(amount_minor), 10**digits)
    sign = "-" if amount_minor < 0 else ""
    decimals = f".{fraction:0{digits}d}" if digits else ""
    return f"{sign}{whole:,}{decimals} {currency}"


def when(instant: datetime, timezone: str) -> str:
    """``instant`` on the recipient's clock, with the zone named."""
    local = instant.astimezone(ZoneInfo(timezone))
    return f"{local:%Y-%m-%d %H:%M} ({timezone})"


def render(
    type_: str, facts: Facts, *, language: str, timezone: str
) -> tuple[str, str]:
    """``(title, body)`` for ``type_`` in ``language``, times on
    ``timezone``'s clock."""
    values = {
        "student": facts.student,
        "course": facts.course_ar if language == "ar" else facts.course_en,
        "time": when(facts.starts_at, timezone) if facts.starts_at else "",
        "remaining": facts.remaining,
        "number": facts.number,
        "amount": (
            money(facts.amount_minor, facts.currency)
            if facts.amount_minor is not None
            else ""
        ),
        "due_on": facts.due_on.isoformat() if facts.due_on else "",
    }
    title, body = TEMPLATES[type_][language]
    return title.format(**values)[:TITLE_LENGTH], body.format(**values)
```

Create `backend/etqan/notifications/links.py`:

```python
"""Where a notification leads, for its recipient's role (spec §4.3). The one
link builder: the API sends the dashboard path, and the email the same path
as an absolute URL (`etqan.platform.frontend.app_url`)."""

from etqan.notifications import kinds

HOME = "/"
SESSION_READERS = ("admin", "teacher", "student", "parent")
# Teachers have no subscription or invoice page.
OTHER_READERS = ("admin", "student", "parent")


def _session(type_: str, target_id: int, role: str) -> str:
    if role == "admin":
        return f"/scheduling/sessions/{target_id}"
    if role == "teacher":
        # Teachers have no session page: their list, or the reports they owe.
        if type_ == kinds.REPORT_MISSING:
            return "/teaching/reports"
        return "/teaching/sessions"
    return "/learning/sessions"


def _subscription(target_id: int, role: str) -> str:
    if role == "admin":
        return f"/scheduling/subscriptions/{target_id}"
    return "/learning/subscriptions"


def _invoice(target_id: int, role: str) -> str:
    if role == "admin":
        return f"/billing/invoices/{target_id}"
    return f"/learning/invoices/{target_id}"


def path_for(*, type_: str, target_kind: str, target_id: int, role: str) -> str:
    """The dashboard path (under `/app`) of what the notice is about, as
    ``role`` sees it. A role that has no page for it goes home."""
    if target_kind == kinds.SESSION and role in SESSION_READERS:
        return _session(type_, target_id, role)
    if target_kind == kinds.SESSION or role not in OTHER_READERS:
        return HOME
    if target_kind == kinds.SUBSCRIPTION:
        return _subscription(target_id, role)
    return _invoice(target_id, role)
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/notifications -q
```

Expected: all pass (23 new in `test_text.py`).

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1171 tests, coverage 97.8% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/notifications
git -C backend commit -m "feat(notifications): the one renderer and link builder, in Arabic and English

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The ten finders and the one recipient resolver

**Files:**
- Create: `backend/etqan/notifications/finders.py`, `backend/etqan/notifications/recipients.py`
- Test: `backend/etqan/notifications/tests/test_finders.py` (new)

**Interfaces:**
- Consumes: Task 2's scheduling services, Task 3's billing and identity services, Task 4's `Facts`.
- Produces:
  - `etqan.notifications.finders.Hit(type, target_kind, target_id, occurrence, student, audience, facts, teacher=None, payer=None)` (frozen);
  - `finders.FINDERS: dict[str, Callable[..., list[Hit]]]`, each called as `finder(*, now: datetime, today: date, value: int | None)`;
  - `finders.session_hit(type_: str, session, audience: tuple[str, ...]) -> Hit`, `finders.overdue_week(today, due_on) -> int`;
  - the audience names `STUDENT`, `GUARDIANS`, `TEACHER`, `ADMINS`, `PAYER`, and `LOOK_BACK` (24 h), `GIVE_UP` (60 min), `REPORT_WINDOW` (7 days);
  - `etqan.notifications.recipients.eligible(user) -> bool` and `recipients.resolve(hits: list[Hit]) -> list[tuple[Hit, User]]`.

- [ ] **Step 1: Write the failing tests**

Each type fires at its moment and not a minute early, for exactly the spec's recipients. A reminder never fires after the start or for a cancelled session. Lateness gives up after an hour. Look-backs close after 24 hours (7 days for reports). An overdue invoice repeats weekly and stops once paid. A student with no login gets nothing, while the guardians still do; deactivated people are skipped, and every guardian is told.

Create `backend/etqan/notifications/tests/test_finders.py`:

```python
"""Each type's finder and its recipients (spec §4.1, §4.2). The family's
lesson is on Monday 1 June 2026 at 10:00 UTC; the clock starts at 08:00."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import timedelta

import pytest
from django.utils import timezone

from etqan.billing import services as billing_services
from etqan.identity import services as identity_services
from etqan.notifications import kinds
from etqan.notifications import recipients
from etqan.notifications.finders import FINDERS
from etqan.notifications.tests.conftest import lesson
from etqan.notifications.tests.conftest import person
from etqan.notifications.tests.conftest import subscribe
from etqan.scheduling import services as scheduling_services

TEN = datetime(2026, 6, 1, 10, 0, tzinfo=UTC)
MINUTE = timedelta(minutes=1)
FAMILY = ["Huda", "Omar", "Yusuf"]


def found(type_, now, value=None):
    """``{(target_id, occurrence): [recipient names]}`` for one type."""
    value = kinds.BY_TYPE[type_].default if value is None else value
    hits = FINDERS[type_](now=now, today=now.date(), value=value)
    result = {}
    for hit, user in recipients.resolve(hits):
        assert (hit.type, hit.target_kind) == (type_, kinds.BY_TYPE[type_].target)
        result.setdefault((hit.target_id, hit.occurrence), []).append(user.full_name)
    return {key: sorted(names) for key, names in result.items()}


@pytest.mark.parametrize(
    ("type_", "lead", "names"),
    [
        (kinds.EARLY_REMINDER, timedelta(minutes=120), FAMILY),
        (kinds.REMINDER, timedelta(minutes=60), FAMILY),
        (kinds.TEACHER_REMINDER, timedelta(minutes=30), ["Bilal"]),
    ],
)
def test_a_reminder_fires_at_its_moment_and_not_a_minute_early(
    family, type_, lead, names
):
    session = lesson(family)
    assert found(type_, TEN - lead - MINUTE) == {}
    assert found(type_, TEN - lead) == {(session.pk, ""): names}
    # Late in the window still counts (a session created or moved inside it).
    assert found(type_, TEN - MINUTE) == {(session.pk, ""): names}
    assert found(type_, TEN) == {}


def test_a_reminder_uses_the_academys_number(family):
    session = lesson(family)
    assert found(kinds.REMINDER, TEN - timedelta(minutes=90), value=90) == {
        (session.pk, ""): FAMILY
    }


def test_a_cancelled_session_gets_no_reminder(family):
    session = lesson(family)
    scheduling_services.cancel_session(session, by=family.admin, reason="Holiday")
    assert found(kinds.REMINDER, TEN - MINUTE) == {}


def test_lateness_while_unmarked_and_only_in_the_first_hour(family, clock):
    session = lesson(family)
    everyone = sorted(["Bilal", *FAMILY])
    assert found(kinds.LATE, TEN + 4 * MINUTE) == {}
    assert found(kinds.LATE, TEN + 5 * MINUTE) == {(session.pk, ""): everyone}
    assert found(kinds.LATE, TEN + 59 * MINUTE) == {(session.pk, ""): everyone}
    assert found(kinds.LATE, TEN + 60 * MINUTE) == {}
    clock.set(TEN + 6 * MINUTE)
    scheduling_services.mark_attendance(
        session, by=family.admin, teacher_attendance="present"
    )
    assert found(kinds.LATE, TEN + 7 * MINUTE) == {}


def test_an_absence_is_told_to_the_guardians_for_a_day(family, clock):
    session = lesson(family)
    clock.set(TEN + 10 * MINUTE)
    scheduling_services.mark_attendance(
        session, by=family.admin, student_attendance="absent"
    )
    marked = TEN + 10 * MINUTE
    guardians = {(session.pk, ""): ["Huda", "Omar"]}
    assert found(kinds.STUDENT_ABSENT, marked) == guardians
    assert found(kinds.STUDENT_ABSENT, marked + timedelta(hours=24)) == guardians
    assert found(kinds.STUDENT_ABSENT, marked + timedelta(hours=24) + MINUTE) == {}


def test_a_present_student_is_not_absent(family, clock):
    session = lesson(family)
    clock.set(TEN + 10 * MINUTE)
    scheduling_services.mark_attendance(
        session, by=family.admin, student_attendance="present"
    )
    assert found(kinds.STUDENT_ABSENT, TEN + 11 * MINUTE) == {}


def test_a_low_subscription_is_told_to_the_family_and_the_admins(family):
    subscription = subscribe(family)  # 4 sessions
    now = TEN - timedelta(hours=2)
    assert found(kinds.SUBSCRIPTION_LOW, now, value=3) == {}
    assert found(kinds.SUBSCRIPTION_LOW, now, value=4) == {
        (subscription.pk, ""): ["Amina", *FAMILY]
    }


def test_an_expiry_is_told_for_a_day(family, clock):
    subscription = subscribe(family)
    expired_at = datetime(2026, 7, 10, 1, 0, tzinfo=UTC)  # past the grace days
    clock.set(expired_at)
    scheduling_services.run_lifecycle()
    subscription.refresh_from_db()
    assert subscription.status == "expired"
    assert found(kinds.SUBSCRIPTION_EXPIRED, expired_at) == {
        (subscription.pk, ""): ["Amina", *FAMILY]
    }
    later = expired_at + timedelta(hours=24) + MINUTE
    assert found(kinds.SUBSCRIPTION_EXPIRED, later) == {}


def invoice(family, **overrides):
    fields = {
        "student_id": family.student.id,
        "amount_minor": 150000,
        "due_on": date(2026, 6, 8),
        "description": "Tajweed",
        "by": family.admin,
        **overrides,
    }
    return billing_services.create_invoice(**fields)


def test_a_new_invoice_is_told_to_its_payer_for_a_day(family):
    bill = invoice(family)  # billed to Omar, the first guardian
    # `created_at` is the database's real time, not the pinned clock.
    created = timezone.now()
    assert found(kinds.INVOICE_ISSUED, created) == {(bill.pk, ""): ["Omar"]}
    later = created + timedelta(hours=24, minutes=5)
    assert found(kinds.INVOICE_ISSUED, later) == {}
    billing_services.void_invoice(bill, by=family.admin)
    assert found(kinds.INVOICE_ISSUED, created) == {}


@pytest.mark.parametrize(
    ("day", "expected"),
    [
        (date(2026, 6, 8), None),  # due today
        (date(2026, 6, 9), "0"),  # the day after
        (date(2026, 6, 15), "0"),
        (date(2026, 6, 16), "1"),  # the eighth day after
        (date(2026, 6, 23), "2"),
    ],
)
def test_an_overdue_invoice_repeats_weekly(family, day, expected):
    bill = invoice(family)
    now = datetime(day.year, day.month, day.day, 12, 0, tzinfo=UTC)
    want = {} if expected is None else {(bill.pk, expected): ["Amina", "Omar"]}
    assert found(kinds.INVOICE_OVERDUE, now) == want


def test_a_paid_invoice_stops_being_overdue(family):
    bill = invoice(family)
    billing_services.add_payment(
        bill, amount_minor=150000, method="cash", paid_on=date(2026, 6, 1), by=None
    )
    assert found(kinds.INVOICE_OVERDUE, datetime(2026, 6, 16, tzinfo=UTC)) == {}


def test_a_missing_report_is_told_to_the_teacher_for_a_week(family, clock):
    session = lesson(family)
    clock.set(TEN + 10 * MINUTE)
    scheduling_services.mark_attendance(
        session, by=family.admin, student_attendance="present"
    )
    ended = TEN + 45 * MINUTE
    assert found(kinds.REPORT_MISSING, ended + timedelta(hours=24)) == {}
    clock.set(ended + timedelta(hours=24) + MINUTE)
    assert found(kinds.REPORT_MISSING, ended + timedelta(hours=24) + MINUTE) == {
        (session.pk, ""): ["Bilal"]
    }
    clock.set(ended + timedelta(days=7) + MINUTE)
    assert found(kinds.REPORT_MISSING, ended + timedelta(days=7) + MINUTE) == {}


def test_a_student_without_a_login_gets_nothing_but_the_guardians_do(family):
    aisha = person("student", "Aisha")  # no email address: no login
    identity_services.link_guardian(family.omar, aisha)
    session = lesson(family, student=aisha)
    assert found(kinds.REMINDER, TEN - MINUTE) == {(session.pk, ""): ["Omar"]}


def test_deactivated_people_are_not_told(family):
    session = lesson(family)
    identity_services.deactivate(family.omar, by=None)
    identity_services.deactivate(family.teacher, by=None)
    assert found(kinds.REMINDER, TEN - MINUTE) == {(session.pk, ""): ["Huda", "Yusuf"]}
    assert found(kinds.TEACHER_REMINDER, TEN - MINUTE) == {}


def test_every_guardian_is_told(family):
    third = person("parent", "Salma", "salma@family.test")
    identity_services.link_guardian(third, family.student)
    session = lesson(family)
    assert found(kinds.REMINDER, TEN - MINUTE) == {
        (session.pk, ""): ["Huda", "Omar", "Salma", "Yusuf"]
    }


def test_another_familys_session_reaches_only_its_own_family(family):
    other = person("student", "Zaid", "zaid@family.test")
    guardian = person("parent", "Salma", "salma@family.test")
    identity_services.link_guardian(guardian, other)
    mine = lesson(family)
    theirs = lesson(family, student=other)
    assert found(kinds.REMINDER, TEN - MINUTE) == {
        (mine.pk, ""): FAMILY,
        (theirs.pk, ""): ["Salma", "Zaid"],
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/notifications/tests/test_finders.py -q`

Expected: FAIL — `cannot import name 'recipients' from 'etqan.notifications'`.

- [ ] **Step 3: Implement**

Create `backend/etqan/notifications/finders.py`:

```python
"""One finder per type (spec §4.2): what is due now, read from scheduling and
billing through their services. A finder decides what and for whom; it
writes nothing. Every finder takes the scan's one instant, the academy's
today and the type's number, and costs a fixed number of queries."""

from collections.abc import Callable
from dataclasses import dataclass
from datetime import date
from datetime import datetime
from datetime import timedelta

from etqan.billing import services as billing_services
from etqan.notifications import kinds
from etqan.notifications.text import Facts
from etqan.scheduling import services as scheduling_services

# Event types look back a day (spec §4.1): enabling notifications on an
# academy with history sends no flood, and an outage of up to a day loses
# nothing.
LOOK_BACK = timedelta(hours=24)
# A late session is announced only within its first hour.
GIVE_UP = timedelta(minutes=60)
# `report.missing` looks at sessions that ended in the last week only.
REPORT_WINDOW = timedelta(days=7)
DAYS_PER_WEEK = 7

STUDENT = "student"
GUARDIANS = "guardians"
TEACHER = "teacher"
ADMINS = "admins"
PAYER = "payer"
FAMILY = (STUDENT, GUARDIANS)


@dataclass(frozen=True)
class Hit:
    """One occurrence of a type about one object, and who is told."""

    type: str
    target_kind: str
    target_id: int
    # "" for a once-per-object type; the week for `invoice.overdue`.
    occurrence: str
    # The StudentProfile it concerns (its user joined): the guardians and the
    # text follow it.
    student: object
    audience: tuple[str, ...]
    facts: Facts
    teacher: object | None = None  # the session's teacher's User
    payer: object | None = None  # the invoice's payer


def session_hit(type_: str, session, audience: tuple[str, ...]) -> Hit:
    return Hit(
        type=type_,
        target_kind=kinds.SESSION,
        target_id=session.pk,
        occurrence="",
        student=session.student,
        audience=audience,
        facts=Facts(
            student=session.student.user.full_name,
            course_ar=session.course.name_ar,
            course_en=session.course.name_en,
            starts_at=session.starts_at,
        ),
        teacher=session.teacher.user,
    )


def _subscription_hit(type_: str, subscription, remaining: int | None) -> Hit:
    return Hit(
        type=type_,
        target_kind=kinds.SUBSCRIPTION,
        target_id=subscription.pk,
        occurrence="",
        student=subscription.student,
        audience=(*FAMILY, ADMINS),
        facts=Facts(
            student=subscription.student.user.full_name,
            course_ar=subscription.course.name_ar,
            course_en=subscription.course.name_en,
            remaining=remaining,
        ),
    )


def _invoice_hit(type_: str, invoice, audience, occurrence: str = "") -> Hit:
    return Hit(
        type=type_,
        target_kind=kinds.INVOICE,
        target_id=invoice.pk,
        occurrence=occurrence,
        student=invoice.student,
        audience=audience,
        facts=Facts(
            student=invoice.student.user.full_name,
            number=invoice.number,
            amount_minor=invoice.amount_minor,
            currency=invoice.currency,
            due_on=invoice.due_on,
        ),
        payer=invoice.payer,
    )


def _reminder(type_: str, audience: tuple[str, ...]):
    def find(*, now: datetime, today: date, value: int | None) -> list[Hit]:
        sessions = scheduling_services.sessions_starting(
            now=now, within=timedelta(minutes=value)
        )
        return [session_hit(type_, session, audience) for session in sessions]

    return find


def late(*, now: datetime, today: date, value: int | None) -> list[Hit]:
    sessions = scheduling_services.sessions_running_late(
        now=now, after=timedelta(minutes=value), give_up=GIVE_UP
    )
    return [session_hit(kinds.LATE, s, (TEACHER, *FAMILY)) for s in sessions]


def student_absent(*, now: datetime, today: date, value: int | None) -> list[Hit]:
    sessions = scheduling_services.absences_marked(since=now - LOOK_BACK)
    return [session_hit(kinds.STUDENT_ABSENT, s, (GUARDIANS,)) for s in sessions]


def subscription_low(*, now: datetime, today: date, value: int | None) -> list[Hit]:
    return [
        _subscription_hit(kinds.SUBSCRIPTION_LOW, subscription, remaining)
        for subscription, remaining in scheduling_services.subscriptions_running_low(
            value
        )
    ]


def subscription_expired(*, now: datetime, today: date, value: int | None) -> list[Hit]:
    subscriptions = scheduling_services.subscriptions_expired(since=now - LOOK_BACK)
    return [
        _subscription_hit(kinds.SUBSCRIPTION_EXPIRED, subscription, None)
        for subscription in subscriptions
    ]


def invoice_issued(*, now: datetime, today: date, value: int | None) -> list[Hit]:
    invoices = billing_services.invoices_issued(since=now - LOOK_BACK)
    return [_invoice_hit(kinds.INVOICE_ISSUED, i, (PAYER,)) for i in invoices]


def overdue_week(today: date, due_on: date) -> int:
    """Spec §4.2 type 9: 0 the day after the due date, then one more every
    seven days."""
    return ((today - due_on).days - 1) // DAYS_PER_WEEK


def invoice_overdue(*, now: datetime, today: date, value: int | None) -> list[Hit]:
    return [
        _invoice_hit(
            kinds.INVOICE_OVERDUE,
            invoice,
            (PAYER, ADMINS),
            occurrence=str(overdue_week(today, invoice.due_on)),
        )
        for invoice in billing_services.invoices_overdue(today=today)
    ]


def report_missing(*, now: datetime, today: date, value: int | None) -> list[Hit]:
    sessions = scheduling_services.reports_missing(ended_since=now - REPORT_WINDOW)
    return [session_hit(kinds.REPORT_MISSING, s, (TEACHER,)) for s in sessions]


FINDERS: dict[str, Callable[..., list[Hit]]] = {
    kinds.EARLY_REMINDER: _reminder(kinds.EARLY_REMINDER, FAMILY),
    kinds.REMINDER: _reminder(kinds.REMINDER, FAMILY),
    kinds.TEACHER_REMINDER: _reminder(kinds.TEACHER_REMINDER, (TEACHER,)),
    kinds.LATE: late,
    kinds.STUDENT_ABSENT: student_absent,
    kinds.SUBSCRIPTION_LOW: subscription_low,
    kinds.SUBSCRIPTION_EXPIRED: subscription_expired,
    kinds.INVOICE_ISSUED: invoice_issued,
    kinds.INVOICE_OVERDUE: invoice_overdue,
    kinds.REPORT_MISSING: report_missing,
}
```

Create `backend/etqan/notifications/recipients.py`:

```python
"""Who is told (spec §4.1 Recipients): the one resolver. Guardians and admins
are read once for every hit of a scan, so the query count does not grow with
the number of hits."""

from etqan.identity import services as identity_services
from etqan.notifications import finders
from etqan.notifications.finders import Hit


def eligible(user) -> bool:
    """Only active users are told. A student with no login (no email
    address) gets nothing; anyone else without one still gets the in-app
    notice, and its email is `skipped`."""
    if user is None or not user.is_active:
        return False
    return user.role != "student" or bool(user.email)


def resolve(hits: list[Hit]) -> list[tuple[Hit, object]]:
    """``(hit, user)`` for every eligible recipient of every hit, each user
    once per hit, in audience order."""
    students = {hit.student.pk for hit in hits if finders.GUARDIANS in hit.audience}
    guardians = identity_services.guardians_by_student(students) if students else {}
    wants_admins = any(finders.ADMINS in hit.audience for hit in hits)
    admins = identity_services.active_admins() if wants_admins else []
    pairs = []
    for hit in hits:
        people = {
            finders.STUDENT: [hit.student.user],
            finders.GUARDIANS: guardians.get(hit.student.pk, []),
            finders.TEACHER: [hit.teacher],
            finders.ADMINS: admins,
            finders.PAYER: [hit.payer],
        }
        seen = set()
        for part in hit.audience:
            for user in people[part]:
                if eligible(user) and user.pk not in seen:
                    seen.add(user.pk)
                    pairs.append((hit, user))
    return pairs
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/notifications -q
```

Expected: all pass (22 new in `test_finders.py`).

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1193 tests, coverage 97.8% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/notifications
git -C backend commit -m "feat(notifications): one finder per type and the one recipient resolver

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The email channel: branded, sent once, retried, then failed

**Files:**
- Create: `backend/etqan/notifications/channels/__init__.py`, `backend/etqan/notifications/channels/email.py`, `backend/etqan/templates/email/notifications/message.en.txt`, `backend/etqan/templates/email/notifications/message.ar.txt`
- Modify: `backend/etqan/platform/tenancy.py`
- Test: `backend/etqan/notifications/tests/test_email.py` (new), `backend/etqan/platform/tests/test_tenancy.py`

**Interfaces:**
- Consumes: Task 1's `Notification` and `clock`; Task 4's `links.path_for`; `etqan.site.emails.brand_email`, `etqan.platform.tasks.send_email_message`, `etqan.platform.frontend.app_url`.
- Produces:
  - `etqan.platform.tenancy.academy_context(schema_name: str)` (a context manager that yields the academy);
  - `etqan.notifications.channels.email`: `compose(notification) -> dict`, `send(notification_id) -> str` (`"sent"` or `"skipped"`), `give_up(notification_id, error)`, the Celery task `deliver_email(schema_name: str, notification_id: int) -> str` (named `notifications.deliver_email`), `queue(notification_ids)` (one task per id after commit), and the constants `TRIES = 3`, `BACKOFF = 60`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/notifications/tests/test_email.py`:

```python
"""Email delivery (spec §4.4)."""

import smtplib

from django.core import mail
from django.db import connection
from django_tenants.utils import tenant_context

from etqan.notifications.channels import email
from etqan.notifications.tests.conftest import START
from etqan.notifications.tests.conftest import notice


def status(row):
    row.refresh_from_db()
    return row.email_status


def test_the_email_is_branded_in_the_notices_language_with_its_link(family):
    row = notice(family.student, target_id=7)
    assert email.deliver_email.delay(connection.schema_name, row.pk).get() == "sent"
    (message,) = mail.outbox
    assert message.to == ["yusuf@family.test"]
    assert message.subject.startswith("[")
    assert message.subject.endswith("] Starting soon: Tajweed")
    assert "Hello Yusuf," in message.body
    assert "Tajweed with Yusuf starts at 2026-06-01 10:00 (UTC)." in message.body
    # A student's link is their sessions list, on this academy's host.
    assert "http://testserver/app/learning/sessions\n" in message.body
    html, mimetype = message.alternatives[0]
    assert (mimetype, 'dir="ltr"' in html) == ("text/html", True)
    row.refresh_from_db()
    assert (row.email_status, row.email_sent_at) == ("sent", START)


def test_an_arabic_notice_is_emailed_in_arabic(family):
    row = notice(family.omar, language="ar", title="غياب: Yusuf", body="غاب Yusuf.")
    email.deliver_email.delay(connection.schema_name, row.pk)
    (message,) = mail.outbox
    assert "مرحبًا Omar،" in message.body
    assert 'dir="rtl"' in message.alternatives[0][0]


def test_a_requeued_task_never_sends_twice(family):
    row = notice(family.student)
    email.deliver_email.delay(connection.schema_name, row.pk)
    again = email.deliver_email.delay(connection.schema_name, row.pk)
    assert again.get() == "skipped"
    assert len(mail.outbox) == 1
    assert status(row) == "sent"


def test_a_recipient_without_an_address_is_skipped(family):
    row = notice(family.huda)
    email.deliver_email.delay(connection.schema_name, row.pk)
    assert (mail.outbox, status(row)) == ([], "skipped")


def failing(monkeypatch, times):
    """Make the first ``times`` sends fail as a dropped SMTP connection."""
    calls = []
    real = email.send_email_message

    def send(**kwargs):
        calls.append(kwargs["to"])
        if len(calls) <= times:
            raise smtplib.SMTPServerDisconnected("Connection unexpectedly closed")
        return real(**kwargs)

    monkeypatch.setattr(email, "send_email_message", send)
    # Tests propagate eager errors, and a retry is raised as one: let the
    # eager run follow its retries as a worker would.
    conf = email.deliver_email.app.conf
    monkeypatch.setitem(conf, "CELERY_TASK_EAGER_PROPAGATES", value=False)
    return calls


def test_a_transient_failure_is_retried(family, monkeypatch):
    calls = failing(monkeypatch, times=1)
    row = notice(family.student)
    email.deliver_email.apply(args=[connection.schema_name, row.pk])
    assert len(calls) == 2
    assert (len(mail.outbox), status(row)) == (1, "sent")


def test_after_three_tries_the_email_is_failed(family, monkeypatch):
    calls = failing(monkeypatch, times=5)
    row = notice(family.student)
    result = email.deliver_email.apply(args=[connection.schema_name, row.pk])
    assert result.get() == "failed"
    assert len(calls) == email.TRIES == 3
    row.refresh_from_db()
    assert (row.email_status, row.email_error, mail.outbox) == (
        "failed",
        "Connection unexpectedly closed",
        [],
    )


def test_the_task_runs_in_the_academy_that_queued_it(family, tenants):
    row = notice(family.student)
    with tenant_context(tenants.other):
        # A worker in any schema, given this academy's schema name.
        email.deliver_email.delay(tenants.main.schema_name, row.pk)
        assert connection.schema_name == tenants.other.schema_name
    assert status(row) == "sent"


def test_emails_are_queued_only_when_the_transaction_commits(
    family, django_capture_on_commit_callbacks
):
    row = notice(family.student)
    with django_capture_on_commit_callbacks(execute=False) as callbacks:
        email.queue([row.pk])
    assert (len(callbacks), mail.outbox) == (1, [])
    callbacks[0]()
    assert status(row) == "sent"
```

In `backend/etqan/platform/tests/test_tenancy.py`, replace:

```python
from etqan.platform.tenancy import for_each_academy
```

with:

```python
from etqan.platform.tenancy import academy_context
from etqan.platform.tenancy import for_each_academy
```

Append to `backend/etqan/platform/tests/test_tenancy.py`:

```python


def test_academy_context_enters_the_named_academy(tenants):
    with academy_context(tenants.other.schema_name) as academy:
        assert academy.pk == tenants.other.pk
        assert connection.schema_name == tenants.other.schema_name
        assert connection.tenant.pk == tenants.other.pk
    assert connection.schema_name == tenants.main.schema_name


def test_academy_context_refuses_an_unknown_schema():
    with pytest.raises(get_tenant_model().DoesNotExist):  # noqa: SIM117
        with academy_context("no_such_academy"):
            pass  # pragma: no cover
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/notifications/tests/test_email.py etqan/platform/tests/test_tenancy.py -q`

Expected: FAIL — `No module named 'etqan.notifications.channels'` and `cannot import name 'academy_context'`.

- [ ] **Step 3: Implement**

In `backend/etqan/platform/tenancy.py`, replace:

```python
import logging
from collections.abc import Callable
```

with:

```python
import logging
from collections.abc import Callable
from collections.abc import Iterator
from contextlib import contextmanager
```

Append to `backend/etqan/platform/tenancy.py`:

```python


@contextmanager
def academy_context(schema_name: str) -> Iterator[object]:
    """Run the block inside the academy whose schema is ``schema_name``: a
    task queued from one academy carries its schema name, never the academy
    object. The academy is read from the public table, so `frontend_url` and
    the branded email see the real academy, not a bare schema."""
    academy = get_tenant_model().objects.get(schema_name=schema_name)
    with tenant_context(academy):
        yield academy
```

Create `backend/etqan/notifications/channels/__init__.py`:

```python
"""Delivery channels (N8-6). Email today; WhatsApp joins in B5 without
touching the finders."""
```

Create `backend/etqan/notifications/channels/email.py`:

```python
"""The email channel (spec §4.4). A notification's email is composed on the
academy's branded layout (Plan 2) in the language it was rendered in, and
sent by the platform's send path, once."""

from functools import partial

from celery import shared_task
from django.db import connection
from django.db import transaction
from django.template.loader import render_to_string

from etqan.notifications import clock
from etqan.notifications import links
from etqan.notifications.models import Notification
from etqan.platform.frontend import app_url
from etqan.platform.tasks import send_email_message
from etqan.platform.tenancy import academy_context
from etqan.site.emails import brand_email

DELIVER = "notifications.deliver_email"
TRIES = 3  # the first try and two retries
BACKOFF = 60  # seconds before the first retry, doubled for the next
ERROR_LENGTH = 1000
PENDING = Notification.EmailStatus.PENDING


def compose(notification: Notification) -> dict:
    """Subject, text and HTML of ``notification``'s email: its title and
    body, a greeting and its link, on the branded layout."""
    language = notification.language
    path = links.path_for(
        type_=notification.type,
        target_kind=notification.target_kind,
        target_id=notification.target_id,
        role=notification.recipient.role,
    )
    body = render_to_string(
        f"email/notifications/message.{language}.txt",
        {
            "name": notification.recipient.full_name,
            "body": notification.body,
            "link": app_url(path),
        },
    ).strip()
    message = brand_email(subject=notification.title, body=body, language=language)
    return {
        "subject": message["subject"],
        "body": message["body"],
        "from_email": message["from_email"],
        "alternatives": [[message["html"], "text/html"]] if message["html"] else None,
    }


@transaction.atomic
def send(notification_id: int) -> str:
    """Send one pending email and mark it `sent`. The row is re-read under
    its own lock (no other row is locked): one already sent, failed or held
    by another worker is left alone, so a re-queued task never sends twice.
    A send error propagates and rolls back, and the row stays pending."""
    notification = (
        Notification.objects.select_for_update(skip_locked=True, of=("self",))
        .select_related("recipient")
        .filter(pk=notification_id, email_status=PENDING)
        .first()
    )
    if notification is None:
        return "skipped"
    address = notification.recipient.email
    if not address:
        notification.email_status = Notification.EmailStatus.SKIPPED
        notification.save(update_fields=["email_status"])
        return "skipped"
    send_email_message(**compose(notification), to=[address])
    notification.email_status = Notification.EmailStatus.SENT
    notification.email_sent_at = clock.now()
    notification.save(update_fields=["email_status", "email_sent_at"])
    return "sent"


def give_up(notification_id: int, error: str) -> None:
    """The last try failed: the pending row becomes `failed` with the error."""
    Notification.objects.filter(pk=notification_id, email_status=PENDING).update(
        email_status=Notification.EmailStatus.FAILED,
        email_error=error[:ERROR_LENGTH],
    )


@shared_task(bind=True, name=DELIVER, max_retries=TRIES - 1)
def deliver_email(self, schema_name: str, notification_id: int) -> str:
    """Spec §4.4, inside the academy whose schema queued it. A transient
    failure (SMTP errors are `OSError`s) retries with backoff; after the
    third try the row is `failed`."""
    with academy_context(schema_name):
        try:
            return send(notification_id)
        except OSError as exc:
            if self.request.retries < self.max_retries:
                countdown = BACKOFF * 2**self.request.retries
                raise self.retry(exc=exc, countdown=countdown) from exc
            give_up(notification_id, str(exc) or type(exc).__name__)
            return "failed"


def queue(notification_ids) -> None:
    """One email task per id, queued once the caller's transaction commits
    (a rolled-back scan emails no one), carrying this academy's schema."""
    schema_name = connection.schema_name
    for notification_id in notification_ids:
        transaction.on_commit(
            partial(deliver_email.delay, schema_name, notification_id)
        )
```

Create `backend/etqan/templates/email/notifications/message.en.txt`:

```
{% autoescape off %}Hello{% if name %} {{ name }}{% endif %},

{{ body }}

Open it here:
{{ link }}{% endautoescape %}
```

Create `backend/etqan/templates/email/notifications/message.ar.txt`:

```
{% autoescape off %}مرحبًا{% if name %} {{ name }}{% endif %}،

{{ body }}

افتحه من هنا:
{{ link }}{% endautoescape %}
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/notifications etqan/platform -q
```

Expected: all pass (8 new in `test_email.py`, 2 in `test_tenancy.py`).

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1203 tests, coverage 97.8% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/notifications etqan/platform etqan/templates/email/notifications
git -C backend commit -m "feat(notifications): the branded email channel, sent once and retried

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The scanner, its beat job and the `scan_notifications` command

**Files:**
- Create: `backend/etqan/notifications/services/scan.py`, `backend/etqan/notifications/tasks.py`, `backend/etqan/notifications/management/__init__.py`, `backend/etqan/notifications/management/commands/__init__.py`, `backend/etqan/notifications/management/commands/scan_notifications.py`
- Modify: `backend/etqan/notifications/services/__init__.py`, `backend/config/settings/base.py`
- Test: `backend/etqan/notifications/tests/test_scan.py` (new)

**Interfaces:**
- Consumes: Task 1's settings, Task 4's `text`, Task 5's `finders` and `recipients`, Task 6's `email.queue`; `etqan.academy.services.get_settings`; `etqan.platform.tenancy.for_each_academy`.
- Produces:
  - `etqan.notifications.services.scan(*, now: datetime) -> int` (rows created in the current academy) and `scan_now() -> int` (at `clock.now()`);
  - in `services/scan.py`: `dedupe_key(hit, user) -> str` and `store(pairs, *, now) -> int` (insert what is new, queue its emails);
  - the Celery task `etqan.notifications.tasks.scan() -> dict[str, str]`, named `notifications.scan`, in `CELERY_BEAT_SCHEDULE` every minute;
  - `python manage.py scan_notifications` (prints `ok: <schema>` per academy; exits non-zero if one failed).

- [ ] **Step 1: Write the failing tests**

The scanner writes each recipient's notice in their language and on their clock. It writes each notice once and emails it once across repeated scans, and it skips switched-off types. Enabling it on an academy with history sends nothing. One academy's failure spares the others, and a scan writes only to its own academy. Its query count does not grow with the notices.

Create `backend/etqan/notifications/tests/test_scan.py`:

```python
"""The scanner (spec §4.1, §8). The family's lesson is on Monday 1 June 2026
at 10:00 UTC; the academy is on UTC and defaults to Arabic."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import timedelta

import pytest
from django.conf import settings
from django.core import mail
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context

from etqan.billing import services as billing_services
from etqan.notifications import finders
from etqan.notifications import services
from etqan.notifications import tasks
from etqan.notifications.models import Notification
from etqan.notifications.tests.conftest import build_family
from etqan.notifications.tests.conftest import lesson
from etqan.notifications.tests.conftest import subscribe
from etqan.scheduling import services as scheduling_services
from etqan.scheduling.tests.conftest import until_pk_exceeds

TEN = datetime(2026, 6, 1, 10, 0, tzinfo=UTC)
REMINDER_AT = TEN - timedelta(minutes=60)
MINUTE = timedelta(minutes=1)


@pytest.fixture
def only(family):
    """Switch every type off but these."""

    def keep(*types):
        services.update_settings(
            [{"type": t, "enabled": t in types} for t in services.current_settings()]
        )

    return keep


def rows(**filters):
    return list(
        Notification.objects.filter(**filters)
        .select_related("recipient")
        .order_by("recipient__full_name")
    )


def test_a_scan_writes_each_recipients_notice_in_their_language_and_zone(family, only):
    only("session.reminder")
    session = lesson(family)
    assert services.scan(now=REMINDER_AT) == 3
    huda, omar, yusuf = rows()
    # Yusuf reads English on Riyadh's clock; Omar Arabic on Cairo's; Huda
    # has neither set, so the academy's Arabic and UTC.
    assert (yusuf.language, yusuf.title, yusuf.body) == (
        "en",
        "Starting soon: Tajweed",
        "Tajweed with Yusuf starts at 2026-06-01 13:00 (Asia/Riyadh).",
    )
    assert (omar.language, omar.title, omar.body) == (
        "ar",
        "تبدأ قريبًا: تجويد",
        "تبدأ حصة تجويد مع Yusuf في 2026-06-01 13:00 (Africa/Cairo).",
    )
    assert huda.body == "تبدأ حصة تجويد مع Yusuf في 2026-06-01 10:00 (UTC)."
    assert [r.dedupe_key for r in (huda, omar, yusuf)] == [
        f"session.reminder:session:{session.pk}:{u.pk}"
        for u in (family.huda, family.omar, family.student)
    ]
    targets = {(r.target_kind, r.target_id, r.created_at) for r in rows()}
    assert targets == {("session", session.pk, REMINDER_AT)}
    # Huda has no email address: her notice is in-app only.
    assert [r.email_status for r in (huda, omar, yusuf)] == [
        "skipped",
        "pending",
        "pending",
    ]


def test_repeated_scans_create_and_email_each_notice_once(
    family, only, django_capture_on_commit_callbacks
):
    only("session.reminder", "session.early_reminder")
    lesson(family)
    with django_capture_on_commit_callbacks(execute=True) as first:
        created = services.scan(now=REMINDER_AT)
    with django_capture_on_commit_callbacks(execute=True) as again:
        assert services.scan(now=REMINDER_AT + MINUTE) == 0
    # Two types for three people, two of whom have an address.
    assert (created, len(first), len(again)) == (6, 4, 0)
    assert sorted(m.to[0] for m in mail.outbox) == [
        "omar@family.test",
        "omar@family.test",
        "yusuf@family.test",
        "yusuf@family.test",
    ]
    assert Notification.objects.filter(email_status="sent").count() == 4


def test_a_switched_off_type_creates_nothing(family, only):
    only("session.early_reminder")
    lesson(family)
    assert services.scan(now=REMINDER_AT) == 3
    assert set(Notification.objects.values_list("type", flat=True)) == {
        "session.early_reminder"
    }
    services.update_settings([{"type": "session.early_reminder", "enabled": False}])
    Notification.objects.all().delete()
    assert services.scan(now=REMINDER_AT) == 0


def test_a_reminder_never_comes_after_the_start(family, only, clock):
    only("session.reminder", "session.early_reminder", "session.teacher_reminder")
    session = lesson(family)
    # The scanner was down through the whole window.
    assert services.scan(now=TEN) == 0
    assert services.scan(now=TEN + MINUTE) == 0
    clock.set(TEN + MINUTE)
    scheduling_services.mark_attendance(
        session, by=family.admin, student_attendance="present"
    )
    assert services.scan(now=TEN - MINUTE) == 0  # completed: never again


def test_enabling_on_an_academy_with_history_sends_no_flood(family, clock, only):
    only("session.student_absent", "subscription.expired", "invoice.issued")
    session = lesson(family)
    clock.set(TEN + 10 * MINUTE)
    scheduling_services.mark_attendance(
        session, by=family.admin, student_attendance="absent"
    )
    expired = subscribe(family)
    clock.set(datetime(2026, 7, 10, 1, 0, tzinfo=UTC))
    scheduling_services.run_lifecycle()
    # A subscription that expired before Plan 8 has no `expired_at`.
    expired.refresh_from_db()
    assert expired.status == "expired"
    type(expired).objects.filter(pk=expired.pk).update(expired_at=None)
    billing_services.create_invoice(
        student_id=family.student.id,
        amount_minor=100,
        due_on=date(2026, 7, 20),
        description="Old",
        by=family.admin,
    )
    # The absence is weeks old, the invoice's creation a day past.
    later = datetime.now(UTC) + timedelta(hours=25)
    assert services.scan(now=later) == 0


def test_one_academys_failure_does_not_stop_the_others(
    family, only, tenants, monkeypatch
):
    only("session.reminder")
    lesson(family)
    real = finders.FINDERS["session.reminder"]

    def fails_in_other(**kwargs):
        if connection.schema_name == tenants.other.schema_name:
            raise RuntimeError("boom")
        return real(**kwargs)

    monkeypatch.setitem(finders.FINDERS, "session.reminder", fails_in_other)
    monkeypatch.setattr("etqan.notifications.clock.now", lambda: REMINDER_AT)
    results = tasks.scan()
    assert results[tenants.main.schema_name] == "ok"
    assert results[tenants.other.schema_name] == "failed"
    assert Notification.objects.count() == 3


def test_a_scan_writes_only_to_its_own_academy(family, clock, tenants):
    here = lesson(family)
    with tenant_context(tenants.other):
        there_family = build_family()
        # The other academy's rows get higher pks than any row here.
        until_pk_exceeds(Notification, 10_000, lambda: None)
        there = lesson(there_family)
    clock.set(REMINDER_AT)
    assert tasks.scan() == {
        tenants.main.schema_name: "ok",
        tenants.other.schema_name: "ok",
    }
    mine = {(r.target_id, r.recipient_id) for r in rows(type="session.reminder")}
    assert mine == {(here.pk, u.pk) for u in (family.student, family.omar, family.huda)}
    with tenant_context(tenants.other):
        theirs = list(Notification.objects.filter(type="session.reminder"))
        assert {r.target_id for r in theirs} == {there.pk}
        assert min(r.pk for r in theirs) > 10_000
    # Nothing of the other academy's reached this one.
    assert not Notification.objects.filter(pk__gt=10_000).exists()


def test_the_query_count_does_not_grow_with_the_notices(family):
    services.current_settings()  # the first read creates the rows

    def count():
        Notification.objects.all().delete()
        with CaptureQueriesContext(connection) as ctx:
            created = services.scan(now=REMINDER_AT)
        # django-tenants may reset the search path between statements.
        sql = [q["sql"] for q in ctx.captured_queries]
        return created, [q for q in sql if not q.startswith("SET search_path")]

    lesson(family)
    one = count()
    for _ in range(3):
        lesson(family)
    many = count()
    assert many[0] > one[0] > 0
    assert len(many[1]) == len(one[1])


def test_the_scan_runs_every_minute_with_its_own_limits():
    entry = settings.CELERY_BEAT_SCHEDULE["notifications.scan"]
    assert entry["task"] == tasks.scan.name == "notifications.scan"
    assert entry["schedule"].minute == set(range(60))
    assert (tasks.scan.soft_time_limit, tasks.scan.time_limit) == (240, 270)


def test_the_command_runs_the_scan_now(family, only, capsys, monkeypatch):
    only("session.reminder")
    lesson(family)
    monkeypatch.setattr("etqan.notifications.clock.now", lambda: REMINDER_AT)
    call_command("scan_notifications")
    assert "ok: pytest_main" in capsys.readouterr().out
    assert Notification.objects.count() == 3


def test_the_command_fails_when_an_academy_does(monkeypatch):
    def boom():
        raise RuntimeError("boom")

    monkeypatch.setattr(services, "scan_now", boom)
    with pytest.raises(CommandError, match="failed"):
        call_command("scan_notifications")
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/notifications/tests/test_scan.py -q`

Expected: FAIL — `cannot import name 'tasks' from 'etqan.notifications'`.

- [ ] **Step 3: Implement**

Create `backend/etqan/notifications/services/scan.py`:

```python
"""The scanner (N8-2, spec §4.1): what is due now becomes notifications.

Per academy: load the settings, run each enabled type's finder, resolve the
recipients in bulk, render each new row once in its recipient's language and
time zone, insert with `ignore_conflicts` on the unique `dedupe_key`, and
queue one email per new pending row after commit. Re-runs and overlapping
runs never create a row twice, and a row is emailed once (the task re-reads
it). The scanner locks nothing: it only inserts its own rows."""

from zoneinfo import ZoneInfo

from etqan.academy import services as academy_services
from etqan.notifications import clock
from etqan.notifications import finders
from etqan.notifications import recipients
from etqan.notifications import text
from etqan.notifications.channels import email
from etqan.notifications.finders import Hit
from etqan.notifications.models import Notification
from etqan.notifications.services import settings

PENDING = Notification.EmailStatus.PENDING
SKIPPED = Notification.EmailStatus.SKIPPED


def dedupe_key(hit: Hit, user) -> str:
    """`<type>:<object>:<id>[:<occurrence>]:<recipient_id>` (spec §3.1)."""
    occurrence = f":{hit.occurrence}" if hit.occurrence else ""
    return f"{hit.type}:{hit.target_kind}:{hit.target_id}{occurrence}:{user.pk}"


def _row(hit: Hit, user, key: str, *, now, academy) -> Notification:
    language = text.language_for(user.preferred_language, academy.default_language)
    title, body = text.render(
        hit.type,
        hit.facts,
        language=language,
        timezone=user.timezone or academy.timezone,
    )
    return Notification(
        recipient=user,
        type=hit.type,
        dedupe_key=key,
        target_kind=hit.target_kind,
        target_id=hit.target_id,
        language=language,
        title=title,
        body=body,
        # A recipient without an address still gets the in-app notice.
        email_status=PENDING if user.email else SKIPPED,
        created_at=now,
    )


def store(pairs: list[tuple[Hit, object]], *, now) -> int:
    """Insert the rows of ``pairs`` that do not exist yet and queue their
    emails; return how many were new. A fixed number of queries however many
    rows: one read of the existing keys, one insert, one read of the new ids."""
    if not pairs:
        return 0
    academy = academy_services.get_settings()
    wanted = {dedupe_key(hit, user): (hit, user) for hit, user in pairs}
    existing = set(
        Notification.objects.filter(dedupe_key__in=list(wanted)).values_list(
            "dedupe_key", flat=True
        )
    )
    new = [
        _row(hit, user, key, now=now, academy=academy)
        for key, (hit, user) in wanted.items()
        if key not in existing
    ]
    if not new:
        return 0
    # A scan running at the same moment may have inserted some of these;
    # the unique key drops them here, and the email task sends once.
    Notification.objects.bulk_create(new, ignore_conflicts=True)
    email.queue(
        Notification.objects.filter(
            dedupe_key__in=[row.dedupe_key for row in new], email_status=PENDING
        ).values_list("pk", flat=True)
    )
    return len(new)


def scan(*, now) -> int:
    """One scan of the current academy at the instant ``now``; returns how
    many notifications it created. Switched-off types are not read at all."""
    academy = academy_services.get_settings()
    today = now.astimezone(ZoneInfo(academy.timezone)).date()
    hits: list[Hit] = []
    for type_, row in settings.current().items():
        if row.enabled:
            hits += finders.FINDERS[type_](now=now, today=today, value=row.value)
    return store(recipients.resolve(hits), now=now)


def scan_now() -> int:
    """The beat job's work in the current academy (`for_each_academy`)."""
    return scan(now=clock.now())
```

Replace the whole of `backend/etqan/notifications/services/__init__.py` with:

```python
"""Public API of the notifications module. No other app imports it (N8-1)."""

from etqan.notifications.services.scan import scan
from etqan.notifications.services.scan import scan_now
from etqan.notifications.services.settings import current as current_settings
from etqan.notifications.services.settings import update as update_settings

__all__ = ["current_settings", "scan", "scan_now", "update_settings"]
```

Create `backend/etqan/notifications/tasks.py`:

```python
from celery import shared_task

from etqan.notifications import services
from etqan.platform.tenancy import for_each_academy

SCAN = "notifications.scan"


# Every minute (N8-2), with its own limits: it loops over every academy. A
# run that outlasts a minute overlaps the next one harmlessly (the unique
# key), and the soft limit stops it cleanly before the hard one.
@shared_task(name=SCAN, soft_time_limit=240, time_limit=270)
def scan() -> dict[str, str]:
    """Spec §4.1: the scan in every academy. One academy's failure is logged
    and rolled back; the others still run."""
    return for_each_academy(services.scan_now, name=SCAN)
```

Create `backend/etqan/notifications/management/__init__.py`:

```python

```

Create `backend/etqan/notifications/management/commands/__init__.py`:

```python

```

Create `backend/etqan/notifications/management/commands/scan_notifications.py`:

```python
"""Run the notifications scan now, as the beat job does every minute."""

from django.core.management.base import BaseCommand
from django.core.management.base import CommandError

from etqan.notifications import tasks


class Command(BaseCommand):
    help = "Run the notifications scan in every active academy now."

    def handle(self, *args, **options):
        results = tasks.scan()
        for schema_name, outcome in results.items():
            self.stdout.write(f"{outcome}: {schema_name}")
        if "failed" in results.values():
            raise CommandError("The scan failed in at least one academy.")
```

In `backend/config/settings/base.py`, replace:

```python
        "schedule": crontab(minute=5),
    },
}
```

with:

```python
        "schedule": crontab(minute=5),
    },
    # Plan 8 (N8-2): every minute, so a notice goes out within about a minute.
    "notifications.scan": {
        "task": "notifications.scan",
        "schedule": crontab(),
    },
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/notifications -q
```

Expected: all pass (11 new in `test_scan.py`).

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1214 tests, coverage 97.8% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add config/settings/base.py etqan/notifications
git -C backend commit -m "feat(notifications): the scanner, every minute in every academy

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: API: the caller's notifications, the unread count, mark read, read all and settings

**Files:**
- Create: `backend/etqan/notifications/services/inbox.py`, `backend/etqan/notifications/api/__init__.py`, `api/serializers.py`, `api/payloads.py`, `api/views.py`, `api/urls.py` (under `backend/etqan/notifications/`)
- Modify: `backend/etqan/notifications/services/__init__.py`, `backend/config/api_router.py`
- Test: `backend/etqan/notifications/tests/test_api.py` (new)

**Interfaces:**
- Consumes: Task 1's settings services, Task 4's `links.path_for`, the `api_for` fixture (root conftest).
- Produces:
  - services `inbox(user, *, unread: bool) -> QuerySet[Notification]`, `unread_count(user) -> int`, `get(user, notification_id) -> Notification` (`NotFoundError` for anyone else's), `mark_read(user, notification_id) -> Notification` (idempotent), `mark_all_read(user) -> int`;
  - `payloads.notification_row(notification, *, role) -> {id, type, title, body, link, read_at, created_at}` and `payloads.setting_rows(rows) -> [{type, enabled, value}]`;
  - routes (spec §5): `GET notifications/` (paged, `?unread=1`), `GET unread-count/` → `{count}`, `POST <id>/read/` → the row, `POST read-all/` → `{count}`, `GET settings/` and `PATCH settings/` (admin; a list of `{type, enabled?, value?}`; answers with all ten).

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/notifications/tests/test_api.py`:

```python
"""The notifications API (spec §4.5, §5)."""

from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.notifications.models import Notification
from etqan.notifications.tests.conftest import START
from etqan.notifications.tests.conftest import notice
from etqan.notifications.tests.conftest import person
from etqan.scheduling.tests.conftest import until_pk_exceeds

URL = "/api/v1/notifications/"
ROLES = ("admin", "teacher", "student", "parent")
ROW_KEYS = {"id", "type", "title", "body", "link", "read_at", "created_at"}


@pytest.fixture
def roles(api_for, clock):
    return {role: api_for(role) for role in ROLES}


def read_url(pk):
    return f"{URL}{pk}/read/"


@pytest.mark.parametrize("role", ROLES)
def test_each_role_reads_only_its_own_newest_first(roles, role):
    me = roles[role].user
    other = roles["admin" if role != "admin" else "teacher"].user
    older = notice(me, target_id=1, created_at=START - timedelta(hours=1))
    newer = notice(me, target_id=2, type_="invoice.issued", title="New invoice")
    notice(other, target_id=3)
    response = roles[role].get(URL)
    assert response.status_code == 200
    body = response.json()
    assert body["count"] == 2
    assert [r["id"] for r in body["results"]] == [newer.pk, older.pk]
    first = body["results"][0]
    # Never `email_status`, `email_error`, `dedupe_key` or `language`.
    assert set(first) == ROW_KEYS
    assert (first["type"], first["title"], first["read_at"]) == (
        "invoice.issued",
        "New invoice",
        None,
    )


@pytest.mark.parametrize(
    ("role", "session_link", "invoice_link"),
    [
        ("admin", "/scheduling/sessions/7", "/billing/invoices/7"),
        ("teacher", "/teaching/sessions", "/"),
        ("student", "/learning/sessions", "/learning/invoices/7"),
        ("parent", "/learning/sessions", "/learning/invoices/7"),
    ],
)
def test_the_link_is_the_readers_page(roles, role, session_link, invoice_link):
    client = roles[role]
    notice(client.user, target_id=7)
    notice(client.user, target_id=7, type_="invoice.overdue")
    links = {r["type"]: r["link"] for r in client.get(URL).json()["results"]}
    assert links == {"session.reminder": session_link, "invoice.overdue": invoice_link}


def test_unread_only_and_the_unread_count(roles):
    client = roles["parent"]
    notice(client.user, target_id=1, read_at=START)
    unread = notice(client.user, target_id=2)
    notice(roles["student"].user, target_id=3)
    ids = [r["id"] for r in client.get(URL, {"unread": "1"}).json()["results"]]
    assert ids == [unread.pk]
    assert len(client.get(URL).json()["results"]) == 2
    assert client.get(f"{URL}unread-count/").json() == {"count": 1}


def test_marking_one_read_is_idempotent(roles, clock):
    client = roles["student"]
    row = notice(client.user)
    first = client.post(read_url(row.pk))
    assert first.status_code == 200
    assert first.json()["read_at"] == "2026-06-01T08:00:00Z"
    clock.set(START + timedelta(hours=1))
    again = client.post(read_url(row.pk))
    assert again.json()["read_at"] == "2026-06-01T08:00:00Z"
    assert client.get(f"{URL}unread-count/").json() == {"count": 0}


def test_another_users_notification_is_a_404(roles):
    theirs = notice(roles["parent"].user)
    response = roles["student"].post(read_url(theirs.pk))
    assert response.status_code == 404
    theirs.refresh_from_db()
    assert theirs.read_at is None
    assert roles["student"].post(read_url(999_999)).status_code == 404


def test_mark_all_read_marks_only_the_callers(roles):
    client = roles["teacher"]
    notice(client.user, target_id=1)
    notice(client.user, target_id=2)
    notice(client.user, target_id=3, read_at=START)
    theirs = notice(roles["admin"].user, target_id=4)
    response = client.post(f"{URL}read-all/")
    assert (response.status_code, response.json()) == (200, {"count": 2})
    assert client.get(f"{URL}unread-count/").json() == {"count": 0}
    theirs.refresh_from_db()
    assert theirs.read_at is None


def test_another_academys_notification_is_a_404(roles, tenants):
    client = roles["parent"]
    mine = notice(client.user, target_id=1)
    with tenant_context(tenants.other):
        stranger = person("parent", "Stranger", "stranger@other.test")
        theirs = until_pk_exceeds(
            Notification, mine.pk, lambda: notice(stranger, target_id=2)
        )
    assert theirs.pk > mine.pk
    assert client.post(read_url(theirs.pk)).status_code == 404
    assert [r["id"] for r in client.get(URL).json()["results"]] == [mine.pk]
    with tenant_context(tenants.other):
        assert Notification.objects.get(pk=theirs.pk).read_at is None


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", ""),
        ("get", "unread-count/"),
        ("post", "read-all/"),
        ("post", "1/read/"),
        ("get", "settings/"),
        ("patch", "settings/"),
    ],
)
def test_visitors_are_refused(method, path):
    assert getattr(APIClient(), method)(f"{URL}{path}").status_code == 403


def test_the_list_and_the_count_cost_the_same_for_any_number(roles):
    client = roles["parent"]

    def queries(path):
        with CaptureQueriesContext(connection) as ctx:
            assert client.get(f"{URL}{path}").status_code == 200
        return len(ctx.captured_queries)

    notice(client.user, target_id=1)
    one = (queries(""), queries("unread-count/"))
    for target in range(2, 30):
        notice(client.user, target_id=target)
    assert (queries(""), queries("unread-count/")) == one


def test_settings_list_every_type_for_admins(roles):
    response = roles["admin"].get(f"{URL}settings/")
    assert response.status_code == 200
    rows = response.json()
    assert len(rows) == 10
    assert rows[0] == {
        "type": "session.early_reminder",
        "enabled": True,
        "value": 120,
    }
    assert rows[4] == {
        "type": "session.student_absent",
        "enabled": True,
        "value": None,
    }


def test_settings_are_saved_and_read_back(roles):
    response = roles["admin"].patch(
        f"{URL}settings/",
        [
            {"type": "session.reminder", "enabled": False},
            {"type": "session.late", "value": 10},
        ],
        format="json",
    )
    assert response.status_code == 200
    rows = {r["type"]: r for r in response.json()}
    assert rows["session.reminder"] == {
        "type": "session.reminder",
        "enabled": False,
        "value": 60,
    }
    assert rows["session.late"]["value"] == 10
    assert len(rows) == 10


def test_a_value_out_of_range_is_a_400_on_its_types_value(roles):
    response = roles["admin"].patch(
        f"{URL}settings/",
        [
            {"type": "session.reminder", "enabled": False},
            {"type": "session.late", "value": 56},
        ],
        format="json",
    )
    assert response.status_code == 400
    assert response.json() == {"session.late.value": ["Choose a number from 1 to 55."]}
    rows = {r["type"]: r for r in roles["admin"].get(f"{URL}settings/").json()}
    assert rows["session.reminder"]["enabled"] is True


def test_an_unknown_type_is_a_400(roles):
    response = roles["admin"].patch(
        f"{URL}settings/", [{"type": "party", "enabled": True}], format="json"
    )
    assert response.status_code == 400


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_settings_are_for_admins_only(roles, role):
    client = roles[role]
    assert client.get(f"{URL}settings/").status_code == 403
    body = [{"type": "session.late", "value": 9}]
    assert client.patch(f"{URL}settings/", body, format="json").status_code == 403


def test_there_is_no_put(roles):
    assert roles["admin"].put(f"{URL}settings/", [], format="json").status_code == 405
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/notifications/tests/test_api.py -q`

Expected: FAIL — every request answers 404 (no route yet).

- [ ] **Step 3: Implement**

Create `backend/etqan/notifications/services/inbox.py`:

```python
"""A user's own notifications (spec §4.5, §5): read and mark only one's own.
Another user's notification does not exist for the caller (a 404)."""

from django.db.models import QuerySet

from etqan.notifications import clock
from etqan.notifications.models import Notification
from etqan.platform.exceptions import NotFoundError


def inbox(user, *, unread: bool) -> QuerySet[Notification]:
    """``user``'s notifications, newest first; only the unread ones when
    ``unread``. One query per page, no joins: a row names nothing else."""
    rows = Notification.objects.filter(recipient=user)
    if unread:
        rows = rows.filter(read_at__isnull=True)
    return rows.order_by("-created_at", "-id")


def unread_count(user) -> int:
    return Notification.objects.filter(recipient=user, read_at__isnull=True).count()


def get(user, notification_id: int) -> Notification:
    """``user``'s notification with this id; `NotFoundError` otherwise."""
    notification = inbox(user, unread=False).filter(pk=notification_id).first()
    if notification is None:
        raise NotFoundError("Notification", notification_id)
    return notification


def mark_read(user, notification_id: int) -> Notification:
    """Mark one read, once: marking it again keeps the first `read_at`.
    Returns a fresh read."""
    Notification.objects.filter(
        pk=notification_id, recipient=user, read_at__isnull=True
    ).update(read_at=clock.now())
    return get(user, notification_id)


def mark_all_read(user) -> int:
    """Mark every unread one read; returns how many were."""
    return Notification.objects.filter(recipient=user, read_at__isnull=True).update(
        read_at=clock.now()
    )
```

Replace the whole of `backend/etqan/notifications/services/__init__.py` with:

```python
"""Public API of the notifications module. No other app imports it (N8-1)."""

from etqan.notifications.services.inbox import get
from etqan.notifications.services.inbox import inbox
from etqan.notifications.services.inbox import mark_all_read
from etqan.notifications.services.inbox import mark_read
from etqan.notifications.services.inbox import unread_count
from etqan.notifications.services.scan import scan
from etqan.notifications.services.scan import scan_now
from etqan.notifications.services.settings import current as current_settings
from etqan.notifications.services.settings import update as update_settings

__all__ = [
    "current_settings",
    "get",
    "inbox",
    "mark_all_read",
    "mark_read",
    "scan",
    "scan_now",
    "unread_count",
    "update_settings",
]
```

Create `backend/etqan/notifications/api/__init__.py`:

```python

```

Create `backend/etqan/notifications/api/serializers.py`:

```python
"""Request bodies and list queries (spec §5). Responses are built in
`payloads`."""

from rest_framework import serializers

from etqan.notifications.kinds import TYPES


class InboxQueryInput(serializers.Serializer):
    unread = serializers.BooleanField(required=False, default=False)


class SettingChangeInput(serializers.Serializer):
    type = serializers.ChoiceField(choices=TYPES)
    enabled = serializers.BooleanField(required=False)
    # Ranges are the service's (a 400 on `<type>.value`), so every range
    # error reads the same.
    value = serializers.IntegerField(required=False, allow_null=True)
```

Create `backend/etqan/notifications/api/payloads.py`:

```python
"""Response shapes (spec §5). `email_status`, `email_error` and `dedupe_key`
never leave the server (spec §4.5)."""

from etqan.notifications import links


def notification_row(notification, *, role: str) -> dict:
    """One notification as its recipient, of ``role``, sees it: ``link`` is
    the dashboard path for that role."""
    return {
        "id": notification.pk,
        "type": notification.type,
        "title": notification.title,
        "body": notification.body,
        "link": links.path_for(
            type_=notification.type,
            target_kind=notification.target_kind,
            target_id=notification.target_id,
            role=role,
        ),
        "read_at": notification.read_at,
        "created_at": notification.created_at,
    }


def setting_rows(rows: dict) -> list[dict]:
    """Every type's switch and number, in the catalogue's order."""
    return [
        {"type": row.type, "enabled": row.enabled, "value": row.value}
        for row in rows.values()
    ]
```

Create `backend/etqan/notifications/api/views.py`:

```python
"""Notification endpoints (spec §5). Thin: parse, call one service, re-read
and arrange a payload. Only the methods the spec lists: no PUT."""

from rest_framework import generics
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.notifications import services
from etqan.notifications.api import payloads
from etqan.notifications.api.serializers import InboxQueryInput
from etqan.notifications.api.serializers import SettingChangeInput
from etqan.platform.permissions import IsAdmin


def _row(request, notification) -> dict:
    return payloads.notification_row(notification, role=request.user.role)


# Spec §4.5: every signed-in role reads and marks only its own; visitors get
# 403 (session authentication, no challenge).
class NotificationListView(generics.GenericAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        query = InboxQueryInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        rows = services.inbox(request.user, unread=query.validated_data["unread"])
        page = self.paginate_queryset(rows)
        return self.get_paginated_response([_row(request, n) for n in page])


class UnreadCountView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({"count": services.unread_count(request.user)})


class ReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        services.mark_read(request.user, pk)
        return Response(_row(request, services.get(request.user, pk)))


class ReadAllView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        return Response({"count": services.mark_all_read(request.user)})


class SettingsView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(payloads.setting_rows(services.current_settings()))

    def patch(self, request):
        body = SettingChangeInput(data=request.data, many=True)
        body.is_valid(raise_exception=True)
        services.update_settings(body.validated_data)
        return Response(payloads.setting_rows(services.current_settings()))
```

Create `backend/etqan/notifications/api/urls.py`:

```python
from django.urls import path

from etqan.notifications.api import views

app_name = "notifications"
urlpatterns = [
    path("", views.NotificationListView.as_view(), name="list"),
    path("unread-count/", views.UnreadCountView.as_view(), name="unread-count"),
    path("read-all/", views.ReadAllView.as_view(), name="read-all"),
    path("settings/", views.SettingsView.as_view(), name="settings"),
    path("<int:pk>/read/", views.ReadView.as_view(), name="read"),
]
```

In `backend/config/api_router.py`, replace:

```python
    path("payroll/", include("etqan.payroll.api.urls")),
```

with:

```python
    path("payroll/", include("etqan.payroll.api.urls")),
    # the caller's notifications, unread-count/, read-all/, settings/ (Plan 8).
    path("notifications/", include("etqan.notifications.api.urls")),
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/notifications -q
```

Expected: all pass (28 new in `test_api.py`).

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1242 tests, coverage 97.9% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add config/api_router.py etqan/notifications
git -C backend commit -m "feat(notifications): the notifications API and admin settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dev seeds: the default settings, one scan and a read and an unread notice per role

**Files:**
- Modify: `backend/etqan/notifications/services/scan.py`, `backend/etqan/notifications/services/__init__.py`, `backend/etqan/tenants/management/commands/seed_dev.py`, `backend/pyproject.toml`
- Test: `backend/etqan/notifications/tests/test_samples.py` (new), `backend/etqan/tenants/tests/test_seed_dev.py` (the pinned `CLOCKS` gain notifications' clock; two new tests)

**Interfaces:**
- Consumes: Task 7's `store`, `dedupe_key`, `scan_now`; Task 5's `finders.session_hit`; `etqan.scheduling.services.sessions_queryset`; `etqan.identity.services.get_user_by_email`.
- Produces: `etqan.notifications.services.has_notifications() -> bool` and `add_samples(user) -> int`; `seed_dev.NOTIFIED` and `seed_dev.seed_notifications(emails)`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/notifications/tests/test_samples.py`:

```python
"""The dev seeds' sample notifications (spec §7)."""

from etqan.notifications import services
from etqan.notifications.tests.conftest import lesson
from etqan.scheduling import services as scheduling_services


def bell(user):
    return [
        (n.type, n.target_id, n.read_at is not None)
        for n in services.inbox(user, unread=False).order_by("id")
    ]


def test_each_role_gets_a_read_and_an_unread_sample_once(family):
    assert services.add_samples(family.omar) == 0  # no session yet
    lesson(family)
    latest = scheduling_services.sessions_queryset().order_by("-starts_at").first()
    for user in (family.admin, family.teacher, family.student, family.omar):
        assert services.add_samples(user) == 2
        assert services.add_samples(user) == 0
    reminder = [
        ("session.reminder", latest.pk, True),
        ("session.reminder", latest.pk, False),
    ]
    assert bell(family.omar) == bell(family.admin) == bell(family.student) == reminder
    assert bell(family.teacher) == [
        ("session.teacher_reminder", latest.pk, True),
        ("session.teacher_reminder", latest.pk, False),
    ]
    assert services.has_notifications()
```

In `backend/etqan/tenants/tests/test_seed_dev.py`, replace:

```python
    "etqan.payroll.clock.now",
)
```

with:

```python
    "etqan.payroll.clock.now",
    "etqan.notifications.clock.now",
)
```

Append to `backend/etqan/tenants/tests/test_seed_dev.py`:

```python


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_scans_and_samples_notifications_once():
    from etqan.notifications import services as notifications  # noqa: PLC0415

    def state():
        return {
            email: [
                (n.type, n.dedupe_key, n.read_at is not None)
                for n in notifications.inbox(
                    User.objects.get(email=email), unread=False
                )
            ]
            for email in (*seed_dev.NOTIFIED["demo"], "huda@demo.test")
        }

    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        assert len(notifications.current_settings()) == 10
        first = state()
        # Every demo role has a read and an unread one in its bell.
        for email in seed_dev.NOTIFIED["demo"]:
            reads = {read for _, _, read in first[email]}
            assert reads == {True, False}, email
        # The scan ran on the seeded data: Zaid's invoice, billed to Huda,
        # was due ten days ago.
        assert "invoice.overdue" in {t for t, _, _ in first["huda@demo.test"]}
    with tenant_context(other):
        assert not notifications.has_notifications()
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_notifications_skips_a_missing_person(capsys, monkeypatch):
    monkeypatch.setitem(
        seed_dev.NOTIFIED, "demo", ("nobody@demo.test", "admin@demo.test")
    )
    call_command("seed_dev")
    assert "skip: nobody@demo.test notifications" in capsys.readouterr().out
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/notifications/tests/test_samples.py etqan/tenants/tests/test_seed_dev.py -q`

Expected: FAIL — `module 'etqan.notifications.services' has no attribute 'add_samples'`, `module … seed_dev has no attribute 'NOTIFIED'`.

- [ ] **Step 3: Implement**

In `backend/etqan/notifications/services/scan.py` (1 of 3), replace:

```python
from zoneinfo import ZoneInfo
```

with:

```python
from dataclasses import replace
from zoneinfo import ZoneInfo
```

In `backend/etqan/notifications/services/scan.py` (2 of 3), replace:

```python
from etqan.notifications import finders
from etqan.notifications import recipients
```

with:

```python
from etqan.notifications import finders
from etqan.notifications import kinds
from etqan.notifications import recipients
```

In `backend/etqan/notifications/services/scan.py` (3 of 3), replace:

```python
from etqan.notifications.services import settings
```

with:

```python
from etqan.notifications.services import settings
from etqan.scheduling import services as scheduling_services
```

Append to `backend/etqan/notifications/services/scan.py`:

```python


# ── Dev seeds ────────────────────────────────────────────────────────────────

SAMPLES = ("sample-read", "sample-unread")


def has_notifications() -> bool:
    return Notification.objects.exists()


def _sessions_seen_by(user):
    sessions = scheduling_services.sessions_queryset()
    if user.role == "teacher":
        return sessions.filter(teacher__user=user)
    if user.role == "student":
        return sessions.filter(student__user=user)
    if user.role == "parent":
        return sessions.filter(student__guardian_links__parent__user=user)
    return sessions


def add_samples(user) -> int:
    """Dev seeds (spec §7): one read and one unread reminder for ``user``
    about the latest session they can see, so the bell has something in
    every role's panel. Idempotent through the key; returns how many rows
    were new (0 for someone with no session)."""
    session = _sessions_seen_by(user).order_by("-starts_at", "-id").first()
    if session is None:
        return 0
    type_ = kinds.TEACHER_REMINDER if user.role == "teacher" else kinds.REMINDER
    hit = finders.session_hit(type_, session, ())
    pairs = [(replace(hit, occurrence=occurrence), user) for occurrence in SAMPLES]
    now = clock.now()
    created = store(pairs, now=now)
    read_key = dedupe_key(pairs[0][0], user)
    Notification.objects.filter(dedupe_key=read_key, read_at__isnull=True).update(
        read_at=now
    )
    return created
```

Replace the whole of `backend/etqan/notifications/services/__init__.py` with:

```python
"""Public API of the notifications module. No other app imports it (N8-1)."""

from etqan.notifications.services.inbox import get
from etqan.notifications.services.inbox import inbox
from etqan.notifications.services.inbox import mark_all_read
from etqan.notifications.services.inbox import mark_read
from etqan.notifications.services.inbox import unread_count
from etqan.notifications.services.scan import add_samples
from etqan.notifications.services.scan import has_notifications
from etqan.notifications.services.scan import scan
from etqan.notifications.services.scan import scan_now
from etqan.notifications.services.settings import current as current_settings
from etqan.notifications.services.settings import update as update_settings

__all__ = [
    "add_samples",
    "current_settings",
    "get",
    "has_notifications",
    "inbox",
    "mark_all_read",
    "mark_read",
    "scan",
    "scan_now",
    "unread_count",
    "update_settings",
]
```

In `backend/etqan/tenants/management/commands/seed_dev.py` (1 of 3), replace:

```python
from etqan.identity import services as identity_services
```

with:

```python
from etqan.identity import services as identity_services
from etqan.notifications import services as notifications_services
```

In `backend/etqan/tenants/management/commands/seed_dev.py` (2 of 3), replace:

```python
class Command(BaseCommand):
```

with:

```python
# Plan 8 (spec §7): after the scan, one read and one unread notification for
# each demo role, so the bell has something in every panel.
NOTIFIED = {
    "demo": (
        "admin@demo.test",
        "bilal@demo.test",
        "yusuf@demo.test",
        "omar@demo.test",
    ),
}


def seed_notifications(emails: tuple[str, ...] | None) -> None:
    """Idempotent: an academy with any notification is left alone. The
    settings get their defaults, the scanner runs once (whatever the seeded
    data makes due: an overdue invoice, a low subscription, absences), then
    the samples. Their emails go out through the dev email backend (mailpit
    locally, files in the e2e job) like any other."""
    if emails is None or notifications_services.has_notifications():
        return
    notifications_services.current_settings()
    notifications_services.scan_now()
    for email in emails:
        try:
            user = identity_services.get_user_by_email(email)
        except NotFoundError:
            print(f"skip: {email} notifications — seeded record not found")  # noqa: T201
            continue
        notifications_services.add_samples(user)


class Command(BaseCommand):
```

In `backend/etqan/tenants/management/commands/seed_dev.py` (3 of 3), replace:

```python
                seed_payroll(PAYROLL.get(subdomain))
```

with:

```python
                seed_payroll(PAYROLL.get(subdomain))
                seed_notifications(NOTIFIED.get(subdomain))
```

In `backend/pyproject.toml`, replace:

```toml
forbidden_modules = ["etqan.notifications"]
```

with:

```toml
forbidden_modules = ["etqan.notifications"]
# The dev seeds are the one exception: they run a scan for the demo academy.
ignore_imports = [
    "etqan.tenants.management.commands.seed_dev -> etqan.notifications.services",
    "etqan.tenants.tests.test_seed_dev -> etqan.notifications.services",
]
```

- [ ] **Step 4: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/notifications etqan/tenants/tests/test_seed_dev.py -q
```

Expected: all pass (1 new in `test_samples.py`, 2 in `test_seed_dev.py`).

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 1245 tests, coverage 97.9% (the gate is 80%).

- [ ] **Step 6: Commit**

```bash
git -C backend add pyproject.toml etqan/notifications etqan/tenants
git -C backend commit -m "feat(seeds): notification settings, one scan and sample notices per demo role

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dashboard: the notifications data layer and the Notifications page

**Files:**
- Create: `dashboard/src/features/notifications/schemas.ts`, `api.ts`, `queries.ts`, `bits.tsx`, `NotificationsPage.tsx` (under `dashboard/src/features/notifications/`), `dashboard/src/routes/_authed/notifications.tsx`, `dashboard/src/test/notifications-fixtures.ts`
- Modify: `dashboard/src/features/notifications/index.ts` (empty since the Kaleem fork), `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (regenerated)
- Test: `dashboard/src/features/notifications/api.test.ts` (new), `dashboard/src/features/notifications/NotificationsPage.test.tsx` (new)

**Interfaces:**
- Consumes: Task 8's routes; `@/lib/api` (`api`, `clean`, `Paginated`, `QueryParams`); `useMe`/`meQueryKey`; `dayIn`, `wallTime`; `Pager`.
- Produces:
  - types `AppNotification {id, type, title, body, link, read_at, created_at}`, `NotificationSetting {type, enabled, value}`, `SettingChange {type, enabled, value?}`, `NotificationType`; `NOTIFICATION_TYPES` (spec order) and `TYPE_INFO` (each type's i18n key and, for the numbered ones, `{label, min, max, error}`);
  - `notificationsApi.list(params)`, `.unreadCount()`, `.read(id)`, `.readAll()`, `.settings()`, `.updateSettings(changes)`;
  - hooks `useUnreadCount()` (polls every `POLL_MS = 60_000`), `useNotifications(params, {enabled})`, `useMarkRead()`, `useMarkAllRead()`, `useOpenNotification() -> (n) => void` (marks an unread one read, then navigates to `n.link`), `useNotificationSettings()`, `useUpdateNotificationSettings()`; keys `notificationsKey = ["notifications"]` (every inbox query; one invalidation after a mark refreshes the list, the bell and the count) and `notificationSettingsKey`;
  - `<NotificationText notification>` (title, body, time on the reader's clock; unread bold with a dot and "Unread" for screen readers);
  - `<NotificationsPage />` and the route `/_authed/notifications` (every role).
- Produces (tests): `notificationRow(overrides)` and `notificationSettings(overrides)` in `@/test/notifications-fixtures`.

- [ ] **Step 1: Write the failing tests**

The page lists the caller's notifications, marks the unread ones, and shows times on the reader's clock (Riyadh, where 22:30 UTC on 31 May is already 1 June). It filters to unread, and it marks a notice read and follows its link, without re-marking one already read. It marks them all read, handles an empty inbox and a load error, and reads in Arabic.

Create `dashboard/src/test/notifications-fixtures.ts`:

```ts
import type {
	AppNotification,
	NotificationSetting,
} from "@/features/notifications/schemas";
import { NOTIFICATION_TYPES } from "@/features/notifications/schemas";

/** A notification as `notifications/` sends it: an unread reminder for a
 * parent, created at 18:00 UTC on 1 June 2026. */
export function notificationRow(
	overrides: Partial<AppNotification> = {},
): AppNotification {
	return {
		id: 31,
		type: "session.reminder",
		title: "Starting soon: Tajweed",
		body: "Tajweed with Yusuf starts at 2026-06-01 21:00 (Asia/Riyadh).",
		link: "/learning/sessions",
		read_at: null,
		created_at: "2026-06-01T18:00:00Z",
		...overrides,
	};
}

const DEFAULTS: Record<string, number | null> = {
	"session.early_reminder": 120,
	"session.reminder": 60,
	"session.teacher_reminder": 30,
	"session.late": 5,
	"subscription.low": 2,
};

/** All ten settings with the spec's defaults, every one switched on. */
export function notificationSettings(
	overrides: Partial<Record<string, Partial<NotificationSetting>>> = {},
): NotificationSetting[] {
	return NOTIFICATION_TYPES.map((type) => ({
		type,
		enabled: true,
		value: DEFAULTS[type] ?? null,
		...overrides[type],
	}));
}
```

Create `dashboard/src/features/notifications/api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { notificationsApi } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
	const ok = () => Promise.resolve({ data: { id: 1 } });
	return {
		...actual,
		api: { get: vi.fn(ok), post: vi.fn(ok), patch: vi.fn(ok) },
	};
});

describe("notificationsApi", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads the caller's notifications and the unread count", async () => {
		await notificationsApi.list({ unread: 1, page: 2, q: "" });
		expect(api.get).toHaveBeenCalledWith("notifications/", {
			params: { unread: "1", page: "2" },
		});
		await notificationsApi.unreadCount();
		expect(api.get).toHaveBeenLastCalledWith("notifications/unread-count/");
		await notificationsApi.settings();
		expect(api.get).toHaveBeenLastCalledWith("notifications/settings/");
	});

	it("marks read and saves settings", async () => {
		await notificationsApi.read(31);
		expect(api.post).toHaveBeenCalledWith("notifications/31/read/");
		await notificationsApi.readAll();
		expect(api.post).toHaveBeenLastCalledWith("notifications/read-all/");
		const changes = [
			{ type: "session.late" as const, enabled: true, value: 9 },
		];
		await notificationsApi.updateSettings(changes);
		expect(api.patch).toHaveBeenCalledWith("notifications/settings/", changes);
	});
});
```

Create `dashboard/src/features/notifications/NotificationsPage.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { meQueryKey } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
import i18n from "@/lib/i18n";
import { notificationRow } from "@/test/notifications-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { notificationsApi } from "./api";
import { NotificationsPage } from "./NotificationsPage";

vi.mock("./api", () => ({
	notificationsApi: {
		list: vi.fn(),
		unreadCount: vi.fn(),
		read: vi.fn(),
		readAll: vi.fn(),
	},
}));

// The reader lives in Riyadh (UTC+3): 22:30 UTC on 31 May is 1 June there.
const me: Me = {
	id: 7,
	email: "omar@demo.test",
	full_name: "Omar",
	role: "parent",
	profiles: ["parent"],
	timezone: "Asia/Riyadh",
};
const unread = notificationRow();
const read = notificationRow({
	id: 30,
	type: "invoice.overdue",
	title: "Invoice INV-000042 is overdue",
	body: "Invoice INV-000042 for Yusuf (1,500.00 EGP) was due on 2026-06-08.",
	link: "/learning/invoices/42",
	read_at: "2026-06-01T19:00:00Z",
	created_at: "2026-05-31T22:30:00Z",
});

function item(title: string) {
	return screen.getByText(title).closest("li") as HTMLElement;
}

describe("NotificationsPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(notificationsApi.list).mockResolvedValue(page([unread, read]));
		vi.mocked(notificationsApi.unreadCount).mockResolvedValue({ count: 1 });
		vi.mocked(notificationsApi.read).mockResolvedValue({
			...unread,
			read_at: "2026-06-01T19:05:00Z",
		});
		vi.mocked(notificationsApi.readAll).mockResolvedValue({ count: 1 });
	});
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("lists the notifications, the unread ones marked, on the reader's clock", async () => {
		const { client } = renderWithRouter(<NotificationsPage />);
		client.setQueryData(meQueryKey, me);
		await screen.findByText("Starting soon: Tajweed");
		expect(notificationsApi.list).toHaveBeenCalledWith({ page: 1 });
		const first = within(item("Starting soon: Tajweed"));
		expect(first.getByText("Unread")).toBeInTheDocument();
		const second = within(item("Invoice INV-000042 is overdue"));
		expect(second.queryByText("Unread")).toBeNull();
		expect(await second.findByText("Jun 1, 2026, 01:30")).toBeInTheDocument();
		expect(first.getByText("Jun 1, 2026, 21:00")).toBeInTheDocument();
	});

	it("shows only the unread ones when asked", async () => {
		const user = userEvent.setup();
		renderWithRouter(<NotificationsPage />);
		await screen.findByText("Starting soon: Tajweed");
		await user.selectOptions(screen.getByLabelText("Show"), "unread");
		await waitFor(() =>
			expect(notificationsApi.list).toHaveBeenLastCalledWith({
				page: 1,
				unread: 1,
			}),
		);
	});

	it("marks one read and follows its link", async () => {
		const user = userEvent.setup();
		const { router } = renderWithRouter(<NotificationsPage />, {
			extraPaths: ["/learning/sessions"],
		});
		await user.click(await screen.findByText("Starting soon: Tajweed"));
		await waitFor(() =>
			expect(router.state.location.pathname).toBe("/learning/sessions"),
		);
		expect(notificationsApi.read).toHaveBeenCalledWith(31);
	});

	it("follows a read one's link without marking it again", async () => {
		const user = userEvent.setup();
		const { router } = renderWithRouter(<NotificationsPage />, {
			extraPaths: ["/learning/invoices/$invoiceId"],
		});
		await user.click(await screen.findByText("Invoice INV-000042 is overdue"));
		await waitFor(() =>
			expect(router.state.location.pathname).toBe("/learning/invoices/42"),
		);
		expect(notificationsApi.read).not.toHaveBeenCalled();
	});

	it("marks them all read", async () => {
		const user = userEvent.setup();
		renderWithRouter(<NotificationsPage />);
		await user.click(
			await screen.findByRole("button", { name: "Mark all read" }),
		);
		await waitFor(() => expect(notificationsApi.readAll).toHaveBeenCalled());
		// The inbox is read again afterwards.
		await waitFor(() => expect(notificationsApi.list).toHaveBeenCalledTimes(2));
	});

	it("says when there is nothing, and when it couldn't load", async () => {
		vi.mocked(notificationsApi.list).mockResolvedValueOnce(page([]));
		vi.mocked(notificationsApi.unreadCount).mockResolvedValue({ count: 0 });
		const { unmount } = renderWithRouter(<NotificationsPage />);
		expect(
			await screen.findByText("No notifications yet."),
		).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Mark all read" })).toBeNull();
		unmount();
		vi.mocked(notificationsApi.list).mockRejectedValueOnce(
			new Error("offline"),
		);
		renderWithRouter(<NotificationsPage />);
		expect(
			await screen.findByText("Couldn't load notifications."),
		).toBeInTheDocument();
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		vi.mocked(notificationsApi.list).mockResolvedValue(page([]));
		renderWithRouter(<NotificationsPage />);
		expect(await screen.findByText("لا توجد إشعارات بعد.")).toBeInTheDocument();
		expect(screen.getByLabelText("عرض")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/notifications`

Expected: FAIL — `Failed to resolve import "./api"` (and `@/features/notifications/schemas` from the fixtures).

- [ ] **Step 3: Implement**

Create `dashboard/src/features/notifications/schemas.ts`:

```ts
/** The ten notices of spec §4.2, in the settings' order. */
export const NOTIFICATION_TYPES = [
	"session.early_reminder",
	"session.reminder",
	"session.teacher_reminder",
	"session.late",
	"session.student_absent",
	"subscription.low",
	"subscription.expired",
	"invoice.issued",
	"invoice.overdue",
	"report.missing",
] as const;
export type NotificationType = (typeof NOTIFICATION_TYPES)[number];

/** One of the caller's notifications (spec §5). `link` is a dashboard path
 * for the caller's role. Named so it never shadows the DOM's
 * `Notification`. */
export interface AppNotification {
	id: number;
	type: NotificationType;
	title: string;
	body: string;
	link: string;
	read_at: string | null;
	created_at: string;
}

export interface NotificationSetting {
	type: NotificationType;
	enabled: boolean;
	value: number | null;
}

export interface SettingChange {
	type: NotificationType;
	enabled: boolean;
	value?: number;
}

/** Each type's i18n key under `notifications.types` and, for the types with
 * a number, what the number means and its range (spec §4.2). */
export const TYPE_INFO: Record<
	NotificationType,
	{
		key: string;
		value?: { label: string; min: number; max: number; error: string };
	}
> = {
	"session.early_reminder": {
		key: "earlyReminder",
		value: {
			label: "minutesBefore",
			min: 30,
			max: 1440,
			error: "notifications.settings.errors.earlyRange",
		},
	},
	"session.reminder": {
		key: "reminder",
		value: {
			label: "minutesBefore",
			min: 5,
			max: 720,
			error: "notifications.settings.errors.reminderRange",
		},
	},
	"session.teacher_reminder": {
		key: "teacherReminder",
		value: {
			label: "minutesBefore",
			min: 5,
			max: 720,
			error: "notifications.settings.errors.reminderRange",
		},
	},
	"session.late": {
		key: "late",
		value: {
			label: "minutesAfter",
			min: 1,
			max: 55,
			error: "notifications.settings.errors.lateRange",
		},
	},
	"session.student_absent": { key: "studentAbsent" },
	"subscription.low": {
		key: "subscriptionLow",
		value: {
			label: "sessionsLeft",
			min: 0,
			max: 10,
			error: "notifications.settings.errors.lowRange",
		},
	},
	"subscription.expired": { key: "subscriptionExpired" },
	"invoice.issued": { key: "invoiceIssued" },
	"invoice.overdue": { key: "invoiceOverdue" },
	"report.missing": { key: "reportMissing" },
};
```

Create `dashboard/src/features/notifications/api.ts`:

```ts
import { api, clean, type Paginated, type QueryParams } from "@/lib/api";
import type {
	AppNotification,
	NotificationSetting,
	SettingChange,
} from "./schemas";

const N = "notifications/";

export const notificationsApi = {
	list: async (params: QueryParams) =>
		(await api.get<Paginated<AppNotification>>(N, { params: clean(params) }))
			.data,
	unreadCount: async () =>
		(await api.get<{ count: number }>(`${N}unread-count/`)).data,
	read: async (id: number) =>
		(await api.post<AppNotification>(`${N}${id}/read/`)).data,
	readAll: async () =>
		(await api.post<{ count: number }>(`${N}read-all/`)).data,
	settings: async () =>
		(await api.get<NotificationSetting[]>(`${N}settings/`)).data,
	updateSettings: async (changes: SettingChange[]) =>
		(await api.patch<NotificationSetting[]>(`${N}settings/`, changes)).data,
};
```

Create `dashboard/src/features/notifications/queries.ts`:

```ts
import {
	keepPreviousData,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import type { QueryParams } from "@/lib/api";
import { notificationsApi } from "./api";
import type { AppNotification, SettingChange } from "./schemas";

/** Every inbox query (the list, the bell and the unread count) lives under
 * this key, so one invalidation refreshes them all. */
export const notificationsKey = ["notifications"] as const;
export const notificationSettingsKey = ["notification-settings"] as const;
/** Spec §6: the bell polls the unread count every 60 s. */
export const POLL_MS = 60_000;

export function useUnreadCount() {
	return useQuery({
		queryKey: [...notificationsKey, "unread-count"],
		queryFn: notificationsApi.unreadCount,
		refetchInterval: POLL_MS,
	});
}

export function useNotifications(
	params: QueryParams,
	{ enabled = true }: { enabled?: boolean } = {},
) {
	return useQuery({
		queryKey: [...notificationsKey, "list", params],
		queryFn: () => notificationsApi.list(params),
		placeholderData: keepPreviousData,
		enabled,
	});
}

function useInboxMutation<A, R>(write: (args: A) => Promise<R>) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: write,
		onSuccess: () => qc.invalidateQueries({ queryKey: notificationsKey }),
	});
}

export function useMarkRead() {
	return useInboxMutation((id: number) => notificationsApi.read(id));
}

export function useMarkAllRead() {
	return useInboxMutation<void, { count: number }>(() =>
		notificationsApi.readAll(),
	);
}

/** Clicking a notification marks it read (when it is unread) and follows
 * its link (spec §6). */
export function useOpenNotification() {
	const markRead = useMarkRead();
	const navigate = useNavigate();
	return (notification: AppNotification) => {
		if (notification.read_at === null) markRead.mutate(notification.id);
		void navigate({ to: notification.link });
	};
}

export function useNotificationSettings() {
	return useQuery({
		queryKey: notificationSettingsKey,
		queryFn: notificationsApi.settings,
	});
}

export function useUpdateNotificationSettings() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (changes: SettingChange[]) =>
			notificationsApi.updateSettings(changes),
		onSuccess: (data) => qc.setQueryData(notificationSettingsKey, data),
	});
}
```

Create `dashboard/src/features/notifications/bits.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { useMe } from "@/features/identity/queries";
import { cn } from "@/lib/cn";
import { dayIn, wallTime } from "@/lib/zoned-time";
import type { AppNotification } from "./schemas";

/** One notification's title, body and time, as the bell and the page show
 * it. Unread ones are bold with a dot, and say so to screen readers. The
 * time is on the reader's own clock. */
export function NotificationText({
	notification,
}: {
	notification: AppNotification;
}) {
	const { t, i18n } = useTranslation();
	const { data: me } = useMe();
	const zone = me?.timezone ?? "UTC";
	const at = new Date(notification.created_at);
	const unread = notification.read_at === null;
	return (
		<span className="flex min-w-0 flex-col gap-0.5 text-start">
			<span
				className={cn(
					"flex items-center gap-2",
					unread ? "font-semibold" : "font-normal",
				)}
			>
				{unread ? (
					<span
						aria-hidden="true"
						className="size-2 shrink-0 rounded-full bg-primary"
					/>
				) : null}
				<span dir="auto">{notification.title}</span>
				{unread ? (
					<span className="sr-only">{t("notifications.unread")}</span>
				) : null}
			</span>
			<span dir="auto" className="text-sm text-muted-foreground">
				{notification.body}
			</span>
			<span className="text-xs text-muted-foreground">
				{t("notifications.when", {
					day: dayIn(at, zone, i18n.language),
					time: wallTime(at, zone, i18n.language),
				})}
			</span>
		</span>
	);
}
```

Create `dashboard/src/features/notifications/NotificationsPage.tsx`:

```tsx
import { Bell } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { cn } from "@/lib/cn";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	EmptyState,
	Field,
	Select,
	Spinner,
} from "@/ui";
import { NotificationText } from "./bits";
import {
	useMarkAllRead,
	useNotifications,
	useOpenNotification,
	useUnreadCount,
} from "./queries";

const PAGE_SIZE = 25;
type Filter = "all" | "unread";

/** Spec §6 Notifications page (every role): the caller's notifications,
 * newest first, All or Unread, paged. Clicking one marks it read and
 * follows its link. */
export function NotificationsPage() {
	const { t } = useTranslation();
	const [filter, setFilter] = useState<Filter>("all");
	const [page, setPage] = useState(1);
	const { data, isPending, isError } = useNotifications({
		page,
		unread: filter === "unread" ? 1 : undefined,
	});
	const unread = useUnreadCount().data?.count ?? 0;
	const markAll = useMarkAllRead();
	const open = useOpenNotification();
	const rows = data?.results ?? [];
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end justify-between gap-3">
				<Field id="notifications-filter" label={t("notifications.filter")}>
					<Select
						value={filter}
						onChange={(event) => {
							setFilter(event.target.value as Filter);
							setPage(1);
						}}
					>
						<option value="all">{t("notifications.all")}</option>
						<option value="unread">{t("notifications.unreadOnly")}</option>
					</Select>
				</Field>
				{unread > 0 ? (
					<Button
						variant="outline"
						disabled={markAll.isPending}
						onClick={() => markAll.mutate()}
					>
						{t("notifications.markAllRead")}
					</Button>
				) : null}
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("notifications.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<Spinner />
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState
							icon={Bell}
							title={
								filter === "unread"
									? t("notifications.emptyUnread")
									: t("notifications.empty")
							}
						/>
					</CardContent>
				</Card>
			) : (
				<ul className="flex flex-col gap-2">
					{rows.map((notification) => (
						<li key={notification.id}>
							<button
								type="button"
								onClick={() => open(notification)}
								className={cn(
									"w-full rounded-lg border p-4 text-start hover:bg-secondary",
									notification.read_at === null
										? "border-primary bg-card"
										: "border-border bg-background",
								)}
							>
								<NotificationText notification={notification} />
							</button>
						</li>
					))}
				</ul>
			)}
			<Pager page={page} pages={pages} onChange={setPage} />
		</div>
	);
}
```

Replace the whole of `dashboard/src/features/notifications/index.ts` with:

```ts
export { notificationsApi } from "./api";
export { NotificationText } from "./bits";
export { NotificationsPage } from "./NotificationsPage";
export * from "./queries";
export * from "./schemas";
```

Create `dashboard/src/routes/_authed/notifications.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { NotificationsPage } from "@/features/notifications";
import { PageContainer, PageHeader } from "@/ui";

// Every role (spec §6): no role guard beyond `_authed`'s sign-in.
export const Route = createFileRoute("/_authed/notifications")({
	component: function NotificationsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("notifications.title"));
		return (
			<PageContainer>
				<PageHeader title={t("notifications.title")} />
				<NotificationsPage />
			</PageContainer>
		);
	},
});
```

Merge into `dashboard/src/locales/en/common.json` (English, a new top-level object):

```json
{
	"notifications": {
		"title": "Notifications",
		"bell": "Notifications",
		"bellUnread": "Notifications, {{count}} unread",
		"markAllRead": "Mark all read",
		"seeAll": "See all",
		"empty": "No notifications yet.",
		"emptyUnread": "No unread notifications.",
		"loadError": "Couldn't load notifications.",
		"unread": "Unread",
		"when": "{{day}}, {{time}}",
		"filter": "Show",
		"all": "All",
		"unreadOnly": "Unread only"
	}
}
```

Merge into `dashboard/src/locales/ar/common.json` (Arabic, a new top-level object):

```json
{
	"notifications": {
		"title": "الإشعارات",
		"bell": "الإشعارات",
		"bellUnread": "الإشعارات، {{count}} غير مقروءة",
		"markAllRead": "تعليم الكل كمقروء",
		"seeAll": "عرض الكل",
		"empty": "لا توجد إشعارات بعد.",
		"emptyUnread": "لا توجد إشعارات غير مقروءة.",
		"loadError": "تعذّر تحميل الإشعارات.",
		"unread": "غير مقروء",
		"when": "{{day}}، {{time}}",
		"filter": "عرض",
		"all": "الكل",
		"unreadOnly": "غير المقروءة فقط"
	}
}
```

- [ ] **Step 4: Format, regenerate the route tree, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build
npx pnpm@10 exec vitest run src/features/notifications
```

Expected: 9 passed.

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 630 tests (621 before Task 10); coverage lines 93.91%, branches 87.02%, functions 80.5% (gates 80/70/70).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(notifications): the notifications data layer and page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Dashboard: the bell in the top bar

**Files:**
- Create: `dashboard/src/features/notifications/NotificationBell.tsx`
- Modify: `dashboard/src/features/notifications/index.ts`, `dashboard/src/features/shell/AppTopbar.tsx`, `dashboard/src/ui/locale-toggle.tsx`
- Test: `dashboard/src/features/notifications/NotificationBell.test.tsx` (new), `dashboard/src/features/shell/AppTopbar.test.tsx` (its `api.get` mock answers by URL, and it asserts the bell), `dashboard/src/features/shell/AppShell.test.tsx` (stubs the unread count)

**Interfaces:**
- Consumes: Task 10's hooks, `NotificationText`, the `/notifications` route and the `notifications.*` strings.
- Produces: `<NotificationBell />` (exported with `LATEST = 10` from `@/features/notifications`), placed in `AppTopbar` after the theme toggle for every role. Its accessible name is `Notifications` or `Notifications, N unread`; the badge caps at `99+`. Below `sm` the language toggle shows only its icon, so the top bar still fits 320 px with the bell.

- [ ] **Step 1: Write the failing tests**

The bell shows the unread count and reads the latest ten only when opened. A click on an item marks it read and follows its link, and the count is re-read. "Mark all read" keeps the menu open. The count is polled every minute. The top bar shows the bell.

Create `dashboard/src/features/notifications/NotificationBell.test.tsx`:

```tsx
import { act, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { notificationRow } from "@/test/notifications-fixtures";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { notificationsApi } from "./api";
import { NotificationBell } from "./NotificationBell";
import { POLL_MS } from "./queries";

vi.mock("./api", () => ({
	notificationsApi: {
		list: vi.fn(),
		unreadCount: vi.fn(),
		read: vi.fn(),
		readAll: vi.fn(),
	},
}));

const reminder = notificationRow();
const overdue = notificationRow({
	id: 30,
	type: "invoice.overdue",
	title: "Invoice INV-000042 is overdue",
	link: "/learning/invoices/42",
	read_at: "2026-06-01T19:00:00Z",
});

async function openBell(name: string | RegExp) {
	const user = userEvent.setup();
	await user.click(await screen.findByRole("button", { name }));
	return { user, menu: await screen.findByRole("menu") };
}

describe("NotificationBell", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(notificationsApi.unreadCount).mockResolvedValue({ count: 3 });
		vi.mocked(notificationsApi.list).mockResolvedValue(
			page([reminder, overdue]),
		);
		vi.mocked(notificationsApi.read).mockResolvedValue(reminder);
		vi.mocked(notificationsApi.readAll).mockResolvedValue({ count: 3 });
	});
	afterEach(async () => {
		vi.useRealTimers();
		await i18n.changeLanguage("en");
	});

	it("shows the unread count and reads the list only when opened", async () => {
		renderWithRouter(<NotificationBell />);
		const bell = await screen.findByRole("button", {
			name: "Notifications, 3 unread",
		});
		expect(within(bell).getByText("3")).toBeInTheDocument();
		expect(notificationsApi.list).not.toHaveBeenCalled();
		const { menu } = await openBell("Notifications, 3 unread");
		expect(notificationsApi.list).toHaveBeenCalledWith({ page_size: 10 });
		expect(
			await within(menu).findByText("Starting soon: Tajweed"),
		).toBeInTheDocument();
		expect(
			within(menu).getByText("Invoice INV-000042 is overdue"),
		).toBeInTheDocument();
		expect(
			within(menu).getByRole("menuitem", { name: "See all" }),
		).toHaveAttribute("href", "/notifications");
	});

	it("has no badge when everything is read", async () => {
		vi.mocked(notificationsApi.unreadCount).mockResolvedValue({ count: 0 });
		renderWithRouter(<NotificationBell />);
		await waitFor(() =>
			expect(notificationsApi.unreadCount).toHaveBeenCalled(),
		);
		const bell = screen.getByRole("button", { name: "Notifications" });
		expect(within(bell).queryByText(/\d/)).toBeNull();
	});

	it("caps the badge at 99+", async () => {
		vi.mocked(notificationsApi.unreadCount).mockResolvedValue({ count: 140 });
		renderWithRouter(<NotificationBell />);
		const bell = await screen.findByRole("button", {
			name: "Notifications, 140 unread",
		});
		expect(bell).toHaveTextContent("99+");
	});

	it("marks one read and follows its link", async () => {
		const { router } = renderWithRouter(<NotificationBell />, {
			extraPaths: ["/learning/sessions"],
		});
		const { user, menu } = await openBell(/unread/);
		await user.click(await within(menu).findByText("Starting soon: Tajweed"));
		await waitFor(() =>
			expect(router.state.location.pathname).toBe("/learning/sessions"),
		);
		expect(notificationsApi.read).toHaveBeenCalledWith(31);
		// The count is read again once it is marked.
		await waitFor(() =>
			expect(notificationsApi.unreadCount).toHaveBeenCalledTimes(2),
		);
	});

	it("marks all read and stays open", async () => {
		const { user, menu } = await (async () => {
			renderWithRouter(<NotificationBell />);
			return openBell(/unread/);
		})();
		await user.click(
			within(menu).getByRole("menuitem", { name: "Mark all read" }),
		);
		await waitFor(() => expect(notificationsApi.readAll).toHaveBeenCalled());
		expect(screen.getByRole("menu")).toBeInTheDocument();
		await waitFor(() => expect(notificationsApi.list).toHaveBeenCalledTimes(2));
	});

	it("says when there is nothing and when the list couldn't load", async () => {
		vi.mocked(notificationsApi.list).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<NotificationBell />);
		const { menu } = await openBell(/unread/);
		expect(
			await within(menu).findByText("No notifications yet."),
		).toBeInTheDocument();
		unmount();
		vi.mocked(notificationsApi.list).mockRejectedValueOnce(
			new Error("offline"),
		);
		renderWithRouter(<NotificationBell />);
		const second = await openBell(/unread/);
		expect(
			await within(second.menu).findByText("Couldn't load notifications."),
		).toBeInTheDocument();
	});

	it("polls the unread count every minute", async () => {
		vi.useFakeTimers({ shouldAdvanceTime: true });
		renderWithRouter(<NotificationBell />);
		await waitFor(() =>
			expect(notificationsApi.unreadCount).toHaveBeenCalledTimes(1),
		);
		await act(async () => {
			await vi.advanceTimersByTimeAsync(POLL_MS);
		});
		await waitFor(() =>
			expect(notificationsApi.unreadCount).toHaveBeenCalledTimes(2),
		);
	});

	it("reads in Arabic", async () => {
		await i18n.changeLanguage("ar");
		renderWithRouter(<NotificationBell />);
		expect(
			await screen.findByRole("button", { name: "الإشعارات، 3 غير مقروءة" }),
		).toBeInTheDocument();
	});
});
```

Replace the whole of `dashboard/src/features/shell/AppTopbar.test.tsx` with:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
	createMemoryHistory,
	createRootRoute,
	createRoute,
	createRouter,
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { api } from "@/lib/api";
import { ThemeProvider } from "@/lib/theme";
import {
	OTHER_ACCENT,
	OTHER_PRIMARY,
	OTHER_PRIMARY_TEXT,
} from "@/test/branding-fixtures";
import { AppTopbar } from "./AppTopbar";

const BRANDING = {
	name: { ar: "إتقان", en: "etqan" },
	tagline: { ar: "", en: "" },
	logo_url: "",
	favicon_url: "",
	share_image_url: "",
	primary_color: OTHER_PRIMARY,
	primary_text: OTHER_PRIMARY_TEXT,
	accent_color: OTHER_ACCENT,
	contact: {
		email: "",
		phone: "",
		whatsapp: "",
		address: { ar: "", en: "" },
	},
	social: {},
	show_powered_by: true,
};

beforeEach(() => {
	// The branding, and Plan 8's unread count for the bell.
	vi.spyOn(api, "get").mockImplementation(async (url) => ({
		data: url === "notifications/unread-count/" ? { count: 2 } : BRANDING,
	}));
});

function renderTopbar(onOpenMenu = () => {}) {
	const queryClient = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	const rootRoute = createRootRoute({
		component: () => (
			<AppTopbar userName="Sara" onSignOut={() => {}} onOpenMenu={onOpenMenu} />
		),
	});
	const profile = createRoute({
		getParentRoute: () => rootRoute,
		path: "/account",
		component: () => null,
	});
	const router = createRouter({
		routeTree: rootRoute.addChildren([profile]),
		history: createMemoryHistory({ initialEntries: ["/"] }),
	});
	return render(
		<QueryClientProvider client={queryClient}>
			<ThemeProvider>
				<RouterProvider router={router} />
			</ThemeProvider>
		</QueryClientProvider>,
	);
}

describe("AppTopbar", () => {
	it("renders the brand, toggles, the bell and the user menu", async () => {
		renderTopbar();
		await screen.findByRole("button", { name: /account menu/i });
		expect(await screen.findByText(/etqan/i)).toBeInTheDocument();
		expect(
			screen.getByRole("button", { name: /toggle theme/i }),
		).toBeInTheDocument();
		expect(
			screen.getByRole("button", { name: /switch language/i }),
		).toBeInTheDocument();
		expect(
			screen.getByRole("button", { name: /account menu/i }),
		).toHaveTextContent("Sara");
		expect(
			await screen.findByRole("button", { name: "Notifications, 2 unread" }),
		).toBeInTheDocument();
	});

	it("fires onOpenMenu from the hamburger", async () => {
		const onOpenMenu = vi.fn();
		renderTopbar(onOpenMenu);
		await screen.findByRole("button", { name: /account menu/i });
		await userEvent.click(screen.getByRole("button", { name: /open menu/i }));
		expect(onOpenMenu).toHaveBeenCalledOnce();
	});

	it("has no axe violations", async () => {
		const { container } = renderTopbar();
		await screen.findByRole("button", { name: /account menu/i });
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

In `dashboard/src/features/shell/AppShell.test.tsx` (1 of 3), replace:

```tsx
import { afterEach, describe, expect, it, vi } from "vitest";
```

with:

```tsx
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
```

In `dashboard/src/features/shell/AppShell.test.tsx` (2 of 3), replace:

```tsx
import type { Me } from "@/features/identity/schemas";
```

with:

```tsx
import type { Me } from "@/features/identity/schemas";
import { notificationsApi } from "@/features/notifications";
```

In `dashboard/src/features/shell/AppShell.test.tsx` (3 of 3), replace:

```tsx
afterEach(() => vi.restoreAllMocks());
```

with:

```tsx
beforeEach(() => {
	// Plan 8: the top bar's bell reads the unread count.
	vi.spyOn(notificationsApi, "unreadCount").mockResolvedValue({ count: 0 });
});
afterEach(() => vi.restoreAllMocks());
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/notifications src/features/shell`

Expected: FAIL — `Failed to resolve import "./NotificationBell"`; the top bar has no `Notifications, 2 unread` button.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/notifications/NotificationBell.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Bell } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Button } from "@/ui";
import { NotificationText } from "./bits";
import {
	useMarkAllRead,
	useNotifications,
	useOpenNotification,
	useUnreadCount,
} from "./queries";

/** The bell shows the latest ten (spec §6). */
export const LATEST = 10;
const MAX_BADGE = 99;
const itemClass =
	"flex w-full cursor-pointer items-start gap-2 rounded-sm px-2 py-2 text-sm outline-none focus:bg-secondary focus:text-foreground";

/** Spec §6 the bell, in the top bar for every role: the unread count, polled
 * every minute, and a dropdown of the latest ten with "Mark all read" and
 * "See all". The list is read only while the dropdown is open. */
export function NotificationBell() {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	const count = useUnreadCount().data?.count ?? 0;
	const latest = useNotifications({ page_size: LATEST }, { enabled: open });
	const markAll = useMarkAllRead();
	const openNotification = useOpenNotification();
	const rows = latest.data?.results ?? [];
	return (
		<DropdownMenu.Root open={open} onOpenChange={setOpen}>
			<DropdownMenu.Trigger asChild>
				<Button
					variant="outline"
					size="icon"
					className="relative"
					aria-label={
						count > 0
							? t("notifications.bellUnread", { count })
							: t("notifications.bell")
					}
				>
					<Bell className="size-4" />
					{count > 0 ? (
						<span
							aria-hidden="true"
							className="absolute -end-1 -top-1 min-w-5 rounded-full bg-destructive px-1 text-xs font-semibold leading-5 text-destructive-foreground"
						>
							{count > MAX_BADGE ? `${MAX_BADGE}+` : count}
						</span>
					) : null}
				</Button>
			</DropdownMenu.Trigger>
			<DropdownMenu.Portal>
				<DropdownMenu.Content
					align="end"
					sideOffset={6}
					className="z-50 w-80 max-w-[calc(100vw-2rem)] rounded-md border border-border bg-popover p-1 text-popover-foreground shadow-md"
				>
					<div className="flex items-center justify-between gap-2 px-2 py-1.5">
						<DropdownMenu.Label className="text-sm font-medium">
							{t("notifications.title")}
						</DropdownMenu.Label>
						{count > 0 ? (
							<DropdownMenu.Item
								className="cursor-pointer rounded-sm px-2 py-1 text-sm text-primary-text outline-none focus:bg-secondary"
								onSelect={(event) => {
									// Stay open: the list re-reads as read.
									event.preventDefault();
									markAll.mutate();
								}}
							>
								{t("notifications.markAllRead")}
							</DropdownMenu.Item>
						) : null}
					</div>
					<DropdownMenu.Separator className="my-1 h-px bg-border" />
					{latest.isError ? (
						<p className="px-2 py-3 text-sm text-destructive">
							{t("notifications.loadError")}
						</p>
					) : latest.isPending ? (
						<p className="px-2 py-3 text-sm text-muted-foreground">
							{t("common.loading")}
						</p>
					) : rows.length === 0 ? (
						<p className="px-2 py-3 text-sm text-muted-foreground">
							{t("notifications.empty")}
						</p>
					) : (
						rows.map((notification) => (
							<DropdownMenu.Item
								key={notification.id}
								className={itemClass}
								onSelect={() => openNotification(notification)}
							>
								<NotificationText notification={notification} />
							</DropdownMenu.Item>
						))
					)}
					<DropdownMenu.Separator className="my-1 h-px bg-border" />
					<DropdownMenu.Item asChild>
						<Link
							to="/notifications"
							className="flex w-full cursor-pointer justify-center rounded-sm px-2 py-2 text-sm font-medium text-primary-text outline-none focus:bg-secondary"
						>
							{t("notifications.seeAll")}
						</Link>
					</DropdownMenu.Item>
				</DropdownMenu.Content>
			</DropdownMenu.Portal>
		</DropdownMenu.Root>
	);
}
```

Replace the whole of `dashboard/src/features/notifications/index.ts` with:

```ts
export { notificationsApi } from "./api";
export { NotificationText } from "./bits";
export { LATEST, NotificationBell } from "./NotificationBell";
export { NotificationsPage } from "./NotificationsPage";
export * from "./queries";
export * from "./schemas";
```

In `dashboard/src/features/shell/AppTopbar.tsx` (1 of 2), replace:

```tsx
import { BrandWordmark } from "@/features/branding";
```

with:

```tsx
import { BrandWordmark } from "@/features/branding";
import { NotificationBell } from "@/features/notifications";
```

In `dashboard/src/features/shell/AppTopbar.tsx` (2 of 2), replace:

```tsx
				<ThemeToggle />
				<span
```

with:

```tsx
				<ThemeToggle />
				{/* Plan 8: every role's bell, next to the account menu. */}
				<NotificationBell />
				<span
```

In `dashboard/src/ui/locale-toggle.tsx`, replace:

```tsx
			<Languages className="size-4" />
			{next === "ar" ? "العربية" : "EN"}
```

with:

```tsx
			<Languages className="size-4" />
			{/* Icon only below `sm` (Plan 8): the bell joined the top bar, and at
			    320px the row must not scroll sideways (SC 1.4.10). The aria-label
			    names the control either way. */}
			<span className="hidden sm:inline">
				{next === "ar" ? "العربية" : "EN"}
			</span>
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vitest run src/features/notifications src/features/shell src/ui
```

Expected: all pass (8 new in `NotificationBell.test.tsx`).

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 638 tests (621 before Task 10); coverage lines 93.95%, branches 87.12%, functions 80.57% (gates 80/70/70).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(notifications): the bell in the top bar

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Dashboard: the Notifications section of the academy settings

**Files:**
- Create: `dashboard/src/features/notifications/NotificationSettingsForm.tsx`
- Modify: `dashboard/src/features/notifications/index.ts`, `dashboard/src/routes/_authed/settings.academy.tsx`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/notifications/NotificationSettingsForm.test.tsx` (new)

**Interfaces:**
- Consumes: Task 10's `useNotificationSettings`, `useUpdateNotificationSettings`, `NOTIFICATION_TYPES`, `TYPE_INFO`, `SettingChange`; Task 8's `400 {"<type>.value": [...]}`; `applyServerErrors`, `useFieldError`, `Field`, `Checkbox`.
- Produces: `<NotificationSettingsForm />` under the academy settings form. It has one `fieldset` per type (the legend names the type), a "Send this notice" switch, and a number field for the five numbered types. The field names are the types themselves (`session.late.value`), so a server error lands on its field. Saving sends all ten as `[{type, enabled, value?}]`.

- [ ] **Step 1: Write the failing tests**

The section shows each type's switch and number (a type with no number has only the switch). It saves every switch and number, and checks each range before saving, with the range in the message. A server error lands inside the type's own fieldset. It says when the settings couldn't load, and it reads in Arabic.

Create `dashboard/src/features/notifications/NotificationSettingsForm.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, AxiosHeaders } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { notificationSettings } from "@/test/notifications-fixtures";
import { renderWithRouter } from "@/test/render";
import { notificationsApi } from "./api";
import { NotificationSettingsForm } from "./NotificationSettingsForm";

vi.mock("./api", () => ({
	notificationsApi: { settings: vi.fn(), updateSettings: vi.fn() },
}));

// A role query's name is matched whole, so "Session reminder" never finds
// "Early session reminder" or "Teacher's session reminder".
const group = (name: string) => screen.getByRole("group", { name });

function badRequest(data: Record<string, string[]>) {
	return new AxiosError("Bad Request", "400", undefined, undefined, {
		status: 400,
		statusText: "Bad Request",
		data,
		headers: {},
		config: { headers: new AxiosHeaders() },
	});
}

describe("NotificationSettingsForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(notificationsApi.settings).mockResolvedValue(
			notificationSettings({ "session.late": { value: 10 } }),
		);
		vi.mocked(notificationsApi.updateSettings).mockImplementation(
			async (changes) => changes.map((c) => ({ ...c, value: c.value ?? null })),
		);
	});
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("shows each type's switch and number", async () => {
		renderWithRouter(<NotificationSettingsForm />);
		const late = await screen.findByRole("group", {
			name: "Session not started",
		});
		expect(within(late).getByLabelText("Minutes after the start")).toHaveValue(
			10,
		);
		expect(
			within(late).getByRole("checkbox", { name: "Send this notice" }),
		).toBeChecked();
		// A type with no number has only its switch.
		const absent = group("Student absent");
		expect(within(absent).queryByRole("spinbutton")).toBeNull();
		expect(
			within(group("Session reminder")).getByLabelText(
				"Minutes before the start",
			),
		).toHaveValue(60);
		expect(screen.getAllByRole("group")).toHaveLength(10);
	});

	it("saves every switch and number", async () => {
		const user = userEvent.setup();
		renderWithRouter(<NotificationSettingsForm />);
		const reminder = await screen.findByRole("group", {
			name: "Session reminder",
		});
		await user.click(
			within(reminder).getByRole("checkbox", { name: "Send this notice" }),
		);
		const low = within(group("Few sessions left")).getByLabelText(
			"When this many sessions are left",
		);
		await user.clear(low);
		await user.type(low, "0");
		await user.click(
			screen.getByRole("button", { name: "Save notifications" }),
		);
		await waitFor(() =>
			expect(notificationsApi.updateSettings).toHaveBeenCalled(),
		);
		const changes = vi.mocked(notificationsApi.updateSettings).mock.calls[0][0];
		expect(changes).toHaveLength(10);
		expect(changes).toContainEqual({
			type: "session.reminder",
			enabled: false,
			value: 60,
		});
		expect(changes).toContainEqual({
			type: "subscription.low",
			enabled: true,
			value: 0,
		});
		expect(changes).toContainEqual({ type: "invoice.overdue", enabled: true });
		expect(await screen.findByText("Saved.")).toBeInTheDocument();
	});

	it("checks each number's range before saving", async () => {
		const user = userEvent.setup();
		renderWithRouter(<NotificationSettingsForm />);
		const late = within(
			await screen.findByRole("group", { name: "Session not started" }),
		).getByLabelText("Minutes after the start");
		await user.clear(late);
		await user.type(late, "56");
		const early = within(group("Early session reminder")).getByLabelText(
			"Minutes before the start",
		);
		await user.clear(early);
		await user.click(
			screen.getByRole("button", { name: "Save notifications" }),
		);
		expect(
			await screen.findByText("Choose 1 to 55 minutes."),
		).toBeInTheDocument();
		expect(screen.getByText("Choose 30 to 1440 minutes.")).toBeInTheDocument();
		expect(notificationsApi.updateSettings).not.toHaveBeenCalled();
	});

	it("puts the server's error on its field", async () => {
		vi.mocked(notificationsApi.updateSettings).mockRejectedValueOnce(
			badRequest({ "session.late.value": ["Choose a number from 1 to 55."] }),
		);
		const user = userEvent.setup();
		renderWithRouter(<NotificationSettingsForm />);
		await screen.findByRole("group", { name: "Session not started" });
		await user.click(
			screen.getByRole("button", { name: "Save notifications" }),
		);
		const late = group("Session not started");
		expect(
			await within(late).findByText("Choose a number from 1 to 55."),
		).toBeInTheDocument();
	});

	it("says when the settings couldn't load, and reads in Arabic", async () => {
		vi.mocked(notificationsApi.settings).mockRejectedValueOnce(
			new Error("offline"),
		);
		const { unmount } = renderWithRouter(<NotificationSettingsForm />);
		expect(
			await screen.findByText("Couldn't load the notification settings."),
		).toBeInTheDocument();
		unmount();
		await i18n.changeLanguage("ar");
		renderWithRouter(<NotificationSettingsForm />);
		expect(
			await screen.findByRole("group", { name: "غياب الطالب" }),
		).toBeInTheDocument();
		expect(
			screen.getByRole("button", { name: "احفظ الإشعارات" }),
		).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/notifications/NotificationSettingsForm.test.tsx`

Expected: FAIL — `Failed to resolve import "./NotificationSettingsForm"`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/notifications/NotificationSettingsForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import {
	type Control,
	get,
	type Path,
	type UseFormRegister,
	useController,
	useForm,
} from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Checkbox,
	Field,
	Input,
	Spinner,
	SubmitButton,
	toast,
} from "@/ui";
import {
	useNotificationSettings,
	useUpdateNotificationSettings,
} from "./queries";
import {
	NOTIFICATION_TYPES,
	type NotificationSetting,
	type NotificationType,
	type SettingChange,
	TYPE_INFO,
} from "./schemas";

const toggle = z.object({ enabled: z.boolean() });

/** A type with a number: its range and message come from `TYPE_INFO`, the
 * one table of spec §4.2's ranges. */
function numbered(type: NotificationType) {
	const range = TYPE_INFO[type].value;
	if (!range) throw new Error(`${type} has no number`);
	const message = range.error;
	return z.object({
		enabled: z.boolean(),
		value: z
			.number({ error: message })
			.int(message)
			.min(range.min, message)
			.max(range.max, message),
	});
}

// Field names are the types themselves (`session.late.value`), so a server
// error on `<type>.value` lands on its field.
const schema = z.object({
	session: z.object({
		early_reminder: numbered("session.early_reminder"),
		reminder: numbered("session.reminder"),
		teacher_reminder: numbered("session.teacher_reminder"),
		late: numbered("session.late"),
		student_absent: toggle,
	}),
	subscription: z.object({
		low: numbered("subscription.low"),
		expired: toggle,
	}),
	invoice: z.object({ issued: toggle, overdue: toggle }),
	report: z.object({ missing: toggle }),
});
type Values = z.infer<typeof schema>;
type Row = { enabled: boolean; value?: number };

function rowOf(values: Values, type: NotificationType): Row {
	return get(values, type) as Row;
}

function toValues(rows: NotificationSetting[]): Values {
	const values: Record<string, Record<string, Row>> = {};
	for (const row of rows) {
		const [group, name] = row.type.split(".");
		values[group] ??= {};
		values[group][name] = TYPE_INFO[row.type].value
			? { enabled: row.enabled, value: row.value ?? undefined }
			: { enabled: row.enabled };
	}
	return values as unknown as Values;
}

function toChanges(values: Values): SettingChange[] {
	return NOTIFICATION_TYPES.map((type) => {
		const row = rowOf(values, type);
		return TYPE_INFO[type].value
			? { type, enabled: row.enabled, value: row.value }
			: { type, enabled: row.enabled };
	});
}

function SettingRow({
	type,
	control,
	register,
	error,
}: {
	type: NotificationType;
	control: Control<Values>;
	register: UseFormRegister<Values>;
	error?: string;
}) {
	const { t } = useTranslation();
	const info = TYPE_INFO[type];
	const id = type.replace(".", "-");
	const enabled = useController({
		control,
		name: `${type}.enabled` as Path<Values>,
	});
	return (
		<fieldset className="flex flex-col gap-3 rounded-md border border-border p-3">
			<legend className="px-1 text-sm font-medium">
				{t(`notifications.types.${info.key}`)}
			</legend>
			<label
				htmlFor={`${id}-enabled`}
				className="flex items-center gap-2 text-sm"
			>
				<Checkbox
					id={`${id}-enabled`}
					checked={enabled.field.value === true}
					onCheckedChange={enabled.field.onChange}
				/>
				{t("notifications.settings.send")}
			</label>
			{info.value ? (
				<Field
					id={`${id}-value`}
					label={t(`notifications.settings.${info.value.label}`)}
					error={error}
				>
					<Input
						type="number"
						min={info.value.min}
						max={info.value.max}
						{...register(`${type}.value` as Path<Values>, {
							valueAsNumber: true,
						})}
					/>
				</Field>
			) : null}
		</fieldset>
	);
}

/** Spec §6 the academy settings' Notifications section (admins): a switch for
 * each of the ten types and a number for the timed ones and the low
 * threshold. Saving answers with the fresh settings; errors land on their
 * field. */
export function NotificationSettingsForm() {
	const { t } = useTranslation();
	const { data, isError } = useNotificationSettings();
	const update = useUpdateNotificationSettings();
	const fieldError = useFieldError();
	const {
		register,
		control,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<Values>({
		resolver: zodResolver(schema),
		values: data ? toValues(data) : undefined,
	});

	async function onSubmit(values: Values) {
		try {
			await update.mutateAsync(toChanges(values));
			toast({ description: t("people.saved"), variant: "success" });
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<section
			aria-labelledby="notification-settings-title"
			className="mt-10 flex max-w-md flex-col gap-4"
		>
			<h2
				id="notification-settings-title"
				className="font-display text-xl font-semibold"
			>
				{t("notifications.settings.title")}
			</h2>
			<p className="text-sm text-muted-foreground">
				{t("notifications.settings.hint")}
			</p>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>
						{t("notifications.settings.loadError")}
					</AlertDescription>
				</Alert>
			) : !data ? (
				<Spinner />
			) : (
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="flex flex-col gap-3"
					noValidate
				>
					{NOTIFICATION_TYPES.map((type) => (
						<SettingRow
							key={type}
							type={type}
							control={control}
							register={register}
							error={fieldError(get(errors, `${type}.value`)?.message)}
						/>
					))}
					<SubmitButton pending={isSubmitting} className="self-start">
						{t("notifications.settings.save")}
					</SubmitButton>
				</form>
			)}
		</section>
	);
}
```

In `dashboard/src/features/notifications/index.ts`, replace:

```ts
export { LATEST, NotificationBell } from "./NotificationBell";
```

with:

```ts
export { LATEST, NotificationBell } from "./NotificationBell";
export { NotificationSettingsForm } from "./NotificationSettingsForm";
```

In `dashboard/src/routes/_authed/settings.academy.tsx` (1 of 2), replace:

```tsx
import { requireAdmin } from "@/features/identity/require-admin";
```

with:

```tsx
import { requireAdmin } from "@/features/identity/require-admin";
import { NotificationSettingsForm } from "@/features/notifications";
```

In `dashboard/src/routes/_authed/settings.academy.tsx` (2 of 2), replace:

```tsx
				<AcademySettingsForm />
```

with:

```tsx
				<AcademySettingsForm />
				{/* Plan 8: the notification switches and numbers (spec §6). */}
				<NotificationSettingsForm />
```

Merge into `dashboard/src/locales/en/common.json` (English, into the `notifications` object):

```json
{
	"notifications": {
		"types": {
			"earlyReminder": "Early session reminder",
			"reminder": "Session reminder",
			"teacherReminder": "Teacher's session reminder",
			"late": "Session not started",
			"studentAbsent": "Student absent",
			"subscriptionLow": "Few sessions left",
			"subscriptionExpired": "Subscription ended",
			"invoiceIssued": "New invoice",
			"invoiceOverdue": "Invoice overdue",
			"reportMissing": "Report missing"
		},
		"settings": {
			"title": "Notifications",
			"hint": "Each notice shows in the app and is emailed to whoever has an email address, in their language. Switching one off stops new ones; those already sent stay.",
			"send": "Send this notice",
			"minutesBefore": "Minutes before the start",
			"minutesAfter": "Minutes after the start",
			"sessionsLeft": "When this many sessions are left",
			"save": "Save notifications",
			"loadError": "Couldn't load the notification settings.",
			"errors": {
				"earlyRange": "Choose 30 to 1440 minutes.",
				"reminderRange": "Choose 5 to 720 minutes.",
				"lateRange": "Choose 1 to 55 minutes.",
				"lowRange": "Choose 0 to 10 sessions."
			}
		}
	}
}
```

Merge into `dashboard/src/locales/ar/common.json` (Arabic, into the `notifications` object):

```json
{
	"notifications": {
		"types": {
			"earlyReminder": "تذكير مبكر بالحصة",
			"reminder": "تذكير بالحصة",
			"teacherReminder": "تذكير المعلم بالحصة",
			"late": "الحصة لم تبدأ",
			"studentAbsent": "غياب الطالب",
			"subscriptionLow": "حصص قليلة متبقية",
			"subscriptionExpired": "انتهاء الاشتراك",
			"invoiceIssued": "فاتورة جديدة",
			"invoiceOverdue": "فاتورة متأخرة",
			"reportMissing": "تقرير ناقص"
		},
		"settings": {
			"title": "الإشعارات",
			"hint": "يظهر كل إشعار في التطبيق ويُرسل بالبريد لمن لديه بريد إلكتروني، بلغته. إيقاف أي إشعار يمنع الجديد منه، ويبقى ما أُرسل.",
			"send": "أرسل هذا الإشعار",
			"minutesBefore": "دقائق قبل البدء",
			"minutesAfter": "دقائق بعد البدء",
			"sessionsLeft": "عندما يتبقى هذا العدد من الحصص",
			"save": "احفظ الإشعارات",
			"loadError": "تعذّر تحميل إعدادات الإشعارات.",
			"errors": {
				"earlyRange": "اختر من 30 إلى 1440 دقيقة.",
				"reminderRange": "اختر من 5 إلى 720 دقيقة.",
				"lateRange": "اختر من 1 إلى 55 دقيقة.",
				"lowRange": "اختر من 0 إلى 10 حصص."
			}
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vitest run src/features/notifications
```

Expected: all pass (5 new).

- [ ] **Step 5: Full suite and linters**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 643 tests (621 before Task 10); coverage lines 94.09%, branches 87.19%, functions 81.0% (gates 80/70/70).

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(notifications): notification switches and numbers in the academy settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: End-to-end through Caddy: an absence reaches the parent's bell and inbox; STATE.md

**Files:**
- Create: `dashboard/e2e/manage.ts`, `dashboard/e2e/notifications.spec.ts`
- Modify: `dashboard/e2e/mail.ts` (`latestLink` searches every email to the address, newest first, so an invite followed by a notification still finds each link), `STATE.md` (meta), submodule pointers (meta, after merge)

**Interfaces:**
- Consumes: Task 7's `scan_notifications` command; Tasks 10–12's bell, page and settings; `e2e/fixtures.ts`'s `login`, `expectLoggedIn`, `acceptInvite`, `DEMO_URL`, `DEMO_ADMIN`.
- Produces: `manage(...args): string` in `e2e/manage.ts`. It runs `python manage.py …` in the backend checkout beside the dashboard (`../../backend`, or `E2E_BACKEND_DIR`) with `E2E_PYTHON` (default `python`), inheriting the environment the server under test runs with. Also `e2e/notifications.spec.ts` (spec §8).
- CI: no change. The `e2e` job already checks out the submodules and exports `DJANGO_SETTINGS_MODULE=config.settings.local`, `DATABASE_URL`, the file email backend and `CELERY_TASK_ALWAYS_EAGER=true` at job level, so Playwright's `python manage.py scan_notifications` reaches the same database, and the emails it queues are written inline to `E2E_MAIL_DIR`. `python` is setup-python's, with `requirements/local.txt` installed.

- [ ] **Step 1: Write the failing test**

The journey creates its own parent (invited by email, reading English), a child without a login, and a priced package, whose subscription is invoiced to the parent. The subscription's slot started an hour ago today. The parent accepts the invite before anything is due. The admin marks the student absent, and the scan runs through the command. The parent's bell then counts two (the absence and the new invoice). The absence leads to the family's sessions, and the page shows it read. At 320 px the top bar never scrolls sideways. The absence's email carries the family's link. Last, the admin's settings keep a number.

Create `dashboard/e2e/manage.ts`:

```ts
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

/** The backend checkout beside the dashboard in the meta repo (the CI `e2e`
 * job checks the submodules out), unless `E2E_BACKEND_DIR` says otherwise. */
const BACKEND_DIR =
	process.env.E2E_BACKEND_DIR ??
	fileURLToPath(new URL("../../backend", import.meta.url));
/** The Python with the backend's requirements: CI's `python`, or
 * `E2E_PYTHON` (`backend/.venv/bin/python` on a laptop). */
const PYTHON = process.env.E2E_PYTHON ?? "python";

/** Run a Django management command against the server under test: same
 * settings, database and email backend, inherited from this environment. A
 * command, not an HTTP route, so nothing test-only is reachable in
 * production. */
export function manage(...args: string[]): string {
	return execFileSync(PYTHON, ["manage.py", ...args], {
		cwd: BACKEND_DIR,
		encoding: "utf8",
	});
}
```

Replace the whole of `dashboard/e2e/mail.ts` with:

```ts
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const MAIL_DIR = process.env.E2E_MAIL_DIR;
const MAILPIT = process.env.E2E_MAILPIT_URL ?? "http://localhost:8025";

/**
 * Django's file backend writes the raw MIME message, and a body with any
 * non-ASCII text (the academy's Arabic name) goes out quoted-printable: `=` is
 * `=3D` and long lines are soft-wrapped with a trailing `=`. Undo both so a
 * link reads as it does in a mail client. Read as latin1 and re-decode as UTF-8
 * so decoded bytes and raw 8-bit bytes both come out right.
 */
function decodeQuotedPrintable(raw: string): string {
	const bytes = raw
		.replace(/=\r?\n/g, "")
		.replace(/=([0-9A-F]{2})/g, (_, hex: string) =>
			String.fromCharCode(Number.parseInt(hex, 16)),
		);
	return Buffer.from(bytes, "latin1").toString("utf8");
}

/** Every email to `address` in the file outbox, newest first. */
function fromDir(address: string): string[] {
	if (!MAIL_DIR) return [];
	const files = readdirSync(MAIL_DIR)
		.map((name) => join(MAIL_DIR, name))
		.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
	return files
		.map((file) => decodeQuotedPrintable(readFileSync(file, "latin1")))
		.filter((text) => text.includes(`To: ${address}`));
}

async function fromMailpit(address: string): Promise<string[]> {
	const search = await fetch(
		`${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${address}"`)}`,
	);
	if (!search.ok) return [];
	const { messages = [] } = (await search.json()) as {
		messages?: { ID: string }[];
	};
	const texts: string[] = [];
	for (const { ID } of messages) {
		const message = await fetch(`${MAILPIT}/api/v1/message/${ID}`);
		if (message.ok) texts.push(((await message.json()) as { Text: string }).Text);
	}
	return texts;
}

/** The first link matching `pattern` in the newest email to `address` that
 * has one. An address can get several emails (an invite, then a
 * notification, Plan 8), so each is searched, newest first. */
export async function latestLink(
	address: string,
	pattern: RegExp,
): Promise<string> {
	for (let attempt = 0; attempt < 30; attempt++) {
		const texts = MAIL_DIR ? fromDir(address) : await fromMailpit(address);
		for (const text of texts) {
			const match = text.match(pattern);
			if (match) return match[0];
		}
		await new Promise((resolve) => setTimeout(resolve, 500));
	}
	throw new Error(`No email with a matching link reached ${address}`);
}
```

Create `dashboard/e2e/notifications.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import {
	acceptInvite,
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	login,
} from "./fixtures";
import { latestLink } from "./mail";
import { manage } from "./manage";

const weekday = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
	);

/** An hour ago on the demo academy's clock (UTC), or midnight in the first
 * hour of the day: today's session must already have started, or its
 * attendance stays closed. */
function startedTime(now = new Date()): string {
	const earlier = new Date(now.getTime() - 60 * 60_000);
	if (earlier.getUTCDate() !== now.getUTCDate()) return "00:00";
	return earlier.toISOString().slice(11, 16);
}

// Spec §8: an admin marks a student absent; the scan runs (the management
// command, as beat would); the parent signs in through the invite, sees the
// bell's count and the item, and follows it; the email is in the outbox. The
// student has no email address, so only the guardian is told. The absence
// and the scan happen within the same minute, far inside the 24-hour
// look-back, so neither midnight nor the time zone can move them apart.
test("a parent hears of an absence in the bell and by email", async ({
	page,
	browser,
}) => {
	const stamp = Date.now();
	const parent = `E2E Notified ${stamp}`;
	const parentEmail = `e2e-notified-${stamp}@e2e.test`;
	const student = `E2E Absentee ${stamp}`;
	const pkg = `E2E Notices ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// A parent (invited by email, reading English), their child without a
	// login, and a package whose subscription is invoiced to the parent
	await page.goto(`${DEMO_URL}/app/people/parents/new`);
	await page.getByLabel(/^full name/i).fill(parent);
	await page.getByLabel(/^email/i).fill(parentEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/parents\/\d+$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);
	await page.getByLabel("Find a parent").fill(parent);
	await page
		.getByRole("button", { name: `Link ${parent}`, exact: true })
		.click();
	await expect(
		page.getByRole("button", { name: `Unlink ${parent}`, exact: true }),
	).toBeVisible();

	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`إشعارات ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(pkg);
	await page.getByLabel("Sessions per week").fill("1");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await page.getByLabel("Price").fill("300");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/packages$/);

	// A subscription whose slot today started an hour ago
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new`);
	const startsOn = page.getByLabel(/^Starts/);
	await expect(startsOn).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);
	const today = await startsOn.inputValue();
	await page.getByLabel("Find a student").fill(student);
	await page.getByLabel(/^Student/).selectOption({ label: student });
	await page.getByLabel(/^Course/).selectOption({ label: "Tajweed" });
	await page.getByLabel(/^Teacher/).selectOption({ label: "Ustadh Bilal" });
	await page.getByLabel(/^Package/).selectOption({ label: pkg });
	await page.getByLabel(weekday(today), { exact: true }).click();
	await page.getByLabel(/^Start time/).fill(startedTime());
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);

	// 1. The parent accepts the invite; nothing to hear yet
	const guardian = await acceptInvite(
		browser,
		parentEmail,
		"e2e-Notified-2026",
		parent,
	);
	await expect(
		guardian.getByRole("button", { name: "Notifications", exact: true }),
	).toBeVisible();

	// 2. The admin marks the student absent on the session page
	await page.goto(`${DEMO_URL}/app/scheduling/sessions`);
	await page.getByRole("searchbox").fill(student);
	await page
		.getByRole("row", { name: new RegExp(student) })
		.getByRole("link", { name: student, exact: true })
		.click();
	await expect(page).toHaveURL(/\/app\/scheduling\/sessions\/\d+$/);
	await page
		.getByLabel(`Student attendance for ${student}`, { exact: true })
		.selectOption("absent");
	await expect(
		page.locator('[data-slot="card-header"]').getByText("Completed", {
			exact: true,
		}),
	).toBeVisible();

	// 3. The scan runs now, as the beat job does every minute
	expect(manage("scan_notifications")).toContain("ok: academy_demo");

	// 4. The bell counts the absence and the new invoice; the absence leads
	// to the family's sessions and is then read
	await guardian.reload();
	const bell = guardian.getByRole("button", {
		name: "Notifications, 2 unread",
	});
	await expect(bell).toBeVisible();
	await bell.click();
	const menu = guardian.getByRole("menu");
	await expect(menu.getByText(/^New invoice INV-\d{6}$/)).toBeVisible();
	await menu.getByText(`Absent: ${student}`, { exact: true }).click();
	await expect(guardian).toHaveURL(/\/app\/learning\/sessions$/);
	await expect(
		guardian.getByRole("button", { name: "Notifications, 1 unread" }),
	).toBeVisible();

	// 5. The page lists both; the absence is read
	await guardian.goto(`${DEMO_URL}/app/notifications`);
	const absence = guardian
		.getByRole("listitem")
		.filter({ hasText: `Absent: ${student}` });
	await expect(absence).toBeVisible();
	await expect(absence.getByText("Unread")).toHaveCount(0);
	await guardian.getByLabel("Show").selectOption("unread");
	await expect(
		guardian.getByRole("listitem").filter({ hasText: `Absent: ${student}` }),
	).toHaveCount(0);

	// 6. At phone width the top bar, bell included, never scrolls sideways
	await guardian.setViewportSize({ width: 320, height: 720 });
	await expect(
		guardian.getByRole("button", { name: "Notifications, 1 unread" }),
	).toBeVisible();
	expect(
		await guardian.evaluate(() => document.documentElement.scrollWidth),
	).toBeLessThanOrEqual(320);
	await guardian.context().close();

	// 7. The absence's email reached the parent, with the family's link
	const link = await latestLink(
		parentEmail,
		/http:\/\/[^\s"<]+\/app\/learning\/sessions(?=\s)/,
	);
	expect(link).toBe(`${DEMO_URL}/app/learning/sessions`);

	// 8. The admin's settings hold the numbers
	await page.goto(`${DEMO_URL}/app/settings/academy`);
	const late = page.getByRole("group", { name: "Session not started" });
	await late.getByLabel("Minutes after the start").fill("10");
	await page.getByRole("button", { name: "Save notifications" }).click();
	await expect(page.getByText("Saved.", { exact: true })).toBeVisible();
	await page.reload();
	await expect(
		page
			.getByRole("group", { name: "Session not started" })
			.getByLabel("Minutes after the start"),
	).toHaveValue("10");
});
```

- [ ] **Step 2: Run the whole e2e suite through Caddy, as the CI `e2e` job does**

From the meta root, with a fresh database: migrate and seed, start Django, the dashboard preview, the marketing server and the Caddy edge, then run Playwright.

```bash
cd backend
export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan_e2e CELERY_BROKER_URL=redis://localhost:56379/0 \
  DJANGO_SETTINGS_MODULE=config.settings.local DJANGO_SECRET_KEY=ci-only DJANGO_READ_DOT_ENV_FILE=False \
  DJANGO_EMAIL_BACKEND=django.core.mail.backends.filebased.EmailBackend DJANGO_EMAIL_FILE_PATH=/tmp/etqan-mail \
  CELERY_TASK_ALWAYS_EAGER=true DJANGO_TENANT_URL_TEMPLATE=http://{domain}
mkdir -p /tmp/etqan-mail
.venv/bin/python manage.py migrate_schemas --shared && .venv/bin/python manage.py seed_dev
nohup .venv/bin/python manage.py runserver 127.0.0.1:8000 > /tmp/django.log 2>&1 &
cd ../dashboard
npx pnpm@10 build
nohup npx pnpm@10 preview --port 4173 --host 127.0.0.1 > /tmp/preview.log 2>&1 &
cd ../marketing
SITE_API_ORIGIN=http://127.0.0.1:8000 SITE_SCHEME=http HOST=127.0.0.1 PORT=4321 \
  nohup node dist/server/entry.mjs > /tmp/marketing.log 2>&1 &
cd ../dashboard
docker run -d --name edge --network host -v "$PWD/../caddy/Caddyfile.e2e:/etc/caddy/Caddyfile:ro" caddy:2.11.4-alpine
CI=1 E2E_DEMO_URL=http://demo.etqan.localhost E2E_OTHER_URL=http://other.etqan.localhost E2E_MAIL_DIR=/tmp/etqan-mail \
  E2E_PYTHON=$PWD/../backend/.venv/bin/python npx pnpm@10 exec playwright test
```

(`etqan_e2e` must be an empty database: `createdb -h localhost -p 55432 -U etqan etqan_e2e`. The marketing server needs a built `marketing/dist`: `pnpm install && pnpm build` in `marketing/` once.) Expected: all 17 specs pass on the first try (`CI=1` allows one retry; a spec that passes only on the retry is a finding), `notifications.spec.ts` included. Before this task's files exist the new spec cannot run; with them and without Tasks 1–12 it fails at `scan_notifications` (unknown command). Afterwards stop the four servers (`docker rm -f edge`, and the Django, preview and marketing processes) and drop `etqan_e2e`.

- [ ] **Step 3: Update `STATE.md`**

In `STATE.md` (1 of 3), replace:

```markdown
Plan 7 (teacher payroll, B0 milestone 7) built and in review: branch `feat/payroll` in backend,
dashboard and meta (spec `docs/superpowers/specs/2026-09-26-payroll-design.md`, plan
`docs/superpowers/plans/2026-09-26-plan-7-payroll.md`). New tenant app `etqan.payroll`: admins set
teachers' rates (a default and per course, in the teacher's pay currency) and bonuses and deductions,
generate a month's draft payslips from completed sessions (teacher present or not marked), issue them
once the month has ended (which freezes them and locks their sessions in scheduling), mark them paid
and export CSV; teachers see and print their own issued and paid payslips at `/app/payslips/<id>/print`.
The e2e suite covers the journey through the Caddy edge.
```

with:

```markdown
Plan 8 (notifications, B0 milestone 8) built and in review: branch `feat/notifications` in backend,
dashboard and meta (spec `docs/superpowers/specs/2026-09-26-notifications-design.md`, plan
`docs/superpowers/plans/2026-09-26-plan-8-notifications.md`). New tenant app `etqan.notifications`:
a beat job (`notifications.scan`, every minute, `for_each_academy`) runs one finder per type (session
reminders, lateness, absences, low and expired subscriptions, issued and overdue invoices, missing
reports) through scheduling's, billing's and identity's read-only services, writes one row per
recipient under a unique `dedupe_key`, renders it once in the recipient's language and time zone,
and emails it once on the branded layout (`notifications.deliver_email`, 3 tries). Every role has a
bell (unread count polled every minute), a Notifications page, and admins a Notifications section in
the academy settings. `manage.py scan_notifications` runs the scan now (the e2e suite uses it).
The e2e suite covers the journey through the Caddy edge.
```

In `STATE.md` (2 of 3), replace:

```markdown
Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 8 of the roadmap. The pay rule is `payroll.services.rules.PAYS`, the amount `session_amount`,
and payslips come only from `build`; the session lock is scheduling's (`lock_sessions`,
`refuse_if_paid`). Never restate any of them. Scheduling never imports payroll or billing.
```

with:

```markdown
Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
the next milestone of the roadmap. Notifications decide who is told what only in
`etqan.notifications` (`finders.FINDERS`, `recipients.resolve`, `text.render`, `links.path_for`);
no other app imports it (the dev seeds excepted), and a new notice type is a finder there, never a
call from a domain app. Never restate the pay rule, the session lock, `derive` or `overdue`.
```

In `STATE.md` (3 of 3), replace:

```markdown
## Follow-ups (from Plans 4–7)
```

with:

```markdown
## Follow-ups (from Plans 4–8)

- A notice is rendered once: a recipient who changes language or time zone keeps the old text on old
  notices; one whose email is removed before delivery gets `skipped`.
- A guardian linked after a once-per-object notice (a reminder, a low subscription) does not get it.
- `invoice.issued` looks back on `created_at`; an invoice voided within the minute is never announced.
- The bell polls every minute (no push); per-user preferences, WhatsApp and editable templates are B5.
```

- [ ] **Step 4: Commit (dashboard, then meta) and open PRs**

```bash
git -C dashboard add e2e
git -C dashboard commit -m "test(e2e): an absence reaches the parent's bell and inbox

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C backend push -u origin feat/notifications
git -C dashboard push -u origin feat/notifications
git add STATE.md docs/superpowers/plans/2026-09-26-plan-8-notifications.md
git commit -m "chore: state for Plan 8 — notifications

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push -u origin feat/notifications
```

Open one PR per repo: backend → `main`, dashboard → `main`, meta → `master`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Nothing merges without the user's approval. After the submodule PRs merge, bump the meta pointers (`git add backend dashboard`) to the merge commits, commit `chore: bump backend and dashboard for Plan 8 — notifications` with the trailer above, and push.

---

