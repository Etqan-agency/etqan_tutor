# M12 Agent 3 (fixer) log

- 2026-10-28T01:21:09Z Cycle 1 start. Bugs 500,501,505,506,507,508,510,511,512,513,514,515. backend+dashboard already on qa/manual-2026-10.
- 2026-10-28T01:37:58Z Fixed (FIXED-UNVERIFIED) 500, 501, 505, 506, 507, 508 (wording only), 510, 511, 512 (dashboard + backend services), 513, 514, 515. All dashboard; backend only identity/services.py _check_emoji + tests. No migrations/API shape changes.
- Checks: tsc 0; Vitest 13 files 119 passed + locale tests 29 passed; biome clean on touched files; pytest test_tags*.py 40 passed; ruff + format clean; lint-imports 54 kept. Outputs in evidence/M12/fix-1/.
- Proposals in coverage-gaps.md (M12 section): 506 disable ungrantable codes + API code; 508 active-first order/search; 510 JobRun error_code; 515 bad names as data.
