---
number: 0040
title: Replace the palette outright, own it in the token package, and adopt EN 301 549
status: accepted
date: 2026-09-12
amends: ADR-0020 (adds EN 301 549 to the baseline); supersedes the palette clause of the 2026-06-13 design-system-visual-identity spec
---

## Context

ADR-0020 made WCAG 2.2 AA a repo-wide baseline, "contrast asserted in tests on both light
and dark themes", and explicitly bound `@kaleem/tokens`, `dashboard`, and `marketing`.
Three months later the enforcement has a specific, documented hole.

**The AA fixes exist, but they live in the wrong repo.** Eight token values are
overridden in `dashboard/src/index.css:29-64` rather than in the shared package. The
override block's own comment explains why, honestly: the package is consumed as a pinned
git tag, so changing it needs publish → re-pin → reinstall → Docker rebuild, and that
breaks live HMR verification. Four of the eight are contrast fixes:

| Token | Package ships | Dashboard overrides to | Why |
| --- | --- | --- | --- |
| light `--muted-foreground` | `#62736C` | `#55655F` | 4.14:1 on `#EFE9DB` — **fails 1.4.3** |
| light `--input` | `#E0D9C8` | `#968B71` | ≈1.4:1 on card — **fails 1.4.11** |
| dark `--input` | `#2A3A34` | `#5E766C` | ≈1.4:1 on card — **fails 1.4.11** |
| dark `--success-foreground` | `#07302A` | `#052621` | exactly 4.50:1 — on the line |

The consequence is recorded in `ISSUES.md` under "Blocks launch": **marketing consumes
the package and therefore inherits the failing values.** The dashboard is fixed;
the other surface is not. Lighthouse independently observes this — the staging login page
scores accessibility 96 with a colour-contrast failure, logged with this same root cause.

Three further findings, each verified rather than inferred:

1. **The contrast test hand-mirrors 26 hex literals** copied from the token files
   (`dashboard/src/test/a11y.test.tsx:64-115`). Its own comment at L58-63 records that
   this already went wrong once: the gate asserted a dark-primary pair the dashboard had
   already overridden, so it passed while the rendered button went untested. The mirror
   is not a style problem; it is a gate that has demonstrably reported green on an
   unverified value.
2. **The `tokens` repo has no CI at all.** There is no `.github/` directory. Its
   `smoke.test.mjs` is a script someone has to remember to type, and it does no contrast
   maths regardless. The package that ADR-0020 names as the place accessibility is
   "designed in or permanently designed out" has never had an automated check.
3. **`/design-preview` does not exist.** `docs/architecture/design-system.md:62`
   describes it as rendering the three-mode login "for manual + automated checks".
   `dashboard/src/routes/` contains no such file. The documented verification
   infrastructure was never built.

Separately, the owner has asked to **replace** the palette rather than patch it, and to
add **EN 301 549** as a conformance target. Neither EN 301 549 nor Section 508 nor VPAT
nor any procurement or public-sector obligation appears anywhere in this repository —
searched and confirmed absent. The recorded regulatory exposure is GDPR only (ADR-0023).
This target is therefore being **introduced, not inherited**, which is worth stating so
that nobody later cites it as a pre-existing requirement.

## Decision

**1. The palette is replaced outright, and `@kaleem/tokens` becomes its only home.**

A new palette is designed against WCAG 2.2 AA from the start, in OKLCH for perceptually
even lightness steps, verified in both themes before any ramp is committed to. Targets:

- Body text ≥4.5:1 on every declared surface, **targeting 7:1 (AAA) on `background` and
  `card` where the hue allows** — usually one extra lightness step, and free.
- Large text ≥3:1; UI component boundaries and state indicators ≥3:1 (1.4.11).
- Focus indicators ≥3:1 against **both** the component and the adjacent background
  (2.4.11 Focus Appearance), ≥2px. The existing `ring-2` + `ring-offset-2` recipe has
  only ever been checked against one of the two.
- **Colour is never the only signal** (1.4.1).

**2. `dashboard/src/index.css:29-64` is deleted in full — not trimmed.**

Four of the eight overrides are shadows, fixed properly by making elevation a per-theme
token (today shadows are defined only in `:root`, which is the entire reason the
dashboard had to restate all three in `.dark`). The other four were computed against
values that will no longer exist: `--muted-foreground: #55655F` was tuned to clear 4.5:1
on `#EFE9DB`, and `#EFE9DB` is going away. **A surviving override is a silently wrong
value — the same failure mode as the drifted mirror.**

**3. The contrast gate is derived from the token source, never mirrored.**

The package ships a pairing manifest declaring, for each foreground token, which surfaces
it may appear on and at what threshold. The gate imports the token data and the manifest
and loops. It contains **zero hex literals and zero pair names**. It runs in two places
for two different reasons: in `tokens` (where the values are, before a tag exists, and
the only protection marketing gets — it has no test suite at all), and in `dashboard`
(asserting the *installed* package, so a bad re-pin goes red at zero extra CI cost).

