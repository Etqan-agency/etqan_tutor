# Dropdown redesign — gate (Agent 2, cycle 1)

Date: 2026-11-02. Judged against the owner's three points (Khaled, screenshots `images/1.png`,
`2.png`: the Trials filter row, AR dark) and `round-3/decisions.md` § "Dropdown redesign".
Code under test: the local working tree (`dashboard/src/ui/select.tsx`, `dashboard/src/index.css`
bridge), served by the running dashboard container.

## Verdict: **FAIL** (cycle 1)

One blocker (P0) and one owner point not met. Everything else is good.

| # | Owner point / requirement | Result |
|---|---|---|
| 1 | Gap between text and chevron | **PARTLY FAILED**: fixed on `w-auto` filter rows (Trials: 8 px), still 125–230 px on the Students and Sessions filter grids |
| 2 | Soft grey border, ≥ 3:1 | PASS |
| 3 | Custom brand popup replaces the native one | **FAILED**: it looks right, but a **mouse click or a finger tap on an option never chooses it** |
| – | Keyboard (arrows, Home/End, PageUp/Down, Enter, Escape, typeahead) | PASS |
| – | A real filter change and a real saved form change | PASS by keyboard; impossible by pointer (see G-1) |
| – | Console errors | none on any screen (only the known aborted `manifest.webmanifest` request) |
| – | Clipping, on screen at 375, RTL | PASS |
| – | `tsc`, full vitest `--maxWorkers=3` | see § Gates |

## Failing points

### G-1 (P0, blocker): choosing an option with the pointer does nothing, on desktop and on phones
- **Steps:**
  1. Trials (`/app/scheduling/trials`), AR dark, 1440.
  2. Click "أي حالة للطلب": the list opens.
  3. Click "مقبول".
- **Expected:** the field shows "مقبول" and the table filters (5 → 4 rows).
- **Actual:** the list closes and nothing is chosen (`value` stays `""`, still 5 rows).
  - Same result with a real touch tap at 375×812 (`isMobile`, `hasTouch`):
    `{"open1":1,"val":"","open2":0}`.
  - Same on Settings → Academy → Default language: clicking "English" leaves `ar`.
- **Event trace** (capture listeners on `document`): `pointerdown` (list open) → `mousedown` (list
  open) → `mouseup` (**list already gone**). No `click` ever reaches the option.
- **Root cause:**
  - The listbox is rendered through `createPortal`, but React still bubbles synthetic events
    through the React tree. So the option's `mousedown` reaches the **wrapper's** `onMouseDown`
    (`select.tsx`, the `<div data-slot="select" onMouseDown=…>`).
  - That handler sees `e.target !== selectRef.current` and runs `if (open) close();`.
  - The list unmounts before `mouseup`/`click`, so `commit()` never runs.
  - The listbox's own `onMouseDown={(e) => e.preventDefault()}` does not stop the propagation.
- **Why the unit tests miss it:** `select.test.tsx` "opens a brand listbox on the pointer…" picks
  with `fireEvent.click(option)` alone, which sends no `mousedown`. A real pointer sends
  `mousedown` first.
- **Suggested fix (for Agent 3):**
  - In the wrapper's `onMouseDown`, ignore events from outside its own DOM subtree:
    `if (!e.currentTarget.contains(e.target as Node)) return;`
  - Or call `e.stopPropagation()` in the listbox's `onMouseDown`.
  - Regression test: `await userEvent.setup().click(option)`, or `fireEvent.mouseDown(option)`
    followed by `fireEvent.click(option)`. Assert the value changes and `onChange` fires once.
  - Then re-check: a mouse pick, a touch pick at 375, a pick inside a dialog (portalled into
    `role=dialog`, same propagation), and a disabled option.
- **Impact:** every one of the ~258 selects in the product can be changed only with a keyboard.
  Phone users cannot use any select at all. This blocks the release.

### G-2 (P2, owner point 1 not met): filter grids still show a long gap before the chevron
- **Where:**
  - Students (`/app/people/students`, the `PeopleList` filter grid). The task names it as the
    owner's view.
  - Sessions (`/app/scheduling/sessions`) filters.
