---
name: schedule-call-audit-fixes
phase: C
modules: [scheduling, dashboard]
status: in-progress
created: 2026-09-12
closed: null
---

## Goal

A UI/UX audit of the three shipped user-facing surfaces — the schedule
(`booking`), the availability editor (`scheduling`), and the call
(`dashboard/features/call`) — found ~40 defects. This spec closes them. Three
are severe enough to name individually, and all three are the same shape: **the
interface destroys work, or takes an irreversible action, without asking.**

1. Unsaved availability edits are silently replaced by server state whenever the
   window regains focus. `new QueryClient()` in `main.tsx` takes React Query's
   defaults (`refetchOnWindowFocus: true`, `staleTime: 0`), and both the
   availability route and `WeeklyAvailabilityEditor` reset local slot state from
   the query in an effect. Alt-tab away mid-edit, come back, work is gone. No
   message.
2. "Copy Saturday to all" **replaces** all seven days, wiping days that already
   had ranges, with no confirmation and no undo. The label says copy.
3. Leaving a call is a single tap of a control sitting in the same thumb-reach
   bar as mute, and it is instant and unrecoverable.

The rest are the ordinary accumulation an audit finds: keyboard patterns that
were never finished, states with no copy, a list that can only look forward,
and per-row timers that run for lessons three weeks out.

This is a **deliberate D10 deviation.** D10 says do not clean up while you are
here — add it to `ISSUES.md` and keep going. The user asked for the whole audit
fixed in one pass, after being told which principle that breaks and why. It is
recorded in `journal/2026-W37.md` as an explicit deviation, and the scope is
bounded by the audit: nothing outside the three audited surfaces is touched.

## User flow

**Editing availability.** A teacher opens the availability editor and adds a
range. The editor is now *dirty*, and says so: the Save button becomes the only
enabled path forward and a line states there are unsaved changes. While dirty,
a background refetch no longer overwrites the editor — server data is held and
applied only once the edit is saved or discarded. Navigating away, or closing
the tab, asks first. Saving clears the dirty state, and the "Saved" line clears
again the moment anything else is edited.

**Copying a day.** "Copy Saturday to all" asks for confirmation, and the
confirmation says what it will do in the terms that matter: how many days
already have ranges that will be replaced. Confirming applies it; the editor is
dirty, so it is still undoable by discarding.

**Timezone.** Changing the timezone is now part of the same dirty edit as the
ranges, not an immediate commit, and the editor states plainly that the ranges
are read in the selected zone — changing it re-reads every range at the same
clock time. The picker itself is a real listbox: arrow keys, Home/End, Escape
to close, an explicit Cancel, and a "Use my device timezone" shortcut for the
common case. The option list is capped while a search narrows it, so it no
longer puts several hundred tab stops into the page.

**Reading the schedule.** The schedule shows the viewer's timezone, once, at
the top — the number on a row means nothing without it when the two parties are
in different countries. Past lessons are reachable: the page has upcoming and
past, and a cancelled lesson moves rather than vanishing. The empty state
points somewhere.

**Leaving a call.** Tapping the leave control asks "Leave this lesson?" with the
consequence stated (the lesson keeps running; you can re-join from the
schedule). Confirming leaves. The dialog is an `AlertDialog`, so it cannot be
dismissed by an outside tap.

**During a call.** The header carries how long is left in the lesson alongside
the connection state. When screen sharing is unavailable in this browser, the
control is present and disabled with copy saying why, instead of silently
absent. A peer muting or unmuting is announced to assistive technology.

## Data model delta

None. No new tables, no new fields, no migrations.

## API delta

None. Every fix is client-side. Past sessions are already returned by
`GET /api/v1/scheduling/sessions/` — the list was filtering them out
client-side.

## Frontend

Routes unchanged: `/_authed/schedule`, `/_authed/availability`,
`/_call/sessions/$sessionId/room`.

Work packages, in merge order. Each is independently shippable.

