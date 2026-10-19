# F06 Agent 2 log

## 2026-10-19 07:40 Start
- Read README (lean, scope cut/resume), environment.md, spec F06 (28 cases, S1-S8). Stack up. Host date 2026-10-19 (Mon), so spec "today 2026-10-18" shifts by +1 day; D1=2026-10-19 is today.

## 2026-10-19 07:41 Setup (evidence/F06/s0-setup.txt, scripts/s0-s3.sh, t1.sh)
- set_features qa --on (12 switches) OK. Logged in 8 jars (adm, codes, nocode, sup, tea, stu, par, oth).
- QA6 people: teachers B=217, C=218 (gender required); students 212-215 (EG), 216 (SA). Parent 6 guards qa-student 5 (no POST children API).
- Catalogue: C1=3 QA6 Quran [7,217,(218 added in TC-011)], C2=4 QA6 Arabic [7], P1=3 (2x45m, 1 month, EGP 150000, 8 sessions), P2=4 (99999, 6 sessions), inactive PI=10.
- Roles: 32 "QA6 Catalogue+Subs" on staff 3 for the run, 33 "QA6 PkgViewOnly" on staff 2 briefly. Both unassigned + inactive at cleanup.

## 07:42-07:47 Catalogue + money (TC-001..009) -- all PASS
- TC-002: XXX/ZZZ accepted = by design (B3d spec line 69 regex). Spec corrected.
- TC-004: id collision made the qa admin rename qa's own package 1 -> reverted (tc004.txt). Isolation evidenced by content + other-schema max(updated_at).
- TC-008/009: invoices bigint, same currency as subscription. S6/S8 = documented D-4/P4-10.

## 07:47-07:53 Lifecycle (TC-010..017)
- TC-010/011 DST correct (Cairo, zoneinfo in container). S7 refuted (conflict listed).
- TC-012 FAIL: S1 confirmed -> QA-041 (P2).
- TC-013 PASS; TC-029 added (pause past renewal start: no overlap).
- TC-015 FAIL: S3 confirmed -> QA-039 (P2).
- TC-016 PASS, S4 refuted (parallel output shares one .out file: harness artifact, codes authoritative).
- TC-017 FAIL: S2 confirmed -> QA-040 (P2, intent to confirm). People re-activated.

## 07:53-08:00 Conflicts, availability, trials, bundles, schedules, job, perms, isolation (TC-018..028)
- TC-018 FAIL -> QA-042 (create/renew never return conflicts). S5 per teacher by design.
- TC-019..028 PASS. TC-022 same student / different course allowed by B2f F-2 (spec corrected).
- TC-027: qa POST with student id 13 resolved to qa's own user 13 (id collision) -> sub 59 cancelled, voided and deleted at cleanup.

## 08:00-08:10 UI smoke + pytest
- Playwright e2e/qa/f06-catalogue-scheduling.spec.ts: run1/run2 failed on my locators (renew navigates to the renewal; strict text) -> run3 3/3 PASS.
- pytest etqan/catalogue etqan/scheduling: 1451 passed (104 s).

## 08:12 Cleanup (cleanup.txt)
- Subs 57 (renewal of qa-student sub 11, made by TC-026) and 59: cancel, void invoice, delete. qaother: sub/pkg/course removed (0 left).
- Availability windows for 7 and 217 cleared; timezone Africa/Cairo; horizon 14.
- MISTAKE + fix: ids.env R2 collision -> role 21 "QA Billing Narrow" (F09) PATCHed inactive; restored to active (F09 created it active, 0 members).
- QA6 data (subscriptions, sessions, bundles 2/4/5/6, group 2, family 10, P1 SA price 5000 SAR) left for F08 / scenarios.

## Result
29 executed: 25 PASS, 4 FAIL (P2: QA-039..042), 0 BLOCKED. All REAL. Status TESTING, awaiting fix cycle 1.

## 2026-10-19 ~16:25Z Retest 1 + gate (run wf_c827a266-5f3)
- Read README (lean/resume), environment, register QA-039..042, coverage-gaps proposals, Agent 3 log. Stack up. Scheduling working-tree diff == fix-cycle-1/fix.diff.
- scripts/r1.sh -> retest-1/r1-api-db.txt (REAL): QA-042 create 9 pairs = DB overlap query, control [], renew 5 / [], teacher 403. QA-039 repro (subs 77/78): duplicate by design, renew conflicts 1 pair. QA-040 repro (sub 34): created 0, skipped_inactive 3, board 0 rows, renew 400; reactivation refills 3 dates.
- Read B2b spec line 193 myself: duplicate is the design -> NOT_A_BUG accepted.
- pytest test_generation_guards 9/9; scheduling+catalogue+academy 1502 passed; ruff/format clean; lint-imports 54/0; dashboard vitest academy 14, biome clean.
- Playwright e2e/qa/f06-retest1.spec.ts (QA-041 warning) 1/1; f06-catalogue-scheduling 3/3 rerun.
- Gate G1 isolation (qaother 404 / cross-host 403) and invoice check (6/6 one invoice at package price) -> retest-1/gate-checks.txt.
- New P3 ETQAN-QA-043 (dashboard doesn't show create/renew conflicts). Cleanup: subs 73-76, 78 deleted; 77 expired (marked lesson), invoice voided.
- Decision: PASSED (12 gates). Open: QA-043 P3. Owner decisions: QA-039/041 proposals, QA-040 intent.
