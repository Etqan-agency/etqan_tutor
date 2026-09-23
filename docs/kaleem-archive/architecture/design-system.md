# Design system architecture

The visual layer shared by the React dashboard and the Astro marketing site. Brand
direction is **Serene Scholar** (deep emerald + warm gold on cream; scholarly, calm,
trustworthy). See the spec `docs/superpowers/specs/2026-06-13-design-system-visual-identity-design.md`
and the binding standard ADR-0020 (a11y WCAG 2.2 AA both themes, i18n, full RTL).

## The shared layer: `@kaleem/tokens`

A standalone repo (`kaleem-lms/tokens`), added here as the 5th submodule at `tokens/`.
It is the single source of truth for the brand.

**Since v0.2.0 the source of truth is DTCG JSON in `tokens/src/`, and the CSS files
below are GENERATED** (ADR-0041). Edit `src/*.tokens.json` and run `node build.mjs`;
`node build.mjs --check` fails CI if the committed CSS has drifted, so a hand-edit
of `tokens.css` is silently reverted. The package ships:

- `tokens.css` — semantic design tokens as CSS custom properties, defined for `:root`
  (light) and `.dark` (dark). Names follow **shadcn's CSS-variable contract**
  (`--background`, `--foreground`, `--primary`, `--ring`, `--destructive`, …) so
  shadcn primitives theme automatically, plus kaleem extras (`--success`/`--warning`/
  `--info`, `--font-*`, `--shadow-*`, `--duration-*`, `--ease-standard`).
- `theme.css` — a Tailwind v4 `@theme inline { … }` preset mapping `--color-*` →
  `var(--*)` so utilities (`bg-primary`, `text-muted-foreground`, `font-display`,
  `rounded-lg`) resolve to the tokens. `inline` means utilities read the live variable,
  so light/dark swapping just works.
- `index.css` — imports both, for single-import consumers.

### Consuming and bumping

Both surfaces install it from its git URL (no registry):

    pnpm add "@kaleem/tokens@git+ssh://git@github.com/kaleem-lms/tokens.git#vX.Y.Z"

and import in their Tailwind v4 entry CSS:

    @import "tailwindcss";
    @import "@kaleem/tokens/tokens.css";
    @import "@kaleem/tokens/theme.css";

To change the brand: edit the tokens repo, commit, tag `vX.Y.Z`, push the tag; then bump
the dependency ref in each consumer and reinstall. Current release: **v0.2.2**.

### Rule: tokens are shared, components are not

The token package is the *only* thing shared between surfaces. Components diverge: the
dashboard uses shadcn-based primitives in `src/ui/`; marketing uses bespoke Astro
sections. Layout density and composition differ per surface; the brand stays identical
because both pull the same tokens.

## Dashboard specifics

- **`src/ui/` is the owned primitive layer** over shadcn. Components are added via shadcn,
  constrained to kaleem `cva` variants, and re-exported through `src/ui/index.ts`.
  **Features import UI only from `@/ui`** — never raw shadcn or `@kaleem/tokens` internals.
  `cn()` (`@/lib/cn`) = clsx + tailwind-merge. Slot is from the unified `radix-ui` package
  (`Slot.Root`). Icons: `lucide-react`.
- **Theming**: `data-theme` is not used; dark mode is the `.dark` class on `<html>`,
  toggled by `ThemeProvider` (`@/lib/theme`), which honors `prefers-color-scheme`, persists
  to `localStorage["kaleem-theme"]`, and is mirrored by a no-flash inline script in
  `index.html`. `@custom-variant dark` in `src/index.css` binds Tailwind's `dark:` to it.
- **i18n + RTL**: `@/lib/i18n` (react-i18next, `en`+`ar`, no hardcoded UI strings).
  `DirectionProvider` (`@/lib/direction`) sets `<html dir>` + `lang` from the locale and
  persists `localStorage["kaleem-locale"]`. Full RTL UI is supported; layout relies on
  logical/`rtl:` classes, not physical left/right.
