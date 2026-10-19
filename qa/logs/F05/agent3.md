# F05 Agent 3 (Debugger & Fix Engineer) log

## 2026-10-19 07:32 fix cycle 1, attempt 1: ETQAN-QA-032
- Confirmed intent: docs/features/people.md Rules 1 refuses duplicate emails; 500 is a defect.
- Root cause: _email_taken pre-check races; unique index raises IntegrityError uncaught in _build_person / change_person_email (replace branch).
- Fix: services._save_claiming_email (savepoint + re-check -> ValidationError field=email; other IntegrityErrors re-raised). No migration/API change.
- Regression: TestConcurrentEmailClaim (2 tests) fail before (IntegrityError) / pass after. identity 863 passed; ruff clean; lint-imports 54/0. REAL.
- API replay (REAL): 5x parallel POST x2 rounds, 2x parallel PATCH x3 rounds -> one 2xx + 400s, no 500, 0 IntegrityError in log.
- Test data left in qa academy: students 170, 175 (QA5 RaceF*), for Agent 2 cleanup.
- Status: FIXED-UNVERIFIED. Did not touch etqan/site, dashboard, marketing. No commits.
