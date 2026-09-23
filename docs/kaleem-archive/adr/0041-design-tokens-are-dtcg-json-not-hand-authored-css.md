---
number: 0041
title: Design tokens are DTCG JSON with a hand-written emitter, not hand-authored CSS
status: accepted
date: 2026-09-12
amends: the 2026-06-13 design-system-visual-identity spec (token package format)
---

## Context

`@kaleem/tokens` ships three hand-authored CSS files: `tokens.css` (custom properties for
`:root` and `.dark`), `theme.css` (a Tailwind v4 `@theme inline` bridge), and an
`index.css` barrel. There is no build step, no JSON, and no schema. For a two-consumer
private package maintained by one developer, that was a reasonable starting point and it
has worked.

It stops working at exactly one point: **verification.**

The only machine-readable form of the palette is CSS text. So the contrast gate cannot
read the palette — it has to restate it. `dashboard/src/test/a11y.test.tsx:64-115`
hand-copies **26 hex literals** out of the token files, and the file's own comment at
L58-63 records what that cost:

> a drifted mirror silently tests nothing (the old gate asserted a dark-primary pair the
> dashboard had already overridden, so it passed while the rendered button went untested)

That is not a hypothetical. The gate reported green on a value that was not the rendered
value. The mirror is a workaround for the palette not being data, and it failed in the
precise way workarounds of that shape fail.

ADR-0040 replaces the palette outright and moves it into the package as the single source
of truth. Doing that on top of a 26-literal mirror would take the highest-risk file in the
repo and make it more load-bearing.

The package also has no CI whatsoever — no `.github/` directory — so `smoke.test.mjs` has
never run automatically, and what it does check is a regex scrape comparing `:root` and
`.dark` variable *names*, not values or structure.

## Decision

**Design tokens are authored as W3C DTCG JSON. A hand-written emitter generates the CSS
that consumers already import.**

```
tokens/
  src/*.tokens.json     # DTCG source of truth
  build.mjs             # emits tokens.css + theme.css; --check mode
  contrast.mjs          # pure (light, dark, pairs) → violations
  tokens.css theme.css  # EMITTED, committed, --check-verified
  .github/workflows/    # the package's first CI
```

**1. Adopt DTCG for one concrete reason, not for the usual ones.**

The usual justifications do not apply here: there is no Figma round-trip, no iOS or
Android target, two consumers, one developer. Adopting a standard for its own sake would
be ceremony.

The reason that does apply: **the contrast gate needs the palette to be data.** A JSON
source makes the palette an importable object that both the emitter and the checker
consume. That is what makes drift structurally impossible rather than merely discouraged —
the gate stops holding values, so it cannot hold stale ones. The entire value of this ADR
is that it enables ADR-0040's derived gate; the standard is the means.

**2. Reject Style Dictionary.**

Its value is the transform and format ecosystem for output targets this project does not
have. Producing kaleem's specific shapes — the `@theme inline` bridge, the
`calc()`-derived radius scale, the `:root`/`.dark` split, and Tailwind v4's paired
`--text-*--line-height` form — requires writing custom formats, which is **more code than
the ~120-line dependency-free emitter it would replace**, plus a dependency and its
upgrade surface. The DTCG source is the durable asset; the emitter is deliberately
disposable. If a third platform ever appears, swap it then.

**3. Commit the emitted CSS, and verify it with `--check`.**

Git-URL dependencies do not reliably run `prepare` across package managers, and consumers
`@import "@kaleem/tokens/tokens.css"` directly — the files must physically exist in the
tree at the tag. `node build.mjs --check` rebuilds into memory, diffs against the
committed files, and exits 1 on mismatch. This is the same pattern as `ruff format
--check .` in `ci.yml`: generated artifacts are committed and CI proves they are current.

**4. Build the emitter against the current CSS before changing any value.**

`build.mjs` must first reproduce today's `tokens.css` and `theme.css` **byte-for-byte**
from a DTCG transcription of the existing tokens. This separates "the emitter works" from
"the palette changed" into two independently verifiable steps. Changing both at once means
that when something renders wrong, there is no way to tell which caused it.

**5. Keep emitting the shadcn variable names.**

