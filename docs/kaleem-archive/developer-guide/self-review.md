# Self Code Review Checklist

Walk this before every merge. `/ship` command invokes this interactively.

## Correctness
- [ ] Tests cover the happy path
- [ ] Tests cover at least 2 edge cases
- [ ] Tests cover at least 1 failure case
- [ ] Tests pass locally
- [ ] Manually tested the feature in a browser

## Discipline
- [ ] Spec is linked and closed
- [ ] Plan is linked and all steps checked
- [ ] No new TODO/FIXME without an ISSUES.md entry
- [ ] No print() / console.log() left in
- [ ] No commented-out code
- [ ] No "while I'm here" refactors (D10)

## Boundaries
- [ ] import-linter passes
- [ ] No new cross-module model imports
- [ ] Public API of any touched module is still documented

## Docs
- [ ] Module arch doc updated if public API changed
- [ ] ADR written if a decision was made
- [ ] Runbook updated if operational concerns emerged

## Sustainability
- [ ] This commit represents one focused work session or less
- [ ] I am not coding past midnight (D11)