- **Verification gate** — three checks, and they prove DIFFERENT things. Conflating
  them is how the previous gate rotted:

  | Check | Where | Proves | Cannot prove |
  | --- | --- | --- | --- |
  | Token contrast | `tokens` CI + `src/test/a11y.test.tsx` | every declared pair meets WCAG 2.2 AA / 1.4.11 / 2.4.11 in both themes, body text at AAA | rendered pixels; undeclared pairs |
  | jsdom axe | `src/routes/design-preview.test.tsx` | roles, names, labels, ARIA across every `@/ui` export in 4 modes | **colour contrast** — axe disables that rule without a renderer |
  | Real-browser axe | `e2e/design-preview.spec.ts` | contrast **as actually rendered**: composited alpha, gradients, real cascade | Safari/iOS — no Apple device exists in this project |

  The contrast checks hold **no colour values**. They read `tokens/src/*.tokens.json`
  and the pairing manifest `tokens/src/contrast-pairs.json`. Until 2026-09-12 the
  dashboard's gate hand-mirrored 26 hex literals and a drift had already made it pass
  while testing nothing — see ADR-0041.

  **A new colour pair must be declared in `contrast-pairs.json`, or nothing verifies
  it.** The gate proves declared pairs are sound; it cannot know about a pair nobody
  listed. That gap is what the real-browser run covers — it found a live AA failure in
  `Alert variant="destructive"` (an undeclared, alpha-composited pair) on its first run.

- **`/design-preview`** renders every `@/ui` export x variant x state in all four
  combinations of theme x direction **at once**. A palette change is atomic — `@theme
  inline` resolves at use site, and a scoped second palette cannot work because Radix
  portals to `document.body` — so seeing the whole surface together is the only way to
  review one. It is the target of both axe sweeps.

### The primitive layer after phase 7

`src/ui/` is the canonical set. Phase 7 (2026-09-12) removed the reasons features had
to hand-roll:

| Primitive | Replaced | The decision worth remembering |
| --- | --- | --- |
| `focusRing(surface)` | 14 copies in 5 forms | The surface is a **parameter**. `ring-offset-2` paints a gap in the *offset* colour, so the offset must be the surface the control sits on — a constant would silently break the one control inside a popover. |
| `Dialog` + `AlertDialog` | 13 files, 2 centring recipes | **Two flavours, not one.** `alertdialog` interrupts for a decision and Radix refuses outside-dismissal for it. A grid positioner replaced transform-centring: RTL is free, the panel can animate, and a too-tall panel scrolls instead of clipping at both ends (1.4.10). |
| `Select` | 4 impls at 3 heights | Stays a **native `<select>`** (ARIA in HTML). Density is a caller's choice; the 44px height and the `--input` boundary are not. |
| `Skeleton` | 3 hand-rolled blocks | Always `aria-hidden` — it announces nothing. The loading announcement is a **separate** `sr-only` `Spinner`. Not every pulse is a skeleton: `StatusChip`'s dot and `WaitingForPeer`'s avatar are live-status affordances on loaded content. |
| `Card` (+ `as`) | 4 hand-rolled surfaces | **One radius, local density.** `as` exists because a session row must be an `<li>`. `CardFooter`/`CardAction` deleted — zero call sites. |
| `Meter` | 2 impls | **Both roles kept.** `progressbar` = a task completing; `meter` = a measurement. `role` is required with no default. |
| `PageHeader` | 5 auth headings | Its `<header>` is *not* a second banner: HTML-AAM scopes `banner` to headers outside `main`. Verified in Chromium; jsdom reports it wrongly. |

**Not folded in, deliberately.** `CallControlButton` keeps its own component: round
controls in a round bar, 48px for one-handed use, and `tone` ≠ `variant` because
`destructive` once coloured both "camera off" and "leave lesson". Those came from
real-device feedback. Its `bg-secondary/95` was **measured** before being kept — worst
case 7.15:1 over white video, above AAA — so the alpha is not a defect.

### Target size (SC 2.5.8)

The criterion measures the **target** — the region that accepts a pointer — not the ink.
Two controls deliberately paint smaller than they accept, via a pseudo-element with
symmetric negative insets (which mirror under RTL for free):

| Control | Ink | Target |
| --- | --- | --- |
| `Button size="sm"` | 40px | 44px |
| `Checkbox` | 20px | 24px |

⚠ A pseudo-element insets from the **padding** box. `Checkbox` is a border-box 20px with
a 1px border, so `-inset-0.5` yields a 22px target, not 24 — it needs `-inset-[3px]`.
This is why the gate hit-tests rather than measuring geometry.

**SC 2.5.8's `inline` exception is implemented, not ignored.** The criterion exempts a
target "in a sentence, or whose size is otherwise constrained by the line-height of
non-target text" — detected structurally (inline-level, with non-target text in the parent).
It does **not** cover a link that is the sole content of its paragraph: nothing constrains
that one, so it must be enlarged. Those use `inlineTapTarget` (19px ink → 25px target).

`e2e/touch-targets.spec.ts` sweeps every enabled control on `/design-preview` at desktop
and phone widths using `elementFromPoint` — **`boundingBox()` returns the painted box and
cannot see a pseudo-element at all**, so a geometry-based gate would fail both controls
while they are correct. It also sweeps the four real auth routes, which is where the
standalone-link failures were found; `/design-preview` renders primitives, not pages, and
has no inline links at all. The gate is 24×24 (what WCAG 2.2 AA requires); 44×44 is the
project preference and is met by everything not deliberately dense. A second test asserts
the dense controls accept *more* than they paint, so deleting the expansion cannot pass.

