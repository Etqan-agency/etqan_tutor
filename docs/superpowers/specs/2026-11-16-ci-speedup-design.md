# CI speed-up: shard the slow suites, skip what is already proven

**Date:** 2026-11-16 · **Scope:** meta repo `.github/` and `scripts/` only (no submodule change)

## Problem

A full CI run took 40–65 min, and a merge reached production about an hour after it
landed. Measured on run 42728426326 (push to master, 58 min):

| Job | Wall clock | Where the time goes |
|---|---|---|
| backend | 45.0 min | `pytest` 2,642 s: 10,428 tests in one process |
| e2e | 23.6 min | Playwright 1,216 s, one worker (the specs share one seeded database) |
| dashboard | 15.6 min | `vitest --coverage` 850 s, 502 files |
| images | starts at minute 45 | needs every test job |
| staging-sim | 10.2 min | needs `images`, so starts at minute 46 |

Every other job takes under 2 min. And each merge re-ran the whole suite on the tree its
pull request had already tested (PR run 63 min, then the push run 65 min).

## Decisions

1. **Backend: four shards, each `pytest -n auto`.** `scripts/pytest-shard.py` splits whole
   files (module fixtures are not set up twice) across shards by test count; it is
   deterministic, and an empty shard is an error, because pytest given no files runs everything.
   Each shard uploads its `.coverage`; `backend-coverage` combines them and the pyproject
   `fail_under` (80) applies there. Shards pass `--cov-fail-under=0`.
   - pytest-xdist was already a dependency. Under it, concurrent `clone_schema` calls overflow
     PostgreSQL's lock table (`out of shared memory`) at the default
     `max_locks_per_transaction=64`. CI starts Postgres with `docker run … -c
     max_locks_per_transaction=512`, because a service container cannot take server flags.
   - Proof: locally with `-n 8` and 512 locks, all 10,427 tests passed in 5 min, coverage 98.3%.
     Two rehearsed shards combined into one report, which applied the floor.
2. **Dashboard: three vitest shards** (`--shard=i/3 --reporter=blob --coverage`, thresholds
   zeroed on the command line) and `dashboard-coverage` running `vitest run --merge-reports
   --coverage`, which applies the `vitest.config.ts` thresholds. Proof: the merged report gave
   the same totals as before (95.3% lines), and with the threshold raised to 99 the merge exits 1.
3. **e2e: three Playwright shards** (`pnpm e2e --shard=i/3`). Each shard is its own job with
   its own Postgres and `seed_dev`, so specs stay serial within a shard against a database
   no other shard touches. This needs specs that do not depend on state left by a spec in another file.
4. **staging-sim runs in parallel with the tests.** It builds its own images from the gha
   layer cache; it never consumed the `images` job's output. The deploys still need both
   `images` (which needs every gate) and `staging-sim`. The cost: a PR whose tests fail still
   pays for its simulation.
5. **triage, restored from ADR-0038 (Kaleem).** `gates=false` when every changed path is
   `docs/**` or a root `*.md`, or (push only) when an unexpired artifact
   `verified-tree-<tree hash>` exists. `record-verified-tree` uploads one when every job of a
   PR run passed or was legitimately skipped. docs-site and security skip only on a verified
   tree (docs-site builds docs/; ADR-0042 keeps the secret scan on docs changes). `images` and
   the deploys run on `!failure() && !cancelled()`, so a verified merge goes straight to images
   (cached, ~1.5 min) and the deploys. Lookups fail closed: an unknown base or an API error runs everything.
6. **Small ones.** Every job has a `timeout-minutes` (only backend and staging-sim had one). The
   Playwright browser is cached. staging-sim frees disk in the background and waits for it
   just before the deploy step. The five copies of the tokens git-auth step are now
   `.github/actions/tokens-auth`.

7. **PostgreSQL pinned to 18.6** in CI, `docker-compose.local.yml` and infra's production
   compose (infra PR #11). Found on this change's first CI run: `postgres:18-alpine` moved to
   18.7 on 2026-11-15, and on 18.7 django-tenants' `clone_schema` spins (one backend at 100%
   CPU, no lock wait), so `create_academy` never returns. That is the hang behind master's
   frozen backend suite (PR #98) and the staging-sim journey timing out. Reproduced locally: the
   same shard passes on 18.6 and hangs on 18.7. `ship.sh` pulls before every deploy, so without
   the pin the next green master would have upgraded production into it. Unpinning waits for a
   django-tenants or PostgreSQL fix, proven by CI.

## Expected

PR critical path ~13–15 min (the e2e shards or staging-sim, then images), down from 40–63.
Merge to production ~5 min when the PR was green on the same tree. Billed minutes per PR
roughly flat: per-shard setup offsets what `-n auto` saves. Each verified merge saves ~100
billed minutes.

## Risks

- **An e2e spec that relied on an earlier spec's data** will fail once sharding separates
  them. The first CI run of this change is the check; fix the spec, don't merge shards back.
- **Trust in the verified-tree artifact.** A pull request can change `ci.yml` and upload any
  artifact name. This is acceptable in a private repo whose contributors are all trusted, and
  a forged record only skips gates for a tree that matches byte for byte. Revisit it if outside
  contributors ever open PRs.
- **Branch protection.** If it is ever enabled, require `images`, which runs on every path,
  not the individual gates (a skipped required check counts as passing).

## Plan

1. `scripts/pytest-shard.py` with `scripts/tests/pytest_shard_test.sh` (TDD), wired into infra-scripts.
2. `.github/actions/tokens-auth`.
3. `ci.yml`: triage; backend split into lint, shards and coverage; dashboard split likewise;
   e2e matrix; staging-sim needs; record-verified-tree; deploy conditions; timeouts.
4. Update `docs/guide/testing.md` (CI section) and the justfile comment.
5. Verify: actionlint; the PR's own CI run (it touches `.github/workflows/`, so staging-sim
   runs); then the merge push should show `verified=true` and skip the gates.
