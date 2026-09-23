---
name: design-system-v2
phase: D
modules: [platform]
status: closed
created: 2026-09-12
closed: 2026-09-12
---

## Goal

Replace the kaleem colour palette with one designed against WCAG 2.2 AA from the start,
move it into `@kaleem/tokens` as the single source of truth, and close the component
duplication that has accumulated in `dashboard/src/ui/` since Phase A. The work also
repairs three pieces of verification that are documented but do not exist or do not
work. It supersedes the visual-identity half of
`2026-06-13-design-system-visual-identity-design.md`; that spec's architecture (a shared
token package, tokens shared and components not) is kept and reinforced.

The request that started this was "our UI components are inconsistent and the palette
fails contrast". The audit found a more specific and more awkward situation, and this
spec is written against what is actually there rather than the framing:

- **The palette problem is real but is fixed in the wrong place.** Eight token values
  are overridden in `dashboard/src/index.css:29-64` instead of in the shared package,
  with a written justification that the package is a pinned git tag and releasing is
  expensive. The consequence is that **marketing consumes the failing values**
  (`ISSUES.md`, "Blocks launch"). Two of them are AA failures (1.4.3) and two are
  1.4.11 failures.
- **There is almost no hardcoding.** Zero hex literals appear in any `.tsx`. All 39 in
  the dashboard live in two files: the override block above, and the contrast test.
- **Marketing has no components at all** — three source files, one `<h1>`, one `<p>`,
  no `src/components/`. That is correct per the 2026-06-13 spec, which deliberately
  scoped marketing to "the token package compiles and applies". There is no
  cross-surface inconsistency because there is not yet a second surface.
- **The real problem is duplication inside the dashboard**: no `Dialog` primitive at
  all (14 files hand-roll Radix across two competing recipes, with 14 hardcoded
  overlays), four `<select>` implementations at three heights, five re-implemented
  `Card` surfaces, four hand-rolled skeletons, and one focus-ring recipe copy-pasted
  into twelve files.
- **Three pieces of verification are fiction.** `dashboard/src/test/a11y.test.tsx`
  hand-mirrors 26 hex literals and its own comment records that a drift already caused
  it to silently test nothing. The `tokens` repo has **no CI whatsoever** — no
  `.github/` directory — so its smoke test has never run automatically. And
  `docs/architecture/design-system.md:62` documents a `/design-preview` route that does
  not exist in `dashboard/src/routes/`.

The intended end state: one palette, in one place, proven by a gate that cannot drift
because it holds no values; a primitive set that leaves no reason to hand-roll a dialog;
and CI checks that make the specific 2026 failure mode — *a mirror drifts and the test
passes anyway* — structurally impossible.

## User flow

No user-facing feature is added. The observable changes are visual and are seen by every
role on every authenticated page, plus anonymous visitors to the marketing site.

1. A user opens the dashboard in light mode. Every surface, text colour, border and
   shadow is drawn from the v2 palette. Body text on `background` and `card` meets
   4.5:1 and targets 7:1 (AAA) where the hue allows. Form-control borders are visible at
   rest at ≥3:1 (1.4.11) — today they are not, at package values.
2. The user switches to dark. The same guarantees hold; shadows are now neutral rather
   than green-tinted and are actually visible on dark surfaces.
3. The user switches to Arabic. Direction flips, the Arabic face loads, and no contrast
   or reflow guarantee changes.
4. A keyboard user tabs through any page. Every interactive element shows a focus
   indicator meeting 2.4.11 Focus Appearance at ≥3:1 against **both** the component and
   the adjacent background.
5. A user with `prefers-reduced-motion` set sees no animation, as today.
6. A user on a phone taps controls. Every interactive target is ≥44×44 CSS px
   (2.5.8 requires 24×24; the call route already enforces 44 and the rest of the app
   will match it).
7. An anonymous visitor loads the marketing site and sees the v2 palette, inherited from
   the package with no marketing code change.

**Error cases.** There is no new runtime failure surface. The failure modes this spec is
actually defending against are build- and review-time:

