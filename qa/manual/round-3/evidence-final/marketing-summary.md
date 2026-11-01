# Marketing, final regression (round 3, Agent 3)

The checks ran 2026-11-01 inside the `marketing` container (`-u 0`, with `SITE_SCHEME` unset). The working tree was `qa/manual-round-2`, including the uncommitted owner and round-3 changes.

| Check | Result | Evidence |
|---|---|---|
| `vitest run` (full suite) | 20 of 20 files and 380 of 380 tests passed | `marketing-vitest.txt` |
| `astro check` (tsc and Astro diagnostics) | 87 files, with 0 errors, 0 warnings and 0 hints | `marketing-astro-check.txt` |
| `biome ci .` (lint and format) | **First run: 1 error.** After the fix: 86 files, no errors | `marketing-lint.txt`, `marketing-lint-after-fix.txt` |
| Re-run of `test/round2-a2.test.ts` after the fix | 7 of 7 tests passed | `marketing-vitest-round2-a2-rerun.txt` |

## Failure and fix
- **`test/round2-a2.test.ts`: Biome format error only.** Two long lines did not match the formatter: a `props: {...}` object literal and an `html.match(...)` call. This was not a behaviour regression. I fixed it with `biome format --write` on that one file, which changes whitespace and line breaks only. No assertions changed.

## Flakes
- None. Every test passed on the first full run.

## Not changed
- No source code changes were needed. The owner's uncommitted edits in `src/` and `test/` were left untouched.
