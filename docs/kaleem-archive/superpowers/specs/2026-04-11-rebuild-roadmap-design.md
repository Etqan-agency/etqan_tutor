---
name: kaleem-rebuild-roadmap
description: Step-by-step roadmap for rebuilding kaleem from an incomplete MVP into a clean, scalable modular-monolith LMS, covering architecture, phasing, process discipline, risks, and escape hatches
type: design-spec
status: draft
created: 2026-04-11
phase: 0
modules: [all]
supersedes: none
---

# kaleem Rebuild Roadmap

## Purpose of this document

kaleem is currently an incomplete MVP with architectural inconsistencies, design drift, and accumulated technical debt. The product (an LMS for teaching non-Arabic speakers Islamic sciences) is well-motivated, but the codebase that tried to express it has enough structural problems that continuing in-place is more expensive than a controlled rebuild.

This document is the full roadmap for that rebuild. It covers:

1. The decisions already made (so nothing drifts silently)
2. The module map and boundary rules (so the rebuild does not reproduce the same tangle)
3. The phased plan from `Phase 0` to `Phase E` with explicit exit criteria
4. The process and discipline rituals that determine whether this attempt succeeds
5. The real risks and their mitigations
6. The pre-approved escape hatches for when the plan must change

The roadmap is written for **future-you** (a solo developer, Abdulkhalek Muhammad) and for **AI coding agents** that will collaborate on the rebuild. Everything here is load-bearing. When in doubt, re-read it rather than improvise.

---

## Context

- **Product:** kaleem — a subscription-based LMS that teaches non-Arabic speakers Islamic sciences (Quran, Tafsir, Arabic language). Users are students, parents, teachers, and admins. A parent subscribes to a monthly plan (e.g., 4 sessions/month), a teacher delivers structured lessons, both sides rate each other and exchange reports.
- **Business model (v1):** B2C subscriptions via Stripe. B2B and per-seat are future-scope.
- **Current state:** not deployed, no real users, no production data. This is the best-possible state for a rebuild — nothing to preserve, nothing to migrate.
- **Team:** solo developer (you).
- **Timeline:** none — "done when it's done".
- **Starting point:** the existing `kaleem/` Django + React repository, which becomes a **read-only reference** during the rebuild but is not extended further.

---

# Section 1 — Decisions recap

Before any roadmap work, the foundational decisions that were agreed during brainstorming. If any of these change later, it must be via an ADR that supersedes this section.

## 1.1 Product decisions

- **v1 scope (as explicitly chosen by the user, against my recommendation):** the full feature list — authentication, student/parent/teacher/admin roles, teacher availability + student booking, 1-on-1 and group sessions with Zoom, trial sessions, Stripe subscriptions, dashboards for every role, curriculum builder, per-session reports + ratings, resources library, in-app chat, email + in-app notifications, gamification (points, badges, streaks, levels), multi-language (Arabic + English; French cut), PWA, teacher payouts, mobile (later as PWA), admin panel (Django admin in v1). See Appendix A for the explicit disagreement and why it is documented here.

## 1.2 Technical stack (confirmed, locked in)

