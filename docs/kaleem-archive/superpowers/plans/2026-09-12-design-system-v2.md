---
spec: 2026-09-12-design-system-v2-design.md
status: in-progress
---

## Steps

Grouped by phase. Each step is independently testable and sized at ≤2h. Phases 1–5 are
strictly ordered (the PR order is the safety mechanism and must not be varied); phase 7
steps are independent of each other except where noted.

### Phase 0 — Spec, ADRs, doc repair (meta repo)

1. [x] Write the spec (`docs/superpowers/specs/2026-09-12-design-system-v2-design.md`).
2. [x] Write this plan.
3. [x] ADR-0040 — replace the palette; adopt EN 301 549 with clause 7 named as out of
       scope. Amends ADR-0020.
4. [x] ADR-0041 — design tokens are DTCG JSON with a hand-written emitter; Style
       Dictionary rejected. Amends the 2026-06-13 visual-identity spec.
5. [x] Repair `docs/architecture/design-system.md`: the `/design-preview` claim at L62
       describes a route that does not exist — mark it planned, not present.
6. [x] `ISSUES.md`: amend the token-promotion entry (drop the `--container-*` clause,
       keep `--text-display`); add EN 301 549 clause 7 captions; add the raw-`<button>`
       audit; add the `/design-preview` doc-vs-reality finding.
7. [x] `STATE.md`: set the active spec and branch.
8. [x] PR → `master`. **This merge is a deploy** — docs-only, so `triage` classifies it
       `code == false` and every gate skips, but confirm that is what happened rather
       than assuming it.

### Phase 1 — Design the palette (no code)

9.  [x] Answer open questions 1 (`sm` height) and 2 (accent-as-text). Both gate later
        work; 2 gates the manifest. **Resolved 2026-09-12:** (1) keep the 40px ink and
        expand the hit area to 44px with a pseudo-element; (2) gold stays banned as text.
10. [x] Draft the primitive OKLCH ramps. Perceptually even lightness steps.
11. [x] Derive the light semantic set; check every intended pair by hand against 4.5 /
        3.0 **before** committing to the ramps.
12. [x] Derive the dark semantic set, same check.
13. [x] Review for 1.4.1 — every status conveyance has an icon or text, not colour alone.
14. [x] Verify focus-indicator contrast (2.4.11) in both themes. **Finding 2026-09-12:
        the premise of this step was wrong.** It assumed the ring must clear 3:1 against
        the component *and* the background. It does not abut the component at all — the
        `ring-offset-2` gap is painted in the surface colour, so on both edges the ring's
        neighbour is the surface. `ring` vs `--primary` is a pair nothing renders.
        Corrected to: ring vs every surface a focusable control sits on. Follow-up logged
        — the offset is hardcoded `ring-offset-background`, so a control on a card draws a
        mismatched halo (contrast passes; it is a visible seam).

### Phase 2 — `tokens` repo

15. [x] Add the repo's **first CI workflow**. It has no `.github/` at all, so
        `smoke.test.mjs` has never run automatically. Do this first: everything below is
        unverified until it exists.
16. [x] Transcribe the **current** tokens to DTCG JSON under `src/`.
17. [x] Write `build.mjs` and make it reproduce today's `tokens.css` and `theme.css`
        **byte-for-byte**. This separates "the emitter works" from "the palette changed"
        into two independently verifiable steps — do not skip it.
18. [x] Add `--check` mode (rebuild in memory, diff, exit 1). Wire into CI.
19. [x] Add the structural-parity assertion (light and dark key trees identical),
        replacing `smoke.test.mjs`'s regex scrape.
20. [x] Write `contrast.mjs` — a pure `(light, dark, pairs) → violations` function.
        Include alpha compositing from the start; the overlay token needs it and
        retrofitting it produces a confidently-passing wrong number.
21. [x] Write `pairs.tokens.json` from the palette designed in phase 1.
22. [x] Wire the contrast check into CI as `node --test`. **Mutation-check it**: break a
        value, watch it go red, restore. A gate never seen failing is not trusted.
23. [x] Swap in the v2 palette values. Now `--check` legitimately fails; regenerate.
24. [x] Add the type scale, per-theme elevation, `--overlay`, and the explicit
        `--spacing`. Add the DTCG `radius` group.
25. [x] Add the JSON files to `package.json` `exports` so the dashboard test can import
        them.
26. [x] Fix the version/tag drift: `package.json` says `0.1.0`, the consumed tag is
        `v0.1.1`. Set it to `0.2.0`.
27. [x] PR → `main`. Merge, tag `v0.2.0`, push the tag. **Deploys nothing** — no consumer
        has re-pinned.

### Phase 3 — Dashboard swap

28. [x] Re-pin `package.json` to `#v0.2.0`; regenerate the lockfile.
29. [x] **Delete `src/index.css:29-64` entirely** — the whole override block, not a trim.
        Four of the eight are shadows now fixed by per-theme elevation; the colour four
        were tuned against values that no longer exist, so keeping any of them is a
        silently-wrong value.
