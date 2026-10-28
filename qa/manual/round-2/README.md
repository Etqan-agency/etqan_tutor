# Manual QA round 2: fix every bug still open (2026-10-28)

The owner decided (2026-10-28) that all 170 open bugs get fixed. There's no new exploration: the bugs
are already filed with steps and screenshots in `qa/bug-register.md`.

## Branches and PRs
- Work on `qa/manual-round-2` in backend, dashboard and marketing. It was branched from
  `qa/manual-2026-10`, which holds the first round's fixes.
- The PRs are separate, stacked on the first-round PRs. The first-round PRs may be merged while
  this round runs.
- Never commit. The conductor commits and opens the PRs at the end.

## Defaults for decisions
The owner approved the recommended defaults for decisions. Each one is recorded in
`round-2/decisions.md` (bug, the choice made, and why) so the reviewer can check it.
- API changes must be additive only, with nothing breaking.
- Migrations must be additive only: a new nullable column or a new table. Nothing destructive.
- Public data on the academy site carries no personal contact details. Teachers show a name,
  photo and bio only; courses and packages show their name and price.

## Token budget: the owner's tokens are limited
- Read only the register entries for your IDs: `awk '/^## ETQAN-QA-NNN:/,/^## ETQAN-QA-/'`.
- Do not open screenshots unless the fix is visual and the text isn't enough. Agent 2 checks each
  visual fix with ONE "after" screenshot.
- Batch related fixes into one shared root-cause fix: the shared person picker, phone card
  tables, `@/lib/bidi`, and the locale files.

## Groups
| Group | What | Bugs |
|---|---|---|
| A1, A2 | Text, translations, wording, CSV | 48 + 48 |
| B | RTL order and missing confirmations | 18 |
| C | Phone layouts and the 100-person pickers | 24 |
| D | Missing info, behaviour, other | 32 |

- Each group's checklist is in `group-<X>.md`.
- Groups run in parallel. Shared files (locales, `bug-register.md`, `triage.md`): re-read right
  before editing, change only your own lines, and never revert anyone else's.
