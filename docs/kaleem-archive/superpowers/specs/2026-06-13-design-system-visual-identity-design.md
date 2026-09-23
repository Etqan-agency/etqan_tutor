---
name: design-system-visual-identity
phase: A
modules: [platform]
status: shipped
created: 2026-06-13
closed: 2026-06-13
---

## Goal

Establish kaleem's design system and visual identity before any dashboard UI is built.
This is the foundation the identity frontend slice (and every feature after it) renders
on top of. It delivers a shared brand layer — design tokens, typography, theming, and
RTL/localization plumbing — plus the dashboard's `src/ui/` primitive layer (shadcn-based),
scoped to exactly what the next build needs.

The brand direction is **Serene Scholar**: deep emerald + warm gold on cream, a
scholarly-but-modern tone that reads as trustworthy to parents, calm and serious to
students and teachers, and quietly rooted in Islamic tradition without being literal.
Typography is **Scholarly Editorial**: Fraunces (wordmark + headings) + Inter (body/UI)
+ IBM Plex Sans Arabic (Arabic UI), with a dedicated naskh reserved for Quranic text.

Two surfaces must feel like one brand — the React dashboard (the app) and the Astro
marketing site — without sharing component code. The mechanism is a standalone
`@kaleem/tokens` package consumed by both.

## Cross-cutting standard: a11y, i18n, localization (repo-wide)

**Every project and submodule must meet global accessibility, internationalization, and
localization standards — this is a baseline, not a feature.** It binds `@kaleem/tokens`,
the dashboard, marketing, and all future submodules. Concretely:

- **a11y** — WCAG 2.2 AA. AA contrast on **both** light and dark themes (verified, not
  assumed). Semantic HTML, correct ARIA, full keyboard operability, visible focus
  (`:focus-visible`), respect for `prefers-reduced-motion`. Automated axe checks in
  component tests.
- **i18n** — no hardcoded UI strings anywhere; all UI text flows through a translation
  catalog. Locale is first-class and selectable.
- **localization** — locale drives both language **and** text direction. Full RTL UI
  mirroring is supported from day one (see §4). Dates/numbers localize per locale.

This standard is ratified project-wide in **ADR-0020** (a11y + i18n + localization are a
repo-wide baseline), so it binds every repo and submodule, not just this spec.

## User flow

Not a user-facing feature. The "users" are the engineer/agent building UI and, indirectly,
every end user who benefits from a consistent, accessible, localized interface. The
validating artifact is the login screen rendered identically from shared primitives in
three modes — light/LTR/English, dark/LTR/English, RTL/Arabic — proving tokens + type +
theming + direction all compose. (Mockup produced during brainstorming; reproduced for
real as the verification gate.)

## Architecture — the shared layer

A new **`@kaleem/tokens`** repository, added as the **5th git submodule** alongside
`backend`, `dashboard`, `marketing`, `infra`. It is the single source of truth for the
brand and ships:

- `tokens.css` — semantic design tokens as CSS custom properties, defined for `:root`
  (light) and `[data-theme="dark"]`.
- A **Tailwind v4 `@theme` preset** so utilities (`bg-primary`, `text-muted-fg`,
  `rounded-lg`, `font-display`) resolve to those custom properties.
- `@font-face` declarations + the type scale.
- The a11y/i18n baseline notes that consumers must honor.

Both surfaces install it **from its git URL** (no npm registry). A version bump
propagates the brand to both. Tailwind v4's CSS-first `@theme` is the shared mechanism
because both the dashboard (Tailwind v4, confirmed installed) and Astro marketing can
consume the same preset.

**Shares** (via the package): color, typography, spacing, radius, shadow, motion tokens;
the logo/wordmark; the a11y/i18n baseline.
**Diverges** (per surface): components — shadcn-based primitives in the dashboard vs.
bespoke expressive Astro sections in marketing; layout density; page composition; motion
intensity. **The rule: tokens are shared, components are not.**

