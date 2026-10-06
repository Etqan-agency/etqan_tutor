# Plan 41 — Weekly Schedules, Substitutes and Bulk Teacher Changes (slice B2g) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B2f (B2g is built on B2f's code: its migration `0011_bundles_groups`, its bundle locks and `each_member`, its `create_subscription(..., bundle=)`, `add_to_group_bundle`, its route-table `UNGATED` set and its conftest helpers). No other phase's slice. B3d (ledger R2, D23, D35) is queued and may merge first: see plan ruling D24 for the three functions both slices touch.
**Slice:** B2g · **Phase spec:** docs/superpowers/specs/2026-10-03-b2-scheduling-depth-design.md (B2-14; §3 row B2g)

**Goal:** The office manages every subscription's (or bundle's) weekly timetable on its own screen — TutorHamster's tabs, stop and restart, put away ("deleted") and restore, a substitute teacher for a period, one teacher change for many timetables, a CSV of every slot and an expanded week calendar — while generation honours the schedule's status and reads the substitutions, behind one switch, `weekly_schedules`, off by default.

**Architecture:**
- **Data** (spec §3). `Subscription.schedule_status` (`active` · `stopped` · `deleted`, database default `active`), `schedule_changed_at`, `schedule_changed_by`; `Session.substitute_for` (→ TeacherProfile, PROTECT); a new `TeacherSubstitution` (subscription CASCADE, teacher PROTECT, `from_date ≤ to_date`). One additive migration `0012_weekly_schedules`. No data rewritten (B2-16).
- **Generation** (G-2, G-5). `_lock_live` leaves out schedules that are not `active` — the same filter that already leaves out B2d's archived subscriptions; `_new_session` gives a date inside a substitution the substitute as `teacher` and the regular teacher as `substitute_for`; the range run reports `skipped_stopped`.
- **Services.** New `services/schedules.py` (one lock for many schedules — bundles first, then every subscription in one statement — then stop, delete, activate, restore and the bulk teacher change, all or nothing, refusals naming the subscription); `services/substitutions.py` (add and remove, each regenerating its range); `services/schedule_reads.py` (the list with bundle rows and collapsed group lines, the calendar, the CSV's slots, the "Add" candidates, seed markers). `create_subscription` gains `schedule_status=` and `substitutions_from=` (renewal and a group newcomer copy them); slots of a deleted schedule are refused; B2b's postponed-teacher move keeps a substitute; `substitute_for_id` joins the activity log.
- **API.** `schedules/` (+ `?format=csv`), `schedules/calendar/`, `schedules/candidates/`, `schedules/stop/`, `schedules/delete/`, `schedules/teacher/`, `schedules/substitutions/`, `schedules/substitutions/<id>/` behind `weekly_schedules`; `schedules/activate/` and `schedules/restore/` ungated (listed in `UNGATED`). New resource `weekly_schedule`. Office only: 404 before the code check. Subscription rows gain `schedule_status`; the office's detail gains `substitutions` and who changed the status; session rows and Today rows gain `substitute_for`.
- **Dashboard.** Weekly schedules (`/app/scheduling/schedules`: tabs, filters, bundle rows, bulk Stop / Activate / Delete / Restore / Change teacher / Substitute, Add, Download all); the expanded calendar (`/app/scheduling/schedules/calendar`, one day at a time on a phone); a "Weekly schedule" card on the subscription page (status badge with Activate / Restore, substitutions with Remove); "Substitute for {teacher}" on session rows and the Today board. New area file `schedules.json`.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod, i18next, Radix UI; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b2g-weekly-schedules-design.md` (slice B2g of the phase spec; approved; rulings summarised in `../_ledger/orchestration/phases/B2.md` "B2g spec"). It builds on Plan 4 (slots, generation, untouched sessions, regenerating callers, renewal, Today), Plan 7 (payroll pays `session.teacher`), Plan 13 (switches, FT-4), B2a (lock order), B2b (postponed sessions, the teacher-change move), B2c (activity log), B2d (archives: the same live filter in generation), B2e (availability warnings), B2f (bundles, current members, `member_id`). Ledger decisions **D6** (one Session row per group student), **D8 / D9** (kinds, `pays_teacher`), **D14** (archives: B2g leaves archived rows out only of its own office lists), **D15** (`member_id`), **D25** (`ValidationError.code`), **D34** (dot-form row keys — B2g has none), **D35** (B2g sends no `price_minor`). Where this plan fills a gap in the spec, the Plan rulings below say so.

## Global Constraints

**Repos and branches**
- Meta worktree: `/home/abdulkhalek/Projects/etqan_tutor-wt/b2` (`$W`). Meta, `backend/` and `dashboard/` are on `feat/b2g-schedules`, created by the controller off `origin/master` (meta) and `origin/main` (submodules) after B2f merged. `marketing/` is untouched.
- Commit in the submodule that owns the file (`git -C $W/backend …`, `git -C $W/dashboard …`). Never run `git submodule update` (or any writing `git submodule` subcommand) in this worktree.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` (this overrides any attribution line a harness suggests).
- Never edit `STATE.md`, CI workflows, Caddyfiles, or meta's submodule pointers.

**Commands (the slot-1 stack must be up: `just dev-backend`)**
- From `$W`, load the stream's environment first: `cd /home/abdulkhalek/Projects/etqan_tutor-wt/b2; set -a; . ./.env.stream; set +a`. Then run docker compose **directly** (a `$DC` variable does not word-split in zsh). `…` below stands for `docker compose -f docker-compose.local.yml`:
  - Backend tests: `… exec -T django pytest -q <paths>` (add `--create-db` once after the migration).
  - Backend format: `… exec -T django ruff check --fix .` then `… exec -T django ruff format .`
  - Backend verify: `… exec -T django ruff check .`, `… exec -T django ruff format --check .`, `… exec -T django lint-imports`, `… exec -T django pytest -q --cov=etqan`
  - Migration: `… exec -T django python manage.py makemigrations scheduling --name weekly_schedules` (Task 1). Trunk's scheduling leaf after B2f is `0011_bundles_groups`, so this is `0012_weekly_schedules`.
  - Dashboard tests: `… exec -T dashboard pnpm exec vitest run <paths>`; verify: `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`, `… exec -T dashboard pnpm test:coverage`. Format first with `… exec -T dashboard pnpm exec biome check --write src e2e`.
  - New route files: regenerate `src/routeTree.gen.ts` with `… exec -T dashboard pnpm exec vite build` before `tsc` (generated: never hand-edit, never hand-merge).
  - Seeding this stream: `just _stack-manage migrate_schemas`, `just _stack-manage seed_dev`. E2E only through `just e2e …` (it runs `--workers=1 --retries=1`).
  - Slice gates: `just test`, `just lint`, `just e2e`.
- There is no host `.venv` or `node_modules`; never run `manage.py`, `migrate` or pytest against any other database.
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE`, `ERA`, `SLF`, `C901` (10), `E501` (88). Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §7)`. Imports are one per line (`from x import a` / `from x import b`), as every trunk file does. A boolean keyword argument is keyword-only (`*,` before it), or FBT fires. Where a line here exceeds 88 characters, `ruff format` wraps it — never shorten a name to dodge it.
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: semantic colour tokens only (`bg-secondary`, `text-muted-foreground`, `border-border`, `text-primary-text` …), never a literal colour — the checker also rejects `"#123456"`-like literals inside tests. Biome rejects `role="group"` on a div (use `<fieldset>` + `<legend>`) and an implicit-`any` `let`.

**TDD and reports (lessons from Plans 21, 25, 31, 33 and 37)**
- Every task runs its new tests before the implementation and keeps the failing output (RED) for the report, then the passing output (GREEN). A report without RED evidence is sent back.
- Trunk helper names: the root `staff_for(*codes)` fixture (an `APIClient`; the user is `client.user`), `api_for("admin")`, `set_features(**switches)` (also `academy=`), `tenants.other`; scheduling's conftest: `clock` (`clock.set(datetime)`), `world` (`teacher`, `student` — Users — `course`, `package`), `subscribe(**overrides)`, `make_admin`, `make_teacher`, `make_student`, `hand_session(sub, *, occurs_on, start=time(10, 0), **fields)`, `two_slots()`, `subscription_for(world, **o)`, `course_teacher(world, name)`, `postponed(sub, to=, on=)`, `as_user(user)`, `archives_on`, `availability_on`, `MONDAY`, `WEDNESDAY`; B2f's `other_course`, `bare_bundle`, `row`, `make_group`, `make_family`, `group_bundle`, `multi_bundle`, `member_of`, `bundles_on`. The clock starts at Monday 1 June 2026 08:00 UTC; the academy is on UTC with a 14-day horizon and 7 grace days, so `two_slots()` (Mon + Wed 18:00) generates 1, 3, 8, 10 and 15 June. Shared test helpers go once in scheduling's conftest (Plan 25 ruling Q4): this plan adds `substitute`, `set_schedule`, `WEEK_2` and the fixtures `schedules_on` and `hamza` (Task 1) there and nowhere else. `first_table(sql)` and `selects(action)` stay two-line local helpers per test file.
- `etqan/platform/tests/test_features.py`'s `BUILT` dict lists every built switch **in registry order**: `weekly_schedules` is a new line under `# ── phase B2 ──` right after `group_subscriptions`. Same commit as the registry.
- `etqan/access/tests/test_routes.py`: every new route joins `ROUTES`; gated ones join `FEATURES`; `FEATURE_WORDS` gets the six `/schedules/<action>/` words; `schedules/activate/` and `schedules/restore/` join `UNGATED`. **Insert** into the current lists and dicts under a `# Slice B2g.` comment after B2f's lines; never paste them whole. The one existing line edited is the `/bundles/` filter of `test_every_bundle_route_is_gated_or_listed_as_ungated` (plan D18).
- `dashboard/src/routes/permissions.test.ts`: **insert** `scheduling\/schedules|` into the current `FEATURE_WORDS` regex; add the two new screens to `FEATURE_SCREENS` under a `// Slice B2g` comment.
- Non-office callers of every schedule route get 404 from `OfficeOr404` (B2c's, `api/activity_views.py`) listed **before** `HasCode`; a switched-off feature answers 404 **after** the permission check (`FeatureOn` last).
- A list or read that renders rows carries a query-count test that counts **SELECTs only** (`sql.lstrip().upper().startswith("SELECT")`), the same for 1 and 3 rows.
- A lock-order test captures the SQL and asserts the bundle lock's form `…FOR NO KEY UPDATE` first and the subscriptions' `…ORDER BY 1 ASC FOR UPDATE` after it (Plan 31's form: `values_list("pk")` after `order_by("pk")`).
- After a lock, a row that is gone is a `NotFoundError` (404) or — for ids sent in a body — a `ValidationError` on that body key (400), never a 500.
- Scheduling code and tests may not import `etqan.identity.models`, `etqan.catalogue.models` or `etqan.site` (import-linter); go through `identity_services` / `catalogue_services`. Querying across a relation (`teacher__user__full_name`) is not an import and is allowed. The tenants seed tests read scheduling only through `etqan.scheduling.services`.
- Forms: never call `watch()` at a form's root (the dialogs here need no watched value at all); a value a child shows goes through `useWatch` in that child, as `SlotFields` does.
- A pre-filled `<select>` whose options load later keeps its value (ruling S10): render one stable keyed option for the kept id and filter that id out of the loaded list (`TermFields`'s pattern). The calendar's `?teacher=` / `?student=` selects (Task 15) are this case.
- A table whose headers are `sr-only` sits in a `relative overflow-x-auto` wrapper, so the phone-width check never finds the hidden text pushing the page sideways.
- The dashboard never restates a server rule: which bulk action applies to a row is the server's answer (a refusal is shown, translated, naming the subscription the server names); who may join a list is the server's candidates; the subscription card shows exactly the status the server sends.
- Outside the app shell every switch counts as on and every code is held (`useHasFeature` / `useCan` allow all): a test rendering a touched page must mock every API call that page now makes (`scheduleApi` as well as `schedulingApi`).
- Async router mount: in tests, the first query after `renderWithRouter` is a `findBy*`; a negative check (`queryBy… → null`) waits for a sibling marker first.

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; `demo` admin `admin@demo.test` ("Demo Academy Admin"). Demo has every built switch on (`seed_dev.FEATURES`).

**Orchestration rules**
- Shared lists: lines only under `── phase B2 ──` (feature registry — one new line; `test_features.BUILT`; the access registry's `weekly_schedule` resource; the dashboard nav's B2 block; `seed_dev`'s B2 block calls `b2.seed_schedules`). No new app: `TENANT_APPS`, `config/api_router.py` (scheduling's routes live in `etqan/scheduling/api/urls.py`, B2's) and `pyproject.toml`'s import contracts are unchanged.
- Files outside `etqan.scheduling` / the scheduling dashboard feature that this plan touches: `backend/etqan/platform/features.py` (+ test); `backend/etqan/access/registry.py` and `tests/test_routes.py`; `backend/etqan/tenants/seeds/b2.py`, `management/commands/seed_dev.py` (B2 block) and `tests/test_seed_b2.py` (a new test; no existing seed test changes, plan D19); `dashboard/src/features/identity/schemas.ts` (`FeatureCode`); `dashboard/src/features/shell/nav.ts` (+ test); `dashboard/src/routes/permissions.test.ts`.
- New translation area: `dashboard/src/locales/{en,ar}/schedules.json`, holding its keys directly (the catalogue wraps each file under its name). `errors.json`'s `scheduling` codes and `sessionActivity.json`'s `fields` are B2's and edited in place. No `es` file (ledger D22). A count that needs a plural uses the `trials.json` / `twoFactor.json` pattern — `_one` / `_other` in English, all six forms (`_zero` … `_other`) in Arabic — which the key-equality test compares as one key; every other string is plural-free.
- New e2e spec: `dashboard/e2e/b2-schedules.spec.ts`, owning its stamped data, safe to run twice on one database, no faked time, asserting durable state (rows, URLs, statuses after reload), never a transient toast.
- Migrations are additive (phase B2-16). Never `makemigrations --merge`; on a clash after a rebase, delete this plan's migration and regenerate it.
- Service signature changes are additive only: `create_subscription(..., schedule_status=None, substitutions_from=None)`; `GenerationResult.skipped_stopped` (a new field with a default); `filter_subscriptions` is untouched. Every other function is new.

**Lock order (binding, spec §4; plan rulings D1, D11, D12)**
- Bundles (`SELECT … ORDER BY … ASC FOR NO KEY UPDATE`, one statement, id order) → every subscription acted on (the plain ids and every member of those bundles) in one `SELECT … ORDER BY 1 ASC FOR UPDATE`, with B2f's second pass for a member that committed meanwhile → (inside the per-subscription services) their sessions (Plan 4). Every schedule action takes both locks before any per-subscription call; the per-subscription services only re-lock rows already held.
- `remove_substitution` locks the subscription's bundle first when it has one (`FOR NO KEY UPDATE`, as B2f's `delete_subscription`), then the subscription, then reads the substitution again.

**API and data rules (spec values verbatim)**
- Status values `active` (default) · `stopped` · `deleted`; a bundle row's status is the members' common status, or `mixed`.
- 409 bodies `{detail, code}`; a refusal inside a schedule action keeps its status, code and field and adds `member_id` = the refusing subscription's id. New code: `scheduling.schedule_deleted` ("This schedule is deleted. Restore it first.").
- Switch (built, off by default, group `teaching`): `weekly_schedules`.
- Substitution: subscription, teacher, `from_date`, `to_date` (required, at most 366 days); ranges of one subscription never overlap; generated sessions only.
- Access: resource `weekly_schedule` ("Weekly schedules" / "الجداول الأسبوعية", `verbs=ALL_VERBS`), in use `view_any`, `update`, `delete`, `restore`. List, CSV, calendar: `weekly_schedule.view_any`; stop, activate, bulk teacher, add and remove a substitution, the Add candidates: `weekly_schedule.update`; delete: `weekly_schedule.delete`; restore: `weekly_schedule.restore`.

## Plan rulings (where the spec is silent, contradictory or leaves a choice)

- **D1 — A bundle row acts on its schedule members: every member that is current (no renewal row, B2f F-5) or still live.** The spec says "current members"; but an old link whose renewal has not started is still live and still generates until the renewal's start (`generation_last_day`), so stopping only the current members would leave a "stopped" bundle teaching for weeks. Stop, delete, activate and restore apply to every schedule member; the bulk teacher change and a substitution apply to the live ones among them, and a bundle with none live is 409 `scheduling.not_allowed_in_status` ("Nothing in this bundle is live.", no `member_id`). The row's status is the common status of its schedule members, else `mixed`. **A subscription id that names a bundle member acts on that member alone** (the subscription page's Activate / Restore, the seeds): the list itself sends `bundle_ids` for a bundle row, so changing a group class from the list changes the whole class, and a member changed alone diverges from its class (a known limit, as B2f's "one row moved alone").
- **D2 — Every refusal inside a schedule action names the refusing subscription with `member_id`**, plain subscriptions included (the spec's "(400, `member_id`)"), through B2f's `each_member`; every action is all or nothing.
- **D3 — Transitions.** Stop and activate refuse a deleted schedule (409 `scheduling.schedule_deleted`, `member_id`); delete accepts active and stopped; restore changes only deleted schedules (any other target is left as it is); setting the status a schedule already has is a no-op (no `schedule_changed_*` write). The bulk teacher change and a new substitution refuse a deleted schedule too (it is put away: restore it first). `add_slots` and `update_slot` refuse it (spec G-3); `delete_slot` stays allowed (it only removes a slot without sessions). None of these refusals depends on the switch: restore is ungated, so nothing is stuck (FT-4).
- **D4 — Generation honours `schedule_status` and the substitutions whatever the switch says** (spec G-13's deploy note: only the previous release ignores them).
- **D5 — `skipped_stopped` counts schedules, not slot dates:** the live, unarchived subscriptions in the run's scope (one, or all) that have an active slot and whose schedule is not `active`. The other `skipped_*` numbers count dates; this one says how many timetables the run left out.
- **D6 — A substituted generated session's meeting link is the slot's own, else the substitute's default link** (the regular teacher's room is theirs).
- **D7 — A substitution naming the subscription's own teacher is ignored by generation** (it can arise after a teacher change: the substitute became the regular teacher). B2b's postponed move (G-7): a postponed session without `substitute_for` takes the new teacher; one with it keeps its substitute and takes the new teacher as `substitute_for` — unless its substitute *is* the new teacher, then `substitute_for` is cleared. Each row is logged `teacher_moved` with the field it changed (`teacher_id` or `substitute_for_id`).
- **D8 — Substitution checks, in order:** dates first, before any lock and without `member_id` — `to_date < from_date` → 400 on `to_date`; more than 366 days → 400 on `to_date`; `from_date` before the academy's today → 400 on `from_date`. Then per subscription, under the locks, with `member_id`: deleted → 409 `scheduling.schedule_deleted`; not live → 409 `scheduling.not_allowed_in_status`; the teacher unknown, inactive or not one of the course's teachers → 400 on `teacher_id`; the subscription's own teacher → 400 on `teacher_id`; overlapping another range of that subscription → 400 on `from_date`.
- **D9 — The regenerated window of an added or removed substitution.** The spec's "`generate(from_date, to_date, subscription=s)` (within the generating window)" is not what `generate` does (it creates any range it is given). Here: the untouched generated sessions dated `max(from_date, today)` to `to_date` are deleted, and the same subscription is generated from `max(from_date, today)` to the later of `min(to_date, today + horizon)` and the last deleted date — so a range run's sessions beyond the horizon come back with the right teacher, and nothing else beyond the horizon is created (the daily job reaches those dates with the substitution in force).
- **D10 — `create_subscription` gains `schedule_status=None` (None: active) and `substitutions_from=None`.** With `substitutions_from`, the source's substitutions overlapping the new term (`to_date ≥ starts_on`, `from_date ≤` the new term's grace end) are copied unchanged before the horizon is generated, so the new term's first sessions already have the substitute. Renewal passes `stopped` for a stopped schedule (else active: a deleted one starts active, G-9) and the old subscription; `add_to_group_bundle` passes the template's status exactly and the template (G-9; the substitutions too, or the newcomer's row would clash with its own class's substitute).
- **D11 — `remove_substitution(substitution)` takes no `by`** (nothing records it: B2c C-3 / C-9 log no creation or deletion; Plan 33 D4: an unused argument is noise). It locks the bundle when the subscription has one, then the subscription, then reads the substitution again (gone → 404). Removing one from a deleted schedule is allowed (it regenerates nothing).
- **D12 — `lock_schedules(subscription_ids, bundle_ids)`** is the one lock (see Lock order). Ids are deduplicated; none at all → 400 on `subscription_ids`; a bundle id not found → 400 on `bundle_ids`; a subscription id not found after the lock → 400 on `subscription_ids`. A body holds at most 200 ids of each kind (as `ArchiveInput`).
- **D13 — The list.** A schedule is a subscription with at least one slot (any slot; its lines are its active slots) that is current or still live — D1's rule, applied to plain subscriptions too (review I-3), so a renewed link drops out of the list once it has ended instead of piling up in the default Active tab. A plain subscription is one row; a bundle is one row of its schedule members with a slot (D1). A bundle row matches when any of its schedule members matches the tab and the filters. Tabs: `active` (default), `stopped`, `deleted`, `live_subscription` (active or paused), `ended_subscription` (expired or cancelled), `all`. Filters: `q` (the student's name — added so a person can find a row, as every other list has), `student` and `teacher` (User ids; the teacher is the subscription's), `kind` (`single` — not in a bundle — or a bundle kind: TH's "subscription type"), `group` (a study group id). Newest first: a row's head is its lowest-id matching member, rows ordered by head id descending. A group bundle's identical lines (same weekday, start, minutes, course and teacher) collapse to one with no student; a family bundle's lines name their student; a row's substitutions are its members' current and future ones (`to_date ≥ today`), duplicates (same teacher and dates) collapsed. Archived subscriptions are left out while `subscription_archive` is on (spec §5).
- **D14 — Payload shapes.** A row: `{key, subscription_id, bundle: {id, kind, name} | null, student, status, members: [{subscription_id, student, course, teacher, status, schedule_status, sessions_used, sessions_total, carried_over_sessions, extra_sessions, progress}], lines: [{weekday, start_time, end_time, minutes, course, teacher, student}], substitutions: [{teacher, from_date, to_date}]}`; `key` is `subscription-<id>` or `bundle-<id>`; `student` is the row's student (a plain or multi-course row) or null; a bundle's `name` is its student's, family's or study group's name. A calendar entry: `{weekday, start_time, end_time, minutes, course, teacher, student, group, subscription_id, bundle_id}` (a collapsed group entry has `student: null`, `subscription_id: null` and the group's name). Times are `HH:MM` on the academy's clock; `end_time` is the start plus the minutes, wrapping past midnight. CSV columns (G-10): Student, Subscription, Bundle, Schedule status, Weekday (English day name), Start, End, Course, Teacher — one line per active slot of every matching subscription (bundle members are not collapsed).
- **D15 — "Add" is a route of its own:** `GET schedules/candidates/?q=` (code `weekly_schedule.update`, feature `weekly_schedules`) answers up to 20 live subscriptions with no slot whose schedule is not deleted, by student name. The dialog then opens the chosen subscription's page, whose Slots panel is the slot editor (spec §8 "opens its slot editor"); no slot form is duplicated.
- **D16 — Optional payload keys.** `substitute_for` on a session row (and a Today row) appears only on a substituted session and is a `PersonRef` `{id, full_name}`, as `teacher` is (the spec writes `{id, name}`; every person on a session row is `full_name`). Existing payloads otherwise stay as they are, with two spec-mandated changes: `schedule_status` on every subscription row (spec: always), and a Today row's `teacher` follows its session — the session's teacher when the row has one (spec §4), so a substituted row names the substitute. `supervised_row` (My supervision) carries `substitute_for` too: it spreads `session_row`. The office's subscription detail adds `substitutions` (current and future: `[{id, subscription_id, teacher, from_date, to_date}]`), `schedule_changed_at` and `schedule_changed_by`.
- **D17 — Answers.** Stop, delete, activate, restore: 200 `{subscriptions: [ids acted on, ascending]}`. Bulk teacher: 200 `{subscriptions, conflicts, outside_availability?}`. Substitution: 201 `{substitutions, conflicts, outside_availability?}`. Remove: 204. `conflicts` are `[{session, other}]` (P4-9: reported, never blocked) among the re-read untouched generated future sessions of the changed subscriptions (teacher change) or of the substituted ranges (substitution); `outside_availability` is the ids of those sessions outside their teacher's windows, present only while `teacher_availability` is on (E-11's pattern).
- **D18 — Route table.** `test_every_bundle_route_is_gated_or_listed_as_ungated` is widened to `/schedules/` (one edited line and its docstring); `FEATURE_WORDS` gets `/schedules/stop/`, `/schedules/delete/`, `/schedules/teacher/`, `/schedules/substitutions/`, `/schedules/calendar/`, `/schedules/candidates/`. The list's own path has no word: any word for it (`/v1/schedules/`) is also a prefix of the ungated `activate/` and `restore/`.
- **D19 — Seeds** (spec §9): in demo, B2f's multi-course bundle for Zaid Huda is stopped through its bundle row, and Aisha Omar's Quran Memorisation member of the Omar family bundle gets Ustadh Bilal for Ustadha Maryam from next Monday to the Sunday after (inside the 14-day horizon). Both act on B2f's seeded bundles, so no subscription is added: `test_seed_dev.py` and `test_seed_staging.py` count non-bundle subscriptions and stay untouched; the stop only removes sessions (Saturday 13:00 and 15:00), and the substitution moves one Saturday's 11:00 lesson to Bilal, whose Saturdays are otherwise 09:00 only. Markers: `has_stopped_schedules()` and `has_substitutions()`, each step its own transaction. A missing bundle returns quietly (B2f's seed is patched out in `test_seed_dev_skips_a_subscription_whose_teacher_was_deactivated`, which counts printed `skip:` lines); a refused step prints its `skip:`. Seeds call the services, which never check the switch; demo has it on anyway.
- **D20 — Dashboard files** live in `features/scheduling` (B2's): `scheduleSchemas.ts`, `scheduleApi.ts` (tests mock it apart from `./api`), `scheduleQueries.ts`, `scheduleRefusal.ts` and the components. `ScheduleStatus` and `Substitution` are declared in `schemas.ts` beside `Subscription` (no circular import). The calendar route validates `?teacher=&student=` (positive integers); the list's "Expanded calendar" link carries the list's teacher filter (the list filters students by name, plan D13).
- **D21 — The subscription page's "Weekly schedule" card** shows while the schedule is not active or the subscription has substitutions: the badge always (spec FT-4), Activate for a stopped schedule with `weekly_schedule.update`, Restore for a deleted one with `weekly_schedule.restore` (both ungated), and Remove on a substitution with `weekly_schedule.update` while the switch is on (its route is gated).
- **D22 — A schedule refusal shown in the dashboard** is the translated code (or the server's message, or its first field error) prefixed by the subscription the server names: "{student} · {course}: {reason}", from the rows on screen. The reason is B2f's: `refusal.ts` gains `refusalReason(error, t)` (extracted from `refusalText`, which then calls it), and `scheduleRefusal` is a thin wrapper over it.
- **D23 — The e2e** creates its own teachers, course, package, student and subscription (stamped), stops and reactivates the schedule from the list, reads the subscription page's upcoming sessions after each reload, then gives next week to the second teacher and finds "Substitute for {first teacher}" on next week's rows of the sessions list.
- **D24 — Rebase note (ledger R2 / D23 / D35).** B3d adds `currency=` to `create_subscription` and `renew_subscription` and touches `add_to_group_bundle`'s price; B2g adds `schedule_status=` / `substitutions_from=` to `create_subscription` and two keyword arguments to the `create_subscription` calls inside `renew_subscription` and `add_to_group_bundle`. Whichever lands second keeps both sets of keyword arguments. B2g adds no new create or renew caller: its only call sites are those two existing ones; the seeds create no subscription; no B2g form sends `price_minor` (D35 holds). The same keep-both rule covers B3e's R3, which inserts `claim_session_for_balance` into `services/__init__.py`'s imports and `__all__` beside B2g's exports, and `dashboard/src/test/scheduling-fixtures.ts`, which B3d and B2g both extend.

## Review Focus

- **A stopped bundle whose renewal has not started.** Expected: stopping the bundle row stops the old link too, so no lesson of the old term is generated or kept after today. Test: Task 4 `test_a_bundle_row_stops_its_old_link_and_its_pending_renewal`.
- **A substitution and every regenerating caller.** Expected: a pause, a slot edit, a start-date edit, a teacher change and a renewal each recreate the range's lessons with the substitute, never a duplicate date, and postponed or hand-added lessons keep their teacher. Tests: Task 5 `test_regenerating_callers_keep_the_substitute` (parametrised), `test_postponed_and_hand_added_sessions_keep_their_teacher`; Task 3 `test_a_renewal_copies_the_substitutions_overlapping_its_term`.
- **A teacher change onto the substitute.** Expected: no session ends with `teacher == substitute_for`; a postponed lesson's substitute that becomes the regular teacher loses the label. Tests: Task 2 `test_a_substitution_naming_the_regular_teacher_is_ignored`; Task 6 `test_a_postponed_lesson_whose_substitute_becomes_the_teacher_loses_the_label`.
- **One bad schedule in a bulk action.** Expected: nothing changes, the answer names that subscription. Tests: Task 4 `test_one_deleted_schedule_refuses_the_whole_stop`; Task 6 `test_the_teacher_change_is_all_or_nothing`.
- **A substitution beyond the horizon after a range run.** Expected: the range run's later lessons come back with the substitute, and nothing past the horizon is created otherwise. Test: Task 5 `test_a_range_runs_later_sessions_come_back_with_the_substitute`.

---

## File Structure

```
backend/
  etqan/platform/features.py (+tests/test_features.py)           weekly_schedules (Task 1)
  etqan/access/registry.py                                       weekly_schedule under ── phase B2 ── (Task 9)
  etqan/access/tests/test_routes.py                              ROUTES, FEATURES, FEATURE_WORDS, UNGATED (Task 9)
  etqan/scheduling/
    models.py                                                    schedule_status, schedule_changed_*,
                                                                 TeacherSubstitution, Session.substitute_for (Task 1)
    migrations/0012_weekly_schedules.py                          generated (Task 1)
    services/rules.py                                            SCHEDULE, refuse_if_schedule_deleted,
                                                                 covering_substitution, SESSION_RELATED (Tasks 2, 8)
    services/generation.py                                       status filter, substitutes, skipped_stopped (Task 2)
    services/subscriptions.py                                    create kwargs, renewal copies, slot refusals,
                                                                 postponed move with a substitute (Tasks 3, 6)
    services/bundle_actions.py                                   a group newcomer copies the schedule (Task 3)
    services/schedules.py                                        NEW: lock_schedules, status actions (Task 4),
                                                                 bulk_change_teacher (Task 6)
    services/substitutions.py                                    NEW (Task 5)
    services/availability.py                                     sessions_outside (Task 5)
    services/activity.py activity_feed.py                        substitute_for_id logged and named (Task 6)
    services/schedule_reads.py                                   NEW (Task 7)
    services/board.py                                            stopped slots left out, session teacher (Task 8)
    services/__init__.py                                         exports (Tasks 2-8)
    api/payloads.py                                              schedule_status, substitutions, substitute_for,
                                                                 today teacher, skipped_stopped (Tasks 2, 8)
    api/serializers.py schedule_payloads.py schedule_views.py    NEW bodies, shapes, views (Task 9)
    api/urls.py                                                  routes (Task 9)
    tests/conftest.py                                            helpers (Task 1)
    tests/test_schedules_*.py test_api_schedules.py              NEW (Tasks 1-9)
  etqan/tenants/seeds/b2.py tests/test_seed_b2.py                seed_schedules (Task 10)
  etqan/tenants/management/commands/seed_dev.py                  one call in the B2 block (Task 10)
dashboard/
  src/features/identity/schemas.ts                               FeatureCode + weekly_schedules (Task 11)
  src/features/scheduling/
    schemas.ts                                                   ScheduleStatus, Substitution; schedule_status,
                                                                 substitutions, substitute_for, skipped_stopped,
                                                                 substitute_for_id (Task 11)
    scheduleSchemas.ts scheduleApi.ts scheduleQueries.ts         NEW (Task 11)
    scheduleRefusal.ts                                           NEW (Task 14)
    SubstituteChip.tsx (+test)                                   NEW (Task 12)
    SessionsList.tsx SessionsPanel.tsx TeacherSessionTable.tsx
    FamilySessions.tsx SessionPage.tsx SimpleSessions.tsx
    FamilyHome.tsx MissingReports.tsx MySupervision.tsx
    TodayBoard.tsx GenerateDialog.tsx                            the chip, Today's teacher, skipped_stopped (Task 12)
    refusal.ts                                                   refusalReason extracted (Task 14)
    SchedulesList.tsx AddScheduleDialog.tsx (+tests)             NEW (Task 13)
    ScheduleActions.tsx ScheduleTeacherDialog.tsx
    SubstituteDialog.tsx (+tests)                                NEW (Task 14)
    ScheduleCalendar.tsx (+test)                                 NEW (Task 15)
    ScheduleStatusCard.tsx (+test) SubscriptionDetail.tsx        NEW card, mounted (Task 16)
    index.ts                                                     exports (Tasks 11-16)
  src/features/shell/nav.ts (+nav.test.ts)                       Weekly schedules under ── phase B2 ── (Task 11)
  src/routes/_authed/scheduling.schedules.index.tsx              NEW (Task 11; the list in Task 13)
  src/routes/_authed/scheduling.schedules.calendar.tsx           NEW (Task 11; the grid in Task 15)
  src/routes/permissions.test.ts                                 FEATURE_SCREENS, FEATURE_WORDS (Task 11)
  src/routeTree.gen.ts                                           regenerated (Task 11)
  src/locales/{en,ar}/schedules.json                             NEW (Task 11)
  src/locales/{en,ar}/errors.json sessionActivity.json           one code, one field (Task 11)
  src/test/scheduling-fixtures.ts                                scheduleRow, calendarEntry, substitutionRow;
                                                                 schedule_status on subscriptionRow (Task 11)
  e2e/b2-schedules.spec.ts                                       NEW (Task 17)
```

---
### Task 1: The switch, the schedule status, the substitution table, `Session.substitute_for`, the migration and the test helpers

**Files:**
- Modify: `backend/etqan/platform/features.py` (one line under `# ── phase B2 ──` after `group_subscriptions`)
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT`)
- Modify: `backend/etqan/scheduling/models.py` (`Subscription.ScheduleStatus` and three fields; `TeacherSubstitution` after `ScheduleSlot`; `Session.substitute_for`)
- Create: `backend/etqan/scheduling/migrations/0012_weekly_schedules.py` (generated)
- Modify: `backend/etqan/scheduling/tests/conftest.py` (B2g helpers)
- Test: `backend/etqan/scheduling/tests/test_schedules_model.py`

**Interfaces:**
- Consumes: B2f's `Subscription` (with `bundle`), `ScheduleSlot`, `Session`.
- Produces: feature code `weekly_schedules` (built, default off, group `teaching`). `Subscription.ScheduleStatus{ACTIVE="active", STOPPED="stopped", DELETED="deleted"}`; `Subscription.schedule_status` (max 7, default and `db_default` active), `schedule_changed_at` (nullable datetime), `schedule_changed_by` (→ User, SET_NULL, `related_name="+"`). `TeacherSubstitution(subscription → Subscription CASCADE related_name="substitutions", teacher → identity.TeacherProfile PROTECT related_name="+", from_date, to_date, created_by → User SET_NULL, created_at)` with constraint `scheduling_substitution_dates_in_order`, ordering `["from_date", "id"]`. `Session.substitute_for` (→ identity.TeacherProfile, null, PROTECT, `related_name="+"`). Conftest: `WEEK_2 = (date(2026, 6, 8), date(2026, 6, 14))`, `substitute(subscription, teacher_user, from_date, to_date) -> TeacherSubstitution`, `set_schedule(subscription, status) -> Subscription`, fixtures `schedules_on` and `hamza` (a second teacher of the course, a User).

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_schedules_model.py`)

```python
"""Slice B2g §3: the schedule's status on the subscription, the substitution
record and the switch."""

from datetime import date

import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.platform import features
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import TeacherSubstitution
from etqan.scheduling.tests.conftest import WEEK_2
from etqan.scheduling.tests.conftest import course_teacher
from etqan.scheduling.tests.conftest import set_schedule
from etqan.scheduling.tests.conftest import substitute


def test_a_new_subscriptions_schedule_is_active(subscribe):
    sub = subscribe()
    stored = Subscription.objects.filter(pk=sub.pk).values_list(
        "schedule_status", flat=True
    )
    assert (sub.schedule_status, stored.get()) == ("active", "active")
    assert (sub.schedule_changed_at, sub.schedule_changed_by) == (None, None)


def test_set_schedule_writes_the_status_straight(subscribe):
    assert set_schedule(subscribe(), "stopped").schedule_status == "stopped"


def test_a_substitution_ends_on_or_after_its_start(subscribe, world):
    sub = subscribe()
    hamza = course_teacher(world)
    with pytest.raises(IntegrityError), transaction.atomic():
        substitute(sub, hamza, date(2026, 6, 9), date(2026, 6, 8))


def test_substitutions_go_with_their_subscription(subscribe, world):
    sub = subscribe()  # no slots: no sessions protect it
    made = substitute(sub, course_teacher(world), *WEEK_2)
    assert list(sub.substitutions.all()) == [made]
    sub.delete()
    assert not TeacherSubstitution.objects.exists()


def test_the_weekly_schedules_switch_is_built_and_off_by_default():
    found = next(f for f in features.REGISTRY if f.code == "weekly_schedules")
    assert (found.built, found.default, found.group) == (True, False, "teaching")
    assert "weekly_schedules" in features.BUILT
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_model.py`
Expected: FAIL — `ImportError: cannot import name 'TeacherSubstitution'`.

- [ ] **Step 3: Implement**

`backend/etqan/platform/features.py` — under `# ── phase B2 ──`, right after the `group_subscriptions` `Feature(...)`:

```python
    # Slice B2g (Plan 41): weekly schedules, off by default; activate and
    # restore stay ungated so nothing is stuck while it is off (spec G-13).
    Feature(
        "weekly_schedules",
        "Weekly schedules",
        "الجداول الأسبوعية",
        "teaching",
        built=True,
    ),
```

`backend/etqan/platform/tests/test_features.py` — in `BUILT`, right after `"group_subscriptions": False,`:

```python
    "weekly_schedules": False,
```

`backend/etqan/scheduling/models.py` — inside `class Subscription`, after `class DurationUnit`:

```python
    class ScheduleStatus(models.TextChoices):
        """Slice B2g §3 (G-1, G-2): the subscription's weekly schedule — its
        slot set — is active, stopped, or put away ("deleted", G-3)."""

        ACTIVE = "active", "Active"
        STOPPED = "stopped", "Stopped"
        DELETED = "deleted", "Deleted"
```

and after the `bundle` field:

```python
    # Slice B2g §3: the schedule's status and who last changed it. A
    # database default (B2-16): a row the previous release inserts is active.
    schedule_status = models.CharField(
        max_length=7,
        choices=ScheduleStatus.choices,
        default=ScheduleStatus.ACTIVE,
        db_default=ScheduleStatus.ACTIVE,
    )
    schedule_changed_at = models.DateTimeField(null=True, blank=True)
    schedule_changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
```

After `class ScheduleSlot` (before `class TrialRequest`):

```python
class TeacherSubstitution(models.Model):
    """Slice B2g §3 (G-5): a substitute teaches a subscription's generated
    sessions dated ``from_date`` to ``to_date``. Generation reads it, so
    every regenerating caller (pause, slot or term edit, teacher change,
    renewal) recreates those sessions with the substitute. No two ranges of
    one subscription overlap (checked in the service, under its lock)."""

    subscription = models.ForeignKey(
        Subscription, on_delete=models.CASCADE, related_name="substitutions"
    )
    teacher = models.ForeignKey(
        "identity.TeacherProfile", on_delete=models.PROTECT, related_name="+"
    )
    from_date = models.DateField()
    to_date = models.DateField()
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["from_date", "id"]
        indexes = [models.Index(fields=["subscription", "from_date"])]
        constraints = [
            models.CheckConstraint(
                condition=Q(from_date__lte=F("to_date")),
                name="scheduling_substitution_dates_in_order",
            )
        ]

    def __str__(self):
        return f"TeacherSubstitution<{self.from_date}..{self.to_date}>"
```

In `class Session`, after the `trial` field:

```python
    # Slice B2g §3 (G-5): the regular teacher a substitute stands in for;
    # `teacher` is then the substitute (payroll pays `teacher`, Plan 7).
    substitute_for = models.ForeignKey(
        "identity.TeacherProfile",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
```

`backend/etqan/scheduling/tests/conftest.py` — add `from etqan.scheduling.models import Subscription` and `from etqan.scheduling.models import TeacherSubstitution` to the imports, and append after B2f's `bundles_on` fixture:

```python
# Slice B2g: helpers the schedule tests share. The second week of the
# clock's June: Monday 8 to Sunday 14 (two_slots() generates 8 and 10).
WEEK_2 = (date(2026, 6, 8), date(2026, 6, 14))


def substitute(subscription, teacher, from_date, to_date):
    """A substitution written straight to the table (``teacher`` is a User),
    for tests whose subject is not `add_substitution`. Nothing is
    regenerated."""
    return TeacherSubstitution.objects.create(
        subscription=subscription,
        teacher=teacher.teacher_profile,
        from_date=from_date,
        to_date=to_date,
    )


def set_schedule(subscription, status):
    """``subscription``'s schedule status written straight to the table, for
    tests whose subject is not the status actions. Sessions are untouched."""
    Subscription.objects.filter(pk=subscription.pk).update(schedule_status=status)
    subscription.refresh_from_db()
    return subscription


@pytest.fixture
def schedules_on(set_features):
    """Slice B2g: the weekly schedules switch on (off by default)."""
    set_features(weekly_schedules=True)


@pytest.fixture
def hamza(world):
    """Slice B2g: Hamza, a second teacher of ``world``'s course — the
    substitute in most schedule tests."""
    return course_teacher(world)
```

Generate the migration: `… exec -T django python manage.py makemigrations scheduling --name weekly_schedules`. Read it: it adds three fields to `subscription`, one to `session`, creates `teachersubstitution` with its index and constraint, and alters nothing else. Then `… exec -T django pytest -q --create-db etqan/scheduling/tests/test_schedules_model.py`.

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_model.py etqan/platform`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/platform/features.py etqan/platform/tests/test_features.py etqan/scheduling/models.py etqan/scheduling/migrations/0012_weekly_schedules.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_schedules_model.py
git -C $W/backend commit -m "feat(scheduling): schedule status, teacher substitutions and the weekly_schedules switch (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 2: Generation honours the status and gives substitutes their sessions

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (a `Weekly schedules (slice B2g)` section after the archives section)
- Modify: `backend/etqan/scheduling/services/generation.py` (`GenerationResult`, `_new_session`, `_lock_live`, `generate`)
- Modify: `backend/etqan/scheduling/api/payloads.py` (`generation_result`)
- Test: `backend/etqan/scheduling/tests/test_schedules_generation.py`

**Interfaces:**
- Consumes: Task 1's fields and conftest helpers.
- Produces: `rules.SCHEDULE` (= `Subscription.ScheduleStatus`), `rules.WEEKLY_SCHEDULES = "weekly_schedules"`, `rules.SCHEDULE_DELETED` (message), `rules.refuse_if_schedule_deleted(subscription) -> None` (409 `scheduling.schedule_deleted`), `rules.covering_substitution(subscription, day) -> TeacherSubstitution | None` (reads the prefetched `substitutions`; ignores one naming the subscription's teacher, plan D7). `GenerationResult.skipped_stopped: int = 0`. Generated sessions inside a substitution: `teacher` = the substitute, `substitute_for` = the subscription's teacher, `meeting_url` = the slot's, else the substitute's default (D6). The range-run answer gains `"skipped_stopped"`.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_schedules_generation.py`)

```python
"""Slice B2g §4 Generation: a stopped or deleted schedule generates nothing,
and a date inside a substitution goes to the substitute (G-2, G-5)."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.catalogue import services as catalogue_services
from etqan.scheduling import services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import WEDNESDAY
from etqan.scheduling.tests.conftest import WEEK_2
from etqan.scheduling.tests.conftest import course_teacher
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import set_schedule
from etqan.scheduling.tests.conftest import substitute
from etqan.scheduling.tests.conftest import two_slots

JUNE_1 = date(2026, 6, 1)
JUNE_30 = date(2026, 6, 30)


def teachers(sub):
    return list(
        Session.objects.filter(subscription=sub)
        .order_by("occurs_on")
        .values_list("occurs_on", "teacher_id", "substitute_for_id")
    )


def selects(action) -> int:
    with CaptureQueriesContext(connection) as ctx:
        action()
    return sum(
        q["sql"].lstrip().upper().startswith("SELECT") for q in ctx.captured_queries
    )


def test_a_stopped_or_deleted_schedule_generates_nothing(subscribe):
    for status in ("stopped", "deleted"):
        sub = set_schedule(subscribe(student_id=make_student(status).id), status)
        ScheduleSlot.objects.create(
            subscription=sub, weekday=MONDAY, start_time=time(9), minutes=45
        )
        assert services.generate_horizon(sub).created == 0
        assert services.run_lifecycle()["created"] == 0
        assert not Session.objects.filter(subscription=sub).exists()


def test_a_range_run_counts_the_schedules_it_left_out(subscribe):
    active = subscribe(slots=two_slots())
    stopped = subscribe(student_id=make_student("Aisha").id, slots=two_slots(time(9)))
    set_schedule(stopped, "stopped")
    Session.objects.filter(subscription=stopped).delete()
    # One without an active slot is no schedule the run could have made.
    idle = set_schedule(subscribe(student_id=make_student("Zaid").id), "stopped")
    result = services.generate(JUNE_1, JUNE_30)
    assert result.skipped_stopped == 1
    assert not Session.objects.filter(subscription__in=[stopped, idle]).exists()
    assert services.generate(JUNE_1, JUNE_30, subscription=active).skipped_stopped == 0
    assert services.generate(JUNE_1, JUNE_30, subscription=stopped).skipped_stopped == 1


def test_regenerating_a_stopped_schedule_only_removes(subscribe):
    sub = set_schedule(subscribe(slots=two_slots()), "stopped")
    services.update_slot(sub.slots.get(weekday=MONDAY), start_time=time(19))
    assert not Session.objects.filter(subscription=sub, occurs_on__week_day=2).exists()
    assert Session.objects.filter(subscription=sub, occurs_on=date(2026, 6, 3)).exists()


def test_sessions_in_a_substitution_get_the_substitute(subscribe, world):
    hamza = course_teacher(world)
    sub = subscribe()
    substitute(sub, hamza, *WEEK_2)
    services.add_slots(sub, weekdays=[MONDAY, WEDNESDAY], start_time=time(18))
    regular = world.teacher.teacher_profile.pk
    cover = hamza.teacher_profile.pk
    assert teachers(sub) == [
        (date(2026, 6, 1), regular, None),
        (date(2026, 6, 3), regular, None),
        (date(2026, 6, 8), cover, regular),
        (date(2026, 6, 10), cover, regular),
        (date(2026, 6, 15), regular, None),
    ]


def test_a_substitutes_session_uses_the_slot_link_else_theirs(subscribe, world):
    """Plan D6."""
    hamza = make_teacher("Hamza", default_meeting_url="https://meet.test/hamza")
    catalogue_services.update_course(
        world.course, teacher_ids=[world.teacher.id, hamza.id]
    )
    sub = subscribe()
    substitute(sub, hamza, *WEEK_2)
    services.add_slots(sub, weekdays=[MONDAY], start_time=time(18))
    services.add_slots(
        sub,
        weekdays=[WEDNESDAY],
        start_time=time(18),
        meeting_url="https://meet.test/room",
    )
    links = dict(
        Session.objects.filter(subscription=sub, occurs_on__range=WEEK_2).values_list(
            "occurs_on", "meeting_url"
        )
    )
    assert links == {
        date(2026, 6, 8): "https://meet.test/hamza",
        date(2026, 6, 10): "https://meet.test/room",
    }


def test_the_daily_job_gives_later_dates_the_substitute(subscribe, world, clock):
    hamza = course_teacher(world)
    sub = subscribe(slots=two_slots())
    substitute(sub, hamza, date(2026, 6, 22), date(2026, 6, 28))
    later = Session.objects.filter(
        subscription=sub, occurs_on__range=(date(2026, 6, 22), date(2026, 6, 28))
    )
    assert not later.exists()  # beyond today's horizon (15 June)
    clock.set(datetime(2026, 6, 15, 8, 0, tzinfo=UTC))
    services.run_lifecycle()
    assert sorted(later.values_list("occurs_on", "teacher_id")) == [
        (date(2026, 6, 22), hamza.teacher_profile.pk),
        (date(2026, 6, 24), hamza.teacher_profile.pk),
    ]


def test_a_substitution_naming_the_regular_teacher_is_ignored(subscribe, world):
    """Plan D7: a session never has itself as its substitute."""
    sub = subscribe()
    substitute(sub, world.teacher, *WEEK_2)
    services.add_slots(sub, weekdays=[MONDAY], start_time=time(18))
    assert {s for _, _, s in teachers(sub)} == {None}


def test_generation_reads_substitutions_in_the_same_selects_for_one_or_many(
    subscribe, world
):
    hamza = course_teacher(world)

    def schedule(name):
        sub = subscribe(student_id=make_student(name).id)
        substitute(sub, hamza, *WEEK_2)
        ScheduleSlot.objects.create(
            subscription=sub, weekday=MONDAY, start_time=time(9), minutes=45
        )

    schedule("Aisha")
    one = selects(lambda: services.generate(JUNE_1, date(2026, 6, 15)))
    Session.objects.all().delete()
    schedule("Zaid")
    schedule("Huda")
    assert selects(lambda: services.generate(JUNE_1, date(2026, 6, 15))) == one


def test_the_range_run_answer_reports_the_stopped_schedules(api_for, subscribe):
    set_schedule(subscribe(slots=two_slots()), "stopped")
    body = (
        api_for("admin")
        .post(
            "/api/v1/schedule/generate/",
            {"from": "2026-06-01", "to": "2026-06-30"},
            format="json",
        )
        .json()
    )
    assert body["skipped_stopped"] == 1
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_generation.py`
Expected: FAIL — `AttributeError: 'GenerationResult' object has no attribute 'skipped_stopped'`, stopped schedules still generating, sessions keeping the regular teacher.

- [ ] **Step 3: Implement**

`backend/etqan/scheduling/services/rules.py` — add `from etqan.scheduling.models import TeacherSubstitution` to the imports, and after the archives section (`refuse_if_session_archived` … `archivable`), before `covering_pause`:

```python
# ── Weekly schedules (slice B2g) ─────────────────────────────────────────────

WEEKLY_SCHEDULES = "weekly_schedules"
SCHEDULE = Subscription.ScheduleStatus
SCHEDULE_DELETED = "This schedule is deleted. Restore it first."


def refuse_if_schedule_deleted(subscription: Subscription) -> None:
    """G-3, plan D3: a deleted schedule takes no slot change, no stop or
    activation, no teacher change and no substitution — whatever the
    switch says (restore is ungated). Call it on the locked row."""
    if subscription.schedule_status == SCHEDULE.DELETED:
        raise ConflictError(SCHEDULE_DELETED, code="scheduling.schedule_deleted")


def covering_substitution(
    subscription: Subscription, day: date
) -> TeacherSubstitution | None:
    """G-5: the substitution of ``subscription`` covering ``day``. Reads the
    (prefetched) substitutions; one naming the subscription's own teacher is
    ignored (plan D7: a teacher change made the substitute the teacher)."""
    for substitution in subscription.substitutions.all():
        if (
            substitution.from_date <= day <= substitution.to_date
            and substitution.teacher_id != subscription.teacher_id
        ):
            return substitution
    return None
```

`backend/etqan/scheduling/services/generation.py` — add `from django.db.models import Prefetch` and `from etqan.scheduling.models import TeacherSubstitution`; then:

```python
@dataclass
class GenerationResult:
    created: int = 0
    skipped_existing: int = 0
    skipped_paused: int = 0
    skipped_out_of_term: int = 0
    conflicts: list[tuple[Session, Session]] = field(default_factory=list)
    # Slice B2g (plan D5): live schedules the run left out because they are
    # stopped or deleted — a count of schedules, not of dates.
    skipped_stopped: int = 0
```

```python
def _new_session(slot: ScheduleSlot, day: date, tz_name: str) -> Session:
    sub = slot.subscription
    # Slice B2g G-5: a date inside a substitution is the substitute's, who
    # stands in for the subscription's teacher.
    cover = rules.covering_substitution(sub, day)
    teacher = cover.teacher if cover is not None else sub.teacher
    return Session(
        slot=slot,
        subscription=sub,
        student_id=sub.student_id,
        teacher_id=teacher.pk,
        course_id=sub.course_id,
        occurs_on=day,
        starts_at=dates.to_utc(day, slot.start_time, tz_name),
        minutes=slot.minutes,
        # Resolved now (spec §3.5): the slot's link, else the teacher's
        # default — the substitute's when they teach it (plan D6).
        meeting_url=slot.meeting_url or teacher.default_meeting_url,
        # Plan 12b (§3.5): the subscription's supervisor when it is created.
        supervisor_id=sub.supervisor_id,
        substitute_for_id=sub.teacher_id if cover is not None else None,
        generated=True,
    )
```

```python
def _lock_live(subscription: Subscription | None) -> list[int]:
    """Lock the live subscriptions (or just ``subscription``), in id order so
    two lockers never deadlock. Renewal, cancel and expiry lock the same rows,
    so generation waits for them; the status filter is re-checked once a row
    is free, so a subscription ended meanwhile is left out. An archived
    subscription never generates (slice B2d D-3), nor does a stopped or
    deleted schedule (slice B2g G-2, plan D4: whatever the switch says)."""
    live = Subscription.objects.filter(
        status__in=rules.LIVE,
        archived_at__isnull=True,
        schedule_status=rules.SCHEDULE.ACTIVE,
    )
    if subscription is not None:
        live = live.filter(pk=subscription.pk)
    return list(live.order_by("pk").select_for_update().values_list("pk", flat=True))


def _stopped(subscription: Subscription | None) -> int:
    """Plan D5: the live, unarchived subscriptions (or just
    ``subscription``) with an active slot whose schedule is not active."""
    stopped = Subscription.objects.filter(
        status__in=rules.LIVE, archived_at__isnull=True, slots__is_active=True
    ).exclude(schedule_status=rules.SCHEDULE.ACTIVE)
    if subscription is not None:
        stopped = stopped.filter(pk=subscription.pk)
    return stopped.distinct().count()
```

In `generate`, replace `prefetch_related_objects([s.subscription for s in slots], "pauses")` with:

```python
    # Slice B2g G-5: the substitutions with their teachers, once per run.
    prefetch_related_objects(
        [s.subscription for s in slots],
        "pauses",
        Prefetch(
            "substitutions",
            queryset=TeacherSubstitution.objects.select_related("teacher"),
        ),
    )
```

and before `return result`:

```python
    result.skipped_stopped = _stopped(subscription)
```

`backend/etqan/scheduling/api/payloads.py` — in `generation_result`, after `"skipped_out_of_term"`:

```python
        # Slice B2g (plan D5).
        "skipped_stopped": result.skipped_stopped,
```

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_generation.py etqan/scheduling/tests/test_generation.py etqan/scheduling/tests/test_lifecycle.py etqan/scheduling/tests/test_api_schedule.py`
Expected: PASS (the existing generation and lifecycle suites unchanged).

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/rules.py etqan/scheduling/services/generation.py etqan/scheduling/api/payloads.py etqan/scheduling/tests/test_schedules_generation.py
git -C $W/backend commit -m "feat(scheduling): generation skips stopped schedules and gives substitutes their dates (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 3: Renewal and a group newcomer copy the schedule; a deleted schedule's slots are refused

**Files:**
- Modify: `backend/etqan/scheduling/services/subscriptions.py` (`create_subscription`, `_copy_substitutions`, `renew_subscription`, `add_slots`, `update_slot`)
- Modify: `backend/etqan/scheduling/services/bundle_actions.py` (`add_to_group_bundle`)
- Test: `backend/etqan/scheduling/tests/test_schedules_renewal.py`

**Interfaces:**
- Consumes: Task 2's `rules.SCHEDULE`, `rules.refuse_if_schedule_deleted`; B2f's `group_bundle`, `add_to_group_bundle`.
- Produces: `create_subscription(..., schedule_status: str | None = None, substitutions_from: Subscription | None = None)` (additive; plan D10). `renew_subscription` keeps a stopped schedule and copies overlapping substitutions; `add_to_group_bundle` copies the template's status and substitutions. `add_slots` / `update_slot` raise 409 `scheduling.schedule_deleted` on a deleted schedule.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_schedules_renewal.py`)

```python
"""Slice B2g G-3, G-6, G-9: what a renewal and a group newcomer take from
the schedule, and a deleted schedule's slots."""

from datetime import date
from datetime import time

import pytest

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import WEEK_2
from etqan.scheduling.tests.conftest import course_teacher
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import set_schedule
from etqan.scheduling.tests.conftest import substitute
from etqan.scheduling.tests.conftest import two_slots

JUNE_8 = date(2026, 6, 8)


def days(sub):
    return list(
        Session.objects.filter(subscription=sub)
        .order_by("occurs_on")
        .values_list("occurs_on", flat=True)
    )


def test_a_new_subscription_may_start_stopped(world):
    sub = services.create_subscription(
        student_id=world.student.id,
        course_id=world.course.id,
        teacher_id=world.teacher.id,
        package_id=world.package.id,
        starts_on=date(2026, 6, 1),
        slots=two_slots(),
        schedule_status="stopped",
    )
    assert sub.schedule_status == "stopped"
    assert days(sub) == []


def test_a_renewal_keeps_a_stopped_schedule(subscribe):
    old = set_schedule(subscribe(slots=two_slots()), "stopped")
    renewal = services.renew_subscription(old, starts_on=JUNE_8)
    assert renewal.schedule_status == "stopped"
    assert days(renewal) == []


def test_a_renewal_of_a_deleted_schedule_starts_active(subscribe):
    old = set_schedule(subscribe(slots=two_slots()), "deleted")
    renewal = services.renew_subscription(old, starts_on=JUNE_8)
    assert renewal.schedule_status == "active"
    assert days(renewal) == [JUNE_8, date(2026, 6, 10), date(2026, 6, 15)]


def test_a_renewal_copies_the_substitutions_overlapping_its_term(subscribe, world):
    hamza = course_teacher(world)
    old = subscribe(slots=two_slots())
    substitute(old, hamza, date(2026, 6, 1), date(2026, 6, 3))
    substitute(old, hamza, *WEEK_2)
    renewal = services.renew_subscription(old, starts_on=JUNE_8)
    assert list(renewal.substitutions.values_list("from_date", "to_date")) == [
        WEEK_2
    ]
    covered = Session.objects.filter(subscription=renewal, occurs_on__range=WEEK_2)
    assert set(covered.values_list("teacher_id", "substitute_for_id")) == {
        (hamza.teacher_profile.pk, world.teacher.teacher_profile.pk)
    }
    # No duplicate date: the old term's sessions from 8 June went.
    assert not Session.objects.filter(subscription=old, occurs_on__gte=JUNE_8).exists()


def test_a_group_newcomer_copies_the_classes_schedule(world):
    hamza = course_teacher(world)
    created = group_bundle(world, make_student("Aisha"))
    for member in created.members:
        set_schedule(member, "stopped")
        substitute(member, hamza, *WEEK_2)
    joined = services.add_to_group_bundle(
        created.bundle, student_id=make_student("Zaid").id, starts_on=JUNE_8
    )
    assert joined.schedule_status == "stopped"
    assert list(joined.substitutions.values_list("teacher_id", "from_date")) == [
        (hamza.teacher_profile.pk, WEEK_2[0])
    ]
    assert days(joined) == []


def test_a_deleted_schedules_slots_cannot_be_added_or_edited(subscribe):
    sub = set_schedule(subscribe(slots=two_slots()), "deleted")
    with pytest.raises(ConflictError) as added:
        services.add_slots(sub, weekdays=[4], start_time=time(9))
    with pytest.raises(ConflictError) as edited:
        services.update_slot(sub.slots.first(), start_time=time(19))
    assert {added.value.code, edited.value.code} == {"scheduling.schedule_deleted"}


def test_a_deleted_schedules_sessionless_slot_can_still_go(subscribe):
    sub = subscribe()
    slot = ScheduleSlot.objects.create(
        subscription=sub, weekday=4, start_time=time(9), minutes=45
    )
    set_schedule(sub, "deleted")
    services.delete_slot(slot)
    assert not ScheduleSlot.objects.filter(pk=slot.pk).exists()
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_renewal.py`
Expected: FAIL — `TypeError: create_subscription() got an unexpected keyword argument 'schedule_status'`; renewals active; slots of a deleted schedule accepted.

- [ ] **Step 3: Implement**

`backend/etqan/scheduling/services/subscriptions.py` — add `from etqan.scheduling.models import TeacherSubstitution`; add after `copied_slots`:

```python
def _copy_substitutions(source: Subscription, subscription: Subscription) -> None:
    """Slice B2g G-6, G-9 (plan D10): ``source``'s substitutions that overlap
    ``subscription``'s term, unchanged — a renewal's, or a group newcomer's
    from the class's template. Copied before the horizon is generated."""
    grace_ends_on = rules.term(
        subscription, rules.settings().renewal_grace_days
    ).grace_ends_on
    TeacherSubstitution.objects.bulk_create(
        TeacherSubstitution(
            subscription=subscription,
            teacher_id=found.teacher_id,
            from_date=found.from_date,
            to_date=found.to_date,
            created_by_id=found.created_by_id,
        )
        for found in source.substitutions.filter(
            to_date__gte=subscription.starts_on, from_date__lte=grace_ends_on
        )
    )
```

`create_subscription` gains two keyword arguments after `bundle` and uses them:

```python
    bundle: SubscriptionBundle | None = None,
    schedule_status: str | None = None,
    substitutions_from: Subscription | None = None,
) -> Subscription:
    """Spec §4.2 Create: copy the package, add the slots, generate the horizon.
    Its sessions take ``supervisor_id``'s supervisor (Plan 12b §3.5). Slice
    B2e §4.4: with ``trial``, the request and its current session are locked
    and checked first, and the new subscription is linked to it. Slice B2f
    F-3: with ``bundle``, it is that bundle's member. Slice B2g (plan D10):
    its schedule starts ``schedule_status`` (None: active), with
    ``substitutions_from``'s substitutions that overlap its term."""
```

In the body, the `Subscription(...)` constructor gets `schedule_status=schedule_status or Subscription.ScheduleStatus.ACTIVE,` after `bundle=bundle,`; and right after the slots loop, before `generation.generate_horizon(subscription)`:

```python
    if substitutions_from is not None:
        _copy_substitutions(substitutions_from, subscription)
```

In `renew_subscription`, the `create_subscription(...)` call gains, after `bundle=old.bundle,`:

```python
        # Slice B2g G-9 (plan D10): a stopped schedule stays stopped; a
        # deleted one starts active. G-6: the substitutions overlapping the
        # new term come along.
        schedule_status=rules.SCHEDULE.STOPPED
        if old.schedule_status == rules.SCHEDULE.STOPPED
        else None,
        substitutions_from=old,
```

In `add_slots`, after `rules.require_status(locked)`:

```python
    rules.refuse_if_schedule_deleted(locked)  # slice B2g G-3
```

In `update_slot`, right after `locked = _lock_unarchived(subscription.pk)`:

```python
    rules.refuse_if_schedule_deleted(locked)  # slice B2g G-3
```

`backend/etqan/scheduling/services/bundle_actions.py` — in `add_to_group_bundle`, the `create_subscription(...)` call gains, after `bundle=locked,`:

```python
            # Slice B2g G-9 (plan D10): the class's schedule as the template
            # has it — its status and its substitutions.
            schedule_status=template.schedule_status,
            substitutions_from=template,
```

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_renewal.py etqan/scheduling/tests/test_renewal.py etqan/scheduling/tests/test_bundles_roster_archive.py etqan/scheduling/tests/test_subscriptions.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/subscriptions.py etqan/scheduling/services/bundle_actions.py etqan/scheduling/tests/test_schedules_renewal.py
git -C $W/backend commit -m "feat(scheduling): renewals and group newcomers keep the schedule; deleted schedules refuse slot edits (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 4: One lock for many schedules; stop, delete, activate and restore

**Files:**
- Create: `backend/etqan/scheduling/services/schedules.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_schedules_status.py`

**Interfaces:**
- Consumes: Task 2's `rules.SCHEDULE`, `rules.refuse_if_schedule_deleted`, `generation.generate_horizon`; B2f's `bundles.each_member`, `bundles.is_current`, `bundles.refused`, `bundle_actions.NOTHING_LIVE`; conftest `multi_bundle`, `group_bundle`, `set_schedule`, `postponed`, `hand_session`.
- Produces (all in `services`): `Targets(bundles: list[SubscriptionBundle], subscriptions: list[Subscription])`; `lock_schedules(subscription_ids, bundle_ids) -> Targets` (plan D12; rows come with `renewal`, `student__user`, `teacher__user` and `course`); `live_targets(targets) -> list[Subscription]` (plan D1); `stop_schedules(*, by, subscription_ids=(), bundle_ids=()) -> list[int]`, `delete_schedules(...)`, `activate_schedules(...)`, `restore_schedules(...)` — same signature, each answering the ids acted on, ascending (plan D17).

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_schedules_status.py`)

```python
"""Slice B2g §4: stopping, deleting, activating and restoring schedules —
plain subscriptions and bundle rows, all or nothing (G-2, G-3, G-4)."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import multi_bundle
from etqan.scheduling.tests.conftest import postponed
from etqan.scheduling.tests.conftest import set_schedule
from etqan.scheduling.tests.conftest import two_slots

JUNE_1 = date(2026, 6, 1)


def days(sub):
    return list(
        Session.objects.filter(subscription=sub)
        .order_by("occurs_on")
        .values_list("occurs_on", flat=True)
    )


def first_table(sql: str) -> str:
    return sql.split(" FROM ")[1].split()[0]


def fresh(sub):
    return Subscription.objects.get(pk=sub.pk)


def test_stop_removes_the_untouched_future_generated_sessions(subscribe, clock):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 3, 8, 0, tzinfo=UTC))
    marked = Session.objects.get(subscription=sub, occurs_on=date(2026, 6, 8))
    Session.objects.filter(pk=marked.pk).update(student_attendance="excused")
    moved = postponed(sub, to=date(2026, 6, 11), on=date(2026, 6, 10))
    added = hand_session(sub, occurs_on=date(2026, 6, 12))
    admin = make_admin()
    assert services.stop_schedules(by=admin, subscription_ids=[sub.pk]) == [sub.pk]
    stopped = fresh(sub)
    assert (stopped.schedule_status, stopped.schedule_changed_by) == ("stopped", admin)
    assert stopped.schedule_changed_at == datetime(2026, 6, 3, 8, 0, tzinfo=UTC)
    # Monday 1 June is past; 3 June starts at 18:00 today, still to come.
    assert set(days(sub)) == {JUNE_1, date(2026, 6, 8), date(2026, 6, 11), date(2026, 6, 12)}
    assert {marked.pk, moved.pk, added.pk} <= set(
        Session.objects.filter(subscription=sub).values_list("pk", flat=True)
    )


def test_stopping_again_changes_nothing(subscribe):
    sub = subscribe(slots=two_slots())
    services.stop_schedules(by=None, subscription_ids=[sub.pk])
    first = fresh(sub).schedule_changed_at
    services.stop_schedules(by=make_admin(), subscription_ids=[sub.pk])
    assert (fresh(sub).schedule_changed_at, fresh(sub).schedule_changed_by) == (
        first,
        None,
    )


def test_activate_regenerates_a_live_schedule(subscribe):
    sub = subscribe(slots=two_slots())
    services.stop_schedules(by=None, subscription_ids=[sub.pk])
    assert days(sub) == []
    services.activate_schedules(by=None, subscription_ids=[sub.pk])
    assert fresh(sub).schedule_status == "active"
    assert len(days(sub)) == 5


def test_activating_an_ended_subscriptions_schedule_generates_nothing(ended):
    services.stop_schedules(by=None, subscription_ids=[ended.pk])
    before = days(ended)
    services.activate_schedules(by=None, subscription_ids=[ended.pk])
    assert (fresh(ended).schedule_status, days(ended)) == ("active", before)


def test_delete_puts_away_and_restore_brings_back(subscribe, ended):
    # `ended` left the clock on Thursday 4 June: 8, 10, 15 and 17 June.
    live = subscribe(student_id=make_student("Aisha").id, slots=two_slots())
    before = days(live)
    ids = sorted([live.pk, ended.pk])
    assert services.delete_schedules(by=None, subscription_ids=ids) == ids
    assert {fresh(s).schedule_status for s in (live, ended)} == {"deleted"}
    assert days(live) == []
    services.restore_schedules(by=None, subscription_ids=ids)
    assert {fresh(s).schedule_status for s in (live, ended)} == {"active"}
    assert days(live) == before


def test_restore_leaves_a_stopped_schedule_stopped(subscribe):
    sub = subscribe(slots=two_slots())
    services.stop_schedules(by=None, subscription_ids=[sub.pk])
    services.restore_schedules(by=None, subscription_ids=[sub.pk])
    assert fresh(sub).schedule_status == "stopped"


@pytest.mark.parametrize("action", ["stop_schedules", "activate_schedules"])
def test_a_deleted_schedule_is_restored_first(subscribe, action):
    sub = set_schedule(subscribe(slots=two_slots()), "deleted")
    with pytest.raises(ConflictError) as refused:
        getattr(services, action)(by=None, subscription_ids=[sub.pk])
    assert (refused.value.code, refused.value.member_id) == (
        "scheduling.schedule_deleted",
        sub.pk,
    )


def test_one_deleted_schedule_refuses_the_whole_stop(subscribe):
    fine = subscribe(slots=two_slots())
    gone = set_schedule(
        subscribe(student_id=make_student("Aisha").id, slots=two_slots(time(9))),
        "deleted",
    )
    with pytest.raises(ConflictError) as refused:
        services.stop_schedules(by=None, subscription_ids=[fine.pk, gone.pk])
    assert refused.value.member_id == gone.pk
    assert (fresh(fine).schedule_status, len(days(fine))) == ("active", 5)


def test_a_bundle_row_acts_on_every_member(world):
    created = multi_bundle(world)
    services.stop_schedules(by=None, bundle_ids=[created.bundle.pk])
    assert {fresh(m).schedule_status for m in created.members} == {"stopped"}
    assert not Session.objects.filter(subscription__in=created.members).exists()


def test_a_bundle_row_stops_its_old_link_and_its_pending_renewal(world):
    """Plan D1: the old link still generates until its renewal starts."""
    created = group_bundle(world)
    (old,) = created.members
    renewal = services.renew_subscription(old, starts_on=date(2026, 6, 10))
    services.stop_schedules(by=None, bundle_ids=[created.bundle.pk])
    assert {fresh(old).schedule_status, fresh(renewal).schedule_status} == {
        "stopped"
    }
    # Every lesson of either link was still to come: none is left.
    assert days(old) == []
    assert days(renewal) == []


def test_a_members_id_acts_on_that_member_alone(world):
    created = multi_bundle(world)
    one, other = created.members
    services.stop_schedules(by=None, subscription_ids=[one.pk])
    assert (fresh(one).schedule_status, fresh(other).schedule_status) == (
        "stopped",
        "active",
    )


def test_a_bundle_rows_refusal_names_its_member(world):
    """Spec §10: a bundle row refuses as a whole, naming the member."""
    created = group_bundle(world, make_student("Aisha"))
    gone = set_schedule(created.members[1], "deleted")
    with pytest.raises(ConflictError) as refused:
        services.stop_schedules(by=None, bundle_ids=[created.bundle.pk])
    assert (refused.value.code, refused.value.member_id) == (
        "scheduling.schedule_deleted",
        gone.pk,
    )
    assert fresh(created.members[0]).schedule_status == "active"


def test_ids_must_be_this_academys(subscribe):
    with pytest.raises(ValidationError) as nothing:
        services.stop_schedules(by=None)
    with pytest.raises(ValidationError) as unknown:
        services.stop_schedules(by=None, subscription_ids=[999999])
    with pytest.raises(ValidationError) as no_bundle:
        services.stop_schedules(by=None, bundle_ids=[999999])
    assert (nothing.value.field, unknown.value.field, no_bundle.value.field) == (
        "subscription_ids",
        "subscription_ids",
        "bundle_ids",
    )


def test_the_bundles_are_locked_before_every_subscription(world, subscribe):
    created = multi_bundle(world)
    plain = subscribe(student_id=make_student("Aisha").id, slots=two_slots(time(9)))
    with CaptureQueriesContext(connection) as ctx:
        services.stop_schedules(
            by=None, subscription_ids=[plain.pk], bundle_ids=[created.bundle.pk]
        )
    locks = [q["sql"] for q in ctx.captured_queries if " FOR " in q["sql"]]
    assert first_table(locks[0]) == '"scheduling_subscriptionbundle"'
    assert locks[0].endswith("FOR NO KEY UPDATE")
    assert first_table(locks[1]) == '"scheduling_subscription"'
    assert locks[1].endswith("ORDER BY 1 ASC FOR UPDATE")
    # Plan 4: sessions come after their subscriptions, never before.
    tables = [first_table(sql) for sql in locks]
    assert tables.index('"scheduling_session"') > 1
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_status.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'stop_schedules'`.

- [ ] **Step 3: Implement** (`backend/etqan/scheduling/services/schedules.py`)

```python
"""Slice B2g §4: what the office does to weekly schedules — a subscription's
slot set (G-1), or a bundle row's. Every action takes one lock — the bundles,
then every subscription in one statement — before any per-subscription call,
and refuses as a whole when one subscription refuses, naming it (plan D2).
Per-subscription services called afterwards only re-lock rows already held."""

from collections.abc import Iterable
from dataclasses import dataclass

from django.db import transaction
from django.db.models import Q

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import dates
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.services import generation
from etqan.scheduling.services import rules
from etqan.scheduling.services.bundle_actions import NOTHING_LIVE
from etqan.scheduling.services.bundles import is_current
from etqan.scheduling.services.bundles import refused

SCHEDULE = rules.SCHEDULE


@dataclass(frozen=True)
class Targets:
    """The locked bundles, and every subscription the action applies to
    (pk order): the plain ids, and each bundle's schedule members (D1)."""

    bundles: list[SubscriptionBundle]
    subscriptions: list[Subscription]


def _locked_ids(subscriptions) -> list[int]:
    """``subscriptions`` locked in one statement, in id order (`ORDER BY 1
    ASC FOR UPDATE`); their ids."""
    return list(
        subscriptions.order_by("pk").select_for_update().values_list("pk", flat=True)
    )


def _schedule_member(member: Subscription) -> bool:
    """Plan D1: current (no renewal at all, B2f F-5) or still live — an old
    link generates until its renewal starts."""
    return is_current(member) or member.status in rules.LIVE


def lock_schedules(
    subscription_ids: Iterable[int], bundle_ids: Iterable[int]
) -> Targets:
    """§4's order (plan D12): the bundles, `FOR NO KEY UPDATE` in id order
    (B2f D2: a lone member's renewal takes only KEY SHARE on its bundle),
    then every subscription named or in those bundles in one statement, with
    B2f's second pass for a member that committed while it waited."""
    sub_ids = sorted(set(subscription_ids))
    bundle_set = sorted(set(bundle_ids))
    if not sub_ids and not bundle_set:
        raise ValidationError("Choose at least one schedule.", field="subscription_ids")
    bundles = list(
        SubscriptionBundle.objects.filter(pk__in=bundle_set)
        .order_by("pk")
        .select_for_update(no_key=True)
    )
    if len(bundles) != len(bundle_set):
        raise ValidationError("Choose bundles of this academy.", field="bundle_ids")
    wanted = Subscription.objects.filter(
        Q(pk__in=sub_ids) | Q(bundle_id__in=bundle_set)
    )
    ids = _locked_ids(wanted)
    while extra := _locked_ids(wanted.exclude(pk__in=ids)):
        ids += extra
    if not set(sub_ids) <= set(ids):
        raise ValidationError(
            "Choose subscriptions of this academy.", field="subscription_ids"
        )
    rows = Subscription.objects.filter(pk__in=ids).select_related(
        "renewal", "student__user", "teacher__user", "course"
    )
    named = set(sub_ids)
    chosen = [
        row
        for row in rows.order_by("pk")
        if row.pk in named or _schedule_member(row)
    ]
    return Targets(bundles=bundles, subscriptions=chosen)


def live_targets(targets: Targets) -> list[Subscription]:
    """Plan D1: what a teacher change or a substitution applies to — the
    named subscriptions (each checks its own status) and the live schedule
    members of each bundle; a bundle with none is refused."""
    bundled = {bundle.pk for bundle in targets.bundles}
    for bundle in targets.bundles:
        if not any(
            m.bundle_id == bundle.pk and m.status in rules.LIVE
            for m in targets.subscriptions
        ):
            raise ConflictError(NOTHING_LIVE, code="scheduling.not_allowed_in_status")
    return [
        m
        for m in targets.subscriptions
        if m.bundle_id not in bundled or m.status in rules.LIVE
    ]


def refuse_deleted(members: Iterable[Subscription]) -> None:
    """Plan D3, checked on every target before anything changes."""
    for member in members:
        try:
            rules.refuse_if_schedule_deleted(member)
        except ConflictError as exc:
            raise refused(member, exc) from None


def _set(members: list[Subscription], status: str, by) -> list[Subscription]:
    """Write ``status`` on those of ``members`` that have another one (plan
    D3: the same status is a no-op); answer them."""
    changed = [m for m in members if m.schedule_status != status]
    now = dates.now()
    Subscription.objects.filter(pk__in=[m.pk for m in changed]).update(
        schedule_status=status,
        schedule_changed_at=now,
        schedule_changed_by=by,
        updated_at=now,
    )
    return changed


def _remove_future(members: list[Subscription]) -> None:
    """§4: their untouched future generated sessions go; postponed, marked
    and hand-added ones stay (Plan 21 D7's `regenerable`)."""
    if members:
        rules.delete_untouched(
            rules.regenerable(
                subscription_id__in=[m.pk for m in members],
                occurs_on__gte=rules.today(),
            )
        )


def _fill(members: list[Subscription]) -> None:
    """§4: a live schedule made active again fills its horizon."""
    for member in members:
        if member.status in rules.LIVE:
            generation.generate_horizon(member)


def _ids(targets: Targets) -> list[int]:
    return [m.pk for m in targets.subscriptions]


@transaction.atomic
def stop_schedules(*, by, subscription_ids=(), bundle_ids=()) -> list[int]:
    """G-2: no new sessions; the untouched future ones go."""
    targets = lock_schedules(subscription_ids, bundle_ids)
    refuse_deleted(targets.subscriptions)
    _remove_future(_set(targets.subscriptions, SCHEDULE.STOPPED, by))
    return _ids(targets)


@transaction.atomic
def delete_schedules(*, by, subscription_ids=(), bundle_ids=()) -> list[int]:
    """G-3: put away (the "deleted" tab), as stopping does to its sessions."""
    targets = lock_schedules(subscription_ids, bundle_ids)
    _remove_future(_set(targets.subscriptions, SCHEDULE.DELETED, by))
    return _ids(targets)


@transaction.atomic
def activate_schedules(*, by, subscription_ids=(), bundle_ids=()) -> list[int]:
    """G-2, G-4: active again on any subscription status; a live one fills
    its horizon."""
    targets = lock_schedules(subscription_ids, bundle_ids)
    refuse_deleted(targets.subscriptions)
    _fill(_set(targets.subscriptions, SCHEDULE.ACTIVE, by))
    return _ids(targets)


@transaction.atomic
def restore_schedules(*, by, subscription_ids=(), bundle_ids=()) -> list[int]:
    """G-3, plan D3: a deleted schedule comes back active; any other target
    is left as it is."""
    targets = lock_schedules(subscription_ids, bundle_ids)
    deleted = [m for m in targets.subscriptions if m.schedule_status == SCHEDULE.DELETED]
    _fill(_set(deleted, SCHEDULE.ACTIVE, by))
    return _ids(targets)
```

`backend/etqan/scheduling/services/__init__.py` — import and list in `__all__` (alphabetical, as the file is): `Targets`, `activate_schedules`, `delete_schedules`, `live_targets`, `lock_schedules`, `restore_schedules`, `stop_schedules` from `etqan.scheduling.services.schedules`.

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_status.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/schedules.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_schedules_status.py
git -C $W/backend commit -m "feat(scheduling): stop, delete, activate and restore schedules and bundle rows, all or nothing (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 5: Substitutions — add one for a period, remove it, each regenerating its range

**Files:**
- Create: `backend/etqan/scheduling/services/substitutions.py`
- Modify: `backend/etqan/scheduling/services/availability.py` (`sessions_outside`)
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_schedules_substitutions.py`

**Interfaces:**
- Consumes: Task 4's `lock_schedules`, `live_targets`; Task 2's generation; `subscriptions.course_teacher(user_id, course)`; B2f's `each_member`; B2e's availability spans.
- Produces: `MAX_SUBSTITUTION_DAYS = 366`; `Substituted(substitutions: list[TeacherSubstitution], conflicts: list[tuple[Session, Session]], outside: list[int] | None)`; `add_substitution(*, by, teacher_id, from_date, to_date, subscription_ids=(), bundle_ids=()) -> Substituted` (plan D8, D9; substitutions come with `teacher__user`); `remove_substitution(substitution) -> None` (plan D11); `substitutions_queryset()`, `substitutions_of(subscription) -> list[TeacherSubstitution]` (current and future, D16), `has_substitutions() -> bool`; `availability.sessions_outside(sessions) -> list[int] | None` (None while `teacher_availability` is off).

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_schedules_substitutions.py`)

```python
"""Slice B2g G-5, G-6: a substitute for a period — checks, the range's
regeneration, and every caller that regenerates afterwards."""

from datetime import date
from datetime import time

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.catalogue import services as catalogue_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import WEDNESDAY
from etqan.scheduling.tests.conftest import WEEK_2
from etqan.scheduling.tests.conftest import deactivated
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import postponed
from etqan.scheduling.tests.conftest import set_schedule
from etqan.scheduling.tests.conftest import two_slots

JUNE_22, JUNE_28 = date(2026, 6, 22), date(2026, 6, 28)


def add(sub, teacher, from_date=WEEK_2[0], to_date=WEEK_2[1]):
    return services.add_substitution(
        by=None,
        teacher_id=teacher.id,
        from_date=from_date,
        to_date=to_date,
        subscription_ids=[sub.pk],
    )


def week_2(sub):
    return sorted(
        Session.objects.filter(subscription=sub, occurs_on__range=WEEK_2).values_list(
            "occurs_on", "teacher_id", "substitute_for_id"
        )
    )


def test_the_ranges_generated_sessions_go_to_the_substitute(subscribe, world, hamza):
    sub = subscribe(slots=two_slots())
    done = add(sub, hamza)
    [made] = done.substitutions
    assert (made.teacher.user, made.from_date, made.to_date) == (hamza, *WEEK_2)
    regular, cover = world.teacher.teacher_profile.pk, hamza.teacher_profile.pk
    assert week_2(sub) == [
        (date(2026, 6, 8), cover, regular),
        (date(2026, 6, 10), cover, regular),
    ]
    last = Session.objects.get(subscription=sub, occurs_on=date(2026, 6, 15))
    assert last.teacher_id == regular
    assert (done.conflicts, done.outside) == ([], None)


@pytest.mark.parametrize(
    ("dates", "field"),
    [
        ((WEEK_2[0], date(2026, 6, 7)), "to_date"),
        ((WEEK_2[0], date(2027, 6, 9)), "to_date"),  # 367 days
        ((date(2026, 5, 31), date(2026, 6, 2)), "from_date"),  # before today
    ],
)
def test_the_dates_are_checked_first(subscribe, hamza, dates, field):
    sub = subscribe(slots=two_slots())
    with pytest.raises(ValidationError) as refused:
        add(sub, hamza, *dates)
    assert (refused.value.field, refused.value.member_id) == (field, None)


def test_a_year_is_allowed(subscribe, hamza):
    sub = subscribe(slots=two_slots())
    assert add(sub, hamza, WEEK_2[0], date(2027, 6, 8)).substitutions  # 366 days


def test_the_substitute_is_another_active_teacher_of_the_course(
    subscribe, world, hamza
):
    sub = subscribe(slots=two_slots())
    for teacher in (world.teacher, make_teacher("Omar"), deactivated(hamza)):
        with pytest.raises(ValidationError) as refused:
            add(sub, teacher)
        assert (refused.value.field, refused.value.member_id) == ("teacher_id", sub.pk)


def test_ranges_of_one_schedule_never_overlap(subscribe, hamza):
    sub = subscribe(slots=two_slots())
    add(sub, hamza)
    with pytest.raises(ValidationError) as refused:
        add(sub, hamza, date(2026, 6, 14), date(2026, 6, 20))
    assert (refused.value.field, refused.value.member_id) == ("from_date", sub.pk)
    assert add(sub, hamza, date(2026, 6, 15), date(2026, 6, 20)).substitutions


def test_a_deleted_or_ended_schedule_takes_no_substitute(subscribe, ended, hamza):
    deleted = set_schedule(
        subscribe(student_id=make_student("Aisha").id, slots=two_slots()), "deleted"
    )
    with pytest.raises(ConflictError) as put_away:
        add(deleted, hamza)
    with pytest.raises(ConflictError) as over:
        add(ended, hamza)
    assert (put_away.value.code, put_away.value.member_id) == (
        "scheduling.schedule_deleted",
        deleted.pk,
    )
    assert (over.value.code, over.value.member_id) == (
        "scheduling.not_allowed_in_status",
        ended.pk,
    )


def test_postponed_and_hand_added_sessions_keep_their_teacher(
    subscribe, world, hamza
):
    sub = subscribe(slots=two_slots())
    moved = postponed(sub, to=date(2026, 6, 9), on=date(2026, 6, 3))
    added = hand_session(sub, occurs_on=date(2026, 6, 12))
    add(sub, hamza)
    for session in (moved, added):
        session.refresh_from_db()
        assert (session.teacher_id, session.substitute_for_id) == (
            world.teacher.teacher_profile.pk,
            None,
        )


def test_removing_it_brings_the_regular_teacher_back(subscribe, world, hamza):
    sub = subscribe(slots=two_slots())
    [made] = add(sub, hamza).substitutions
    services.remove_substitution(made)
    regular = world.teacher.teacher_profile.pk
    assert week_2(sub) == [
        (date(2026, 6, 8), regular, None),
        (date(2026, 6, 10), regular, None),
    ]
    assert not sub.substitutions.exists()
    with pytest.raises(NotFoundError):
        services.remove_substitution(made)


@pytest.mark.parametrize("change", ["pause", "slot", "starts_on", "teacher"])
def test_regenerating_callers_keep_the_substitute(subscribe, world, hamza, change):
    sub = subscribe(slots=two_slots())
    add(sub, hamza)
    if change == "pause":
        services.add_pause(sub, from_date=date(2026, 6, 3), to_date=date(2026, 6, 3))
    elif change == "slot":
        services.update_slot(sub.slots.get(weekday=MONDAY), start_time=time(19))
    elif change == "starts_on":
        services.update_subscription(sub, starts_on=date(2026, 6, 2))
    else:
        omar = make_teacher("Omar")
        catalogue_services.update_course(
            world.course, teacher_ids=[world.teacher.id, hamza.id, omar.id]
        )
        services.update_subscription(sub, teacher_id=omar.id)
    regular = Subscription.objects.get(pk=sub.pk).teacher_id
    assert {(t, s) for _, t, s in week_2(sub)} == {(hamza.teacher_profile.pk, regular)}
    assert len(week_2(sub)) == 2
    days = list(
        Session.objects.filter(subscription=sub).values_list("occurs_on", flat=True)
    )
    assert len(days) == len(set(days))


def test_payroll_pays_the_substitute(subscribe, hamza):
    sub = subscribe(slots=two_slots())
    add(sub, hamza)
    paid = services.payroll_sessions(*WEEK_2).filter(subscription=sub)
    assert set(paid.values_list("teacher_id", flat=True)) == {hamza.teacher_profile.pk}


def test_clashes_and_unavailable_sessions_are_reported(
    subscribe, hamza, availability_on
):
    sub = subscribe(slots=two_slots())
    theirs = subscribe(
        student_id=make_student("Aisha").id,
        teacher_id=hamza.id,
        slots=[{"weekdays": [MONDAY], "start_time": time(18)}],
    )
    services.set_availability(
        hamza.teacher_profile.pk,
        [{"weekday": WEDNESDAY, "start_time": time(17), "end_time": time(20)}],
    )
    done = add(sub, hamza)
    monday = Session.objects.get(subscription=sub, occurs_on=date(2026, 6, 8))
    assert [(s.pk, o.subscription_id) for s, o in done.conflicts] == [
        (monday.pk, theirs.pk)
    ]
    assert done.outside == [monday.pk]


def test_a_range_runs_later_sessions_come_back_with_the_substitute(
    subscribe, hamza
):
    """Plan D9."""
    sub = subscribe(slots=two_slots())
    services.generate(date(2026, 6, 1), date(2026, 6, 30), subscription=sub)
    add(sub, hamza, JUNE_22, JUNE_28)
    later = Session.objects.filter(subscription=sub, occurs_on__range=(JUNE_22, JUNE_28))
    assert sorted(later.values_list("occurs_on", "teacher_id")) == [
        (JUNE_22, hamza.teacher_profile.pk),
        (date(2026, 6, 24), hamza.teacher_profile.pk),
    ]


def test_nothing_past_the_horizon_is_made_otherwise(subscribe, hamza):
    sub = subscribe(slots=two_slots())
    add(sub, hamza, JUNE_22, JUNE_28)
    assert not Session.objects.filter(
        subscription=sub, occurs_on__gt=date(2026, 6, 15)
    ).exists()


def test_removing_one_locks_the_bundle_before_the_subscription(world, hamza):
    """Plan D11, §4's order: bundle (`FOR NO KEY UPDATE`), then the
    subscription, then (in `delete_untouched`) its sessions."""
    created = group_bundle(world)
    (member,) = created.members
    [made] = add(member, hamza).substitutions
    with CaptureQueriesContext(connection) as ctx:
        services.remove_substitution(made)
    locks = [q["sql"] for q in ctx.captured_queries if " FOR " in q["sql"]]
    tables = [sql.split(" FROM ")[1].split()[0] for sql in locks]
    assert tables[:2] == ['"scheduling_subscriptionbundle"', '"scheduling_subscription"']
    assert locks[0].rstrip().endswith("FOR NO KEY UPDATE")
    assert tables.index('"scheduling_session"') > 1


def test_a_group_row_gives_the_whole_class_its_substitute(world, hamza):
    created = group_bundle(world, make_student("Aisha"))
    done = services.add_substitution(
        by=None,
        teacher_id=hamza.id,
        from_date=WEEK_2[0],
        to_date=WEEK_2[1],
        bundle_ids=[created.bundle.pk],
    )
    assert sorted(s.subscription_id for s in done.substitutions) == sorted(
        m.pk for m in created.members
    )
    # F-4: one class's rows at one time are not a clash.
    assert done.conflicts == []
    covered = Session.objects.filter(
        subscription__in=created.members, occurs_on__range=WEEK_2
    )
    assert set(covered.values_list("teacher_id", flat=True)) == {
        hamza.teacher_profile.pk
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_substitutions.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'add_substitution'`.

- [ ] **Step 3: Implement**

`backend/etqan/scheduling/services/availability.py` — append:

```python
def sessions_outside(sessions) -> list[int] | None:
    """Slice B2g (plan D17): the ids of ``sessions`` outside their teacher's
    windows (a teacher with no window warns nothing), in one query; None
    while the switch is off."""
    if not features.enabled(AVAILABILITY):
        return None
    sessions = list(sessions)
    zone = rules.settings().timezone
    by_teacher = defaultdict(list)
    for window in TeacherAvailability.objects.filter(
        teacher_id__in={s.teacher_id for s in sessions}
    ):
        by_teacher[window.teacher_id].append(window)
    spans = {pk: _spans(windows) for pk, windows in by_teacher.items()}
    return [
        s.pk
        for s in sessions
        if s.teacher_id in spans
        and not _covers(spans[s.teacher_id], s.starts_at, s.minutes, zone)
    ]
```

`backend/etqan/scheduling/services/substitutions.py`:

```python
"""Slice B2g G-5, G-6: substitute teachers. A substitution is a record
generation reads (`rules.covering_substitution`): adding or removing one
deletes the untouched generated sessions of its range and generates them
again, so they go to the substitute or back to the regular teacher. Every
later regeneration (pause, slot or term edit, teacher change, renewal) reads
it too. Postponed and hand-added sessions keep their teacher (G-6)."""

from dataclasses import dataclass
from datetime import date
from datetime import timedelta

from django.db import transaction
from django.db.models import Max
from django.db.models import QuerySet

from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import dates
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.models import TeacherSubstitution
from etqan.scheduling.services import availability
from etqan.scheduling.services import generation
from etqan.scheduling.services import rules
from etqan.scheduling.services import subscriptions as subs
from etqan.scheduling.services.bundles import each_member
from etqan.scheduling.services.schedules import live_targets
from etqan.scheduling.services.schedules import lock_schedules

MAX_SUBSTITUTION_DAYS = 366


@dataclass(frozen=True)
class Substituted:
    substitutions: list[TeacherSubstitution]
    # P4-9: reported, never blocked; plan D17.
    conflicts: list[tuple[Session, Session]]
    outside: list[int] | None


def substitutions_queryset() -> QuerySet[TeacherSubstitution]:
    return TeacherSubstitution.objects.select_related("teacher__user", "subscription")


def substitutions_of(subscription: Subscription) -> list[TeacherSubstitution]:
    """Plan D16: the current and future ones (`to_date` from today), by start."""
    return list(
        substitutions_queryset()
        .filter(subscription=subscription, to_date__gte=rules.today())
        .order_by("from_date", "id")
    )


def has_substitutions() -> bool:
    """Whether this academy has any substitution (the seeds' marker)."""
    return TeacherSubstitution.objects.exists()


def _check_dates(from_date: date, to_date: date) -> None:
    """Plan D8: the range alone, before any lock."""
    if to_date < from_date:
        raise ValidationError(
            "End the substitution on or after its start.", field="to_date"
        )
    if dates.inclusive_days(from_date, to_date) > MAX_SUBSTITUTION_DAYS:
        raise ValidationError(
            f"A substitution lasts at most {MAX_SUBSTITUTION_DAYS} days.",
            field="to_date",
        )
    if from_date < rules.today():
        raise ValidationError(
            "Start the substitution today or later.", field="from_date"
        )


def _substitute(teacher_id: int, member: Subscription):
    """Plan D8: an active teacher of the course, not the schedule's own."""
    try:
        profile = subs.course_teacher(teacher_id, member.course)
    except ValidationError as exc:
        raise ValidationError(exc.message, field="teacher_id") from None
    if profile.pk == member.teacher_id:
        raise ValidationError(
            "Choose a teacher other than the schedule's own.", field="teacher_id"
        )
    return profile


def _regenerate_range(
    subscription: Subscription, from_date: date, to_date: date
) -> list[Session]:
    """Plan D9: delete the untouched generated sessions dated from
    ``max(from_date, today)`` to ``to_date`` and generate them again, up to
    the later of the horizon and the last deleted date. Answers the range's
    untouched generated sessions afterwards (the action's conflicts)."""
    today = rules.today()
    first = max(from_date, today)
    if first > to_date:
        return []
    gone = rules.regenerable(
        subscription=subscription, occurs_on__range=(first, to_date)
    )
    last_gone = gone.aggregate(last=Max("occurs_on"))["last"]
    rules.delete_untouched(gone)
    horizon = rules.settings().generation_horizon_days
    last = min(to_date, today + timedelta(days=horizon))
    if last_gone is not None:
        last = max(last, last_gone)
    if first > last:
        return []
    generation.generate(first, last, subscription=subscription)
    made = rules.regenerable(subscription=subscription, occurs_on__range=(first, last))
    return list(rules.sessions_queryset().filter(pk__in=made.values("pk")))


@transaction.atomic
def add_substitution(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §7)
    *,
    by,
    teacher_id: int,
    from_date: date,
    to_date: date,
    subscription_ids=(),
    bundle_ids=(),
) -> Substituted:
    """§4: per subscription (plan D1's targets), checked in plan D8's order,
    a record, then its range regenerated — all or nothing (plan D2)."""
    _check_dates(from_date, to_date)
    targets = lock_schedules(subscription_ids, bundle_ids)

    def add(member: Subscription):
        rules.refuse_if_schedule_deleted(member)
        rules.require_status(member)
        teacher = _substitute(teacher_id, member)
        if member.substitutions.filter(
            from_date__lte=to_date, to_date__gte=from_date
        ).exists():
            raise ValidationError(
                "This overlaps another substitution of this schedule.",
                field="from_date",
            )
        made = TeacherSubstitution.objects.create(
            subscription=member,
            teacher=teacher,
            from_date=from_date,
            to_date=to_date,
            created_by=by,
        )
        return made.pk, _regenerate_range(member, from_date, to_date)

    done = each_member(live_targets(targets), add)
    created = [session for _, sessions in done for session in sessions]
    return Substituted(
        substitutions=list(
            substitutions_queryset()
            .filter(pk__in=[pk for pk, _ in done])
            .order_by("subscription_id", "id")
        ),
        conflicts=generation.conflicts(created),
        outside=availability.sessions_outside(created),
    )


@transaction.atomic
def remove_substitution(substitution: TeacherSubstitution) -> None:
    """§4, plan D11: the record goes and its range returns to the regular
    teacher. The bundle first when there is one (§4's order), then the
    subscription; a substitution removed meanwhile is not found (404)."""
    bundle_id = (
        Subscription.objects.filter(pk=substitution.subscription_id)
        .values_list("bundle_id", flat=True)
        .first()
    )
    if bundle_id is not None:
        SubscriptionBundle.objects.select_for_update(no_key=True).filter(
            pk=bundle_id
        ).first()
    locked = (
        Subscription.objects.select_for_update()
        .filter(pk=substitution.subscription_id)
        .first()
    )
    found = (
        TeacherSubstitution.objects.filter(pk=substitution.pk).first()
        if locked is not None
        else None
    )
    if found is None:
        raise NotFoundError("Substitution", substitution.pk)
    found.delete()
    _regenerate_range(locked, found.from_date, found.to_date)
```

`backend/etqan/scheduling/services/__init__.py` — export `MAX_SUBSTITUTION_DAYS`, `Substituted`, `add_substitution`, `has_substitutions`, `remove_substitution`, `substitutions_of`, `substitutions_queryset` (from `services.substitutions`) and `sessions_outside` (from `services.availability`), each in `__all__`.

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_substitutions.py etqan/scheduling/tests/test_availability_services.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/substitutions.py etqan/scheduling/services/availability.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_schedules_substitutions.py
git -C $W/backend commit -m "feat(scheduling): substitute teachers for a period, regenerating their range (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 6: The bulk teacher change; postponed lessons keep their substitute; the log names it

**Files:**
- Modify: `backend/etqan/scheduling/services/schedules.py` (`TeacherChanged`, `bulk_change_teacher`)
- Modify: `backend/etqan/scheduling/services/subscriptions.py` (`_move_postponed_teacher`)
- Modify: `backend/etqan/scheduling/services/activity.py` (`LOGGED_FIELDS`)
- Modify: `backend/etqan/scheduling/services/activity_feed.py` (`REFERENCES`, `_names`)
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_schedules_teacher.py`

**Interfaces:**
- Consumes: Task 4's `lock_schedules`, `live_targets`, `refuse_deleted`; Task 5's `add_substitution`, `availability.sessions_outside`; `update_subscription(subscription, *, teacher_id, by)`.
- Produces: `TeacherChanged(subscriptions: list[Subscription], conflicts, outside: list[int] | None)`; `bulk_change_teacher(*, by, teacher_id, subscription_ids=(), bundle_ids=()) -> TeacherChanged` (G-7, plan D1, D2; a refused teacher is 400 on `teacher_id`). `activity.LOGGED_FIELDS` holds `substitute_for_id` right after `teacher_id`; the feed names it like `teacher_id`.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_schedules_teacher.py`)

```python
"""Slice B2g G-7: one teacher for several schedules, all or nothing;
substitutions stay; B2b's postponed move and the activity log."""

from datetime import date
from datetime import time

import pytest

from etqan.catalogue import services as catalogue_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import SessionActivity
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import WEEK_2
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import other_course
from etqan.scheduling.tests.conftest import postponed
from etqan.scheduling.tests.conftest import set_schedule
from etqan.scheduling.tests.conftest import two_slots


def change(teacher, *subs, bundle_ids=()):
    return services.bulk_change_teacher(
        by=None,
        teacher_id=teacher.id,
        subscription_ids=[s.pk for s in subs],
        bundle_ids=bundle_ids,
    )


def cover(sub, teacher):
    return services.add_substitution(
        by=None,
        teacher_id=teacher.id,
        from_date=WEEK_2[0],
        to_date=WEEK_2[1],
        subscription_ids=[sub.pk],
    )


@pytest.fixture
def omar(world, hamza):
    """A third teacher of the course."""
    teacher = make_teacher("Omar")
    catalogue_services.update_course(
        world.course, teacher_ids=[world.teacher.id, hamza.id, teacher.id]
    )
    return teacher


def teacher_of(sub):
    return Subscription.objects.get(pk=sub.pk).teacher_id


def test_the_teacher_of_several_schedules_changes_at_once(subscribe, hamza):
    one = subscribe(slots=two_slots())
    two = subscribe(student_id=make_student("Aisha").id, slots=two_slots(time(9)))
    done = change(hamza, one, two)
    assert [s.pk for s in done.subscriptions] == sorted([one.pk, two.pk])
    taught = Session.objects.filter(subscription__in=[one, two])
    assert set(taught.values_list("teacher_id", flat=True)) == {
        hamza.teacher_profile.pk
    }
    assert (done.conflicts, done.outside) == ([], None)


def test_the_teacher_change_is_all_or_nothing(subscribe, world, hamza):
    one = subscribe(slots=two_slots())
    fiqh = other_course(world)  # taught by world.teacher alone
    two = subscribe(
        student_id=make_student("Aisha").id, course_id=fiqh.pk, slots=two_slots(time(9))
    )
    with pytest.raises(ValidationError) as refused:
        change(hamza, one, two)
    assert (refused.value.field, refused.value.member_id) == ("teacher_id", two.pk)
    assert teacher_of(one) == world.teacher.teacher_profile.pk


def test_substitutions_stay_and_stand_in_for_the_new_teacher(
    subscribe, hamza, omar
):
    sub = subscribe(slots=two_slots())
    cover(sub, hamza)
    change(omar, sub)
    covered = Session.objects.filter(subscription=sub, occurs_on__range=WEEK_2)
    assert set(covered.values_list("teacher_id", "substitute_for_id")) == {
        (hamza.teacher_profile.pk, omar.teacher_profile.pk)
    }


def test_a_postponed_lesson_keeps_its_substitute(
    subscribe, world, hamza, omar, set_features
):
    set_features(activity_log=True)  # B2c records only while it is on
    sub = subscribe(slots=two_slots())
    cover(sub, hamza)
    moved = postponed(sub, to=date(2026, 6, 11), on=date(2026, 6, 10))
    plain = postponed(sub, to=date(2026, 6, 4), on=date(2026, 6, 3))
    change(omar, sub)
    moved.refresh_from_db()
    plain.refresh_from_db()
    regular = world.teacher.teacher_profile.pk
    assert (moved.teacher_id, moved.substitute_for_id) == (
        hamza.teacher_profile.pk,
        omar.teacher_profile.pk,
    )
    assert (plain.teacher_id, plain.substitute_for_id) == (omar.teacher_profile.pk, None)
    logged = {
        e.session_id: e.changes
        for e in SessionActivity.objects.filter(action="teacher_moved")
    }
    assert logged[moved.pk] == {
        "substitute_for_id": [regular, omar.teacher_profile.pk]
    }
    assert logged[plain.pk] == {"teacher_id": [regular, omar.teacher_profile.pk]}


def test_a_postponed_lesson_whose_substitute_becomes_the_teacher_loses_the_label(
    subscribe, hamza
):
    sub = subscribe(slots=two_slots())
    cover(sub, hamza)
    moved = postponed(sub, to=date(2026, 6, 11), on=date(2026, 6, 10))
    change(hamza, sub)
    moved.refresh_from_db()
    assert (moved.teacher_id, moved.substitute_for_id) == (
        hamza.teacher_profile.pk,
        None,
    )
    # Plan D7: the substitution now names the teacher and is ignored.
    covered = Session.objects.filter(
        subscription=sub, occurs_on__range=WEEK_2, postponed_at__isnull=True
    )
    assert set(covered.values_list("substitute_for_id", flat=True)) == {None}


def test_the_activity_log_names_the_substitute_for(
    subscribe, hamza, omar, set_features
):
    set_features(activity_log=True)
    sub = subscribe(slots=two_slots())
    cover(sub, hamza)
    moved = postponed(sub, to=date(2026, 6, 11), on=date(2026, 6, 10))
    change(omar, sub)
    feed = services.session_activity(
        services.sessions_queryset().get(pk=moved.pk), make_admin()
    )
    rows = [c for shown in feed.entries for c in shown.changes]
    named = next(c for c in rows if c["field"] == "substitute_for_id")
    assert named["after"] == {"id": omar.teacher_profile.pk, "name": "Omar"}


def test_a_group_row_changes_the_whole_class(world, hamza):
    created = group_bundle(world, make_student("Aisha"))
    done = change(hamza, bundle_ids=[created.bundle.pk])
    assert {teacher_of(m) for m in created.members} == {hamza.teacher_profile.pk}
    assert done.conflicts == []  # F-4


def test_a_bundle_with_nothing_live_is_refused(world, hamza):
    created = group_bundle(world)
    services.cancel_bundle(created.bundle)
    with pytest.raises(ConflictError) as refused:
        change(hamza, bundle_ids=[created.bundle.pk])
    assert (refused.value.code, refused.value.member_id) == (
        "scheduling.not_allowed_in_status",
        None,
    )


def test_a_deleted_schedule_keeps_its_teacher(subscribe, hamza):
    sub = set_schedule(subscribe(slots=two_slots()), "deleted")
    with pytest.raises(ConflictError) as refused:
        change(hamza, sub)
    assert (refused.value.code, refused.value.member_id) == (
        "scheduling.schedule_deleted",
        sub.pk,
    )
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_teacher.py`
Expected: FAIL — `AttributeError: … no attribute 'bulk_change_teacher'`.

- [ ] **Step 3: Implement**

`backend/etqan/scheduling/services/schedules.py` — add imports `from etqan.scheduling.models import Session`, `from etqan.scheduling.services import availability`, `from etqan.scheduling.services import subscriptions as subs`, `from etqan.scheduling.services.bundles import each_member`, `from etqan.platform.exceptions import ValidationError` (already there), then append:

```python
@dataclass(frozen=True)
class TeacherChanged:
    subscriptions: list[Subscription]
    # P4-9: reported, never blocked; plan D17.
    conflicts: list[tuple[Session, Session]]
    outside: list[int] | None


@transaction.atomic
def bulk_change_teacher(
    *, by, teacher_id: int, subscription_ids=(), bundle_ids=()
) -> TeacherChanged:
    """G-7: `update_subscription(teacher)` on every target (plan D1), all or
    nothing, each refusal naming its subscription (plan D2). Substitutions
    stay: they replace whoever is the regular teacher."""
    targets = lock_schedules(subscription_ids, bundle_ids)
    members = live_targets(targets)
    refuse_deleted(members)

    def change(member: Subscription) -> Subscription:
        try:
            return subs.update_subscription(member, teacher_id=teacher_id, by=by)
        except ValidationError as exc:
            field = "teacher_id" if exc.field == "teacher" else exc.field
            raise ValidationError(exc.message, field=field, code=exc.code) from None

    changed = each_member(members, change)
    made = rules.regenerable(subscription__in=[m.pk for m in changed])
    created = list(rules.sessions_queryset().filter(pk__in=made.values("pk")))
    return TeacherChanged(
        subscriptions=changed,
        conflicts=generation.conflicts(created),
        outside=availability.sessions_outside(created),
    )
```

`backend/etqan/scheduling/services/subscriptions.py` — `_move_postponed_teacher` becomes:

```python
def _move_postponed_teacher(subscription: Subscription, *, by) -> None:
    """B2b B-9: postponed lessons go with the subscription's teacher. Slice
    B2c: each move is logged (`teacher_moved`), from the teacher each row
    had, read under the lock `_postponed_unmarked` took. Slice B2g G-7 (plan
    D7): a lesson a substitute teaches keeps them and now stands in for the
    new teacher — unless the substitute is the new teacher."""
    ids = _postponed_unmarked(subscription)
    new = subscription.teacher_id
    moves = []
    for pk, teacher_id, standing_in in Session.objects.filter(
        pk__in=ids
    ).values_list("pk", "teacher_id", "substitute_for_id"):
        if standing_in is None:
            moves.append((pk, "teacher_id", teacher_id, new))
        else:
            after = None if teacher_id == new else new
            moves.append((pk, "substitute_for_id", standing_in, after))
    now = dates.now()
    for field in ("teacher_id", "substitute_for_id"):
        for after in {m[3] for m in moves if m[1] == field}:
            Session.objects.filter(
                pk__in=[m[0] for m in moves if m[1] == field and m[3] == after]
            ).update(**{field: after, "updated_at": now})
    activity.record_many(
        [(pk, {field: (before, after)}) for pk, field, before, after in sorted(moves)],
        by,
        activity.Action.TEACHER_MOVED,
    )
```

`backend/etqan/scheduling/services/activity.py` — in `LOGGED_FIELDS`, right after `"teacher_id",`:

```python
    # Slice B2g G-7: B2b's teacher-change move of a substituted lesson.
    "substitute_for_id",
```

`backend/etqan/scheduling/services/activity_feed.py`:

```python
# Logged ids and what they name: a user (supervisor), a teacher profile (the
# teacher, or — slice B2g — the teacher a substitute stands in for), a
# subscription (no code column: its id is shown, Plan 25 D8).
REFERENCES = ("supervisor_id", "teacher_id", "substitute_for_id", "subscription_id")
```

and in `_names`, read the teachers of both fields and name both:

```python
    teachers = _ids(entries, "teacher_id") | _ids(entries, "substitute_for_id")
```

```python
    return {
        "supervisor_id": user_names,
        "teacher_id": teacher_names,
        "substitute_for_id": teacher_names,
        "subscription_id": {},
    }
```

`backend/etqan/scheduling/services/__init__.py` — export `TeacherChanged`, `bulk_change_teacher`.

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_teacher.py etqan/scheduling/tests/test_activity_tracking.py etqan/scheduling/tests/test_activity_tracking_more.py etqan/scheduling/tests/test_activity_feed.py etqan/scheduling/tests/test_archive_subscriptions.py etqan/scheduling/tests/test_times_postponement_postpone.py`
Expected: PASS (B2b's existing teacher-move tests and `LOGGED_FIELDS[-1] == "archived_at"` unchanged).

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/schedules.py etqan/scheduling/services/subscriptions.py etqan/scheduling/services/activity.py etqan/scheduling/services/activity_feed.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_schedules_teacher.py
git -C $W/backend commit -m "feat(scheduling): one teacher for many schedules; postponed lessons keep their substitute (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 7: Reading schedules — the list with bundle rows, the calendar, the CSV's slots, the Add candidates

**Files:**
- Create: `backend/etqan/scheduling/services/schedule_reads.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_schedules_reads.py`

**Interfaces:**
- Consumes: Task 1's fields; `rules.derive`, `rules.SUBSCRIPTION_ARCHIVE`, `rules.LIVE`, `rules.ENDED`; B2f's `group_bundle`, `make_family`, `row`.
- Produces: `SCHEDULE_TABS`, `SCHEDULE_KINDS` (`"single"` + B2f's kinds), `MAX_SCHEDULE_CANDIDATES = 20`; `Line(weekday, start_time, minutes, course, teacher, student | None, subscription_id | None)`; `ScheduleRow(bundle, members, lines, status, substitutions, derived)`; `CalendarEntry(line, bundle)`; `schedules_queryset()`, `filter_schedules(schedules, *, tab="active", q="", student=None, teacher=None, kind="", group=None)`, `schedule_heads(matching)` (one head per row, newest first), `schedule_rows(heads) -> list[ScheduleRow]` (constant SELECTs), `schedule_calendar(*, teacher=None, student=None) -> list[CalendarEntry]`, `schedule_slots(matching) -> list[tuple[Subscription, ScheduleSlot]]`, `schedule_candidates(q="") -> list[Subscription]`, `has_stopped_schedules() -> bool`. Members come with `student__user`, `teacher__user`, `course`, `bundle__{study_group,family,student__user}`, `active_slots` and `current_substitutions` (with `teacher__user`).

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_schedules_reads.py`)

```python
"""Slice B2g §5, G-10, G-11: the schedules list, the calendar, the CSV's
slots and the Add candidates."""

from datetime import date
from datetime import time

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.scheduling import services
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import WEEK_2
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import make_family
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import row
from etqan.scheduling.tests.conftest import set_schedule
from etqan.scheduling.tests.conftest import substitute
from etqan.scheduling.tests.conftest import two_slots

JUNE_1 = date(2026, 6, 1)


def rows(**filters):
    matching = services.filter_schedules(services.schedules_queryset(), **filters)
    return services.schedule_rows(services.schedule_heads(matching))


def names(found):
    return {r.members[0].student.user.full_name for r in found}


def selects(action) -> int:
    with CaptureQueriesContext(connection) as ctx:
        action()
    return sum(
        q["sql"].lstrip().upper().startswith("SELECT") for q in ctx.captured_queries
    )


def family_bundle(world, first, second):
    one, two = make_student(first), make_student(second)
    family = make_family(one, two, name=f"{first} family")
    return services.create_bundle(
        "family",
        None,
        starts_on=JUNE_1,
        family_id=family.pk,
        rows=[
            row(world, student=one.id, slots=two_slots()),
            row(world, student=two.id, slots=two_slots(time(9))),
        ],
    )


def test_one_row_per_subscription_with_a_slot_newest_first(subscribe):
    first = subscribe(slots=two_slots())
    second = subscribe(student_id=make_student("Aisha").id, slots=two_slots(time(9)))
    subscribe(student_id=make_student("Zaid").id)  # no slot: no schedule
    found = rows()
    assert [r.members for r in found] == [[second], [first]]
    assert [
        (line.weekday, line.start_time, line.minutes, line.subscription_id)
        for line in found[1].lines
    ] == [(0, time(18), 45, first.pk), (2, time(18), 45, first.pk)]
    assert (found[1].status, found[1].bundle) == ("active", None)


@pytest.fixture
def four(subscribe):
    """An active, a stopped, a deleted and an ended schedule."""
    made = {}
    for name in ("Live", "Stopped", "Deleted", "Ended"):
        made[name] = subscribe(student_id=make_student(name).id, slots=two_slots())
    set_schedule(made["Stopped"], "stopped")
    set_schedule(made["Deleted"], "deleted")
    services.cancel_subscription(made["Ended"])
    return made


@pytest.mark.parametrize(
    ("tab", "expected"),
    [
        ("active", {"Live", "Ended"}),
        ("stopped", {"Stopped"}),
        ("deleted", {"Deleted"}),
        ("live_subscription", {"Live", "Stopped", "Deleted"}),
        ("ended_subscription", {"Ended"}),
        ("all", {"Live", "Stopped", "Deleted", "Ended"}),
    ],
)
def test_the_tabs(four, tab, expected):
    assert names(rows(tab=tab)) == expected


def test_the_filters(subscribe, world):
    hamza = make_teacher("Hamza")
    yusuf = subscribe(slots=two_slots())
    aisha = make_student("Aisha")
    subscribe(student_id=aisha.id, slots=two_slots(time(9)))
    created = group_bundle(world, make_student("Zaid"))
    assert names(rows(q="ais")) == {"Aisha"}
    assert names(rows(student=aisha.id)) == {"Aisha"}
    assert rows(teacher=hamza.id) == []
    assert len(rows(teacher=world.teacher.id)) == 3
    assert names(rows(kind="single")) == {"Yusuf", "Aisha"}
    assert [r.bundle for r in rows(kind="group")] == [created.bundle]
    assert [r.bundle for r in rows(group=created.bundle.study_group_id)] == [
        created.bundle
    ]
    assert yusuf in rows(kind="single")[1].members


def test_a_family_bundle_is_one_row_whose_lines_name_their_student(world):
    created = family_bundle(world, "Aisha", "Zaid")
    [found] = rows()
    assert found.bundle == created.bundle
    assert sorted((line.weekday, line.student.user.full_name) for line in found.lines) == [
        (0, "Aisha"),
        (0, "Zaid"),
        (2, "Aisha"),
        (2, "Zaid"),
    ]


def test_a_group_bundles_identical_lines_collapse(world):
    group_bundle(world, make_student("Aisha"))
    [found] = rows()
    assert [(x.weekday, x.student, x.subscription_id) for x in found.lines] == [
        (0, None, None),
        (2, None, None),
    ]
    assert len(found.members) == 2


def test_a_bundle_row_whose_members_differ_is_mixed(world):
    created = group_bundle(world, make_student("Aisha"))
    services.stop_schedules(by=None, subscription_ids=[created.members[0].pk])
    assert [r.status for r in rows(tab="all")] == ["mixed"]
    assert len(rows(tab="active")) == len(rows(tab="stopped")) == 1


def test_a_bundle_row_holds_its_schedule_members(world):
    """Plan D1: current or live — an expired old link drops out."""
    created = group_bundle(world)
    (old,) = created.members
    renewal = services.renew_subscription(old, starts_on=date(2026, 6, 10))
    [found] = rows()
    assert {m.pk for m in found.members} == {old.pk, renewal.pk}
    Subscription.objects.filter(pk=old.pk).update(status="expired")
    [found] = rows(tab="all")
    assert [m.pk for m in found.members] == [renewal.pk]


def test_a_plain_renewal_chain_shows_its_old_link_only_while_live(subscribe):
    """Plan D13 (review I-3): the same rule as a bundle row's members."""
    old = subscribe(slots=two_slots())
    renewal = services.renew_subscription(old, starts_on=date(2026, 6, 10))
    assert [r.members for r in rows()] == [[renewal], [old]]
    Subscription.objects.filter(pk=old.pk).update(status="expired")
    assert [r.members for r in rows(tab="all")] == [[renewal]]


def test_a_rows_substitutions_are_current_and_collapsed(world, hamza, clock):
    created = group_bundle(world, make_student("Aisha"))
    for member in created.members:
        substitute(member, hamza, *WEEK_2)
        substitute(member, hamza, date(2026, 5, 1), date(2026, 5, 31))  # over
    [found] = rows()
    assert [(s.teacher_id, s.from_date) for s in found.substitutions] == [
        (hamza.teacher_profile.pk, WEEK_2[0])
    ]


def test_archived_subscriptions_leave_while_the_archive_is_on(
    ended, archives_on, set_features
):
    services.archive_subscription(ended, by=None)
    assert rows(tab="all") == []
    set_features(subscription_archive=False)
    assert [r.members for r in rows(tab="all")] == [[ended]]


def test_the_rows_cost_the_same_selects_for_one_or_many(world, subscribe, hamza):
    def plain(name):
        sub = subscribe(student_id=make_student(name).id, slots=two_slots())
        substitute(sub, hamza, *WEEK_2)

    plain("Aisha")
    family_bundle(world, "Zaid", "Huda")
    one = selects(lambda: rows(tab="all"))
    plain("Omar")
    plain("Sara")
    family_bundle(world, "Ali", "Mona")
    assert len(rows(tab="all")) == 5
    assert selects(lambda: rows(tab="all")) == one


def test_the_calendar_csv_and_candidates_cost_the_same_selects_for_one_or_many(
    world, subscribe, hamza
):
    def more(name):
        sub = subscribe(student_id=make_student(name).id, slots=two_slots())
        substitute(sub, hamza, *WEEK_2)
        subscribe(student_id=make_student(f"{name} bare").id)  # a candidate

    def reads():
        matching = services.filter_schedules(services.schedules_queryset(), tab="all")
        return (
            selects(services.schedule_calendar),
            selects(lambda: services.schedule_slots(matching)),
            selects(services.schedule_candidates),
        )

    more("Aisha")
    family_bundle(world, "Zaid", "Huda")
    one = reads()
    more("Omar")
    more("Sara")
    family_bundle(world, "Ali", "Mona")
    assert len(services.schedule_calendar()) == 14  # 3 plain x 2 + 2 families x 4
    assert reads() == one


def test_the_calendar_shows_active_schedules_of_live_subscriptions(subscribe, ended):
    live = subscribe(student_id=make_student("Aisha").id, slots=two_slots())
    set_schedule(
        subscribe(student_id=make_student("Zaid").id, slots=two_slots(time(9))),
        "stopped",
    )
    entries = services.schedule_calendar()
    assert {e.line.subscription_id for e in entries} == {live.pk}
    assert [e.line.weekday for e in entries] == [0, 2]


def test_the_calendar_collapses_a_group_class_and_filters(world):
    created = group_bundle(world, make_student("Aisha"))
    entries = services.schedule_calendar()
    assert [(e.line.weekday, e.line.student, e.bundle.pk) for e in entries] == [
        (0, None, created.bundle.pk),
        (2, None, created.bundle.pk),
    ]
    assert services.schedule_calendar(teacher=make_teacher("Omar").id) == []
    assert len(services.schedule_calendar(student=world.student.id)) == 2


def test_the_csv_lists_every_active_slot(subscribe):
    sub = subscribe(slots=two_slots())
    ScheduleSlot.objects.create(
        subscription=sub, weekday=4, start_time=time(9), minutes=30, is_active=False
    )
    matching = services.filter_schedules(services.schedules_queryset(), tab="all")
    found = services.schedule_slots(matching)
    assert [(m.pk, s.weekday) for m, s in found] == [(sub.pk, 0), (sub.pk, 2)]


def test_the_candidates_are_live_subscriptions_without_slots(subscribe, ended):
    bare = subscribe(student_id=make_student("Aisha").id)
    subscribe(student_id=make_student("Zaid").id, slots=two_slots())
    set_schedule(subscribe(student_id=make_student("Huda").id), "deleted")
    assert services.schedule_candidates() == [bare]
    assert services.schedule_candidates(q="ais") == [bare]
    assert services.schedule_candidates(q="zai") == []


def test_has_stopped_schedules(subscribe):
    sub = subscribe()
    assert not services.has_stopped_schedules()
    set_schedule(sub, "stopped")
    assert services.has_stopped_schedules()
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_reads.py`
Expected: FAIL — `AttributeError: … no attribute 'filter_schedules'`.

- [ ] **Step 3: Implement** (`backend/etqan/scheduling/services/schedule_reads.py`)

```python
"""Slice B2g §5, G-10, G-11: reading weekly schedules. A schedule is a
subscription with at least one slot (G-1); a bundle is one row of its
schedule members (plan D1, D13). Everything a page of rows shows is read in a
fixed number of queries."""

from collections import defaultdict
from dataclasses import dataclass
from datetime import time

from django.db.models import Exists
from django.db.models import OuterRef
from django.db.models import Prefetch
from django.db.models import Q
from django.db.models import QuerySet
from django.db.models import Subquery

from etqan.platform import features
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.models import TeacherSubstitution
from etqan.scheduling.services import rules

SCHEDULE = rules.SCHEDULE
GROUP = SubscriptionBundle.Kind.GROUP
SINGLE = "single"
SCHEDULE_KINDS = (SINGLE, *SubscriptionBundle.Kind.values)
MIXED = "mixed"
MAX_SCHEDULE_CANDIDATES = 20
# §5's tabs (plan D13).
TABS = {
    "active": Q(schedule_status=SCHEDULE.ACTIVE),
    "stopped": Q(schedule_status=SCHEDULE.STOPPED),
    "deleted": Q(schedule_status=SCHEDULE.DELETED),
    "live_subscription": Q(status__in=rules.LIVE),
    "ended_subscription": Q(status__in=rules.ENDED),
    "all": Q(),
}
SCHEDULE_TABS = tuple(TABS)


@dataclass(frozen=True)
class Line:
    """One timing line (§5): a slot's day and time, its course and teacher;
    a collapsed group line has no student and no subscription."""

    weekday: int
    start_time: time
    minutes: int
    course: object
    teacher: object
    student: object | None
    subscription_id: int | None


@dataclass(frozen=True)
class ScheduleRow:
    bundle: SubscriptionBundle | None
    members: list[Subscription]
    lines: list[Line]
    status: str  # active · stopped · deleted · mixed
    substitutions: list[TeacherSubstitution]
    derived: dict[int, rules.Derived]


@dataclass(frozen=True)
class CalendarEntry:
    line: Line
    bundle: SubscriptionBundle | None


def _visible(subscriptions: QuerySet[Subscription]) -> QuerySet[Subscription]:
    """§5: archived subscriptions leave while the archive is on (B2d)."""
    if features.enabled(rules.SUBSCRIPTION_ARCHIVE):
        return subscriptions.filter(archived_at__isnull=True)
    return subscriptions


def schedules_queryset() -> QuerySet[Subscription]:
    """Plan D13: every subscription with a slot that is current (no renewal
    at all) or still live — D1's rule for bundle members and plain
    subscriptions alike, so a renewed link leaves once it has ended."""
    has_slot = Exists(ScheduleSlot.objects.filter(subscription=OuterRef("pk")))
    shown = Q(renewal__isnull=True) | Q(status__in=rules.LIVE)
    return _visible(Subscription.objects.filter(has_slot).filter(shown))


def filter_schedules(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (spec §5)
    schedules: QuerySet[Subscription],
    *,
    tab: str = "active",
    q: str = "",
    student: int | None = None,
    teacher: int | None = None,
    kind: str = "",
    group: int | None = None,
) -> QuerySet[Subscription]:
    """§5's tabs and filters (plan D13); people are User ids."""
    schedules = schedules.filter(TABS.get(tab, TABS["active"]))
    exact = {
        "student__user_id": student,
        "teacher__user_id": teacher,
        "bundle__study_group_id": group,
    }
    schedules = schedules.filter(
        **{key: value for key, value in exact.items() if value is not None}
    )
    if kind == SINGLE:
        schedules = schedules.filter(bundle__isnull=True)
    elif kind:
        schedules = schedules.filter(bundle__kind=kind)
    if q := q.strip():
        schedules = schedules.filter(student__user__full_name__icontains=q)
    return schedules


def schedule_heads(matching: QuerySet[Subscription]) -> QuerySet[Subscription]:
    """One subscription per row — a plain one, or a bundle's lowest-id
    matching member — newest first (plan D13). Paginate this."""
    first = (
        matching.filter(bundle_id=OuterRef("bundle_id")).order_by("pk").values("pk")[:1]
    )
    return matching.filter(Q(bundle__isnull=True) | Q(pk=Subquery(first))).order_by(
        "-pk"
    )


def _with_rows(subscriptions: QuerySet[Subscription]) -> QuerySet[Subscription]:
    """What a row reads: people, course, bundle owner, active slots and the
    current and future substitutions (plan D13)."""
    return subscriptions.select_related(
        "student__user",
        "teacher__user",
        "course",
        "bundle__study_group",
        "bundle__family",
        "bundle__student__user",
    ).prefetch_related(
        Prefetch(
            "slots",
            queryset=ScheduleSlot.objects.filter(is_active=True).order_by(
                "weekday", "start_time", "id"
            ),
            to_attr="active_slots",
        ),
        Prefetch(
            "substitutions",
            queryset=TeacherSubstitution.objects.filter(to_date__gte=rules.today())
            .select_related("teacher__user")
            .order_by("from_date", "id"),
            to_attr="current_substitutions",
        ),
    )


def _lines(bundle: SubscriptionBundle | None, members) -> list[Line]:
    """G-1: each member's active slots; a group bundle's identical lines
    collapse to one with no student (one class)."""
    group = bundle is not None and bundle.kind == GROUP
    seen = set()
    lines = []
    for member in members:
        for slot in member.active_slots:
            key = (
                slot.weekday,
                slot.start_time,
                slot.minutes,
                member.course_id,
                member.teacher_id,
            )
            if group and key in seen:
                continue
            seen.add(key)
            lines.append(
                Line(
                    weekday=slot.weekday,
                    start_time=slot.start_time,
                    minutes=slot.minutes,
                    course=member.course,
                    teacher=member.teacher,
                    student=None if group else member.student,
                    subscription_id=None if group else member.pk,
                )
            )
    return sorted(
        lines, key=lambda line: (line.weekday, line.start_time, line.subscription_id or 0)
    )


def _status(members) -> str:
    found = {member.schedule_status for member in members}
    return found.pop() if len(found) == 1 else MIXED


def _substitutions(members) -> list[TeacherSubstitution]:
    """Plan D13: the members' current ones, one per teacher and range."""
    seen = set()
    shown = []
    for member in members:
        for found in member.current_substitutions:
            key = (found.teacher_id, found.from_date, found.to_date)
            if key not in seen:
                seen.add(key)
                shown.append(found)
    return sorted(shown, key=lambda s: (s.from_date, s.teacher_id, s.pk))


def schedule_rows(heads) -> list[ScheduleRow]:
    """A page of `schedule_heads` as rows; a bundle row holds every schedule
    member of its bundle (plan D13)."""
    heads = list(heads)
    plain = list(
        _with_rows(
            Subscription.objects.filter(
                pk__in=[h.pk for h in heads if h.bundle_id is None]
            )
        )
    )
    bundle_ids = {h.bundle_id for h in heads if h.bundle_id is not None}
    bundled = (
        list(_with_rows(schedules_queryset().filter(bundle_id__in=bundle_ids)).order_by("pk"))
        if bundle_ids
        else []
    )
    derived = rules.derive(plain + bundled)
    by_pk = {sub.pk: sub for sub in plain}
    by_bundle = defaultdict(list)
    for member in bundled:
        by_bundle[member.bundle_id].append(member)
    rows = []
    for head in heads:
        if head.bundle_id is None:
            bundle, members = None, [by_pk[head.pk]]
        else:
            members = by_bundle[head.bundle_id]
            bundle = members[0].bundle
        rows.append(
            ScheduleRow(
                bundle=bundle,
                members=members,
                lines=_lines(bundle, members),
                status=_status(members),
                substitutions=_substitutions(members),
                derived={m.pk: derived[m.pk] for m in members},
            )
        )
    return rows


def schedule_calendar(
    *, teacher: int | None = None, student: int | None = None
) -> list[CalendarEntry]:
    """G-11: active schedules' active slots of live subscriptions, by day and
    time; a group class is one entry (plan D14). Slots, not sessions."""
    live = schedules_queryset().filter(
        schedule_status=SCHEDULE.ACTIVE, status__in=rules.LIVE
    )
    if teacher is not None:
        live = live.filter(teacher__user_id=teacher)
    if student is not None:
        live = live.filter(student__user_id=student)
    groups = defaultdict(list)
    entries = []
    for member in _with_rows(live).order_by("pk"):
        if member.bundle_id is not None and member.bundle.kind == GROUP:
            groups[member.bundle_id].append(member)
        else:
            entries += [
                CalendarEntry(line, member.bundle) for line in _lines(None, [member])
            ]
    for theirs in groups.values():
        bundle = theirs[0].bundle
        entries += [CalendarEntry(line, bundle) for line in _lines(bundle, theirs)]
    return sorted(
        entries,
        key=lambda e: (
            e.line.weekday,
            e.line.start_time,
            e.line.student.user.full_name
            if e.line.student is not None
            else e.bundle.study_group.name,
        ),
    )


def schedule_slots(matching: QuerySet[Subscription]) -> list[tuple]:
    """G-10: every active slot of every matching subscription, by student."""
    members = _with_rows(matching).order_by("student__user__full_name", "pk")
    return [(member, slot) for member in members for slot in member.active_slots]


def schedule_candidates(q: str = "") -> list[Subscription]:
    """Plan D15: live subscriptions with no slot whose schedule is not
    deleted, by the student's name."""
    no_slot = ~Exists(ScheduleSlot.objects.filter(subscription=OuterRef("pk")))
    subs = (
        Subscription.objects.filter(no_slot, status__in=rules.LIVE)
        .exclude(schedule_status=SCHEDULE.DELETED)
        .select_related("student__user", "course", "teacher__user")
    )
    if q := q.strip():
        subs = subs.filter(student__user__full_name__icontains=q)
    return list(subs.order_by("student__user__full_name", "pk")[:MAX_SCHEDULE_CANDIDATES])


def has_stopped_schedules() -> bool:
    """Whether any schedule is stopped (the seeds' marker)."""
    return Subscription.objects.filter(schedule_status=SCHEDULE.STOPPED).exists()
```

`backend/etqan/scheduling/services/__init__.py` — export `MAX_SCHEDULE_CANDIDATES`, `SCHEDULE_KINDS`, `SCHEDULE_TABS`, `CalendarEntry`, `Line`, `ScheduleRow`, `filter_schedules`, `has_stopped_schedules`, `schedule_calendar`, `schedule_candidates`, `schedule_heads`, `schedule_rows`, `schedule_slots`, `schedules_queryset`.

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_reads.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/schedule_reads.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_schedules_reads.py
git -C $W/backend commit -m "feat(scheduling): the schedules list with bundle rows, the calendar, the CSV slots and Add candidates (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 8: Existing reads show the schedule — subscription payloads, `substitute_for` on sessions, the Today board

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (`SESSION_RELATED`, `subscriptions_queryset`)
- Modify: `backend/etqan/scheduling/services/board.py` (`today_board`)
- Modify: `backend/etqan/scheduling/api/payloads.py` (`subscription_row`, `subscription_detail`, `substitution_row`, `session_row`, `today_row`)
- Test: `backend/etqan/scheduling/tests/test_schedules_payloads.py`

**Interfaces:**
- Consumes: Task 5's `substitutions_of`; Task 2's `rules.SCHEDULE`.
- Produces: subscription rows always carry `"schedule_status"`; the office's detail adds `"schedule_changed_at"`, `"schedule_changed_by"` (`{id, full_name}` or null) and `"substitutions": [substitution_row]`; `payloads.substitution_row(s) -> {id, subscription_id, teacher: {id, full_name}, from_date, to_date}`; a substituted session row (and a Today row with such a session, and — through `session_row` — My supervision's `supervised_row`) adds `"substitute_for": {id, full_name}`; a Today row's `teacher` is its session's teacher when it has one. The Today board leaves out a non-active schedule's slots unless a session exists on them that day.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_schedules_payloads.py`)

```python
"""Slice B2g §6, §7: what existing reads show of the schedule — the status
on subscriptions, substitutions for the office, `substitute_for` on
sessions, and the Today board (§4)."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.scheduling import services
from etqan.scheduling.api import payloads
from etqan.scheduling.models import ScheduleSlot
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import WEEK_2
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import set_schedule
from etqan.scheduling.tests.conftest import supervisor
from etqan.scheduling.tests.conftest import two_slots

SUBS = "/api/v1/subscriptions/"
SESSIONS = "/api/v1/sessions/"


def cover(sub, teacher, by=None):
    return services.add_substitution(
        by=by,
        teacher_id=teacher.id,
        from_date=WEEK_2[0],
        to_date=WEEK_2[1],
        subscription_ids=[sub.pk],
    )


def test_every_subscription_row_says_its_schedule_status(api_for, subscribe):
    sub = set_schedule(subscribe(slots=two_slots()), "stopped")
    admin = api_for("admin")
    assert admin.get(f"{SUBS}{sub.pk}/").json()["schedule_status"] == "stopped"
    assert admin.get(SUBS).json()["results"][0]["schedule_status"] == "stopped"


def test_the_office_reads_substitutions_and_who_changed_the_status(
    api_for, subscribe, world, hamza
):
    admin = api_for("admin")
    sub = subscribe(slots=two_slots())
    [made] = cover(sub, hamza, by=admin.user).substitutions
    services.stop_schedules(by=admin.user, subscription_ids=[sub.pk])
    body = admin.get(f"{SUBS}{sub.pk}/").json()
    assert body["substitutions"] == [
        {
            "id": made.pk,
            "subscription_id": sub.pk,
            "teacher": {"id": hamza.id, "full_name": "Hamza"},
            "from_date": "2026-06-08",
            "to_date": "2026-06-14",
        }
    ]
    assert body["schedule_changed_by"] == {
        "id": admin.user.pk,
        "full_name": admin.user.full_name,
    }
    assert body["schedule_changed_at"].startswith("2026-06-01T08:00")
    theirs = as_user(world.teacher).get(f"{SUBS}{sub.pk}/").json()
    assert "substitutions" not in theirs
    assert theirs["schedule_status"] == "stopped"


def test_a_substituted_session_says_whom_it_stands_in_for(
    api_for, subscribe, world, hamza
):
    sub = subscribe(slots=two_slots())
    cover(sub, hamza)
    monday = Session.objects.get(subscription=sub, occurs_on=WEEK_2[0])
    regular = {"id": world.teacher.id, "full_name": world.teacher.full_name}
    for client in (api_for("admin"), as_user(hamza)):
        found = client.get(f"{SESSIONS}{monday.pk}/").json()
        assert (found["teacher"]["id"], found["substitute_for"]) == (hamza.id, regular)
    listed = as_user(world.student).get(SESSIONS, {"when": "upcoming"}).json()
    mine = next(r for r in listed["results"] if r["id"] == monday.pk)
    assert mine["substitute_for"] == regular
    # The regular teacher no longer sees it (§6: teacher scope follows it),
    # and the substitute never sees the subscription itself.
    assert as_user(world.teacher).get(f"{SESSIONS}{monday.pk}/").status_code == 404
    assert as_user(hamza).get(f"{SUBS}{sub.pk}/").status_code == 404
    other = Session.objects.get(subscription=sub, occurs_on=date(2026, 6, 15))
    assert "substitute_for" not in api_for("admin").get(f"{SESSIONS}{other.pk}/").json()


def test_the_supervisors_rows_say_whom_a_substitute_stands_in_for(
    subscribe, world, hamza
):
    """Review I-1: My supervision's `supervised_row` spreads `session_row`,
    and `supervised_sessions` reads `sessions_queryset` (SESSION_RELATED), so
    `substitute_for` reaches it with no change of its own."""
    sara = supervisor("Sara")
    sub = subscribe(slots=two_slots(), supervisor_id=sara.id)
    cover(sub, hamza)
    rows = [payloads.supervised_row(s) for s in services.supervised_sessions(sara)]
    [covered] = [r for r in rows if r["occurs_on"] == WEEK_2[0]]
    assert covered["substitute_for"] == {
        "id": world.teacher.id,
        "full_name": world.teacher.full_name,
    }
    assert "substitute_for" not in rows[0]  # 1 June: the regular teacher's


def test_the_board_leaves_out_a_stopped_schedules_slots(subscribe):
    sub = set_schedule(subscribe(), "stopped")
    ScheduleSlot.objects.create(
        subscription=sub, weekday=MONDAY, start_time=time(9), minutes=45
    )
    assert services.today_board() == []


def test_a_stopped_schedules_marked_session_still_shows(subscribe):
    sub = subscribe(slots=two_slots())
    Session.objects.filter(subscription=sub, occurs_on=date(2026, 6, 1)).update(
        status="completed", student_attendance="present"
    )
    set_schedule(sub, "stopped")
    assert [r.state for r in services.today_board()] == ["completed"]


def test_a_today_row_names_the_sessions_teacher(subscribe, world, hamza, clock):
    sub = subscribe(slots=two_slots())
    clock.set(datetime(2026, 6, 8, 8, 0, tzinfo=UTC))
    cover(sub, hamza)
    [found] = services.today_board()
    body = payloads.today_row(found)
    assert body["teacher"] == {"id": hamza.id, "full_name": "Hamza"}
    assert body["substitute_for"] == {
        "id": world.teacher.id,
        "full_name": world.teacher.full_name,
    }


def test_today_rows_read_their_teachers_in_the_same_selects(
    subscribe, hamza, clock
):
    clock.set(datetime(2026, 6, 8, 8, 0, tzinfo=UTC))

    def schedule(name):
        sub = subscribe(student_id=make_student(name).id, slots=two_slots())
        cover(sub, hamza)

    def queries():
        with CaptureQueriesContext(connection) as ctx:
            [payloads.today_row(r) for r in services.today_board()]
        return sum(
            q["sql"].lstrip().upper().startswith("SELECT")
            for q in ctx.captured_queries
        )

    schedule("Aisha")
    one = queries()
    schedule("Zaid")
    schedule("Huda")
    assert queries() == one
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_payloads.py`
Expected: FAIL — `KeyError: 'schedule_status'`, no `substitute_for`, a stopped slot on the board.

- [ ] **Step 3: Implement**

`backend/etqan/scheduling/services/rules.py` — append to `SESSION_RELATED`:

```python
    # Slice B2g §6: whom a substitute stands in for.
    "substitute_for__user",
```

and in `subscriptions_queryset`'s `select_related(...)`, after `"bundle",`:

```python
            # Slice B2g §7: the office's detail names who changed the schedule.
            "schedule_changed_by",
```

`backend/etqan/scheduling/services/board.py` — the slot filter's first branch becomes:

```python
            Q(
                is_active=True,
                subscription__status__in=rules.LIVE,
                # Slice B2g §4: a stopped or deleted schedule's slots show
                # only with a session that day.
                subscription__schedule_status=rules.SCHEDULE.ACTIVE,
            )
```

and the two session reads name their teachers (the row's `teacher`, Task 8's payload):

```python
    sessions = {
        s.slot_id: s
        for s in Session.objects.filter(slot__in=slots, occurs_on=day).select_related(
            "teacher__user", "substitute_for__user"
        )
    }
    away = {
        s.original_slot_id: s
        for s in Session.objects.filter(
            original_slot__in=slots, original_on=day
        ).select_related("teacher__user", "substitute_for__user")
    }
```

`backend/etqan/scheduling/api/payloads.py`:

In `subscription_row`'s dict, after `"status": sub.status,`:

```python
        # Slice B2g §7: always, to everyone in scope.
        "schedule_status": sub.schedule_status,
```

After `pause_row`, add:

```python
def substitution_row(substitution) -> dict:
    """Slice B2g §7 (plan D16): from `services.substitutions_queryset`."""
    return {
        "id": substitution.pk,
        "subscription_id": substitution.subscription_id,
        "teacher": _person(substitution.teacher),
        "from_date": substitution.from_date,
        "to_date": substitution.to_date,
    }
```

In `subscription_detail`, before `if not is_admin:`:

```python
    if is_admin:
        # Slice B2g §7 (plan D16): the office's.
        detail["schedule_changed_at"] = sub.schedule_changed_at
        detail["schedule_changed_by"] = _user(sub.schedule_changed_by)
        detail["substitutions"] = [
            substitution_row(s) for s in services.substitutions_of(sub)
        ]
```

In `session_row`, right after the `row = {...}` dict:

```python
    if session.substitute_for_id is not None:
        # Slice B2g §6 (plan D16): everyone in scope sees whom it stands in for.
        row["substitute_for"] = _person(session.substitute_for)
```

`today_row` becomes:

```python
def today_row(row: services.TodayRow) -> dict:
    sub, values, session = row.subscription, row.derived, row.session
    # Slice B2g §4: a row with a session shows that session's teacher.
    teacher = session.teacher if session is not None else sub.teacher
    body = {
        "slot_id": row.slot.pk if row.slot else None,
        "subscription_id": sub.pk,
        "session_id": session.pk if session else None,
        "date": row.day,
        "start_time": _hhmm(row.start_time),
        "starts_at": row.starts_at,
        "minutes": row.minutes,
        "state": row.state,
        "student": _student(sub.student),
        "teacher": _person(teacher),
        "course": _named(sub.course),
        "sessions_total": sub.sessions_total,
        "sessions_used": values.sessions_used,
        "carried_over_sessions": values.carried_over_sessions,
        "extra_sessions": values.extra_sessions,
        "progress": round(values.progress, 4),
    }
    if session is not None and session.substitute_for_id is not None:
        body["substitute_for"] = _person(session.substitute_for)
    return body
```

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_schedules_payloads.py etqan/scheduling/tests/test_today.py etqan/scheduling/tests/test_api_sessions.py etqan/scheduling/tests/test_api_subscriptions.py etqan/scheduling/tests/test_times_postponement_board.py etqan/scheduling/tests/test_archive_board.py`
Expected: PASS (the existing board and payload suites unchanged).

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/rules.py etqan/scheduling/services/board.py etqan/scheduling/api/payloads.py etqan/scheduling/tests/test_schedules_payloads.py
git -C $W/backend commit -m "feat(scheduling): schedule status on subscriptions, substitutes on sessions and Today (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: The schedule routes, the `weekly_schedule` codes and the route table

**Files:**
- Modify: `backend/etqan/access/registry.py` (one resource under `# ── phase B2 ──`, after `study_group`)
- Modify: `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`, `FEATURE_WORDS`, `UNGATED`, one test line)
- Modify: `backend/etqan/scheduling/api/serializers.py` (six bodies)
- Modify: `backend/etqan/scheduling/api/payloads.py` (public names for four shared shapes)
- Create: `backend/etqan/scheduling/api/schedule_payloads.py`
- Create: `backend/etqan/scheduling/api/schedule_views.py`
- Modify: `backend/etqan/scheduling/api/urls.py` (ten routes after B2f's)
- Test: `backend/etqan/scheduling/tests/test_api_schedules.py`

**Interfaces:**
- Consumes: Tasks 4-8's services and `payloads.substitution_row`; B2c's `OfficeOr404`; B2f's `bundle_payloads.conflict_rows(conflicts, *, viewer)`; `CSVExportMixin`.
- Produces: the routes of spec §7 plus `schedules/candidates/` (plan D15), with plan D14 / D17's answers; `schedule_payloads.CSV_COLUMNS`, `schedule_row(row)`, `calendar_entry(entry)`, `candidate_row(subscription)`, `csv_rows(pairs)`, `substituted(result, *, viewer)`, `teacher_changed(result, *, viewer)`; resource `weekly_schedule` with `view_any`, `update`, `delete`, `restore` in use.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_api_schedules.py`)

```python
"""Slice B2g §6-§7: the schedule routes — office only, behind the switch but
activate and restore, with plan D14 / D17's answers."""

import pytest

from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import set_schedule
from etqan.scheduling.tests.conftest import two_slots

URL = "/api/v1/schedules/"
TAJWEED = {"name_ar": "تجويد", "name_en": "Tajweed"}


@pytest.fixture
def admin(api_for, schedules_on):
    return api_for("admin")


def person(user):
    return {"id": user.id, "full_name": user.full_name}


def test_teachers_students_and_parents_get_404_before_the_code(api_for, schedules_on):
    for role in ("teacher", "student", "parent"):
        client = api_for(role)
        assert client.get(URL).status_code == 404
        assert client.post(f"{URL}activate/", {}, format="json").status_code == 404


def test_a_plain_row(admin, subscribe, world):
    sub = subscribe(slots=two_slots())
    body = admin.get(URL).json()
    assert body["count"] == 1
    [found] = body["results"]
    assert {key: found[key] for key in ("key", "subscription_id", "bundle")} == {
        "key": f"subscription-{sub.pk}",
        "subscription_id": sub.pk,
        "bundle": None,
    }
    assert (found["status"], found["substitutions"]) == ("active", [])
    assert found["student"] == {**person(world.student), "timezone": "Asia/Riyadh"}
    assert found["lines"][0] == {
        "weekday": 0,
        "start_time": "18:00",
        "end_time": "18:45",
        "minutes": 45,
        "course": {"id": world.course.pk, **TAJWEED},
        "teacher": person(world.teacher),
        "student": None,
    }
    [member] = found["members"]
    assert (member["subscription_id"], member["schedule_status"], member["status"]) == (
        sub.pk,
        "active",
        "active",
    )
    assert (member["sessions_total"], member["sessions_used"]) == (8, 0)


def test_a_group_row(admin, world):
    created = group_bundle(world, make_student("Aisha"))
    [found] = admin.get(URL).json()["results"]
    assert found["bundle"] == {
        "id": created.bundle.pk,
        "kind": "group",
        "name": "Evening circle",
    }
    assert (found["key"], found["subscription_id"], found["student"]) == (
        f"bundle-{created.bundle.pk}",
        None,
        None,
    )
    assert [line["student"] for line in found["lines"]] == [None, None]
    assert len(found["members"]) == 2


def test_an_unknown_tab_is_400(admin):
    assert admin.get(URL, {"tab": "nope"}).status_code == 400


def test_download_all_is_one_line_per_slot(admin, subscribe, set_features):
    set_features(export=True)
    sub = subscribe(slots=two_slots())
    response = admin.get(URL, {"format": "csv"})
    lines = response.content.decode("utf-8-sig").splitlines()
    assert lines[0] == (
        "Student,Subscription,Bundle,Schedule status,Weekday,Start,End,Course,Teacher"
    )
    assert lines[1:] == [
        f"Yusuf,{sub.pk},,active,Monday,18:00,18:45,Tajweed,Bilal",
        f"Yusuf,{sub.pk},,active,Wednesday,18:00,18:45,Tajweed,Bilal",
    ]


def test_stop_and_activate_answer_the_subscriptions(admin, subscribe):
    sub = subscribe(slots=two_slots())
    body = {"subscription_ids": [sub.pk]}
    stopped = admin.post(f"{URL}stop/", body, format="json")
    assert (stopped.status_code, stopped.json()) == (200, {"subscriptions": [sub.pk]})
    assert not Session.objects.filter(subscription=sub).exists()
    assert admin.post(f"{URL}activate/", body, format="json").json() == {
        "subscriptions": [sub.pk]
    }
    assert Session.objects.filter(subscription=sub).count() == 5


def test_a_refusal_names_the_subscription(admin, subscribe):
    sub = set_schedule(subscribe(slots=two_slots()), "deleted")
    refused = admin.post(f"{URL}stop/", {"subscription_ids": [sub.pk]}, format="json")
    assert (refused.status_code, refused.json()) == (
        409,
        {
            "detail": "This schedule is deleted. Restore it first.",
            "code": "scheduling.schedule_deleted",
            "member_id": sub.pk,
        },
    )


def test_a_body_names_one_to_two_hundred_schedules(admin):
    empty = admin.post(f"{URL}stop/", {}, format="json")
    assert (empty.status_code, empty.json()) == (
        400,
        {"subscription_ids": ["Choose at least one schedule."]},
    )
    many = {"subscription_ids": list(range(1, 202))}
    assert admin.post(f"{URL}stop/", many, format="json").status_code == 400
    unknown = admin.post(f"{URL}delete/", {"bundle_ids": [999999]}, format="json")
    assert unknown.json() == {"bundle_ids": ["Choose bundles of this academy."]}


def test_activate_and_restore_work_with_the_switch_off(api_for, subscribe, set_features):
    set_features(weekly_schedules=False)
    admin = api_for("admin")
    sub = set_schedule(subscribe(slots=two_slots()), "deleted")
    assert admin.get(URL).status_code == 404
    restored = admin.post(
        f"{URL}restore/", {"subscription_ids": [sub.pk]}, format="json"
    )
    assert restored.status_code == 200
    assert Subscription.objects.get(pk=sub.pk).schedule_status == "active"


def test_the_teacher_route(admin, subscribe, hamza):
    sub = subscribe(slots=two_slots())
    body = {"subscription_ids": [sub.pk], "teacher_id": hamza.id}
    changed = admin.post(f"{URL}teacher/", body, format="json")
    assert (changed.status_code, changed.json()) == (
        200,
        {"subscriptions": [sub.pk], "conflicts": []},
    )
    refused = admin.post(
        f"{URL}teacher/", {**body, "teacher_id": 999999}, format="json"
    )
    assert (refused.status_code, refused.json()) == (
        400,
        {"teacher_id": ["Choose an active teacher."], "member_id": sub.pk},
    )


def test_a_substitution_is_201_and_goes_with_delete(
    admin, subscribe, hamza, availability_on
):
    sub = subscribe(slots=two_slots())
    created = admin.post(
        f"{URL}substitutions/",
        {
            "subscription_ids": [sub.pk],
            "teacher_id": hamza.id,
            "from_date": "2026-06-08",
            "to_date": "2026-06-14",
        },
        format="json",
    )
    assert created.status_code == 201
    body = created.json()
    [made] = body["substitutions"]
    assert (made["subscription_id"], made["teacher"], made["from_date"]) == (
        sub.pk,
        person(hamza),
        "2026-06-08",
    )
    # Hamza has no windows: nothing is outside them (E-11).
    assert (body["conflicts"], body["outside_availability"]) == ([], [])
    assert admin.delete(f"{URL}substitutions/{made['id']}/").status_code == 204
    assert admin.delete(f"{URL}substitutions/{made['id']}/").status_code == 404


def test_the_calendar_route(admin, subscribe, world):
    sub = subscribe(slots=two_slots())
    entries = admin.get(f"{URL}calendar/", {"teacher": world.teacher.id}).json()
    assert entries[0] == {
        "weekday": 0,
        "start_time": "18:00",
        "end_time": "18:45",
        "minutes": 45,
        "course": {"id": world.course.pk, **TAJWEED},
        "teacher": person(world.teacher),
        "student": {**person(world.student), "timezone": "Asia/Riyadh"},
        "group": None,
        "subscription_id": sub.pk,
        "bundle_id": None,
    }
    assert admin.get(f"{URL}calendar/", {"teacher": "x"}).status_code == 400


def test_the_candidates_route(admin, subscribe, world):
    bare = subscribe()
    assert admin.get(f"{URL}candidates/", {"q": "yus"}).json() == [
        {
            "id": bare.pk,
            "student": {**person(world.student), "timezone": "Asia/Riyadh"},
            "course": {"id": world.course.pk, **TAJWEED},
            "teacher": person(world.teacher),
        }
    ]
```

And in `backend/etqan/access/tests/test_routes.py` (insert, never paste whole):

After B2f's last `ROUTES` line (`("DELETE", f"/api/v1/bundles/{N}/members/{N}/", "subscription.update"),`):

```python
    # Slice B2g.
    ("GET", "/api/v1/schedules/", "weekly_schedule.view_any"),
    ("GET", "/api/v1/schedules/calendar/", "weekly_schedule.view_any"),
    ("GET", "/api/v1/schedules/candidates/", "weekly_schedule.update"),
    ("POST", "/api/v1/schedules/stop/", "weekly_schedule.update"),
    ("POST", "/api/v1/schedules/activate/", "weekly_schedule.update"),
    ("POST", "/api/v1/schedules/delete/", "weekly_schedule.delete"),
    ("POST", "/api/v1/schedules/restore/", "weekly_schedule.restore"),
    ("POST", "/api/v1/schedules/teacher/", "weekly_schedule.update"),
    ("POST", "/api/v1/schedules/substitutions/", "weekly_schedule.update"),
    ("DELETE", f"/api/v1/schedules/substitutions/{N}/", "weekly_schedule.update"),
```

After B2f's last `FEATURES` entry (`("DELETE", f"/api/v1/bundles/{N}/archive/"): "subscription_archive",`):

```python
    # Slice B2g (G-13: activate and restore are in UNGATED).
    **dict.fromkeys(
        (
            ("GET", "/api/v1/schedules/"),
            ("GET", "/api/v1/schedules/calendar/"),
            ("GET", "/api/v1/schedules/candidates/"),
            ("POST", "/api/v1/schedules/stop/"),
            ("POST", "/api/v1/schedules/delete/"),
            ("POST", "/api/v1/schedules/teacher/"),
            ("POST", "/api/v1/schedules/substitutions/"),
            ("DELETE", f"/api/v1/schedules/substitutions/{N}/"),
        ),
        "weekly_schedules",
    ),
```

After B2f's last `FEATURE_WORDS` entry (`"/bundles/group/": "group_subscriptions",`):

```python
    # Slice B2g (plan D18: no word for the list itself — any would also be a
    # prefix of the ungated activate/ and restore/).
    "/schedules/stop/": "weekly_schedules",
    "/schedules/delete/": "weekly_schedules",
    "/schedules/teacher/": "weekly_schedules",
    "/schedules/substitutions/": "weekly_schedules",
    "/schedules/calendar/": "weekly_schedules",
    "/schedules/candidates/": "weekly_schedules",
```

In `UNGATED`, after its last line:

```python
    # Slice B2g (spec G-13): nothing stays stopped or deleted while it is off.
    ("POST", "/api/v1/schedules/activate/"),
    ("POST", "/api/v1/schedules/restore/"),
```

And the one edited line, in `test_every_bundle_route_is_gated_or_listed_as_ungated` (plan D18):

```python
def test_every_bundle_route_is_gated_or_listed_as_ungated():
    """Slice B2f F-11, slice B2g G-13: a new /bundles/ or /schedules/ route
    must say which it is, and no feature word claims an ungated one."""
    bundles = {(m, p) for m, p, _ in ROUTES if "/bundles/" in p or "/schedules/" in p}
```

(the rest of the test is unchanged).

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_schedules.py etqan/access/tests/test_routes.py`
Expected: FAIL — 404 on every `/schedules/` path (no route); `weekly_schedule.view_any` not in the registry.

- [ ] **Step 3: Implement**

`backend/etqan/access/registry.py` — under `# ── phase B2 ──`, after the `study_group` resource:

```python
    # Slice B2g (§6): TutorHamster's `weekly::schedule`.
    Resource(
        "weekly_schedule",
        "Weekly schedules",
        "الجداول الأسبوعية",
        ("view_any", "update", "delete", "restore"),
    ),
```

`backend/etqan/scheduling/api/serializers.py` — add `from etqan.scheduling.services import SCHEDULE_KINDS` and `from etqan.scheduling.services import SCHEDULE_TABS`, then append:

```python
class ScheduleFilterInput(serializers.Serializer):
    """Slice B2g §5 (plan D13): the schedules list's query."""

    tab = serializers.ChoiceField(choices=SCHEDULE_TABS, required=False, default="active")
    q = serializers.CharField(required=False, allow_blank=True, default="", max_length=100)
    student = _id(required=False)
    teacher = _id(required=False)
    kind = serializers.ChoiceField(choices=SCHEDULE_KINDS, required=False)
    group = _id(required=False)


class CalendarFilterInput(serializers.Serializer):
    """Slice B2g G-11."""

    teacher = _id(required=False)
    student = _id(required=False)


class ScheduleCandidatesInput(serializers.Serializer):
    """Slice B2g plan D15."""

    q = serializers.CharField(required=False, allow_blank=True, default="", max_length=100)


class ScheduleTargetsInput(serializers.Serializer):
    """Slice B2g §7 (plan D12): the schedules an action applies to."""

    subscription_ids = serializers.ListField(
        child=_id(), required=False, max_length=200
    )
    bundle_ids = serializers.ListField(child=_id(), required=False, max_length=200)

    def validate(self, attrs):
        if not attrs.get("subscription_ids") and not attrs.get("bundle_ids"):
            raise serializers.ValidationError(
                {"subscription_ids": ["Choose at least one schedule."]}
            )
        return attrs


class ScheduleTeacherInput(ScheduleTargetsInput):
    teacher_id = _id()


class SubstitutionInput(ScheduleTargetsInput):
    teacher_id = _id()
    from_date = serializers.DateField()
    to_date = serializers.DateField()
```

`backend/etqan/scheduling/api/payloads.py` — after `_user`, name the shared shapes publicly (review M-3: `schedule_payloads` reuses them instead of copying; the private names stay for every existing caller):

```python
# Slice B2g: the shapes `schedule_payloads` reuses — one implementation each.
person = _person
student = _student
named = _named
hhmm = _hhmm
```

`backend/etqan/scheduling/api/schedule_payloads.py`:

```python
"""Slice B2g §7: JSON shapes for weekly schedules (plan D14, D17). Derived
values come from `services.schedule_rows`; these functions only arrange
them."""

from datetime import date
from datetime import datetime
from datetime import timedelta

from etqan.scheduling.api import payloads
from etqan.scheduling.api.bundle_payloads import conflict_rows

WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
# G-10 (plan D14).
CSV_COLUMNS = (
    ("student", "Student"),
    ("subscription_id", "Subscription"),
    ("bundle_id", "Bundle"),
    ("schedule_status", "Schedule status"),
    ("weekday", "Weekday"),
    ("start_time", "Start"),
    ("end_time", "End"),
    ("course", "Course"),
    ("teacher", "Teacher"),
)


# One implementation of each shape (review M-3): `payloads`' own helpers.
_hhmm = payloads.hhmm
_person = payloads.person
_student = payloads.student
_named = payloads.named


def _end(start, minutes: int) -> str:
    """The start plus the minutes on the clock, wrapping past midnight."""
    return _hhmm((datetime.combine(date.min, start) + timedelta(minutes=minutes)).time())


def _bundle_name(bundle) -> str:
    if bundle.kind == "group":
        return bundle.study_group.name
    if bundle.kind == "family":
        return bundle.family.name
    return bundle.student.user.full_name


def _line(line, *, with_student: bool) -> dict:
    return {
        "weekday": line.weekday,
        "start_time": _hhmm(line.start_time),
        "end_time": _end(line.start_time, line.minutes),
        "minutes": line.minutes,
        "course": _named(line.course),
        "teacher": _person(line.teacher),
        "student": _student(line.student)
        if with_student and line.student is not None
        else None,
    }


def _member(member, values) -> dict:
    return {
        "subscription_id": member.pk,
        "student": _student(member.student),
        "course": _named(member.course),
        "teacher": _person(member.teacher),
        "status": member.status,
        "schedule_status": member.schedule_status,
        "sessions_used": values.sessions_used,
        "sessions_total": member.sessions_total,
        "carried_over_sessions": values.carried_over_sessions,
        "extra_sessions": values.extra_sessions,
        "progress": round(values.progress, 4),
    }


def schedule_row(row) -> dict:
    """Plan D14: a plain or multi-course row names its student; a family
    row's lines name theirs; a group row's are the class's."""
    bundle, head = row.bundle, row.members[0]
    one_student = bundle is None or bundle.kind == "multi_course"
    return {
        "key": f"bundle-{bundle.pk}" if bundle else f"subscription-{head.pk}",
        "subscription_id": None if bundle else head.pk,
        "bundle": None
        if bundle is None
        else {"id": bundle.pk, "kind": bundle.kind, "name": _bundle_name(bundle)},
        "student": _student(head.student) if one_student else None,
        "status": row.status,
        "members": [_member(m, row.derived[m.pk]) for m in row.members],
        "lines": [
            _line(line, with_student=bundle is not None and bundle.kind == "family")
            for line in row.lines
        ],
        "substitutions": [
            {
                "teacher": _person(found.teacher),
                "from_date": found.from_date,
                "to_date": found.to_date,
            }
            for found in row.substitutions
        ],
    }


def calendar_entry(entry) -> dict:
    """G-11 (plan D14): a collapsed group entry names its group."""
    bundle = entry.bundle
    group = bundle is not None and bundle.kind == "group"
    return {
        **_line(entry.line, with_student=True),
        "group": bundle.study_group.name if group else None,
        "subscription_id": entry.line.subscription_id,
        "bundle_id": bundle.pk if bundle is not None else None,
    }


def candidate_row(subscription) -> dict:
    """Plan D15."""
    return {
        "id": subscription.pk,
        "student": _student(subscription.student),
        "course": _named(subscription.course),
        "teacher": _person(subscription.teacher),
    }


def csv_rows(pairs) -> list[dict]:
    """G-10: one line per (subscription, active slot)."""
    return [
        {
            "student": member.student.user.full_name,
            "subscription_id": member.pk,
            "bundle_id": member.bundle_id,
            "schedule_status": member.schedule_status,
            "weekday": WEEKDAYS[slot.weekday],
            "start_time": _hhmm(slot.start_time),
            "end_time": _end(slot.start_time, slot.minutes),
            "course": member.course.name_en,
            "teacher": member.teacher.user.full_name,
        }
        for member, slot in pairs
    ]


def _outside(ids) -> dict:
    """E-11's pattern: only while availability is on."""
    return {} if ids is None else {"outside_availability": ids}


def substituted(result, *, viewer) -> dict:
    return {
        "substitutions": [payloads.substitution_row(s) for s in result.substitutions],
        "conflicts": conflict_rows(result.conflicts, viewer=viewer),
        **_outside(result.outside),
    }


def teacher_changed(result, *, viewer) -> dict:
    return {
        "subscriptions": [sub.pk for sub in result.subscriptions],
        "conflicts": conflict_rows(result.conflicts, viewer=viewer),
        **_outside(result.outside),
    }
```

`backend/etqan/scheduling/api/schedule_views.py`:

```python
"""Slice B2g §6-§7: weekly schedules. The office only: everyone else gets 404,
before the code check (§6). Every route follows the switch but activate and
restore, which stay ungated so nothing is stuck while it is off (G-13,
FT-4). Thin: parse, call a service, arrange a payload."""

from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.csv import CSVExportMixin
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.scheduling import services
from etqan.scheduling.api import schedule_payloads
from etqan.scheduling.api.activity_views import OfficeOr404
from etqan.scheduling.api.serializers import CalendarFilterInput
from etqan.scheduling.api.serializers import ScheduleCandidatesInput
from etqan.scheduling.api.serializers import ScheduleFilterInput
from etqan.scheduling.api.serializers import ScheduleTargetsInput
from etqan.scheduling.api.serializers import ScheduleTeacherInput
from etqan.scheduling.api.serializers import SubstitutionInput

# Non-office callers 404 first; a switched-off feature 404s after the code.
OFFICE = (OfficeOr404, HasCode, FeatureOn)
FEATURE = "weekly_schedules"


def _query(serializer, request) -> dict:
    query = serializer(data=request.query_params)
    query.is_valid(raise_exception=True)
    return dict(query.validated_data)


def _body(serializer, request) -> dict:
    body = serializer(data=request.data)
    body.is_valid(raise_exception=True)
    return dict(body.validated_data)


class ScheduleListView(CSVExportMixin, generics.GenericAPIView):
    permission_classes = OFFICE
    permission_codes = {"GET": "weekly_schedule.view_any"}
    feature = FEATURE
    csv_filename = "schedules"
    csv_columns = schedule_payloads.CSV_COLUMNS

    def get(self, request):
        matching = services.filter_schedules(
            services.schedules_queryset(), **_query(ScheduleFilterInput, request)
        )
        if self.wants_csv():
            return self.csv_response(
                schedule_payloads.csv_rows(services.schedule_slots(matching))
            )
        page = self.paginate_queryset(services.schedule_heads(matching))
        return self.get_paginated_response(
            [schedule_payloads.schedule_row(row) for row in services.schedule_rows(page)]
        )


class ScheduleCalendarView(APIView):
    permission_classes = OFFICE
    permission_codes = {"GET": "weekly_schedule.view_any"}
    feature = FEATURE

    def get(self, request):
        entries = services.schedule_calendar(**_query(CalendarFilterInput, request))
        return Response([schedule_payloads.calendar_entry(e) for e in entries])


class ScheduleCandidatesView(APIView):
    """Plan D15: who "Add" may open."""

    permission_classes = OFFICE
    permission_codes = {"GET": "weekly_schedule.update"}
    feature = FEATURE

    def get(self, request):
        found = services.schedule_candidates(**_query(ScheduleCandidatesInput, request))
        return Response([schedule_payloads.candidate_row(s) for s in found])


class _StatusView(APIView):
    permission_classes = OFFICE
    service = None

    def post(self, request):
        ids = self.service(by=request.user, **_body(ScheduleTargetsInput, request))
        return Response({"subscriptions": ids})


class ScheduleStopView(_StatusView):
    permission_codes = {"POST": "weekly_schedule.update"}
    feature = FEATURE
    service = staticmethod(services.stop_schedules)


class ScheduleDeleteView(_StatusView):
    permission_codes = {"POST": "weekly_schedule.delete"}
    feature = FEATURE
    service = staticmethod(services.delete_schedules)


class ScheduleActivateView(_StatusView):
    """Ungated (G-13): listed in the route table's UNGATED."""

    permission_codes = {"POST": "weekly_schedule.update"}
    service = staticmethod(services.activate_schedules)


class ScheduleRestoreView(_StatusView):
    """Ungated (G-13): listed in the route table's UNGATED."""

    permission_codes = {"POST": "weekly_schedule.restore"}
    service = staticmethod(services.restore_schedules)


class ScheduleTeacherView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "weekly_schedule.update"}
    feature = FEATURE

    def post(self, request):
        result = services.bulk_change_teacher(
            by=request.user, **_body(ScheduleTeacherInput, request)
        )
        return Response(schedule_payloads.teacher_changed(result, viewer=request.user))


class SubstitutionListView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "weekly_schedule.update"}
    feature = FEATURE

    def post(self, request):
        result = services.add_substitution(
            by=request.user, **_body(SubstitutionInput, request)
        )
        return Response(
            schedule_payloads.substituted(result, viewer=request.user),
            status=status.HTTP_201_CREATED,
        )


class SubstitutionDetailView(APIView):
    permission_classes = OFFICE
    permission_codes = {"DELETE": "weekly_schedule.update"}
    feature = FEATURE

    def delete(self, request, pk):
        found = get_object_or_404(services.substitutions_queryset(), pk=pk)
        services.remove_substitution(found)
        return Response(status=status.HTTP_204_NO_CONTENT)
```

`backend/etqan/scheduling/api/urls.py` — add `from etqan.scheduling.api import schedule_views` and, after B2f's `bundle-member` path:

```python
    # Slice B2g (spec §7; plan D15's candidates).
    path("schedules/", schedule_views.ScheduleListView.as_view(), name="schedule-list"),
    path(
        "schedules/calendar/",
        schedule_views.ScheduleCalendarView.as_view(),
        name="schedule-calendar",
    ),
    path(
        "schedules/candidates/",
        schedule_views.ScheduleCandidatesView.as_view(),
        name="schedule-candidates",
    ),
    path(
        "schedules/stop/", schedule_views.ScheduleStopView.as_view(), name="schedule-stop"
    ),
    path(
        "schedules/delete/",
        schedule_views.ScheduleDeleteView.as_view(),
        name="schedule-delete",
    ),
    path(
        "schedules/activate/",
        schedule_views.ScheduleActivateView.as_view(),
        name="schedule-activate",
    ),
    path(
        "schedules/restore/",
        schedule_views.ScheduleRestoreView.as_view(),
        name="schedule-restore",
    ),
    path(
        "schedules/teacher/",
        schedule_views.ScheduleTeacherView.as_view(),
        name="schedule-teacher",
    ),
    path(
        "schedules/substitutions/",
        schedule_views.SubstitutionListView.as_view(),
        name="schedule-substitutions",
    ),
    path(
        "schedules/substitutions/<int:pk>/",
        schedule_views.SubstitutionDetailView.as_view(),
        name="schedule-substitution",
    ),
```

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_schedules.py etqan/access/tests`
Expected: PASS (every route in the table, the two ungated ones answering with every feature off, the switched-off ones 404 after the code check).

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/access/registry.py etqan/access/tests/test_routes.py etqan/scheduling/api/serializers.py etqan/scheduling/api/payloads.py etqan/scheduling/api/schedule_payloads.py etqan/scheduling/api/schedule_views.py etqan/scheduling/api/urls.py etqan/scheduling/tests/test_api_schedules.py
git -C $W/backend commit -m "feat(scheduling): the weekly schedule routes and weekly_schedule codes; activate and restore ungated (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 10: Demo seeds — a stopped schedule and a week's substitution

**Files:**
- Modify: `backend/etqan/tenants/seeds/b2.py` (`SCHEDULES`, `seed_schedules`)
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (one call in the B2 block, after `b2.seed_bundles`)
- Test: `backend/etqan/tenants/tests/test_seed_b2.py` (one new test)

**Interfaces:**
- Consumes: `scheduling_services.stop_schedules`, `add_substitution`, `has_stopped_schedules`, `has_substitutions`, `bundles_queryset`, `subscriptions_queryset`, `substitutions_queryset`, `sessions_queryset`, `today`; B2f's seeded bundles.
- Produces: `b2.seed_schedules(subdomain)` — idempotent, demo only (plan D19).

- [ ] **Step 1: Write the failing test** (append to `backend/etqan/tenants/tests/test_seed_b2.py`)

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_demo_gets_a_stopped_schedule_and_a_weeks_substitution_once():
    """Slice B2g §9, plan D19: both on B2f's seeded bundles."""
    call_command("seed_dev")
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        assert features.enabled("weekly_schedules")
        multi = scheduling_services.bundles_queryset().get(kind="multi_course")
        members = scheduling_services.subscriptions_queryset().filter(bundle=multi)
        assert {m.schedule_status for m in members} == {"stopped"}
        assert not scheduling_services.untouched_sessions(
            subscription__in=members, generated=True
        ).exists()
        [found] = scheduling_services.substitutions_queryset()
        assert found.teacher.user.full_name == "Ustadh Bilal"
        assert found.subscription.student.user.full_name == "Aisha Omar"
        assert found.subscription.bundle.kind == "family"
        assert found.from_date.weekday() == 0
        assert (found.to_date - found.from_date).days == 6
        covered = scheduling_services.sessions_queryset().filter(
            subscription=found.subscription,
            occurs_on__range=(found.from_date, found.to_date),
        )
        assert covered.exists()
        assert {
            (s.teacher.user.full_name, s.substitute_for.user.full_name) for s in covered
        } == {("Ustadh Bilal", "Ustadha Maryam")}
    with tenant_context(other):
        assert not scheduling_services.has_substitutions()
        assert not scheduling_services.has_stopped_schedules()
```

- [ ] **Step 2: Run it to see it fail**

Run: `… exec -T django pytest -q etqan/tenants/tests/test_seed_b2.py -k weeks_substitution`
Expected: FAIL — `ValueError: not enough values to unpack (expected 1, got 0)` (no substitution seeded).

- [ ] **Step 3: Implement**

`backend/etqan/tenants/seeds/b2.py` — append:

```python
# Slice B2g (spec §9, plan D19): in demo, Zaid Huda's multi-course bundle is
# a stopped schedule, and Aisha Omar's Quran Memorisation in the Omar family
# bundle has Ustadh Bilal standing in for Ustadha Maryam all next week. Both
# act on B2f's seeded bundles: no subscription is added, so the seed tests'
# subscription counts stay as they are. Other academies get nothing.
SCHEDULES = {
    "demo": {
        "stopped": {"student": "Zaid Huda"},
        "substitution": {
            "family": "Omar family",
            "student": "Aisha Omar",
            "course": "Quran Memorisation",
            "teacher": "Ustadh Bilal",
        },
    }
}


def _next_week():
    """Next Monday to the Sunday after (inside the 14-day horizon)."""
    today = scheduling_services.today()
    monday = today + timedelta(days=7 - today.weekday())
    return monday, monday + timedelta(days=6)


def _seed_stopped(item: dict) -> None:
    if scheduling_services.has_stopped_schedules():
        return
    bundle = (
        scheduling_services.bundles_queryset()
        .filter(kind="multi_course", student__user__full_name=item["student"])
        .first()
    )
    if bundle is None:
        return  # B2f's seed made none (plan D19): nothing to stop
    try:
        with transaction.atomic():
            scheduling_services.stop_schedules(by=None, bundle_ids=[bundle.pk])
    except (ValidationError, ConflictError) as exc:
        print(f"skip: stopped schedule — {exc}")  # noqa: T201


def _seed_substitution(item: dict) -> None:
    if scheduling_services.has_substitutions():
        return
    member = (
        scheduling_services.subscriptions_queryset()
        .filter(
            bundle__kind="family",
            bundle__family__name=item["family"],
            student__user__full_name=item["student"],
            course__name_en=item["course"],
        )
        .first()
    )
    teacher = _person("teacher", item["teacher"])
    if member is None or teacher is None:
        return  # B2f's seed made none (plan D19)
    first, last = _next_week()
    try:
        with transaction.atomic():
            scheduling_services.add_substitution(
                by=None,
                teacher_id=teacher.id,
                from_date=first,
                to_date=last,
                subscription_ids=[member.pk],
            )
    except (ValidationError, ConflictError) as exc:
        print(f"skip: substitution — {exc}")  # noqa: T201


def seed_schedules(subdomain: str) -> None:
    """Idempotent: each step is skipped once its marker holds, and each is
    one transaction (a refused one leaves nothing and is retried later)."""
    spec = SCHEDULES.get(subdomain)
    if spec is None:
        return
    _seed_stopped(spec["stopped"])
    _seed_substitution(spec["substitution"])
```

`backend/etqan/tenants/management/commands/seed_dev.py` — in the B2 block, right after `b2.seed_bundles(subdomain)`:

```python
        b2.seed_schedules(subdomain)
```

- [ ] **Step 4: Run it, and every seed test, to see them pass**

Run: `… exec -T django pytest -q etqan/tenants/tests`
Expected: PASS — the new test, and every existing seed test unchanged (`test_seed_dev_skips_a_subscription_whose_teacher_was_deactivated` still counts 3 `skip:` lines: without B2f's bundles this seed prints nothing).

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/tenants/seeds/b2.py etqan/tenants/management/commands/seed_dev.py etqan/tenants/tests/test_seed_b2.py
git -C $W/backend commit -m "feat(seeds): a stopped schedule and a week's substitute in demo (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Then run the backend gates once before the dashboard: `… exec -T django ruff check .`, `… exec -T django ruff format --check .`, `… exec -T django lint-imports`, `… exec -T django pytest -q --cov=etqan` (≥ 80 %).

---
### Task 11: Dashboard foundations — the switch, types, API, hooks, fixtures, strings, routes, nav

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`)
- Modify: `dashboard/src/features/scheduling/schemas.ts` (`ScheduleStatus`, `Substitution`; fields on `Subscription`, `SubscriptionDetail`, `Session`, `TodayRow`, `GenerationResult`; `ACTIVITY_FIELDS`)
- Create: `dashboard/src/features/scheduling/scheduleSchemas.ts`, `scheduleApi.ts`, `scheduleApi.test.ts`, `scheduleQueries.ts`
- Modify: `dashboard/src/features/scheduling/index.ts`
- Modify: `dashboard/src/test/scheduling-fixtures.ts`
- Create: `dashboard/src/locales/en/schedules.json`, `dashboard/src/locales/ar/schedules.json`
- Modify: `dashboard/src/locales/{en,ar}/errors.json` (`scheduling.schedule_deleted`), `dashboard/src/locales/{en,ar}/sessionActivity.json` (`fields.substitute_for_id`)
- Create: `dashboard/src/routes/_authed/scheduling.schedules.index.tsx`, `dashboard/src/routes/_authed/scheduling.schedules.calendar.tsx`
- Modify: `dashboard/src/features/shell/nav.ts`, `nav.test.ts`; `dashboard/src/routes/permissions.test.ts`; `dashboard/src/routeTree.gen.ts` (regenerated)

**Interfaces:**
- Consumes: Task 9's routes and payloads.
- Produces: `FeatureCode` `"weekly_schedules"`; in `schemas.ts`: `SCHEDULE_STATUSES`, `ScheduleStatus`, `Substitution {id, subscription_id, teacher: PersonRef, from_date, to_date}`, `Subscription.schedule_status`, `SubscriptionDetail.substitutions?`, `schedule_changed_at?`, `schedule_changed_by?`, `Session.substitute_for?: PersonRef`, `TodayRow.substitute_for?`, `GenerationResult.skipped_stopped`, `"substitute_for_id"` in `ACTIVITY_FIELDS` after `"teacher_id"`. In `scheduleSchemas.ts`: `SCHEDULE_TABS`, `ScheduleTab`, `SCHEDULE_KINDS`, `ScheduleRowStatus`, `ScheduleBundle`, `ScheduleLine`, `ScheduleMember`, `ScheduleRow`, `ScheduleTargets`, `ScheduleConflict`, `StatusAnswer`, `TeacherChangeAnswer`, `SubstitutionAnswer`, `SubstitutionBody`, `CalendarEntry`, `ScheduleCandidate`, `StatusAction`, `targetsOf(keys: string[]): ScheduleTargets`, `rowName(row): string`. `scheduleApi` (`list`, `calendar`, `candidates`, `setStatus({action, ...targets})`, `changeTeacher`, `addSubstitution`, `removeSubstitution`), `schedulesCsvUrl(params)`. Hooks `useSchedules(params)`, `useScheduleCalendar(params)`, `useScheduleCandidates(q, enabled)` — all under `schedulingKey`. Fixtures `scheduleRow`, `scheduleMember`, `calendarEntry`, `substitutionRow`, `scheduleCandidate`. Routes `/scheduling/schedules/` (`weekly_schedule.view_any`, feature `weekly_schedules`) and `/scheduling/schedules/calendar` (same), each a header for now. Nav "Weekly schedules" under the B2 marker.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/scheduleApi.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { scheduleApi, schedulesCsvUrl } from "./scheduleApi";
import { rowName, targetsOf } from "./scheduleSchemas";
import { scheduleRow } from "@/test/scheduling-fixtures";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
	const ok = () => Promise.resolve({ data: { subscriptions: [] } });
	return {
		...actual,
		api: {
			defaults: { baseURL: "/api/v1/" },
			get: vi.fn(ok),
			post: vi.fn(ok),
			delete: vi.fn(ok),
		},
	};
});

describe("scheduleApi (slice B2g §7)", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads the list, the calendar and the Add candidates", async () => {
		await scheduleApi.list({ tab: "stopped", q: "", page: 2 });
		expect(api.get).toHaveBeenLastCalledWith("schedules/", {
			params: { tab: "stopped", page: "2" },
		});
		await scheduleApi.calendar({ teacher: 21 });
		expect(api.get).toHaveBeenLastCalledWith("schedules/calendar/", {
			params: { teacher: "21" },
		});
		await scheduleApi.candidates("yus");
		expect(api.get).toHaveBeenLastCalledWith("schedules/candidates/", {
			params: { q: "yus" },
		});
		expect(schedulesCsvUrl({ tab: "all", page: 3 })).toBe(
			"/api/v1/schedules/?tab=all&format=csv",
		);
	});

	it("posts each status action to its own route", async () => {
		for (const action of ["stop", "activate", "delete", "restore"] as const) {
			await scheduleApi.setStatus({ action, subscription_ids: [7] });
			expect(api.post).toHaveBeenLastCalledWith(`schedules/${action}/`, {
				subscription_ids: [7],
			});
		}
	});

	it("changes the teacher and adds and removes a substitution", async () => {
		await scheduleApi.changeTeacher({ bundle_ids: [9], teacher_id: 21 });
		expect(api.post).toHaveBeenLastCalledWith("schedules/teacher/", {
			bundle_ids: [9],
			teacher_id: 21,
		});
		const body = {
			subscription_ids: [7],
			teacher_id: 22,
			from_date: "2026-06-08",
			to_date: "2026-06-14",
		};
		await scheduleApi.addSubstitution(body);
		expect(api.post).toHaveBeenLastCalledWith("schedules/substitutions/", body);
		await scheduleApi.removeSubstitution(5);
		expect(api.delete).toHaveBeenLastCalledWith("schedules/substitutions/5/");
	});
});

describe("targetsOf", () => {
	it("splits row keys into subscription and bundle ids", () => {
		expect(targetsOf(["subscription-7", "bundle-9", "subscription-8"])).toEqual(
			{ subscription_ids: [7, 8], bundle_ids: [9] },
		);
		expect(targetsOf(["bundle-9"])).toEqual({ bundle_ids: [9] });
	});
});

describe("rowName", () => {
	it("is the bundle's name, else the student's", () => {
		expect(rowName(scheduleRow())).toBe("Yusuf");
		expect(
			rowName(
				scheduleRow({
					bundle: { id: 9, kind: "group", name: "Evening circle" },
					student: null,
				}),
			),
		).toBe("Evening circle");
	});
});
```

`dashboard/src/features/shell/nav.test.ts` — insert (never paste whole):
- in "ships the grouped admin areas in order", after `"/people/groups",` (under `// Slice B2f`): `// Slice B2g` and `"/scheduling/schedules",`;
- in "hides the items of every feature the academy has switched off", after `"/people/groups", // B2f`: `"/scheduling/schedules", // B2g`;
- in "names a feature on exactly the items that belong to one", after `"/people/groups": "study_groups",`: `// Slice B2g` and `"/scheduling/schedules": "weekly_schedules",`;
- in "groups consecutive items": `expect(groups[1]?.items).toHaveLength(8); // + B6 student levels, upgrades; B2e trials; B2g schedules`.

`dashboard/src/routes/permissions.test.ts` — in `FEATURE_SCREENS`, after `"/_authed/people/groups/": "study_groups",`:

```ts
	// Slice B2g
	"/_authed/scheduling/schedules/": "weekly_schedules",
	"/_authed/scheduling/schedules/calendar": "weekly_schedules",
```

and insert `scheduling\/schedules|` at the start of `FEATURE_WORDS` (`/scheduling\/schedules|people\/groups|families|…/`).

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/scheduleApi.test.ts src/features/shell/nav.test.ts src/routes/permissions.test.ts`
Expected: FAIL — `Failed to resolve import "./scheduleApi"`; nav and screens missing.

- [ ] **Step 3: Implement**

`dashboard/src/features/identity/schemas.ts` — in `FeatureCode`, after `| "group_subscriptions"`:

```ts
	// Slice B2g (Plan 41).
	| "weekly_schedules"
```

`dashboard/src/features/scheduling/schemas.ts`:

After `GroupLabel`:

```ts
/** Slice B2g §3: a subscription's weekly schedule (its slot set). */
export const SCHEDULE_STATUSES = ["active", "stopped", "deleted"] as const;
export type ScheduleStatus = (typeof SCHEDULE_STATUSES)[number];

/** Slice B2g G-5: a substitute for a period (plan D16). */
export interface Substitution {
	id: number;
	subscription_id: number;
	teacher: PersonRef;
	from_date: string;
	to_date: string;
}
```

In `Subscription`, after `status`:

```ts
	// Slice B2g: always (spec §7).
	schedule_status: ScheduleStatus;
```

In `SubscriptionDetail`, after `archived_by`:

```ts
	// Slice B2g (plan D16): the office's — current and future substitutions,
	// and who last changed the schedule's status.
	substitutions?: Substitution[];
	schedule_changed_at?: string | null;
	schedule_changed_by?: PersonRef | null;
```

In `Session`, after `group`:

```ts
	// Slice B2g: only on a substituted session — the teacher stood in for.
	substitute_for?: PersonRef;
```

In `TodayRow`, after `teacher`:

```ts
	// Slice B2g: the row's session is a substitute's.
	substitute_for?: PersonRef;
```

In `GenerationResult`, after `skipped_out_of_term`:

```ts
	// Slice B2g (plan D5): schedules left out because stopped or deleted.
	skipped_stopped: number;
```

In `ACTIVITY_FIELDS`, after `"teacher_id",`: `"substitute_for_id",`.

`dashboard/src/features/scheduling/scheduleSchemas.ts`:

```ts
import type {
	BundleRef,
	NamedRef,
	PersonRef,
	ScheduleStatus,
	Session,
	StudentRef,
	Substitution,
	SubscriptionStatus,
} from "./schemas";

/** Slice B2g §5 (plan D13): TutorHamster's tabs, in order. */
export const SCHEDULE_TABS = [
	"active",
	"stopped",
	"deleted",
	"live_subscription",
	"ended_subscription",
	"all",
] as const;
export type ScheduleTab = (typeof SCHEDULE_TABS)[number];
/** TH's "subscription type": not in a bundle, or a bundle's kind. */
export const SCHEDULE_KINDS = [
	"single",
	"multi_course",
	"family",
	"group",
] as const;
export type ScheduleRowStatus = ScheduleStatus | "mixed";
export type StatusAction = "stop" | "activate" | "delete" | "restore";

export interface ScheduleBundle extends BundleRef {
	name: string;
}
export interface ScheduleLine {
	weekday: number;
	start_time: string;
	end_time: string;
	minutes: number;
	course: NamedRef;
	teacher: PersonRef;
	student: StudentRef | null;
}
export interface ScheduleMember {
	subscription_id: number;
	student: StudentRef;
	course: NamedRef;
	teacher: PersonRef;
	status: SubscriptionStatus;
	schedule_status: ScheduleStatus;
	sessions_used: number;
	sessions_total: number;
	carried_over_sessions: number;
	extra_sessions: number;
	progress: number;
}
export interface ScheduleRow {
	key: string;
	subscription_id: number | null;
	bundle: ScheduleBundle | null;
	student: StudentRef | null;
	status: ScheduleRowStatus;
	members: ScheduleMember[];
	lines: ScheduleLine[];
	substitutions: { teacher: PersonRef; from_date: string; to_date: string }[];
}
export interface ScheduleTargets {
	subscription_ids?: number[];
	bundle_ids?: number[];
}
export interface ScheduleConflict {
	session: Session;
	other: Session;
}
export interface StatusAnswer {
	subscriptions: number[];
}
export interface TeacherChangeAnswer extends StatusAnswer {
	conflicts: ScheduleConflict[];
	outside_availability?: number[];
}
export interface SubstitutionBody extends ScheduleTargets {
	teacher_id: number;
	from_date: string;
	to_date: string;
}
export interface SubstitutionAnswer {
	substitutions: Substitution[];
	conflicts: ScheduleConflict[];
	outside_availability?: number[];
}
export interface CalendarEntry {
	weekday: number;
	start_time: string;
	end_time: string;
	minutes: number;
	course: NamedRef;
	teacher: PersonRef;
	student: StudentRef | null;
	group: string | null;
	subscription_id: number | null;
	bundle_id: number | null;
}
export interface ScheduleCandidate {
	id: number;
	student: StudentRef;
	course: NamedRef;
	teacher: PersonRef;
}

/** The chosen rows' keys (`subscription-<id>` / `bundle-<id>`) as a body:
 * a bundle row acts on its bundle (plan D1). Empty lists are left out. */
export function targetsOf(keys: string[]): ScheduleTargets {
	const ids = (prefix: string) =>
		keys
			.filter((key) => key.startsWith(prefix))
			.map((key) => Number(key.slice(prefix.length)));
	const subscription_ids = ids("subscription-");
	const bundle_ids = ids("bundle-");
	return {
		...(subscription_ids.length ? { subscription_ids } : {}),
		...(bundle_ids.length ? { bundle_ids } : {}),
	};
}

/** A row as people call it: its bundle's name, else its student's. */
export function rowName(row: ScheduleRow): string {
	return row.bundle?.name ?? row.student?.full_name ?? "";
}
```

`dashboard/src/features/scheduling/scheduleApi.ts`:

```ts
import {
	api,
	clean,
	csvUrl,
	type Paginated,
	type QueryParams,
} from "@/lib/api";
import type {
	CalendarEntry,
	ScheduleCandidate,
	ScheduleRow,
	ScheduleTargets,
	StatusAction,
	StatusAnswer,
	SubstitutionAnswer,
	SubstitutionBody,
	TeacherChangeAnswer,
} from "./scheduleSchemas";

const S = "schedules/";

/** Slice B2g §7: the weekly schedule routes. */
export const scheduleApi = {
	list: async (params: QueryParams) =>
		(await api.get<Paginated<ScheduleRow>>(S, { params: clean(params) })).data,
	calendar: async (params: QueryParams) =>
		(
			await api.get<CalendarEntry[]>(`${S}calendar/`, {
				params: clean(params),
			})
		).data,
	candidates: async (q: string) =>
		(
			await api.get<ScheduleCandidate[]>(`${S}candidates/`, {
				params: clean({ q }),
			})
		).data,
	setStatus: async ({
		action,
		...targets
	}: ScheduleTargets & { action: StatusAction }) =>
		(await api.post<StatusAnswer>(`${S}${action}/`, targets)).data,
	changeTeacher: async (body: ScheduleTargets & { teacher_id: number }) =>
		(await api.post<TeacherChangeAnswer>(`${S}teacher/`, body)).data,
	addSubstitution: async (body: SubstitutionBody) =>
		(await api.post<SubstitutionAnswer>(`${S}substitutions/`, body)).data,
	removeSubstitution: async (id: number) => {
		await api.delete(`${S}substitutions/${id}/`);
	},
};

/** G-10: "Download all", with the list's tab and filters. */
export function schedulesCsvUrl(params: QueryParams): string {
	return csvUrl(S, params);
}
```

`dashboard/src/features/scheduling/scheduleQueries.ts`:

```ts
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import type { QueryParams } from "@/lib/api";
import { schedulingKey } from "./queries";
import { scheduleApi } from "./scheduleApi";

/** Slice B2g: under `schedulingKey`, so every scheduling write — a status
 * action, a substitution, a slot — refreshes them (`useSchedulingMutation`). */
export function useSchedules(params: QueryParams) {
	return useQuery({
		queryKey: [...schedulingKey, "schedules", params],
		queryFn: () => scheduleApi.list(params),
		placeholderData: keepPreviousData,
	});
}

export function useScheduleCalendar(params: QueryParams) {
	return useQuery({
		queryKey: [...schedulingKey, "schedule-calendar", params],
		queryFn: () => scheduleApi.calendar(params),
		placeholderData: keepPreviousData,
	});
}

/** Plan D15: the server's Add candidates, fetched while the dialog is open. */
export function useScheduleCandidates(q: string, enabled: boolean) {
	return useQuery({
		queryKey: [...schedulingKey, "schedule-candidates", q],
		queryFn: () => scheduleApi.candidates(q),
		enabled,
	});
}
```

`dashboard/src/features/scheduling/index.ts` — add `export { scheduleApi, schedulesCsvUrl } from "./scheduleApi";`, `export * from "./scheduleQueries";`, `export * from "./scheduleSchemas";`.

`dashboard/src/test/scheduling-fixtures.ts` — `subscriptionRow` gains `schedule_status: "active",` after `status`; `sessionRow`'s fields stay; append:

```ts
/** Slice B2g fixtures (plan D14). */
export function scheduleMember(
	overrides: Partial<ScheduleMember> = {},
): ScheduleMember {
	return {
		subscription_id: 7,
		student: { id: 11, full_name: "Yusuf", timezone: "Asia/Riyadh" },
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		teacher: { id: 21, full_name: "Bilal" },
		status: "active",
		schedule_status: "active",
		sessions_used: 3,
		sessions_total: 8,
		carried_over_sessions: 0,
		extra_sessions: 0,
		progress: 0.375,
		...overrides,
	};
}

export function scheduleRow(overrides: Partial<ScheduleRow> = {}): ScheduleRow {
	return {
		key: "subscription-7",
		subscription_id: 7,
		bundle: null,
		student: { id: 11, full_name: "Yusuf", timezone: "Asia/Riyadh" },
		status: "active",
		members: [scheduleMember()],
		lines: [
			{
				weekday: 0,
				start_time: "18:00",
				end_time: "18:45",
				minutes: 45,
				course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
				teacher: { id: 21, full_name: "Bilal" },
				student: null,
			},
		],
		substitutions: [],
		...overrides,
	};
}

export function calendarEntry(
	overrides: Partial<CalendarEntry> = {},
): CalendarEntry {
	return {
		weekday: 0,
		start_time: "18:00",
		end_time: "18:45",
		minutes: 45,
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		teacher: { id: 21, full_name: "Bilal" },
		student: { id: 11, full_name: "Yusuf", timezone: "Asia/Riyadh" },
		group: null,
		subscription_id: 7,
		bundle_id: null,
		...overrides,
	};
}

export function substitutionRow(
	overrides: Partial<Substitution> = {},
): Substitution {
	return {
		id: 5,
		subscription_id: 7,
		teacher: { id: 22, full_name: "Hamza" },
		from_date: "2026-06-08",
		to_date: "2026-06-14",
		...overrides,
	};
}

export function scheduleCandidate(
	overrides: Partial<ScheduleCandidate> = {},
): ScheduleCandidate {
	return {
		id: 12,
		student: { id: 13, full_name: "Aisha", timezone: "Asia/Riyadh" },
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		teacher: { id: 21, full_name: "Bilal" },
		...overrides,
	};
}
```

with `CalendarEntry`, `ScheduleCandidate`, `ScheduleMember`, `ScheduleRow` imported from `@/features/scheduling/scheduleSchemas` and `Substitution` added to the `schemas` import. Run `… exec -T dashboard pnpm exec tsc --noEmit` and add `schedule_status: "active"` to any other literal `Subscription` it reports (there is none today besides the fixture; `bundleMember` spreads `subscriptionRow`), and `skipped_stopped: 0` to any literal `GenerationResult` in `GenerateDialog.test.tsx`.

`dashboard/src/locales/en/schedules.json`:

```json
{
	"nav": "Weekly schedules",
	"title": "Weekly schedules",
	"subtitle": "Every subscription's weekly timetable: stop and restart it, put it away, or give lessons to a substitute.",
	"tabs": {
		"label": "Schedules",
		"active": "Active",
		"stopped": "Stopped",
		"deleted": "Deleted",
		"live_subscription": "Live subscriptions",
		"ended_subscription": "Ended subscriptions",
		"all": "All"
	},
	"status": {
		"active": "Active",
		"stopped": "Stopped",
		"deleted": "Deleted",
		"mixed": "Mixed"
	},
	"kind": {
		"label": "Subscription type",
		"any": "Any type",
		"single": "Individual",
		"multi_course": "Multi-course",
		"family": "Family",
		"group": "Group"
	},
	"filters": {
		"search": "Search by student",
		"teacher": "Teacher",
		"anyTeacher": "Any teacher",
		"student": "Student",
		"anyStudent": "Any student",
		"group": "Study group",
		"anyGroup": "Any study group"
	},
	"columns": {
		"select": "Select",
		"name": "Student or bundle",
		"lines": "Timetable",
		"progress": "Progress",
		"status": "Status",
		"substitutes": "Substitutes"
	},
	"line": "{{day}} {{start}}–{{end}} · {{course}} · {{teacher}}",
	"lineFor": "{{student}}: {{day}} {{start}}–{{end}} · {{course}} · {{teacher}}",
	"substitution": "{{teacher}}, {{from}} – {{to}}",
	"selectRow": "Select {{name}}",
	"selectPage": "Select every schedule on this page",
	"empty": "No schedules here.",
	"loadError": "Couldn't load the schedules.",
	"download": "Download all",
	"add": {
		"action": "Add schedule",
		"title": "Add a schedule",
		"body": "Pick a live subscription that has no weekly times yet. Its page opens, where you add the times.",
		"search": "Find a subscription",
		"pick": "Add a schedule for {{student}} — {{course}}",
		"none": "No live subscription without times matches."
	},
	"calendar": {
		"action": "Expanded calendar",
		"title": "Expanded calendar",
		"subtitle": "The week of every active schedule. Substitutions and postponements are not shown here.",
		"day": "Day",
		"empty": "Nothing on this day.",
		"back": "Back to the schedules",
		"group": "Group: {{name}}",
		"time": "{{start}}–{{end}}"
	},
	"bulk": {
		"label": "Selected schedules",
		"selected": "Selected: {{count}}",
		"stop": "Stop",
		"activate": "Activate",
		"delete": "Delete",
		"restore": "Restore",
		"teacher": "Change teacher",
		"substitute": "Substitute",
		"stopTitle": "Stop these schedules",
		"stopBody": "No new sessions are created. Future sessions nobody has marked are removed.",
		"deleteTitle": "Delete these schedules",
		"deleteBody": "They move to the Deleted tab and create no sessions. Future sessions nobody has marked are removed. You can restore them.",
		"done_one": "Done for {{count}} subscription.",
		"done_other": "Done for {{count}} subscriptions.",
		"refused": "{{student}} · {{course}}: {{reason}}"
	},
	"teacher": {
		"title": "Change the teacher",
		"body": "The new teacher of every selected schedule. Sessions nobody has marked move to them; substitutions stay.",
		"label": "New teacher",
		"save": "Change teacher",
		"done_one": "The teacher was changed on {{count}} subscription.",
		"done_other": "The teacher was changed on {{count}} subscriptions."
	},
	"substitute": {
		"title": "Give lessons to a substitute",
		"body": "Generated sessions in these dates are taught by the substitute. Postponed and hand-added sessions keep their teacher.",
		"teacher": "Substitute teacher",
		"from": "From",
		"to": "To",
		"save": "Add substitute",
		"done_one": "The substitute was added to {{count}} subscription.",
		"done_other": "The substitute was added to {{count}} subscriptions."
	},
	"clashes": "Sessions overlapping the teacher's other sessions: {{count}}.",
	"outside": "Sessions outside the teacher's availability: {{count}}.",
	"card": {
		"title": "Weekly schedule",
		"stopped": "Schedule stopped",
		"deleted": "Schedule deleted",
		"changed": "Changed on {{date}} by {{name}}",
		"changedBySystem": "Changed on {{date}}",
		"activate": "Activate schedule",
		"restore": "Restore schedule",
		"activated": "The schedule is active again.",
		"restored": "The schedule was restored.",
		"substitutions": "Substitutions",
		"remove": "Remove",
		"removeTitle": "Remove this substitution",
		"removeBody": "Its generated sessions go back to the regular teacher.",
		"removed": "The substitution was removed."
	},
	"substituteFor": "Substitute for {{name}}",
	"generateStopped": "Stopped or deleted schedules left out: {{count}}."
}
```

`dashboard/src/locales/ar/schedules.json`:

```json
{
	"nav": "الجداول الأسبوعية",
	"title": "الجداول الأسبوعية",
	"subtitle": "الجدول الأسبوعي لكل اشتراك: أوقفه أو أعد تشغيله، أو احذفه مؤقتًا، أو أسند حصصه إلى معلم بديل.",
	"tabs": {
		"label": "الجداول",
		"active": "نشطة",
		"stopped": "متوقفة",
		"deleted": "محذوفة",
		"live_subscription": "اشتراكات جارية",
		"ended_subscription": "اشتراكات منتهية",
		"all": "الكل"
	},
	"status": {
		"active": "نشط",
		"stopped": "متوقف",
		"deleted": "محذوف",
		"mixed": "مختلط"
	},
	"kind": {
		"label": "نوع الاشتراك",
		"any": "أي نوع",
		"single": "فردي",
		"multi_course": "متعدد الدورات",
		"family": "عائلي",
		"group": "مجموعة"
	},
	"filters": {
		"search": "ابحث باسم الطالب",
		"teacher": "المعلم",
		"anyTeacher": "أي معلم",
		"student": "الطالب",
		"anyStudent": "أي طالب",
		"group": "المجموعة الدراسية",
		"anyGroup": "أي مجموعة دراسية"
	},
	"columns": {
		"select": "تحديد",
		"name": "الطالب أو الحزمة",
		"lines": "المواعيد",
		"progress": "التقدم",
		"status": "الحالة",
		"substitutes": "البدلاء"
	},
	"line": "{{day}} {{start}}–{{end}} · {{course}} · {{teacher}}",
	"lineFor": "{{student}}: {{day}} {{start}}–{{end}} · {{course}} · {{teacher}}",
	"substitution": "{{teacher}}، {{from}} – {{to}}",
	"selectRow": "تحديد {{name}}",
	"selectPage": "تحديد كل الجداول في هذه الصفحة",
	"empty": "لا توجد جداول هنا.",
	"loadError": "تعذر تحميل الجداول.",
	"download": "تنزيل الكل",
	"add": {
		"action": "إضافة جدول",
		"title": "إضافة جدول",
		"body": "اختر اشتراكًا جاريًا ليست له مواعيد أسبوعية بعد. تُفتح صفحته لتضيف المواعيد فيها.",
		"search": "ابحث عن اشتراك",
		"pick": "إضافة جدول لـ {{student}} — {{course}}",
		"none": "لا يوجد اشتراك جارٍ بلا مواعيد يطابق البحث."
	},
	"calendar": {
		"action": "التقويم الموسّع",
		"title": "التقويم الموسّع",
		"subtitle": "أسبوع كل جدول نشط. لا تظهر هنا الإنابات ولا التأجيلات.",
		"day": "اليوم",
		"empty": "لا شيء في هذا اليوم.",
		"back": "العودة إلى الجداول",
		"group": "المجموعة: {{name}}",
		"time": "{{start}}–{{end}}"
	},
	"bulk": {
		"label": "الجداول المحددة",
		"selected": "المحدد: {{count}}",
		"stop": "إيقاف",
		"activate": "تفعيل",
		"delete": "حذف",
		"restore": "استرجاع",
		"teacher": "تغيير المعلم",
		"substitute": "معلم بديل",
		"stopTitle": "إيقاف هذه الجداول",
		"stopBody": "لن تُنشأ حصص جديدة. تُحذف الحصص القادمة التي لم يسجَّل فيها شيء.",
		"deleteTitle": "حذف هذه الجداول",
		"deleteBody": "تنتقل إلى تبويب المحذوفة ولا تُنشئ حصصًا. تُحذف الحصص القادمة التي لم يسجَّل فيها شيء. يمكنك استرجاعها.",
		"done_zero": "لم يُنفَّذ على أي اشتراك.",
		"done_one": "تم لاشتراك واحد.",
		"done_two": "تم لاشتراكين.",
		"done_few": "تم لـ {{count}} اشتراكات.",
		"done_many": "تم لـ {{count}} اشتراكًا.",
		"done_other": "تم لـ {{count}} اشتراك.",
		"refused": "{{student}} · {{course}}: {{reason}}"
	},
	"teacher": {
		"title": "تغيير المعلم",
		"body": "المعلم الجديد لكل جدول محدد. تنتقل إليه الحصص التي لم يسجَّل فيها شيء، وتبقى الإنابات.",
		"label": "المعلم الجديد",
		"save": "تغيير المعلم",
		"done_zero": "لم يتغير المعلم في أي اشتراك.",
		"done_one": "تم تغيير المعلم في اشتراك واحد.",
		"done_two": "تم تغيير المعلم في اشتراكين.",
		"done_few": "تم تغيير المعلم في {{count}} اشتراكات.",
		"done_many": "تم تغيير المعلم في {{count}} اشتراكًا.",
		"done_other": "تم تغيير المعلم في {{count}} اشتراك."
	},
	"substitute": {
		"title": "إسناد الحصص إلى معلم بديل",
		"body": "يدرّس المعلم البديل الحصص المولّدة في هذه التواريخ. تبقى الحصص المؤجلة والمضافة يدويًا مع معلمها.",
		"teacher": "المعلم البديل",
		"from": "من",
		"to": "إلى",
		"save": "إضافة البديل",
		"done_zero": "لم يُضف البديل إلى أي اشتراك.",
		"done_one": "أُضيف البديل إلى اشتراك واحد.",
		"done_two": "أُضيف البديل إلى اشتراكين.",
		"done_few": "أُضيف البديل إلى {{count}} اشتراكات.",
		"done_many": "أُضيف البديل إلى {{count}} اشتراكًا.",
		"done_other": "أُضيف البديل إلى {{count}} اشتراك."
	},
	"clashes": "حصص تتعارض مع حصص أخرى للمعلم: {{count}}.",
	"outside": "حصص خارج أوقات المعلم المتاحة: {{count}}.",
	"card": {
		"title": "الجدول الأسبوعي",
		"stopped": "الجدول متوقف",
		"deleted": "الجدول محذوف",
		"changed": "تغيّر في {{date}} بواسطة {{name}}",
		"changedBySystem": "تغيّر في {{date}}",
		"activate": "تفعيل الجدول",
		"restore": "استرجاع الجدول",
		"activated": "عاد الجدول نشطًا.",
		"restored": "تم استرجاع الجدول.",
		"substitutions": "الإنابات",
		"remove": "إزالة",
		"removeTitle": "إزالة هذه الإنابة",
		"removeBody": "تعود حصصها المولّدة إلى المعلم الأصلي.",
		"removed": "تمت إزالة الإنابة."
	},
	"substituteFor": "بديلًا عن {{name}}",
	"generateStopped": "جداول متوقفة أو محذوفة لم تُنشأ لها حصص: {{count}}."
}
```

`errors.json` — in `scheduling`, after `"nothing_to_renew"`: en `"schedule_deleted": "This schedule is deleted. Restore it first."`; ar `"schedule_deleted": "هذا الجدول محذوف. استرجعه أولًا."`.

`sessionActivity.json` — in `fields`, after `"teacher_id"`: en `"substitute_for_id": "Substitute for"`; ar `"substitute_for_id": "بديلًا عن"`.

`dashboard/src/routes/_authed/scheduling.schedules.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

// Slice B2g (spec §8): the weekly schedules; the list arrives in Task 13.
export const Route = createFileRoute("/_authed/scheduling/schedules/")({
	staticData: {
		permission: "weekly_schedule.view_any",
		feature: "weekly_schedules",
	},
	component: function SchedulesRoute() {
		const { t } = useTranslation();
		usePageTitle(t("schedules.title"));
		return (
			<PageHeader
				title={t("schedules.title")}
				description={t("schedules.subtitle")}
			/>
		);
	},
});
```

`dashboard/src/routes/_authed/scheduling.schedules.calendar.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

/** Plan D20: `?teacher=&student=` are positive User ids, else left out. */
function positive(value: unknown): number | undefined {
	const n = Number(value);
	return Number.isInteger(n) && n > 0 ? n : undefined;
}

// Slice B2g (G-11): the expanded calendar; the grid arrives in Task 15.
export const Route = createFileRoute("/_authed/scheduling/schedules/calendar")({
	staticData: {
		permission: "weekly_schedule.view_any",
		feature: "weekly_schedules",
	},
	validateSearch: (
		search: Record<string, unknown>,
	): { teacher?: number; student?: number } => {
		const teacher = positive(search.teacher);
		const student = positive(search.student);
		return {
			...(teacher ? { teacher } : {}),
			...(student ? { student } : {}),
		};
	},
	component: function ScheduleCalendarRoute() {
		const { t } = useTranslation();
		usePageTitle(t("schedules.calendar.title"));
		return (
			<PageHeader
				title={t("schedules.calendar.title")}
				description={t("schedules.calendar.subtitle")}
			/>
		);
	},
});
```

`dashboard/src/features/shell/nav.ts` — add `CalendarDays,` to the `lucide-react` import (alphabetical, after `Activity, BookOpen, CalendarClock,`), and under `// ── phase B2 ──`, after B2f's study groups item:

```ts
	// Slice B2g: the office's weekly schedules.
	office(
		"/scheduling/schedules",
		"schedules.nav",
		CalendarDays,
		"scheduling",
		"weekly_schedule.view_any",
		"weekly_schedules",
	),
```

Regenerate the route tree: `… exec -T dashboard pnpm exec vite build`.

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T dashboard pnpm exec tsc --noEmit` then `… exec -T dashboard pnpm exec vitest run src/features/scheduling src/features/shell src/routes src/lib`
Expected: PASS (the ar/en key-equality test included; `activityFormat.test.ts` finds the new field's label).

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/identity/schemas.ts src/features/scheduling/schemas.ts src/features/scheduling/scheduleSchemas.ts src/features/scheduling/scheduleApi.ts src/features/scheduling/scheduleApi.test.ts src/features/scheduling/scheduleQueries.ts src/features/scheduling/index.ts src/test/scheduling-fixtures.ts src/locales/en/schedules.json src/locales/ar/schedules.json src/locales/en/errors.json src/locales/ar/errors.json src/locales/en/sessionActivity.json src/locales/ar/sessionActivity.json src/routes/_authed/scheduling.schedules.index.tsx src/routes/_authed/scheduling.schedules.calendar.tsx src/routeTree.gen.ts src/features/shell/nav.ts src/features/shell/nav.test.ts src/routes/permissions.test.ts
git -C $W/dashboard commit -m "feat(scheduling): weekly schedule types, API, strings, routes and nav (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

(If `tsc` reported other test files needing `schedule_status` or `skipped_stopped`, add them to this commit.)

---
### Task 12: "Substitute for {teacher}" on sessions and the Today board; stopped schedules in a range run

**Files:**
- Create: `dashboard/src/features/scheduling/SubstituteChip.tsx`, `SubstituteChip.test.tsx`
- Modify: `dashboard/src/features/scheduling/SessionsList.tsx`, `SessionsPanel.tsx`, `TeacherSessionTable.tsx`, `FamilySessions.tsx`, `SessionPage.tsx` (the chip right after each `<GroupChip group={session.group} />`)
- Modify: `dashboard/src/features/scheduling/SimpleSessions.tsx`, `FamilyHome.tsx`, `MissingReports.tsx`, `MySupervision.tsx` and their tests (review I-1: every other view naming a session's teacher)
- Modify: `dashboard/src/features/scheduling/TodayBoard.tsx` (the teacher cell), `TodayBoard.test.tsx`
- Modify: `dashboard/src/features/scheduling/GenerateDialog.tsx`, `GenerateDialog.test.tsx`

**Interfaces:**
- Consumes: Task 11's `Session.substitute_for`, `TodayRow.substitute_for`, `GenerationResult.skipped_stopped`, `schedules.substituteFor`, `schedules.generateStopped`.
- Produces: `SubstituteChip({ of }: { of?: PersonRef | null })` — a neutral chip "Substitute for {name}", nothing when `of` is empty.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/SubstituteChip.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { SubstituteChip } from "./SubstituteChip";

describe("SubstituteChip", () => {
	it("names the teacher a substitute stands in for, and nothing else", () => {
		const { container, rerender } = render(
			<SubstituteChip of={{ id: 21, full_name: "Bilal" }} />,
		);
		expect(screen.getByText("Substitute for Bilal")).toBeVisible();
		rerender(<SubstituteChip of={undefined} />);
		expect(container).toBeEmptyDOMElement();
	});
});
```

`dashboard/src/features/scheduling/TodayBoard.test.tsx` — append inside `describe("TodayBoard")`:

```tsx
	it("names a substituted row's teacher and whom they stand in for", async () => {
		vi.mocked(schedulingApi.today).mockResolvedValue({
			date: "2026-06-08",
			rows: [
				todayRow({
					teacher: { id: 22, full_name: "Hamza" },
					substitute_for: { id: 21, full_name: "Bilal" },
				}),
			],
		});
		renderWithRouter(<TodayBoard />, {
			extraPaths: ["/scheduling/subscriptions/$subscriptionId"],
		});
		const row = await screen.findByRole("row", { name: /Yusuf/ });
		expect(within(row).getByText("Hamza")).toBeInTheDocument();
		expect(within(row).getByText("Substitute for Bilal")).toBeInTheDocument();
	});
```

Review I-1 — one test in each of the four other views that name a session's teacher (each inside its file's existing `describe`, reusing its mocks):

`SimpleSessions.test.tsx`:

```tsx
	it("says whom a substitute stands in for (slice B2g)", async () => {
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([
				sessionRow({
					teacher: { id: 22, full_name: "Hamza" },
					substitute_for: { id: 21, full_name: "Bilal" },
				}),
			]),
		);
		renderWithRouter(<SimpleSessions />);
		const list = await screen.findByRole("list", { name: "Sessions" });
		expect(within(list).getByText("Substitute for Bilal")).toBeInTheDocument();
	});
```

`FamilyHome.test.tsx`:

```tsx
	it("says whom a substitute stands in for (slice B2g)", async () => {
		vi.mocked(identityApi.me).mockResolvedValue({
			id: 1,
			email: "s@b.com",
			full_name: "Sara",
			role: "student",
			profiles: ["student"],
			timezone: "Asia/Riyadh",
		});
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([
				sessionRow({
					teacher: { id: 22, full_name: "Hamza" },
					substitute_for: { id: 21, full_name: "Bilal" },
				}),
			]),
		);
		renderWithRouter(<FamilyHome />);
		expect(await screen.findByText("Substitute for Bilal")).toBeInTheDocument();
	});
```

`MissingReports.test.tsx`:

```tsx
	it("says whom a substitute stood in for (slice B2g)", async () => {
		vi.mocked(schedulingApi.missingReports).mockResolvedValue(
			page([
				{
					...ROW,
					teacher: { id: 22, full_name: "Hamza" },
					substitute_for: { id: 21, full_name: "Bilal" },
				},
			]),
		);
		renderWithRouter(<MissingReports asAdmin />);
		const item = await screen.findByRole("listitem");
		expect(within(item).getByText("Substitute for Bilal")).toBeInTheDocument();
	});
```

`MySupervision.test.tsx` (the backend's half is Task 8's `test_the_supervisors_rows_say_whom_a_substitute_stands_in_for`):

```tsx
	it("says whom a substitute stands in for (slice B2g)", async () => {
		vi.mocked(schedulingApi.supervision).mockResolvedValue(
			page([
				supervisedRow({
					teacher: { id: 22, full_name: "Hamza" },
					substitute_for: { id: 21, full_name: "Bilal" },
				}),
			]),
		);
		renderWithRouter(<MySupervision />);
		const table = await screen.findByRole("table");
		expect(within(table).getByText("Substitute for Bilal")).toBeInTheDocument();
	});
```

(Each file already imports `page`, `screen`, `within` and its row fixture; add any of `sessionRow` / `supervisedRow` / `within` a file lacks.)

`dashboard/src/features/scheduling/GenerateDialog.test.tsx` — in "runs a range and lists the double-bookings", the mocked result gains `skipped_stopped: 2,` and, after the summary assertion:

```tsx
		expect(
			within(dialog).getByText("Stopped or deleted schedules left out: 2."),
		).toBeInTheDocument();
```

and add `skipped_stopped: 0,` to every other `GenerationResult` the file mocks (the line stays hidden at 0).

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/SubstituteChip.test.tsx src/features/scheduling/TodayBoard.test.tsx src/features/scheduling/GenerateDialog.test.tsx src/features/scheduling/SimpleSessions.test.tsx src/features/scheduling/FamilyHome.test.tsx src/features/scheduling/MissingReports.test.tsx src/features/scheduling/MySupervision.test.tsx`
Expected: FAIL — `Failed to resolve import "./SubstituteChip"`; no "Substitute for Bilal"; no stopped line.

- [ ] **Step 3: Implement**

`dashboard/src/features/scheduling/SubstituteChip.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { StatusChip } from "@/ui";
import type { PersonRef } from "./schemas";

/** Slice B2g §6: everyone who sees a substituted session sees whom its
 * teacher stands in for; any other session shows nothing. */
export function SubstituteChip({ of }: { of?: PersonRef | null }) {
	const { t } = useTranslation();
	if (!of) return null;
	return (
		<StatusChip tone="neutral">
			{t("schedules.substituteFor", { name: of.full_name })}
		</StatusChip>
	);
}
```

In each of `SessionsList.tsx`, `SessionsPanel.tsx`, `TeacherSessionTable.tsx`, `FamilySessions.tsx` and `SessionPage.tsx`: `import { SubstituteChip } from "./SubstituteChip";` and, right after the existing `<GroupChip group={session.group} />`:

```tsx
<SubstituteChip of={session.substitute_for} />
```

`SimpleSessions.tsx` — right after the `<p>` holding `` `${session.teacher.full_name} · ${localName(session.course)}` ``: `<SubstituteChip of={session.substitute_for} />`.

`FamilyHome.tsx` — right after the `<span>` holding `scheduling.family.sessionLine`: `<SubstituteChip of={session.substitute_for} />`.

`MissingReports.tsx` — right after the `<span>` holding `scheduling.missing.row`: `<SubstituteChip of={session.substitute_for} />`.

`MySupervision.tsx` — the teacher cell becomes:

```tsx
									<td className="p-3">
										<span className="flex flex-wrap items-center gap-1">
											{session.teacher.full_name}
											<SubstituteChip of={session.substitute_for} />
										</span>
									</td>
```

(each file imports `SubstituteChip` from `./SubstituteChip`).

`TodayBoard.tsx` — import `SubstituteChip` and the teacher cell becomes:

```tsx
										<td className="p-3">
											<span className="flex flex-wrap items-center gap-1">
												{row.teacher.full_name}
												<SubstituteChip of={row.substitute_for} />
											</span>
										</td>
```

`GenerateDialog.tsx` — right after the summary `<p className="font-medium">…</p>`:

```tsx
							{result.skipped_stopped > 0 ? (
								<p>
									{t("schedules.generateStopped", {
										count: result.skipped_stopped,
									})}
								</p>
							) : null}
```

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling`
Expected: PASS (the five session views' existing tests unchanged).

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/SubstituteChip.tsx src/features/scheduling/SubstituteChip.test.tsx src/features/scheduling/SessionsList.tsx src/features/scheduling/SessionsPanel.tsx src/features/scheduling/TeacherSessionTable.tsx src/features/scheduling/FamilySessions.tsx src/features/scheduling/SessionPage.tsx src/features/scheduling/SimpleSessions.tsx src/features/scheduling/SimpleSessions.test.tsx src/features/scheduling/FamilyHome.tsx src/features/scheduling/FamilyHome.test.tsx src/features/scheduling/MissingReports.tsx src/features/scheduling/MissingReports.test.tsx src/features/scheduling/MySupervision.tsx src/features/scheduling/MySupervision.test.tsx src/features/scheduling/TodayBoard.tsx src/features/scheduling/TodayBoard.test.tsx src/features/scheduling/GenerateDialog.tsx src/features/scheduling/GenerateDialog.test.tsx
git -C $W/dashboard commit -m "feat(scheduling): substitute labels on sessions and Today; stopped schedules in a range run (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 13: The Weekly schedules list — tabs, filters, bundle rows, Add, Download all, the calendar link

**Files:**
- Create: `dashboard/src/features/scheduling/SchedulesList.tsx`, `SchedulesList.test.tsx`
- Create: `dashboard/src/features/scheduling/AddScheduleDialog.tsx`, `AddScheduleDialog.test.tsx`
- Modify: `dashboard/src/features/scheduling/index.ts` (`SchedulesList`)
- Modify: `dashboard/src/routes/_authed/scheduling.schedules.index.tsx` (renders it)

**Interfaces:**
- Consumes: Task 11's `useSchedules`, `useScheduleCandidates`, `schedulesCsvUrl`, `SCHEDULE_TABS`, `SCHEDULE_KINDS`, `rowName`, fixtures; B2f's `useStudyGroups`; `usePeople`, `useAcademySettings`, `studentTime`, `weekdayName`, `formatDay`.
- Produces: `SchedulesList()` holding `selected: string[]` (row keys) and the page's `rows` (Task 14 mounts its bar there); `ScheduleStatusChip({ status })`; `AddScheduleDialog()`. The search box is the student filter (`q`, plan D13); the teacher, type and study-group selects send `teacher`, `kind`, `group`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/SchedulesList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import {
	academySettings,
	page,
	scheduleMember,
	scheduleRow,
} from "@/test/scheduling-fixtures";
import { bundleApi } from "./bundleApi";
import { scheduleApi } from "./scheduleApi";
import { SchedulesList } from "./SchedulesList";

vi.mock("./scheduleApi", async (orig) => {
	const actual = await orig<typeof import("./scheduleApi")>();
	return {
		...actual,
		scheduleApi: {
			...actual.scheduleApi,
			list: vi.fn(),
			candidates: vi.fn(),
			setStatus: vi.fn(),
		},
	};
});
vi.mock("./bundleApi", async (orig) => {
	const actual = await orig<typeof import("./bundleApi")>();
	return { ...actual, bundleApi: { ...actual.bundleApi, groups: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

const GROUP = scheduleRow({
	key: "bundle-9",
	subscription_id: null,
	bundle: { id: 9, kind: "group", name: "Evening circle" },
	student: null,
	status: "mixed",
	members: [
		scheduleMember({
			subscription_id: 12,
			student: { id: 15, full_name: "Zaid", timezone: "UTC" },
		}),
		scheduleMember({
			subscription_id: 13,
			student: { id: 14, full_name: "Aisha", timezone: "UTC" },
			schedule_status: "stopped",
		}),
	],
	substitutions: [
		{
			teacher: { id: 22, full_name: "Hamza" },
			from_date: "2026-06-08",
			to_date: "2026-06-14",
		},
	],
});

function lastParams() {
	return vi.mocked(scheduleApi.list).mock.calls.at(-1)?.[0];
}

describe("SchedulesList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 21, user: { full_name: "Bilal" } }]) as never,
		);
		vi.mocked(bundleApi.groups).mockResolvedValue(page([]) as never);
		vi.mocked(scheduleApi.list).mockResolvedValue(
			page([scheduleRow(), GROUP]) as never,
		);
		vi.mocked(scheduleApi.candidates).mockResolvedValue([]);
	});

	it("shows each row's timetable, progress, status and substitutes", async () => {
		renderWithRouter(<SchedulesList />, {
			extraPaths: [
				"/scheduling/subscriptions/$subscriptionId",
				"/scheduling/bundles/$bundleId",
			],
		});
		const yusuf = await screen.findByRole("row", { name: /Yusuf/ });
		expect(
			within(yusuf).getByText("Mon 18:00–18:45 · Tajweed · Bilal"),
		).toBeInTheDocument();
		// The academy is on UTC; the student on Riyadh's clock.
		expect(
			within(yusuf).getByText("Student's time: 21:00"),
		).toBeInTheDocument();
		expect(within(yusuf).getByText("Active")).toBeInTheDocument();
		expect(within(yusuf).getByRole("link", { name: "Yusuf" })).toHaveAttribute(
			"href",
			"/scheduling/subscriptions/7",
		);
		const group = screen.getByRole("row", { name: /Evening circle/ });
		expect(within(group).getByText("Mixed")).toBeInTheDocument();
		expect(within(group).getByText("Group")).toBeInTheDocument();
		expect(
			within(group).getByRole("link", { name: "Evening circle" }),
		).toHaveAttribute("href", "/scheduling/bundles/9");
		expect(
			within(group).getByText("Hamza, Jun 8, 2026 – Jun 14, 2026"),
		).toBeInTheDocument();
	});

	it("asks the server for each tab and filter", async () => {
		const user = userEvent.setup();
		renderWithRouter(<SchedulesList />);
		await screen.findByRole("row", { name: /Yusuf/ });
		expect(lastParams()).toEqual({ page: 1, tab: "active" });
		await user.click(screen.getByRole("tab", { name: "Stopped" }));
		await waitFor(() =>
			expect(lastParams()).toEqual({ page: 1, tab: "stopped" }),
		);
		await user.type(screen.getByRole("searchbox"), "ai");
		await waitFor(() => expect(lastParams()).toMatchObject({ q: "ai" }));
		await user.selectOptions(
			screen.getByLabelText("Subscription type"),
			"single",
		);
		await waitFor(() => expect(lastParams()).toMatchObject({ kind: "single" }));
		// Review I-2: the teachers arrive after the select renders.
		await screen.findByRole("option", { name: "Bilal" });
		await user.selectOptions(screen.getByLabelText("Teacher"), "21");
		await waitFor(() => expect(lastParams()).toMatchObject({ teacher: "21" }));
	});

	it("links Download all and the calendar with the list's filters", async () => {
		const user = userEvent.setup();
		renderWithRouter(<SchedulesList />, {
			extraPaths: ["/scheduling/schedules/calendar"],
		});
		await screen.findByRole("row", { name: /Yusuf/ });
		// Review I-2: the teachers arrive after the select renders.
		await screen.findByRole("option", { name: "Bilal" });
		await user.selectOptions(screen.getByLabelText("Teacher"), "21");
		await waitFor(() =>
			expect(
				screen.getByRole("link", { name: "Download all" }),
			).toHaveAttribute(
				"href",
				"/api/v1/schedules/?tab=active&teacher=21&format=csv",
			),
		);
		expect(
			screen.getByRole("link", { name: "Expanded calendar" }),
		).toHaveAttribute("href", "/scheduling/schedules/calendar?teacher=21");
	});

	it("says so when there is no schedule", async () => {
		vi.mocked(scheduleApi.list).mockResolvedValue(page([]) as never);
		renderWithRouter(<SchedulesList />);
		expect(await screen.findByText("No schedules here.")).toBeInTheDocument();
	});
});
```

`dashboard/src/features/scheduling/AddScheduleDialog.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { scheduleCandidate } from "@/test/scheduling-fixtures";
import { AddScheduleDialog } from "./AddScheduleDialog";
import { scheduleApi } from "./scheduleApi";

vi.mock("./scheduleApi", async (orig) => {
	const actual = await orig<typeof import("./scheduleApi")>();
	return {
		...actual,
		scheduleApi: { ...actual.scheduleApi, candidates: vi.fn() },
	};
});

describe("AddScheduleDialog (plan D15)", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(scheduleApi.candidates).mockResolvedValue([scheduleCandidate()]);
	});

	it("searches the server's candidates and opens the chosen subscription", async () => {
		const user = userEvent.setup();
		renderWithRouter(<AddScheduleDialog />, {
			extraPaths: ["/scheduling/subscriptions/$subscriptionId"],
		});
		await user.click(await screen.findByRole("button", { name: "Add schedule" }));
		await user.type(screen.getByLabelText("Find a subscription"), "ai");
		await waitFor(() =>
			expect(scheduleApi.candidates).toHaveBeenLastCalledWith("ai"),
		);
		await user.click(
			await screen.findByRole("button", {
				name: "Add a schedule for Aisha — Tajweed",
			}),
		);
		expect(
			await screen.findByText("at /scheduling/subscriptions/$subscriptionId"),
		).toBeInTheDocument();
	});

	it("says so when nothing matches", async () => {
		vi.mocked(scheduleApi.candidates).mockResolvedValue([]);
		const user = userEvent.setup();
		renderWithRouter(<AddScheduleDialog />);
		await user.click(await screen.findByRole("button", { name: "Add schedule" }));
		expect(
			await screen.findByText("No live subscription without times matches."),
		).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/SchedulesList.test.tsx src/features/scheduling/AddScheduleDialog.test.tsx`
Expected: FAIL — `Failed to resolve import "./SchedulesList"`.

- [ ] **Step 3: Implement**

`dashboard/src/features/scheduling/AddScheduleDialog.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	Button,
	Dialog,
	DialogContent,
	DialogDescription,
	DialogTitle,
	DialogTrigger,
	Input,
	Spinner,
} from "@/ui";
import { useLocalName } from "./bits";
import { useScheduleCandidates } from "./scheduleQueries";

/** Spec §8 "Add" (plan D15): pick a live subscription without slots — the
 * server's list — and open its page, whose Slots panel adds the times. */
export function AddScheduleDialog() {
	const { t } = useTranslation();
	const localName = useLocalName();
	const navigate = useNavigate();
	const [open, setOpen] = useState(false);
	const [q, setQ] = useState("");
	const { data, isPending } = useScheduleCandidates(q, open);

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm">
					<Plus className="size-4" />
					{t("schedules.add.action")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("schedules.add.title")}</DialogTitle>
				<DialogDescription>{t("schedules.add.body")}</DialogDescription>
				<div className="mt-4 flex flex-col gap-3">
					<label htmlFor="schedule-candidates" className="text-sm font-medium">
						{t("schedules.add.search")}
					</label>
					<Input
						id="schedule-candidates"
						type="search"
						value={q}
						onChange={(e) => setQ(e.target.value)}
					/>
					{isPending ? (
						<Spinner />
					) : data && data.length > 0 ? (
						<ul className="flex flex-col gap-2">
							{data.map((found) => (
								<li key={found.id}>
									<Button
										type="button"
										variant="outline"
										size="sm"
										className="w-full justify-start"
										onClick={() => {
											setOpen(false);
											void navigate({
												to: "/scheduling/subscriptions/$subscriptionId",
												params: { subscriptionId: String(found.id) },
											});
										}}
									>
										{t("schedules.add.pick", {
											student: found.student.full_name,
											course: localName(found.course),
										})}
									</Button>
								</li>
							))}
						</ul>
					) : (
						<p className="text-sm text-muted-foreground">
							{t("schedules.add.none")}
						</p>
					)}
				</div>
			</DialogContent>
		</Dialog>
	);
}
```

`dashboard/src/features/scheduling/SchedulesList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { CalendarDays } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { useAcademySettings } from "@/features/academy/queries";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { usePeople } from "@/features/people";
import type { QueryParams } from "@/lib/api";
import { formatDay, studentTime, todayIn, weekdayName } from "@/lib/zoned-time";
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
import { AddScheduleDialog } from "./AddScheduleDialog";
import { SubscriptionProgress, useLocalName } from "./bits";
import { useStudyGroups } from "./bundleQueries";
import { schedulesCsvUrl } from "./scheduleApi";
import { useSchedules } from "./scheduleQueries";
import {
	rowName,
	SCHEDULE_KINDS,
	SCHEDULE_TABS,
	type ScheduleRow,
	type ScheduleRowStatus,
} from "./scheduleSchemas";

// The backend paginates at 25 rows a page (StandardPagination).
const PAGE_SIZE = 25;
const LINK = "font-medium text-primary-text underline-offset-4 hover:underline";
const TONE: Record<ScheduleRowStatus, "live" | "neutral" | "warning"> = {
	active: "live",
	stopped: "neutral",
	deleted: "warning",
	mixed: "neutral",
};

export function ScheduleStatusChip({ status }: { status: ScheduleRowStatus }) {
	const { t } = useTranslation();
	return (
		<StatusChip tone={TONE[status]}>{t(`schedules.status.${status}`)}</StatusChip>
	);
}

function Lines({ row, zone }: { row: ScheduleRow; zone?: string }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	return (
		<ul className="flex flex-col gap-1">
			{row.lines.map((line) => {
				const values = {
					day: weekdayName(line.weekday, i18n.language),
					start: line.start_time,
					end: line.end_time,
					course: localName(line.course),
					teacher: line.teacher.full_name,
				};
				// B2-15: academy time, plus the student's when it differs.
				const theirs = zone
					? studentTime({
							date: todayIn(zone),
							time: line.start_time,
							academyZone: zone,
							studentZone: (line.student ?? row.student)?.timezone,
							language: i18n.language,
						})
					: null;
				return (
					<li
						key={`${line.weekday}-${line.start_time}-${line.course.id}-${line.teacher.id}-${line.student?.id ?? 0}`}
					>
						{line.student
							? t("schedules.lineFor", {
									...values,
									student: line.student.full_name,
								})
							: t("schedules.line", values)}
						{theirs ? (
							<span className="block text-xs text-muted-foreground">
								{t("scheduling.slots.studentTime", { time: theirs })}
							</span>
						) : null}
					</li>
				);
			})}
		</ul>
	);
}

function NameCell({ row }: { row: ScheduleRow }) {
	const { t } = useTranslation();
	if (row.bundle) {
		return (
			<span className="flex flex-col gap-1">
				<Link
					to="/scheduling/bundles/$bundleId"
					params={{ bundleId: String(row.bundle.id) }}
					className={LINK}
				>
					{row.bundle.name}
				</Link>
				<span className="text-xs text-muted-foreground">
					{t(`schedules.kind.${row.bundle.kind}`)}
				</span>
			</span>
		);
	}
	return (
		<Link
			to="/scheduling/subscriptions/$subscriptionId"
			params={{ subscriptionId: String(row.subscription_id) }}
			className={LINK}
		>
			{row.student?.full_name}
		</Link>
	);
}

/** Spec §8 Weekly schedules: TH's tabs, filters and rows; a bundle is one
 * row (plan D13). The bulk bar acts on the chosen rows; the choice is
 * cleared whenever the query changes. */
export function SchedulesList() {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	const [params, setParams] = useState<QueryParams>({ page: 1, tab: "active" });
	const [selected, setSelected] = useState<string[]>([]);
	const { data, isPending, isError } = useSchedules(params);
	const { data: academy } = useAcademySettings();
	const listTeachers = can("teacher.view_any");
	const { data: teachers } = usePeople(
		"teachers",
		{ page_size: 100 },
		{ enabled: listTeachers },
	);
	const listGroups = can("study_group.view_any") && hasFeature("study_groups");
	const { data: groups } = useStudyGroups(
		{ page_size: 100 },
		{ enabled: listGroups },
	);
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const keys = rows.map((row) => row.key);
	const allChosen = keys.length > 0 && keys.every((k) => selected.includes(k));
	const teacher = params.teacher ? Number(params.teacher) : undefined;
	const update = (patch: QueryParams) => {
		setParams({ ...params, page: 1, ...patch });
		setSelected([]);
	};
	const toggle = (key: string) =>
		setSelected(
			selected.includes(key)
				? selected.filter((k) => k !== key)
				: [...selected, key],
		);
	const day = (value: string) => formatDay(value, i18n.language);

	return (
		<div className="flex flex-col gap-4">
			<div
				role="tablist"
				aria-label={t("schedules.tabs.label")}
				className="flex flex-wrap gap-2 border-b border-border pb-2"
			>
				{SCHEDULE_TABS.map((tab) => (
					<button
						key={tab}
						type="button"
						role="tab"
						aria-selected={params.tab === tab}
						onClick={() => update({ tab })}
						className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
					>
						{t(`schedules.tabs.${tab}`)}
					</button>
				))}
			</div>
			<div className="flex flex-wrap items-end gap-3">
				<div className="min-w-48 flex-1">
					<label htmlFor="schedules-search" className="sr-only">
						{t("schedules.filters.search")}
					</label>
					<Input
						id="schedules-search"
						type="search"
						placeholder={t("schedules.filters.search")}
						value={String(params.q ?? "")}
						onChange={(e) => update({ q: e.target.value })}
					/>
				</div>
				{listTeachers ? (
					<Select
						aria-label={t("schedules.filters.teacher")}
						className="w-auto"
						value={String(params.teacher ?? "")}
						onChange={(e) => update({ teacher: e.target.value })}
					>
						<option value="">{t("schedules.filters.anyTeacher")}</option>
						{teachers?.results.map((p) => (
							<option key={p.id} value={p.id}>
								{p.user.full_name}
							</option>
						))}
					</Select>
				) : null}
				<Select
					aria-label={t("schedules.kind.label")}
					className="w-auto"
					value={String(params.kind ?? "")}
					onChange={(e) => update({ kind: e.target.value })}
				>
					<option value="">{t("schedules.kind.any")}</option>
					{SCHEDULE_KINDS.map((kind) => (
						<option key={kind} value={kind}>
							{t(`schedules.kind.${kind}`)}
						</option>
					))}
				</Select>
				{listGroups ? (
					<Select
						aria-label={t("schedules.filters.group")}
						className="w-auto"
						value={String(params.group ?? "")}
						onChange={(e) => update({ group: e.target.value })}
					>
						<option value="">{t("schedules.filters.anyGroup")}</option>
						{groups?.results.map((g) => (
							<option key={g.id} value={g.id}>
								{g.name}
							</option>
						))}
					</Select>
				) : null}
				{hasFeature("export") ? (
					<Button asChild variant="outline" size="sm">
						<a href={schedulesCsvUrl(params)} download>
							{t("schedules.download")}
						</a>
					</Button>
				) : null}
				<Button asChild variant="outline" size="sm">
					<Link
						to="/scheduling/schedules/calendar"
						search={teacher ? { teacher } : {}}
					>
						<CalendarDays className="size-4" />
						{t("schedules.calendar.action")}
					</Link>
				</Button>
				{can("weekly_schedule.update") && can("subscription.update") ? (
					<AddScheduleDialog />
				) : null}
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("schedules.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={CalendarDays} title={t("schedules.empty")} />
					</CardContent>
				</Card>
			) : (
				// `relative`: the sr-only header text never widens the page.
				<div className="relative overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								<th scope="col" className="w-10 p-3">
									<Checkbox
										id="select-schedules"
										checked={allChosen}
										onCheckedChange={(on) =>
											setSelected(
												on
													? [...new Set([...selected, ...keys])]
													: selected.filter((k) => !keys.includes(k)),
											)
										}
									/>
									<label htmlFor="select-schedules" className="sr-only">
										{t("schedules.selectPage")}
									</label>
								</th>
								{(
									["name", "lines", "progress", "status", "substitutes"] as const
								).map((key) => (
									<th
										key={key}
										scope="col"
										className="p-3 text-start font-medium"
									>
										{t(`schedules.columns.${key}`)}
									</th>
								))}
							</tr>
						</thead>
						<tbody>
							{rows.map((row) => (
								<tr key={row.key} className="border-t border-border align-top">
									<td className="p-3">
										<Checkbox
											id={`select-${row.key}`}
											checked={selected.includes(row.key)}
											onCheckedChange={() => toggle(row.key)}
										/>
										<label htmlFor={`select-${row.key}`} className="sr-only">
											{t("schedules.selectRow", { name: rowName(row) })}
										</label>
									</td>
									<td className="p-3">
										<NameCell row={row} />
									</td>
									<td className="p-3">
										<Lines row={row} zone={academy?.timezone} />
									</td>
									<td className="p-3">
										<div className="flex flex-col gap-2">
											{row.members.map((m) => (
												<SubscriptionProgress
													key={m.subscription_id}
													name={m.student.full_name}
													used={m.sessions_used}
													carried={m.carried_over_sessions}
													total={m.sessions_total}
													extra={m.extra_sessions}
												/>
											))}
										</div>
									</td>
									<td className="p-3">
										<ScheduleStatusChip status={row.status} />
									</td>
									<td className="p-3">
										<ul className="flex flex-col gap-1">
											{row.substitutions.map((s) => (
												<li key={`${s.teacher.id}-${s.from_date}-${s.to_date}`}>
													{t("schedules.substitution", {
														teacher: s.teacher.full_name,
														from: day(s.from_date),
														to: day(s.to_date),
													})}
												</li>
											))}
										</ul>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => {
					setParams({ ...params, page: next });
					setSelected([]);
				}}
			/>
		</div>
	);
}
```

`index.ts` — `export { SchedulesList } from "./SchedulesList";`.

`scheduling.schedules.index.tsx` — import `SchedulesList` from `@/features/scheduling`, and render it after the header:

```tsx
		return (
			<>
				<PageHeader
					title={t("schedules.title")}
					description={t("schedules.subtitle")}
				/>
				<SchedulesList />
			</>
		);
```

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/SchedulesList.test.tsx src/features/scheduling/AddScheduleDialog.test.tsx` then `… exec -T dashboard pnpm exec tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/SchedulesList.tsx src/features/scheduling/SchedulesList.test.tsx src/features/scheduling/AddScheduleDialog.tsx src/features/scheduling/AddScheduleDialog.test.tsx src/features/scheduling/index.ts src/routes/_authed/scheduling.schedules.index.tsx
git -C $W/dashboard commit -m "feat(scheduling): the weekly schedules list with bundle rows, Add and Download all (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 14: Bulk actions — Stop, Activate, Delete, Restore, Change teacher, Substitute

**Files:**
- Modify: `dashboard/src/features/scheduling/refusal.ts` (`refusalReason`, extracted from `refusalText`)
- Create: `dashboard/src/features/scheduling/scheduleRefusal.ts`, `scheduleRefusal.test.ts`
- Create: `dashboard/src/features/scheduling/ScheduleActions.tsx`, `ScheduleActions.test.tsx`
- Create: `dashboard/src/features/scheduling/ScheduleTeacherDialog.tsx`, `SubstituteDialog.tsx`, `ScheduleDialogs.test.tsx`
- Modify: `dashboard/src/features/scheduling/SchedulesList.tsx` (mounts the bar)

**Interfaces:**
- Consumes: Task 11's `scheduleApi.setStatus` / `changeTeacher` / `addSubstitution`, `targetsOf`, `ScheduleRow`; Task 13's `SchedulesList` state; B2f's `memberIdOf`; `parseApiError`, `codeKey`, `isoDate`; `usePeople`.
- Produces: `refusalReason(error, t): string` (in `refusal.ts`); `scheduleRefusal(error, rows, t, localName): string` (plan D22); `ScheduleActions({ selected, rows, onDone })` — nothing while `selected` is empty; `ScheduleTeacherDialog({ targets, rows, onDone })`; `SubstituteDialog({ targets, rows, onDone })`. Each shows the buttons its code allows: `weekly_schedule.update` (Stop, Activate, Change teacher, Substitute), `weekly_schedule.delete` (Delete), `weekly_schedule.restore` (Restore).

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/scheduleRefusal.test.ts`:

```ts
import { AxiosError, type AxiosResponse } from "axios";
import i18n from "i18next";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { scheduleMember, scheduleRow } from "@/test/scheduling-fixtures";
import { scheduleRefusal } from "./scheduleRefusal";

function refused(status: number, data: object) {
	const error = new AxiosError("refused");
	error.response = { status, data } as AxiosResponse;
	return error;
}

const rows = [
	scheduleRow({
		members: [
			scheduleMember({
				subscription_id: 12,
				student: { id: 15, full_name: "Zaid", timezone: "UTC" },
			}),
		],
	}),
];
const local = (named: { name_en: string }) => named.name_en;

describe("scheduleRefusal (plan D22)", () => {
	it("names the subscription the server names", () => {
		const error = refused(409, {
			detail: "This schedule is deleted. Restore it first.",
			code: "scheduling.schedule_deleted",
			member_id: 12,
		});
		expect(scheduleRefusal(error, rows, i18n.t, local)).toBe(
			"Zaid · Tajweed: This schedule is deleted. Restore it first.",
		);
	});

	it("reads a field's message when there is no code", () => {
		const error = refused(400, {
			teacher_id: ["Choose an active teacher."],
			member_id: 12,
		});
		expect(scheduleRefusal(error, rows, i18n.t, local)).toBe(
			"Zaid · Tajweed: Choose an active teacher.",
		);
	});

	it("is the reason alone when no subscription is named", () => {
		const error = refused(409, {
			detail: "Nothing in this bundle is live.",
			code: "scheduling.not_allowed_in_status",
		});
		expect(scheduleRefusal(error, rows, i18n.t, local)).toBe(
			"That isn't possible in the current status.",
		);
	});
});
```

`dashboard/src/features/scheduling/ScheduleActions.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { peopleApi } from "@/features/people/api";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { page, scheduleRow } from "@/test/scheduling-fixtures";
import { ScheduleActions } from "./ScheduleActions";
import { scheduleApi } from "./scheduleApi";

vi.mock("./scheduleApi", async (orig) => {
	const actual = await orig<typeof import("./scheduleApi")>();
	return {
		...actual,
		scheduleApi: { ...actual.scheduleApi, setStatus: vi.fn() },
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

const SELECTED = ["subscription-7", "bundle-9"];

describe("ScheduleActions", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(page([]) as never);
		vi.mocked(scheduleApi.setStatus).mockResolvedValue({
			subscriptions: [7, 12, 13],
		});
	});

	it("shows nothing while no row is chosen", async () => {
		renderWithRouter(
			<>
				<p>marker</p>
				<ScheduleActions selected={[]} rows={[]} onDone={vi.fn()} />
			</>,
		);
		await screen.findByText("marker");
		expect(screen.queryByRole("region", { name: "Selected schedules" })).toBeNull();
	});

	it("stops the chosen rows after a confirmation", async () => {
		const done = vi.fn();
		const user = userEvent.setup();
		renderWithRouter(
			<ScheduleActions selected={SELECTED} rows={[scheduleRow()]} onDone={done} />,
		);
		const bar = await screen.findByRole("region", { name: "Selected schedules" });
		expect(within(bar).getByText("Selected: 2")).toBeInTheDocument();
		await user.click(within(bar).getByRole("button", { name: "Stop" }));
		await user.click(
			screen.getByRole("button", { name: "Stop these schedules" }),
		);
		await waitFor(() =>
			expect(scheduleApi.setStatus).toHaveBeenCalledWith({
				action: "stop",
				subscription_ids: [7],
				bundle_ids: [9],
			}),
		);
		expect(await screen.findByText("Done for 3 subscriptions.")).toBeVisible();
		expect(done).toHaveBeenCalled();
	});

	it("activates and restores without a confirmation", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<ScheduleActions selected={SELECTED} rows={[]} onDone={vi.fn()} />,
		);
		await user.click(await screen.findByRole("button", { name: "Activate" }));
		// The buttons wait while one action runs: let the first one finish.
		expect(await screen.findByText("Done for 3 subscriptions.")).toBeVisible();
		await user.click(screen.getByRole("button", { name: "Restore" }));
		await waitFor(() =>
			expect(
				vi.mocked(scheduleApi.setStatus).mock.calls.map(([body]) => body.action),
			).toEqual(["activate", "restore"]),
		);
	});

	it("toasts a refusal naming the subscription", async () => {
		const error = new AxiosError("refused");
		error.response = {
			status: 409,
			data: {
				detail: "This schedule is deleted. Restore it first.",
				code: "scheduling.schedule_deleted",
				member_id: 7,
			},
		} as AxiosResponse;
		vi.mocked(scheduleApi.setStatus).mockRejectedValueOnce(error);
		const user = userEvent.setup();
		renderWithRouter(
			<ScheduleActions selected={SELECTED} rows={[scheduleRow()]} onDone={vi.fn()} />,
		);
		await user.click(await screen.findByRole("button", { name: "Activate" }));
		expect(
			await screen.findByText(
				"Yusuf · Tajweed: This schedule is deleted. Restore it first.",
			),
		).toBeVisible();
	});

	it("offers each action only with its code", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("weekly_schedule.restore")}>
				<ScheduleActions selected={SELECTED} rows={[]} onDone={vi.fn()} />
			</CanProvider>,
		);
		const bar = await screen.findByRole("region", { name: "Selected schedules" });
		expect(within(bar).getByRole("button", { name: "Restore" })).toBeVisible();
		for (const name of [
			"Stop",
			"Activate",
			"Delete",
			"Change teacher",
			"Substitute",
		]) {
			expect(within(bar).queryByRole("button", { name })).toBeNull();
		}
	});
});
```

`dashboard/src/features/scheduling/ScheduleDialogs.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { page, scheduleRow, substitutionRow } from "@/test/scheduling-fixtures";
import { scheduleApi } from "./scheduleApi";
import { ScheduleTeacherDialog } from "./ScheduleTeacherDialog";
import { SubstituteDialog } from "./SubstituteDialog";

vi.mock("./scheduleApi", async (orig) => {
	const actual = await orig<typeof import("./scheduleApi")>();
	return {
		...actual,
		scheduleApi: {
			...actual.scheduleApi,
			changeTeacher: vi.fn(),
			addSubstitution: vi.fn(),
		},
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

const TARGETS = { subscription_ids: [7] };
const ROWS = [scheduleRow()];

describe("ScheduleTeacherDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 22, user: { full_name: "Hamza" } }]) as never,
		);
		vi.mocked(scheduleApi.changeTeacher).mockResolvedValue({
			subscriptions: [7],
			conflicts: [],
		});
	});

	it("sends the new teacher for the chosen schedules", async () => {
		const done = vi.fn();
		const user = userEvent.setup();
		renderWithRouter(
			<ScheduleTeacherDialog targets={TARGETS} rows={ROWS} onDone={done} />,
		);
		await user.click(await screen.findByRole("button", { name: "Change teacher" }));
		// Review I-2: the list loads once the dialog opens.
		await screen.findByRole("option", { name: "Hamza" });
		await user.selectOptions(screen.getByLabelText(/^New teacher/), "22");
		await user.click(
			screen.getAllByRole("button", { name: "Change teacher" }).at(-1) as HTMLElement,
		);
		await waitFor(() =>
			expect(scheduleApi.changeTeacher).toHaveBeenCalledWith({
				subscription_ids: [7],
				teacher_id: 22,
			}),
		);
		expect(
			await screen.findByText("The teacher was changed on 1 subscription."),
		).toBeVisible();
		expect(done).toHaveBeenCalled();
	});

	it("names the refusing subscription inside the dialog", async () => {
		const error = new AxiosError("refused");
		error.response = {
			status: 400,
			data: { teacher_id: ["This teacher does not teach the course."], member_id: 7 },
		} as AxiosResponse;
		vi.mocked(scheduleApi.changeTeacher).mockRejectedValueOnce(error);
		const user = userEvent.setup();
		renderWithRouter(
			<ScheduleTeacherDialog targets={TARGETS} rows={ROWS} onDone={vi.fn()} />,
		);
		await user.click(await screen.findByRole("button", { name: "Change teacher" }));
		// Review I-2: the list loads once the dialog opens.
		await screen.findByRole("option", { name: "Hamza" });
		await user.selectOptions(screen.getByLabelText(/^New teacher/), "22");
		await user.click(
			screen.getAllByRole("button", { name: "Change teacher" }).at(-1) as HTMLElement,
		);
		expect(
			await screen.findByText(
				"Yusuf · Tajweed: This teacher does not teach the course.",
			),
		).toBeVisible();
	});
});

describe("SubstituteDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 22, user: { full_name: "Hamza" } }]) as never,
		);
		vi.mocked(scheduleApi.addSubstitution).mockResolvedValue({
			substitutions: [substitutionRow()],
			conflicts: [],
			outside_availability: [41],
		});
	});

	it("adds the substitute for the dates and reports the warnings", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<SubstituteDialog targets={TARGETS} rows={ROWS} onDone={vi.fn()} />,
		);
		await user.click(await screen.findByRole("button", { name: "Substitute" }));
		await screen.findByRole("option", { name: "Hamza" });
		await user.selectOptions(screen.getByLabelText(/^Substitute teacher/), "22");
		await user.type(screen.getByLabelText(/^From/), "2026-06-08");
		await user.type(screen.getByLabelText(/^To/), "2026-06-14");
		await user.click(screen.getByRole("button", { name: "Add substitute" }));
		await waitFor(() =>
			expect(scheduleApi.addSubstitution).toHaveBeenCalledWith({
				subscription_ids: [7],
				teacher_id: 22,
				from_date: "2026-06-08",
				to_date: "2026-06-14",
			}),
		);
		expect(
			await screen.findByText(
				"The substitute was added to 1 subscription. Sessions outside the teacher's availability: 1.",
			),
		).toBeVisible();
	});

	it("checks the dates before sending and shows the server's own", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<SubstituteDialog targets={TARGETS} rows={ROWS} onDone={vi.fn()} />,
		);
		await user.click(await screen.findByRole("button", { name: "Substitute" }));
		await screen.findByRole("option", { name: "Hamza" });
		await user.selectOptions(screen.getByLabelText(/^Substitute teacher/), "22");
		await user.type(screen.getByLabelText(/^From/), "2026-06-14");
		await user.type(screen.getByLabelText(/^To/), "2026-06-08");
		await user.click(screen.getByRole("button", { name: "Add substitute" }));
		expect(
			await screen.findByText("End on or after the start."),
		).toBeVisible();
		expect(scheduleApi.addSubstitution).not.toHaveBeenCalled();
		const error = new AxiosError("refused");
		error.response = {
			status: 400,
			data: { from_date: ["Start the substitution today or later."] },
		} as AxiosResponse;
		vi.mocked(scheduleApi.addSubstitution).mockRejectedValueOnce(error);
		await user.clear(screen.getByLabelText(/^To/));
		await user.type(screen.getByLabelText(/^To/), "2026-06-20");
		await user.click(screen.getByRole("button", { name: "Add substitute" }));
		expect(
			await screen.findByText("Start the substitution today or later."),
		).toBeVisible();
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/scheduleRefusal.test.ts src/features/scheduling/ScheduleActions.test.tsx src/features/scheduling/ScheduleDialogs.test.tsx`
Expected: FAIL — `Failed to resolve import "./scheduleRefusal"`.

- [ ] **Step 3: Implement**

`dashboard/src/features/scheduling/refusal.ts` — extract the reason B2f's `refusalText` builds into an exported helper (review M-2; `refusalText` keeps its signature and output, so `refusal.test.ts` is unchanged):

```ts
/** A refusal's reason: the translated rule code, else the server's message,
 * else its first field error (never `member_id`), else a generic line. */
export function refusalReason(error: unknown, t: TFunction): string {
	const parsed = parseApiError(error);
	const field = Object.entries(parsed.fieldErrors).find(
		([key]) => key !== "member_id",
	);
	return (
		(parsed.code ? t(codeKey(parsed.code), { defaultValue: "" }) : "") ||
		parsed.message ||
		field?.[1] ||
		t("errors.generic")
	);
}
```

and in `refusalText`, the lines from `const parsed = parseApiError(error);` to the end of `const reason = …;` become `const parsed = parseApiError(error);` and `const reason = refusalReason(error, t);` (`parsed.code` is still read for the freeze-cap line).

`dashboard/src/features/scheduling/scheduleRefusal.ts` — a thin wrapper:

```ts
import type { TFunction } from "i18next";
import { memberIdOf, refusalReason } from "./refusal";
import type { NamedRef } from "./schemas";
import type { ScheduleRow } from "./scheduleSchemas";

/** Plan D22: B2f's refusal reason, prefixed by the subscription the server
 * names (`member_id`) when it is on screen. */
export function scheduleRefusal(
	error: unknown,
	rows: ScheduleRow[],
	t: TFunction,
	localName: (named: NamedRef) => string,
): string {
	const reason = refusalReason(error, t);
	const id = memberIdOf(error);
	const member = rows
		.flatMap((row) => row.members)
		.find((m) => m.subscription_id === id);
	if (!member) return reason;
	return t("schedules.bulk.refused", {
		student: member.student.full_name,
		course: localName(member.course),
		reason,
	});
}
```

`dashboard/src/features/scheduling/ScheduleActions.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { useCan } from "@/features/identity/permissions";
import { Button, toast } from "@/ui";
import { useLocalName } from "./bits";
import { useSchedulingMutation } from "./queries";
import { scheduleApi } from "./scheduleApi";
import { ScheduleTeacherDialog } from "./ScheduleTeacherDialog";
import { scheduleRefusal } from "./scheduleRefusal";
import {
	type ScheduleRow,
	type StatusAction,
	targetsOf,
} from "./scheduleSchemas";
import { SubstituteDialog } from "./SubstituteDialog";

/** Spec §8: the bulk actions on the chosen rows (keys), each by its code;
 * which ones apply is the server's answer (a refusal names its row). */
export function ScheduleActions({
	selected,
	rows,
	onDone,
}: {
	selected: string[];
	rows: ScheduleRow[];
	onDone: () => void;
}) {
	const { t } = useTranslation();
	const can = useCan();
	const localName = useLocalName();
	const status = useSchedulingMutation(scheduleApi.setStatus);
	if (selected.length === 0) return null;
	const targets = targetsOf(selected);
	const update = can("weekly_schedule.update");

	function run(action: StatusAction) {
		status.mutate(
			{ action, ...targets },
			{
				onSuccess: (answer) => {
					onDone();
					toast({
						description: t("schedules.bulk.done", {
							count: answer.subscriptions.length,
						}),
						variant: "success",
					});
				},
				onError: (error) =>
					toast({
						description: scheduleRefusal(error, rows, t, localName),
						variant: "destructive",
					}),
			},
		);
	}

	return (
		<section
			aria-label={t("schedules.bulk.label")}
			className="flex flex-wrap items-center gap-2 rounded-lg border border-border bg-secondary p-3"
		>
			<span className="text-sm">
				{t("schedules.bulk.selected", { count: selected.length })}
			</span>
			{update ? (
				<Confirm
					action={t("schedules.bulk.stop")}
					title={t("schedules.bulk.stopTitle")}
					body={t("schedules.bulk.stopBody")}
					onConfirm={() => run("stop")}
				/>
			) : null}
			{update ? (
				<Button
					size="sm"
					variant="outline"
					disabled={status.isPending}
					onClick={() => run("activate")}
				>
					{t("schedules.bulk.activate")}
				</Button>
			) : null}
			{can("weekly_schedule.delete") ? (
				<Confirm
					action={t("schedules.bulk.delete")}
					title={t("schedules.bulk.deleteTitle")}
					body={t("schedules.bulk.deleteBody")}
					onConfirm={() => run("delete")}
				/>
			) : null}
			{can("weekly_schedule.restore") ? (
				<Button
					size="sm"
					variant="outline"
					disabled={status.isPending}
					onClick={() => run("restore")}
				>
					{t("schedules.bulk.restore")}
				</Button>
			) : null}
			{update ? (
				<ScheduleTeacherDialog targets={targets} rows={rows} onDone={onDone} />
			) : null}
			{update ? (
				<SubstituteDialog targets={targets} rows={rows} onDone={onDone} />
			) : null}
		</section>
	);
}
```

`dashboard/src/features/scheduling/ScheduleTeacherDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { parseApiError } from "@/features/identity/api";
import { usePeople } from "@/features/people";
import { useFieldError } from "@/lib/field-error";
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
	Select,
	SubmitButton,
	toast,
} from "@/ui";
import { useLocalName } from "./bits";
import { useSchedulingMutation } from "./queries";
import { memberIdOf } from "./refusal";
import { scheduleApi } from "./scheduleApi";
import { scheduleRefusal } from "./scheduleRefusal";
import type { ScheduleRow, ScheduleTargets } from "./scheduleSchemas";

const ACTIVE = { is_active: "true", page_size: 100 } as const;
const teacherSchema = z.object({
	teacher: z.string().min(1, "scheduling.errors.required"),
});
type TeacherValues = z.infer<typeof teacherSchema>;

/** Spec G-7: one teacher for every chosen schedule, all or nothing. A
 * refusal naming a subscription is shown in the dialog (plan D22). */
export function ScheduleTeacherDialog({
	targets,
	rows,
	onDone,
}: {
	targets: ScheduleTargets;
	rows: ScheduleRow[];
	onDone: () => void;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const localName = useLocalName();
	const [open, setOpen] = useState(false);
	const [refusal, setRefusal] = useState<string | null>(null);
	const { data: teachers } = usePeople("teachers", ACTIVE, { enabled: open });
	const change = useSchedulingMutation(scheduleApi.changeTeacher);
	const {
		register,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<TeacherValues>({
		resolver: zodResolver(teacherSchema),
		defaultValues: { teacher: "" },
	});

	async function onSubmit(values: TeacherValues) {
		setRefusal(null);
		try {
			const answer = await change.mutateAsync({
				...targets,
				teacher_id: Number(values.teacher),
			});
			reset();
			setOpen(false);
			onDone();
			const warnings = [
				answer.conflicts.length
					? t("schedules.clashes", { count: answer.conflicts.length })
					: "",
				answer.outside_availability?.length
					? t("schedules.outside", {
							count: answer.outside_availability.length,
						})
					: "",
			].filter(Boolean);
			toast({
				description: [
					t("schedules.teacher.done", { count: answer.subscriptions.length }),
					...warnings,
				].join(" "),
				variant: "success",
			});
		} catch (error) {
			const own = parseApiError(error).fieldErrors.teacher_id;
			if (own && memberIdOf(error) === null) {
				setError("teacher", { message: own });
			} else {
				setRefusal(scheduleRefusal(error, rows, t, localName));
			}
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("schedules.bulk.teacher")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("schedules.teacher.title")}</DialogTitle>
				<DialogDescription>{t("schedules.teacher.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="schedule-teacher"
						label={t("schedules.teacher.label")}
						error={fieldError(errors.teacher?.message)}
						required
					>
						<Select {...register("teacher")}>
							<option value="">—</option>
							{teachers?.results.map((p) => (
								<option key={p.id} value={p.id}>
									{p.user.full_name}
								</option>
							))}
						</Select>
					</Field>
					{refusal ? (
						<Alert variant="destructive">
							<AlertDescription>{refusal}</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>
							{t("schedules.teacher.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

`dashboard/src/features/scheduling/SubstituteDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { parseApiError } from "@/features/identity/api";
import { usePeople } from "@/features/people";
import { useFieldError } from "@/lib/field-error";
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
	toast,
} from "@/ui";
import { useLocalName } from "./bits";
import { useSchedulingMutation } from "./queries";
import { memberIdOf } from "./refusal";
import { isoDate } from "./schemas";
import { scheduleApi } from "./scheduleApi";
import { scheduleRefusal } from "./scheduleRefusal";
import type { ScheduleRow, ScheduleTargets } from "./scheduleSchemas";

const ACTIVE = { is_active: "true", page_size: 100 } as const;
const substituteSchema = z
	.object({
		teacher: z.string().min(1, "scheduling.errors.required"),
		from_date: isoDate,
		to_date: isoDate,
	})
	.refine((v) => v.to_date >= v.from_date, {
		path: ["to_date"],
		message: "scheduling.errors.rangeOrder",
	});
type SubstituteValues = z.infer<typeof substituteSchema>;
// The server's body keys → this form's fields (plan D8's keys).
const FIELDS = [
	["teacher_id", "teacher"],
	["from_date", "from_date"],
	["to_date", "to_date"],
] as const;

/** Spec G-5: a substitute for the chosen schedules over a period. Date and
 * teacher refusals without a subscription go on their fields; one naming a
 * subscription is shown in the dialog (plan D22). The `to ≥ from` check
 * is the one rule restated here, as PausesPanel's pause form does (a form
 * should not send a backwards range); the 366-day cap and the overlaps are
 * the server's alone. */
export function SubstituteDialog({
	targets,
	rows,
	onDone,
}: {
	targets: ScheduleTargets;
	rows: ScheduleRow[];
	onDone: () => void;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const localName = useLocalName();
	const [open, setOpen] = useState(false);
	const [refusal, setRefusal] = useState<string | null>(null);
	const { data: teachers } = usePeople("teachers", ACTIVE, { enabled: open });
	const add = useSchedulingMutation(scheduleApi.addSubstitution);
	const {
		register,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<SubstituteValues>({
		resolver: zodResolver(substituteSchema),
		defaultValues: { teacher: "", from_date: "", to_date: "" },
	});

	async function onSubmit(values: SubstituteValues) {
		setRefusal(null);
		try {
			const answer = await add.mutateAsync({
				...targets,
				teacher_id: Number(values.teacher),
				from_date: values.from_date,
				to_date: values.to_date,
			});
			reset();
			setOpen(false);
			onDone();
			const warnings = [
				answer.conflicts.length
					? t("schedules.clashes", { count: answer.conflicts.length })
					: "",
				answer.outside_availability?.length
					? t("schedules.outside", {
							count: answer.outside_availability.length,
						})
					: "",
			].filter(Boolean);
			toast({
				description: [
					t("schedules.substitute.done", {
						count: answer.substitutions.length,
					}),
					...warnings,
				].join(" "),
				variant: "success",
			});
		} catch (error) {
			const parsed = parseApiError(error);
			const placed =
				memberIdOf(error) === null
					? FIELDS.filter(([key, field]) => {
							const message = parsed.fieldErrors[key];
							if (message) setError(field, { message });
							return Boolean(message);
						})
					: [];
			if (placed.length === 0) {
				setRefusal(scheduleRefusal(error, rows, t, localName));
			}
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("schedules.bulk.substitute")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("schedules.substitute.title")}</DialogTitle>
				<DialogDescription>{t("schedules.substitute.body")}</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="substitute-teacher"
						label={t("schedules.substitute.teacher")}
						error={fieldError(errors.teacher?.message)}
						required
					>
						<Select {...register("teacher")}>
							<option value="">—</option>
							{teachers?.results.map((p) => (
								<option key={p.id} value={p.id}>
									{p.user.full_name}
								</option>
							))}
						</Select>
					</Field>
					<div className="grid gap-4 sm:grid-cols-2">
						<Field
							id="substitute-from"
							label={t("schedules.substitute.from")}
							error={fieldError(errors.from_date?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("from_date")} />
						</Field>
						<Field
							id="substitute-to"
							label={t("schedules.substitute.to")}
							error={fieldError(errors.to_date?.message)}
							required
						>
							<Input type="date" dir="ltr" {...register("to_date")} />
						</Field>
					</div>
					{refusal ? (
						<Alert variant="destructive">
							<AlertDescription>{refusal}</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<SubmitButton pending={isSubmitting}>
							{t("schedules.substitute.save")}
						</SubmitButton>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

`dashboard/src/features/scheduling/SchedulesList.tsx` — import `ScheduleActions` and render it right before the `{isError ? …}` block:

```tsx
			<ScheduleActions
				selected={selected}
				rows={rows}
				onDone={() => setSelected([])}
			/>
```

Add to `SchedulesList.test.tsx` (inside the describe):

```tsx
	it("acts on the chosen rows and clears the choice", async () => {
		vi.mocked(scheduleApi.setStatus).mockResolvedValue({ subscriptions: [7] });
		const user = userEvent.setup();
		renderWithRouter(<SchedulesList />);
		await user.click(await screen.findByLabelText("Select Yusuf"));
		await user.click(screen.getByRole("button", { name: "Activate" }));
		await waitFor(() =>
			expect(scheduleApi.setStatus).toHaveBeenCalledWith({
				action: "activate",
				subscription_ids: [7],
			}),
		);
		await waitFor(() =>
			expect(screen.queryByRole("region", { name: "Selected schedules" })).toBeNull(),
		);
	});
```

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/refusal.test.ts src/features/scheduling/scheduleRefusal.test.ts src/features/scheduling/ScheduleActions.test.tsx src/features/scheduling/ScheduleDialogs.test.tsx src/features/scheduling/SchedulesList.test.tsx` then `… exec -T dashboard pnpm exec tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/refusal.ts src/features/scheduling/scheduleRefusal.ts src/features/scheduling/scheduleRefusal.test.ts src/features/scheduling/ScheduleActions.tsx src/features/scheduling/ScheduleActions.test.tsx src/features/scheduling/ScheduleTeacherDialog.tsx src/features/scheduling/SubstituteDialog.tsx src/features/scheduling/ScheduleDialogs.test.tsx src/features/scheduling/SchedulesList.tsx src/features/scheduling/SchedulesList.test.tsx
git -C $W/dashboard commit -m "feat(scheduling): bulk stop, activate, delete, restore, teacher change and substitute (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 15: The expanded calendar — a week grid, one day at a time on a phone

**Files:**
- Create: `dashboard/src/features/scheduling/ScheduleCalendar.tsx`, `ScheduleCalendar.test.tsx`
- Modify: `dashboard/src/features/scheduling/index.ts` (`ScheduleCalendar`)
- Modify: `dashboard/src/routes/_authed/scheduling.schedules.calendar.tsx` (renders it with the search)

**Interfaces:**
- Consumes: Task 11's `useScheduleCalendar`, `CalendarEntry`, `calendarEntry` fixture, the route's `{teacher?, student?}` search; `usePeople`; `useAcademySettings` (the phone view opens on the academy's weekday); `WEEKDAYS`, `weekdayName`, `todayIn`.
- Produces: `ScheduleCalendar({ teacher, student, onFilter })` — `onFilter(next: {teacher?: number; student?: number})`; one `<section aria-label={day name}>` per weekday, Monday first; on a phone only the chosen day's section shows (a "Day" select); the teacher and student selects keep a pre-filled id as one stable option while their lists load (S10).

- [ ] **Step 1: Write the failing test** (`dashboard/src/features/scheduling/ScheduleCalendar.test.tsx`)

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import {
	academySettings,
	calendarEntry,
	page,
} from "@/test/scheduling-fixtures";
import { ScheduleCalendar } from "./ScheduleCalendar";
import { scheduleApi } from "./scheduleApi";

vi.mock("./scheduleApi", async (orig) => {
	const actual = await orig<typeof import("./scheduleApi")>();
	return {
		...actual,
		scheduleApi: { ...actual.scheduleApi, calendar: vi.fn() },
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));

describe("ScheduleCalendar (G-11)", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 21, user: { full_name: "Bilal" } }]) as never,
		);
		vi.mocked(scheduleApi.calendar).mockResolvedValue([
			calendarEntry(),
			calendarEntry({
				weekday: 2,
				start_time: "19:00",
				end_time: "20:00",
				student: null,
				group: "Evening circle",
				subscription_id: null,
				bundle_id: 9,
			}),
		]);
	});

	it("puts each slot on its day, Monday first", async () => {
		renderWithRouter(<ScheduleCalendar onFilter={vi.fn()} />);
		const monday = await screen.findByRole("region", { name: "Monday" });
		expect(within(monday).getByText("18:00–18:45")).toBeInTheDocument();
		expect(within(monday).getByText("Yusuf")).toBeInTheDocument();
		expect(within(monday).getByText("Tajweed · Bilal")).toBeInTheDocument();
		const wednesday = screen.getByRole("region", { name: "Wednesday" });
		expect(within(wednesday).getByText("Group: Evening circle")).toBeInTheDocument();
		const tuesday = screen.getByRole("region", { name: "Tuesday" });
		expect(within(tuesday).getByText("Nothing on this day.")).toBeInTheDocument();
		expect(
			screen
				.getAllByRole("heading", { level: 2 })
				.map((heading) => heading.textContent),
		).toEqual([
			"Monday",
			"Tuesday",
			"Wednesday",
			"Thursday",
			"Friday",
			"Saturday",
			"Sunday",
		]);
	});

	it("shows one day at a time on a phone", async () => {
		const user = userEvent.setup();
		renderWithRouter(<ScheduleCalendar onFilter={vi.fn()} />);
		await screen.findByRole("region", { name: "Monday" });
		await user.selectOptions(screen.getByLabelText("Day"), "2");
		expect(screen.getByRole("region", { name: "Wednesday" })).toHaveClass("flex");
		expect(screen.getByRole("region", { name: "Monday" })).toHaveClass(
			"hidden",
		);
	});

	it("filters by teacher, and keeps a teacher it was opened with", async () => {
		const onFilter = vi.fn();
		const user = userEvent.setup();
		const { unmount } = renderWithRouter(<ScheduleCalendar onFilter={onFilter} />);
		await screen.findByRole("option", { name: "Bilal" });
		await user.selectOptions(screen.getByLabelText("Teacher"), "21");
		expect(onFilter).toHaveBeenCalledWith({ teacher: 21 });
		unmount();
		vi.mocked(peopleApi.list).mockReturnValue(new Promise(() => {}));
		renderWithRouter(<ScheduleCalendar teacher={22} onFilter={onFilter} />);
		await waitFor(() =>
			expect(scheduleApi.calendar).toHaveBeenLastCalledWith({ teacher: 22 }),
		);
		// Ruling S10: the kept id is one stable option while the list loads.
		expect(screen.getByLabelText("Teacher")).toHaveValue("22");
	});
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/ScheduleCalendar.test.tsx`
Expected: FAIL — `Failed to resolve import "./ScheduleCalendar"`.

- [ ] **Step 3: Implement**

`dashboard/src/features/scheduling/ScheduleCalendar.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { useCan } from "@/features/identity/permissions";
import { usePeople } from "@/features/people";
import { cn } from "@/lib/cn";
import { todayIn, weekdayName } from "@/lib/zoned-time";
import { Alert, AlertDescription, Select, Spinner } from "@/ui";
import { useLocalName } from "./bits";
import { useScheduleCalendar } from "./scheduleQueries";
import type { CalendarEntry } from "./scheduleSchemas";
import { WEEKDAYS } from "./schemas";

type Filter = { teacher?: number; student?: number };

/** The academy's weekday today, 0 = Monday (review M-7): a phone opens on
 * the academy's day, not the browser's. */
function weekdayIn(zone: string): number {
	return (new Date(`${todayIn(zone)}T00:00:00Z`).getUTCDay() + 6) % 7;
}

/** Ruling S10: a select opened with an id keeps it as one stable option
 * while its list loads; the label comes from the list, else the entries. */
function PersonFilter({
	label,
	anyLabel,
	value,
	people,
	known,
	onChange,
}: {
	label: string;
	anyLabel: string;
	value?: number;
	people: { id: number; user: { full_name: string } }[];
	known?: string;
	onChange: (next?: number) => void;
}) {
	const listed = people.find((p) => p.id === value)?.user.full_name;
	return (
		<Select
			aria-label={label}
			className="w-auto"
			value={value ? String(value) : ""}
			onChange={(e) => onChange(e.target.value ? Number(e.target.value) : undefined)}
		>
			<option value="">{anyLabel}</option>
			{value ? (
				<option key="kept" value={value}>
					{listed ?? known ?? `#${value}`}
				</option>
			) : null}
			{people
				.filter((p) => p.id !== value)
				.map((p) => (
					<option key={p.id} value={p.id}>
						{p.user.full_name}
					</option>
				))}
		</Select>
	);
}

function Entry({ entry }: { entry: CalendarEntry }) {
	const { t } = useTranslation();
	const localName = useLocalName();
	return (
		<li className="rounded-md bg-secondary p-2 text-sm">
			<span dir="ltr" className="block font-medium">
				{t("schedules.calendar.time", {
					start: entry.start_time,
					end: entry.end_time,
				})}
			</span>
			<span className="block">
				{entry.group
					? t("schedules.calendar.group", { name: entry.group })
					: entry.student?.full_name}
			</span>
			<span className="block text-xs text-muted-foreground">
				{`${localName(entry.course)} · ${entry.teacher.full_name}`}
			</span>
		</li>
	);
}

/** Spec G-11: a week grid (Monday–Sunday, no dates) of the active schedules'
 * slots; read-only. A phone shows one day at a time. */
export function ScheduleCalendar({
	teacher,
	student,
	onFilter,
}: Filter & { onFilter: (next: Filter) => void }) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const { data: academy } = useAcademySettings();
	const [chosen, setDay] = useState<number | null>(null);
	const day = chosen ?? (academy ? weekdayIn(academy.timezone) : 0);
	const { data: entries, isPending, isError } = useScheduleCalendar({
		teacher,
		student,
	});
	const listTeachers = can("teacher.view_any");
	const listStudents = can("student.view_any");
	const { data: teachers } = usePeople(
		"teachers",
		{ page_size: 100 },
		{ enabled: listTeachers },
	);
	const { data: students } = usePeople(
		"students",
		{ page_size: 100 },
		{ enabled: listStudents },
	);
	const name = (d: number) => weekdayName(d, i18n.language, "long");
	const found = entries ?? [];

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				{listTeachers || teacher ? (
					<PersonFilter
						label={t("schedules.filters.teacher")}
						anyLabel={t("schedules.filters.anyTeacher")}
						value={teacher}
						people={teachers?.results ?? []}
						known={found.find((e) => e.teacher.id === teacher)?.teacher.full_name}
						onChange={(next) => onFilter({ student, teacher: next })}
					/>
				) : null}
				{listStudents || student ? (
					<PersonFilter
						label={t("schedules.filters.student")}
						anyLabel={t("schedules.filters.anyStudent")}
						value={student}
						people={students?.results ?? []}
						known={found.find((e) => e.student?.id === student)?.student?.full_name}
						onChange={(next) => onFilter({ teacher, student: next })}
					/>
				) : null}
				<div className="sm:hidden">
					<Select
						aria-label={t("schedules.calendar.day")}
						value={String(day)}
						onChange={(e) => setDay(Number(e.target.value))}
					>
						{WEEKDAYS.map((d) => (
							<option key={d} value={d}>
								{name(d)}
							</option>
						))}
					</Select>
				</div>
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("schedules.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<Spinner />
			) : (
				<div className="grid gap-3 sm:grid-cols-7">
					{WEEKDAYS.map((d) => {
						const theirs = found.filter((e) => e.weekday === d);
						return (
							<section
								key={d}
								aria-label={name(d)}
								className={cn(
									"flex-col gap-2 rounded-lg border border-border p-2",
									d === day ? "flex" : "hidden sm:flex",
								)}
							>
								<h2 className="text-sm font-medium">{name(d)}</h2>
								{theirs.length === 0 ? (
									<p className="text-xs text-muted-foreground">
										{t("schedules.calendar.empty")}
									</p>
								) : (
									<ul className="flex flex-col gap-2">
										{theirs.map((e) => (
											<Entry
												key={`${e.start_time}-${e.subscription_id ?? `b${e.bundle_id}`}`}
												entry={e}
											/>
										))}
									</ul>
								)}
							</section>
						);
					})}
				</div>
			)}
		</div>
	);
}
```

`index.ts` — `export { ScheduleCalendar } from "./ScheduleCalendar";`.

`scheduling.schedules.calendar.tsx` — the component renders the header, a back link and the grid:

```tsx
	component: function ScheduleCalendarRoute() {
		const { t } = useTranslation();
		const search = Route.useSearch();
		const navigate = useNavigate();
		usePageTitle(t("schedules.calendar.title"));
		return (
			<>
				<PageHeader
					title={t("schedules.calendar.title")}
					description={t("schedules.calendar.subtitle")}
				/>
				<Link
					to="/scheduling/schedules"
					className="text-sm font-medium text-primary-text underline-offset-4 hover:underline"
				>
					{t("schedules.calendar.back")}
				</Link>
				<ScheduleCalendar
					teacher={search.teacher}
					student={search.student}
					onFilter={(next) =>
						void navigate({ to: "/scheduling/schedules/calendar", search: next })
					}
				/>
			</>
		);
	},
```

with `import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";` and `import { ScheduleCalendar } from "@/features/scheduling";`.

- [ ] **Step 4: Run it to see it pass**

Run: `… exec -T dashboard pnpm exec vite build` (route file changed), `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm exec vitest run src/features/scheduling/ScheduleCalendar.test.tsx src/routes`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/ScheduleCalendar.tsx src/features/scheduling/ScheduleCalendar.test.tsx src/features/scheduling/index.ts src/routes/_authed/scheduling.schedules.calendar.tsx src/routeTree.gen.ts
git -C $W/dashboard commit -m "feat(scheduling): the expanded weekly calendar, one day at a time on a phone (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 16: The subscription page's "Weekly schedule" card

**Files:**
- Create: `dashboard/src/features/scheduling/ScheduleStatusCard.tsx`, `ScheduleStatusCard.test.tsx`
- Modify: `dashboard/src/features/scheduling/SubscriptionDetail.tsx` (mounts the card after `SubscriptionActions`)

**Interfaces:**
- Consumes: Task 11's `SubscriptionDetail.schedule_status`, `substitutions`, `schedule_changed_*`, `scheduleApi.setStatus`, `removeSubstitution`, fixtures `subscriptionDetail`, `substitutionRow`; `adminWith`, `staffMe`.
- Produces: `ScheduleStatusCard({ sub, academyZone })` (plan D21) — nothing while the schedule is active and has no substitution.

- [ ] **Step 1: Write the failing test** (`dashboard/src/features/scheduling/ScheduleStatusCard.test.tsx`)

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { adminWith, staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import {
	subscriptionDetail,
	substitutionRow,
} from "@/test/scheduling-fixtures";
import { scheduleApi } from "./scheduleApi";
import { ScheduleStatusCard } from "./ScheduleStatusCard";

vi.mock("./scheduleApi", async (orig) => {
	const actual = await orig<typeof import("./scheduleApi")>();
	return {
		...actual,
		scheduleApi: {
			...actual.scheduleApi,
			setStatus: vi.fn(),
			removeSubstitution: vi.fn(),
		},
	};
});

const STOPPED = subscriptionDetail({
	schedule_status: "stopped",
	schedule_changed_at: "2026-06-01T08:00:00Z",
	schedule_changed_by: { id: 50, full_name: "Amina" },
});

describe("ScheduleStatusCard (plan D21)", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(scheduleApi.setStatus).mockResolvedValue({ subscriptions: [7] });
		vi.mocked(scheduleApi.removeSubstitution).mockResolvedValue();
	});

	it("shows nothing for an active schedule without substitutes", async () => {
		renderWithRouter(
			<>
				<p>marker</p>
				<ScheduleStatusCard sub={subscriptionDetail()} academyZone="UTC" />
			</>,
		);
		await screen.findByText("marker");
		expect(screen.queryByText("Weekly schedule")).toBeNull();
	});

	it("activates a stopped schedule", async () => {
		const user = userEvent.setup();
		renderWithRouter(<ScheduleStatusCard sub={STOPPED} academyZone="UTC" />);
		expect(await screen.findByText("Schedule stopped")).toBeVisible();
		expect(
			screen.getByText("Changed on Jun 1, 2026 by Amina"),
		).toBeInTheDocument();
		await user.click(screen.getByRole("button", { name: "Activate schedule" }));
		await waitFor(() =>
			expect(scheduleApi.setStatus).toHaveBeenCalledWith({
				action: "activate",
				subscription_ids: [7],
			}),
		);
		expect(await screen.findByText("The schedule is active again.")).toBeVisible();
	});

	it("restores a deleted one, even with the switch off", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<ScheduleStatusCard
					sub={subscriptionDetail({
						schedule_status: "deleted",
						substitutions: [substitutionRow()],
					})}
					academyZone="UTC"
				/>
			</CanProvider>,
		);
		expect(await screen.findByText("Schedule deleted")).toBeVisible();
		expect(screen.queryByRole("button", { name: "Activate schedule" })).toBeNull();
		// The substitution's own route is gated: no Remove while it is off.
		expect(
			screen.getByText("Hamza, Jun 8, 2026 – Jun 14, 2026"),
		).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Remove" })).toBeNull();
		await user.click(screen.getByRole("button", { name: "Restore schedule" }));
		await waitFor(() =>
			expect(scheduleApi.setStatus).toHaveBeenCalledWith({
				action: "restore",
				subscription_ids: [7],
			}),
		);
	});

	it("removes a substitution after a confirmation", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<ScheduleStatusCard
				sub={subscriptionDetail({ substitutions: [substitutionRow()] })}
				academyZone="UTC"
			/>,
		);
		await user.click(await screen.findByRole("button", { name: "Remove" }));
		await user.click(
			screen.getByRole("button", { name: "Remove this substitution" }),
		);
		await waitFor(() =>
			expect(scheduleApi.removeSubstitution).toHaveBeenCalledWith(5),
		);
	});

	it("shows the badge alone to someone without the codes", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("subscription.view")}>
				<ScheduleStatusCard sub={STOPPED} academyZone="UTC" />
			</CanProvider>,
		);
		expect(await screen.findByText("Schedule stopped")).toBeVisible();
		expect(screen.queryByRole("button")).toBeNull();
	});
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/ScheduleStatusCard.test.tsx`
Expected: FAIL — `Failed to resolve import "./ScheduleStatusCard"`.

- [ ] **Step 3: Implement**

`dashboard/src/features/scheduling/ScheduleStatusCard.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { errorText } from "@/lib/form-errors";
import { dayIn, formatDay } from "@/lib/zoned-time";
import {
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	StatusChip,
	toast,
} from "@/ui";
import { useSchedulingMutation } from "./queries";
import { scheduleApi } from "./scheduleApi";
import type { SubscriptionDetail } from "./schemas";

