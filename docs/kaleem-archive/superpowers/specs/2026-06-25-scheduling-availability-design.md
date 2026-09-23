---
name: scheduling-availability
phase: B
modules: [scheduling, identity]
status: draft
created: 2026-06-25
closed: null
---

## Goal

Let teachers and students declare **when they're available**, as a recurring weekly pattern,
in their own timezone, via a Calendly-style editor. This is the foundation for a later
two-sided **matching** feature (system finds teachers whose availability overlaps a student's,
filtered by rules like teacher-gender preference, and broadcasts to them; first to accept is
linked). **This spec builds only availability + its editor** — not matching, sessions, billing,
or video.

It also starts the roadmap's **Phase B `scheduling`** module and **unifies** availability into
one queryable store: today the student's availability is a JSON blob on `identity.StudentProfile`;
this moves it into a real, queryable `scheduling.WeeklyAvailability` table shared by teachers and
students, so the future matching engine can compute overlap efficiently.

> **Phase note (deviation):** the roadmap sequences `billing` (B1) before `scheduling` (B2) and
> expects Phase A fully closed first. We are starting `scheduling` early at the user's explicit
> direction. Recorded as a deliberate deviation in the weekly journal. Nothing here depends on
> billing or sessions; those gates are added when the booking/matching specs land.

## User flow

**Teacher — set availability** (new page, e.g. `/availability`):
1. Open the page → see a "Weekly availability" editor. Timezone is auto-detected and shown at
   the top ("Times shown in your timezone: Africa/Cairo (UTC+3)").
2. For each weekday (Saturday-first), the teacher adds one or more time ranges via **+ Add time**
   → an inline `start → end` picker (15-minute steps; end must be after start) → the range appears
   as a removable pill (`09:00 – 12:00 ×`).
3. Optional **"Copy [day] to all"** to replicate a day's ranges across the week.
4. **Save** persists the full set. Days with no ranges read "Unavailable".
5. **Change** next to the timezone opens a searchable IANA-zone picker; saving updates the user's
   timezone.

**Student — set availability** (existing `/account` page): the same editor replaces the current
day + start/end "Preferred times" rows. The student page keeps its separate **teacher-gender
preference** control (unchanged), which saves to `identity`.

**Error cases:** end ≤ start → inline validation, no save; invalid timezone → rejected; network
error on save → inline error, the editor keeps the user's edits; not authenticated → redirect to
login (standard `_authed` guard).

## Data model delta

**`identity.User`** — add `timezone: CharField` (IANA name, e.g. `Africa/Cairo`; default `UTC`;
validated against `zoneinfo.available_timezones()`).

**`identity.StudentProfile`** — **remove** `time_preferences` (JSONField). Keep
`teacher_gender_preference`.

**New `scheduling.WeeklyAvailability`:**

```
WeeklyAvailability
  id
  user        FK -> AUTH_USER_MODEL   (CASCADE)   # teacher or student
  weekday     PositiveSmallInteger    (0..6, Saturday-first: 0=Saturday … 6=Friday)
  start_time  TimeField                            # local wall-clock in user.timezone
  end_time    TimeField                            # must be > start_time
  constraints: end_time > start_time; (no hard uniqueness — overlaps are merged in the service)
  index: (user, weekday)
```

Mini-ERD:

```
User (identity) ──1:N──> WeeklyAvailability (scheduling)
User.timezone anchors every row's wall-clock times.
```

Times are stored as naive wall-clock **interpreted in `user.timezone`**. No per-row tz column —
the anchor is the user's single timezone. (Multi-timezone-per-user is out of scope.)

## API delta

All under `/api/v1/scheduling/`, DRF SessionAuthentication + CSRF, JSON.

**`GET /me/availability/`** → `200`
```json
{ "timezone": "Africa/Cairo",
  "slots": [ { "weekday": 0, "start_time": "09:00", "end_time": "12:00" }, ... ] }
```
Caller's own availability + timezone. Requires a student or teacher profile (else `403`).

**`PUT /me/availability/`** — body:
```json
{ "timezone": "Africa/Cairo",
  "slots": [ { "weekday": 0, "start_time": "09:00", "end_time": "12:00" }, ... ] }
```
**Full-replace** semantics. In one transaction: validate, merge same-day overlapping/adjacent
ranges, delete the caller's existing rows, insert the new set, and update the caller's timezone
via `identity.services.set_timezone`. Returns the saved state (same shape as `GET`). Errors are
typed (`platform.drf`): `end ≤ start`, bad weekday, malformed time, invalid IANA zone → `400`
with field-scoped messages; no profile → `403`; missing CSRF on mutation → `403`.

