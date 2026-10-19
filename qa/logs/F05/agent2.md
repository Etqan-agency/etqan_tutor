# F05 Agent 2 log (execution & quality gate)

- 2026-10-19 04:10 Read README (lean mode, scope cut, resume), environment.md, spec F05. Stack up (6 h). Wrote helper lib (scratchpad f05/lib.sh; copies in evidence/F05/scripts). `set_features qa --on families parents contracts quick_login export` → ok. Baseline users qa admin 1 / parent 4 / staff 21 / student 11 / teacher 16; qaother admin 1 / student 1 / teacher 1 / staff 1.
- 04:11 Setup: 60 QA5 Bulk students (60×201), role 29 "QA5 Student Edit", qaother student id 5. evidence/F05/setup.txt
- 04:12 TC-001..003 PASS (tc001-003.txt). TC-004..006 PASS (tc004-006.txt); TC-006 step 5 expectation corrected (payer still parent of K2), follow-up confirmed flag true after full unlink.
- 04:13 TC-007: S2 CONFIRMED (retired family accepts bulk add + PATCH). Note: qaother/qa id collision (5) — isolation moved to TC-016. Session kill via bulk deactivate proven on s1 (shell-made accounts can't log in: unverified email).
- 04:14 TC-008: lists/pagination/CSV ok; `country=eg` → 0 vs SQL 64 (UI sends upper-case: P4).
- 04:15 TC-009, TC-010 PASS. 04:16 TC-011 first run invalid (copied cookie jar → shared session impersonated); redo with separate logins PASS. TC-012: S6 + S10 confirmed. TC-027 PASS.
- 04:17 TC-013 matrix exact (8 jars × 14). TC-014: S3 behaviour confirmed, documented (people.md L99) → by design. TC-015 PASS.
- 04:18 TC-021 (S8 confirmed, no orphans, 255-char name), TC-022 matrix PASS (media URLs 404). 04:19 TC-016 isolation PASS (checksums 8 tables both schemas).
- 04:19 TC-017, TC-018, TC-019 PASS; S4 by design (supervisor sees IBAN/notes/IP). `es` on me = stored value kept, by design.
- 04:20 TC-020 PASS (an apparent 400 was a stale $CODE in a pipe; re-run 200). TC-023: S1 CONFIRMED (4/5 create, 1/2 edit → 500, IntegrityError identity_user_email_key); family and last-admin races ok. Only race requests 500 in django log.
- 04:24 TC-024 (S5 → QA-022 note, S7 confirmed), TC-025 PASS, TC-026 PASS. S9 by design (s9.txt).
- 04:25 Playwright e2e/qa/f05-people.spec.ts run 1: TC-030 ok, 028/029 selector issues (substring "Activated.", payer option label suffix/loading); run 2: 3/3 passed (pw-run2.txt).
- 04:28 pytest etqan/identity etqan/employment: 888 passed.
- 04:30 Added TC-031 (impersonation escalation) PASS. Filed ETQAN-QA-032..037, note on QA-022, Next ID 038. Results table in spec; execution-progress F05 → TESTING; test-matrix counts. No commits.

## Retest 1 + gate (Agent 2, 2026-10-19)
- 04:33 Read README/environment, QA-032 entry, Agent 3 report. Diff of identity/services.py: QA-032 hunks only `_save_claiming_email` + 2 call sites (the `_validate_new_password` hunks are F02 QA-018); test `TestConcurrentEmailClaim`. update_person/create are `@transaction.atomic` + ATOMIC_REQUESTS, so the EmailAddress delete rolls back on the loser.
- 04:34 Original repro (rt1.sh, REAL): 3×5 creates → 1×201+4×400 each, mixed-case 1×201+4×400, 3×2 edits 1×200+1×400; 0 500/IntegrityError in django log; postgres 19 unique violations (catch path exercised). Sequential dup/valid cases ok. retest-1/qa032-api-repro.txt
- 04:35 Regression tests 2/2; mutation (helper → plain save, in memory) 2 failed with IntegrityError. pytest identity+employment 890 passed; ruff/format clean; lint-imports 54/0. Playwright f05-people 3/3.
- 04:36 Gate checks: G1 qaother same address 1×201+3×400, qa untouched (PASS). G2 parallel signed-in email change: both 200, 2nd confirm 400, loser stale pending → filed ETQAN-QA-038 (P3). Next ID 039.
- 04:37 Clean-up: bulk deactivate 14 qa race students (170, 175, QA5 RT1*) + qaother id 8.
- 04:40 QA-032 VERIFIED. Gate: PASSED (12/12). Updated bug-register, execution-progress (row + § F05 gate decision), test-matrix, coverage-gaps § F05, spec TC-023 row. No commits.