- A token value is edited and breaks a declared contrast pair → the contrast gate fails
  in both the `tokens` repo and `dashboard-lint`.
- A component is written with a hardcoded colour → the colour lint fails
  `dashboard-lint`.
- The `@kaleem/tokens` pin is bumped without the `tokens` submodule pointer (or the
  reverse) → the pin-consistency check fails. This is not hypothetical: the package
  currently reports version `0.1.0` while the consumed tag is `v0.1.1`.

## Data model delta

None. No backend change, no migration, no new table or field.

## API delta

None. No endpoint is added, changed, or removed.

## Frontend

This spec is almost entirely frontend, so this section carries the detail the template
usually spreads across the data and API sections.

### Routes

- **`/design-preview` — NEW, and it is the load-bearing deliverable of this spec.**
  `docs/architecture/design-system.md:62` already claims this route exists; it does not.
  It renders every `src/ui` export × every variant × every state, in light/dark ×
  LTR/RTL. Visible to anyone (it is a static render of primitives and touches no user
  data); it is the target of both the broadened axe sweep and the real-browser axe
  check. Because a palette swap is atomic (below), this route is the only way to review
  one in a single screen — it is the single highest-value mitigation in the plan.
- No other route is added. Existing routes change appearance only.

### Components and states

Every interactive primitive must implement seven states: `default`, `hover`,
`focus-visible`, `active`, `disabled`, `loading`, `error`. Keyboard behaviour follows the
**WAI-ARIA APG**. **Native elements come before ARIA** — this is why `Select` stays a
native `<select>`.

**New:**

| Component | API | Replaces |
| --- | --- | --- |
| `Dialog`, `DialogTrigger`, `DialogContent`, `DialogHeader`, `DialogTitle`, `DialogDescription`, `DialogFooter`, `DialogClose` | `DialogContentProps { size?: "sm" \| "md" \| "lg" }` | 14 hand-rolled Radix surfaces across two recipes, and 14 hardcoded `bg-black/40`-class overlays |
| `focusRing` (a string constant in `src/ui/styles.ts`, composed via `cn()`) | — | the same focus recipe copy-pasted into 12 files |
| `Skeleton` | `{ className?, "aria-label"? }` | four hand-rolled `animate-pulse` blocks at four heights |
| `Meter` | `{ value, max?, role: "progressbar" \| "meter", label }` | two identical visual recipes under two different (and **both correct**) roles |
| `Badge` | `{ tone: "neutral" \| "success" \| "warning" \| "danger" \| "info", icon?, pulse? }` | `StatusChip` plus an inline pill in `bento-tile.tsx` |

`focusRing` is deliberately a string constant rather than a Tailwind `@utility` in the
token package: it stays greppable, it is lintable, and it can change without a package
release.

**Changed:** `Select` keeps its native `<select>` element and its `h-11`; the two local
`SELECT_CLASS` constants and the one inline implementation converge onto it. `Button`
sources `focusRing` from `styles.ts`.

**Removed:** `CardFooter` and `CardAction` — exported, zero call sites.

**Explicitly not merged:** `CallControlButton` stays a feature component.
`CallControlButton.tsx:27-51` argues a real design case that came out of C5/C6
real-device feedback — round because square controls inside a `rounded-full` bar read
unfinished, 48px because call controls are tapped one-handed in a hurry, and `tone` ≠
`variant` because `destructive` previously coloured both "camera off" and "leave lesson",
making a benign toggle look like the most destructive action on screen. Folding it into
`Button` would regress a UI that was fixed from user pain. It will instead source
`focusRing` and the shared size scale, and map its `TONE_CLASS` to tokens rather than
ad-hoc `/95` alphas.

### The token layer

`@kaleem/tokens` moves from hand-authored CSS to **W3C DTCG JSON as the source**, with a
dependency-free emitter producing the `tokens.css` and `theme.css` that consumers already
import. The emitted CSS stays committed (git-URL dependencies do not reliably run
`prepare`, and consumers `@import` the files directly) and is kept honest by
`node build.mjs --check`, mirroring `ruff format --check .`.

