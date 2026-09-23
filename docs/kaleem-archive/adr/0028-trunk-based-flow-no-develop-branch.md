---
number: 0028
title: Trunk-based flow — feat/… → PR → trunk, with no develop branch
status: accepted
date: 2026-09-04
supersedes: ADR-0014 (branching clause only; its meta-repo rule stands)
---

## Context

ADR-0014 (2026-06-09) mandated `feat/<name>` → `dev` → PR → `master` in every repo. Three
months of practice produced a workflow nobody actually follows and two open `ISSUES.md`
entries that each say *"needs an ADR"*:

1. **The submodules never grew a `dev` branch.** `backend`, `dashboard`, `marketing` and
   `infra` all merge `feat → main`. Only the meta repo has `develop`. So the documented
   rule has been false for four of five repos since the day it was written.

2. **`develop → master` is squash-merged, so the branches never share history.** Every
   promotion squashes; after #90 `master` was 1-ahead and `develop` 60-ahead of a common
   base. Each promotion then needs a manual `git merge origin/master` back into `develop`
   to reconcile submodule pointers. A squash once silently **dropped a pointer-bump
   commit** (#85, fixed by #87), and the same class of mistake nearly shipped billing
   without the varchar fix (#125 caught it by diffing pointers before promoting).

3. **The integration branch never did any integrating.** Its justification in ADR-0014 was
   "a place where work is staged and verified before it reaches the protected trunk". But
   until 2026-09-03 CI did not even *run* on `develop` — `ci.yml` triggered on
   `[master, main]` only — so the first time anything was checked was the promotion PR,
   which is also the deploy. Two full phases reached staging that way.

The layer added ceremony, a recurring manual reconciliation step, and a class of
silent-data-loss bug, in exchange for a verification step that was not happening.

## Decision

**Every repo — meta and all submodules — uses `feat/<name>` → PR → trunk. There is no
`develop`/`dev` branch anywhere.**

- Branch `feat/<name>` (or `fix/…`, `docs/…`, `chore/…`) off the trunk. Work there.
- Open a PR into the trunk. Green CI + review, then merge.
- **Never commit directly to the trunk.** Everything lands through a PR. No direct pushes,
  no `--no-verify` (D5).
- **Merge commits, not squashes,** for anything carrying submodule pointers. Squashing is
  what made pointer bumps droppable.
- The trunk is `main` in the submodules and `master` in the meta repo. Normalising those
  names is not part of this decision; the rule is "the repo's trunk", whatever it is called.

**ADR-0014's other rule stands unchanged:** the meta repo is not a working repo. Only
`docs/**`, ADRs, specs, `STATE.md`, `ISSUES.md`, `CLAUDE.md`, CI config, and submodule
pointer bumps belong there. All feature code lives in the submodules.

**Migration.** One final `develop → master` promotion carries the outstanding work, after
which `develop` is deleted and dropped from `ci.yml`'s triggers. Nothing is lost: `master`
contains everything `develop` had.

## Consequences

**Good**

- The documented workflow becomes the one four of five repos already follow. The rule stops
  being false.
- The manual pointer reconciliation after every promotion disappears, and with it the
  silently-dropped-pointer failure mode.
- Every change is checked on the PR that introduces it, rather than at a promotion that is
  also a deploy.
- One less branch to reason about per repo, and no more "is this on develop or master?".

**Bad / costs**

- **Every merge to the meta trunk now deploys to staging.** `deploy-staging` is gated on
  push to `master`, and there is no longer an integration branch to accumulate work. That is
  continuous deployment to staging — desirable, but it means a merge is a deploy, and the
  e2e + coverage gates (ADR-0026, ADR-0027) are the only thing between a PR and the staging
  environment. Merge accordingly.
- No staging area for a multi-PR feature. Anything that must land atomically needs a stacked
  branch or a feature flag, neither of which this project has needed yet.
- Trunk-based flow leans harder on branch protection and on the gates being real. This is
  only safe because those gates were made real first (ADR-0026, ADR-0027); adopting it while
  CI was still fictional would have been reckless.

## Alternatives considered

- **Keep `develop` and fix it properly** — grow a `dev` branch in all four submodules, and
  switch promotions to merge commits. Rejected: it doubles down on ceremony whose stated
  benefit (pre-trunk verification) is now delivered by running CI on every PR. The two-tier
  flow's only real function had become bookkeeping.
- **Keep `develop` in meta only**, matching what actually happens. Rejected: it is the
  meta repo — the one carrying submodule pointers — where squash-divergence causes the
  actual data loss. The layer is worst exactly where it was being kept.
- **Release branches.** Rejected as premature: nothing has shipped to production yet, and
  there is one environment. Revisit at public launch, when a hotfix path matters.
