# F08 Agent 2 log (Execution & Quality Gate), lean mode

## 2026-10-19 16:30Z Start (run wf_c827a266-5f3)
- Read README (lean, scope cut, resume, paused/resumed), environment.md, spec F08. Stack up (all containers Up). Scripts in `evidence/F08/scripts/` (lib.sh copied from F06, jars in scratchpad).
- s0: logged in adm/codes/nocode/sup/tea/tea2/stu/par/oth (all 200). Survey: qa-teacher = user 7 / profile 1, qa-student = user 5 / profile 1; rate 6000/h; teacher 7 has draft payslips Oct/Nov (no issued Oct), so July used for the lock case.
- s1: set_features on (all already on). Sub A 82, Sub B 83 (starts 2026-10-01, package 2 = 8 x 30 min); 14 hand-added sessions 235-250 (API returns `{"session":{...}}`, ids recorded by hand in ids.env).

## 16:36-16:41Z API cases TC-002..TC-013
- TC-002 PASS (settings toggled live, restored to absent=true/excused=false). TC-003 PASS (6000/3000/4500).
- TC-004 PASS: payslip 42 PAY-000039 (July, teacher 7) issued; 11 write paths 409 / bulk skipped; PUT report 200 (outside the documented lock, observation).
- TC-005/006/007/008 PASS (identical re-mark writes no activity: S8 refuted; 5 concurrent marks serialised).
- TC-009 PASS incl. DST (10-31 15:00 → 13:00Z) and slot reattach; TC-010 PASS (pause and archived-future sub-steps not runnable, noted).
- TC-011/012 PASS. S3: supervisor edits any session = roles-permissions spec §3.4, by design.
- TC-013 PASS: 16 routes 404 cross-tenant, bulk not_found, cross-host cookie 403, DB unchanged.

## 16:41-16:48Z TC-014..TC-026
- TC-014 FAIL P4 (QA-047 has_report while switch off). TC-015, TC-024 PASS.
- TC-016 FAIL P3: S6 confirmed (QA-044). Checked plan 12b and grep: no money use.
- TC-017 PASS: Jitsi REAL; spec's J2 expectation corrected (no Zoom account → create_meeting returns Jitsi at once). zoom_api back off.
- TC-018 PASS (impersonation via people/teachers/7/quick-login → 403 identity.impersonating; stopped after). S7 no extra exposure.
- TC-019, TC-020, TC-021, TC-022, TC-023, TC-025 PASS. S4 by design (B2c C-9), S10 by design (B2a line 68).
- TC-026 FAIL P3: S5 confirmed (QA-045); S1 by design per B2d D-7, feature doc contradicts → QA-046 P4.

## 16:49-16:55Z UI, pytest, added case
- ui0.sh: J7 deleted, Sub C 84 (QA Student Two), U1 309 started 10 min ago.
- Playwright e2e/qa/f08-sessions-attendance.spec.ts: 3/3 PASS first run (`pw-run1.txt`, screenshots in `pw/`). DB: U1 completed, marked_by 7, activity row; Sub C 1 used / 7 left.
- pytest etqan/scheduling: 1380 passed (110.9 s).
- TC-027 added (P1): teacher re-marks an 11-day-old session; consumption/pay follow, locked session 409. PASS. S2 by design.

## Result
27 executed: 24 PASS, 3 FAIL (P3 x2, P4 x1, plus P4 doc QA-046), 0 BLOCKED. No P0-P2. Status TESTING (gate pending).
Bugs filed: ETQAN-QA-044 (P3), 045 (P3), 046 (P4), 047 (P4). Settings and switches restored; zoom_api off. Data left for scenarios: subs 82/83/84, sessions 235-309, payslip 42 issued (July).

## 2026-10-19 ~17:00Z Gate (Agent 2)
- Coverage checklist: roles/tenant/money/state complete. Cheap missing check G1 (`scripts/g1.sh`, `gate/g1-overconsumption.txt`, REAL): 8 extra present on Sub C 84 → 9 used / −1 remaining / extra 1 / progress 1.0 = DB 9; teacher 200, foreign student 404, qaother 404; undo+delete → 1/7, 0 rows. By design (`rules.derive`).
- Regression: `pytest etqan/scheduling` 1380 passed (107 s). U1 309 undone by admin, then Playwright f08 3/3 PASS (`gate/pw-f08-regression.txt`); DB U1 completed, marked_by 7, Sub C 1/7.
- No P0–P2, no fixes to retest, no escalations. Decision: **PASSED** (12 gates). Open: QA-044, 045 (P3), 046, 047 (P4). Wrote § F08 gate decision, row, test-matrix, coverage-gaps checklist. Nothing committed.
