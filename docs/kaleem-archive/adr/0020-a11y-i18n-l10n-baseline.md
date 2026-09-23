---
number: 0020
title: Accessibility, i18n, and localization are a repo-wide baseline
status: accepted
date: 2026-06-13
---

## Context

kaleem teaches Islamic sciences to non-Arabic speakers worldwide. Students are global and
Latin-script; many teachers and admins are Arabic speakers; Arabic content (Quran, Tafsir)
is core to the product. Parents pay subscriptions and need to trust the interface.

Accessibility, internationalization, and localization are easy to treat as per-feature
"polish" that slips, then becomes prohibitively expensive to retrofit — physical `left`/
`right` CSS hardcoded everywhere, UI strings baked into components, color choices that fail
contrast in one theme. The design-system work (see
`docs/superpowers/specs/2026-06-13-design-system-visual-identity-design.md`) forces the
question now, because tokens and primitives are where these standards are either designed
in or permanently designed out. The user has stated, explicitly and repeatedly, that these
are a baseline rather than an option.

## Decision

**a11y, i18n, and localization are a project-wide baseline binding on every repo and
submodule** (`@kaleem/tokens`, `dashboard`, `marketing`, and all future submodules), not a
per-feature choice. Concretely:

- **Accessibility — WCAG 2.2 AA.** AA contrast verified on **both** light and dark themes
  (asserted in tests, not assumed). Semantic HTML and correct ARIA. Full keyboard
  operability with visible `:focus-visible`. Motion gated behind `prefers-reduced-motion`.
  Automated axe checks in component tests.
- **i18n.** No hardcoded UI strings anywhere; all UI text flows through a translation
  catalog. Locale is first-class and selectable.
- **localization.** Locale drives both language **and** text direction. Full RTL UI
  mirroring is supported from day one, implemented via logical CSS properties
  (`margin-inline`, `padding-inline`, `ps-/pe-`, `start/end`) — physical `left`/`right` is
  disallowed in layout. Dates and numbers localize per locale.

The Definition of Done (D9) is extended: a feature is not done unless its UI meets this
baseline (axe clean, AA in both themes, keyboard-navigable, no hardcoded strings,
RTL-correct).

## Alternatives considered

- **Treat a11y/i18n/RTL as later phases.** Cheapest now, but retrofitting RTL means
  revisiting every layout, and retrofitting i18n means re-extracting strings across the
  whole app. Rejected — the cost compounds and the audience needs it at launch.
- **Content-only RTL (LTR UI, Arabic only in content blocks).** Simpler, defensible given
  students are non-Arabic speakers. Rejected because teachers/admins are likely Arabic
  speakers and a bilingual mirror-able UI is core, not optional (see the design spec's RTL
  decision).
- **AA on light theme only, "good enough" on dark.** Rejected — both themes ship at launch
  (per the design spec), so both must be accessible; partial compliance is not compliance.

## Consequences

**Good**
- These properties are designed into the token layer and primitives once, cheaply, instead
  of retrofitted expensively.
- The product is usable by its actual audience (global learners, Arabic-speaking
  teachers/admins, users relying on assistive tech) from launch.
- Clear, testable acceptance criteria (axe, contrast assertions, RTL snapshots) rather than
  subjective judgement.

**Bad / costs**
- More up-front rigor: every primitive must be theme-aware, dir-agnostic, keyboard-
  accessible, and string-free; every screen is reviewed in light, dark, and RTL.
- CI/test surface grows (axe, contrast, RTL snapshots).
- Discipline tax on every feature — but that is the point; the baseline is non-negotiable.