## Design tokens

Semantic naming (not raw color names) so themes swap cleanly. Concrete starting values —
refine during implementation, but these are the intended direction:

### Color (light → dark)

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `primary` | `#0E5C4F` | `#4FB89F` | brand actions, emphasis |
| `primary-hover` | `#0B4A40` | `#3AA08C` | hover/active |
| `accent` | `#C9A227` | `#D9B43C` | gold highlights, sparingly |
| `bg` | `#FAF7F0` | `#0E1715` | page background |
| `surface` | `#FFFFFF` | `#16211D` | cards, panels |
| `surface-muted` | `#EFE9DB` | `#1E2B27` | subtle fills |
| `border` | `#E0D9C8` | `#2A3A34` | dividers, input borders |
| `fg` | `#16211D` | `#ECEFEC` | primary text |
| `muted-fg` | `#62736C` | `#9DB0A8` | secondary text (light darkened from #6B7A74 for WCAG AA) |
| `success` | `#127D6B` | `#3AA08C` | positive status |
| `warning` | `#C98A2B` | `#D9B43C` | caution |
| `danger` | `#C0432E` | `#E0735B` | errors, destructive |
| `info` | `#2F6F8F` | `#5AA9C9` | informational |

Plus full ramps (50–900) for `primary` and a warm neutral scale. All foreground/background
pairings must pass WCAG AA in both themes.

### Typography

- `--font-display`: **Fraunces** (wordmark, headings)
- `--font-sans`: **Inter** (body, UI)
- `--font-arabic`: **IBM Plex Sans Arabic** (Arabic UI text)
- `--font-quran`: **reserved** — a dedicated naskh for ayah rendering (value deferred;
  candidates: Amiri Quran, Noto Naskh Arabic, KFGQPC). Token slot exists now.
- Type scale (modular ~1.2): `xs 12 · sm 14 · base 16 · lg 18 · xl 20 · 2xl 24 · 3xl 30 ·
  4xl 36 · 5xl 48` (px, expressed in rem). Weights 400/500/600/700. Display sizes carry
  tighter line-height + tracking; body uses 1.6 line-height.

### Spacing / radius / shadow / motion

- **Spacing** — 4px base scale (Tailwind default retained).
- **Radius** — `sm 6 · md 8 (default) · lg 12 · xl 16 · full 9999`.
- **Shadow** — warm green-tinted, low-opacity `sm / md / lg` (e.g. `rgba(14,92,79,.06–.10)`).
- **Motion** — duration (`fast 120ms · base 200ms · slow 320ms`) + easing tokens; all
  motion gated behind `prefers-reduced-motion`.

## Theming — light + dark, both shipping at launch

- Tokens authored as semantic light/dark pairs from day one.
- Theme is set by `data-theme` on `<html>` (`light` | `dark`).
- A `ThemeProvider` honors `prefers-color-scheme` by default and persists an explicit
  user choice to `localStorage`; no flash-of-wrong-theme on load.
- Both themes ship and are QA'd; every new screen is reviewed in both.
- Marketing site may remain light-only (it consumes the same tokens regardless).

## RTL + localization — full UI mirroring from day one

- `dir` on `<html>` is driven by the active locale.
- **All layout CSS uses logical properties** (`margin-inline`, `padding-inline`,
  `ps-/pe-`, `start/end`, `inset-inline`). No physical `left`/`right` in layout.
- Primitives are direction-agnostic; direction-implying icons (chevrons, arrows) flip
  under `[dir="rtl"]`.
- i18n: a lightweight catalog (library chosen in the plan — `react-i18next` likely).
  **Zero hardcoded UI strings.** The locale switch flips both language and direction.
- Arabic *content* blocks (Quran, Tafsir) carry their own `dir="rtl"` + Arabic/naskh font
  regardless of the surrounding UI locale.
- This spec delivers RTL-capable primitives + the dir/theme switches and a seed locale
  setup; full translation catalogs are populated as features land.

## shadcn + the `src/ui/` primitives layer

- shadcn is configured against our tokens so generated components inherit the theme
  (Tailwind v4 + CSS variables mode).
- `src/ui/` is our **owned wrapper layer**: components are copied in via shadcn, then
  their variants are constrained to our `cva` definitions and re-exported through
  `src/ui/index.ts`.
- **Features import only from `@/ui`, never raw shadcn.** This is the boundary.
- Conventions: `cn()` = `clsx` + `tailwind-merge` (both already installed); `cva` for
  variants; every primitive is theme-aware, dir-agnostic, keyboard-accessible, and
  string-free (labels passed in).

### Primitives delivered in this spec (exactly the identity slice's needs)

`Button`, `Input`, `Label`, `Field` (label + control + error wiring) / `FormError`,
`Card`, `Alert`, `Spinner` — plus an **auth layout shell** and the **theme toggle** and
**direction/locale toggle** controls. Nothing speculative.

## Marketing (Astro)

Wired to consume `@kaleem/tokens` (Tailwind preset + `@font-face`) so it is visually
identical in brand. **No marketing pages are built in this spec** — the deliverable is
that the token package compiles and applies correctly in the Astro build, proving the
shared layer works across both build systems. Expressive marketing page work is a
separate future spec.

## Module boundaries

Cross-cutting `platform`/frontend-infra; no backend module is touched. No new backend
events, no data model. The only structural change to the meta repo is adding the
`@kaleem/tokens` submodule pointer. Boundary rule introduced: dashboard features import
UI only from `@/ui`, never from shadcn or `@kaleem/tokens` internals directly.

## Out of scope

- The identity screens themselves (login/register/verify/me) — the **next** spec; this
  one only makes them buildable and provides the validating mockup-made-real.
- Marketing pages/content.
- The final Quran naskh font choice (token slot reserved, value deferred).
- Full translation catalogs (seed/scaffold only; populated per feature).
- Feature-specific components (Dialog, Dropdown, Tabs, Table, Toast, Select, Avatar,
  Badge, …) — added when a feature first needs them, not speculatively.

## Test plan

**Happy path**
- `@kaleem/tokens` builds; CSS variables resolve; Tailwind preset compiles in both the
  dashboard (Vite) and marketing (Astro) builds.
- Each primitive renders with default + each `cva` variant.
- The three-mode login screen (light/LTR, dark/LTR, RTL/Arabic) renders correctly from
  shared primitives, in the browser.

**a11y / theming / RTL (must pass)**
- Automated axe checks per primitive — zero violations.
- AA contrast assertions on key fg/bg pairings in **both** themes.
- Keyboard operability + visible `:focus-visible` on all interactive primitives.
- Snapshot/visual check of the primitive set under `dir="rtl"` — layout mirrors, no
  physical-direction leakage.
- Theme toggle persists across reload with no flash-of-wrong-theme.

**Failure / edge**
- `Field`/`FormError` render and announce errors (aria-describedby / role wiring).
- `prefers-reduced-motion` disables motion tokens.

**Definition of Done (D9)** — tokens package + primitives built and unit/a11y-tested;
import-linter/boundary conventions documented; light+dark+RTL verified in the browser;
deployed to staging via the existing dashboard pipeline; `docs/architecture/` design-system
note added; journal entry; `STATE.md` updated.

## Open questions

- **Quran naskh font** — defer (token slot reserved). Decide when first Quran-rendering
  feature is specced. Not blocking.
- **i18n library** — `react-i18next` vs. a lighter alternative. Resolve in the
  implementation plan; not architecturally blocking.
- **`@kaleem/tokens` repo bootstrapping** — new GitHub repo under the org, added as a
  submodule; follows the same `feat → main` git-flow as other submodules. Mechanical.
- **a11y/i18n/localization ADR** — should be written so the standard is binding repo-wide.