/** Spec §8, plan D21: the schedule's badge with Activate / Restore — both
 * ungated, so a schedule is never stuck while the switch is off (FT-4) —
 * and its substitutions with Remove (a gated route: only while it is on). */
export function ScheduleStatusCard({
	sub,
	academyZone,
}: {
	sub: SubscriptionDetail;
	academyZone: string;
}) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	const status = useSchedulingMutation(scheduleApi.setStatus);
	const remove = useSchedulingMutation(scheduleApi.removeSubstitution);
	const substitutions = sub.substitutions ?? [];
	const away = sub.schedule_status !== "active";
	if (!away && substitutions.length === 0) return null;
	const day = (value: string) => formatDay(value, i18n.language);
	const fail = (error: unknown) =>
		toast({ description: errorText(error, t), variant: "destructive" });
	const removable = can("weekly_schedule.update") && hasFeature("weekly_schedules");

	function act(action: "activate" | "restore") {
		status.mutate(
			{ action, subscription_ids: [sub.id] },
			{
				onSuccess: () =>
					toast({
						description: t(
							action === "activate"
								? "schedules.card.activated"
								: "schedules.card.restored",
						),
						variant: "success",
					}),
				onError: fail,
			},
		);
	}

	const changed = sub.schedule_changed_at
		? dayIn(new Date(sub.schedule_changed_at), academyZone, i18n.language)
		: null;

	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
				<CardTitle>{t("schedules.card.title")}</CardTitle>
				{away ? (
					<StatusChip
						tone={sub.schedule_status === "deleted" ? "warning" : "neutral"}
					>
						{t(`schedules.card.${sub.schedule_status}`)}
					</StatusChip>
				) : null}
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				{away && changed ? (
					<p className="text-sm text-muted-foreground">
						{sub.schedule_changed_by
							? t("schedules.card.changed", {
									date: changed,
									name: sub.schedule_changed_by.full_name,
								})
							: t("schedules.card.changedBySystem", { date: changed })}
					</p>
				) : null}
				{sub.schedule_status === "stopped" && can("weekly_schedule.update") ? (
					<Button
						size="sm"
						className="self-start"
						disabled={status.isPending}
						onClick={() => act("activate")}
					>
						{t("schedules.card.activate")}
					</Button>
				) : null}
				{sub.schedule_status === "deleted" && can("weekly_schedule.restore") ? (
					<Button
						size="sm"
						className="self-start"
						disabled={status.isPending}
						onClick={() => act("restore")}
					>
						{t("schedules.card.restore")}
					</Button>
				) : null}
				{substitutions.length > 0 ? (
					<section
						aria-label={t("schedules.card.substitutions")}
						className="flex flex-col gap-2"
					>
						<h3 className="text-sm font-medium">
							{t("schedules.card.substitutions")}
						</h3>
						<ul className="flex flex-col gap-2">
							{substitutions.map((s) => (
								<li key={s.id} className="flex flex-wrap items-center gap-2">
									<span>
										{t("schedules.substitution", {
											teacher: s.teacher.full_name,
											from: day(s.from_date),
											to: day(s.to_date),
										})}
									</span>
									{removable ? (
										<Confirm
											action={t("schedules.card.remove")}
											title={t("schedules.card.removeTitle")}
											body={t("schedules.card.removeBody")}
											onConfirm={() =>
												remove.mutate(s.id, {
													onSuccess: () =>
														toast({
															description: t("schedules.card.removed"),
															variant: "success",
														}),
													onError: fail,
												})
											}
										/>
									) : null}
								</li>
							))}
						</ul>
					</section>
				) : null}
			</CardContent>
		</Card>
	);
}
```

`SubscriptionDetail.tsx` — `import { ScheduleStatusCard } from "./ScheduleStatusCard";` and, right after `<SubscriptionActions sub={sub} />`:

```tsx
			<ScheduleStatusCard sub={sub} academyZone={academy.timezone} />
