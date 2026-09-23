---
number: 0036
title: Feature components split into a use<Feature> hook and presentational components
status: accepted
date: 2026-09-07
---

## Context

The session UI redesign (`docs/superpowers/specs/2026-09-07-session-ui-redesign-design.md`)
needed to touch `CallRoom.tsx` (458 lines interleaving WebRTC lifecycle, failure derivation
and JSX), `Lobby.tsx` and `SessionList.tsx`. All three carry C3e's Safari/iOS hardening —
gesture-gated `getUserMedia`, a play-effect with a single-item dependency array, terminal-state
cleanup, a visibility-recovery trigger with an exact guard order. Threading a layout change
through code like that, in place, is how one of those guards gets silently reordered.

Two options were on the table: a presentation-only rewrite that carries the existing logic
across verbatim, or a restructure. The restructure was chosen — recorded as a deliberate D10
deviation in the journal, not a default.

## Decision

**A feature component that owns lifecycle logic splits into a `use<Feature>` hook returning a
view model, plus stateless presentational components.** The hook is where effects, refs and
derived state live — `useCallRoom`, for instance, owns the connection lifecycle and returns
the values and callbacks a view needs. The components underneath it take that view model as
props and render; they hold no effects and no refs of their own.

This shipped for `CallRoom` (`useCallRoom`), and the same shape was reused for `Lobby` and
`SessionList`'s extracted children.

## Consequences

**The extraction is only safe when the existing test suite passes unmodified.** This is the
entire premise the pattern rests on, not a footnote. The plan's own sequencing rule (Sequencing,
step 1) required each extraction step to leave `CallRoom.test.tsx`, `Lobby.test.tsx` and
`SessionList.test.tsx` byte-identical and green — "if a single test needs editing at this step,
the extraction is wrong and gets redone." That is what makes this an adoptable pattern rather
than a licence to rewrite: the freeze converts "trust me, the behaviour didn't change" into
something a diff can prove.

**A passing frozen suite is necessary but not sufficient — Task 2 proved it.** Step 2 of the
plan's sequencing mutation-checks every guard that moved, by deleting it and confirming a test
goes red. On `useCallRoom`, the `expiredCalledRef` re-mint guard survived its own deletion: the
existing frozen test still passed, because it was relying on React's render bailout to avoid a
double call, not on the ref. The guard was real code protecting a real bug, and the suite that
was supposed to be pinning it had never exercised it. A new test was added to `useCallRoom.test.tsx`
to cover it, verified RED-under-mutation and GREEN-after-revert. Byte-identical-and-green is
evidence the extraction didn't change *observed* behaviour; it is not evidence every guard in
the file is covered. Step 2 exists because step 1 alone would have shipped an uncovered guard
and called it proven.

**Cost.** Every lifecycle extraction now needs two passes — the freeze, then the mutation
check — before the redesign work can start. That is slower than editing in place. It is the
cost of doing this restructure at all on files carrying hardening this specific and this easy
to silently break.

**Where this applies next.** Any feature component mixing WebRTC/media lifecycle, timers, or
other effect-heavy logic with substantial JSX is a candidate. It is not a rule for every
component — a component with no effects and no refs has nothing to extract.
