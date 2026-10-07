# Phase B5 — Communication — Design

**Date:** 2026-10-07
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings applied 2026-10-07.
**Phase:** B5 of `2026-09-24-parity-roadmap-design.md` §2. It covers:
- WhatsApp: numbers, groups, and routing per teacher and per course;
- 11+ editable bilingual notification templates, with per-session reminder times;
- a manual broadcast composer;
- per-user notification preferences;
- internal chat and chat groups.

These are COMM-001…010. B5 depends on B0 notifications (Plan 8, merged) and on B2 (phase spec recorded).
**Works under:** `2026-10-02-parallel-orchestration-design.md` (ledger, slices, merge queue, ownership).
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` (cited `P1 §x` / IDs) and
`docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` (cited `TH §x`). R7 is dropped (ledger D1): anything the audits
do not show is marked `[assumed]`.

This document has two parts:
- §1–§4 are the phase spec: the split into slices, and the decisions that hold across them.
- §5–§11 are the first slice's spec: **B5a — templates & preferences**.

Later slices get their own spec files, designed against this one.

## 1. Goal

Widen Plan 8's notifications into TutorHamster's communication layer:
- each academy edits the text of its automatic notices in Arabic and English;
- people choose which kinds of notice they receive;
- the office writes messages to any audience;
- WhatsApp joins email and the in-app bell as a channel;
- the automatic notices cover TutorHamster's full list, plus what B2 and B6 left to B5;
- people talk to each other in an internal chat.

Every feature is a per-academy switch, off by default (PO-5), so each slice merges on its own.

## 2. Phase decisions

| # | Decision | Source |
|---|---|---|
| B5-1 | **`etqan.notifications` stays the one place that decides who is told what** (N8-1). B5 owns it. Templates, preferences, broadcasts and the WhatsApp channel are added to it. **Internal chat is a new tenant app, `etqan.chat`** (B5e, B5f), added to `TENANT_APPS` under the `── phase B5 ──` marker. No other app imports `etqan.notifications`. | spec 2026-09-26 N8-1; orchestration §4.3 |
| B5-2 | **Notices stay pull-based** (N8-2). Every new automatic notice is a finder over another app's read service, run by the every-minute scan. Domain apps never call into notifications; chat notices too are a finder over a `chat.services` read service (B5f). Read services B5d needs are already published (ledger D29 `homework_events`), or will be asked for by B5d's spec as requests to their owners (B2 for postponement, substitute and schedule-change events; B6 for level-upgrade decisions). | spec 2026-09-26 N8-2; spec 2026-10-05-b6 B6-6; ledger D29 |
| B5-3 | B5 is five slices (§3), each behind its own switches, all **off by default**. B5e flips the registry's `_later` line `internal_chat` in place. Every other switch is new, under the `── phase B5 ──` marker. The existing `auto_notifications` switch keeps its meaning: whether the scan runs at all. | PO-5; spec 2026-09-30 FT-2; TH SYS-002 |
| B5-4 | **Notice text has two languages, Arabic and English.** An academy's templates have an `ar` and an `en` text. A reader whose language is Spanish gets the academy's default language (ledger D22), never a Spanish template. | TH §2.7 COMM-004; ledger D11, D22 |
| B5-5 | **WhatsApp goes through the official WhatsApp Cloud API (Meta), with no group posting** (owner, ledger D40, answering E3). **B5c is on hold** until the owner's integrations design is approved (D41). Its provider is then reached only through `etqan.integrations.resolve(service)`: an Etqan default account, or the academy's own. B5 stores no keys of its own (D42). Until then no WhatsApp channel is offered anywhere: it is not shown in composers and not accepted by APIs. TH's group routing (global groups, per-teacher group, per-schedule course group) is **not built**, because the Cloud API cannot post to groups (D40). | ledger D40, D41, D42; orchestration §8.1 |
| B5-6 | **Guard on messaging:** sending a broadcast (B5b) and starting a conversation, sending or deleting a chat message (B5e) add `NotImpersonating`. | ledger D19 |
| B5-7 | **Archived rows still notify:** no finder filters on `archived_at`. | ledger D14 |
| B5-8 | **Group classes** are one session per roster student (D6), and each student row is notified on its own, as today. A teacher with a group gets one notice per row [assumed]. | ledger D6 |
| B5-9 | **Per-user preferences govern automatic notices and chat notices; manual broadcasts ignore them.** A broadcast is the office writing to someone directly. | TH §2.7 COMM-003, COMM-006 · [assumed] |
| B5-10 | No B5 migration drops or rewrites data in an existing table. New columns and tables go only in B5's own apps (`etqan.notifications`, `etqan.chat`). Per-person settings that TH shows on identity's profiles live in B5-owned tables keyed by user id, not as identity fields: the per-student chat switches (B5e). | orchestration §8.2, §4.3 |
| B5-11 | Dashboard code stays in `src/features/notifications/` (B5a–B5d) and a new `src/features/chat/` (B5e). New translation areas are new files `locales/{en,ar}/<area>.json`. | orchestration §6.1; ledger D11 |
| B5-12 | **COMM-007's per-session reminder timestamps are already covered and are not built as fields.** TH stamps nine reminder datetimes on each session. Our equivalent is the per-type offset (Plan 8's settings, editable) plus the `Notification` row itself: its `dedupe_key` names the session and type, and its `created_at` is the stamp. B5d adds its new session types the same way. No per-session field or override is added. | spec 2026-09-26 N8-2, N8-5; TH §2.4 SCHED-003 notification fields · [assumed] per-session override not needed |
| B5-13 | **Who may mute what:** a duty notice to staff cannot be muted by its recipient. Each `Kind` names the roles it reaches and the roles for which it is a duty. Duties are `report.missing` to a teacher and `session.late` to a teacher. A role sees only the categories that have a non-duty type reaching it. Admins and staff have no preferences in B5: office alerts are their job. | [assumed]; review |

## 3. Slices

| Slice | Topic | Contents | Audit IDs | Switches (off by default) | Requires | Size |
|---|---|---|---|---|---|---|
| **B5a** | templates & preferences | Per notice: title and body editable per academy in ar and en, with a placeholder list, validation, a preview and reset to default. Per student, parent and teacher: notice preferences by category (sessions, payments, schedule updates, reports & homework), set by the person on their account page or by the office on the person's page. The scan honours both. | COMM-004, COMM-006, FLOW-013 | `notification_templates`, `notification_preferences` | — | M |
| **B5b** | broadcasts & log | The office composes a message to one of TH's ten audiences: admins · several teachers · several students · one student · one teacher · one parent · all students · all teachers · all parents · a **study group** (B2f). Channel: email (WhatsApp joins with B5c); the in-app item is always made. A list of sent broadcasts with per-recipient email status and read flag (read-only, BR-42), plus delete. A read-only **notification log** of every notice (automatic and broadcast) with recipient, email status and read flag, filtered by type and status. | COMM-003, BR-42 | `broadcasts` | B5a; B2f (the study-group audience task only) | M |
| **B5c** | WhatsApp (**on hold**, D41) | WhatsApp as a channel of automatic notices (on/off per notice type) and of broadcasts, sent through `integrations.resolve("whatsapp")` (D42) to recipients' numbers (`User.phone`; parents only with `has_whatsapp`). The admin's own WhatsApp number receives office notices. No group routing (D40). Its spec is written once the integrations design is approved. | COMM-009, INT-007 (number part) | `whatsapp` | integrations slice (D41, D42) | S–M |
| **B5d** | more automatic notices | TH's missing templates (mapping below), plus the notices B2 and B6 left to B5: postponement and schedule updates (student / teacher), trial sessions, compensation sessions, substitute teacher, homework set / answered / completed (D29), and a level upgrade being decided. Each is a finder over the owning app's read service (B5-2). New types join the settings list (on/off + number) and a preference category. | COMM-004 | none new | B2e, B2g, B6b (each task needs only the slice it reads) | M–L |
| **B5e** | chat core | New app `etqan.chat`: one-to-one conversations (who may start with whom by role and teaching link) and office-managed chat groups (name, participants); plain-text messages, sender's soft delete, read state and read counts; polling (no websockets [assumed]); per-student "chat enabled" and "can start conversations" switches (B5-10); unread badge via D27. Spec `2026-10-07-b5e-chat-design.md`. | COMM-001 (participants' side), COMM-002, BR-43, P1 §5.4 (parents not in chat) | `internal_chat` (flipped) | — | M–L |
| **B5f** | chat extras | Attachments (private storage, D12) and group images; the office's message moderation list (view, edit, delete and bulk delete any message; filter by sender / receiver type per B5e E-13 and by dates, COMM-001); the groups' created-date filter (COMM-002); chat notices as a notifications finder over a `chat.services` read service, under the `chat` preference (B5-2) | COMM-001 (office side) | none new | B5e | M |

Already built and unchanged: COMM-008 (the in-app stream, Plan 8 N8-4); COMM-010 (each template's on/off
switch is Plan 8's per-type setting, N8-5; B5a only shows it); COMM-007 (B5-12).

**TH's eleven templates** (TH §2.7 COMM-004) against our types:

| TH template | Ours |
|---|---|
| Session reminder (student) | `session.reminder` (Plan 8) |
| Early reminder (student), 2 h | `session.early_reminder` (Plan 8) |
| Lateness reminder (student), +5 min | `session.late` (Plan 8; to teacher and family) |
| Absence notice (student) | `session.student_absent` (Plan 8) |
| Teacher-absent apology (to the student) | new in B5d |
| Subscription renewal ("when the subscription ends") | `subscription.expired` (Plan 8) |
| Subscription nearing expiry | `subscription.low` (Plan 8, a session threshold) [assumed same intent] |
| Teacher session reminder, 30 min | `session.teacher_reminder` (Plan 8) |
| Teacher early reminder, 2 h | new in B5d |
| Teacher "session started 5 min ago" | `session.late` already tells the teacher when no attendance is marked [assumed sufficient]; not added |
| Teacher "session ended 5 min ago" | new in B5d (a nudge to mark attendance and write the report) |

Order (amended for D41 and the B5e/B5f split): B5a, B5b, B5d, B5e, B5f, then B5c once the integrations design is approved. B5a and B5b
need nothing unmerged apart from B5b's one study-group task. They change how every later notice is rendered and
delivered, so they go first. B5d waits for its source slices. B5e is independent and the largest.

Not taken by any B5 slice, with the reason:

- **SMS and phone OTP:** B9 (roadmap §3).
- **Push notifications to mobile apps:** B11.
- **"Subscription offers" notices** (TH's academy-level preference switch): TH shows no offer object and the
  behaviour is UNKNOWN; not built.
- **The request centre's notices** (LEAD-003): the subsystem is unreachable on TH (P1 §18.1); not built.
- **The monthly teacher evaluation notice** (SYS-004 action): behaviour UNKNOWN (TH V27); not built.
- **Certificate notices:** COMM-004 lists none (ledger D33).
- **WhatsApp group routing** (COMM-005 groups, per-teacher custom group, per-schedule course group): the Cloud
  API cannot post to groups (D40).
- **Registration notices in the bell:** B9c sends registration emails itself (R-8a); not added.

Each slice spec details its own data, rules, API, screens, seeds and tests; this table is the contract between
them. A slice may move an item to a later slice only by amending this table.

## 4. Shared lists, ownership and requests

- **Marker lines.** B5 adds lines only under its `── phase B5 ──` markers:
  - `TENANT_APPS` (`etqan.chat`, B5e);
  - the feature registry (B5e also flips `internal_chat` in place);
  - the access `RESOURCES`;
  - `config/api_router.py` (`chat/`, B5e; notifications' own `notifications/` route already exists);
  - seeds (`etqan/tenants/seeds/b5.py`, called under the marker in `seed_dev`);
  - `pyproject.toml` (the platform contract's forbidden list for `etqan.chat`, and a `etqan.chat` contract);
  - the dashboard's `NAV_ITEMS`.
- **Lines outside the markers that B5 owns:**
  - the "no app imports notifications" contract gains `ignore_imports` entry
    `etqan.tenants.seeds.b5 -> etqan.notifications.services` (B5a);
  - the "notifications reaches other apps only through their services" contract gains `etqan.learning.models`
    and `etqan.learning.api` (B5d) and `etqan.chat.models` and `etqan.chat.api` (B5e) in its forbidden list.
- **Dashboard.** The `FeatureCode` union in `dashboard/src/features/identity/schemas.ts` gains each new switch.
- **One-line mounts** in pages B5 does not own (the account page, the people detail pages, B2g's schedule page)
  are additive and named in each slice spec.
- **e2e.** New e2e specs are `e2e/b5-*.spec.ts`. They turn switches on with `manage("set_features", …)`, as
  existing specs do.

---

# Slice B5a — Templates & preferences

## 5. B5a decisions

| # | Decision | Source |
|---|---|---|
| T-1 | **Every automatic notice type has an editable title and body in ar and en.** For each (type, language) an academy's text is either its own override or the built-in default (`text.TEMPLATES`). Saving stores an override; "reset to default" deletes it. Title and body are overridden together. | TH §2.7 COMM-004; P1 COMM-004 |
| T-2 | **Placeholders.** A template names facts as `{name}`. The allowed set depends on the type's `Kind.target`, plus its type:<br>• target `session` (the five `session.*` types and `report.missing`): `student`, `course`, `time`;<br>• target `subscription`: `student`, `course`, plus `sessions` for `subscription.low` only;<br>• target `invoice`: `student`, `number`, `amount`, `due_on`.<br>A literal brace is written `{{` / `}}`. The following are each a 400 with code `notifications.bad_placeholder` on the field (`title` or `body`):<br>• an unknown name;<br>• a positional `{}`;<br>• an attribute or index (`{student.x}`);<br>• a conversion (`!r`);<br>• a format spec (`:>5`);<br>• an unbalanced brace.<br>A template need not use every placeholder. `text.render` fills every key for every type, so the per-type restriction is the checker's alone. | [assumed] syntax (the built-ins already use `str.format` names); ledger D25 codes |
| T-3 | Title is 1–150 characters and body 1–1000; both are required after trimming (400 `title` / `body`). The rendered title is still cut at 200 (the column). | [assumed] |
| T-4 | **The on/off switch and the number stay where they are** (Plan 8's settings, = TH's "initial status", COMM-010). The templates screen shows each type's switch read-only. It links to the settings form (`/settings/academy`) only for a viewer holding `academy_settings.view`. | TH §2.7 COMM-004; spec 2026-09-26 N8-5; review |
| T-5 | **Preview:** the office can render a draft (type, language, title, body) against fixed sample facts (§8.2) before saving. Preview validates exactly as saving does. | [assumed] |
| T-6 | Templates are under the switch **`notification_templates`** (new, group `communication`, requires nothing). While it is off:<br>• the scan renders built-in text;<br>• the templates API is 404 (`FeatureOn` after the role check);<br>• saved overrides are kept, and apply again when it is turned on.<br>A notice already created never changes (N8-4). | B5-3; spec 2026-09-30 FT-4 |
| T-7 | Templates use the existing access resource **`notification_settings`**: `view` reads and previews, `update` saves and resets. No new resource. | TH puts templates and switches on the same system-settings tabs · [assumed] same codes |
| T-8 | **Preference categories** are TH's five notice toggles on the student form; its two chat toggles are B5e's. They are `sessions`, `payments`, `schedule`, `reports_homework` and `chat`. Every notice type belongs to exactly one category (§8.3). Later slices add their types. | TH §2.1 PEOPLE-001 Preferences; P1 COMM-006 |
| T-9 | **Students, parents and teachers have preferences** (B5-13); admins and staff have none in B5. All categories default **on**. Each role sees only the categories that have a non-duty type reaching it. In B5a that is:<br>• students: `sessions`, `payments` (as payer or family);<br>• parents: `sessions` (guardian reminders, absence), `payments`;<br>• teachers: `sessions` (`session.teacher_reminder`; `session.late` is a duty).<br>`reports_homework`, `schedule` and `chat` are shown once a later slice gives them a type for that role. | P1 COMM-006 (toggles on the student form; "notification toggles" on teacher records) · [assumed] parents; B5-13 |
| T-10 | **An opted-out category means no notice at all** for that person on that occurrence: the scan creates no row, so no bell item and no email. This is FLOW-013's "respect the recipient's toggles" before rendering. Other recipients of the same occurrence are unaffected, and duty notices (B5-13) are never dropped. Turning a category back on does not replay what was skipped, beyond what the finders still find: reminders for upcoming sessions, and events still inside the 24-hour look-back. | P1 FLOW-013 · [assumed] look-back replay accepted |
| T-11 | **Who sets them.** A signed-in student, parent or teacher sets their own on their account page. The office sets a student's, teacher's or parent's on that person's page, with the person's resource codes (`student.view` / `update`, `teacher.…`, `parent.…`); admins always pass. The office card shows only for a person who can be notified: a student without an email address is never notified (`recipients.eligible`), so their card says so instead of showing switches. A parent's card also needs the `parents` feature (guardians are told only while it is on). | TH §2.1 (toggles on the office's student form) · [assumed] self-service |
| T-12 | Preferences are under the switch **`notification_preferences`** (new, group `communication`, requires nothing). While it is off, the scan ignores opt-outs and the preferences API is 404. Stored choices are kept. | B5-3; FT-4 |
| T-13 | **Manual broadcasts (B5b) ignore preferences** (B5-9). | B5-9 |

## 6. B5a screens (dashboard)

| Who | Where | What |
|---|---|---|
| Office | **Settings → Notification templates**: new route file `routes/_authed/settings.notification-templates.tsx`, path `/settings/notification-templates`. Nav: group `settings`, needs `notification_settings.view` and `notification_templates`. | Notice types grouped as in the settings form (sessions · subscriptions · invoices · reports). Each row shows: the name, the on/off state (read-only), and a "customised" badge per language.<br>A row opens an **edit dialog** with:<br>• language tabs ar / en;<br>• title and body fields;<br>• the type's placeholders as chips that insert at the cursor;<br>• a **Preview** button that renders title and body with sample facts;<br>• Save (`notification_settings.update`);<br>• **Reset to default** (with a confirm), shown when that language is customised.<br>400s land on their fields. Without `update`, the dialog is read-only. |
| Student, parent, teacher | **Account → Notification preferences** card on `/account` (`notification_preferences`). | One switch per category shown for the role (T-9), each with a one-line description. A change saves on toggle (optimistic; reverted with a toast on error). Admins and staff see no card. |
| Office | **People → student / teacher / parent detail**: the same card, mounted with one line in each of `people.students.$personId.tsx`, `people.teachers.$personId.tsx` and `people.parents.$personId.tsx`. Needs `<role>.view` to see and `<role>.update` to change, plus `notification_preferences`; the parent card also needs `parents`. | The person's switches, read-only without `update`. A student with no email address gets a note instead of switches (T-11). |

## 7. B5a data

```text
etqan.notifications.NotificationTemplate
  type        CharField(32, choices = notice types)
  language    CharField(2, choices ar | en)
  title       CharField(150)
  body        TextField   (≤ 1000, checked by the service)
  updated_at  auto_now
  unique (type, language)

