# Manual campaign, round 3 (from 2026-11-01)

This round is a complete re-test after the owner's latest changes, mainly the premium dashboard
UI. The plan is in `~/.claude-project1/plans/streamed-chasing-bear.md` under "round 3".

The tool, the accounts and the roles are the same as in rounds 1–2: read `qa/manual/README.md`
first. Only the differences are listed below.

## What changed from rounds 1–2
- **Code under test is the local working tree, as it is now.**
  - backend and dashboard are on `feat/premium-dashboard-ui`, with **uncommitted owner changes**.
    marketing is on `qa/manual-round-2`.
  - **Never** checkout, stash, reset, pull, or commit anything. Agent 3 edits files in place, and
    the owner commits everything himself.
  - Before editing a file, run `git -C <sub> diff <file>`, so you never overwrite the owner's
    uncommitted lines.
- **Fix everything.** P0 through P4 all get fixed, not just P0–P2.
  - For decision items, apply the safe, recommended default and log it in `round-3/decisions.md`.
  - Migrations: additive only, and only if really needed.
  - Anything destructive becomes a proposal in `decisions.md`.
- **Extra focus. Each of these is a real bug, not cosmetic:**
  1. **Spacing and icons.**
     - Uneven padding, margins and gaps.
     - Icons: the wrong size, misaligned with their text, the wrong position, or not mirrored
       in RTL (back/next arrows, chevrons).
     - Inconsistent buttons, cards and tables.
     - Fix shared components (`dashboard/src/ui/`) and theme tokens rather than patching one
       screen.
  2. **Translation must be natural, not literal.**
     - Flag Arabic that reads like a word-for-word translation, is awkward, uses inconsistent
       terms, or mixes in English.
     - Agent 3 rewrites it as natural product Arabic, following `round-3/glossary.md`, which is
       created by the translation review. Read it if it exists.
  3. **Responsive layout.** Test at **375, 768, 1024 and 1440** widths. At each one check:
     - no sideways scroll;
     - nothing overlapping or cut off;
     - tables turn into cards on a phone, using the shared `phoneCards` pattern;
     - menus, dialogs and touch targets work.
  4. **Both themes.** Check the main screens in light and dark mode with `--theme dark`. The
     premium UI is new, so check the new look on every screen.
- **The tool has a new flag, `--theme dark|light`.** Viewports: `375x812`, `768x1024`,
  `1024x768`, `1440x900`.

## Paths
| What | Where |
|---|---|
| Raw findings | `round-3/findings/<area>.md`, with blocks `### <AREA>-R3-NNN` |
| Screenshots | `qa/manual/screens/r3/<area>/`, with `triage/` and `fix/` subfolders |
| Triage table | `round-3/triage.md`, one section per area |
| Area status | `round-3/progress.md` |
| Decisions | `round-3/decisions.md` |
| Logs | `round-3/logs/<area>/agent{1,2,3}.md` |

Bugs go in `qa/bug-register.md`, appended under `## --- <AREA> round 3 ---`, using the same entry
format as before. Every entry has:
- a screenshot;
- the steps;
- the fix;
- the regression test;
- the verification status.

## Bug ID ranges (each area files only inside its own range)
| Area | Range | Area | Range |
|---|---|---|---|
| M02 | 900–949 | M15 | 1300–1349 |
| M03 | 950–999 | M12 | 1350–1399 |
| M04 | 1000–1049 | M05 | 1400–1449 |
| M06 | 1050–1099 | M10 | 1450–1499 |
| M07 | 1100–1149 | M11 | 1500–1549 |
| M08 | 1150–1199 | M13 | 1550–1599 |
| M09 | 1200–1249 | M16 | 1600–1649 |
| M14 | 1250–1299 | M01 | 1650–1699 |

Translation review: 1700–1799.

## Parallel work
Eight areas run at the same time, so follow the shared-file rules in `qa/manual/README.md` §
Parallel runs:
- re-read a file right before editing it;
- change only your own lines;
- keep other people's changes.

Use your own `--session` names, prefixed `r3-<area>-…`.