30. [x] Move `--text-display` into the package's type scale; **keep** `--container-*` and
        `--card-min` dashboard-local.
31. [x] Replace `a11y.test.tsx:64-115` with the derived check: import the colour trees
        and the manifest, resolve aliases, loop. **Zero hex literals, zero pair names.**
        Keep the `relLum`/`ratio` maths at L9-19 — that code is correct.
32. [x] Write the limits into that test file explicitly: it tests declared pairs not
        rendered pixels; it cannot detect an undeclared pair; jsdom axe cannot evaluate
        `color-contrast` at all.
33. [x] Build `/design-preview` — every `src/ui` export × variant × state.
34. [x] Add light/dark × LTR/RTL switching to the preview route.
35. [x] Broaden the jsdom axe sweep to run over the preview route.
36. [x] Add `@axe-core/playwright` against `/design-preview`, four modes. **This is the
        only check anywhere that evaluates contrast as actually rendered** — composited
        alpha, gradients, real cascade. It lands here, with the swap, not in phase 6.
37. [x] Fix visual fallout. Re-measure and raise the coverage floors.
38. [x] Open `/design-preview` in a real browser in all four modes and look at it. The
        swap is atomic — this is the review.
39. [x] PR → `main`. **Deploys nothing** — meta still points at the old commit.

### Phase 4 — Marketing

40. [x] Re-pin, regenerate the lockfile, `pnpm build`, eyeball the rendered page.
41. [x] Add `astro check` to the `marketing-build` job. Closes a real gap (marketing has
        a `tsconfig.json` and zero typechecking) but **catches nothing about the
        palette** — describe it accurately in the PR.
42. [x] PR → `main`. Deploys nothing.

### Phase 5 — The deploy

43. [ ] Meta PR bumping **all three submodule pointers in one PR** plus the docs. One PR
        so CI runs once against the complete state, staging never shows a split-brand,
        and rollback is one `git revert`.
44. [ ] Merge **between lessons** — a deploy drops every call in progress.
45. [ ] Staging walk: log in, one dialog, one form, one session card, the call lobby;
        both themes, both directions. Confirm marketing renders v2.
46. [ ] Run Lighthouse via `workflow_dispatch`; **raise the a11y floor** if it measured
        higher. `ISSUES.md` records the staging login page failing contrast at a11y 96
        with exactly this root cause — expect it to close.
47. [ ] Journal entry, `STATE.md`, close the launch-blocking `ISSUES.md` entry.

### Phase 6 — CI gates

48. [x] Colour lint: hex in `.tsx` **and** `bg-black/`-class utilities that contain no
        hex. Annotated allowlist for `button.tsx`'s legitimate `color-mix` hover recipe.
49. [x] Pin ↔ submodule consistency check. Catches the drift that produced the
        `0.1.0`/`v0.1.1` mismatch, a half-done pointer bump, and a committed `link:`.
50. [x] Both as **steps in `dashboard-lint`**, not new jobs — GitHub bills a one-minute
        floor per job, and steps need none of the `needs: triage` boilerplate nor changes
        to `record-verified-tree.needs` / `deploy-staging.needs`.
51. [x] Mutation-check both: introduce a violation of each, watch CI go red.

### Phase 7 — Primitives (one primitive + tests + migration per PR)

52. [x] **P1** `focusRing` in `src/ui/styles.ts`; migrate all 12 copies. Zero visual
        change. First, because P8 depends on it.
53. [x] **P2a** `Dialog` primitive, fully tested, using `bg-overlay`.
54. [x] **P2a** migrate three identity dialogs (`RemoveEmailDialog`, `SetPrimaryDialog`,
        `SetChildPasswordDialog`) — simplest, best-tested, no e2e dependency.
55. [x] **P2b** migrate the five e2e-covered dialogs. Preserve every `role` and
        accessible name; the e2e suite is the detector.
56. [x] **P2b** migrate the remaining six.
57. [x] **P3** converge the three rogue selects onto `ui/select.tsx` (after open question
        3). Keep it a native `<select>`.
58. [x] **P4** `Skeleton`; migrate four sites. Consume `--duration-*` to make the motion
        tokens live.
59. [x] **P5** converge five hand-rolled `Card` surfaces; delete `CardFooter` and
        `CardAction`. Deleting dead exported functions **raises** function coverage —
        bank that headroom here, before a PR that costs functions.
60. [x] **P6** `Meter`; migrate both sites **keeping both roles**. `meter` for a mic
        level, `progressbar` for quota consumed — both are correct.
61. [x] **P7** converge the five duplicated auth `<h1>`s onto the type scale. **Visible
        design change** — needs the D9 click-through. Leave the wordmark alone; it is
        explicitly exempt.
62. [x] **P8** `CallControlButton`: source `focusRing` and the shared size scale, map
        `TONE_CLASS` to tokens. **Not a merge into `Button`.**
