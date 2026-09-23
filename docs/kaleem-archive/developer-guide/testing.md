# Testing Guide

## Running tests

```bash
just test           # all tests (backend + frontend + boundaries)
just test-backend   # backend only
just test-frontend  # frontend only (type check in Phase 0)
```

## TDD workflow (D3)

1. Write the failing test
2. Run it — verify it fails with the expected error
3. Write the minimal code to make it pass
4. Run it — verify it passes
5. Refactor if needed, tests still passing
6. Commit

## Coverage gate

100% coverage (line + branch), machine-enforced in CI in every repo (`backend`, `dashboard`,
`marketing`). This is a hard gate, not a target — CI fails below 100% and the change does not
merge or deploy. See ADR-0021.

- **All code** — services, models, views, serializers, frontend: 100% line + branch.
- **Exclusions are per-line and justified**, never blanket file/directory exclusions for
  business logic (`# pragma: no cover  # <why>`, `/* v8 ignore next -- <why> */`). Migrations,
  settings, and generated files are excluded at the config level.
- **End-to-end tests (Playwright)** ship with every user-facing feature, covering the primary
  happy path and key failure paths, run in CI against a real built app.
