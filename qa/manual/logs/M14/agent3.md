# M14 Agent 3 (fixer) log

## 2026-10-27T20:55:54Z cycle 1
- Branch: dashboard already on `qa/manual-2026-10`; backend untouched (all 19 fixes are dashboard-only, no API/migration).
- Fixed (FIXED-UNVERIFIED in register): ETQAN-QA-400, 401, 402, 404, 405, 406, 407, 408, 413, 415, 416, 417, 418, 419, 420, 422, 425, 426, 427.
- Shared files touched (others' changes kept): `components/Confirm.tsx` (optional keepLabel/confirmLabel), `branding/PrintSheet.tsx` (Back), `lib/money.ts` + `billing/schemas.ts` (latinDigits), `lib/server-messages.ts` (overlap sentence), locale JSON (keys added only, formatting preserved).
- Concurrency notes: `curriculum.json` `progress.noLevels`/`noLevelsOffice` were written by a parallel area at the same time; ProgressPanel uses their keys/values. `WithdrawalDialog.tsx` is also being edited by M09 (QA-367); my bodyOwn line kept.
- Checks: tsc --noEmit clean; biome check on 41 touched files clean; vitest 23 files: 215 pass, 2 failures not mine (WithdrawalsPage "no balance" = M09's in-progress QA-367 test; TeacherSessions postpone-deadline flaked during M07's QA-255 edit, passes on rerun). Evidence in qa/manual/evidence/M14/fix-1/.
- No browser repro done by me (Agent 2's triage screenshots used); fixes need Agent 2's before/after check, esp. 400 (disabled + hint), 402 (Home empty link), 408 (scroll to row), 425/426/427 (phone 375).
