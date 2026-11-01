# Marketing, final gate (round 3, Agent 2)

I re-ran these checks myself on 2026-11-01 and did not reuse Agent 3's numbers. They ran inside the `marketing` container (`docker compose exec -T -u 0 marketing`, with `SITE_SCHEME` unset). The code under test was the working tree on `qa/manual-round-2`, including the uncommitted owner and round-3 changes.

| Check | Command | Result | Evidence |
|---|---|---|---|
| Full test suite | `npx vitest run` | **PASS**: 20 of 20 files and 380 of 380 tests passed, exit 0 | `marketing-gate-vitest.txt` |
| Type and Astro check | `npx astro check` | **PASS**: 87 files, with 0 errors, 0 warnings and 0 hints, exit 0 | `marketing-gate-astro-check.txt` |
| Lint and format | `npx biome ci .` | **PASS**: 86 files checked, no errors, exit 0 | `marketing-gate-lint.txt` |

- **Flakes:** none. Every test passed on the first full run, so no reruns were needed.
- **Noise only:** the stderr shows Astro's deprecation warning about `markdown.gfm` and `markdown.smartypants`. It doesn't affect the result.
- **Match with Agent 3:** these counts are the same as in `marketing-summary.md` (380/380, 87 files with 0 errors, lint clean after the Biome format fix).

**Gate verdict: marketing PASSES.**