- **What's wrong:**
  - The selects are `w-full` cells of a 4-column grid, 273 px wide at 1440.
  - Measured gap from the end of the text to the chevron:
    - Students AR dark: 180–230 px.
    - Students EN light: 125–186 px.
    - Sessions EN light: 137–195 px.
- **Shots:** `after-01-students-ar-dark-1440.png`, `after-19-students-en-light-1440.png`.
- **Contrast with Trials:** the `w-auto` rows (Trials, Invoices) are fixed: 8–9 px measured
  (`after-02`).
- **Why it's still a problem:** the owner said "in every dropdown". On these two grids the visual
  is unchanged from before (compare `build-01-students-ar-dark.png`).
- **Note:** form selects (Settings, New subscription, dialogs) are full-width with the chevron at
  the end, like every text field in the same form. That is the normal form pattern, and I don't
  count it against point 1.
- **Suggestion:**
  - Give the filter grids content-sized selects: `w-auto` in a wrapping flex row, like Trials.
  - Or keep the grid and put the chevron right after the text (`justify-start`, no `flex-1` on
    the label) so the gap stays 8 px.
  - The owner should see which one he prefers.

### Minor (P3, fix alongside)
- **G-3: LTR labels are mis-ordered in an RTL list.** In the RTL popup (New subscription →
  Student, AR), names like `+cmd`, `-5 days`, `=HYPERLINK("http://x")` render as `cmd+`,
  `days 5-`, `HYPERLINK("http://x")=` (`after-10`). The option label and the trigger text need
  `dir="auto"`, or `<bdi>`, the way `PersonName` does it.
- **G-4: filter selects resize when the value changes.** A `w-auto` filter changes width as the
  value changes ("أي حالة للطلب" 126 px → "مقبول" 96 px), so the whole Trials row shifts sideways
  after each pick (`after-04`). Acceptable, but a stable `min-w` per filter would be calmer.

## What passed

### Point 2: border grey
Resolved colours, read in the running app:
- dark `--input` = `rgb(121,126,124)` = `#797E7C`;
- light `--input` = `#938D83`.

Recomputed WCAG contrast:

| Theme | on background | on card / popover | on secondary |
|---|---|---|---|
| dark (new) | 4.16:1 | 3.26:1 | 2.39:1 (no Select sits there, as decisions.md notes) |
| dark (old ink.500) | 5.29:1 | – | – |
| light (unchanged) | 3.13:1 | 3.29:1 | 2.78:1 (pre-existing) |

- **Dark:** visibly softer and on the brand's ink hue, not a white outline. The binding surface is
  the card (3.26:1), so there is little room for anything softer.
- **Light:** already at the 3:1 floor on the page. A lighter grey would fail WCAG 1.4.11, so
  leaving it unchanged is correct.
- Time and date inputs share the same `border-input`, so every field matches (`after-17`).

### Point 3: the popup look
The popup is portalled, uses `bg-popover` with a hairline border, `rounded-lg` and a soft shadow.
- The chosen row has an emerald tint and a check mark in a fixed start column. The hover row is
  `bg-secondary`.
- It looks professional and on-brand in all four combinations (AR/EN × light/dark): `after-03`,
  `-05`, `-07`, `-10`, `-11`, `-14`, `-15`, `-18`.
- **RTL:** the list is anchored to the field's right edge, the check sits on the right, and text is
  right-aligned. The chevron is mirrored to the left, and it flips up while the list is open.

### Keyboard
On Trials, focus on the select, AR. Each check was verified by reading `aria-activedescendant` and
the value:
- Enter opens on the current value.
- ↓↓ moves the highlight.
- Escape closes the list without changing the value, and focus stays on the select.
- End jumps to the last option and Home to the first.
- Enter chooses the highlighted option: `accepted`, and the table goes from 5 to 4 rows.

Typeahead (Invoices, EN, Any student):
- `d` → "Daniel Carter";
- the burst `F02 S` → "F02 Student a".

Long list: Settings → Time zone has 419 options in 2 groups. It opens at 320 px with group
headings, and PageDown scrolls it (`after-07`).

Dialog ("Add session", EN dark): the list is portalled inside `role=dialog`. The first Escape
closes only the list and the dialog stays open; the second Escape closes the dialog (`after-18`).