The reason for DTCG is specific and is **not** design-tool interop — there is no Figma
round-trip, no second platform, two consumers and one developer. It is that **the
contrast gate needs the palette to be data.** Today the only machine-readable form is CSS
text, which is exactly why the test hand-copies 26 literals. See ADR-0041.

Token categories and the decisions taken on each:

| Category | Decision |
| --- | --- |
| Colour | Primitive OKLCH ramps + semantic aliases, per-theme files with structural parity asserted by the build |
| Typography | A real scale (`xs`…`display`), each rung carrying size, line-height and letter-spacing in Tailwind v4's paired form. Absorbs `--text-display` out of the dashboard |
| Spacing | **One token, `--spacing`, declared explicitly. No `--space-1..12` scale** — see Out of scope |
| Radius | Single `--radius` + four derived in `@theme`, as today. A DTCG `radius` group gives the five hand-rolled `Card` surfaces one authority |
| Elevation | **Modelled per theme, like colour.** Today shadows exist only in `:root`, which is precisely why the dashboard had to override all three in `.dark` |
| Motion | `--duration-*` and `--ease-standard` exist but have **zero usages**. Made live inside the `Dialog` and `Skeleton` work, which need enter/exit and pulse timing anyway. If still unreferenced when that lands, deleted in the same PR |
| Overlay | **New `--overlay`, with a different value per theme.** 40% black reads completely differently over cream than over near-black. The single highest-leverage addition: it kills 14 duplicated hardcoded scrims |

Naming is semantic, never literal: `color.text.primary`, `color.surface.card`,
`color.border.input`, `color.overlay`. The **emitted CSS variable keeps the shadcn name**
(`--background`, `--primary`, `--ring`, …) because every primitive in `src/ui/` depends
on that contract; breaking it would turn a palette swap into a component rewrite.

A **pairing manifest** (`pairs.tokens.json`) declares, for every foreground token, which
surfaces it may appear on and at what threshold — 4.5 for text, 3.0 for form-control
boundaries (1.4.11), and a composited entry for the alpha-carrying overlay. This manifest
is the artifact that replaces the 26 mirrored literals.

### Palette constraints

- Body text ≥4.5:1 on every declared surface; **target 7:1 (AAA) on `background` and
  `card` where the hue allows** — usually one extra lightness step, and free.
- Large text ≥3:1; UI component boundaries and state indicators ≥3:1 (1.4.11).
- Focus indicator ≥3:1 against **both** the component and the adjacent background
  (2.4.11), ≥2px. The current recipe is `ring-2` + `ring-offset-2`; the offset ring must
  be verified against both, not just one.
- **Never colour alone** (1.4.1). Every status conveyance pairs colour with an icon or
  text. Explicit review item on `Badge`, `Alert`, `toast`, and the call `tone` states.
- Derived in **OKLCH** for perceptually even lightness steps; verified with the checker
  before any ramp is committed to.

### API calls

None. No component in this spec talks to the backend.

### "Done"

Built, deployed to staging, and verified in a browser end-to-end — specifically,
`/design-preview` opened in all four modes and looked at, plus a walk through one dialog,
one form, one session card and the call lobby on staging.

## Module boundaries

`platform` owns this; it is cross-cutting by nature and touches no business module. No
backend module is involved, so `import-linter` is unaffected and no new events are
emitted.

The one boundary that matters here is the **surface boundary**, and this spec reinforces
the existing rule rather than changing it: *tokens are shared, components are not.*
`@kaleem/tokens` remains the only thing shared between the dashboard and marketing.

A consequence worth stating because it cuts against the scoping decision below:
**marketing consumes the token package and has no palette of its own, so replacing the
palette changes marketing's rendering automatically.** Excluding marketing from this spec
means no marketing *component* work. It does not mean marketing is unaffected. Its
`marketing-build` job must stay green and it inherits the new palette for free — which
is also how the launch-blocking inherited contrast failure gets closed.

## Out of scope