```

- [ ] **Step 4: Run it to see it pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/ScheduleStatusCard.test.tsx src/features/scheduling/SubscriptionDetail.test.tsx`
Expected: PASS (`SubscriptionDetail`'s tests unchanged: its fixture is active with no substitutions, so no card).

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/ScheduleStatusCard.tsx src/features/scheduling/ScheduleStatusCard.test.tsx src/features/scheduling/SubscriptionDetail.tsx
git -C $W/dashboard commit -m "feat(scheduling): the subscription page's weekly schedule card with Activate, Restore and substitutes (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Then run the dashboard gates: `… exec -T dashboard pnpm exec biome check --write src e2e`, `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`, `… exec -T dashboard pnpm test:coverage` (lines/statements ≥ 80, branches/functions ≥ 70).

---
### Task 17: End-to-end through Caddy, and the slice gates

**Files:**
- Create: `dashboard/e2e/b2-schedules.spec.ts`

**Interfaces:**
- Consumes: everything above, through the browser; `manage("set_features", "demo", "--on", …)`; `login`, `expectLoggedIn`, `DEMO_URL`, `DEMO_ADMIN` from `./fixtures`.

- [ ] **Step 1: Write the spec** (`dashboard/e2e/b2-schedules.spec.ts`)

```ts
import { expect, type Page, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

/** The date `days` from now in UTC (demo's academy clock). */
function inDays(days: number): string {
	return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

const weekday = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
	);

/** Next Monday and the Sunday after (inside the 14-day horizon). */
function nextWeek(): [string, string] {
	const toMonday = 7 - ((new Date().getUTCDay() + 6) % 7);
	return [inDays(toMonday), inDays(toMonday + 6)];
}

async function upcoming(page: Page, student: string) {
	await page.goto(`${DEMO_URL}/app/scheduling/sessions`);
	await page.getByLabel("Period").selectOption("upcoming");
	await page.getByRole("searchbox").fill(student);
}

async function schedules(page: Page, student: string, tab = "Active") {
	await page.goto(`${DEMO_URL}/app/scheduling/schedules`);
	await page.getByRole("tab", { name: tab, exact: true }).click();
	await page.getByRole("searchbox").fill(student);
	return page.getByRole("row", { name: new RegExp(student) });
}

// Slice B2g spec §10: the admin stops a schedule (its future sessions go),
// activates it (they return), and gives next week to a substitute (the
// sessions show the substitute). Stamped data, so a second run on the same
// database never meets the first run's rows; the asserts read durable
// state after reloads, never a toast.
test("the admin stops, activates and substitutes a weekly schedule", async ({
	page,
}) => {
	test.setTimeout(180_000);
	const stamp = Date.now();
	const regular = `E2E Week Tutor ${stamp}`;
	const cover = `E2E Week Cover ${stamp}`;
	const course = `E2E Week Recitation ${stamp}`;
	const pkg = `E2E Week Monthly ${stamp}`;
	const student = `E2E Week Student ${stamp}`;
	manage("set_features", "demo", "--on", "weekly_schedules");
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// Two teachers of one own course, a package and a student
	for (const [index, name] of [regular, cover].entries()) {
		await page.goto(`${DEMO_URL}/app/people/teachers/new`);
		await page.getByLabel(/^full name/i).fill(name);
		await page.getByLabel(/^gender/i).selectOption("male");
		await page.getByLabel(/^email/i).fill(`e2e-week-${index}-${stamp}@e2e.test`);
		await page.getByLabel("Preferred language").selectOption("en");
		await page.getByRole("button", { name: "Save", exact: true }).click();
		await expect(page).toHaveURL(/\/app\/people\/teachers\/\d+$/);
	}
	await page.goto(`${DEMO_URL}/app/catalogue/courses/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`تلاوة أسبوعية ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(course);
	await page.getByLabel(regular, { exact: true }).click();
	await page.getByLabel(cover, { exact: true }).click();
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/courses$/);

	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`شهرية أسبوعية ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(pkg);
	await page.getByLabel("Sessions per week").fill("2");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await page.getByLabel("Freeze days allowed").fill("10");
	await page.getByLabel("Price").fill("300");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/packages$/);

	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByLabel(/^email/i).fill(`e2e-week-student-${stamp}@e2e.test`);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);

	// A schedule on tomorrow's and the next day's weekdays at noon
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new`);
	await page.getByLabel("Find a student").fill(student);
	await page.getByLabel(/^Student/).selectOption({ label: student });
	await page.getByLabel(/^Course/).selectOption({ label: course });
	await page.getByLabel(/^Teacher/).selectOption({ label: regular });
	await page.getByLabel(/^Package/).selectOption({ label: pkg });
	await page.getByLabel(weekday(inDays(1)), { exact: true }).click();
	await page.getByLabel(weekday(inDays(2)), { exact: true }).click();
	await page.getByLabel(/^Start time/).fill("12:00");
	await page.getByRole("button", { name: "Create subscription" }).click();
	await expect(page).toHaveURL(/\/app\/scheduling\/subscriptions\/\d+$/);
	const subscriptionPage = page.url();
	await upcoming(page, student);
	await expect(
		page.getByRole("row", { name: new RegExp(student) }).first(),
	).toBeVisible();

	// Stop it from the list: its future sessions go
	const row = await schedules(page, student);
	await expect(row).toContainText(course);
	await page.getByLabel(`Select ${student}`).click();
	const bar = page.getByRole("region", { name: "Selected schedules" });
	await bar.getByRole("button", { name: "Stop", exact: true }).click();
	await page.getByRole("button", { name: "Stop these schedules" }).click();
	await expect(bar).toBeHidden();
	await expect(await schedules(page, student, "Stopped")).toContainText("Stopped");
	await upcoming(page, student);
	await expect(page.getByText("No sessions match.")).toBeVisible();

	// Activate it from the subscription page: they return
	await page.goto(subscriptionPage);
	await expect(page.getByText("Schedule stopped")).toBeVisible();
	await page.getByRole("button", { name: "Activate schedule" }).click();
	// Active with no substitute: the card goes once the page has re-read it.
	await expect(page.getByText("Schedule stopped")).toBeHidden();
	await expect(await schedules(page, student)).toContainText("Active");
	await upcoming(page, student);
	await expect(
		page.getByRole("row", { name: new RegExp(student) }).first(),
	).toBeVisible();

	// Next week goes to the substitute
	const [monday, sunday] = nextWeek();
	await schedules(page, student);
	await page.getByLabel(`Select ${student}`).click();
	await page
		.getByRole("region", { name: "Selected schedules" })
		.getByRole("button", { name: "Substitute" })
		.click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^Substitute teacher/).selectOption({ label: cover });
	await dialog.getByLabel(/^From/).fill(monday);
	await dialog.getByLabel(/^To/).fill(sunday);
	await dialog.getByRole("button", { name: "Add substitute" }).click();
	await expect(dialog).toBeHidden();
	await upcoming(page, student);
	const covered = page
		.getByRole("row")
		.filter({ hasText: `Substitute for ${regular}` });
	await expect(covered.first()).toBeVisible();
	await expect(covered.first()).toContainText(cover);
	await page.goto(subscriptionPage);
	await expect(
		page.getByRole("region", { name: "Substitutions" }),
	).toContainText(cover);

	// At phone width neither the list nor the calendar scrolls sideways
	await page.setViewportSize({ width: 375, height: 800 });
	for (const path of ["schedules", "schedules/calendar"]) {
		await page.goto(`${DEMO_URL}/app/scheduling/${path}`);
		await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
		await page.waitForLoadState("networkidle");
		expect(
			await page.evaluate(
				() => document.documentElement.scrollWidth <= window.innerWidth,
			),
		).toBe(true);
	}
	await expect(page.getByLabel("Day")).toBeVisible();
	await page.setViewportSize({ width: 1280, height: 800 });

	// Arabic reads right to left
	await page.evaluate(() => localStorage.setItem("etqan-locale", "ar"));
	await page.goto(`${DEMO_URL}/app/scheduling/schedules`);
	await expect(
		page.getByRole("heading", { name: "الجداول الأسبوعية" }),
	).toBeVisible();
	await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
});
```