### Real changes (both by keyboard, because of G-1)
- **Filter:** Trials, request status → مقبول. The rows were filtered correctly (`after-04`). The
  session wasn't saved, so nothing persists.
- **Form:** Settings → Academy → Default language `ar` → `en`, then Save and a reload. It
  persisted as `en=English` (`after-08`). I then reverted it to `ar`, saved, reloaded and checked
  `ar=العربية`. The QA academy is back to its original state.

### 375 px
- Trials AR dark: the list is 343 px wide, from 16 to 359 px, with no sideways scroll
  (`scrollWidth` 375, `after-09`).
- New subscription EN light: the field is near the bottom of the screen, so the list flips above
  it and stays on screen (`after-11`).
- Parent child picker AR dark at 375 (`after-14`) and EN light at 1440 (`after-15`): correct.

### Teacher portal
- The attendance selects are disabled until a session starts. They render dimmed with the softer
  border and don't open (`after-12` AR dark 1440, `after-16` EN light 375).
- The availability editor has no selects; it uses time inputs, as decisions.md says (`after-17`).

## Screenshots (`qa/manual/screens/r3/dropdown/`)

| File | What |
|---|---|
| `after-01-students-ar-dark-1440.png` | Students filters, owner's view: G-2 |
| `after-02-trials-ar-dark-1440.png` | Trials filters, 8 px gap |
| `after-03-trials-open-ar-dark-1440.png` | popup open, hover row |
| `after-04-trials-filtered-accepted-ar-dark.png` | keyboard filter change applied |
| `after-05-invoices-open-en-light-1440.png` | invoices student popup |
| `after-06-settings-en-light-1440.png` | form selects |
| `after-07-settings-timezone-open-ar-dark-1440.png` | 419-option list |
| `after-08-settings-saved-english-en-light.png` | saved form value (reverted after) |
| `after-09-trials-open-ar-dark-375.png` | phone popup |
| `after-10-new-subscription-open-ar-dark-1440.png` | form popup, G-3 visible |
| `after-11-new-subscription-open-en-light-375.png` | phone, flipped above |
| `after-12-teacher-home-open-ar-dark-1440.png` | teacher, disabled selects |
| `after-14-parent-child-picker-open-ar-dark-375.png` | parent child picker |
| `after-15-parent-child-picker-open-en-light-1440.png` | parent child picker |
| `after-16-teacher-sessions-en-light-375.png` | teacher phone |
| `after-17-teacher-availability-ar-dark-1440.png` | availability (time inputs) |
| `after-18-dialog-open-en-dark-1440.png` | popup inside a dialog |
| `after-19-students-en-light-1440.png` | Students EN light: G-2 |
| `gate/mouse-pick-trials.png` | after a mouse click on "مقبول": nothing chosen (G-1) |

## Gates
All runs were in the `dashboard` container.
- **`tsc --noEmit`:** exit 0, no output.
- **Full vitest `--maxWorkers=3`:** 4398 / 4409 passed, 11 failed in 9 files. The 11 failures, all
  under machine load, with a backend pytest running alongside:
  - 5 hit the 5 s timeout;
  - the other 6 were `findBy…` / `waitFor` waits that ran out under load:
    - `StudentForm`: "creates a student without email…";
    - `ArticleEditor`: QA-709;
    - `RequestDialog` ×3;
    - `TagsSettings`;
    - `NotificationBell`;
    - `ProgressPanel`;
    - `ArticlesManager`;
    - `SimpleSessions`;
    - `SendLinksButton`.
- **Rerun of those 9 files alone, `--maxWorkers=3`:** 9/9 files and 129/129 tests pass. That
  points to timing flakes, not to regressions from the Select.
- **Gap in the suite:** it stays green while G-1 exists, because no test drives a real
  `mousedown` → `click` on an option.

## To pass cycle 2
1. Fix G-1 with a regression test that uses a real pointer sequence.
2. Fix G-2 on the Students and Sessions filter grids, and on any other `w-full` filter grid
   (`PeopleList`, `NotificationLogPage`).
3. G-3 and G-4 alongside.

The gate will then repeat:
- mouse and touch picks (page, dialog, 375);
- the gap measurement on Students and Sessions;
- the full keyboard pass;
- `tsc` and vitest.
