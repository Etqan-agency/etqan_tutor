# Plan 33 — Trial Sessions and Teacher Availability (slice B2e) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B2a, B2b, B2c, B2d (B2's own; no other phase's slice).
**Slice:** B2e · **Phase spec:** docs/superpowers/specs/2026-10-03-b2-scheduling-depth-design.md (B2-11 as amended: inquiry intake from the dashboard; B2-12)

**Goal:** The office records trial requests with TutorHamster's fields, schedules each as a `trial` session with a teacher it can pick with a "Suggest" button, follows it through attendance like any session, and turns a completed trial into a subscription; teachers have weekly availability windows that power the suggestion and warn (never block) when the office schedules outside them; two per-academy switches, off by default.

**Architecture:**
- **Data** (spec §3). New `TrialRequest` and `TeacherAvailability` tables; `Session.Kind` gains `trial`; `Session.trial` (→ TrialRequest, PROTECT, `related_name="sessions"`) with a check (`kind = 'trial'` ⇔ `trial` set) and a partial unique constraint (one live session per request). One additive migration `0010_trials_availability`. No data rewritten.
- **Rules** (`services/rules.py`). The trial helpers every module needs without import circles: the switch names, the three trial refusals, `CURRENT_TRIAL_ORDER` (live first, then latest), `is_trial_session`, `refuse_trial_restore`.
- **Services.** New `services/availability.py` (windows, `set_availability` under a transaction-scoped advisory lock, `is_available`, `outside_availability`, `slots_outside`, `available_map`); new `services/trials.py` (`create_trial`, `update_trial`, `delete_trial`, `schedule_trial`, `trials_queryset`, `filter_trials`, `can_schedule`, `can_convert`, `trial_status`); new `services/suggest.py` (`suggest_teachers`, about six queries); new `services/conversion.py` (`claim_trial`, called by `create_subscription(trial=)`). B2a's `manual._session` gains `trial=None`; `delete_session` refuses a trial session; `restore_session` gains the trial refusals; B2c's field map shows `pays_teacher` while `extra_sessions` **or** `trial_sessions` is on and its revert needs the session kind's switch.
- **Identity.** One additive service `identity_services.active_teachers(user_ids=None)`: scheduling may not import `identity.models` (`lint-imports`).
- **API.** `trials/` (list + CSV, create), `trials/<id>/` (read, update, delete), `trials/<id>/schedule/`, `trials/suggest/` (feature `trial_sessions`, office only: 404 before the code check); `schedule/availability/<user_id>/` and `schedule/availability/` (feature `teacher_availability`); `subscriptions/` POST takes `trial_id`; slot rows and the add / postpone / schedule answers carry `outside_availability` while availability is on; session rows carry `trial_id` (office); `sessions/<id>/pays-teacher/` follows `trial_sessions` for a trial session.
- **Dashboard.** Trials list, form, detail with Schedule (Suggest), history and Convert; the subscription form pre-filled from a trial; an availability editor on the teacher page and "My availability" for teachers; the outside-availability warning on slot rows and next to every conflicts display; a Trial tab and badge in the sessions list; "Create trial request" on trial inquiries (B8's list, under a ledger claim). Strings in new area files `trials.json` and `availability.json`.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod, i18next, Radix UI; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b2e-trials-availability-design.md` (slice B2e of the phase spec). It builds on Plan 2 (site inquiries, kind `trial`), Plan 4 (subscriptions, slots, P4-9 clashes reported never blocked, the course-teacher rule), Plan 5 (attendance, cancel, restore, reports), Plan 7 (payroll by course rate), B2a (Plan 17: session kinds, `manual._session`, `delete_session`, `pays_teacher`, the one-live-compensation constraint), B2b (Plan 21: postponement), B2c (Plan 25: `track`, `FIELD_FEATURES`, the inverse table), B2d (Plan 31: archives), Plan 13 (switches, FT-4). Ledger decisions **D8** (`Session.kind` gains `trial`; only regular and compensation consume) and **D9** (`pays_teacher`, default true; `payroll_sessions` leaves out sessions with it off). Where this plan fills a gap in the spec, the Decisions below say so.

## Global Constraints

**Repos and branches**
- Meta worktree: `/home/abdulkhalek/Projects/etqan_tutor-wt/b2` (`$W`). Meta, `backend/` and `dashboard/` are on `feat/b2e-trials`, created by the controller off `origin/master` (meta) and `origin/main` (submodules) after B2d merged. `marketing/` is untouched.
- Commit in the submodule that owns the file (`git -C $W/backend …`, `git -C $W/dashboard …`). Never run `git submodule update` (or any writing `git submodule` subcommand) in this worktree.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` (this overrides any attribution line a harness suggests).
- Never edit `STATE.md`, CI workflows, Caddyfiles, or meta's submodule pointers.

**Commands (the slot-1 stack must be up: `just dev-backend`)**
- From `$W`, load the stream's environment first: `cd /home/abdulkhalek/Projects/etqan_tutor-wt/b2; set -a; . ./.env.stream; set +a`. Then run docker compose **directly** (a `$DC` variable does not word-split in zsh). `…` below stands for `docker compose -f docker-compose.local.yml`:
  - Backend tests: `… exec -T django pytest -q <paths>` (add `--create-db` once after the migration).
  - Backend format: `… exec -T django ruff check --fix .` then `… exec -T django ruff format .`
  - Backend verify: `… exec -T django ruff check .`, `… exec -T django ruff format --check .`, `… exec -T django lint-imports`, `… exec -T django pytest -q --cov=etqan`
  - Migration: `… exec -T django python manage.py makemigrations scheduling --name trials_availability` (Task 1). Trunk's scheduling leaf after B2d is `0009_archives`, so this is `0010_trials_availability`.
  - Dashboard tests: `… exec -T dashboard pnpm exec vitest run <paths>`; verify: `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`, `… exec -T dashboard pnpm test:coverage`. Format first with `… exec -T dashboard pnpm exec biome check --write src e2e`.
  - New route files: regenerate `src/routeTree.gen.ts` with `… exec -T dashboard pnpm exec vite build` before `tsc` (generated: never hand-edit, never hand-merge).
  - Seeding this stream: `just _stack-manage migrate_schemas`, `just _stack-manage seed_dev`. E2E only through `just e2e …` (it runs `--workers=1 --retries=1`).
  - Slice gates: `just test` (its backend recipe blanks `DJANGO_EMAIL_SUBJECT_PREFIX`), `just lint`, `just e2e`.
- There is no host `.venv` or `node_modules`; never run `manage.py`, `migrate` or pytest against any other database.
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE`, `ERA`, `SLF`, `C901` (10), `E501` (88). Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §6)`. Imports are one per line (`from x import a` / `from x import b`), as every trunk file does. A boolean keyword argument is keyword-only (`*,` before it), or FBT fires.
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: semantic colour tokens only (`bg-secondary`, `text-muted-foreground`, `border-border`, `text-primary-text` …), never a literal colour — the checker also rejects `"#123456"`-like literals inside tests. Biome rejects `role="group"` on a div (use `<fieldset>` + `<legend>`) and an implicit-`any` `let` (write `let body: ReactNode;`).

**TDD and reports (lessons from Plans 21, 25 and 31)**
- Every task runs its new tests before the implementation and keeps the failing output (RED) for the report, then the passing output (GREEN). A report without RED evidence is sent back.
- Trunk helper names: `identity_services.link_guardian(parent, student)` (positional Users), the root `staff_for(*codes)` fixture (an `APIClient`; the user is `client.user`), `api_for("admin")`, `set_features(**switches)` (also `academy=`), `tenants.other`; scheduling's conftest: `clock` (`clock.set(datetime)`), `world` (`teacher`, `student` — Users — `course`, `package`), `subscribe(**overrides)`, `make_admin`, `make_teacher`, `make_student`, `hand_session(sub, *, occurs_on, start=time(10, 0), **fields)`, `two_slots()`, `build_world()`, `subscription_for(world, **o)`, `course_teacher(world, name)`, `until_pk_exceeds`, `as_user(user)`, `supervisor(name)`, `archives_on`. `rules.acts_as_office` exists: never re-define it. Shared test helpers go once in scheduling's conftest (Plan 25 ruling Q4), never copied between files: this plan adds `TRIAL_DAY`, `trial_for`, `hand_trial_session`, `trials_on`, `availability_on` (Task 4), `schedule_for` (Task 5) and `completed_trial` (Task 7) there and nowhere else.
- `etqan/platform/tests/test_features.py`'s `BUILT` dict lists every built switch **in registry order**: `trial_sessions` and `teacher_availability` are new lines under `# ── phase B2 ──` right after `simplified_sessions`, so their `BUILT` keys go right after `"simplified_sessions": False,`. Same commit as the registry.
- `etqan/access/tests/test_routes.py`: every new route joins `ROUTES` and `FEATURES`; `FEATURE_WORDS` gets `/trials/` and `/availability/`. **Insert** into the current lists and dict (B2's lines under their `# Slice B2e.` comment, after B2d's), never paste them whole: trunk's entries from other phases must stay. The registry's `IN_USE` must equal the codes the routes declare. The teacher's own `schedule/availability/` is `SELF_SERVICE`.
- `dashboard/src/routes/permissions.test.ts`: **insert** `trials|availability|` into the current `FEATURE_WORDS` regex (Plan 31 ruling R4); never replace the regex, so trunk's `gateways|checkouts` and `videos` stay. Add the new screens to `FEATURE_SCREENS` under a `// Slice B2e` comment.
- Non-office callers of the trial routes get 404 from `OfficeOr404` (B2c's, `api/activity_views.py`) listed **before** `HasCode`; a switched-off feature answers 404 **after** the permission check (`FeatureOn` last). The availability routes answer students and parents 404 the same way (`FamilyOr404`, Task 10).
- A list or read that renders rows carries a query-count test (same count for 1 and 3 rows).
- Scheduling code and tests may not import `etqan.identity.models`, `etqan.catalogue.models` or `etqan.site` (import-linter); go through `identity_services` / `catalogue_services`.
- The dashboard never restates a server rule: whether a trial may be scheduled or converted is the server's `can_schedule` / `can_convert`; outside availability is the server's `outside_availability`; a refused write shows the translated 409 code (`errorText`).
- Outside the app shell every switch counts as on and every code is held (`useHasFeature` / `useCan` allow all): a test rendering a touched page must mock every API call that page now makes (the trials API, the availability API).
- Async router mount: in tests, the first query after `renderWithRouter` is a `findBy*`; a negative check (`queryBy… → null`) waits for a sibling marker first (Plan 31 final-review fix).

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; `demo` admin `admin@demo.test` ("Demo Academy Admin").

**Orchestration rules**
- Shared lists: lines only under `── phase B2 ──` (feature registry, `test_features.BUILT`'s B2 block, the access registry's resources, the dashboard nav's B2 block, `seed_dev`'s B2 block calls `etqan/tenants/seeds/b2.py`).
- Files outside `etqan.scheduling` / the scheduling dashboard feature that this plan touches: `backend/etqan/identity/services.py` (+ test; one additive function — identity is shared and unowned, the spec requires it, §4.3); `backend/etqan/tenants/tests/test_seed_dev.py`, `test_seed_staging.py`, `test_seed_b2.py` (counts narrowed to non-trial rows, Task 11); `dashboard/src/routes/_authed/people.teachers.$personId.tsx` (unowned; one section, Task 16); **B8's** `dashboard/src/features/website/InquiriesList.tsx`, `InquiriesList.test.tsx` and `dashboard/src/routes/_authed/website.inquiries.tsx` (Task 18, under a one-commit ledger `claim` / `release`, conductor ruling 2026-10-03).
- New translation areas: `dashboard/src/locales/{en,ar}/trials.json` and `availability.json`, holding their keys directly (the catalogue wraps each file under its name). `errors.json`'s `scheduling` codes and `sessionClasses.json` (the `trial` kind and tab beside their siblings) are B2's and edited in place. No `es` file (ledger D22).
- New e2e spec: `dashboard/e2e/b2-trials.spec.ts`, owning its stamped data, safe to run twice on one database, no faked time, asserting durable state (banners, rows, links), never a transient toast.
- Migrations are additive (phase B2-16). Never `makemigrations --merge`; on a clash after a rebase, delete this plan's migration and regenerate it.
- Service signature changes are additive only (keyword arguments with defaults that keep today's behaviour): `create_subscription(..., trial=None)`, `manual._session(..., trial=None)`.

**Lock order (binding, spec §4)**
- Trial request → its sessions (pk order, one `FOR UPDATE … ORDER BY id`) → a new subscription (the insert). `schedule_trial`, `delete_trial` and `update_trial` lock the request first; `claim_trial` (conversion) locks the request, then its current session, before `create_subscription` inserts. A session-first caller (B2a / Plan 5 services on a trial session: attendance, cancel, restore, disposal, pays-teacher, postpone, times, archive) never locks the request: `restore_session` reads it unlocked, after the session's lock.
- `set_availability` takes `pg_advisory_xact_lock(hashtext('scheduling.availability.<schema>'), <teacher profile id>)` before it replaces the windows, so two saves for one teacher never interleave; it locks no row.

**API and data rules (spec values verbatim)**
- 409 bodies `{detail, code}`. New codes: `scheduling.trial_rejected`, `scheduling.trial_scheduled`, `scheduling.trial_not_completed`, `scheduling.trial_converted`, `scheduling.trial_session`; existing `scheduling.not_allowed_in_status` for a trial's session that is marked, completed, at disposal or paid on delete.
- Switches (built, off by default, group `teaching`): `trial_sessions`, `teacher_availability`.
- Request fields: student\* (active account, any profile status), source\* `website|app|api`, course\*, `students_count`\* 1–20 (default 1), `preferred_gender`\* `male|female|any` (default `any`), `minutes`\* 15–180, `desired_at` (UTC, nullable), `requested_on`\* (default the academy's today), `request_status`\* `under_review` (default) `|accepted|rejected`, `heard_from`\* `facebook|google|youtube|web_search|referral|other`, `rated` (default false), `notes`, `inquiry_id` (unique when set), `converted_to` (→ Subscription, `SET_NULL`, unique).
- Trial status: `not_scheduled`, or the current session's status (`scheduled`, `completed`, `cancelled`, `at_disposal`). The current session is the live (non-cancelled) one, else the latest.
- Availability windows: weekday 0–6 (Monday = 0), `start_time < end_time`, academy wall-clock, never across midnight; windows of one teacher on one weekday never overlap (touching is allowed and counts as one when checking).

### Decisions this plan makes where the spec is silent or leaves a choice

- **D1 — Module split.** The trial helpers that `attendance.py`, `manual.py`, `trials.py` and `conversion.py` all need live in `rules.py` (it imports models only), so no module imports in a circle: `trials.py` imports `manual` (for `_session` / `_add`), `manual` imports `attendance`, and `attendance` imports only `rules`. Conversion is its own module (`services/conversion.py`, imported by `subscriptions.py`), because `subscriptions` may not import `trials` (`trials → manual → subscriptions`).
- **D2 — The dashboard learns what it may do from `can_schedule` and `can_convert`** in the trial payload (the server's rule, Plan 31 D2's pattern): `can_schedule` = not converted, not rejected, and no live session; `can_convert` = the current session is completed and the request is not converted. The routes still refuse on their own.
- **D3 — Field names on refusals.** The body keys are the field names: a teacher who does not teach the course is 400 on `teacher_id` on the schedule route (spec §4.2 says `teacher_id`; `course_teacher`'s `teacher` field is re-keyed), and a converting student who is not the trial's is 400 on `student` (spec §4.4 says `student_id`, the service argument; the subscription body's key is `student`, so the form shows it on the Student field).
- **D4 — `update_trial` takes no `by`** (nothing records who edited a request; spec §4.1 lists it, but an unused argument is noise). `create_trial` records `created_by`.
- **D5 — Trial list filters.** Besides spec §4.6's filters (student by User id, course, teacher, teacher gender, status, request status, source, heard from, requested from / to), the list takes `q` (the student's name, `icontains`), as every other list does; the dashboard filters by `q`. Newest first is `-requested_on, -id`.
- **D6 — `outside_availability` appears only while `teacher_availability` is on** (FT-4, Plan 31 D6): slot rows and the four answers carry the key then, and never otherwise, so every existing payload is byte-for-byte today's with the switch off. A session crossing local midnight, or ending exactly at midnight (a window cannot end at 24:00), is outside.
- **D7 — Advisory lock key.** Advisory locks are database-wide, not per schema, so the key is `hashtext('scheduling.availability.' || <schema name>)` plus the teacher profile id: two academies never wait on each other.
- **D8 — Pays-teacher by kind.** `PaysTeacherView` keeps `feature = "extra_sessions"` (the route table's column) and, in `initial()`, switches to `trial_sessions` when the session is a trial one (one indexed query, before the permission check, revealing nothing: an unknown id stays `extra_sessions`). B2c's `FIELD_FEATURES` values become tuples (any one on shows the field) and the `pays_teacher` inverse needs the session kind's switch, read from `entry.session` (cached on each entry by `describe_activity`, select-related by `get_activity_entry`: no query per entry).
- **D9 — Trial sessions in the session list and on the session page.** The kind label and tab are `sessionClasses.kind.trial` / `sessionClasses.tabs.trial` (beside their siblings in B2's `sessionClasses.json`), so the existing `SessionKindChip` badges trial sessions in every list (office, teacher, family) with no new component. The session payload's `trial_id` is the office's (staff-only field). The session page hides Delete for a trial session (the generic delete always refuses it, so the button could only fail) and links its trial instead.
- **D10 — Suggest answers.** `gender_match` is true for everyone when the preference is `any` (no one is ranked down); `available` is `null` for every candidate while availability is off (ignored); each answer also carries `week_sessions` (the tie-break count) so the office sees why one ranks above another.
- **D11 — The schedule answer is `201 {trial, conflicts, outside_availability?}`**, `trial` being the trial detail (with its new current session); the dashboard reads the session from it.
- **D12 — Edit is a dialog on the trial page; new is a route** (`/app/scheduling/trials/new`), like the subscription form. The trial form posts to `trials/` or patches `trials/<id>/`.
- **D13 — Inquiry intake without a cross-feature import.** `InquiriesList` (B8) gains one optional prop, `actions(inquiry)`, rendered beside "Mark handled"; the route `website.inquiries.tsx` passes scheduling's `TrialFromInquiry` and marks the inquiry handled with website's `useHandleInquiry` once the trial is created. Website never imports scheduling, and scheduling never imports website. This is the trivial additive edit the conductor ruling allows, under one-commit claims on the three files (Task 18).
- **D14 — Conversion pre-fill.** "Convert to subscription" opens `/app/scheduling/subscriptions/new?trial=<id>`; the form reads the trial, pre-fills student, course and teacher (the current session's), keeps the trial's student as the one Student option, sends `trial_id`, and returns to the trial on success. Ledger request R2 (B3d's country-pricing hook) later passes the student to `TermFields` here; nothing in this plan conflicts with it.
- **D15 — The teacher page has no tabs**, so "Availability" is a section below the teacher form (as B9a's Contracts button is a block above it), shown while `teacher_availability` is on and the viewer holds `teacher_schedule.view`; editable with `teacher_schedule.update`.
- **D16 — Seeds** (spec §8): weekly windows for Ustadh Bilal (Mon–Thu 16:00–21:00) and Ustadha Maryam (Sun–Wed 09:00–13:00); Aisha Omar's Tajweed request under review; Yusuf Omar's Quran Memorisation trial scheduled with Ustadha Maryam in three days at 16:00; Zaid Huda's Tajweed trial with Ustadh Bilal two days ago at 17:00, marked present by the teacher with a report (so the seed tests' "one missing report" holds), converted through `create_subscription(trial=)` into a "Two-week intensive" subscription with no slots, starting today (no invoice: billing is the API's). One transaction per step, as the system; markers "a window exists" / "a trial request exists". The shared seed tests that count every subscription or every hand-added session read the non-trial rows (`trial_request__isnull=True`, `kind` ≠ `trial`): the trial's own data is exactly what they should not count.
- **D17 — Messages.** `scheduling.trial_rejected`: "This trial request was rejected."; `scheduling.trial_scheduled`: "This trial already has a session. Change or cancel that session first."; `scheduling.trial_not_completed`: "Only a completed trial can become a subscription."; `scheduling.trial_converted`: "This trial is already a subscription."; `scheduling.trial_session`: "This is a trial session. Delete or cancel it from its trial."

## Review Focus

- **A trial cancelled and scheduled again, then its old session restored.** Expected: the second schedule makes a new session and keeps the cancelled one as history; restoring the old one is refused with 409 `scheduling.trial_scheduled` (and the partial unique constraint backs it). Test: Task 5 `test_cancel_then_schedule_again_keeps_history_and_one_live`, `test_restore_refusals_for_a_trial_session`.
- **Converting a trial whose session was un-marked or cancelled after completion.** Expected: 409 `scheduling.trial_not_completed`, nothing created; a deleted converted subscription makes the request convertible again. Test: Task 7 `test_only_a_completed_current_session_converts` (parametrised: un-marked, cancelled, never marked), `test_deleting_the_subscription_makes_it_convertible_again`.
- **A session on the night the academy's clock changes.** Expected: availability is checked on the local start and the local end of the real instants, so a 60-minute session from 01:30 on a spring-forward night ends at 03:30 local and is outside a 01:00–03:00 window; touching windows count as one. Test: Task 3 `test_is_available_reads_local_times_across_a_dst_change`.
- **The same trial inquiry turned into a request twice** (a double click, a second tab). Expected: the second create is 400 on `inquiry_id`; the inquiry is marked handled once by the dashboard. Test: Task 9 `test_an_inquiry_makes_one_trial_request`.
- **A teacher with no windows, and availability switched off.** Expected: no warning anywhere (`outside_availability` false with windows missing; the key absent while off), the suggestion ranks the teacher as "no windows" between "available" and "not available", and nothing is blocked. Tests: Task 3 `test_no_windows_is_unknown_not_unavailable`, Task 10 `test_slot_rows_warn_only_while_on_and_only_with_windows`, Task 6 `test_availability_ranks_yes_then_unknown_then_no`.

---

## File Structure

```
backend/
  etqan/platform/features.py                        trial_sessions, teacher_availability under ── phase B2 ── (Task 1)
  etqan/platform/tests/test_features.py             BUILT (Task 1)
  etqan/identity/services.py (+tests/test_active_teachers.py)   active_teachers (Task 2)
  etqan/access/registry.py                          trial_session, teacher_schedule under ── phase B2 ── (Task 9)
  etqan/access/tests/test_routes.py                 ROUTES, FEATURES, FEATURE_WORDS, SELF_SERVICE (Tasks 9, 10)
  etqan/scheduling/
    models.py                                       TrialRequest, Session.Kind.TRIAL + Session.trial, TeacherAvailability (Task 1)
    migrations/0010_trials_availability.py          generated (Task 1)
    services/rules.py                               trial helpers (Task 4); restore refusal (Task 5)
    services/availability.py                        NEW (Task 3)
    services/trials.py                              NEW: requests (Task 4); schedule_trial (Task 5)
    services/suggest.py                             NEW (Task 6)
    services/conversion.py                          NEW (Task 7)
    services/manual.py                              _session(trial=); delete_session refuses trials (Task 5)
    services/attendance.py                          restore_session's trial refusals (Task 5)
    services/subscriptions.py                       create_subscription(trial=) (Task 7)
    services/activity.py revert.py activity_feed.py pays_teacher by kind (Task 8)
    services/__init__.py                            exports (Tasks 3–8)
    api/trial_views.py                              NEW (Task 9)
    api/availability_views.py                       NEW (Task 10)
    api/serializers.py payloads.py urls.py          trial and availability bodies, payloads, routes (Tasks 9, 10)
    api/views.py session_views.py                   trial_id on subscription create; pays-teacher by kind (Tasks 8, 10)
    tests/conftest.py                               TRIAL_DAY, trial_for, hand_trial_session, trials_on,
                                                    availability_on (Task 4); schedule_for (Task 5);
                                                    completed_trial (Task 7)
    tests/test_trials_*.py test_availability_*.py   NEW (Tasks 1, 3–10)
  etqan/tenants/seeds/b2.py tests/test_seed_b2.py   seed_availability, seed_trials (Task 11)
  etqan/tenants/tests/test_seed_dev.py test_seed_staging.py   non-trial counts (Task 11)
  etqan/tenants/management/commands/seed_dev.py     two calls in the B2 block (Task 11)
dashboard/
  src/features/identity/schemas.ts                  FeatureCode + 2 (Task 12)
  src/features/scheduling/
    schemas.ts api.ts queries.ts (+api.test.ts,     trial and availability types, routes, hooks (Task 12)
      trials.schemas.test.ts)
    TrialsList.tsx (+test)                          NEW (Task 13)
    TrialForm.tsx TrialPage.tsx ScheduleTrialDialog.tsx (+tests)   NEW (Task 14)
    SubscriptionForm.tsx (+test)                    trial pre-fill (Task 15)
    AvailabilityEditor.tsx (+test)                  NEW (Task 16)
    AddSessionDialog.tsx MakeUpDialog.tsx PostponeDialog.tsx SlotsPanel.tsx   AddedNotes, slot warning (Task 17)
    SessionsList.tsx SessionClasses.tsx (+tests)    Trial tab; trial link, pays switch, no Delete (Task 17)
    TrialFromInquiry.tsx (+test)                    NEW (Task 18)
    TrialPage.tsx (+test)                           Convert (Task 15)
    index.ts                                        exports (Tasks 13–18)
  src/features/shell/nav.ts (+nav.test.ts)          Trials, My availability under ── phase B2 ── (Tasks 13, 16)
  src/features/website/InquiriesList.tsx (+test)    `actions` prop (Task 18, under a claim)
  src/routes/_authed/scheduling.trials.index.tsx    NEW (Task 13)
  src/routes/_authed/scheduling.trials.new.tsx      NEW (Task 14)
  src/routes/_authed/scheduling.trials.$trialId.tsx NEW (Task 14)
  src/routes/_authed/scheduling.subscriptions.new.tsx       ?trial= (Task 15)
  src/routes/_authed/teaching.availability.tsx      NEW (Task 16)
  src/routes/_authed/people.teachers.$personId.tsx  Availability section (Task 16)
  src/routes/_authed/website.inquiries.tsx          TrialFromInquiry (Task 18, under a claim)
  src/routes/permissions.test.ts                    FEATURE_SCREENS, FEATURE_WORDS (Tasks 13, 14, 16)
  src/routeTree.gen.ts                              regenerated (Tasks 13, 14, 16)
  src/locales/{en,ar}/trials.json availability.json NEW (Task 12)
  src/locales/{en,ar}/errors.json sessionClasses.json       codes; trial kind and tab (Task 12)
  src/test/scheduling-fixtures.ts                   trialRow, trialDetail, suggestion (Task 12)
  e2e/b2-trials.spec.ts                             NEW (Task 19)
```

---
### Task 1: The switches, the trial and availability tables, and the migration

**Files:**
- Modify: `backend/etqan/platform/features.py` (two lines under `# ── phase B2 ──`, after B2d's `simplified_sessions`)
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT`)
- Modify: `backend/etqan/scheduling/models.py` (`TrialRequest` before `Session`; `Session.Kind.TRIAL`, `Session.trial`, two constraints; `TeacherAvailability` at the end)
- Create: `backend/etqan/scheduling/migrations/0010_trials_availability.py` (generated)
- Test: `backend/etqan/scheduling/tests/test_trials_model.py`

**Interfaces:**
- Produces: feature codes `trial_sessions`, `teacher_availability` (built, default off, group `teaching`). `TrialRequest` with nested choices `Source` (`WEBSITE`, `APP`, `API`), `Gender` (`MALE`, `FEMALE`, `ANY`), `RequestStatus` (`UNDER_REVIEW`, `ACCEPTED`, `REJECTED`), `HeardFrom` (`FACEBOOK`, `GOOGLE`, `YOUTUBE`, `WEB_SEARCH`, `REFERRAL`, `OTHER`) and the fields of spec §3.1 (`converted_to` is a `OneToOneField(Subscription, related_name="trial_request")`). `Session.Kind.TRIAL = "trial"`; `Session.trial` (→ `TrialRequest`, null, PROTECT, `related_name="sessions"`); constraints `scheduling_trial_has_request`, `scheduling_one_live_trial_session`. `TeacherAvailability(teacher → identity.TeacherProfile CASCADE related_name="+", weekday, start_time, end_time)`, ordered `weekday, start_time, id`, check `scheduling_availability_end_after_start`.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_trials_model.py`)

```python
"""Slice B2e §3, E-13: the two switches and the new tables."""

from datetime import date
from datetime import time

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.platform import features
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.models import TeacherAvailability
from etqan.scheduling.models import TrialRequest

pytestmark = pytest.mark.django_db
SWITCHES = ("trial_sessions", "teacher_availability")


@pytest.mark.parametrize("code", SWITCHES)
def test_the_two_switches_are_built_and_off_by_default(code):
    feature = features.get(code)
    assert (feature.built, feature.default, feature.group) == (True, False, "teaching")
    assert features.is_on(code, {}) is False


def test_the_switches_follow_b2d_under_the_b2_marker():
    codes = [feature.code for feature in features.REGISTRY]
    assert codes.index("simplified_sessions") + 1 == codes.index("trial_sessions")
    assert codes.index("trial_sessions") + 1 == codes.index("teacher_availability")


def _request(world, **fields):
    values = {
        "student": world.student.student_profile,
        "course": world.course,
        "source": TrialRequest.Source.WEBSITE,
        "minutes": 30,
        "requested_on": date(2026, 6, 1),
        "heard_from": TrialRequest.HeardFrom.GOOGLE,
        **fields,
    }
    return TrialRequest.objects.create(**values)


def _trial_session(world, trial, **fields):
    values = {
        "kind": Session.Kind.TRIAL,
        "trial": trial,
        "student": trial.student,
        "teacher": world.teacher.teacher_profile,
        "course": trial.course,
        "occurs_on": date(2026, 6, 2),
        "starts_at": dates.to_utc(date(2026, 6, 2), time(10, 0), "UTC"),
        "minutes": 30,
        **fields,
    }
    return Session.objects.create(**values)


def test_a_request_starts_under_review_for_one_student_and_any_teacher(world):
    trial = _request(world)
    trial.refresh_from_db()
    assert (
        trial.request_status,
        trial.preferred_gender,
        trial.students_count,
        trial.rated,
        trial.inquiry_id,
        trial.converted_to_id,
    ) == ("under_review", "any", 1, False, None, None)


def test_one_inquiry_makes_at_most_one_request(world):
    _request(world, inquiry_id=7)
    _request(world)  # no inquiry: never unique
    _request(world)
    with pytest.raises(IntegrityError), transaction.atomic():
        _request(world, inquiry_id=7)


def test_a_trial_session_needs_its_request_and_only_it_has_one(world, subscribe):
    trial = _request(world)
    with pytest.raises(IntegrityError), transaction.atomic():
        _trial_session(world, trial, trial=None)
    sub = subscribe()
    with pytest.raises(IntegrityError), transaction.atomic():
        Session.objects.create(
            subscription=sub,
            student=trial.student,
            teacher=world.teacher.teacher_profile,
            course=trial.course,
            occurs_on=date(2026, 6, 2),
            starts_at=dates.to_utc(date(2026, 6, 2), time(10, 0), "UTC"),
            minutes=30,
            trial=trial,
        )


def test_one_live_session_per_request_and_cancelled_ones_stay(world):
    trial = _request(world)
    _trial_session(world, trial, status=Session.Status.CANCELLED)
    _trial_session(world, trial, status=Session.Status.CANCELLED)
    _trial_session(world, trial)
    with pytest.raises(IntegrityError), transaction.atomic():
        _trial_session(world, trial)
    assert trial.sessions.count() == 3


def test_a_window_ends_after_it_starts(world):
    teacher = world.teacher.teacher_profile
    TeacherAvailability.objects.create(
        teacher=teacher, weekday=0, start_time=time(9), end_time=time(10)
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        TeacherAvailability.objects.create(
            teacher=teacher, weekday=0, start_time=time(11), end_time=time(11)
        )
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_model.py`
Expected: FAIL at import (`ImportError: cannot import name 'TeacherAvailability'`). Keep the output for the report.

- [ ] **Step 3: Add the two switches** (`backend/etqan/platform/features.py`)

Under `# ── phase B2 ──`, right after B2d's `simplified_sessions` entry and before `# ── phase B3 ──`:

```python
    # Slice B2e (Plan 33): trial sessions and teacher availability, off by default.
    Feature(
        "trial_sessions",
        "Trial sessions",
        "الحصص التجريبية",
        "teaching",
        built=True,
    ),
    Feature(
        "teacher_availability",
        "Teacher availability",
        "مواعيد المعلمين المتاحة",
        "teaching",
        built=True,
    ),
```

In `backend/etqan/platform/tests/test_features.py`, right after `"simplified_sessions": False,` (inside the B2 block):

```python
    "trial_sessions": False,
    "teacher_availability": False,
```

- [ ] **Step 4: Add the models** (`backend/etqan/scheduling/models.py`)

Between `ScheduleSlot` and `Session`, add:

```python
class TrialRequest(models.Model):
    """Slice B2e §3.1 (E-1): a request for a trial session — an office record
    teachers and families never see. Its sessions point at it (`Session.trial`,
    one live at a time); a completed one may become a subscription."""

    class Source(models.TextChoices):
        WEBSITE = "website", "Website"
        APP = "app", "App"
        API = "api", "API"

    class Gender(models.TextChoices):
        MALE = "male", "Male"
        FEMALE = "female", "Female"
        ANY = "any", "No preference"

    class RequestStatus(models.TextChoices):
        UNDER_REVIEW = "under_review", "Under review"
        ACCEPTED = "accepted", "Accepted"
        REJECTED = "rejected", "Rejected"

    class HeardFrom(models.TextChoices):
        FACEBOOK = "facebook", "Facebook"
        GOOGLE = "google", "Google"
        YOUTUBE = "youtube", "YouTube"
        WEB_SEARCH = "web_search", "Web search"
        REFERRAL = "referral", "Referral"
        OTHER = "other", "Other"

    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    source = models.CharField(max_length=8, choices=Source.choices)
    course = models.ForeignKey(
        "catalogue.Course", on_delete=models.PROTECT, related_name="trial_requests"
    )
    students_count = models.PositiveSmallIntegerField(
        default=1, validators=[MinValueValidator(1), MaxValueValidator(20)]
    )
    preferred_gender = models.CharField(
        max_length=6, choices=Gender.choices, default=Gender.ANY
    )
    # [assumed] 15-180: a session holds 15-240 minutes (Plan 4).
    minutes = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(15), MaxValueValidator(180)]
    )
    desired_at = models.DateTimeField(null=True, blank=True)  # UTC
    requested_on = models.DateField()  # the academy's date
    request_status = models.CharField(
        max_length=12, choices=RequestStatus.choices, default=RequestStatus.UNDER_REVIEW
    )
    heard_from = models.CharField(max_length=10, choices=HeardFrom.choices)
    rated = models.BooleanField(default=False)
    notes = models.TextField(blank=True, default="")
    # E-8: the site inquiry it came from, as a plain id (scheduling never
    # imports the site); unique when set.
    inquiry_id = models.PositiveIntegerField(null=True, blank=True)
    # E-7: the subscription it became; deleting that subscription unlinks it.
    converted_to = models.OneToOneField(
        Subscription,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="trial_request",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-requested_on", "-id"]
        constraints = [
            models.UniqueConstraint(
                fields=["inquiry_id"],
                condition=Q(inquiry_id__isnull=False),
                name="scheduling_trial_one_per_inquiry",
            ),
            models.CheckConstraint(
                condition=Q(students_count__gte=1, students_count__lte=20),
                name="scheduling_trial_students_1_to_20",
            ),
            models.CheckConstraint(
                condition=Q(minutes__gte=15, minutes__lte=180),
                name="scheduling_trial_minutes_15_to_180",
            ),
        ]

    def __str__(self):
        return f"TrialRequest<{self.pk}, {self.request_status}>"
```

In `Session.Kind`, after `EXTRA`, and its docstring:

```python
    class Kind(models.TextChoices):
        """Slice B2a (A-1): generated sessions are regular; the office adds
        regular, compensation and extra ones by hand. Slice B2e (E-3): a
        trial session comes from a trial request."""

        REGULAR = "regular", "Regular"
        COMPENSATION = "compensation", "Compensation"
        EXTRA = "extra", "Extra"
        TRIAL = "trial", "Trial"
```

In `Session`, after `archived_with_subscription`:

```python
    # Slice B2e §3.2 (E-3): a trial session's request, as a make-up points at
    # its original. PROTECT: `delete_trial` deletes its sessions first.
    trial = models.ForeignKey(
        TrialRequest,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="sessions",
    )
```

In `Session.Meta.constraints`, after `scheduling_postponed_origin_unique`:

```python
            # Slice B2e §3.2: a trial session has its request, and only it.
            models.CheckConstraint(
                condition=(Q(kind="trial") & Q(trial__isnull=False))
                | (~Q(kind="trial") & Q(trial__isnull=True)),
                name="scheduling_trial_has_request",
            ),
            # E-3: at most one live (non-cancelled) session per request.
            models.UniqueConstraint(
                fields=["trial"],
                condition=Q(trial__isnull=False) & ~Q(status="cancelled"),
                name="scheduling_one_live_trial_session",
            ),
```

At the end of the file:

```python
class TeacherAvailability(models.Model):
    """Slice B2e §3.3 (E-9): a weekly window a teacher can teach in, on the
    academy's wall clock, as slots are (Plan 4 P4-6). Read to warn and to
    suggest, never to block (E-11)."""

    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.CASCADE, related_name="+"
    )
    weekday = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(0), MaxValueValidator(6)]
    )  # 0 = Monday … 6 = Sunday, as slots
    start_time = models.TimeField()
    end_time = models.TimeField()

    class Meta:
        ordering = ["weekday", "start_time", "id"]
        indexes = [models.Index(fields=["teacher", "weekday"])]
        constraints = [
            models.CheckConstraint(
                condition=Q(end_time__gt=F("start_time")),
                name="scheduling_availability_end_after_start",
            ),
            models.CheckConstraint(
                condition=Q(weekday__gte=0, weekday__lte=6),
                name="scheduling_availability_weekday_0_to_6",
            ),
        ]

    def __str__(self):
        return f"TeacherAvailability<{self.weekday} {self.start_time}-{self.end_time}>"
```

- [ ] **Step 5: Generate the migration**

Run: `… exec -T django python manage.py makemigrations scheduling --name trials_availability`
Expected: `0010_trials_availability.py` depending on `0009_archives`, with `CreateModel` for `TrialRequest` and `TeacherAvailability`, one `AlterField` on `session.kind` (choices only), one `AddField` (`session.trial`, nullable) and the `AddConstraint`/`AddIndex` operations above; no `RunPython`, nothing rewritten (phase B2-16). Open the file and check that.

- [ ] **Step 6: Run the tests to see them pass**

Run: `… exec -T django pytest -q --create-db etqan/scheduling/tests/test_trials_model.py etqan/platform/tests/test_features.py etqan/scheduling/tests/test_session_classes_model.py`
Expected: PASS.

- [ ] **Step 7: Format, verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/platform/features.py etqan/platform/tests/test_features.py etqan/scheduling/models.py etqan/scheduling/migrations/0010_trials_availability.py etqan/scheduling/tests/test_trials_model.py
git -C $W/backend commit -m "feat(scheduling): trial requests, trial sessions and availability windows (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 2: Identity's active teachers, for scheduling to rank

**Files:**
- Modify: `backend/etqan/identity/services.py` (one function, after `teacher_profiles_by_id`)
- Test: `backend/etqan/identity/tests/test_active_teachers.py`

**Interfaces:**
- Produces: `identity_services.active_teachers(user_ids: Iterable[int] | None = None) -> list[TeacherProfile]` — the profiles of active users with role `teacher`, with `user` select-related, ordered by the user's full name then id; `user_ids=None` means every active teacher; an id that is not an active teacher is simply absent. One query.

- [ ] **Step 1: Write the failing test** (`backend/etqan/identity/tests/test_active_teachers.py`)

```python
"""Slice B2e §4.3: the candidates scheduling ranks, in one query (scheduling
may not import identity.models)."""

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.identity import services

pytestmark = pytest.mark.django_db


def teacher(name, **profile):
    return services.create_person(
        "teacher", full_name=name, profile={"gender": "male", **profile}
    )


def test_every_active_teacher_by_name_with_their_user():
    zaid = teacher("Zaid")
    amr = teacher("Amr")
    gone = teacher("Gone")
    services.deactivate(gone, by=None)
    services.create_person("student", full_name="Not a teacher")
    with CaptureQueriesContext(connection) as queries:
        found = services.active_teachers()
        names = [profile.user.full_name for profile in found]
    assert names == ["Amr", "Zaid"]
    assert len(queries) == 1
    assert {p.user_id for p in found} == {amr.pk, zaid.pk}


def test_only_the_ids_asked_for():
    zaid = teacher("Zaid")
    teacher("Amr")
    student = services.create_person("student", full_name="Sami")
    found = services.active_teachers([zaid.pk, student.pk, 999999])
    assert [p.user_id for p in found] == [zaid.pk]
    assert services.active_teachers([]) == []
```

- [ ] **Step 2: Run it to see it fail**

Run: `… exec -T django pytest -q etqan/identity/tests/test_active_teachers.py`
Expected: FAIL (`AttributeError: module 'etqan.identity.services' has no attribute 'active_teachers'`).

- [ ] **Step 3: Write the function** (`backend/etqan/identity/services.py`, after `teacher_profiles_by_id`; `Iterable` from `collections.abc` if the module does not import it yet)

```python
def active_teachers(user_ids: Iterable[int] | None = None) -> list[TeacherProfile]:
    """Slice B2e §4.3: the profiles of active teachers (``user_ids=None``:
    all of them), with their users, by name — one query. An id that is not
    an active teacher is simply absent."""
    profiles = TeacherProfile.objects.filter(
        user__role=User.Role.TEACHER, user__is_active=True
    )
    if user_ids is not None:
        profiles = profiles.filter(user_id__in=list(user_ids))
    return list(profiles.select_related("user").order_by("user__full_name", "user_id"))
```

- [ ] **Step 4: Run it to see it pass**

Run: `… exec -T django pytest -q etqan/identity/tests/test_active_teachers.py`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/identity/services.py etqan/identity/tests/test_active_teachers.py
git -C $W/backend commit -m "feat(identity): active_teachers for scheduling's suggestion (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 3: Availability windows — replace, read, and check a session or a slot

**Files:**
- Create: `backend/etqan/scheduling/services/availability.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_availability_services.py`

**Interfaces:**
- Consumes: Task 1's `TeacherAvailability`; `rules.settings()`; `features.enabled`.
- Produces (all exported from `etqan.scheduling.services` but the private ones):
  - `AVAILABILITY = "teacher_availability"` (the switch name, in `availability.py`).
  - `windows_of(teacher_id: int) -> list[TeacherAvailability]` — a teacher profile id; ordered weekday, start.
  - `set_availability(teacher_id: int, windows: Iterable[dict]) -> list[TeacherAvailability]` — each dict `{weekday, start_time, end_time}`; replaces every window in one transaction, after `pg_advisory_xact_lock`; 400 `field="windows.<i>"` (the index in the given order) for a weekday outside 0–6, an end not after the start, or an overlap with an earlier window of that day; 400 `field="windows"` for more than 50.
  - `is_available(teacher_id: int, starts_at: datetime, minutes: int) -> bool | None` — `None` when the teacher has no windows.
  - `available_map(teacher_ids: Iterable[int], starts_at: datetime, minutes: int) -> dict[int, bool | None]` — one query for every candidate.
  - `outside_availability(session: Session) -> bool | None` — `None` while the switch is off; else `True` exactly when the teacher has windows and the session is outside them.
  - `slots_outside(subscription: Subscription, slots) -> dict[int, bool] | None` — `None` while off; else each slot id → whether it is outside the subscription teacher's windows (all `False` when the teacher has none). One query.
  - `has_availability() -> bool` (the seeds' marker).

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_availability_services.py`)

```python
"""Slice B2e §4.5, E-9, E-11: weekly windows, replaced together, checked on
the academy's clock from real instants."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import dates
from etqan.scheduling import services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
MONDAY = date(2026, 6, 1)


def window(weekday, start, end):
    return {"weekday": weekday, "start_time": time(*start), "end_time": time(*end)}


@pytest.fixture
def teacher(world):
    return world.teacher.teacher_profile


def test_set_replaces_every_window(teacher):
    services.set_availability(teacher.pk, [window(0, (9,), (12,)), window(2, (16,), (18,))])
    saved = services.set_availability(teacher.pk, [window(1, (10,), (11, 30))])
    assert [(w.weekday, w.start_time, w.end_time) for w in saved] == [
        (1, time(10), time(11, 30))
    ]
    assert [w.pk for w in services.windows_of(teacher.pk)] == [saved[0].pk]
    assert services.set_availability(teacher.pk, []) == []


def test_set_takes_the_teachers_advisory_lock_before_it_writes(teacher):
    with CaptureQueriesContext(connection) as queries:
        services.set_availability(teacher.pk, [window(0, (9,), (10,))])
    sql = [q["sql"] for q in queries]
    lock = next(i for i, s in enumerate(sql) if "pg_advisory_xact_lock" in s)
    delete = next(i for i, s in enumerate(sql) if s.startswith("DELETE"))
    assert lock < delete


@pytest.mark.parametrize(
    ("windows", "field"),
    [
        ([window(7, (9,), (10,))], "windows.0"),
        ([window(0, (9,), (10,)), window(0, (10,), (10,))], "windows.1"),
        ([window(0, (11,), (10,))], "windows.0"),
        ([window(0, (9,), (11,)), window(1, (9,), (11,)), window(0, (10,), (12,))], "windows.2"),
    ],
)
def test_set_refuses_bad_windows_naming_the_index(teacher, windows, field):
    services.set_availability(teacher.pk, [window(3, (8,), (9,))])
    with pytest.raises(ValidationError) as caught:
        services.set_availability(teacher.pk, windows)
    assert caught.value.field == field
    assert [w.weekday for w in services.windows_of(teacher.pk)] == [3]


def test_touching_windows_are_allowed_and_count_as_one(teacher):
    services.set_availability(
        teacher.pk, [window(0, (10,), (11,)), window(0, (9,), (10,))]
    )
    starts = dates.to_utc(MONDAY, time(9, 30), "UTC")
    assert services.is_available(teacher.pk, starts, 60) is True
    assert services.is_available(teacher.pk, starts, 120) is False


def test_set_refuses_more_than_fifty(teacher):
    many = [window(d % 7, (h,), (h, 30)) for d in range(7) for h in range(8)]
    with pytest.raises(ValidationError) as caught:
        services.set_availability(teacher.pk, many[:51])
    assert caught.value.field == "windows"


def test_no_windows_is_unknown_not_unavailable(teacher, set_features):
    starts = dates.to_utc(MONDAY, time(10), "UTC")
    assert services.is_available(teacher.pk, starts, 45) is None
    session = Session(teacher_id=teacher.pk, starts_at=starts, minutes=45)
    assert services.outside_availability(session) is None  # the switch is off
    set_features(teacher_availability=True)
    assert services.outside_availability(session) is False


def test_is_available_at_the_window_edges(teacher):
    services.set_availability(teacher.pk, [window(0, (9,), (12,))])

    def at(hour, minute=0):
        return dates.to_utc(MONDAY, time(hour, minute), "UTC")

    assert services.is_available(teacher.pk, at(9), 180) is True
    assert services.is_available(teacher.pk, at(8, 59), 30) is False
    assert services.is_available(teacher.pk, at(11, 30), 31) is False
    assert services.is_available(teacher.pk, at(12), 15) is False
    tuesday = dates.to_utc(date(2026, 6, 2), time(10), "UTC")
    assert services.is_available(teacher.pk, tuesday, 30) is False


def test_a_session_crossing_or_ending_at_midnight_is_outside(teacher):
    services.set_availability(teacher.pk, [window(0, (20,), (23, 59))])
    late = dates.to_utc(MONDAY, time(23), "UTC")
    assert services.is_available(teacher.pk, late, 45) is True
    assert services.is_available(teacher.pk, late, 60) is False
    assert services.is_available(teacher.pk, late, 90) is False


def test_the_academys_timezone_decides_the_day_and_the_time(teacher):
    academy_services.update_settings(timezone="Asia/Riyadh")  # UTC+3
    services.set_availability(teacher.pk, [window(0, (0, 30), (2,))])
    # Sunday 31 May 22:00 UTC is Monday 01:00 in Riyadh.
    starts = datetime(2026, 5, 31, 22, 0, tzinfo=UTC)
    assert services.is_available(teacher.pk, starts, 60) is True


def test_is_available_reads_local_times_across_a_dst_change(teacher):
    """Review Focus: 01:30 + 60 minutes on New York's spring-forward night
    (8 March 2026, a Sunday) ends at 03:30 local, not 02:30."""
    academy_services.update_settings(timezone="America/New_York")
    services.set_availability(teacher.pk, [window(6, (1,), (3,))])
    starts = dates.to_utc(date(2026, 3, 8), time(1, 30), "America/New_York")
    assert services.is_available(teacher.pk, starts, 30) is True
    assert services.is_available(teacher.pk, starts, 60) is False


def test_available_map_does_not_grow_with_the_candidates(teacher):
    services.set_availability(teacher.pk, [window(0, (9,), (12,))])
    starts = dates.to_utc(MONDAY, time(10), "UTC")
    with CaptureQueriesContext(connection) as one:
        found = services.available_map([teacher.pk], starts, 60)
    with CaptureQueriesContext(connection) as three:
        many = services.available_map([teacher.pk, 999998, 999999], starts, 60)
    assert found == {teacher.pk: True}
    assert many == {teacher.pk: True, 999998: None, 999999: None}
    assert len(one) == len(three) <= 2  # the settings row, then every window


def test_slots_outside_reads_the_subscriptions_teacher(subscribe, teacher, set_features):
    sub = subscribe(slots=two_slots(time(18, 0)))  # Monday and Wednesday 18:00, 45 min
    slots = list(ScheduleSlot.objects.filter(subscription=sub))
    assert services.slots_outside(sub, slots) is None  # off
    set_features(teacher_availability=True)
    assert services.slots_outside(sub, slots) == {s.pk: False for s in slots}
    services.set_availability(teacher.pk, [window(0, (17,), (19,))])
    flags = services.slots_outside(sub, slots)
    assert {s.weekday: flags[s.pk] for s in slots} == {0: False, 2: True}
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_availability_services.py`
Expected: FAIL (`AttributeError: module 'etqan.scheduling.services' has no attribute 'set_availability'`).

- [ ] **Step 3: Write the service** (`backend/etqan/scheduling/services/availability.py`)

```python
"""Teacher availability (slice B2e §4.5): weekly windows on the academy's
clock (E-9), read to warn (E-11) and to suggest (E-6), never to block. A
session is checked on the local start and the local end of its real UTC
instants, so a clock change between them is counted; a slot, being a
wall-clock time already, is checked as it reads."""

from collections import defaultdict
from collections.abc import Iterable
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.db import connection
from django.db import transaction

from etqan.platform import features
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import TeacherAvailability
from etqan.scheduling.services import rules

AVAILABILITY = "teacher_availability"
MAX_WINDOWS = 50
Spans = dict[int, list[tuple[time, time]]]


def windows_of(teacher_id: int) -> list[TeacherAvailability]:
    """The teacher profile's windows, by weekday and start."""
    return list(
        TeacherAvailability.objects.filter(teacher_id=teacher_id).order_by(
            "weekday", "start_time", "id"
        )
    )


def has_availability() -> bool:
    """Whether any teacher of this academy has a window (the seeds' marker)."""
    return TeacherAvailability.objects.exists()


def _spans(windows) -> Spans:
    """Each weekday's windows, sorted, touching or overlapping ones merged
    into one (§4.5: touching windows count as one)."""
    by_day: dict[int, list[tuple[time, time]]] = defaultdict(list)
    for w in sorted(windows, key=lambda w: (w.weekday, w.start_time)):
        day = by_day[w.weekday]
        if day and w.start_time <= day[-1][1]:
            day[-1] = (day[-1][0], max(day[-1][1], w.end_time))
        else:
            day.append((w.start_time, w.end_time))
    return by_day


def _inside(spans: Spans, weekday: int, start: time, end: time | None) -> bool:
    if end is None:
        return False
    return any(s <= start and end <= e for s, e in spans.get(weekday, ()))


def _clock_end(start: time, minutes: int) -> time | None:
    """A wall-clock time ``minutes`` later the same day; None at or past
    midnight (plan D6: a window cannot end at 24:00)."""
    end = datetime.combine(date.min, start) + timedelta(minutes=minutes)
    return end.time() if end.date() == date.min else None


def _covers(spans: Spans, starts_at: datetime, minutes: int, zone: str) -> bool:
    tz = ZoneInfo(zone)
    start = starts_at.astimezone(tz)
    end = (starts_at + timedelta(minutes=minutes)).astimezone(tz)
    if end.date() != start.date():
        return False
    return _inside(spans, start.weekday(), start.time(), end.time())


def _validated(windows: Iterable[dict]) -> list[TeacherAvailability]:
    rows = list(windows)
    if len(rows) > MAX_WINDOWS:
        raise ValidationError(
            f"Choose at most {MAX_WINDOWS} windows.", field="windows"
        )
    seen: dict[int, list[tuple[time, time]]] = defaultdict(list)
    result = []
    for index, row in enumerate(rows):
        field = f"windows.{index}"
        weekday, start, end = row["weekday"], row["start_time"], row["end_time"]
        if weekday not in range(7):
            raise ValidationError("Choose a day from Monday to Sunday.", field=field)
        if end <= start:
            raise ValidationError("End the window after it starts.", field=field)
        if any(start < e and s < end for s, e in seen[weekday]):
            raise ValidationError(
                "This window overlaps another one on the same day.", field=field
            )
        seen[weekday].append((start, end))
        result.append(
            TeacherAvailability(weekday=weekday, start_time=start, end_time=end)
        )
    return result


def _lock(teacher_id: int) -> None:
    """Plan D7: a transaction-scoped advisory lock per teacher and academy,
    so two saves for one teacher never interleave."""
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT pg_advisory_xact_lock(hashtext(%s), %s)",
            [f"scheduling.availability.{connection.schema_name}", teacher_id],
        )


@transaction.atomic
def set_availability(teacher_id: int, windows: Iterable[dict]) -> list[TeacherAvailability]:
    """§4.5: every window of the teacher (a profile id) replaced by
    ``windows`` — validated first, then under the teacher's lock."""
    rows = _validated(windows)
    _lock(teacher_id)
    TeacherAvailability.objects.filter(teacher_id=teacher_id).delete()
    for row in rows:
        row.teacher_id = teacher_id
    TeacherAvailability.objects.bulk_create(rows)
    return windows_of(teacher_id)


def is_available(teacher_id: int, starts_at: datetime, minutes: int) -> bool | None:
    """§4.5: inside the teacher's windows (True), outside (False), or no
    windows at all (None: unknown, not unavailable)."""
    windows = windows_of(teacher_id)
    if not windows:
        return None
    return _covers(_spans(windows), starts_at, minutes, rules.settings().timezone)


def available_map(
    teacher_ids: Iterable[int], starts_at: datetime, minutes: int
) -> dict[int, bool | None]:
    """`is_available` for several teachers: the settings, then one query."""
    ids = list(teacher_ids)
    zone = rules.settings().timezone
    by_teacher = defaultdict(list)
    for w in TeacherAvailability.objects.filter(teacher_id__in=ids):
        by_teacher[w.teacher_id].append(w)
    return {
        pk: _covers(_spans(by_teacher[pk]), starts_at, minutes, zone)
        if by_teacher[pk]
        else None
        for pk in ids
    }


def outside_availability(session: Session) -> bool | None:
    """E-11: the session-level warning — None while the switch is off (no
    warning is computed); True only when the teacher has windows and the
    session is outside them."""
    if not features.enabled(AVAILABILITY):
        return None
    return is_available(session.teacher_id, session.starts_at, session.minutes) is False


def slots_outside(subscription: Subscription, slots) -> dict[int, bool] | None:
    """E-11: each slot of ``subscription`` against its teacher's windows,
    read once. None while the switch is off."""
    if not features.enabled(AVAILABILITY):
        return None
    spans = _spans(windows_of(subscription.teacher_id))
    return {
        slot.pk: bool(spans)
        and not _inside(
            spans, slot.weekday, slot.start_time, _clock_end(slot.start_time, slot.minutes)
        )
        for slot in slots
    }
```

Add to `backend/etqan/scheduling/services/__init__.py` (imports in alphabetical module order, names in `__all__` sorted):

```python
from etqan.scheduling.services.availability import AVAILABILITY
from etqan.scheduling.services.availability import available_map
from etqan.scheduling.services.availability import has_availability
from etqan.scheduling.services.availability import is_available
from etqan.scheduling.services.availability import outside_availability
from etqan.scheduling.services.availability import set_availability
from etqan.scheduling.services.availability import slots_outside
from etqan.scheduling.services.availability import windows_of
```

and `"AVAILABILITY"`, `"available_map"`, `"has_availability"`, `"is_available"`, `"outside_availability"`, `"set_availability"`, `"slots_outside"`, `"windows_of"` in `__all__`.

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_availability_services.py`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/scheduling/services/availability.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_availability_services.py
git -C $W/backend commit -m "feat(scheduling): teacher availability windows and their checks (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 4: Trial requests — create, update, delete, read and filter

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (a `# ── Trials (slice B2e) ──` section after the archives section)
- Create: `backend/etqan/scheduling/services/trials.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Modify: `backend/etqan/scheduling/tests/conftest.py` (`TRIAL_DAY`, `trial_for`, `hand_trial_session`, `trials_on`, `availability_on`)
- Test: `backend/etqan/scheduling/tests/test_trials_requests.py`

**Interfaces:**
- Consumes: Task 1's models; `subscriptions.active_student` / `active_course` (B2a D7 aliases); `from_django`.
- Produces:
  - In `rules`: `TRIAL_SESSIONS = "trial_sessions"`; `CURRENT_TRIAL_ORDER` (a tuple for `.order_by(*…)`: live first, then latest `starts_at`, then highest id); `trial_rejected()`, `trial_scheduled()`, `trial_converted()` → `ConflictError` with codes `scheduling.trial_rejected` / `.trial_scheduled` / `.trial_converted` (D17's messages); `trial_sessions_of(trial_id) -> QuerySet[Session]`; `current_trial_session(trial_id) -> Session | None`; `is_trial_session(pk) -> bool`.
  - In `trials` (and exported): `NOT_SCHEDULED = "not_scheduled"`, `TRIAL_STATUSES` (`not_scheduled` + every `Session.Status`); `create_trial(*, by, student_id, course_id, source, minutes, heard_from, students_count=1, preferred_gender="any", desired_at=None, requested_on=None, request_status="under_review", rated=False, notes="", inquiry_id=None) -> TrialRequest`; `update_trial(trial, **fields) -> TrialRequest` (keys: `student_id`, `course_id`, `source`, `students_count`, `preferred_gender`, `minutes`, `desired_at`, `requested_on`, `request_status`, `heard_from`, `rated`, `notes`, `inquiry_id`); `delete_trial(trial) -> None`; `lock_trial(trial) -> TrialRequest`; `trial_status(current: Session | None) -> str`; `can_schedule(trial, current) -> bool`; `can_convert(trial, current) -> bool`; `trials_queryset() -> QuerySet[TrialRequest]` (annotated `current_session_id`, `sessions_count`; student user, course and `created_by` joined); `filter_trials(trials, *, q="", student=None, course=None, teacher=None, teacher_gender="", status="", request_status="", source="", heard_from="", requested_from=None, requested_to=None)`; `current_sessions(ids) -> dict[int, Session]` (by session id, teacher user joined; one query); `has_trials() -> bool`.
  - Conftest: `TRIAL_DAY = date(2026, 6, 2)`; `trial_for(world, **overrides)`; `hand_trial_session(trial, teacher, *, occurs_on=TRIAL_DAY, start=time(10, 0), **fields)` (a trial session written straight to the table, for tests whose subject is not `schedule_trial`); fixtures `trials_on`, `availability_on`.

- [ ] **Step 1: Add the shared test helpers** (`backend/etqan/scheduling/tests/conftest.py`, after the B2d block)

```python
# Slice B2e: Tuesday 2 June 2026, the day the trial tests schedule on.
TRIAL_DAY = date(2026, 6, 2)


def trial_for(world, **overrides):
    """A trial request for ``world``'s student and course (slice B2e), made
    by the system."""
    fields = {
        "by": None,
        "student_id": world.student.id,
        "course_id": world.course.id,
        "source": "website",
        "minutes": 30,
        "heard_from": "google",
        **overrides,
    }
    return services.create_trial(**fields)


def hand_trial_session(trial, teacher, *, occurs_on=TRIAL_DAY, start=time(10, 0), **fields):
    """A trial session written straight to the table (``teacher`` is a User),
    for tests whose subject is not `schedule_trial`. The academy is on UTC."""
    values = {
        "kind": Session.Kind.TRIAL,
        "trial": trial,
        "student_id": trial.student_id,
        "teacher_id": teacher.teacher_profile.pk,
        "course_id": trial.course_id,
        "occurs_on": occurs_on,
        "starts_at": dates.to_utc(occurs_on, start, "UTC"),
        "minutes": trial.minutes,
        "generated": False,
        **fields,
    }
    return Session.objects.create(**values)


@pytest.fixture
def trials_on(set_features):
    """Slice B2e: the trial switch on (off by default)."""
    set_features(trial_sessions=True)


@pytest.fixture
def availability_on(set_features):
    """Slice B2e: the availability switch on (off by default)."""
    set_features(teacher_availability=True)
```

- [ ] **Step 2: Write the failing tests** (`backend/etqan/scheduling/tests/test_trials_requests.py`)

```python
"""Slice B2e §4.1, §4.6, E-1, E-2: trial requests and their lists."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionReport
from etqan.scheduling.models import TrialRequest
from etqan.scheduling.tests.conftest import hand_trial_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import trial_for

pytestmark = pytest.mark.django_db
CANCELLED = Session.Status.CANCELLED


def test_a_new_request_is_under_review_from_today(world):
    admin = make_admin()
    trial = trial_for(world, by=admin)
    assert (trial.request_status, trial.requested_on, trial.created_by) == (
        "under_review",
        date(2026, 6, 1),
        admin,
    )
    assert services.trial_status(services.current_trial_session(trial.pk)) == (
        "not_scheduled"
    )


def test_any_profile_status_but_an_active_account(world):
    newcomer = identity_services.create_person(
        "student", full_name="Newcomer", profile={"status": "trial"}
    )
    assert trial_for(world, student_id=newcomer.id).student.user == newcomer
    gone = make_student("Gone")
    identity_services.deactivate(gone, by=None)
    for student_id in (gone.id, world.teacher.id, 999999):
        with pytest.raises(ValidationError) as caught:
            trial_for(world, student_id=student_id)
        assert caught.value.field == "student"


def test_an_inactive_course_is_refused(world):
    catalogue_services.update_course(world.course, is_active=False)
    with pytest.raises(ValidationError) as caught:
        trial_for(world)
    assert caught.value.field == "course"


@pytest.mark.parametrize(
    ("field", "good", "bad"),
    [
        ("minutes", (15, 180), (14, 181)),
        ("students_count", (1, 20), (0, 21)),
    ],
)
def test_the_number_bounds(world, field, good, bad):
    for value in good:
        assert getattr(trial_for(world, **{field: value}), field) == value
    for value in bad:
        with pytest.raises(ValidationError) as caught:
            trial_for(world, **{field: value})
        assert caught.value.field == field


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("source", "fax"),
        ("heard_from", "tv"),
        ("preferred_gender", "other"),
        ("request_status", "done"),
    ],
)
def test_every_choice_is_checked(world, field, value):
    with pytest.raises(ValidationError) as caught:
        trial_for(world, **{field: value})
    assert caught.value.field == field


def test_one_request_per_inquiry(world):
    trial_for(world, inquiry_id=12)
    with pytest.raises(ValidationError) as caught:
        trial_for(world, inquiry_id=12)
    assert caught.value.field == "inquiry_id"
    assert TrialRequest.objects.filter(inquiry_id=12).count() == 1


def test_update_changes_what_was_sent(world):
    trial = trial_for(world)
    other = make_student("Sami")
    services.update_trial(
        trial, student_id=other.id, minutes=45, notes="Prefers evenings", rated=True
    )
    trial.refresh_from_db()
    assert (trial.student.user, trial.minutes, trial.notes, trial.rated) == (
        other,
        45,
        "Prefers evenings",
        True,
    )
    with pytest.raises(ValidationError) as caught:
        services.update_trial(trial, converted_to_id=1)
    assert caught.value.field == "converted_to_id"


@pytest.mark.parametrize(
    "change",
    [
        {"minutes": 45},
        {"request_status": "rejected"},
        {"course_id": "new"},
        {"student_id": "new"},
    ],
)
def test_a_live_session_fixes_student_course_minutes_and_rejection(world, change):
    trial = trial_for(world)
    hand_trial_session(trial, world.teacher)
    if change.get("course_id") == "new":
        change = {
            "course_id": catalogue_services.create_course(
                name_ar="نحو", name_en="Grammar"
            ).pk
        }
    if change.get("student_id") == "new":
        change = {"student_id": make_student("Sami").id}
    with pytest.raises(ConflictError) as caught:
        services.update_trial(trial, **change)
    assert caught.value.code == "scheduling.trial_scheduled"
    services.update_trial(trial, notes="Still editable", minutes=trial.minutes)


def test_a_cancelled_session_fixes_nothing(world):
    trial = trial_for(world)
    hand_trial_session(trial, world.teacher, status=CANCELLED)
    services.update_trial(trial, minutes=60, request_status="rejected")
    trial.refresh_from_db()
    assert (trial.minutes, trial.request_status) == (60, "rejected")


def test_the_current_session_is_the_live_one_else_the_latest(world):
    trial = trial_for(world)
    first = hand_trial_session(trial, world.teacher, status=CANCELLED)
    later = hand_trial_session(
        trial, world.teacher, occurs_on=date(2026, 6, 5), status=CANCELLED
    )
    assert services.current_trial_session(trial.pk) == later
    live = hand_trial_session(trial, world.teacher, occurs_on=date(2026, 6, 3))
    assert services.current_trial_session(trial.pk) == live
    assert services.trial_status(live) == "scheduled"
    assert first.pk < later.pk < live.pk


def test_delete_takes_its_scheduled_and_cancelled_sessions(world):
    trial = trial_for(world)
    hand_trial_session(trial, world.teacher, status=CANCELLED)
    hand_trial_session(trial, world.teacher, occurs_on=date(2026, 6, 4))
    services.delete_trial(trial)
    assert not TrialRequest.objects.filter(pk=trial.pk).exists()
    assert not Session.objects.filter(kind="trial").exists()


@pytest.mark.parametrize(
    "fields",
    [
        {"student_attendance": "present", "status": "completed"},
        {"teacher_attendance": "present"},
        {"status": "at_disposal"},
        {"payroll_locked": True},
        {"status": "cancelled", "student_attendance": "absent"},
    ],
)
def test_delete_refuses_a_marked_completed_disposed_or_paid_session(world, fields):
    trial = trial_for(world)
    hand_trial_session(trial, world.teacher, **fields)
    with pytest.raises(ConflictError) as caught:
        services.delete_trial(trial)
    assert caught.value.code == "scheduling.not_allowed_in_status"
    assert TrialRequest.objects.filter(pk=trial.pk).exists()


def test_delete_refuses_a_converted_request_first(world, subscribe):
    trial = trial_for(world)
    hand_trial_session(
        trial, world.teacher, status="completed", student_attendance="present"
    )
    TrialRequest.objects.filter(pk=trial.pk).update(converted_to=subscribe())
    with pytest.raises(ConflictError) as caught:
        services.delete_trial(trial)
    assert caught.value.code == "scheduling.trial_converted"


def test_delete_locks_the_request_then_its_sessions(world):
    trial = trial_for(world)
    hand_trial_session(trial, world.teacher)
    with CaptureQueriesContext(connection) as queries:
        services.delete_trial(trial)
    locks = [q["sql"] for q in queries if "FOR UPDATE" in q["sql"]]
    assert '"scheduling_trialrequest"' in locks[0]
    assert '"scheduling_session"' in locks[1]
    assert "ORDER BY" in locks[1]


def test_a_reported_session_blocks_the_delete_too(world):
    trial = trial_for(world)
    session = hand_trial_session(
        trial, world.teacher, status="completed", student_attendance="present"
    )
    SessionReport.objects.create(
        session=session, behaviour=4, participation=4, written_by=world.teacher
    )
    with pytest.raises(ConflictError):
        services.delete_trial(trial)


def _ids(**filters):
    trials = services.filter_trials(services.trials_queryset(), **filters)
    return [trial.pk for trial in trials]


def test_the_list_filters(world):
    hamza = make_teacher("Hamza", gender="female")
    review = trial_for(world, source="app", heard_from="facebook")
    booked = trial_for(world, requested_on=date(2026, 5, 20))
    hand_trial_session(booked, hamza)
    done = trial_for(world, heard_from="referral")
    hand_trial_session(
        done, world.teacher, status="completed", student_attendance="present"
    )
    assert _ids() == [done.pk, review.pk, booked.pk]
    assert _ids(status="not_scheduled") == [review.pk]
    assert _ids(status="completed") == [done.pk]
    assert _ids(teacher=hamza.id) == [booked.pk]
    assert _ids(teacher_gender="female") == [booked.pk]
    assert _ids(teacher_gender="male") == [done.pk]
    assert _ids(source="app") == [review.pk]
    assert _ids(heard_from="referral") == [done.pk]
    assert _ids(requested_to=date(2026, 5, 31)) == [booked.pk]
    assert _ids(requested_from=date(2026, 6, 1)) == [done.pk, review.pk]
    assert _ids(q="yus") == [done.pk, review.pk, booked.pk]
    assert _ids(q="nobody") == []
    assert _ids(student=world.student.id, course=world.course.id) == _ids()


def test_the_list_costs_the_same_for_one_or_three_requests(world):
    def read():
        with CaptureQueriesContext(connection) as queries:
            trials = list(services.trials_queryset())
            services.current_sessions(
                [t.current_session_id for t in trials if t.current_session_id]
            )
            names = [t.student.user.full_name for t in trials]  # joined
        assert all(names)
        return len(queries), trials

    one = trial_for(world)
    hand_trial_session(one, world.teacher)
    count_one, _ = read()
    for _ in range(2):
        hand_trial_session(trial_for(world), world.teacher)
    count_three, trials = read()
    assert count_one == count_three
    assert [t.sessions_count for t in trials] == [1, 1, 1]


def test_can_schedule_and_can_convert(world):
    trial = trial_for(world)
    assert services.can_schedule(trial, None) is True
    assert services.can_convert(trial, None) is False
    session = hand_trial_session(trial, world.teacher)
    assert services.can_schedule(trial, session) is False
    session.status = "completed"
    assert services.can_convert(trial, session) is True
    session.status = "cancelled"
    assert services.can_schedule(trial, session) is True
    trial.request_status = "rejected"
    assert services.can_schedule(trial, session) is False


def test_desired_at_is_an_instant(world):
    at = datetime(2026, 6, 3, 15, 0, tzinfo=UTC)
    assert trial_for(world, desired_at=at).desired_at == at
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_requests.py`
Expected: FAIL (`AttributeError: module 'etqan.scheduling.services' has no attribute 'create_trial'`).

- [ ] **Step 4: Add the shared trial rules** (`backend/etqan/scheduling/services/rules.py`)

Imports to add: `from django.db.models import Case`, `from django.db.models import IntegerField`, `from django.db.models import When`. After the archives section (`archivable`), add:

```python
# ── Trials (slice B2e) ───────────────────────────────────────────────────────

TRIAL_SESSIONS = "trial_sessions"
TRIAL = Session.Kind.TRIAL
# E-3: a request's current session is its live one, else its latest.
CURRENT_TRIAL_ORDER = (
    Case(
        When(status=Session.Status.CANCELLED, then=Value(1)),
        default=Value(0),
        output_field=IntegerField(),
    ),
    F("starts_at").desc(),
    F("id").desc(),
)


def trial_rejected() -> ConflictError:
    return ConflictError(
        "This trial request was rejected.", code="scheduling.trial_rejected"
    )


def trial_scheduled() -> ConflictError:
    return ConflictError(
        "This trial already has a session. Change or cancel that session first.",
        code="scheduling.trial_scheduled",
    )


def trial_converted() -> ConflictError:
    return ConflictError(
        "This trial is already a subscription.", code="scheduling.trial_converted"
    )


def trial_sessions_of(trial_id: int) -> QuerySet[Session]:
    return Session.objects.filter(trial_id=trial_id)


def current_trial_session(trial_id: int) -> Session | None:
    """E-3: the request's live session, else its latest."""
    return trial_sessions_of(trial_id).order_by(*CURRENT_TRIAL_ORDER).first()


def is_trial_session(pk) -> bool:
    """Whether ``pk`` is a trial session of this academy (one indexed query)."""
    return Session.objects.filter(pk=pk, kind=TRIAL).exists()
```

- [ ] **Step 5: Write the requests service** (`backend/etqan/scheduling/services/trials.py`)

```python
"""Trial requests (slice B2e §4.1, §4.6): the office's record of a request
for a trial session, its lists, and deleting it with its sessions. Lock
order (§4): the request, then its sessions in id order, then (conversion,
`services.conversion`) a new subscription. A session-first service never
locks the request."""

from datetime import date
from datetime import datetime

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import Count
from django.db.models import Exists
from django.db.models import OuterRef
from django.db.models import Q
from django.db.models import QuerySet
from django.db.models import Subquery
from django.db.models import Value
from django.db.models.functions import Coalesce

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.validators import from_django
from etqan.scheduling.models import Session
from etqan.scheduling.models import TrialRequest
from etqan.scheduling.services import rules
from etqan.scheduling.services import subscriptions as subs

REQUEST = TrialRequest.RequestStatus
CANCELLED = Session.Status.CANCELLED
NOT_SCHEDULED = "not_scheduled"
TRIAL_STATUSES = (NOT_SCHEDULED, *Session.Status.values)
EDITABLE = (
    "student_id",
    "course_id",
    "source",
    "students_count",
    "preferred_gender",
    "minutes",
    "desired_at",
    "requested_on",
    "request_status",
    "heard_from",
    "rated",
    "notes",
    "inquiry_id",
)
# §4.1: what a live session fixes (change the session instead).
FIXED_BY_SESSION = frozenset({"student_id", "course_id", "minutes"})


def _save(trial: TrialRequest) -> None:
    try:
        # Constraints are checked here, with readable messages.
        trial.full_clean(validate_constraints=False)
    except DjangoValidationError as exc:
        raise from_django(exc) from None
    if (
        trial.inquiry_id is not None
        and TrialRequest.objects.filter(inquiry_id=trial.inquiry_id)
        .exclude(pk=trial.pk)
        .exists()
    ):
        raise ValidationError(
            "This inquiry already has a trial request.", field="inquiry_id"
        )
    trial.save()


def has_trials() -> bool:
    """Whether this academy has any trial request (the seeds' marker)."""
    return TrialRequest.objects.exists()


@transaction.atomic
def create_trial(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §6)
    *,
    by,
    student_id: int,
    course_id: int,
    source: str,
    minutes: int,
    heard_from: str,
    students_count: int = 1,
    preferred_gender: str = TrialRequest.Gender.ANY,
    desired_at: datetime | None = None,
    requested_on: date | None = None,
    request_status: str = REQUEST.UNDER_REVIEW,
    rated: bool = False,
    notes: str = "",
    inquiry_id: int | None = None,
) -> TrialRequest:
    """E-1: an active student (any profile status, `trial` included) and an
    active course; the request date defaults to the academy's today. ``by``
    is who recorded it (None: the system)."""
    trial = TrialRequest(
        student=subs.active_student(student_id),
        course=subs.active_course(course_id),
        source=source,
        minutes=minutes,
        heard_from=heard_from,
        students_count=students_count,
        preferred_gender=preferred_gender,
        desired_at=desired_at,
        requested_on=requested_on or rules.today(),
        request_status=request_status,
        rated=rated,
        notes=notes,
        inquiry_id=inquiry_id,
        created_by=by,
    )
    _save(trial)
    return trial


def lock_trial(trial: TrialRequest) -> TrialRequest:
    """The request's row, locked for this transaction and read fresh (only
    its own row: ``of=("self",)``)."""
    locked = (
        TrialRequest.objects.select_for_update(of=("self",))
        .select_related("student__user", "course")
        .filter(pk=trial.pk)
        .first()
    )
    if locked is None:
        raise NotFoundError("Trial request", trial.pk)
    return locked


def lock_sessions(trial: TrialRequest) -> list[int]:
    """§4: the request's sessions, after the request, in id order."""
    return list(
        Session.objects.select_for_update()
        .filter(trial=trial)
        .order_by("pk")
        .values_list("pk", flat=True)
    )


def _value(trial: TrialRequest, name: str):
    return trial.student.user_id if name == "student_id" else getattr(trial, name)


@transaction.atomic
def update_trial(trial: TrialRequest, **fields) -> TrialRequest:
    """§4.1: change what was sent. While the request has a live session, a
    new student, course or length — and a rejection — is refused 409
    `scheduling.trial_scheduled` (change or cancel the session first)."""
    unknown = sorted(set(fields) - set(EDITABLE))
    if unknown:
        raise ValidationError("This field can't be changed.", field=unknown[0])
    locked = lock_trial(trial)
    changed = {
        name: value for name, value in fields.items() if value != _value(locked, name)
    }
    live = rules.trial_sessions_of(locked.pk).exclude(status=CANCELLED).exists()
    rejects = changed.get("request_status") == REQUEST.REJECTED
    if live and (FIXED_BY_SESSION & set(changed) or rejects):
        raise rules.trial_scheduled()
    if "student_id" in changed:
        locked.student = subs.active_student(changed.pop("student_id"))
    if "course_id" in changed:
        locked.course = subs.active_course(changed.pop("course_id"))
    for name, value in changed.items():
        setattr(locked, name, value)
    _save(locked)
    return locked


@transaction.atomic
def delete_trial(trial: TrialRequest) -> None:
    """§4.1: lock the request, then its sessions. Refusals in order: it was
    converted; a session is marked, completed, at the administration's
    disposal or on an issued payslip. Then its sessions (scheduled or
    cancelled, with their reports and log) go, and the request."""
    locked = lock_trial(trial)
    ids = lock_sessions(locked)
    if locked.converted_to_id is not None:
        raise rules.trial_converted()
    sessions = Session.objects.filter(pk__in=ids)
    if sessions.filter(
        rules.MARKED | Q(status=Session.Status.AT_DISPOSAL) | Q(payroll_locked=True)
    ).exists():
        raise ConflictError(
            "A session of this trial is marked, completed, at the "
            "administration's disposal or paid.",
            code="scheduling.not_allowed_in_status",
        )
    sessions.delete()
    locked.delete()


# ── Reads (§4.6) ─────────────────────────────────────────────────────────────


def trial_status(current: Session | None) -> str:
    """E-3: `not_scheduled`, or the current session's status."""
    return NOT_SCHEDULED if current is None else current.status


def can_schedule(trial: TrialRequest, current: Session | None) -> bool:
    """Plan D2: what `schedule_trial` would allow, as the page asks it."""
    return (
        trial.converted_to_id is None
        and trial.request_status != REQUEST.REJECTED
        and (current is None or current.status == CANCELLED)
    )


def can_convert(trial: TrialRequest, current: Session | None) -> bool:
    """Plan D2, E-7: the current session is completed, not yet converted."""
    return (
        trial.converted_to_id is None
        and current is not None
        and current.status == Session.Status.COMPLETED
    )


def trials_queryset() -> QuerySet[TrialRequest]:
    """Requests with what a row shows, in one query: the student and course
    joined, the current session's id (E-3) and the number of sessions."""
    current = Session.objects.filter(trial=OuterRef("pk")).order_by(
        *rules.CURRENT_TRIAL_ORDER
    )
    counted = (
        Session.objects.filter(trial=OuterRef("pk"))
        .order_by()
        .values("trial")
        .annotate(n=Count("pk"))
        .values("n")
    )
    return TrialRequest.objects.select_related(
        "student__user", "course", "created_by"
    ).annotate(
        current_session_id=Subquery(current.values("pk")[:1]),
        sessions_count=Coalesce(Subquery(counted[:1]), Value(0)),
    )


def current_sessions(ids) -> dict[int, Session]:
    """The current sessions of a page of requests, by session id, with their
    teachers: one query."""
    sessions = Session.objects.filter(pk__in=list(ids)).select_related("teacher__user")
    return {session.pk: session for session in sessions}


def filter_trials(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (spec §4.6)
    trials: QuerySet[TrialRequest],
    *,
    q: str = "",
    student: int | None = None,
    course: int | None = None,
    teacher: int | None = None,
    teacher_gender: str = "",
    status: str = "",
    request_status: str = "",
    source: str = "",
    heard_from: str = "",
    requested_from: date | None = None,
    requested_to: date | None = None,
) -> QuerySet[TrialRequest]:
    """§4.6, plan D5: people are User ids; the teacher, their gender and the
    status are the current session's; newest first."""
    exact = {
        "student__user_id": student,
        "course_id": course,
        "request_status": request_status,
        "source": source,
        "heard_from": heard_from,
        "requested_on__gte": requested_from,
        "requested_on__lte": requested_to,
    }
    trials = trials.filter(
        **{key: value for key, value in exact.items() if value not in (None, "")}
    )
    if q := q.strip():
        trials = trials.filter(student__user__full_name__icontains=q)
    if status == NOT_SCHEDULED:
        trials = trials.filter(current_session_id__isnull=True)
    on_current = {
        "teacher__user_id": teacher,
        "teacher__gender": teacher_gender,
        "status": "" if status == NOT_SCHEDULED else status,
    }
    wanted = {key: value for key, value in on_current.items() if value not in (None, "")}
    if wanted:
        trials = trials.filter(
            Exists(Session.objects.filter(pk=OuterRef("current_session_id"), **wanted))
        )
    return trials.order_by("-requested_on", "-id")
```

Add to `backend/etqan/scheduling/services/__init__.py`:

```python
from etqan.scheduling.services.rules import TRIAL_SESSIONS
from etqan.scheduling.services.rules import current_trial_session
from etqan.scheduling.services.rules import is_trial_session
from etqan.scheduling.services.trials import NOT_SCHEDULED
from etqan.scheduling.services.trials import TRIAL_STATUSES
from etqan.scheduling.services.trials import can_convert
from etqan.scheduling.services.trials import can_schedule
from etqan.scheduling.services.trials import create_trial
from etqan.scheduling.services.trials import current_sessions
from etqan.scheduling.services.trials import delete_trial
from etqan.scheduling.services.trials import filter_trials
from etqan.scheduling.services.trials import has_trials
from etqan.scheduling.services.trials import trial_status
from etqan.scheduling.services.trials import trials_queryset
from etqan.scheduling.services.trials import update_trial
```

with each name in `__all__` (sorted).

- [ ] **Step 6: Run the tests to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_requests.py`
Expected: PASS. If `test_delete_locks_the_request_then_its_sessions` finds the request's lock written as `FOR UPDATE OF "scheduling_trialrequest"`, assert that form (Plan 31 ruling R6: assert trunk's own SQL).

- [ ] **Step 7: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/scheduling/services/rules.py etqan/scheduling/services/trials.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_trials_requests.py
git -C $W/backend commit -m "feat(scheduling): trial requests, their refusals and lists (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 5: Scheduling a trial; the generic delete and restore learn trial sessions

**Files:**
- Modify: `backend/etqan/scheduling/services/manual.py` (`_session(..., trial=None)`, `add_trial_session`, `delete_session`'s first refusal)
- Modify: `backend/etqan/scheduling/services/rules.py` (`refuse_trial_restore`)
- Modify: `backend/etqan/scheduling/services/attendance.py` (`restore_session` calls it)
- Modify: `backend/etqan/scheduling/services/trials.py` (`Scheduled`, `schedule_trial`)
- Modify: `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/tests/conftest.py` (`schedule_for`)
- Test: `backend/etqan/scheduling/tests/test_trials_scheduling.py`

**Interfaces:**
- Consumes: Task 4's `lock_trial`, `lock_sessions`, `rules.trial_*`; B2a's `manual._session` / `_add` / `Added`; `subs.course_teacher`.
- Produces: `manual.add_trial_session(*, by, trial, teacher, occurs_on, start_time, minutes, meeting_url, pays_teacher) -> Added`; `trials.Scheduled(trial: TrialRequest, session: Session, conflicts: list[tuple[Session, Session]])`; `schedule_trial(trial, *, by, teacher_id: int, occurs_on: date, start_time: time, minutes: int | None = None, meeting_url: str = "", pays_teacher: bool = True) -> Scheduled` (exported, with `Scheduled`); `rules.refuse_trial_restore(session)`; `delete_session` refuses a trial session with 409 `scheduling.trial_session`. Conftest `schedule_for(trial, teacher, *, occurs_on=TRIAL_DAY, start=time(10, 0), **fields) -> Scheduled` (as the system).

- [ ] **Step 1: Add the conftest helper** (`backend/etqan/scheduling/tests/conftest.py`, after `hand_trial_session`)

```python
def schedule_for(trial, teacher, *, occurs_on=TRIAL_DAY, start=time(10, 0), **fields):
    """`schedule_trial` as the system (slice B2e); ``teacher`` is a User."""
    return services.schedule_trial(
        trial,
        by=None,
        teacher_id=teacher.id,
        occurs_on=occurs_on,
        start_time=start,
        **fields,
    )
```

- [ ] **Step 2: Write the failing tests** (`backend/etqan/scheduling/tests/test_trials_scheduling.py`)

```python
"""Slice B2e §4.1–§4.2, E-3–E-5, E-12: a trial request scheduled as a trial
session, which then lives through every session flow unchanged."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.academy import services as academy_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import TrialRequest
from etqan.scheduling.services import rules
from etqan.scheduling.tests.conftest import TRIAL_DAY
from etqan.scheduling.tests.conftest import course_teacher
from etqan.scheduling.tests.conftest import hand_trial_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import schedule_for
from etqan.scheduling.tests.conftest import trial_for
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db


def test_scheduling_makes_a_trial_session_from_the_request(world):
    admin = make_admin()
    trial = trial_for(world, minutes=40)
    result = services.schedule_trial(
        trial,
        by=admin,
        teacher_id=world.teacher.id,
        occurs_on=TRIAL_DAY,
        start_time=time(16, 0),
    )
    session = result.session
    assert (
        session.kind,
        session.trial_id,
        session.subscription_id,
        session.slot_id,
        session.generated,
    ) == ("trial", trial.pk, None, None, False)
    assert (session.student_id, session.course_id, session.minutes) == (
        trial.student_id,
        trial.course_id,
        40,
    )
    assert session.teacher.user == world.teacher
    assert session.meeting_url == "https://meet.test/bilal"
    assert (session.pays_teacher, session.created_by, session.status) == (
        True,
        admin,
        "scheduled",
    )
    assert session.starts_at == datetime(2026, 6, 2, 16, 0, tzinfo=UTC)
    assert result.trial.request_status == "accepted"
    assert result.conflicts == []


def test_the_body_overrides_the_defaults(world):
    trial = trial_for(world, request_status="accepted")
    result = schedule_for(
        trial,
        world.teacher,
        minutes=60,
        meeting_url="https://meet.test/trial",
        pays_teacher=False,
    )
    assert (
        result.session.minutes,
        result.session.meeting_url,
        result.session.pays_teacher,
    ) == (60, "https://meet.test/trial", False)
    assert result.trial.request_status == "accepted"


def test_the_start_is_the_academys_wall_clock(world):
    academy_services.update_settings(timezone="Asia/Riyadh")
    session = schedule_for(trial_for(world), world.teacher, start=time(16, 0)).session
    assert session.starts_at == datetime(2026, 6, 2, 13, 0, tzinfo=UTC)


def test_a_past_start_is_allowed(world):
    session = schedule_for(
        trial_for(world), world.teacher, occurs_on=date(2026, 5, 30)
    ).session
    assert services.has_started(session)


def test_refusals_in_order(world):
    trial = trial_for(world)
    schedule_for(trial, world.teacher)
    hamza = make_teacher("Hamza")  # not one of the course's teachers
    with pytest.raises(ConflictError) as caught:
        schedule_for(trial, hamza)  # the live session comes before the teacher
    assert caught.value.code == "scheduling.trial_scheduled"
    rejected = trial_for(world, request_status="rejected")
    hand_trial_session(rejected, world.teacher)  # rejected comes before live
    with pytest.raises(ConflictError) as caught:
        schedule_for(rejected, world.teacher)
    assert caught.value.code == "scheduling.trial_rejected"
    with pytest.raises(ValidationError) as caught:
        schedule_for(trial_for(world), hamza)
    assert caught.value.field == "teacher_id"


def test_converted_comes_first(world, subscribe):
    trial = trial_for(world, request_status="rejected")
    TrialRequest.objects.filter(pk=trial.pk).update(converted_to=subscribe())
    with pytest.raises(ConflictError) as caught:
        schedule_for(trial, world.teacher)
    assert caught.value.code == "scheduling.trial_converted"


def test_an_inactive_teacher_is_refused_on_teacher_id(world):
    other = course_teacher(world, "Hamza")
    identity_services.deactivate(other, by=None)
    with pytest.raises(ValidationError) as caught:
        schedule_for(trial_for(world), other)
    assert caught.value.field == "teacher_id"


def test_overlaps_are_reported_never_blocked(world, subscribe):
    subscribe(slots=two_slots(time(10, 0)))  # Monday and Wednesday 10:00
    result = schedule_for(
        trial_for(world), world.teacher, occurs_on=date(2026, 6, 3), start=time(10, 15)
    )
    assert [(s.pk, o.occurs_on) for s, o in result.conflicts] == [
        (result.session.pk, date(2026, 6, 3))
    ]


def test_cancel_then_schedule_again_keeps_history_and_one_live(world):
    trial = trial_for(world)
    first = schedule_for(trial, world.teacher).session
    services.cancel_session(first, by=None, reason="Student was ill")
    second = schedule_for(trial, world.teacher, occurs_on=date(2026, 6, 4)).session
    assert list(
        Session.objects.filter(trial=trial).order_by("pk").values_list("status", flat=True)
    ) == ["cancelled", "scheduled"]
    assert services.current_trial_session(trial.pk) == second
    with pytest.raises(ConflictError) as caught:
        services.restore_session(first, by=None)
    assert caught.value.code == "scheduling.trial_scheduled"
    with pytest.raises(IntegrityError), transaction.atomic():
        Session.objects.filter(pk=first.pk).update(status="scheduled")


def test_restore_refusals_for_a_trial_session(world, subscribe):
    trial = trial_for(world)
    session = schedule_for(trial, world.teacher).session
    services.cancel_session(session, by=None, reason="Moved")
    services.update_trial(trial, request_status="rejected")
    with pytest.raises(ConflictError) as caught:
        services.restore_session(session, by=None)
    assert caught.value.code == "scheduling.trial_rejected"
    services.update_trial(trial, request_status="accepted")
    TrialRequest.objects.filter(pk=trial.pk).update(converted_to=subscribe())
    with pytest.raises(ConflictError) as caught:
        services.restore_session(session, by=None)
    assert caught.value.code == "scheduling.trial_converted"
    TrialRequest.objects.filter(pk=trial.pk).update(converted_to=None)
    services.restore_session(session, by=None)
    session.refresh_from_db()
    assert session.status == "scheduled"


def test_the_generic_delete_refuses_a_trial_session(world):
    session = schedule_for(trial_for(world), world.teacher).session
    with pytest.raises(ConflictError) as caught:
        services.delete_session(session)
    assert caught.value.code == "scheduling.trial_session"
    assert Session.objects.filter(pk=session.pk).exists()


def test_a_trial_session_never_consumes(world, clock):
    session = schedule_for(trial_for(world), world.teacher).session
    clock.set(datetime(2026, 6, 2, 11, 0, tzinfo=UTC))
    services.mark_attendance(session, by=None, student_attendance="present")
    consumed = Session.objects.filter(rules.consuming(rules.settings()), pk=session.pk)
    assert not consumed.exists()
    assert services.is_compensable(Session.objects.get(pk=session.pk)) is False


def test_a_trial_session_gets_the_session_reminder(world):
    session = schedule_for(trial_for(world), world.teacher).session
    starting = services.sessions_starting(
        now=datetime(2026, 6, 2, 9, 0, tzinfo=UTC), within=timedelta(hours=2)
    )
    assert session.pk in [s.pk for s in starting]


def test_payroll_pays_it_while_it_pays_the_teacher(world):
    paid = schedule_for(trial_for(world), world.teacher).session
    unpaid = schedule_for(
        trial_for(world), world.teacher, start=time(12, 0), pays_teacher=False
    ).session
    ids = {s.pk for s in services.payroll_sessions(TRIAL_DAY, TRIAL_DAY)}
    assert paid.pk in ids
    assert unpaid.pk not in ids


def test_the_student_and_the_office_postpone_it_by_b2bs_rules(world, set_features):
    set_features(postponement=True)
    session = schedule_for(trial_for(world), world.teacher, occurs_on=date(2026, 6, 3)).session
    moved = services.postpone_session(
        session, by=world.student, occurs_on=date(2026, 6, 4), start_time=time(10, 0)
    ).session
    assert moved.occurs_on == date(2026, 6, 4)
    again = services.postpone_session(
        moved, by=make_admin(), occurs_on=date(2026, 6, 5), start_time=time(9, 0)
    ).session
    assert (again.occurs_on, again.kind, again.trial_id) == (
        date(2026, 6, 5),
        "trial",
        session.trial_id,
    )
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_scheduling.py`
Expected: FAIL (`ImportError: cannot import name 'schedule_for'` until Step 1 is in, then `AttributeError: … 'schedule_trial'`).

- [ ] **Step 4: Teach B2a's helper the trial** (`backend/etqan/scheduling/services/manual.py`)

`_session` gains a last keyword `trial=None` and passes `trial=trial` to `Session(...)`:

```python
    compensates: Session | None = None,
    trial=None,
) -> Session:
    return Session(
        kind=kind,
        subscription=subscription,
        student=student,
        course=course,
        teacher=teacher,
        compensates=compensates,
        # Slice B2e (E-3): a trial session points at its request.
        trial=trial,
```

After `create_compensation`, add:

```python
def add_trial_session(  # noqa: PLR0913 -- keyword-only; the columns a trial session sets
    *,
    by,
    trial,
    teacher,
    occurs_on: date,
    start_time: time,
    minutes: int,
    meeting_url: str,
    pays_teacher: bool,
) -> Added:
    """Slice B2e §4.2: a trial session, built as every hand-added one (the
    academy's wall clock to UTC with Plan 4's one conversion, `full_clean`):
    no subscription and no slot, the request's student and course. The
    caller (`trials.schedule_trial`) holds the request's lock."""
    return _add(
        _session(
            by=by,
            kind=Session.Kind.TRIAL,
            subscription=None,
            student=trial.student,
            course=trial.course,
            teacher=teacher,
            occurs_on=occurs_on,
            start_time=start_time,
            minutes=minutes,
            meeting_url=meeting_url,
            pays_teacher=pays_teacher,
            notes="",
            trial=trial,
        )
    )
```

In `delete_session`, right after `locked, _original = attendance.lock_with_original(session)` (before `refuse_if_paid`), and in its docstring's refusal list ("Refusals in this order: a trial session, paid, generated, …"):

```python
    if locked.kind == Session.Kind.TRIAL:
        # Slice B2e §4.1: a trial session goes with its trial, never alone.
        raise ConflictError(
            "This is a trial session. Delete or cancel it from its trial.",
            code="scheduling.trial_session",
        )
```

- [ ] **Step 5: The restore refusal** (`backend/etqan/scheduling/services/rules.py`, in the Trials section; add `from etqan.scheduling.models import TrialRequest` to its imports)

```python
def refuse_trial_restore(session: Session) -> None:
    """§4.1: a trial session comes back only while its request takes one —
    not rejected, not converted, and no other session of it live. Read after
    the session's lock and never locking the request (lock order §4); the
    partial unique constraint backs the last rule."""
    if session.kind != TRIAL:
        return
    trial = (
        TrialRequest.objects.filter(pk=session.trial_id)
        .values("request_status", "converted_to_id")
        .first()
    )
    if trial["request_status"] == TrialRequest.RequestStatus.REJECTED:
        raise trial_rejected()
    if trial["converted_to_id"] is not None:
        raise trial_converted()
    others = trial_sessions_of(session.trial_id).exclude(pk=session.pk)
    if others.exclude(status=Session.Status.CANCELLED).exists():
        raise trial_scheduled()
```

In `backend/etqan/scheduling/services/attendance.py`'s `restore_session`, right after `refuse_if_compensated(locked)`:

```python
        rules.refuse_trial_restore(locked)  # slice B2e §4.1
```

and add "Slice B2e: a trial session is refused while its request is rejected or converted, or another of its sessions is live." to the docstring.

- [ ] **Step 6: Write `schedule_trial`** (`backend/etqan/scheduling/services/trials.py`)

Imports to add: `from dataclasses import dataclass`, `from datetime import time`, `from etqan.scheduling.services import manual`. Then:

```python
@dataclass(frozen=True)
class Scheduled:
    trial: TrialRequest
    session: Session
    conflicts: list[tuple[Session, Session]]


@transaction.atomic
def schedule_trial(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §6)
    trial: TrialRequest,
    *,
    by,
    teacher_id: int,
    occurs_on: date,
    start_time: time,
    minutes: int | None = None,
    meeting_url: str = "",
    pays_teacher: bool = True,
) -> Scheduled:
    """§4.2. Lock the request, then its sessions. Refusals in order: it was
    converted; rejected; a live session; the teacher is inactive or does not
    teach the course (400 on `teacher_id`, plan D3). A past start is allowed
    (E-5). The length defaults to the request's, the link to the teacher's;
    a request under review becomes accepted. The teacher's overlapping
    sessions are reported, never blocked (P4-9)."""
    locked = lock_trial(trial)
    lock_sessions(locked)
    if locked.converted_to_id is not None:
        raise rules.trial_converted()
    if locked.request_status == REQUEST.REJECTED:
        raise rules.trial_rejected()
    if rules.trial_sessions_of(locked.pk).exclude(status=CANCELLED).exists():
        raise rules.trial_scheduled()
    try:
        teacher = subs.course_teacher(teacher_id, locked.course)
    except ValidationError as exc:
        raise ValidationError(exc.message, field="teacher_id") from None
    added = manual.add_trial_session(
        by=by,
        trial=locked,
        teacher=teacher,
        occurs_on=occurs_on,
        start_time=start_time,
        minutes=minutes or locked.minutes,
        meeting_url=meeting_url,
        pays_teacher=pays_teacher,
    )
    if locked.request_status == REQUEST.UNDER_REVIEW:
        locked.request_status = REQUEST.ACCEPTED
        locked.save(update_fields=["request_status", "updated_at"])
    return Scheduled(locked, added.session, added.conflicts)
```

Export `Scheduled` and `schedule_trial` from `services/__init__.py` (and `add_trial_session` is internal: not exported).

- [ ] **Step 7: Run the tests to see them pass, and the suites they touch**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_scheduling.py etqan/scheduling/tests/test_session_classes_manual.py etqan/scheduling/tests/test_attendance.py etqan/scheduling/tests/test_times_postponement_postpone.py`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/scheduling/services/manual.py etqan/scheduling/services/rules.py etqan/scheduling/services/attendance.py etqan/scheduling/services/trials.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_trials_scheduling.py
git -C $W/backend commit -m "feat(scheduling): schedule a trial as a trial session; delete and restore guard it (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 6: Suggest a teacher

**Files:**
- Create: `backend/etqan/scheduling/services/suggest.py`
- Modify: `backend/etqan/scheduling/services/__init__.py`
- Test: `backend/etqan/scheduling/tests/test_trials_suggest.py`

**Interfaces:**
- Consumes: Task 2's `identity_services.active_teachers`; Task 3's `availability.available_map`, `AVAILABILITY`; `catalogue_services.teacher_user_ids_for_course`; `subs.active_course`; `rules.ENDS_AT`.
- Produces: `Suggestion(teacher, free: bool, available: bool | None, gender_match: bool, week_sessions: int)` (`teacher` is a TeacherProfile with its user); `suggest_teachers(*, course_id: int, occurs_on: date, start_time: time, minutes: int, preferred_gender: str = "any") -> list[Suggestion]` — at most `MAX_SUGGESTIONS = 5`, ranked by E-6; 400 on `course` for an unknown or inactive course. Both exported.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_trials_suggest.py`)

```python
"""Slice B2e §4.3, E-6: the ranked teachers for a trial's day and time."""

from datetime import time

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.tests.conftest import TRIAL_DAY
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import schedule_for
from etqan.scheduling.tests.conftest import trial_for
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
TUESDAY = 1


def teach(world, *teachers):
    """``world``'s course lists its teacher and ``teachers`` (Users)."""
    catalogue_services.update_course(
        world.course, teacher_ids=[world.teacher.id, *(t.id for t in teachers)]
    )
    return teachers


def suggest(world, **overrides):
    fields = {
        "course_id": world.course.id,
        "occurs_on": TRIAL_DAY,
        "start_time": time(10, 0),
        "minutes": 30,
        **overrides,
    }
    return services.suggest_teachers(**fields)


def rows(found, *flags):
    return [
        (s.teacher.user.full_name, *(getattr(s, flag) for flag in flags))
        for s in found
    ]


def window(weekday, start, end):
    return {"weekday": weekday, "start_time": time(start), "end_time": time(end)}


def test_the_courses_teachers_when_it_lists_any(world):
    teach(world, make_teacher("Amr"))
    make_teacher("Outsider")
    assert rows(suggest(world)) == [("Amr",), ("Bilal",)]


def test_every_active_teacher_when_the_course_lists_none(world):
    open_course = catalogue_services.create_course(name_ar="نحو", name_en="Grammar")
    make_teacher("Amr")
    gone = make_teacher("Gone")
    identity_services.deactivate(gone, by=None)
    assert rows(suggest(world, course_id=open_course.pk)) == [("Amr",), ("Bilal",)]


def test_an_unknown_or_inactive_course_is_refused(world):
    with pytest.raises(ValidationError) as caught:
        suggest(world, course_id=999999)
    assert caught.value.field == "course"


def test_free_teachers_first(world):
    (amr,) = teach(world, make_teacher("Amr"))
    schedule_for(trial_for(world), amr, start=time(10, 15))
    assert rows(suggest(world), "free") == [("Bilal", True), ("Amr", False)]


def test_availability_ranks_yes_then_unknown_then_no(world, availability_on):
    amr, cyd = teach(world, make_teacher("Amr"), make_teacher("Cyd"))
    services.set_availability(cyd.teacher_profile.pk, [window(TUESDAY, 9, 12)])
    services.set_availability(amr.teacher_profile.pk, [window(0, 9, 12)])
    assert rows(suggest(world), "available") == [
        ("Cyd", True),
        ("Bilal", None),
        ("Amr", False),
    ]


def test_availability_is_ignored_while_it_is_off(world):
    amr, cyd = teach(world, make_teacher("Amr"), make_teacher("Cyd"))
    services.set_availability(amr.teacher_profile.pk, [window(0, 9, 12)])
    assert rows(suggest(world), "available") == [
        ("Amr", None),
        ("Bilal", None),
        ("Cyd", None),
    ]


def test_gender_matches_rank_and_no_gender_never_matches(world):
    amal = make_teacher("Amal", gender="female")
    nadir = make_teacher("Nadir")
    profile = nadir.teacher_profile
    type(profile).objects.filter(pk=profile.pk).update(gender="")
    teach(world, amal, nadir)
    assert rows(suggest(world, preferred_gender="female"), "gender_match") == [
        ("Amal", True),
        ("Bilal", False),
        ("Nadir", False),
    ]
    assert rows(suggest(world, preferred_gender="male"), "gender_match") == [
        ("Bilal", True),
        ("Amal", False),
        ("Nadir", False),
    ]
    assert all(s.gender_match for s in suggest(world))  # no preference


def test_fewer_sessions_in_the_academy_week_then_the_name(world, subscribe):
    teach(world, make_teacher("Zaki"), make_teacher("Amr"))
    subscribe(slots=two_slots(time(18, 0)))  # Bilal: Monday 1 and Wednesday 3 June
    assert rows(suggest(world), "week_sessions") == [
        ("Amr", 0),
        ("Zaki", 0),
        ("Bilal", 2),
    ]


def test_at_most_five(world):
    teach(world, *(make_teacher(f"Teacher {n}") for n in range(6)))
    assert len(suggest(world)) == services.MAX_SUGGESTIONS == 5


@pytest.mark.parametrize("availability", [False, True])
def test_the_query_count_does_not_grow_with_the_candidates(
    world, set_features, availability
):
    set_features(teacher_availability=availability)

    def count():
        with CaptureQueriesContext(connection) as queries:
            suggest(world)
        return len(queries)

    one = count()
    teach(world, make_teacher("Amr"), make_teacher("Cyd"), make_teacher("Dina"))
    assert count() == one
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_suggest.py`
Expected: FAIL (`AttributeError: … has no attribute 'suggest_teachers'`).

- [ ] **Step 3: Write the service** (`backend/etqan/scheduling/services/suggest.py`)

```python
"""Suggest a teacher for a trial (slice B2e §4.3, E-6). Candidates are the
course's teachers (every active teacher when it lists none), active. Ranked
by: free (no overlapping non-cancelled session), then available (inside
their windows; then no windows; then outside — ignored while availability is
off), then gender match (ignored with no preference; a teacher with no
gender never matches), then fewest non-cancelled sessions in the academy
week (Monday to Sunday) of the local date, then name. Never blocks. A fixed
number of queries, however many candidates."""

from dataclasses import dataclass
from datetime import date
from datetime import time
from datetime import timedelta
from typing import Any

from django.db.models import Count

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform import features
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.models import TrialRequest
from etqan.scheduling.services import availability
from etqan.scheduling.services import rules
from etqan.scheduling.services import subscriptions as subs

MAX_SUGGESTIONS = 5
ANY = TrialRequest.Gender.ANY
# True (inside), None (no windows: unknown), False (outside).
AVAILABLE_RANK = {True: 0, None: 1, False: 2}


@dataclass(frozen=True)
class Suggestion:
    teacher: Any  # a TeacherProfile with its user (scheduling never imports identity.models)
    free: bool
    available: bool | None
    gender_match: bool
    week_sessions: int


def _matches(teacher, preferred_gender: str) -> bool:
    """Plan D10: everyone matches "no preference"."""
    if preferred_gender == ANY:
        return True
    return bool(teacher.gender) and teacher.gender == preferred_gender


def suggest_teachers(
    *,
    course_id: int,
    occurs_on: date,
    start_time: time,
    minutes: int,
    preferred_gender: str = ANY,
) -> list[Suggestion]:
    course = subs.active_course(course_id)
    listed = catalogue_services.teacher_user_ids_for_course(course.pk)
    teachers = identity_services.active_teachers(listed or None)
    if not teachers:
        return []
    ids = [teacher.pk for teacher in teachers]
    starts_at = dates.to_utc(occurs_on, start_time, rules.settings().timezone)
    ends_at = starts_at + timedelta(minutes=minutes)
    live = Session.objects.filter(teacher_id__in=ids).exclude(
        status=Session.Status.CANCELLED
    )
    busy = set(
        live.alias(ends_at=rules.ENDS_AT)
        .filter(starts_at__lt=ends_at, ends_at__gt=starts_at)
        .values_list("teacher_id", flat=True)
    )
    monday = occurs_on - timedelta(days=occurs_on.weekday())
    week = dict(
        live.filter(occurs_on__range=(monday, monday + timedelta(days=6)))
        .order_by()
        .values("teacher_id")
        .annotate(n=Count("pk"))
        .values_list("teacher_id", "n")
    )
    on = features.enabled(availability.AVAILABILITY)
    inside = availability.available_map(ids, starts_at, minutes) if on else {}
    found = [
        Suggestion(
            teacher=teacher,
            free=teacher.pk not in busy,
            available=inside.get(teacher.pk),
            gender_match=_matches(teacher, preferred_gender),
            week_sessions=week.get(teacher.pk, 0),
        )
        for teacher in teachers
    ]
    found.sort(
        key=lambda s: (
            not s.free,
            AVAILABLE_RANK[s.available] if on else 0,
            not s.gender_match,
            s.week_sessions,
            s.teacher.user.full_name,
            s.teacher.user_id,
        )
    )
    return found[:MAX_SUGGESTIONS]
```

Export `MAX_SUGGESTIONS`, `Suggestion` and `suggest_teachers` from `services/__init__.py`.

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_suggest.py`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/scheduling/services/suggest.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_trials_suggest.py
git -C $W/backend commit -m "feat(scheduling): suggest a teacher for a trial (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 7: Converting a completed trial into a subscription

**Files:**
- Create: `backend/etqan/scheduling/services/conversion.py`
- Modify: `backend/etqan/scheduling/services/subscriptions.py` (`create_subscription(..., trial=None)`)
- Modify: `backend/etqan/scheduling/tests/conftest.py` (the `completed_trial` fixture, shared with Task 10's API tests)
- Test: `backend/etqan/scheduling/tests/test_trials_conversion.py`

**Interfaces:**
- Consumes: Task 4's `rules.current_trial_session` order, `rules.trial_converted`; Task 5's scheduled trial sessions.
- Produces: `conversion.claim_trial(trial: TrialRequest, *, student_id: int) -> TrialRequest` (locks the request, then its current session; refuses); `create_subscription(..., trial: TrialRequest | None = None)` — when given: `claim_trial` first (before anything else is read or written), the subscription as today, then `trial.converted_to` set, all in the one transaction. Codes: 409 `scheduling.trial_not_completed`, 409 `scheduling.trial_converted`; 400 on `student` for another student (plan D3).

- [ ] **Step 1: Add the shared fixture** (`backend/etqan/scheduling/tests/conftest.py`, after `schedule_for`)

```python
@pytest.fixture
def completed_trial(world, clock):
    """Slice B2e: a trial whose session on Tuesday 2 June 10:00 the student
    missed — a no-show still converts (E-7); the clock is then at 11:00."""
    trial = trial_for(world)
    session = schedule_for(trial, world.teacher).session
    clock.set(datetime(2026, 6, 2, 11, 0, tzinfo=UTC))
    services.mark_attendance(session, by=None, student_attendance="absent")
    return trial
```

- [ ] **Step 2: Write the failing tests** (`backend/etqan/scheduling/tests/test_trials_conversion.py`)

```python
"""Slice B2e §4.4, E-7: a completed trial becomes a subscription, once."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import TrialRequest
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import schedule_for
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import trial_for

pytestmark = pytest.mark.django_db


def convert(world, trial, **overrides):
    return subscription_for(world, starts_on=date(2026, 6, 8), trial=trial, **overrides)


def test_a_completed_trial_becomes_a_linked_subscription(world, completed_trial):
    sub = convert(world, completed_trial)
    completed_trial.refresh_from_db()
    assert completed_trial.converted_to == sub
    assert sub.student.user == world.student
    current = services.current_trial_session(completed_trial.pk)
    assert services.can_convert(completed_trial, current) is False


def test_conversion_refusals_in_order(world, completed_trial):
    other = make_student("Sami")
    with pytest.raises(ValidationError) as caught:
        convert(world, completed_trial, student_id=other.id)
    assert caught.value.field == "student"
    convert(world, completed_trial)
    with pytest.raises(ConflictError) as caught:
        convert(world, completed_trial)
    assert caught.value.code == "scheduling.trial_converted"
    assert Subscription.objects.count() == 1


@pytest.mark.parametrize("undo", ["unmark", "cancel", "never"])
def test_only_a_completed_current_session_converts(world, clock, undo):
    admin = make_admin()  # only the office clears an attendance
    trial = trial_for(world)
    session = schedule_for(trial, world.teacher).session
    clock.set(datetime(2026, 6, 2, 11, 0, tzinfo=UTC))
    if undo != "never":
        services.mark_attendance(session, by=admin, student_attendance="present")
    if undo == "unmark":
        services.mark_attendance(session, by=admin, student_attendance="not_set")
    if undo == "cancel":
        services.cancel_session(session, by=admin, reason="Recorded by mistake")
    with pytest.raises(ConflictError) as caught:
        convert(world, trial)
    assert caught.value.code == "scheduling.trial_not_completed"
    assert not Subscription.objects.exists()
    trial.refresh_from_db()
    assert trial.converted_to is None


def test_a_request_never_scheduled_does_not_convert(world):
    with pytest.raises(ConflictError) as caught:
        convert(world, trial_for(world))
    assert caught.value.code == "scheduling.trial_not_completed"


def test_deleting_the_subscription_makes_it_convertible_again(world, completed_trial):
    sub = convert(world, completed_trial)
    services.delete_subscription(sub, before_delete=lambda _pk: None)
    completed_trial.refresh_from_db()
    assert completed_trial.converted_to is None
    assert convert(world, completed_trial).pk != sub.pk


def test_a_converted_trial_is_not_scheduled_again(world, completed_trial):
    convert(world, completed_trial)
    with pytest.raises(ConflictError) as caught:
        schedule_for(completed_trial, world.teacher)
    assert caught.value.code == "scheduling.trial_converted"


def test_lock_order_request_then_session_then_the_insert(world, completed_trial):
    with CaptureQueriesContext(connection) as queries:
        convert(world, completed_trial)
    sql = [q["sql"] for q in queries]
    request = next(
        i for i, s in enumerate(sql) if "FOR UPDATE" in s and "scheduling_trialrequest" in s
    )
    session = next(
        i
        for i, s in enumerate(sql)
        if "FOR UPDATE" in s and s.lstrip().startswith("SELECT") and '"scheduling_session"' in s
    )
    insert = next(
        i for i, s in enumerate(sql) if s.startswith('INSERT INTO "scheduling_subscription"')
    )
    assert request < session < insert


def test_without_a_trial_create_is_unchanged(world):
    sub = subscription_for(world)
    assert not TrialRequest.objects.filter(converted_to=sub).exists()
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_conversion.py`
Expected: FAIL (`TypeError: create_subscription() got an unexpected keyword argument 'trial'`).

- [ ] **Step 4: Write the claim** (`backend/etqan/scheduling/services/conversion.py`)

```python
"""Converting a trial (slice B2e §4.4, E-7): the subscription form, opened
from a completed trial, links the new subscription to the request in the
same transaction. Lock order (§4): the request, then its current session,
then the subscription's insert. Its own module: `subscriptions` may not
import `trials` (which imports `manual`, which imports `subscriptions`)."""

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.models import Session
from etqan.scheduling.models import TrialRequest
from etqan.scheduling.services import rules


def claim_trial(trial: TrialRequest, *, student_id: int) -> TrialRequest:
    """Lock the request and its current session (the live one, else the
    latest, E-3), then refuse, in order: the session is not completed (any
    student attendance converts, E-7); the request was converted; the
    subscription is for another student (400 on `student`, plan D3)."""
    locked = TrialRequest.objects.select_for_update().filter(pk=trial.pk).first()
    if locked is None:
        raise ValidationError("Choose a trial request.", field="trial_id")
    current_id = (
        rules.trial_sessions_of(locked.pk)
        .order_by(*rules.CURRENT_TRIAL_ORDER)
        .values_list("pk", flat=True)
        .first()
    )
    current = (
        Session.objects.select_for_update(of=("self",))
        .select_related("student")
        .filter(pk=current_id)
        .first()
    )
    if current is None or current.status != Session.Status.COMPLETED:
        raise ConflictError(
            "Only a completed trial can become a subscription.",
            code="scheduling.trial_not_completed",
        )
    if locked.converted_to_id is not None:
        raise rules.trial_converted()
    if current.student.user_id != student_id:
        raise ValidationError("Choose the trial's student.", field="student")
    return locked
```

- [ ] **Step 5: Take it in `create_subscription`** (`backend/etqan/scheduling/services/subscriptions.py`)

Add `from etqan.scheduling.services import conversion` and `from etqan.scheduling.models import TrialRequest` (type only). The signature gains a last keyword `trial: TrialRequest | None = None`; the body:

```python
    """Spec §4.2 Create: copy the package, add the slots, generate the horizon.
    Its sessions take ``supervisor_id``'s supervisor (Plan 12b §3.5). Slice
    B2e §4.4: with ``trial``, the request and its current session are locked
    and checked first, and the new subscription is linked to it."""
    claimed = (
        conversion.claim_trial(trial, student_id=student_id) if trial is not None else None
    )
    course = _course(course_id)
    ...  # unchanged down to generation.generate_horizon(subscription)
    if claimed is not None:
        claimed.converted_to = subscription
        claimed.save(update_fields=["converted_to", "updated_at"])
    return subscription
```

- [ ] **Step 6: Run the tests to see them pass, and today's subscription suites**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_conversion.py etqan/scheduling/tests/test_subscriptions.py etqan/scheduling/tests/test_renewal.py`
Expected: PASS. If the session's lock reads `FOR UPDATE OF "scheduling_session"`, the `'"scheduling_session"'` check still finds it.

- [ ] **Step 7: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/scheduling/services/conversion.py etqan/scheduling/services/subscriptions.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_trials_conversion.py
git -C $W/backend commit -m "feat(scheduling): a completed trial becomes a subscription, once (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 8: "Paid to teacher" on trial sessions — the action, the log and its revert

**Files:**
- Modify: `backend/etqan/scheduling/services/activity.py` (`FIELD_FEATURES` values become tuples; `field_on`; `visible_fields`)
- Modify: `backend/etqan/scheduling/services/revert.py` (`revert_refusal` reads `field_on`; the `pays_teacher` inverse's switch by kind)
- Modify: `backend/etqan/scheduling/services/activity_feed.py` (`describe_activity` caches each entry's session; `get_activity_entry` joins it)
- Modify: `backend/etqan/scheduling/api/session_views.py` (`PaysTeacherView.initial`)
- Test: `backend/etqan/scheduling/tests/test_trials_pays_teacher.py`

**Interfaces:**
- Consumes: Task 4's `rules.is_trial_session`, `rules.TRIAL_SESSIONS`; Task 5's trial sessions.
- Produces: `activity.FIELD_FEATURES: dict[str, tuple[str, ...]]` (a field shows while **any** of its switches is on; `pays_teacher` → `("extra_sessions", "trial_sessions")`); `activity.field_on(field: str) -> bool`; the `pays_teacher` revert needs `trial_sessions` for a trial session and `extra_sessions` for any other (E-4, plan D8); `POST sessions/<id>/pays-teacher/` follows `trial_sessions` for a trial session.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_trials_pays_teacher.py`)

```python
"""Slice B2e E-4, §6: a trial session's "paid to teacher?" is switched with
`trial_sessions` (not `extra_sessions`); B2c's log shows the field while
either is on and reverts it by the session's own switch."""

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.platform.permissions import FEATURE_OFF
from etqan.scheduling import services
from etqan.scheduling.services import activity
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import schedule_for
from etqan.scheduling.tests.conftest import TRIAL_DAY
from etqan.scheduling.tests.conftest import trial_for

pytestmark = pytest.mark.django_db


@pytest.fixture
def admin():
    return make_admin()


@pytest.fixture
def trial_session(world):
    return schedule_for(trial_for(world), world.teacher).session


def pays(client, session, *, on):
    return client.post(
        f"/api/v1/sessions/{session.pk}/pays-teacher/",
        {"pays_teacher": on},
        format="json",
    )


def test_a_trial_session_follows_the_trial_switch(admin, trial_session, set_features):
    office = as_user(admin)
    set_features(trial_sessions=True, extra_sessions=False)
    response = pays(office, trial_session, on=False)
    assert (response.status_code, response.json()["pays_teacher"]) == (200, False)
    set_features(trial_sessions=False, extra_sessions=True)
    response = pays(office, trial_session, on=True)
    assert (response.status_code, response.json()) == (404, {"detail": FEATURE_OFF})


def test_any_other_session_keeps_the_extra_switch(admin, subscribe, set_features):
    session = hand_session(subscribe(), occurs_on=TRIAL_DAY)
    office = as_user(admin)
    set_features(trial_sessions=True, extra_sessions=False)
    assert pays(office, session, on=False).status_code == 404
    set_features(extra_sessions=True)
    assert pays(office, session, on=False).status_code == 200


def test_an_unknown_session_answers_as_the_route_always_did(admin, set_features):
    set_features(trial_sessions=True, extra_sessions=False)
    response = as_user(admin).post(
        "/api/v1/sessions/999999/pays-teacher/", {"pays_teacher": False}, format="json"
    )
    assert (response.status_code, response.json()) == (404, {"detail": FEATURE_OFF})


@pytest.mark.parametrize(
    ("switches", "shown"),
    [
        ({"extra_sessions": True, "trial_sessions": False}, True),
        ({"extra_sessions": False, "trial_sessions": True}, True),
        ({"extra_sessions": False, "trial_sessions": False}, False),
    ],
)
def test_the_log_shows_the_field_while_either_switch_is_on(set_features, switches, shown):
    set_features(**switches)
    assert ("pays_teacher" in activity.visible_fields()) is shown
    assert activity.field_on("supervisor_id") is False  # supervision is off
    assert activity.field_on("status") is True  # a field no switch hides


def test_the_revert_needs_the_sessions_own_switch(admin, trial_session, set_features):
    set_features(activity_log=True, trial_sessions=True, extra_sessions=False)
    services.set_pays_teacher(trial_session, pays_teacher=False, by=admin)
    entry = services.activity_of(trial_session).first()
    assert services.revert_refusal(entry, admin) is None
    set_features(trial_sessions=False, extra_sessions=True)
    entry = services.activity_of(trial_session).first()
    assert services.revert_refusal(entry, admin) == "not_revertible"


def test_reading_the_log_costs_no_query_per_entry(admin, trial_session, set_features):
    set_features(activity_log=True, trial_sessions=True)

    def read():
        fresh = services.sessions_queryset().get(pk=trial_session.pk)
        with CaptureQueriesContext(connection) as queries:
            services.session_activity(fresh, admin)
        return len(queries)

    services.set_pays_teacher(trial_session, pays_teacher=False, by=admin)
    one = read()
    services.set_pays_teacher(trial_session, pays_teacher=True, by=admin)
    services.set_pays_teacher(trial_session, pays_teacher=False, by=admin)
    assert read() == one
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_pays_teacher.py`
Expected: FAIL (`AttributeError: module … activity has no attribute 'field_on'`, and the first test's 404).

- [ ] **Step 3: The field map takes several switches** (`backend/etqan/scheduling/services/activity.py`)

```python
# §3.1, C-10: a field shows, and an entry holding it reverts, only while one
# of its own switches is on (slice B2e E-4: `pays_teacher` belongs to extra
# and trial sessions alike). A field not listed always shows.
FIELD_FEATURES: dict[str, tuple[str, ...]] = {
    "supervisor_id": ("supervision",),
    "supervisor_attendance": ("supervision",),
    "teacher_in_at": ("session_times",),
    "teacher_out_at": ("session_times",),
    "student_in_at": ("session_times",),
    "student_out_at": ("session_times",),
    "actual_minutes": ("session_times",),
    "occurs_on": ("postponement",),
    "starts_at": ("postponement",),
    "pays_teacher": ("extra_sessions", "trial_sessions"),
}


def field_on(field: str) -> bool:
    """Whether ``field`` shows: no switch hides it, or one of its own is on.
    No query."""
    codes = FIELD_FEATURES.get(field)
    return codes is None or any(features.enabled(code) for code in codes)
```

and `visible_fields` becomes:

```python
def visible_fields() -> frozenset[str]:
    """The logged fields whose own switch is on (C-10). No query."""
    return frozenset(field for field in LOGGED_FIELDS if field_on(field))
```

- [ ] **Step 4: The revert reads them, and the session's kind** (`backend/etqan/scheduling/services/revert.py`)

Add after `_disposal_when_touched`:

```python
def _pays_switch(entry: SessionActivity) -> set[str]:
    """Slice B2e E-4 (plan D8): a trial session's "paid to teacher" is the
    trial switch's; any other session's is the extra switch's. The entry's
    session is cached by `describe_activity` and joined by
    `get_activity_entry`, so this costs no query there."""
    trial = entry.session.kind == Session.Kind.TRIAL
    return {"trial_sessions" if trial else "extra_sessions"}
```

In `INVERSES`, `Action.PAYS_TEACHER: Inverse(_unpay, _codes(), _pays_switch),`. In `revert_refusal`, replace the `fields = {…}` set and its check with:

```python
    fields_on = all(activity.field_on(field) for field in entry.changes)
    switches_on = all(features.enabled(code) for code in inverse.switches(entry))
    if not (fields_on and switches_on):
        return REFUSED
```

- [ ] **Step 5: No query per entry** (`backend/etqan/scheduling/services/activity_feed.py`)

In `get_activity_entry`: `SessionActivity.objects.select_related("actor", "session")`. In `describe_activity`, before the list it returns:

```python
    for entry in entries:
        # Slice B2e (plan D8): the revert rule reads the session's kind.
        entry.session = session
```

- [ ] **Step 6: The route follows the session's kind** (`backend/etqan/scheduling/api/session_views.py`)

```python
class PaysTeacherView(APIView):
    """B2a §4.7. The route's switch is `extra_sessions` (the route table's
    column); a trial session's is `trial_sessions` (slice B2e E-4, plan D8),
    looked up before the permission check — an unknown id keeps the
    route's own, so nothing is revealed."""

    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"POST": "session.update"}
    feature = "extra_sessions"

    def initial(self, request, *args, **kwargs):
        if services.is_trial_session(kwargs.get("pk")):
            self.feature = services.TRIAL_SESSIONS
        super().initial(request, *args, **kwargs)

    def post(self, request, pk):
        ...  # unchanged
```

- [ ] **Step 7: Run the tests to see them pass, and B2c's suites**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_trials_pays_teacher.py etqan/scheduling/tests/test_activity_revert.py etqan/scheduling/tests/test_activity_feed.py etqan/scheduling/tests/test_api_activity.py etqan/scheduling/tests/test_api_session_classes.py etqan/access/tests/test_routes.py`
Expected: PASS (the route table still reads `extra_sessions` for `pays-teacher/`).

- [ ] **Step 8: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/scheduling/services/activity.py etqan/scheduling/services/revert.py etqan/scheduling/services/activity_feed.py etqan/scheduling/api/session_views.py etqan/scheduling/tests/test_trials_pays_teacher.py
git -C $W/backend commit -m "feat(scheduling): a trial session's paid-to-teacher follows the trial switch (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: The trial routes, the `trial_session` codes and the route table

**Files:**
- Create: `backend/etqan/scheduling/api/trial_views.py`
- Modify: `backend/etqan/scheduling/api/serializers.py` (`TrialInput`, `TrialFilterInput`, `TrialScheduleInput`, `SuggestInput`)
- Modify: `backend/etqan/scheduling/api/payloads.py` (`outside`, `trial_row`, `trial_rows`, `trial_detail`, `scheduled_trial`, `suggestion_row`)
- Modify: `backend/etqan/scheduling/api/urls.py`, `backend/etqan/scheduling/services/__init__.py` (export `trial_sessions_of`)
- Modify: `backend/etqan/access/registry.py` (`trial_session` under `# ── phase B2 ──`)
- Modify: `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`, `FEATURE_WORDS` — insert under `# Slice B2e.`)
- Test: `backend/etqan/scheduling/tests/test_api_trials.py`

**Interfaces:**
- Consumes: Tasks 3–6's services; B2c's `OfficeOr404`; `payloads._student`, `_person`, `_named`, `_user`, `session_row`, `shows_supervision`.
- Produces (spec §6):
  - `GET /api/v1/trials/` → paginated trial rows (filters: `q`, `student`, `course`, `teacher`, `teacher_gender`, `status`, `request_status`, `source`, `heard_from`, `requested_from`, `requested_to`; `?format=csv`); `POST` → `201` trial detail.
  - `GET|PATCH|DELETE /api/v1/trials/<pk>/` → detail / detail / `204`.
  - `POST /api/v1/trials/<pk>/schedule/` `{teacher_id, occurs_on, start_time, minutes?, meeting_url?, pays_teacher?}` → `201 {trial, conflicts: [{session, other}], outside_availability?}`.
  - `GET /api/v1/trials/suggest/?course=&occurs_on=&start_time=&minutes=&gender=` → `[{teacher: {id, full_name, gender}, free, available, gender_match, week_sessions}]`.
  - Trial row: `id, student {id, full_name, timezone}, course {id, name_ar, name_en}, source, students_count, preferred_gender, minutes, desired_at, requested_on, request_status, heard_from, rated, notes, inquiry_id, status, current_session {id, status, occurs_on, starts_at, minutes, teacher {id, full_name}, student_attendance, pays_teacher} | null, sessions_count, converted_to, can_schedule, can_convert, created_by {id, full_name} | null, created_at`; the detail adds `sessions` (every session of the request, latest first, each the `current_session` shape plus `cancel_reason`).
  - `payloads.outside(session) -> dict` (`{}` while availability is off, else `{"outside_availability": bool}`), reused by Task 10.
  - Codes: `trial_session.view_any`, `.view`, `.create`, `.update`, `.delete` in use.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_api_trials.py`)

```python
"""Slice B2e §5–§6: the trial routes, who reaches them, and their answers."""

from datetime import time

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context

from etqan.identity import services as identity_services
from etqan.platform.permissions import FEATURE_OFF
from etqan.scheduling import services
from etqan.scheduling.models import TrialRequest
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import schedule_for
from etqan.scheduling.tests.conftest import trial_for
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
TRIALS = "/api/v1/trials/"


@pytest.fixture
def admin():
    return make_admin()


@pytest.fixture
def office(admin):
    return as_user(admin)


def body(world, **overrides):
    return {
        "student": world.student.id,
        "course": world.course.id,
        "source": "website",
        "minutes": 30,
        "heard_from": "facebook",
        **overrides,
    }


def test_the_office_records_a_request(world, office, admin, trials_on):
    response = office.post(TRIALS, body(world, notes="From the site"), format="json")
    assert response.status_code == 201
    data = response.json()
    assert (data["status"], data["request_status"], data["requested_on"]) == (
        "not_scheduled",
        "under_review",
        "2026-06-01",
    )
    assert data["student"]["id"] == world.student.id
    assert data["created_by"] == {"id": admin.pk, "full_name": "Amina"}
    assert (data["can_schedule"], data["can_convert"], data["sessions"]) == (
        True,
        False,
        [],
    )


def test_bad_fields_are_400_on_their_names(world, office, trials_on):
    for overrides, field in (
        ({"minutes": 181}, "minutes"),
        ({"students_count": 0}, "students_count"),
        ({"source": "fax"}, "source"),
        ({"student": world.teacher.id}, "student"),
    ):
        response = office.post(TRIALS, body(world, **overrides), format="json")
        assert response.status_code == 400
        assert field in response.json()


def test_an_inquiry_makes_one_trial_request(world, office, trials_on):
    """Review Focus: a double click or a second tab."""
    assert office.post(TRIALS, body(world, inquiry_id=4), format="json").status_code == 201
    again = office.post(TRIALS, body(world, inquiry_id=4), format="json")
    assert again.status_code == 400
    assert "inquiry_id" in again.json()
    assert TrialRequest.objects.filter(inquiry_id=4).count() == 1


def test_scheduling_answers_the_trial_and_its_overlaps(world, office, trials_on):
    trial = trial_for(world)
    response = office.post(
        f"{TRIALS}{trial.pk}/schedule/",
        {"teacher_id": world.teacher.id, "occurs_on": "2026-06-02", "start_time": "10:00"},
        format="json",
    )
    assert response.status_code == 201
    data = response.json()
    assert set(data) == {"trial", "conflicts"}  # no availability key while it is off
    current = data["trial"]["current_session"]
    assert (data["trial"]["status"], current["starts_at"], current["minutes"]) == (
        "scheduled",
        "2026-06-02T10:00:00Z",
        30,
    )
    assert current["teacher"] == {"id": world.teacher.id, "full_name": "Bilal"}
    assert data["trial"]["can_schedule"] is False


def test_the_schedule_refusals_reach_the_api(world, office, trials_on):
    trial = trial_for(world, request_status="rejected")
    response = office.post(
        f"{TRIALS}{trial.pk}/schedule/",
        {"teacher_id": world.teacher.id, "occurs_on": "2026-06-02", "start_time": "10:00"},
        format="json",
    )
    assert (response.status_code, response.json()["code"]) == (
        409,
        "scheduling.trial_rejected",
    )
    other = identity_services.create_person(
        "teacher", full_name="Hamza", profile={"gender": "male"}
    )
    open_one = trial_for(world)
    response = office.post(
        f"{TRIALS}{open_one.pk}/schedule/",
        {"teacher_id": other.id, "occurs_on": "2026-06-02", "start_time": "10:00"},
        format="json",
    )
    assert response.status_code == 400
    assert "teacher_id" in response.json()


def test_the_scheduled_answer_warns_outside_availability(
    world, office, trials_on, availability_on
):
    services.set_availability(
        world.teacher.teacher_profile.pk,
        [{"weekday": 0, "start_time": time(9), "end_time": time(12)}],
    )
    trial = trial_for(world)
    data = office.post(
        f"{TRIALS}{trial.pk}/schedule/",
        {"teacher_id": world.teacher.id, "occurs_on": "2026-06-02", "start_time": "10:00"},
        format="json",
    ).json()
    assert data["outside_availability"] is True


def test_read_update_and_delete(world, office, trials_on):
    trial = trial_for(world)
    schedule_for(trial, world.teacher)
    detail = office.get(f"{TRIALS}{trial.pk}/").json()
    assert [s["status"] for s in detail["sessions"]] == ["scheduled"]
    assert detail["sessions_count"] == 1
    patched = office.patch(
        f"{TRIALS}{trial.pk}/", {"rated": True, "notes": "Keen"}, format="json"
    )
    assert (patched.status_code, patched.json()["rated"]) == (200, True)
    refused = office.patch(f"{TRIALS}{trial.pk}/", {"minutes": 45}, format="json")
    assert (refused.status_code, refused.json()["code"]) == (
        409,
        "scheduling.trial_scheduled",
    )
    assert office.delete(f"{TRIALS}{trial.pk}/").status_code == 204
    assert office.get(f"{TRIALS}{trial.pk}/").status_code == 404


def test_the_list_filters_pages_and_exports(world, office, trials_on):
    booked = trial_for(world)
    schedule_for(booked, world.teacher)
    waiting = trial_for(world)
    rows = office.get(TRIALS).json()["results"]
    assert [r["id"] for r in rows] == [waiting.pk, booked.pk]
    assert rows[1]["current_session"]["teacher"]["full_name"] == "Bilal"
    only = office.get(TRIALS, {"status": "not_scheduled"}).json()["results"]
    assert [r["id"] for r in only] == [waiting.pk]
    assert office.get(TRIALS, {"status": "bogus"}).status_code == 400
    csv = office.get(TRIALS, {"format": "csv"})
    assert csv.status_code == 200
    header = csv.content.decode("utf-8-sig").splitlines()[0]
    assert header.startswith("ID,Request date,Student,Course,Source")
    assert "How did you hear about us" in header


def test_the_list_costs_the_same_for_one_or_three(world, office, trials_on):
    def count():
        with CaptureQueriesContext(connection) as queries:
            assert office.get(TRIALS).status_code == 200
        return len(queries)

    schedule_for(trial_for(world), world.teacher)
    one = count()
    for hour in (11, 12):
        schedule_for(trial_for(world), world.teacher, start=time(hour, 0))
    assert count() == one


def test_suggest_answers_the_ranked_teachers(world, office, trials_on):
    response = office.get(
        f"{TRIALS}suggest/",
        {
            "course": world.course.id,
            "occurs_on": "2026-06-02",
            "start_time": "10:00",
            "minutes": 30,
            "gender": "female",
        },
    )
    assert response.status_code == 200
    assert response.json() == [
        {
            "teacher": {"id": world.teacher.id, "full_name": "Bilal", "gender": "male"},
            "free": True,
            "available": None,
            "gender_match": False,
            "week_sessions": 0,
        }
    ]
    assert office.get(f"{TRIALS}suggest/", {"course": world.course.id}).status_code == 400


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_teachers_students_and_parents_get_404(world, trials_on, role):
    if role == "parent":
        user = identity_services.create_person("parent", full_name="Omar")
        identity_services.link_guardian(user, world.student)
    else:
        user = {"teacher": world.teacher, "student": world.student}[role]
    trial = trial_for(world)
    client = as_user(user)
    for response in (
        client.get(TRIALS),
        client.post(TRIALS, body(world), format="json"),
        client.get(f"{TRIALS}{trial.pk}/"),
        client.patch(f"{TRIALS}{trial.pk}/", {"rated": True}, format="json"),
        client.delete(f"{TRIALS}{trial.pk}/"),
        client.post(f"{TRIALS}{trial.pk}/schedule/", {}, format="json"),
        client.get(f"{TRIALS}suggest/"),
    ):
        assert response.status_code == 404
    assert TrialRequest.objects.filter(pk=trial.pk, rated=False).exists()


def test_staff_need_each_code(world, staff_for, trials_on):
    trial = trial_for(world)
    viewer = staff_for("trial_session.view_any")
    assert viewer.get(TRIALS).status_code == 200
    assert viewer.get(f"{TRIALS}{trial.pk}/").status_code == 403
    assert viewer.delete(f"{TRIALS}{trial.pk}/").status_code == 403
    assert staff_for("trial_session.delete").delete(f"{TRIALS}{trial.pk}/").status_code == 204


def test_switched_off_the_routes_404_after_the_permission_check(world, office, staff_for):
    trial = trial_for(world)
    for response in (office.get(TRIALS), office.get(f"{TRIALS}{trial.pk}/")):
        assert (response.status_code, response.json()) == (404, {"detail": FEATURE_OFF})
    assert staff_for("session.view_any").get(TRIALS).status_code == 403


def test_another_academys_trial_is_out_of_reach(world, office, tenants, trials_on):
    ceiling = TrialRequest.objects.aggregate(m=Max("pk"))["m"] or 0
    with tenant_context(tenants.other):
        theirs = until_pk_exceeds(
            TrialRequest, ceiling, lambda: trial_for(build_world())
        )
    assert office.get(f"{TRIALS}{theirs.pk}/").status_code == 404
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_trials.py`
Expected: FAIL (`404` on every `/api/v1/trials/` route: no URL yet).

- [ ] **Step 3: The request bodies** (`backend/etqan/scheduling/api/serializers.py`; add `from etqan.scheduling.models import TrialRequest` and `from etqan.scheduling.services import TRIAL_STATUSES`)

```python
# Slice B2e (spec §6).
class TrialInput(serializers.Serializer):
    student = _id()
    course = _id()
    source = serializers.ChoiceField(choices=TrialRequest.Source.values)
    students_count = serializers.IntegerField(min_value=1, max_value=20, required=False)
    preferred_gender = serializers.ChoiceField(
        choices=TrialRequest.Gender.values, required=False
    )
    minutes = serializers.IntegerField(min_value=15, max_value=180)
    desired_at = serializers.DateTimeField(required=False, allow_null=True)
    requested_on = serializers.DateField(required=False)
    request_status = serializers.ChoiceField(
        choices=TrialRequest.RequestStatus.values, required=False
    )
    heard_from = serializers.ChoiceField(choices=TrialRequest.HeardFrom.values)
    rated = serializers.BooleanField(required=False)
    notes = serializers.CharField(required=False, allow_blank=True)
    inquiry_id = _id(required=False, allow_null=True)


class TrialFilterInput(serializers.Serializer):
    """§4.6's filters, plan D5's `q`. A bad value is a field error."""

    q = serializers.CharField(required=False, allow_blank=True)
    student = _id(required=False)
    course = _id(required=False)
    teacher = _id(required=False)
    teacher_gender = serializers.ChoiceField(choices=("male", "female"), required=False)
    status = serializers.ChoiceField(choices=TRIAL_STATUSES, required=False)
    request_status = serializers.ChoiceField(
        choices=TrialRequest.RequestStatus.values, required=False
    )
    source = serializers.ChoiceField(choices=TrialRequest.Source.values, required=False)
    heard_from = serializers.ChoiceField(
        choices=TrialRequest.HeardFrom.values, required=False
    )
    requested_from = serializers.DateField(required=False)
    requested_to = serializers.DateField(required=False)


class TrialScheduleInput(serializers.Serializer):
    teacher_id = _id()
    occurs_on = serializers.DateField()
    start_time = serializers.TimeField()
    minutes = serializers.IntegerField(min_value=15, max_value=240, required=False)
    meeting_url = serializers.URLField(required=False, allow_blank=True, max_length=200)
    pays_teacher = serializers.BooleanField(required=False)


class SuggestInput(serializers.Serializer):
    course = _id()
    occurs_on = serializers.DateField()
    start_time = serializers.TimeField()
    minutes = serializers.IntegerField(min_value=15, max_value=240)
    # DRF refuses `required=False` beside a default: the default implies it.
    gender = serializers.ChoiceField(choices=TrialRequest.Gender.values, default="any")
```

- [ ] **Step 4: The payloads** (`backend/etqan/scheduling/api/payloads.py`, at the end)

```python
# ── Slice B2e (spec §6) ──────────────────────────────────────────────────────


def outside(session) -> dict:
    """E-11, plan D6: the session-level warning, only while availability is
    on (FT-4: off, every answer is today's)."""
    flag = services.outside_availability(session)
    return {} if flag is None else {"outside_availability": flag}


def _trial_session(session) -> dict | None:
    if session is None:
        return None
    return {
        "id": session.pk,
        "status": session.status,
        "occurs_on": session.occurs_on,
        "starts_at": session.starts_at,
        "minutes": session.minutes,
        "teacher": _person(session.teacher),
        "student_attendance": session.student_attendance,
        "pays_teacher": session.pays_teacher,
    }


def trial_row(trial, current) -> dict:
    """A request as the office reads it (§6). ``trial`` comes from
    `services.trials_queryset()`; ``current`` is its current session or
    None. `can_schedule` / `can_convert` are the server's rule (plan D2)."""
    return {
        "id": trial.pk,
        "student": _student(trial.student),
        "course": _named(trial.course),
        "source": trial.source,
        "students_count": trial.students_count,
        "preferred_gender": trial.preferred_gender,
        "minutes": trial.minutes,
        "desired_at": trial.desired_at,
        "requested_on": trial.requested_on,
        "request_status": trial.request_status,
        "heard_from": trial.heard_from,
        "rated": trial.rated,
        "notes": trial.notes,
        "inquiry_id": trial.inquiry_id,
        "status": services.trial_status(current),
        "current_session": _trial_session(current),
        "sessions_count": trial.sessions_count,
        "converted_to": trial.converted_to_id,
        "can_schedule": services.can_schedule(trial, current),
        "can_convert": services.can_convert(trial, current),
        "created_by": _user(trial.created_by),
        "created_at": trial.created_at,
    }


def trial_rows(trials) -> list[dict]:
    """A page of requests: their current sessions in one query."""
    trials = list(trials)
    current = services.current_sessions(
        t.current_session_id for t in trials if t.current_session_id
    )
    return [trial_row(t, current.get(t.current_session_id)) for t in trials]


def trial_detail(pk) -> dict:
    trial = services.trials_queryset().get(pk=pk)
    sessions = list(
        services.trial_sessions_of(trial.pk)
        .select_related("teacher__user")
        .order_by("-starts_at", "-id")
    )
    current = next((s for s in sessions if s.pk == trial.current_session_id), None)
    return {
        **trial_row(trial, current),
        "sessions": [
            {**_trial_session(s), "cancel_reason": s.cancel_reason} for s in sessions
        ],
    }


def scheduled_trial(result: services.Scheduled, *, viewer) -> dict:
    """§4.2 step 4, plan D11."""
    shown = shows_supervision(viewer)
    return {
        "trial": trial_detail(result.trial.pk),
        "conflicts": [
            {
                "session": session_row(session, viewer=viewer, supervision=shown),
                "other": session_row(other, viewer=viewer, supervision=shown),
            }
            for session, other in result.conflicts
        ],
        **outside(result.session),
    }


def suggestion_row(found: services.Suggestion) -> dict:
    teacher = found.teacher
    return {
        "teacher": {
            "id": teacher.user_id,
            "full_name": teacher.user.full_name,
            "gender": teacher.gender,
        },
        "free": found.free,
        "available": found.available,
        "gender_match": found.gender_match,
        "week_sessions": found.week_sessions,
    }
```

Export `trial_sessions_of` from `services/__init__.py` (from `rules`).

- [ ] **Step 5: The views** (`backend/etqan/scheduling/api/trial_views.py`)

```python
"""Slice B2e §5–§6: trial requests, scheduling them, and the suggestion. The
office only: everyone else gets 404, before the code check (§5); a
switched-off `trial_sessions` answers 404 after it."""

from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.scheduling import services
from etqan.scheduling.api import payloads
from etqan.scheduling.api.activity_views import OfficeOr404
from etqan.scheduling.api.serializers import SuggestInput
from etqan.scheduling.api.serializers import TrialFilterInput
from etqan.scheduling.api.serializers import TrialInput
from etqan.scheduling.api.serializers import TrialScheduleInput
from etqan.scheduling.models import TrialRequest

OFFICE_ONLY = (OfficeOr404, HasCode, FeatureOn)
FEATURE = "trial_sessions"
# Body keys (spec §6) → service keyword arguments.
IDS = {"student": "student_id", "course": "course_id"}
# TutorHamster's "Export to Excel": every column.
CSV_COLUMNS = (
    ("id", "ID"),
    ("requested_on", "Request date"),
    ("student", "Student"),
    ("course", "Course"),
    ("source", "Source"),
    ("students_count", "Number of students"),
    ("preferred_gender", "Preferred teacher gender"),
    ("minutes", "Minutes"),
    ("desired_at", "Desired start (UTC)"),
    ("request_status", "Request status"),
    ("status", "Trial status"),
    ("current_session.teacher", "Teacher"),
    ("current_session.starts_at", "Session starts at (UTC)"),
    ("current_session.pays_teacher", "Paid to teacher"),
    ("heard_from", "How did you hear about us"),
    ("rated", "Student rated the trial"),
    ("converted_to", "Subscription"),
    ("notes", "Notes"),
)


def _ids(data: dict) -> dict:
    return {IDS.get(key, key): value for key, value in data.items()}


def trial_or_404(pk) -> TrialRequest:
    return get_object_or_404(TrialRequest, pk=pk)


class TrialListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = OFFICE_ONLY
    permission_codes = {"GET": "trial_session.view_any", "POST": "trial_session.create"}
    feature = FEATURE
    csv_filename = "trials"
    csv_columns = CSV_COLUMNS

    def get(self, request):
        query = TrialFilterInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        trials = services.filter_trials(
            services.trials_queryset(), **query.validated_data
        )
        if self.wants_csv():
            return self.csv_response(payloads.trial_rows(trials))
        page = self.paginate_queryset(trials)
        return self.get_paginated_response(payloads.trial_rows(page))

    def post(self, request):
        body = TrialInput(data=request.data)
        body.is_valid(raise_exception=True)
        trial = services.create_trial(by=request.user, **_ids(body.validated_data))
        return Response(payloads.trial_detail(trial.pk), status=status.HTTP_201_CREATED)


class TrialDetailView(APIView):
    permission_classes = OFFICE_ONLY
    permission_codes = {
        "GET": "trial_session.view",
        "PATCH": "trial_session.update",
        "DELETE": "trial_session.delete",
    }
    feature = FEATURE

    def get(self, request, pk):
        return Response(payloads.trial_detail(trial_or_404(pk).pk))

    def patch(self, request, pk):
        trial = trial_or_404(pk)
        body = TrialInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_trial(trial, **_ids(body.validated_data))
        return Response(payloads.trial_detail(pk))

    def delete(self, request, pk):
        services.delete_trial(trial_or_404(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class TrialScheduleView(APIView):
    permission_classes = OFFICE_ONLY
    permission_codes = {"POST": "trial_session.update"}
    feature = FEATURE

    def post(self, request, pk):
        trial = trial_or_404(pk)
        body = TrialScheduleInput(data=request.data)
        body.is_valid(raise_exception=True)
        result = services.schedule_trial(trial, by=request.user, **body.validated_data)
        return Response(
            payloads.scheduled_trial(result, viewer=request.user),
            status=status.HTTP_201_CREATED,
        )


class TrialSuggestView(APIView):
    permission_classes = OFFICE_ONLY
    permission_codes = {"GET": ("trial_session.create", "trial_session.update")}
    feature = FEATURE

    def get(self, request):
        query = SuggestInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        data = query.validated_data
        found = services.suggest_teachers(
            course_id=data["course"],
            occurs_on=data["occurs_on"],
            start_time=data["start_time"],
            minutes=data["minutes"],
            preferred_gender=data["gender"],
        )
        return Response([payloads.suggestion_row(s) for s in found])
```

In `backend/etqan/scheduling/api/urls.py` add `from etqan.scheduling.api import trial_views` and, after B2d's session archive paths:

```python
    # Slice B2e (spec §6).
    path("trials/", trial_views.TrialListView.as_view(), name="trial-list"),
    path(
        "trials/suggest/", trial_views.TrialSuggestView.as_view(), name="trial-suggest"
    ),
    path(
        "trials/<int:pk>/", trial_views.TrialDetailView.as_view(), name="trial-detail"
    ),
    path(
        "trials/<int:pk>/schedule/",
        trial_views.TrialScheduleView.as_view(),
        name="trial-schedule",
    ),
```

- [ ] **Step 6: The codes and the route table**

`backend/etqan/access/registry.py`, under `# ── phase B2 ──`:

```python
    # Slice B2e (§5): TutorHamster's `trial::session`.
    Resource("trial_session", "Trial sessions", "الحصص التجريبية", (*EDIT, "delete")),
```

`backend/etqan/access/tests/test_routes.py` — **insert** (never paste the lists whole). In `ROUTES`, after B2d's four lines:

```python
    # Slice B2e.
    ("GET", "/api/v1/trials/", "trial_session.view_any"),
    ("POST", "/api/v1/trials/", "trial_session.create"),
    ("GET", "/api/v1/trials/suggest/", ("trial_session.create", "trial_session.update")),
    ("GET", f"/api/v1/trials/{N}/", "trial_session.view"),
    ("PATCH", f"/api/v1/trials/{N}/", "trial_session.update"),
    ("DELETE", f"/api/v1/trials/{N}/", "trial_session.delete"),
    ("POST", f"/api/v1/trials/{N}/schedule/", "trial_session.update"),
```

In `FEATURES`, after B2d's four lines:

```python
    # Slice B2e.
    **dict.fromkeys(
        (
            ("GET", "/api/v1/trials/"),
            ("POST", "/api/v1/trials/"),
            ("GET", "/api/v1/trials/suggest/"),
            ("GET", f"/api/v1/trials/{N}/"),
            ("PATCH", f"/api/v1/trials/{N}/"),
            ("DELETE", f"/api/v1/trials/{N}/"),
            ("POST", f"/api/v1/trials/{N}/schedule/"),
        ),
        "trial_sessions",
    ),
```

In `FEATURE_WORDS`, after B2d's two lines:

```python
    # Slice B2e.
    "/trials/": "trial_sessions",
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_trials.py etqan/access/tests/`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/scheduling/api/trial_views.py etqan/scheduling/api/serializers.py etqan/scheduling/api/payloads.py etqan/scheduling/api/urls.py etqan/scheduling/services/__init__.py etqan/access/registry.py etqan/access/tests/test_routes.py etqan/scheduling/tests/test_api_trials.py
git -C $W/backend commit -m "feat(scheduling): trial routes, office only, with the suggestion (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 10: The availability routes, the warnings in every answer, conversion through the API, and `trial_id` on session rows

**Files:**
- Create: `backend/etqan/scheduling/api/availability_views.py`
- Modify: `backend/etqan/scheduling/api/serializers.py` (`WindowInput`, `AvailabilityInput`; `SubscriptionCreateInput.trial_id`)
- Modify: `backend/etqan/scheduling/api/payloads.py` (`availability`; `slot_row(slot, outside=None)`; `subscription_detail`; `added_session`; `postponed_session`; `session_row`'s `trial_id`)
- Modify: `backend/etqan/scheduling/api/views.py` (`SlotListView`; `SubscriptionListView.post`'s `trial_id`)
- Modify: `backend/etqan/scheduling/api/urls.py`
- Modify: `backend/etqan/access/registry.py` (`teacher_schedule` under `# ── phase B2 ──`), `backend/etqan/access/tests/test_routes.py` (insert under `# Slice B2e.`; `SELF_SERVICE`)
- Test: `backend/etqan/scheduling/tests/test_api_availability.py`, `backend/etqan/scheduling/tests/test_api_trials_links.py`

**Interfaces:**
- Consumes: Task 3's services; Task 7's `create_subscription(trial=)`; Task 9's `payloads.outside`.
- Produces:
  - `GET|PUT /api/v1/schedule/availability/<user_id>/` (office `teacher_schedule.view` / `.update`; the teacher for themselves; students and parents 404) and `GET|PUT /api/v1/schedule/availability/` (the signed-in teacher's own) → `{teacher: {id, full_name}, windows: [{weekday, start_time "HH:MM", end_time "HH:MM"}]}`; PUT body `{windows: [{weekday, start_time, end_time}]}`. Feature `teacher_availability`.
  - Slot rows (subscription detail, `subscriptions/<id>/slots/`) carry `outside_availability` while availability is on; B2a's three add-session answers and the office's B2b postponement answer carry it too (plan D6).
  - `POST /api/v1/subscriptions/` takes `trial_id`: 400 on it while `trial_sessions` is off or when unknown; 403 without `trial_session.update` (admins pass).
  - Session rows carry `trial_id` for the office (a staff-only field).
  - Codes `teacher_schedule.view`, `.update` in use.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_api_availability.py`)

```python
"""Slice B2e §5–§6, E-10, E-11: availability by the office and by each
teacher for themselves; the warning on slot rows and in the answers. 8 June
2026 is a Monday."""

from datetime import time

import pytest

from etqan.identity import services as identity_services
from etqan.platform.permissions import FEATURE_OFF
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
MINE = "/api/v1/schedule/availability/"
WINDOWS = {"windows": [{"weekday": 0, "start_time": "17:00", "end_time": "19:00"}]}


def of(user):
    return f"{MINE}{user.pk}/"


@pytest.fixture
def office():
    return as_user(make_admin())


def test_the_office_reads_and_replaces_a_teachers_windows(world, office, availability_on):
    assert office.get(of(world.teacher)).json() == {
        "teacher": {"id": world.teacher.pk, "full_name": "Bilal"},
        "windows": [],
    }
    saved = office.put(of(world.teacher), WINDOWS, format="json")
    assert saved.status_code == 200
    assert saved.json()["windows"] == [
        {"weekday": 0, "start_time": "17:00", "end_time": "19:00"}
    ]


def test_a_bad_window_is_400_on_its_index(world, office, availability_on):
    response = office.put(
        of(world.teacher),
        {
            "windows": [
                {"weekday": 0, "start_time": "09:00", "end_time": "11:00"},
                {"weekday": 0, "start_time": "10:00", "end_time": "12:00"},
            ]
        },
        format="json",
    )
    assert response.status_code == 400
    assert "windows.1" in response.json()


def test_each_teacher_edits_only_their_own(world, availability_on):
    mine = as_user(world.teacher)
    assert mine.put(MINE, WINDOWS, format="json").status_code == 200
    assert mine.get(MINE).json()["windows"][0]["weekday"] == 0
    assert mine.get(of(world.teacher)).status_code == 200
    other = make_teacher("Hamza")
    assert mine.get(of(other)).status_code == 404
    assert mine.put(of(other), WINDOWS, format="json").status_code == 404


@pytest.mark.parametrize("role", ["student", "parent"])
def test_students_and_parents_get_404(world, availability_on, role):
    user = world.student
    if role == "parent":
        user = identity_services.create_person("parent", full_name="Omar")
        identity_services.link_guardian(user, world.student)
    client = as_user(user)
    assert client.get(of(world.teacher)).status_code == 404
    assert client.put(of(world.teacher), WINDOWS, format="json").status_code == 404
    assert client.get(MINE).status_code == 403  # the teacher's own page


def test_staff_need_the_code_of_each_way(world, staff_for, availability_on):
    reader = staff_for("teacher_schedule.view")
    assert reader.get(of(world.teacher)).status_code == 200
    assert reader.put(of(world.teacher), WINDOWS, format="json").status_code == 403
    writer = staff_for("teacher_schedule.update")
    assert writer.put(of(world.teacher), WINDOWS, format="json").status_code == 200
    assert writer.get(MINE).status_code == 403  # "My availability" is a teacher's


def test_a_user_who_is_no_teacher_is_404(world, office, availability_on):
    assert office.get(of(world.student)).status_code == 404


def test_switched_off_the_routes_404_after_the_permission_check(world, office, staff_for):
    response = office.get(of(world.teacher))
    assert (response.status_code, response.json()) == (404, {"detail": FEATURE_OFF})
    assert as_user(world.teacher).get(MINE).status_code == 404
    assert staff_for("session.view_any").get(of(world.teacher)).status_code == 403


def test_slot_rows_warn_only_while_on_and_only_with_windows(
    world, office, subscribe, set_features
):
    """Review Focus: no windows is no warning; off is no key at all."""
    sub = subscribe(slots=two_slots(time(18, 0)))  # Monday and Wednesday
    detail = office.get(f"/api/v1/subscriptions/{sub.pk}/").json()
    assert all("outside_availability" not in slot for slot in detail["slots"])
    set_features(teacher_availability=True)
    detail = office.get(f"/api/v1/subscriptions/{sub.pk}/").json()
    assert [slot["outside_availability"] for slot in detail["slots"]] == [False, False]
    services.set_availability(
        world.teacher.teacher_profile.pk,
        [{"weekday": 0, "start_time": time(17), "end_time": time(19)}],
    )
    slots = office.get(f"/api/v1/subscriptions/{sub.pk}/slots/").json()
    assert {s["weekday"]: s["outside_availability"] for s in slots} == {
        0: False,
        2: True,
    }


def test_the_add_and_postpone_answers_warn_too(world, office, subscribe, set_features):
    set_features(
        teacher_availability=True, manual_sessions=True, postponement=True
    )
    services.set_availability(
        world.teacher.teacher_profile.pk,
        [{"weekday": 0, "start_time": time(17), "end_time": time(19)}],
    )
    sub = subscribe()
    added = office.post(
        "/api/v1/sessions/regular/",
        {"subscription": sub.pk, "occurs_on": "2026-06-02", "start_time": "10:00"},
        format="json",
    ).json()
    assert added["outside_availability"] is True
    session = Session.objects.get(pk=added["session"]["id"])
    moved = office.post(
        f"/api/v1/sessions/{session.pk}/postpone/",
        {"occurs_on": "2026-06-08", "start_time": "17:30"},
        format="json",
    ).json()
    assert moved["outside_availability"] is False
    family = as_user(world.student).post(
        f"/api/v1/sessions/{session.pk}/postpone/",
        {"occurs_on": "2026-06-09", "start_time": "10:00"},
        format="json",
    )
    assert family.status_code == 200
    assert "outside_availability" not in family.json()
```

`backend/etqan/scheduling/tests/test_api_trials_links.py`:

```python
"""Slice B2e §4.4, §5, E-12: conversion through the subscription route; a
trial session in everyone's lists; `trial_id` is the office's."""

import pytest

from etqan.scheduling.models import TrialRequest
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import schedule_for
from etqan.scheduling.tests.conftest import trial_for

pytestmark = pytest.mark.django_db
SUBS = "/api/v1/subscriptions/"


def body(world, trial):
    return {
        "student": world.student.id,
        "course": world.course.id,
        "teacher": world.teacher.id,
        "package": world.package.id,
        "starts_on": "2026-06-08",
        "trial_id": trial.pk,
    }


def test_the_office_converts_a_completed_trial(world, completed_trial, trials_on):
    response = as_user(make_admin()).post(SUBS, body(world, completed_trial), format="json")
    assert response.status_code == 201
    completed_trial.refresh_from_db()
    assert completed_trial.converted_to_id == response.json()["id"]


def test_trial_id_is_400_while_trials_are_off(world, completed_trial):
    response = as_user(make_admin()).post(SUBS, body(world, completed_trial), format="json")
    assert response.status_code == 400
    assert "trial_id" in response.json()
    assert TrialRequest.objects.get(pk=completed_trial.pk).converted_to_id is None


def test_staff_also_need_trial_session_update(world, completed_trial, staff_for, trials_on):
    creator = staff_for("subscription.create")
    assert creator.post(SUBS, body(world, completed_trial), format="json").status_code == 403
    both = staff_for("subscription.create", "trial_session.update")
    assert both.post(SUBS, body(world, completed_trial), format="json").status_code == 201


def test_an_unknown_trial_is_400_and_a_refusal_is_409(world, trials_on):
    office = as_user(make_admin())
    unknown = {**body(world, trial_for(world)), "trial_id": 999999}
    assert office.post(SUBS, unknown, format="json").status_code == 400
    open_one = trial_for(world)
    refused = office.post(SUBS, body(world, open_one), format="json")
    assert (refused.status_code, refused.json()["code"]) == (
        409,
        "scheduling.trial_not_completed",
    )


def test_a_trial_session_is_in_the_teachers_and_the_students_lists(world):
    session = schedule_for(trial_for(world), world.teacher).session
    for user in (world.teacher, world.student):
        rows = as_user(user).get("/api/v1/sessions/").json()["results"]
        (row,) = [r for r in rows if r["id"] == session.pk]
        assert row["kind"] == "trial"
        assert "trial_id" not in row
    office = as_user(make_admin()).get(f"/api/v1/sessions/{session.pk}/").json()
    assert office["trial_id"] == session.trial_id


def test_a_trial_session_keeps_showing_while_trials_are_off(world):
    """FT-4: switched off, trial sessions already made stay in the lists."""
    session = schedule_for(trial_for(world), world.teacher).session
    rows = as_user(make_admin()).get("/api/v1/sessions/", {"kind": "trial"}).json()
    assert [r["id"] for r in rows["results"]] == [session.pk]
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_availability.py etqan/scheduling/tests/test_api_trials_links.py`
Expected: FAIL (`404` on `/api/v1/schedule/availability/…`; `KeyError: 'outside_availability'`; `trial_id` ignored → 201).

- [ ] **Step 3: The bodies** (`backend/etqan/scheduling/api/serializers.py`)

In `SubscriptionCreateInput`, after `supervisor_id`:

```python
    # Slice B2e §4.4: the trial this subscription converts (the view checks
    # the switch and the code).
    trial_id = _id(required=False)
```

and after `SuggestInput`:

```python
class WindowInput(serializers.Serializer):
    weekday = serializers.IntegerField(min_value=0, max_value=6)
    start_time = serializers.TimeField()
    end_time = serializers.TimeField()


class AvailabilityInput(serializers.Serializer):
    """§4.5: every window of the teacher, replaced together."""

    windows = WindowInput(many=True, allow_empty=True)
```

- [ ] **Step 4: The views** (`backend/etqan/scheduling/api/availability_views.py`)

```python
"""Slice B2e §5–§6, E-10: a teacher's availability, edited by the office
(`teacher_schedule.view` / `.update`) and by each teacher for themselves.
Students and parents get 404, before the code check; a switched-off
`teacher_availability` answers 404 after it."""

from django.http import Http404
from rest_framework.exceptions import NotFound
from rest_framework.permissions import BasePermission
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.identity import services as identity_services
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.platform.permissions import IsTeacher
from etqan.platform.permissions import role_of
from etqan.scheduling import services
from etqan.scheduling.api import payloads
from etqan.scheduling.api.serializers import AvailabilityInput

FEATURE = "teacher_availability"


class FamilyOr404(BasePermission):
    """§5: a student or parent never learns these routes exist (404, as
    B2c's `OfficeOr404`); an anonymous caller gets the usual refusal. List it
    before `HasCode`."""

    def has_permission(self, request, view):
        role = role_of(request.user)
        if role is None:
            return False
        if role in ("student", "parent"):
            raise NotFound
        return True


def _teacher(user_id: int):
    profile = identity_services.get_teacher_profile(user_id)
    if profile is None or profile.user.role != "teacher":
        raise Http404
    return profile


class _Availability(APIView):
    def answer(self, profile):
        return Response(payloads.availability(profile, services.windows_of(profile.pk)))

    def replace(self, request, profile):
        body = AvailabilityInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.set_availability(profile.pk, body.validated_data["windows"])
        return self.answer(profile)


class TeacherAvailabilityView(_Availability):
    """A teacher's windows by their User id: the office by code, a teacher
    only their own (anyone else's is 404)."""

    permission_classes = [FamilyOr404, HasCode | IsTeacher, FeatureOn]
    permission_codes = {"GET": "teacher_schedule.view", "PUT": "teacher_schedule.update"}
    feature = FEATURE

    def profile(self, request, user_id):
        if role_of(request.user) == "teacher" and request.user.pk != user_id:
            raise Http404
        return _teacher(user_id)

    def get(self, request, user_id):
        return self.answer(self.profile(request, user_id))

    def put(self, request, user_id):
        return self.replace(request, self.profile(request, user_id))


class MyAvailabilityView(_Availability):
    """The signed-in teacher's own windows ("My availability")."""

    permission_classes = [IsTeacher, FeatureOn]
    feature = FEATURE

    def get(self, request):
        return self.answer(_teacher(request.user.pk))

    def put(self, request):
        return self.replace(request, _teacher(request.user.pk))
```

In `backend/etqan/scheduling/api/urls.py` (`from etqan.scheduling.api import availability_views`), after the trial paths:

```python
    path(
        "schedule/availability/",
        availability_views.MyAvailabilityView.as_view(),
        name="my-availability",
    ),
    path(
        "schedule/availability/<int:user_id>/",
        availability_views.TeacherAvailabilityView.as_view(),
        name="teacher-availability",
    ),
```

- [ ] **Step 5: The payloads** (`backend/etqan/scheduling/api/payloads.py`)

`slot_row` gains the flag:

```python
def slot_row(slot, outside: bool | None = None) -> dict:
    row = {
        "id": slot.pk,
        "weekday": slot.weekday,
        "start_time": _hhmm(slot.start_time),
        "minutes": slot.minutes,
        "meeting_url": slot.meeting_url,
        "is_active": slot.is_active,
        "has_sessions": getattr(slot, "has_sessions", True),
    }
    if outside is not None:
        # Slice B2e E-11, plan D6: while availability is on.
        row["outside_availability"] = outside
    return row


def slot_rows(sub, slots) -> list[dict]:
    """A subscription's slots with E-11's flag (one query while on)."""
    slots = list(slots)
    flags = services.slots_outside(sub, slots)
    return [slot_row(s, None if flags is None else flags[s.pk]) for s in slots]
```

In `subscription_detail`, `"slots": slot_rows(sub, services.slots_of(sub)),`. In `added_session`, add `**outside(added.session),` after `"conflicts"`; in `postponed_session`, add `**(outside(result.session) if is_office(viewer) else {}),` after `"conflicts"`. In `session_row`, add `"trial_id": session.trial_id,` after `"compensation_id"`, and `"trial_id",` to `STAFF_ONLY_SESSION_FIELDS` under a `# Slice B2e (spec §6).` comment. At the end of the B2e section:

```python
def availability(profile, windows) -> dict:
    """§6: a teacher's windows, as the editor reads them."""
    return {
        "teacher": _person(profile),
        "windows": [
            {
                "weekday": w.weekday,
                "start_time": _hhmm(w.start_time),
                "end_time": _hhmm(w.end_time),
            }
            for w in windows
        ],
    }
```

(`outside` is defined in Task 9's section, below `added_session`; Python resolves it at call time, so the order in the file does not matter.)

- [ ] **Step 6: The subscription views** (`backend/etqan/scheduling/api/views.py`)

`SlotListView.get` returns `Response(payloads.slot_rows(sub, services.slots_of(sub)))`. Add the imports `from rest_framework.exceptions import ValidationError as BadRequest`, `from etqan.platform.permissions import codes_of`, `from etqan.platform.permissions import role_of`, `from etqan.scheduling.models import TrialRequest`, and:

```python
def _trial_to_convert(request, trial_id: int | None) -> TrialRequest | None:
    """Slice B2e §4.4: ``trial_id`` exists only while trial sessions are on
    (400 on it otherwise), and needs `trial_session.update` besides the
    route's own `subscription.create` (§5)."""
    if trial_id is None:
        return None
    if not features.enabled(services.TRIAL_SESSIONS):
        raise BadRequest({"trial_id": ["Trial sessions are not enabled."]})
    user = request.user
    if role_of(user) != "admin" and "trial_session.update" not in codes_of(user):
        raise PermissionDenied("Converting a trial needs trial_session.update.")
    trial = TrialRequest.objects.filter(pk=trial_id).first()
    if trial is None:
        raise BadRequest({"trial_id": ["Choose a trial request."]})
    return trial
```

In `SubscriptionListView.post`:

```python
        data = _ids(body.validated_data)
        data.update(_supervisor_field(data))
        trial = _trial_to_convert(request, data.pop("trial_id", None))
        # P6-1: billing after scheduling, in one transaction: if the invoice
        # fails, the subscription and its sessions are rolled back too.
        with transaction.atomic():
            sub = services.create_subscription(**data, trial=trial)
            billing_services.invoice_subscription(sub.pk, by=request.user)
```

- [ ] **Step 7: The codes and the route table**

`backend/etqan/access/registry.py`, after Task 9's `trial_session` line:

```python
    # Slice B2e (§5): TutorHamster's `teacher::schedule`.
    Resource(
        "teacher_schedule", "Teacher schedules", "مواعيد المعلمين", ("view", "update")
    ),
```

`backend/etqan/access/tests/test_routes.py` — **insert**: in `ROUTES` under Task 9's `# Slice B2e.` lines:

```python
    ("GET", f"/api/v1/schedule/availability/{N}/", "teacher_schedule.view"),
    ("PUT", f"/api/v1/schedule/availability/{N}/", "teacher_schedule.update"),
```

in `FEATURES` under Task 9's B2e block:

```python
    ("GET", f"/api/v1/schedule/availability/{N}/"): "teacher_availability",
    ("PUT", f"/api/v1/schedule/availability/{N}/"): "teacher_availability",
```

in `FEATURE_WORDS` under `"/trials/"`: `"/availability/": "teacher_availability",`; and in `SELF_SERVICE`:

```python
    # Slice B2e: a teacher's own availability (IsTeacher).
    "etqan.scheduling.api.availability_views.MyAvailabilityView": (
        "the caller's own availability (teachers)"
    ),
```

- [ ] **Step 8: Run the tests to see them pass, and the suites whose answers grew**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_availability.py etqan/scheduling/tests/test_api_trials_links.py etqan/scheduling/tests/test_api_subscriptions.py etqan/scheduling/tests/test_api_session_classes.py etqan/scheduling/tests/test_api_times_postponement.py etqan/scheduling/tests/test_api_sessions.py etqan/access/tests/`
Expected: PASS (every existing answer is unchanged with availability off).

- [ ] **Step 9: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/scheduling/api/availability_views.py etqan/scheduling/api/serializers.py etqan/scheduling/api/payloads.py etqan/scheduling/api/views.py etqan/scheduling/api/urls.py etqan/access/registry.py etqan/access/tests/test_routes.py etqan/scheduling/tests/test_api_availability.py etqan/scheduling/tests/test_api_trials_links.py
git -C $W/backend commit -m "feat(scheduling): availability routes, outside-availability warnings, conversion through the API (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 11: Demo seeds — windows for two teachers and three trials

**Files:**
- Modify: `backend/etqan/tenants/seeds/b2.py` (`AVAILABILITY`, `TRIALS`, `seed_availability`, `seed_trials`)
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (two calls in the B2 block, after `b2.seed_archives`)
- Modify: `backend/etqan/tenants/tests/test_seed_b2.py` (two tests; B2a's hand-added count leaves trial sessions out)
- Modify: `backend/etqan/tenants/tests/test_seed_dev.py` (`test_seed_dev_adds_subscriptions_once` counts non-trial subscriptions)
- Modify: `backend/etqan/tenants/tests/test_seed_staging.py` (`snapshot()`'s subscription count)

**Interfaces:**
- Consumes: Tasks 3–7's services (`set_availability`, `has_availability`, `create_trial`, `schedule_trial`, `has_trials`, `create_subscription(trial=)`), `mark_attendance`, `write_report`, `identity_services.get_teacher_profile`.
- Produces: `b2.seed_availability(subdomain)`, `b2.seed_trials(subdomain)` (plan D16). Both idempotent; `other` gets nothing.

- [ ] **Step 1: Write the failing tests** (append to `backend/etqan/tenants/tests/test_seed_b2.py`; add `from datetime import time` and `from etqan.platform.exceptions import ConflictError` to its imports)

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_demo_gets_windows_and_three_trials_once():
    call_command("seed_dev")
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        assert features.enabled("trial_sessions")
        assert features.enabled("teacher_availability")
        bilal = identity_services.people_queryset("teacher").get(full_name="Ustadh Bilal")
        windows = scheduling_services.windows_of(bilal.teacher_profile.pk)
        assert [(w.weekday, w.start_time, w.end_time) for w in windows] == [
            (day, time(16), time(21)) for day in range(4)
        ]
        trials = list(scheduling_services.trials_queryset().order_by("pk"))
        current = [scheduling_services.current_trial_session(t.pk) for t in trials]
        assert [scheduling_services.trial_status(s) for s in current] == [
            "not_scheduled",
            "scheduled",
            "completed",
        ]
        assert [t.request_status for t in trials] == [
            "under_review",
            "accepted",
            "accepted",
        ]
        converted = trials[2]
        assert converted.converted_to.student.user.full_name == "Zaid Huda"
        assert converted.converted_to.slots.count() == 0
        done = scheduling_services.sessions_queryset().get(pk=current[2].pk)
        assert (done.student_attendance, done.has_report) == ("present", True)
        assert current[1].occurs_on > scheduling_services.today()
    with tenant_context(other):
        assert not scheduling_services.has_trials()
        assert not scheduling_services.has_availability()


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_a_refused_trial_step_leaves_nothing_of_that_request(capsys, monkeypatch):
    """Only the trial step's conversion is refused (seed_subscriptions calls
    the same service, so the patch wraps `seed_trials` alone)."""

    def refuse(**_kwargs):
        raise ConflictError("Refused for the test.", code="test.refused")

    real = b2.seed_trials

    def seed_trials_refusing(subdomain):
        with monkeypatch.context() as patch:
            patch.setattr(b2.scheduling_services, "create_subscription", refuse)
            real(subdomain)

    monkeypatch.setattr(b2, "seed_trials", seed_trials_refusing)
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(Academy.objects.get(subdomain="demo")):
        students = [
            t.student.user.full_name for t in scheduling_services.trials_queryset()
        ]
        assert sorted(students) == ["Aisha Omar", "Yusuf Omar"]
    assert "skip: trial converted — Refused for the test." in capsys.readouterr().out
```

In B2a's `test_demo_gets_a_make_up_and_an_unpaid_extra_session_once`, the hand-added sessions are B2a's own: `hand = scheduling_services.sessions_queryset().filter(generated=False).exclude(kind="trial")` (slice B2e's trial sessions are added by hand too).

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/tenants/tests/test_seed_b2.py`
Expected: FAIL (`AssertionError` on `features.enabled("trial_sessions")`… then `[] == [...]`: nothing seeded yet; `AttributeError: … has no attribute 'seed_trials'` for the wrapper test).

- [ ] **Step 3: The seed steps** (`backend/etqan/tenants/seeds/b2.py`, at the end)

```python
# Slice B2e (spec §8, plan D16): in demo, weekly windows for two teachers and
# three trial requests — one under review, one scheduled in three days, one
# whose session two days ago was attended, reported and converted into a
# subscription (no slots; no invoice: billing is the API's). Other academies
# get nothing.
AVAILABILITY = {
    "demo": {
        "Ustadh Bilal": [(day, time(16, 0), time(21, 0)) for day in (0, 1, 2, 3)],
        "Ustadha Maryam": [(day, time(9, 0), time(13, 0)) for day in (6, 0, 1, 2)],
    }
}
TRIALS = {
    "demo": {
        "under review": {
            "student": "Aisha Omar",
            "course": "Tajweed",
            "source": "website",
            "heard_from": "facebook",
        },
        "scheduled": {
            "student": "Yusuf Omar",
            "course": "Quran Memorisation",
            "source": "app",
            "heard_from": "google",
            "teacher": "Ustadha Maryam",
            "in_days": 3,
            "start": time(16, 0),
        },
        "converted": {
            "student": "Zaid Huda",
            "course": "Tajweed",
            "source": "website",
            "heard_from": "referral",
            "teacher": "Ustadh Bilal",
            "in_days": -2,
            "start": time(17, 0),
            "package": "Two-week intensive",
        },
    }
}
TRIAL_MINUTES = 30


def seed_availability(subdomain: str) -> None:
    """Idempotent: skipped once any teacher has a window."""
    spec = AVAILABILITY.get(subdomain)
    if spec is None or scheduling_services.has_availability():
        return
    for name, windows in spec.items():
        teacher = _person("teacher", name)
        profile = teacher and identity_services.get_teacher_profile(teacher.id)
        if not profile:
            print(f"skip: availability of {name} — seeded record not found")  # noqa: T201
            continue
        scheduling_services.set_availability(
            profile.pk,
            [
                {"weekday": day, "start_time": start, "end_time": end}
                for day, start, end in windows
            ],
        )


def _trial_records(item: dict) -> dict | None:
    found = {
        "student": _person("student", item["student"]),
        "course": catalogue_services.find_course(item["course"]),
    }
    if "teacher" in item:
        found["teacher"] = _person("teacher", item["teacher"])
    if "package" in item:
        found["package"] = catalogue_services.find_package(item["package"])
    return None if None in found.values() else found


def _seed_trial(item: dict, found: dict) -> None:
    """One request, scheduled and converted as far as ``item`` says, as the
    system; the teacher marks and reports, as seed_attendance does."""
    today = scheduling_services.today()
    trial = scheduling_services.create_trial(
        by=None,
        student_id=found["student"].id,
        course_id=found["course"].id,
        source=item["source"],
        minutes=TRIAL_MINUTES,
        heard_from=item["heard_from"],
    )
    teacher = found.get("teacher")
    if teacher is None:
        return
    session = scheduling_services.schedule_trial(
        trial,
        by=None,
        teacher_id=teacher.id,
        occurs_on=today + timedelta(days=item["in_days"]),
        start_time=item["start"],
    ).session
    if "package" not in found:
        return
    scheduling_services.mark_attendance(
        session, by=teacher, student_attendance="present", teacher_attendance="present"
    )
    scheduling_services.write_report(
        session, by=teacher, behaviour=5, participation=4, notes="A keen first lesson."
    )
    scheduling_services.create_subscription(
        student_id=found["student"].id,
        course_id=found["course"].id,
        teacher_id=teacher.id,
        package_id=found["package"].id,
        starts_on=today,
        trial=trial,
    )


def seed_trials(subdomain: str) -> None:
    """Idempotent: skipped once the academy has a trial request. Each request
    is one transaction: a refused step is printed and leaves nothing of it."""
    spec = TRIALS.get(subdomain)
    if spec is None or scheduling_services.has_trials():
        return
    for key, item in spec.items():
        found = _trial_records(item)
        if found is None:
            print(f"skip: trial {key} — a seeded record was not found")  # noqa: T201
            continue
        try:
            with transaction.atomic():
                _seed_trial(item, found)
        except (ValidationError, ConflictError) as exc:
            print(f"skip: trial {key} — {exc}")  # noqa: T201
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, after `b2.seed_archives(subdomain)`:

```python
        b2.seed_availability(subdomain)
        b2.seed_trials(subdomain)
```

- [ ] **Step 4: Narrow the shared counts to the everyday rows**

`backend/etqan/tenants/tests/test_seed_dev.py`, in `test_seed_dev_adds_subscriptions_once`'s `seeded()`:

```python
        subs = list(
            scheduling.subscriptions_queryset()
            .filter(archived_at__isnull=True)  # slice B2d: the archive's own
            .filter(trial_request__isnull=True)  # slice B2e: the trial's own
            .order_by("id")
        )
```

`backend/etqan/tenants/tests/test_seed_staging.py`, `snapshot()`:

```python
        # Slice B2d / B2e: the everyday rows, not the archive's or the trial's.
        "subscriptions": scheduling.subscriptions_queryset()
        .filter(archived_at__isnull=True, trial_request__isnull=True)
        .count(),
```

- [ ] **Step 5: Run every seed test**

Run: `… exec -T django pytest -q etqan/tenants/tests/`
Expected: PASS. `test_seed_dev_marks_past_sessions_and_writes_reports_once` keeps passing because the converted trial's session is present **and** reported (one missing report still); `test_seed_dev_skips_a_subscription_whose_teacher_was_deactivated` keeps passing because its delete loop also removes the converted subscription (no sessions) and `seed_trials` skips on its marker the second time. If either fails, report the failure and the smallest fix (Plan 31 rulings R2/R3 precedent) rather than loosening another assertion.

- [ ] **Step 6: Seed the stream once and look**

Run: `just _stack-manage migrate_schemas`, `just _stack-manage seed_dev` (twice; the second prints no `skip: trial` line).

- [ ] **Step 7: Verify and commit**

Run: `… exec -T django ruff check --fix .`, `… exec -T django ruff format .`, `… exec -T django lint-imports`

```bash
git -C $W/backend add etqan/tenants/seeds/b2.py etqan/tenants/management/commands/seed_dev.py etqan/tenants/tests/test_seed_b2.py etqan/tenants/tests/test_seed_dev.py etqan/tenants/tests/test_seed_staging.py
git -C $W/backend commit -m "feat(seeds): demo availability windows and three trials, one converted (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 12: Dashboard foundations — switches, types, routes, hooks, fixtures and strings

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode` + 2, after `"simplified_sessions"`)
- Modify: `dashboard/src/features/scheduling/schemas.ts` (trial and availability types and form schemas; `SESSION_KINDS` + `trial`; `Session.trial_id`; `Slot`, `AddedSession`, `PostponedSession` `outside_availability`; `SubscriptionBody.trial_id`)
- Modify: `dashboard/src/features/scheduling/api.ts` (+ `api.test.ts`), `dashboard/src/features/scheduling/queries.ts`
- Modify: `dashboard/src/test/scheduling-fixtures.ts` (`trialRow`, `trialDetail`, `suggestionRow`)
- Create: `dashboard/src/locales/{en,ar}/trials.json`, `dashboard/src/locales/{en,ar}/availability.json`
- Modify: `dashboard/src/locales/{en,ar}/errors.json` (five `scheduling` codes), `dashboard/src/locales/{en,ar}/sessionClasses.json` (`kind.trial`, `tabs.trial`)

**Interfaces:**
- Consumes: Tasks 9–10's routes and payloads.
- Produces (all exported through `@/features/scheduling`'s `export * from "./schemas"` / `"./queries"`):
  - Types `Trial`, `TrialDetail`, `TrialSessionRef`, `TrialBody`, `TrialPatch`, `ScheduleTrialBody`, `ScheduledTrial`, `Suggestion`, `Availability`, `AvailabilityWindow`; constants `TRIAL_SOURCES`, `TRIAL_GENDERS`, `TRIAL_REQUEST_STATUSES`, `HEARD_FROM`, `TRIAL_STATUSES`; form schemas `trialFormSchema` / `TrialFormValues`, `scheduleTrialFormSchema` / `ScheduleTrialFormValues`, `availabilityFormSchema` / `AvailabilityFormValues`; helper `toTrialBody(values, academyZone): TrialBody`.
  - `schedulingApi.trials(params)`, `.trial(id)`, `.createTrial(body)`, `.updateTrial({id, ...patch})`, `.deleteTrial(id)`, `.scheduleTrial({id, ...body})`, `.suggest(params)`, `.availability(userId?)`, `.saveAvailability({userId?, windows})`; `trialsCsvUrl(params)`.
  - Hooks `useTrials(params)`, `useTrial(id | undefined)`, `useAvailability(userId | undefined, enabled)` (`undefined` = the signed-in teacher's own).
  - Fixtures `trialRow(overrides)`, `trialDetail(overrides)`, `suggestionRow(overrides)`.

- [ ] **Step 1: Write the failing API test** (append to `dashboard/src/features/scheduling/api.test.ts`; import `trialsCsvUrl` beside the other CSV helpers)

```ts
	it("reads and writes trials and availability (B2e §6)", async () => {
		await schedulingApi.trials({ status: "not_scheduled", q: "", page: 1 });
		expect(api.get).toHaveBeenLastCalledWith("trials/", {
			params: { status: "not_scheduled", page: "1" },
		});
		await schedulingApi.trial(5);
		expect(api.get).toHaveBeenLastCalledWith("trials/5/");
		await schedulingApi.createTrial({
			student: 11,
			course: 3,
			source: "website",
			minutes: 30,
			heard_from: "google",
		});
		expect(api.post).toHaveBeenLastCalledWith(
			"trials/",
			expect.objectContaining({ student: 11, source: "website" }),
		);
		await schedulingApi.updateTrial({ id: 5, rated: true });
		expect(api.patch).toHaveBeenLastCalledWith("trials/5/", { rated: true });
		await schedulingApi.deleteTrial(5);
		expect(api.delete).toHaveBeenLastCalledWith("trials/5/");
		await schedulingApi.scheduleTrial({
			id: 5,
			teacher_id: 21,
			occurs_on: "2026-06-02",
			start_time: "10:00",
		});
		expect(api.post).toHaveBeenLastCalledWith("trials/5/schedule/", {
			teacher_id: 21,
			occurs_on: "2026-06-02",
			start_time: "10:00",
		});
		await schedulingApi.suggest({
			course: 3,
			occurs_on: "2026-06-02",
			start_time: "10:00",
			minutes: 30,
			gender: "any",
		});
		expect(api.get).toHaveBeenLastCalledWith("trials/suggest/", {
			params: {
				course: "3",
				occurs_on: "2026-06-02",
				start_time: "10:00",
				minutes: "30",
				gender: "any",
			},
		});
		await schedulingApi.availability(21);
		expect(api.get).toHaveBeenLastCalledWith("schedule/availability/21/");
		await schedulingApi.availability();
		expect(api.get).toHaveBeenLastCalledWith("schedule/availability/");
		await schedulingApi.saveAvailability({ windows: [] });
		expect(api.put).toHaveBeenLastCalledWith("schedule/availability/", {
			windows: [],
		});
		await schedulingApi.saveAvailability({ userId: 21, windows: [] });
		expect(api.put).toHaveBeenLastCalledWith("schedule/availability/21/", {
			windows: [],
		});
		expect(trialsCsvUrl({ status: "completed", page: 2 })).toBe(
			"/api/v1/trials/?status=completed&format=csv",
		);
	});
```

and a schema test (new file `dashboard/src/features/scheduling/trials.schemas.test.ts`):

```ts
import { describe, expect, it } from "vitest";
import { toTrialBody, type TrialFormValues } from "./schemas";

const VALUES: TrialFormValues = {
	student: "11",
	course: "3",
	source: "website",
	students_count: "1",
	preferred_gender: "any",
	minutes: "30",
	desired_on: "",
	desired_time: "",
	requested_on: "2026-06-01",
	request_status: "under_review",
	heard_from: "google",
	rated: false,
	notes: "",
};

describe("toTrialBody", () => {
	it("sends numbers and no desired start when none is chosen", () => {
		expect(toTrialBody(VALUES, "UTC")).toEqual({
			student: 11,
			course: 3,
			source: "website",
			students_count: 1,
			preferred_gender: "any",
			minutes: 30,
			desired_at: null,
			requested_on: "2026-06-01",
			request_status: "under_review",
			heard_from: "google",
			rated: false,
			notes: "",
		});
	});

	it("reads the desired start on the academy's clock", () => {
		const body = toTrialBody(
			{ ...VALUES, desired_on: "2026-06-03", desired_time: "16:00" },
			"Asia/Riyadh",
		);
		expect(body.desired_at).toBe("2026-06-03T13:00:00.000Z");
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/api.test.ts src/features/scheduling/trials.schemas.test.ts`
Expected: FAIL (`schedulingApi.trials is not a function`; `toTrialBody` is not exported).

- [ ] **Step 3: Types and schemas** (`dashboard/src/features/scheduling/schemas.ts`)

`SESSION_KINDS` becomes `["regular", "compensation", "extra", "trial"] as const` (comment: "Slice B2e (E-3): a trial session comes from a trial request"). In `Session`, after `compensation_id`: `// Slice B2e: the office's; the trial request it belongs to.` `trial_id?: number | null;`. In `Slot`, `AddedSession` and `PostponedSession`: `// Slice B2e E-11: only while teacher availability is on.` `outside_availability?: boolean;`. In `SubscriptionBody`: `// Slice B2e §4.4: the trial this subscription converts.` `trial_id?: number;`. Import `zonedInstant` from `@/lib/zoned-time` at the top. At the end:

```ts
// ── Slice B2e: trial sessions and teacher availability (spec §3, §6) ─────────

export const TRIAL_SOURCES = ["website", "app", "api"] as const;
export type TrialSource = (typeof TRIAL_SOURCES)[number];
export const TRIAL_GENDERS = ["any", "male", "female"] as const;
export type TrialGender = (typeof TRIAL_GENDERS)[number];
export const TRIAL_REQUEST_STATUSES = [
	"under_review",
	"accepted",
	"rejected",
] as const;
export type TrialRequestStatus = (typeof TRIAL_REQUEST_STATUSES)[number];
export const HEARD_FROM = [
	"facebook",
	"google",
	"youtube",
	"web_search",
	"referral",
	"other",
] as const;
export type HeardFrom = (typeof HEARD_FROM)[number];
/** E-3: not scheduled, or the current session's status. */
export const TRIAL_STATUSES = ["not_scheduled", ...SESSION_STATUSES] as const;
export type TrialStatus = (typeof TRIAL_STATUSES)[number];

export interface TrialSessionRef {
	id: number;
	status: SessionStatus;
	occurs_on: string;
	starts_at: string;
	minutes: number;
	teacher: PersonRef;
	student_attendance: Attendance;
	pays_teacher: boolean;
}
export interface Trial {
	id: number;
	student: StudentRef;
	course: NamedRef;
	source: TrialSource;
	students_count: number;
	preferred_gender: TrialGender;
	minutes: number;
	desired_at: string | null;
	requested_on: string;
	request_status: TrialRequestStatus;
	heard_from: HeardFrom;
	rated: boolean;
	notes: string;
	inquiry_id: number | null;
	status: TrialStatus;
	current_session: TrialSessionRef | null;
	sessions_count: number;
	converted_to: number | null;
	// Plan D2: the server's rule, never restated.
	can_schedule: boolean;
	can_convert: boolean;
	created_by: PersonRef | null;
	created_at: string;
}
export interface TrialDetail extends Trial {
	sessions: (TrialSessionRef & { cancel_reason: string })[];
}
export interface TrialBody {
	student: number;
	course: number;
	source: TrialSource;
	minutes: number;
	heard_from: HeardFrom;
	students_count?: number;
	preferred_gender?: TrialGender;
	desired_at?: string | null;
	requested_on?: string;
	request_status?: TrialRequestStatus;
	rated?: boolean;
	notes?: string;
	inquiry_id?: number | null;
}
export type TrialPatch = Partial<TrialBody>;
export interface ScheduleTrialBody {
	teacher_id: number;
	occurs_on: string;
	start_time: string;
	minutes?: number;
	meeting_url?: string;
	pays_teacher?: boolean;
}
export interface ScheduledTrial {
	trial: TrialDetail;
	conflicts: { session: Session; other: Session }[];
	outside_availability?: boolean;
}
export interface Suggestion {
	teacher: { id: number; full_name: string; gender: string };
	free: boolean;
	available: boolean | null;
	gender_match: boolean;
	week_sessions: number;
}
export interface AvailabilityWindow {
	weekday: number;
	start_time: string;
	end_time: string;
}
export interface Availability {
	teacher: PersonRef;
	windows: AvailabilityWindow[];
}

const digits = (message: string) => z.string().regex(/^\d+$/, message);
export const trialFormSchema = z.object({
	student: pick,
	course: pick,
	source: z.enum(TRIAL_SOURCES),
	students_count: digits("trials.errors.number"),
	preferred_gender: z.enum(TRIAL_GENDERS),
	minutes: digits("trials.errors.number"),
	// The desired start, on the academy's clock; both empty: none.
	desired_on: z.string(),
	desired_time: z.string(),
	requested_on: isoDate,
	request_status: z.enum(TRIAL_REQUEST_STATUSES),
	heard_from: z.enum(HEARD_FROM),
	rated: z.boolean(),
	notes: z.string(),
});
export type TrialFormValues = z.infer<typeof trialFormSchema>;

/** The form's values as the API takes them (spec §6). */
export function toTrialBody(v: TrialFormValues, academyZone: string): TrialBody {
	const desired =
		v.desired_on && v.desired_time
			? zonedInstant(v.desired_on, v.desired_time, academyZone).toISOString()
			: null;
	return {
		student: Number(v.student),
		course: Number(v.course),
		source: v.source,
		students_count: Number(v.students_count),
		preferred_gender: v.preferred_gender,
		minutes: Number(v.minutes),
		desired_at: desired,
		requested_on: v.requested_on,
		request_status: v.request_status,
		heard_from: v.heard_from,
		rated: v.rated,
		notes: v.notes,
	};
}

export const scheduleTrialFormSchema = z.object({
	teacher: pick,
	occurs_on: isoDate,
	start_time: clock,
	minutes: optionalMinutes,
	meeting_url: z.union([z.url("scheduling.errors.urlInvalid"), z.literal("")]),
	pays_teacher: z.boolean(),
});
export type ScheduleTrialFormValues = z.infer<typeof scheduleTrialFormSchema>;

export const availabilityFormSchema = z.object({
	windows: z.array(
		z.object({ weekday: z.number(), start_time: clock, end_time: clock }),
	),
});
export type AvailabilityFormValues = z.infer<typeof availabilityFormSchema>;
```

(`pick`, `isoDate`, `clock`, `optionalMinutes` are this file's existing consts; the new block goes below `optionalMinutes`' definition, i.e. at the end of the file.)

- [ ] **Step 4: Routes and hooks** (`dashboard/src/features/scheduling/api.ts`, `queries.ts`)

In `api.ts`, import the new types, add `const T = "trials/";` and `const AV = "schedule/availability/";` beside `S`/`SE`/`SV`, and inside `schedulingApi` after B2d's entries:

```ts
	// Slice B2e (spec §6).
	trials: async (params: QueryParams) =>
		(await api.get<Paginated<Trial>>(T, { params: clean(params) })).data,
	trial: async (id: number) => (await api.get<TrialDetail>(`${T}${id}/`)).data,
	createTrial: async (body: TrialBody) =>
		(await api.post<TrialDetail>(T, body)).data,
	updateTrial: async ({ id, ...body }: TrialPatch & { id: number }) =>
		(await api.patch<TrialDetail>(`${T}${id}/`, body)).data,
	deleteTrial: async (id: number) => {
		await api.delete(`${T}${id}/`);
	},
	scheduleTrial: async ({ id, ...body }: ScheduleTrialBody & { id: number }) =>
		(await api.post<ScheduledTrial>(`${T}${id}/schedule/`, body)).data,
	suggest: async (params: QueryParams) =>
		(await api.get<Suggestion[]>(`${T}suggest/`, { params: clean(params) }))
			.data,
	availability: async (userId?: number) =>
		(await api.get<Availability>(userId ? `${AV}${userId}/` : AV)).data,
	saveAvailability: async ({
		userId,
		windows,
	}: {
		userId?: number;
		windows: AvailabilityWindow[];
	}) =>
		(await api.put<Availability>(userId ? `${AV}${userId}/` : AV, { windows }))
			.data,
```

and after `subscriptionsCsvUrl`:

```ts
/** The trials list's CSV export, with the list's filters (slice B2e). */
export function trialsCsvUrl(params: QueryParams): string {
	return csvUrl(T, params);
}
```

Export `trialsCsvUrl` from `index.ts` beside the other CSV helpers. In `queries.ts`:

```ts
/** Slice B2e: the trial requests list and one request. */
export function useTrials(params: QueryParams) {
	return useQuery({
		queryKey: [...schedulingKey, "trials", params],
		queryFn: () => schedulingApi.trials(params),
		placeholderData: keepPreviousData,
	});
}

export function useTrial(id: number | undefined) {
	return useQuery({
		queryKey: [...schedulingKey, "trial", id],
		queryFn: () => schedulingApi.trial(id as number),
		enabled: id !== undefined,
	});
}

/** A teacher's windows by User id, or (``undefined``) the signed-in
 * teacher's own. */
export function useAvailability(userId: number | undefined, enabled = true) {
	return useQuery({
		queryKey: [...schedulingKey, "availability", userId ?? "me"],
		queryFn: () => schedulingApi.availability(userId),
		enabled,
	});
}
```

- [ ] **Step 5: The switches** (`dashboard/src/features/identity/schemas.ts`)

After `| "simplified_sessions"`:

```ts
	// Slice B2e (Plan 33).
	| "trial_sessions"
	| "teacher_availability"
```

- [ ] **Step 6: Fixtures** (`dashboard/src/test/scheduling-fixtures.ts`; import `Suggestion`, `Trial`, `TrialDetail`)

```ts
/** Slice B2e: Yusuf's trial request, scheduled with Bilal on 2 June. */
export function trialRow(overrides: Partial<Trial> = {}): Trial {
	return {
		id: 5,
		student: { id: 11, full_name: "Yusuf", timezone: "Asia/Riyadh" },
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		source: "website",
		students_count: 1,
		preferred_gender: "any",
		minutes: 30,
		desired_at: null,
		requested_on: "2026-06-01",
		request_status: "accepted",
		heard_from: "google",
		rated: false,
		notes: "",
		inquiry_id: null,
		status: "scheduled",
		current_session: {
			id: 61,
			status: "scheduled",
			occurs_on: "2026-06-02",
			starts_at: "2026-06-02T10:00:00Z",
			minutes: 30,
			teacher: { id: 21, full_name: "Bilal" },
			student_attendance: "not_set",
			pays_teacher: true,
		},
		sessions_count: 1,
		converted_to: null,
		can_schedule: false,
		can_convert: false,
		created_by: { id: 51, full_name: "Demo Admin" },
		created_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

export function trialDetail(overrides: Partial<TrialDetail> = {}): TrialDetail {
	const row = trialRow(overrides);
	return {
		...row,
		sessions: row.current_session
			? [{ ...row.current_session, cancel_reason: "" }]
			: [],
		...overrides,
	};
}

export function suggestionRow(overrides: Partial<Suggestion> = {}): Suggestion {
	return {
		teacher: { id: 21, full_name: "Bilal", gender: "male" },
		free: true,
		available: true,
		gender_match: true,
		week_sessions: 2,
		...overrides,
	};
}
```

- [ ] **Step 7: Strings**

`dashboard/src/locales/en/trials.json`:

```json
{
	"nav": "Trials",
	"title": "Trial sessions",
	"subtitle": "Trial requests and the sessions they become.",
	"new": "New trial request",
	"edit": "Edit request",
	"editTitle": "Edit trial request",
	"create": "Create trial request",
	"save": "Save",
	"created": "Trial request created.",
	"saved": "Trial request saved.",
	"empty": "No trial requests match.",
	"loadError": "Couldn't load the trial requests.",
	"notFound": "This trial request doesn't exist.",
	"search": "Search by student",
	"badge": "Trial",
	"linkToTrial": "Trial request",
	"yes": "Yes",
	"no": "No",
	"filters": {
		"anyStatus": "Any trial status",
		"anyRequestStatus": "Any request status",
		"anySource": "Any source",
		"anyHeardFrom": "Any answer",
		"anyGender": "Any teacher gender",
		"teacherGender": "Teacher gender",
		"anyTeacher": "Any teacher",
		"anyCourse": "Any course",
		"requestedFrom": "Requested from",
		"requestedTo": "Requested to",
		"columns": "More columns"
	},
	"columns": {
		"student": "Student",
		"course": "Course",
		"status": "Trial status",
		"requestStatus": "Request status",
		"teacher": "Teacher",
		"session": "Session",
		"minutes": "Minutes",
		"requestedOn": "Request date",
		"paysTeacher": "Paid to teacher",
		"heardFrom": "How they heard of us"
	},
	"fields": {
		"student": "Student",
		"findStudent": "Find a student",
		"source": "Request source",
		"course": "Course",
		"studentsCount": "Number of students",
		"preferredGender": "Preferred teacher gender",
		"minutes": "Minutes",
		"desiredOn": "Desired date",
		"desiredTime": "Desired time (academy)",
		"requestedOn": "Request date",
		"requestStatus": "Request status",
		"heardFrom": "How did you hear about us",
		"rated": "The student rated the trial",
		"notes": "Notes"
	},
	"errors": {
		"number": "Enter a whole number."
	},
	"source": {
		"website": "Website",
		"app": "App",
		"api": "API"
	},
	"gender": {
		"any": "No preference",
		"male": "Male",
		"female": "Female"
	},
	"requestStatus": {
		"under_review": "Under review",
		"accepted": "Accepted",
		"rejected": "Rejected"
	},
	"heardFrom": {
		"facebook": "Facebook",
		"google": "Google",
		"youtube": "YouTube",
		"web_search": "Web search",
		"referral": "Referral",
		"other": "Other"
	},
	"status": {
		"not_scheduled": "Not scheduled",
		"scheduled": "Scheduled",
		"completed": "Completed",
		"cancelled": "Cancelled",
		"at_disposal": "At the administration's disposal"
	},
	"detail": {
		"request": "Request",
		"session": "Current session",
		"noSession": "Not scheduled yet.",
		"openSession": "Open the session",
		"attendance": "Student attendance: {{value}}",
		"history": "Earlier sessions",
		"cancelledBecause": "Cancelled: {{reason}}",
		"converted": "Converted to subscription #{{id}}",
		"convert": "Convert to subscription",
		"delete": "Delete request",
		"deleteTitle": "Delete trial request",
		"deleteBody": "The request and its unmarked sessions are deleted. This can't be undone.",
		"deleted": "Trial request deleted.",
		"fromInquiry": "From website inquiry #{{id}}"
	},
	"schedule": {
		"button": "Schedule",
		"title": "Schedule the trial",
		"body": "Choose a teacher, a day and a time on the academy's clock.",
		"teacher": "Teacher",
		"suggest": "Suggest",
		"suggestions": "Suggested teachers",
		"noSuggestions": "No active teacher teaches this course.",
		"choose": "Choose {{name}}",
		"free": "Free",
		"busy": "Has another session",
		"available": "Available",
		"unavailable": "Outside availability",
		"noWindows": "No availability set",
		"genderMatch": "Gender matches",
		"weekSessions_one": "{{count}} session this week",
		"weekSessions_other": "{{count}} sessions this week",
		"date": "Date",
		"time": "Start time (academy)",
		"studentTime": "{{time}} for the student",
		"minutes": "Minutes",
		"minutesHint": "Leave empty for the request's length.",
		"meetingUrl": "Meeting link",
		"paysTeacher": "Paid to teacher",
		"submit": "Schedule",
		"done": "Trial scheduled.",
		"close": "Done"
	},
	"inquiry": {
		"button": "Create trial request",
		"title": "Trial request from an inquiry",
		"body": "The inquiry's details are in the notes. Choose the student; add them first if they are new.",
		"notes": "Website inquiry from {{name}} ({{contact}}): {{message}}",
		"handleFailed": "The trial request was created, but the inquiry couldn't be marked handled."
	}
}
```

`dashboard/src/locales/ar/trials.json` — the same keys:

```json
{
	"nav": "الحصص التجريبية",
	"title": "الحصص التجريبية",
	"subtitle": "طلبات الحصص التجريبية والحصص الناتجة عنها.",
	"new": "طلب حصة تجريبية جديد",
	"edit": "تعديل الطلب",
	"editTitle": "تعديل طلب الحصة التجريبية",
	"create": "إنشاء طلب حصة تجريبية",
	"save": "حفظ",
	"created": "تم إنشاء طلب الحصة التجريبية.",
	"saved": "تم حفظ طلب الحصة التجريبية.",
	"empty": "لا توجد طلبات مطابقة.",
	"loadError": "تعذّر تحميل طلبات الحصص التجريبية.",
	"notFound": "طلب الحصة التجريبية غير موجود.",
	"search": "ابحث باسم الطالب",
	"badge": "تجريبية",
	"linkToTrial": "طلب الحصة التجريبية",
	"yes": "نعم",
	"no": "لا",
	"filters": {
		"anyStatus": "أي حالة للحصة",
		"anyRequestStatus": "أي حالة للطلب",
		"anySource": "أي مصدر",
		"anyHeardFrom": "أي إجابة",
		"anyGender": "أي جنس للمعلم",
		"teacherGender": "جنس المعلم",
		"anyTeacher": "أي معلم",
		"anyCourse": "أي دورة",
		"requestedFrom": "تاريخ الطلب من",
		"requestedTo": "تاريخ الطلب إلى",
		"columns": "أعمدة إضافية"
	},
	"columns": {
		"student": "الطالب",
		"course": "الدورة",
		"status": "حالة الحصة التجريبية",
		"requestStatus": "حالة الطلب",
		"teacher": "المعلم",
		"session": "الحصة",
		"minutes": "الدقائق",
		"requestedOn": "تاريخ الطلب",
		"paysTeacher": "مدفوعة للمعلم",
		"heardFrom": "كيف عرفوا عنا"
	},
	"fields": {
		"student": "الطالب",
		"findStudent": "ابحث عن طالب",
		"source": "مصدر الطلب",
		"course": "الدورة",
		"studentsCount": "عدد الطلاب",
		"preferredGender": "جنس المعلم المفضّل",
		"minutes": "الدقائق",
		"desiredOn": "التاريخ المرغوب",
		"desiredTime": "الوقت المرغوب (بتوقيت الأكاديمية)",
		"requestedOn": "تاريخ الطلب",
		"requestStatus": "حالة الطلب",
		"heardFrom": "كيف عرفت عنا",
		"rated": "قيّم الطالب الحصة التجريبية",
		"notes": "ملاحظات"
	},
	"errors": {
		"number": "أدخل عددًا صحيحًا."
	},
	"source": {
		"website": "الموقع",
		"app": "التطبيق",
		"api": "واجهة برمجية"
	},
	"gender": {
		"any": "بدون تفضيل",
		"male": "ذكر",
		"female": "أنثى"
	},
	"requestStatus": {
		"under_review": "قيد المراجعة",
		"accepted": "مقبول",
		"rejected": "مرفوض"
	},
	"heardFrom": {
		"facebook": "فيسبوك",
		"google": "جوجل",
		"youtube": "يوتيوب",
		"web_search": "البحث على الإنترنت",
		"referral": "ترشيح",
		"other": "أخرى"
	},
	"status": {
		"not_scheduled": "لم تُجدول",
		"scheduled": "مجدولة",
		"completed": "مكتملة",
		"cancelled": "ملغاة",
		"at_disposal": "تحت تصرف الإدارة"
	},
	"detail": {
		"request": "الطلب",
		"session": "الحصة الحالية",
		"noSession": "لم تُجدول بعد.",
		"openSession": "افتح الحصة",
		"attendance": "حضور الطالب: {{value}}",
		"history": "الحصص السابقة",
		"cancelledBecause": "أُلغيت: {{reason}}",
		"converted": "تحوّل إلى الاشتراك رقم {{id}}",
		"convert": "تحويل إلى اشتراك",
		"delete": "حذف الطلب",
		"deleteTitle": "حذف طلب الحصة التجريبية",
		"deleteBody": "يُحذف الطلب وحصصه غير المسجّل حضورها. لا يمكن التراجع عن ذلك.",
		"deleted": "تم حذف طلب الحصة التجريبية.",
		"fromInquiry": "من استفسار الموقع رقم {{id}}"
	},
	"schedule": {
		"button": "جدولة",
		"title": "جدولة الحصة التجريبية",
		"body": "اختر معلمًا ويومًا ووقتًا بتوقيت الأكاديمية.",
		"teacher": "المعلم",
		"suggest": "اقتراح",
		"suggestions": "المعلمون المقترحون",
		"noSuggestions": "لا يوجد معلم نشط يدرّس هذه الدورة.",
		"choose": "اختر {{name}}",
		"free": "متاح",
		"busy": "لديه حصة أخرى",
		"available": "ضمن المواعيد",
		"unavailable": "خارج المواعيد المتاحة",
		"noWindows": "لم تُحدد مواعيد",
		"genderMatch": "الجنس مطابق",
		"weekSessions_zero": "لا حصص هذا الأسبوع",
		"weekSessions_one": "حصة واحدة هذا الأسبوع",
		"weekSessions_two": "حصتان هذا الأسبوع",
		"weekSessions_few": "{{count}} حصص هذا الأسبوع",
		"weekSessions_many": "{{count}} حصة هذا الأسبوع",
		"weekSessions_other": "{{count}} حصة هذا الأسبوع",
		"date": "التاريخ",
		"time": "وقت البدء (بتوقيت الأكاديمية)",
		"studentTime": "{{time}} بتوقيت الطالب",
		"minutes": "الدقائق",
		"minutesHint": "اتركه فارغًا لمدة الطلب.",
		"meetingUrl": "رابط الحصة",
		"paysTeacher": "مدفوعة للمعلم",
		"submit": "جدولة",
		"done": "تمت جدولة الحصة التجريبية.",
		"close": "تم"
	},
	"inquiry": {
		"button": "إنشاء طلب حصة تجريبية",
		"title": "طلب حصة تجريبية من استفسار",
		"body": "تفاصيل الاستفسار في الملاحظات. اختر الطالب، وأضفه أولًا إن كان جديدًا.",
		"notes": "استفسار من الموقع من {{name}} ({{contact}}): {{message}}",
		"handleFailed": "أُنشئ طلب الحصة التجريبية، لكن تعذّر تعليم الاستفسار كمُعالَج."
	}
}
```

`dashboard/src/locales/en/availability.json`:

```json
{
	"nav": "My availability",
	"title": "Availability",
	"subtitle": "Weekly windows on the academy's clock. Scheduling outside them is allowed and shows a warning.",
	"day": "{{day}}",
	"none": "No windows",
	"add": "Add a window on {{day}}",
	"remove": "Remove the window from {{start}} to {{end}} on {{day}}",
	"start": "From",
	"end": "To",
	"save": "Save availability",
	"saved": "Availability saved.",
	"loadError": "Couldn't load the availability.",
	"outside": "Outside {{teacher}}'s availability",
	"outsideSession": "This is outside {{teacher}}'s availability."
}
```

`dashboard/src/locales/ar/availability.json`:

```json
{
	"nav": "مواعيدي المتاحة",
	"title": "المواعيد المتاحة",
	"subtitle": "فترات أسبوعية بتوقيت الأكاديمية. الجدولة خارجها مسموحة مع تنبيه.",
	"day": "{{day}}",
	"none": "لا توجد فترات",
	"add": "أضف فترة يوم {{day}}",
	"remove": "احذف الفترة من {{start}} إلى {{end}} يوم {{day}}",
	"start": "من",
	"end": "إلى",
	"save": "حفظ المواعيد",
	"saved": "تم حفظ المواعيد.",
	"loadError": "تعذّر تحميل المواعيد.",
	"outside": "خارج المواعيد المتاحة لـ {{teacher}}",
	"outsideSession": "هذا خارج المواعيد المتاحة لـ {{teacher}}."
}
```

In `errors.json`'s `scheduling` object (both languages), after `has_upcoming_sessions` — en:

```json
		"trial_rejected": "This trial request was rejected.",
		"trial_scheduled": "This trial already has a session. Change or cancel that session first.",
		"trial_not_completed": "Only a completed trial can become a subscription.",
		"trial_converted": "This trial is already a subscription.",
		"trial_session": "This is a trial session. Delete or cancel it from its trial."
```

ar:

```json
		"trial_rejected": "طلب الحصة التجريبية هذا مرفوض.",
		"trial_scheduled": "لهذه الحصة التجريبية حصة بالفعل. عدّل تلك الحصة أو ألغها أولًا.",
		"trial_not_completed": "لا تتحول إلى اشتراك إلا حصة تجريبية مكتملة.",
		"trial_converted": "تحولت هذه الحصة التجريبية إلى اشتراك بالفعل.",
		"trial_session": "هذه حصة تجريبية. احذفها أو ألغها من طلبها."
```

In `sessionClasses.json`: `kind.trial` — en `"Trial"`, ar `"تجريبية"`; `tabs.trial` — en `"Trial"`, ar `"تجريبية"`.

- [ ] **Step 8: Run the tests to see them pass, and the locale test**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/api.test.ts src/features/scheduling/trials.schemas.test.ts src/locales/locales.test.ts src/features/identity`
Expected: PASS.

- [ ] **Step 9: Verify and commit**

Run: `… exec -T dashboard pnpm exec biome check --write src e2e`, `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`

```bash
git -C $W/dashboard add src/features/identity/schemas.ts src/features/scheduling/schemas.ts src/features/scheduling/api.ts src/features/scheduling/api.test.ts src/features/scheduling/trials.schemas.test.ts src/features/scheduling/queries.ts src/features/scheduling/index.ts src/test/scheduling-fixtures.ts src/locales/en/trials.json src/locales/ar/trials.json src/locales/en/availability.json src/locales/ar/availability.json src/locales/en/errors.json src/locales/ar/errors.json src/locales/en/sessionClasses.json src/locales/ar/sessionClasses.json
git -C $W/dashboard commit -m "feat(scheduling): trial and availability types, routes, hooks and strings (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 13: The trials list, its nav entry and its screen

**Files:**
- Create: `dashboard/src/features/scheduling/TrialsList.tsx` (+ `TrialsList.test.tsx`)
- Modify: `dashboard/src/features/scheduling/index.ts` (export `TrialsList`)
- Create: `dashboard/src/routes/_authed/scheduling.trials.index.tsx`; `scheduling.trials.new.tsx` and `scheduling.trials.$trialId.tsx` as headers only (Task 14 fills them)
- Modify: `dashboard/src/features/shell/nav.ts` (+ `nav.test.ts`) — Trials under `// ── phase B2 ──`
- Modify: `dashboard/src/routes/permissions.test.ts` (`FEATURE_SCREENS`; insert `trials|` into `FEATURE_WORDS`)
- Regenerate: `dashboard/src/routeTree.gen.ts`

**Interfaces:**
- Consumes: Task 12's `useTrials`, `trialsCsvUrl`, `TRIAL_STATUSES`, `TRIAL_REQUEST_STATUSES`, `TRIAL_SOURCES`, `HEARD_FROM`, `trialRow`.
- Produces: `TrialsList()` (no props); the screen `/app/scheduling/trials` (`staticData: { permission: "trial_session.view_any", feature: "trial_sessions" }`); the nav item `office("/scheduling/trials", "trials.nav", Sparkles, "scheduling", "trial_session.view_any", "trial_sessions")`. Rows link to `/scheduling/trials/$trialId` (Task 14's route; tests stub it with `extraPaths`).

- [ ] **Step 1: Write the failing tests** (`dashboard/src/features/scheduling/TrialsList.test.tsx`)

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { academySettings, page, trialRow } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { TrialsList } from "./TrialsList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, trials: vi.fn() },
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

const lastParams = () => vi.mocked(schedulingApi.trials).mock.calls.at(-1)?.[0];

describe("TrialsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 21, user: { full_name: "Bilal" } }]) as never,
		);
		vi.mocked(catalogueApi.list).mockResolvedValue(
			page([{ id: 3, name_ar: "تجويد", name_en: "Tajweed" }]) as never,
		);
		vi.mocked(schedulingApi.trials).mockResolvedValue(
			page([
				trialRow(),
				trialRow({
					id: 6,
					student: { id: 12, full_name: "Aisha", timezone: "UTC" },
					status: "not_scheduled",
					request_status: "under_review",
					current_session: null,
					heard_from: "referral",
				}),
			]),
		);
	});

	it("lists each request with its status, teacher and session", async () => {
		renderWithRouter(<TrialsList />, {
			extraPaths: ["/scheduling/trials/$trialId"],
		});
		const yusuf = await screen.findByRole("row", { name: /Yusuf/ });
		expect(yusuf).toHaveTextContent("Scheduled");
		expect(yusuf).toHaveTextContent("Accepted");
		expect(yusuf).toHaveTextContent("Bilal");
		expect(yusuf).toHaveTextContent("10:00");
		const aisha = screen.getByRole("row", { name: /Aisha/ });
		expect(aisha).toHaveTextContent("Not scheduled");
		expect(aisha).toHaveTextContent("Under review");
		await userEvent.setup().click(within(yusuf).getByRole("link", { name: "Yusuf" }));
		expect(await screen.findByText("at /scheduling/trials/$trialId")).toBeVisible();
	});

	it("filters by status, request status, source and the student's name", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TrialsList />);
		await screen.findByRole("row", { name: /Yusuf/ });
		await user.selectOptions(screen.getByLabelText("Trial status"), "completed");
		await waitFor(() => expect(lastParams()).toMatchObject({ status: "completed", page: 1 }));
		await user.selectOptions(screen.getByLabelText("Request status"), "rejected");
		await user.selectOptions(screen.getByLabelText("Request source"), "app");
		await user.selectOptions(
			screen.getByLabelText("How did you hear about us"),
			"referral",
		);
		await user.type(screen.getByRole("searchbox"), "yus");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				status: "completed",
				request_status: "rejected",
				source: "app",
				heard_from: "referral",
				q: "yus",
			}),
		);
	});

	it("shows the optional columns on demand", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TrialsList />);
		await screen.findByRole("row", { name: /Yusuf/ });
		expect(screen.queryByRole("columnheader", { name: "Minutes" })).toBeNull();
		await user.click(screen.getByRole("checkbox", { name: "Minutes" }));
		await user.click(screen.getByRole("checkbox", { name: "How they heard of us" }));
		expect(screen.getByRole("columnheader", { name: "Minutes" })).toBeVisible();
		expect(screen.getByRole("row", { name: /Aisha/ })).toHaveTextContent("Referral");
	});

	it("offers a new request and the CSV export", async () => {
		renderWithRouter(<TrialsList />, {
			extraPaths: ["/scheduling/trials/new"],
		});
		await screen.findByRole("row", { name: /Yusuf/ });
		expect(screen.getByRole("link", { name: /New trial request/ })).toBeVisible();
		expect(screen.getByRole("link", { name: "Export CSV" })).toHaveAttribute(
			"href",
			"/api/v1/trials/?format=csv",
		);
	});

	it("says when nothing matches", async () => {
		vi.mocked(schedulingApi.trials).mockResolvedValue(page([]));
		renderWithRouter(<TrialsList />);
		expect(await screen.findByText("No trial requests match.")).toBeVisible();
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/TrialsList.test.tsx`
Expected: FAIL (`Failed to resolve import "./TrialsList"`).

- [ ] **Step 3: Write the list** (`dashboard/src/features/scheduling/TrialsList.tsx`)

```tsx
import { Link } from "@tanstack/react-router";
import { Plus, Sparkles } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ExportButton } from "@/components/ExportButton";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { type Course, useCatalogue } from "@/features/catalogue";
import { useCan } from "@/features/identity/permissions";
import { usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { dayIn, formatDay, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	Checkbox,
	EmptyState,
	Input,
	Select,
	Spinner,
	StatusChip,
} from "@/ui";
import { trialsCsvUrl } from "./api";
import { useLocalName } from "./bits";
import { useTrials } from "./queries";
import {
	HEARD_FROM,
	TRIAL_REQUEST_STATUSES,
	TRIAL_SOURCES,
	TRIAL_STATUSES,
	type Trial,
} from "./schemas";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
// TutorHamster's optional columns (spec §7).
const OPTIONAL = ["minutes", "requestedOn", "paysTeacher", "heardFrom"] as const;
type Optional = (typeof OPTIONAL)[number];
const DAYS = [
	["requested_from", "trials.filters.requestedFrom"],
	["requested_to", "trials.filters.requestedTo"],
] as const;
const LINK = "font-medium text-primary-text underline-offset-4 hover:underline";

/** Slice B2e §7: the trial requests, with TutorHamster's filters, optional
 * columns and CSV. Times are the academy's. */
export function TrialsList() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const localName = useLocalName();
	const [params, setParams] = useState<QueryParams>({ page: 1 });
	const [shown, setShown] = useState<Optional[]>([]);
	const { data, isPending, isError } = useTrials(params);
	const { data: academy } = useAcademySettings();
	const listTeachers = can("teacher.view_any");
	const listCourses = can("course.view_any");
	const { data: teachers } = usePeople(
		"teachers",
		{ page_size: 100 },
		{ enabled: listTeachers },
	);
	const { data: courses } = useCatalogue<Course>(
		"courses",
		{ page_size: 100 },
		{ enabled: listCourses },
	);
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const update = (patch: QueryParams) => setParams({ ...params, page: 1, ...patch });
	const toggle = (column: Optional) =>
		setShown(
			shown.includes(column)
				? shown.filter((c) => c !== column)
				: [...shown, column],
		);

	const choice = (
		key: string,
		label: string,
		any: string,
		options: { value: string | number; label: string }[],
	) => (
		<Select
			aria-label={label}
			className="w-auto"
			value={String(params[key] ?? "")}
			onChange={(e) => update({ [key]: e.target.value })}
		>
			<option value="">{any}</option>
			{options.map((o) => (
				<option key={o.value} value={o.value}>
					{o.label}
				</option>
			))}
		</Select>
	);

	const session = (trial: Trial) => {
		const current = trial.current_session;
		if (!current || !academy) return "—";
		const at = new Date(current.starts_at);
		return `${dayIn(at, academy.timezone, i18n.language)} ${wallTime(at, academy.timezone, i18n.language)}`;
	};
	const optionalCell = (trial: Trial, column: Optional) => {
		if (column === "minutes") return trial.minutes;
		if (column === "requestedOn") return formatDay(trial.requested_on, i18n.language);
		if (column === "heardFrom") return t(`trials.heardFrom.${trial.heard_from}`);
		const pays = trial.current_session?.pays_teacher;
		return pays === undefined ? "—" : t(pays ? "trials.yes" : "trials.no");
	};

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<div className="min-w-48 flex-1">
					<label htmlFor="trials-search" className="sr-only">
						{t("trials.search")}
					</label>
					<Input
						id="trials-search"
						type="search"
						placeholder={t("trials.search")}
						value={String(params.q ?? "")}
						onChange={(e) => update({ q: e.target.value })}
					/>
				</div>
				{choice(
					"status",
					t("trials.columns.status"),
					t("trials.filters.anyStatus"),
					TRIAL_STATUSES.map((s) => ({ value: s, label: t(`trials.status.${s}`) })),
				)}
				{choice(
					"request_status",
					t("trials.columns.requestStatus"),
					t("trials.filters.anyRequestStatus"),
					TRIAL_REQUEST_STATUSES.map((s) => ({
						value: s,
						label: t(`trials.requestStatus.${s}`),
					})),
				)}
				{choice(
					"source",
					t("trials.fields.source"),
					t("trials.filters.anySource"),
					TRIAL_SOURCES.map((s) => ({ value: s, label: t(`trials.source.${s}`) })),
				)}
				{choice(
					"heard_from",
					t("trials.fields.heardFrom"),
					t("trials.filters.anyHeardFrom"),
					HEARD_FROM.map((s) => ({ value: s, label: t(`trials.heardFrom.${s}`) })),
				)}
				{choice(
					"teacher_gender",
					t("trials.filters.teacherGender"),
					t("trials.filters.anyGender"),
					(["male", "female"] as const).map((g) => ({
						value: g,
						label: t(`trials.gender.${g}`),
					})),
				)}
				{listTeachers
					? choice(
							"teacher",
							t("trials.columns.teacher"),
							t("trials.filters.anyTeacher"),
							(teachers?.results ?? []).map((p) => ({
								value: p.id,
								label: p.user.full_name,
							})),
						)
					: null}
				{listCourses
					? choice(
							"course",
							t("trials.columns.course"),
							t("trials.filters.anyCourse"),
							(courses?.results ?? []).map((c) => ({
								value: c.id,
								label: localName(c),
							})),
						)
					: null}
				{DAYS.map(([key, label]) => (
					<div key={key} className="flex flex-col gap-1">
						<label htmlFor={`trials-${key}`} className="text-xs">
							{t(label)}
						</label>
						<Input
							id={`trials-${key}`}
							type="date"
							dir="ltr"
							className="w-auto"
							value={String(params[key] ?? "")}
							onChange={(e) => update({ [key]: e.target.value })}
						/>
					</div>
				))}
				<ExportButton href={trialsCsvUrl(params)} />
				{can("trial_session.create") ? (
					<Button asChild size="sm">
						<Link to="/scheduling/trials/new">
							<Plus className="size-4" />
							{t("trials.new")}
						</Link>
					</Button>
				) : null}
			</div>
			<fieldset className="flex flex-wrap items-center gap-4 text-sm">
				<legend className="mb-1 text-xs text-muted-foreground">
					{t("trials.filters.columns")}
				</legend>
				{OPTIONAL.map((column) => (
					<span key={column} className="flex items-center gap-2">
						<Checkbox
							id={`trials-column-${column}`}
							checked={shown.includes(column)}
							onCheckedChange={() => toggle(column)}
						/>
						<label htmlFor={`trials-column-${column}`}>
							{t(`trials.columns.${column}`)}
						</label>
					</span>
				))}
			</fieldset>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("trials.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={Sparkles} title={t("trials.empty")} />
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
										"status",
										"requestStatus",
										"teacher",
										"session",
									] as const
								).map((key) => (
									<th key={key} scope="col" className="p-3 text-start font-medium">
										{t(`trials.columns.${key}`)}
									</th>
								))}
								{OPTIONAL.filter((c) => shown.includes(c)).map((column) => (
									<th key={column} scope="col" className="p-3 text-start font-medium">
										{t(`trials.columns.${column}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((trial) => (
								<tr key={trial.id} className="border-t border-border">
									<td className="p-3">
										<Link
											to="/scheduling/trials/$trialId"
											params={{ trialId: String(trial.id) }}
											className={LINK}
										>
											{trial.student.full_name}
										</Link>
									</td>
									<td className="p-3">{localName(trial.course)}</td>
									<td className="p-3">
										<StatusChip tone={trial.status === "completed" ? "live" : "neutral"}>
											{t(`trials.status.${trial.status}`)}
										</StatusChip>
									</td>
									<td className="p-3">
										{t(`trials.requestStatus.${trial.request_status}`)}
									</td>
									<td className="p-3">
										{trial.current_session?.teacher.full_name ?? "—"}
									</td>
									<td className="p-3" dir="ltr">
										{session(trial)}
									</td>
									{OPTIONAL.filter((c) => shown.includes(c)).map((column) => (
										<td key={column} className="p-3">
											{optionalCell(trial, column)}
										</td>
									))}
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager page={page} pages={pages} onChange={(next) => setParams({ ...params, page: next })} />
		</div>
	);
}
```

The filter labels "Trial status" (`trials.columns.status`), "Request status" (`trials.columns.requestStatus`), "Request source" (`trials.fields.source`) and "How did you hear about us" (`trials.fields.heardFrom`) are what the tests select by; the optional column's checkbox reads "How they heard of us" (`trials.columns.heardFrom`), so no two controls share a name.

Export it from `index.ts`: `export { TrialsList } from "./TrialsList";`.

- [ ] **Step 4: The screen** (`dashboard/src/routes/_authed/scheduling.trials.index.tsx`)

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { TrialsList } from "@/features/scheduling";
import { PageHeader } from "@/ui";

// Slice B2e (spec §7): the trial requests.
export const Route = createFileRoute("/_authed/scheduling/trials/")({
	staticData: { permission: "trial_session.view_any", feature: "trial_sessions" },
	component: function TrialsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("trials.title"));
		return (
			<>
				<PageHeader title={t("trials.title")} description={t("trials.subtitle")} />
				<TrialsList />
			</>
		);
	},
});
```

The list links to `/scheduling/trials/new` and `/scheduling/trials/$trialId`; TanStack Router types every `to`, so create both routes now as headers only (Task 14 fills them in). `dashboard/src/routes/_authed/scheduling.trials.new.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

// Slice B2e (spec §7): a new trial request (the form comes in Task 14).
export const Route = createFileRoute("/_authed/scheduling/trials/new")({
	staticData: { permission: "trial_session.create", feature: "trial_sessions" },
	component: function NewTrialRoute() {
		const { t } = useTranslation();
		usePageTitle(t("trials.new"));
		return <PageHeader title={t("trials.new")} />;
	},
});
```

`dashboard/src/routes/_authed/scheduling.trials.$trialId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

// Slice B2e (spec §7): one trial request (the page comes in Task 14).
export const Route = createFileRoute("/_authed/scheduling/trials/$trialId")({
	staticData: { permission: "trial_session.view", feature: "trial_sessions" },
	component: function TrialRoute() {
		const { t } = useTranslation();
		usePageTitle(t("trials.title"));
		return <PageHeader title={t("trials.title")} />;
	},
});
```

Run `… exec -T dashboard pnpm exec vite build` to regenerate `src/routeTree.gen.ts`.

- [ ] **Step 5: The nav entry and the screen tables**

`dashboard/src/features/shell/nav.ts`: import `Sparkles` from `lucide-react` (alphabetical), and under `// ── phase B2 ──`:

```ts
	// Slice B2e: the office's trial requests.
	office(
		"/scheduling/trials",
		"trials.nav",
		Sparkles,
		"scheduling",
		"trial_session.view_any",
		"trial_sessions",
	),
```

`dashboard/src/features/shell/nav.test.ts` — **insert**, never paste: in "ships the grouped admin areas in order", `"/scheduling/trials",` right after `"/settings/roles",` (with a `// Slice B2e` comment); in "names a feature on exactly the items that belong to one", `"/scheduling/trials": "trial_sessions",`; in "groups consecutive items", the scheduling group's length goes from 4 to 5.

`dashboard/src/routes/permissions.test.ts`: in `FEATURE_SCREENS`, after B2d's lines:

```ts
	// Slice B2e
	"/_authed/scheduling/trials/": "trial_sessions",
	"/_authed/scheduling/trials/new": "trial_sessions",
	"/_authed/scheduling/trials/$trialId": "trial_sessions",
```

and **insert** `trials|` into the current `FEATURE_WORDS` regex right after `archive|` (do not retype the rest of it).

- [ ] **Step 6: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/TrialsList.test.tsx src/features/shell src/routes/permissions.test.ts`
Expected: PASS.

- [ ] **Step 7: Verify and commit**

Run: `… exec -T dashboard pnpm exec biome check --write src e2e`, `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`

```bash
git -C $W/dashboard add src/features/scheduling/TrialsList.tsx src/features/scheduling/TrialsList.test.tsx src/features/scheduling/index.ts src/routes/_authed/scheduling.trials.index.tsx src/routes/_authed/scheduling.trials.new.tsx 'src/routes/_authed/scheduling.trials.$trialId.tsx' src/routeTree.gen.ts src/features/shell/nav.ts src/features/shell/nav.test.ts src/routes/permissions.test.ts
git -C $W/dashboard commit -m "feat(scheduling): the trial requests list (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 14: The trial form, the trial page and the Schedule dialog with Suggest

**Files:**
- Create: `dashboard/src/features/scheduling/TrialForm.tsx` (+ `TrialForm.test.tsx`)
- Create: `dashboard/src/features/scheduling/ScheduleTrialDialog.tsx` (+ `ScheduleTrialDialog.test.tsx`)
- Create: `dashboard/src/features/scheduling/TrialPage.tsx` (+ `TrialPage.test.tsx`)
- Modify: `dashboard/src/features/scheduling/AddSessionDialog.tsx` (`AddedNotes`, beside `ConflictList`)
- Modify: `dashboard/src/features/scheduling/index.ts` (export `TrialForm`, `TrialPage`)
- Modify: `dashboard/src/routes/_authed/scheduling.trials.new.tsx`, `dashboard/src/routes/_authed/scheduling.trials.$trialId.tsx` (fill Task 13's headers)

**Interfaces:**
- Consumes: Task 12's api, hooks, schemas and fixtures; `useChoices` (`courses`, `teachersFor`); `ConflictList`; `studentTime`, `todayIn`, `wallTime`, `dayIn`, `formatDay`; `Confirm`; `Fact`.
- Produces:
  - `TrialForm({ trial?: TrialDetail; defaults?: Partial<TrialFormValues>; inquiryId?: number; onSaved: (saved: TrialDetail) => void })` — creates (`createTrial`, with `inquiry_id` when given) or edits (`updateTrial`).
  - `ScheduleTrialDialog({ trial: TrialDetail; academyZone: string })` — the Schedule button and dialog (teacher, Suggest, date, time with the student's time, minutes, link, paid to teacher).
  - `TrialPage({ trialId: number })` — the request, its current session, earlier sessions, Edit, Delete, Schedule, and the converted link. (Convert is Task 15's.)
  - `AddedNotes({ conflicts, outside, teacher, academyZone, title? })` — the outside-availability warning and the conflicts list, the one component every "after adding" panel shows (Task 17 wires it into B2a / B2b's dialogs).

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/TrialForm.test.tsx`:

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
import { academySettings, page, trialDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { TrialForm } from "./TrialForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			createTrial: vi.fn(),
			updateTrial: vi.fn(),
		},
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

describe("TrialForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(
			academySettings({ timezone: "Asia/Riyadh" }),
		);
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 11, user: { full_name: "Yusuf", timezone: "UTC" } }]) as never,
		);
		vi.mocked(catalogueApi.list).mockResolvedValue(
			page([
				{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [] },
			]) as never,
		);
		vi.mocked(schedulingApi.createTrial).mockResolvedValue(trialDetail());
		vi.mocked(schedulingApi.updateTrial).mockResolvedValue(trialDetail());
	});

	it("records a request with TutorHamster's fields", async () => {
		const onSaved = vi.fn();
		const user = userEvent.setup();
		renderWithRouter(<TrialForm onSaved={onSaved} inquiryId={9} />);
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		await user.selectOptions(screen.getByLabelText(/^Course/), "3");
		await user.selectOptions(screen.getByLabelText(/^Request source/), "app");
		await user.selectOptions(
			screen.getByLabelText(/^How did you hear about us/),
			"youtube",
		);
		await user.clear(screen.getByLabelText(/^Minutes/));
		await user.type(screen.getByLabelText(/^Minutes/), "45");
		await user.type(screen.getByLabelText("Desired date"), "2026-06-03");
		await user.type(screen.getByLabelText("Desired time (academy)"), "16:00");
		await user.click(screen.getByRole("button", { name: "Create trial request" }));
		await waitFor(() =>
			expect(schedulingApi.createTrial).toHaveBeenCalledWith({
				student: 11,
				course: 3,
				source: "app",
				students_count: 1,
				preferred_gender: "any",
				minutes: 45,
				desired_at: "2026-06-03T13:00:00.000Z",
				requested_on: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
				request_status: "under_review",
				heard_from: "youtube",
				rated: false,
				notes: "",
				inquiry_id: 9,
			}),
		);
		expect(onSaved).toHaveBeenCalledWith(trialDetail());
	});

	it("shows the server's word on a field", async () => {
		vi.mocked(schedulingApi.createTrial).mockRejectedValue(
			new AxiosError("bad", "400", undefined, undefined, {
				status: 400,
				data: { minutes: ["Ensure this value is less than or equal to 180."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<TrialForm onSaved={vi.fn()} />);
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		await user.selectOptions(screen.getByLabelText(/^Course/), "3");
		await user.click(screen.getByRole("button", { name: "Create trial request" }));
		expect(
			await screen.findByText("Ensure this value is less than or equal to 180."),
		).toBeVisible();
	});

	it("edits a request, keeping its student as an option", async () => {
		const user = userEvent.setup();
		vi.mocked(peopleApi.list).mockResolvedValue(page([]) as never);
		renderWithRouter(
			<TrialForm
				trial={trialDetail({ notes: "Evenings", student: { id: 40, full_name: "Omar", timezone: "UTC" } })}
				onSaved={vi.fn()}
			/>,
		);
		expect(await screen.findByLabelText(/^Student/)).toHaveValue("40");
		await user.click(screen.getByRole("checkbox", { name: /rated the trial/ }));
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(schedulingApi.updateTrial).toHaveBeenCalledWith(
				expect.objectContaining({ id: 5, student: 40, rated: true, notes: "Evenings" }),
			),
		);
	});
});
```

`dashboard/src/features/scheduling/ScheduleTrialDialog.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import {
	page,
	sessionRow,
	suggestionRow,
	trialDetail,
} from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { ScheduleTrialDialog } from "./ScheduleTrialDialog";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			suggest: vi.fn(),
			scheduleTrial: vi.fn(),
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

const open = trialDetail({
	status: "not_scheduled",
	current_session: null,
	can_schedule: true,
	preferred_gender: "female",
});

async function openDialog() {
	const user = userEvent.setup();
	renderWithRouter(<ScheduleTrialDialog trial={open} academyZone="UTC" />);
	await user.click(await screen.findByRole("button", { name: "Schedule" }));
	const dialog = screen.getByRole("dialog");
	await user.type(within(dialog).getByLabelText(/^Date/), "2026-06-02");
	await user.type(within(dialog).getByLabelText(/^Start time/), "10:00");
	return { user, dialog };
}

describe("ScheduleTrialDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([
				{ id: 21, user: { full_name: "Bilal" } },
				{ id: 22, user: { full_name: "Amal" } },
			]) as never,
		);
		vi.mocked(catalogueApi.list).mockResolvedValue(
			page([
				{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [] },
			]) as never,
		);
	});

	it("suggests teachers with their flags and chooses one", async () => {
		vi.mocked(schedulingApi.suggest).mockResolvedValue([
			suggestionRow({ teacher: { id: 22, full_name: "Amal", gender: "female" }, week_sessions: 0 }),
			suggestionRow({ free: false, available: false, gender_match: false }),
		]);
		const { user, dialog } = await openDialog();
		await user.click(within(dialog).getByRole("button", { name: "Suggest" }));
		const list = await within(dialog).findByRole("list", { name: "Suggested teachers" });
		const [amal, bilal] = within(list).getAllByRole("listitem");
		expect(amal).toHaveTextContent("Free");
		expect(amal).toHaveTextContent("Available");
		expect(amal).toHaveTextContent("Gender matches");
		expect(amal).toHaveTextContent("0 sessions this week");
		expect(bilal).toHaveTextContent("Has another session");
		expect(bilal).toHaveTextContent("Outside availability");
		expect(schedulingApi.suggest).toHaveBeenCalledWith({
			course: 3,
			occurs_on: "2026-06-02",
			start_time: "10:00",
			minutes: 30,
			gender: "female",
		});
		await user.click(within(amal).getByRole("button", { name: "Choose Amal" }));
		expect(within(dialog).getByLabelText(/^Teacher/)).toHaveValue("22");
	});

	it("schedules and then shows the warning and the overlaps", async () => {
		vi.mocked(schedulingApi.scheduleTrial).mockResolvedValue({
			trial: trialDetail(),
			conflicts: [{ session: sessionRow({ id: 61 }), other: sessionRow({ id: 62 }) }],
			outside_availability: true,
		});
		const { user, dialog } = await openDialog();
		await user.selectOptions(within(dialog).getByLabelText(/^Teacher/), "21");
		await user.click(within(dialog).getByRole("button", { name: "Schedule" }));
		await waitFor(() =>
			expect(schedulingApi.scheduleTrial).toHaveBeenCalledWith({
				id: 5,
				teacher_id: 21,
				occurs_on: "2026-06-02",
				start_time: "10:00",
				meeting_url: "",
				pays_teacher: true,
			}),
		);
		expect(
			await within(dialog).findByText("This is outside Bilal's availability."),
		).toBeVisible();
		expect(within(dialog).getByRole("listitem")).toHaveTextContent("Bilal");
	});

	it("translates a refusal", async () => {
		vi.mocked(schedulingApi.scheduleTrial).mockRejectedValue(
			new AxiosError("refused", "409", undefined, undefined, {
				status: 409,
				data: { detail: "Refused.", code: "scheduling.trial_scheduled" },
			} as never),
		);
		const { user, dialog } = await openDialog();
		await user.selectOptions(within(dialog).getByLabelText(/^Teacher/), "21");
		await user.click(within(dialog).getByRole("button", { name: "Schedule" }));
		expect(
			await within(dialog).findByText(
				"This trial already has a session. Change or cancel that session first.",
			),
		).toBeVisible();
	});
});
```

`dashboard/src/features/scheduling/TrialPage.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { CanProvider } from "@/features/identity/permissions";
import { peopleApi } from "@/features/people/api";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page, trialDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { TrialPage } from "./TrialPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			trial: vi.fn(),
			deleteTrial: vi.fn(),
		},
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

describe("TrialPage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(page([]) as never);
		vi.mocked(catalogueApi.list).mockResolvedValue(page([]) as never);
		vi.mocked(schedulingApi.trial).mockResolvedValue(
			trialDetail({
				inquiry_id: 14,
				sessions: [
					{ ...trialDetail().sessions[0] },
					{
						...trialDetail().sessions[0],
						id: 60,
						status: "cancelled",
						cancel_reason: "Student was ill",
					},
				],
			}),
		);
		vi.mocked(schedulingApi.deleteTrial).mockResolvedValue();
	});

	it("shows the request, its current session and the earlier ones", async () => {
		renderWithRouter(<TrialPage trialId={5} />, {
			extraPaths: ["/scheduling/sessions/$sessionId"],
		});
		expect(await screen.findByText("From website inquiry #14")).toBeVisible();
		expect(screen.getByText("Website")).toBeVisible();
		expect(screen.getByRole("link", { name: "Open the session" })).toBeVisible();
		expect(screen.getByText("Cancelled: Student was ill")).toBeVisible();
		// can_schedule is false: no Schedule button while a session is live.
		expect(screen.queryByRole("button", { name: "Schedule" })).toBeNull();
	});

	it("schedules only when the server allows it", async () => {
		vi.mocked(schedulingApi.trial).mockResolvedValue(
			trialDetail({ status: "not_scheduled", current_session: null, can_schedule: true }),
		);
		renderWithRouter(<TrialPage trialId={5} />);
		expect(await screen.findByText("Not scheduled yet.")).toBeVisible();
		expect(screen.getByRole("button", { name: "Schedule" })).toBeVisible();
	});

	it("links the subscription it became", async () => {
		vi.mocked(schedulingApi.trial).mockResolvedValue(
			trialDetail({ status: "completed", converted_to: 77 }),
		);
		renderWithRouter(<TrialPage trialId={5} />, {
			extraPaths: ["/scheduling/subscriptions/$subscriptionId"],
		});
		expect(
			await screen.findByRole("link", { name: "Converted to subscription #77" }),
		).toBeVisible();
	});

	it("deletes after a confirm", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TrialPage trialId={5} />, {
			extraPaths: ["/scheduling/trials"],
		});
		await user.click(await screen.findByRole("button", { name: "Delete request" }));
		await user.click(screen.getByRole("button", { name: "Delete trial request" }));
		await waitFor(() => expect(schedulingApi.deleteTrial).toHaveBeenCalledWith(5));
		expect(await screen.findByText("at /scheduling/trials")).toBeVisible();
	});

	it("hides what the viewer may not do", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("trial_session.view")}>
				<TrialPage trialId={5} />
			</CanProvider>,
		);
		await screen.findByText("From website inquiry #14");
		expect(screen.queryByRole("button", { name: "Edit request" })).toBeNull();
		expect(screen.queryByRole("button", { name: "Delete request" })).toBeNull();
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/TrialForm.test.tsx src/features/scheduling/ScheduleTrialDialog.test.tsx src/features/scheduling/TrialPage.test.tsx`
Expected: FAIL (unresolved imports).

- [ ] **Step 3: The notes every "after adding" panel shows** (`dashboard/src/features/scheduling/AddSessionDialog.tsx`, after `ConflictList`; import `StatusChip` from `@/ui`)

```tsx
/** Slice B2e E-11: the outside-availability warning and the overlaps, after
 * a session is added, scheduled or moved. Shows nothing when there is
 * neither. */
export function AddedNotes({
	conflicts,
	outside,
	teacher,
	academyZone,
	title,
}: {
	conflicts: AddedSession["conflicts"];
	outside?: boolean;
	teacher: string;
	academyZone: string;
	title?: string;
}) {
	const { t } = useTranslation();
	return (
		<div className="flex flex-col gap-3">
			{outside ? (
				<p role="status">
					<StatusChip tone="warning">
						{t("availability.outsideSession", { teacher })}
					</StatusChip>
				</p>
			) : null}
			{conflicts.length > 0 ? (
				<ConflictList conflicts={conflicts} academyZone={academyZone} title={title} />
			) : null}
		</div>
	);
}
```

- [ ] **Step 4: The form** (`dashboard/src/features/scheduling/TrialForm.tsx`)

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { usePeople } from "@/features/people";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { todayIn, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Checkbox,
	Field,
	Input,
	Select,
	Spinner,
	SubmitButton,
	Textarea,
} from "@/ui";
import { schedulingApi } from "./api";
import { useLocalName } from "./bits";
import { useChoices } from "./choices";
import { useSchedulingMutation } from "./queries";
import {
	HEARD_FROM,
	TRIAL_GENDERS,
	TRIAL_REQUEST_STATUSES,
	TRIAL_SOURCES,
	type TrialDetail,
	type TrialFormValues,
	toTrialBody,
	trialFormSchema,
} from "./schemas";

function initial(
	zone: string,
	trial: TrialDetail | undefined,
	defaults: Partial<TrialFormValues>,
): TrialFormValues {
	const desired = trial?.desired_at ? new Date(trial.desired_at) : null;
	return {
		student: trial ? String(trial.student.id) : "",
		course: trial ? String(trial.course.id) : "",
		source: trial?.source ?? "website",
		students_count: String(trial?.students_count ?? 1),
		preferred_gender: trial?.preferred_gender ?? "any",
		minutes: String(trial?.minutes ?? 30),
		desired_on: desired ? todayIn(zone, desired) : "",
		desired_time: desired ? wallTime(desired, zone, "en") : "",
		requested_on: trial?.requested_on ?? todayIn(zone),
		request_status: trial?.request_status ?? "under_review",
		heard_from: trial?.heard_from ?? "other",
		rated: trial?.rated ?? false,
		notes: trial?.notes ?? "",
		...defaults,
	};
}

/** Slice B2e §7, E-1: a trial request's fields. With ``trial`` it edits
 * (PATCH); otherwise it creates, with ``inquiryId`` when it came from a site
 * inquiry (E-8). The student must exist: the office adds a new one first. */
export function TrialForm({
	trial,
	defaults = {},
	inquiryId,
	onSaved,
}: {
	trial?: TrialDetail;
	defaults?: Partial<TrialFormValues>;
	inquiryId?: number;
	onSaved: (saved: TrialDetail) => void;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const localName = useLocalName();
	const [query, setQuery] = useState("");
	const { data: academy } = useAcademySettings();
	const { data: students } = usePeople("students", {
		is_active: "true",
		page_size: 100,
		q: query.trim(),
	});
	const { courses } = useChoices();
	const create = useSchedulingMutation(schedulingApi.createTrial);
	const update = useSchedulingMutation(schedulingApi.updateTrial);
	const {
		register,
		handleSubmit,
		setError,
		watch,
		setValue,
		formState: { errors, isSubmitting },
	} = useForm<TrialFormValues>({
		resolver: zodResolver(trialFormSchema),
		values: academy ? initial(academy.timezone, trial, defaults) : undefined,
	});
	const options = students?.results ?? [];
	const keep =
		trial && !options.some((p) => p.id === trial.student.id) ? trial.student : null;

	async function onSubmit(values: TrialFormValues) {
		if (!academy) return;
		const body = toTrialBody(values, academy.timezone);
		try {
			const saved = trial
				? await update.mutateAsync({ id: trial.id, ...body })
				: await create.mutateAsync(
						inquiryId ? { ...body, inquiry_id: inquiryId } : body,
					);
			onSaved(saved);
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.desired_at) {
				setError("desired_on", { message: parsed.fieldErrors.desired_at });
			}
			if (parsed.fieldErrors.inquiry_id) {
				setError("root.server", { message: parsed.fieldErrors.inquiry_id });
			}
		}
	}

	if (!academy) return <Spinner />;
	const select = (
		name: keyof TrialFormValues,
		label: string,
		values: readonly string[],
		prefix: string,
	) => (
		<Field
			id={`trial-${name}`}
			label={label}
			error={fieldError(errors[name]?.message)}
			required
		>
			<Select {...register(name)}>
				{values.map((value) => (
					<option key={value} value={value}>
						{t(`${prefix}.${value}`)}
					</option>
				))}
			</Select>
		</Field>
	);

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-6" noValidate>
			<div className="grid gap-4 sm:grid-cols-2">
				<Field id="trial-student-search" label={t("trials.fields.findStudent")}>
					<Input
						type="search"
						value={query}
						onChange={(e) => setQuery(e.target.value)}
					/>
				</Field>
				<Field
					id="trial-student"
					label={t("trials.fields.student")}
					error={fieldError(errors.student?.message)}
					required
				>
					<Select {...register("student")}>
						<option value="">—</option>
						{keep ? <option value={keep.id}>{keep.full_name}</option> : null}
						{options.map((p) => (
							<option key={p.id} value={p.id}>
								{p.user.full_name}
							</option>
						))}
					</Select>
				</Field>
				<Field
					id="trial-course"
					label={t("trials.fields.course")}
					error={fieldError(errors.course?.message)}
					required
				>
					<Select {...register("course")}>
						<option value="">—</option>
						{trial && !courses.some((c) => c.id === trial.course.id) ? (
							<option value={trial.course.id}>{localName(trial.course)}</option>
						) : null}
						{courses.map((c) => (
							<option key={c.id} value={c.id}>
								{localName(c)}
							</option>
						))}
					</Select>
				</Field>
				{select("source", t("trials.fields.source"), TRIAL_SOURCES, "trials.source")}
				<Field
					id="trial-students-count"
					label={t("trials.fields.studentsCount")}
					error={fieldError(errors.students_count?.message)}
					required
				>
					<Input inputMode="numeric" dir="ltr" {...register("students_count")} />
				</Field>
				{select(
					"preferred_gender",
					t("trials.fields.preferredGender"),
					TRIAL_GENDERS,
					"trials.gender",
				)}
				<Field
					id="trial-minutes"
					label={t("trials.fields.minutes")}
					error={fieldError(errors.minutes?.message)}
					required
				>
					<Input inputMode="numeric" dir="ltr" {...register("minutes")} />
				</Field>
				<Field
					id="trial-desired-on"
					label={t("trials.fields.desiredOn")}
					error={fieldError(errors.desired_on?.message)}
				>
					<Input type="date" dir="ltr" {...register("desired_on")} />
				</Field>
				<Field id="trial-desired-time" label={t("trials.fields.desiredTime")}>
					<Input type="time" dir="ltr" {...register("desired_time")} />
				</Field>
				<Field
					id="trial-requested-on"
					label={t("trials.fields.requestedOn")}
					error={fieldError(errors.requested_on?.message)}
					required
				>
					<Input type="date" dir="ltr" {...register("requested_on")} />
				</Field>
				{select(
					"request_status",
					t("trials.fields.requestStatus"),
					TRIAL_REQUEST_STATUSES,
					"trials.requestStatus",
				)}
				{select(
					"heard_from",
					t("trials.fields.heardFrom"),
					HEARD_FROM,
					"trials.heardFrom",
				)}
			</div>
			<div className="flex items-center gap-2 text-sm">
				<Checkbox
					id="trial-rated"
					checked={watch("rated")}
					onCheckedChange={(on) => setValue("rated", on === true)}
				/>
				<label htmlFor="trial-rated">{t("trials.fields.rated")}</label>
			</div>
			<Field id="trial-notes" label={t("trials.fields.notes")}>
				<Textarea rows={4} {...register("notes")} />
			</Field>
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>{fieldError(errors.root.server.message)}</AlertDescription>
				</Alert>
			) : null}
			<SubmitButton pending={isSubmitting} className="self-start">
				{t(trial ? "trials.save" : "trials.create")}
			</SubmitButton>
		</form>
	);
}
```

(The "heard from" default is `other`, so the required field always has a value; the office changes it. `Field` marks required fields with an asterisk in the label, which is why the tests match labels with `/^…/`.)

- [ ] **Step 5: The Schedule dialog** (`dashboard/src/features/scheduling/ScheduleTrialDialog.tsx`)

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { FormProvider, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useHasFeature } from "@/features/identity/permissions";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { studentTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Checkbox,
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
	StatusChip,
	SubmitButton,
	toast,
} from "@/ui";
import { AddedNotes } from "./AddSessionDialog";
import { schedulingApi } from "./api";
import { useChoices } from "./choices";
import { useSchedulingMutation } from "./queries";
import {
	type ScheduledTrial,
	type ScheduleTrialFormValues,
	scheduleTrialFormSchema,
	type Suggestion,
	type TrialDetail,
} from "./schemas";

const EMPTY: ScheduleTrialFormValues = {
	teacher: "",
	occurs_on: "",
	start_time: "",
	minutes: "",
	meeting_url: "",
	pays_teacher: true,
};

function Flags({ found, preferred }: { found: Suggestion; preferred: string }) {
	const { t } = useTranslation();
	const hasFeature = useHasFeature();
	return (
		<span className="flex flex-wrap gap-1">
			<StatusChip tone={found.free ? "live" : "warning"}>
				{t(found.free ? "trials.schedule.free" : "trials.schedule.busy")}
			</StatusChip>
			{hasFeature("teacher_availability") ? (
				<StatusChip tone={found.available === false ? "warning" : "neutral"}>
					{t(
						found.available === null
							? "trials.schedule.noWindows"
							: found.available
								? "trials.schedule.available"
								: "trials.schedule.unavailable",
					)}
				</StatusChip>
			) : null}
			{preferred !== "any" && found.gender_match ? (
				<StatusChip>{t("trials.schedule.genderMatch")}</StatusChip>
			) : null}
			<span className="text-xs text-muted-foreground">
				{t("trials.schedule.weekSessions", { count: found.week_sessions })}
			</span>
		</span>
	);
}

/** Slice B2e §7: schedule the trial — a teacher (or a suggestion), a day and
 * a time on the academy's clock with the student's beside it, the length
 * (the request's by default), the link and "paid to teacher". Afterwards it
 * shows the outside-availability warning and the overlaps (never blocks). */
export function ScheduleTrialDialog({
	trial,
	academyZone,
}: {
	trial: TrialDetail;
	academyZone: string;
}) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const [result, setResult] = useState<ScheduledTrial | null>(null);
	const { teachersFor } = useChoices();
	const schedule = useSchedulingMutation(schedulingApi.scheduleTrial);
	const suggest = useMutation({ mutationFn: schedulingApi.suggest });
	const methods = useForm<ScheduleTrialFormValues>({
		resolver: zodResolver(scheduleTrialFormSchema),
		defaultValues: EMPTY,
	});
	const { register, handleSubmit, setError, reset, setValue, watch, formState } =
		methods;
	const [occursOn, startTime, minutes] = watch(["occurs_on", "start_time", "minutes"]);
	const theirs = studentTime({
		date: occursOn,
		time: startTime,
		academyZone,
		studentZone: trial.student.timezone,
		language: i18n.language,
	});
	const teachers = teachersFor(String(trial.course.id));

	function close(next: boolean) {
		setOpen(next);
		if (!next) {
			reset(EMPTY);
			setResult(null);
			suggest.reset();
		}
	}

	async function onSubmit(v: ScheduleTrialFormValues) {
		try {
			const done = await schedule.mutateAsync({
				id: trial.id,
				teacher_id: Number(v.teacher),
				occurs_on: v.occurs_on,
				start_time: v.start_time,
				...(v.minutes ? { minutes: Number(v.minutes) } : {}),
				meeting_url: v.meeting_url,
				pays_teacher: v.pays_teacher,
			});
			toast({ description: t("trials.schedule.done") });
			if (done.conflicts.length > 0 || done.outside_availability) setResult(done);
			else close(false);
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.teacher_id) {
				setError("teacher", { message: parsed.fieldErrors.teacher_id });
			}
		}
	}

	return (
		<Dialog open={open} onOpenChange={close}>
			<DialogTrigger asChild>
				<Button size="sm">{t("trials.schedule.button")}</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("trials.schedule.title")}</DialogTitle>
				<DialogDescription>{t("trials.schedule.body")}</DialogDescription>
				{result ? (
					<div className="mt-4 flex flex-col gap-4">
						<AddedNotes
							conflicts={result.conflicts}
							outside={result.outside_availability}
							teacher={result.trial.current_session?.teacher.full_name ?? ""}
							academyZone={academyZone}
						/>
						<DialogFooter>
							<DialogClose asChild>
								<Button type="button">{t("trials.schedule.close")}</Button>
							</DialogClose>
						</DialogFooter>
					</div>
				) : (
					<FormProvider {...methods}>
						<form
							onSubmit={handleSubmit(onSubmit)}
							className="mt-4 flex flex-col gap-4"
							noValidate
						>
							<div className="grid grid-cols-2 gap-3">
								<Field
									id="trial-date"
									label={t("trials.schedule.date")}
									error={fieldError(formState.errors.occurs_on?.message)}
									required
								>
									<Input type="date" dir="ltr" {...register("occurs_on")} />
								</Field>
								<Field
									id="trial-time"
									label={t("trials.schedule.time")}
									error={fieldError(formState.errors.start_time?.message)}
									required
								>
									<Input type="time" dir="ltr" {...register("start_time")} />
								</Field>
							</div>
							{theirs ? (
								<p className="-mt-2 text-xs text-muted-foreground">
									{t("trials.schedule.studentTime", { time: theirs })}
								</p>
							) : null}
							<div className="flex items-end gap-2">
								<Field
									id="trial-teacher"
									label={t("trials.schedule.teacher")}
									error={fieldError(formState.errors.teacher?.message)}
									required
									className="flex-1"
								>
									<Select {...register("teacher")}>
										<option value="" />
										{teachers.map((p) => (
											<option key={p.id} value={p.id}>
												{p.user.full_name}
											</option>
										))}
									</Select>
								</Field>
								<Button
									type="button"
									variant="outline"
									disabled={!occursOn || !startTime || suggest.isPending}
									onClick={() =>
										suggest.mutate({
											course: trial.course.id,
											occurs_on: occursOn,
											start_time: startTime,
											minutes: minutes ? Number(minutes) : trial.minutes,
											gender: trial.preferred_gender,
										})
									}
								>
									{t("trials.schedule.suggest")}
								</Button>
							</div>
							{suggest.data ? (
								suggest.data.length === 0 ? (
									<p className="text-sm text-muted-foreground">
										{t("trials.schedule.noSuggestions")}
									</p>
								) : (
									<ul
										aria-label={t("trials.schedule.suggestions")}
										className="flex flex-col divide-y divide-border rounded-md border border-border"
									>
										{suggest.data.map((found) => (
											<li
												key={found.teacher.id}
												className="flex flex-wrap items-center justify-between gap-2 p-2"
											>
												<span className="flex flex-col gap-1">
													<span className="font-medium">{found.teacher.full_name}</span>
													<Flags found={found} preferred={trial.preferred_gender} />
												</span>
												<Button
													type="button"
													size="sm"
													variant="outline"
													aria-label={t("trials.schedule.choose", {
														name: found.teacher.full_name,
													})}
													onClick={() => setValue("teacher", String(found.teacher.id))}
												>
													{t("trials.schedule.choose", { name: found.teacher.full_name })}
												</Button>
											</li>
										))}
									</ul>
								)
							) : null}
							<Field
								id="trial-minutes"
								label={t("trials.schedule.minutes")}
								error={fieldError(formState.errors.minutes?.message)}
							>
								<Input type="text" inputMode="numeric" dir="ltr" {...register("minutes")} />
							</Field>
							<p className="-mt-2 text-xs text-muted-foreground">
								{t("trials.schedule.minutesHint")}
							</p>
							<Field
								id="trial-link"
								label={t("trials.schedule.meetingUrl")}
								error={fieldError(formState.errors.meeting_url?.message)}
							>
								<Input type="url" dir="ltr" {...register("meeting_url")} />
							</Field>
							<div className="flex items-center gap-2 text-sm">
								<Checkbox
									id="trial-pays-teacher"
									checked={watch("pays_teacher")}
									onCheckedChange={(on) => setValue("pays_teacher", on === true)}
								/>
								<label htmlFor="trial-pays-teacher">
									{t("trials.schedule.paysTeacher")}
								</label>
							</div>
							{formState.errors.root?.server ? (
								<Alert variant="destructive">
									<AlertDescription>
										{fieldError(formState.errors.root.server.message)}
									</AlertDescription>
								</Alert>
							) : null}
							<DialogFooter>
								<SubmitButton pending={formState.isSubmitting}>
									{t("trials.schedule.submit")}
								</SubmitButton>
							</DialogFooter>
						</form>
					</FormProvider>
				)}
			</DialogContent>
		</Dialog>
	);
}
```

The "Schedule" trigger and the dialog's submit share the word; the tests reach the submit through `within(dialog)`.

- [ ] **Step 6: The page** (`dashboard/src/features/scheduling/TrialPage.tsx`)

```tsx
import { Link, useNavigate } from "@tanstack/react-router";
import { isAxiosError } from "axios";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Fact } from "@/components/Fact";
import { useAcademySettings } from "@/features/academy/queries";
import { useCan } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import { dayIn, formatDay, otherZoneTime, wallTime } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Dialog,
	DialogContent,
	DialogTitle,
	DialogTrigger,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { SessionStatusChip, useLocalName } from "./bits";
import { useSchedulingMutation, useTrial } from "./queries";
import { schedulingApi } from "./api";
import { ScheduleTrialDialog } from "./ScheduleTrialDialog";
import type { TrialDetail, TrialSessionRef } from "./schemas";
import { TrialForm } from "./TrialForm";

const LINK = "font-medium text-primary-text underline-offset-4 hover:underline";

function When({ session, zone, studentZone }: { session: TrialSessionRef; zone: string; studentZone: string }) {
	const { t, i18n } = useTranslation();
	const at = new Date(session.starts_at);
	const theirs = otherZoneTime(at, studentZone, zone, i18n.language);
	return (
		<span dir="ltr">
			{dayIn(at, zone, i18n.language)} {wallTime(at, zone, i18n.language)}
			{theirs ? (
				<span className="block text-xs font-normal text-muted-foreground">
					{t("trials.schedule.studentTime", { time: theirs })}
				</span>
			) : null}
		</span>
	);
}

function EditRequest({ trial }: { trial: TrialDetail }) {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("trials.edit")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("trials.editTitle")}</DialogTitle>
				<div className="mt-4">
					<TrialForm
						trial={trial}
						onSaved={() => {
							toast({ description: t("trials.saved") });
							setOpen(false);
						}}
					/>
				</div>
			</DialogContent>
		</Dialog>
	);
}

/** Slice B2e §7: one trial request — its fields, its current session (with
 * a link to it), the earlier ones, and what the server allows next. */
export function TrialPage({ trialId }: { trialId: number }) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const navigate = useNavigate();
	const localName = useLocalName();
	const { data: trial, isError, error } = useTrial(trialId);
	const { data: academy } = useAcademySettings();
	const remove = useSchedulingMutation(schedulingApi.deleteTrial);
	if (isError) {
		const missing = isAxiosError(error) && error.response?.status === 404;
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{t(missing ? "trials.notFound" : "trials.loadError")}
				</AlertDescription>
			</Alert>
		);
	}
	if (!trial || !academy) return <Spinner />;
	const zone = academy.timezone;
	const current = trial.current_session;
	const earlier = trial.sessions.filter((s) => s.id !== current?.id);
	const desired = trial.desired_at ? new Date(trial.desired_at) : null;

	return (
		<div className="flex flex-col gap-6">
			<Card>
				<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
					<CardTitle>{trial.student.full_name}</CardTitle>
					<span className="flex flex-wrap items-center gap-2">
						<StatusChip tone={trial.status === "completed" ? "live" : "neutral"}>
							{t(`trials.status.${trial.status}`)}
						</StatusChip>
						{can("trial_session.update") ? <EditRequest trial={trial} /> : null}
						{can("trial_session.delete") ? (
							<Confirm
								action={t("trials.detail.delete")}
								title={t("trials.detail.deleteTitle")}
								body={t("trials.detail.deleteBody")}
								onConfirm={() =>
									remove.mutate(trial.id, {
										onSuccess: () => {
											toast({ description: t("trials.detail.deleted") });
											navigate({ to: "/scheduling/trials" });
										},
										onError: (e) =>
											toast({ description: errorText(e, t), variant: "destructive" }),
									})
								}
							/>
						) : null}
					</span>
				</CardHeader>
				<CardContent className="flex flex-col gap-4">
					{trial.inquiry_id ? (
						<p className="text-sm text-muted-foreground">
							{t("trials.detail.fromInquiry", { id: trial.inquiry_id })}
						</p>
					) : null}
					<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
						<Fact label={t("trials.fields.course")}>{localName(trial.course)}</Fact>
						<Fact label={t("trials.fields.source")}>{t(`trials.source.${trial.source}`)}</Fact>
						<Fact label={t("trials.fields.studentsCount")}>{trial.students_count}</Fact>
						<Fact label={t("trials.fields.preferredGender")}>
							{t(`trials.gender.${trial.preferred_gender}`)}
						</Fact>
						<Fact label={t("trials.fields.minutes")}>{trial.minutes}</Fact>
						<Fact label={t("trials.fields.desiredOn")}>
							{desired ? (
								<span dir="ltr">
									{dayIn(desired, zone, i18n.language)} {wallTime(desired, zone, i18n.language)}
								</span>
							) : (
								"—"
							)}
						</Fact>
						<Fact label={t("trials.fields.requestedOn")}>
							{formatDay(trial.requested_on, i18n.language)}
						</Fact>
						<Fact label={t("trials.fields.requestStatus")}>
							{t(`trials.requestStatus.${trial.request_status}`)}
						</Fact>
						<Fact label={t("trials.fields.heardFrom")}>
							{t(`trials.heardFrom.${trial.heard_from}`)}
						</Fact>
						<Fact label={t("trials.fields.rated")}>
							{t(trial.rated ? "trials.yes" : "trials.no")}
						</Fact>
					</dl>
					{trial.notes ? (
						<p className="whitespace-pre-line text-sm text-muted-foreground">{trial.notes}</p>
					) : null}
				</CardContent>
			</Card>
			<Card>
				<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
					<CardTitle>{t("trials.detail.session")}</CardTitle>
					<span className="flex flex-wrap gap-2">
						{trial.can_schedule && can("trial_session.update") ? (
							<ScheduleTrialDialog trial={trial} academyZone={zone} />
						) : null}
					</span>
				</CardHeader>
				<CardContent className="flex flex-col gap-4">
					{current ? (
						<>
							<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
								<Fact label={t("trials.columns.session")}>
									<When session={current} zone={zone} studentZone={trial.student.timezone} />
								</Fact>
								<Fact label={t("trials.columns.teacher")}>{current.teacher.full_name}</Fact>
								<Fact label={t("trials.columns.status")}>
									<SessionStatusChip status={current.status} />
								</Fact>
								<Fact label={t("trials.columns.paysTeacher")}>
									{t(current.pays_teacher ? "trials.yes" : "trials.no")}
								</Fact>
							</dl>
							<p className="text-sm">
								{t("trials.detail.attendance", {
									value: t(`scheduling.attendance.${current.student_attendance}`),
								})}
							</p>
							<Link
								to="/scheduling/sessions/$sessionId"
								params={{ sessionId: String(current.id) }}
								className={LINK}
							>
								{t("trials.detail.openSession")}
							</Link>
						</>
					) : (
						<p className="text-sm text-muted-foreground">{t("trials.detail.noSession")}</p>
					)}
					{trial.converted_to ? (
						<Link
							to="/scheduling/subscriptions/$subscriptionId"
							params={{ subscriptionId: String(trial.converted_to) }}
							className={LINK}
						>
							{t("trials.detail.converted", { id: trial.converted_to })}
						</Link>
					) : null}
				</CardContent>
			</Card>
			{earlier.length > 0 ? (
				<Card>
					<CardHeader className="border-b border-border">
						<CardTitle>{t("trials.detail.history")}</CardTitle>
					</CardHeader>
					<CardContent>
						<ul className="flex flex-col divide-y divide-border">
							{earlier.map((s) => (
								<li key={s.id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
									<When session={s} zone={zone} studentZone={trial.student.timezone} />
									<span>{s.teacher.full_name}</span>
									<SessionStatusChip status={s.status} />
									{s.cancel_reason ? (
										<span className="text-muted-foreground">
											{t("trials.detail.cancelledBecause", { reason: s.cancel_reason })}
										</span>
									) : null}
								</li>
							))}
						</ul>
					</CardContent>
				</Card>
			) : null}
		</div>
	);
}
```

Export `TrialForm` and `TrialPage` from `index.ts`.

- [ ] **Step 7: Fill the two routes**

`dashboard/src/routes/_authed/scheduling.trials.new.tsx` — the component becomes:

```tsx
	component: function NewTrialRoute() {
		const { t } = useTranslation();
		const navigate = useNavigate();
		usePageTitle(t("trials.new"));
		return (
			<>
				<PageHeader title={t("trials.new")} />
				<TrialForm
					onSaved={(saved) =>
						navigate({
							to: "/scheduling/trials/$trialId",
							params: { trialId: String(saved.id) },
						})
					}
				/>
			</>
		);
	},
```

(imports: `useNavigate` from `@tanstack/react-router`, `TrialForm` from `@/features/scheduling`.)

`dashboard/src/routes/_authed/scheduling.trials.$trialId.tsx` — the component becomes:

```tsx
	component: function TrialRoute() {
		const { t } = useTranslation();
		const { trialId } = Route.useParams();
		usePageTitle(t("trials.title"));
		const id = Number(trialId);
		return (
			<>
				<PageHeader title={t("trials.title")} />
				{Number.isInteger(id) && id > 0 ? (
					<TrialPage trialId={id} />
				) : (
					<p className="text-sm text-muted-foreground">{t("trials.notFound")}</p>
				)}
			</>
		);
	},
```

- [ ] **Step 8: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/TrialForm.test.tsx src/features/scheduling/ScheduleTrialDialog.test.tsx src/features/scheduling/TrialPage.test.tsx src/features/scheduling/AddSessionDialog.test.tsx`
Expected: PASS.

- [ ] **Step 9: Verify and commit**

Run: `… exec -T dashboard pnpm exec biome check --write src e2e`, `… exec -T dashboard pnpm exec vite build`, `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`

```bash
git -C $W/dashboard add src/features/scheduling/TrialForm.tsx src/features/scheduling/TrialForm.test.tsx src/features/scheduling/ScheduleTrialDialog.tsx src/features/scheduling/ScheduleTrialDialog.test.tsx src/features/scheduling/TrialPage.tsx src/features/scheduling/TrialPage.test.tsx src/features/scheduling/AddSessionDialog.tsx src/features/scheduling/index.ts src/routes/_authed/scheduling.trials.new.tsx 'src/routes/_authed/scheduling.trials.$trialId.tsx' src/routeTree.gen.ts
git -C $W/dashboard commit -m "feat(scheduling): the trial form, page and Schedule dialog with Suggest (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 15: Convert to subscription — the button, the pre-filled form, the way back

**Files:**
- Modify: `dashboard/src/features/scheduling/SubscriptionForm.tsx` (+ `SubscriptionForm.test.tsx`)
- Modify: `dashboard/src/routes/_authed/scheduling.subscriptions.new.tsx` (`?trial=`)
- Modify: `dashboard/src/features/scheduling/TrialPage.tsx` (+ `TrialPage.test.tsx`): the Convert button
- Regenerate: `dashboard/src/routeTree.gen.ts`

**Interfaces:**
- Consumes: Task 12's `useTrial`, `TrialDetail`, `SubscriptionBody.trial_id`; Task 14's `TrialPage`.
- Produces: `SubscriptionForm({ trial?: TrialDetail })` — with a trial: student, course and teacher pre-filled (the trial's student kept as an option), `trial_id` sent, and back to `/scheduling/trials/$trialId` on success (plan D14). The route `/app/scheduling/subscriptions/new?trial=<id>` (`validateSearch` → `{ trial?: number }`). On the trial page, "Convert to subscription" while `can_convert` and the viewer holds `subscription.create` and `trial_session.update` (spec §5).

- [ ] **Step 1: Write the failing tests**

Append to `dashboard/src/features/scheduling/SubscriptionForm.test.tsx` (inside its `describe`, reusing its mocks; import `trialDetail` from the fixtures):

```tsx
	it("converts a trial: pre-filled, sent with trial_id, back to the trial", async () => {
		vi.mocked(schedulingApi.create).mockResolvedValue(
			subscriptionDetail({ id: 9 }),
		);
		const user = userEvent.setup();
		const { router } = renderWithRouter(
			<SubscriptionForm
				trial={trialDetail({
					status: "completed",
					can_convert: true,
					student: { id: 40, full_name: "Omar", timezone: "UTC" },
				})}
			/>,
			{ extraPaths: ["/scheduling/trials/$trialId"] },
		);
		expect(await screen.findByLabelText(/^Student/)).toHaveValue("40");
		expect(screen.getByLabelText(/^Course/)).toHaveValue("3");
		expect(screen.getByLabelText(/^Teacher/)).toHaveValue("21");
		await user.selectOptions(screen.getByLabelText(/^Package/), "5");
		await user.click(screen.getByRole("button", { name: "Remove these slot times" }));
		await user.click(screen.getByRole("button", { name: "Create subscription" }));
		await waitFor(() =>
			expect(schedulingApi.create).toHaveBeenCalledWith(
				expect.objectContaining({
					student: 40,
					course: 3,
					teacher: 21,
					package: 5,
					slots: [],
					trial_id: 5,
				}),
			),
		);
		await waitFor(() =>
			expect(router.state.location.pathname).toBe("/scheduling/trials/5"),
		);
	});
```

Append to `dashboard/src/features/scheduling/TrialPage.test.tsx`:

```tsx
	it("offers Convert on a trial the server says may convert", async () => {
		vi.mocked(schedulingApi.trial).mockResolvedValue(
			trialDetail({ status: "completed", can_convert: true }),
		);
		renderWithRouter(<TrialPage trialId={5} />, {
			extraPaths: ["/scheduling/subscriptions/new"],
		});
		expect(
			await screen.findByRole("link", { name: "Convert to subscription" }),
		).toHaveAttribute("href", "/scheduling/subscriptions/new?trial=5");
	});

	it("hides Convert without trial_session.update", async () => {
		vi.mocked(schedulingApi.trial).mockResolvedValue(
			trialDetail({ status: "completed", can_convert: true }),
		);
		renderWithRouter(
			<CanProvider me={staffMe("trial_session.view", "subscription.create")}>
				<TrialPage trialId={5} />
			</CanProvider>,
		);
		await screen.findByRole("link", { name: "Open the session" });
		expect(screen.queryByRole("link", { name: "Convert to subscription" })).toBeNull();
	});
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/SubscriptionForm.test.tsx src/features/scheduling/TrialPage.test.tsx`
Expected: FAIL (the form ignores `trial`; no Convert link).

- [ ] **Step 3: The form takes a trial** (`dashboard/src/features/scheduling/SubscriptionForm.tsx`)

The signature becomes `export function SubscriptionForm({ trial }: { trial?: TrialDetail } = {})` (import `type TrialDetail` from `./schemas`). The `values` block:

```tsx
		values: academy
			? {
					// Slice B2e (plan D14): a trial's student, course and teacher.
					student: trial ? String(trial.student.id) : "",
					course: trial ? String(trial.course.id) : "",
					teacher: trial?.current_session
						? String(trial.current_session.teacher.id)
						: "",
					package: "",
					starts_on: todayIn(academy.timezone),
					price: "",
					slots: [{ weekdays: [], start_time: "", minutes: 45 }],
					supervisor: "",
				}
			: undefined,
```

The student `<Select>` keeps the trial's student when the search leaves it out:

```tsx
							<option value="">—</option>
							{trial &&
							!students?.results.some((p) => p.id === trial.student.id) ? (
								<option value={trial.student.id}>{trial.student.full_name}</option>
							) : null}
```

In `onSubmit`, the body gains `...(trial ? { trial_id: trial.id } : {}),` and the navigation:

```tsx
			if (trial) {
				navigate({
					to: "/scheduling/trials/$trialId",
					params: { trialId: String(trial.id) },
				});
				return;
			}
			navigate({
				to: "/scheduling/subscriptions/$subscriptionId",
				params: { subscriptionId: String(created.id) },
			});
```

(`applyServerErrors` already puts a 400 on `student` — the converting student who is not the trial's, plan D3 — on the Student field, and a 409 code as the form's error.)

- [ ] **Step 4: The route reads `?trial=`** (`dashboard/src/routes/_authed/scheduling.subscriptions.new.tsx`)

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SubscriptionForm, useTrial } from "@/features/scheduling";
import { PageHeader, Spinner } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling/subscriptions/new")({
	staticData: { permission: "subscription.create" },
	// Slice B2e (plan D14): converting a trial opens this form pre-filled.
	validateSearch: (search: Record<string, unknown>): { trial?: number } => {
		const trial = Number(search.trial);
		return Number.isInteger(trial) && trial > 0 ? { trial } : {};
	},
	component: function NewSubscriptionRoute() {
		const { t } = useTranslation();
		const { trial: trialId } = Route.useSearch();
		const { data: trial } = useTrial(trialId);
		usePageTitle(t("scheduling.new"));
		return (
			<>
				<PageHeader title={t("scheduling.new")} />
				{trialId !== undefined && !trial ? <Spinner /> : <SubscriptionForm trial={trial} />}
			</>
		);
	},
});
```

Every other link to this route (`Link to="/scheduling/subscriptions/new"`) still type-checks: the search is optional.

- [ ] **Step 5: The Convert button** (`dashboard/src/features/scheduling/TrialPage.tsx`)

In the current-session card's header `<span>`, after the Schedule dialog:

```tsx
						{trial.can_convert &&
						can("subscription.create") &&
						can("trial_session.update") ? (
							<Button asChild size="sm">
								<Link to="/scheduling/subscriptions/new" search={{ trial: trial.id }}>
									{t("trials.detail.convert")}
								</Link>
							</Button>
						) : null}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vite build`, then `… exec -T dashboard pnpm exec vitest run src/features/scheduling/SubscriptionForm.test.tsx src/features/scheduling/TrialPage.test.tsx`
Expected: PASS.

- [ ] **Step 7: Verify and commit**

Run: `… exec -T dashboard pnpm exec biome check --write src e2e`, `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`

```bash
git -C $W/dashboard add src/features/scheduling/SubscriptionForm.tsx src/features/scheduling/SubscriptionForm.test.tsx src/features/scheduling/TrialPage.tsx src/features/scheduling/TrialPage.test.tsx src/routes/_authed/scheduling.subscriptions.new.tsx src/routeTree.gen.ts
git -C $W/dashboard commit -m "feat(scheduling): convert a completed trial through the pre-filled subscription form (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 16: The availability editor — on the teacher page and as "My availability"

**Files:**
- Create: `dashboard/src/features/scheduling/AvailabilityEditor.tsx` (+ `AvailabilityEditor.test.tsx`)
- Modify: `dashboard/src/features/scheduling/index.ts` (export `AvailabilityEditor`)
- Modify: `dashboard/src/routes/_authed/people.teachers.$personId.tsx` (the Availability section, plan D15)
- Create: `dashboard/src/routes/_authed/teaching.availability.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (+ `nav.test.ts`) — My availability under `// ── phase B2 ──`
- Modify: `dashboard/src/routes/permissions.test.ts` (`FEATURE_SCREENS`; insert `availability|` into `FEATURE_WORDS`)
- Regenerate: `dashboard/src/routeTree.gen.ts`

**Interfaces:**
- Consumes: Task 12's `useAvailability`, `schedulingApi.saveAvailability`, `availabilityFormSchema`; `weekdayName`.
- Produces: `AvailabilityEditor({ userId?: number; editable: boolean })` — a week of windows (Monday to Sunday), add / remove per day, one Save; the server's `windows.<i>` refusals under their row. The screen `/app/teaching/availability` (`staticData: { feature: "teacher_availability" }`) and its nav item.

- [ ] **Step 1: Write the failing tests** (`dashboard/src/features/scheduling/AvailabilityEditor.test.tsx`)

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { schedulingApi } from "./api";
import { AvailabilityEditor } from "./AvailabilityEditor";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: {
			...actual.schedulingApi,
			availability: vi.fn(),
			saveAvailability: vi.fn(),
		},
	};
});

const BILAL = { id: 21, full_name: "Bilal" };

describe("AvailabilityEditor", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(schedulingApi.availability).mockResolvedValue({
			teacher: BILAL,
			windows: [{ weekday: 0, start_time: "16:00", end_time: "21:00" }],
		});
		vi.mocked(schedulingApi.saveAvailability).mockImplementation(
			async ({ windows }) => ({ teacher: BILAL, windows }),
		);
	});

	it("shows the week and saves an added window", async () => {
		const user = userEvent.setup();
		renderWithRouter(<AvailabilityEditor userId={21} editable />);
		const monday = await screen.findByRole("group", { name: "Monday" });
		expect(within(monday).getByLabelText("From")).toHaveValue("16:00");
		const tuesday = screen.getByRole("group", { name: "Tuesday" });
		expect(tuesday).toHaveTextContent("No windows");
		await user.click(
			within(tuesday).getByRole("button", { name: "Add a window on Tuesday" }),
		);
		await user.type(within(tuesday).getByLabelText("From"), "09:00");
		await user.type(within(tuesday).getByLabelText("To"), "12:00");
		await user.click(screen.getByRole("button", { name: "Save availability" }));
		await waitFor(() =>
			expect(schedulingApi.saveAvailability).toHaveBeenCalledWith({
				userId: 21,
				windows: [
					{ weekday: 0, start_time: "16:00", end_time: "21:00" },
					{ weekday: 1, start_time: "09:00", end_time: "12:00" },
				],
			}),
		);
		expect(schedulingApi.availability).toHaveBeenCalledWith(21);
	});

	it("removes a window", async () => {
		const user = userEvent.setup();
		renderWithRouter(<AvailabilityEditor editable />);
		await user.click(
			await screen.findByRole("button", {
				name: "Remove the window from 16:00 to 21:00 on Monday",
			}),
		);
		await user.click(screen.getByRole("button", { name: "Save availability" }));
		await waitFor(() =>
			expect(schedulingApi.saveAvailability).toHaveBeenCalledWith({
				userId: undefined,
				windows: [],
			}),
		);
	});

	it("puts the server's refusal under its row", async () => {
		vi.mocked(schedulingApi.availability).mockResolvedValue({
			teacher: BILAL,
			windows: [
				{ weekday: 0, start_time: "09:00", end_time: "11:00" },
				{ weekday: 0, start_time: "10:00", end_time: "12:00" },
			],
		});
		vi.mocked(schedulingApi.saveAvailability).mockRejectedValue(
			new AxiosError("bad", "400", undefined, undefined, {
				status: 400,
				data: { "windows.1": ["This window overlaps another one on the same day."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<AvailabilityEditor userId={21} editable />);
		await user.click(await screen.findByRole("button", { name: "Save availability" }));
		expect(
			await screen.findByText("This window overlaps another one on the same day."),
		).toBeVisible();
	});

	it("only reads without the right to edit", async () => {
		renderWithRouter(<AvailabilityEditor userId={21} editable={false} />);
		const monday = await screen.findByRole("group", { name: "Monday" });
		expect(monday).toHaveTextContent("16:00");
		expect(screen.queryByRole("button", { name: "Save availability" })).toBeNull();
		expect(within(monday).queryByLabelText("From")).toBeNull();
	});
});
```

(A `<fieldset>` with a `<legend>` has the accessible role `group` named by its legend; that is what Biome asks for instead of `role="group"` on a div.)

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/AvailabilityEditor.test.tsx`
Expected: FAIL (unresolved import).

- [ ] **Step 3: Write the editor** (`dashboard/src/features/scheduling/AvailabilityEditor.tsx`)

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { Plus, X } from "lucide-react";
import { useFieldArray, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { weekdayName } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Input,
	Spinner,
	SubmitButton,
	toast,
} from "@/ui";
import { schedulingApi } from "./api";
import { useAvailability, useSchedulingMutation } from "./queries";
import {
	type AvailabilityFormValues,
	availabilityFormSchema,
	WEEKDAYS,
} from "./schemas";

/** Slice B2e §7, E-9 / E-10: a teacher's weekly windows on the academy's
 * clock — the office's for ``userId``, else the signed-in teacher's own.
 * Overlaps and order are the server's to refuse; its answer lands under the
 * row it names (`windows.<i>`). */
export function AvailabilityEditor({
	userId,
	editable,
}: {
	userId?: number;
	editable: boolean;
}) {
	const { t, i18n } = useTranslation();
	const fieldError = useFieldError();
	const { data, isError } = useAvailability(userId);
	const save = useSchedulingMutation(schedulingApi.saveAvailability);
	const {
		control,
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<AvailabilityFormValues>({
		resolver: zodResolver(availabilityFormSchema),
		values: data ? { windows: data.windows } : undefined,
	});
	const rows = useFieldArray({ control, name: "windows" });

	async function onSubmit(values: AvailabilityFormValues) {
		try {
			await save.mutateAsync({ userId, windows: values.windows });
			toast({ description: t("availability.saved") });
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	if (isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>{t("availability.loadError")}</AlertDescription>
			</Alert>
		);
	}
	if (!data) return <Spinner />;
	const rowError = (index: number) => {
		const row = errors.windows?.[index] as
			| { message?: string; start_time?: { message?: string }; end_time?: { message?: string } }
			| undefined;
		return fieldError(
			row?.message ?? row?.start_time?.message ?? row?.end_time?.message,
		);
	};

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4" noValidate>
			{WEEKDAYS.map((day) => {
				const name = weekdayName(day, i18n.language, "long");
				const mine = rows.fields
					.map((field, index) => ({ field, index }))
					.filter(({ field }) => field.weekday === day);
				return (
					<fieldset key={day} className="flex flex-col gap-2 rounded-lg border border-border p-3">
						<legend className="px-1 text-sm font-medium">{name}</legend>
						{mine.length === 0 ? (
							<p className="text-sm text-muted-foreground">{t("availability.none")}</p>
						) : null}
						{mine.map(({ field, index }) =>
							editable ? (
								<div key={field.id} className="flex flex-col gap-1">
									<div className="flex flex-wrap items-center gap-2">
										<label htmlFor={`window-${index}-start`} className="text-xs">
											{t("availability.start")}
										</label>
										<Input
											id={`window-${index}-start`}
											type="time"
											dir="ltr"
											className="w-auto"
											{...register(`windows.${index}.start_time`)}
										/>
										<label htmlFor={`window-${index}-end`} className="text-xs">
											{t("availability.end")}
										</label>
										<Input
											id={`window-${index}-end`}
											type="time"
											dir="ltr"
											className="w-auto"
											{...register(`windows.${index}.end_time`)}
										/>
										<Button
											type="button"
											size="sm"
											variant="outline"
											aria-label={t("availability.remove", {
												start: field.start_time,
												end: field.end_time,
												day: name,
											})}
											onClick={() => rows.remove(index)}
										>
											<X className="size-4" />
										</Button>
									</div>
									{rowError(index) ? (
										<p role="alert" className="text-sm text-destructive">
											{rowError(index)}
										</p>
									) : null}
								</div>
							) : (
								<p key={field.id} className="text-sm" dir="ltr">
									{field.start_time}–{field.end_time}
								</p>
							),
						)}
						{editable ? (
							<Button
								type="button"
								size="sm"
								variant="outline"
								className="self-start"
								aria-label={t("availability.add", { day: name })}
								onClick={() => rows.append({ weekday: day, start_time: "", end_time: "" })}
							>
								<Plus className="size-4" />
							</Button>
						) : null}
					</fieldset>
				);
			})}
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>{fieldError(errors.root.server.message)}</AlertDescription>
				</Alert>
			) : null}
			{editable ? (
				<SubmitButton pending={isSubmitting} className="self-start">
					{t("availability.save")}
				</SubmitButton>
			) : null}
		</form>
	);
}
```

(`text-destructive` is the semantic token `Field`'s own error line uses. The "Remove" label names the window as it was loaded or typed — an empty new row reads "from  to"; that is acceptable for a row not yet filled in.)

Export it from `index.ts`.

- [ ] **Step 4: The teacher page's section** (`dashboard/src/routes/_authed/people.teachers.$personId.tsx`)

Imports: `AvailabilityEditor` from `@/features/scheduling`; `Card`, `CardContent`, `CardHeader`, `CardTitle` from `@/ui`. In the component:

```tsx
		// Slice B2e (plan D15): the teacher's availability, below the form.
		const showAvailability =
			personId !== "new" &&
			hasFeature("teacher_availability") &&
			can("teacher_schedule.view");
```

and after `<TeacherForm personId={personId} />`:

```tsx
				{showAvailability ? (
					<Card>
						<CardHeader className="border-b border-border">
							<CardTitle>{t("availability.title")}</CardTitle>
						</CardHeader>
						<CardContent className="flex flex-col gap-3">
							<p className="text-sm text-muted-foreground">{t("availability.subtitle")}</p>
							<AvailabilityEditor
								userId={Number(personId)}
								editable={can("teacher_schedule.update")}
							/>
						</CardContent>
					</Card>
				) : null}
```

- [ ] **Step 5: "My availability"** (`dashboard/src/routes/_authed/teaching.availability.tsx`)

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { AvailabilityEditor } from "@/features/scheduling";
import { PageHeader } from "@/ui";

// Slice B2e (E-10): a teacher's own weekly windows.
export const Route = createFileRoute("/_authed/teaching/availability")({
	staticData: { feature: "teacher_availability" },
	component: function MyAvailabilityRoute() {
		const { t } = useTranslation();
		usePageTitle(t("availability.nav"));
		return (
			<>
				<PageHeader title={t("availability.nav")} description={t("availability.subtitle")} />
				<AvailabilityEditor editable />
			</>
		);
	},
});
```

Run `… exec -T dashboard pnpm exec vite build`.

- [ ] **Step 6: The nav item and the screen tables**

`dashboard/src/features/shell/nav.ts`: import `CalendarRange` from `lucide-react`; under `// ── phase B2 ──`, after Task 13's Trials item:

```ts
	// Slice B2e: a teacher's own availability.
	{
		to: "/teaching/availability",
		labelKey: "availability.nav",
		icon: CalendarRange,
		group: "teaching",
		requiresRole: "teacher",
		feature: "teacher_availability",
	},
```

`dashboard/src/features/shell/nav.test.ts` — **insert**: `"/teaching/availability",` after `"/scheduling/trials",` in "ships the grouped admin areas in order"; `"/teaching/availability": "teacher_availability",` in "names a feature on exactly the items that belong to one"; and in "shows a teacher their sessions, the reports they owe and their payslips", `"/teaching/availability",` after `"/teaching/payslips",`.

`dashboard/src/routes/permissions.test.ts`: in `FEATURE_SCREENS` under `// Slice B2e`: `"/_authed/teaching/availability": "teacher_availability",`; insert `availability|` into the current `FEATURE_WORDS` regex right after Task 13's `trials|`.

- [ ] **Step 7: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/AvailabilityEditor.test.tsx src/features/shell src/routes`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

Run: `… exec -T dashboard pnpm exec biome check --write src e2e`, `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`

```bash
git -C $W/dashboard add src/features/scheduling/AvailabilityEditor.tsx src/features/scheduling/AvailabilityEditor.test.tsx src/features/scheduling/index.ts 'src/routes/_authed/people.teachers.$personId.tsx' src/routes/_authed/teaching.availability.tsx src/routeTree.gen.ts src/features/shell/nav.ts src/features/shell/nav.test.ts src/routes/permissions.test.ts
git -C $W/dashboard commit -m "feat(scheduling): teacher availability on the teacher page and as My availability (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 17: The warning everywhere a session is added or moved; trial sessions in the sessions list and on the session page

**Files:**
- Modify: `dashboard/src/features/scheduling/AddSessionDialog.tsx` (+ `AddSessionDialog.test.tsx`): `notesOf`; the dialog shows `AddedNotes`
- Modify: `dashboard/src/features/scheduling/MakeUpDialog.tsx`, `dashboard/src/features/scheduling/PostponeDialog.tsx` (+ `PostponeDialog.test.tsx`)
- Modify: `dashboard/src/features/scheduling/SlotsPanel.tsx` (+ `SlotsPanel.test.tsx`)
- Modify: `dashboard/src/features/scheduling/SessionsList.tsx` (+ `SessionsList.test.tsx`): the Trial tab
- Modify: `dashboard/src/features/scheduling/SessionClasses.tsx` (+ `SessionClasses.test.tsx`): the trial's link, "paid to teacher" by kind, no Delete for a trial session

**Interfaces:**
- Consumes: Task 14's `AddedNotes`; Task 12's `outside_availability` fields, `Session.trial_id`, the `trial` kind.
- Produces: `notesOf(answer: { session: Session; conflicts: AddedSession["conflicts"]; outside_availability?: boolean }): Notes | null` and `type Notes = { conflicts; outside: boolean; teacher: string }` in `AddSessionDialog.tsx` — the one rule for "show the after-panel" (any overlap, or the server's warning).

- [ ] **Step 1: Write the failing tests**

Append to `dashboard/src/features/scheduling/AddSessionDialog.test.tsx` (inside its `describe`):

```tsx
	it("warns when the session is outside the teacher's availability", async () => {
		vi.mocked(schedulingApi.addSession).mockResolvedValue({
			session: sessionRow({ id: 90 }),
			conflicts: [],
			outside_availability: true,
		});
		const user = userEvent.setup();
		renderWithRouter(<AddSessionDialog kinds={["regular"]} academyZone="UTC" />);
		await user.click(await screen.findByRole("button", { name: "Add session" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(await within(dialog).findByLabelText(/^Subscription/), "7");
		await user.type(within(dialog).getByLabelText(/^Date/), "2026-06-01");
		await user.type(within(dialog).getByLabelText(/^Start time/), "18:00");
		await user.click(within(dialog).getByRole("button", { name: "Add session" }));
		expect(
			await within(dialog).findByText("This is outside Bilal's availability."),
		).toBeVisible();
		expect(within(dialog).queryByText(/other sessions at that time/)).toBeNull();
	});
```

Append to `dashboard/src/features/scheduling/PostponeDialog.test.tsx`:

```tsx
	it("warns the office when the new time is outside the teacher's availability", async () => {
		vi.mocked(schedulingApi.postpone).mockResolvedValue({
			session: moved,
			conflicts: [],
			outside_availability: true,
		});
		const { user, dialog } = await postpone(true);
		await user.click(within(dialog).getByRole("button", { name: "Postpone" }));
		expect(
			await within(dialog).findByText("This is outside Bilal's availability."),
		).toBeVisible();
	});
```

Append to `dashboard/src/features/scheduling/SlotsPanel.test.tsx`:

```tsx
	it("marks a slot outside the teacher's availability", async () => {
		renderWithRouter(
			<SlotsPanel
				sub={subscriptionDetail({
					slots: [
						slot({ outside_availability: true }),
						slot({ id: 32, weekday: 2, outside_availability: false }),
					],
				})}
				studentTime={riyadh}
			/>,
		);
		const rows = await screen.findAllByRole("listitem");
		expect(rows[0]).toHaveTextContent("Outside Bilal's availability");
		expect(rows[1]).not.toHaveTextContent("Outside");
	});
```

Append to `dashboard/src/features/scheduling/SessionsList.test.tsx`:

```tsx
	it("has a Trial tab while trial sessions are on (B2e)", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<CanProvider me={adminWith("trial_sessions")}>
				<SessionsList />
			</CanProvider>,
		);
		const tabs = await screen.findByRole("group", { name: "Session kind" });
		await user.click(within(tabs).getByRole("button", { name: "Trial" }));
		expect(lastParams()).toEqual(expect.objectContaining({ kind: "trial", page: 1 }));
	});

	it("hides the Trial tab while trial sessions are off (B2e)", async () => {
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<SessionsList />
			</CanProvider>,
		);
		const tabs = await screen.findByRole("group", { name: "Session kind" });
		expect(within(tabs).queryByRole("button", { name: "Trial" })).toBeNull();
	});
```

Append to `dashboard/src/features/scheduling/SessionClasses.test.tsx` (its `show` helper waits for the card title; the title of a trial session's card is "Trial", so widen that regex to `/^(Regular|Make-up|Extra|Trial)$/`):

```tsx
	it("links a trial session's request, with no Delete (B2e)", async () => {
		const trial = sessionRow({
			kind: "trial",
			trial_id: 5,
			subscription_id: null,
			slot_id: null,
			generated: false,
			pays_teacher: true,
		});
		await show(
			<CanProvider me={adminWith("trial_sessions")}>
				<SessionClasses session={trial} academyZone="UTC" />
			</CanProvider>,
			{ extraPaths: ["/scheduling/trials/$trialId"] },
		);
		expect(screen.getByRole("link", { name: "Trial request" })).toBeVisible();
		expect(screen.queryByRole("button", { name: "Delete session" })).toBeNull();
		// "Paid to teacher" follows the trial switch for a trial session.
		expect(screen.getByRole("checkbox", { name: "Pays the teacher" })).toBeVisible();
	});

	it("hides a trial session's paid-to-teacher while trials are off (B2e)", async () => {
		const trial = sessionRow({ kind: "trial", trial_id: 5, generated: false, pays_teacher: true });
		await show(
			<CanProvider me={adminWith("extra_sessions")}>
				<SessionClasses session={trial} academyZone="UTC" />
			</CanProvider>,
		);
		expect(screen.queryByRole("checkbox")).toBeNull();
	});
```

("Delete session" and "Pays the teacher" are trunk's `sessionClasses.delete.button` and `sessionClasses.paysTeacher.label`.)

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/AddSessionDialog.test.tsx src/features/scheduling/PostponeDialog.test.tsx src/features/scheduling/SlotsPanel.test.tsx src/features/scheduling/SessionsList.test.tsx src/features/scheduling/SessionClasses.test.tsx`
Expected: FAIL on the new tests only.

- [ ] **Step 3: One rule for the after-panel** (`dashboard/src/features/scheduling/AddSessionDialog.tsx`, beside `AddedNotes`; import `type Session` from `./schemas`)

```tsx
export interface Notes {
	conflicts: AddedSession["conflicts"];
	outside: boolean;
	teacher: string;
}

/** Slice B2e E-11: what the after-panel shows, or null when there is
 * nothing to show (no overlap, no warning). */
export function notesOf(answer: {
	session: Session;
	conflicts: AddedSession["conflicts"];
	outside_availability?: boolean;
}): Notes | null {
	const outside = answer.outside_availability === true;
	if (answer.conflicts.length === 0 && !outside) return null;
	return {
		conflicts: answer.conflicts,
		outside,
		teacher: answer.session.teacher.full_name,
	};
}
```

In `AddSessionDialog`: `const [notes, setNotes] = useState<Notes | null>(null);` replaces the `conflicts` state; `close` resets it with `setNotes(null)`; after the add:

```tsx
			toast({ description: t("sessionClasses.add.added") });
			const found = notesOf(added);
			if (found) setNotes(found);
			else close(false);
```

and the panel:

```tsx
				{notes ? (
					<div className="mt-4 flex flex-col gap-4">
						<AddedNotes {...notes} academyZone={academyZone} />
						<DialogFooter>
```

The same three edits in `MakeUpDialog.tsx` (import `AddedNotes`, `notesOf`, `type Notes` from `./AddSessionDialog`) and in `PostponeDialog.tsx`, where only the office gets the panel:

```tsx
			const found = office ? notesOf(moved) : null;
			if (found) setNotes(found);
			else close(false);
```

with `<AddedNotes {...notes} academyZone={academyZone} title={t("sessionTimes.postpone.conflicts")} />`.

- [ ] **Step 4: The slot row's warning** (`dashboard/src/features/scheduling/SlotsPanel.tsx`)

In the row's chips (`<div className="flex flex-wrap items-center gap-2">`), first:

```tsx
										{slot.outside_availability ? (
											<StatusChip tone="warning">
												{t("availability.outside", {
													teacher: sub.teacher.full_name,
												})}
											</StatusChip>
										) : null}
```

- [ ] **Step 5: The Trial tab** (`dashboard/src/features/scheduling/SessionsList.tsx`)

`KIND_TABS` gains a last entry `["trial", "trial", "trial_sessions"],` (comment: "Slice B2e: trial sessions, while the trial switch is on; with it off they still show under All (FT-4)").

- [ ] **Step 6: A trial session's class card** (`dashboard/src/features/scheduling/SessionClasses.tsx`)

`deletable` gains `session.kind !== "trial" &&` first (plan D9: the generic delete always refuses a trial session). The pays-teacher condition becomes:

```tsx
	// Slice B2e (E-4): a trial session's "paid to teacher" is the trial
	// switch's; any other's is the extra switch's.
	const paysFeature = session.kind === "trial" ? "trial_sessions" : "extra_sessions";
	...
				{session.pays_teacher !== undefined && hasFeature(paysFeature) ? (
```

and in the `<dl>`, after the compensation links:

```tsx
					{session.trial_id && hasFeature("trial_sessions") ? (
						<Fact label={t("trials.linkToTrial")}>
							<Link
								to="/scheduling/trials/$trialId"
								params={{ trialId: String(session.trial_id) }}
								className="font-medium text-primary-text underline-offset-4 hover:underline"
							>
								{t("trials.linkToTrial")}
							</Link>
						</Fact>
					) : null}
```

- [ ] **Step 7: Run the tests to see them pass**

Run the Step 2 command again, then the whole scheduling folder: `… exec -T dashboard pnpm exec vitest run src/features/scheduling`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

Run: `… exec -T dashboard pnpm exec biome check --write src e2e`, `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`

```bash
git -C $W/dashboard add src/features/scheduling/AddSessionDialog.tsx src/features/scheduling/AddSessionDialog.test.tsx src/features/scheduling/MakeUpDialog.tsx src/features/scheduling/PostponeDialog.tsx src/features/scheduling/PostponeDialog.test.tsx src/features/scheduling/SlotsPanel.tsx src/features/scheduling/SlotsPanel.test.tsx src/features/scheduling/SessionsList.tsx src/features/scheduling/SessionsList.test.tsx src/features/scheduling/SessionClasses.tsx src/features/scheduling/SessionClasses.test.tsx
git -C $W/dashboard commit -m "feat(scheduling): outside-availability warnings; trial sessions in the list and on their page (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 18: "Create trial request" on a trial inquiry (B8's list, under a ledger claim)

**Files:**
- Create: `dashboard/src/features/scheduling/TrialFromInquiry.tsx` (+ `TrialFromInquiry.test.tsx`); export from `index.ts`
- Modify (under ledger claims; B8 owns them): `dashboard/src/features/website/InquiriesList.tsx` (+ `InquiriesList.test.tsx`), `dashboard/src/routes/_authed/website.inquiries.tsx`

**Interfaces:**
- Consumes: Task 14's `TrialForm`; website's `useHandleInquiry(status)` (B8's, exported from `@/features/website`).
- Produces: `TrialFromInquiry({ inquiry: InquiryLike; onCreated: () => Promise<unknown> | void })` with `InquiryLike = { id: number; kind: string; status: string; name: string; email: string; phone: string; message: string }` (structural: website's `Inquiry` fits, so scheduling never imports website); `InquiriesList({ actions?: (inquiry: Inquiry) => ReactNode })` (plan D13).

- [ ] **Step 1: Write the failing test for scheduling's part** (`dashboard/src/features/scheduling/TrialFromInquiry.test.tsx`)

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { CanProvider } from "@/features/identity/permissions";
import { peopleApi } from "@/features/people/api";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { academySettings, page, trialDetail } from "@/test/scheduling-fixtures";
import { schedulingApi } from "./api";
import { TrialFromInquiry } from "./TrialFromInquiry";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		schedulingApi: { ...actual.schedulingApi, createTrial: vi.fn() },
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

const INQUIRY = {
	id: 14,
	kind: "trial",
	status: "new",
	name: "Sara",
	email: "sara@example.com",
	phone: "+966500000000",
	message: "Interested in a trial lesson.",
};

describe("TrialFromInquiry", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 11, user: { full_name: "Sara", timezone: "UTC" } }]) as never,
		);
		vi.mocked(catalogueApi.list).mockResolvedValue(
			page([{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [] }]) as never,
		);
		vi.mocked(schedulingApi.createTrial).mockResolvedValue(trialDetail({ id: 8 }));
	});

	it("creates a request from the inquiry, then marks it and opens the trial", async () => {
		const onCreated = vi.fn().mockResolvedValue(undefined);
		const user = userEvent.setup();
		const { router } = renderWithRouter(
			<TrialFromInquiry inquiry={INQUIRY} onCreated={onCreated} />,
			{ extraPaths: ["/scheduling/trials/$trialId"] },
		);
		await user.click(await screen.findByRole("button", { name: "Create trial request" }));
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).getByLabelText("Notes")).toHaveValue(
			"Website inquiry from Sara (sara@example.com · +966500000000): Interested in a trial lesson.",
		);
		expect(within(dialog).getByLabelText(/^Request source/)).toHaveValue("website");
		await user.selectOptions(await within(dialog).findByLabelText(/^Student/), "11");
		await user.selectOptions(within(dialog).getByLabelText(/^Course/), "3");
		await user.click(within(dialog).getByRole("button", { name: "Create trial request" }));
		await waitFor(() =>
			expect(schedulingApi.createTrial).toHaveBeenCalledWith(
				expect.objectContaining({ inquiry_id: 14, source: "website", student: 11 }),
			),
		);
		await waitFor(() => expect(onCreated).toHaveBeenCalled());
		await waitFor(() =>
			expect(router.state.location.pathname).toBe("/scheduling/trials/8"),
		);
	});

	it("says so when the inquiry could not be marked handled", async () => {
		const onCreated = vi.fn().mockRejectedValue(new Error("network"));
		const user = userEvent.setup();
		renderWithRouter(<TrialFromInquiry inquiry={INQUIRY} onCreated={onCreated} />, {
			extraPaths: ["/scheduling/trials/$trialId"],
		});
		await user.click(await screen.findByRole("button", { name: "Create trial request" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(await within(dialog).findByLabelText(/^Student/), "11");
		await user.selectOptions(within(dialog).getByLabelText(/^Course/), "3");
		await user.click(within(dialog).getByRole("button", { name: "Create trial request" }));
		expect(
			await screen.findByText(
				"The trial request was created, but the inquiry couldn't be marked handled.",
			),
		).toBeVisible();
	});

	it("shows only on a new trial inquiry, to whoever may do both", async () => {
		const { unmount } = renderWithRouter(
			<>
				<TrialFromInquiry inquiry={{ ...INQUIRY, kind: "contact" }} onCreated={vi.fn()} />
				<TrialFromInquiry inquiry={{ ...INQUIRY, status: "handled" }} onCreated={vi.fn()} />
				<p>marker</p>
			</>,
		);
		await screen.findByText("marker");
		expect(screen.queryByRole("button", { name: "Create trial request" })).toBeNull();
		unmount();
		renderWithRouter(
			<CanProvider me={staffMe("trial_session.create")}>
				<TrialFromInquiry inquiry={INQUIRY} onCreated={vi.fn()} />
				<p>marker</p>
			</CanProvider>,
		);
		await screen.findByText("marker");
		expect(screen.queryByRole("button", { name: "Create trial request" })).toBeNull();
	});
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/TrialFromInquiry.test.tsx`
Expected: FAIL (unresolved import).

- [ ] **Step 3: Write it** (`dashboard/src/features/scheduling/TrialFromInquiry.tsx`)

```tsx
import { useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import {
	Button,
	Dialog,
	DialogContent,
	DialogDescription,
	DialogTitle,
	DialogTrigger,
	toast,
} from "@/ui";
import { TrialForm } from "./TrialForm";

/** What it reads of a site inquiry: website's `Inquiry` fits, so scheduling
 * never imports website (plan D13). */
export interface InquiryLike {
	id: number;
	kind: string;
	status: string;
	name: string;
	email: string;
	phone: string;
	message: string;
}

/** Slice B2e E-8: "Create trial request" on a new trial inquiry, shown with
 * both `trial_session.create` and `inquiry.update` while trials are on. The
 * form opens with source `website` and the inquiry in the notes; once the
 * request exists, ``onCreated`` marks the inquiry handled (the page passes
 * website's own mutation) and the trial opens. A failure between the two
 * leaves the inquiry unhandled and says so (spec §10). */
export function TrialFromInquiry({
	inquiry,
	onCreated,
}: {
	inquiry: InquiryLike;
	onCreated: () => Promise<unknown> | void;
}) {
	const { t } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	const navigate = useNavigate();
	const [open, setOpen] = useState(false);
	if (
		inquiry.kind !== "trial" ||
		inquiry.status !== "new" ||
		!hasFeature("trial_sessions") ||
		!can("trial_session.create") ||
		!can("inquiry.update")
	) {
		return null;
	}
	const contact = [inquiry.email, inquiry.phone].filter(Boolean).join(" · ");
	const notes = t("trials.inquiry.notes", {
		name: inquiry.name,
		contact,
		message: inquiry.message,
	});

	async function created(trialId: number) {
		setOpen(false);
		toast({ description: t("trials.created") });
		try {
			await onCreated();
		} catch {
			toast({ description: t("trials.inquiry.handleFailed"), variant: "destructive" });
		}
		navigate({ to: "/scheduling/trials/$trialId", params: { trialId: String(trialId) } });
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("trials.inquiry.button")}
				</Button>
			</DialogTrigger>
			<DialogContent size="lg">
				<DialogTitle>{t("trials.inquiry.title")}</DialogTitle>
				<DialogDescription>{t("trials.inquiry.body")}</DialogDescription>
				<div className="mt-4">
					<TrialForm
						defaults={{ source: "website", notes }}
						inquiryId={inquiry.id}
						onSaved={(saved) => created(saved.id)}
					/>
				</div>
			</DialogContent>
		</Dialog>
	);
}
```

Export `TrialFromInquiry` (and `type InquiryLike`) from `index.ts`.

- [ ] **Step 4: Run it to see it pass, and commit scheduling's part on its own**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/TrialFromInquiry.test.tsx`
Expected: PASS.

```bash
git -C $W/dashboard add src/features/scheduling/TrialFromInquiry.tsx src/features/scheduling/TrialFromInquiry.test.tsx src/features/scheduling/index.ts
git -C $W/dashboard commit -m "feat(scheduling): create a trial request from a site inquiry (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Take the claims on B8's three files** (from `$W`)

```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/b2
R="B2e spec E-8/§7, conductor ruling 2026-10-03: InquiriesList gains an optional actions prop; the inquiries route passes scheduling's TrialFromInquiry (one commit)"
python3 scripts/orchestration/ledger.py claim --reason "$R" B2 dashboard/src/features/website/InquiriesList.tsx
python3 scripts/orchestration/ledger.py claim --reason "$R" B2 dashboard/src/features/website/InquiriesList.test.tsx
python3 scripts/orchestration/ledger.py claim --reason "$R" B2 dashboard/src/routes/_authed/website.inquiries.tsx
```

If any claim is refused (another phase holds it), stop and report: the fallback is a ledger `request` to B8 with this task's diff (conductor ruling).

- [ ] **Step 6: Write the failing test for the prop** (append to `dashboard/src/features/website/InquiriesList.test.tsx`; `renderList` gains an optional `actions` argument passed to `<InquiriesList actions={actions} />`)

```tsx
	it("renders the actions a page passes for each inquiry (B2e)", async () => {
		vi.mocked(websiteApi.listInquiries).mockResolvedValue(page([newInquiry]));
		renderList((inquiry) => <button type="button">{`Act on ${inquiry.name}`}</button>);
		expect(await screen.findByRole("button", { name: "Act on Sara" })).toBeVisible();
	});
```

with `renderList` becoming:

```tsx
function renderList(actions?: (inquiry: Inquiry) => ReactNode) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	render(
		<QueryClientProvider client={client}>
			<InquiriesList actions={actions} />
			<Toaster />
		</QueryClientProvider>,
	);
}
```

(`import type { ReactNode } from "react";`; `websiteApi.listInquiries` is the file's existing mock.)

Run: `… exec -T dashboard pnpm exec vitest run src/features/website/InquiriesList.test.tsx`
Expected: FAIL (`Act on Sara` not found).

- [ ] **Step 7: The prop and the route**

`dashboard/src/features/website/InquiriesList.tsx` — three additive lines: `import type { ReactNode } from "react";` and `import type { Inquiry, InquiryStatus } from "./schemas";` (replacing the `InquiryStatus`-only type import), the signature

```tsx
/** `actions` lets a page add its own buttons beside "Mark handled" (slice
 * B2e: "Create trial request"); website never imports them. */
export function InquiriesList({
	actions,
}: {
	actions?: (inquiry: Inquiry) => ReactNode;
} = {}) {
```

and, in the row's right-hand `<div className="flex items-center gap-2">`, right after the kind `StatusChip`: `{actions?.(inquiry)}`.

`dashboard/src/routes/_authed/website.inquiries.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { TrialFromInquiry } from "@/features/scheduling";
import { InquiriesList, useHandleInquiry } from "@/features/website";

export const Route = createFileRoute("/_authed/website/inquiries")({
	staticData: { permission: "inquiry.view_any" },
	component: InquiriesRoute,
});

function InquiriesRoute() {
	const { t } = useTranslation();
	usePageTitle(t("website.nav.inquiries"));
	// Slice B2e (E-8, plan D13): a trial inquiry becomes a trial request; the
	// inquiry is then marked handled through the site's own admin API.
	const handle = useHandleInquiry("new");
	return (
		<InquiriesList
			actions={(inquiry) => (
				<TrialFromInquiry
					inquiry={inquiry}
					onCreated={() => handle.mutateAsync(inquiry.id)}
				/>
			)}
		/>
	);
}
```

- [ ] **Step 8: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/website src/routes`
Expected: PASS.

- [ ] **Step 9: One commit on B8's files, then release the claims**

Run: `… exec -T dashboard pnpm exec biome check --write src e2e`, `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`

```bash
git -C $W/dashboard add src/features/website/InquiriesList.tsx src/features/website/InquiriesList.test.tsx src/routes/_authed/website.inquiries.tsx
git -C $W/dashboard commit -m "feat(website): inquiries take page actions; a trial inquiry becomes a trial request (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
cd /home/abdulkhalek/Projects/etqan_tutor-wt/b2
python3 scripts/orchestration/ledger.py release B2 dashboard/src/features/website/InquiriesList.tsx
python3 scripts/orchestration/ledger.py release B2 dashboard/src/features/website/InquiriesList.test.tsx
python3 scripts/orchestration/ledger.py release B2 dashboard/src/routes/_authed/website.inquiries.tsx
```

Report the claim and release lines and the commit's hash (it must touch only these three files).

---
### Task 19: End-to-end through Caddy, and the slice gates

**Files:**
- Create: `dashboard/e2e/b2-trials.spec.ts`

**Interfaces:**
- Consumes: everything above, through the browser; `manage("set_features", "demo", "--on", …)`; `login`, `expectLoggedIn`, `DEMO_URL`, `DEMO_ADMIN` from `./fixtures`.

- [ ] **Step 1: Write the spec** (`dashboard/e2e/b2-trials.spec.ts`)

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

const SWITCHES = ["trial_sessions", "teacher_availability"];

/** The date `days` from now in UTC (demo's academy clock). */
function inDays(days: number): string {
	return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

const weekdayLong = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "long", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
	);

// Slice B2e spec §9: the admin gives a teacher a window, records a trial
// request, uses Suggest, schedules it at a past start, marks the student
// present and converts it into a subscription. Stamped data, so a second run
// on the same database never meets the first run's rows; the asserts read
// durable state (values, rows, links), never a toast.
test("the admin schedules a trial in the past, marks it and converts it", async ({
	page,
}) => {
	test.setTimeout(150_000);
	const stamp = Date.now();
	const teacher = `E2E Trial Tutor ${stamp}`;
	const student = `E2E Trial Learner ${stamp}`;
	const course = `E2E Trial Recitation ${stamp}`;
	const pkg = `E2E Trial Eight ${stamp}`;
	const yesterday = inDays(-1);
	manage("set_features", "demo", "--on", ...SWITCHES);
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// Own teacher, course, package and student
	await page.goto(`${DEMO_URL}/app/people/teachers/new`);
	await page.getByLabel(/^full name/i).fill(teacher);
	await page.getByLabel(/^gender/i).selectOption("male");
	await page.getByLabel(/^email/i).fill(`e2e-trial-tutor-${stamp}@e2e.test`);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/teachers\/\d+$/);
	const teacherPage = page.url();

	await page.goto(`${DEMO_URL}/app/catalogue/courses/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`تلاوة تجريبية ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(course);
	await page.getByLabel(teacher, { exact: true }).click();
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/courses$/);

	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`ثمان تجريبية ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(pkg);
	await page.getByLabel("Sessions per week").fill("2");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await page.getByLabel("Price").fill("400");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/packages$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByLabel(/^email/i).fill(`e2e-trial-learner-${stamp}@e2e.test`);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);

	// The teacher is available yesterday morning
	await page.goto(teacherPage);
	const day = page.getByRole("group", { name: weekdayLong(yesterday) });
	await day.getByRole("button", { name: `Add a window on ${weekdayLong(yesterday)}` }).click();
	await day.getByLabel("From").fill("08:00");
	await day.getByLabel("To").fill("12:00");
	await page.getByRole("button", { name: "Save availability" }).click();
	await page.reload();
	await expect(
		page.getByRole("group", { name: weekdayLong(yesterday) }).getByLabel("From"),
	).toHaveValue("08:00");

	// The request
	await page.goto(`${DEMO_URL}/app/scheduling/trials/new`);
	await page.getByLabel("Find a student").fill(student);
	await page.getByLabel(/^Student/).selectOption({ label: student });
	await page.getByLabel(/^Course/).selectOption({ label: course });
	await page.getByLabel(/^Request source/).selectOption("website");
	await page.getByLabel(/^How did you hear about us/).selectOption("referral");
	await page.getByRole("button", { name: "Create trial request" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/trials\/\d+$/);
	const trialPage = page.url();
	await expect(page.getByText("Not scheduled yet.")).toBeVisible();

	// Suggest, then schedule at yesterday 10:00 (a past start, E-5)
	await page.getByRole("button", { name: "Schedule", exact: true }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^Date/).fill(yesterday);
	await dialog.getByLabel(/^Start time/).fill("10:00");
	await dialog.getByRole("button", { name: "Suggest" }).click();
	const suggested = dialog.getByRole("list", { name: "Suggested teachers" });
	const mine = suggested.getByRole("listitem").filter({ hasText: teacher });
	await expect(mine).toContainText("Available");
	await mine.getByRole("button", { name: `Choose ${teacher}` }).click();
	await dialog.getByRole("button", { name: "Schedule", exact: true }).click();
	await expect(page.getByRole("link", { name: "Open the session" })).toBeVisible();

	// Mark the student present on the session page
	await page.getByRole("link", { name: "Open the session" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/sessions\/\d+$/);
	const attendance = page.getByLabel(`Student attendance for ${student}`, { exact: true });
	await attendance.selectOption("present");
	await page.reload();
	await expect(
		page.getByLabel(`Student attendance for ${student}`, { exact: true }),
	).toHaveValue("present");

	// Convert it: the form is pre-filled and comes back to the trial
	await page.goto(trialPage);
	await page.getByRole("link", { name: "Convert to subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/new\?trial=\d+$/);
	await expect(page.getByLabel(/^Student/)).toHaveValue(/\d+/);
	await page.getByLabel(/^Package/).selectOption({ label: pkg });
	await page.getByRole("button", { name: "Remove these slot times" }).click();
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(new RegExp(`${new URL(trialPage).pathname}$`));
	await expect(
		page.getByRole("link", { name: /^Converted to subscription #\d+$/ }),
	).toBeVisible();

	// At phone width the trial page never scrolls sideways
	await page.setViewportSize({ width: 375, height: 800 });
	await page.reload();
	await expect(
		page.getByRole("link", { name: /^Converted to subscription #\d+$/ }),
	).toBeVisible();
	expect(
		await page.evaluate(
			() => document.documentElement.scrollWidth <= window.innerWidth,
		),
	).toBe(true);
	await page.setViewportSize({ width: 1280, height: 800 });

	// The list finds it, converted; Arabic reads right to left
	await page.goto(`${DEMO_URL}/app/scheduling/trials`);
	await page.getByRole("searchbox").fill(student);
	await expect(page.getByRole("row", { name: new RegExp(student) })).toContainText(
		"Completed",
	);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "ar"));
	await page.goto(`${DEMO_URL}/app/scheduling/trials`);
	await expect(page.getByRole("heading", { name: "الحصص التجريبية" })).toBeVisible();
});
```

- [ ] **Step 2: Run it, twice, on the stream's database**

Run: `just e2e e2e/b2-trials.spec.ts` (twice). Expected: `1 passed` both times. If the trials list or the teacher page loads slowly under host load, raise only the single wait that timed out, with a comment; never add a fixed sleep.

- [ ] **Step 3: Commit**

```bash
git -C $W/dashboard add e2e/b2-trials.spec.ts
git -C $W/dashboard commit -m "test(e2e): the admin schedules a trial in the past, marks it and converts it (B2e)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: The slice gates**

Run, from `$W`: `just test` (backend ≥ 80 %, dashboard lines/statements ≥ 80, branches/functions ≥ 70), `just lint` (ruff, `lint-imports`, Biome, the colour checker), then a fresh stack (`just dev-backend` rebuilt if requirements changed, `migrate_schemas`, `seed_dev`) and `just e2e` (it runs `--workers=1 --retries=1`). Expected: all green. Report the counts and coverage figures, and any spec that only passed on its retry (with its failing step), as Plan 31's gate did.

---
## Self-review (done while writing)

**Spec coverage** (spec section → task):
- §1 goal, E-13 switches → Task 1 (registry, `BUILT`), Tasks 9–10 (routes 404 after the permission; `trial_id` 400 while off), Tasks 13, 16 (screens and nav by feature), Task 10 `test_a_trial_session_keeps_showing_while_trials_are_off` (FT-4).
- E-1 / §3.1 fields and bounds → Tasks 1, 4 (every bound, every choice, active account with profile status `trial`), 9 (400 on the field's name), 12 (form).
- E-2 statuses → Task 4 (update refusals), Task 5 (rejected cannot be scheduled; its sessions cannot be restored).
- E-3 / §3.2 trial sessions, one live, current session, history → Tasks 1, 4, 5 (`test_cancel_then_schedule_again_keeps_history_and_one_live`).
- E-4 pays teacher → Task 5 (default on, payroll with and without), Task 8 (the action and the log by `trial_sessions`), Task 17 (the checkbox by kind).
- E-5 teacher rule, past start → Task 5.
- E-6 / §4.3 suggest → Task 6 (each flag, the tie-breaks, no-teacher courses, no gender, availability off, query count), Task 9 (route), Task 14 (button and flags).
- E-7 / §4.4 conversion → Task 7 (refusals in order, lock order by SQL capture, one per request, deleting the subscription), Task 10 (route, explicit code, 400 while off), Task 15 (pre-filled form, back to the trial).
- E-8 inquiry intake → Task 4 / 9 (one request per inquiry), Task 18 (button, notes, marking handled, the claim).
- E-9 / §3.3 / §4.5 windows, advisory lock, `is_available`, DST, midnight, touching → Task 3; E-10 office and self-service → Task 10, Task 16.
- E-11 warnings → Task 3 (`outside_availability`, `slots_outside`), Task 9 (schedule answer), Task 10 (slot rows, add / postpone answers, only while on, no windows → no warning), Task 17 (every display).
- E-12 office-only requests, the trial session in everyone's lists with its badge, non-office postponement → Task 9 (404s), Task 10 (teacher and student lists, no `trial_id`), Task 5 (student and office postponement), Task 12 / 17 (kind label and tab).
- §4.1 delete and the generic delete, restore → Tasks 4, 5. §4.6 lists and CSV → Tasks 4, 9, 13.
- §5 access (codes, 404 for non-office, own availability) → Tasks 9, 10.
- §6 B2c's field → switch map → Task 8. New codes → Tasks 4–7 (services), 12 (translations).
- §7 dashboard → Tasks 12–18. §8 seeds → Task 11. §9 e2e → Task 19.
- §10 known limits are kept as stated (two calls for intake, said by `handleFailed`; academy-time windows; one session per request; `SET_NULL` on conversion; the catalogue's refusal wording).

**Placeholder scan:** no "TBD"/"TODO"/"similar to Task N"; every code step shows its code. Two steps tell the implementer to assert trunk's exact SQL form if it differs (`FOR UPDATE OF …`, Plan 31 ruling R6) — that is a fact to read, not a gap.

**Type and name consistency:** `create_trial` / `update_trial` / `delete_trial` / `schedule_trial` / `suggest_teachers` / `claim_trial` / `set_availability` / `is_available` / `available_map` / `outside_availability` / `slots_outside` / `windows_of` / `has_trials` / `has_availability` are defined once (Tasks 3–7) and used with the same signatures in Tasks 8–11; `services.TRIAL_SESSIONS`, `services.trial_sessions_of`, `services.Scheduled`, `services.Suggestion` are exported where they are first defined. `payloads.outside` (Task 9) is reused by Task 10. Dashboard: `Trial`, `TrialDetail`, `TrialSessionRef`, `ScheduledTrial`, `Suggestion`, `Availability`, `AvailabilityWindow`, `TrialFormValues`, `toTrialBody` (Task 12) are what Tasks 13–18 import; `AddedNotes` (Task 14) and `notesOf` / `Notes` (Task 17) share the `{conflicts, outside, teacher}` shape; `useTrial`, `useTrials`, `useAvailability` are exported through `export * from "./queries"`.

**Review Focus:** five lines, each with its test in the owning task (Tasks 3, 5, 6, 7, 9, 10). Other input classes the spec implies and the tasks already cover: a teacher deactivated after being listed (Task 6, Task 5's inactive teacher), another academy's ids (Task 9), the same inquiry from a second tab (Review Focus 4), a converted subscription deleted (Task 7), switching availability off after windows exist (Task 3 / 10: no key, no warning, suggestion ignores it).

---

**Execution:** Plan 33 has 19 tasks — 11 backend (models → services → API → seeds) and 8 dashboard, then the e2e and gates. The tasks depend on each other's interfaces in a strict chain (Task 12's types feed every dashboard task; Tasks 3–7's services feed 8–11), so subagent-driven execution with a review after each task, as Plans 21, 25 and 31 were built, is the fitting method.