### Color-usage guardrails

- **A SURFACE colour is not a text colour.** `--primary` is the filled emerald behind a
  button; painted as text it measures **4.29:1 on `--card`** and 3.14:1 on `--secondary` in
  dark, under 1.4.3's 4.5. That shipped on every auth page. Use **`--primary-text`**
  (`text-primary-text`) for emerald text — v0.2.2, chosen to clear 4.5:1 on background, card,
  popover, secondary and muted in both themes. Light is unchanged: it is the same emerald.700
  `--primary` already had there. `scripts/check-colors.mjs` rejects the surface colours used
  as text, with the wordmark's decorative "." annotated as the one exemption.

- **`--accent` (gold) is a surface/decoration color, not a text color.** In v2 it measures
  **3.05:1 in light** (needs 4.5) and **7.28:1 in dark**. The ban is a light-mode constraint
  applied to BOTH themes, because one token cannot be conditionally usable per theme; if that
  ever becomes intolerable the fix is a separate `--accent-text` token, not relaxing the ban. Use `text-accent` only for decorative marks (e.g.
  the brand "." in the wordmark) or paired with `--accent-foreground` *on* an accent surface.
  Never use it for body copy, labels, links, or any meaningful text. For "highlight" text that
  must stay readable, use `--primary` (emerald) or `--foreground`.
- **Functional color is never the only signal.** Status meaning (error/success/info) must be
  backed by an icon or text, not color alone — e.g. toast variants carry a leading status icon,
  and form errors render text, not just a red border (WCAG color-not-only).
- **Interactive controls meet the 44px touch-target minimum** by default (`Button`/`Input` are
  `h-11`; icon buttons `h-11 w-11`). `sm` keeps a 40px ink height with the hit area expanded
  to 44x44 by a pseudo-element — SC 2.5.8 measures the target, not the ink, so dense tables
  keep their density without failing the guidance (ADR-0040 decision, 2026-09-12).

## CI: fetching the private token package

All CI is centralized in the meta repo's `.github/workflows/ci.yml` (the submodule repos
have no workflows). `@kaleem/tokens` is a private git dependency, so:

- **Runner install jobs** (`dashboard-lint`, `dashboard-build`, `marketing-build`)
  configure `git insteadOf` with `secrets.TOKENS_REPO_TOKEN` before `pnpm install`.
- **Image builds** (`deploy-staging`) pass the token to the Docker build as a **BuildKit
  secret** (`--secret id=tokens_token,env=TOKENS_REPO_TOKEN`); the Dockerfiles add `git`
  to the `node:22-alpine` build stage and use the secret for install only — the token is
  never persisted in a committed layer.

`TOKENS_REPO_TOKEN` (read access to `kaleem-lms/tokens`) must exist as a secret on the
**meta repo** (or org-level). CI runs on PRs to / pushes on `master`/`main`. A **merge to
the meta trunk is the staging deploy** — there is no `develop` branch and no promotion
step (ADR-0028).

**The `tokens` repo has its own CI as of v0.2.0** (ADR-0041): `build.mjs --check`, the
contrast gate, unit tests, and a mutation step that breaks a token value on purpose and
fails if the gate stays green. `smoke.test.mjs` is gone — it scraped CSS with a regex and
was superseded by real structural parity between the light and dark token trees.

## What each a11y gate cannot see

Four gates run, and every real failure so far slipped through at least three of them. The
useful question is not "is it green" but "which gate could possibly have caught this".

| Gate | Sees | Blind to |
| --- | --- | --- |
| Token contrast (`tokens` CI + `a11y.test.tsx`) | every **declared** pair, both themes | a pair nobody declared — how `--primary`-as-text shipped at 4.29:1 |
| jsdom axe (`design-preview.test.tsx`) | roles, names, labels, ARIA | **colour contrast** (axe disables it without a renderer); also maps `<header>` in `<main>` to `banner`, which real browsers do not |
| Browser axe (`design-preview.spec.ts`, `identity.spec.ts`) | contrast **as rendered**, composited alpha, real cascade | anything not on a swept route — the preview renders primitives, not pages |
| Lighthouse (nightly) | a weighted subset, **default theme only** | dark mode entirely. It scored 1.00 on pages with a live 1.4.3 dark failure |

**The pattern:** a gate proves the thing it measures, and every one of them is narrower than
"the UI is accessible". Adding a route to a sweep is usually worth more than tightening a
threshold.
