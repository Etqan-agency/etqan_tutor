# F10 Agent 3 (Debugger & Fix Engineer) log

## 2026-10-19 01:25 — Fix cycle 1, attempt 1: ETQAN-QA-029 (P2) → FIXED-UNVERIFIED
- Reproduced via code reading + live: `_pay` only checks `paid_on > today`; `post_salary` uses `spent_on=paid_on`. (REAL)
- Spec check: docs/features/payroll.md, payroll spec §4.4, B4c C-1 define only the upper bound; withdrawals have a lower bound
  (request day). No product intent for unbounded backdating → defect confirmed.
- Fix: `backend/etqan/payroll/services/payslips.py:_pay` refuses `paid_on` before the payslip month's first day (400 `paid_on`).
  Month-start chosen over issue day because payments are recorded after the fact (existing tests pay 30 Jun, issue 1 Jul).
- Tests: new `test_a_payslip_is_not_paid_before_the_month_it_pays` (x2) + API assertion; before 3 failed, after 3 passed;
  payroll+finance 582 passed; ruff clean; lint-imports 54/0. Live REAL: payslip 13 → 400 for 2026-01-01 and 2026-06-30.
- Docs: payroll.md § Lifecycle updated. Evidence: qa/evidence/F10/fix-cycle-1/. No commits.
