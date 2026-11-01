# Dashboard: final regression, round 3 (Agent 3, 2026-11-01)

Run inside the `dashboard` container on branch `feat/premium-dashboard-ui`, against the working tree with the owner's uncommitted changes. Nothing was committed.

## Result: all green after the fixes

| Check | First run | After the fixes | Evidence |
|---|---|---|---|
| `pnpm exec tsc --noEmit` | 1 error (TS2873) | 0 errors | `dashboard-tsc.txt` |
| `pnpm exec biome check` | 12 errors, 7 warnings, 4 infos | 0 errors, 7 warnings, 4 infos | `dashboard-biome.txt`, `dashboard-biome-after.txt` |
| `vitest run --maxWorkers=3` | 2 failed / 4384 tests (495 files) | 4384 passed / 495 files | `dashboard-vitest.txt`, `dashboard-vitest-after.txt` |
| Targeted rerun (affected tests + tsc + biome) | | 213/213 passed, rc=0 | `dashboard-rerun.txt` |

There were no flakes: both vitest failures were deterministic and both still failed when run alone.

## Fixes

1. **tsc TS2873** in `src/features/billing/qa-m08-r3.test.tsx:295`.
   - Cause: `{"" || null}` is a constant expression, so tsc flags it as "always falsy".
   - Fix: the cell value is now a `string` variable (`String("")`).
   - The ETQAN-QA-1188 check is unchanged: the empty cell still renders no child nodes.
2. **biome: 12 errors, all formatting or import order.** They were in files the owner or round 3 had changed:
   - `BidiText.tsx`
   - `AcademySettingsForm.test.tsx`
   - `RoleEditor.test.tsx`
   - `ConversationList.tsx`
   - `StudentLevelsList.test.tsx`
   - `ReturnPage.test.tsx`
   - `BroadcastDetail.test.tsx`
   - `NotificationLogPage.tsx`
   - `ReportActions.test.tsx`
   - `BrandingForm.test.tsx`
   - `VideosManager.test.tsx`
   - `website/index.ts`

   They were fixed with biome's safe `--write` on those 12 files only. The changes are whitespace and import/export order, with no change in behaviour.

   The remaining 7 warnings and 4 infos are not errors:
   - `index.css` `!important` and specificity;
   - `main.tsx` non-null assertion;
   - `PermissionGate` optional chain;
   - `TrialFromInquiry` void union;
   - two useless fragments;
   - one `useTemplate`;
   - the biome.json schema version.
3. **`src/routes/design-preview.test.tsx` "covers every @/ui export" failed.** This was a real gap:
   - Round 3 added `BackToSiteLink` (QA-1615), `SearchInput` (QA-1039) and `Star`/`StarRow` (QA-1318) to `@/ui`, but not to the preview page. So they were never reviewed in the preview or axe-scanned.
   - It also added 14 class-string recipes to `@/ui`. The test didn't list them as non-visual: `amountRows`, `detailRows`, `formGrid`, `listToolbar`, `pageAction`, `phoneCardLead`, `phoneCardsFrame`, `segmentedTab(s)`, `tableFrame`, `tableHead`, `wideTableCard*`.

   The fix:
   - `src/routes/design-preview.tsx` now renders the 4 new components in all four theme×direction panels.
   - The test lists them as rendered and lists the recipes, plus `SearchInputProps`, as non-visual.
   - The axe sweep over the preview still passes with them included.
4. **`src/features/quicklogin/SecurityLogPage.test.tsx` "LastSignIn joins device, IP and zone" failed.** This was a stale expectation:
   - ETQAN-QA-1018 deliberately changed `LastSignIn.tsx` to show the zone as a city (`zoneLabel`), so it shows "Cairo" and not "Africa/Cairo".
   - The test now expects "Cairo".
   - The ETQAN-QA-065 assertions are kept: no `dir=ltr` wrapper, and one `<bdi>` per part.

## Files touched

All paths are under `dashboard/`:
- `src/features/billing/qa-m08-r3.test.tsx`
- `src/routes/design-preview.tsx`
- `src/routes/design-preview.test.tsx`
- `src/features/quicklogin/SecurityLogPage.test.tsx`
- the 12 biome-formatted files listed above.