| Concern | Choice |
| --- | --- |
| Backend framework | Django 5.x + Django REST Framework |
| Async tasks | Celery + Redis |
| Database | Postgres |
| Auth library | django-allauth (wrapped behind the identity module's public API, replaceable) |
| API docs | drf-spectacular |
| Dashboard frontend | React 19 + TanStack Router + TanStack Query + Tailwind + shadcn/Radix; minimal Zustand only for pure client state |
| Marketing site | Astro (separate submodule) |
| Infrastructure | Self-hosted VPS(s) with Docker Compose |
| Optional escape | Next.js as an option for marketing if Astro is ever insufficient (not committed) |

## 1.3 Architecture decisions

- **Architecture style:** modular monolith with **enforced module boundaries** via `import-linter`. No cross-module model imports; all inter-module communication is via each module's public API (`<module>/services.py`) or in-process domain events.
- **Identity model:** a single `User` (from allauth) plus optional `StudentProfile`, `TeacherProfile`, `ParentProfile` tables as `OneToOne`. One person can have multiple profile rows (e.g., a teacher who is also a parent). `Admin` is represented by `User.is_staff = True`, not a separate model. **Multi-table inheritance (the current code's approach) is explicitly forbidden.**
- **Authentication:** session cookies with real CSRF protection, same-origin frontend and backend. JWT is deferred until a native mobile client exists (if ever). The current `CsrfExemptSessionAuthentication` hack is removed.
- **allauth:** kept, but **wrapped**. Nothing outside the `identity` module imports from `allauth` directly. The `identity/services.py` public API exposes `register_student`, `register_teacher`, `register_parent`, `verify_email`, `request_password_reset`, etc. If allauth is ever replaced, only the `identity` module changes.

## 1.4 Execution decisions

- **Rebuild approach:** **Approach 2 — greenfield parallel rebuild**. A fresh project structure is built alongside the current repo. The current `kaleem/` code becomes a read-only reference for "what does this feature need to do", but no code is copy-pasted — everything is re-implemented under the new rules.
- **Sequencing:** **S2 — happy-path first**. The critical path (identity → billing → scheduling → assessment → analytics) is built first so that after Phase B, kaleem is functionally a working LMS. All subsequent phases add depth, breadth, or polish without breaking what Phase B shipped.

## 1.5 Repository layout (confirmed)

A single meta repo `kaleem/` at the top level, with **git submodules** for sub-projects:

```
kaleem/                          ← meta repo (top-level)
├── backend/            [sm]     ← Django + DRF modular monolith
├── dashboard/          [sm]     ← React + TanStack (authenticated app)
├── marketing/          [sm]     ← Astro (landing, pricing, about, blog)
├── infra/              [sm]     ← docker-compose.*, nginx, deploy scripts
├── docs/                        ← specs, ADRs, journal, runbooks, architecture
│   ├── superpowers/
│   │   ├── specs/
│   │   ├── plans/
│   │   └── journal/
│   ├── adr/
│   ├── architecture/
│   ├── developer-guide/
│   ├── runbook/
│   └── templates/
├── .github/
│   └── workflows/               ← orchestrates CI across submodules
├── .claude/                     ← hooks, skills, memory (agent-friendly setup)
├── CLAUDE.md                    ← operating manual for Claude-based agents
├── AGENTS.md                    ← same content, symlinked, for Cursor/Aider/Continue
├── STATE.md                     ← current phase + in-progress spec
├── ISSUES.md                    ← "spotted it, fix later" backlog
├── justfile                     ← single-command task entrypoints
└── README.md
```

**Rationale for putting `docs/` in the meta repo:** specs and ADRs frequently span multiple submodules. Placing them inside any single submodule would misrepresent scope. The meta repo is the only place where cross-cutting documentation naturally belongs.

**Submodule pitfall warning (documented once, then dropped):** git submodules have a learning curve — detached HEAD, forgotten `git submodule update`, CI gotchas. If friction costs more than ~1h/week, switch to a pnpm workspace monorepo via escape hatch **E1**.

## 1.6 Monitoring & observability (Phase 0 deliverable, not deferred)

A minimal self-hosted open-source stack, free at this scale:

- **Sentry** (self-hosted or free tier) for error tracking and performance monitoring in backend and frontend
- **OpenTelemetry SDK** in the Django app for vendor-neutral instrumentation
- **Prometheus + Grafana + Loki** (one VPS) for metrics, logs, dashboards
- **Uptime Kuma** for external uptime checks and alerts
- **django-debug-toolbar + django-silk** in dev/staging only
- **Structured JSON logging** from day 1, with request ID propagation through Celery
- **Health check endpoints:** `/health/live` and `/health/ready` consumed by Docker healthchecks and Uptime Kuma

Lives in the `infra/` submodule as a separate `monitoring/` docker-compose stack. **Brought online in Phase 0 — you cannot debug what you cannot see.**

## 1.7 Documentation for developer onboarding (written progressively)

The target: a new developer (or future-you after 6 months away) can get kaleem running locally and understand the architecture in **under 2 hours**.

Required documents, written progressively as the rebuild happens:

| Doc | Location | Purpose | When |
| --- | --- | --- | --- |
| `README.md` (meta) | meta repo | Overview, prerequisites, 5-minute quick-start | Phase 0 |
| `README.md` (per submodule) | each submodule | Sub-project purpose, quick-start | Phase 0 |
| `CONTRIBUTING.md` | meta repo | Coding standards, PR process, test requirements, D1–D11 summary | Phase 0 |
| `docs/architecture/overview.md` | meta repo | Module map, boundaries, data flow, Mermaid diagram | Phase 0 |
| `docs/architecture/<module>.md` | meta repo, one per module | Module responsibility, public API, data model, dependencies | As each module is built |
| `docs/adr/NNNN-*.md` | meta repo | Architecture Decision Records (per D8) | Continuously |
| `docs/developer-guide/local-setup.md` | meta repo | Local dev env, docker-compose, seed data, test users | Phase 0 |
| `docs/developer-guide/testing.md` | meta repo | How to run tests, coverage targets, TDD workflow | Phase 0 |
| `docs/developer-guide/common-tasks.md` | meta repo | Recipes: add a new module, new endpoint, new model | Phase 0, extended |
| `docs/runbook/deploy.md` | meta repo | Deploy, rollback, manage env vars | Phase 0 |
| `docs/runbook/backup-restore.md` | meta repo | DB backup, media backup, restore procedures | Phase 0 |
| `docs/runbook/incidents.md` | meta repo | Common incidents and what to do | Continuously |
| `CLAUDE.md` | meta repo | Operating manual for AI agents | Phase 0, extended |
| `docs/superpowers/specs/*.md` | meta repo | Per-feature specs (per D1) | Continuously |
| `docs/superpowers/journal/YYYY-WW.md` | meta repo | Weekly journal entries (per D7) | Continuously |

**Rule (extends D9):** a module is not "done" until its `docs/architecture/<module>.md` is written. No exceptions.

## 1.8 Agent-friendly project setup

Every agent session dropped into this repo should have enough structured context to work productively within 30 seconds. Everything below is committed to git.

### Auto-loaded context files

| File | Purpose |
| --- | --- |
| `CLAUDE.md` (meta root) | Full operating manual for Claude-based agents |
| `AGENTS.md` (meta root) | Symlink to CLAUDE.md, picked up by Cursor, Aider, Continue |
| `.github/copilot-instructions.md` | Key rules mirrored for GitHub Copilot |
| `CLAUDE.md` (per submodule) | Scoped context, loaded in addition to the meta one |
| `CLAUDE.md` (per backend module) | Tiny per-module file: what it owns, its public API, what not to import |
| `.editorconfig` | Consistent formatting for every editor and agent |

### Claude Code hooks (`.claude/settings.json`)

**SessionStart**
- Print current phase, in-progress spec, top entries from `ISSUES.md`
- Run `git status` and show it

**PreToolUse**
- Bash commands matching `rm -rf`, `git push --force`, `git reset --hard`, `git checkout .` → block unless explicitly approved
- Bash `git commit` → verify Ruff, Biome, mypy green
- Edit/Write to `backend/kaleem/<module>/models.py` → remind to update migrations and architecture doc

**PostToolUse**
- Edit/Write to `*.py` → run `ruff check --fix` + `ruff format` on the file
- Edit/Write to `*.ts`/`*.tsx` → run `biome check --apply` on the file
- Edit/Write to `backend/kaleem/<module>/services.py` → warn "public API changed, does any caller need updating? does the architecture doc need updating?"
- Edit/Write to `backend/kaleem/<module>/models.py` → run `python manage.py makemigrations --dry-run --check`

**UserPromptSubmit**
- Inject a small reminder of current phase and next uncompleted task from the active spec

**Stop / SubagentStop**
- Warn if there are uncommitted changes and no open spec

### Project slash commands

| Command | Does |
| --- | --- |
| `/new-feature <name>` | Scaffolds a spec file from template, refuses to proceed to code until committed |
| `/new-module <name>` | Scaffolds a new backend module with standard structure, registers it, adds to import-linter |
| `/new-adr <title>` | Creates auto-numbered ADR from template |
| `/run-tests` | Runs backend + frontend tests in correct order |
| `/journal` | Opens this week's journal file for the D7 ritual |
| `/check-boundaries` | Runs import-linter manually |
| `/ship` | Walks the Definition of Done checklist interactively |

### Single-command task entrypoints (`justfile`)

```
just setup          # clone submodules, install deps, create DBs, seed data
just dev            # bring up everything locally
just test           # run all tests (backend + frontend + boundary linter)
just test-backend
just test-frontend
just lint           # ruff + mypy + biome + tsc + import-linter
just migrate
just shell          # Django shell_plus
just deploy
just new-module X
just seed           # reset DB and load seed_basic fixture
```

### Git-level enforcement (`.pre-commit-config.yaml`)

- `ruff check` + `ruff format` (backend)
- `mypy` (backend)
- `biome check` (frontend)
- `tsc --noEmit` (frontend)
- `import-linter` (backend, module boundaries)
- `gitleaks` (block committed secrets)
- Forbid committing `.env*` files
- Conventional-commits message format
- Trailing whitespace, EOL, large-file check

CI runs the exact same suite so local and CI cannot diverge.

### Seed data

`backend/kaleem/platform/fixtures/` contains `seed_basic.py` (1 admin, 2 teachers, 3 parents, 5 students, 3 plans, 2 courses, 10 sessions, some completed with reports) and `seed_rich.py` for larger datasets. Every test user has a predictable email and password, documented in `docs/developer-guide/local-setup.md`.

### Machine-readable project state

- **`STATE.md`**: frontmatter with `current_phase`, `active_spec`, `active_branch`, `last_green_ci`. Updated by `/journal` and `/ship`. Auto-loaded at session start.
- **Specs** and **ADRs**: all have structured frontmatter so agents can query them.

---

# Section 2 — Module map & boundaries

The modular monolith stands or falls on whether these boundaries are real. Each module has **four fixed fields** that must appear in its `docs/architecture/<module>.md`:

1. **Owns** — the data (DB tables) that belong to this module. No other module queries these tables directly.
2. **Public API** — the service functions in `<module>/services.py` or `<module>/api.py` that other modules call.
3. **Depends on** — which other modules this one calls.
4. **Does not do** — explicit non-goals.

## 2.1 Backend modules (11)

### 1. `identity`
- **Owns:** `User` (via allauth), `StudentProfile`, `TeacherProfile`, `ParentProfile`, email verification, password reset, sessions, MFA
- **Public API:** `register_student(email, password, name, age, parent_id?)`, `register_teacher(...)`, `register_parent(...)`, `get_user(id)`, `get_profile(user, role)`, `change_password(...)`, `verify_email(...)`, `assign_child_to_parent(...)`, `assign_student_to_teacher(...)`
- **Depends on:** nothing (foundation)
- **Does not do:** authorization logic for other modules (each module decides its own access rules); profile photos (stored in `content`)

### 2. `billing`
- **Owns:** `SubscriptionPlan`, `Subscription` (one user can have many over time, **not** `OneToOne`), `Invoice`, `StripeCustomerRef`, `StripeEventLog`
- **Public API:** `list_active_plans()`, `create_checkout_session(user, plan)`, `handle_stripe_webhook(payload, signature)`, `get_active_subscription(user)`, `cancel_subscription(user)`, `is_entitled_to(user, capability)`
- **Depends on:** `identity`
- **Does not do:** anything with sessions/bookings (that is `scheduling`, which asks billing for entitlement)
- **Future:** teacher payouts live here in Phase D, not a separate module

### 3. `scheduling`
- **Owns:** `TeacherAvailability` (recurring weekly pattern), `Booking`, `Session` (actual scheduled session with Zoom link), `TrialRequest`, `TrialSession`
- **Public API:** `list_availability(teacher, from, to)`, `book_session(student, teacher, datetime)`, `cancel_session(session, reason)`, `complete_session(session)`, `request_trial(student, preferences)`, `approve_trial(trial_request, teacher, datetime)`, `upcoming_sessions(user)`
- **Depends on:** `identity`, `billing` (entitlement check before booking), `notifications` (via public API for reminders)
- **Does not do:** video API calls directly — delegated to an internal `scheduling/integrations/video.py` adapter inside the module. v1 adapter targets Zoom; v2 replaces it with a custom WebRTC/SFU implementation (full custom P2P video service — see Appendix C).
- **Note:** the old code's `TimeSlot.occupy_time` static method is thrown out. Scheduling logic lives in services, not on models. The video adapter interface is designed to be stable across the Zoom→custom swap: `create_room(session)`, `get_join_url(session, user)`, `end_room(session)`.

### 4. `assessment`
- **Owns:** `SessionReport`, `Rating`, `ProgressSnapshot`
- **Public API:** `write_session_report(session, teacher, content, rating)`, `rate_teacher(session, student, stars, comment)`, `rate_student(session, teacher, stars, comment)`, `list_reports_for_student(student)`, `get_progress(student)`
- **Depends on:** `identity`, `scheduling` (read-only via public API)
- **Does not do:** dashboard aggregation (that is `analytics`)
- **Note:** `SessionReport.content` is a **typed** JSONField validated by a Pydantic schema — not free-form JSON like the old code

### 5. `curriculum`
- **Owns:** `Course`, `Unit`, `Lesson`, `LessonAssignment`, `LessonCompletion`
- **Public API:** `create_course(teacher, ...)`, `add_unit(course, ...)`, `add_lesson(unit, ...)`, `assign_lesson(lesson, student)`, `mark_lesson_complete(lesson, student)`, `get_student_curriculum(student)`
- **Depends on:** `identity`, `content` (lessons may reference resources)
- **Does not do:** session attendance (`scheduling`), grading (`assessment`)

### 6. `content`
- **Owns:** `Resource`, `ResourceCategory`, `ResourceAssignment`, `UserUpload`
- **Public API:** `upload_resource(teacher, file, metadata)`, `assign_resource(teacher, student, resource)`, `list_assigned_resources(student)`, `upload_user_file(user, file, kind)`
- **Depends on:** `identity`
- **Does not do:** video streaming (third-party), virus scanning (delegated to an adapter)
- **Note:** profile photos move here from `identity` — profile photos are user-uploaded files, which is a `content` concern

### 7. `messaging`
- **Owns:** `Chat`, `ChatMembership`, `Message`, `MessageMedia`, `ReadReceipt`
- **Public API:** `create_direct_chat(user_a, user_b)`, `create_group_chat(...)`, `send_message(chat, author, content, attachments?)`, `list_chats(user)`, `list_messages(chat, pagination)`, `mark_read(chat, user, up_to_message_id)`
- **Depends on:** `identity`, `notifications`
- **Does not do:** presence/typing indicators (v2), video calls (that is `scheduling` via Zoom)
- **Note:** uses `User` not `UserProfile` as author (fixes the old code's bug)

### 8. `notifications`
- **Owns:** `NotificationPreference`, `NotificationLog`, `EmailTemplate`, `ReminderSchedule`
- **Public API:** `notify(user, kind, payload)`, `schedule_reminder(user, kind, when, payload)`, `set_preferences(user, prefs)`, `get_preferences(user)`
- **Depends on:** `identity`
- **Does not do:** decide *when* domain events happen — each module calls `notify()` when *it* decides
- **Note:** v1 channels: email (transactional), in-app (stored, surfaced via API). Push/SMS are v2.

### 9. `engagement`
- **Owns:** `PointsLedger`, `Badge`, `BadgeAward`, `Streak`, `LevelDefinition`
- **Public API:** `award_points(user, reason, amount)`, `check_and_award_badges(user)`, `get_user_state(user)`, `get_leaderboard(scope)`
- **Depends on:** `identity`
- **Does not do:** decide what triggers points — each module calls `award_points` when something gamifiable happens

### 10. `analytics`
- **Owns:** no primary data; only derived/cached aggregations (`DashboardSnapshot`, `MetricCache`)
- **Public API:** `get_student_dashboard(student)`, `get_teacher_dashboard(teacher)`, `get_parent_dashboard(parent)`, `get_admin_overview()`
- **Depends on:** read-only via public APIs of `identity`, `scheduling`, `assessment`, `billing`, `engagement`
- **Does not do:** own any source-of-truth data
- **Note:** replaces the current `dashboard/api/views.py` which directly imports models from 3 other apps — exactly the boundary violation this module fixes

### 11. `platform` (cross-cutting)
- **Owns:** structured logging config, request ID middleware, base pagination classes, common exceptions, health check endpoints, OpenTelemetry setup
- **Public API:** imported by everything, imports nothing from business modules
- **Depends on:** nothing
- **Does not do:** any business logic

## 2.2 Boundary enforcement rules

These are encoded as `import-linter` contracts:

1. No business module may import models from another business module. Only public APIs (`<module>.services`, `<module>.api`, `<module>.types`).
2. No business module may import from another module's `views`, `serializers`, or `tasks`.
3. `analytics` may only read from other modules via public APIs. It may not write to other modules.
4. `platform` may be imported by any module but may import no business module.
5. Circular dependencies are forbidden at the module level. If two modules need each other, one publishes an event and the other subscribes.
6. `identity` depends on nothing. It is the bedrock.

## 2.3 Inter-module communication styles

- **Synchronous service calls (default):** direct Python function calls via the public API. Typed, debuggable, used when the caller needs a result now.
- **Asynchronous domain events (escape hatch):** for fan-out cross-module concerns (gamification, notifications). A tiny in-process event bus (wrapped Django signals or a small dispatcher). Used sparingly.
- **Celery tasks:** for anything that can defer (emails, report generation, Stripe webhook handling, Zoom meeting creation).

## 2.4 Frontend module mirror (dashboard submodule)

Under `dashboard/src/features/`, one feature folder per backend module:

```
features/
├── identity/           (login, register, profile)
├── billing/            (plans, checkout, invoices)
├── scheduling/         (availability editor, booking UI, session view)
├── assessment/         (reports, ratings)
├── curriculum/         (lesson browsing, completion)
├── content/            (resources library)
├── messaging/          (chats, messages)
├── notifications/      (in-app feed, preferences)
├── engagement/         (badges, streaks, leaderboard)
├── analytics/          (dashboards)
└── admin/              (admin-only UI — Django admin for v1, custom later)
```

Each feature folder owns its routes, components, API client functions, and Zod schemas. Shared UI primitives live under `dashboard/src/ui/`. No feature imports from another feature's internals — only via its public `index.ts`.

---

# Section 3 — Phased roadmap

Six phases. Each has a **single clear deliverable**, explicit exit criteria, and a list of what is deliberately *not* in that phase. Phases are sized by spec count, not weeks.

**Rule:** no phase starts until the previous phase's exit criteria are all green. This is the anti-scope-creep guardrail.

## Phase 0 — Bootstrap

**Goal:** a healthy, agent-friendly, CI-green empty skeleton that an agent or future-you can pick up instantly.

**In scope:**
- Meta repo + 4 submodules (`backend`, `dashboard`, `marketing`, `infra`) initialized
- Backend: fresh Django project, Postgres + Redis + Celery wired, Docker Compose for local
- Frontend: Vite + React + TanStack Router + TanStack Query + Tailwind + shadcn skeleton
- Marketing: Astro skeleton with one placeholder page
- `platform` module created (structured logging, request ID middleware, pagination, health checks, OpenTelemetry, error classes)
- `import-linter` configured with the Section 2 contracts (enforced from day 1 even with empty modules)
- Pre-commit + ruff + mypy + biome + tsc + gitleaks + conventional-commits all green
- CI pipeline: lint → type → test → boundary-check → build, green on an empty project
- Sentry integrated in backend + frontend, test error dispatched and verified
- Uptime Kuma deployed to infra, monitoring staging health checks
- Prometheus + Grafana + Loki stack deployed to infra
- `justfile` with all task targets, each proven working
- `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `.editorconfig` committed
- `.claude/settings.json` hooks committed and verified
- `.claude/skills/` with `/new-feature`, `/new-module`, `/new-adr`, `/run-tests`, `/journal`, `/check-boundaries`, `/ship`
- `docs/` skeleton
- **ADR-0001 through ADR-0010** written: modular monolith choice, identity model, auth strategy, repo layout, the big-v1 scope decision and my explicit disagreement, Sentry choice, Docker Compose vs K8s, submodule vs monorepo, CSRF+session vs JWT, allauth wrap decision
- `README.md` (meta + per-submodule) — fresh clone must go to running local via `just setup && just dev`
- `STATE.md` initialized
- One VPS provisioned with staging env, deploy runbook written and tested

**Exit criteria:**
- Fresh `git clone --recursive && just setup && just dev` brings up the full local stack with seeded test users
- `just test` and `just lint` green
- CI green
- A test error appears in Sentry
- Uptime Kuma shows staging as up
- `docs/architecture/overview.md` contains the module map diagram
- A fresh reader of `CLAUDE.md` + `docs/developer-guide/local-setup.md` can run the project without asking questions

**Size:** ~8–12 specs.

**Not in this phase:** any feature code, any domain model beyond `platform`, any frontend route other than a placeholder.

**The Phase 0 trap:** resist the urge to skip this. Every hour here saves ten later.

## Phase A — Identity

**Goal:** a real human can register as a student / teacher / parent, verify their email, log in, log out, reset password, and see their own profile.

**In scope:**
- `identity` module: `User`, profiles, roles, allauth wrapped behind public API
- Session + CSRF auth, end-to-end with React
- Registration flows for all three roles (admin via `createsuperuser`)
- Email verification with custom templates
- Password reset
- Profile edit
- Dashboard shell: routes for `/login`, `/register/:role`, `/verify`, `/forgot`, `/app` (where `/app` is just "hello, <name>")
- Django admin enabled for `User` and profiles (v1 admin panel; no custom UI yet)
- Full test coverage: services, API endpoints, auth flows, email verification, boundary check

**Exit criteria:**
- All 3 registration flows work through the UI end-to-end
- Email verification arrives in Mailpit locally and in real inbox on staging
- Password reset works
- `identity/` services are the only thing importing from `allauth`
- `docs/architecture/identity.md` written, including ER diagram
- `import-linter` passes
- Coverage on `identity/services.py` ≥ 90%

**Size:** ~5–7 specs.

## Phase B — Happy path

**Goal:** the single most valuable phase — by the end, kaleem is functionally a working LMS. A parent can pay, a student can book, a teacher can teach, a report exists.

### B1 — `billing`
- `SubscriptionPlan` (Django admin CRUD)
- `Subscription` (one-to-many over time)
- Stripe checkout session creation
- Stripe webhook handling with signature verification, idempotent event processing, `StripeEventLog`
- `is_entitled_to(user, capability)` service used by scheduling
- Pricing page in React (list plans, click → checkout → return)
- Billing section in profile (current plan, history, cancel)

### B2 — `scheduling`
- `TeacherAvailability` (recurring weekly pattern, timezone-aware)
- Availability editor UI for teachers
- `Booking` + `Session` models
- Student booking UI ("here are my teacher's slots, pick one")
- **Video integration wrapped in an internal adapter** (`scheduling/integrations/video.py`), Zoom meeting created asynchronously via Celery on session confirmation. The adapter interface (`create_room`, `get_join_url`, `end_room`) is designed to survive the v2 swap from Zoom to a custom WebRTC service (see Appendix C)
- `cancel_session`, `complete_session`, `upcoming_sessions` APIs
- Entitlement check via `billing.is_entitled_to` before booking — no active subscription = no booking
- Session detail view with Zoom join button
- Timezones: user sets timezone in profile; availability stored in teacher's tz; displayed in viewer's tz

### B3 — `assessment`
- `SessionReport` with typed `content` (Pydantic schema)
- `Rating` (symmetric: student rates teacher, teacher rates student; parent can rate at month boundaries)
- Teacher writes report after session (UI form against the typed schema)
- Student + parent view the report
- Aggregate "your avg rating" per role
- `scheduling.complete_session()` prompts the teacher to write a report

### B4 — `analytics` (minimal)
- `get_student_dashboard(student)`: upcoming sessions, last report, current streak, attendance
- `get_teacher_dashboard(teacher)`: today's sessions, weekly calendar, unreported sessions
- `get_parent_dashboard(parent)`: per-child next session + last report
- **Reads only via other modules' public APIs**
- Clean dashboard UIs in React for each role

**Exit criteria:**
- A real Stripe test payment flows end-to-end (test mode)
- A student books a real session in a teacher's slot
- A real Zoom meeting is created and joinable
- Teacher completes the session and writes a report with typed content
- Student and parent see the report
- Entitlement enforcement blocks unpaid users from booking
- Timezone test: teacher in Cairo, student in London — session displays correctly to both
- Architecture docs for `billing`, `scheduling`, `assessment`, `analytics` all written
- `import-linter` passes
- All modules at 100% coverage (line + branch), e2e green for user-facing flows (ADR-0021)
- No direct cross-module model imports

**Size:** ~25–35 specs.

**At end of Phase B, you could launch.** You won't (per the user's Phase D/E commitments), but you could — that is the test.

### Phase B → Phase C transition: preview mode

Before opening any Phase C spec, **preview mode runs for 2–4 weeks**. This is a non-optional gate, not a nice-to-have:

- Invite **3–5 prospective parents + 1–2 prospective teachers** to use the staging environment free of charge
- Staging Stripe in test mode; real Zoom meetings; real session flow
- Collect structured feedback: what did they expect that wasn't there? what confused them? what would make them pay?
- Write a "preview review" ADR summarizing findings and any Phase C re-ordering it implies

Phase C's spec order is **provisional until preview review is done**. If preview users say "curriculum builder isn't what matters, reminders are", Phase C is re-ordered to put C3 before C2. This is not scope creep — it is scope correction, which R5 explicitly calls for. The roadmap expects this.

**Preview mode cost:** ~0 dollars and ~10 hours of your time for the feedback sessions. The single highest-ROI activity in the entire rebuild.

## Phase C — Depth

**Goal:** teachers deliver structured lessons with materials; students get reminders; trial flow works.

### C1 — `content`
- `Resource`, `ResourceCategory`, upload + metadata
- `ResourceAssignment`: teacher assigns to student
- Student "my resources" list
- Profile photo upload moves here from `identity`

### C2 — `curriculum`
- `Course`, `Unit`, `Lesson`, `LessonAssignment`, `LessonCompletion`
- Teacher builds a course: units, lessons, attach resources from `content`
- Teacher assigns lessons to students
- Student views assigned lessons, marks complete
- Teacher sees completion state per student

### C3 — `notifications`
- `NotificationPreference`, `NotificationLog`, `EmailTemplate`, `ReminderSchedule`
- Transactional emails for: registration, email verification, password reset, booking confirmation, session reminder (24h + 1h before), cancellation, new report, new resource assigned
- In-app notification feed (stored, bell icon, mark read)
- User preferences page
- Celery beat for reminder scheduling

### C4 — Trial sessions
- `TrialRequest` in scheduling
- Public page: "try a free session" → captures availability preferences
- Admin/teacher approves → trial session created → email sent
- Billing entitlement has a "trial" capability; trial does not require a subscription

**Exit criteria:**
- A teacher builds a 3-unit course with 10 lessons referencing uploaded resources
- Assigning a lesson notifies the student
- Session reminder email arrives 24h before a scheduled session (tested in staging with a session 24h15m out)
- A trial request → approval → trial session → first lesson delivered, without touching prod Stripe
- All new modules have architecture docs, 100% coverage (line + branch) + e2e green, pass import-linter (ADR-0021)

**Size:** ~15–20 specs.

## Phase D — Breadth

**Goal:** the product feels full-featured. Communication, gamification, and teacher earnings all work.

### D1 — `messaging`
- Direct chats (student↔teacher, parent↔teacher)
- Group chats (class group)
- Message history with pagination, read receipts, basic media attachments
- Real-time delivery via Django Channels + WebSockets
- Notifications integration: new message → in-app notification

### D2 — `engagement`
- Points ledger
- Badges (defined via Django admin, auto-awarded)
- Streaks (consecutive weeks with a completed session)
- Levels (computed from points)
- Leaderboards: per-class and optional global
- Invoked by `scheduling`, `assessment`, `curriculum` at appropriate moments via the event bus

### D3 — `billing` teacher payouts
- `TeacherEarning`: each completed session contributes at the teacher's rate
- Payout records (manual bank transfer tracked in DB; Stripe Connect is post-v1)
- Teacher "my earnings" dashboard
- Monthly payout statement PDF

**Exit criteria:**
- Student and teacher have a real conversation with image attachments
- Student earns a badge after completing their 10th session (verified end-to-end)
- A 30-day streak is detected correctly across timezones
- A teacher sees their earnings for completed sessions, exported as PDF
- All new modules have docs + coverage + boundary check

**Size:** ~15–20 specs.

## Phase E — Reach

**Goal:** public marketing site, mobile-ready UI, multi-language, production hardening.

### E1 — Marketing site (Astro submodule)
- Landing, pricing, about, curriculum overview, meet-the-teachers, blog scaffold, legal
- SEO: sitemaps, OG tags, structured data, good Lighthouse scores
- Shared Tailwind theme with dashboard so visual identity is consistent
- Hosted on the apex domain (`kaleem.academy`) with app on `app.kaleem.academy`

### E2 — Multi-language (i18n)
- **Arabic + English only.** French is cut.
- Full RTL support for Arabic (layout, icons, date pickers)
- Language picker, persistent per-user
- Translation workflow: i18next + single JSON file per language per app

### E3 — Mobile (PWA)
- Dashboard becomes a proper PWA: installable, offline shell, service worker
- Native mobile remains v2; PWA covers ~90% of the value

### E4 — Production hardening
- Rate limiting on DRF (django-ratelimit or custom; auth endpoints were rate-limited in Phase A already)
- Redis caching for read-heavy endpoints (dashboards, plan list)
- API versioning introduced here: `/api/v1/`
- Backup automation: nightly DB + media offsite, restore drill documented
- Load test with k6 or locust; document capacity per VPS size
- OWASP Top 10 walkthrough, logged as ADR

**Exit criteria:**
- Marketing site live on `kaleem.academy`, Lighthouse SEO/perf ≥ 90
- App is a working PWA, installable on iOS + Android + desktop
- Arabic UI is fully functional, no LTR leaks
- Rate limiting blocks abusive patterns (tested)
- Backup + restore drill completed and documented
- `/api/v1/` versioned, old paths deprecated
- **kaleem is ready to onboard real paying users**

**Size:** ~10–15 specs.

## Phase sequencing summary

```
Phase 0 ──▶ Phase A ──▶ Phase B ──▶ Phase C ──▶ Phase D ──▶ Phase E
bootstrap   identity    happy path   depth        breadth     reach
~10 specs   ~6 specs    ~30 specs    ~17 specs    ~17 specs   ~12 specs
```

**Total: ~85–100 specs across the full v1 scope.** Use D7 (weekly review) to track completion. If Phase B alone is consuming > 40% of total effort, either scope is creeping or estimates are off — stop and re-plan.

---

# Section 4 — Process & discipline

D1–D11 are principles. This section is how they become daily behavior.

## 4.1 The feature lifecycle (the single rail)

Every feature flows through 7 stages. No skipping.

```
1. spec       → docs/superpowers/specs/YYYY-MM-DD-<name>.md        (D1)
2. plan       → docs/superpowers/plans/YYYY-MM-DD-<name>-plan.md   (D2)
3. tests      → failing tests first                                 (D3)
4. code       → make tests pass + implement                         (D3)
5. review     → self-review against spec + boundary check           (D4, D5)
6. ship       → merge to main, deploy to staging                    (D9)
7. journal    → one-paragraph entry in this week's journal          (D7)
```

Stages 1–2 happen together. Stages 3–4 loop until green. Stage 5 is a checklist. Stage 6 is automated by `just ship`. Stage 7 happens Fridays.

## 4.2 D1–D11 committed (all accepted)

- **D1** Spec-before-code, always
- **D2** Plan-before-code, for anything > 1 day
- **D3** TDD, every repo, at 100% coverage (line + branch) + e2e for user-facing flows (ADR-0021)
- **D4** Automated module boundary enforcement via import-linter
- **D5** CI must be green before merge (no `--no-verify`)
- **D6** One feature branch at a time
- **D7** Weekly self-review ritual (Friday, 30 min)
- **D8** ADRs for any non-trivial decision
- **D9** Definition of Done, no exceptions
- **D10** No refactoring sprees (write to `ISSUES.md`, keep going)
- **D11** No heroes — sustainable pace

## 4.3 Templates (committed once)

### `docs/templates/spec.md`
```
---
name: <short-name>
phase: 0 | A | B | C | D | E
modules: [identity, billing, ...]
status: draft | approved | in-progress | shipped | abandoned
created: YYYY-MM-DD
closed: YYYY-MM-DD | null
---

## Goal
One paragraph: what and why.

## User flow
Step by step, from the user's POV. Include error cases.

## Data model delta
New tables, new fields, new relationships. Include a mini ERD.

## API delta
New endpoints, changed endpoints, removed endpoints. Request/response shape.

## Module boundaries
Which module owns this? What other modules does it call? Any new events?

## Out of scope
What this spec explicitly does NOT do.

## Test plan
Happy path + edge cases + failure cases that must pass.

## Open questions
Must be resolved before stage 3 (tests).
```

### `docs/templates/plan.md`
```
---
spec: <spec-file>
status: draft | approved | in-progress | done
---

## Steps
1. [ ] ...
2. [ ] ...

Each step must be independently testable. Steps should be ≤ 2h each.

## Risks
What might go wrong? Fallback?

## Verification
How will you verify each step and the whole?
```

### `docs/templates/adr.md`
```
---
number: NNNN
title: <decision>
status: proposed | accepted | superseded by ADR-NNNN
date: YYYY-MM-DD
---

## Context
## Decision
## Alternatives considered
## Consequences
```

### `docs/templates/journal-week.md`
```
---
week: YYYY-WW
phase: <current>
---

## Shipped this week
## In progress
## Slipped or blocked
## Decisions made (link ADRs)
## Next week's focus
## Energy check (1-5)
```

## 4.4 Rituals

| Ritual | Cadence | Time | What happens |
| --- | --- | --- | --- |
| Session start | Every coding session | 2 min | Read `STATE.md`, read top of `ISSUES.md`, check current spec stage (automated by hook) |
| Spec kickoff | Per feature | 30–90 min | Write the spec first alone, then refine with Claude |
| Plan-then-code | Per feature | 15–30 min | Write plan from approved spec, then start with failing test |
| Self code review | Per merge | 15 min | Fresh eyes on own diff, walk the checklist |
| Weekly review (D7) | Friday | 30 min | Fill journal template, update `STATE.md`, re-read roadmap, check pace, write ADR if needed |
| Phase review | At each phase exit | 2 hours | Walk exit criteria, write phase retrospective ADR, confirm arch docs are honest |
| Monthly debt sweep | Last Friday | 1 hour | Read `ISSUES.md`, move 1–3 items into next week's specs or accept "won't fix" |
| Backup drill | Every 2 months | 30 min | Restore the DB from backup to a scratch env |

## 4.5 Self code review checklist

Pinned in `docs/developer-guide/self-review.md`, invoked by `/ship`:

```
Correctness
  [ ] Tests cover the happy path
  [ ] Tests cover at least 2 edge cases
  [ ] Tests cover at least 1 failure case
  [ ] Tests pass locally
  [ ] I manually tested the feature in a browser

Discipline
  [ ] Spec is linked and closed
  [ ] Plan is linked and all steps checked
  [ ] No new TODO/FIXME without an ISSUES.md entry
  [ ] No print() / console.log() left in
  [ ] No commented-out code
  [ ] No "while I'm here" refactors (D10)

Boundaries
  [ ] import-linter passes
  [ ] No new cross-module model imports
  [ ] Public API of any touched module is still documented

Docs
  [ ] Module arch doc updated if public API changed
  [ ] ADR written if a decision was made
  [ ] Runbook updated if operational concerns emerged

Sustainability
  [ ] This commit represents ≤ one focused work session
  [ ] I am not coding past midnight (D11)
  [ ] I am not coding to avoid feeling unproductive
```

## 4.6 Definition of Done (D9 in full)

A feature is only done when:

1. Spec committed, `status: shipped`
2. Plan committed, `status: done`, all steps checked
3. All tests passing locally and in CI
4. `import-linter` green
5. 100% coverage gate green (line + branch) + e2e green for primary/key-failure paths (ADR-0021)
6. Self-review checklist walked
7. Manual golden-path test in a browser
8. Two edge cases manually tested
9. Deployed to staging, smoke-tested there
10. Module architecture doc updated if public API changed
11. Journal entry written
12. `STATE.md` updated
13. `ISSUES.md` reviewed for new issues introduced

An agent running `/ship` walks this list interactively.

## 4.7 The "don't do this" list

Copied verbatim into `CLAUDE.md`:

1. Don't use Django multi-table inheritance for roles. Single User + optional profile tables.
2. Don't leave CSRF disabled. Session auth + real CSRF, no exceptions.
3. Don't store role-specific data as JSON blobs on User. Use typed profile tables.
4. Don't put business logic on models. Services live in `services.py`.
5. Don't let any module import another module's models. Public API only.
6. Don't register a ViewSet but forget to wire it in the router.
7. Don't use `OneToOneField` for things that happen over time. Subscriptions, memberships, etc. are always many-over-time.
8. Don't catch bare `Exception` and stringify it as the API error. Use typed exceptions and proper error mapping.
9. Don't leave `print()` in production code. Use structured logging.
10. Don't hardcode URLs in the frontend. Use env vars.
11. Don't commit `.env*` files. Pre-commit blocks them.
12. Don't add a feature without a spec. D1. Always.
13. Don't refactor while implementing. D10. Write to `ISSUES.md` and keep going.
14. Don't code past bedtime. D11.

## 4.8 `ISSUES.md` discipline

Plaintext backlog file in the meta repo root. Three sections:

```
# ISSUES

## Now (next 1-2 weeks)
- <item> — <one line>

## Soon (next month or two)
- <item>

## Someday / Won't fix
- <item>
```

**Rule:** when you spot a problem during other work, write it here in 15 seconds and go back to what you were doing. No "quick fix". The monthly debt sweep is when you deal with it.

---

# Section 5 — Risks & mitigations

Each risk: **likelihood · impact · early warning · mitigation · escalation trigger.**

## R1 — Scope creep inside an already-big scope 🔴
Likelihood: very high · Impact: catastrophic

- **Warning sign:** in Phase B writing an unplanned spec ("I know this isn't in v1, but…") or a spec growing a new "stretch goal" section
- **Mitigation:** every spec declares its phase in frontmatter. Specs that don't map to an existing phase go to `ISSUES.md` first, then only after monthly debt sweep do they become specs. `/new-feature` enforces this.
- **Escalation trigger:** 2+ unplanned specs in a month → unscheduled phase review; re-plan explicitly or delete

## R2 — Solo burnout 🔴
Likelihood: high · Impact: project death

- **Warning sign:** 2 weeks energy ≤ 2/5, or 2 weeks without a commit, or hero sessions followed by silent days
- **Mitigation:** D11. The roadmap does not move during breaks — nothing blocks, nothing dies.
- **Escalation trigger:** 2 weeks energy ≤ 2 → stop feature work; use the week to journal and write an ADR about what's draining you

## R3 — Perfectionism trap
Likelihood: high · Impact: silent month-long delays

- **Warning sign:** spec > 2× estimated size, 3+ commits revising the same file, ADR superseding a same-phase ADR
- **Mitigation:** "good enough, ship, ADR-supersede later"
- **Escalation trigger:** a spec sitting in stage 4 > 2× planned duration → stop, ask "what would ship this today?", push cleanup to `ISSUES.md`

## R4 — Skipping discipline when tired
Likelihood: high · Impact: slow return of the original mess

- **Warning sign:** commit touches feature code without a linked spec; `TODO: add tests` merged; arch doc not updated after public API change
- **Mitigation:** **mechanical enforcement** via hooks and pre-commit. Discipline lives in tooling, not willpower.
- **Escalation trigger:** disabling a hook or using `--no-verify` → revert, write an ADR before changing the rule

## R5 — Market drift: building the wrong thing for 18 months
Likelihood: medium · Impact: high

- **Warning sign:** deep in Phase C with no prospective user touched kaleem since Phase B
- **Mitigation:** **Phase B ends with preview mode** — invite 3–5 real parents + 1–2 teachers to use staging free for a month. Collect feedback *before* starting Phase C. Phase C's priorities are informed by preview feedback, not the original roadmap.
- **Escalation trigger:** preview user says a Phase C/D feature "isn't what I'd use" → re-plan that phase

## R6 — Foundation trap: infinite Phase 0
Likelihood: medium-high · Impact: delays Phase A indefinitely

- **Warning sign:** Phase 0 running > ~3 weeks of elapsed solo time
- **Mitigation:** hard **8–12 spec cap** on Phase 0. Tool choices that are close → pick the one with better docs and move on.
- **Escalation trigger:** week 4 of Phase 0 with no Phase A started → force a Phase 0 exit review

## R7 — Dependency rot over 18+ months
Likelihood: high · Impact: medium

- **Warning sign:** failing `pnpm install` or `uv sync` on clean checkout, or deprecation warnings in CI
- **Mitigation:** Dependabot on meta repo + all 4 submodules, weekly auto-PRs. D7 ritual merges the week's batch. Patch auto-merge on green CI; minor/major get a 10-minute review.
- **Escalation trigger:** > 20 open Dependabot PRs → pause feature work for one day to clear

## R8 — Third-party integration breakage
Likelihood: medium · Impact: medium

- **Warning sign:** webhook test failing after a routine dependency update
- **Mitigation:** every external integration behind an internal adapter (`scheduling/integrations/zoom.py`, `billing/integrations/stripe.py`). Integration tests use recorded fixtures (`vcrpy`). Monitor external status pages via Uptime Kuma.
- **Escalation trigger:** any flaking Stripe/Zoom test → treat as a real bug

## R9 — Knowledge bus factor = 1
Likelihood: always · Impact: project death if you step away

- **Warning sign:** re-reading your own code and not understanding why it exists
- **Mitigation:** ADRs, specs, architecture docs, journal — not for "other developers" but for future-you. Agents can read all these in seconds and remind you of context you forgot.
- **Escalation trigger:** re-reading own code to figure out what it does → write a doc about it before continuing

## R10 — Security incident before launch
Likelihood: low pre-launch · Impact: very high post-launch

- **Warning sign:** unexpected 5xx on auth/billing in Sentry; gitleaks firing; dependency CVE
- **Mitigation:** security baseline in Phase 0. OWASP Top 10 walkthrough at Phase 0 exit and Phase B exit. `gitleaks` in pre-commit. Secrets in env only. `django-axes` for brute-force protection. Auth endpoint rate limiting in **Phase A** (not E). Threat model doc in Phase A.
- **Escalation trigger:** any high-severity CVE in a dependency → drop everything, patch, deploy

## R11 — Infrastructure mistakes (self-hosted tax)
Likelihood: medium · Impact: medium-high

- **Warning sign:** VPS disk > 80%, cert < 14d from expiry, untested backup
- **Mitigation:** Uptime Kuma for aliveness. Grafana alerts on disk/CPU/memory. Let's Encrypt auto-renewal. Postgres major version pinned and upgraded via ADR. Daily backups, offsite copy. **Restore drill every 2 months** (every 2 weeks once paying users exist).
- **Escalation trigger:** any infra alert firing twice in a week → ADR about root cause

## R12 — Competitors shipping faster
Likelihood: medium · Impact: medium

- **Warning sign:** prospective user mentions a new "Quran teaching platform"
- **Mitigation:** R5 (preview at end of Phase B) protects against this. Real users with a working product at month ~8 beats an imaginary perfect product at month 24.
- **Escalation trigger:** keep shipping

## 5.1 Risk-monitoring ritual

At every weekly review (D7), self-check R1–R5 honestly:

```
Weekly risk check:
- R1 (scope creep): any unplanned specs this week? [ ]
- R2 (burnout): energy ≥ 3/5 this week? [ ]
- R3 (perfectionism): any spec > 2× planned size? [ ]
- R4 (discipline): all specs have tests before merge? [ ]
- R5 (market drift): when did I last talk to a real user? [ ]
```

One unchecked and not fixable this week → logged in the journal as "watching". Two weeks unchecked → escalation trigger, do the mitigation.

---

# Section 6 — Escape hatches & decision triggers

The roadmap is a plan, not a contract. Changes must be possible without feeling like failure. What makes change healthy is having triggers defined *before* they are needed.

## 6.1 Pre-approved decision triggers

### T1 — Phase exit
**Always.** Walk exit criteria, write a phase retrospective ADR, confirm architecture docs, decide to proceed or re-plan. The single most important trigger.

### T2 — Phase running 2× longer than estimated
Stop. Is the scope wrong? Is a module fighting back? Are you skipping the process? Re-plan, then continue.

### T3 — First real user feedback (end of Phase B preview mode)
Phase C priorities are provisional until preview feedback arrives. Formal preview review 2–4 weeks after preview mode opens. Re-order Phase C accordingly.

### T4 — A module fights back
2 specs into a module and it feels wrong → stop and re-examine the module definition. Fix the definition, ADR it, continue.

### T5 — Energy crash (2 consecutive weeks ≤ 2/5)
Triggers a life review, not just a project review. D11 says pause. Take a week off from feature work. During that week re-read roadmap + journal, write an ADR about what is draining you.

### T6 — A core tech decision turns out wrong
Write an ADR, pick an escape hatch, schedule the switch explicitly. Never secret-migrate.

### T7 — Life event
New job, illness, family, relocation, financial pressure → emergency re-plan. What is the smallest version of kaleem still valuable given new constraints? Re-enter brainstorming with this spec as input. Do not soldier on silently.

### T8 — Financial pressure
**The one case where you forcibly cut scope.** Declare "Phase B-public": shippable subset with payment, scheduling, reports only. Charge for it. Use revenue to fund the rest. This is essentially admitting the original "happy path v1" recommendation was right; ADR it and move on, no ego.

### T9 — Competitor launches something very similar
Usually the answer is "keep shipping". Sometimes "differentiate harder on one vector" — marketing decision, not roadmap decision. ADR; don't change code because of external noise.

## 6.2 Escape hatches (pre-approved alternate paths)

### E1 — git submodules → pnpm workspace monorepo
**Trigger:** submodule friction costing > 1h/week.
**Hatch:** merge all 4 submodules into a single repo with pnpm workspaces (pnpm can orchestrate `just` across folders even for Python).
**Pre-approved.** One focused day, ADR, move on.

### E2 — self-hosted VPS → managed platform (Railway/Fly.io/Render)
**Trigger:** > 5h ops in a week, or second prod incident from infra, or losing sleep over it.
**Hatch:** backend + Postgres + Redis to Railway or Fly. `infra/` submodule becomes managed-platform config.
**Partially pre-approved.** Cost estimate first — managed platforms can 3–5× hosting bill. OK if ops savings > cost delta.

### E3 — session + CSRF → JWT
**Trigger:** real native mobile app work begins and sessions don't work well with native clients.
**Hatch:** introduce JWT alongside sessions for mobile specifically. Web stays on sessions.
**Pre-approved** when real mobile work starts, not speculatively.

### E4 — big v1 → phased public launch
**Trigger:** any **two** of R1, R2, T2, T8 firing together.
**Hatch:** ship Phase A+B publicly, start charging, build Phases C–E post-launch.
**Pre-approved.** If two triggers fire together, reach for this without re-debating.

### E5 — modular monolith → service split for one module
**Trigger:** one module's deploy/test cycle slowing the whole monolith, or wildly different scaling needs (e.g., messaging at real-time scale).
**Hatch:** extract one module to a separate service via HTTP/gRPC. The modular monolith was designed for this.
**Not pre-approved.** Significant complexity jump. Requires a full ADR with evidence.

### E6 — allauth → custom auth
**Trigger:** allauth customization costing > 2 days in a single spec or forcing architecture compromises.
**Hatch:** replace allauth behind the identity module's public API. Rest of the app unaffected.
**Not pre-approved.** Almost always wrong. If this trigger fires, re-read ADR-0004 first.

### E7 — Django → another framework
**Trigger:** none anticipated.
**Hatch:** none. The problem is somewhere else. Write an ADR about what you *think* is wrong, sleep on it, re-brainstorm only if still convinced in a week.
**Explicitly discouraged.**

## 6.3 The "re-brainstorm" trigger

Drop this spec entirely and start over when:

- 3+ triggers from T1–T9 fire in the same phase, OR
- A preview user review (T3) invalidates the core premise, OR
- 3+ months of effectively no progress (commits, not feelings)

When it happens, enter a new brainstorming session, load this spec, use it as **input** not gospel. The new brainstorm produces a new spec, which supersedes this one via ADR. The old spec stays with `status: superseded`.

## 6.4 Meta-rule: changes to the plan get ADRs

Any change — re-scoped phase, re-ordered modules, cut feature, added feature, new escape hatch taken, module definition changed — gets an ADR. The ADR cites the trigger, names the change, predicts consequences. **Silent drift is forbidden; explicit change is encouraged.**

---

# Appendix A — The "big v1" scope disagreement

During brainstorming Q4, the user was presented with a "happy path v1" recommendation: ship the smallest workflow that a customer will pay for (auth → subscribe → book → session → report) and phase everything else as v1.1, v1.2, v2.

The user rejected this and chose **the full ~20-feature v1** (chat, curriculum, gamification, multi-language, dashboards, trials, group sessions, reports, resources, notifications, payouts, mobile/PWA, admin, curriculum builder, plus "other features they don't remember now").

**This is documented here, verbatim, at the user's request and per the brainstorming agreement, so that future-you reading this document in month 14 can see:**

1. The big-v1 choice was made consciously, knowing the cost estimate (18–24 months solo)
2. The recommendation was to ship a minimal v1 first and phase the rest
3. The reasoning for the big-v1 choice is not recorded here because the user did not elaborate; this is acceptable — sometimes a founder wants what a founder wants
4. **If at month 14 this choice turns out to be wrong, the escape hatch is E4 (phased public launch), which is pre-approved**

The "happy path" recommendation is not lost — it is preserved as Phase B's exit gate (end of Phase B = the happy path is complete and working) and as E4's fallback scope. The disagreement is the reason Section 5's risks weight R1 (scope creep) and R2 (burnout) as "top risks" rather than normal risks.

**This appendix is not a complaint. It is insurance.**

---

# Appendix B — Next steps after this spec is approved

1. **Spec self-review** (this document)
2. **User reviews this spec** and either approves or requests changes
3. **Commit this spec and `CLAUDE.md`** to the current repo (the future meta repo)
4. **Hand off to the `writing-plans` skill** to produce the first implementation plan — which will be Phase 0 (Bootstrap), specifically the spec for initializing the meta repo, submodules, CI, and the agent-friendly setup
5. **Execute Phase 0** following the plan

From there the feature lifecycle in Section 4.1 takes over: every subsequent feature goes spec → plan → tests → code → review → ship → journal, without exception.

---

---

# Appendix C — v2 custom WebRTC video service

During brainstorming, the user expressed a strong commitment to replacing Zoom with a **full custom P2P/SFU video service** built from scratch. After discussing the complexity (6–12 months of specialized work: STUN/TURN, signaling, NAT traversal, SFU for group calls, Safari quirks, reconnection, bandwidth adaptation, recording), the decision was:

- **v1:** use Zoom via an adapter in the `scheduling` module. The adapter exposes a stable interface: `create_room(session)`, `get_join_url(session, user)`, `end_room(session)`.
- **v2:** replace the Zoom adapter with a custom implementation. This is a **must-have for v2**, not a "nice to have".

### What v2 video requires (scoped here for future planning)

A new `video` module (or a major expansion of `scheduling/integrations/`) that owns:

- **STUN/TURN server** (coturn, self-hosted on a dedicated VPS or the same infra)
- **Signaling server** (WebSocket-based, handles SDP offer/answer exchange, ICE candidate relay)
- **SFU** (Selective Forwarding Unit) for group sessions — pure P2P collapses past ~4 participants. Options: build on top of mediasoup, Janus, or Pion (Go-based). Or LiveKit as an intermediate step.
- **Client-side WebRTC** (React components: video grid, screen share, mute/unmute, camera toggle, connection quality indicator)
- **Bandwidth adaptation / simulcast** (multiple quality layers, dynamic switching)
- **Reconnection logic** (network change detection, ICE restart)
- **Recording** (server-side media capture if session recording is a requirement)
- **Browser compatibility layer** (Safari, Firefox, Chrome all have WebRTC differences)
- **Mobile browser testing** (especially iOS Safari)

### Why the adapter pattern matters

The `scheduling` module's video adapter is designed so that swapping Zoom for custom WebRTC is a **single-module change**:

1. Implement the new adapter in `scheduling/integrations/video_custom.py`
2. Both adapters conform to the same interface (`create_room`, `get_join_url`, `end_room`)
3. A settings flag or env var selects which adapter is active
4. No other module's code changes
5. Both adapters can coexist during migration (Zoom as fallback)

### Estimated scope

15–25 specs, 6–12 months of focused work. This is deliberately **not in v1** because it would more than double the rebuild timeline. It becomes the first major v2 initiative after v1 launches and has paying users.

### Decision record

This decision will be formalized as **ADR-0011** (Zoom for v1, custom WebRTC for v2) during Phase 0.

---

*End of roadmap spec.*