1. **Marketing components.** Owner decision. Marketing stays three files; it re-pins to
   the new token release and nothing else.
2. **A spacing scale.** Tailwind v4's `--spacing` multiplier already *is* the spacing
   scale and the codebase uses it consistently. Adding `--space-1..12` creates a second
   vocabulary no component speaks, and converting to it is exactly the repo-wide sweep
   D10 forbids. "No spacing tokens at all" reads like a gap in an audit; in a Tailwind v4
   codebase it is the correct state.
3. **Style Dictionary.** Emitting the `@theme inline` bridge, the `calc()`-derived radius
   scale and Tailwind's paired type form would all need custom formats — more code than
   the ~120-line emitter they would replace. See ADR-0041.
4. **Visual-regression snapshots.** An intentional palette replacement invalidates every
   baseline on day one and then levies a churn tax forever, on a solo developer, for a
   product with no pixel contract. `/design-preview` plus the D9 click-through covers
   this better and cheaper.
5. **Sweeping the 20 raw `<button>` elements.** Many are legitimate in-place icon
   controls, not `Button` variants. Audited opportunistically; logged in `ISSUES.md`.
6. **EN 301 549 clause 7 — captions and audio description for the live video lessons.**
   This is the one clause with real teeth for kaleem and it is genuinely substantial. It
   belongs to the call feature, needs its own spec, and is tracked in `ISSUES.md`.
   Adopting EN 301 549 in ADR-0040 without saying this plainly would be the failure mode.
7. **The pre-existing a11y defects already in `ISSUES.md`** — the Arabic reflow overflow
   on `/account` (1.4.10), the duplicate "Add child" accessible name, the double `<h1>`
   on the room route, the un-linked validation message in `StudentPreferencesCard`, the
   un-i18n'd zod messages. They are real and they stay logged. Fixing them here would be
   a refactoring spree (D10); several also predate this work and belong to their own
   modules.
8. **Promoting `--container-content` / `--container-narrow` / `--card-min`** into the
   package, despite `ISSUES.md` currently saying to. Content width is surface-specific —
   the dashboard's 88rem authed shell has nothing to do with marketing's page width, and
   one shared value forces a second name the moment they disagree. That ISSUES entry is
   amended rather than executed. `--text-display` *does* move, because it is typography
   and becomes a rung of the real type scale.

## Test plan

### Happy path

1. `node build.mjs --check` in `tokens` reproduces the committed CSS byte-for-byte.
2. The light and dark colour trees are structurally identical (every key present in
   both) — a real assertion replacing today's regex-scraped string comparison.
3. Every pair in the manifest meets its threshold, in both themes, including the
   composited overlay. Run in `tokens` as `node --test` and again in `dashboard` against
   the *installed* package.
4. `pnpm tsc --noEmit`, `pnpm lint`, `pnpm test:coverage` above the raised floors.
5. All 16 e2e specs pass **unchanged**.
6. `@axe-core/playwright` reports no violations on `/design-preview` in light/dark ×
   LTR/RTL.
7. `pnpm build` green in both dashboard and marketing.

### Edge cases

- The overlay token carries alpha and must be composited over each allowed backdrop
  before its ratio is computed. Getting this wrong produces a confidently-passing wrong
  number, so it is built in from day one rather than added later.
- A dialog migrated to the new primitive must keep its `role` and its accessible name.
  e2e selectors are role + accessible name (ADR-0027), so **a spec that needs editing is
  itself the signal that a regression happened** — the suite is the detector.
- RTL: the new `Dialog` must centre correctly in both directions without the
  `rtl:translate-x-1/2` escape hatch the six current dialogs use.
- `Meter` must preserve both existing roles. `meter` is correct for a mic level and
  `progressbar` for quota consumed; "unifying" them to one role would be a regression,
  not a fix. Only the visual recipe is shared.

### Failure cases that must pass

1. **Mutation-check the contrast gate.** Break one token value on purpose and watch the
   checker go red. Given that this project's previous contrast gate passed while testing
   nothing, a gate that has never been *seen* failing is not trusted.
