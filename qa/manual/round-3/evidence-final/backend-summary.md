# Backend final regression, round 3 (Agent 3)

Run on 2026-11-01 and 2026-11-02, inside the `django` container, against the working tree on
`feat/premium-dashboard-ui`, which includes the owner's uncommitted changes. Nothing was committed.

pytest-xdist is not installed in the image, so the suite ran serially. Another pytest process was
already using the shared `test_etqan` database. To avoid clashing with it, this run pointed
`DATABASE_URL` at `etqan_r3final`, so its test database was `test_etqan_r3final`, made fresh with
`--create-db`.

| Check | Result | Evidence |
|---|---|---|
| `ruff check .` | All checks passed | `backend-ruff-check.txt` |
| `ruff format --check .` | 1204 files already formatted | `backend-ruff-format.txt` |
| `lint-imports` | 54 contracts kept, 0 broken | `backend-lint-imports.txt` |
| `makemigrations --check --dry-run` | No changes detected | `backend-makemigrations.txt` |
| Full `pytest -p no:cacheprovider` | **1 failed**, 10374 passed, 1 skipped (1:29:56) | `backend-pytest.txt` |
| Rerun after the fix (`test_seed_b2`, `test_seed_finance`, `test_seed_staging`, `test_seed_dev`) and ruff on the changed file | 40 passed, ruff clean | `backend-pytest-rerun.txt` |

## The failure and its fix

`etqan/tenants/tests/test_seed_b2.py::test_demo_gets_a_postponed_session_and_teacher_times_once`
failed with `assert 0 == 1` on `teacher_in_at`. The seed printed
`skip: times for session 35 — This session is on an issued payslip.`

- **Kind:** a real bug that depends on the date. It is not a round-3 regression, and it is not a
  flake caused by load. `seed_dev` runs `seed_payroll` first, which issues last month's payslips and
  locks those sessions. After that, `b2.seed_times_postponement` records times on the latest
  completed session. On the first days of a month, that session is still last month's, so it is
  locked by the payroll lock (spec §4.5), and `record_times` refuses it. The result is that the demo
  academy gets no teacher times. Today was 2026-11-01, which is how the bug showed up.
- **Fix (root cause):** in `backend/etqan/tenants/seeds/b2.py`, the seed now picks the latest
  completed session where `payroll_locked=False`. The payroll lock is unchanged, and so is
  everything round 1, 2 or 3 fixed. The seed is still idempotent.
- **Regression test:** the existing `test_seed_b2` test covers it. With the fix it passed on
  2026-11-01, the date that had failed, and the other seed modules also pass (40/40).

## Flakes
None. The only failure could be reproduced deterministically for that date.

## Notes
- Expect each seed test to be slow, about 1.5 minutes per `seed_dev` call under the current load.
- The test database `test_etqan_r3final` is still in Postgres. It does no harm and can be dropped.