| # | Package | Findings closed |
| --- | --- | --- |
| 1 | Availability: dirty state, nav guard, copy confirm, validation | P0-1, P0-2, P1-4, P1-5, P1-6, P1-8, P2 ordering/width/totals |
| 2 | `TimezoneBar`: listbox keyboard, dismissal, capped list | P1-7 |
| 3 | Schedule: past sessions, timezone, empty state, timers, skeletons | P1-11, P1-12, P1-15, P2 timers/spinners/claim/quota |
| 4 | Call: leave confirm, safe area, session clock, a11y, states | P0-3, P1-9, P1-10, P1-13, P1-14, P1-16, P2 call items |

**Not in scope, with reasons** (see Out of scope for the rest):

- The lobby mic/camera asymmetry the audit flagged is a **deliberate C5
  decision**, not a defect: muting happens mid-sentence, and re-acquiring the
  microphone there costs latency and can fail outright. The camera releases; the
  microphone does not. Unchanged.
- Output-device selection (`setSinkId`) is a feature, not a fix, and is not
  supported on the browser the call work most needs it for. `ISSUES.md`.

## Module boundaries

`dashboard` only. No backend module is touched, so `import-linter` has nothing
new to check. The three dashboard features involved (`booking`, `scheduling`,
`call`) already import each other through their published `index.ts` barrels and
that does not change.

## Out of scope

- Any backend change. Every finding is client-side.
- A calendar or week grid view of the schedule. The audit notes the schedule is
  a forward-only list; adding history closes the defect, and a calendar is a
  feature that needs its own spec.
- Drag-select availability entry. The audit notes a weekday 9–5 schedule takes
  ~20 interactions; "copy to all" with a confirm plus a weekday shortcut
  reduces it. A grid editor is its own spec.
- Replacing the hand-rolled `CallSettingsMenu` / `DevicePickerButton` popovers
  with Radix primitives. Their *behavioural* gaps (touch dismissal, focus) are
  fixed here; the structural rewrite is a refactor and belongs in its own
  change, per D10.
- Virtualising the timezone list with a windowing library. Capping the rendered
  count closes the defect without a new dependency.

## Test plan

Every package is TDD: the failing test lands first.

**Unit (vitest + RTL + jest-axe), must pass:**

- A background refetch while the editor is dirty does **not** replace local
  slots; the same refetch while clean does.
- Copy-to-all does nothing until confirmed, and names the count of days it will
  replace.
- Two identical ranges on one day remove independently (the React-key collision).
- An overlapping range is refused with a message naming the range it overlaps.
- "Saved" disappears on the next edit.
- `TimezoneBar`: ArrowDown/ArrowUp move the active option, Home/End jump,
  Escape closes and restores focus to the trigger, Cancel closes, exactly one
  option is in the tab sequence at a time.
- The schedule renders a past lesson under a past heading, and shows the
  viewer's timezone.
- `useNow` does not tick for a session outside the proximity window.
- Leaving a call requires confirmation; the confirm calls `leave`, the cancel
  does not.
- `CallStatus` renders time remaining and re-announces peer mute politely.
- axe: no violations on the availability editor, the timezone picker open, the
  schedule with both sections, and the leave dialog.

**e2e (Playwright), added to the existing suite:**

- Availability: edit, trigger a focus refetch, assert the edit survives; then
  navigate away and assert the guard appears.
- Schedule: a past lesson is visible under its own heading after a reload.
- Call: tapping leave shows the dialog; cancelling keeps the call up; confirming
  returns to the schedule.

⚠ The e2e suite hardcodes the call control bar's target count in three places
and names a "Layout" button in two more (CLAUDE.md D3). This change does not
alter the bar's membership — leave gains a dialog, share gains a disabled state
— but the count assertions must be re-checked, not assumed.

**Coverage:** both floors are ratchets (ADR-0026). Dashboard's floor rises if
this work lifts it; it may not fall.

## Open questions

None blocking. One judgement recorded rather than asked: the fixes stack on
`feat/call-controls-redesign` (#48) because the audited code exists nowhere
else, which makes this a fourth PR in an unmerged chain and a known D6
deviation. The alternative — waiting for the chain to merge — was rejected by
the user's instruction to fix everything now.