- [ ] **Step 2: Run it, twice, on the stream's database**

Run: `just e2e e2e/b2-schedules.spec.ts` (twice). Expected: `1 passed` both times. If a list loads slowly under host load, raise only the single wait that timed out, with a comment; never add a fixed sleep.

- [ ] **Step 3: Commit**

```bash
git -C $W/dashboard add e2e/b2-schedules.spec.ts
git -C $W/dashboard commit -m "test(e2e): stop, activate and substitute a weekly schedule (B2g)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: The slice gates**

Run, from `$W`: `just test` (backend ≥ 80 %, dashboard lines/statements ≥ 80, branches/functions ≥ 70), `just lint` (ruff, `lint-imports`, Biome, the colour checker), then a fresh stack (`just dev-backend`, `migrate_schemas`, `seed_dev` — demo now has a stopped multi-course bundle and next week's substitute on Aisha Omar's Saturday lesson) and the whole `just e2e` (it runs `--workers=1 --retries=1`). Expected: all green. The seeds remove Zaid Huda's Saturday 13:00 and 15:00 bundle lessons and move one Saturday 11:00 lesson to Ustadh Bilal; a pre-existing spec that breaks on them is narrowed to its own stamped rows (never by changing the seeds' meaning) and the change is reported. Report the counts, the coverage figures, and any spec that only passed on its retry (with its failing step).

---
## Self-review (done while writing)

**Spec coverage** (spec section → task):
- §1 goal, G-13 switch → Task 1 (registry, `BUILT`), Task 9 (gated routes, ungated activate / restore in `UNGATED`), Tasks 11, 16 (screens by switch and code; the card's Activate / Restore always).
- G-1 a schedule is a slot set; bundle rows and collapsed group lines → Task 7 (`schedules_queryset`, `_lines`), Task 9 (payload), Task 13 (rows); plan D1, D13.
- G-2 status, stop removes untouched future generated sessions, activate regenerates when live → Task 2 (generation filter), Task 4.
- G-3 soft delete, restore, slots of a deleted schedule refused (409 `scheduling.schedule_deleted`) → Tasks 3, 4; plan D3.
- G-4 any subscription status → Task 4 (`test_activating_an_ended_subscriptions_schedule_generates_nothing`, `test_delete_puts_away_and_restore_brings_back`).
- G-5 substitution record, generation gives the substitute, regeneration, ≤ 366 days, no overlap, payroll pays the session's teacher → Tasks 1, 2, 5; plan D6-D9.
- G-6 generated sessions only; renewal copies overlapping ranges → Task 5 (`test_postponed_and_hand_added_sessions_keep_their_teacher`), Task 3.
- G-7 bulk teacher via `update_subscription`, all or nothing, substitutions stay, B2b's postponed move with `substitute_for` → Task 6; plan D7.
- G-8 "delete and move" not built → nothing added (Known limits kept).
- G-9 renewal copies `stopped`, starts `active` after `deleted`; a group newcomer copies the status → Task 3; plan D10.
- G-10 CSV → Tasks 7, 9 (`test_download_all_is_one_line_per_slot`), 13 (Download all).
- G-11 expanded calendar → Tasks 7, 9, 15.
- G-12 WhatsApp / notices → B5, untouched.
- §3 data → Task 1. §4 lock order → Task 4 (SQL capture), Task 5 (`remove_substitution`); generation, stop / delete / activate / restore, add / remove substitution, bulk teacher, bundle rows, Today board, slots, B2c `LOGGED_FIELDS` → Tasks 2-8.
- §5 lists (tabs, filters, rows, archived hidden) → Task 7, Task 13.
- §6 access (resource, codes, non-office 404, teacher scope follows `session.teacher`, the substitute never reads the subscription, "Substitute for" on every view that names a session's teacher, My supervision included) → Tasks 8, 9, 12.
- §7 API table → Task 9 (every row in `ROUTES`), plus the candidates route (plan D15).
- §8 dashboard → Tasks 11-16; strings in `schedules.json`; RTL and phone width checked in Task 17.
- §9 seeds → Task 10. §10 testing → each task's tests, Task 17's e2e. §11 known limits kept; §12 out of scope untouched.
- Ledger: D14 (archives — only B2g's own office lists leave archived rows out), D15 (`member_id`), D25, D35 (no `price_minor` sent), R2 call sites (plan D24).

**Placeholder scan:** no "TBD" / "TODO" / "similar to Task N"; every code step shows its code. `…` stands for the docker compose prefix in commands and, inside a block that edits an existing function, for that function's unchanged lines (each such block names the function and what changes).

**Type and name consistency:** backend — `rules.SCHEDULE`, `refuse_if_schedule_deleted`, `covering_substitution`, `GenerationResult.skipped_stopped` (Task 2); `create_subscription(schedule_status=, substitutions_from=)` (Task 3); `Targets`, `lock_schedules`, `live_targets`, `refuse_deleted`, `stop_schedules` / `delete_schedules` / `activate_schedules` / `restore_schedules(*, by, subscription_ids=(), bundle_ids=())` (Task 4); `Substituted`, `add_substitution(*, by, teacher_id, from_date, to_date, subscription_ids=(), bundle_ids=())`, `remove_substitution(substitution)`, `substitutions_queryset`, `substitutions_of`, `has_substitutions`, `availability.sessions_outside` (Task 5); `TeacherChanged`, `bulk_change_teacher(*, by, teacher_id, subscription_ids=(), bundle_ids=())` (Task 6); `schedules_queryset`, `filter_schedules`, `schedule_heads`, `schedule_rows`, `schedule_calendar`, `schedule_slots`, `schedule_candidates`, `has_stopped_schedules`, `SCHEDULE_TABS`, `SCHEDULE_KINDS` (Task 7); `payloads.substitution_row` (Task 8) — used with these names by Tasks 9 and 10. Conftest `WEEK_2`, `substitute`, `set_schedule`, `schedules_on`, `hamza` are defined once (Task 1). Dashboard — `ScheduleStatus`, `Substitution` (in `schemas.ts`), `ScheduleRow`, `ScheduleTargets`, `targetsOf`, `rowName`, `scheduleApi.*`, `useSchedules`, `useScheduleCalendar`, `useScheduleCandidates` (Task 11) are what Tasks 12-17 import; `SubstituteChip({ of })` (Task 12); `SchedulesList` mounts `ScheduleActions({ selected, rows, onDone })` (Tasks 13-14); `ScheduleCalendar({ teacher, student, onFilter })` (Task 15); `ScheduleStatusCard({ sub, academyZone })` (Task 16).

**Review fixes applied (plan-41 review, 2026-10-06):** I-1 (the chip on SimpleSessions, FamilyHome, MissingReports and MySupervision; `supervised_row` tested), I-2 (every `selectOptions` waits for its option), I-3 (plain rows follow D1's current-or-live rule), the four small tests (substitute 404 on the subscription, a bundle-row refusal's `member_id`, SELECT-only counts for calendar / CSV / candidates, `remove_substitution`'s lock order), the Today count on SELECTs, D16 reworded, M-2/M-3/M-6/M-7/M-10 folded in, M-8/M-9/M-11 in Known minors, D24 widened.

**Review Focus:** five lines, each with its test in the owning task (Tasks 2-6). Other input classes the spec implies and the tasks already cover: another academy's or an unknown id in a body (Task 4 `test_ids_must_be_this_academys`, Task 9), a body with no or too many ids (Task 9), a deleted schedule's slots (Task 3), the switch turned off with schedules stopped (Task 9 `test_activate_and_restore_work_with_the_switch_off`, Task 16), a substitution entirely beyond the horizon (Task 5), an archived subscription in the list (Task 7), a pre-filled calendar filter whose list is still loading (Task 15).

**Known minors, accepted:**
- M-1: the calendar shows both an old link and its pending renewal while both are live (it shows slots, not sessions — spec G-11's own limit).
- M-2: the list's student filter is the name search (`q`); the API's `student` id filter is used by no screen yet. The "Expanded calendar" link carries the list's teacher filter only.
- M-3: a renewal that keeps a stopped schedule starts with `schedule_changed_*` empty: its card says "Schedule stopped" without who stopped it.
- M-4: the Add dialog asks the server on every keystroke (no debounce), as the study-group candidates do.
- M-5: a substitution's `created_by` is stored and never shown.
- M-6: a substitution that plan D7 ignores (it names the subscription's current teacher, after a teacher change) still shows in the list and on the card, and still blocks an overlapping new range; remove it to free the dates.
- M-7: `SubstituteDialog` checks `to ≥ from` in the browser before sending — a restated server rule, with PausesPanel's pause form as precedent; every other rule (the 366-day cap, overlaps, the teacher) is the server's alone.
- M-8: a teacher change or a substitution on a multi-course or family **bundle row** is all or nothing across members with different courses and teachers: it is refused (naming the member) when the new teacher does not teach every member's course, or already is one member's teacher. Act on the member rows (their subscription pages) instead.

---

## Spec amendments (for the controller)

The plan departs from or adds to the approved B2g spec in these places; record them as amendments to `docs/superpowers/specs/2026-10-03-b2g-weekly-schedules-design.md` and in `orchestration/phases/B2.md`, so B4, B5 and B11 read the shipped contract:

- **D1** — §4 "Bundle rows": actions apply to the bundle's **schedule members — current or still live** (not only current), so an old link with a pending renewal stops too; teacher change and substitution apply to the live ones among them (none live → 409 `scheduling.not_allowed_in_status`); the row's status is computed over the same members. A subscription id naming a member acts on that member alone.
- **D3** — §4: stop and activate refuse a deleted schedule; restore changes only deleted ones; the same status is a no-op; the bulk teacher change and a substitution refuse a deleted schedule; `delete_slot` stays allowed.
- **D5** — §4: `skipped_stopped` counts schedules (live, unarchived, with an active slot), not dates.
- **D9** — §4 `add_substitution`: the range regenerated is `max(from_date, today)` to the later of `min(to_date, today + horizon)` and the last deleted date.
- **D11** — §4: `remove_substitution(substitution)` takes no `by`.
- **D13** — §5: a schedule is a subscription with a slot that is **current or still live** — D1's rule for plain subscriptions too (review I-3), so a renewed link leaves the list once it has ended; filter `q` (student name) added; the kind filter is `kind=single|multi_course|family|group`; the default tab is `active`; rows newest first.
- **D15** — a route added to §7: `GET schedules/candidates/?q=` (code `weekly_schedule.update`, feature `weekly_schedules`), up to 20 live subscriptions without a slot whose schedule is not deleted; "Add" opens the chosen subscription's page.
- **D16** — §7: session `substitute_for` is `{id, full_name}` and appears only on substituted sessions (Today rows and My supervision's rows too); a **Today row's `teacher` follows its session** (the substitute on a substituted lesson; the subscription's teacher only for a row without a session) — B5 and B11 reading Today should know; the office's subscription detail adds `substitutions` (current and future), `schedule_changed_at`, `schedule_changed_by`.
- **D17** — §7 answers: status actions `{subscriptions}`; bulk teacher `{subscriptions, conflicts, outside_availability?}`; substitution 201 `{substitutions, conflicts, outside_availability?}`; remove 204.

Also tell the conductor and B3 (ledger R2, D24 here): B2g adds `schedule_status=` and `substitutions_from=` to `create_subscription` and passes them from `renew_subscription` and `add_to_group_bundle`; whichever of B3d and B2g lands second keeps both slices' keyword arguments.

---

**Execution:** Plan 41 has 17 tasks — 10 backend (models and switch → generation → renewal copies → status actions → substitutions → teacher change → reads → payloads → API → seeds), 6 dashboard (11-16), then the e2e with the slice gates (17). The tasks depend on each other's interfaces in a strict chain (Task 4's lock feeds Tasks 5-6; Tasks 4-8 feed 9-10; Task 11's types feed every dashboard task), so subagent-driven execution with a review after each task, as Plans 21, 25, 31, 33 and 37 were built, is the fitting method.