etqan.notifications.NotificationOptOut
  user        FK User  CASCADE  related_name="+"
  category    CharField(24, choices sessions | payments | schedule | reports_homework | chat)
  created_at
  unique (user, category)
```

A row in `NotificationOptOut` means "off", and no row means on. So every existing user starts with everything
on, and no backfill is needed. One migration in `etqan.notifications`, with new tables only.

## 8. B5a behaviour

### 8.1 Rendering with overrides

`text.render(type_, facts, *, language, timezone, template=None)` gains an optional `(title, body)` override
(additive). Values are filled exactly as today, so an override can only name facts the built-in could.

`scan.store(pairs, *, now)` loads every override once per call: one query, made only while
`notification_templates` is on and `pairs` is not empty. It passes the matching override to each row's render.
`add_samples` goes through `store`, so dev samples use the overrides too.

### 8.2 Placeholders and samples

`text.PLACEHOLDERS` maps each type to its allowed names (T-2). A test keeps it equal to what the type's finder
fills.

`text.SAMPLE_FACTS` holds one fixed `Facts` per target kind for previews:
- student "Sara Ahmed" (`Facts.student` is one string, used in both languages);
- course "Qur'an" / "القرآن";
- time 2026-01-15 16:00 UTC, shown in the academy's timezone;
- 3 sessions remaining;
- invoice `INV-0001`, 150000 EGP, due 2026-01-31.

`services.templates.check(type_, title, body)` is the one checker, used by both save and preview. It walks
`string.Formatter().parse` over each text and rejects per T-2 and T-3.

### 8.3 Categories and duties

`kinds.Kind` gains:
- `category`;
- `roles`: the recipient roles the type reaches, matching its finder's audience (student / parent / teacher /
  admin); a test keeps them equal;
- `duty_roles`: the roles for which it cannot be muted.

B5a's map:

| Category | Types |
|---|---|
| `sessions` | `session.early_reminder`, `session.reminder`, `session.teacher_reminder`, `session.late` (duty for teacher), `session.student_absent` |
| `payments` | `subscription.low`, `subscription.expired`, `invoice.issued`, `invoice.overdue` |
| `reports_homework` | `report.missing` (duty for teacher) |

`kinds.CATEGORIES` is the ordered tuple of the five categories. `kinds.categories_for(role)` returns the
categories with at least one type that reaches the role and is not a duty for it.

### 8.4 Honouring preferences in the scan

The filtering lives in `scan()`, so seeding through `add_samples` bypasses it. After
`recipients.resolve(hits)`, while `notification_preferences` is on and there are pairs, the scan:
1. reads the opt-outs of the resolved users once (`user_id, category` for those ids: one query);
2. drops each `(hit, user)` whose type's category the user opted out of, unless the type is a duty for
   `user.role`.

A scan therefore gains at most two fixed queries (this one and §8.1's), whatever the number of hits (Plan 8
rule).

### 8.5 Services (`etqan.notifications.services`)

| Function | Does |
|---|---|
| `templates.listing() -> list[TemplateRow]` | Every type × language: type, language, title, body (override or default), `customised`, default title and body, placeholders, and enabled (from the settings). |
| `templates.save(type_, language, *, title, body) -> TemplateRow` | Checks (§8.2), then upserts. An unknown type or language → `NotFoundError`. |
| `templates.reset(type_, language) -> TemplateRow` | Deletes the override (a no-op if there is none). |
| `templates.preview(type_, language, *, title, body) -> tuple[str, str]` | Checks, then renders with the samples in the academy's timezone. |
| `preferences.of(user) -> list[(category, enabled)]` | The categories for `user.role` (§8.3) and their state. Empty for admins and staff. |
| `preferences.set(user, changes: list[(category, enabled)]) -> list` | Idempotent: inserts the opt-outs (`bulk_create(ignore_conflicts=True)`) and deletes the opt-ins. A category not in `categories_for(user.role)` → 400 `category`. |

The package `__init__` exports them (additive).

## 9. B5a API (under `/api/v1/notifications/`)

The preferences endpoints use one shape for reading and writing:
`{"categories": [{"category": "...", "enabled": bool}]}`; a PATCH may send a subset. Answers also carry
`notifiable` (`recipients.eligible(user)`), so the card can show T-11's note.

| Method & path | Permission | Body / answer |
|---|---|---|
| `GET templates/` | `notification_settings.view`, then `notification_templates` | list of §8.5 rows |
| `PUT templates/<type>/<language>/` | `notification_settings.update`, then `notification_templates` | `{title, body}` → the row |
| `DELETE templates/<type>/<language>/` | `notification_settings.update`, then `notification_templates` | → the row, now default (200) |
| `POST templates/preview/` | `notification_settings.view`, then `notification_templates` | `{type, language, title, body}` → `{title, body}` |
| `GET preferences/` | signed in (`SELF_SERVICE` in the route test), then `notification_preferences` | own categories |
| `PATCH preferences/` | same | own categories |
| `GET preferences/<user_id>/` | `[HasCode, FeatureOn]` with codes `("student.view", "teacher.view", "parent.view")` (any one) | the person's categories |
| `PATCH preferences/<user_id>/` | same, with the three `.update` codes | the person's categories |

For `preferences/<user_id>/`, `HasCode` first lets in any office user holding one of the three codes; a non-office
caller gets 403. Then the order is:
1. Feature off → 404.
2. The view loads the target with `identity.services.get_user`. Missing, or not a student, teacher or parent → 404.
3. A parent target while `parents` is off → 404.
4. The caller lacks the target's own `f"{role}.view"` or `f"{role}.update"` code (`codes_of`; admins pass) → 404,
   so nothing reveals who exists.

All of this is tested. Neither write takes `NotImpersonating` (changing a preference is not messaging).
`notification_settings`'s `in_use` stays `view`, `update`.

## 10. B5a seeds, tests, e2e

- **Seeds.** `etqan/tenants/seeds/b5.py`: `seed_b5(subdomain)` is called under the B5 marker in `seed_dev`. On the
  demo academy it customises `subscription.expired` in both languages; it is idempotent. The registry default
  for both switches is off. The demo academy gets them on through `seed_dev.FEATURES` (every built feature), as
  for every other phase. No opt-out is seeded, so existing bell and e2e expectations hold.
- **Backend tests:**
  - the placeholder checker: each rejection kind, `{{ }}` accepted, and per-type sets;
  - `PLACEHOLDERS` and `Kind.roles` match the finders;
  - save, reset, preview and listing;
  - the API permission matrix: codes, role 404s, the switch 404 after the role check, and the ordering in §9;
  - the scan renders an override only while the switch is on;
  - the scan skips an opted-out recipient and keeps the others;
  - duty notices are never dropped;
  - opt-outs are ignored while `notification_preferences` is off;
  - the scan's query count does not grow with the number of hits;
  - every type has a category.

  Coverage ≥ 80 %.
- **Dashboard tests:**
  - the templates page: list, edit, chips insert, preview, save with 400 mapping, reset, read-only without
    `update`, and the settings link only with `academy_settings.view`;
  - the preferences card: own, office mode, read-only, a student without email, and the optimistic revert.

  Thresholds per CLAUDE.md.
- **e2e** `e2e/b5-templates.spec.ts`:
  1. `set_features demo --on notification_templates notification_preferences`;
  2. an admin customises `session.reminder` (en), previews, saves, then resets;
  3. a student turns `payments` off on their account page, and it stays off after a reload.

## 11. B5a non-goals

- Templates for broadcasts (a broadcast is free text, B5b).
- Per-channel templates (WhatsApp uses the same text, B5c).
- New notice types (B5d).
- Rich text or HTML in templates: plain text only, and emails wrap it in the branded layout as today.
- Per-user quiet hours.
- A Spanish template.
- Preferences for admins and staff.
