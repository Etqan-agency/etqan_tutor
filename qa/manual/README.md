# Manual test campaign (started 2026-10-27)

The plan is `~/.claude-project1/plans/streamed-chasing-bear.md` (plan v2). The owner chose:
- **Scope:** everything, all 16 areas.
- **Fixes:** P0–P2 plus easy, safe P3s.
- **Languages and devices:** AR + EN, desktop + mobile.

It runs in batches of 4 areas, with a checkpoint after each batch.
- **Batch 1:** M02 sign-in & account, M03 dashboards & navigation, M04 people, M06 subscriptions &
  schedules.
- After batch 1 the run stops so the owner can check the cost.

## Roles
| Agent | Does | Never |
|---|---|---|
| **Agent 1, manual tester** | Uses the product like a real person, one step at a time, in a real browser. **Looks at every screenshot.** Writes raw findings with a screenshot for each problem. | Classify, fix, or dismiss anything |
| **Agent 2, triage + gate** | Reproduces each finding itself in the browser with its own screenshot. Dedupes, rejects non-bugs (checking `docs/features`), sets severity and type, files bugs from ETQAN-QA-048 on, retests fixes with before/after screenshots. **Alone passes an area.** | Fix code |
| **Agent 3, fixer** | Fixes P0–P2 and the P3s marked easy, at the root cause, each with a regression test. | Verify its own fix; build migrations, API changes or refactors (those become proposals) |

## The browser tool: `qa/manual/tools/step.mjs`
- Each call opens the page, does the actions in order, and saves a screenshot.
- It prints JSON with:
  - `url`;
  - `dir` (`rtl` or `ltr`);
  - `error` (the action that failed);
  - `consoleErrors`;
  - `failedRequests` (status ≥ 400);
  - `text` (the visible page text).
- The session persists per `--session`, so cookies and language survive between calls. **One
  session per role and language**, for example `M04-admin-ar`, `M04-teacher-en`.
- Run it from `qa/manual/tools/`:

```bash
node step.mjs --session M04-admin-ar --lang ar --viewport 1440x900 \
  --url http://qa.etqan.localhost/app/people/students \
  --actions '[{"clickRole":["button","إضافة طالب"]},{"wait":500}]' \
  --shot ../screens/M04/step-012.png
```

- Actions: `goto`, `click`, `dblclick`, `fill`, `fillLabel`, `clickRole`, `select`, `check`,
  `uncheck`, `press`, `upload`, `hover`, `wait`, `waitFor`, `back`, `reload`, `eval`, `shotEl`.
  Their syntax is in the file header.
- Use `--viewport 375x812` for mobile and `--full` for a full-page shot. Use `--nosave` so that one
  call doesn't change the stored session.
- **After every call, open the screenshot with the Read tool and look at it.** Judge layout, RTL,
  text, overlap, cut-off text, wrong numbers, broken states. The text field alone isn't enough.

## Accounts and data
- Accounts are listed in `qa/environment.md` § Accounts and in `qa/feature-inventory.md` § QA
  academies.
- Academy `qa` has **all 86 built switches on** (2026-10-27) and plenty of data.
- `qaother` is nearly empty, which makes it the place to test empty states.
- The academy's own staff, teachers, students and parents: password `QA-People-2026!`, or as listed.
- Rows with test names (`f02-*`, `QA5 RT*`, `F03-*`) are leftovers from Tier 1. Judge the
  **product**, not their odd names. A currency like `ZZZ` is the already-known QA-022.
- Read `qa/bug-register.md` before filing. Known bugs (QA-001…047) are not re-filed: link to them
  instead.

## Files
- `findings/<area>.md`: Agent 1's raw notes. One `### <AREA>-F-NNN` block per finding, with:
  - the steps;
  - the screenshot path;
  - what it expected;
  - what it saw;
  - console and network errors.
- `screens/<area>/`: screenshots. Name problem shots `<AREA>-F-NNN-<slug>.png`. Agent 2's repro
  shots and before/after shots go in `screens/<area>/triage/` and `screens/<area>/fix/`.
- `triage.md`: Agent 2's sorted table. For each finding:
  - its finding ID;
  - the bug ID, or `dup of …` / `not a bug` (with the reason);
  - severity and type;
  - whether it is an easy P3;
  - status.
- `progress.md`: per-area status, owned by Agent 2.
- `logs/<area>/agent{1,2,3}.md`: time-stamped activity logs.

## Rules
- **Never commit or push.** Agent 3 works on branch `qa/manual-2026-10` in each submodule it
  touches (create it from `main`).
- One browser at a time.
- Playwright specs run with `--workers=1`.
- Only scoped tests.
- Never touch the demo, other, khaled or journey-* academies.
- Never touch the files of the owner's other sessions (website/official site, `brand/`).
- If Docker is down: `open -a Docker`, then `~/.etqan-qa-tools/dc.sh up -d --no-build --no-deps
  django celery_worker celery_beat flower dashboard marketing mailpit caddy`. The `website` service
  is out of scope and its image isn't built.

## Parallel runs (from 2026-10-27 21:50): areas run AT THE SAME TIME
- **Bug IDs:** each area files ONLY inside its own range. Don't use the register's "Next ID" while
  areas run in parallel.

  | Area | Range |
  |---|---|
  | M02 | ETQAN-QA-048 … 099 |
  | M03 | ETQAN-QA-100 … 149 |
  | M04 | ETQAN-QA-150 … 199 |
  | M06 | ETQAN-QA-200 … 249 |
  | M07 | ETQAN-QA-250 … 299 |
  | M08 | ETQAN-QA-300 … 349 |
  | M09 | ETQAN-QA-350 … 399 |
  | M14 | ETQAN-QA-400 … 449 |
  | M15 | ETQAN-QA-450 … 499 |
  | M12 | ETQAN-QA-500 … 549 |
  | M05 | ETQAN-QA-550 … 599 |
  | M10 | ETQAN-QA-600 … 649 |
  | M11 | ETQAN-QA-650 … 699 |
  | M13 | ETQAN-QA-700 … 749 |
  | M16 | ETQAN-QA-750 … 799 |
  | M01 | ETQAN-QA-800 … 849 |

  Append your bugs at the end of `qa/bug-register.md`, under a heading `## --- <AREA> manual bugs ---`
  that you create once.
- **Shared files** (`bug-register.md`, `triage.md`, `progress.md`, locale JSON files, shared
  components):
  - Re-read the file right before every edit.
  - Change only your own lines and rows.
  - Never revert or reformat other people's changes.
- **Agent 3:** if another area's fix touches the same file, keep both changes. Run `git -C <sub> diff
  <file>` before editing so you know what's already there.
- If a page fails for a few seconds while another agent's change reloads the server, retry once
  before reporting it.
