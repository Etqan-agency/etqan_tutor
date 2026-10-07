# Slice B5d — More automatic notices — Design

**Date:** 2026-10-07
**Status:** Self-approved after an independent spec review (orchestration PO-3); review findings applied 2026-10-07.
**Phase spec:** `2026-10-07-b5-communication-design.md` §3, the B5d row and the mapping of TH's eleven templates.
Decisions B5-1…B5-13 bind it, along with ledger D39.
**Evidence:** TH §2.7 COMM-004 (templates and timings), and its notification preferences tab (student / teacher
schedule update, trial sessions). P1 COMM-004 and COMM-007; FLOW-005; §15. Spec notes in B2a, B2b B-13, B2e and
B2g G-12 leave these notices to B5. Ledger D8, D26, D29 and D39. R7 is dropped (D1).
**Requires:**
- B5a: categories, templates and preferences.
- B5b: migration `0003` and the `NOTICE_TYPES` / `NOTICE_TARGETS` split.
- Per notice, the owner's read service (§4): **R6** to B2, **R7** to B6.
- B2g, for the substitution notice only.
- B2f, for the carried-over study-group audience only.

Each notice is its own plan task, built once its read service is in.

## 1. Goal

The scan learns twelve more notices: TH's three missing ones, the session-change, trial and compensation notices B2
left to B5, and the homework and level-upgrade notices B6 left to B5. Each is a finder over a read service that the
owning app publishes (D39), with its own setting, editable text and preference category. Reminders also follow a
session that moved (B2b B-13).

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| M-1 | **Read services, not field filters (D39).** Every finder calls a windowed or instant read service exported by the owning app's `services` package. Notifications never filters another app's model fields. The services are requested in §4 (R6 to B2, R7 to B6). They are additive and read-only, have a fixed query count, and return objects with what a `Hit` needs selected. | ledger D39; B5-2 |
| M-2 | **New types** (`kinds.Kind`). Each has a target, a default, a range, a category, roles and duty roles. Each also has a settings row (default **on**, as Plan 8's), templates, placeholders and sample facts. The 24-hour look-back applies to the event types, so a type's first scan after deploy announces the last day's events; this is accepted, as in Plan 8. | spec 2026-09-26 N8-2..N8-5; B5a |
| M-3 | **`session.teacher_early_reminder`.** It goes to the teacher, by default 120 minutes before the session (range 30–1440). It reads the existing `sessions_starting`. Category `sessions`. | TH COMM-004 |
| M-4 | **`session.teacher_absent`** (the apology). It goes to the student and guardians when a non-cancelled session's teacher was marked absent within the look-back. The read service is R6a `teacher_absences_marked(*, since)`. It is **ungated** [assumed: the office marks teacher absence whether or not `teacher_attendance` is on]. Category `sessions`. | TH COMM-004; P1 §15 |
| M-5 | **`session.ended`**, a nudge to the teacher. It is sent `value` minutes after a session's end (default 5, range 1–55) while the session is still `scheduled` with both attendances `not_set`, and it is given up 60 minutes after the end. The read service is R6b `sessions_ended(*, now, after, give_up)`. Category `sessions`; it is not a duty [assumed]. `report.missing` stays the duty, in `reports_homework`: it concerns the report, while this concerns the session. It is gated by `teacher_attendance`, because it asks the teacher to mark it. It links to `/teaching/sessions`. | TH COMM-004 |
| M-6 | **`session.postponed`.** It goes to the student, guardians and teacher, but not to whoever made the move [assumed]. The read service is R6c `postponements(*, since, until)`. It is built on B2c's POSTPONE activity entries, so every move counts, a move back to the original slot included.<br>• **Occurrence** = the activity entry id, so a second move is notified too.<br>• **Placeholders:** `time` = the new start, `old_time` = the start before *this* move.<br>Category `schedule`, gated by `postponement`. | B2b B-4, B-13; TH preferences "schedule update" |
| M-7 | **`session.compensation_booked`.** It goes to the student, guardians and teacher for a compensation session created within the look-back that starts in the future and is not cancelled. The read service is R6d `sessions_booked(*, kind, since, now)`. `time` is the make-up's start. Category `schedule`, gated by `compensation_sessions`. | B2a spec note |
| M-8 | **`session.trial_booked`.** The same service with `kind="trial"`. It goes to the student, guardians and teacher. Category `schedule`: TH's "trial sessions" toggle is folded into schedule [assumed]. Gated by `trial_sessions` (B2e E-13). | TH preferences "trial sessions"; B2e; D8 |
| M-9 | **`schedule.substitution`.** When B2g records a substitute for a subscription over a date range, the student, guardians, the substitute and the regular teacher are told, once per substitution record. The read service is R6e `substitutions(*, since, until)`, after B2g.<br>• **Target kind** `subscription`, **occurrence** = the substitution id.<br>• **Placeholders:** `student`, `course`, `teacher` (the substitute), `regular_teacher`, `from`, `to`.<br>A bulk change of a subscription's own teacher, and Plan 4's single-subscription teacher change, are **not** notified: nothing records them, since sessions are regenerated (B2g G-5/G-7, B2c C-3). This is a non-goal until B2 records such changes. Category `schedule`, gated by `weekly_schedules`. | B2g G-5..G-7, G-12; review |
| M-10 | **Homework**, through R7a `homework_notices(*, since, until) -> list[HomeworkNotice]`. Each item has: kind, homework id, title, course names, the student's profile with its user, the setter's user id and role, and at.<br>• `homework.set` → the student and guardians;<br>• `homework.answered` → the setter, only when their role is `teacher` (office-set homework tells nobody);<br>• `homework.completed` → the student and guardians.<br>Each fires once per homework and kind: later re-answers or re-completions are not repeated [assumed]. Target kind `homework`, category `reports_homework`, gated by `homework`. Links: student and parent `/learning/homework`, teacher `/teaching/homework`, office home. | ledger D29; B6-6 |
| M-11 | **Level upgrades**, through R7b `upgrade_notices(*, since, until) -> list[UpgradeNotice]`. Each item has: kind (`requested` or `decided`), request id, student profile with user, course names, target level names, status, the requester's user id and role, and at.<br>• `level.upgrade_requested` → active admins (the office decides). Admins have no preferences, so it is always sent while switched on.<br>• `level.upgrade_decided` → the student, guardians, and the requester only when their role is `teacher`. Placeholders `student`, `course`, `level`, `outcome` (localised approved / not approved).<br>Target kind `upgrade`, category `reports_homework` [assumed: progress news], gated by `levels`. Links: office `/scheduling/level-upgrades`, student and parent `/learning/progress`, teacher `/teaching/levels`. | B6a C-10/C-11; B6-6 ("upgrade-request notices are B5's") |
| M-12 | **Reminders follow a moved session (B2b B-13).** The three reminder types (`session.reminder`, `session.early_reminder`, `session.teacher_reminder`) and the new `session.teacher_early_reminder` use occurrence = the session's `starts_at` (ISO, UTC). A postponed session is therefore reminded again at its new time. Sessions already reminded under the old key, inside their window at deploy, may be reminded once more; this is accepted. | B2b B-13, B2g |
| M-13 | **Model additions in notifications** (B5-owned):<br>• `Hit` gains `extra_teacher` (a second teacher user, for the regular teacher in M-9) and `requester` (a user);<br>• `finders.AUDIENCES` parts gain `EXTRA_TEACHER` (role teacher) and `REQUESTER` (role teacher, only when the user's role is teacher);<br>• `recipients.resolve` gains both branches;<br>• `Facts` gains `old_starts_at`, `title`, `level_ar`, `level_en`, `outcome`, `teacher`, `regular_teacher`, `from_on` and `to_on`, each filled only for its types.<br>`text.PLACEHOLDERS` adds `old_time`, `title`, `level`, `outcome`, `teacher`, `regular_teacher`, `from` and `to` per type. | B5a §8.2; review |
| M-14 | **Migration** (one, in `etqan.notifications`). It alters the choices of `NotificationSetting.type`, `NotificationTemplate.type` and `Notification.type`. It alters `Notification.target_kind`'s choices and widens it from 12 to 16 characters, which needs no data rewrite (B5-10). | B5-10; review |
| M-15 | **Screens.** The settings form and the templates page gain the groups **schedule** (postponed, compensation, trial, substitution), **homework** and **levels**. The preferences card shows `schedule` and `reports_homework` wherever they now have a non-duty type for the role. | B5a §6 |
| M-16 | **Carried over from B5b.** If B5b shipped without its study-group audience (R5 not done in time), B5d builds it, with B5b's Task 7 text, once B2f and R5 are in. | B5b §7 |
| M-17 | **Import contract.** The notifications contract's forbidden list gains `etqan.learning.models` and `etqan.learning.api` (phase §4). | phase §4 |

## 3. Tests

- **Per finder:** inside and outside the window, the switch and feature gating, the recipients (including
  `REQUESTER` and `EXTRA_TEACHER` role filtering), and occurrence and dedupe:
  - two postponements give two notices;
  - re-scans give none.
- **Cost:** query counts are fixed for 1 vs many hits.
- **Invariants:** B5a's invariant tests (placeholders, roles, categories) extend automatically.
- **Width:** `target_kind` "upgrade" and "homework" fit.
- **Reminders:** a reminder for a postponed session is sent again at the new time.
- **Links:** the path for each new target kind and role.
- **Dashboard:** the new settings and template groups, and the preferences card's newly shown categories.
- **e2e** `e2e/b5-notices.spec.ts`:
  - a postponement tells the student;
  - homework set tells the student, through `manage("scan_notifications", …)`.

## 4. Requests

**R6 to B2** (the `etqan.scheduling.services` read services, each additive, read-only and with a fixed query
count, returning `Session` objects with `student__user`, `teacher__user` and `course` selected):

| Service | Returns |
|---|---|
| a. `teacher_absences_marked(*, since)` | Non-cancelled sessions with `teacher_attendance="absent"` and `marked_at >= since` |
| b. `sessions_ended(*, now, after, give_up)` | Sessions with status `scheduled` and both attendances `not_set`, whose end (`ENDS_AT`) lies in `(now - give_up, now - after]` |
| c. `postponements(*, since, until) -> list[Postponement(entry_id, session, previous_starts_at, new_starts_at, by_user_id, at)]` | From B2c POSTPONE activity entries |
| d. `sessions_booked(*, kind, since, now)` | Sessions of `kind` created at `since` or later, with `starts_at > now`, not cancelled |
| e. `substitutions(*, since, until) -> list[Substitution(id, subscription_id, student, course, regular_teacher_user, substitute_user, starts_on, ends_on, created_at)]` | B2g's substitution records; after B2g merges |

**R7 to B6** (the `etqan.learning.services` read services, unscoped, each with a fixed query count):

| Service | Returns |
|---|---|
| a. `homework_notices(*, since, until) -> list[HomeworkNotice(kind, homework_id, title, course_name_ar, course_name_en, student, set_by_user_id, set_by_role, at)]` | `student` is a `StudentProfile` with its user. The service is derived from `homework_events`. |
| b. `upgrade_notices(*, since, until) -> list[UpgradeNotice(kind "requested"\|"decided", request_id, student, course_name_ar, course_name_en, level_name_ar, level_name_en, status, requested_by_user_id, requested_by_role, at)]` | Upgrade requests made or decided in the window |

## 5. Non-goals

- Notices for a subscription's own teacher changing; nothing records it (M-9).
- Per-session reminder stamps (B5-12).
- "Subscription offers" (phase §3).
- Certificate notices (D33).
- Registration notices.
- WhatsApp (B5c).
- Repeated homework re-answers (M-10).