This is only possible if the palette is machine-readable data rather than CSS text, which
is what ADR-0041 decides.

**The gate must be mutation-checked before it is trusted.** Break a value, watch it go
red, restore. This project has already shipped a contrast test that reported green while
testing nothing; a gate never *seen* failing does not count as a gate.

**4. `/design-preview` is built, because the swap is atomic.**

There is no way to dual-run two palettes here. `@theme inline` binds every utility to
`var(--color-*)` resolved at use site, so changing a value repaints everything at once.
Scoping a second palette to a subtree fails because **every Radix overlay portals to
`document.body`** — 14 dialogs plus dropdowns and toasts would render outside the scope.
The preview route is what makes an atomic swap reviewable in one screen, and it is the
target for both the axe sweep and the real-browser contrast check.

**5. EN 301 549 is adopted, with its actual scope stated.**

**For the design system, the delta over WCAG 2.2 AA is approximately zero.** Clause 9
(web) incorporates WCAG by reference, and 2.2 AA is a superset of what it requires.
Clauses 5 and 11 add software-level obligations already satisfied or inapplicable.
Adopting it changes no engineering requirement in this ADR.

**The one clause with real teeth for kaleem is clause 7 — captions and audio description
for video.** kaleem delivers live 1-on-1 video lessons. Nothing in the design system
touches this; it belongs to the call feature, needs its own spec, and is substantial
work. **It is explicitly out of scope here and tracked in `ISSUES.md`.** Writing "EN 301
549 conformant" without saying that is the failure mode this clause exists to prevent.

## Alternatives considered

- **Keep the Serene Scholar palette and only promote the four contrast fixes.** The
  cheapest path, and the one `ISSUES.md` already prescribes. Rejected by owner decision
  in favour of a full replacement. Worth recording that it was the lower-risk option: it
  would have closed the launch blocker in one small release without a visual change.
- **Keep the overrides in the dashboard and accept marketing's divergence.** Rejected.
  It is the status quo, it is a recorded launch blocker, and it means the two surfaces
  render different brands — one accessible, one not.
- **Scope a second palette to a subtree and migrate component by component.** Rejected on
  a mechanism, not a preference: Radix portals to `document.body`, so every dialog,
  dropdown and toast escapes the scope. It would have looked like it worked in
  development and broken exactly where overlays appear.
- **Visual-regression snapshots to protect the swap.** Rejected. An intentional palette
  replacement invalidates every baseline on day one and then charges a churn tax forever,
  to a solo developer, on a product with no pixel contract. `/design-preview` plus the D9
  click-through covers it better and cheaper.
- **Cite Section 508 as well.** Rejected: it is the US federal procurement rule, there is
  no US public-sector exposure recorded, and it incorporates WCAG 2.0 AA — strictly
  weaker than what ADR-0020 already binds. Citing it would add words and no obligation.

## Consequences

**Good**

- The launch-blocking inherited-contrast issue closes, for both surfaces, in one release.
  Marketing gets the fix without a marketing code change.
- The contrast gate stops being able to drift, because it stops holding values. The
  specific 2026 failure — a mirror drifts and the test passes anyway — becomes
  structurally impossible rather than merely discouraged.
- `tokens` gets CI for the first time. The package ADR-0020 names as the home of
  accessibility decisions has, until now, had nothing checking it.
- `docs/architecture/design-system.md` stops describing a route that does not exist. As
  ADR-0026 argued about `CLAUDE.md`: a single false load-bearing claim is contagious,
  because a reader who finds one has no way to tell which of the rest are real.
- The pinned git tag turns out to be a safety mechanism, not only friction — `v0.2.0` is
  live nowhere until a consumer re-pins, so the whole replacement can be built and
  reviewed at zero exposure.

**Bad / costs**

- **This is the most visually disruptive change the project has made.** Every surface on
  both sites changes at once, and it cannot be staged by component. The mitigations are
  real but they are mitigations, not a staged rollout.
- The brand assets in `brand/` — logos, favicons, app icons, marketing imagery — were
  produced against Serene Scholar and will be off-palette the moment this ships.
  Regenerating them is not in this ADR's scope and is not budgeted. **This is the largest
  unpriced cost of choosing replacement over repair**, and it should be expected to
  surface as follow-up work.
- `brand/design.md` and the 2026-06-13 spec's palette tables become historical. They are
  amended rather than deleted, but anyone reading them without the amendment will get the
  wrong hexes.
- The pairing manifest becomes a new hand-maintained artifact. It eliminates *value*
  drift but not *coverage* gaps: a component pairing two tokens nobody declared still
  passes. The real-browser axe check is the compensating control, and it must land with
  the swap rather than afterwards.
- Adopting EN 301 549 puts a clause-7 obligation on the record that the project cannot
  currently meet — kaleem has no captioning for live lessons. That is the honest position
  and it is better logged than unstated, but it does convert an unknown into a known open
  item.
- None of this is verifiable on Safari or iOS. This project has no Apple device, and
  Playwright's WebKit on Linux is not iOS Safari. Recorded as a D9 deviation, as C3e was.
