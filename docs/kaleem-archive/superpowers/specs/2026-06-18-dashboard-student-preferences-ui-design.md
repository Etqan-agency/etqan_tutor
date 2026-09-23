---
name: dashboard-student-preferences-ui
phase: A
modules: [identity]
status: draft
created: 2026-06-18
closed: null
---

## Goal

Give a signed-in **student** a UI to set their learning preferences — a
teacher-gender preference and a list of preferred time slots — on the `/account`
page. This is **Spec 4 of 4** (the last) in the dashboard-completion roadmap
(shell → email management → children/invites → **onboarding preferences**).

Unlike Specs 1–3 this one includes a **small backend change**: the existing
`me/student-profile/` endpoint is POST-only, and `/me` does not carry the
student's own preferences, so the form has no way to read back what was already
saved. We add a `GET` so the form pre-fills and becomes a real editable settings
surface rather than a blind overwrite.

## User flow

On the existing **`/account`** page (Profile card + Email-addresses card), a
student additionally sees a **Learning preferences** card. (Non-students — a pure
parent or teacher — do not see it.) The card:

1. On open, loads the student's current preferences (`GET me/student-profile/`).
   A `Spinner` shows while loading; a query error shows an inline `Alert`.
2. Pre-fills a form:
   - **Teacher gender preference** — a `<select>` with **Male**, **Female**,
     **No preference** (default: No preference).
   - **Preferred time slots** — a repeatable list. Each row is a **day**
     `<select>` + a **start** `<input type="time">` + an **end**
     `<input type="time">` + a **Remove** (×) button. An **"+ Add time slot"**
     button appends an empty row. The list may be empty.
3. **Save** → `POST me/student-profile/` with
   `{ teacher_gender_preference, time_preferences }`. On success a "Saved."
   confirmation appears and the `student-profile` query is invalidated.

### Days

A fixed weekday list, **Saturday-first** (the conventional week start in the
Arabic/Islamic context), with localized labels. Canonical keys (English,
lowercase) are stored: `saturday, sunday, monday, tuesday, wednesday, thursday,
friday`.

### Validation / edge cases

- A row requires a day, a start, and an end (structural, via zod). **End must be
  after start** (`end_time > start_time`) is checked in the component's `onSubmit`
  (times are "HH:MM" 24-hour strings from `<input type="time">`, which compare
  correctly lexicographically): an offending row gets a translated field error
  (`setError("time_preferences.{i}.end_time", { message: t("prefs.endAfterStart") })`)
  and the `POST` is blocked. Doing the cross-field check in `onSubmit` keeps the
  message i18n'd via `t(...)` (zod refine messages are static strings).
- An **empty** time-slot list is valid — saving it clears the student's
  preferences (the backend's `set_student_profile` replaces the list wholesale
  when provided, and accepts `[]`).
- Server errors are mapped via the existing `parseApiError` to a form-level
  `Alert`; throttle (429) → the neutral throttle message.
- Cross-row **overlap** is NOT validated (the backend does not care; out of scope
  for onboarding preferences).

## Data model delta

None. `StudentProfile.time_preferences` (JSON list of `{day, start_time,
end_time}`) and `teacher_gender_preference` (`male | female | no_preference`,
default `no_preference`) already exist.

## API delta

**One additive backend endpoint.** Add a `GET` handler to the existing
`StudentProfileView` (`backend/kaleem/identity/api/views.py`):

- `GET /api/v1/identity/me/student-profile/` →
  `200 { time_preferences: [{day, start_time, end_time}], teacher_gender_preference }`
  for the caller's `StudentProfile`.
- If the caller has no `StudentProfile` → `404` via the typed
  `platform.exceptions.NotFoundError` (the existing DRF handler maps it to
  `{"detail": ...}`). The UI only calls this for students, who always have a
  `StudentProfile` from registration; the 404 is defense-in-depth.
- Documented with `@extend_schema` using a `StudentProfileResponseSerializer`
  (`time_preferences` = `TimeSlotSerializer(many=True)`, `teacher_gender_preference`
  = `CharField`).

`POST me/student-profile/` is unchanged — it already exists, partial-updates, and
accepts an empty `time_preferences` list.

## Frontend

**Route.** No new route. `src/routes/_authed/account.tsx` gains a student-only
card: `{me.profiles.includes("student") ? <StudentPreferencesCard /> : null}`
after the existing Profile and `EmailAddresses` cards (`me` is already read there).

**Data layer** (`features/identity/`):

