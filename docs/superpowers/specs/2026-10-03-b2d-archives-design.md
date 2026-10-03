# Slice B2d — Archives and the Simplified Sessions View — Design

**Date:** 2026-10-03
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); its 19 findings are applied below.
**Phase:** B2, slice d (`2026-10-03-b2-scheduling-depth-design.md` §3, as amended by B2b: B2d = archives & simplified
view).
**Builds on:** Plan 4 (subscription statuses, `delete_subscription`, renewal, the Today board), Plan 5 (sessions list,
bulk), Plan 12a (codes and verbs), Plan 13 (switches, FT-4), B2a (session classes), B2b (postponement, board rows),
B2c (`track`, `record_many`, `LOGGED_FIELDS`, the inverse table).
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` SUB-003, SUB-004, SCHED-005, SCHED-006 / PANEL-007, BR-45, BR-46, §8.1–8.2,
§19 (archive = separate tables or a scoped view: UNKNOWN); `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` SUB-002/3/4,
SCHED-005/006, §1.3 #11, §5.4–5.5.

## 1. Goal

The office can put finished subscriptions and sessions away: they leave the everyday office lists, keep counting
everywhere, appear on their own archive screens, and come back with one click. A simplified sessions view gives the
office a compact list for a phone.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| D-1 | **One concept: archived.** TutorHamster shows an "archive" screen (routed `expired-subscriptions` / `expired-sessions`) and a separate "delete keeping records" with a "deleted records" filter and restore. Both put a record away while keeping it; we build one flag, `archived_at`, and one archive screen per entity, and call the action "Archive (delete keeping records)". | P1 SUB-003, SUB-004, BR-45; phase B2-10 |
| D-2 | **Archived is a scoped view, not a move to other tables**: the same rows with `archived_at` set. Other apps never filter on `archived_at`, so every count, invoice, payroll run and consumption number keeps including archived rows (BR-46 "table + archive" holds by construction). Recorded in the ledger. | P1 BR-46, §19 (separate tables UNKNOWN) · [assumed] scoped view |
| D-3 | **Only an ended subscription is archived** (`expired` or `cancelled`) and only while none of its sessions is still due (a `scheduled` session starting in the future: cancel or expiry leave make-ups, extras and postponed rows behind). An archived subscription never generates. A live one is cancelled first. | P1 §8.1 shows soft delete from paused / expired · [assumed] ended only, nothing due |
| D-4 | Archiving a subscription archives its sessions with it; restoring it restores the sessions that were archived *with it*, not ones archived on their own. | [assumed] |
| D-5 | **A session is archived on its own** when it is no longer due: `completed`, `cancelled`, `at_disposal`, or `scheduled` with its start in the past. A future scheduled session is refused. Payroll-locked and compensated sessions can be archived: archiving changes no number. | P1 SCHED-005 (archive holds unmarked sessions: bulk "mark as completed") · [assumed] rule |
| D-6 | Archiving is **manual** (row and bulk actions). No job archives on a schedule. | TH §4 U8 (archive moves unconfirmed) · [assumed] |
| D-7 | **Archived sessions still take writes**: attendance, cancel, restore, reports and bulk work on them (TH's archive offers "mark as completed"). Postponing an archived session is refused (it would become a hidden future session). **An archived subscription refuses** renewal, adding a make-up or extra session against it, and slot edits / deletion (409 `scheduling.archived`; restore it first); its other writes already refuse an ended subscription (Plan 4 `require_status`). These refusals apply only while `subscription_archive` is on (D-13). | P1 SCHED-005 bulk actions · review · [assumed] |
| D-8 | Hidden from the **office's default lists** only: the subscriptions list, the sessions list (and their CSVs) and the Today board. People's own lists, a subscription's own sessions panel, the missing-reports queue, the supervision list, billing and payroll are unchanged. | [assumed]: the office decides what clutters its lists; people keep seeing their own records |
| D-9 | **Permanent delete** keeps Plan 4's rule (no marked, completed, cancelled or at-disposal session; not renewed) and works from the subscription archive screen too. The session archive has no delete: a hand-added session is deleted from its own page by B2a's rules. | P1 SUB-004, SCHED-005 (TH has bulk delete: not built) |
| D-10 | Codes: archive = `subscription.delete` / `session.delete` (TutorHamster's "delete keeping records"); restore = `subscription.restore` / `session.restore` (TH's `restore` verb), which become in use. The same `*.delete` code also guards permanent delete, as today: no role can archive without being able to delete permanently. Accepted (moving permanent delete to `force_delete` would need a role data migration in an app B2 does not own). | P1 SUB-004 (restore / force_delete verbs); Plan 12a · review |
| D-11 | Archive screens (§6.1 has the filters and columns). Subscriptions: bulk restore; Delete permanently per row; CSV. Sessions: P1's columns, filters "compensation only" and "completed only" plus the sessions list's filters, bulk Present / Absent / Cancel (the existing bulk route) and Restore, CSV. TH's account type and payment method filters are not built (no such fields; payment fields are B3's, ledger D10). Who archived a session is known only from the B2c log (no `archived_by` on sessions). | P1 SUB-003, SCHED-005 |
| D-12 | **Simplified sessions view** (office, `session.view_any`): one compact row per session (time in academy time and the student's when it differs, student, teacher, course, status, attendance), today by default with a date picker and the list's pagination ("more" loads the next page); Present / Absent buttons reuse the existing attendance controls and their rules (`attendance.update`, started, not cancelled, not compensated); a Join link. It reads the existing sessions list API (so it follows the archive default); `simplified_sessions` gates only the screen, there is no backend route. | P1 SCHED-006 / PANEL-007 (`/onlyadmin/`; contents UNKNOWN) · [assumed] contents |
| D-13 | Switches, off by default: `subscription_archive`, `session_archive` (registry lines flipped to built in place), `simplified_sessions` (new line under the B2 marker). With an archive switch off: its routes and its `archived=` parameter 404, its screen and actions are hidden, its D-7 refusals stop, and **archived records show in the default lists again** (off hides the feature, never the data, FT-4); turning it back on hides them again. | PO-5; spec Plan 13 FT-4 · review |
| D-14 | Archive and restore are logged (B2c): `archived_at` joins `LOGGED_FIELDS`; a session's own archive / restore are revertible entries; the cascade from a subscription is a `record_many` entry, not revertible. | spec B2c C-4, C-8 |

## 3. Data

New nullable columns (phase B2-16; no data rewritten):

| Model | Field | Notes |
|---|---|---|
| Subscription | `archived_at` | datetime, nullable |
| Subscription | `archived_by` | → User, nullable, `SET_NULL` |
| Session | `archived_at` | datetime, nullable |
| Session | `archived_with_subscription` | bool, `db_default` false: set when the subscription's archive archived it (D-4) |

No new index: archive lists filter a nullable column on small per-academy tables.

## 4. Behaviour

### 4.1 Subscriptions

`archive_subscription(subscription, by)`: lock the subscription, then its sessions (Plan 4 lock order, pk order).
Refusals, in order: already archived → 409 `scheduling.archived`; status not `expired` / `cancelled` → 409
`scheduling.not_allowed_in_status`; a `scheduled` session starting in the future → 409
`scheduling.has_upcoming_sessions`. Then set `archived_at = now`, `archived_by = by`; and on its sessions not archived
yet, `archived_at = now`, `archived_with_subscription = true` (one `.update()`, logged with `record_many` as
`subscription_archived`).

`restore_subscription(subscription, by)`: lock in the same order. Refusal: not archived → 409
`scheduling.not_archived`. Clear both fields; clear `archived_at` and `archived_with_subscription` on its sessions with
`archived_with_subscription = true` (`record_many`, `subscription_restored`).

`refuse_if_archived(subscription)` (409 `scheduling.archived`, only while `subscription_archive` is on) is called after
the subscription's lock by `renew_subscription` (before its status check), `create_regular_session`,
`create_extra_session` (when a subscription is given), `create_compensation` (on the original's subscription),
`add_slots`, `update_slot` and `delete_slot`.

### 4.2 Sessions

`archive_session(session, by)` and `unarchive_session(session, by)`: lock the session (B2a lock order, no subscription
lock: session writes never lock a subscription after a session), then `track(session, by, "archive" | "unarchive")`,
then refuse, raising:

- archive: already archived → 409 `scheduling.archived`; a future `scheduled` session → 409
  `scheduling.not_allowed_in_status`.
- unarchive: not archived → 409 `scheduling.not_archived`; its subscription archived (read after the session lock)
  while `subscription_archive` is on → 409 `scheduling.archived` (restore the subscription). An unarchive also clears
  `archived_with_subscription` (reachable only while `subscription_archive` is off, D-13).

`archive_sessions(ids, by)` / `unarchive_sessions(ids, by)`: up to 200 ids locked up front in pk order (as
`bulk_sessions`), each passed to the single-session service in its own savepoint; a refusal's code becomes its skip
code. Answer `{done, skipped}`.

`postpone_session` (B2b) refuses an archived session with 409 `scheduling.archived` while `session_archive` is on,
after its locks and before its status checks.

### 4.3 B2c additions

`archived_at`: an ISO UTC instant or null. Actions added to B2c's table:

| Action | Service | Inverse | Revert also needs (code · switch) | Shown while |
|---|---|---|---|---|
| `archive` | `archive_session` | `unarchive_session` | `session.restore` · `session_archive` | `session_archive` on |
| `unarchive` | `unarchive_session` | `archive_session` | `session.delete` · `session_archive` | `session_archive` on |
| `subscription_archived` | `archive_subscription` (`record_many`) | none | | `subscription_archive` on |
| `subscription_restored` | `restore_subscription` (`record_many`) | none | | `subscription_archive` on |

### 4.4 Lists

The list views take `archived`: `exclude`, `only` or `include`, **office only** (a non-office caller sending it gets
404, as `?format=csv` does), and only while the entity's archive switch is on (else 404).

| Endpoint | Office default | Others |
|---|---|---|
| `subscriptions/` (and CSV) | `exclude` while `subscription_archive` is on, else `include` | `include` (their own, unchanged) |
| `sessions/` (and CSV) | `exclude` while `session_archive` is on, else `include` | `include` |
| `subscriptions/<id>/sessions/` | `include`, rows carry `archived_at` (badge) | unchanged |
| `schedule/today/` | archived sessions left out while `session_archive` is on (below) | — |

The branch is on `is_office`, inside the same views that serve every role through `scope_for`. Subscription filtering
moves from `api/views.py` into a service `filter_subscriptions` (CLAUDE.md: logic in services). The dashboard's invoice
form subscription picker passes `archived=include`.

**Today board:** when a slot's session that day is archived, the whole row is dropped (a row with no session would show
`missing` and invite generating a slot date that exists), and archived sessions do not count as the slot's session for
`has_session`. B2b's session-only rows and `postponed` rows follow the same rule.

## 5. Access

| | Office code | Teacher / student / parent |
|---|---|---|
| Archive a subscription | `subscription.delete` | 404 |
| Restore a subscription | `subscription.restore` | 404 |
| Archive sessions | `session.delete` | 404 |
| Restore sessions | `session.restore` | 404 |
| Archive lists (`archived=`) | `subscription.view_any` / `session.view_any` | 404 |

Non-office callers get 404 from an `is_office` check before `HasCode`, as the report views do. The `subscription` and
`session` resource lines widen `in_use` with `restore` (a B2 edit to B2-owned resources, phase §4).

## 6. API (`/api/v1/`)

| Route | Method | Notes |
|---|---|---|
| `subscriptions/<id>/archive/` | POST | Archive (§4.1). Feature `subscription_archive`. Code `subscription.delete`. Returns the subscription. |
| `subscriptions/<id>/archive/` | DELETE | Restore. Same feature. Code `subscription.restore`. Returns the subscription. |
| `sessions/archive/` | POST | `{ids}`. Feature `session_archive`. Code `session.delete`. `{done, skipped: [{id, code}]}`. |
| `sessions/unarchive/` | POST | `{ids}`. Feature `session_archive`. Code `session.restore`. Same answer. |
| `subscriptions/?archived=…`, `sessions/?archived=…` | GET | §4.4 (and CSV). |

New 409 codes: `scheduling.archived`, `scheduling.not_archived`, `scheduling.has_upcoming_sessions`.

### 6.1 Archive filters and columns

| | New query parameters (with `archived=only`) | Payload / CSV additions |
|---|---|---|
| Subscriptions | `archived_from`, `archived_to` (academy dates); `created_from`, `created_to`; existing student, course, teacher, status | `archived_at` (payload and CSV, office only); `archived_by` on the detail |
| Sessions | `archived_from`, `archived_to`; `kind=compensation` (existing B2a filter) for "compensation only"; `status=completed` (existing) for "completed only"; existing filters | `archived_at` joins the office-only session fields; CSV adds `ends_at`, `kind`, `archived_at` |

`archived_at` is left out of payloads while the entity's archive switch is off (FT-4).

## 7. Dashboard (`/app/`)

- **Subscriptions** (`/app/scheduling/subscriptions`): header link "Archive"; row and detail action "Archive (delete
  keeping records)" on ended subscriptions with nothing due, with a confirm; the archive screen
  (`/app/scheduling/subscriptions/archive`) with bulk Restore and per-row Delete permanently; an archived
  subscription's detail shows a banner with Restore and lists its sessions with an "Archived" badge.
- **Sessions** (`/app/scheduling/sessions`): header links "Archive" and "Simplified view"; a bulk "Archive" on the
  list; the archive screen (`/app/scheduling/sessions/archive`) with bulk Present / Absent / Cancel / Restore; an
  archived session's page shows a banner with Restore and hides Postpone.
- **Simplified view** (`/app/scheduling/sessions/simple`): D-12, phone-first.
- **Invoice form:** its subscription picker includes archived subscriptions.
- Strings in en and ar in a new area file `archives.json`; RTL, phone width, semantic tokens; new 409 codes translated;
  NAV unchanged (reached from the list headers).

## 8. Seeds

In `demo`, under the B2 marker, with the three switches among `features.BUILT`: one expired subscription with nothing
due, archived with its sessions; one past cancelled session archived on its own. Idempotent; `other` gets nothing.

## 9. Testing

- **Subscriptions:** archive refusals in order (incl. a leftover future make-up, extra and postponed session); only
  ended ones; the cascade marks only not-yet-archived sessions; restore brings back only `archived_with_subscription`
  sessions; every `refuse_if_archived` caller, on and off; permanent delete from the archive keeps Plan 4's refusals;
  lock order (SQL capture).
- **Sessions:** each D-5 status; the future scheduled refusal; bulk skip codes; unarchive refused under an archived
  subscription only while `subscription_archive` is on; postponing an archived session refused; payroll-locked and
  compensated sessions archive with no number changing.
- **Counting (BR-46):** `derive` (used / carried over / remaining) across a renewal chain whose predecessor is
  archived, `payroll_sessions`, invoice generation and the missing-reports queue are identical before and after
  archiving.
- **Lists:** office default excludes; `only`, `include`; non-office `archived=` 404; switch off: archived rows return to
  the default lists and the parameter 404s; portals unchanged; the subscription's sessions panel includes archived
  rows; the Today board drops a slot row whose session is archived (and B2b's rows); the new filters and CSV columns.
- **B2c:** archive / unarchive entries and their reverts; cascade entries not revertible; visibility by switch.
- **Access:** the code matrix; non-office 404; cross-academy isolation.
- **Existing suites** pass unchanged.
- **Dashboard:** both archive screens, the actions and banners, the simplified view with its quick buttons and paging.
- **e2e** (`e2e/b2-archive.spec.ts`, spec-owned data): the admin cancels a subscription, archives it, finds it on the
  archive screen and not on the list, and restores it.

## 10. Known limits (accepted)

- Archiving is never automatic.
- An archived session can be marked from the archive screen and stays archived.
- Students, teachers and parents still see archived records in their own lists.
- Archive and permanent delete share the `*.delete` code (D-10).

## 11. Out of scope

Payment-method and account-type filters (B3 / not built); bulk delete on the session archive; trials (B2e); bundles
(B2f): a bundle's archive arrives with bundles; weekly schedules and their "deleted" tab (B2g).
