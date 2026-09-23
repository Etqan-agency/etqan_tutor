---
number: 0014
title: Git-flow in every repo (feat → dev → PR → master); no feature work in the meta repo
status: accepted
date: 2026-06-09
---

## Context

Work spans a meta repo and four submodules (`backend`, `dashboard`, `marketing`,
`infra`). Without an explicit branching rule, agents (and humans) commit straight
to the trunk, and it is unclear which repo a change belongs in. Direct-to-trunk
commits skip review and break the PR-gated CI story; doing feature work in the
meta repo instead of the relevant submodule scatters changes and muddies the
submodule-pointer model.

We want one branching workflow that every repo follows, and a clear rule that the
meta repo is not a place to do feature work.

## Decision

**Every repo uses git-flow: `feat/<name>` → `dev` → PR → `master`.**

- Branch `feat/<name>` (or `fix/…`) off `dev`. Do the work there.
- Open a PR into `dev`. After review + green CI, it merges.
- `dev` reaches the trunk via its own PR (`dev` → `master`).
- **Never commit directly to `dev` or the trunk.** Everything lands through a PR.
  No direct pushes, no `--no-verify` (D5).

**The meta repo is not a working repo.** Do not do application/feature work there.
The only changes that belong in the meta repo are:

1. Documentation — `docs/**`, ADRs, specs, `STATE.md`, `ISSUES.md`, `CLAUDE.md`.
2. Submodule pointer bumps.

Even those go through the same `feat → dev → PR → master` flow — no direct commits
to the meta trunk. All real feature code lives in the submodules, each with its
own git-flow.

This supersedes the ad-hoc "commit straight to master" pattern visible in earlier
history; D6 ("one feature branch at a time") still holds on top of this.

Branch-name normalization (submodules currently sit on `main`, the meta repo on
`master`) and creating the `dev` integration branch in each repo are a separate
setup task, intentionally not done in this ADR — this records the policy only.

## Alternatives considered

- **Trunk-based / commit straight to master.** Simplest, and what earlier history
  did. Rejected: no review gate, no place for integration testing, easy to ship
  half-finished work to the trunk.
- **GitHub-flow (feature → master, no `dev`).** Lighter. Rejected: the user wants a
  `dev` integration branch where work is staged and verified before it reaches the
  protected trunk.
- **Allow feature work in the meta repo.** Rejected: scatters changes across repos
  and undermines the submodule-pointer model; the meta repo's job is composition +
  docs, not feature code.

## Consequences

Good:

- One predictable workflow across all five repos; agents have an unambiguous rule.
- Every change is review- and CI-gated before reaching the trunk (D5).
- Changes land in the right repo; the meta repo stays a thin composition + docs layer.

Bad / costs:

- More ceremony than direct commits: a branch + PR even for small doc edits.
- Requires branch protection and a `dev` branch in each repo (separate setup, pending).
- The mixed `main`/`master` trunk naming must be normalized before the flow reads
  cleanly end-to-end.