**`identity`** gains `services.set_timezone(user, tz)` (validates + saves `User.timezone`). The
existing `GET/POST /me/student-profile/` **shrinks** to `teacher_gender_preference` only.

## Frontend

Dashboard slice (React 19 + TanStack Router/Query, `@kaleem/tokens`, en/ar + RTL, jest-axe):

- **Routes:**
  - New `/_authed/availability` — **teachers** (gate by `teacher` profile); page wraps the editor.
  - Existing `/_authed/account` — **students**: the editor replaces the current "Preferred times"
    rows in the learning-preferences card; gender preference stays.
- **Shared component `WeeklyAvailabilityEditor`** (likely `features/scheduling/`):
  - Per-weekday rows (Saturday-first); each range a removable pill; **+ Add time** opens an inline
    `start → end` picker (15-min steps, `end > start`); **Copy [day] to all**; **Save** (full-replace).
  - Timezone bar (auto-detect via `Intl.DateTimeFormat().resolvedOptions().timeZone`) + searchable
    zone picker on **Change**.
  - States: loading (skeleton/spinner), empty ("Unavailable" per day), error (inline alert, edits
    preserved), success (toast). Optimistic-free; invalidates the availability query on save.
- **API calls** via the scheduling feature's api module (`GET`/`PUT /me/availability/`); gender via
  the existing identity endpoint.
- **"Done"** = built, deployed to staging, browser-verified end-to-end (teacher sets availability,
  student sets availability, timezone change persists, reload shows saved state) in both en and ar/RTL.

## Module boundaries

- **`scheduling` owns** `WeeklyAvailability` and the `/me/availability/` API. New module: `models.py`,
  `services.py` (public API), `api.py` + serializers wired into the DRF router, `admin.py`, `apps.py`.
- **Public service API:** `get_availability(user)`, `set_availability(user, slots, timezone=None)`,
  `to_utc_intervals(user, reference_date)` (tz-conversion primitive, handles weekday wraparound).
- **Calls into `identity`** only via `identity.services.set_timezone` (cross-module through services —
  boundary-legal). `identity` does **not** import `scheduling`.
- **import-linter:** add a contract so `scheduling` may not import another module's models; verified
  in CI.
- No new domain events in this spec.

## Out of scope

- The **matching engine** (overlap search, rule filters, broadcast to teachers, first-accept-claim,
  student↔teacher linking) — future spec. We only build the conversion primitive it will use.
- **Sessions / bookings / Zoom**, **billing / entitlement** gates, ratings/reports.
- **Cross-user availability viewing** (seeing someone else's times converted into yours).
- Additional match factors beyond what already exists (age, etc. — "set later").
- **DST exactness** and multi-timezone-per-user: `to_utc_intervals` uses a reference date; recurring
  weekly local times shift UTC offset across DST — accepted approximation, documented.
- Data migration of existing student `time_preferences`: **none** — in development we reset the DB
  and re-run migrations (staging has only disposable smoke users).

## Test plan

**Backend (TDD, 100% line+branch):**
- *Model:* `end > start` enforced; `weekday` bounds; `__str__`.
- *Services:* `set_availability` merges same-day overlapping/adjacent ranges, full-replace deletes
  prior rows, sets timezone via identity; `get_availability` shape; `to_utc_intervals` including the
  **teacher +3 / student +2** example and a **weekday-wraparound** case (`Sat 01:00 +3 → Fri 22:00 UTC`);
  `identity.set_timezone` validates/saves and rejects bad zones.
- *API:* `GET`/`PUT` happy path; auth required; CSRF required on `PUT`; typed `400`s for `end ≤ start`,
  bad weekday, malformed time, invalid zone; `403` when caller has no student/teacher profile.
- *Boundaries:* import-linter contract green; no direct cross-module model import.

**Frontend (TDD, jest-axe, en/ar + RTL):**
- `WeeklyAvailabilityEditor`: render rows; add a range via the inline picker; remove a pill;
  `end > start` validation; copy-to-all; full-replace save payload; timezone display + change;
  "Unavailable" empty day; loading/error(success preserves edits)/success(toast); a11y clean.
- Teacher `/availability` page (teacher-gated) and student `/account` integration (editor + gender).
- Timezone picker (search + select).

**e2e:** the Playwright harness still doesn't exist (ISSUES); the primary path is browser-verified
manually for this slice, with the gap flagged — consistent with prior slices.

## Open questions

- None blocking. (Defaults chosen and made explicit above: 15-minute step granularity; `User.timezone`
  defaults to `UTC`; availability endpoint gated to student/teacher profile holders; `to_utc_intervals`
  uses a reference date for DST.)
