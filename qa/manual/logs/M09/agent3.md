
## 2026-10-27T20:42:57Z Agent 3 cycle 1 start
- Bugs: QA-350 351 353 356 358 360 363 364 366 367 368 370 373. Branch qa/manual-2026-10 (already present in dashboard+backend).

## 2026-10-27T20:57:50Z Agent 3 cycle 1 done
- FIXED-UNVERIFIED: QA-350 351 353 356 358 360 363 364 366 367 368 370 373 (register updated with root cause/fix/tests).
- Dashboard files: payroll/{PayslipsList,PayslipPage,FixedSalary,RateDialog,StudentRates,StudentRateDialog,MarkPaidDialog,WithdrawalActions,WithdrawalsPage,MyBalance,WithdrawalDialog,BulkRatesDialog,AdjustmentDialog,bits}.tsx, components/Confirm.tsx (additive confirmVariant, triggerVariant primary), lib/money.ts, lib/server-messages.ts, locales/{en,ar,es}/payroll.json. Backend: payroll/services/salary_expenses.py + test.
- Checks: tsc 0; vitest 196 pass / 4 fail from M08 QA-300 billing amount change (not M09); pytest payroll 439 pass; ruff, lint-imports clean. Evidence qa/manual/evidence/M09/fix-1/.
- QA-368: spec docs still quote 'receipt' -> owner to confirm wording/update spec.
