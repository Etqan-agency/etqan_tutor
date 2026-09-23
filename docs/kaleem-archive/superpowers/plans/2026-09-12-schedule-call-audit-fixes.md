# Plan — schedule/call audit fixes (C6)

Spec: `docs/superpowers/specs/2026-09-12-schedule-call-audit-fixes-design.md`

Branch: `feat/c6-audit-fixes` in `dashboard`, stacked on
`feat/call-controls-redesign` (#48). One PR per package if the chain allows;
otherwise one PR with four reviewable commits.

Each task is TDD: the failing test first, then the code, then the next test.

## Package 1 — availability (P0)

1. **Dirty tracking.** `WeeklyAvailabilityEditor` gains a `dirty` flag set by
   every mutation (add/remove/copy/timezone). The `useEffect` that syncs
   `value.slots` becomes conditional on `!dirty`. Test: a prop change while
   dirty does not replace state; while clean it does.
2. **Route + unload guard.** A `useBlocker` on the availability route and a
   `beforeunload` listener, both keyed on `dirty`. Test: blocker registered when
   dirty, not when clean.
3. **Slot identity.** Give each slot a client-side `id` (a counter, not the
   time) so pills key stably. Test: two identical ranges, remove the first,
   assert the second survives.
4. **Overlap validation.** `InlineEditor` refuses a range overlapping an
   existing one on that day, naming it. Test: 09–12 then 10–11 refused.
5. **`copyToAll` confirm.** Radix `AlertDialog`, copy naming the count of days
   that will be replaced. Test: unconfirmed = no change; confirmed = applied.
6. **`saveStatus` reset.** Clear on any mutation. Test.
7. **Timezone into the dirty edit.** The route stops committing
   `TimezoneBar.onChange` straight to saved state; the editor owns pending
   timezone and states that ranges are read in the selected zone. Test.
8. **`removeSlot` order.** Rebuild preserving original order. Test on payload.
9. **Weekday column** `w-20` → `min-w-20 w-auto` + `shrink-0`. **Weekly total**
   line in the footer. Tests: Arabic label not clipped (width assertion),
   total reflects slots.

## Package 2 — `TimezoneBar` (P1-7)

10. Roving tabindex + `aria-activedescendant`; ArrowUp/Down/Home/End; Enter
    selects; Escape closes and restores focus; explicit Cancel; outside
    pointerdown closes. Tests per key.
11. Cap the rendered list (100) with a "keep typing to narrow" hint when the
    filter matches more. Test: 400 zones in, ≤100 options rendered.
12. "Use my device timezone" action wired to the existing `detectTimezone()`.
    Test.
13. axe on open state.

## Package 3 — schedule (P1)

14. **Past sessions.** `SessionList` splits upcoming / past (past = not
    `scheduled`, or `starts_at` in the past), past collapsed by default, newest
    first. Test both sections.
15. **Timezone line** on `SchedulePage`, from `Intl.DateTimeFormat().resolvedOptions()`.
    Test.
16. **Empty state** gains a description and, for a student, a pointer to
    claiming a slot. Test.
17. **`useNow` proximity gate.** `active` additionally requires
    `can_join_at - now < 1h`; outside that the row renders a static countdown.
    Test: no interval scheduled for a distant session (fake timers).
18. **Skeletons** replacing the three page-level spinners. Test: no layout shift
    assertion is not reachable in jsdom — assert the skeleton renders instead.
19. **Claim cards**: per-card pending (only the clicked card shows a spinner),
    and the card names the teacher/subject when the API provides them. Test.
20. **Quota meter**: a progress bar alongside the text, `role="progressbar"`
    with the text as its accessible name. Test + axe.

## Package 4 — call (P0-3 + P1)

21. **Leave confirmation.** An `AlertDialog` in `CallControls`. Tests: confirm
    calls `onLeave`, cancel does not, dialog is not outside-dismissable.
22. **Safe-area chrome.** `--call-chrome-height` becomes
    `calc(5rem + env(safe-area-inset-bottom))` and the bar drops the fixed `h-`
    in favour of min-height, so thumbnails positioned against the variable stay
    clear. Test: computed offsets in jsdom are limited — assert the class
    contract, and add the real check to the e2e emulation.
23. **Single `<h1>`.** The route's `sr-only` h1 is the only one; `Lobby`'s
    becomes an `<h2>`. Test.
24. **Session clock.** `CallStatus` shows remaining time from the session's
    `starts_at` + `duration_minutes`, ticking each minute. Test.
25. **Share unsupported.** Render the control disabled with explanatory copy
    instead of omitting it. Test.
26. **Toggle semantics.** Stable labels + `aria-pressed`, dropping the flipping
    label. Tests updated across `CallControls` and `Lobby`.
27. **Peer mute announced.** A polite live region in `CallRoom` announcing the
    peer's mic state change. Test.
28. **Terminal copy.** `detailKey` for `room-full`, `replaced`, `linkExpired`
    with an actual next step. Test each.
29. **Layout restore.** Restore the pre-share layout when sharing stops;
    persist `spotlightOn`. Test.
30. **Lobby join pending.** Disable Join and show a spinner while
    `getUserMedia` is outstanding. Test.
31. **Touch dismissal.** `CallSettingsMenu` and `DevicePickerButton` listen on
    `pointerdown`, not `mousedown`. Test.
32. **Lobby level meter.** A `WebAudio` input meter under the preview proving
    the microphone is live. Test with a stubbed `AudioContext`.

## Close-out

33. Run `pnpm test`, `pnpm lint`, `tsc`, and the e2e suite. Re-check the three
    hardcoded control-bar counts in `dashboard/e2e/`.
34. Raise the dashboard coverage floor to the new measured value (ADR-0026
    ratchet). Never lower it.
35. Journal entry recording the D10 and D6 deviations; `STATE.md`; new e2e rows
    in CLAUDE.md's D3 table.
