# M09 Agent 1 log
- 2026-10-27T20:04:29Z start M09 payroll manual pass
- 2026-10-27T20:25:32Z payslips list/detail/print/generate (Aug/Sep/Oct)/issue/mark-paid/pay-to-balance, rates (add/delete/fixed/bulk/student), adjustments, settings, projections, withdrawals (create/cancel/approve/reject/pay), teacher payslips/ack/balance, role URLs, EN pass, mobile; F-001..029 filed. Test data: QA6 Teacher B rate 75.50, fixed 3000 from Sep 2026, deduction 4000 (15/10), student rate Omar 80, PAY-000044 issued+paid 01/10; PAY-000039 paid to balance; qa-teacher withdrawals 20 (paid), 5 (rejected), 3 (cancelled); bulk default 55 for F02 Teacher + QA6 Teacher C.
- 2026-10-27T20:28:19Z filters/CSV/adjustment edit+delete/percent, teacher EN, admin unknown id, settings toast; F-030..032; Covered list written. Done: 32 findings (F-001..F-032), ~90 step.mjs calls.
- 2026-10-27T21:12:45Z Agent 1 confirmation sweep M09 start
- 2026-10-28T00:26:46Z confirmation sweep (re-run) start
- 2026-10-28T00:35:52Z confirmation sweep done: ~35 step.mjs calls; new findings F-033..F-036 (report-deduction minus flipped, deduction date reversed/Arabic in EN, pay/cancel dialogs don't name request, teacher balance amount misaligned). Data: M09-C1 2.00 approved+paid 28/10, M09-C2 1.00 requested+cancelled, Oct drafts regenerated.
