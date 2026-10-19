# F02 Agent 3 — fix cycle 1 (attempt 1)

## 2026-10-19 (local) — ETQAN-QA-017, ETQAN-QA-018
- Read README (lean + scope cut), environment, bug register entries 017/018, `docs/features/sign-in.md`.
- QA-017: intent confirmed (sign-in.md § Quick login "the user is signed out"; `test_features.py` comment
  "Signed out, not only refused: it stays out once parents are back on"). Wrote 2 regression tests,
  both failed (row survives the 403) — REAL (pytest, test DB). Root cause: ATOMIC_REQUESTS rollback of
  `session.flush()`'s DELETE via DRF `set_rollback()`. Fix: refused key kept on request +
  `EndRefusedSessionMiddleware` deletes it after the view (outside the transaction).
- QA-018: `change_password` / `confirm_password_reset` skipped `validate_password`; serializers had no
  max_length. Fix: `services._validate_new_password` + `max_length=128`. 8 regression cases failed
  before, pass after. Same-password reuse left as owner decision (no validator/spec requires it).
- Checks: ruff check + format clean, lint-imports 54 kept, `pytest etqan/identity` 861 passed.
  Live REAL on stack: `evidence/F02/fix-cycle-1/live-after.txt` (qa-parent@ password unchanged).
- Status: both FIXED-UNVERIFIED in the register; Agent 2 verifies. No commits.
- platform + tenants pytest (middleware is global): 423 passed (`evidence/F02/fix-cycle-1/pytest-platform-tenants.txt`).