63. [x] Touch-target sweep in the `e2e` job, **after open question 1**. Before that
        decision it goes red everywhere and teaches nothing.

## Risks

**A palette swap is atomic. There is no way to dual-run two palettes here.** `@theme
inline` binds every utility to `var(--color-*)` resolved at use site, so changing a value
repaints everything at once. The one apparently-real alternative — scoping `.palette-v2`
to a subtree — fails for a specific fatal reason: **every Radix overlay portals to
`document.body`**, so 14 dialogs plus dropdowns and toasts would render outside the scope
on the old palette. Stating this plainly is more useful than shipping a scheme that
half-works.

The safety comes from three other places instead:

1. **The pinned git tag *is* the dual-run.** `v0.2.0` exists and is live nowhere until a
   consumer re-pins. The release friction that `ISSUES.md` treats purely as a cost is the
   same property that gives unlimited iteration at zero exposure.
2. **`/design-preview`** makes an atomic swap reviewable in one screen. This is why it
   moved into phase 3 rather than being deferred.
3. **One revert.** A single meta PR means one `git revert` of one merge commit.

| Risk | Mitigation |
| --- | --- |
| **The palette is replaced and the only thing proving it is a pair list a human wrote.** The manifest eliminates *value* drift but not *coverage* gaps — an undeclared pair passes silently. **This is the largest single risk in the plan.** | Land the real-browser axe check (step 36) in phase 3 **with** the swap, not in phase 6. It is the only check that sees rendered contrast |
| A gate that has never been seen failing is not trusted — this project already shipped a contrast test that passed while testing nothing | Mutation-check steps 22 and 51 explicitly. Break it, watch it go red, restore |
| Deleting the override block hides a silent regression | It lands in the same PR as the contrast gate, the preview route and the browser axe check, so three independent things would have to fail together |
| The emitter's output does not match what Tailwind expects | Step 17 reproduces today's CSS byte-for-byte before any value changes |
| Meta pointer bump and `package.json` pin drift apart — they are **independent**, and the current `0.1.0`/`v0.1.1` mismatch is that drift already realised | Step 49's pin-consistency check. Also catches a committed `link:` HMR override |
| P2b touches 14 files including e2e-covered dialogs | e2e selectors are role + accessible name (ADR-0027), so a spec needing edits *is* the regression signal. Split the step further if it gets uncomfortable — there is no prize for one big PR |
| The colour lint surfaces a pile of pre-existing hits | Budget an annotated allowlist, **not** a compliance sweep (D10) |
| Coverage floor drops on migration-only PRs | P2a ships the primitive fully tested; P5 banks function headroom first. At 88.35 one function ≈ 0.18pp |
| The dashboard unit suite flakes ~1 run in 4 (jsdom Window creation), silently dropping a whole file | Known and logged. Re-run before concluding a failure is real — and before concluding a *pass* is real on a coverage-sensitive PR |
| The deploy drops live calls | Merge between lessons (step 44) |

**Fallback if phase 2 slips.** The mirrored contrast test can be killed without DTCG:
parse `@kaleem/tokens/tokens.css` at test time with a regex into per-block maps, layering
`dashboard/src/index.css` on top to test the *effective* value. Uglier, zero drift, and
**works today without touching the package** — so phase 3 can proceed alone if needed.

## Verification

**Per step.** Steps 15–27 are verified by the tokens repo's own CI once step 15 lands —
which is why it is first. Steps 28–39 by `pnpm tsc --noEmit`, `pnpm lint`,
`pnpm test:coverage` above the raised floors, all 16 e2e specs green, and axe clean on
the preview route in four modes. Steps 52–63 each by the full seven-gate run, with the
requirement that **e2e specs pass unchanged**.

**Per phase.**

- **Phase 2:** `node build.mjs --check` byte-identical; structural parity; every manifest
  pair green including the composited overlay; the mutation check seen going red.
- **Phase 3:** the four-mode browser look at `/design-preview`. The swap is atomic, so
  this *is* the review, not a formality.
- **Phase 5:** the staging walk in both themes and both directions, plus confirming
  marketing renders v2.

**Whole-plan acceptance.**

1. `grep -rn '#[0-9a-fA-F]\{6\}' dashboard/src --include=*.tsx` returns nothing.
2. `grep -rn 'bg-black/' dashboard/src` returns nothing.
3. `dashboard/src/index.css` contains no token-value override block.
4. `a11y.test.tsx` contains zero hex literals.
5. Deliberately breaking any token value turns `dashboard-lint` red.
6. Every `src/ui` export appears on `/design-preview` in four modes.
7. D9 walked: spec closed, ADRs written, staging verified in a browser, journal entry,
   `STATE.md` updated.

**What cannot be verified here, stated rather than implied.** No Apple device exists in
this project, and Playwright's WebKit on Linux is not iOS Safari. Nothing in this plan
verifies the palette or any primitive on Safari or iOS. Recorded as a D9 deviation in the
week's journal, as C3e was — not skipped.