- `schemas.ts`:
  - `interface TimeSlot { day: string; start_time: string; end_time: string }`
  - `type TeacherGender = "male" | "female" | "no_preference"`
  - `interface StudentProfile { time_preferences: TimeSlot[]; teacher_gender_preference: TeacherGender }`
  - `timeSlotSchema = z.object({ day: z.string().min(1), start_time: z.string().min(1), end_time: z.string().min(1) })` (structural required-field validation only; the `end_time > start_time` cross-field check is done in the component's `onSubmit` so the message can be `t(...)`-translated)
  - `studentPreferencesSchema = z.object({ teacher_gender_preference: z.enum(["male","female","no_preference"]), time_preferences: z.array(timeSlotSchema) })` → `StudentPreferencesInput`
  - `WEEKDAYS: readonly string[]` — the Saturday-first key list (used by the day select).
- `api.ts` — add to `identityApi`:
  - `getStudentProfile(): Promise<StudentProfile>` → `GET identity/me/student-profile/`
  - `saveStudentProfile(input: StudentPreferencesInput): Promise<void>` → `POST identity/me/student-profile/`
- `queries.ts`:
  - `studentProfileQueryKey = ["student-profile"]`, `studentProfileQueryOptions`, `useStudentProfile()`
  - `useSaveStudentProfile()` — invalidates `studentProfileQueryKey`

**Component** (`features/identity/components/`):

- `StudentPreferencesCard.tsx` — exports `StudentPreferencesCard()`. Uses
  `useStudentProfile` (Spinner while pending; inline `Alert` on error). When data
  loads, renders a react-hook-form (`useFieldArray` for the slots) seeded with the
  fetched values via `defaultValues`/`reset`. Teacher-gender `<select>`; the slot
  rows (day `<select>` + start/end `<input type="time">` + Remove); "+ Add time
  slot"; a Save button; a "Saved." confirmation; a form-level error `Alert`.
  Follows the existing form components' conventions (`Field`/`Input`/`Alert`/
  `Button` from `@/ui`, `parseApiError` from `../api`). A native `<select>` styled
  with the codebase's input classes is used (no new dependency).

**States.** Loading: Spinner. Loaded with no slots: the slot list is empty with
the "+ Add time slot" button (a muted "No time slots yet" line above it). Error:
inline `Alert` (`prefs.loadError`). Save success: "Saved." confirmation.

## Module boundaries

Frontend changes stay inside the dashboard's `features/identity` slice and the
`/account` route. The backend change stays inside `kaleem.identity` (a new GET on
an existing view + a response serializer). No module boundary crossed; no
`import-linter` impact.

## Out of scope

- A parent editing an existing **child's** preferences (today they are only set at
  child creation via `POST children/`). Logged to `ISSUES.md`.
- The teacher availability grid (a separate teacher-side feature).
- Any onboarding **wizard** / first-run gating — this is an editable settings card
  reachable any time from `/account`.
- Cross-row time-slot overlap detection.
- Time-zone handling (times are naive "HH:MM" strings, as the backend stores).

## Test plan

**Backend** (pytest, `backend/kaleem/identity/tests/`): `GET me/student-profile/`
returns the saved `time_preferences` + `teacher_gender_preference`; returns `404`
for a user with no `StudentProfile`; (POST behavior already covered by existing
tests).

**Frontend** (Vitest + RTL + jest-axe; failing test first; 100% line+branch):

- **Pre-fill**: with `getStudentProfile` mocked to return saved prefs, the form
  shows the teacher-gender value and one row per saved slot.
- **Add / remove slot**: "+ Add time slot" appends a row; Remove deletes it.
- **Valid submit**: filling a slot + choosing a gender and clicking Save calls
  `saveStudentProfile` with `{ teacher_gender_preference, time_preferences }` and
  shows "Saved."; assert the `student-profile` query is invalidated.
- **Validation**: a row with end ≤ start shows "End time must be after start time"
  and does not call `saveStudentProfile`.
- **Empty list**: removing all rows and saving sends `time_preferences: []`.
- **Loading / error**: Spinner while pending; inline `Alert` on query error.
- **Account route**: the card renders for a student `me` and is absent for a
  non-student `me`.
- a11y: every control label-associated; Remove buttons have accessible names;
  jest-axe on the component; RTL logical CSS.

## Open questions

Resolved during brainstorming (2026-06-18):

- **Read-back:** add a `GET me/student-profile/` (small backend change) so the
  form pre-fills and is editable — not a write-only blind overwrite.
- **Time-preferences UX:** repeatable slot rows (day `<select>` + start/end
  `<input type="time">`), not a grid or per-day checkboxes.
- **Placement:** a student-only **Learning preferences** card on the existing
  `/account` page, not a dedicated route or the Home page.
