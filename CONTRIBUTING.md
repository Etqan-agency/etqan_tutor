# Contributing to etqan_tutor

Start with the [developer guide](docs/guide/README.md). The short version:

1. **Spec**: a design in `docs/superpowers/specs/` for anything beyond a small fix. Check the
   product spec's non-goals first.
2. **Plan**: an implementation plan in `docs/superpowers/plans/`.
3. **Tests first**: write failing tests, then the code (TDD).
4. **Check**: `just test` and `just lint` pass locally; CI must be green before merge.
5. **Document**: update the feature's page in `docs/features/` in the same PR.
6. **Merge**: submodule PR (trunk `main`) first, then the meta repo PR (trunk `master`) that
   bumps the pointer. A green `master` deploys to staging.

## Rules

- Branch `feat/<topic>` or `fix/<topic>` in every repo you touch; Conventional Commits.
- No `--no-verify`, no force-push to shared branches.
- Apps talk to each other only through `services`; `lint-imports` enforces the boundaries.
- Migrations are backward-compatible (expand first, contract later): deploys are blue/green
  and migrations are never reversed.
- The binding rules are in [CLAUDE.md](CLAUDE.md).