2. Introduce a hardcoded `#ff0000` in a `.tsx` → the colour lint fails.
3. Introduce a `bg-black/40` → the colour lint fails. This matters separately from the
   hex case: the string contains no hex, and it is the exact pattern that produced the
   14 duplicated overlays.
4. Bump the `@kaleem/tokens` pin without the submodule pointer → the pin check fails.
5. Commit a `link:` override for local HMR → the pin check fails.
6. Remove a required accessible name from a migrated dialog → the relevant e2e spec
   fails.

### What this plan cannot prove, stated rather than implied

No Apple device exists in this project — no Mac, no iPhone, no iPad — and Playwright's
WebKit on Linux is not iOS Safari. **Nothing here verifies the palette or any primitive
on Safari or iOS.** This is the same D9 deviation recorded for C3e and is recorded again
in the week's journal rather than skipped.

Separately, the contrast gate proves that *declared* pairs are sound. It cannot detect an
*undeclared* pair — a component putting `text-muted-foreground` on `bg-primary` passes,
because nobody declared it. That gap is covered by the colour lint and the real-browser
axe run, and the limitation is stated in the test file rather than left implicit.

## Phase 1 outcome — the verified palette

**Closed 2026-09-12. 50 pairs asserted across both themes, 0 failures.** Derivation bench:
`assets/2026-09-12-palette-v2-bench.mjs` (`node …bench.mjs` to re-run, `… emit` for CSS,
`… ramps` for the ladders). The bench is the provenance, not the gate — `contrast.mjs` in
the `tokens` repo becomes the gate in phase 2.

**The hue family is kept** — emerald, gold, cream. Every *value* is new, the ramps and the
structure are new, but the identity survives. This was a deliberate narrowing of ADR-0040's
cost: a different hue family would have discarded the `brand/` logos, favicons and imagery,
which that ADR names as the largest unpriced cost of replacing rather than repairing.

Seven ramps on one shared lightness ladder (0.972 → 0.224), hue held constant down each,
chroma reduced per step until the colour is genuinely inside sRGB rather than clamped:
`emerald` 168° (brand), `green` 146° (success only), `gold` 88° (accent), `sand` 82° (warm
neutral), `ink` 170° (cool neutral), `red` 28°, `blue` 232°.

Three findings came out of the derivation, and two of them corrected the *manifest*, not
the palette:

1. **Success must not be the brand emerald.** A success alert in the exact colour of the
   primary CTA reads as an action, not an outcome. Hence a separate `green` ramp at 146°.
2. **A focus ring never abuts the control it rings.** The recipe
   `ring-2 ring-ring ring-offset-2 ring-offset-<surface>` puts a surface-coloured 2px gap
   between ring and component, so on both its edges the ring's neighbour is the *surface*.
   Asserting `ring` against `--primary` measured a pair that is never rendered. What
   2.4.11 actually requires is that the ring area differ ≥3:1 between focused and
   unfocused states — unfocused, that area **is** the surface. The manifest now tests the
   ring against every surface a focusable control sits on. **Follow-up:** the offset is
   hardcoded `ring-offset-background`, so a control on a card draws a faintly mismatched
   halo. Contrast passes; the seam is for the `focusRing` work.
3. **A modal's background fill is not a 1.4.11 requirement, and in dark mode cannot be
   one.** An earlier draft asserted the popover at ≥3:1 against the scrimmed page. That is
   unachievable in any dark theme — the page and the dialog are both dark, and a *lighter*
   scrim moves the page closer to the dialog, making it worse. SC 1.4.11 covers controls
   and graphics needed to understand content; the controls inside the dialog are covered
   by their own pairs. Reported as a design-quality note, not a gate.

Light `--overlay` is `#191C1B` at 55%; dark is `#000000` at 68%. In dark it dims the page
by only 1.16:1 — stated rather than hidden, because modality there is carried by the
dialog's border and elevation.

Full emitted values are in the bench; they graduate to `tokens/src/*.tokens.json` in
phase 2 rather than being transcribed here, so this spec does not become a 26th mirror of
the numbers — which is the failure this whole spec exists to end.