The emitted CSS variables stay `--background`, `--primary`, `--ring`, and so on. Every
primitive in `dashboard/src/ui/` depends on that contract — `tokens.css:1-4` says so —
and breaking it would turn a palette swap into a component rewrite. The DTCG keys are the
semantic names (`color.text.primary`, `color.surface.card`); the mapping to shadcn names
lives in `build.mjs`, in one place.

**6. Model themes as two files with identical key trees, and assert that.**

DTCG has no standardised theme or mode construct. Use `color.light.tokens.json` and
`color.dark.tokens.json` and have the build perform a **structural diff** — every key
present in both. This is what `smoke.test.mjs` was reaching for with a regex, upgraded
from string matching to a real assertion, and shorter.

**7. Give the package CI. Do it first.**

The repo has never had a workflow. Everything above is unverified until one exists, so it
is the first step of the implementation rather than a finishing touch. It runs
`build.mjs --check`, the structural-parity assertion, and the contrast checker as
`node --test`.

## Alternatives considered

- **Keep hand-authored CSS; fix the mirror by parsing the CSS at test time.** Genuinely
  viable: regex the custom properties out of `tokens.css` into per-block maps and loop.
  Zero drift, no package change, works today. Rejected as the *primary* choice because
  the parser becomes a second, fragile definition of the token format — it has to know
  about `:root` versus `.dark`, comments, `calc()`, and any future syntax. **Retained as
  the documented fallback** if the DTCG work slips: it can ship alone and still kill the
  mirror.
- **Style Dictionary.** Rejected above — custom formats would exceed the emitter they
  replace.
- **A TypeScript module as the source** (`export const tokens = {...}`), emitting CSS from
  it. Simpler than JSON in some ways and type-checked for free. Rejected because the
  `tokens` repo has no TypeScript toolchain and adding one to a three-file CSS package to
  hold a colour map is a worse trade than a JSON file plus a schema-free emitter. It also
  gives up DTCG's alias syntax, which is what keeps the primitive ramps and the semantic
  layer from being restated.
- **Publish to a registry instead of pinning a git tag**, to make releases cheap. Tempting,
  since release friction is the stated cause of the dashboard override block. Rejected
  here: the friction turns out to be the same property as the safety — a pinned tag is
  live nowhere until a consumer re-pins, which is what lets an entire palette replacement
  be built and reviewed at zero exposure (ADR-0040). Revisit if release cadence rises.
- **Generate the contrast pairs automatically** from every foreground × every surface
  combination, instead of a hand-written manifest. Rejected: the cross product asserts
  pairs the UI never paints, so it either fails on combinations nobody cares about or
  forces an exclusion list — which is the hand-written manifest again, inverted and
  harder to read.

## Consequences

**Good**

- The contrast gate stops restating the palette, so it stops being able to restate it
  wrongly. The specific failure recorded in `a11y.test.tsx:58-63` cannot recur.
- The same data drives the emitter, the gate in `tokens`, and the gate in `dashboard`.
  Three consumers, one definition, no synchronisation step between them.
- Marketing gets contrast protection for the first time. It has no test suite at all, so
  the package-side check is the only thing that will ever guard it.
- The package gets CI at all, which is a larger improvement than the format change.
- Primitive ramps and semantic aliases separate cleanly via DTCG's reference syntax, so
  "what is the emerald ramp" and "what is a primary button" stop being the same edit.

**Bad / costs**

- The source of truth is no longer the file consumers import. Reading `tokens.css` to
  learn a value still works, but *editing* it is now wrong and silently reverted by
  `--check`. That is a footgun for anyone — human or agent — who opens the obvious file.
  The emitted files must carry a generated-file header saying so.
- A build step in a package that had none. It is ~120 lines with no dependencies, but it
  is a thing that can break, and it breaks between "I edited a token" and "the CSS is
  correct".
- DTCG has no theme construct, so the two-file convention is a local invention. It is
  asserted by the build rather than by the standard, and a reader coming from another
  DTCG codebase will not recognise it.
- Transcribing the existing tokens to JSON is uninteresting work that produces no visible
  change, and step 17's byte-for-byte requirement makes it fussier still. It is the right
  order, but it will feel like a detour.
- The JSON files must be added to `package.json` `exports` for the dashboard test to
  import them, which widens the package's public surface beyond the three CSS files it
  has shipped until now.
