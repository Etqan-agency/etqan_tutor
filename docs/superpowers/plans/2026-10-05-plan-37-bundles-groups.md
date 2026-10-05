# Plan 37 — Study Groups and Subscription Bundles (slice B2f) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B2e (B2f is built on B2e's code: its migration `0010_trials_availability`, its route-table and registry lines, its conftest helpers). No other phase's slice. Task 20 is conditional on B3d (see its header); every other task builds against today's `create_subscription` / `renew_subscription`, with no currency.
**Slice:** B2f · **Phase spec:** docs/superpowers/specs/2026-10-03-b2-scheduling-depth-design.md (B2-2, B2-3, B2-13; §3 row B2f)

**Goal:** The office keeps study groups (named sets of students, each student in at most one) and creates subscription bundles of three kinds — multi-course (one student, several courses), family (students of one family) and group (one class for a whole study group) — that are renewed, paused, cancelled, archived and dissolved as one, while every member stays an ordinary `Subscription`; a group class is one session row per student and its rows never clash with each other; four per-academy switches, off by default.

**Architecture:**
- **Data** (spec §3). New `StudyGroup`, `StudyGroupMember` (one group per student: a unique student), `SubscriptionBundle` (kind + exactly the owner of its kind, a check constraint); `Subscription.bundle` (nullable, PROTECT, `related_name="subscriptions"`). One additive migration `0011_bundles_groups`. No data rewritten.
- **Platform** (ledger D15). `ConflictError` and `ValidationError` gain an optional `member_id`; the exception handler adds it to the body when set. Additive, after trunk's D25 `code`.
- **Services.** New `services/groups.py` (study groups), `services/bundles.py` (create a bundle; the lock and the all-or-nothing helpers), `services/bundle_actions.py` (renew, pause, cancel, archive, restore, add, remove, notes, dissolve), `services/bundle_reads.py` (list, filters, one bundle's view: members, current ones, totals, roster, `can_*`). `subscriptions.py`: `create_subscription(..., bundle=None)`; a renewal keeps the bundle and its course; `copied_slots`; deleting a bundle's last member deletes the bundle (bundle locked first). `rules.py`: `GROUP_BUNDLE_ID`, `group_siblings`, `group_bundle_of`; `generation.conflicts` and B2b's `_teacher_busy` leave out a group class's own rows (F-4).
- **API.** `groups/`, `groups/candidates/`, `groups/<id>/` (feature `study_groups`); `bundles/multi-course/`, `bundles/family/`, `bundles/group/` (one create route per kind, each gated by its feature); the shared, ungated `bundles/`, `bundles/<id>/` (read, notes, dissolve), `renew/`, `pause/`, `cancel/`, `members/`, `members/<student_id>/`; `bundles/<id>/archive/` (feature `subscription_archive`). Office only: 404 before the code check. Every created, renewed or added member is invoiced in the view, in the same transaction (P6-1). Subscription rows gain `bundle` (only when bundled) and the list's `bundle` / `bundle_kind` filters; session rows gain `group` (only for a group bundle's sessions).
- **Dashboard.** Study groups (`/app/people/groups`, list and dialog); a type choice on New subscription leading to the bundle form (multi-course, family, group; live totals); the bundle page (`/app/scheduling/bundles/<id>`: members, totals, roster tab, notes, actions with the refusing member named); "Part of a … bundle" on the subscription page, a list badge and filter; "Group: {name}" on session rows. New area files `bundles.json`, `studyGroups.json`.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod, i18next, Radix UI; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-10-03-b2f-bundles-groups-design.md` (slice B2f of the phase spec; approved; rulings summarised in `../_ledger/orchestration/phases/B2.md` "B2f spec"). It builds on Plan 4 (subscriptions, slots, generation, renewal, pauses, P4-9 clashes), Plan 6 (billing per subscription in the view, P6-1), Plan 11 (families), Plan 12b (supervision), Plan 13 (switches, `requires`, FT-4), B2a (one create route per kind, A-13), B2b (`teacher_busy`), B2d (archives), B2e. Ledger decisions **D6** (one Session row per group student), **D7** (bundles over Subscriptions), **D14** (archives), **D15** (`member_id`; group class paid N times until B4), **D23** / **D25** (B3d's currency hook and `ValidationError.code`). Where this plan fills a gap in the spec, the Plan rulings below say so.

## Global Constraints

**Repos and branches**
- Meta worktree: `/home/abdulkhalek/Projects/etqan_tutor-wt/b2` (`$W`). Meta, `backend/` and `dashboard/` are on `feat/b2f-bundles`, created by the controller off `origin/master` (meta) and `origin/main` (submodules) after B2e merged. `marketing/` is untouched.
- Commit in the submodule that owns the file (`git -C $W/backend …`, `git -C $W/dashboard …`). Never run `git submodule update` (or any writing `git submodule` subcommand) in this worktree.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` (this overrides any attribution line a harness suggests).
- Never edit `STATE.md`, CI workflows, Caddyfiles, or meta's submodule pointers.

**Commands (the slot-1 stack must be up: `just dev-backend`)**
- From `$W`, load the stream's environment first: `cd /home/abdulkhalek/Projects/etqan_tutor-wt/b2; set -a; . ./.env.stream; set +a`. Then run docker compose **directly** (a `$DC` variable does not word-split in zsh). `…` below stands for `docker compose -f docker-compose.local.yml`:
  - Backend tests: `… exec -T django pytest -q <paths>` (add `--create-db` once after the migration).
  - Backend format: `… exec -T django ruff check --fix .` then `… exec -T django ruff format .`
  - Backend verify: `… exec -T django ruff check .`, `… exec -T django ruff format --check .`, `… exec -T django lint-imports`, `… exec -T django pytest -q --cov=etqan`
  - Migration: `… exec -T django python manage.py makemigrations scheduling --name bundles_groups` (Task 2). Trunk's scheduling leaf after B2e is `0010_trials_availability`, so this is `0011_bundles_groups`.
  - Dashboard tests: `… exec -T dashboard pnpm exec vitest run <paths>`; verify: `… exec -T dashboard pnpm exec tsc --noEmit`, `… exec -T dashboard pnpm lint`, `… exec -T dashboard pnpm test:coverage`. Format first with `… exec -T dashboard pnpm exec biome check --write src e2e`.
  - New route files: regenerate `src/routeTree.gen.ts` with `… exec -T dashboard pnpm exec vite build` before `tsc` (generated: never hand-edit, never hand-merge).
  - Seeding this stream: `just _stack-manage migrate_schemas`, `just _stack-manage seed_dev`. E2E only through `just e2e …` (it runs `--workers=1 --retries=1`).
  - Slice gates: `just test`, `just lint`, `just e2e`.
- There is no host `.venv` or `node_modules`; never run `manage.py`, `migrate` or pytest against any other database.
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE`, `ERA`, `SLF`, `C901` (10), `E501` (88). Long keyword-only signatures carry `# noqa: PLR0913 -- keyword-only; mirrors the API body (spec §6)`. Imports are one per line (`from x import a` / `from x import b`), as every trunk file does. A boolean keyword argument is keyword-only (`*,` before it), or FBT fires. Code blocks in this plan are written to that style; where a line here exceeds 88 characters, `ruff format` wraps it — never shorten a name to dodge it.
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: semantic colour tokens only (`bg-secondary`, `text-muted-foreground`, `border-border`, `text-primary-text` …), never a literal colour — the checker also rejects `"#123456"`-like literals inside tests. Biome rejects `role="group"` on a div (use `<fieldset>` + `<legend>`) and an implicit-`any` `let`.

**TDD and reports (lessons from Plans 21, 25, 31 and 33)**
- Every task runs its new tests before the implementation and keeps the failing output (RED) for the report, then the passing output (GREEN). A report without RED evidence is sent back.
- Trunk helper names: the root `staff_for(*codes)` fixture (an `APIClient`; the user is `client.user`), `api_for("admin")`, `set_features(**switches)` (also `academy=`), `tenants.other`; scheduling's conftest: `clock` (`clock.set(datetime)`), `world` (`teacher`, `student` — Users — `course`, `package`), `subscribe(**overrides)`, `make_admin`, `make_teacher`, `make_student`, `hand_session(sub, *, occurs_on, start=time(10, 0), **fields)`, `two_slots()`, `subscription_for(world, **o)`, `course_teacher(world, name)`, `until_pk_exceeds`, `as_user(user)`, `archives_on`, `MONDAY`, `WEDNESDAY`. Shared test helpers go once in scheduling's conftest (Plan 25 ruling Q4), never copied between files: this plan adds `deactivated` (Task 3), `other_course`, `bare_bundle` (Task 4), `row`, `make_group`, `make_family`, `group_bundle`, `multi_bundle`, `member_of`, `bundles_on` (Task 6) there and nowhere else. `first_table(sql)` stays a two-line local helper per test file, as Plan 31's files have it.
- `etqan/platform/tests/test_features.py`'s `BUILT` dict lists every built switch **in registry order**: `study_groups` is flipped in place (it sits between `articles` and `donations` in the registry), and the three bundle switches are new lines under `# ── phase B2 ──` right after `teacher_availability`. Same commit as the registry.
- `etqan/access/tests/test_routes.py`: every new route joins `ROUTES`; gated ones join `FEATURES`; `FEATURE_WORDS` gets `/groups/` and the three per-kind create paths; the ungated bundle routes go in a new `UNGATED` set (spec F-11: "listed as intentionally ungated"). **Insert** into the current lists and dicts under a `# Slice B2f.` comment after B2e's lines; never paste them whole.
- `dashboard/src/routes/permissions.test.ts`: **insert** `people\/groups|` into the current `FEATURE_WORDS` regex (Plan 31 ruling R4); add the new feature screen to `FEATURE_SCREENS` under a `// Slice B2f` comment.
- Non-office callers of every group and bundle route get 404 from `OfficeOr404` (B2c's, `api/activity_views.py`) listed **before** `HasCode`; a switched-off feature answers 404 **after** the permission check (`FeatureOn` last).
- A list or read that renders rows carries a query-count test that counts **SELECTs only** (`sql.lstrip().upper().startswith("SELECT")`), the same for 1 and 3 rows.
- A lock-order test captures the SQL and asserts the member lock's form `…ORDER BY 1 ASC FOR UPDATE` (Plan 31's form: `values_list("pk")` after `order_by("pk")`).
- Scheduling code and tests may not import `etqan.identity.models`, `etqan.catalogue.models` or `etqan.site` (import-linter); go through `identity_services` / `catalogue_services`. Querying across a relation (`student__user__is_active`, `bundle.family.name`) is not an import and is allowed.
- The dashboard never restates a server rule: what may be done to a bundle is the server's `can_renew` / `can_pause` / `can_cancel` / `can_archive` / `can_restore` / `can_add_member` and the roster's `can_remove`; a study group's Delete is its `can_delete`; who may join a group is the server's candidates list; a refused write shows the translated code and the member the server names (`member_id`).
- Outside the app shell every switch counts as on and every code is held (`useHasFeature` / `useCan` allow all): a test rendering a touched page must mock every API call that page now makes (`bundleApi` as well as `schedulingApi`).
- Async router mount: in tests, the first query after `renderWithRouter` is a `findBy*`; a negative check (`queryBy… → null`) waits for a sibling marker first.

**Coverage and dev data**
- Gates: backend ≥ 80 %; dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026`; `demo` admin `admin@demo.test` ("Demo Academy Admin"). Demo has every built switch on (`seed_dev.FEATURES`).

**Orchestration rules**
- Shared lists: lines only under `── phase B2 ──` (feature registry — `study_groups` flipped in place, three new lines under the marker; `test_features.BUILT`; the access registry's `study_group` resource; the dashboard nav's B2 block; `seed_dev`'s B2 block calls `b2.seed_bundles`). No new app: `TENANT_APPS`, `config/api_router.py` (scheduling's routes live in `etqan/scheduling/api/urls.py`, B2's) and `pyproject.toml`'s import contracts are unchanged.
- Platform change (`etqan/platform/exceptions.py`, `drf.py`) is additive (ledger D15) and lands after trunk's D25 `code` parameter (B9c), which is already on `main`.
- Files outside `etqan.scheduling` / the scheduling dashboard feature that this plan touches: `backend/etqan/platform/exceptions.py`, `drf.py` (+ test); `backend/etqan/platform/features.py` (+ test); `backend/etqan/access/registry.py` and `tests/test_routes.py`; `backend/etqan/tenants/seeds/b2.py`, `management/commands/seed_dev.py` (B2 block) and the three seed tests (counts narrowed to non-bundle rows, Task 12); `dashboard/src/features/identity/schemas.ts` (`FeatureCode`); `dashboard/src/features/shell/nav.ts` (+ test); `dashboard/src/routes/permissions.test.ts`.
- New translation areas: `dashboard/src/locales/{en,ar}/bundles.json` and `studyGroups.json`, holding their keys directly (the catalogue wraps each file under its name). `errors.json`'s `scheduling` codes are B2's and edited in place. No `es` file (ledger D22). No plural keys (the ar/en key-equality test).
- New e2e spec: `dashboard/e2e/b2-bundles.spec.ts`, owning its stamped data, safe to run twice on one database, no faked time, asserting durable state (rows, URLs, statuses after reload), never a transient toast.
- Migrations are additive (phase B2-16). Never `makemigrations --merge`; on a clash after a rebase, delete this plan's migration and regenerate it.
- Service signature changes are additive only: `create_subscription(..., bundle=None)`; `ConflictError(..., member_id=None)`, `ValidationError(..., member_id=None)`; `filter_subscriptions(..., bundle=None, bundle_kind="")`.

**Lock order (binding, spec §4; plan rulings D2, D3)**
- Bundle (`SELECT … FOR NO KEY UPDATE`) → every member in one `SELECT … ORDER BY 1 ASC FOR UPDATE` → (inside the per-member service) the member's sessions (Plan 4). Every bundle action takes both locks before any per-member call; `update_bundle` (notes) takes only the bundle's.
- `delete_subscription` on a bundled member locks the bundle first (same `FOR NO KEY UPDATE`), then its own row as today.
- `create_bundle` (group) takes the study group `FOR NO KEY UPDATE` before reading its members, so `delete_group` / `update_group` (`FOR UPDATE` on the group) never interleave with it.

**API and data rules (spec values verbatim)**
- 409 bodies `{detail, code}`; a member's refusal inside a bundle action keeps its status, code and field and adds `member_id` (§4.6). New codes: `scheduling.group_in_use`, `scheduling.nothing_to_renew`.
- Switches (built, off by default, group `teaching`): `study_groups` (flipped in place), `multi_course_subscriptions`, `family_subscriptions` (requires `families`), `group_subscriptions` (requires `study_groups`).
- Bundle kinds: `multi_course` (one student, ≥ 2 rows, distinct courses), `family` (students of one active family, ≥ 2 rows, student + course distinct), `group` (one active study group, exactly one row, one subscription per active member). Packages of any type.
- Study group: name\* (≤ 120), students\* (User ids; each student in at most one group; a new member must be active), notes, active (default true).
- Access: resource `study_group` ("Study groups" / "المجموعات الدراسية"), in use `view`, `view_any`, `create`, `update`, `delete`. Bundles: list `subscription.view_any`, read `subscription.view`, create `subscription.create`, renew / pause / cancel / members / notes / dissolve `subscription.update`, archive `subscription.delete`, restore `subscription.restore`.

## Plan rulings (where the spec is silent, contradictory or leaves a choice)

- **D1 — Row errors are keyed `rows.<i>.<field>`**, not `rows[i].<field>` as the spec writes it: DRF's own nested-serializer errors and the dashboard's `parseApiError` already flatten to the dot form, which react-hook-form uses as its field path, so one form handles both. The bundle's own fields `starts_on` and `supervisor_id` stay top-level; an error with no field is `rows.<i>`. **B3d's D-5 (and ledger request R2 (4)) write `rows[0].price_minor`: read it as `rows.0.price_minor`** — whichever side builds D-5 emits and maps the dot form. The controller tells the conductor and B3 before either side builds it (review I-4).
- **D2 — The bundle row is locked `FOR NO KEY UPDATE`** (`select_for_update(no_key=True)`). Inserting or deleting a member takes PostgreSQL's `FOR KEY SHARE` on the bundle row (its foreign key); a plain `FOR UPDATE` would conflict with it, and a lone member's renewal (member locked, then its insert waiting on the bundle) against a bundle action (bundle locked, then waiting on that member) would deadlock. `NO KEY UPDATE` still serialises bundle actions among themselves.
- **D3 — `delete_subscription` locks a member's bundle before the member** (§4's order), and deletes the bundle when it removed its last member (F-9). The subscription's `bundle_id` is read before the lock; a bundle dissolved meanwhile is simply not found.
- **D4 — Current members** are those with no renewal row at all (`renewal__isnull=True`, F-5). Actions skip cancelled current members. The roster shows, per student, the newest current non-cancelled member, else the newest current one, else the newest.
- **D5 — Pause and cancel choose among live members, not only current ones.** §4.3's pause note ("so an old link and its not-yet-started renewal never both get it") only makes sense if the old link is a candidate: a pause goes to every live member whose term holds `from_date`. Cancel cancels every live member, the old link and a pending renewal alike — as §4.3 says for removing a group student — so a cancelled bundle stops teaching at once. No candidate: pause → 400 on `from_date`; cancel → 409 `scheduling.not_allowed_in_status` (no `member_id`).
- **D6 — Archive and restore apply to every member of the bundle (all links)**, not only the current ones: an archived bundle leaves nothing of itself in the default lists. Archive refuses while any member is live (409 `scheduling.not_allowed_in_status`, `member_id` = the first live member by id); members already archived are skipped; nothing left to archive → 409 `scheduling.archived`; nothing to restore → 409 `scheduling.not_archived`.
- **D7 — A member's renewal course refusal is 400 on `course`** (the body key the renew dialog shows it on, as B2e D3 chose body keys), not `course_id`. Naming the same course is allowed.
- **D8 — Group roster changes.** Adding: a non-group bundle → 400 `detail`; the student inactive or unknown → 400 on `student_id`; already holding a live member here → 400 on `student_id`; no current non-cancelled member to copy → 409 `scheduling.not_allowed_in_status`. The new subscription copies the template's course, teacher, package, price (P4-10 is about renewals; the template's price is the class's price) and active slots (as renewal copies them), and keeps its supervisor while they may still be one. A refusal of the copied values names the template (`member_id`). Removing: non-group → 400 `detail`; nothing live → 409 `scheduling.not_allowed_in_status` (spec).
- **D9 — A group bundle needs an active study group** (400 on `group_id`) with at least one active student (400 on `group_id`). A multi-course bundle's owner is 400 on `student_id`; a family's 400 on `family_id` (unknown or retired). A row's `student` is read only for family bundles.
- **D10 — Optional payload keys.** `bundle: {id, kind}` appears on subscription rows only for members, and `group: {bundle_id, name}` on session rows only for a group bundle's sessions: every existing payload stays byte-for-byte today's (Plan 33 D6's pattern).
- **D11 — The bundle payload carries the server's `can_*` flags**: `can_renew` (there is a current, non-cancelled member, and every such member may renew — the action is all or nothing), `can_pause` and `can_cancel` (a live member), `can_add_member` (a group with a current non-cancelled member), and, only while `subscription_archive` is on, `can_archive` (every member ended, one not archived, none with a session still due) and `can_restore` (one archived). Roster rows carry `can_remove` (a group student with a live member). The dashboard shows exactly these.
- **D12 — The create answer is 201 with the bundle detail plus `conflicts: [{session, other}]`.** The form goes straight to the bundle page when there is none; otherwise it lists them with a link to the bundle (P4-9: reported, never blocked). This is where the e2e reads "no clash warning".
- **D13 — Who may join a study group is the server's:** `GET groups/candidates/?q=&group=<id>` (codes `study_group.create` or `study_group.update`, feature `study_groups`) answers up to 20 active students in no other group, by name. The dialog never filters on its own.
- **D14 — Bundles list.** `GET bundles/` filters: `kind`, `student` (User id: the owner or any member's student), `family`, `group`, `state` (`live`: a current member is live; `ended`). The dashboard has no bundles list screen (spec §7 lists none); bundles are reached from their members' badges and the list's type filter.
- **D15 — Service signatures take `by` only where it is recorded**: `create_bundle(kind, by, …)` (`created_by`), `renew_bundle(bundle, *, by, …)` (the activity log of moved sessions), `archive_bundle` / `restore_bundle(bundle, *, by)`. `pause_bundle`, `cancel_bundle`, `add_to_group_bundle`, `remove_from_group_bundle`, `update_bundle`, `dissolve_bundle` take none (Plan 33 D4: an unused argument is noise). Bundle actions answer 200 with the bundle detail; adding a student 201; dissolving 204.
- **D16 — Totals** = `{sessions_total, prices: [{currency, price_minor}]}` over current non-cancelled members, prices summed per currency and sorted by currency (§4.5, BR-09/10; never across currencies). Members carry `current` and `freeze_days_left` (the pause dialog names a refusing member's remaining freeze days from it: §4.3's "naming the member and its remaining freeze days" without changing `add_pause`'s message).
- **D17 — The clash exemption costs no query in `conflicts`:** the "others" query is annotated with the session's group bundle (a `CASE`), and created sessions are always among the others (non-cancelled, same teacher, inside the window). `_teacher_busy` compares through `Coalesce(…, 0)`, so a plain session at the same start is never dropped by a `NULL` comparison.
- **D18 — Dashboard files** live in `features/scheduling` (B2's) as new files `bundleSchemas.ts`, `bundleApi.ts` (tests mock it apart from `./api`), `bundleQueries.ts`, `refusal.ts` and the components. `BundleRowFields` is its own component on `useChoices` and `SlotFields`: `TermFields` is not touched (it is ledger R2's hook target for B3d). `BundleRef` and `GroupLabel` are declared in `schemas.ts` beside `Subscription` / `Session`.
- **D19 — Routes.** The type choice lives on the existing `/scheduling/subscriptions/new` (search `type=multi_course|family|group`, validated); no new create route. The bundle page (route made in Task 13, D28) `/scheduling/bundles/$bundleId` needs `subscription.view` and no feature (its API is ungated). Study groups: `/people/groups` (`study_group.view_any`, feature `study_groups`), add and edit in dialogs as families are.
- **D20 — Owner pickers need their own read code:** the family form lists families only for `family.view_any`, the group form study groups only for `study_group.view_any`; a type whose picker the viewer may not read is not offered.
- **D21 — Seeds** (spec §8): in demo, run whatever the switches say (bundles are data the ungated routes read; demo has every built switch on anyway); marker "a bundle exists"; all three start today: group "Evening Quran circle" (Yusuf Omar, Aisha Omar, Zaid Huda; Quran Memorisation, Ustadha Maryam, "Monthly, 2 a week", Tue + Thu 19:00); multi-course for Zaid Huda (Tajweed / Bilal Sat 13:00; Quran Memorisation / Maryam Sat 15:00); family over "Omar family" (Yusuf: Tajweed / Bilal Sat 09:00; Aisha: Quran Memorisation / Maryam Sat 11:00). **No bundle gives Aisha Omar a Tajweed subscription** (review I-1): B2d's seed marker ("Aisha has a Tajweed subscription") and `test_seed_b2.py`'s archive test (exactly one Aisha/Tajweed row) stay untouched. No invoices (billing is the API's, as B2e's seeds). The shared seed tests that count every subscription (`test_seed_dev.py`, `test_seed_staging.py`) read the non-bundle rows (`bundle__isnull=True`) — a deliberate edit of two existing tests, as B2d and B2e made (spec §9 "existing suites pass unchanged" holds for every other suite).
- **D22 — Messages.** `scheduling.group_in_use`: "This study group has subscription bundles. Dissolve them first."; `scheduling.nothing_to_renew`: "Nothing in this bundle can be renewed."
- **D23 — A study-group membership race** (two saves putting one student in two groups) ends on the unique constraint: the second is 400 on `student_ids`, never a 500.
- **D24 — Rebase note.** B3d flips `country_pricing` in place right before `study_groups` in the registry and in `BUILT`: whichever lands second keeps both lines, in registry order. B3d may also have touched `ValidationError`; `member_id` is added after `code`, keyword-compatible with either order of landing.
- **D25 — `lock_bundle` takes a second pass** (review M-1): a lone member's renewal that commits while the member lock waits is outside that statement's snapshot, so a fresh statement locks any newcomer (same id order) before the action reads its members. Tested in Task 7 through the `_lock_ids` seam.
- **D26 — A create body holds at most 20 rows** (review M-2, `MAX_BUNDLE_ROWS`); DRF answers 400 on `rows` past it.
- **D27 — A bundle row starts with one slot group**, as the subscription form does (review I-2): it needs a day and a time to submit, or the user removes it for a slotless row.
- **D28 — The bundle screen's route exists from Task 13** as a header-only screen (review I-3), so the typed `/scheduling/bundles/$bundleId` links of Tasks 16 and 18 compile task by task; Task 17 renders the page in it.

## Review Focus

- **A removed group student and a cancelled renewal.** Expected: a bundle renewal never re-enrols a student whose current member is cancelled; with every current member cancelled the renewal is 409 `scheduling.nothing_to_renew`. Tests: Task 7 `test_a_removed_student_is_never_renewed_again`, `test_a_cancelled_member_is_skipped_and_nothing_left_is_409`.
- **A pause whose date falls in an old link's term while its renewal is pending.** Expected: only the link whose term holds the date is paused; a cap reached by any one member refuses all, naming it. Tests: Task 7 `test_a_pause_goes_to_the_link_whose_term_holds_it`, `test_the_freeze_cap_refuses_the_whole_pause_and_names_the_member`.
- **A lone member renewed while a bundle action runs.** Expected: no deadlock — the bundle is locked `FOR NO KEY UPDATE`, members after it in id order; a member's delete takes the bundle first too. Tests: Task 7 `test_the_bundle_is_locked_before_its_members` (parametrised over every action), Task 4 `test_a_members_delete_locks_the_bundle_first`.
- **The clash exemption hiding a real clash.** Expected: only rows of one group bundle at the same start and minutes are exempt; another group, a multi-course sibling, a plain lesson at the same time, or a different start inside the group still clash, and a plain lesson at the same start still makes a postponement `teacher_busy`. Tests: Task 5 (all six).
- **Deleting members one by one.** Expected: the bundle survives while it has a member (even below its creation minimum) and goes with its last one. Test: Task 4 `test_deleting_the_last_member_deletes_the_bundle`.

---

## File Structure

```
backend/
  etqan/platform/exceptions.py drf.py (+tests/test_drf.py)      member_id (Task 1)
  etqan/platform/features.py (+tests/test_features.py)           study_groups flipped; three switches (Task 2)
  etqan/access/registry.py                                       study_group under ── phase B2 ── (Task 10)
  etqan/access/tests/test_routes.py                              ROUTES, FEATURES, FEATURE_WORDS, UNGATED (Tasks 10, 11)
  etqan/scheduling/
    models.py                                                    StudyGroup, StudyGroupMember, SubscriptionBundle,
                                                                 Subscription.bundle (Task 2)
    migrations/0011_bundles_groups.py                            generated (Task 2)
    services/groups.py                                           NEW (Task 3)
    services/subscriptions.py                                    bundle=, copied_slots, renewal keeps bundle and
                                                                 course, last member deletes bundle (Task 4)
    services/rules.py generation.py postpone.py                  F-4 clash exemption (Task 5)
    services/bundles.py                                          NEW: create_bundle (Task 6); locks and helpers (Task 7)
    services/bundle_actions.py                                   NEW (Tasks 7, 8)
    services/bundle_reads.py                                     NEW (Task 9)
    services/__init__.py                                         exports (Tasks 3-9)
    api/serializers.py                                           group and bundle bodies (Tasks 10, 11)
    api/bundle_payloads.py                                       NEW (Tasks 10, 11)
    api/payloads.py views.py                                     bundle on subscription rows, group on sessions,
                                                                 list filters (Task 9)
    api/group_views.py bundle_views.py                           NEW (Tasks 10, 11)
    api/urls.py                                                  routes (Tasks 10, 11)
    tests/conftest.py                                            helpers (Tasks 3, 4, 6)
    tests/test_bundles_*.py test_groups_*.py test_api_*.py       NEW (Tasks 2-11)
  etqan/tenants/seeds/b2.py tests/test_seed_b2.py                seed_bundles (Task 12)
  etqan/tenants/tests/test_seed_dev.py test_seed_staging.py      non-bundle counts (Task 12)
  etqan/tenants/management/commands/seed_dev.py                  one call in the B2 block (Task 12)
dashboard/
  src/features/identity/schemas.ts                               FeatureCode + 4 (Task 13)
  src/features/scheduling/
    schemas.ts                                                   BundleRef, GroupLabel; Subscription.bundle,
                                                                 Session.group (Task 13)
    bundleSchemas.ts bundleApi.ts bundleQueries.ts refusal.ts    NEW (Task 13)
    StudyGroupsList.tsx StudyGroupDialog.tsx (+tests)            NEW (Task 14)
    BundleRowFields.tsx BundleForm.tsx (+tests)                  NEW (Tasks 15, 16)
    SubscriptionTypeChoice.tsx NewSubscription.tsx (+tests)      type choice (Task 16)
    BundlePage.tsx BundleMembers.tsx BundleRoster.tsx (+tests)   NEW (Task 17)
    BundleActions.tsx (+test)                                    NEW (Task 18)
    GroupChip.tsx BundleLink.tsx (+tests)                        NEW (Task 19)
    SubscriptionDetail.tsx SubscriptionsList.tsx SessionsList.tsx
    SessionsPanel.tsx TeacherSessionTable.tsx FamilySessions.tsx
    SessionPage.tsx                                              badge, filter, link, group chip (Task 19)
    index.ts                                                     exports (Tasks 13-19)
  src/features/shell/nav.ts (+nav.test.ts)                       Study groups under ── phase B2 ── (Task 14)
  src/routes/_authed/people.groups.index.tsx                     NEW (Task 14)
  src/routes/_authed/scheduling.bundles.$bundleId.tsx            NEW, minimal (Task 13); the page (Task 17)
  src/routes/_authed/scheduling.subscriptions.new.tsx            ?type= (Task 16)
  src/routes/permissions.test.ts                                 FEATURE_SCREENS, FEATURE_WORDS (Task 14)
  src/routeTree.gen.ts                                           regenerated (Tasks 13, 14)
  src/locales/{en,ar}/bundles.json studyGroups.json              NEW (Task 13)
  src/locales/{en,ar}/errors.json                                two codes (Task 13)
  src/test/scheduling-fixtures.ts                                studyGroupRow, bundleMember, bundleDetail (Task 13)
  e2e/b2-bundles.spec.ts                                         NEW (Task 21)
```

---
### Task 1: `member_id` on the platform's refusals (ledger D15)

**Files:**
- Modify: `backend/etqan/platform/exceptions.py` (`ConflictError`, `ValidationError`)
- Modify: `backend/etqan/platform/drf.py` (`exception_handler`)
- Test: `backend/etqan/platform/tests/test_drf.py`

**Interfaces:**
- Consumes: trunk's `ValidationError(message, field=None, code="validation_error")` (B9c, ledger D25) and the handler that adds `code` when it is not the default.
- Produces: `ConflictError(message, code="conflict", member_id: int | None = None)`, `ValidationError(message, field=None, code="validation_error", member_id: int | None = None)`; both expose `.member_id`. The handler adds `"member_id": <int>` to the body when it is not None, after `code`.

- [ ] **Step 1: Write the failing tests** (append to `backend/etqan/platform/tests/test_drf.py`)

```python
def test_a_bundle_members_refusal_names_the_member():
    """Slice B2f §4.6 (ledger D15): a bundle action re-raises one member's
    refusal with that subscription's id; status, code and field are kept."""
    conflict = exception_handler(
        ConflictError(
            "Too many freeze days.",
            code="scheduling.freeze_days_exceeded",
            member_id=12,
        ),
        {},
    )
    assert conflict.status_code == 409
    assert conflict.data == {
        "detail": "Too many freeze days.",
        "code": "scheduling.freeze_days_exceeded",
        "member_id": 12,
    }
    invalid = exception_handler(
        ValidationError("Choose an active student.", field="student", member_id=12),
        {},
    )
    assert invalid.status_code == 400
    assert invalid.data == {"student": ["Choose an active student."], "member_id": 12}


def test_without_a_member_every_body_is_unchanged():
    assert ConflictError("x").member_id is None
    assert ValidationError("x").member_id is None
    assert exception_handler(ConflictError("x", code="a.b"), {}).data == {
        "detail": "x",
        "code": "a.b",
    }
    assert exception_handler(ValidationError("bad", field="f"), {}).data == {
        "f": ["bad"]
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/platform/tests/test_drf.py`
Expected: FAIL — `TypeError: ConflictError.__init__() got an unexpected keyword argument 'member_id'`.

- [ ] **Step 3: Implement**

`backend/etqan/platform/exceptions.py` — `ConflictError` and `ValidationError` become:

```python
class ConflictError(EtqanError):
    """The request was well-formed but lost a race for a resource.

    Distinct from ValidationError on purpose: nothing about the caller's input
    was wrong, so telling them it was would send them off editing a correct
    request. The canonical case is two teachers accepting one match request.
    """

    def __init__(
        self, message: str, code: str = "conflict", member_id: int | None = None
    ):
        # `code` names the rule that refused the request (for example
        # "scheduling.already_renewed"). The API returns it next to `detail` so
        # clients can show their own translated wording.
        # Slice B2f §4.6 (ledger D15): the bundle member that refused, when a
        # bundle action re-raises one member's refusal.
        self.member_id = member_id
        super().__init__(message=message, code=code)


class ValidationError(EtqanError):
    def __init__(
        self,
        message: str,
        field: str | None = None,
        code: str = "validation_error",
        member_id: int | None = None,
    ):
        self.field = field
        # Slice B2f §4.6 (ledger D15), as on ConflictError.
        self.member_id = member_id
        super().__init__(message=message, code=code)
```

`backend/etqan/platform/drf.py` — in `exception_handler`, widen the body's type and add the member after the code:

```python
        field = getattr(exc, "field", None)
        body: dict[str, list[str] | str | int]
        body = {field: [exc.message]} if field else {"detail": exc.message}
        if isinstance(exc, ConflictError | UnavailableError) or (
            isinstance(exc, ValidationError) and exc.code != "validation_error"
        ):
            body["code"] = exc.code
        # Slice B2f §4.6 (ledger D15): which bundle member refused.
        member_id = getattr(exc, "member_id", None)
        if member_id is not None:
            body["member_id"] = member_id
        return Response(body, status=http_status)
```

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/platform`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/platform/exceptions.py etqan/platform/drf.py etqan/platform/tests/test_drf.py
git -C $W/backend commit -m "feat(platform): refusals may name the bundle member that refused (B2f, ledger D15)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 2: The switches, the study group and bundle tables, `Subscription.bundle`, and the migration

**Files:**
- Modify: `backend/etqan/platform/features.py` (flip `study_groups` in place; three lines under `# ── phase B2 ──` after `teacher_availability`)
- Modify: `backend/etqan/platform/tests/test_features.py` (`BUILT`)
- Modify: `backend/etqan/scheduling/models.py` (`StudyGroup`, `StudyGroupMember`, `SubscriptionBundle` before `Subscription`; `Subscription.bundle`)
- Create: `backend/etqan/scheduling/migrations/0011_bundles_groups.py` (generated)
- Test: `backend/etqan/scheduling/tests/test_bundles_model.py`

**Interfaces:**
- Produces: feature codes `study_groups`, `multi_course_subscriptions`, `family_subscriptions` (requires `families`), `group_subscriptions` (requires `study_groups`) — built, default off, group `teaching`. Models `StudyGroup(name, notes, is_active, created_at, updated_at)`, `StudyGroupMember(group → StudyGroup CASCADE related_name="members", student → identity.StudentProfile OneToOne CASCADE related_name="+", added_at)`, `SubscriptionBundle(kind: Kind{MULTI_COURSE, FAMILY, GROUP}, student → StudentProfile, family → identity.Family, study_group → StudyGroup related_name="bundles", notes, created_by, created_at, updated_at)` with constraint `scheduling_bundle_owner_matches_kind`; `Subscription.bundle` (→ SubscriptionBundle, null, PROTECT, `related_name="subscriptions"`).

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_bundles_model.py`)

```python
"""Slice B2f §3, F-11: the four switches and the new tables."""

import pytest
from django.db import IntegrityError
from django.db import transaction
from django.db.models import ProtectedError

from etqan.platform import features
from etqan.scheduling.models import StudyGroup
from etqan.scheduling.models import StudyGroupMember
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.tests.conftest import subscription_for

pytestmark = pytest.mark.django_db
SWITCHES = (
    "study_groups",
    "multi_course_subscriptions",
    "family_subscriptions",
    "group_subscriptions",
)


@pytest.mark.parametrize("code", SWITCHES)
def test_the_four_switches_are_built_and_off_by_default(code):
    feature = features.get(code)
    assert (feature.built, feature.default, feature.group) == (True, False, "teaching")
    assert features.is_on(code, {}) is False


def test_family_and_group_bundles_need_their_prerequisite():
    assert features.get("multi_course_subscriptions").requires == ()
    assert features.get("family_subscriptions").requires == ("families",)
    assert features.get("group_subscriptions").requires == ("study_groups",)
    alone = {"group_subscriptions": True}
    assert features.is_on("group_subscriptions", alone) is False
    assert features.is_on("group_subscriptions", {**alone, "study_groups": True})
    assert not features.is_on(
        "family_subscriptions", {"family_subscriptions": True, "families": False}
    )


def test_the_bundle_switches_follow_b2e_under_the_b2_marker():
    codes = [feature.code for feature in features.REGISTRY]
    start = codes.index("teacher_availability")
    assert codes[start + 1 : start + 4] == [
        "multi_course_subscriptions",
        "family_subscriptions",
        "group_subscriptions",
    ]
    # Flipped in place, where Plan 13 listed it.
    assert codes.index("articles") < codes.index("study_groups")
    assert codes.index("study_groups") < codes.index("donations")


def test_a_student_is_in_one_study_group_at_most(world):
    profile = world.student.student_profile
    evening = StudyGroup.objects.create(name="Evening")
    morning = StudyGroup.objects.create(name="Morning")
    StudyGroupMember.objects.create(group=evening, student=profile)
    with pytest.raises(IntegrityError), transaction.atomic():
        StudyGroupMember.objects.create(group=morning, student=profile)


@pytest.mark.parametrize(
    ("kind", "owner"),
    [("multi_course", "study_group"), ("group", "student"), ("family", "student")],
)
def test_a_bundle_names_exactly_the_owner_of_its_kind(world, kind, owner):
    owners = {
        "student": world.student.student_profile,
        "study_group": StudyGroup.objects.create(name="Evening"),
    }
    with pytest.raises(IntegrityError), transaction.atomic():
        SubscriptionBundle.objects.create(kind=kind, **{owner: owners[owner]})


def test_a_subscription_is_in_no_bundle_and_a_bundle_keeps_its_members(world):
    sub = subscription_for(world)
    assert sub.bundle_id is None
    bundle = SubscriptionBundle.objects.create(
        kind=SubscriptionBundle.Kind.MULTI_COURSE,
        student=world.student.student_profile,
    )
    Subscription.objects.filter(pk=sub.pk).update(bundle=bundle)
    assert list(bundle.subscriptions.values_list("pk", flat=True)) == [sub.pk]
    with pytest.raises(ProtectedError):
        bundle.delete()
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_model.py`
Expected: FAIL — `ImportError: cannot import name 'StudyGroup'`.

- [ ] **Step 3: The switches**

`backend/etqan/platform/features.py` — replace the `_later("study_groups", …)` line in place with:

```python
    # Slice B2f (Plan 37): flipped to built in place, off by default.
    Feature(
        "study_groups",
        "Study groups",
        "نظام المجموعات الدراسية",
        "teaching",
        built=True,
    ),
```

and add after B2e's `teacher_availability` feature, still under `# ── phase B2 ──`:

```python
    # Slice B2f (Plan 37): subscription bundles, one switch per kind, off by
    # default; a family bundle needs families, a group bundle study groups.
    Feature(
        "multi_course_subscriptions",
        "Multi-course subscriptions",
        "الاشتراكات متعددة الدورات",
        "teaching",
        built=True,
    ),
    Feature(
        "family_subscriptions",
        "Family subscriptions",
        "اشتراكات العائلات",
        "teaching",
        built=True,
        requires=("families",),
    ),
    Feature(
        "group_subscriptions",
        "Group subscriptions",
        "اشتراكات المجموعات",
        "teaching",
        built=True,
        requires=("study_groups",),
    ),
```

`backend/etqan/platform/tests/test_features.py` — in `BUILT`, insert `"study_groups": False,` right after `"articles": False,` (and add "B2f's study_groups" to the comment's list of flipped lines), and after `"teacher_availability": False,`:

```python
    "multi_course_subscriptions": False,
    "family_subscriptions": False,
    "group_subscriptions": False,
```

- [ ] **Step 4: The models**

`backend/etqan/scheduling/models.py` — add before `class Subscription`:

```python
class StudyGroup(models.Model):
    """Slice B2f §3.1 (F-1): a named set of students taught together; each
    student is in at most one (BR-17). A bundle does not follow later changes
    of its group (F-7)."""

    name = models.CharField(max_length=120)
    notes = models.TextField(blank=True, default="")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name", "id"]

    def __str__(self):
        return f"StudyGroup<{self.name}>"


class StudyGroupMember(models.Model):
    group = models.ForeignKey(
        StudyGroup, on_delete=models.CASCADE, related_name="members"
    )
    # One group per student (BR-17): one-to-one, so the database says so.
    student = models.OneToOneField(
        "identity.StudentProfile", on_delete=models.CASCADE, related_name="+"
    )
    added_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["group", "id"]

    def __str__(self):
        return f"StudyGroupMember<{self.group_id}, {self.student_id}>"


class SubscriptionBundle(models.Model):
    """Slice B2f §3.2 (ledger D7): several subscriptions made, renewed,
    paused, cancelled and archived as one. Each member is an ordinary
    `Subscription` (F-3); the bundle stores only its kind, its owner and its
    notes — totals are read, never stored."""

    class Kind(models.TextChoices):
        MULTI_COURSE = "multi_course", "Multi-course"
        FAMILY = "family", "Family"
        GROUP = "group", "Group"

    kind = models.CharField(max_length=12, choices=Kind.choices)
    student = models.ForeignKey(
        "identity.StudentProfile",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    # Families are never deleted (Plan 11): PROTECT costs nothing.
    family = models.ForeignKey(
        "identity.Family",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    study_group = models.ForeignKey(
        StudyGroup,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="bundles",
    )
    notes = models.TextField(blank=True, default="")
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
        ordering = ["-created_at", "-id"]
        constraints = [
            # §3.2: exactly the field of its kind is set.
            models.CheckConstraint(
                condition=Q(
                    kind="multi_course",
                    student__isnull=False,
                    family__isnull=True,
                    study_group__isnull=True,
                )
                | Q(
                    kind="family",
                    student__isnull=True,
                    family__isnull=False,
                    study_group__isnull=True,
                )
                | Q(
                    kind="group",
                    student__isnull=True,
                    family__isnull=True,
                    study_group__isnull=False,
                ),
                name="scheduling_bundle_owner_matches_kind",
            )
        ]

    def __str__(self):
        return f"SubscriptionBundle<{self.pk}, {self.kind}>"
```

and in `Subscription`, after `archived_by`:

```python
    # Slice B2f §3.3 (ledger D7): the bundle it belongs to. Nullable, no data
    # changes (B2-16); PROTECT: a bundle's members are unlinked (dissolve) or
    # deleted before the bundle goes (F-9).
    bundle = models.ForeignKey(
        SubscriptionBundle,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="subscriptions",
    )
```

- [ ] **Step 5: Generate the migration**

Run: `… exec -T django python manage.py makemigrations scheduling --name bundles_groups`
Expected: `0011_bundles_groups.py` creating the three models, the constraint and `subscription.bundle` (nullable). Read it: nothing altered or removed on existing columns.

- [ ] **Step 6: Run the tests to see them pass**

Run: `… exec -T django pytest -q --create-db etqan/scheduling/tests/test_bundles_model.py etqan/platform/tests/test_features.py`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/platform/features.py etqan/platform/tests/test_features.py etqan/scheduling/models.py etqan/scheduling/migrations/0011_bundles_groups.py etqan/scheduling/tests/test_bundles_model.py
git -C $W/backend commit -m "feat(scheduling): study groups, subscription bundles and their switches (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 3: Study groups — create, update, delete, read, and who may join

**Files:**
- Create: `backend/etqan/scheduling/services/groups.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Modify: `backend/etqan/scheduling/tests/conftest.py` (`deactivated`)
- Test: `backend/etqan/scheduling/tests/test_groups_services.py`

**Interfaces:**
- Consumes: `identity_services.get_student_profile(user_id)`, `identity_services.people_queryset("student")`; `StudyGroup`, `StudyGroupMember`, `SubscriptionBundle` (Task 2).
- Produces (exported from `etqan.scheduling.services`): `create_group(*, name, student_ids, notes="", is_active=True) -> StudyGroup`; `update_group(group, *, fields: dict) -> StudyGroup` (keys `name`, `notes`, `is_active`, `student_ids` — the full list); `delete_group(group) -> None` (409 `scheduling.group_in_use`); `groups_queryset() -> QuerySet[StudyGroup]` (annotated `in_use`, members prefetched with `student__user`, by name); `filter_groups(groups, *, q="", is_active="") -> QuerySet` (`is_active` is `"true"`, `"false"` or `""`); `group_candidates(*, q="", group=None) -> list[User]`; `MAX_CANDIDATES = 20`. Conftest: `deactivated(user) -> user` (sets `is_active=False` straight in the table).

- [ ] **Step 1: The conftest helper** (`backend/etqan/scheduling/tests/conftest.py`, after `as_user`)

```python
def deactivated(user):
    """``user`` with their account switched off straight in the table, for
    tests whose subject is not identity's deactivation (slice B2f)."""
    type(user).objects.filter(pk=user.pk).update(is_active=False)
    user.refresh_from_db()
    return user
```

- [ ] **Step 2: Write the failing tests** (`backend/etqan/scheduling/tests/test_groups_services.py`)

```python
"""Slice B2f §4.1: study groups — one group per student (BR-17), active rules,
and no delete while a bundle uses the group."""

import pytest

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import StudyGroup
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.tests.conftest import deactivated
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher

pytestmark = pytest.mark.django_db


def members(group) -> list[int]:
    return sorted(group.members.values_list("student__user_id", flat=True))


def test_a_group_holds_its_students_once_each(world):
    sister = make_student("Aisha")
    group = services.create_group(
        name="  Evening circle ",
        student_ids=[world.student.id, sister.id, world.student.id],
        notes="Tuesdays",
    )
    assert (group.name, group.notes, group.is_active) == (
        "Evening circle",
        "Tuesdays",
        True,
    )
    assert members(group) == sorted([world.student.id, sister.id])


def test_a_student_in_another_group_is_refused_by_name(world):
    services.create_group(name="Morning", student_ids=[world.student.id])
    with pytest.raises(ValidationError) as exc:
        services.create_group(
            name="Evening", student_ids=[make_student("Aisha").id, world.student.id]
        )
    assert exc.value.field == "student_ids"
    assert "Yusuf" in exc.value.message
    assert not StudyGroup.objects.filter(name="Evening").exists()


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({"name": "   "}, "name"),
        ({"name": "x" * 121}, "name"),
        ({"student_ids": []}, "student_ids"),
        ({"student_ids": "teacher"}, "student_ids"),
    ],
)
def test_a_name_and_students_are_required(world, fields, field):
    values = {"name": "Evening", "student_ids": [world.student.id], **fields}
    if values["student_ids"] == "teacher":
        values["student_ids"] = [make_teacher("Hamza").id]
    with pytest.raises(ValidationError) as exc:
        services.create_group(**values)
    assert exc.value.field == field


def test_a_new_member_must_be_active_but_an_inactive_one_may_stay(world):
    sister = make_student("Aisha")
    group = services.create_group(
        name="Evening", student_ids=[world.student.id, sister.id]
    )
    deactivated(sister)
    services.update_group(
        group, fields={"name": "Late", "student_ids": [world.student.id, sister.id]}
    )
    group.refresh_from_db()
    assert (group.name, members(group)) == (
        "Late",
        sorted([world.student.id, sister.id]),
    )
    cousin = deactivated(make_student("Zaid"))
    with pytest.raises(ValidationError) as exc:
        services.update_group(group, fields={"student_ids": [cousin.id]})
    assert exc.value.field == "student_ids"
    assert "Zaid" in exc.value.message


def test_update_replaces_the_members_and_the_rest(world):
    sister = make_student("Aisha")
    group = services.create_group(
        name="Evening", student_ids=[world.student.id, sister.id]
    )
    services.update_group(
        group,
        fields={"student_ids": [sister.id], "notes": "Moved", "is_active": False},
    )
    group.refresh_from_db()
    assert (members(group), group.notes, group.is_active) == (
        [sister.id],
        "Moved",
        False,
    )
    # The student who left may join another group now.
    services.create_group(name="Morning", student_ids=[world.student.id])


def test_a_group_in_use_is_not_deleted(world):
    group = services.create_group(name="Evening", student_ids=[world.student.id])
    bundle = SubscriptionBundle.objects.create(kind="group", study_group=group)
    with pytest.raises(ConflictError) as exc:
        services.delete_group(group)
    assert exc.value.code == "scheduling.group_in_use"
    bundle.delete()
    services.delete_group(group)
    assert not StudyGroup.objects.exists()


def test_the_queryset_reads_members_and_use(world):
    group = services.create_group(name="Evening", student_ids=[world.student.id])
    SubscriptionBundle.objects.create(kind="group", study_group=group)
    services.create_group(name="Morning", student_ids=[make_student("Aisha").id])
    rows = list(services.filter_groups(services.groups_queryset(), q="even"))
    assert [(g.name, g.in_use) for g in rows] == [("Evening", True)]
    assert [m.student.user.full_name for m in rows[0].members.all()] == ["Yusuf"]
    services.update_group(group, fields={"is_active": False})
    found = services.filter_groups(services.groups_queryset(), is_active="false")
    assert [g.name for g in found] == ["Evening"]


def test_candidates_are_active_students_in_no_other_group(world):
    sister = make_student("Aisha")
    cousin = make_student("Ahmad")
    deactivated(make_student("Amal"))
    group = services.create_group(name="Evening", student_ids=[world.student.id])
    services.create_group(name="Morning", student_ids=[cousin.id])
    assert [u.full_name for u in services.group_candidates(q="a")] == ["Aisha"]
    # Editing a group lists its own students too.
    found = services.group_candidates(group=group)
    assert [u.pk for u in found] == [sister.id, world.student.id]
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_groups_services.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'create_group'`.

- [ ] **Step 4: Implement** (`backend/etqan/scheduling/services/groups.py`)

```python
"""Slice B2f §4.1: study groups — named sets of students taught together, each
student in at most one group (F-1, BR-17). Inactive students may stay members;
a student joining must be active. A bundle using a group keeps it."""

from collections.abc import Iterable

from django.db import IntegrityError
from django.db import transaction
from django.db.models import Exists
from django.db.models import OuterRef
from django.db.models import Prefetch
from django.db.models import QuerySet

from etqan.identity import services as identity_services
from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.models import StudyGroup
from etqan.scheduling.models import StudyGroupMember
from etqan.scheduling.models import SubscriptionBundle

NAME_MAX = 120
MAX_CANDIDATES = 20
IN_USE = "This study group has subscription bundles. Dissolve them first."


def _name(value: str | None) -> str:
    name = (value or "").strip()
    if not name:
        raise ValidationError("Enter a name.", field="name")
    if len(name) > NAME_MAX:
        raise ValidationError("Keep the name to 120 characters.", field="name")
    return name


def _profiles(student_ids: Iterable[int], *, group: StudyGroup | None) -> list:
    """The students ``student_ids`` (User ids) name, once each, in order. Each
    is a student; one joining ``group`` must be active and in no other group
    (400 on ``student_ids`` naming them, BR-17)."""
    wanted = list(dict.fromkeys(student_ids))
    if not wanted:
        raise ValidationError("Choose at least one student.", field="student_ids")
    kept = (
        set()
        if group is None
        else set(group.members.values_list("student__user_id", flat=True))
    )
    profiles = []
    for user_id in wanted:
        profile = identity_services.get_student_profile(user_id)
        if profile is None or profile.user.role != "student":
            raise ValidationError("Choose students from the list.", field="student_ids")
        if user_id not in kept and not profile.user.is_active:
            raise ValidationError(
                f"{profile.user.full_name} is not active.", field="student_ids"
            )
        profiles.append(profile)
    elsewhere = StudyGroupMember.objects.filter(student__in=profiles)
    if group is not None:
        elsewhere = elsewhere.exclude(group=group)
    names = sorted(elsewhere.values_list("student__user__full_name", flat=True))
    if names:
        raise ValidationError(
            f"Already in another study group: {', '.join(names)}.",
            field="student_ids",
        )
    return profiles


def _set_members(group: StudyGroup, profiles: list) -> None:
    """``group``'s members become exactly ``profiles``."""
    wanted = {profile.pk for profile in profiles}
    group.members.exclude(student_id__in=wanted).delete()
    have = set(group.members.values_list("student_id", flat=True))
    joining = [
        StudyGroupMember(group=group, student=profile)
        for profile in profiles
        if profile.pk not in have
    ]
    try:
        with transaction.atomic():
            StudyGroupMember.objects.bulk_create(joining)
    except IntegrityError:
        # Plan D23: another save put one of them in a group first.
        raise ValidationError(
            "A student was just added to another study group.", field="student_ids"
        ) from None


@transaction.atomic
def create_group(
    *, name: str, student_ids: Iterable[int], notes: str = "", is_active: bool = True
) -> StudyGroup:
    clean = _name(name)
    profiles = _profiles(student_ids, group=None)
    group = StudyGroup.objects.create(
        name=clean, notes=notes or "", is_active=is_active
    )
    _set_members(group, profiles)
    return group


@transaction.atomic
def update_group(group: StudyGroup, *, fields: dict) -> StudyGroup:
    """§4.1: name, notes, active, and the students as a full list."""
    locked = StudyGroup.objects.select_for_update().get(pk=group.pk)
    if "name" in fields:
        locked.name = _name(fields["name"])
    if "notes" in fields:
        locked.notes = fields["notes"] or ""
    if "is_active" in fields:
        locked.is_active = fields["is_active"]
    locked.save()
    if "student_ids" in fields:
        _set_members(locked, _profiles(fields["student_ids"], group=locked))
    return locked


@transaction.atomic
def delete_group(group: StudyGroup) -> None:
    locked = StudyGroup.objects.select_for_update().get(pk=group.pk)
    if SubscriptionBundle.objects.filter(study_group=locked).exists():
        raise ConflictError(IN_USE, code="scheduling.group_in_use")
    locked.delete()


def groups_queryset() -> QuerySet[StudyGroup]:
    """Groups by name, each with ``in_use`` (a bundle uses it) and its members
    by name: two queries for a whole page."""
    members = StudyGroupMember.objects.select_related("student__user").order_by(
        "student__user__full_name", "id"
    )
    used = SubscriptionBundle.objects.filter(study_group=OuterRef("pk"))
    return (
        StudyGroup.objects.annotate(in_use=Exists(used))
        .prefetch_related(Prefetch("members", queryset=members))
        .order_by("name", "id")
    )


def filter_groups(
    groups: QuerySet[StudyGroup], *, q: str = "", is_active: str = ""
) -> QuerySet[StudyGroup]:
    if q := q.strip():
        groups = groups.filter(name__icontains=q)
    if is_active in ("true", "false"):
        groups = groups.filter(is_active=is_active == "true")
    return groups


def group_candidates(*, q: str = "", group: StudyGroup | None = None) -> list:
    """Plan D13: up to 20 active students who may join ``group`` (or a new
    group) — in no other group — by name."""
    taken = StudyGroupMember.objects.all()
    if group is not None:
        taken = taken.exclude(group=group)
    students = identity_services.people_queryset("student").filter(is_active=True)
    if q := q.strip():
        students = students.filter(full_name__icontains=q)
    return list(
        students.exclude(student_profile__in=taken.values("student"))[
            :MAX_CANDIDATES
        ]
    )
```

`backend/etqan/scheduling/services/__init__.py` — import and add to `__all__` (alphabetical): `MAX_CANDIDATES`, `create_group`, `delete_group`, `filter_groups`, `group_candidates`, `groups_queryset`, `update_group` from `etqan.scheduling.services.groups`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_groups_services.py`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/groups.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_groups_services.py
git -C $W/backend commit -m "feat(scheduling): study groups, one per student (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 4: Members — created in a bundle, renewed into it with their course, the bundle gone with its last member

**Files:**
- Modify: `backend/etqan/scheduling/services/subscriptions.py` (`create_subscription(bundle=)`, `copied_slots`, `renew_subscription`, `delete_subscription`)
- Modify: `backend/etqan/scheduling/services/__init__.py` (`copied_slots`)
- Modify: `backend/etqan/scheduling/tests/conftest.py` (`other_course`, `bare_bundle`)
- Test: `backend/etqan/scheduling/tests/test_bundles_members.py`

**Interfaces:**
- Consumes: `SubscriptionBundle` (Task 2).
- Produces: `create_subscription(..., bundle: SubscriptionBundle | None = None)` (keyword, additive); `copied_slots(subscription) -> list[dict]` (a create body's `slots`, as renewal copies them); `renew_subscription` keeps `bundle` and refuses a different `course_id` for a member (400 on `course`, plan D7); `delete_subscription` locks the bundle first and deletes it with its last member (plan D3). Conftest: `other_course(world, name="Fiqh") -> Course` (taught by `world.teacher`), `bare_bundle(world, kind="multi_course", **owner) -> SubscriptionBundle` (straight to the table; a multi-course one owned by `world.student` by default).

- [ ] **Step 1: The conftest helpers** (`backend/etqan/scheduling/tests/conftest.py`; import `SubscriptionBundle` from `etqan.scheduling.models`)

```python
# Slice B2f: helpers the bundle tests share.
def other_course(world, name="Fiqh"):
    """A second course, taught by ``world``'s teacher."""
    return catalogue_services.create_course(
        name_ar=f"{name} ع", name_en=name, teacher_ids=[world.teacher.id]
    )


def bare_bundle(world, kind="multi_course", **owner):
    """A bundle row written straight to the table, for tests whose subject is
    not `create_bundle`: multi-course for ``world``'s student by default."""
    if not owner:
        owner = {"student": world.student.student_profile}
    return SubscriptionBundle.objects.create(kind=kind, **owner)
```

- [ ] **Step 2: Write the failing tests** (`backend/etqan/scheduling/tests/test_bundles_members.py`)

```python
"""Slice B2f F-3, F-6, F-9: a member is an ordinary subscription with its
bundle set; any renewal keeps the bundle and the course; the bundle goes with
its last member, locked first."""

from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import bare_bundle
from etqan.scheduling.tests.conftest import course_teacher
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import other_course
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
NEVER_INVOICED = lambda _pk: None  # noqa: E731 -- the API passes billing's check


def first_table(sql: str) -> str:
    return sql.split(" FROM ", 1)[1].split(maxsplit=1)[0]


def test_a_subscription_joins_the_bundle_it_is_created_in(world):
    bundle = bare_bundle(world)
    assert subscription_for(world, bundle=bundle).bundle_id == bundle.pk
    assert subscription_for(world).bundle_id is None


def test_a_renewal_stays_in_the_bundle_by_the_service(world):
    bundle = bare_bundle(world)
    sub = subscription_for(world, bundle=bundle, slots=two_slots())
    other = course_teacher(world)
    renewal = services.renew_subscription(sub, teacher_id=other.id)
    assert (renewal.bundle_id, renewal.teacher.user_id) == (bundle.pk, other.id)
    assert renewal.slots.count() == 2


def test_a_renewal_stays_in_the_bundle_by_the_api(world):
    bundle = bare_bundle(world)
    sub = subscription_for(world, bundle=bundle)
    office = as_user(make_admin())
    response = office.post(f"/api/v1/subscriptions/{sub.pk}/renew/", {}, format="json")
    assert response.status_code == 201
    assert Subscription.objects.get(pk=response.json()["id"]).bundle_id == bundle.pk


def test_a_members_renewal_keeps_its_course(world):
    sub = subscription_for(world, bundle=bare_bundle(world))
    fiqh = other_course(world)
    with pytest.raises(ValidationError) as exc:
        services.renew_subscription(sub, course_id=fiqh.pk)
    assert exc.value.field == "course"
    # Naming its own course is no change.
    renewal = services.renew_subscription(sub, course_id=world.course.pk)
    assert renewal.course_id == world.course.pk


def test_a_plain_subscription_may_still_change_course(world):
    fiqh = other_course(world)
    renewal = services.renew_subscription(subscription_for(world), course_id=fiqh.pk)
    assert renewal.course_id == fiqh.pk


def test_copied_slots_follow_the_package_length_unless_their_own(world):
    sub = subscription_for(world, slots=two_slots())
    services.update_slot(sub.slots.first(), minutes=60)
    copied = sorted(services.copied_slots(sub), key=lambda s: s["weekdays"])
    assert [(s["weekdays"], s["minutes"]) for s in copied] == [([0], 60), ([2], None)]


def test_deleting_the_last_member_deletes_the_bundle(world):
    bundle = bare_bundle(world)
    first = subscription_for(world, bundle=bundle)
    second = subscription_for(
        world, bundle=bundle, course_id=other_course(world).pk
    )
    services.delete_subscription(first, before_delete=NEVER_INVOICED)
    # Below its creation minimum, it stays (F-9).
    assert SubscriptionBundle.objects.filter(pk=bundle.pk).exists()
    services.delete_subscription(second, before_delete=NEVER_INVOICED)
    assert not SubscriptionBundle.objects.filter(pk=bundle.pk).exists()
    # A plain subscription's delete touches no bundle.
    services.delete_subscription(
        subscription_for(world, starts_on=date(2026, 6, 8)),
        before_delete=NEVER_INVOICED,
    )


def test_a_members_delete_locks_the_bundle_first(world):
    sub = subscription_for(world, bundle=bare_bundle(world))
    with CaptureQueriesContext(connection) as ctx:
        services.delete_subscription(sub, before_delete=NEVER_INVOICED)
    locks = [
        q["sql"]
        for q in ctx.captured_queries
        if "FOR UPDATE" in q["sql"] or "FOR NO KEY UPDATE" in q["sql"]
    ]
    assert "FOR NO KEY UPDATE" in locks[0]
    assert first_table(locks[0]) == '"scheduling_subscriptionbundle"'
    assert first_table(locks[1]) == '"scheduling_subscription"'
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_members.py`
Expected: FAIL — `TypeError: create_subscription() got an unexpected keyword argument 'bundle'`.

- [ ] **Step 4: Implement** (`backend/etqan/scheduling/services/subscriptions.py`; import `SubscriptionBundle` from `etqan.scheduling.models`)

`create_subscription` gains the keyword after `trial`, and sets it on the new row:

```python
    trial: TrialRequest | None = None,
    bundle: SubscriptionBundle | None = None,
) -> Subscription:
    """Spec §4.2 Create: copy the package, add the slots, generate the horizon.
    Its sessions take ``supervisor_id``'s supervisor (Plan 12b §3.5). Slice
    B2e §4.4: with ``trial``, the request and its current session are locked
    and checked first, and the new subscription is linked to it. Slice B2f
    F-3: with ``bundle``, it is that bundle's member."""
    ...
    subscription = Subscription(
        student=_student(student_id),
        course=course,
        teacher=_teacher(teacher_id, course),
        starts_on=starts_on,
        notes=notes,
        renewed_from=renewed_from,
        supervisor=supervision.supervisor_for(supervisor_id),
        bundle=bundle,
    )
```

Add after `_add_slots` (in the Slots section):

```python
def copied_slots(subscription: Subscription) -> list[dict]:
    """``subscription``'s active slots as a create body's ``slots``: renewal
    copies them, and so does a group bundle's new student (slice B2f §4.3). A
    slot on the package length follows the new package."""
    return [
        {
            "weekdays": [slot.weekday],
            "start_time": slot.start_time,
            "minutes": None
            if slot.minutes == subscription.session_minutes
            else slot.minutes,
            "meeting_url": slot.meeting_url,
        }
        for slot in subscription.slots.filter(is_active=True)
    ]
```

In `renew_subscription`, after the `starts_on <= old.starts_on` check:

```python
    if (
        old.bundle_id is not None
        and course_id is not None
        and course_id != old.course_id
    ):
        # Slice B2f F-6 (plan D7): a member keeps its course, so a multi-course
        # bundle's courses stay distinct and a group stays one class.
        raise ValidationError(
            "A bundle member's renewal keeps its course.", field="course"
        )
```

replace the inline `slots = [ … ]` comprehension with `slots = copied_slots(old)`, and pass the bundle on:

```python
    renewal = create_subscription(
        student_id=old.student.user_id,
        course_id=course_id or old.course_id,
        teacher_id=teacher_id or old.teacher.user_id,
        package_id=package.pk,
        starts_on=starts_on,
        price_minor=price_minor,
        slots=slots,
        renewed_from=old,
        supervisor_id=supervisor.pk if supervisor else None,
        # Slice B2f F-6: a renewal stays in the bundle, whatever the route.
        bundle=old.bundle,
    )
```

`delete_subscription` — extend the docstring with "Slice B2f F-9 (plan D3): a member's bundle is locked first — §4's order, bundle then members — and goes with its last member." and wrap the body:

```python
    bundle_id = subscription.bundle_id
    if bundle_id is not None:
        # Plan D2: the bundle actions' own lock, so a member's delete and a
        # bundle action never wait on each other in opposite orders.
        SubscriptionBundle.objects.select_for_update(no_key=True).filter(
            pk=bundle_id
        ).first()
    locked = Subscription.objects.select_for_update().get(pk=subscription.pk)
    ...  # unchanged down to `locked.delete()`
    locked.delete()
    if (
        bundle_id is not None
        and not Subscription.objects.filter(bundle_id=bundle_id).exists()
    ):
        SubscriptionBundle.objects.filter(pk=bundle_id).delete()
```

`backend/etqan/scheduling/services/__init__.py` — export `copied_slots` from `subscriptions`.

- [ ] **Step 5: Run the tests to see them pass, and the renewal suites unchanged**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_members.py etqan/scheduling/tests/test_renewal.py etqan/scheduling/tests/test_subscriptions.py etqan/scheduling/tests/test_api_subscriptions.py`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/subscriptions.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_bundles_members.py
git -C $W/backend commit -m "feat(scheduling): bundle members — renewals keep bundle and course, the last delete takes the bundle (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 5: A group class never clashes with itself (F-4)

**Files:**
- Modify: `backend/etqan/scheduling/services/rules.py` (`GROUP_BUNDLE_ID`, `group_siblings`, `group_bundle_of`)
- Modify: `backend/etqan/scheduling/services/generation.py` (`conflicts`)
- Modify: `backend/etqan/scheduling/services/postpone.py` (`_teacher_busy`)
- Test: `backend/etqan/scheduling/tests/test_bundles_clashes.py`

**Interfaces:**
- Consumes: `bare_bundle`, `other_course` (Task 4); `Subscription.bundle` (Task 2).
- Produces: `rules.GROUP_BUNDLE_ID` (a `Case` on `Session`: the subscription's bundle id when that bundle is a `group`, else NULL); `rules.group_siblings(one, other, groups: dict[int, int | None]) -> bool`; `rules.group_bundle_of(session) -> int | None` (one query). `generation.conflicts(created)` keeps its signature and leaves out group siblings (plan D17); `_teacher_busy` leaves them out too. Nothing reads a switch: the exemption stays while `group_subscriptions` is off (F-4).

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_bundles_clashes.py`)

```python
"""Slice B2f F-4, §4.4: rows of one group class — one group bundle, the same
start and minutes — never clash; every other overlap still does (P4-9, B2b's
teacher_busy)."""

from datetime import date
from datetime import time
from datetime import timedelta

import pytest

from etqan.platform.exceptions import ConflictError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import StudyGroup
from etqan.scheduling.services import generation
from etqan.scheduling.tests.conftest import MONDAY
from etqan.scheduling.tests.conftest import bare_bundle
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
MONDAYS = [{"weekdays": [MONDAY], "start_time": time(18, 0)}]


def a_group(world, name="Evening"):
    study_group = StudyGroup.objects.create(name=name)
    return bare_bundle(world, "group", study_group=study_group)


def pair(world, bundle, slots=None):
    """Two members of ``bundle`` — ``world``'s student and a new one — on the
    same slots."""
    slots = slots or two_slots()
    first = subscription_for(world, bundle=bundle, slots=slots)
    second = subscription_for(
        world, student_id=make_student("Aisha").id, bundle=bundle, slots=slots
    )
    return first, second


def clashes(sub):
    return generation.conflicts(list(Session.objects.filter(subscription=sub)))


def test_rows_of_one_group_class_never_clash(world):
    _, second = pair(world, a_group(world))
    assert clashes(second) == []


@pytest.mark.parametrize("change", ["start", "minutes"])
def test_a_different_start_or_length_inside_the_group_still_clashes(world, change):
    _, second = pair(world, a_group(world))
    moved = Session.objects.filter(subscription=second).order_by("pk").first()
    if change == "start":
        moved.starts_at += timedelta(minutes=15)
    else:
        moved.minutes = 30
    moved.save()
    assert [pair_[0].pk for pair_ in clashes(second)] == [moved.pk]


def test_the_same_time_in_another_group_still_clashes(world):
    subscription_for(world, bundle=a_group(world), slots=two_slots())
    other = subscription_for(
        world,
        student_id=make_student("Aisha").id,
        bundle=a_group(world, "Morning"),
        slots=two_slots(),
    )
    assert clashes(other)


def test_a_multi_course_bundles_rows_at_one_time_clash(world):
    _, second = pair(world, bare_bundle(world))
    assert clashes(second)


def test_a_lesson_at_the_same_time_outside_the_group_still_clashes(world):
    pair(world, a_group(world))
    plain = subscription_for(
        world, student_id=make_student("Zaid").id, slots=two_slots()
    )
    # Each plain session overlaps both rows of the group class.
    assert len(clashes(plain)) == 2 * Session.objects.filter(subscription=plain).count()


@pytest.fixture
def postponing(set_features):
    set_features(postponement=True)


def test_a_student_may_postpone_onto_their_own_group_class(world, postponing):
    first, second = pair(world, a_group(world), slots=MONDAYS)
    hand_session(second, occurs_on=date(2026, 6, 10), start=time(18, 0))
    session = Session.objects.get(subscription=first, occurs_on=date(2026, 6, 8))
    moved = services.postpone_session(
        session, by=world.student, occurs_on=date(2026, 6, 10), start_time=time(18, 0)
    ).session
    assert moved.occurs_on == date(2026, 6, 10)


def test_postponing_onto_a_plain_lesson_at_the_same_time_is_still_busy(
    world, postponing
):
    first, _ = pair(world, a_group(world), slots=MONDAYS)
    plain = subscription_for(world, student_id=make_student("Zaid").id)
    hand_session(plain, occurs_on=date(2026, 6, 10), start=time(18, 0))
    session = Session.objects.get(subscription=first, occurs_on=date(2026, 6, 8))
    with pytest.raises(ConflictError) as exc:
        services.postpone_session(
            session,
            by=world.student,
            occurs_on=date(2026, 6, 10),
            start_time=time(18, 0),
        )
    assert exc.value.code == "scheduling.teacher_busy"
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_clashes.py`
Expected: FAIL — `test_rows_of_one_group_class_never_clash` lists the siblings; `test_a_student_may_postpone_onto_their_own_group_class` raises `scheduling.teacher_busy`. The other six cases pass already (the parametrised start/length test counts twice; they pin today's behaviour).

- [ ] **Step 3: Implement**

`backend/etqan/scheduling/services/rules.py` — import `BigIntegerField` from `django.db.models` and `SubscriptionBundle` from `etqan.scheduling.models`; add after `ENDS_AT`:

```python
# Slice B2f F-4: a session's group bundle — its subscription's bundle when
# that bundle is a `group` one, else NULL — in SQL.
GROUP_BUNDLE_ID = Case(
    When(
        subscription__bundle__kind=SubscriptionBundle.Kind.GROUP,
        then=F("subscription__bundle_id"),
    ),
    output_field=BigIntegerField(),
)


def group_siblings(one: Session, other: Session, groups: dict) -> bool:
    """F-4: two rows of one group class — one group bundle (``groups`` maps a
    session id to `GROUP_BUNDLE_ID`), the same start and the same minutes —
    are not a clash."""
    group = groups.get(one.pk)
    return (
        group is not None
        and group == groups.get(other.pk)
        and one.starts_at == other.starts_at
        and one.minutes == other.minutes
    )


def group_bundle_of(session: Session) -> int | None:
    """The group bundle ``session`` belongs to, or None (one query)."""
    if session.subscription_id is None:
        return None
    return (
        Subscription.objects.filter(
            pk=session.subscription_id, bundle__kind=SubscriptionBundle.Kind.GROUP
        )
        .values_list("bundle_id", flat=True)
        .first()
    )
```

`backend/etqan/scheduling/services/generation.py` — `conflicts` evaluates the others once, with their group, and skips siblings:

```python
def conflicts(created: list[Session]) -> list[tuple[Session, Session]]:
    """Each created session that overlaps another non-cancelled session of the
    same teacher (P4-9: reported, never blocked). Each pair is listed once.
    Slice B2a: also used for one session added by hand. Slice B2f F-4: rows of
    one group class are not a clash (plan D17: the created sessions are among
    the others, so their group costs no extra query)."""
    if not created:
        return []
    others = list(
        rules.sessions_queryset()
        .exclude(status=Session.Status.CANCELLED)
        .filter(
            teacher_id__in={s.teacher_id for s in created},
            starts_at__gte=min(s.starts_at for s in created) - MAX_SESSION,
            starts_at__lt=max(ends_at(s) for s in created),
        )
        .annotate(group_bundle_id=rules.GROUP_BUNDLE_ID)
    )
    groups = {other.pk: other.group_bundle_id for other in others}
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
            if rules.group_siblings(session, other, groups):
                continue
            if other.starts_at < ends_at(session) and session.starts_at < ends_at(
                other
            ):
                pairs.append((session, other))
    return pairs
```

`backend/etqan/scheduling/services/postpone.py` — import `Coalesce` from `django.db.models.functions` and `Value` from `django.db.models`:

```python
def _teacher_busy(locked: Session, start) -> bool:
    end = start + timedelta(minutes=locked.minutes)
    busy = (
        Session.objects.annotate(ends_at=rules.ENDS_AT)
        .filter(teacher_id=locked.teacher_id, starts_at__lt=end, ends_at__gt=start)
        .exclude(pk=locked.pk)
        .exclude(status=Session.Status.CANCELLED)
    )
    group = rules.group_bundle_of(locked)
    if group is not None:
        # Slice B2f F-4: the same group class's other rows at this very time.
        # Coalesce (plan D17): a NULL group must never drop a plain session.
        busy = busy.alias(
            group_key=Coalesce(rules.GROUP_BUNDLE_ID, Value(0))
        ).exclude(group_key=group, starts_at=start, minutes=locked.minutes)
    return busy.exists()
```

- [ ] **Step 4: Run them to see them pass, and the clash and postponement suites unchanged**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_clashes.py etqan/scheduling/tests/test_generation.py etqan/scheduling/tests/test_times_postponement_postpone.py etqan/scheduling/tests/test_session_classes_manual.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/rules.py etqan/scheduling/services/generation.py etqan/scheduling/services/postpone.py etqan/scheduling/tests/test_bundles_clashes.py
git -C $W/backend commit -m "feat(scheduling): a group class's rows never clash with each other (B2f F-4)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 6: Creating a bundle of each kind

**Files:**
- Create: `backend/etqan/scheduling/services/bundles.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Modify: `backend/etqan/scheduling/tests/conftest.py` (`row`, `make_group`, `make_family`, `group_bundle`, `multi_bundle`, `member_of`, `bundles_on`)
- Test: `backend/etqan/scheduling/tests/test_bundles_create.py`

**Interfaces:**
- Consumes: `create_subscription(..., bundle=)` (Task 4), `subs.active_student`, `identity_services.get_family` (raises `NotFoundError`), `generation.conflicts` with F-4 (Task 5), `StudyGroup` (Task 2).
- Produces (exported): `create_bundle(kind, by, *, starts_on, rows, student_id=None, family_id=None, group_id=None, supervisor_id=None, notes="") -> CreatedBundle`; `CreatedBundle(bundle, members: list[Subscription], conflicts: list[tuple[Session, Session]])`; `BUNDLE_KINDS = ("multi_course", "family", "group")`. `rows` are dicts with the subscription body's keys `course`, `teacher`, `package`, optional `price_minor`, `slots`, and (family) `student` — User / course / package ids. Errors: owner → 400 on `student_id` / `family_id` / `group_id`; row counts → 400 on `rows`; a row's → 400 on `rows.<i>.<field>` (plan D1); `starts_on`, `supervisor_id` stay top-level. One transaction.
- Conftest: `row(world, course=None, **overrides) -> dict`; `make_group(*students, name="Evening circle") -> StudyGroup`; `make_family(*students, name="Omar family") -> Family`; `group_bundle(world, *others, slots=None) -> CreatedBundle` (a group of `world.student` and `others`, slots `two_slots()` from 1 June); `multi_bundle(world) -> CreatedBundle` (Tajweed + Fiqh for `world.student`, `two_slots()` on the first row); `member_of(created, user) -> Subscription`; fixture `bundles_on` (the four switches on).

- [ ] **Step 1: The conftest helpers** (`backend/etqan/scheduling/tests/conftest.py`)

```python
def row(world, course=None, **overrides) -> dict:
    """One bundle row for ``world``: its course (or ``course``), teacher and
    package, as the create body sends them."""
    return {
        "course": (course or world.course).pk,
        "teacher": world.teacher.id,
        "package": world.package.pk,
        **overrides,
    }


def make_group(*students, name="Evening circle"):
    return services.create_group(name=name, student_ids=[s.id for s in students])


def make_family(*students, name="Omar family"):
    """A family of ``students``, the first one paying."""
    return identity_services.create_family(
        name=name, student_ids=[s.id for s in students], payer_id=students[0].id
    )


def group_bundle(world, *others, slots=None):
    """A group bundle from 1 June for a study group of ``world``'s student
    and ``others``, on ``slots`` (Monday and Wednesday 18:00 by default)."""
    group = make_group(world.student, *others)
    return services.create_bundle(
        "group",
        None,
        starts_on=date(2026, 6, 1),
        group_id=group.pk,
        rows=[row(world, slots=slots or two_slots())],
    )


def multi_bundle(world):
    """Tajweed (Monday and Wednesday 18:00) and Fiqh (no slots) for
    ``world``'s student, from 1 June."""
    return services.create_bundle(
        "multi_course",
        None,
        starts_on=date(2026, 6, 1),
        student_id=world.student.id,
        rows=[row(world, slots=two_slots()), row(world, other_course(world))],
    )


def member_of(created, user):
    """``user``'s member in a `CreatedBundle`."""
    return next(m for m in created.members if m.student.user_id == user.id)


@pytest.fixture
def bundles_on(set_features):
    """Slice B2f: the four switches on (they are off by default)."""
    set_features(
        study_groups=True,
        multi_course_subscriptions=True,
        family_subscriptions=True,
        group_subscriptions=True,
    )
```

- [ ] **Step 2: Write the failing tests** (`backend/etqan/scheduling/tests/test_bundles_create.py`)

```python
"""Slice B2f §4.2: creating a bundle of each kind — its rules, an error on the
row that caused it (plan D1), all or nothing, and the clashes it answers."""

from collections import defaultdict
from datetime import date
from datetime import time

import pytest

from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.tests.conftest import deactivated
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_family
from etqan.scheduling.tests.conftest import make_group
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import other_course
from etqan.scheduling.tests.conftest import row
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
JUNE_1 = date(2026, 6, 1)


def create(kind, rows, **owner):
    return services.create_bundle(kind, None, starts_on=JUNE_1, rows=rows, **owner)


def nothing_kept():
    return not (
        SubscriptionBundle.objects.exists()
        or Subscription.objects.exists()
        or Session.objects.exists()
    )


# ── Multi-course ─────────────────────────────────────────────────────────────


def test_a_multi_course_bundle_is_one_subscription_per_course(world):
    admin = make_admin()
    fiqh = other_course(world)
    created = services.create_bundle(
        "multi_course",
        admin,
        starts_on=JUNE_1,
        student_id=world.student.id,
        rows=[row(world, slots=two_slots()), row(world, fiqh, price_minor=90000)],
        notes="Two subjects",
    )
    bundle = created.bundle
    assert (bundle.kind, bundle.student.user_id, bundle.notes, bundle.created_by_id) == (
        "multi_course",
        world.student.id,
        "Two subjects",
        admin.pk,
    )
    members = list(Subscription.objects.filter(bundle=bundle).order_by("pk"))
    assert [m.pk for m in created.members] == [m.pk for m in members]
    assert [(m.course_id, m.price_minor) for m in members] == [
        (world.course.pk, 150000),
        (fiqh.pk, 90000),
    ]
    assert {m.student.user_id for m in members} == {world.student.id}
    assert Session.objects.filter(subscription=members[0]).exists()


@pytest.mark.parametrize(("count", "field"), [(1, "rows"), (2, "rows.1.course")])
def test_a_multi_course_bundle_needs_two_distinct_courses(world, count, field):
    with pytest.raises(ValidationError) as exc:
        create("multi_course", [row(world)] * count, student_id=world.student.id)
    assert exc.value.field == field
    assert nothing_kept()


def test_a_multi_course_bundle_is_for_an_active_student(world):
    rows = [row(world), row(world, other_course(world))]
    with pytest.raises(ValidationError) as exc:
        create("multi_course", rows, student_id=make_teacher("Hamza").id)
    assert exc.value.field == "student_id"


def test_a_rows_refusal_is_keyed_to_that_row_and_nothing_is_kept(world):
    rows = [
        row(world, slots=two_slots()),
        row(world, other_course(world), package=999999),
    ]
    with pytest.raises(ValidationError) as exc:
        create("multi_course", rows, student_id=world.student.id)
    assert (exc.value.field, exc.value.message) == (
        "rows.1.package",
        "Choose an active package.",
    )
    assert nothing_kept()


def test_a_slot_error_names_its_row(world):
    rows = [
        row(world, slots=[{"weekdays": [], "start_time": time(18, 0)}]),
        row(world, other_course(world)),
    ]
    with pytest.raises(ValidationError) as exc:
        create("multi_course", rows, student_id=world.student.id)
    assert exc.value.field == "rows.0.slots"


def test_the_bundles_own_fields_stay_top_level(world):
    rows = [row(world), row(world, other_course(world))]
    with pytest.raises(ValidationError) as exc:
        create(
            "multi_course", rows, student_id=world.student.id, supervisor_id=999999
        )
    assert exc.value.field == "supervisor_id"


# ── Family ───────────────────────────────────────────────────────────────────


def test_a_family_bundle_covers_students_of_one_family(world):
    sister = make_student("Aisha")
    family = make_family(world.student, sister)
    fiqh = other_course(world)
    created = create(
        "family",
        [
            row(world, student=world.student.id),
            row(world, student=sister.id),
            row(world, fiqh, student=sister.id),
        ],
        family_id=family.pk,
    )
    assert created.bundle.family_id == family.pk
    assert sorted((m.student.user_id, m.course_id) for m in created.members) == sorted(
        [
            (world.student.id, world.course.pk),
            (sister.id, world.course.pk),
            (sister.id, fiqh.pk),
        ]
    )


@pytest.mark.parametrize(
    ("rows", "field"),
    [
        (lambda w, s, x: [row(w, student=w.student.id)], "rows"),
        (
            lambda w, s, x: [row(w, student=w.student.id), row(w, student=x.id)],
            "rows.1.student",
        ),
        (lambda w, s, x: [row(w, student=s.id), row(w)], "rows.1.student"),
        (
            lambda w, s, x: [row(w, student=s.id), row(w, student=s.id)],
            "rows.1.course",
        ),
    ],
)
def test_a_family_bundles_rows_are_its_students_once_per_course(world, rows, field):
    sister = make_student("Aisha")
    family = make_family(world.student, sister)
    stranger = make_student("Zaid")
    with pytest.raises(ValidationError) as exc:
        create("family", rows(world, sister, stranger), family_id=family.pk)
    assert exc.value.field == field
    assert nothing_kept()


@pytest.mark.parametrize("retired", [True, False])
def test_a_family_bundle_needs_an_active_family(world, retired):
    family = make_family(world.student, make_student("Aisha"))
    if retired:
        identity_services.update_family(family, fields={"is_active": False})
    rows = [row(world, student=world.student.id), row(world, student=world.student.id)]
    with pytest.raises(ValidationError) as exc:
        create("family", rows, family_id=family.pk if retired else 999999)
    assert exc.value.field == "family_id"


def test_an_inactive_family_student_is_refused_on_their_row(world):
    sister = make_student("Aisha")
    family = make_family(world.student, sister)
    deactivated(sister)
    rows = [row(world, student=world.student.id), row(world, student=sister.id)]
    with pytest.raises(ValidationError) as exc:
        create("family", rows, family_id=family.pk)
    assert exc.value.field == "rows.1.student"


# ── Group ────────────────────────────────────────────────────────────────────


def test_a_group_bundle_subscribes_every_active_member_to_one_class(world):
    sister, cousin = make_student("Aisha"), make_student("Zaid")
    group = make_group(world.student, sister, cousin)
    deactivated(cousin)
    created = create("group", [row(world, slots=two_slots())], group_id=group.pk)
    assert created.bundle.study_group_id == group.pk
    assert sorted(m.student.user_id for m in created.members) == sorted(
        [world.student.id, sister.id]
    )
    # Ledger D6: one row per student at each time of the class.
    by_time = defaultdict(set)
    for session in Session.objects.filter(subscription__bundle=created.bundle):
        by_time[session.starts_at].add(session.student_id)
    assert by_time
    assert all(len(students) == 2 for students in by_time.values())
    # F-4: the class is not a clash with itself.
    assert created.conflicts == []


@pytest.mark.parametrize("count", [0, 2])
def test_a_group_bundle_has_exactly_one_row(world, count):
    group = make_group(world.student)
    with pytest.raises(ValidationError) as exc:
        create("group", [row(world)] * count, group_id=group.pk)
    assert exc.value.field == "rows"


@pytest.mark.parametrize("why", ["inactive group", "no active student", "unknown"])
def test_a_group_bundle_needs_an_active_group_with_an_active_student(world, why):
    group = make_group(world.student)
    if why == "inactive group":
        services.update_group(group, fields={"is_active": False})
    if why == "no active student":
        deactivated(world.student)
    group_id = 999999 if why == "unknown" else group.pk
    with pytest.raises(ValidationError) as exc:
        create("group", [row(world)], group_id=group_id)
    assert exc.value.field == "group_id"
    assert not SubscriptionBundle.objects.exists()


# ── The answer ───────────────────────────────────────────────────────────────


def test_the_answer_lists_real_clashes(world):
    rows = [
        row(world, slots=two_slots()),
        row(world, other_course(world), slots=two_slots()),
    ]
    created = create("multi_course", rows, student_id=world.student.id)
    # Same teacher, same times, two courses: P4-9 reports it, never blocks.
    assert created.conflicts
    assert all(a.subscription_id != b.subscription_id for a, b in created.conflicts)
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_create.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'create_bundle'` (raised from the conftest helpers as well).

- [ ] **Step 4: Implement** (`backend/etqan/scheduling/services/bundles.py`)

```python
"""Slice B2f §4.2 and §4.6: subscription bundles — several subscriptions made,
renewed, paused, cancelled and archived as one (ledger D7). Each member is an
ordinary `Subscription` with its `bundle` set: nothing a member computes,
invoices or pays changes (F-3)."""

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date

from django.db import transaction

from etqan.identity import services as identity_services
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.models import Session
from etqan.scheduling.models import StudyGroup
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.services import generation
from etqan.scheduling.services import rules
from etqan.scheduling.services import subscriptions as subs

Kind = SubscriptionBundle.Kind
BUNDLE_KINDS = tuple(Kind.values)
# Plan D1: the bundle's own body fields; every other error is its row's.
TOP_LEVEL_FIELDS = frozenset({"starts_on", "supervisor_id"})


@dataclass(frozen=True)
class CreatedBundle:
    bundle: SubscriptionBundle
    members: list[Subscription]
    # §4.2 step 4: the members' new sessions' clashes, F-4 applied.
    conflicts: list[tuple[Session, Session]]


@dataclass(frozen=True)
class _Plan:
    """One subscription to create: its row's index, its student, the row."""

    index: int
    student_id: int
    row: dict


def _rekeyed(exc: ValidationError, index: int) -> ValidationError:
    """Plan D1: a row's error on ``rows.<index>.<field>``."""
    if exc.field in TOP_LEVEL_FIELDS:
        return exc
    field = f"rows.{index}.{exc.field}" if exc.field else f"rows.{index}"
    return ValidationError(exc.message, field=field, code=exc.code)


def _at_least_two(rows: list[dict]) -> None:
    if len(rows) < 2:
        raise ValidationError("Add at least two rows.", field="rows")


def _distinct(rows: list[dict], key) -> None:
    seen = set()
    for index, row in enumerate(rows):
        if key(row) in seen:
            raise ValidationError(
                "This course is already in the bundle for this student.",
                field=f"rows.{index}.course",
            )
        seen.add(key(row))


def _plan_multi_course(rows: list[dict], student_id: int | None):
    """F-2: one student, two or more distinct courses."""
    try:
        profile = subs.active_student(student_id)
    except ValidationError as exc:
        raise ValidationError(exc.message, field="student_id") from None
    _at_least_two(rows)
    _distinct(rows, lambda row: row["course"])
    plans = [_Plan(index, student_id, row) for index, row in enumerate(rows)]
    return {"student": profile}, plans


def _plan_family(rows: list[dict], family_id: int | None):
    """F-2, F-8: students of one active family, two or more rows, student and
    course distinct. Whether each is active is `create_subscription`'s."""
    try:
        family = identity_services.get_family(family_id)
    except NotFoundError:
        raise ValidationError("Choose a family.", field="family_id") from None
    if not family.is_active:
        raise ValidationError("Choose an active family.", field="family_id")
    _at_least_two(rows)
    theirs = {student.user_id for student in family.students.all()}
    for index, row in enumerate(rows):
        if row.get("student") not in theirs:
            raise ValidationError(
                "Choose a student of this family.", field=f"rows.{index}.student"
            )
    _distinct(rows, lambda row: (row["student"], row["course"]))
    plans = [_Plan(index, row["student"], row) for index, row in enumerate(rows)]
    return {"family": family}, plans


def _plan_group(rows: list[dict], group_id: int | None):
    """F-2, plan D9: one active study group, one row, one subscription per
    active member. The group is locked so it is not changed or deleted
    meanwhile (§4 lock order)."""
    group = (
        StudyGroup.objects.select_for_update(no_key=True).filter(pk=group_id).first()
    )
    if group is None or not group.is_active:
        raise ValidationError("Choose an active study group.", field="group_id")
    if len(rows) != 1:
        raise ValidationError("A group bundle has exactly one row.", field="rows")
    students = list(
        group.members.filter(student__user__is_active=True)
        .order_by("student__user__full_name", "pk")
        .values_list("student__user_id", flat=True)
    )
    if not students:
        raise ValidationError("This study group has no active student.", field="group_id")
    return {"study_group": group}, [_Plan(0, student, rows[0]) for student in students]


def _member(
    bundle: SubscriptionBundle, plan: _Plan, *, starts_on: date, supervisor_id
) -> Subscription:
    row = plan.row
    try:
        return subs.create_subscription(
            student_id=plan.student_id,
            course_id=row["course"],
            teacher_id=row["teacher"],
            package_id=row["package"],
            starts_on=starts_on,
            price_minor=row.get("price_minor"),
            slots=row.get("slots", ()),
            supervisor_id=supervisor_id,
            bundle=bundle,
        )
    except ValidationError as exc:
        raise _rekeyed(exc, plan.index) from None


@transaction.atomic
def create_bundle(  # noqa: PLR0913 -- keyword-only; mirrors the API body (spec §4.2)
    kind: str,
    by,
    *,
    starts_on: date,
    rows: Iterable[dict],
    student_id: int | None = None,
    family_id: int | None = None,
    group_id: int | None = None,
    supervisor_id: int | None = None,
    notes: str = "",
) -> CreatedBundle:
    """§4.2: check the kind's rules, then the bundle and each member through
    `create_subscription(..., bundle=)`, in one transaction: any refusal
    leaves nothing. ``by`` is who created it (None: the system)."""
    rows = [dict(row) for row in rows]
    if kind == Kind.MULTI_COURSE:
        owner, plans = _plan_multi_course(rows, student_id)
    elif kind == Kind.FAMILY:
        owner, plans = _plan_family(rows, family_id)
    elif kind == Kind.GROUP:
        owner, plans = _plan_group(rows, group_id)
    else:
        raise ValueError(f"Unknown bundle kind: {kind!r}")
    bundle = SubscriptionBundle.objects.create(
        kind=kind, notes=notes or "", created_by=by, **owner
    )
    members = [
        _member(bundle, plan, starts_on=starts_on, supervisor_id=supervisor_id)
        for plan in plans
    ]
    created = list(
        rules.sessions_queryset()
        .filter(subscription__in=members)
        .exclude(status=Session.Status.CANCELLED)
    )
    return CreatedBundle(bundle, members, generation.conflicts(created))
```

(`subs.active_student(None)` already refuses: `identity_services.get_student_profile(None)` finds nothing.)

`backend/etqan/scheduling/services/__init__.py` — export `BUNDLE_KINDS`, `CreatedBundle`, `create_bundle` from `etqan.scheduling.services.bundles`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_create.py etqan/scheduling/tests/test_bundles_clashes.py`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/bundles.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/conftest.py etqan/scheduling/tests/test_bundles_create.py
git -C $W/backend commit -m "feat(scheduling): create multi-course, family and group bundles (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 7: Bundle actions — renew, pause, cancel, notes and dissolve, all or nothing

**Files:**
- Modify: `backend/etqan/scheduling/services/bundles.py` (`is_current`, `lock_bundle`, `refused`, `each_member`)
- Create: `backend/etqan/scheduling/services/bundle_actions.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_bundles_actions.py`

**Interfaces:**
- Consumes: `multi_bundle`, `group_bundle`, `member_of`, `deactivated` (conftest); `renew_subscription`, `add_pause`, `cancel_subscription`; `ConflictError` / `ValidationError` with `member_id` (Task 1).
- Produces: in `bundles.py` — `is_current(member) -> bool` (no renewal row; select `renewal`), `lock_bundle(bundle) -> tuple[SubscriptionBundle, list[Subscription]]` (bundle `FOR NO KEY UPDATE`, then every member `ORDER BY 1 ASC FOR UPDATE`, then a second pass for a member that appeared while it waited — review M-1; members with `renewal` and `student`, by id), `_lock_ids(queryset) -> list[int]`, `refused(member, exc)`, `each_member(members, call) -> list`. In `bundle_actions.py` (exported): `renew_bundle(bundle, *, by, starts_on=None) -> list[Subscription]` (409 `scheduling.nothing_to_renew`), `pause_bundle(bundle, *, from_date, to_date, reason="") -> list[SubscriptionPause]` (400 on `from_date` when no live member's term holds it), `cancel_bundle(bundle) -> list[Subscription]` (409 `scheduling.not_allowed_in_status`), `update_bundle(bundle, *, notes) -> SubscriptionBundle`, `dissolve_bundle(bundle) -> None`. A member's refusal is re-raised with its `member_id`, keeping status, code and field.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_bundles_actions.py`)

```python
"""Slice B2f §4.3, F-5: renew, pause, cancel, notes and dissolve — all or
nothing over the members, a refusal naming its member (§4.6), the bundle
locked before its members (§4)."""

from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.services import bundles
from etqan.scheduling.tests.conftest import deactivated
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import member_of
from etqan.scheduling.tests.conftest import multi_bundle

pytestmark = pytest.mark.django_db
JULY_1 = date(2026, 7, 1)


def first_table(sql: str) -> str:
    return sql.split(" FROM ", 1)[1].split(maxsplit=1)[0]


# ── Renew ────────────────────────────────────────────────────────────────────


def test_renewing_renews_every_current_member_into_the_bundle(world):
    created = multi_bundle(world)
    renewals = services.renew_bundle(created.bundle, by=None)
    assert sorted(r.renewed_from_id for r in renewals) == sorted(
        m.pk for m in created.members
    )
    assert {r.bundle_id for r in renewals} == {created.bundle.pk}
    # The renewals are the current members now: renewing again renews them.
    again = services.renew_bundle(created.bundle, by=None)
    assert sorted(r.renewed_from_id for r in again) == sorted(r.pk for r in renewals)


def test_a_cancelled_member_is_skipped_and_nothing_left_is_409(world):
    created = multi_bundle(world)
    first, second = created.members
    services.cancel_subscription(first)
    (renewal,) = services.renew_bundle(created.bundle, by=None)
    assert renewal.renewed_from_id == second.pk
    # A cancelled renewal is its chain's current link: skipped too.
    services.cancel_subscription(renewal)
    with pytest.raises(ConflictError) as exc:
        services.renew_bundle(created.bundle, by=None)
    assert (exc.value.code, exc.value.member_id) == ("scheduling.nothing_to_renew", None)


def test_a_removed_student_is_never_renewed_again(world):
    sister = make_student("Aisha")
    created = group_bundle(world, sister)
    services.cancel_subscription(member_of(created, sister))
    renewals = services.renew_bundle(created.bundle, by=None)
    assert [r.student.user_id for r in renewals] == [world.student.id]


def test_one_members_refusal_refuses_the_renewal_and_names_it(world):
    sister = make_student("Aisha")
    created = group_bundle(world, sister)
    deactivated(sister)
    with pytest.raises(ValidationError) as exc:
        services.renew_bundle(created.bundle, by=None)
    assert (exc.value.field, exc.value.member_id) == (
        "student",
        member_of(created, sister).pk,
    )
    assert not Subscription.objects.filter(renewed_from__isnull=False).exists()


def test_a_bundle_renewal_takes_one_start_for_every_member(world):
    created = multi_bundle(world)
    renewals = services.renew_bundle(created.bundle, by=None, starts_on=JULY_1)
    assert {r.starts_on for r in renewals} == {JULY_1}


# ── Pause ────────────────────────────────────────────────────────────────────


def test_pausing_pauses_every_live_member_whose_term_holds_the_date(world):
    created = multi_bundle(world)
    pauses = services.pause_bundle(
        created.bundle,
        from_date=date(2026, 6, 3),
        to_date=date(2026, 6, 5),
        reason="Travel",
    )
    assert sorted(p.subscription_id for p in pauses) == sorted(
        m.pk for m in created.members
    )
    assert {p.reason for p in pauses} == {"Travel"}


def test_a_pause_goes_to_the_link_whose_term_holds_it(world):
    created = multi_bundle(world)
    first, second = created.members
    renewal = services.renew_subscription(first, starts_on=JULY_1)
    pauses = services.pause_bundle(
        created.bundle, from_date=date(2026, 6, 10), to_date=date(2026, 6, 12)
    )
    assert sorted(p.subscription_id for p in pauses) == sorted([first.pk, second.pk])
    assert not renewal.pauses.exists()


def test_no_live_term_holding_the_date_is_400_on_from_date(world):
    created = multi_bundle(world)
    with pytest.raises(ValidationError) as exc:
        services.pause_bundle(
            created.bundle, from_date=date(2026, 9, 1), to_date=date(2026, 9, 2)
        )
    assert (exc.value.field, exc.value.member_id) == ("from_date", None)


def test_the_freeze_cap_refuses_the_whole_pause_and_names_the_member(world):
    created = multi_bundle(world)
    first, second = created.members
    # Eight of its ten freeze days are used.
    services.add_pause(second, from_date=date(2026, 6, 10), to_date=date(2026, 6, 17))
    with pytest.raises(ConflictError) as exc:
        services.pause_bundle(
            created.bundle, from_date=date(2026, 6, 20), to_date=date(2026, 6, 24)
        )
    assert (exc.value.code, exc.value.member_id) == (
        "scheduling.freeze_days_exceeded",
        second.pk,
    )
    assert not SubscriptionPause.objects.filter(subscription=first).exists()


# ── Cancel ───────────────────────────────────────────────────────────────────


def test_cancelling_cancels_every_live_member_old_link_and_renewal(world):
    created = multi_bundle(world)
    first, _ = created.members
    services.renew_subscription(first, starts_on=JULY_1)
    cancelled = services.cancel_bundle(created.bundle)
    assert len(cancelled) == 3
    statuses = set(
        Subscription.objects.filter(bundle=created.bundle).values_list(
            "status", flat=True
        )
    )
    assert statuses == {"cancelled"}


def test_nothing_live_to_cancel_is_409(world):
    created = multi_bundle(world)
    services.cancel_bundle(created.bundle)
    with pytest.raises(ConflictError) as exc:
        services.cancel_bundle(created.bundle)
    assert (exc.value.code, exc.value.member_id) == (
        "scheduling.not_allowed_in_status",
        None,
    )


# ── Notes and dissolve ───────────────────────────────────────────────────────


def test_notes_change_on_their_own(world):
    created = multi_bundle(world)
    services.update_bundle(created.bundle, notes="Evenings only")
    created.bundle.refresh_from_db()
    assert created.bundle.notes == "Evenings only"


def test_dissolving_unlinks_the_members_and_deletes_the_bundle(world):
    created = multi_bundle(world)
    ids = [m.pk for m in created.members]
    services.dissolve_bundle(created.bundle)
    assert not SubscriptionBundle.objects.exists()
    assert Subscription.objects.filter(pk__in=ids, bundle__isnull=True).count() == 2


# ── Lock order ───────────────────────────────────────────────────────────────


def test_a_member_renewed_while_the_bundle_waited_is_acted_on_too(
    world, monkeypatch
):
    """Review M-1: a renewal committed while the bundle action waited on its
    member's lock is caught by the second pass and cancelled with the rest."""
    created = multi_bundle(world)
    first = created.members[0]
    real = bundles._lock_ids  # noqa: SLF001 -- the seam the race goes through
    late = []

    def racing(members):
        ids = real(members)
        if not late:
            # What another session's renewal would have committed meanwhile.
            late.append(services.renew_subscription(first, starts_on=JULY_1))
        return ids

    monkeypatch.setattr(bundles, "_lock_ids", racing)
    cancelled = services.cancel_bundle(created.bundle)
    assert late[0].pk in {sub.pk for sub in cancelled}


ACTIONS = {
    "renew": lambda b: services.renew_bundle(b, by=None),
    "pause": lambda b: services.pause_bundle(
        b, from_date=date(2026, 6, 3), to_date=date(2026, 6, 4)
    ),
    "cancel": services.cancel_bundle,
    "dissolve": services.dissolve_bundle,
    "notes": lambda b: services.update_bundle(b, notes="x"),
}


@pytest.mark.parametrize("action", sorted(ACTIONS))
def test_the_bundle_is_locked_before_its_members(world, action):
    created = multi_bundle(world)
    with CaptureQueriesContext(connection) as ctx:
        ACTIONS[action](created.bundle)
    locks = [
        q["sql"]
        for q in ctx.captured_queries
        if "FOR UPDATE" in q["sql"] or "FOR NO KEY UPDATE" in q["sql"]
    ]
    # Plan D2: NO KEY UPDATE, so a lone member's insert never waits on it.
    assert "FOR NO KEY UPDATE" in locks[0]
    assert first_table(locks[0]) == '"scheduling_subscriptionbundle"'
    if action != "notes":
        assert first_table(locks[1]) == '"scheduling_subscription"'
        # Every member at once, in id order, before any member's own call.
        assert locks[1].rstrip().endswith("ORDER BY 1 ASC FOR UPDATE")
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_actions.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'renew_bundle'`.

- [ ] **Step 3: The shared helpers** (append to `backend/etqan/scheduling/services/bundles.py`; import `Callable` from `collections.abc` and `ConflictError` from `etqan.platform.exceptions`)

```python
def is_current(member: Subscription) -> bool:
    """F-5 (plan D4): the last link of its renewal chain — no renewal at all,
    cancelled or not. Select ``renewal`` to keep it free of queries."""
    return getattr(member, "renewal", None) is None


def lock_bundle(bundle: SubscriptionBundle) -> tuple[SubscriptionBundle, list]:
    """§4's order: the bundle — `FOR NO KEY UPDATE` (plan D2: a member's
    insert or delete takes only KEY SHARE on it, so a lone member's renewal
    never waits on a bundle action) — then every member in one statement, in
    id order, before any member's own call. The members come back with their
    renewal and student, oldest first."""
    locked = SubscriptionBundle.objects.select_for_update(no_key=True).get(
        pk=bundle.pk
    )
    ids = _lock_ids(Subscription.objects.filter(bundle=locked))
    # Review M-1: a lone member's renewal that committed while the statement
    # above waited on that member is not in its snapshot; a fresh statement
    # sees it. Lock any such newcomer, again in id order, until none is left
    # (one more pass at most: a new member needs a lock this action holds).
    while extra := _lock_ids(
        Subscription.objects.filter(bundle=locked).exclude(pk__in=ids)
    ):
        ids += extra
    members = list(
        Subscription.objects.filter(pk__in=ids)
        .select_related("renewal", "student")
        .order_by("pk")
    )
    return locked, members


def _lock_ids(members) -> list[int]:
    """``members`` locked in one statement, in id order (`ORDER BY 1 ASC FOR
    UPDATE`); their ids."""
    return list(
        members.order_by("pk").select_for_update().values_list("pk", flat=True)
    )


def refused(member: Subscription, exc: ConflictError | ValidationError):
    """§4.6: one member's refusal as the bundle action's, naming the member
    and keeping its status, code and field."""
    if isinstance(exc, ConflictError):
        return ConflictError(exc.message, code=exc.code, member_id=member.pk)
    return ValidationError(
        exc.message, field=exc.field, code=exc.code, member_id=member.pk
    )


def each_member(members: Iterable[Subscription], call: Callable) -> list:
    """F-5: ``call(member)`` for every member, all or nothing — the first
    refusal refuses the action, and the caller's transaction undoes the
    rest."""
    done = []
    for member in members:
        try:
            done.append(call(member))
        except (ConflictError, ValidationError) as exc:
            raise refused(member, exc) from None
    return done
```

- [ ] **Step 4: The actions** (`backend/etqan/scheduling/services/bundle_actions.py`)

```python
"""Slice B2f §4.3: what the office does to a whole bundle. Each action locks
the bundle and then every member (§4), applies the members' own services,
and refuses as a whole when one member refuses, naming it (F-5, §4.6).
Members stay editable one by one with the subscription actions."""

from datetime import date

from django.db import transaction

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import dates
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.models import SubscriptionPause
from etqan.scheduling.services import rules
from etqan.scheduling.services import subscriptions as subs
from etqan.scheduling.services.bundles import each_member
from etqan.scheduling.services.bundles import is_current
from etqan.scheduling.services.bundles import lock_bundle

CANCELLED = Subscription.Status.CANCELLED
NOTHING_LIVE = "Nothing in this bundle is live."


def _nothing_live() -> ConflictError:
    return ConflictError(NOTHING_LIVE, code="scheduling.not_allowed_in_status")


@transaction.atomic
def renew_bundle(
    bundle: SubscriptionBundle, *, by, starts_on: date | None = None
) -> list[Subscription]:
    """`renew_subscription` on each current member that is not cancelled
    (plan D4); each renewal stays in the bundle (F-6). ``starts_on`` is one
    start for them all, else each member's own default."""
    _, members = lock_bundle(bundle)
    due = [m for m in members if is_current(m) and m.status != CANCELLED]
    if not due:
        raise ConflictError(
            "Nothing in this bundle can be renewed.",
            code="scheduling.nothing_to_renew",
        )
    return each_member(
        due, lambda m: subs.renew_subscription(m, starts_on=starts_on, by=by)
    )


@transaction.atomic
def pause_bundle(
    bundle: SubscriptionBundle, *, from_date: date, to_date: date, reason: str = ""
) -> list[SubscriptionPause]:
    """Plan D5: `add_pause` on every live member whose term holds
    ``from_date``, so an old link and its not-yet-started renewal never both
    get it. One member's freeze cap refuses all of it, naming that member."""
    _, members = lock_bundle(bundle)
    due = [
        m
        for m in members
        if m.status in rules.LIVE
        and m.starts_on <= from_date <= rules.term(m, 0).ends_on
    ]
    if not due:
        raise ValidationError(
            "No live member's term includes this date.", field="from_date"
        )
    return each_member(
        due,
        lambda m: subs.add_pause(
            m, from_date=from_date, to_date=to_date, reason=reason
        ),
    )


@transaction.atomic
def cancel_bundle(bundle: SubscriptionBundle) -> list[Subscription]:
    """Plan D5: `cancel_subscription` on every live member — the old link and
    a pending renewal alike — so the bundle stops at once."""
    _, members = lock_bundle(bundle)
    live = [m for m in members if m.status in rules.LIVE]
    if not live:
        raise _nothing_live()
    each_member(live, subs.cancel_subscription)
    return live


@transaction.atomic
def update_bundle(bundle: SubscriptionBundle, *, notes: str) -> SubscriptionBundle:
    locked = SubscriptionBundle.objects.select_for_update(no_key=True).get(
        pk=bundle.pk
    )
    locked.notes = notes or ""
    locked.save(update_fields=["notes", "updated_at"])
    return locked


@transaction.atomic
def dissolve_bundle(bundle: SubscriptionBundle) -> None:
    """F-9: the members become plain subscriptions, and the bundle goes."""
    locked, _ = lock_bundle(bundle)
    Subscription.objects.filter(bundle=locked).update(
        bundle=None, updated_at=dates.now()
    )
    locked.delete()
```

`backend/etqan/scheduling/services/__init__.py` — export `cancel_bundle`, `dissolve_bundle`, `pause_bundle`, `renew_bundle`, `update_bundle` from `bundle_actions`, and `is_current` from `bundles`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_actions.py`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/bundles.py etqan/scheduling/services/bundle_actions.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_bundles_actions.py
git -C $W/backend commit -m "feat(scheduling): renew, pause, cancel and dissolve a bundle as one (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 8: Bundle actions — archive and restore; a group's students added and removed

**Files:**
- Modify: `backend/etqan/scheduling/services/bundle_actions.py`
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Test: `backend/etqan/scheduling/tests/test_bundles_roster_archive.py`

**Interfaces:**
- Consumes: `lock_bundle`, `each_member`, `is_current`, `refused` (Task 7); `archive_subscription` / `restore_subscription` (B2d); `copied_slots`, `create_subscription(bundle=)` (Task 4); `access_services.get_supervisor`.
- Produces (exported): `archive_bundle(bundle, *, by) -> list[Subscription]`, `restore_bundle(bundle, *, by) -> list[Subscription]` (plan D6), `add_to_group_bundle(bundle, *, student_id, starts_on) -> Subscription`, `remove_from_group_bundle(bundle, *, student_id) -> list[Subscription]` (plan D8).

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_bundles_roster_archive.py`)

```python
"""Slice B2f §4.3: archive and restore over every member (plan D6); a group
bundle's roster — add from the template, remove with a pending renewal
(F-7, plan D8)."""

from datetime import date

import pytest

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.models import Subscription
from etqan.scheduling.tests.conftest import course_teacher
from etqan.scheduling.tests.conftest import deactivated
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import member_of
from etqan.scheduling.tests.conftest import multi_bundle

pytestmark = pytest.mark.django_db
JUNE_8 = date(2026, 6, 8)


def archived(created) -> list[bool]:
    return [
        at is not None
        for at in Subscription.objects.filter(bundle=created.bundle)
        .order_by("pk")
        .values_list("archived_at", flat=True)
    ]


# ── Archive and restore ──────────────────────────────────────────────────────


def test_archiving_and_restoring_take_every_member(world):
    created = multi_bundle(world)
    services.cancel_bundle(created.bundle)
    services.archive_bundle(created.bundle, by=None)
    assert archived(created) == [True, True]
    services.restore_bundle(created.bundle, by=None)
    assert archived(created) == [False, False]


def test_archiving_names_the_first_live_member(world):
    created = multi_bundle(world)
    first, second = created.members
    services.cancel_subscription(first)
    with pytest.raises(ConflictError) as exc:
        services.archive_bundle(created.bundle, by=None)
    assert (exc.value.code, exc.value.member_id) == (
        "scheduling.not_allowed_in_status",
        second.pk,
    )
    assert archived(created) == [False, False]


def test_members_already_in_place_are_left_alone(world):
    created = multi_bundle(world)
    first, _ = created.members
    services.cancel_bundle(created.bundle)
    services.archive_subscription(first, by=None)
    services.archive_bundle(created.bundle, by=None)
    assert archived(created) == [True, True]
    with pytest.raises(ConflictError) as exc:
        services.archive_bundle(created.bundle, by=None)
    assert exc.value.code == "scheduling.archived"
    services.restore_subscription(first, by=None)
    services.restore_bundle(created.bundle, by=None)
    assert archived(created) == [False, False]
    with pytest.raises(ConflictError) as exc:
        services.restore_bundle(created.bundle, by=None)
    assert exc.value.code == "scheduling.not_archived"


# ── Add to a group ───────────────────────────────────────────────────────────


def test_a_new_student_joins_from_the_template(world):
    created = group_bundle(world)
    (template,) = created.members
    newcomer = make_student("Aisha")
    sub = services.add_to_group_bundle(
        created.bundle, student_id=newcomer.id, starts_on=JUNE_8
    )
    assert (
        sub.bundle_id,
        sub.student.user_id,
        sub.course_id,
        sub.teacher_id,
        sub.package_id,
        sub.price_minor,
        sub.starts_on,
    ) == (
        created.bundle.pk,
        newcomer.id,
        template.course_id,
        template.teacher_id,
        template.package_id,
        template.price_minor,
        JUNE_8,
    )
    slots = sorted(
        (s.weekday, s.start_time, s.minutes) for s in sub.slots.filter(is_active=True)
    )
    assert slots == sorted(
        (s.weekday, s.start_time, s.minutes) for s in template.slots.all()
    )


def test_the_template_is_the_newest_current_live_member(world):
    sister = make_student("Aisha")
    created = group_bundle(world, sister)
    newest = max(created.members, key=lambda m: m.pk)
    other = course_teacher(world)
    services.update_subscription(newest, teacher_id=other.id)
    joined = services.add_to_group_bundle(
        created.bundle, student_id=make_student("Zaid").id, starts_on=JUNE_8
    )
    assert joined.teacher.user_id == other.id
    # The newest is now Zaid's; once it and the one before are cancelled, the
    # oldest live one is copied.
    services.cancel_subscription(joined)
    services.cancel_subscription(newest)
    again = services.add_to_group_bundle(
        created.bundle, student_id=make_student("Huda").id, starts_on=JUNE_8
    )
    assert again.teacher.user_id == world.teacher.id


@pytest.mark.parametrize("who", ["member", "inactive", "unknown"])
def test_a_student_who_cannot_join_is_refused_on_student_id(world, who):
    created = group_bundle(world)
    student = {
        "member": lambda: world.student,
        "inactive": lambda: deactivated(make_student("Aisha")),
        "unknown": lambda: type(world.student)(id=999999),
    }[who]()
    with pytest.raises(ValidationError) as exc:
        services.add_to_group_bundle(
            created.bundle, student_id=student.id, starts_on=JUNE_8
        )
    assert (exc.value.field, exc.value.member_id) == ("student_id", None)


def test_a_removed_student_may_join_again(world):
    sister = make_student("Aisha")
    created = group_bundle(world, sister)
    services.remove_from_group_bundle(created.bundle, student_id=sister.id)
    joined = services.add_to_group_bundle(
        created.bundle, student_id=sister.id, starts_on=JUNE_8
    )
    assert joined.status == "active"


def test_nothing_live_to_copy_is_409(world):
    created = group_bundle(world)
    services.cancel_bundle(created.bundle)
    with pytest.raises(ConflictError) as exc:
        services.add_to_group_bundle(
            created.bundle, student_id=make_student("Aisha").id, starts_on=JUNE_8
        )
    assert exc.value.code == "scheduling.not_allowed_in_status"


def test_a_template_refusal_names_the_template(world):
    created = group_bundle(world)
    (template,) = created.members
    deactivated(world.teacher)
    with pytest.raises(ValidationError) as exc:
        services.add_to_group_bundle(
            created.bundle, student_id=make_student("Aisha").id, starts_on=JUNE_8
        )
    assert (exc.value.field, exc.value.member_id) == ("teacher", template.pk)


@pytest.mark.parametrize(
    "action",
    [
        lambda b, s: services.add_to_group_bundle(b, student_id=s.id, starts_on=JUNE_8),
        lambda b, s: services.remove_from_group_bundle(b, student_id=s.id),
    ],
)
def test_only_a_group_bundle_has_a_roster(world, action):
    created = multi_bundle(world)
    with pytest.raises(ValidationError) as exc:
        action(created.bundle, world.student)
    assert exc.value.field is None


# ── Remove from a group ──────────────────────────────────────────────────────


def test_removing_cancels_the_students_live_members_with_a_pending_renewal(world):
    sister = make_student("Aisha")
    created = group_bundle(world, sister)
    theirs = member_of(created, sister)
    renewal = services.renew_subscription(theirs, starts_on=date(2026, 7, 1))
    cancelled = services.remove_from_group_bundle(
        created.bundle, student_id=sister.id
    )
    assert sorted(c.pk for c in cancelled) == sorted([theirs.pk, renewal.pk])
    statuses = dict(
        Subscription.objects.filter(bundle=created.bundle).values_list("pk", "status")
    )
    assert statuses[member_of(created, world.student).pk] == "active"
    assert {statuses[theirs.pk], statuses[renewal.pk]} == {"cancelled"}
    with pytest.raises(ConflictError) as exc:
        services.remove_from_group_bundle(created.bundle, student_id=sister.id)
    assert exc.value.code == "scheduling.not_allowed_in_status"
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_roster_archive.py`
Expected: FAIL — `AttributeError: module 'etqan.scheduling.services' has no attribute 'archive_bundle'`.

- [ ] **Step 3: Implement** (append to `backend/etqan/scheduling/services/bundle_actions.py`; import `access_services` from `etqan.access`, `archive_subscription` / `restore_subscription` from `etqan.scheduling.services.archive`, `refused` from `etqan.scheduling.services.bundles`)

```python
@transaction.atomic
def archive_bundle(bundle: SubscriptionBundle, *, by) -> list[Subscription]:
    """B2d through every member (plan D6): refused while any member is live,
    naming the first; members already archived are left alone."""
    _, members = lock_bundle(bundle)
    live = next((m for m in members if m.status in rules.LIVE), None)
    if live is not None:
        raise ConflictError(
            f"Not allowed while the subscription is {live.status}.",
            code="scheduling.not_allowed_in_status",
            member_id=live.pk,
        )
    todo = [m for m in members if m.archived_at is None]
    if not todo:
        raise ConflictError(rules.ARCHIVED, code="scheduling.archived")
    return each_member(todo, lambda m: archive_subscription(m, by=by))


@transaction.atomic
def restore_bundle(bundle: SubscriptionBundle, *, by) -> list[Subscription]:
    _, members = lock_bundle(bundle)
    todo = [m for m in members if m.archived_at is not None]
    if not todo:
        raise ConflictError("This isn't archived.", code="scheduling.not_archived")
    return each_member(todo, lambda m: restore_subscription(m, by=by))


def _roster_only(bundle: SubscriptionBundle) -> None:
    if bundle.kind != SubscriptionBundle.Kind.GROUP:
        raise ValidationError("Only a group bundle adds or removes students.")


@transaction.atomic
def add_to_group_bundle(
    bundle: SubscriptionBundle, *, student_id: int, starts_on: date
) -> Subscription:
    """F-7, plan D8: a new subscription from ``starts_on`` copying the
    template — the most recently created current, non-cancelled member — with
    its course, teacher, package, price, active slots and supervisor."""
    locked, members = lock_bundle(bundle)
    _roster_only(locked)
    try:
        profile = subs.active_student(student_id)
    except ValidationError as exc:
        raise ValidationError(exc.message, field="student_id") from None
    if any(m.student_id == profile.pk and m.status in rules.LIVE for m in members):
        raise ValidationError(
            "This student already has a live subscription in this bundle.",
            field="student_id",
        )
    template = max(
        (m for m in members if is_current(m) and m.status != CANCELLED),
        key=lambda m: (m.created_at, m.pk),
        default=None,
    )
    if template is None:
        raise _nothing_live()
    supervisor = access_services.get_supervisor(template.supervisor_id)
    try:
        return subs.create_subscription(
            student_id=student_id,
            course_id=template.course_id,
            teacher_id=template.teacher.user_id,
            package_id=template.package_id,
            starts_on=starts_on,
            price_minor=template.price_minor,
            slots=subs.copied_slots(template),
            supervisor_id=supervisor.pk if supervisor else None,
            bundle=locked,
        )
    except ValidationError as exc:
        raise refused(template, exc) from None


@transaction.atomic
def remove_from_group_bundle(
    bundle: SubscriptionBundle, *, student_id: int
) -> list[Subscription]:
    """F-7: cancels the student's live members — the current one and a
    pending renewal."""
    locked, members = lock_bundle(bundle)
    _roster_only(locked)
    live = [
        m
        for m in members
        if m.student.user_id == student_id and m.status in rules.LIVE
    ]
    if not live:
        raise ConflictError(
            "This student has nothing live in this bundle.",
            code="scheduling.not_allowed_in_status",
        )
    each_member(live, subs.cancel_subscription)
    return live
```

(`archive_subscription` and `restore_subscription` lock each member again and then its sessions: a re-lock inside the same transaction, never a new order.)

`backend/etqan/scheduling/services/__init__.py` — export `add_to_group_bundle`, `archive_bundle`, `remove_from_group_bundle`, `restore_bundle`.

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_roster_archive.py etqan/scheduling/tests/test_bundles_actions.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/bundle_actions.py etqan/scheduling/services/__init__.py etqan/scheduling/tests/test_bundles_roster_archive.py
git -C $W/backend commit -m "feat(scheduling): archive and restore a bundle; add and remove a group's students (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: Reading bundles — the view, the list, and the labels on subscriptions and sessions

**Files:**
- Create: `backend/etqan/scheduling/services/bundle_reads.py`
- Modify: `backend/etqan/scheduling/services/rules.py` (`SESSION_RELATED`, `subscriptions_queryset`, `filter_subscriptions`)
- Modify: `backend/etqan/scheduling/services/__init__.py` (exports)
- Modify: `backend/etqan/scheduling/api/payloads.py` (`bundle` on subscription rows, `group` on session rows)
- Modify: `backend/etqan/scheduling/api/views.py` (`subscription_filters`: `bundle`, `bundle_kind`)
- Test: `backend/etqan/scheduling/tests/test_bundles_reads.py`, `backend/etqan/scheduling/tests/test_api_bundle_labels.py`

**Interfaces:**
- Consumes: Tasks 6-8.
- Produces (exported): `bundles_queryset() -> QuerySet[SubscriptionBundle]` (owner joined; `members_count`, `is_live` annotated); `filter_bundles(bundles, *, kind="", student=None, family=None, group=None, state="")`; `BUNDLE_STATES = ("live", "ended")`; `has_bundles() -> bool`; `bundle_view(bundle) -> BundleView` with `bundle`, `members` (rows of `subscriptions_queryset`, by id), `current: frozenset[int]`, `freeze_days_left: dict[int, int]`, `sessions_total: int`, `prices: list[tuple[str, int]]`, `roster: list[RosterRow]`, `can_renew`, `can_pause`, `can_cancel`, `can_add_member: bool`, `can_archive`, `can_restore: bool | None` (None while the archive is off); `RosterRow(member, attended: int, can_remove: bool)`. `filter_subscriptions(..., bundle=None, bundle_kind="")`. Payloads: subscription rows gain `bundle: {id, kind}` only for members; session rows gain `group: {bundle_id, name}` only for a group bundle's sessions (plan D10). The subscriptions list reads `?bundle=<id>` and `?bundle_kind=<kind>` (an unknown kind is ignored, as the list ignores bad values).

- [ ] **Step 1: Write the failing service tests** (`backend/etqan/scheduling/tests/test_bundles_reads.py`)

```python
"""Slice B2f §4.5, F-10, plan D11/D16: one bundle's members, totals, roster
and what may be done to it; the list and its filters."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.billing import services as billing_services
from etqan.catalogue import services as catalogue_services
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import make_family
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import member_of
from etqan.scheduling.tests.conftest import multi_bundle
from etqan.scheduling.tests.conftest import other_course
from etqan.scheduling.tests.conftest import row
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
JUNE_1 = date(2026, 6, 1)


def view_of(created):
    return services.bundle_view(services.bundles_queryset().get(pk=created.bundle.pk))


def test_the_view_marks_current_members_and_sums_the_live_ones(world):
    usd = catalogue_services.create_package(
        name_ar="أسبوعي",
        name_en="Weekly",
        sessions_per_week=1,
        session_minutes=30,
        duration_value=1,
        duration_unit="month",
        freeze_days_allowed=0,
        price_minor=4000,
        currency="USD",
    )
    created = services.create_bundle(
        "multi_course",
        None,
        starts_on=JUNE_1,
        student_id=world.student.id,
        rows=[
            row(world),
            row(world, other_course(world), package=usd.pk),
            row(world, other_course(world, "Seerah")),
        ],
    )
    first, second, third = created.members
    renewal = services.renew_subscription(first)
    services.cancel_subscription(third)
    view = view_of(created)
    assert [m.pk for m in view.members] == [first.pk, second.pk, third.pk, renewal.pk]
    assert view.current == {second.pk, third.pk, renewal.pk}
    # Current and not cancelled: the renewal and the USD member; never summed
    # across currencies.
    assert view.prices == [("EGP", renewal.price_minor), ("USD", 4000)]
    assert view.sessions_total == renewal.sessions_total + second.sessions_total
    assert view.freeze_days_left[first.pk] == 10


def test_the_roster_shows_each_students_member_and_attended_sessions(world, clock):
    sister = make_student("Aisha")
    created = group_bundle(world, sister)
    clock.set(datetime(2026, 6, 1, 19, 0, tzinfo=UTC))
    for user, mark in ((world.student, "present"), (sister, "absent")):
        session = Session.objects.get(
            subscription=member_of(created, user), occurs_on=JUNE_1
        )
        services.mark_attendance(session, by=None, student_attendance=mark)
    roster = view_of(created).roster
    assert [
        (r.member.student.user_id, r.member.pk, r.attended, r.can_remove)
        for r in roster
    ] == [
        (sister.id, member_of(created, sister).pk, 0, True),
        (world.student.id, member_of(created, world.student).pk, 1, True),
    ]


def test_the_roster_follows_a_students_current_live_member(world):
    sister = make_student("Aisha")
    created = group_bundle(world, sister)
    theirs = member_of(created, sister)
    renewal = services.renew_subscription(theirs, starts_on=date(2026, 7, 1))
    services.remove_from_group_bundle(created.bundle, student_id=sister.id)
    (aisha, _) = view_of(created).roster
    assert (aisha.member.pk, aisha.member.status, aisha.can_remove) == (
        renewal.pk,
        "cancelled",
        False,
    )


def test_what_may_be_done_follows_the_members(world, archives_on):
    created = multi_bundle(world)

    def flags():
        view = view_of(created)
        return (
            view.can_renew,
            view.can_pause,
            view.can_cancel,
            view.can_add_member,
            view.can_archive,
            view.can_restore,
        )

    assert flags() == (True, True, True, False, False, False)
    services.cancel_bundle(created.bundle)
    assert flags() == (False, False, False, False, True, False)
    services.archive_bundle(created.bundle, by=None)
    assert flags() == (False, False, False, False, False, True)


def test_a_group_with_a_live_member_takes_students(world):
    assert view_of(group_bundle(world)).can_add_member is True


def test_the_archive_flags_are_absent_while_the_archive_is_off(world):
    view = view_of(multi_bundle(world))
    assert (view.can_archive, view.can_restore) == (None, None)


def test_the_view_costs_the_same_for_two_or_four_members(world):
    def selects(created) -> int:
        bundle = services.bundles_queryset().get(pk=created.bundle.pk)
        with CaptureQueriesContext(connection) as ctx:
            services.bundle_view(bundle)
        return sum(
            q["sql"].lstrip().upper().startswith("SELECT") for q in ctx.captured_queries
        )

    two = selects(multi_bundle(world))
    sisters = [make_student(name) for name in ("Aisha", "Huda", "Zaid")]
    four = group_bundle(world, *sisters)
    assert selects(four) == two


def test_the_list_filters_by_kind_owner_and_state(world):
    sister = make_student("Aisha")
    multi = multi_bundle(world)
    group = group_bundle(world, sister)
    family = make_family(world.student, sister)
    fam = services.create_bundle(
        "family",
        None,
        starts_on=JUNE_1,
        family_id=family.pk,
        rows=[row(world, student=world.student.id), row(world, student=sister.id)],
    )
    services.cancel_bundle(multi.bundle)

    def ids(**filters):
        found = services.filter_bundles(services.bundles_queryset(), **filters)
        return [b.pk for b in found]

    assert ids() == [fam.bundle.pk, group.bundle.pk, multi.bundle.pk]
    assert ids(kind="group") == [group.bundle.pk]
    # A member's student counts, not only a multi-course owner.
    assert ids(student=sister.id) == [fam.bundle.pk, group.bundle.pk]
    assert ids(family=family.pk) == [fam.bundle.pk]
    assert ids(group=group.bundle.study_group_id) == [group.bundle.pk]
    assert ids(state="ended") == [multi.bundle.pk]
    assert ids(state="live") == [fam.bundle.pk, group.bundle.pk]
    counted = services.bundles_queryset().get(pk=group.bundle.pk)
    assert (counted.members_count, counted.is_live) == (2, True)
    assert services.has_bundles() is True


def test_a_members_numbers_are_a_plain_subscriptions(world, clock):
    """F-3 (ledger D7, spec §9 "unchanged reads"): derived numbers, invoices,
    payroll and notices read a member exactly as a plain subscription."""
    member = multi_bundle(world).members[0]
    plain = subscription_for(
        world, student_id=make_student("Aisha").id, slots=two_slots()
    )
    clock.set(datetime(2026, 6, 1, 19, 0, tzinfo=UTC))
    for sub in (member, plain):
        session = Session.objects.get(subscription=sub, occurs_on=JUNE_1)
        services.mark_attendance(session, by=None, student_attendance="present")
    values = services.derive([member, plain])
    assert values[member.pk] == values[plain.pk]
    paid = {s.subscription_id for s in services.payroll_sessions(JUNE_1, JUNE_1)}
    assert {member.pk, plain.pk} <= paid
    # Seven left of eight, at or below the threshold: both are announced.
    low = {sub.pk: left for sub, left in services.subscriptions_running_low(8)}
    assert {member.pk, plain.pk} <= set(low)
    assert low[member.pk] == low[plain.pk]
    invoices = [
        billing_services.invoice_subscription(sub.pk, by=None) for sub in (member, plain)
    ]
    assert invoices[0].amount_minor == invoices[1].amount_minor
```

- [ ] **Step 2: Write the failing API tests** (`backend/etqan/scheduling/tests/test_api_bundle_labels.py`)

```python
"""Slice B2f §4.5, plan D10: a member's row names its bundle, a group's
sessions their group — for everyone in scope; every other row is unchanged."""

from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.scheduling import services
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_group
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import member_of
from etqan.scheduling.tests.conftest import multi_bundle
from etqan.scheduling.tests.conftest import row
from etqan.scheduling.tests.conftest import subscription_for
from etqan.scheduling.tests.conftest import two_slots

pytestmark = pytest.mark.django_db
SUBS = "/api/v1/subscriptions/"
SESSIONS = "/api/v1/sessions/"


@pytest.fixture
def office():
    return as_user(make_admin())


def test_a_members_row_names_its_bundle_and_a_plain_row_does_not(world, office):
    created = group_bundle(world)
    member = member_of(created, world.student)
    plain = subscription_for(world)
    rows = {r["id"]: r for r in office.get(SUBS).json()["results"]}
    assert rows[member.pk]["bundle"] == {"id": created.bundle.pk, "kind": "group"}
    assert "bundle" not in rows[plain.pk]
    detail = office.get(f"{SUBS}{member.pk}/").json()
    assert detail["bundle"] == {"id": created.bundle.pk, "kind": "group"}


def test_the_subscriptions_list_filters_by_bundle_and_kind(world, office):
    group = group_bundle(world)
    multi = multi_bundle(world)
    subscription_for(world)

    def ids(**params):
        return sorted(r["id"] for r in office.get(SUBS, params).json()["results"])

    assert ids(bundle_kind="group") == [m.pk for m in group.members]
    assert ids(bundle=multi.bundle.pk) == sorted(m.pk for m in multi.members)
    assert len(ids(bundle_kind="bogus")) == 4


def test_group_sessions_carry_the_group_for_everyone_in_scope(world, office):
    created = group_bundle(world)
    label = {"bundle_id": created.bundle.pk, "name": "Evening circle"}
    plain = subscription_for(world, student_id=make_student("Zaid").id)
    office_rows = office.get(SESSIONS).json()["results"]
    grouped = [r for r in office_rows if r["subscription_id"] != plain.pk]
    assert grouped
    assert all(r["group"] == label for r in grouped)
    teacher_rows = as_user(world.teacher).get(SESSIONS).json()["results"]
    assert all(
        r.get("group") == label
        for r in teacher_rows
        if r["subscription_id"] != plain.pk
    )
    student_rows = as_user(world.student).get(SESSIONS).json()["results"]
    assert student_rows
    assert all(r["group"] == label for r in student_rows)


def test_multi_course_sessions_carry_no_group(world, office):
    multi_bundle(world)
    rows = office.get(SESSIONS).json()["results"]
    assert rows
    assert all("group" not in r for r in rows)


def test_the_session_list_costs_the_same_with_more_group_rows(world, office):
    def selects() -> int:
        with CaptureQueriesContext(connection) as ctx:
            assert office.get(SESSIONS).status_code == 200
        return sum(
            q["sql"].lstrip().upper().startswith("SELECT") for q in ctx.captured_queries
        )

    group_bundle(world)
    one = selects()
    # A second class, of two other students (one group per student).
    late = make_group(make_student("Aisha"), make_student("Huda"), name="Late")
    services.create_bundle(
        "group",
        None,
        starts_on=date(2026, 6, 1),
        group_id=late.pk,
        rows=[row(world, slots=two_slots())],
    )
    assert selects() == one
```

- [ ] **Step 3: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_reads.py etqan/scheduling/tests/test_api_bundle_labels.py`
Expected: FAIL — `AttributeError: … has no attribute 'bundle_view'`; the API tests fail on the missing `bundle` / `group` keys.

- [ ] **Step 4: The reads** (`backend/etqan/scheduling/services/bundle_reads.py`)

```python
"""Slice B2f §4.5: what the office reads about bundles — the list, and one
bundle's members (the current ones marked), totals, roster and what may be
done to it. Totals are sums over the current, non-cancelled members, read and
never stored (F-3, BR-09, BR-10), per currency (plan D16)."""

from collections import defaultdict
from dataclasses import dataclass

from django.db.models import Count
from django.db.models import Exists
from django.db.models import OuterRef
from django.db.models import Q
from django.db.models import QuerySet

from etqan.platform import features
from etqan.scheduling.models import Session
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.services import rules

CANCELLED = Subscription.Status.CANCELLED
RENEWABLE = (
    Subscription.Status.ACTIVE,
    Subscription.Status.PAUSED,
    Subscription.Status.EXPIRED,
)
BUNDLE_STATES = ("live", "ended")


@dataclass(frozen=True)
class RosterRow:
    """F-10: a student, the member that stands for them, and their attended
    sessions (completed, student present) over all their members here."""

    member: Subscription
    attended: int
    can_remove: bool


@dataclass(frozen=True)
class BundleView:
    bundle: SubscriptionBundle
    members: list[Subscription]
    current: frozenset[int]
    freeze_days_left: dict[int, int]
    sessions_total: int
    prices: list[tuple[str, int]]
    roster: list[RosterRow]
    can_renew: bool
    can_pause: bool
    can_cancel: bool
    can_add_member: bool
    # Plan D11: None while the subscription archive is off.
    can_archive: bool | None
    can_restore: bool | None


def bundles_queryset() -> QuerySet[SubscriptionBundle]:
    """Bundles with their owner joined, ``members_count`` and ``is_live`` (a
    current member is live), newest first."""
    live = Subscription.objects.filter(
        bundle=OuterRef("pk"), renewal__isnull=True, status__in=rules.LIVE
    )
    return (
        SubscriptionBundle.objects.select_related(
            "student__user", "family", "study_group", "created_by"
        )
        .annotate(members_count=Count("subscriptions"), is_live=Exists(live))
        .order_by("-created_at", "-id")
    )


def filter_bundles(  # noqa: PLR0913 -- keyword-only; mirrors the list's query (§4.5)
    bundles: QuerySet[SubscriptionBundle],
    *,
    kind: str = "",
    student: int | None = None,
    family: int | None = None,
    group: int | None = None,
    state: str = "",
) -> QuerySet[SubscriptionBundle]:
    """Plan D14: ``student`` (a User id) matches the owner or any member's
    student; ``state`` is `live` or `ended`."""
    exact = {"kind": kind, "family_id": family, "study_group_id": group}
    bundles = bundles.filter(
        **{key: value for key, value in exact.items() if value not in (None, "")}
    )
    if student is not None:
        theirs = Subscription.objects.filter(
            bundle=OuterRef("pk"), student__user_id=student
        )
        bundles = bundles.filter(Q(student__user_id=student) | Exists(theirs))
    if state in BUNDLE_STATES:
        bundles = bundles.filter(is_live=state == "live")
    return bundles


def has_bundles() -> bool:
    return SubscriptionBundle.objects.exists()


def _attended(bundle: SubscriptionBundle) -> dict[int, int]:
    rows = (
        Session.objects.filter(
            subscription__bundle=bundle,
            status=Session.Status.COMPLETED,
            student_attendance=Session.Attendance.PRESENT,
        )
        .order_by()
        .values("student_id")
        .annotate(n=Count("pk"))
        .values_list("student_id", "n")
    )
    return dict(rows)


def _roster(bundle, members, current) -> list[RosterRow]:
    """Plan D4: per student, the newest current non-cancelled member, else
    the newest current one, else the newest; by the student's name."""
    attended = _attended(bundle)
    group = bundle.kind == SubscriptionBundle.Kind.GROUP
    by_student = defaultdict(list)
    for member in members:
        by_student[member.student_id].append(member)
    roster = []
    for student_id, theirs in by_student.items():
        shown = max(
            theirs,
            key=lambda m: (
                m.pk in current and m.status != CANCELLED,
                m.pk in current,
                m.pk,
            ),
        )
        roster.append(
            RosterRow(
                member=shown,
                attended=attended.get(student_id, 0),
                can_remove=group and any(m.status in rules.LIVE for m in theirs),
            )
        )
    return sorted(
        roster, key=lambda r: (r.member.student.user.full_name, r.member.student_id)
    )


def _archive_flags(members: list[Subscription]) -> dict:
    """Plan D11: archivable when every member has ended, one is not archived
    and none of those has a session still due (B2d D-3)."""
    if not features.enabled(rules.SUBSCRIPTION_ARCHIVE):
        return {"can_archive": None, "can_restore": None}
    waiting = [m for m in members if m.archived_at is None]
    return {
        "can_archive": bool(waiting)
        and all(m.status in rules.ENDED for m in members)
        and all(rules.archivable(m) for m in waiting),
        "can_restore": len(waiting) < len(members),
    }


def bundle_view(bundle: SubscriptionBundle) -> BundleView:
    """Everything the bundle page reads, in a fixed number of queries.
    ``bundle`` comes from `bundles_queryset`."""
    renewed = Subscription.objects.filter(renewed_from=OuterRef("pk"))
    members = list(
        rules.subscriptions_queryset()
        .filter(bundle=bundle)
        .annotate(has_renewal=Exists(renewed))
        .order_by("pk")
    )
    current = frozenset(m.pk for m in members if not m.has_renewal)
    counted = [m for m in members if m.pk in current and m.status != CANCELLED]
    prices: dict[str, int] = defaultdict(int)
    for member in counted:
        prices[member.currency] += member.price_minor
    archive_on = features.enabled(rules.SUBSCRIPTION_ARCHIVE)
    live = any(m.status in rules.LIVE for m in members)
    return BundleView(
        bundle=bundle,
        members=members,
        current=current,
        freeze_days_left={
            m.pk: max(0, m.freeze_days_allowed - rules.term(m, 0).paused_days)
            for m in members
        },
        sessions_total=sum(m.sessions_total for m in counted),
        prices=sorted(prices.items()),
        roster=_roster(bundle, members, current),
        # Review M-3: the renewal is all or nothing, so every counted member
        # must be able to renew.
        can_renew=bool(counted)
        and all(
            m.status in RENEWABLE and not (archive_on and m.archived_at)
            for m in counted
        ),
        can_pause=live,
        can_cancel=live,
        can_add_member=bundle.kind == SubscriptionBundle.Kind.GROUP and bool(counted),
        **_archive_flags(members),
    )
```

`backend/etqan/scheduling/services/__init__.py` — export `BUNDLE_STATES`, `BundleView`, `RosterRow`, `bundle_view`, `bundles_queryset`, `filter_bundles`, `has_bundles`.

- [ ] **Step 5: The rows** — `backend/etqan/scheduling/services/rules.py`:

```python
SESSION_RELATED = (
    ...,  # unchanged entries
    # Slice B2f §4.5: a group bundle's sessions name their group.
    "subscription__bundle__study_group",
)
```

`subscriptions_queryset`: add `"bundle"` to its `select_related(...)`. `filter_subscriptions` gains two keyword arguments, read like the others:

```python
    created_to: date | None = None,
    bundle: int | None = None,
    bundle_kind: str = "",
) -> QuerySet[Subscription]:
    ...
    exact = {
        "status": status,
        "student__user_id": student,
        "teacher__user_id": teacher,
        "course_id": course,
        # Slice B2f §4.5.
        "bundle_id": bundle,
        "bundle__kind": bundle_kind,
    }
```

`backend/etqan/scheduling/api/views.py` — `subscription_filters` reads them (an unknown kind is ignored):

```python
    kind = params.get("bundle_kind", "")
    return {
        ...,  # unchanged keys
        # Slice B2f §4.5.
        "bundle": _as_int(params.get("bundle", "")),
        "bundle_kind": kind if kind in services.BUNDLE_KINDS else "",
    }
```

`backend/etqan/scheduling/api/payloads.py` — in `subscription_row`, before the `supervision` block:

```python
    if sub.bundle_id is not None:
        # Slice B2f §4.5 (plan D10): only on a bundle's members.
        row["bundle"] = {"id": sub.bundle_id, "kind": sub.bundle.kind}
```

and a helper plus its call in `session_row` (after the `supervision` block, before `_add_times_and_postponement`):

```python
def _group(session) -> dict | None:
    """Slice B2f §4.5 (plan D10): a group bundle's session names its group,
    to everyone in scope. Read through `sessions_queryset` (joined)."""
    sub = session.subscription if session.subscription_id else None
    bundle = sub.bundle if sub is not None and sub.bundle_id else None
    if bundle is None or bundle.kind != "group":
        return None
    return {"bundle_id": bundle.pk, "name": bundle.study_group.name}
```

```python
    group = _group(session)
    if group is not None:
        row["group"] = group
```

- [ ] **Step 6: Run the tests to see them pass, and the list suites unchanged**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_reads.py etqan/scheduling/tests/test_api_bundle_labels.py etqan/scheduling/tests/test_api_subscriptions.py etqan/scheduling/tests/test_api_sessions.py etqan/scheduling/tests/test_api_archive_lists.py`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/scheduling/services/bundle_reads.py etqan/scheduling/services/rules.py etqan/scheduling/services/__init__.py etqan/scheduling/api/payloads.py etqan/scheduling/api/views.py etqan/scheduling/tests/test_bundles_reads.py etqan/scheduling/tests/test_api_bundle_labels.py
git -C $W/backend commit -m "feat(scheduling): read bundles; members name their bundle, group sessions their group (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 10: The study group routes, the `study_group` codes and the route table

**Files:**
- Modify: `backend/etqan/access/registry.py` (`study_group` under `# ── phase B2 ──`, after B2e's `teacher_schedule`)
- Modify: `backend/etqan/scheduling/api/serializers.py` (`GroupInput`, `GroupFilterInput`, `GroupCandidatesInput`)
- Create: `backend/etqan/scheduling/api/bundle_payloads.py` (`group_row`)
- Create: `backend/etqan/scheduling/api/group_views.py`
- Modify: `backend/etqan/scheduling/api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`, `FEATURE_WORDS`)
- Test: `backend/etqan/scheduling/tests/test_api_groups.py`

**Interfaces:**
- Consumes: Task 3's services; `OfficeOr404` (B2c), `HasCode`, `FeatureOn`.
- Produces: routes `GET/POST groups/` (`study_group.view_any` / `study_group.create`; list paginated, `?q=&is_active=true|false`), `GET groups/candidates/?q=&group=<id>` (`study_group.create` or `study_group.update`; `[{id, full_name}]`), `GET/PATCH/DELETE groups/<id>/` (`study_group.view` / `.update` / `.delete`), all with feature `study_groups`. Group payload `{id, name, notes, is_active, members: [{id, full_name, is_active}], can_delete, created_at}` (`members[].id` is the User id).

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_api_groups.py`)

```python
"""Slice B2f §5-§6: the study group routes, who reaches them, their answers."""

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context

from etqan.scheduling import services
from etqan.scheduling.models import StudyGroup
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_group
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
GROUPS = "/api/v1/groups/"


@pytest.fixture
def office():
    return as_user(make_admin())


@pytest.fixture
def groups_on(set_features):
    set_features(study_groups=True)


def test_the_office_keeps_a_group(world, office, groups_on):
    sister = make_student("Aisha")
    created = office.post(
        GROUPS,
        {"name": "Evening", "student_ids": [world.student.id, sister.id]},
        format="json",
    )
    assert created.status_code == 201
    data = created.json()
    assert (data["name"], data["is_active"], data["notes"], data["can_delete"]) == (
        "Evening",
        True,
        "",
        True,
    )
    assert data["members"] == [
        {"id": sister.id, "full_name": "Aisha", "is_active": True},
        {"id": world.student.id, "full_name": "Yusuf", "is_active": True},
    ]
    pk = data["id"]
    patched = office.patch(
        f"{GROUPS}{pk}/",
        {"student_ids": [sister.id], "notes": "Tuesdays"},
        format="json",
    )
    assert [m["id"] for m in patched.json()["members"]] == [sister.id]
    assert office.get(f"{GROUPS}{pk}/").json()["notes"] == "Tuesdays"
    assert office.delete(f"{GROUPS}{pk}/").status_code == 204
    assert not StudyGroup.objects.exists()


def test_refusals_name_their_field_or_rule(world, office, groups_on):
    group = make_group(world.student)
    taken = office.post(
        GROUPS, {"name": "Morning", "student_ids": [world.student.id]}, format="json"
    )
    assert taken.status_code == 400
    assert "Yusuf" in taken.json()["student_ids"][0]
    SubscriptionBundle.objects.create(kind="group", study_group=group)
    in_use = office.delete(f"{GROUPS}{group.pk}/")
    assert (in_use.status_code, in_use.json()["code"]) == (
        409,
        "scheduling.group_in_use",
    )
    assert office.get(GROUPS).json()["results"][0]["can_delete"] is False


def test_the_list_searches_and_filters(world, office, groups_on):
    make_group(world.student, name="Evening")
    late = make_group(make_student("Aisha"), name="Late")
    services.update_group(late, fields={"is_active": False})

    def names(**params):
        return [g["name"] for g in office.get(GROUPS, params).json()["results"]]

    assert names() == ["Evening", "Late"]
    assert names(q="eve") == ["Evening"]
    assert names(is_active="false") == ["Late"]
    assert office.get(GROUPS, {"is_active": "maybe"}).status_code == 400


def test_candidates_come_from_the_server(world, office, groups_on):
    group = make_group(world.student)
    make_student("Aisha")
    found = office.get(f"{GROUPS}candidates/", {"q": "a"}).json()
    assert [c["full_name"] for c in found] == ["Aisha"]
    mine = office.get(f"{GROUPS}candidates/", {"group": group.pk}).json()
    assert [c["full_name"] for c in mine] == ["Aisha", "Yusuf"]


def test_the_list_costs_the_same_for_one_or_three(world, office, groups_on):
    def selects() -> int:
        with CaptureQueriesContext(connection) as ctx:
            assert office.get(GROUPS).status_code == 200
        return sum(
            q["sql"].lstrip().upper().startswith("SELECT") for q in ctx.captured_queries
        )

    make_group(world.student)
    one = selects()
    make_group(make_student("Aisha"), make_student("Huda"), name="Late")
    make_group(make_student("Zaid"), name="Early")
    assert selects() == one


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_everyone_but_the_office_gets_404(world, api_for, groups_on, role):
    group = make_group(world.student)
    client = api_for(role)
    for path in (GROUPS, f"{GROUPS}{group.pk}/", f"{GROUPS}candidates/"):
        assert client.get(path).status_code == 404


def test_another_academys_group_is_out_of_reach(world, office, groups_on, tenants):
    make_group(world.student)
    ceiling = StudyGroup.objects.aggregate(m=Max("pk"))["m"] or 0
    with tenant_context(tenants.other):
        theirs = until_pk_exceeds(
            StudyGroup, ceiling, lambda: StudyGroup.objects.create(name="Theirs")
        )
    assert office.get(f"{GROUPS}{theirs.pk}/").status_code == 404
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_groups.py`
Expected: FAIL — 404 `Not found.` on every route (no URL).

- [ ] **Step 3: The access resource** (`backend/etqan/access/registry.py`, under `# ── phase B2 ──`, after `teacher_schedule`)

```python
    # Slice B2f (§5): TutorHamster's `group`.
    Resource(
        "study_group",
        "Study groups",
        "المجموعات الدراسية",
        (*EDIT, "delete"),
    ),
```

- [ ] **Step 4: Bodies, payload, views, routes**

`backend/etqan/scheduling/api/serializers.py`:

```python
class GroupInput(serializers.Serializer):
    """Slice B2f §4.1. The service checks the name and the students."""

    name = serializers.CharField(allow_blank=True)
    student_ids = serializers.ListField(child=_id(), max_length=500)
    notes = serializers.CharField(required=False, allow_blank=True)
    is_active = serializers.BooleanField(required=False)


class GroupFilterInput(serializers.Serializer):
    q = serializers.CharField(required=False, allow_blank=True)
    # A ChoiceField: an absent BooleanField reads as False from a query string.
    is_active = serializers.ChoiceField(choices=("true", "false"), required=False)


class GroupCandidatesInput(serializers.Serializer):
    q = serializers.CharField(required=False, allow_blank=True)
    group = _id(required=False)
```

`backend/etqan/scheduling/api/bundle_payloads.py`:

```python
"""Slice B2f: JSON shapes for study groups and bundles. Derived values come
from `services.bundle_view`; these functions only arrange them."""


def group_row(group) -> dict:
    """A group from `services.groups_queryset` (members prefetched)."""
    return {
        "id": group.pk,
        "name": group.name,
        "notes": group.notes,
        "is_active": group.is_active,
        "members": [
            {
                "id": member.student.user_id,
                "full_name": member.student.user.full_name,
                "is_active": member.student.user.is_active,
            }
            for member in group.members.all()
        ],
        # Plan D11: the server's rule for the Delete button.
        "can_delete": not group.in_use,
        "created_at": group.created_at,
    }
```

`backend/etqan/scheduling/api/group_views.py`:

```python
"""Slice B2f §5-§6: study groups. The office only: everyone else gets 404,
before the code check (§5); a switched-off `study_groups` answers 404 after
it."""

from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.scheduling import services
from etqan.scheduling.api import bundle_payloads
from etqan.scheduling.api.activity_views import OfficeOr404
from etqan.scheduling.api.serializers import GroupCandidatesInput
from etqan.scheduling.api.serializers import GroupFilterInput
from etqan.scheduling.api.serializers import GroupInput

OFFICE_ONLY = (OfficeOr404, HasCode, FeatureOn)
FEATURE = "study_groups"


def group_or_404(pk):
    return get_object_or_404(services.groups_queryset(), pk=pk)


def _answer(pk, *, code=status.HTTP_200_OK) -> Response:
    group = services.groups_queryset().get(pk=pk)
    return Response(bundle_payloads.group_row(group), status=code)


class GroupListView(generics.GenericAPIView):
    permission_classes = OFFICE_ONLY
    permission_codes = {"GET": "study_group.view_any", "POST": "study_group.create"}
    feature = FEATURE

    def get(self, request):
        query = GroupFilterInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        groups = services.filter_groups(
            services.groups_queryset(), **query.validated_data
        )
        page = self.paginate_queryset(groups)
        return self.get_paginated_response(
            [bundle_payloads.group_row(group) for group in page]
        )

    def post(self, request):
        body = GroupInput(data=request.data)
        body.is_valid(raise_exception=True)
        group = services.create_group(**body.validated_data)
        return _answer(group.pk, code=status.HTTP_201_CREATED)


class GroupCandidatesView(APIView):
    """Plan D13: who may join a new group, or ``group``."""

    permission_classes = OFFICE_ONLY
    permission_codes = {"GET": ("study_group.create", "study_group.update")}
    feature = FEATURE

    def get(self, request):
        query = GroupCandidatesInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        data = query.validated_data
        group = None
        if "group" in data:
            group = services.groups_queryset().filter(pk=data["group"]).first()
        found = services.group_candidates(q=data.get("q", ""), group=group)
        return Response([{"id": u.pk, "full_name": u.full_name} for u in found])


class GroupDetailView(APIView):
    permission_classes = OFFICE_ONLY
    permission_codes = {
        "GET": "study_group.view",
        "PATCH": "study_group.update",
        "DELETE": "study_group.delete",
    }
    feature = FEATURE

    def get(self, request, pk):
        return _answer(group_or_404(pk).pk)

    def patch(self, request, pk):
        group = group_or_404(pk)
        body = GroupInput(data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        services.update_group(group, fields=dict(body.validated_data))
        return _answer(pk)

    def delete(self, request, pk):
        services.delete_group(group_or_404(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)
```

`backend/etqan/scheduling/api/urls.py` — `from etqan.scheduling.api import group_views`, then after B2e's routes:

```python
    # Slice B2f (spec §6).
    path("groups/", group_views.GroupListView.as_view(), name="group-list"),
    path(
        "groups/candidates/",
        group_views.GroupCandidatesView.as_view(),
        name="group-candidates",
    ),
    path("groups/<int:pk>/", group_views.GroupDetailView.as_view(), name="group-detail"),
```

- [ ] **Step 5: The route table** (`backend/etqan/access/tests/test_routes.py`; insert, never replace)

In `ROUTES`, after B2e's lines:

```python
    # Slice B2f.
    ("GET", "/api/v1/groups/", "study_group.view_any"),
    ("POST", "/api/v1/groups/", "study_group.create"),
    (
        "GET",
        "/api/v1/groups/candidates/",
        ("study_group.create", "study_group.update"),
    ),
    ("GET", f"/api/v1/groups/{N}/", "study_group.view"),
    ("PATCH", f"/api/v1/groups/{N}/", "study_group.update"),
    ("DELETE", f"/api/v1/groups/{N}/", "study_group.delete"),
```

In `FEATURES`, after B2e's entries:

```python
    # Slice B2f.
    **dict.fromkeys(
        (
            ("GET", "/api/v1/groups/"),
            ("POST", "/api/v1/groups/"),
            ("GET", "/api/v1/groups/candidates/"),
            ("GET", f"/api/v1/groups/{N}/"),
            ("PATCH", f"/api/v1/groups/{N}/"),
            ("DELETE", f"/api/v1/groups/{N}/"),
        ),
        "study_groups",
    ),
```

In `FEATURE_WORDS`, after B2e's: `"/groups/": "study_groups",` under `# Slice B2f.`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_groups.py etqan/access`
Expected: PASS (the route table's coverage, code, feature and registry tests included).

- [ ] **Step 7: Commit**

```bash
git -C $W/backend add etqan/access/registry.py etqan/access/tests/test_routes.py etqan/scheduling/api/serializers.py etqan/scheduling/api/bundle_payloads.py etqan/scheduling/api/group_views.py etqan/scheduling/api/urls.py etqan/scheduling/tests/test_api_groups.py
git -C $W/backend commit -m "feat(scheduling): study group routes, office only, and their codes (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 11: The bundle routes — one create route per kind, the shared ungated ones, billing per member

**Files:**
- Modify: `backend/etqan/scheduling/api/serializers.py` (bundle bodies and query)
- Modify: `backend/etqan/scheduling/api/bundle_payloads.py` (`bundle_row`, `bundle_detail`, `roster_row`, `conflict_rows`)
- Modify: `backend/etqan/scheduling/api/views.py` (`supervisor_field`, a public name for `_supervisor_field`)
- Create: `backend/etqan/scheduling/api/bundle_views.py`
- Modify: `backend/etqan/scheduling/api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py` (`ROUTES`, `FEATURES`, `FEATURE_WORDS`, `UNGATED` and its test)
- Test: `backend/etqan/scheduling/tests/test_api_bundles.py`

**Interfaces:**
- Consumes: Tasks 6-9's services; `billing_services.invoice_subscription(pk, *, by)`; `payloads.subscription_rows`, `payloads.session_row`, `payloads.shows_supervision`.
- Produces: routes (§6) — `POST bundles/multi-course/` (feature `multi_course_subscriptions`), `POST bundles/family/` (`family_subscriptions`), `POST bundles/group/` (`group_subscriptions`): `subscription.create`, 201 = bundle detail + `conflicts` (plan D12). Ungated: `GET bundles/` (`subscription.view_any`; `?kind=&student=&family=&group=&state=`), `GET/PATCH/DELETE bundles/<id>/` (`subscription.view` / `.update` / `.update`; PATCH `{notes}`; DELETE dissolves, 204), `POST bundles/<id>/renew/` (`{starts_on?}`), `pause/` (`{from_date, to_date, reason?}`), `cancel/`, `POST bundles/<id>/members/` (`{student_id, starts_on}`, 201), `DELETE bundles/<id>/members/<student_id>/` — all `subscription.update`, answering the bundle detail. `POST/DELETE bundles/<id>/archive/` (`subscription.delete` / `subscription.restore`, feature `subscription_archive`). Bundle detail: `{id, kind, student, family, study_group, notes, state, created_by, created_at, members: [subscription row + current, freeze_days_left], totals: {sessions_total, prices: [{currency, price_minor}]}, roster: [{student: {id, full_name}, subscription_id, course, teacher, status, attended, can_remove}], can_renew, can_pause, can_cancel, can_add_member, can_archive?, can_restore?}`. List row: `{id, kind, student, family, study_group, notes, members_count, state, created_at}`.

- [ ] **Step 1: Write the failing tests** (`backend/etqan/scheduling/tests/test_api_bundles.py`)

```python
"""Slice B2f §5-§6: the bundle routes — per-kind creates behind their
switches, the shared routes ungated (FT-4), billing per member (P6-1), member
refusals named (§4.6), office only."""

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context

from etqan.platform.permissions import FEATURE_OFF
from etqan.scheduling import services
from etqan.scheduling.models import Subscription
from etqan.scheduling.models import SubscriptionBundle
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import build_world
from etqan.scheduling.tests.conftest import deactivated
from etqan.scheduling.tests.conftest import group_bundle
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_family
from etqan.scheduling.tests.conftest import make_group
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import member_of
from etqan.scheduling.tests.conftest import multi_bundle
from etqan.scheduling.tests.conftest import other_course
from etqan.scheduling.tests.conftest import row
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
BUNDLES = "/api/v1/bundles/"
SLOTS = [{"weekdays": [0, 2], "start_time": "18:00"}]


@pytest.fixture
def office():
    return as_user(make_admin())


def invoices_of(office, subscription_id) -> list[dict]:
    return office.get(
        "/api/v1/billing/invoices/", {"subscription": subscription_id}
    ).json()["results"]


def multi_body(world, **overrides) -> dict:
    return {
        "student_id": world.student.id,
        "starts_on": "2026-06-01",
        "rows": [
            row(world, slots=SLOTS),
            row(world, other_course(world), price_minor=90000),
        ],
        "notes": "Two subjects",
        **overrides,
    }


# ── Create ───────────────────────────────────────────────────────────────────


def test_a_multi_course_bundle_is_created_and_each_member_invoiced(
    world, office, bundles_on
):
    response = office.post(f"{BUNDLES}multi-course/", multi_body(world), format="json")
    assert response.status_code == 201
    data = response.json()
    assert (data["kind"], data["notes"], data["state"], data["conflicts"]) == (
        "multi_course",
        "Two subjects",
        "live",
        [],
    )
    assert data["student"] == {"id": world.student.id, "full_name": "Yusuf"}
    assert (data["family"], data["study_group"]) == (None, None)
    assert [m["current"] for m in data["members"]] == [True, True]
    assert data["totals"] == {
        "sessions_total": sum(m["sessions_total"] for m in data["members"]),
        "prices": [{"currency": "EGP", "price_minor": 240000}],
    }
    for member in data["members"]:
        (invoice,) = invoices_of(office, member["id"])
        assert invoice["amount_minor"] == member["price_minor"]


def test_a_rows_refusal_is_its_rows_field_and_nothing_is_kept(
    world, office, bundles_on
):
    body = multi_body(world)
    body["rows"][1]["package"] = 999999
    response = office.post(f"{BUNDLES}multi-course/", body, format="json")
    assert (response.status_code, response.json()) == (
        400,
        {"rows.1.package": ["Choose an active package."]},
    )
    assert not SubscriptionBundle.objects.exists()
    malformed = office.post(f"{BUNDLES}multi-course/", {"rows": [{}]}, format="json")
    assert malformed.status_code == 400
    assert "student_id" in malformed.json()


def test_a_family_bundle_needs_families_on(world, office, set_features):
    sister = make_student("Aisha")
    family = make_family(world.student, sister)
    body = {
        "family_id": family.pk,
        "starts_on": "2026-06-01",
        "rows": [row(world, student=world.student.id), row(world, student=sister.id)],
    }
    set_features(family_subscriptions=True, families=False)
    off = office.post(f"{BUNDLES}family/", body, format="json")
    assert (off.status_code, off.json()) == (404, {"detail": FEATURE_OFF})
    set_features(family_subscriptions=True, families=True)
    created = office.post(f"{BUNDLES}family/", body, format="json")
    assert created.status_code == 201
    assert created.json()["family"] == {"id": family.pk, "name": "Omar family"}


def test_a_group_bundle_has_one_member_per_student_and_no_clash(
    world, office, bundles_on
):
    sister = make_student("Aisha")
    group = make_group(world.student, sister)
    response = office.post(
        f"{BUNDLES}group/",
        {"group_id": group.pk, "starts_on": "2026-06-01", "rows": [row(world, slots=SLOTS)]},
        format="json",
    )
    assert response.status_code == 201
    data = response.json()
    assert data["study_group"] == {"id": group.pk, "name": "Evening circle"}
    assert sorted(m["student"]["id"] for m in data["members"]) == sorted(
        [world.student.id, sister.id]
    )
    assert data["conflicts"] == []
    assert [r["student"]["full_name"] for r in data["roster"]] == ["Aisha", "Yusuf"]
    assert data["can_add_member"] is True


@pytest.mark.parametrize(
    ("path", "switch"),
    [
        ("multi-course/", "multi_course_subscriptions"),
        ("family/", "family_subscriptions"),
        ("group/", "group_subscriptions"),
    ],
)
def test_each_create_route_follows_its_own_switch(world, office, set_features, path, switch):
    set_features(study_groups=True, **{switch: False})
    response = office.post(f"{BUNDLES}{path}", {}, format="json")
    assert (response.status_code, response.json()) == (404, {"detail": FEATURE_OFF})


# ── The shared routes ────────────────────────────────────────────────────────


def test_the_shared_routes_work_with_every_bundle_switch_off(world, office):
    """F-11 / FT-4: a bundle made while a switch was on keeps working."""
    created = multi_bundle(world)
    pk = created.bundle.pk
    assert office.get(BUNDLES).json()["results"][0]["id"] == pk
    assert office.get(f"{BUNDLES}{pk}/").status_code == 200
    patched = office.patch(f"{BUNDLES}{pk}/", {"notes": "Evenings"}, format="json")
    assert patched.json()["notes"] == "Evenings"
    paused = office.post(
        f"{BUNDLES}{pk}/pause/",
        {"from_date": "2026-06-03", "to_date": "2026-06-04", "reason": "Trip"},
        format="json",
    )
    assert paused.status_code == 200
    assert [m["freeze_days_left"] for m in paused.json()["members"]] == [8, 8]
    renewed = office.post(f"{BUNDLES}{pk}/renew/", {}, format="json")
    assert renewed.status_code == 200
    renewals = Subscription.objects.filter(bundle_id=pk, renewed_from__isnull=False)
    assert renewals.count() == 2
    for renewal in renewals:
        assert len(invoices_of(office, renewal.pk)) == 1
    cancelled = office.post(f"{BUNDLES}{pk}/cancel/", {}, format="json")
    assert {m["status"] for m in cancelled.json()["members"]} == {"cancelled"}
    assert cancelled.json()["state"] == "ended"
    assert office.delete(f"{BUNDLES}{pk}/").status_code == 204
    assert Subscription.objects.filter(bundle__isnull=True).count() == 4


def test_a_members_refusal_carries_its_member(world, office):
    sister = make_student("Aisha")
    created = group_bundle(world, sister)
    deactivated(sister)
    response = office.post(f"{BUNDLES}{created.bundle.pk}/renew/", {}, format="json")
    assert response.status_code == 400
    assert response.json() == {
        "student": ["Choose an active student."],
        "member_id": member_of(created, sister).pk,
    }
    nothing = multi_bundle(world)
    services.cancel_bundle(nothing.bundle)
    refused = office.post(f"{BUNDLES}{nothing.bundle.pk}/renew/", {}, format="json")
    assert (refused.status_code, refused.json()["code"]) == (
        409,
        "scheduling.nothing_to_renew",
    )


def test_a_groups_students_are_added_invoiced_and_removed(world, office):
    created = group_bundle(world)
    pk = created.bundle.pk
    newcomer = make_student("Aisha")
    added = office.post(
        f"{BUNDLES}{pk}/members/",
        {"student_id": newcomer.id, "starts_on": "2026-06-08"},
        format="json",
    )
    assert added.status_code == 201
    joined = Subscription.objects.get(bundle_id=pk, student__user_id=newcomer.id)
    assert len(invoices_of(office, joined.pk)) == 1
    removed = office.delete(f"{BUNDLES}{pk}/members/{newcomer.id}/")
    assert removed.status_code == 200
    aisha = next(r for r in removed.json()["roster"] if r["student"]["id"] == newcomer.id)
    assert (aisha["status"], aisha["can_remove"]) == ("cancelled", False)


def test_archive_follows_the_archive_switch(world, office, set_features):
    created = multi_bundle(world)
    services.cancel_bundle(created.bundle)
    path = f"{BUNDLES}{created.bundle.pk}/archive/"
    off = office.post(path)
    assert (off.status_code, off.json()) == (404, {"detail": FEATURE_OFF})
    assert "can_archive" not in office.get(f"{BUNDLES}{created.bundle.pk}/").json()
    set_features(subscription_archive=True)
    archived = office.post(path)
    assert (archived.status_code, archived.json()["can_restore"]) == (200, True)
    restored = office.delete(path)
    assert (restored.status_code, restored.json()["can_archive"]) == (200, True)


def test_the_list_filters_and_costs_the_same_for_one_or_three(world, office):
    def selects() -> int:
        with CaptureQueriesContext(connection) as ctx:
            assert office.get(BUNDLES).status_code == 200
        return sum(
            q["sql"].lstrip().upper().startswith("SELECT") for q in ctx.captured_queries
        )

    group = group_bundle(world)
    one = selects()
    multi_bundle(world)
    multi_bundle(world)
    assert selects() == one
    rows = office.get(BUNDLES, {"kind": "group"}).json()["results"]
    assert [(r["id"], r["members_count"], r["state"]) for r in rows] == [
        (group.bundle.pk, 1, "live")
    ]
    assert rows[0]["study_group"] == {
        "id": group.bundle.study_group_id,
        "name": "Evening circle",
    }
    assert office.get(BUNDLES, {"state": "bogus"}).status_code == 400


def test_a_bundle_costs_the_same_for_two_or_four_members(world, office):
    def selects(pk) -> int:
        with CaptureQueriesContext(connection) as ctx:
            assert office.get(f"{BUNDLES}{pk}/").status_code == 200
        return sum(
            q["sql"].lstrip().upper().startswith("SELECT") for q in ctx.captured_queries
        )

    two = selects(multi_bundle(world).bundle.pk)
    four = group_bundle(world, make_student("Aisha"), make_student("Huda"), make_student("Zaid"))
    assert selects(four.bundle.pk) == two


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_everyone_but_the_office_gets_404(world, api_for, role):
    pk = multi_bundle(world).bundle.pk
    client = api_for(role)
    assert client.get(BUNDLES).status_code == 404
    assert client.get(f"{BUNDLES}{pk}/").status_code == 404
    assert client.post(f"{BUNDLES}{pk}/renew/", {}, format="json").status_code == 404


def test_another_academys_bundle_is_out_of_reach(world, office, tenants):
    multi_bundle(world)
    ceiling = SubscriptionBundle.objects.aggregate(m=Max("pk"))["m"] or 0
    with tenant_context(tenants.other):
        theirs = until_pk_exceeds(
            SubscriptionBundle, ceiling, lambda: multi_bundle(build_world()).bundle
        )
    assert office.get(f"{BUNDLES}{theirs.pk}/").status_code == 404
    assert office.post(f"{BUNDLES}{theirs.pk}/cancel/").status_code == 404
```

(In the other academy `build_world()` makes that academy's own teacher, course, package and student; `multi_bundle` takes any such world.)

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_bundles.py`
Expected: FAIL — 404 `Not found.` (no URLs).

- [ ] **Step 3: Bodies** (`backend/etqan/scheduling/api/serializers.py`; import `BUNDLE_KINDS` and `BUNDLE_STATES` from `etqan.scheduling.services`, one per line, beside `TRIAL_STATUSES`)

```python
class BundleRowInput(serializers.Serializer):
    """Slice B2f §4.2: a row has the subscription body's keys; a family row
    names its student (User id), other kinds ignore it."""

    student = _id(required=False)
    course = _id()
    teacher = _id()
    package = _id()
    price_minor = serializers.IntegerField(min_value=0, required=False)
    slots = SlotInput(many=True, required=False)


# Review M-2: a create body stays bounded (a family or a course list is short).
MAX_BUNDLE_ROWS = 20


class _BundleInput(serializers.Serializer):
    starts_on = serializers.DateField()
    rows = BundleRowInput(many=True, max_length=MAX_BUNDLE_ROWS)
    # Plan 12b: ignored while the academy's supervision is off.
    supervisor_id = _id(required=False, allow_null=True)
    notes = serializers.CharField(required=False, allow_blank=True)


class MultiCourseBundleInput(_BundleInput):
    student_id = _id()


class FamilyBundleInput(_BundleInput):
    family_id = _id()


class GroupBundleInput(_BundleInput):
    group_id = _id()


class BundleFilterInput(serializers.Serializer):
    kind = serializers.ChoiceField(choices=BUNDLE_KINDS, required=False)
    student = _id(required=False)
    family = _id(required=False)
    group = _id(required=False)
    state = serializers.ChoiceField(choices=BUNDLE_STATES, required=False)


class BundleRenewInput(serializers.Serializer):
    starts_on = serializers.DateField(required=False)


class BundleNotesInput(serializers.Serializer):
    notes = serializers.CharField(allow_blank=True)


class BundleMemberInput(serializers.Serializer):
    student_id = _id()
    starts_on = serializers.DateField()
```


- [ ] **Step 4: Payloads** (append to `backend/etqan/scheduling/api/bundle_payloads.py`)

```python
from etqan.scheduling.api import payloads


def _person(user) -> dict | None:
    return None if user is None else {"id": user.pk, "full_name": user.full_name}


def _owner(bundle) -> dict:
    """§4.5: the kind's owner; the other two are null."""
    student = bundle.student
    return {
        "student": None
        if student is None
        else {"id": student.user_id, "full_name": student.user.full_name},
        "family": None
        if bundle.family_id is None
        else {"id": bundle.family_id, "name": bundle.family.name},
        "study_group": None
        if bundle.study_group_id is None
        else {"id": bundle.study_group_id, "name": bundle.study_group.name},
    }


def _state(bundle) -> str:
    return "live" if bundle.is_live else "ended"


def bundle_row(bundle) -> dict:
    """A list row, from `services.bundles_queryset`."""
    return {
        "id": bundle.pk,
        "kind": bundle.kind,
        **_owner(bundle),
        "notes": bundle.notes,
        "members_count": bundle.members_count,
        "state": _state(bundle),
        "created_at": bundle.created_at,
    }


def roster_row(row) -> dict:
    member = row.member
    return {
        "student": {
            "id": member.student.user_id,
            "full_name": member.student.user.full_name,
        },
        "subscription_id": member.pk,
        "course": {
            "id": member.course_id,
            "name_ar": member.course.name_ar,
            "name_en": member.course.name_en,
        },
        "teacher": {"id": member.teacher.user_id, "full_name": member.teacher.user.full_name},
        "status": member.status,
        "attended": row.attended,
        "can_remove": row.can_remove,
    }


def bundle_detail(view, *, viewer) -> dict:
    """§4.5 and plan D11/D16: the bundle, its members (subscription rows with
    `current` and `freeze_days_left`), totals, roster and flags."""
    bundle = view.bundle
    rows = payloads.subscription_rows(
        view.members, is_admin=True, supervision=payloads.shows_supervision(viewer)
    )
    body = {
        "id": bundle.pk,
        "kind": bundle.kind,
        **_owner(bundle),
        "notes": bundle.notes,
        "state": _state(bundle),
        "created_by": _person(bundle.created_by),
        "created_at": bundle.created_at,
        "members": [
            {
                **row,
                "current": member.pk in view.current,
                "freeze_days_left": view.freeze_days_left[member.pk],
            }
            for member, row in zip(view.members, rows, strict=True)
        ],
        "totals": {
            "sessions_total": view.sessions_total,
            "prices": [
                {"currency": currency, "price_minor": amount}
                for currency, amount in view.prices
            ],
        },
        "roster": [roster_row(row) for row in view.roster],
        "can_renew": view.can_renew,
        "can_pause": view.can_pause,
        "can_cancel": view.can_cancel,
        "can_add_member": view.can_add_member,
    }
    if view.can_archive is not None:
        body["can_archive"] = view.can_archive
        body["can_restore"] = view.can_restore
    return body


def conflict_rows(conflicts, *, viewer) -> list[dict]:
    """§4.2 step 4: the members' new sessions' clashes (P4-9)."""
    shown = payloads.shows_supervision(viewer)
    return [
        {
            "session": payloads.session_row(s, viewer=viewer, supervision=shown),
            "other": payloads.session_row(o, viewer=viewer, supervision=shown),
        }
        for s, o in conflicts
    ]
```

(Put the `from etqan.scheduling.api import payloads` import at the top of the file with the module docstring.)

- [ ] **Step 5: Views and routes**

`backend/etqan/scheduling/api/views.py` — after `_supervisor_field`:

```python
# Slice B2f: the bundle create views read `supervisor_id` the same way.
supervisor_field = _supervisor_field
```

`backend/etqan/scheduling/api/bundle_views.py`:

```python
"""Slice B2f §5-§6: subscription bundles. The office only: everyone else gets
404, before the code check (§5). One create route per kind, each behind its
own switch (B2a A-13); the shared routes are ungated, so a bundle made while a
switch was on keeps working (F-11, FT-4); archive follows the archive switch.
Every created, renewed or added member is invoiced here, in the same
transaction (P6-1)."""

from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.billing import services as billing_services
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.scheduling import services
from etqan.scheduling.api import bundle_payloads
from etqan.scheduling.api.activity_views import OfficeOr404
from etqan.scheduling.api.serializers import BundleFilterInput
from etqan.scheduling.api.serializers import BundleMemberInput
from etqan.scheduling.api.serializers import BundleNotesInput
from etqan.scheduling.api.serializers import BundleRenewInput
from etqan.scheduling.api.serializers import FamilyBundleInput
from etqan.scheduling.api.serializers import GroupBundleInput
from etqan.scheduling.api.serializers import MultiCourseBundleInput
from etqan.scheduling.api.serializers import PauseInput
from etqan.scheduling.api.views import supervisor_field

OFFICE = (OfficeOr404, HasCode, FeatureOn)


def bundle_or_404(pk):
    return get_object_or_404(services.bundles_queryset(), pk=pk)


def answer(request, pk, *, code=status.HTTP_200_OK, conflicts=None) -> Response:
    view = services.bundle_view(services.bundles_queryset().get(pk=pk))
    body = bundle_payloads.bundle_detail(view, viewer=request.user)
    if conflicts is not None:
        body["conflicts"] = bundle_payloads.conflict_rows(conflicts, viewer=request.user)
    return Response(body, status=code)


def _invoice(subscriptions, by) -> None:
    for subscription in subscriptions:
        billing_services.invoice_subscription(subscription.pk, by=by)


class _BundleCreateView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "subscription.create"}
    kind = ""
    body = None

    def post(self, request):
        body = self.body(data=request.data)
        body.is_valid(raise_exception=True)
        data = dict(body.validated_data)
        data.update(supervisor_field(data))
        with transaction.atomic():
            created = services.create_bundle(self.kind, request.user, **data)
            _invoice(created.members, request.user)
        return answer(
            request,
            created.bundle.pk,
            code=status.HTTP_201_CREATED,
            conflicts=created.conflicts,
        )


class MultiCourseBundleView(_BundleCreateView):
    kind = "multi_course"
    feature = "multi_course_subscriptions"
    body = MultiCourseBundleInput


class FamilyBundleView(_BundleCreateView):
    kind = "family"
    feature = "family_subscriptions"
    body = FamilyBundleInput


class GroupBundleView(_BundleCreateView):
    kind = "group"
    feature = "group_subscriptions"
    body = GroupBundleInput


class BundleListView(generics.GenericAPIView):
    permission_classes = OFFICE
    permission_codes = {"GET": "subscription.view_any"}

    def get(self, request):
        query = BundleFilterInput(data=request.query_params)
        query.is_valid(raise_exception=True)
        bundles = services.filter_bundles(
            services.bundles_queryset(), **query.validated_data
        )
        page = self.paginate_queryset(bundles)
        return self.get_paginated_response(
            [bundle_payloads.bundle_row(bundle) for bundle in page]
        )


class BundleDetailView(APIView):
    permission_classes = OFFICE
    permission_codes = {
        "GET": "subscription.view",
        "PATCH": "subscription.update",
        "DELETE": "subscription.update",
    }

    def get(self, request, pk):
        return answer(request, bundle_or_404(pk).pk)

    def patch(self, request, pk):
        bundle = bundle_or_404(pk)
        body = BundleNotesInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.update_bundle(bundle, **body.validated_data)
        return answer(request, pk)

    def delete(self, request, pk):
        services.dissolve_bundle(bundle_or_404(pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class BundleRenewView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "subscription.update"}

    def post(self, request, pk):
        bundle = bundle_or_404(pk)
        body = BundleRenewInput(data=request.data)
        body.is_valid(raise_exception=True)
        with transaction.atomic():
            renewals = services.renew_bundle(
                bundle, by=request.user, **body.validated_data
            )
            _invoice(renewals, request.user)
        return answer(request, pk)


class BundlePauseView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "subscription.update"}

    def post(self, request, pk):
        bundle = bundle_or_404(pk)
        body = PauseInput(data=request.data)
        body.is_valid(raise_exception=True)
        services.pause_bundle(bundle, **body.validated_data)
        return answer(request, pk)


class BundleCancelView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "subscription.update"}

    def post(self, request, pk):
        services.cancel_bundle(bundle_or_404(pk))
        return answer(request, pk)


class BundleArchiveView(APIView):
    """POST archives every member — `subscription.delete`; DELETE restores
    them — `subscription.restore` (plan D6)."""

    permission_classes = OFFICE
    permission_codes = {
        "POST": "subscription.delete",
        "DELETE": "subscription.restore",
    }
    feature = "subscription_archive"

    def post(self, request, pk):
        services.archive_bundle(bundle_or_404(pk), by=request.user)
        return answer(request, pk)

    def delete(self, request, pk):
        services.restore_bundle(bundle_or_404(pk), by=request.user)
        return answer(request, pk)


class BundleMembersView(APIView):
    permission_classes = OFFICE
    permission_codes = {"POST": "subscription.update"}

    def post(self, request, pk):
        bundle = bundle_or_404(pk)
        body = BundleMemberInput(data=request.data)
        body.is_valid(raise_exception=True)
        with transaction.atomic():
            joined = services.add_to_group_bundle(bundle, **body.validated_data)
            _invoice([joined], request.user)
        return answer(request, pk, code=status.HTTP_201_CREATED)


class BundleMemberView(APIView):
    permission_classes = OFFICE
    permission_codes = {"DELETE": "subscription.update"}

    def delete(self, request, pk, student_id):
        services.remove_from_group_bundle(bundle_or_404(pk), student_id=student_id)
        return answer(request, pk)
```

`backend/etqan/scheduling/api/urls.py` — `from etqan.scheduling.api import bundle_views`, then after the group routes:

```python
    path(
        "bundles/multi-course/",
        bundle_views.MultiCourseBundleView.as_view(),
        name="bundle-multi-course",
    ),
    path("bundles/family/", bundle_views.FamilyBundleView.as_view(), name="bundle-family"),
    path("bundles/group/", bundle_views.GroupBundleView.as_view(), name="bundle-group"),
    path("bundles/", bundle_views.BundleListView.as_view(), name="bundle-list"),
    path(
        "bundles/<int:pk>/", bundle_views.BundleDetailView.as_view(), name="bundle-detail"
    ),
    path(
        "bundles/<int:pk>/renew/",
        bundle_views.BundleRenewView.as_view(),
        name="bundle-renew",
    ),
    path(
        "bundles/<int:pk>/pause/",
        bundle_views.BundlePauseView.as_view(),
        name="bundle-pause",
    ),
    path(
        "bundles/<int:pk>/cancel/",
        bundle_views.BundleCancelView.as_view(),
        name="bundle-cancel",
    ),
    path(
        "bundles/<int:pk>/archive/",
        bundle_views.BundleArchiveView.as_view(),
        name="bundle-archive",
    ),
    path(
        "bundles/<int:pk>/members/",
        bundle_views.BundleMembersView.as_view(),
        name="bundle-members",
    ),
    path(
        "bundles/<int:pk>/members/<int:student_id>/",
        bundle_views.BundleMemberView.as_view(),
        name="bundle-member",
    ),
```

- [ ] **Step 6: The route table** (`backend/etqan/access/tests/test_routes.py`; insert, never replace)

`ROUTES`, under `# Slice B2f.` after the group lines:

```python
    ("POST", "/api/v1/bundles/multi-course/", "subscription.create"),
    ("POST", "/api/v1/bundles/family/", "subscription.create"),
    ("POST", "/api/v1/bundles/group/", "subscription.create"),
    ("GET", "/api/v1/bundles/", "subscription.view_any"),
    ("GET", f"/api/v1/bundles/{N}/", "subscription.view"),
    ("PATCH", f"/api/v1/bundles/{N}/", "subscription.update"),
    ("DELETE", f"/api/v1/bundles/{N}/", "subscription.update"),
    ("POST", f"/api/v1/bundles/{N}/renew/", "subscription.update"),
    ("POST", f"/api/v1/bundles/{N}/pause/", "subscription.update"),
    ("POST", f"/api/v1/bundles/{N}/cancel/", "subscription.update"),
    ("POST", f"/api/v1/bundles/{N}/archive/", "subscription.delete"),
    ("DELETE", f"/api/v1/bundles/{N}/archive/", "subscription.restore"),
    ("POST", f"/api/v1/bundles/{N}/members/", "subscription.update"),
    ("DELETE", f"/api/v1/bundles/{N}/members/{N}/", "subscription.update"),
```

`FEATURES`, under the group block:

```python
    ("POST", "/api/v1/bundles/multi-course/"): "multi_course_subscriptions",
    ("POST", "/api/v1/bundles/family/"): "family_subscriptions",
    ("POST", "/api/v1/bundles/group/"): "group_subscriptions",
    ("POST", f"/api/v1/bundles/{N}/archive/"): "subscription_archive",
    ("DELETE", f"/api/v1/bundles/{N}/archive/"): "subscription_archive",
```

`FEATURE_WORDS`, under `# Slice B2f.`:

```python
    "/bundles/multi-course/": "multi_course_subscriptions",
    "/bundles/family/": "family_subscriptions",
    "/bundles/group/": "group_subscriptions",
```

After `FEATURE_WORDS`, the new set and its test:

```python
# Slice B2f (spec F-11): the shared bundle routes declare no feature on
# purpose — a bundle made while a switch was on keeps working (FT-4).
UNGATED = {
    ("GET", "/api/v1/bundles/"),
    ("GET", f"/api/v1/bundles/{N}/"),
    ("PATCH", f"/api/v1/bundles/{N}/"),
    ("DELETE", f"/api/v1/bundles/{N}/"),
    ("POST", f"/api/v1/bundles/{N}/renew/"),
    ("POST", f"/api/v1/bundles/{N}/pause/"),
    ("POST", f"/api/v1/bundles/{N}/cancel/"),
    ("POST", f"/api/v1/bundles/{N}/members/"),
    ("DELETE", f"/api/v1/bundles/{N}/members/{N}/"),
}
```

```python
def test_every_bundle_route_is_gated_or_listed_as_ungated():
    """Slice B2f F-11: a new /bundles/ route must say which it is."""
    bundles = {(m, p) for m, p, _ in ROUTES if "/bundles/" in p}
    assert set(FEATURES).isdisjoint(UNGATED)
    assert {key for key in bundles if key not in FEATURES} == UNGATED
    for method, path in UNGATED:
        assert _declared_feature(method, path) == (None, True)
```

(`_declared_feature` returns `(feature, FeatureOn in permission_classes)`: ungated views still list `FeatureOn`, which then passes.)

- [ ] **Step 7: Run the tests to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_api_bundles.py etqan/access`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git -C $W/backend add etqan/scheduling/api/serializers.py etqan/scheduling/api/bundle_payloads.py etqan/scheduling/api/views.py etqan/scheduling/api/bundle_views.py etqan/scheduling/api/urls.py etqan/access/tests/test_routes.py etqan/scheduling/tests/test_api_bundles.py
git -C $W/backend commit -m "feat(scheduling): bundle routes — per-kind creates, shared actions, billing per member (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 12: Demo seeds — a study group with its group bundle, a multi-course and a family bundle

**Files:**
- Modify: `backend/etqan/tenants/seeds/b2.py` (`BUNDLES`, `seed_bundles`)
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (one call in the B2 block, after `b2.seed_trials`)
- Modify: `backend/etqan/tenants/tests/test_seed_b2.py` (one new test; its B2d archive test stays untouched — the seed never gives Aisha a Tajweed bundle member, plan D21), `test_seed_dev.py`, `test_seed_staging.py` (counts narrowed to non-bundle rows)

**Interfaces:**
- Consumes: `scheduling_services.create_group`, `create_bundle`, `has_bundles`, `today`; `identity_services.families_queryset`; `catalogue_services.find_course` / `find_package`; b2's `_person`.
- Produces: `b2.seed_bundles(subdomain)`, idempotent on "a bundle exists" (plan D21).

- [ ] **Step 1: Write the failing test** (append to `backend/etqan/tenants/tests/test_seed_b2.py`)

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_demo_gets_a_group_a_multi_course_and_a_family_bundle_once():
    call_command("seed_dev")
    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        assert all(
            features.enabled(code)
            for code in (
                "study_groups",
                "multi_course_subscriptions",
                "family_subscriptions",
                "group_subscriptions",
            )
        )
        bundles = {
            b.kind: b
            for b in scheduling_services.bundles_queryset()
        }
        assert sorted(bundles) == ["family", "group", "multi_course"]
        group = scheduling_services.bundle_view(bundles["group"])
        assert bundles["group"].study_group.name == "Evening Quran circle"
        assert sorted(m.student.user.full_name for m in group.members) == [
            "Aisha Omar",
            "Yusuf Omar",
            "Zaid Huda",
        ]
        assert {m.teacher.user.full_name for m in group.members} == {"Ustadha Maryam"}
        assert {m.course.name_en for m in group.members} == {"Quran Memorisation"}
        # Ledger D6: one row per student at each time of the class.
        times = {}
        for session in scheduling_services.sessions_queryset().filter(
            subscription__bundle=bundles["group"]
        ):
            times.setdefault(session.starts_at, set()).add(session.student_id)
        assert times
        assert all(len(students) == 3 for students in times.values())
        multi = scheduling_services.bundle_view(bundles["multi_course"])
        assert bundles["multi_course"].student.user.full_name == "Zaid Huda"
        assert sorted(m.course.name_en for m in multi.members) == [
            "Quran Memorisation",
            "Tajweed",
        ]
        family = scheduling_services.bundle_view(bundles["family"])
        assert bundles["family"].family.name == "Omar family"
        assert sorted(
            (m.student.user.full_name, m.course.name_en) for m in family.members
        ) == [("Aisha Omar", "Quran Memorisation"), ("Yusuf Omar", "Tajweed")]
        # Review I-1: B2d's archive seed keys on Aisha/Tajweed; no bundle adds one.
        aisha_tajweed = scheduling_services.subscriptions_queryset().filter(
            student__user__full_name="Aisha Omar", course__name_en="Tajweed"
        )
        assert not aisha_tajweed.filter(bundle__isnull=False).exists()
    with tenant_context(other):
        assert not scheduling_services.has_bundles()
```

`backend/etqan/tenants/tests/test_seed_dev.py` — in `test_seed_dev_adds_subscriptions_once`'s `seeded()`, add `.filter(bundle__isnull=True)  # slice B2f: the bundles' own` after the trial line; in `test_seed_dev_skips_a_subscription_whose_teacher_was_deactivated`, add next to the `seed_archives` patch:

```python
    # Slice B2f: the bundles' members are not among the four specs either,
    # and their seed would print its own skips once Maryam is inactive.
    monkeypatch.setattr(b2, "seed_bundles", lambda _subdomain: None)
```

`backend/etqan/tenants/tests/test_seed_staging.py` — `snapshot()`'s subscriptions filter becomes `.filter(archived_at__isnull=True, trial_request__isnull=True, bundle__isnull=True)` (comment: "Slice B2d / B2e / B2f: the everyday rows, not the archive's, the trial's or the bundles'").

- [ ] **Step 2: Run it to see it fail**

Run: `… exec -T django pytest -q etqan/tenants/tests/test_seed_b2.py -k bundle`
Expected: FAIL — `assert sorted(bundles) == [...]` (no bundle).

- [ ] **Step 3: Implement** (`backend/etqan/tenants/seeds/b2.py`, at the end)

```python
# Slice B2f (spec §8, plan D21): in demo, one study group of three students
# taught as one Quran Memorisation class, one multi-course bundle and one
# family bundle over the Omar family, all from today. No bundle gives Aisha
# Omar a Tajweed subscription: B2d's archive seed keys on that pair. Bundles are data the shared routes
# read whatever the switches say (demo has every built switch on anyway); no
# invoices (billing is the API's). Other academies get nothing.
MONTHLY = "Monthly, 2 a week"
BUNDLES = {
    "demo": {
        "group": {
            "name": "Evening Quran circle",
            "students": ("Yusuf Omar", "Aisha Omar", "Zaid Huda"),
            "rows": [
                {
                    "course": "Quran Memorisation",
                    "teacher": "Ustadha Maryam",
                    "package": MONTHLY,
                    "slots": [{"weekdays": [1, 3], "start_time": time(19, 0)}],
                }
            ],
        },
        "multi_course": {
            "student": "Zaid Huda",
            "rows": [
                {
                    "course": "Tajweed",
                    "teacher": "Ustadh Bilal",
                    "package": MONTHLY,
                    "slots": [{"weekdays": [5], "start_time": time(13, 0)}],
                },
                {
                    "course": "Quran Memorisation",
                    "teacher": "Ustadha Maryam",
                    "package": MONTHLY,
                    "slots": [{"weekdays": [5], "start_time": time(15, 0)}],
                },
            ],
        },
        "family": {
            "family": "Omar family",
            "rows": [
                {
                    "student": "Yusuf Omar",
                    "course": "Tajweed",
                    "teacher": "Ustadh Bilal",
                    "package": MONTHLY,
                    "slots": [{"weekdays": [5], "start_time": time(9, 0)}],
                },
                {
                    "student": "Aisha Omar",
                    "course": "Quran Memorisation",
                    "teacher": "Ustadha Maryam",
                    "package": MONTHLY,
                    "slots": [{"weekdays": [5], "start_time": time(11, 0)}],
                },
            ],
        },
    }
}


def _bundle_row(item: dict) -> dict | None:
    """A seeded row as the create body has it (ids), or None when a seeded
    record is missing."""
    found = {
        "course": catalogue_services.find_course(item["course"]),
        "teacher": _person("teacher", item["teacher"]),
        "package": catalogue_services.find_package(item["package"]),
    }
    if "student" in item:
        found["student"] = _person("student", item["student"])
    if None in found.values():
        return None
    return {**{key: value.pk for key, value in found.items()}, "slots": item["slots"]}


def _bundle_owner(kind: str, item: dict) -> dict | None:
    """The owner keyword ``create_bundle`` takes; a group is made here."""
    if kind == "multi_course":
        student = _person("student", item["student"])
        return None if student is None else {"student_id": student.pk}
    if kind == "family":
        family = (
            identity_services.families_queryset().filter(name=item["family"]).first()
        )
        return None if family is None else {"family_id": family.pk}
    students = [_person("student", name) for name in item["students"]]
    if None in students:
        return None
    group = scheduling_services.create_group(
        name=item["name"], student_ids=[s.pk for s in students]
    )
    return {"group_id": group.pk}


def seed_bundles(subdomain: str) -> None:
    """Idempotent: skipped once the academy has a bundle. Each bundle, its
    study group included, is one transaction: a refused one is printed and
    leaves nothing of it."""
    spec = BUNDLES.get(subdomain)
    if spec is None or scheduling_services.has_bundles():
        return
    for kind, item in spec.items():
        rows = [_bundle_row(row) for row in item["rows"]]
        # Checked before the transaction: a group is made inside it.
        if None in rows:
            print(f"skip: {kind} bundle — a seeded record was not found")  # noqa: T201
            continue
        try:
            with transaction.atomic():
                owner = _bundle_owner(kind, item)
                if owner is None:
                    print(f"skip: {kind} bundle — a seeded record was not found")  # noqa: T201
                    continue
                scheduling_services.create_bundle(
                    kind,
                    None,
                    starts_on=scheduling_services.today(),
                    rows=rows,
                    **owner,
                )
        except (ValidationError, ConflictError) as exc:
            print(f"skip: {kind} bundle — {exc}")  # noqa: T201
```

`backend/etqan/tenants/management/commands/seed_dev.py` — in the B2 block, after `b2.seed_trials(subdomain)`: `b2.seed_bundles(subdomain)`.

- [ ] **Step 4: Run the seed tests to see them pass**

Run: `… exec -T django pytest -q etqan/tenants`
Expected: PASS — `test_seed_b2.py::test_demo_gets_an_archived_subscription_and_a_session_archived_alone_once` included, unchanged.

- [ ] **Step 5: Commit**

```bash
git -C $W/backend add etqan/tenants/seeds/b2.py etqan/tenants/management/commands/seed_dev.py etqan/tenants/tests/test_seed_b2.py etqan/tenants/tests/test_seed_dev.py etqan/tenants/tests/test_seed_staging.py
git -C $W/backend commit -m "feat(seeds): demo study group and three bundles (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Then run the whole backend once (`… exec -T django pytest -q --cov=etqan`, `ruff check .`, `ruff format --check .`, `lint-imports`) and report the coverage figure: every existing suite must pass unchanged (spec §9).

---
### Task 13: Dashboard foundations — switches, types, routes, hooks, the refusal helper, fixtures and strings

**Files:**
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode` + 4)
- Modify: `dashboard/src/features/scheduling/schemas.ts` (`BundleRef`, `GroupLabel`; `Subscription.bundle?`, `Session.group?`)
- Create: `dashboard/src/features/scheduling/bundleSchemas.ts`, `bundleApi.ts`, `bundleQueries.ts`, `refusal.ts`
- Modify: `dashboard/src/features/scheduling/index.ts`
- Modify: `dashboard/src/test/scheduling-fixtures.ts` (`studyGroupRow`, `bundleMember`, `rosterRow`, `bundleDetail`)
- Create: `dashboard/src/locales/{en,ar}/bundles.json`, `studyGroups.json`
- Modify: `dashboard/src/locales/{en,ar}/errors.json` (`scheduling.group_in_use`, `scheduling.nothing_to_renew`)
- Create: `dashboard/src/routes/_authed/scheduling.bundles.$bundleId.tsx` (a minimal screen: its header only; Task 17 renders the page in it — review I-3, so Tasks 16 and 18 can type `/scheduling/bundles/$bundleId` links)
- Regenerate: `dashboard/src/routeTree.gen.ts`
- Test: `dashboard/src/features/scheduling/bundleApi.test.ts`, `refusal.test.ts`

**Interfaces:**
- Consumes: the API of Tasks 10-11.
- Produces: types `BundleRef {id, kind}`, `GroupLabel {bundle_id, name}` (in `schemas.ts`); in `bundleSchemas.ts`: `BUNDLE_KINDS`, `BundleKind`, `StudyGroup`, `StudyGroupMember`, `StudyGroupBody`, `StudyGroupPatch`, `BundleOwner`, `BundleRow`, `BundleMember`, `RosterRow`, `BundleConflict`, `BundleDetail`, `BundleRowBody`, `BundleCreateBody`; form schemas `studyGroupFormSchema` / `StudyGroupFormValues`, `bundleRowSchema` / `BundleRowValues`, `bundleFormSchema` / `BundleFormValues`. `bundleApi` (`groups`, `createGroup`, `updateGroup`, `deleteGroup`, `candidates`, `bundles`, `bundle`, `create`, `updateNotes`, `dissolve`, `renew`, `pause`, `cancel`, `archive`, `restore`, `addMember`, `removeMember`). Hooks `useStudyGroups(params, {enabled})`, `useGroupCandidates(q, groupId, enabled)`, `useBundle(id)` — all under `schedulingKey`, so `useSchedulingMutation` refreshes them. `memberIdOf(error) -> number | null`, `refusalText(error, bundle, t, localName) -> string`. Fixtures `studyGroupRow(o)`, `bundleMember(o)`, `rosterRow(o)`, `bundleDetail(o)`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/bundleApi.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { bundleApi } from "./bundleApi";

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
			put: vi.fn(ok),
			delete: vi.fn(ok),
		},
	};
});

describe("bundleApi", () => {
	beforeEach(() => vi.clearAllMocks());

	it("reads and writes study groups (slice B2f §6)", async () => {
		await bundleApi.groups({ q: "", is_active: "true", page: 1 });
		expect(api.get).toHaveBeenLastCalledWith("groups/", {
			params: { is_active: "true", page: "1" },
		});
		await bundleApi.candidates({ q: "ai", group: 4 });
		expect(api.get).toHaveBeenLastCalledWith("groups/candidates/", {
			params: { q: "ai", group: "4" },
		});
		await bundleApi.createGroup({ name: "Evening", student_ids: [11] });
		expect(api.post).toHaveBeenLastCalledWith("groups/", {
			name: "Evening",
			student_ids: [11],
		});
		await bundleApi.updateGroup({ id: 4, is_active: false });
		expect(api.patch).toHaveBeenLastCalledWith("groups/4/", {
			is_active: false,
		});
		await bundleApi.deleteGroup(4);
		expect(api.delete).toHaveBeenLastCalledWith("groups/4/");
	});

	it("creates each kind on its own route", async () => {
		const body = { starts_on: "2026-06-01", rows: [] };
		await bundleApi.create({ kind: "multi_course", student_id: 11, ...body });
		expect(api.post).toHaveBeenLastCalledWith("bundles/multi-course/", {
			student_id: 11,
			...body,
		});
		await bundleApi.create({ kind: "family", family_id: 2, ...body });
		expect(api.post).toHaveBeenLastCalledWith("bundles/family/", {
			family_id: 2,
			...body,
		});
		await bundleApi.create({ kind: "group", group_id: 3, ...body });
		expect(api.post).toHaveBeenLastCalledWith("bundles/group/", {
			group_id: 3,
			...body,
		});
	});

	it("acts on one bundle", async () => {
		await bundleApi.bundle(9);
		expect(api.get).toHaveBeenLastCalledWith("bundles/9/");
		await bundleApi.renew({ id: 9 });
		expect(api.post).toHaveBeenLastCalledWith("bundles/9/renew/", {});
		await bundleApi.renew({ id: 9, starts_on: "2026-07-01" });
		expect(api.post).toHaveBeenLastCalledWith("bundles/9/renew/", {
			starts_on: "2026-07-01",
		});
		await bundleApi.pause({ id: 9, from_date: "2026-06-03", to_date: "2026-06-04" });
		expect(api.post).toHaveBeenLastCalledWith("bundles/9/pause/", {
			from_date: "2026-06-03",
			to_date: "2026-06-04",
		});
		await bundleApi.cancel(9);
		expect(api.post).toHaveBeenLastCalledWith("bundles/9/cancel/");
		await bundleApi.archive(9);
		expect(api.post).toHaveBeenLastCalledWith("bundles/9/archive/");
		await bundleApi.restore(9);
		expect(api.delete).toHaveBeenLastCalledWith("bundles/9/archive/");
		await bundleApi.addMember({ id: 9, student_id: 12, starts_on: "2026-06-08" });
		expect(api.post).toHaveBeenLastCalledWith("bundles/9/members/", {
			student_id: 12,
			starts_on: "2026-06-08",
		});
		await bundleApi.removeMember({ id: 9, studentId: 12 });
		expect(api.delete).toHaveBeenLastCalledWith("bundles/9/members/12/");
		await bundleApi.updateNotes({ id: 9, notes: "Evenings" });
		expect(api.patch).toHaveBeenLastCalledWith("bundles/9/", {
			notes: "Evenings",
		});
		await bundleApi.dissolve(9);
		expect(api.delete).toHaveBeenLastCalledWith("bundles/9/");
	});
});
```

`dashboard/src/features/scheduling/refusal.test.ts`:

```ts
import { AxiosError, type AxiosResponse } from "axios";
import { describe, expect, it } from "vitest";
import i18n from "@/lib/i18n";
import { bundleDetail, bundleMember } from "@/test/scheduling-fixtures";
import { memberIdOf, refusalText } from "./refusal";

function failed(status: number, data: unknown): AxiosError {
	const error = new AxiosError("failed");
	error.response = { status, data } as AxiosResponse;
	return error;
}

const t = i18n.getFixedT("en");
const name = (n: { name_en: string }) => n.name_en;

describe("bundle refusals", () => {
	const bundle = bundleDetail({
		members: [
			bundleMember({ id: 7 }),
			bundleMember({
				id: 8,
				student: { id: 12, full_name: "Aisha", timezone: "UTC" },
				freeze_days_left: 2,
			}),
		],
	});

	it("reads the member the server names", () => {
		expect(memberIdOf(failed(409, { code: "x", member_id: 8 }))).toBe(8);
		expect(memberIdOf(failed(409, { code: "x" }))).toBeNull();
		expect(memberIdOf(new Error("offline"))).toBeNull();
	});

	it("names the member and its course", () => {
		const error = failed(400, {
			student: ["Choose an active student."],
			member_id: 7,
		});
		expect(refusalText(error, bundle, t, name)).toBe(
			"Yusuf (Tajweed): Choose an active student.",
		);
	});

	it("adds the freeze days left to a freeze-cap refusal", () => {
		const error = failed(409, {
			detail: "That is more than the freeze days allowed.",
			code: "scheduling.freeze_days_exceeded",
			member_id: 8,
		});
		expect(refusalText(error, bundle, t, name)).toBe(
			"Aisha (Tajweed): That is more than the freeze days left. Freeze days left for Aisha: 2.",
		);
	});

	it("says the rule alone when no member is named", () => {
		const error = failed(409, {
			detail: "Nothing in this bundle can be renewed.",
			code: "scheduling.nothing_to_renew",
		});
		expect(refusalText(error, bundle, t, name)).toBe(
			"Nothing in this bundle can be renewed.",
		);
	});
});
```

(`@/lib/i18n` default-exports the initialised instance.)

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/bundleApi.test.ts src/features/scheduling/refusal.test.ts`
Expected: FAIL — `Cannot find module './bundleApi'`.

- [ ] **Step 3: Types**

`dashboard/src/features/identity/schemas.ts` — in `FeatureCode`, after B2e's two:

```ts
	// Slice B2f (Plan 37).
	| "study_groups"
	| "multi_course_subscriptions"
	| "family_subscriptions"
	| "group_subscriptions"
```

`dashboard/src/features/scheduling/schemas.ts` — before `interface Subscription`:

```ts
/** Slice B2f §4.5: a member's bundle (only on members, plan D10). */
export interface BundleRef {
	id: number;
	kind: "multi_course" | "family" | "group";
}
/** Slice B2f §4.5: a group bundle's session names its group. */
export interface GroupLabel {
	bundle_id: number;
	name: string;
}
```

and the optional fields: in `Subscription`, after `can_archive?`: `// Slice B2f: only on a bundle's members.` `bundle?: BundleRef;`; in `Session`, after `ends_at?`: `// Slice B2f: only on a group bundle's sessions, for everyone in scope.` `group?: GroupLabel;`.

`dashboard/src/features/scheduling/bundleSchemas.ts`:

```ts
import { z } from "zod";
import {
	type BundleRef,
	isoDate,
	type NamedRef,
	type PersonRef,
	price,
	type Session,
	type SlotGroupValues,
	type Subscription,
	type SubscriptionStatus,
	slotGroupSchema,
} from "./schemas";

/** Slice B2f F-2: the bundle kinds, as the API names them. */
export const BUNDLE_KINDS = ["multi_course", "family", "group"] as const;
export type BundleKind = BundleRef["kind"];

/** F-1: a study group; `members[].id` is the student's User id. */
export interface StudyGroupMember {
	id: number;
	full_name: string;
	is_active: boolean;
}
export interface StudyGroup {
	id: number;
	name: string;
	notes: string;
	is_active: boolean;
	members: StudyGroupMember[];
	/** The server's rule: no bundle uses it (plan D11). */
	can_delete: boolean;
	created_at: string;
}
export interface StudyGroupBody {
	name: string;
	student_ids: number[];
	notes?: string;
	is_active?: boolean;
}
export type StudyGroupPatch = Partial<StudyGroupBody>;

/** §4.5: the kind's owner; the other two are null. */
export interface BundleOwner {
	student: PersonRef | null;
	family: { id: number; name: string } | null;
	study_group: { id: number; name: string } | null;
}
export type BundleState = "live" | "ended";
export interface BundleRow extends BundleOwner {
	id: number;
	kind: BundleKind;
	notes: string;
	members_count: number;
	state: BundleState;
	created_at: string;
}
export interface BundleMember extends Subscription {
	current: boolean;
	freeze_days_left: number;
}
export interface RosterRow {
	student: PersonRef;
	subscription_id: number;
	course: NamedRef;
	teacher: PersonRef;
	status: SubscriptionStatus;
	attended: number;
	can_remove: boolean;
}
export interface BundleConflict {
	session: Session;
	other: Session;
}
export interface BundleDetail extends BundleOwner {
	id: number;
	kind: BundleKind;
	notes: string;
	state: BundleState;
	created_by: PersonRef | null;
	created_at: string;
	members: BundleMember[];
	totals: {
		sessions_total: number;
		prices: { currency: string; price_minor: number }[];
	};
	roster: RosterRow[];
	// Plan D11: the server's rules; the archive pair only while it is on.
	can_renew: boolean;
	can_pause: boolean;
	can_cancel: boolean;
	can_add_member: boolean;
	can_archive?: boolean;
	can_restore?: boolean;
	// Plan D12: on the create answer only.
	conflicts?: BundleConflict[];
}

export interface BundleRowBody {
	student?: number;
	course: number;
	teacher: number;
	package: number;
	price_minor?: number;
	slots?: SlotGroupValues[];
}
export interface BundleCreateBody {
	student_id?: number;
	family_id?: number;
	group_id?: number;
	starts_on: string;
	rows: BundleRowBody[];
	notes?: string;
	supervisor_id?: number | null;
}
// Form schemas. Messages are i18n keys, translated by `useFieldError`.
const pick = z.string().min(1, "scheduling.errors.required");

export const studyGroupFormSchema = z.object({
	name: z
		.string()
		.trim()
		.min(1, "studyGroups.errors.nameRequired")
		.max(120, "studyGroups.errors.nameTooLong"),
	student_ids: z.array(z.number()).min(1, "studyGroups.errors.studentsRequired"),
	notes: z.string(),
	is_active: z.boolean(),
});
export type StudyGroupFormValues = z.infer<typeof studyGroupFormSchema>;

export const bundleRowSchema = z.object({
	/** Family rows only; "" elsewhere. */
	student: z.string(),
	course: pick,
	teacher: pick,
	package: pick,
	price,
	slots: z.array(slotGroupSchema),
});
export type BundleRowValues = z.infer<typeof bundleRowSchema>;

export const bundleFormSchema = z.object({
	/** The student, family or study group, by kind. */
	owner: pick,
	starts_on: isoDate,
	notes: z.string(),
	supervisor: z.string(),
	rows: z.array(bundleRowSchema),
});
export type BundleFormValues = z.infer<typeof bundleFormSchema>;
```


- [ ] **Step 4: Routes and hooks**

`dashboard/src/features/scheduling/bundleApi.ts`:

```ts
import { api, clean, type Paginated, type QueryParams } from "@/lib/api";
import type {
	BundleCreateBody,
	BundleDetail,
	BundleKind,
	BundleRow,
	StudyGroup,
	StudyGroupBody,
	StudyGroupPatch,
} from "./bundleSchemas";
import type { PauseBody, PersonRef } from "./schemas";

const G = "groups/";
const B = "bundles/";
/** Slice B2f §6: one create route per kind. */
const CREATE: Record<BundleKind, string> = {
	multi_course: "multi-course/",
	family: "family/",
	group: "group/",
};
const detail = async (request: Promise<{ data: BundleDetail }>) =>
	(await request).data;

export const bundleApi = {
	groups: async (params: QueryParams) =>
		(await api.get<Paginated<StudyGroup>>(G, { params: clean(params) })).data,
	createGroup: async (body: StudyGroupBody) =>
		(await api.post<StudyGroup>(G, body)).data,
	updateGroup: async ({ id, ...body }: StudyGroupPatch & { id: number }) =>
		(await api.patch<StudyGroup>(`${G}${id}/`, body)).data,
	deleteGroup: async (id: number) => {
		await api.delete(`${G}${id}/`);
	},
	/** Plan D13: who may join, the server's answer. */
	candidates: async (params: QueryParams) =>
		(await api.get<PersonRef[]>(`${G}candidates/`, { params: clean(params) }))
			.data,
	bundles: async (params: QueryParams) =>
		(await api.get<Paginated<BundleRow>>(B, { params: clean(params) })).data,
	bundle: (id: number) => detail(api.get(`${B}${id}/`)),
	create: ({ kind, ...body }: BundleCreateBody & { kind: BundleKind }) =>
		detail(api.post(`${B}${CREATE[kind]}`, body)),
	updateNotes: ({ id, notes }: { id: number; notes: string }) =>
		detail(api.patch(`${B}${id}/`, { notes })),
	dissolve: async (id: number) => {
		await api.delete(`${B}${id}/`);
	},
	renew: ({ id, starts_on }: { id: number; starts_on?: string }) =>
		detail(api.post(`${B}${id}/renew/`, starts_on ? { starts_on } : {})),
	pause: ({ id, ...body }: PauseBody & { id: number }) =>
		detail(api.post(`${B}${id}/pause/`, body)),
	cancel: (id: number) => detail(api.post(`${B}${id}/cancel/`)),
	archive: (id: number) => detail(api.post(`${B}${id}/archive/`)),
	restore: (id: number) => detail(api.delete(`${B}${id}/archive/`)),
	addMember: ({
		id,
		...body
	}: {
		id: number;
		student_id: number;
		starts_on: string;
	}) => detail(api.post(`${B}${id}/members/`, body)),
	removeMember: ({ id, studentId }: { id: number; studentId: number }) =>
		detail(api.delete(`${B}${id}/members/${studentId}/`)),
};
```

`dashboard/src/features/scheduling/bundleQueries.ts`:

```ts
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import type { QueryParams } from "@/lib/api";
import { bundleApi } from "./bundleApi";
import { schedulingKey } from "./queries";

/** Slice B2f: study groups and bundles live under `schedulingKey`, so every
 * scheduling write — a bundle action or one member's own — refreshes them
 * (`useSchedulingMutation`). */
export function useStudyGroups(
	params: QueryParams,
	{ enabled = true }: { enabled?: boolean } = {},
) {
	return useQuery({
		queryKey: [...schedulingKey, "study-groups", params],
		queryFn: () => bundleApi.groups(params),
		placeholderData: keepPreviousData,
		enabled,
	});
}

/** Plan D13: who may join a new group (no `groupId`) or this one. */
export function useGroupCandidates(
	q: string,
	groupId: number | undefined,
	enabled: boolean,
) {
	return useQuery({
		queryKey: [...schedulingKey, "group-candidates", q, groupId ?? "new"],
		queryFn: () => bundleApi.candidates({ q, group: groupId }),
		enabled,
	});
}

export function useBundle(id: number | undefined) {
	return useQuery({
		queryKey: [...schedulingKey, "bundle", id],
		queryFn: () => bundleApi.bundle(id as number),
		enabled: id !== undefined,
	});
}
```

`dashboard/src/features/scheduling/refusal.ts`:

```ts
import { isAxiosError } from "axios";
import type { TFunction } from "i18next";
import { parseApiError } from "@/features/identity/api";
import { codeKey } from "@/lib/form-errors";
import type { BundleDetail } from "./bundleSchemas";
import type { NamedRef } from "./schemas";

const FREEZE_CAP = "scheduling.freeze_days_exceeded";

/** Slice B2f §4.6: the bundle member the server names, or null. */
export function memberIdOf(error: unknown): number | null {
	if (!isAxiosError(error)) return null;
	const data = error.response?.data as { member_id?: unknown } | undefined;
	return typeof data?.member_id === "number" ? data.member_id : null;
}

/** A bundle action's refusal as one sentence: the translated rule (or the
 * server's message, or its first field error), naming the member that
 * refused when there is one; a freeze-cap refusal adds that member's freeze
 * days left (plan D16). */
export function refusalText(
	error: unknown,
	bundle: BundleDetail,
	t: TFunction,
	localName: (named: NamedRef) => string,
): string {
	const parsed = parseApiError(error);
	const field = Object.entries(parsed.fieldErrors).find(
		([key]) => key !== "member_id",
	);
	const reason =
		(parsed.code ? t(codeKey(parsed.code), { defaultValue: "" }) : "") ||
		parsed.message ||
		field?.[1] ||
		t("errors.generic");
	const id = memberIdOf(error);
	const member = bundle.members.find((m) => m.id === id);
	if (!member) return reason;
	const named = t("bundles.refused", {
		name: member.student.full_name,
		course: localName(member.course),
		reason,
	});
	if (parsed.code !== FREEZE_CAP) return named;
	return `${named} ${t("bundles.freezeLeft", {
		name: member.student.full_name,
		count: member.freeze_days_left,
	})}`;
}
```

`dashboard/src/features/scheduling/index.ts` — add `export { bundleApi } from "./bundleApi";`, `export * from "./bundleQueries";`, `export * from "./bundleSchemas";`.

The bundle screen's route, minimal for now (Task 17 renders `BundlePage` in it), so every later task can link to it and `tsc --noEmit` passes task by task — `dashboard/src/routes/_authed/scheduling.bundles.$bundleId.tsx` becomes:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling/bundles/$bundleId")({
	// Plan D19: the shared bundle routes are ungated, so is their screen.
	staticData: { permission: "subscription.view" },
	component: function BundleRoute() {
		const { t } = useTranslation();
		usePageTitle(t("bundles.title"));
		return <PageHeader title={t("bundles.title")} />;
	},
});
```

Regenerate the route tree: `… exec -T dashboard pnpm exec vite build`.

- [ ] **Step 5: Fixtures** (append to `dashboard/src/test/scheduling-fixtures.ts`; import the new types from `@/features/scheduling/bundleSchemas`)

```ts
export function studyGroupRow(overrides: Partial<StudyGroup> = {}): StudyGroup {
	return {
		id: 4,
		name: "Evening circle",
		notes: "",
		is_active: true,
		members: [
			{ id: 12, full_name: "Aisha", is_active: true },
			{ id: 11, full_name: "Yusuf", is_active: true },
		],
		can_delete: true,
		created_at: "2026-06-01T08:00:00Z",
		...overrides,
	};
}

export function bundleMember(overrides: Partial<BundleMember> = {}): BundleMember {
	return {
		...subscriptionRow(),
		bundle: { id: 9, kind: "group" },
		current: true,
		freeze_days_left: 10,
		...overrides,
	};
}

export function rosterRow(overrides: Partial<RosterRow> = {}): RosterRow {
	return {
		student: { id: 11, full_name: "Yusuf" },
		subscription_id: 7,
		course: { id: 3, name_ar: "تجويد", name_en: "Tajweed" },
		teacher: { id: 21, full_name: "Bilal" },
		status: "active",
		attended: 2,
		can_remove: true,
		...overrides,
	};
}

export function bundleDetail(overrides: Partial<BundleDetail> = {}): BundleDetail {
	return {
		id: 9,
		kind: "group",
		student: null,
		family: null,
		study_group: { id: 4, name: "Evening circle" },
		notes: "",
		state: "live",
		created_by: { id: 1, full_name: "Amina" },
		created_at: "2026-06-01T08:00:00Z",
		members: [bundleMember()],
		totals: {
			sessions_total: 8,
			prices: [{ currency: "EGP", price_minor: 150000 }],
		},
		roster: [rosterRow()],
		can_renew: true,
		can_pause: true,
		can_cancel: true,
		can_add_member: true,
		...overrides,
	};
}
```

- [ ] **Step 6: Strings**

`dashboard/src/locales/en/bundles.json`:

```json
{
	"title": "Subscription bundle",
	"kind": {
		"multi_course": "Multi-course",
		"family": "Family",
		"group": "Group"
	},
	"types": {
		"label": "Subscription type",
		"individual": "Individual",
		"individualHint": "One student, one course.",
		"multi_course": "Multi-course",
		"multi_courseHint": "One student, several courses.",
		"family": "Family",
		"familyHint": "Students of one family.",
		"group": "Group",
		"groupHint": "A study group taught together."
	},
	"form": {
		"student": "Student",
		"findStudent": "Find a student",
		"family": "Family",
		"group": "Study group",
		"startsOn": "Starts",
		"notes": "Notes",
		"rows": "Courses",
		"row": "Course {{n}}",
		"addRow": "Add a course",
		"removeRow": "Remove course {{n}}",
		"rowStudent": "Student",
		"groupMembers": "Active students who will be subscribed: {{count}}",
		"perStudent": "Every student gets these values.",
		"create": "Create bundle",
		"clashes": "The bundle was created. Some of its sessions overlap the teacher's other sessions:",
		"clash": "{{student}}, {{when}}: overlaps {{other}}",
		"open": "Open the bundle"
	},
	"totals": {
		"title": "Totals",
		"sessions": "Sessions",
		"price": "Price"
	},
	"page": {
		"owner": "Owner",
		"kind": "Type",
		"state": {
			"live": "Live",
			"ended": "Ended"
		},
		"createdBy": "Created by",
		"notFound": "This bundle doesn't exist.",
		"loadError": "Couldn't load the bundle."
	},
	"tabs": {
		"label": "Bundle sections",
		"members": "Members",
		"roster": "Roster"
	},
	"members": {
		"student": "Student",
		"course": "Course",
		"teacher": "Teacher",
		"status": "Status",
		"ends": "Ends",
		"current": "Current",
		"earlier": "Earlier term"
	},
	"roster": {
		"student": "Student",
		"userId": "User ID",
		"course": "Course",
		"teacher": "Teacher",
		"status": "Status",
		"attended": "Attended",
		"remove": "Remove",
		"removeName": "Remove {{name}}",
		"removeTitle": "Remove from the group",
		"removeBody": "Their live subscriptions in this bundle are cancelled, a pending renewal too."
	},
	"notes": {
		"title": "Notes",
		"edit": "Edit notes",
		"save": "Save notes",
		"none": "No notes."
	},
	"actions": {
		"label": "Bundle actions",
		"renew": "Renew bundle",
		"renewBody": "Every current member is renewed, each as its own subscription. Leave the date empty to start each one where its term ends.",
		"startsOn": "Renewals start on",
		"pause": "Pause bundle",
		"pauseBody": "Every live member whose term includes the first day is paused.",
		"from": "From",
		"to": "To",
		"reason": "Reason",
		"cancel": "Cancel bundle",
		"cancelBody": "Every live member is cancelled, a pending renewal too.",
		"archive": "Archive bundle",
		"archiveBody": "Every member is archived with its sessions.",
		"restore": "Restore bundle",
		"restoreBody": "Every archived member comes back.",
		"add": "Add a student",
		"addBody": "The student gets the class's course, teacher, package, price and slots from the day you choose.",
		"addStudent": "Student",
		"dissolve": "Dissolve bundle",
		"dissolveBody": "The members become plain subscriptions and the bundle is deleted. Nothing else changes."
	},
	"refused": "{{name}} ({{course}}): {{reason}}",
	"freezeLeft": "Freeze days left for {{name}}: {{count}}.",
	"partOf": "Part of a {{kind}} bundle.",
	"openBundle": "Open the bundle",
	"badge": "{{kind}} bundle",
	"filter": {
		"label": "Bundle type",
		"any": "Any type"
	},
	"group": "Group: {{name}}"
}
```

`dashboard/src/locales/ar/bundles.json` (same keys):

```json
{
	"title": "حزمة اشتراكات",
	"kind": {
		"multi_course": "متعددة الدورات",
		"family": "عائلية",
		"group": "مجموعة"
	},
	"types": {
		"label": "نوع الاشتراك",
		"individual": "فردي",
		"individualHint": "طالب واحد ودورة واحدة.",
		"multi_course": "متعدد الدورات",
		"multi_courseHint": "طالب واحد وعدة دورات.",
		"family": "عائلي",
		"familyHint": "طلاب عائلة واحدة.",
		"group": "مجموعة",
		"groupHint": "مجموعة دراسية تدرس معًا."
	},
	"form": {
		"student": "الطالب",
		"findStudent": "ابحث عن طالب",
		"family": "العائلة",
		"group": "المجموعة الدراسية",
		"startsOn": "يبدأ في",
		"notes": "ملاحظات",
		"rows": "الدورات",
		"row": "الدورة {{n}}",
		"addRow": "أضف دورة",
		"removeRow": "احذف الدورة {{n}}",
		"rowStudent": "الطالب",
		"groupMembers": "الطلاب النشطون الذين سيُشتركون: {{count}}",
		"perStudent": "يحصل كل طالب على هذه القيم.",
		"create": "أنشئ الحزمة",
		"clashes": "أُنشئت الحزمة. تتداخل بعض حصصها مع حصص أخرى للمعلم:",
		"clash": "{{student}}، {{when}}: تتداخل مع {{other}}",
		"open": "افتح الحزمة"
	},
	"totals": {
		"title": "الإجماليات",
		"sessions": "الحصص",
		"price": "السعر"
	},
	"page": {
		"owner": "المالك",
		"kind": "النوع",
		"state": {
			"live": "سارية",
			"ended": "منتهية"
		},
		"createdBy": "أنشأها",
		"notFound": "هذه الحزمة غير موجودة.",
		"loadError": "تعذّر تحميل الحزمة."
	},
	"tabs": {
		"label": "أقسام الحزمة",
		"members": "الأعضاء",
		"roster": "قائمة الطلاب"
	},
	"members": {
		"student": "الطالب",
		"course": "الدورة",
		"teacher": "المعلم",
		"status": "الحالة",
		"ends": "ينتهي في",
		"current": "الحالي",
		"earlier": "فترة سابقة"
	},
	"roster": {
		"student": "الطالب",
		"userId": "رقم المستخدم",
		"course": "الدورة",
		"teacher": "المعلم",
		"status": "الحالة",
		"attended": "الحضور",
		"remove": "إزالة",
		"removeName": "أزل {{name}}",
		"removeTitle": "الإزالة من المجموعة",
		"removeBody": "تُلغى اشتراكاته السارية في هذه الحزمة، وكذلك أي تجديد لم يبدأ بعد."
	},
	"notes": {
		"title": "ملاحظات",
		"edit": "عدّل الملاحظات",
		"save": "احفظ الملاحظات",
		"none": "لا توجد ملاحظات."
	},
	"actions": {
		"label": "إجراءات الحزمة",
		"renew": "جدّد الحزمة",
		"renewBody": "يُجدَّد كل عضو حالي، كلٌّ في اشتراكه الخاص. اترك التاريخ فارغًا ليبدأ كلٌّ منها عند نهاية فترته.",
		"startsOn": "تبدأ التجديدات في",
		"pause": "أوقف الحزمة مؤقتًا",
		"pauseBody": "يُوقَف مؤقتًا كل عضو سارٍ تشمل فترتُه اليومَ الأول.",
		"from": "من",
		"to": "إلى",
		"reason": "السبب",
		"cancel": "ألغِ الحزمة",
		"cancelBody": "يُلغى كل عضو سارٍ، وكذلك أي تجديد لم يبدأ بعد.",
		"archive": "أرشف الحزمة",
		"archiveBody": "يُؤرشف كل عضو مع حصصه.",
		"restore": "استعد الحزمة",
		"restoreBody": "يعود كل عضو مؤرشف.",
		"add": "أضف طالبًا",
		"addBody": "يحصل الطالب على دورة الحلقة ومعلمها وباقتها وسعرها ومواعيدها من اليوم الذي تختاره.",
		"addStudent": "الطالب",
		"dissolve": "فكّ الحزمة",
		"dissolveBody": "يصبح الأعضاء اشتراكات عادية وتُحذف الحزمة. لا يتغير شيء آخر."
	},
	"refused": "{{name}} ({{course}}): {{reason}}",
	"freezeLeft": "أيام التجميد المتبقية لـ {{name}}: {{count}}.",
	"partOf": "جزء من حزمة {{kind}}.",
	"openBundle": "افتح الحزمة",
	"badge": "حزمة {{kind}}",
	"filter": {
		"label": "نوع الحزمة",
		"any": "أي نوع"
	},
	"group": "المجموعة: {{name}}"
}
```

`dashboard/src/locales/en/studyGroups.json`:

```json
{
	"nav": "Study groups",
	"title": "Study groups",
	"subtitle": "Students taught together; each student is in one group at most.",
	"add": "Add study group",
	"addBody": "Name the group and choose its students.",
	"edit": "Edit",
	"editName": "Edit {{name}}",
	"editTitle": "Edit study group",
	"editBody": "Change the name, the students, the notes or whether it is active.",
	"name": "Name",
	"students": "Students",
	"noStudents": "No students chosen yet.",
	"findStudent": "Find a student",
	"noMatches": "No student can join: they are inactive or in another group.",
	"addOne": "Add",
	"addStudent": "Add {{name}}",
	"remove": "Remove",
	"removeStudent": "Remove {{name}}",
	"inactiveMember": "{{name}} (inactive)",
	"notes": "Notes",
	"active": "Active",
	"save": "Save study group",
	"saved": "Study group saved.",
	"delete": "Delete",
	"deleteName": "Delete {{name}}",
	"deleteTitle": "Delete study group",
	"deleteBody": "The group is deleted. Its students are free to join another one.",
	"deleted": "Study group deleted.",
	"status": {
		"active": "Active",
		"inactive": "Inactive"
	},
	"search": "Search study groups",
	"empty": "No study groups yet.",
	"loadError": "Couldn't load the study groups.",
	"columns": {
		"name": "Name",
		"students": "Students",
		"status": "Status",
		"actions": "Actions"
	},
	"errors": {
		"nameRequired": "Enter a name.",
		"nameTooLong": "Keep the name to 120 characters.",
		"studentsRequired": "Choose at least one student."
	}
}
```

`dashboard/src/locales/ar/studyGroups.json`:

```json
{
	"nav": "المجموعات الدراسية",
	"title": "المجموعات الدراسية",
	"subtitle": "طلاب يدرسون معًا؛ كل طالب في مجموعة واحدة على الأكثر.",
	"add": "أضف مجموعة دراسية",
	"addBody": "سمِّ المجموعة واختر طلابها.",
	"edit": "تعديل",
	"editName": "عدّل {{name}}",
	"editTitle": "تعديل المجموعة الدراسية",
	"editBody": "غيّر الاسم أو الطلاب أو الملاحظات أو حالة التفعيل.",
	"name": "الاسم",
	"students": "الطلاب",
	"noStudents": "لم يُختر أي طالب بعد.",
	"findStudent": "ابحث عن طالب",
	"noMatches": "لا يمكن لأي طالب الانضمام: إما غير نشط أو في مجموعة أخرى.",
	"addOne": "أضف",
	"addStudent": "أضف {{name}}",
	"remove": "إزالة",
	"removeStudent": "أزل {{name}}",
	"inactiveMember": "{{name}} (غير نشط)",
	"notes": "ملاحظات",
	"active": "نشطة",
	"save": "احفظ المجموعة",
	"saved": "حُفظت المجموعة الدراسية.",
	"delete": "حذف",
	"deleteName": "احذف {{name}}",
	"deleteTitle": "حذف المجموعة الدراسية",
	"deleteBody": "تُحذف المجموعة، ويصبح طلابها أحرارًا في الانضمام إلى مجموعة أخرى.",
	"deleted": "حُذفت المجموعة الدراسية.",
	"status": {
		"active": "نشطة",
		"inactive": "غير نشطة"
	},
	"search": "ابحث في المجموعات الدراسية",
	"empty": "لا توجد مجموعات دراسية بعد.",
	"loadError": "تعذّر تحميل المجموعات الدراسية.",
	"columns": {
		"name": "الاسم",
		"students": "الطلاب",
		"status": "الحالة",
		"actions": "الإجراءات"
	},
	"errors": {
		"nameRequired": "أدخل اسمًا.",
		"nameTooLong": "لا يزيد الاسم على 120 حرفًا.",
		"studentsRequired": "اختر طالبًا واحدًا على الأقل."
	}
}
```

`errors.json` — under `scheduling`, beside B2e's codes: en `"group_in_use": "This study group has subscription bundles. Dissolve them first."`, `"nothing_to_renew": "Nothing in this bundle can be renewed."`; ar `"group_in_use": "لهذه المجموعة الدراسية حزم اشتراكات. فكّها أولًا."`, `"nothing_to_renew": "لا شيء في هذه الحزمة يمكن تجديده."`.

- [ ] **Step 7: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/bundleApi.test.ts src/features/scheduling/refusal.test.ts src/locales src/routes`
Expected: PASS (the ar/en key-equality test and the route screen tests included). Then `… exec -T dashboard pnpm exec tsc --noEmit` and `pnpm lint`: clean.

- [ ] **Step 8: Commit**

```bash
git -C $W/dashboard add src/features/identity/schemas.ts src/features/scheduling/schemas.ts src/features/scheduling/bundleSchemas.ts src/features/scheduling/bundleApi.ts src/features/scheduling/bundleQueries.ts src/features/scheduling/refusal.ts src/features/scheduling/index.ts src/features/scheduling/bundleApi.test.ts src/features/scheduling/refusal.test.ts src/test/scheduling-fixtures.ts src/locales/en/bundles.json src/locales/ar/bundles.json src/locales/en/studyGroups.json src/locales/ar/studyGroups.json src/locales/en/errors.json src/locales/ar/errors.json "src/routes/_authed/scheduling.bundles.\$bundleId.tsx" src/routeTree.gen.ts
git -C $W/dashboard commit -m "feat(scheduling): bundle and study group types, routes, hooks and strings (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 14: Study groups — the list, the dialog, the screen and its nav entry

**Files:**
- Create: `dashboard/src/features/scheduling/StudyGroupsList.tsx`, `StudyGroupDialog.tsx`
- Modify: `dashboard/src/features/scheduling/index.ts` (`StudyGroupsList`)
- Create: `dashboard/src/routes/_authed/people.groups.index.tsx`
- Modify: `dashboard/src/features/shell/nav.ts`, `nav.test.ts` (under `// ── phase B2 ──`)
- Modify: `dashboard/src/routes/permissions.test.ts`
- Regenerate: `dashboard/src/routeTree.gen.ts`
- Test: `dashboard/src/features/scheduling/StudyGroupsList.test.tsx`, `StudyGroupDialog.test.tsx`

**Interfaces:**
- Consumes: `bundleApi.groups/createGroup/updateGroup/deleteGroup/candidates`, `useStudyGroups`, `useGroupCandidates`, `studyGroupFormSchema` (Task 13); `useSchedulingMutation`; `Confirm` (`@/components/Confirm`); `useCan`.
- Produces: `<StudyGroupsList />`; `<StudyGroupDialog group? />` (Add without `group`, Edit with it). Route `/people/groups/` (`study_group.view_any`, feature `study_groups`). Nav item "Study groups" in the `people` group.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/StudyGroupsList.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import { page, studyGroupRow } from "@/test/scheduling-fixtures";
import { bundleApi } from "./bundleApi";
import { StudyGroupsList } from "./StudyGroupsList";

vi.mock("./bundleApi", async (orig) => {
	const actual = await orig<typeof import("./bundleApi")>();
	return {
		...actual,
		bundleApi: {
			...actual.bundleApi,
			groups: vi.fn(),
			deleteGroup: vi.fn(),
			candidates: vi.fn(),
		},
	};
});

describe("StudyGroupsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(bundleApi.groups).mockResolvedValue(
			page([
				studyGroupRow(),
				studyGroupRow({
					id: 5,
					name: "Late circle",
					is_active: false,
					can_delete: false,
					members: [{ id: 13, full_name: "Zaid", is_active: false }],
				}),
			]) as never,
		);
		vi.mocked(bundleApi.candidates).mockResolvedValue([]);
		vi.mocked(bundleApi.deleteGroup).mockResolvedValue();
	});

	it("lists each group with its students and status", async () => {
		renderWithRouter(<StudyGroupsList />);
		const row = await screen.findByRole("row", { name: /Evening circle/ });
		expect(row).toHaveTextContent("Aisha, Yusuf");
		expect(row).toHaveTextContent("Active");
		const late = screen.getByRole("row", { name: /Late circle/ });
		expect(late).toHaveTextContent("Zaid (inactive)");
		expect(late).toHaveTextContent("Inactive");
	});

	it("deletes only a group the server says may go", async () => {
		const user = userEvent.setup();
		renderWithRouter(<StudyGroupsList />);
		await user.click(
			await screen.findByRole("button", { name: "Delete Evening circle" }),
		);
		await user.click(
			screen.getByRole("button", { name: "Delete study group" }),
		);
		await waitFor(() => expect(bundleApi.deleteGroup).toHaveBeenCalledWith(4));
		expect(
			screen.queryByRole("button", { name: "Delete Late circle" }),
		).toBeNull();
	});

	it("searches by name", async () => {
		const user = userEvent.setup();
		renderWithRouter(<StudyGroupsList />);
		await screen.findByRole("row", { name: /Evening circle/ });
		await user.type(screen.getByRole("searchbox"), "eve");
		await waitFor(() =>
			expect(bundleApi.groups).toHaveBeenLastCalledWith(
				expect.objectContaining({ q: "eve", page: 1 }),
			),
		);
	});

	it("hides what the viewer may not do", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("study_group.view_any")}>
				<StudyGroupsList />
			</CanProvider>,
		);
		await screen.findByRole("row", { name: /Evening circle/ });
		expect(screen.queryByRole("button", { name: "Add study group" })).toBeNull();
		expect(
			screen.queryByRole("button", { name: "Edit Evening circle" }),
		).toBeNull();
		expect(
			screen.queryByRole("button", { name: "Delete Evening circle" }),
		).toBeNull();
	});
});
```

`dashboard/src/features/scheduling/StudyGroupDialog.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { studyGroupRow } from "@/test/scheduling-fixtures";
import { bundleApi } from "./bundleApi";
import { StudyGroupDialog } from "./StudyGroupDialog";

vi.mock("./bundleApi", async (orig) => {
	const actual = await orig<typeof import("./bundleApi")>();
	return {
		...actual,
		bundleApi: {
			...actual.bundleApi,
			candidates: vi.fn(),
			createGroup: vi.fn(),
			updateGroup: vi.fn(),
		},
	};
});

describe("StudyGroupDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(bundleApi.candidates).mockResolvedValue([
			{ id: 12, full_name: "Aisha" },
			{ id: 11, full_name: "Yusuf" },
		]);
		vi.mocked(bundleApi.createGroup).mockResolvedValue(studyGroupRow());
		vi.mocked(bundleApi.updateGroup).mockResolvedValue(studyGroupRow());
	});

	it("creates a group of the students the server offers", async () => {
		const user = userEvent.setup();
		renderWithRouter(<StudyGroupDialog />);
		await user.click(await screen.findByRole("button", { name: "Add study group" }));
		await user.type(screen.getByLabelText(/^Name/), "Evening circle");
		await user.click(await screen.findByRole("button", { name: "Add Aisha" }));
		await user.click(screen.getByRole("button", { name: "Add Yusuf" }));
		await user.click(screen.getByRole("button", { name: "Save study group" }));
		await waitFor(() =>
			expect(bundleApi.createGroup).toHaveBeenCalledWith({
				name: "Evening circle",
				student_ids: [12, 11],
				notes: "",
				is_active: true,
			}),
		);
	});

	it("asks the server who may join, as they type", async () => {
		const user = userEvent.setup();
		renderWithRouter(<StudyGroupDialog group={studyGroupRow()} />);
		await user.click(
			await screen.findByRole("button", { name: "Edit Evening circle" }),
		);
		await user.type(screen.getByLabelText("Find a student"), "ai");
		await waitFor(() =>
			expect(bundleApi.candidates).toHaveBeenLastCalledWith({
				q: "ai",
				group: 4,
			}),
		);
	});

	it("edits a group and shows a refusal on its students", async () => {
		const user = userEvent.setup();
		const error = new AxiosError("bad");
		error.response = {
			status: 400,
			data: { student_ids: ["Already in another study group: Zaid."] },
		} as AxiosResponse;
		vi.mocked(bundleApi.updateGroup).mockRejectedValueOnce(error);
		renderWithRouter(<StudyGroupDialog group={studyGroupRow()} />);
		await user.click(
			await screen.findByRole("button", { name: "Edit Evening circle" }),
		);
		expect(screen.getByLabelText(/^Name/)).toHaveValue("Evening circle");
		await user.click(screen.getByRole("button", { name: "Remove Aisha" }));
		await user.click(screen.getByRole("button", { name: "Save study group" }));
		expect(
			await screen.findByText("Already in another study group: Zaid."),
		).toBeVisible();
		expect(bundleApi.updateGroup).toHaveBeenCalledWith({
			id: 4,
			name: "Evening circle",
			student_ids: [11],
			notes: "",
			is_active: true,
		});
	});
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/StudyGroupsList.test.tsx src/features/scheduling/StudyGroupDialog.test.tsx`
Expected: FAIL — `Cannot find module './StudyGroupsList'`.

- [ ] **Step 3: The dialog** (`dashboard/src/features/scheduling/StudyGroupDialog.tsx`)

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
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
	FormError,
	Input,
	Textarea,
	toast,
} from "@/ui";
import { bundleApi } from "./bundleApi";
import { useGroupCandidates } from "./bundleQueries";
import {
	type StudyGroup,
	type StudyGroupFormValues,
	studyGroupFormSchema,
} from "./bundleSchemas";
import { useSchedulingMutation } from "./queries";

type Chosen = { id: number; full_name: string };

function blank(group?: StudyGroup): StudyGroupFormValues {
	return {
		name: group?.name ?? "",
		student_ids: (group?.members ?? []).map((m) => m.id),
		notes: group?.notes ?? "",
		is_active: group?.is_active ?? true,
	};
}

/** Slice B2f §7: add a study group (no `group`) or edit one — its name, its
 * students (whoever the server says may join, plan D13), notes and whether
 * it is active. */
export function StudyGroupDialog({ group }: { group?: StudyGroup }) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState("");
	const [chosen, setChosen] = useState<Chosen[]>(group?.members ?? []);
	const create = useSchedulingMutation(bundleApi.createGroup);
	const update = useSchedulingMutation(bundleApi.updateGroup);
	const { data: candidates } = useGroupCandidates(query.trim(), group?.id, open);
	const {
		register,
		handleSubmit,
		reset,
		setError,
		setValue,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<StudyGroupFormValues>({
		resolver: zodResolver(studyGroupFormSchema),
		defaultValues: blank(group),
	});
	const prefix = group ? `group-${group.id}` : "new-group";
	const ids = watch("student_ids");
	const addable = (candidates ?? []).filter((c) => !ids.includes(c.id));

	function choose(next: Chosen[]) {
		setChosen(next);
		setValue(
			"student_ids",
			next.map((s) => s.id),
			{ shouldValidate: next.length > 0 },
		);
	}

	function openChange(next: boolean) {
		if (next) {
			reset(blank(group));
			setChosen(group?.members ?? []);
			setQuery("");
		}
		setOpen(next);
	}

	async function onSubmit(values: StudyGroupFormValues) {
		const body = { ...values, name: values.name.trim() };
		try {
			if (group) await update.mutateAsync({ id: group.id, ...body });
			else await create.mutateAsync(body);
			toast({ description: t("studyGroups.saved"), variant: "success" });
			setOpen(false);
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={openChange}>
			<DialogTrigger asChild>
				{group ? (
					<Button
						size="sm"
						variant="outline"
						aria-label={t("studyGroups.editName", { name: group.name })}
					>
						{t("studyGroups.edit")}
					</Button>
				) : (
					<Button size="sm">{t("studyGroups.add")}</Button>
				)}
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>
					{t(group ? "studyGroups.editTitle" : "studyGroups.add")}
				</DialogTitle>
				<DialogDescription>
					{t(group ? "studyGroups.editBody" : "studyGroups.addBody")}
				</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id={`${prefix}-name`}
						label={t("studyGroups.name")}
						error={fieldError(errors.name?.message)}
						required
					>
						<Input {...register("name")} />
					</Field>
					<fieldset
						className="flex flex-col gap-2"
						aria-describedby={
							errors.student_ids ? `${prefix}-students-error` : undefined
						}
					>
						<legend className="text-sm font-medium">
							{t("studyGroups.students")}
						</legend>
						{chosen.length === 0 ? (
							<p className="text-sm text-muted-foreground">
								{t("studyGroups.noStudents")}
							</p>
						) : (
							<ul className="flex flex-col gap-2">
								{chosen.map((s) => (
									<li
										key={s.id}
										className="flex items-center justify-between gap-2 text-sm"
									>
										<span>{s.full_name}</span>
										<Button
											type="button"
											size="sm"
											variant="outline"
											aria-label={t("studyGroups.removeStudent", {
												name: s.full_name,
											})}
											onClick={() =>
												choose(chosen.filter((c) => c.id !== s.id))
											}
										>
											{t("studyGroups.remove")}
										</Button>
									</li>
								))}
							</ul>
						)}
						<Field id={`${prefix}-find`} label={t("studyGroups.findStudent")}>
							<Input
								type="search"
								value={query}
								onChange={(e) => setQuery(e.target.value)}
							/>
						</Field>
						{addable.length > 0 ? (
							<ul className="flex flex-col gap-2">
								{addable.map((c) => (
									<li
										key={c.id}
										className="flex items-center justify-between gap-2 text-sm"
									>
										<span>{c.full_name}</span>
										<Button
											type="button"
											size="sm"
											aria-label={t("studyGroups.addStudent", {
												name: c.full_name,
											})}
											onClick={() => choose([...chosen, c])}
										>
											{t("studyGroups.addOne")}
										</Button>
									</li>
								))}
							</ul>
						) : candidates ? (
							<p className="text-sm text-muted-foreground">
								{t("studyGroups.noMatches")}
							</p>
						) : null}
						{errors.student_ids ? (
							<FormError id={`${prefix}-students-error`}>
								{fieldError(errors.student_ids.message)}
							</FormError>
						) : null}
					</fieldset>
					<Field id={`${prefix}-notes`} label={t("studyGroups.notes")}>
						<Textarea rows={3} {...register("notes")} />
					</Field>
					<div className="flex items-center gap-2">
						<Checkbox
							id={`${prefix}-active`}
							checked={watch("is_active")}
							onCheckedChange={(on) => setValue("is_active", on === true)}
						/>
						<label htmlFor={`${prefix}-active`} className="text-sm">
							{t("studyGroups.active")}
						</label>
					</div>
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
						<Button type="submit" disabled={isSubmitting}>
							{t("studyGroups.save")}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

- [ ] **Step 4: The list** (`dashboard/src/features/scheduling/StudyGroupsList.tsx`)

```tsx
import { UsersRound } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { Pager } from "@/components/Pager";
import { useCan } from "@/features/identity/permissions";
import type { QueryParams } from "@/lib/api";
import { errorText } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	EmptyState,
	Input,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import { bundleApi } from "./bundleApi";
import { useStudyGroups } from "./bundleQueries";
import type { StudyGroup } from "./bundleSchemas";
import { useSchedulingMutation } from "./queries";
import { StudyGroupDialog } from "./StudyGroupDialog";

const PAGE_SIZE = 25;

/** Slice B2f §7: the study groups — name, students, status — with Add, Edit
 * and, when the server allows it (`can_delete`), Delete. */
export function StudyGroupsList() {
	const { t } = useTranslation();
	const can = useCan();
	const [params, setParams] = useState<QueryParams>({ page: 1 });
	const { data, isPending, isError } = useStudyGroups(params);
	const remove = useSchedulingMutation(bundleApi.deleteGroup);
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));

	const students = (group: StudyGroup) =>
		group.members
			.map((m) =>
				m.is_active
					? m.full_name
					: t("studyGroups.inactiveMember", { name: m.full_name }),
			)
			.join(", ");

	async function onDelete(group: StudyGroup) {
		try {
			await remove.mutateAsync(group.id);
			toast({ description: t("studyGroups.deleted"), variant: "success" });
		} catch (error) {
			toast({ description: errorText(error, t), variant: "destructive" });
		}
	}

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-center gap-3">
				<Input
					type="search"
					aria-label={t("studyGroups.search")}
					placeholder={t("studyGroups.search")}
					className="w-full sm:max-w-xs"
					value={String(params.q ?? "")}
					onChange={(e) => setParams({ q: e.target.value, page: 1 })}
				/>
				{can("study_group.create") ? <StudyGroupDialog /> : null}
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("studyGroups.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={UsersRound} title={t("studyGroups.empty")} />
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-muted-foreground">
							<tr>
								{(["name", "students", "status", "actions"] as const).map(
									(key) => (
										<th
											key={key}
											scope="col"
											className="p-3 text-start font-medium"
										>
											{t(`studyGroups.columns.${key}`)}
										</th>
									),
								)}
							</tr>
						</thead>
						<tbody>
							{rows.map((group) => (
								<tr key={group.id} className="border-t border-border">
									<td className="p-3 font-medium">{group.name}</td>
									<td className="p-3">{students(group)}</td>
									<td className="p-3">
										<StatusChip tone={group.is_active ? "live" : "neutral"}>
											{t(
												group.is_active
													? "studyGroups.status.active"
													: "studyGroups.status.inactive",
											)}
										</StatusChip>
									</td>
									<td className="flex flex-wrap gap-2 p-3">
										{can("study_group.update") ? (
											<StudyGroupDialog group={group} />
										) : null}
										{can("study_group.delete") && group.can_delete ? (
											<Confirm
												action={t("studyGroups.deleteName", {
													name: group.name,
												})}
												title={t("studyGroups.deleteTitle")}
												body={t("studyGroups.deleteBody")}
												onConfirm={() => onDelete(group)}
											/>
										) : null}
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
				onChange={(next) => setParams({ ...params, page: next })}
			/>
		</div>
	);
}
```

(`Confirm` labels its trigger with `action`; the test finds "Delete Evening circle" by that text. The search box's role is `searchbox` from `type="search"`.)

`dashboard/src/features/scheduling/index.ts`: `export { StudyGroupsList } from "./StudyGroupsList";`.

- [ ] **Step 5: The screen, the nav entry and the screen tables**

`dashboard/src/routes/_authed/people.groups.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { StudyGroupsList } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/people/groups/")({
	staticData: { permission: "study_group.view_any", feature: "study_groups" },
	component: function StudyGroupsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("studyGroups.title"));
		return (
			<>
				<PageHeader
					title={t("studyGroups.title")}
					description={t("studyGroups.subtitle")}
				/>
				<StudyGroupsList />
			</>
		);
	},
});
```

`dashboard/src/features/shell/nav.ts` — under `// ── phase B2 ──`, after B2e's "My availability" item:

```ts
	// Slice B2f: the office's study groups, next to families.
	office(
		"/people/groups",
		"studyGroups.nav",
		Users,
		"people",
		"study_group.view_any",
		"study_groups",
	),
```

`dashboard/src/features/shell/nav.test.ts` — insert `"/people/groups",` after `"/teaching/availability",` in the full list (under `// Slice B2e`, add `// Slice B2f`), add `"/people/groups"` to the "hides the items of every feature the academy has switched off" loop, and `"/people/groups": "study_groups",` to the feature map after B2e's two.

`dashboard/src/routes/permissions.test.ts` — insert `people\/groups|` at the start of the `FEATURE_WORDS` regex's alternation (keep every existing word), and under `FEATURE_SCREENS` add:

```ts
	// Slice B2f
	"/_authed/people/groups/": "study_groups",
```

Regenerate the route tree: `… exec -T dashboard pnpm exec vite build`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/StudyGroupsList.test.tsx src/features/scheduling/StudyGroupDialog.test.tsx src/features/shell src/routes`
Expected: PASS. Then `tsc --noEmit` and `pnpm lint`: clean.

- [ ] **Step 7: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/StudyGroupsList.tsx src/features/scheduling/StudyGroupDialog.tsx src/features/scheduling/StudyGroupsList.test.tsx src/features/scheduling/StudyGroupDialog.test.tsx src/features/scheduling/index.ts src/routes/_authed/people.groups.index.tsx src/features/shell/nav.ts src/features/shell/nav.test.ts src/routes/permissions.test.ts src/routeTree.gen.ts
git -C $W/dashboard commit -m "feat(scheduling): the study groups screen (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 15: One bundle row — course, teacher, package, price and slots

**Files:**
- Create: `dashboard/src/features/scheduling/BundleRowFields.tsx`
- Test: `dashboard/src/features/scheduling/BundleRowFields.test.tsx`

**Interfaces:**
- Consumes: `useChoices` (courses, teachers by course, packages), `SlotFields` (`prefix`), `BundleFormValues` (Task 13).
- Produces: `<BundleRowFields index students? onRemove? studentTime? />` inside a `FormProvider<BundleFormValues>`: a `<fieldset>` "Course {n}" with (when `students` is given — family rows) a Student select, then Course, Teacher (the course's own, reset when the course changes), Package (fills the price and the slot minutes), Price ({currency}), and the row's slot groups (add / remove). Field paths `rows.<index>.<name>`; server errors keyed the same way show under their field (plan D1). `TermFields` is not used or touched (plan D18).

- [ ] **Step 1: Write the failing test** (`dashboard/src/features/scheduling/BundleRowFields.test.tsx`)

```tsx
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useEffect } from "react";
import { FormProvider, useForm } from "react-hook-form";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { renderWithRouter } from "@/test/render";
import { page } from "@/test/scheduling-fixtures";
import { BundleRowFields } from "./BundleRowFields";
import type { BundleFormValues } from "./bundleSchemas";

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

const person = (id: number, full_name: string) => ({
	id,
	user: { full_name, timezone: "UTC" },
});
const monthly = {
	id: 5,
	name_ar: "شهري",
	name_en: "Monthly",
	sessions_total: 8,
	session_minutes: 50,
	duration_value: 1,
	duration_unit: "month",
	price_minor: 150000,
	currency: "EGP",
};

function Host({
	students,
	serverError,
	onRemove,
}: {
	students?: { id: number; full_name: string }[];
	serverError?: string;
	onRemove?: () => void;
}) {
	const methods = useForm<BundleFormValues>({
		defaultValues: {
			owner: "",
			starts_on: "2026-06-01",
			notes: "",
			supervisor: "",
			rows: [
				{
					student: "",
					course: "",
					teacher: "",
					package: "",
					price: "",
					slots: [{ weekdays: [], start_time: "", minutes: 45 }],
				},
			],
		},
	});
	useEffect(() => {
		if (serverError) {
			methods.setError("rows.0.package", { message: serverError });
		}
	}, [methods, serverError]);
	return (
		<FormProvider {...methods}>
			<BundleRowFields index={0} students={students} onRemove={onRemove} />
			<output aria-label="price">{methods.watch("rows.0.price")}</output>
			<output aria-label="minutes">
				{String(methods.watch("rows.0.slots.0.minutes"))}
			</output>
		</FormProvider>
	);
}

describe("BundleRowFields", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([person(21, "Bilal"), person(22, "Maryam")]) as never,
		);
		vi.mocked(catalogueApi.list).mockImplementation(
			async (kind) =>
				(kind === "courses"
					? page([
							{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [21] },
						])
					: page([monthly])) as never,
		);
	});

	it("offers the course's teachers and fills the price and minutes from the package", async () => {
		const user = userEvent.setup();
		renderWithRouter(<Host />);
		const row = await screen.findByRole("group", { name: "Course 1" });
		await user.selectOptions(
			await within(row).findByLabelText(/^Course/),
			"3",
		);
		expect(within(row).queryByRole("option", { name: "Maryam" })).toBeNull();
		await user.selectOptions(within(row).getByLabelText(/^Teacher/), "21");
		await user.selectOptions(within(row).getByLabelText(/^Package/), "5");
		expect(screen.getByLabelText("price")).toHaveTextContent("1500");
		expect(screen.getByLabelText("minutes")).toHaveTextContent("50");
		expect(within(row).getByLabelText(/^Price \(EGP\)/)).toHaveValue("1500.00");
	});

	it("names a family row's student from the family", async () => {
		renderWithRouter(
			<Host
				students={[
					{ id: 12, full_name: "Aisha" },
					{ id: 11, full_name: "Yusuf" },
				]}
			/>,
		);
		const row = await screen.findByRole("group", { name: "Course 1" });
		const student = within(row).getByLabelText(/^Student/);
		expect(
			within(student).getAllByRole("option").map((o) => o.textContent),
		).toEqual(["—", "Aisha", "Yusuf"]);
	});

	it("shows the server's error on its field and removes itself", async () => {
		const user = userEvent.setup();
		const onRemove = vi.fn();
		renderWithRouter(
			<Host serverError="Choose an active package." onRemove={onRemove} />,
		);
		expect(
			await screen.findByText("Choose an active package."),
		).toBeVisible();
		await user.click(screen.getByRole("button", { name: "Remove course 1" }));
		expect(onRemove).toHaveBeenCalled();
	});
});
```

(`toMajor(150000, "EGP")` is `"1500.00"`: the price field holds it, and the `price` output contains it.)

- [ ] **Step 2: Run it to see it fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/BundleRowFields.test.tsx`
Expected: FAIL — `Cannot find module './BundleRowFields'`.

- [ ] **Step 3: Implement** (`dashboard/src/features/scheduling/BundleRowFields.tsx`)

```tsx
import { Plus } from "lucide-react";
import { get, useFieldArray, useFormContext } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { toMajor } from "@/lib/money";
import { Button, Field, Input, Select } from "@/ui";
import { useLocalName } from "./bits";
import type { BundleFormValues } from "./bundleSchemas";
import { useChoices } from "./choices";
import { SlotFields } from "./SlotFields";

/**
 * Slice B2f §7: one bundle row — a subscription's course, teacher, package,
 * price and weekly slots; a family row also names its student (`students`,
 * the family's). Lives in the bundle form's `FormProvider`; every path is
 * `rows.<index>.<name>`, as the server keys a row's errors (plan D1).
 */
export function BundleRowFields({
	index,
	students,
	onRemove,
	studentTime,
}: {
	index: number;
	students?: { id: number; full_name: string }[];
	onRemove?: () => void;
	studentTime?: (time: string) => string | null;
}) {
	const { t } = useTranslation();
	const localName = useLocalName();
	const fieldError = useFieldError();
	const { courses, packages, packageById, teachersFor } = useChoices();
	const {
		control,
		register,
		setValue,
		watch,
		formState: { errors },
	} = useFormContext<BundleFormValues>();
	const path = `rows.${index}` as const;
	const slots = useFieldArray({ control, name: `${path}.slots` });
	const pkg = packageById(watch(`${path}.package`));
	const teachers = teachersFor(watch(`${path}.course`));
	const id = (name: string) => `rows-${index}-${name}`;
	const error = (name: string) =>
		fieldError(get(errors, `${path}.${name}`)?.message);
	const n = index + 1;

	return (
		<fieldset className="flex flex-col gap-4 rounded-lg border border-border p-4">
			<legend className="px-1 font-semibold">
				{t("bundles.form.row", { n })}
			</legend>
			<div className="grid gap-4 sm:grid-cols-2">
				{students ? (
					<Field
						id={id("student")}
						label={t("bundles.form.rowStudent")}
						error={error("student")}
						required
					>
						<Select {...register(`${path}.student`)}>
							<option value="">—</option>
							{students.map((s) => (
								<option key={s.id} value={s.id}>
									{s.full_name}
								</option>
							))}
						</Select>
					</Field>
				) : null}
				<Field
					id={id("course")}
					label={t("scheduling.columns.course")}
					error={error("course")}
					required
				>
					<Select
						{...register(`${path}.course`, {
							// A new course may not list the chosen teacher.
							onChange: () => setValue(`${path}.teacher`, ""),
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
					error={error("teacher")}
					required
				>
					<Select {...register(`${path}.teacher`)}>
						<option value="">—</option>
						{teachers.map((p) => (
							<option key={p.id} value={p.id}>
								{p.user.full_name}
							</option>
						))}
					</Select>
				</Field>
				<Field
					id={id("package")}
					label={t("scheduling.summary.package")}
					error={error("package")}
					required
				>
					<Select
						{...register(`${path}.package`, {
							onChange: (e) => {
								const chosen = packageById(e.target.value);
								if (!chosen) return;
								setValue(
									`${path}.price`,
									toMajor(chosen.price_minor, chosen.currency),
								);
								slots.fields.forEach((_, j) => {
									setValue(
										`${path}.slots.${j}.minutes`,
										chosen.session_minutes,
									);
								});
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
					id={id("price")}
					label={t("scheduling.form.price", { currency: pkg?.currency ?? "" })}
					error={error("price")}
					required
				>
					<Input inputMode="decimal" dir="ltr" {...register(`${path}.price`)} />
				</Field>
			</div>
			<div className="flex flex-col gap-3">
				<h3 className="text-sm font-medium">{t("scheduling.slots.title")}</h3>
				{slots.fields.map((group, j) => (
					<div
						key={group.id}
						className="flex flex-col gap-3 rounded-md border border-border p-3"
					>
						<SlotFields
							prefix={`${path}.slots.${j}.`}
							studentTime={studentTime}
						/>
						<Button
							type="button"
							variant="outline"
							size="sm"
							className="self-start"
							onClick={() => slots.remove(j)}
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
						slots.append({
							weekdays: [],
							start_time: "",
							minutes: pkg?.session_minutes ?? 45,
						})
					}
				>
					<Plus className="size-4" />
					{t("scheduling.slots.addGroup")}
				</Button>
				{error("slots") ? (
					<p className="text-sm text-destructive">{error("slots")}</p>
				) : null}
			</div>
			{onRemove ? (
				<Button
					type="button"
					variant="outline"
					size="sm"
					className="self-start"
					onClick={onRemove}
				>
					{t("bundles.form.removeRow", { n })}
				</Button>
			) : null}
		</fieldset>
	);
}
```

(SlotFields gives each input an id from its `prefix`, so two rows never share an id: `rows.0.slots.0.start_time` and `rows.1.slots.0.start_time`. `text-destructive` is a semantic token already used by `FormError`.)

- [ ] **Step 4: Run it to see it pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/BundleRowFields.test.tsx`
Expected: PASS. Then `tsc --noEmit`, `pnpm lint`.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/BundleRowFields.tsx src/features/scheduling/BundleRowFields.test.tsx
git -C $W/dashboard commit -m "feat(scheduling): one bundle row's fields (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 16: The bundle form for each kind, and the type choice on New subscription

**Files:**
- Create: `dashboard/src/features/scheduling/BundleForm.tsx`, `SubscriptionTypeChoice.tsx`
- Modify: `dashboard/src/features/scheduling/NewSubscription.tsx`
- Modify: `dashboard/src/routes/_authed/scheduling.subscriptions.new.tsx` (search `type`)
- Modify: `dashboard/src/routes/_authed/scheduling.subscriptions.new.test.ts` (the search validator)
- Test: `dashboard/src/features/scheduling/BundleForm.test.tsx`, `NewSubscription.test.tsx` (extend)

**Interfaces:**
- Consumes: `BundleRowFields` (Task 15); `bundleApi.create`, `useStudyGroups`, `bundleFormSchema` (Task 13); `useFamilies` (`@/features/people`); `useAcademySettings`; `SupervisorOptions`; `RadioCardGroup` (`@/ui`); `useHasFeature`, `useCan`.
- Produces: `<BundleForm kind />` (posts to the kind's route; no conflicts → `/scheduling/bundles/$bundleId`; conflicts → listed with "Open the bundle", plan D12); `<SubscriptionTypeChoice value onChange types />`; `availableTypes(hasFeature, can) -> SubscriptionType[]` with `type SubscriptionType = "individual" | BundleKind` (plan D20); `NewSubscription({ trialId?, type? })`. Route search `{ trial?: number; type?: BundleKind }`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/BundleForm.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { familyRow } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import {
	academySettings,
	bundleDetail,
	page,
	sessionRow,
	studyGroupRow,
} from "@/test/scheduling-fixtures";
import { BundleForm } from "./BundleForm";
import { bundleApi } from "./bundleApi";

vi.mock("./bundleApi", async (orig) => {
	const actual = await orig<typeof import("./bundleApi")>();
	return {
		...actual,
		bundleApi: { ...actual.bundleApi, create: vi.fn(), groups: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return {
		...actual,
		peopleApi: { ...actual.peopleApi, list: vi.fn(), families: vi.fn() },
	};
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, list: vi.fn() },
	};
});

const person = (id: number, full_name: string) => ({
	id,
	user: { full_name, timezone: "UTC" },
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
const BUNDLE_PAGE = "/scheduling/bundles/$bundleId";

async function fillRow(
	user: ReturnType<typeof userEvent.setup>,
	n: number,
	course: string,
) {
	const row = await screen.findByRole("group", { name: `Course ${n}` });
	await user.selectOptions(within(row).getByLabelText(/^Course/), course);
	await user.selectOptions(within(row).getByLabelText(/^Teacher/), "21");
	await user.selectOptions(within(row).getByLabelText(/^Package/), "5");
	// Review I-2: a row starts with one slot group, as the subscription form
	// does; it must have a day and a time before the form submits.
	await user.click(within(row).getByLabelText("Mon"));
	await user.type(within(row).getByLabelText(/^Start time/), "18:00");
	return row;
}

describe("BundleForm", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(peopleApi.list).mockImplementation(
			async (kind) =>
				(kind === "students"
					? page([person(11, "Yusuf")])
					: page([person(21, "Bilal")])) as never,
		);
		vi.mocked(peopleApi.families).mockResolvedValue(
			page([familyRow({ id: 2, name: "Omar family" })]) as never,
		);
		vi.mocked(bundleApi.groups).mockResolvedValue(
			page([studyGroupRow()]) as never,
		);
		vi.mocked(catalogueApi.list).mockImplementation(
			async (kind) =>
				(kind === "courses"
					? page([
							{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [] },
							{ id: 4, name_ar: "فقه", name_en: "Fiqh", teacher_ids: [] },
						])
					: page([monthly])) as never,
		);
		vi.mocked(bundleApi.create).mockResolvedValue(
			bundleDetail({ id: 9, conflicts: [] }),
		);
	});

	it("creates a multi-course bundle and opens it", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BundleForm kind="multi_course" />, {
			extraPaths: [BUNDLE_PAGE],
		});
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		await fillRow(user, 1, "3");
		await fillRow(user, 2, "4");
		const totals = screen.getByRole("list", { name: "Totals" });
		expect(within(totals).getByText("16")).toBeVisible();
		await user.click(screen.getByRole("button", { name: "Create bundle" }));
		await waitFor(() =>
			expect(bundleApi.create).toHaveBeenCalledWith(
				expect.objectContaining({
					kind: "multi_course",
					student_id: 11,
					rows: [
						expect.objectContaining({
							course: 3,
							teacher: 21,
							package: 5,
							price_minor: 150000,
							slots: [{ weekdays: [0], start_time: "18:00", minutes: 45 }],
						}),
						expect.objectContaining({ course: 4, price_minor: 150000 }),
					],
				}),
			),
		);
		expect(await screen.findByText(`at ${BUNDLE_PAGE}`)).toBeVisible();
	});

	it("takes a family's students on its rows", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BundleForm kind="family" />, { extraPaths: [BUNDLE_PAGE] });
		await user.selectOptions(await screen.findByLabelText(/^Family/), "2");
		const first = await fillRow(user, 1, "3");
		await user.selectOptions(within(first).getByLabelText(/^Student/), "12");
		const second = await fillRow(user, 2, "3");
		await user.selectOptions(within(second).getByLabelText(/^Student/), "11");
		await user.click(screen.getByRole("button", { name: "Create bundle" }));
		await waitFor(() =>
			expect(bundleApi.create).toHaveBeenCalledWith(
				expect.objectContaining({
					kind: "family",
					family_id: 2,
					rows: [
						expect.objectContaining({ student: 12, course: 3 }),
						expect.objectContaining({ student: 11, course: 3 }),
					],
				}),
			),
		);
	});

	it("subscribes a study group with one row", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BundleForm kind="group" />, { extraPaths: [BUNDLE_PAGE] });
		await user.selectOptions(await screen.findByLabelText(/^Study group/), "4");
		expect(
			screen.getByText(/Active students who will be subscribed: 2/),
		).toBeVisible();
		await fillRow(user, 1, "3");
		expect(screen.queryByRole("group", { name: "Course 2" })).toBeNull();
		expect(screen.queryByRole("button", { name: "Add a course" })).toBeNull();
		await user.click(screen.getByRole("button", { name: "Create bundle" }));
		await waitFor(() =>
			expect(bundleApi.create).toHaveBeenCalledWith(
				expect.objectContaining({ kind: "group", group_id: 4 }),
			),
		);
	});

	it("puts the server's errors on the row and the owner", async () => {
		const user = userEvent.setup();
		const error = new AxiosError("bad");
		error.response = {
			status: 400,
			data: {
				"rows.1.package": ["Choose an active package."],
				"rows.0.price_minor": ["Enter a price."],
				student_id: ["Choose an active student."],
			},
		} as AxiosResponse;
		vi.mocked(bundleApi.create).mockRejectedValueOnce(error);
		renderWithRouter(<BundleForm kind="multi_course" />);
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		await fillRow(user, 1, "3");
		const second = await fillRow(user, 2, "4");
		await user.click(screen.getByRole("button", { name: "Create bundle" }));
		expect(
			await within(second).findByText("Choose an active package."),
		).toBeVisible();
		expect(screen.getByText("Enter a price.")).toBeVisible();
		expect(screen.getByText("Choose an active student.")).toBeVisible();
	});

	it("lists the clashes it reports and links the bundle", async () => {
		const user = userEvent.setup();
		vi.mocked(bundleApi.create).mockResolvedValue(
			bundleDetail({
				id: 9,
				conflicts: [
					{ session: sessionRow(), other: sessionRow({ id: 42 }) },
				],
			}),
		);
		renderWithRouter(<BundleForm kind="multi_course" />, {
			extraPaths: [BUNDLE_PAGE],
		});
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		await fillRow(user, 1, "3");
		await fillRow(user, 2, "4");
		await user.click(screen.getByRole("button", { name: "Create bundle" }));
		expect(
			await screen.findByRole("link", { name: "Open the bundle" }),
		).toHaveAttribute("href", "/scheduling/bundles/9");
	});
});
```

Extend `dashboard/src/features/scheduling/NewSubscription.test.tsx` (it already mocks the people, catalogue, academy and scheduling APIs; also mock `./bundleApi`'s `groups` to `page([])` and `@/features/people/api`'s `families` to `page([])`, and import `adminWith` from `@/test/access-fixtures`, `CanProvider` from `@/features/identity/permissions`):

```tsx
	it("offers the bundle types the academy has on", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<CanProvider
				me={adminWith(
					"multi_course_subscriptions",
					"study_groups",
					"group_subscriptions",
				)}
			>
				<NewSubscription />
			</CanProvider>,
		);
		const types = await screen.findByRole("radiogroup", {
			name: "Subscription type",
		});
		// Each radio is named by its label alone; no Family without its switch.
		expect(within(types).getAllByRole("radio")).toHaveLength(3);
		for (const name of ["Individual", "Multi-course", "Group"]) {
			expect(within(types).getByRole("radio", { name })).toBeVisible();
		}
		await user.click(within(types).getByRole("radio", { name: "Multi-course" }));
		expect(
			await screen.findByRole("button", { name: "Create bundle" }),
		).toBeVisible();
	});

	it("shows no choice while no bundle type is on", async () => {
		renderWithRouter(
			<CanProvider me={adminWith()}>
				<NewSubscription />
			</CanProvider>,
		);
		expect(
			await screen.findByRole("button", { name: "Create subscription" }),
		).toBeVisible();
		expect(screen.queryByRole("radiogroup")).toBeNull();
	});

	it("opens on the type the link names", async () => {
		renderWithRouter(
			<CanProvider me={adminWith("multi_course_subscriptions")}>
				<NewSubscription type="multi_course" />
			</CanProvider>,
		);
		expect(
			await screen.findByRole("button", { name: "Create bundle" }),
		).toBeVisible();
	});
```


`dashboard/src/routes/_authed/scheduling.subscriptions.new.test.ts` — add cases to its search-validator test: `{ type: "group" }` → `{ type: "group" }`; `{ type: "bogus" }` → `{}`; `{ trial: "5", type: "family" }` → `{ trial: 5, type: "family" }`.

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/BundleForm.test.tsx src/features/scheduling/NewSubscription.test.tsx src/routes/_authed/scheduling.subscriptions.new.test.ts`
Expected: FAIL — `Cannot find module './BundleForm'`.

- [ ] **Step 3: The form** (`dashboard/src/features/scheduling/BundleForm.tsx`)

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { Link, useNavigate } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState } from "react";
import { FormProvider, useFieldArray, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useAcademySettings } from "@/features/academy/queries";
import { useFamilies, usePeople } from "@/features/people";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import { formatMoney, toMinor } from "@/lib/money";
import { formatDay, todayIn } from "@/lib/zoned-time";
import {
	Alert,
	AlertDescription,
	Button,
	Field,
	Input,
	Select,
	Spinner,
	SubmitButton,
	Textarea,
} from "@/ui";
import { useLocalName } from "./bits";
import { BundleRowFields } from "./BundleRowFields";
import { bundleApi } from "./bundleApi";
import { useStudyGroups } from "./bundleQueries";
import {
	type BundleDetail,
	type BundleFormValues,
	type BundleKind,
	type BundleRowValues,
	bundleFormSchema,
} from "./bundleSchemas";
import { useChoices } from "./choices";
import { useSchedulingMutation } from "./queries";
import { SupervisorOptions } from "./SupervisorOptions";

const ACTIVE = { is_active: "true", page_size: 100 } as const;
const OWNER_KEY = {
	multi_course: "student_id",
	family: "family_id",
	group: "group_id",
} as const;
const OWNER_LABEL = {
	multi_course: "bundles.form.student",
	family: "bundles.form.family",
	group: "bundles.form.group",
} as const;

const blankRow = (): BundleRowValues => ({
	student: "",
	course: "",
	teacher: "",
	package: "",
	price: "",
	slots: [{ weekdays: [], start_time: "", minutes: 45 }],
});

/**
 * Slice B2f §7: a bundle of one kind — its owner (a student, a family or a
 * study group), the start, then its rows (one for a group: every active
 * student gets it). Totals show live from the chosen packages. The server
 * decides everything else and keys a row's errors `rows.<i>.<field>`.
 */
export function BundleForm({ kind }: { kind: BundleKind }) {
	const { t, i18n } = useTranslation();
	const navigate = useNavigate();
	const fieldError = useFieldError();
	const [query, setQuery] = useState("");
	const [created, setCreated] = useState<BundleDetail | null>(null);
	const { data: academy } = useAcademySettings();
	const { packageById } = useChoices();
	const { data: students } = usePeople(
		"students",
		{ ...ACTIVE, q: query.trim() },
		{ enabled: kind === "multi_course" },
	);
	const { data: families } = useFamilies(ACTIVE, { enabled: kind === "family" });
	const { data: groups } = useStudyGroups(ACTIVE, { enabled: kind === "group" });
	const create = useSchedulingMutation(bundleApi.create);
	const methods = useForm<BundleFormValues>({
		resolver: zodResolver(bundleFormSchema),
		values: academy
			? {
					owner: "",
					starts_on: todayIn(academy.timezone),
					notes: "",
					supervisor: "",
					rows: kind === "group" ? [blankRow()] : [blankRow(), blankRow()],
				}
			: undefined,
	});
	const {
		control,
		register,
		handleSubmit,
		setError,
		watch,
		formState: { errors, isSubmitting },
	} = methods;
	const rows = useFieldArray({ control, name: "rows" });
	const supervision = academy?.supervision_enabled === true;
	const owner = watch("owner");
	const family = families?.results.find((f) => String(f.id) === owner);
	const group = groups?.results.find((g) => String(g.id) === owner);
	const activeMembers = group?.members.filter((m) => m.is_active).length ?? 0;
	// A group's one row is every active student's: totals count them all.
	const times = kind === "group" ? Math.max(activeMembers, 1) : 1;
	const chosen = watch("rows").map((row) => ({
		row,
		pkg: packageById(row.package),
	}));
	const sessions = chosen.reduce(
		(sum, { pkg }) => sum + (pkg ? pkg.sessions_total * times : 0),
		0,
	);
	const prices = new Map<string, number>();
	for (const { row, pkg } of chosen) {
		if (!pkg || !/^\d+(\.\d{1,3})?$/.test(row.price)) continue;
		const minor = toMinor(row.price, pkg.currency) * times;
		prices.set(pkg.currency, (prices.get(pkg.currency) ?? 0) + minor);
	}

	async function onSubmit(values: BundleFormValues) {
		try {
			const bundle = await create.mutateAsync({
				kind,
				[OWNER_KEY[kind]]: Number(values.owner),
				starts_on: values.starts_on,
				notes: values.notes,
				rows: values.rows.map((row) => ({
					...(kind === "family" ? { student: Number(row.student) } : {}),
					course: Number(row.course),
					teacher: Number(row.teacher),
					package: Number(row.package),
					price_minor: toMinor(
						row.price,
						packageById(row.package)?.currency ?? "USD",
					),
					slots: row.slots,
				})),
				...(supervision
					? {
							supervisor_id: values.supervisor
								? Number(values.supervisor)
								: null,
						}
					: {}),
			});
			if (bundle.conflicts?.length) {
				setCreated(bundle);
				return;
			}
			navigate({
				to: "/scheduling/bundles/$bundleId",
				params: { bundleId: String(bundle.id) },
			});
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			for (const [key, message] of Object.entries(parsed.fieldErrors)) {
				const price = /^rows\.(\d+)\.price_minor$/.exec(key);
				if (price) {
					setError(`rows.${Number(price[1])}.price`, { message });
				}
			}
			const ownerError = parsed.fieldErrors[OWNER_KEY[kind]];
			if (ownerError) setError("owner", { message: ownerError });
			if (parsed.fieldErrors.supervisor_id) {
				setError("supervisor", { message: parsed.fieldErrors.supervisor_id });
			}
			if (parsed.fieldErrors.rows) {
				setError("root.server", { message: parsed.fieldErrors.rows });
			}
		}
	}

	if (!academy) return <Spinner />;
	if (created) return <Clashes bundle={created} />;

	return (
		<FormProvider {...methods}>
			<form
				onSubmit={handleSubmit(onSubmit)}
				className="flex flex-col gap-6"
				noValidate
			>
				<div className="grid gap-4 sm:grid-cols-2">
					{kind === "multi_course" ? (
						<Field id="bundle-find" label={t("bundles.form.findStudent")}>
							<Input
								type="search"
								value={query}
								onChange={(e) => setQuery(e.target.value)}
							/>
						</Field>
					) : null}
					<Field
						id="bundle-owner"
						label={t(OWNER_LABEL[kind])}
						error={fieldError(errors.owner?.message)}
						required
					>
						<Select {...register("owner")}>
							<option value="">—</option>
							{kind === "multi_course"
								? students?.results.map((p) => (
										<option key={p.id} value={p.id}>
											{p.user.full_name}
										</option>
									))
								: null}
							{kind === "family"
								? families?.results.map((f) => (
										<option key={f.id} value={f.id}>
											{f.name}
										</option>
									))
								: null}
							{kind === "group"
								? groups?.results.map((g) => (
										<option key={g.id} value={g.id}>
											{g.name}
										</option>
									))
								: null}
						</Select>
					</Field>
					<Field
						id="bundle-starts"
						label={t("bundles.form.startsOn")}
						error={fieldError(errors.starts_on?.message)}
						required
					>
						<Input type="date" dir="ltr" {...register("starts_on")} />
					</Field>
					{supervision ? (
						<Field
							id="bundle-supervisor"
							label={t("scheduling.supervision.supervisor")}
							error={fieldError(errors.supervisor?.message)}
						>
							<Select {...register("supervisor")}>
								<SupervisorOptions />
							</Select>
						</Field>
					) : null}
				</div>
				{group ? (
					<p className="rounded-md bg-secondary p-3 text-sm">
						{t("bundles.form.groupMembers", { count: activeMembers })}{" "}
						{t("bundles.form.perStudent")}
					</p>
				) : null}
				<section className="flex flex-col gap-4">
					<h2 className="font-semibold">{t("bundles.form.rows")}</h2>
					{rows.fields.map((field, index) => (
						<BundleRowFields
							key={field.id}
							index={index}
							students={kind === "family" ? (family?.students ?? []) : undefined}
							onRemove={
								kind === "group" ? undefined : () => rows.remove(index)
							}
						/>
					))}
					{kind === "group" ? null : (
						<Button
							type="button"
							variant="outline"
							size="sm"
							className="self-start"
							onClick={() => rows.append(blankRow())}
						>
							<Plus className="size-4" />
							{t("bundles.form.addRow")}
						</Button>
					)}
				</section>
				<ul
					aria-label={t("bundles.totals.title")}
					className="flex flex-wrap gap-6 rounded-md border border-border p-3 text-sm"
				>
					<li className="flex flex-col">
						<span className="text-muted-foreground">
							{t("bundles.totals.sessions")}
						</span>
						<span className="font-semibold">{sessions}</span>
					</li>
					{[...prices].map(([currency, minor]) => (
						<li key={currency} className="flex flex-col">
							<span className="text-muted-foreground">
								{t("bundles.totals.price")}
							</span>
							<span className="font-semibold" dir="ltr">
								{formatMoney(minor, currency, i18n.language)}
							</span>
						</li>
					))}
				</ul>
				<Field id="bundle-notes" label={t("bundles.form.notes")}>
					<Textarea rows={3} {...register("notes")} />
				</Field>
				{errors.root?.server ? (
					<Alert variant="destructive">
						<AlertDescription>
							{fieldError(errors.root.server.message)}
						</AlertDescription>
					</Alert>
				) : null}
				<SubmitButton pending={isSubmitting} className="self-start">
					{t("bundles.form.create")}
				</SubmitButton>
			</form>
		</FormProvider>
	);
}

/** Plan D12: the members' new sessions overlap other sessions of their
 * teacher — reported, never blocked (P4-9) — and the bundle is open. */
function Clashes({ bundle }: { bundle: BundleDetail }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	return (
		<div className="flex flex-col gap-4">
			<Alert>
				<AlertDescription>{t("bundles.form.clashes")}</AlertDescription>
			</Alert>
			<ul className="flex flex-col gap-2 text-sm">
				{(bundle.conflicts ?? []).map(({ session, other }) => (
					<li key={`${session.id}-${other.id}`}>
						{t("bundles.form.clash", {
							student: session.student.full_name,
							when: formatDay(session.occurs_on, i18n.language),
							other: `${other.student.full_name} — ${localName(other.course)}`,
						})}
					</li>
				))}
			</ul>
			<Button asChild className="self-start">
				<Link
					to="/scheduling/bundles/$bundleId"
					params={{ bundleId: String(bundle.id) }}
				>
					{t("bundles.form.open")}
				</Link>
			</Button>
		</div>
	);
}
```


- [ ] **Step 4: The type choice** (`dashboard/src/features/scheduling/SubscriptionTypeChoice.tsx`)

```tsx
import { useTranslation } from "react-i18next";
import type { FeatureCode } from "@/features/identity/schemas";
import { RadioCardGroup } from "@/ui";
import type { BundleKind } from "./bundleSchemas";

export type SubscriptionType = "individual" | BundleKind;

/** Plan D20: a bundle type is offered while its switch is on and the viewer
 * may read its owner picker (families, study groups). */
export function availableTypes(
	hasFeature: (code: FeatureCode) => boolean,
	can: (code: string) => boolean,
): SubscriptionType[] {
	const types: SubscriptionType[] = ["individual"];
	if (hasFeature("multi_course_subscriptions")) types.push("multi_course");
	if (hasFeature("family_subscriptions") && can("family.view_any")) {
		types.push("family");
	}
	if (hasFeature("group_subscriptions") && can("study_group.view_any")) {
		types.push("group");
	}
	return types;
}

/** Slice B2f §7: individual, multi-course, family or group. */
export function SubscriptionTypeChoice({
	types,
	value,
	onChange,
}: {
	types: SubscriptionType[];
	value: SubscriptionType;
	onChange: (type: SubscriptionType) => void;
}) {
	const { t } = useTranslation();
	return (
		<RadioCardGroup
			label={t("bundles.types.label")}
			value={value}
			onValueChange={(next) => onChange(next as SubscriptionType)}
			options={types.map((type) => ({
				value: type,
				label: t(`bundles.types.${type}`),
				description: t(`bundles.types.${type}Hint`),
			}))}
		/>
	);
}
```

`dashboard/src/features/scheduling/NewSubscription.tsx` becomes:

```tsx
import { isAxiosError } from "axios";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCan, useHasFeature } from "@/features/identity/permissions";
import { Alert, AlertDescription, Spinner } from "@/ui";
import { BundleForm } from "./BundleForm";
import type { BundleKind } from "./bundleSchemas";
import { useTrial } from "./queries";
import { SubscriptionForm } from "./SubscriptionForm";
import {
	availableTypes,
	type SubscriptionType,
	SubscriptionTypeChoice,
} from "./SubscriptionTypeChoice";

/** The new-subscription form; with `trialId` it converts that trial (plan
 * D14), waiting for it, or saying why it cannot be loaded. Slice B2f: a type
 * choice leads to the bundle form while a bundle type is available (`type`
 * opens on it). */
export function NewSubscription({
	trialId,
	type,
}: {
	trialId?: number;
	type?: BundleKind;
}) {
	const { t } = useTranslation();
	const can = useCan();
	const hasFeature = useHasFeature();
	const types = availableTypes(hasFeature, can);
	const [chosen, setChosen] = useState<SubscriptionType>(
		type && types.includes(type) ? type : "individual",
	);
	const { data: trial, isError, error } = useTrial(trialId);
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
	if (trialId !== undefined && !trial) return <Spinner />;
	if (trialId !== undefined || types.length === 1) {
		return <SubscriptionForm trial={trial} />;
	}
	return (
		<div className="flex flex-col gap-6">
			<SubscriptionTypeChoice types={types} value={chosen} onChange={setChosen} />
			{chosen === "individual" ? (
				<SubscriptionForm />
			) : (
				<BundleForm key={chosen} kind={chosen} />
			)}
		</div>
	);
}
```

`dashboard/src/routes/_authed/scheduling.subscriptions.new.tsx` — the validator and the route component:

```tsx
import { BUNDLE_KINDS, type BundleKind, NewSubscription } from "@/features/scheduling";

	// Slice B2e (plan D14): converting a trial opens this form pre-filled.
	// Slice B2f (plan D19): `type` opens on a bundle type.
	validateSearch: (
		search: Record<string, unknown>,
	): { trial?: number; type?: BundleKind } => {
		const trial = Number(search.trial);
		const type = BUNDLE_KINDS.find((kind) => kind === search.type);
		return {
			...(Number.isInteger(trial) && trial > 0 ? { trial } : {}),
			...(type ? { type } : {}),
		};
	},
	component: function NewSubscriptionRoute() {
		const { t } = useTranslation();
		const { trial: trialId, type } = Route.useSearch();
		usePageTitle(t("scheduling.new"));
		return (
			<>
				<PageHeader title={t("scheduling.new")} />
				<NewSubscription trialId={trialId} type={type} />
			</>
		);
	},
```

`dashboard/src/features/scheduling/index.ts`: `export { BundleForm } from "./BundleForm";`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling src/routes`
Expected: PASS (the B2e trial-conversion tests of `NewSubscription` / `SubscriptionForm` unchanged). Then `tsc --noEmit`, `pnpm lint`.

- [ ] **Step 6: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/BundleForm.tsx src/features/scheduling/BundleForm.test.tsx src/features/scheduling/SubscriptionTypeChoice.tsx src/features/scheduling/NewSubscription.tsx src/features/scheduling/NewSubscription.test.tsx src/features/scheduling/index.ts src/routes/_authed/scheduling.subscriptions.new.tsx src/routes/_authed/scheduling.subscriptions.new.test.ts
git -C $W/dashboard commit -m "feat(scheduling): new multi-course, family and group bundles from New subscription (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 17: The bundle page — owner, totals, notes, members and roster

**Files:**
- Create: `dashboard/src/features/scheduling/BundlePage.tsx`, `BundleMembers.tsx`, `BundleRoster.tsx`, `BundleNotesDialog.tsx`
- Modify: `dashboard/src/features/scheduling/index.ts` (`BundlePage`)
- Modify: `dashboard/src/routes/_authed/scheduling.bundles.$bundleId.tsx` (Task 13's minimal screen now renders `BundlePage`)
- Test: `dashboard/src/features/scheduling/BundlePage.test.tsx`

**Interfaces:**
- Consumes: `useBundle`, `bundleApi.updateNotes` (Task 13); `SubscriptionStatusChip`, `useLocalName` (`./bits`); `Fact`; `formatMoney`, `formatDay`; `useCan`.
- Produces: `<BundlePage bundleId: string />` (a header card: kind, state, owner link, created by, totals; notes with an Edit dialog for `subscription.update`; a tablist Members / Roster); `<BundleMembers bundle />` (table "Members": student → the member's subscription page, course, teacher, status, ends, Current / Earlier term); `<BundleRoster bundle actions? />` (table "Roster": student, user id, course, teacher, status, attended, and `actions(row)` — Task 18's Remove). The route `/scheduling/bundles/$bundleId` (Task 13; `subscription.view`, no feature: plan D19) renders it.

- [ ] **Step 1: Write the failing test** (`dashboard/src/features/scheduling/BundlePage.test.tsx`)

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, type AxiosResponse } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { CanProvider } from "@/features/identity/permissions";
import { staffMe } from "@/test/access-fixtures";
import { renderWithRouter } from "@/test/render";
import {
	bundleDetail,
	bundleMember,
	page,
	rosterRow,
} from "@/test/scheduling-fixtures";
import { bundleApi } from "./bundleApi";
import { BundlePage } from "./BundlePage";

vi.mock("./bundleApi", async (orig) => {
	const actual = await orig<typeof import("./bundleApi")>();
	return {
		...actual,
		bundleApi: {
			...actual.bundleApi,
			bundle: vi.fn(),
			updateNotes: vi.fn(),
		},
	};
});
// Task 18's actions read the people list for "Add a student".
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return {
		...actual,
		peopleApi: { ...actual.peopleApi, list: vi.fn(async () => page([]) as never) },
	};
});

const SUBSCRIPTION = "/scheduling/subscriptions/$subscriptionId";

describe("BundlePage", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(bundleApi.bundle).mockResolvedValue(
			bundleDetail({
				notes: "Evenings only",
				members: [
					bundleMember({ id: 7, current: false, status: "expired" }),
					bundleMember({ id: 8, renewed_from: 7 }),
				],
				totals: {
					sessions_total: 16,
					prices: [
						{ currency: "EGP", price_minor: 150000 },
						{ currency: "USD", price_minor: 4000 },
					],
				},
				roster: [rosterRow({ subscription_id: 8, attended: 3 })],
			}),
		);
		vi.mocked(bundleApi.updateNotes).mockResolvedValue(bundleDetail());
	});

	it("shows the owner, the state and the totals per currency", async () => {
		renderWithRouter(<BundlePage bundleId="9" />, {
			extraPaths: ["/people/groups"],
		});
		expect(
			await screen.findByRole("link", { name: "Evening circle" }),
		).toHaveAttribute("href", "/people/groups");
		expect(screen.getByText("Group")).toBeVisible();
		expect(screen.getByText("Live")).toBeVisible();
		expect(screen.getByText("16")).toBeVisible();
		// Never summed across currencies (plan D16).
		expect(screen.getByText("EGP 1,500.00")).toBeVisible();
		expect(screen.getByText("$40.00")).toBeVisible();
		expect(screen.getByText("Evenings only")).toBeVisible();
	});

	it("lists the members, the current one marked, each linking its subscription", async () => {
		renderWithRouter(<BundlePage bundleId="9" />, { extraPaths: [SUBSCRIPTION] });
		const members = await screen.findByRole("table", { name: "Members" });
		const rows = within(members).getAllByRole("row").slice(1);
		expect(rows[0]).toHaveTextContent("Earlier term");
		expect(rows[1]).toHaveTextContent("Current");
		expect(within(rows[1]).getByRole("link", { name: "Yusuf" })).toHaveAttribute(
			"href",
			"/scheduling/subscriptions/8",
		);
	});

	it("shows the roster on its tab", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BundlePage bundleId="9" />);
		await user.click(await screen.findByRole("tab", { name: "Roster" }));
		const roster = screen.getByRole("table", { name: "Roster" });
		const row = within(roster).getAllByRole("row")[1];
		expect(row).toHaveTextContent("11");
		expect(row).toHaveTextContent("Tajweed");
		expect(row).toHaveTextContent("3");
	});

	it("edits the notes", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BundlePage bundleId="9" />);
		await user.click(await screen.findByRole("button", { name: "Edit notes" }));
		const notes = screen.getByLabelText("Notes", { selector: "textarea" });
		await user.clear(notes);
		await user.type(notes, "Mornings");
		await user.click(screen.getByRole("button", { name: "Save notes" }));
		await waitFor(() =>
			expect(bundleApi.updateNotes).toHaveBeenCalledWith({
				id: 9,
				notes: "Mornings",
			}),
		);
	});

	it("hides the notes' Edit without subscription.update", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("subscription.view")}>
				<BundlePage bundleId="9" />
			</CanProvider>,
		);
		await screen.findByText("Evenings only");
		expect(screen.queryByRole("button", { name: "Edit notes" })).toBeNull();
	});

	it("says when the bundle is not there", async () => {
		const error = new AxiosError("missing");
		error.response = { status: 404, data: {} } as AxiosResponse;
		vi.mocked(bundleApi.bundle).mockRejectedValue(error);
		renderWithRouter(<BundlePage bundleId="9" />);
		expect(
			await screen.findByText("This bundle doesn't exist."),
		).toBeVisible();
	});
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/BundlePage.test.tsx`
Expected: FAIL — `Cannot find module './BundlePage'`.

- [ ] **Step 3: The members and roster tables**

`dashboard/src/features/scheduling/BundleMembers.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { formatDay } from "@/lib/zoned-time";
import { StatusChip } from "@/ui";
import { SubscriptionStatusChip, useLocalName } from "./bits";
import type { BundleDetail } from "./bundleSchemas";

const LINK =
	"font-medium text-primary-text underline-offset-4 hover:underline";

/** §4.5: every member, oldest first; the current ones (the last link of
 * each renewal chain, plan D4) marked. */
export function BundleMembers({ bundle }: { bundle: BundleDetail }) {
	const { t, i18n } = useTranslation();
	const localName = useLocalName();
	const columns = ["student", "course", "teacher", "status", "ends"] as const;
	return (
		<div className="overflow-x-auto rounded-lg border border-border">
			<table aria-label={t("bundles.tabs.members")} className="w-full text-sm">
				<thead className="bg-secondary text-muted-foreground">
					<tr>
						{columns.map((key) => (
							<th key={key} scope="col" className="p-3 text-start font-medium">
								{t(`bundles.members.${key}`)}
							</th>
						))}
						<th scope="col" className="p-3 text-start font-medium">
							<span className="sr-only">{t("bundles.members.current")}</span>
						</th>
					</tr>
				</thead>
				<tbody>
					{bundle.members.map((member) => (
						<tr key={member.id} className="border-t border-border">
							<td className="p-3">
								<Link
									to="/scheduling/subscriptions/$subscriptionId"
									params={{ subscriptionId: String(member.id) }}
									className={LINK}
								>
									{member.student.full_name}
								</Link>
							</td>
							<td className="p-3">{localName(member.course)}</td>
							<td className="p-3">{member.teacher.full_name}</td>
							<td className="p-3">
								<SubscriptionStatusChip status={member.status} />
							</td>
							<td className="p-3">{formatDay(member.ends_on, i18n.language)}</td>
							<td className="p-3">
								<StatusChip tone={member.current ? "live" : "neutral"}>
									{t(
										member.current
											? "bundles.members.current"
											: "bundles.members.earlier",
									)}
								</StatusChip>
							</td>
						</tr>
					))}
				</tbody>
			</table>
		</div>
	);
}
```

`dashboard/src/features/scheduling/BundleRoster.tsx`:

```tsx
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { SubscriptionStatusChip, useLocalName } from "./bits";
import type { BundleDetail, RosterRow } from "./bundleSchemas";

/** F-10 (TH SUB-008): per student, their user id, their member's course,
 * teacher and status, and the sessions they attended here. `actions` adds a
 * row's buttons (Task 18's Remove). */
export function BundleRoster({
	bundle,
	actions,
}: {
	bundle: BundleDetail;
	actions?: (row: RosterRow) => ReactNode;
}) {
	const { t } = useTranslation();
	const localName = useLocalName();
	const columns = [
		"student",
		"userId",
		"course",
		"teacher",
		"status",
		"attended",
	] as const;
	return (
		<div className="overflow-x-auto rounded-lg border border-border">
			<table aria-label={t("bundles.tabs.roster")} className="w-full text-sm">
				<thead className="bg-secondary text-muted-foreground">
					<tr>
						{columns.map((key) => (
							<th key={key} scope="col" className="p-3 text-start font-medium">
								{t(`bundles.roster.${key}`)}
							</th>
						))}
						{actions ? (
							<th scope="col" className="p-3">
								<span className="sr-only">{t("bundles.actions.label")}</span>
							</th>
						) : null}
					</tr>
				</thead>
				<tbody>
					{bundle.roster.map((row) => (
						<tr key={row.student.id} className="border-t border-border">
							<td className="p-3 font-medium">{row.student.full_name}</td>
							<td className="p-3" dir="ltr">
								{row.student.id}
							</td>
							<td className="p-3">{localName(row.course)}</td>
							<td className="p-3">{row.teacher.full_name}</td>
							<td className="p-3">
								<SubscriptionStatusChip status={row.status} />
							</td>
							<td className="p-3">{row.attended}</td>
							{actions ? <td className="p-3">{actions(row)}</td> : null}
						</tr>
					))}
				</tbody>
			</table>
		</div>
	);
}
```

- [ ] **Step 4: Notes and the page**

`dashboard/src/features/scheduling/BundleNotesDialog.tsx`:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { errorText } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Textarea,
} from "@/ui";
import { bundleApi } from "./bundleApi";
import type { BundleDetail } from "./bundleSchemas";
import { useSchedulingMutation } from "./queries";

export function BundleNotesDialog({ bundle }: { bundle: BundleDetail }) {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	const [notes, setNotes] = useState(bundle.notes);
	const [failed, setFailed] = useState<string | null>(null);
	const save = useSchedulingMutation(bundleApi.updateNotes);

	async function onSave() {
		try {
			await save.mutateAsync({ id: bundle.id, notes });
			setOpen(false);
		} catch (error) {
			setFailed(errorText(error, t));
		}
	}

	return (
		<Dialog
			open={open}
			onOpenChange={(next) => {
				setNotes(bundle.notes);
				setFailed(null);
				setOpen(next);
			}}
		>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("bundles.notes.edit")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("bundles.notes.title")}</DialogTitle>
				<Field id="bundle-notes" label={t("bundles.notes.title")}>
					<Textarea
						rows={4}
						value={notes}
						onChange={(e) => setNotes(e.target.value)}
					/>
				</Field>
				{failed ? (
					<Alert variant="destructive">
						<AlertDescription>{failed}</AlertDescription>
					</Alert>
				) : null}
				<DialogFooter>
					<DialogClose asChild>
						<Button type="button" variant="outline">
							{t("people.cancel")}
						</Button>
					</DialogClose>
					<Button type="button" onClick={onSave} disabled={save.isPending}>
						{t("bundles.notes.save")}
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
```

(The test reads the textarea by its label "Notes" with `selector: "textarea"`: the field's label is `bundles.notes.title` — "Notes".)

`dashboard/src/features/scheduling/BundlePage.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { isAxiosError } from "axios";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import { useCan } from "@/features/identity/permissions";
import { formatMoney } from "@/lib/money";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
	StatusChip,
} from "@/ui";
import { BundleMembers } from "./BundleMembers";
import { BundleNotesDialog } from "./BundleNotesDialog";
import { useBundle } from "./bundleQueries";
import { BundleRoster } from "./BundleRoster";
import type { BundleDetail } from "./bundleSchemas";

const LINK =
	"font-medium text-primary-text underline-offset-4 hover:underline";
const TABS = ["members", "roster"] as const;

function Owner({ bundle }: { bundle: BundleDetail }) {
	if (bundle.student) {
		return (
			<Link
				to="/people/students/$personId"
				params={{ personId: String(bundle.student.id) }}
				className={LINK}
			>
				{bundle.student.full_name}
			</Link>
		);
	}
	if (bundle.family) {
		return (
			<Link
				to="/people/families/$familyId"
				params={{ familyId: String(bundle.family.id) }}
				className={LINK}
			>
				{bundle.family.name}
			</Link>
		);
	}
	return (
		<Link to="/people/groups" className={LINK}>
			{bundle.study_group?.name}
		</Link>
	);
}

/** Slice B2f §7: one bundle — its owner, totals and notes, its members (the
 * current ones marked) and its roster; Task 18 adds the actions. */
export function BundlePage({ bundleId }: { bundleId: string }) {
	const { t, i18n } = useTranslation();
	const can = useCan();
	const [tab, setTab] = useState<(typeof TABS)[number]>("members");
	const parsed = Number(bundleId);
	const invalid = !Number.isInteger(parsed) || parsed < 1;
	const { data: bundle, isError, error } = useBundle(invalid ? undefined : parsed);
	const missing =
		invalid || (isAxiosError(error) && error.response?.status === 404);
	if (missing || isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{t(missing ? "bundles.page.notFound" : "bundles.page.loadError")}
				</AlertDescription>
			</Alert>
		);
	}
	if (!bundle) return <Spinner />;
	return (
		<div className="flex flex-col gap-6">
			<Card>
				<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
					<CardTitle>{t(`bundles.kind.${bundle.kind}`)}</CardTitle>
					<StatusChip tone={bundle.state === "live" ? "live" : "neutral"}>
						{t(`bundles.page.state.${bundle.state}`)}
					</StatusChip>
				</CardHeader>
				<CardContent className="flex flex-col gap-4">
					<dl className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
						<Fact label={t("bundles.page.owner")}>
							<Owner bundle={bundle} />
						</Fact>
						<Fact label={t("bundles.page.createdBy")}>
							{bundle.created_by?.full_name ?? "—"}
						</Fact>
						<Fact label={t("bundles.totals.sessions")}>
							{bundle.totals.sessions_total}
						</Fact>
						<Fact label={t("bundles.totals.price")}>
							<span className="flex flex-col" dir="ltr">
								{bundle.totals.prices.map((p) => (
									<span key={p.currency}>
										{formatMoney(p.price_minor, p.currency, i18n.language)}
									</span>
								))}
							</span>
						</Fact>
					</dl>
					<div className="flex flex-wrap items-start justify-between gap-2">
						<p className="whitespace-pre-line text-sm">
							{bundle.notes || t("bundles.notes.none")}
						</p>
						{can("subscription.update") ? (
							<BundleNotesDialog bundle={bundle} />
						) : null}
					</div>
				</CardContent>
			</Card>
			<div
				role="tablist"
				aria-label={t("bundles.tabs.label")}
				className="flex flex-wrap gap-2 border-b border-border pb-2"
			>
				{TABS.map((key) => (
					<button
						key={key}
						type="button"
						role="tab"
						aria-selected={tab === key}
						onClick={() => setTab(key)}
						className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
					>
						{t(`bundles.tabs.${key}`)}
					</button>
				))}
			</div>
			{tab === "members" ? (
				<BundleMembers bundle={bundle} />
			) : (
				<BundleRoster bundle={bundle} />
			)}
		</div>
	);
}
```

(The kind shows as the card title — "Group"; the test's `getByText("Group")` finds it.)

`dashboard/src/routes/_authed/scheduling.bundles.$bundleId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { BundlePage } from "@/features/scheduling";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/scheduling/bundles/$bundleId")({
	// Plan D19: the shared bundle routes are ungated, so is their screen.
	staticData: { permission: "subscription.view" },
	component: function BundleRoute() {
		const { t } = useTranslation();
		const { bundleId } = Route.useParams();
		usePageTitle(t("bundles.title"));
		return (
			<>
				<PageHeader title={t("bundles.title")} />
				<BundlePage bundleId={bundleId} />
			</>
		);
	},
});
```

`index.ts`: `export { BundlePage } from "./BundlePage";`. (The route's id is unchanged: no tree regeneration needed.)

- [ ] **Step 5: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/BundlePage.test.tsx src/routes`
Expected: PASS. Then `tsc --noEmit`, `pnpm lint`.

- [ ] **Step 6: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/BundlePage.tsx src/features/scheduling/BundleMembers.tsx src/features/scheduling/BundleRoster.tsx src/features/scheduling/BundleNotesDialog.tsx src/features/scheduling/BundlePage.test.tsx src/features/scheduling/index.ts "src/routes/_authed/scheduling.bundles.\$bundleId.tsx"
git -C $W/dashboard commit -m "feat(scheduling): the bundle page — owner, totals, notes, members, roster (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 18: The bundle's actions, each refusal naming its member

**Files:**
- Create: `dashboard/src/features/scheduling/BundleActions.tsx`
- Modify: `dashboard/src/features/scheduling/BundlePage.tsx` (actions bar; Remove on roster rows)
- Test: `dashboard/src/features/scheduling/BundleActions.test.tsx`

**Interfaces:**
- Consumes: `bundleApi.renew/pause/cancel/archive/restore/addMember/removeMember/dissolve`, `refusalText` (Task 13); `Confirm`; `usePeople` (students, for Add); `useCan`; the bundle's `can_*` flags.
- Produces: `<BundleActions bundle />` — Renew (dialog, optional start), Pause (dialog: from, to, reason), Cancel, Archive, Restore (confirms), Add a student (dialog: find, student, start), Dissolve (confirm, then the subscriptions list); each shown only while its flag says so and the viewer holds its code (renew / pause / cancel / add / dissolve `subscription.update`, archive `subscription.delete`, restore `subscription.restore`). `<RemoveStudentButton bundle row />` for roster rows with `can_remove`. A refusal shows as one alert (`role="alert"`) naming the member (plan D16).

- [ ] **Step 1: Write the failing test** (`dashboard/src/features/scheduling/BundleActions.test.tsx`)

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
import {
	bundleDetail,
	bundleMember,
	page,
	rosterRow,
} from "@/test/scheduling-fixtures";
import { BundleActions, RemoveStudentButton } from "./BundleActions";
import { bundleApi } from "./bundleApi";

vi.mock("./bundleApi", async (orig) => {
	const actual = await orig<typeof import("./bundleApi")>();
	return {
		...actual,
		bundleApi: {
			...actual.bundleApi,
			renew: vi.fn(),
			pause: vi.fn(),
			cancel: vi.fn(),
			archive: vi.fn(),
			restore: vi.fn(),
			addMember: vi.fn(),
			removeMember: vi.fn(),
			dissolve: vi.fn(),
		},
	};
});
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return { ...actual, peopleApi: { ...actual.peopleApi, list: vi.fn() } };
});

function refusal(status: number, data: unknown): AxiosError {
	const error = new AxiosError("refused");
	error.response = { status, data } as AxiosResponse;
	return error;
}

const BUNDLE = bundleDetail({
	members: [
		bundleMember({ id: 7 }),
		bundleMember({
			id: 8,
			student: { id: 12, full_name: "Aisha", timezone: "UTC" },
			freeze_days_left: 2,
		}),
	],
});

describe("BundleActions", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		for (const write of [
			bundleApi.renew,
			bundleApi.pause,
			bundleApi.cancel,
			bundleApi.archive,
			bundleApi.restore,
			bundleApi.addMember,
			bundleApi.removeMember,
		]) {
			vi.mocked(write).mockResolvedValue(BUNDLE);
		}
		vi.mocked(bundleApi.dissolve).mockResolvedValue();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 13, user: { full_name: "Zaid", timezone: "UTC" } }]) as never,
		);
	});

	it("renews from a chosen day, or each member's own", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BundleActions bundle={BUNDLE} />);
		await user.click(await screen.findByRole("button", { name: "Renew bundle" }));
		const dialog = screen.getByRole("dialog");
		await user.click(within(dialog).getByRole("button", { name: "Renew bundle" }));
		await waitFor(() =>
			expect(bundleApi.renew).toHaveBeenCalledWith({ id: 9, starts_on: undefined }),
		);
	});

	it("names the member that refused a renewal", async () => {
		const user = userEvent.setup();
		vi.mocked(bundleApi.renew).mockRejectedValueOnce(
			refusal(400, { student: ["Choose an active student."], member_id: 8 }),
		);
		renderWithRouter(<BundleActions bundle={BUNDLE} />);
		await user.click(await screen.findByRole("button", { name: "Renew bundle" }));
		const dialog = screen.getByRole("dialog");
		await user.click(within(dialog).getByRole("button", { name: "Renew bundle" }));
		expect(await within(dialog).findByRole("alert")).toHaveTextContent(
			"Aisha (Tajweed): Choose an active student.",
		);
	});

	it("pauses and names a freeze cap with the days left", async () => {
		const user = userEvent.setup();
		vi.mocked(bundleApi.pause).mockRejectedValueOnce(
			refusal(409, {
				detail: "That is more than the freeze days allowed.",
				code: "scheduling.freeze_days_exceeded",
				member_id: 8,
			}),
		);
		renderWithRouter(<BundleActions bundle={BUNDLE} />);
		await user.click(await screen.findByRole("button", { name: "Pause bundle" }));
		const dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^From/), "2026-06-03");
		await user.type(within(dialog).getByLabelText(/^To/), "2026-06-05");
		await user.type(within(dialog).getByLabelText(/^Reason/), "Travel");
		await user.click(within(dialog).getByRole("button", { name: "Pause bundle" }));
		await waitFor(() =>
			expect(bundleApi.pause).toHaveBeenCalledWith({
				id: 9,
				from_date: "2026-06-03",
				to_date: "2026-06-05",
				reason: "Travel",
			}),
		);
		expect(await within(dialog).findByRole("alert")).toHaveTextContent(
			"Freeze days left for Aisha: 2.",
		);
	});

	it("cancels after a confirm and shows a refusal on the page", async () => {
		const user = userEvent.setup();
		vi.mocked(bundleApi.cancel).mockRejectedValueOnce(
			refusal(409, {
				detail: "Nothing in this bundle is live.",
				code: "scheduling.not_allowed_in_status",
			}),
		);
		renderWithRouter(<BundleActions bundle={BUNDLE} />);
		await user.click(await screen.findByRole("button", { name: "Cancel bundle" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Cancel bundle",
			}),
		);
		await waitFor(() => expect(bundleApi.cancel).toHaveBeenCalledWith(9));
		expect(await screen.findByRole("alert")).toHaveTextContent(
			"That isn't possible in the current status.",
		);
	});

	it("adds a student to a group from the day chosen", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BundleActions bundle={BUNDLE} />);
		await user.click(await screen.findByRole("button", { name: "Add a student" }));
		const dialog = screen.getByRole("dialog");
		await user.selectOptions(
			await within(dialog).findByLabelText(/^Student/),
			"13",
		);
		await user.type(within(dialog).getByLabelText(/^Starts/), "2026-06-08");
		await user.click(within(dialog).getByRole("button", { name: "Add a student" }));
		await waitFor(() =>
			expect(bundleApi.addMember).toHaveBeenCalledWith({
				id: 9,
				student_id: 13,
				starts_on: "2026-06-08",
			}),
		);
	});

	it("offers only what the server's flags allow", async () => {
		renderWithRouter(
			<BundleActions
				bundle={bundleDetail({
					kind: "multi_course",
					can_renew: false,
					can_pause: false,
					can_cancel: false,
					can_add_member: false,
					can_archive: true,
					can_restore: false,
				})}
			/>,
		);
		expect(
			await screen.findByRole("button", { name: "Archive bundle" }),
		).toBeVisible();
		for (const name of [
			"Renew bundle",
			"Pause bundle",
			"Cancel bundle",
			"Add a student",
			"Restore bundle",
		]) {
			expect(screen.queryByRole("button", { name })).toBeNull();
		}
	});

	it("archives, restores and dissolves", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<BundleActions
				bundle={bundleDetail({ can_archive: true, can_restore: true })}
			/>,
			{ extraPaths: ["/scheduling/subscriptions"] },
		);
		await user.click(await screen.findByRole("button", { name: "Archive bundle" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Archive bundle",
			}),
		);
		await waitFor(() => expect(bundleApi.archive).toHaveBeenCalledWith(9));
		await user.click(screen.getByRole("button", { name: "Restore bundle" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Restore bundle",
			}),
		);
		await waitFor(() => expect(bundleApi.restore).toHaveBeenCalledWith(9));
		await user.click(screen.getByRole("button", { name: "Dissolve bundle" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Dissolve bundle",
			}),
		);
		expect(await screen.findByText("at /scheduling/subscriptions")).toBeVisible();
	});

	it("removes a roster student after a confirm", async () => {
		const user = userEvent.setup();
		renderWithRouter(
			<RemoveStudentButton
				bundle={BUNDLE}
				row={rosterRow({ student: { id: 12, full_name: "Aisha" } })}
			/>,
		);
		await user.click(await screen.findByRole("button", { name: "Remove Aisha" }));
		await user.click(
			within(screen.getByRole("alertdialog")).getByRole("button", {
				name: "Remove from the group",
			}),
		);
		await waitFor(() =>
			expect(bundleApi.removeMember).toHaveBeenCalledWith({ id: 9, studentId: 12 }),
		);
	});

	it("hides every action without its code", async () => {
		renderWithRouter(
			<CanProvider me={staffMe("subscription.view")}>
				<BundleActions bundle={bundleDetail({ can_archive: true, can_restore: true })} />
			</CanProvider>,
		);
		await screen.findByRole("group", { name: "Bundle actions" });
		expect(screen.queryAllByRole("button")).toHaveLength(0);
	});
});
```


- [ ] **Step 2: Run it to see it fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/BundleActions.test.tsx`
Expected: FAIL — `Cannot find module './BundleActions'`.

- [ ] **Step 3: Implement** (`dashboard/src/features/scheduling/BundleActions.tsx`)

```tsx
import { useNavigate } from "@tanstack/react-router";
import { type ReactNode, useState } from "react";
import { useTranslation } from "react-i18next";
import { Confirm } from "@/components/Confirm";
import { useCan } from "@/features/identity/permissions";
import { usePeople } from "@/features/people";
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
	Textarea,
} from "@/ui";
import { useLocalName } from "./bits";
import { bundleApi } from "./bundleApi";
import type { BundleDetail, RosterRow } from "./bundleSchemas";
import { useSchedulingMutation } from "./queries";
import { refusalText } from "./refusal";

/** The refusal of one bundle action, naming its member (§4.6). */
function useRefusal(bundle: BundleDetail) {
	const { t } = useTranslation();
	const localName = useLocalName();
	const [text, setText] = useState<string | null>(null);
	return {
		text,
		clear: () => setText(null),
		show: (error: unknown) => setText(refusalText(error, bundle, t, localName)),
	};
}

function Refusal({ text }: { text: string | null }) {
	if (!text) return null;
	return (
		<Alert variant="destructive" role="alert">
			<AlertDescription>{text}</AlertDescription>
		</Alert>
	);
}

/** A dialog action: its trigger and its confirm share `label`; `fields` is
 * the form's body; the refusal stays in the dialog. */
function ActionDialog({
	label,
	body,
	children,
	onSubmit,
	refusal,
	pending,
}: {
	label: string;
	body: string;
	children?: ReactNode;
	onSubmit: () => Promise<boolean>;
	refusal: ReturnType<typeof useRefusal>;
	pending: boolean;
}) {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	return (
		<Dialog
			open={open}
			onOpenChange={(next) => {
				refusal.clear();
				setOpen(next);
			}}
		>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{label}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{label}</DialogTitle>
				<DialogDescription>{body}</DialogDescription>
				<div className="mt-4 flex flex-col gap-4">{children}</div>
				<Refusal text={refusal.text} />
				<DialogFooter>
					<DialogClose asChild>
						<Button type="button" variant="outline">
							{t("people.cancel")}
						</Button>
					</DialogClose>
					<Button
						type="button"
						disabled={pending}
						onClick={async () => {
							if (await onSubmit()) setOpen(false);
						}}
					>
						{label}
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}

function RenewAction({ bundle }: { bundle: BundleDetail }) {
	const { t } = useTranslation();
	const refusal = useRefusal(bundle);
	const [startsOn, setStartsOn] = useState("");
	const renew = useSchedulingMutation(bundleApi.renew);
	return (
		<ActionDialog
			label={t("bundles.actions.renew")}
			body={t("bundles.actions.renewBody")}
			refusal={refusal}
			pending={renew.isPending}
			onSubmit={async () => {
				try {
					await renew.mutateAsync({ id: bundle.id, starts_on: startsOn || undefined });
					return true;
				} catch (error) {
					refusal.show(error);
					return false;
				}
			}}
		>
			<Field id="bundle-renew-starts" label={t("bundles.actions.startsOn")}>
				<Input
					type="date"
					dir="ltr"
					value={startsOn}
					onChange={(e) => setStartsOn(e.target.value)}
				/>
			</Field>
		</ActionDialog>
	);
}

function PauseAction({ bundle }: { bundle: BundleDetail }) {
	const { t } = useTranslation();
	const refusal = useRefusal(bundle);
	const [values, setValues] = useState({ from_date: "", to_date: "", reason: "" });
	const pause = useSchedulingMutation(bundleApi.pause);
	const set = (key: keyof typeof values) => (value: string) =>
		setValues({ ...values, [key]: value });
	return (
		<ActionDialog
			label={t("bundles.actions.pause")}
			body={t("bundles.actions.pauseBody")}
			refusal={refusal}
			pending={pause.isPending}
			onSubmit={async () => {
				try {
					await pause.mutateAsync({ id: bundle.id, ...values });
					return true;
				} catch (error) {
					refusal.show(error);
					return false;
				}
			}}
		>
			<Field id="bundle-pause-from" label={t("bundles.actions.from")} required>
				<Input
					type="date"
					dir="ltr"
					value={values.from_date}
					onChange={(e) => set("from_date")(e.target.value)}
				/>
			</Field>
			<Field id="bundle-pause-to" label={t("bundles.actions.to")} required>
				<Input
					type="date"
					dir="ltr"
					value={values.to_date}
					onChange={(e) => set("to_date")(e.target.value)}
				/>
			</Field>
			<Field id="bundle-pause-reason" label={t("bundles.actions.reason")}>
				<Textarea
					rows={2}
					value={values.reason}
					onChange={(e) => set("reason")(e.target.value)}
				/>
			</Field>
		</ActionDialog>
	);
}

function AddStudentAction({ bundle }: { bundle: BundleDetail }) {
	const { t } = useTranslation();
	const refusal = useRefusal(bundle);
	const [query, setQuery] = useState("");
	const [student, setStudent] = useState("");
	const [startsOn, setStartsOn] = useState("");
	const add = useSchedulingMutation(bundleApi.addMember);
	const { data: students } = usePeople("students", {
		is_active: "true",
		page_size: 50,
		q: query.trim(),
	});
	return (
		<ActionDialog
			label={t("bundles.actions.add")}
			body={t("bundles.actions.addBody")}
			refusal={refusal}
			pending={add.isPending}
			onSubmit={async () => {
				try {
					await add.mutateAsync({
						id: bundle.id,
						student_id: Number(student),
						starts_on: startsOn,
					});
					return true;
				} catch (error) {
					refusal.show(error);
					return false;
				}
			}}
		>
			<Field id="bundle-add-find" label={t("bundles.form.findStudent")}>
				<Input
					type="search"
					value={query}
					onChange={(e) => setQuery(e.target.value)}
				/>
			</Field>
			<Field id="bundle-add-student" label={t("bundles.actions.addStudent")} required>
				<Select value={student} onChange={(e) => setStudent(e.target.value)}>
					<option value="">—</option>
					{students?.results.map((p) => (
						<option key={p.id} value={p.id}>
							{p.user.full_name}
						</option>
					))}
				</Select>
			</Field>
			<Field id="bundle-add-starts" label={t("bundles.form.startsOn")} required>
				<Input
					type="date"
					dir="ltr"
					value={startsOn}
					onChange={(e) => setStartsOn(e.target.value)}
				/>
			</Field>
		</ActionDialog>
	);
}

/** Slice B2f §7: the bundle's actions, each behind its code and the
 * server's flag (plan D11); a refused one names the member (§4.6). */
export function BundleActions({ bundle }: { bundle: BundleDetail }) {
	const { t } = useTranslation();
	const can = useCan();
	const navigate = useNavigate();
	const refusal = useRefusal(bundle);
	const cancel = useSchedulingMutation(bundleApi.cancel);
	const archive = useSchedulingMutation(bundleApi.archive);
	const restore = useSchedulingMutation(bundleApi.restore);
	const dissolve = useSchedulingMutation(bundleApi.dissolve);
	const update = can("subscription.update");

	const confirmed = (write: (id: number) => Promise<unknown>) => async () => {
		refusal.clear();
		try {
			await write(bundle.id);
		} catch (error) {
			refusal.show(error);
		}
	};

	return (
		<div className="flex flex-col gap-3">
			<fieldset className="flex flex-wrap gap-2">
				<legend className="sr-only">{t("bundles.actions.label")}</legend>
				{update && bundle.can_renew ? <RenewAction bundle={bundle} /> : null}
				{update && bundle.can_pause ? <PauseAction bundle={bundle} /> : null}
				{update && bundle.can_add_member ? (
					<AddStudentAction bundle={bundle} />
				) : null}
				{update && bundle.can_cancel ? (
					<Confirm
						action={t("bundles.actions.cancel")}
						title={t("bundles.actions.cancel")}
						body={t("bundles.actions.cancelBody")}
						onConfirm={confirmed(cancel.mutateAsync)}
					/>
				) : null}
				{can("subscription.delete") && bundle.can_archive ? (
					<Confirm
						action={t("bundles.actions.archive")}
						title={t("bundles.actions.archive")}
						body={t("bundles.actions.archiveBody")}
						onConfirm={confirmed(archive.mutateAsync)}
					/>
				) : null}
				{can("subscription.restore") && bundle.can_restore ? (
					<Confirm
						action={t("bundles.actions.restore")}
						title={t("bundles.actions.restore")}
						body={t("bundles.actions.restoreBody")}
						onConfirm={confirmed(restore.mutateAsync)}
					/>
				) : null}
				{update ? (
					<Confirm
						action={t("bundles.actions.dissolve")}
						title={t("bundles.actions.dissolve")}
						body={t("bundles.actions.dissolveBody")}
						onConfirm={confirmed(async (id) => {
							await dissolve.mutateAsync(id);
							navigate({ to: "/scheduling/subscriptions" });
						})}
					/>
				) : null}
			</fieldset>
			<Refusal text={refusal.text} />
		</div>
	);
}

/** F-7: a roster row's Remove (the server's `can_remove`). */
export function RemoveStudentButton({
	bundle,
	row,
}: {
	bundle: BundleDetail;
	row: RosterRow;
}) {
	const { t } = useTranslation();
	const refusal = useRefusal(bundle);
	const remove = useSchedulingMutation(bundleApi.removeMember);
	return (
		<div className="flex flex-col gap-2">
			<Confirm
				action={t("bundles.roster.removeName", { name: row.student.full_name })}
				title={t("bundles.roster.removeTitle")}
				body={t("bundles.roster.removeBody")}
				onConfirm={async () => {
					refusal.clear();
					try {
						await remove.mutateAsync({ id: bundle.id, studentId: row.student.id });
					} catch (error) {
						refusal.show(error);
					}
				}}
			/>
			<Refusal text={refusal.text} />
		</div>
	);
}
```

(The actions sit in a `<fieldset>` + `<legend>` — Biome rejects `role="group"` on a div — so the "hides every action" test finds the group by its legend "Bundle actions".)

`BundlePage.tsx` — render `<BundleActions bundle={bundle} />` above the header card, and give the roster its Remove:

```tsx
				<BundleRoster
					bundle={bundle}
					actions={(row) =>
						can("subscription.update") && row.can_remove ? (
							<RemoveStudentButton bundle={bundle} row={row} />
						) : null
					}
				/>
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/BundleActions.test.tsx src/features/scheduling/BundlePage.test.tsx`
Expected: PASS. Then `tsc --noEmit`, `pnpm lint`.

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/BundleActions.tsx src/features/scheduling/BundleActions.test.tsx src/features/scheduling/BundlePage.tsx
git -C $W/dashboard commit -m "feat(scheduling): bundle actions with the refusing member named (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 19: "Part of a bundle" on the subscription page, the list's badge and filter, "Group: {name}" on sessions

**Files:**
- Create: `dashboard/src/features/scheduling/GroupChip.tsx`, `BundleLink.tsx`
- Modify: `dashboard/src/features/scheduling/SubscriptionDetail.tsx` (`BundleLink` above the summary)
- Modify: `dashboard/src/features/scheduling/SubscriptionsList.tsx` (badge beside the student; "Bundle type" filter)
- Modify: `dashboard/src/features/scheduling/SessionsList.tsx`, `SessionsPanel.tsx`, `TeacherSessionTable.tsx`, `FamilySessions.tsx`, `SessionPage.tsx` (`<GroupChip>` beside each `<SessionKindChip>`)
- Test: `dashboard/src/features/scheduling/GroupChip.test.tsx`, `BundleLink.test.tsx`; one case each added to `SubscriptionsList.test.tsx`, `SessionsList.test.tsx`, `TeacherSessions.test.tsx`

**Interfaces:**
- Consumes: `Subscription.bundle`, `Session.group` (Task 13); `useHasFeature`.
- Produces: `<GroupChip group? />` ("Group: {name}", nothing without a group); `<BundleLink bundle? />` ("Part of a {kind} bundle." with "Open the bundle"; nothing for a plain subscription); `<BundleChip bundle? />` (exported from `BundleLink.tsx`: the list badge, a link). The subscriptions list sends `bundle_kind` while one of the three bundle switches is on. No new API call on any touched page: the existing tests' mocks suffice.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/scheduling/GroupChip.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { GroupChip } from "./GroupChip";

describe("GroupChip", () => {
	it("names a group class's group, and nothing else", () => {
		const { container, rerender } = render(
			<GroupChip group={{ bundle_id: 9, name: "Evening circle" }} />,
		);
		expect(screen.getByText("Group: Evening circle")).toBeVisible();
		rerender(<GroupChip group={undefined} />);
		expect(container).toBeEmptyDOMElement();
	});
});
```

`dashboard/src/features/scheduling/BundleLink.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import "@/lib/i18n";
import { renderWithRouter } from "@/test/render";
import { BundleChip, BundleLink } from "./BundleLink";

const PAGE = "/scheduling/bundles/$bundleId";

describe("BundleLink", () => {
	it("says which bundle a member is part of and links it", async () => {
		renderWithRouter(<BundleLink bundle={{ id: 9, kind: "family" }} />, {
			extraPaths: [PAGE],
		});
		expect(await screen.findByText("Part of a Family bundle.")).toBeVisible();
		expect(screen.getByRole("link", { name: "Open the bundle" })).toHaveAttribute(
			"href",
			"/scheduling/bundles/9",
		);
	});

	it("badges a member's row", async () => {
		renderWithRouter(<BundleChip bundle={{ id: 9, kind: "group" }} />, {
			extraPaths: [PAGE],
		});
		expect(
			await screen.findByRole("link", { name: "Group bundle" }),
		).toHaveAttribute("href", "/scheduling/bundles/9");
	});

	it("shows nothing for a plain subscription", async () => {
		renderWithRouter(
			<>
				<p>marker</p>
				<BundleLink bundle={undefined} />
				<BundleChip bundle={undefined} />
			</>,
		);
		await screen.findByText("marker");
		expect(screen.queryByRole("link")).toBeNull();
	});
});
```

`SubscriptionsList.test.tsx` — add (the file's existing mocks stay; `subscriptionRow` from the fixtures):

```tsx
	it("badges a bundle's member and filters by bundle type", async () => {
		const user = userEvent.setup();
		vi.mocked(schedulingApi.list).mockResolvedValue(
			page([subscriptionRow({ bundle: { id: 9, kind: "group" } })]) as never,
		);
		renderWithRouter(<SubscriptionsList />, {
			extraPaths: ["/scheduling/bundles/$bundleId"],
		});
		expect(
			await screen.findByRole("link", { name: "Group bundle" }),
		).toHaveAttribute("href", "/scheduling/bundles/9");
		await user.selectOptions(screen.getByLabelText("Bundle type"), "group");
		await waitFor(() =>
			expect(schedulingApi.list).toHaveBeenLastCalledWith(
				expect.objectContaining({ bundle_kind: "group", page: 1 }),
			),
		);
	});
```

`SessionsList.test.tsx` — add (its `beforeEach` mocks stay):

```tsx
	it("labels a group class's session with its group", async () => {
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([sessionRow({ group: { bundle_id: 9, name: "Evening circle" } }), AISHA]),
		);
		renderWithRouter(<SessionsList />);
		const table = await screen.findByRole("table");
		const [, yusuf, aisha] = within(table).getAllByRole("row");
		expect(within(yusuf).getByText("Group: Evening circle")).toBeVisible();
		expect(within(aisha).queryByText(/^Group:/)).toBeNull();
	});
```

`TeacherSessions.test.tsx` — add:

```tsx
	it("shows the teacher which group a session belongs to", async () => {
		vi.mocked(schedulingApi.sessionList).mockResolvedValue(
			page([sessionRow({ group: { bundle_id: 9, name: "Evening circle" } })]),
		);
		renderWithRouter(<TeacherSessions />);
		expect(await screen.findByText("Group: Evening circle")).toBeVisible();
	});
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/GroupChip.test.tsx src/features/scheduling/BundleLink.test.tsx src/features/scheduling/SubscriptionsList.test.tsx src/features/scheduling/SessionsList.test.tsx src/features/scheduling/TeacherSessions.test.tsx`
Expected: FAIL — missing modules, then missing labels.

- [ ] **Step 3: Implement**

`dashboard/src/features/scheduling/GroupChip.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { StatusChip } from "@/ui";
import type { GroupLabel } from "./schemas";

/** Slice B2f §7: a group class's session says which group, to everyone in
 * scope; any other session shows nothing. */
export function GroupChip({ group }: { group?: GroupLabel | null }) {
	const { t } = useTranslation();
	if (!group) return null;
	return (
		<StatusChip tone="neutral">
			{t("bundles.group", { name: group.name })}
		</StatusChip>
	);
}
```

`dashboard/src/features/scheduling/BundleLink.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription } from "@/ui";
import type { BundleRef } from "./schemas";

const LINK =
	"font-medium text-primary-text underline-offset-4 hover:underline";

/** Slice B2f §7: the subscription page says which bundle it is part of. */
export function BundleLink({ bundle }: { bundle?: BundleRef }) {
	const { t } = useTranslation();
	if (!bundle) return null;
	return (
		<Alert>
			<AlertDescription className="flex flex-wrap items-center gap-2">
				<span>
					{t("bundles.partOf", { kind: t(`bundles.kind.${bundle.kind}`) })}
				</span>
				<Link
					to="/scheduling/bundles/$bundleId"
					params={{ bundleId: String(bundle.id) }}
					className={LINK}
				>
					{t("bundles.openBundle")}
				</Link>
			</AlertDescription>
		</Alert>
	);
}

/** The subscriptions list's badge on a bundle's member. */
export function BundleChip({ bundle }: { bundle?: BundleRef }) {
	const { t } = useTranslation();
	if (!bundle) return null;
	return (
		<Link
			to="/scheduling/bundles/$bundleId"
			params={{ bundleId: String(bundle.id) }}
			className="rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground hover:underline"
		>
			{t("bundles.badge", { kind: t(`bundles.kind.${bundle.kind}`) })}
		</Link>
	);
}
```

`SubscriptionDetail.tsx` — import `BundleLink` and render `<BundleLink bundle={sub.bundle} />` right after `<ArchivedSubscriptionBanner … />`.

`SubscriptionsList.tsx`:
- import `BundleChip` from `./BundleLink` and `BUNDLE_KINDS` from `./bundleSchemas`;
- `const bundles = ["multi_course_subscriptions", "family_subscriptions", "group_subscriptions"].some((code) => hasFeature(code as FeatureCode));` (import `FeatureCode` type from `@/features/identity/schemas`);
- the student cell becomes:

```tsx
									<td className="p-3">
										<span className="flex flex-wrap items-center gap-2">
											<Link
												to="/scheduling/subscriptions/$subscriptionId"
												params={{ subscriptionId: String(sub.id) }}
												className="font-medium text-primary-text underline-offset-4 hover:underline"
											>
												{sub.student.full_name}
											</Link>
											<BundleChip bundle={sub.bundle} />
										</span>
									</td>
```

- after the course filter, while `bundles`:

```tsx
				{bundles ? (
					<Select
						aria-label={t("bundles.filter.label")}
						className="w-auto"
						value={String(params.bundle_kind ?? "")}
						onChange={(e) => update({ bundle_kind: e.target.value })}
					>
						<option value="">{t("bundles.filter.any")}</option>
						{BUNDLE_KINDS.map((kind) => (
							<option key={kind} value={kind}>
								{t(`bundles.kind.${kind}`)}
							</option>
						))}
					</Select>
				) : null}
```

(`update` is the list's own setter, which resets `page` to 1 as for the other filters.)

The five session views — next to each `<SessionKindChip kind={session.kind} />` add `<GroupChip group={session.group} />` (import from `./GroupChip`); in `SessionPage.tsx` beside its kind chip the same.

- [ ] **Step 4: Run the tests to see them pass**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling`
Expected: PASS (every existing scheduling test unchanged). Then `tsc --noEmit`, `pnpm lint`, and `… exec -T dashboard pnpm test:coverage` (lines/statements ≥ 80, branches/functions ≥ 70).

- [ ] **Step 5: Commit**

```bash
git -C $W/dashboard add src/features/scheduling/GroupChip.tsx src/features/scheduling/BundleLink.tsx src/features/scheduling/GroupChip.test.tsx src/features/scheduling/BundleLink.test.tsx src/features/scheduling/SubscriptionDetail.tsx src/features/scheduling/SubscriptionsList.tsx src/features/scheduling/SubscriptionsList.test.tsx src/features/scheduling/SessionsList.tsx src/features/scheduling/SessionsList.test.tsx src/features/scheduling/SessionsPanel.tsx src/features/scheduling/TeacherSessionTable.tsx src/features/scheduling/TeacherSessions.test.tsx src/features/scheduling/FamilySessions.tsx src/features/scheduling/SessionPage.tsx
git -C $W/dashboard commit -m "feat(scheduling): bundle link, list badge and filter, group label on sessions (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---
### Task 20 (conditional): If B3d has merged before B2f builds — D-5 group currency rules

**Run this task only if, when B2f's build starts, B3d (plan 36) is merged on `main`:** `catalogue.services.package_price` exists, `create_subscription` / `renew_subscription` take `currency`, and the dashboard has `usePackagePrice`. The controller decides at build time; if B3d has not merged, skip this task — B3d's own request R2 (4) then brings these rules (ledger D23; B3d spec D-5: "If B2f is not merged when this lands, (4) becomes part of B2f's own build", and the reverse). Rebase onto `main` first. Whichever side builds D-5 keys the refusal `rows.0.price_minor` (plan D1; B3d's text `rows[0].price_minor` reads as that). This task comes before the e2e and the slice gates (Task 21) so they cover it.

**Files:**
- Modify: `backend/etqan/scheduling/services/bundles.py` (`_plan_group`, `_member`), `bundle_actions.py` (`add_to_group_bundle`)
- Modify: `backend/etqan/scheduling/api/serializers.py` (`BundleRowInput.currency`)
- Test: `backend/etqan/scheduling/tests/test_bundles_country_pricing.py`
- Create: `dashboard/src/features/scheduling/rowPrice.ts` (`useRowPrice`)
- Modify: `dashboard/src/features/scheduling/BundleRowFields.tsx`, `BundleForm.tsx`, `bundleSchemas.ts` (`currency` on rows), `src/locales/{en,ar}/bundles.json` (`form.mixedCurrencies`)
- Modify (mocks only): `BundleRowFields.test.tsx`, `BundleForm.test.tsx`, `NewSubscription.test.tsx` (`catalogueApi.price`)
- Test: `dashboard/src/features/scheduling/BundleForm.currency.test.tsx`

**Interfaces:**
- Consumes (B3d): `catalogue_services.package_price(package, *, country) -> Price(price_minor, currency, country, source)`; `create_subscription(..., currency=None)` refusing a different currency with `ValidationError(field="price_minor", code="catalogue.price_currency_changed")`; dashboard `usePackagePrice(packageId?, studentId?) -> {data?: PackagePrice; isPending; isError}` and `catalogueApi.price(packageId, studentId?)` from `@/features/catalogue`; the student profile's `country`.
- Produces: a group row with an explicit `price_minor` is 400 on `rows.0.price_minor` unless every active member resolves to one currency; without one, each member takes its own resolved default; `add_to_group_bundle` copies the template's price only when the new student's resolved currency equals the template's, else the student's resolved default; rows take an optional `currency` passed to `create_subscription`. Dashboard: multi-course and family rows prefill price and currency from `usePackagePrice(package, student)` and send `currency`; the group form prefills nothing and sends no price while the active members' resolved currencies differ.

- [ ] **Step 1: Write the failing backend tests** (`backend/etqan/scheduling/tests/test_bundles_country_pricing.py`)

```python
"""B3d D-5 (ledger D23) for B2f: a group class across countries — one
explicit price only when every member pays in one currency; otherwise each
member's own default; a new student copies the class's price only in its
currency."""

from datetime import date

import pytest

from etqan.catalogue import services as catalogue_services
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.scheduling import services
from etqan.scheduling.tests.conftest import make_group
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import member_of
from etqan.scheduling.tests.conftest import row

pytestmark = pytest.mark.django_db
JUNE_1 = date(2026, 6, 1)
SAR_ROW = {"country": "SA", "price_minor": 45000, "currency": "SAR"}


@pytest.fixture
def mixed(world, set_features):
    """``world``'s student in Saudi Arabia (450.00 SAR there), a sister
    elsewhere (the package's 1500.00 EGP)."""
    set_features(country_pricing=True)
    catalogue_services.set_country_prices(world.package, [SAR_ROW])
    identity_services.update_person(world.student, profile={"country": "SA"})
    sister = make_student("Aisha")
    return world, sister, make_group(world.student, sister)


def test_an_explicit_price_across_currencies_is_refused(mixed):
    world, _, group = mixed
    with pytest.raises(ValidationError) as exc:
        services.create_bundle(
            "group",
            None,
            starts_on=JUNE_1,
            group_id=group.pk,
            rows=[row(world, price_minor=100000)],
        )
    assert exc.value.field == "rows.0.price_minor"


def test_without_a_price_each_member_takes_their_own(mixed):
    world, sister, group = mixed
    created = services.create_bundle(
        "group", None, starts_on=JUNE_1, group_id=group.pk, rows=[row(world)]
    )
    mine = member_of(created, world.student)
    theirs = member_of(created, sister)
    assert (mine.price_minor, mine.currency) == (45000, "SAR")
    assert (theirs.price_minor, theirs.currency) == (150000, "EGP")


def test_one_currency_takes_one_explicit_price(world, set_features):
    set_features(country_pricing=True)
    group = make_group(world.student, make_student("Aisha"))
    created = services.create_bundle(
        "group",
        None,
        starts_on=JUNE_1,
        group_id=group.pk,
        rows=[row(world, price_minor=120000)],
    )
    assert {m.price_minor for m in created.members} == {120000}


def test_a_new_student_copies_the_price_only_in_its_currency(mixed):
    world, sister, group = mixed
    services.update_group(group, fields={"student_ids": [sister.id]})
    created = services.create_bundle(
        "group",
        None,
        starts_on=JUNE_1,
        group_id=group.pk,
        rows=[row(world, price_minor=120000)],
    )
    egyptian = make_student("Zaid")
    same = services.add_to_group_bundle(
        created.bundle, student_id=egyptian.id, starts_on=date(2026, 6, 8)
    )
    assert (same.price_minor, same.currency) == (120000, "EGP")
    saudi = services.add_to_group_bundle(
        created.bundle, student_id=world.student.id, starts_on=date(2026, 6, 8)
    )
    assert (saudi.price_minor, saudi.currency) == (45000, "SAR")
```

- [ ] **Step 2: Run them to see them fail**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_country_pricing.py`
Expected: FAIL — the explicit price is applied to both members (no refusal); the Saudi newcomer copies 120000.

- [ ] **Step 3: Implement**

`bundles.py` (import `catalogue_services` from `etqan.catalogue`) — a helper, and its call at the end of `_plan_group`, just before its `return`:

```python
def _one_currency(group: StudyGroup, row: dict, students: list[int]) -> None:
    """B3d D-5 (ledger D23): one explicit price only when every active member
    resolves to one currency. An unknown or inactive package is left to
    `create_subscription`'s own 400 on `rows.0.package`."""
    if row.get("price_minor") is None:
        return
    package = catalogue_services.get_package(row["package"])
    if package is None:
        return
    countries = group.members.filter(student__user_id__in=students).values_list(
        "student__country", flat=True
    )
    currencies = {
        catalogue_services.package_price(package, country=country).currency
        for country in countries
    }
    if len(currencies) > 1:
        raise ValidationError(
            "These students pay in different currencies: leave the price empty.",
            field="rows.0.price_minor",
        )
```

```python
    _one_currency(group, rows[0], students)
    return {"study_group": group}, [_Plan(0, student, rows[0]) for student in students]
```

`_member` passes `currency=row.get("currency")` to `create_subscription`.

`bundle_actions.py` — `add_to_group_bundle` resolves the newcomer's price before creating:

```python
    resolved = catalogue_services.package_price(template.package, country=profile.country)
    # B3d D-5: the class's price only in its own currency, else the student's
    # resolved default.
    price_minor = (
        template.price_minor if resolved.currency == template.currency else None
    )
```

and passes `price_minor=price_minor` (not `template.price_minor`) to `create_subscription`.

`serializers.py` — `BundleRowInput` gains `currency = CurrencyField(required=False)` after `price_minor` (B3d's field, already in this file: three letters, upper-cased).

- [ ] **Step 4: Run them to see them pass**

Run: `… exec -T django pytest -q etqan/scheduling/tests/test_bundles_country_pricing.py etqan/scheduling/tests/test_bundles_create.py etqan/scheduling/tests/test_bundles_roster_archive.py`
Expected: PASS (every Task 6 / 8 test unchanged with `country_pricing` off).

- [ ] **Step 5: Write the failing dashboard test** (`dashboard/src/features/scheduling/BundleForm.currency.test.tsx`)

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { academyApi } from "@/features/academy/api";
import { catalogueApi } from "@/features/catalogue/api";
import { peopleApi } from "@/features/people/api";
import { packagePrice } from "@/test/catalogue-fixtures";
import { familyRow } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import {
	academySettings,
	bundleDetail,
	page,
	studyGroupRow,
} from "@/test/scheduling-fixtures";
import { BundleForm } from "./BundleForm";
import { bundleApi } from "./bundleApi";

vi.mock("./bundleApi", async (orig) => {
	const actual = await orig<typeof import("./bundleApi")>();
	return {
		...actual,
		bundleApi: { ...actual.bundleApi, create: vi.fn(), groups: vi.fn() },
	};
});
vi.mock("@/features/academy/api", () => ({ academyApi: { get: vi.fn() } }));
vi.mock("@/features/people/api", async (orig) => {
	const actual = await orig<typeof import("@/features/people/api")>();
	return {
		...actual,
		peopleApi: { ...actual.peopleApi, list: vi.fn(), families: vi.fn() },
	};
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return {
		...actual,
		catalogueApi: { ...actual.catalogueApi, list: vi.fn(), price: vi.fn() },
	};
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
const BUNDLE_PAGE = "/scheduling/bundles/$bundleId";
// Aisha (User 12) lives where the package costs 450.00 SAR; Yusuf (11) pays
// the package's own 1500.00 EGP.
const SAR = packagePrice({ price_minor: 45000, currency: "SAR", source: "country" });

async function fill(
	user: ReturnType<typeof userEvent.setup>,
	row: HTMLElement,
	student?: string,
) {
	if (student) {
		await user.selectOptions(within(row).getByLabelText(/^Student/), student);
	}
	await user.selectOptions(within(row).getByLabelText(/^Course/), "3");
	await user.selectOptions(within(row).getByLabelText(/^Teacher/), "21");
	await user.selectOptions(within(row).getByLabelText(/^Package/), "5");
	await user.click(within(row).getByLabelText("Mon"));
	await user.type(within(row).getByLabelText(/^Start time/), "18:00");
}

describe("BundleForm with country prices (B3d D-5)", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(academyApi.get).mockResolvedValue(academySettings());
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([{ id: 21, user: { full_name: "Bilal", timezone: "UTC" } }]) as never,
		);
		vi.mocked(peopleApi.families).mockResolvedValue(
			page([familyRow({ id: 2, name: "Omar family" })]) as never,
		);
		vi.mocked(bundleApi.groups).mockResolvedValue(
			page([studyGroupRow()]) as never,
		);
		vi.mocked(catalogueApi.list).mockImplementation(
			async (kind) =>
				(kind === "courses"
					? page([
							{ id: 3, name_ar: "تجويد", name_en: "Tajweed", teacher_ids: [] },
						])
					: page([monthly])) as never,
		);
		vi.mocked(catalogueApi.price).mockImplementation(async (_pkg, student) =>
			student === 12 ? SAR : packagePrice(),
		);
		vi.mocked(bundleApi.create).mockResolvedValue(
			bundleDetail({ id: 9, conflicts: [] }),
		);
	});

	it("prices each family row for its student's country and sends the currency", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BundleForm kind="family" />, { extraPaths: [BUNDLE_PAGE] });
		await user.selectOptions(await screen.findByLabelText(/^Family/), "2");
		const first = await screen.findByRole("group", { name: "Course 1" });
		await fill(user, first, "12");
		expect(
			await within(first).findByLabelText(/^Price \(SAR\)/),
		).toHaveValue("450.00");
		const second = screen.getByRole("group", { name: "Course 2" });
		await fill(user, second, "11");
		expect(
			await within(second).findByLabelText(/^Price \(EGP\)/),
		).toHaveValue("1500.00");
		await user.click(screen.getByRole("button", { name: "Create bundle" }));
		await waitFor(() =>
			expect(bundleApi.create).toHaveBeenCalledWith(
				expect.objectContaining({
					rows: [
						expect.objectContaining({
							student: 12,
							price_minor: 45000,
							currency: "SAR",
						}),
						expect.objectContaining({
							student: 11,
							price_minor: 150000,
							currency: "EGP",
						}),
					],
				}),
			),
		);
	});

	it("leaves a group's price to each member while their currencies differ", async () => {
		const user = userEvent.setup();
		renderWithRouter(<BundleForm kind="group" />, { extraPaths: [BUNDLE_PAGE] });
		await user.selectOptions(await screen.findByLabelText(/^Study group/), "4");
		const only = await screen.findByRole("group", { name: "Course 1" });
		await fill(user, only);
		expect(
			await within(only).findByText(
				"These students pay in different currencies: each pays their own price.",
			),
		).toBeVisible();
		expect(within(only).getByLabelText(/^Price/)).toBeDisabled();
		await user.click(screen.getByRole("button", { name: "Create bundle" }));
		await waitFor(() => expect(bundleApi.create).toHaveBeenCalled());
		const [body] = vi.mocked(bundleApi.create).mock.calls[0];
		expect(body.rows[0]).not.toHaveProperty("price_minor");
		expect(body.rows[0]).not.toHaveProperty("currency");
	});

	it("prices a group in one currency like any row", async () => {
		vi.mocked(catalogueApi.price).mockResolvedValue(packagePrice());
		const user = userEvent.setup();
		renderWithRouter(<BundleForm kind="group" />, { extraPaths: [BUNDLE_PAGE] });
		await user.selectOptions(await screen.findByLabelText(/^Study group/), "4");
		const only = await screen.findByRole("group", { name: "Course 1" });
		await fill(user, only);
		expect(
			await within(only).findByLabelText(/^Price \(EGP\)/),
		).toHaveValue("1500.00");
		await user.click(screen.getByRole("button", { name: "Create bundle" }));
		await waitFor(() =>
			expect(bundleApi.create).toHaveBeenCalledWith(
				expect.objectContaining({
					rows: [
						expect.objectContaining({ price_minor: 150000, currency: "EGP" }),
					],
				}),
			),
		);
	});
});
```

The existing dashboard tests that render a bundle row now call `catalogueApi.price`: in `BundleRowFields.test.tsx`, `BundleForm.test.tsx` and `NewSubscription.test.tsx`, add `price: vi.fn()` to the `catalogueApi` mock and, in each `beforeEach`, `vi.mocked(catalogueApi.price).mockResolvedValue(packagePrice());` (import `packagePrice` from `@/test/catalogue-fixtures`). `packagePrice()` is the same 1500.00 EGP the `monthly` package has, so every assertion in those files stays as written.

- [ ] **Step 6: Run it to see it fail**

Run: `… exec -T dashboard pnpm exec vitest run src/features/scheduling/BundleForm.currency.test.tsx`
Expected: FAIL — the first row shows `Price (EGP)` and "1500.00"; no mixed-currency note.

- [ ] **Step 7: Implement the dashboard half**

`dashboard/src/features/scheduling/bundleSchemas.ts` — `BundleRowBody` gains `currency?: string;` after `price_minor`, and the row schema becomes:

```ts
export const bundleRowSchema = z.object({
	/** Family rows only; "" elsewhere. */
	student: z.string(),
	course: pick,
	teacher: pick,
	package: pick,
	/** B3d D-5: "" leaves each member their own resolved price. */
	price: z.union([price, z.literal("")]),
	/** The currency the price was converted in (B3d D-4); "" for none. */
	currency: z.string(),
	slots: z.array(slotGroupSchema),
});
```

Create `dashboard/src/features/scheduling/rowPrice.ts`:

```ts
import { useQueries } from "@tanstack/react-query";
import { catalogueApi, packagePriceKey } from "@/features/catalogue";

/** B3d D-5 for one bundle row: `packageId`'s resolved price for each of
 * `studentIds` (the package's own while none is chosen). `price` when they
 * all resolve to one currency, `mixed` when they do not, `pending` while one
 * is on its way. The keys are `usePackagePrice`'s, so the two share a cache. */
export function useRowPrice(packageId: string, studentIds: number[]) {
	const pkg = /^\d+$/.test(packageId) ? Number(packageId) : undefined;
	const students: (number | undefined)[] = studentIds.length
		? studentIds
		: [undefined];
	const results = useQueries({
		queries: students.map((student) => ({
			queryKey: [...packagePriceKey, pkg, student ?? null],
			queryFn: () => catalogueApi.price(pkg as number, student),
			enabled: pkg !== undefined,
		})),
	});
	const prices = results.flatMap((r) => (r.data ? [r.data] : []));
	const currencies = new Set(prices.map((p) => p.currency));
	return {
		price:
			prices.length === students.length && currencies.size === 1
				? prices[0]
				: undefined,
		mixed: currencies.size > 1,
		pending: pkg !== undefined && results.some((r) => r.isPending),
	};
}
```

`dashboard/src/features/scheduling/BundleRowFields.tsx`:
- props gain `studentIds = []` (`studentIds?: number[]` — whose prices the row resolves) and `onPending?: (index: number, pending: boolean) => void`; import `useEffect` from `react` and `useRowPrice` from `./rowPrice`;
- after `const pkg = …`:

```tsx
	const resolved = useRowPrice(watch(`${path}.package`), studentIds);
	useEffect(() => {
		onPending?.(index, resolved.pending);
	}, [index, onPending, resolved.pending]);
	// B3d D-5 (as B3d's TermFields, plan 36 P8): the price follows the resolved
	// one whenever it changes; a group whose members pay in different
	// currencies sends none.
	useEffect(() => {
		if (resolved.mixed) {
			setValue(`${path}.price`, "");
			setValue(`${path}.currency`, "");
			return;
		}
		if (!resolved.price) return;
		setValue(
			`${path}.price`,
			toMajor(resolved.price.price_minor, resolved.price.currency),
		);
		setValue(`${path}.currency`, resolved.price.currency);
	}, [path, resolved.mixed, resolved.price, setValue]);
	const currency = resolved.price?.currency ?? pkg?.currency ?? "";
```

- the Package select's `onChange` keeps only the slot-minutes loop (the price now comes from the effect):

```tsx
							onChange: (e) => {
								const chosen = packageById(e.target.value);
								if (!chosen) return;
								slots.fields.forEach((_, j) => {
									setValue(
										`${path}.slots.${j}.minutes`,
										chosen.session_minutes,
									);
								});
							},
```

- the Price field:

```tsx
				<Field
					id={id("price")}
					label={t("scheduling.form.price", { currency })}
					error={error("price")}
				>
					<Input
						inputMode="decimal"
						dir="ltr"
						disabled={resolved.mixed}
						{...register(`${path}.price`)}
					/>
				</Field>
				{resolved.mixed ? (
					<p className="text-sm text-muted-foreground sm:col-span-2">
						{t("bundles.form.mixedCurrencies")}
					</p>
				) : null}
```

`dashboard/src/features/scheduling/BundleForm.tsx`:
- import `useCallback` from `react`; `blankRow()` gains `currency: ""`;
- after `const group = …`:

```tsx
	const [pending, setPending] = useState<Record<number, boolean>>({});
	const onPending = useCallback(
		(index: number, value: boolean) =>
			setPending((now) => (now[index] === value ? now : { ...now, [index]: value })),
		[],
	);
	const waiting = Object.values(pending).some(Boolean);
	/** Whose resolved prices a row follows (B3d D-5). */
	const studentIdsFor = (index: number): number[] => {
		if (kind === "multi_course") return owner ? [Number(owner)] : [];
		if (kind === "family") {
			const student = watch(`rows.${index}.student`);
			return student ? [Number(student)] : [];
		}
		return group?.members.filter((m) => m.is_active).map((m) => m.id) ?? [];
	};
```

- the totals loop reads the row's currency first: `const currency = row.currency || pkg.currency;` and skips a row with an empty price (`if (!pkg || !row.price || …) continue;`), adding into `prices` under `currency`;
- each `BundleRowFields` gets `studentIds={studentIdsFor(index)}` and `onPending={onPending}`;
- each submitted row becomes:

```tsx
				rows: values.rows.map((row) => ({
					...(kind === "family" ? { student: Number(row.student) } : {}),
					course: Number(row.course),
					teacher: Number(row.teacher),
					package: Number(row.package),
					// B3d D-5: no price leaves each member their own.
					...(row.price
						? {
								price_minor: toMinor(
									row.price,
									row.currency ||
										(packageById(row.package)?.currency ?? "USD"),
								),
								...(row.currency ? { currency: row.currency } : {}),
							}
						: {}),
					slots: row.slots,
				})),
```

- the submit button waits for the prices: `<SubmitButton pending={isSubmitting} disabled={waiting} className="self-start">`.

`dashboard/src/locales/en/bundles.json` and `ar/bundles.json` — under `form`: en `"mixedCurrencies": "These students pay in different currencies: each pays their own price."`, ar `"mixedCurrencies": "يدفع هؤلاء الطلاب بعملات مختلفة: يدفع كلٌّ سعره الخاص."`.

**B3d names this task assumes**, checked against `docs/superpowers/plans/2026-10-05-plan-36-country-prices.md` (B3d's plan, in the b3 worktree):
- backend `catalogue_services.package_price(package, *, country) -> Price(price_minor, currency, country, source)` (plan 36 Task 1), `set_country_prices(package, rows)` (Task 1), `create_subscription(..., currency=None)` and `CurrencyField` in `scheduling/api/serializers.py` (Task 9), `StudentProfile.country` (plan 36 reads `old.student.country`), `identity_services.update_person(user, profile={"country": …})` (Task 9's tests) — verified;
- dashboard `catalogueApi.price(packageId: number, studentId?: number)`, `packagePriceKey = ["catalogue", "price"]` with keys `[...packagePriceKey, pkg, student ?? null]`, `PackagePrice {price_minor, currency, source}`, all exported from `@/features/catalogue`, and the `packagePrice(overrides)` fixture in `@/test/catalogue-fixtures` (Task 6) — verified against the plan text;
- **confirm at build** (plan text only, not merged code): the exact export lines of `@/features/catalogue/index.ts` and the fixture file's path — read them on `main` before Step 5 and adjust the two import lines if they differ.

- [ ] **Step 8: Run everything and commit**

Run: `… exec -T django pytest -q etqan/scheduling`, `… exec -T dashboard pnpm exec vitest run src/features/scheduling`, then `ruff check .`, `ruff format --check .`, `lint-imports`, `tsc --noEmit`, `pnpm lint`. Task 21's gates and e2e then run over this task's changes too.

```bash
git -C $W/backend add etqan/scheduling/services/bundles.py etqan/scheduling/services/bundle_actions.py etqan/scheduling/api/serializers.py etqan/scheduling/tests/test_bundles_country_pricing.py
git -C $W/backend commit -m "feat(scheduling): group bundles across currencies (B3d D-5, ledger D23)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C $W/dashboard add src/features/scheduling/rowPrice.ts src/features/scheduling/BundleRowFields.tsx src/features/scheduling/BundleForm.tsx src/features/scheduling/bundleSchemas.ts src/features/scheduling/BundleForm.currency.test.tsx src/features/scheduling/BundleRowFields.test.tsx src/features/scheduling/BundleForm.test.tsx src/features/scheduling/NewSubscription.test.tsx src/locales/en/bundles.json src/locales/ar/bundles.json
git -C $W/dashboard commit -m "feat(scheduling): bundle rows priced by country; a mixed-currency group sends no price (B3d D-5)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Record in `orchestration/phases/B2.md` that D-5 landed with B2f (so B3d's R2 (4) is done, with the dot-form key of plan D1), or, if this task was skipped, that R2 (4) stays with B3d and uses `rows.0.price_minor`.

---

### Task 21: End-to-end through Caddy, and the slice gates

**Files:**
- Create: `dashboard/e2e/b2-bundles.spec.ts`

**Interfaces:**
- Consumes: everything above, through the browser; `manage("set_features", "demo", "--on", …)`; `login`, `expectLoggedIn`, `DEMO_URL`, `DEMO_ADMIN` from `./fixtures`.

- [ ] **Step 1: Write the spec** (`dashboard/e2e/b2-bundles.spec.ts`)

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

const SWITCHES = ["study_groups", "group_subscriptions"];

/** The date `days` from now in UTC (demo's academy clock). */
function inDays(days: number): string {
	return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

const weekday = (day: string) =>
	new Intl.DateTimeFormat("en", { weekday: "short", timeZone: "UTC" }).format(
		new Date(`${day}T00:00:00Z`),
	);

// Slice B2f spec §9: the admin makes a study group of two students, subscribes
// it as one group class, sees one subscription and one same-time session per
// student with no clash, and pauses the bundle. Stamped data, so a second run
// on the same database never meets the first run's rows; the asserts read
// durable state (rows, URLs, statuses after a reload), never a toast.
test("the admin subscribes a study group as one class and pauses it", async ({
	page,
}) => {
	test.setTimeout(180_000);
	const stamp = Date.now();
	const teacher = `E2E Circle Tutor ${stamp}`;
	const course = `E2E Circle Recitation ${stamp}`;
	const pkg = `E2E Circle Monthly ${stamp}`;
	const group = `E2E Circle ${stamp}`;
	const students = [`E2E Circle Amal ${stamp}`, `E2E Circle Badr ${stamp}`];
	const today = inDays(0);
	const tomorrow = inDays(1);
	manage("set_features", "demo", "--on", ...SWITCHES);
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// Own teacher, course, package and students
	await page.goto(`${DEMO_URL}/app/people/teachers/new`);
	await page.getByLabel(/^full name/i).fill(teacher);
	await page.getByLabel(/^gender/i).selectOption("male");
	await page.getByLabel(/^email/i).fill(`e2e-circle-tutor-${stamp}@e2e.test`);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/teachers\/\d+$/);

	await page.goto(`${DEMO_URL}/app/catalogue/courses/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`حلقة تجريبية ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(course);
	await page.getByLabel(teacher, { exact: true }).click();
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/courses$/);

	await page.goto(`${DEMO_URL}/app/catalogue/packages/new`);
	await page.getByLabel(/^name \(arabic\)/i).fill(`شهرية تجريبية ${stamp}`);
	await page.getByLabel(/^name \(english\)/i).fill(pkg);
	await page.getByLabel("Sessions per week").fill("2");
	await page.getByLabel("Duration", { exact: true }).fill("1");
	await page.getByLabel("Duration unit").selectOption("month");
	await page.getByLabel("Freeze days allowed").fill("10");
	await page.getByLabel("Price").fill("300");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/catalogue\/packages$/);

	for (const [index, name] of students.entries()) {
		await page.goto(`${DEMO_URL}/app/people/students/new`);
		await page.getByLabel(/^full name/i).fill(name);
		await page.getByLabel(/^email/i).fill(`e2e-circle-${index}-${stamp}@e2e.test`);
		await page.getByLabel("Preferred language").selectOption("en");
		await page.getByRole("button", { name: "Save", exact: true }).click();
		await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);
	}

	// The study group, its two students offered by the server
	await page.goto(`${DEMO_URL}/app/people/groups`);
	await page.getByRole("button", { name: "Add study group" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^Name/).fill(group);
	for (const name of students) {
		await dialog.getByLabel("Find a student").fill(name);
		await dialog.getByRole("button", { name: `Add ${name}` }).click();
	}
	await dialog.getByRole("button", { name: "Save study group" }).click();
	await expect(dialog).toBeHidden();
	await page.reload();
	await page.getByRole("searchbox").fill(group);
	const groupRow = page.getByRole("row", { name: new RegExp(group) });
	for (const name of students) await expect(groupRow).toContainText(name);

	// One group class for both: tomorrow at noon
	await page.goto(`${DEMO_URL}/app/scheduling/subscriptions/new?type=group`);
	await page.getByLabel(/^Study group/).selectOption({ label: group });
	await expect(
		page.getByText(/Active students who will be subscribed: 2/),
	).toBeVisible();
	const row = page.getByRole("group", { name: "Course 1" });
	await row.getByLabel(/^Course/).selectOption({ label: course });
	await row.getByLabel(/^Teacher/).selectOption({ label: teacher });
	await row.getByLabel(/^Package/).selectOption({ label: pkg });
	await row.getByLabel(weekday(tomorrow), { exact: true }).click();
	await row.getByLabel(/^Start time/).fill("12:00");
	await page.getByRole("button", { name: "Create bundle" }).click();
	// No clash warning: the form goes straight to the bundle (plan D12).
	await expect(page).toHaveURL(/\/app\/scheduling\/bundles\/\d+$/);
	const bundlePage = page.url();
	const members = page.getByRole("table", { name: "Members" });
	for (const name of students) {
		await expect(members.getByRole("row", { name: new RegExp(name) })).toBeVisible();
	}

	// One session per student, at the same time, labelled with the group
	await page.goto(`${DEMO_URL}/app/scheduling/sessions`);
	await page.getByLabel("Period").selectOption("upcoming");
	await page.getByRole("searchbox").fill(String(stamp));
	const grouped = page.getByRole("row").filter({ hasText: `Group: ${group}` });
	for (const name of students) {
		await expect(grouped.filter({ hasText: name }).first()).toBeVisible();
	}
	const first = await grouped.filter({ hasText: students[0] }).first().innerText();
	const second = await grouped.filter({ hasText: students[1] }).first().innerText();
	const time = /\b\d{2}:\d{2}\b/;
	expect(first.match(time)?.[0]).toBe(second.match(time)?.[0]);

	// Pause the bundle from today: both members read Paused after a reload
	await page.goto(bundlePage);
	await page.getByRole("button", { name: "Pause bundle" }).click();
	const pause = page.getByRole("dialog");
	await pause.getByLabel(/^From/).fill(today);
	await pause.getByLabel(/^To/).fill(inDays(2));
	await pause.getByLabel(/^Reason/).fill("E2E break");
	await pause.getByRole("button", { name: "Pause bundle" }).click();
	await expect(pause).toBeHidden();
	await page.reload();
	for (const name of students) {
		await expect(
			page.getByRole("table", { name: "Members" }).getByRole("row", {
				name: new RegExp(name),
			}),
		).toContainText("Paused");
	}

	// At phone width the bundle page never scrolls sideways
	await page.setViewportSize({ width: 375, height: 800 });
	await page.reload();
	await expect(page.getByRole("table", { name: "Members" })).toBeVisible();
	expect(
		await page.evaluate(
			() => document.documentElement.scrollWidth <= window.innerWidth,
		),
	).toBe(true);
	await page.setViewportSize({ width: 1280, height: 800 });

	// Arabic reads right to left
	await page.evaluate(() => localStorage.setItem("etqan-locale", "ar"));
	await page.goto(`${DEMO_URL}/app/people/groups`);
	await expect(
		page.getByRole("heading", { name: "المجموعات الدراسية" }),
	).toBeVisible();
});
```

- [ ] **Step 2: Run it, twice, on the stream's database**

Run: `just e2e e2e/b2-bundles.spec.ts` (twice). Expected: `1 passed` both times. If a list loads slowly under host load, raise only the single wait that timed out, with a comment; never add a fixed sleep.

- [ ] **Step 3: Commit**

```bash
git -C $W/dashboard add e2e/b2-bundles.spec.ts
git -C $W/dashboard commit -m "test(e2e): a study group subscribed as one class, then paused (B2f)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: The slice gates**

Run, from `$W`: `just test` (backend ≥ 80 %, dashboard lines/statements ≥ 80, branches/functions ≥ 70), `just lint` (ruff, `lint-imports`, Biome, the colour checker), then a fresh stack (`just dev-backend`, `migrate_schemas`, `seed_dev` — the demo now has a study group and three bundles) and the whole `just e2e` (it runs `--workers=1 --retries=1`). Expected: all green. The seeded bundles add sessions to Ustadh Bilal's and Ustadha Maryam's days; a pre-existing spec that breaks on them is narrowed to its own stamped rows (never by changing the seeds' meaning) and the change is reported. Report the counts, the coverage figures, and any spec that only passed on its retry (with its failing step).

---
## Self-review (done while writing)

**Spec coverage** (spec section → task):
- §1 goal, F-11 switches → Task 2 (registry, `BUILT`, `requires`), Tasks 10-11 (per-kind create routes behind their switches; group routes behind `study_groups`; the shared routes ungated and listed in `UNGATED`; `requires` → 404 while `families` is off), Tasks 14, 16 (screens and types by switch and code).
- F-1 / §3.1 / §4.1 study groups (one per student, active rules, delete refused in use) → Tasks 2, 3, 10, 14; plan D13 (candidates), D23 (race).
- F-2 kinds and row rules / §4.2 create (validation, re-keyed errors, all-or-nothing, billing per member, clashes with F-4) → Task 6 (services), Task 11 (routes, invoices, 400 bodies), Tasks 15-16 (form).
- F-3 members are ordinary subscriptions; totals read, never stored → Task 4, Task 9 (`test_a_members_numbers_are_a_plain_subscriptions`: derived numbers, invoices, payroll, notices), Task 9 / 11 (totals per currency).
- F-4 / §4.4 clash exemption in `conflicts` and `teacher_busy`; the label → Task 5, Task 9 (`group` on sessions), Task 19 (chips).
- F-5 current members, all or nothing → Task 7 (`is_current`, `each_member`, every action), Task 8.
- F-6 renewal keeps bundle and course → Task 4 (service and API routes).
- F-7 roster changes; the group and the bundle are separate → Task 8 (add from the template, remove with a pending renewal), Task 3 (`update_group` touches no bundle), Task 18 (Add / Remove).
- F-8 family bundles need `families` → Task 11 (`test_a_family_bundle_needs_families_on`); BR-14 not enforced → nothing added.
- F-9 dissolve; the last member's delete → Tasks 4, 7, 11, 18.
- F-10 roster → Task 9 (`RosterRow`, attended), Task 11 (payload), Task 17 (tab).
- §4 lock order → Task 4 (delete), Task 7 (every action, SQL capture with `ORDER BY 1 ASC FOR UPDATE`), Task 6 (the group's lock); plan D2.
- §4.3 each action → Tasks 7, 8 (services), 11 (routes), 18 (UI).
- §4.5 reading (payload, `bundle` on subscriptions, list filters `bundle` / `bundle_kind`, `group` on sessions, bundles list filters) → Tasks 9, 11.
- §4.6 `member_id` → Tasks 1, 7, 8, 11, 13 (`refusalText`), 18.
- §5 access (`study_group` resource, bundle codes, non-office 404) → Tasks 10, 11.
- §6 API table → Tasks 10, 11 (every row of the table is in `ROUTES`).
- §7 dashboard → Tasks 13-19; strings in `bundles.json` / `studyGroups.json`, RTL and phone width checked in Task 21.
- §8 seeds → Task 12. §9 testing → every task's tests, Task 21's e2e.
- §10 known limits are kept as stated (a group class paid N times, D15; one row moved or cancelled alone; totals per currency, shown only; no following of later group or family changes). §11 out of scope is untouched.
- Ledger D23 / B3d D-5 → Task 20, conditional, with its own tests, run before the e2e and the gates (Task 21).

**Placeholder scan:** no "TBD"/"TODO"/"similar to Task N"; every code step shows its code. `…` stands for the docker compose prefix in commands and, inside a code block that edits an existing function, for that function's unchanged lines (each such block names the function and what changes).

**Type and name consistency:** backend — `create_group` / `update_group(fields=)` / `delete_group` / `groups_queryset` / `filter_groups(q, is_active)` / `group_candidates(q, group)` (Task 3); `create_subscription(bundle=)` / `copied_slots` (Task 4); `GROUP_BUNDLE_ID` / `group_siblings(one, other, groups)` / `group_bundle_of` (Task 5); `create_bundle(kind, by, *, …)` / `CreatedBundle` / `BUNDLE_KINDS` (Task 6); `is_current` / `lock_bundle` / `refused` / `each_member` and `renew_bundle(bundle, *, by, starts_on)` / `pause_bundle(bundle, *, from_date, to_date, reason)` / `cancel_bundle(bundle)` / `update_bundle(bundle, *, notes)` / `dissolve_bundle(bundle)` (Task 7); `archive_bundle` / `restore_bundle(bundle, *, by)` / `add_to_group_bundle(bundle, *, student_id, starts_on)` / `remove_from_group_bundle(bundle, *, student_id)` (Task 8); `bundles_queryset` / `filter_bundles` / `bundle_view` / `BundleView` / `RosterRow` / `BUNDLE_STATES` / `has_bundles` (Task 9) — used with these signatures by Tasks 10-12 and 21. Conftest helpers `deactivated`, `other_course`, `bare_bundle`, `row`, `make_group`, `make_family`, `group_bundle`, `multi_bundle`, `member_of`, `bundles_on` are defined once (Tasks 3, 4, 6). Dashboard — `BundleRef`, `GroupLabel` (in `schemas.ts`), `BundleKind`, `BundleDetail`, `BundleMember`, `RosterRow`, `StudyGroup`, `BundleFormValues`, `BundleRowValues`, `StudyGroupFormValues`, `bundleApi.*`, `useStudyGroups`, `useGroupCandidates`, `useBundle`, `refusalText`, `memberIdOf` (Task 13) are what Tasks 14-21 import; `BundleRowFields(index, students, onRemove, studentTime)` (Task 15) is what `BundleForm` renders (Task 16); `BundleRoster(bundle, actions)` (Task 17) takes `RemoveStudentButton` (Task 18).

**Review Focus:** five lines, each with its test in the owning task (Tasks 4, 5, 7). Other input classes the spec implies and the tasks already cover: another academy's group or bundle id (Tasks 10, 11), a student inactive since the group was made (Tasks 6, 7, 8), a retired family (Task 6), switching a bundle kind off after bundles exist (Task 11, FT-4), a member deleted on its own (Task 4), the same student added twice to a group bundle (Task 8), a malformed create body (Task 11).

**Known minors, accepted (review of 2026-10-05):**
- G-1: students and parents get `bundle` on their own subscription rows from the API (spec §5), but no backend test reads it as a non-office viewer and `FamilySubscriptions.tsx` shows no label; the API alone is taken to satisfy §5 for now.
- G-2: `test_seed_dev.py` and `test_seed_staging.py` are edited (counts narrowed to non-bundle rows, D21), as B2d and B2e did; every other existing suite is unchanged.
- M-4: the Add-student dialog's student list (`usePeople` in `AddStudentAction`) loads with the bundle page, not only when the dialog opens.
- M-5: Task 20 reads the country from `StudentProfile.country` — verified against plan 36's text, to confirm on merged code at build.
- M-7: the "Study groups" nav item sits under the B2 marker in the People group, not directly next to Families, with the `Users` icon Parents also uses.

---

## Spec amendments (for the controller)

The plan departs from or adds to the approved B2f spec in four places; record them as amendments to `docs/superpowers/specs/2026-10-03-b2f-bundles-groups-design.md` and in `orchestration/phases/B2.md`, so B4 and B11 read the shipped contract:

- **D5** — §4.3 Pause applies to every **live** member whose term holds `from_date` (not only current members); Cancel cancels every live member, the old link and a pending renewal alike. No candidate: pause → 400 on `from_date`; cancel → 409 `scheduling.not_allowed_in_status`.
- **D7** — F-6's refusal of a course change on a member's renewal is 400 on `course` (the body key), not `course_id`.
- **D13** — a route added to §6: `GET groups/candidates/?q=&group=<id>` (codes `study_group.create` or `study_group.update`, feature `study_groups`) answers who may join a study group.
- **D15** — service signatures in §4.3 drop the unused `by`: `pause_bundle`, `cancel_bundle`, `add_to_group_bundle`, `remove_from_group_bundle`, `update_bundle`, `dissolve_bundle` take none; `renew_bundle`, `archive_bundle`, `restore_bundle` take it keyword-only.

Also tell the conductor and B3 (ledger R2 (4), B3d D-5): the group refusal's key is `rows.0.price_minor` (D1).

---

**Execution:** Plan 37 has 21 tasks — 12 backend (platform → models → services → API → seeds), 7 dashboard (13-19), one conditional task (20: B3d's D-5 group currency rules, backend and dashboard) that the controller runs only if B3d has merged first, then the e2e with the slice gates (21), which therefore always cover Task 20's changes when it runs. The tasks depend on each other's interfaces in a strict chain (Task 13's types feed every dashboard task; Tasks 3-9's services feed 10-12), so subagent-driven execution with a review after each task, as Plans 21, 25, 31 and 33 were built, is the fitting method.