## Open questions

Resolved and remaining. Each is a decision, not a sweep.

1. ~~**`Button size="sm"` is 40px**~~ — **RESOLVED 2026-09-12: option (c).** Keep the 40px
   ink; expand the hit area to 44×44 with a pseudo-element. SC 2.5.8 measures the target,
   not the ink, so the dense variant survives in the schedule, availability and timezone
   tables while the touch guidance is met. Unblocks the touch-target gate and closes
   `STATE.md` next-action #3.
2. ~~**Does `--accent` gold stay banned as a text colour?**~~ — **RESOLVED 2026-09-12:
   yes, banned.** Surface and decoration only. Worth recording *why* it is a universal ban:
   in the v2 palette gold-as-text reaches 3.05:1 in light (fails 4.5) but **7.28:1 in
   dark** (passes comfortably). The ban is a light-mode constraint applied to both themes,
   because one token cannot be conditionally usable per theme. If that ever becomes
   intolerable the fix is a separate `--accent-text` token, not relaxing the ban.
3. **Select height** across the four implementations (h-9 / h-10 / h-11).
   Recommendation: `h-11`, matching `Input` and the existing primitive. Blocks P3 only.
4. **Card radius** — one value, or two (card vs control)? Recommendation: one, unless
   `/design-preview` surfaces a real case.
5. **Motion tokens: live or dead?** Recommendation: live, consumed by `Dialog` and
   `Skeleton`. If still unreferenced when that work lands, delete them in the same PR
   rather than leaving a third dead release.
6. The auth-heading convergence is a **visible design change** (1.5rem → 1.875rem across
   five routes), not a refactor. It needs the D9 click-through and should be called that
   in the journal.

---

## Outcome (closed 2026-09-12)

Both halves shipped. The palette was replaced and deployed (phases 0–5); the
primitive layer was consolidated in phase 7 across dashboard PRs #52–#61, and the
CI gates G2/G3 landed with it.

**What the consolidation found, which is the case for doing it at all.** Comparing
duplicate implementations surfaced four defects that no gate had caught, because
each gate proves something narrower than "the UI is right":

| Defect | Criterion | Measured |
| --- | --- | --- |
| Availability selects bordered with `--border`, the decorative hairline | 1.4.11 | 1.29:1 light / 1.75:1 dark (needs 3:1) |
| `Checkbox` target | 2.5.8 | 20×20 (needs 24×24) |
| One select at h-9 with no focus indicator | 2.4.11 | — |
| `Select` aligned `text-end`, which is LEFT under `dir=rtl` | — | Arabic text pushed off its reading edge |

The contrast gate could not have found the first: it proves *declared pairs*, and
nobody declares "hairline used as a form boundary". That limitation was written
into the spec from the start and is exactly what showed up.

**Three plan assumptions that measurement overturned**, recorded because the plan
was wrong in a useful way each time:

1. `CallControlButton`'s `bg-secondary/95` was expected to be a latent defect.
   Measured worst case **7.15:1** over white video — above AAA. Not changed.
2. A colour-lint allowlist was budgeted for. Phase 7 left the tree clean, so G2
   ships with **no allowlist**.
3. The `sm` hit-area expansion needed 3px, not the 2px the arithmetic suggested:
   a pseudo-element insets from the *padding* box.

**Restraint is part of the outcome.** Six things that look duplicated were left
separate on purpose, each with the reason written where someone will next be
tempted: `AlertDialog` vs `Dialog`, `meter` vs `progressbar`, live-status pulses
vs `Skeleton`, `CallControlButton`, the `AppShell` drawer, and `VideoTile`'s
video surfaces.

**Known gaps, tracked in `ISSUES.md` rather than silently closed:** EN 301 549
clause 7 (captions/audio description) is out of scope and unbuilt; `/availability`
overflows at 320px (SC 1.4.10, pre-existing); there is no `Sheet` primitive; and
`focusRing` has no `secondary` surface, which needs a token release.
