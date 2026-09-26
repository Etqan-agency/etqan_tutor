# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 7 (teacher payroll, B0 milestone 7) built and in review: branch `feat/payroll` in backend,
dashboard and meta (spec `docs/superpowers/specs/2026-09-26-payroll-design.md`, plan
`docs/superpowers/plans/2026-09-26-plan-7-payroll.md`). New tenant app `etqan.payroll`: admins set
teachers' rates (a default and per course, in the teacher's pay currency) and bonuses and deductions,
generate a month's draft payslips from completed sessions (teacher present or not marked), issue them
once the month has ended (which freezes them and locks their sessions in scheduling), mark them paid
and export CSV; teachers see and print their own issued and paid payslips at `/app/payslips/<id>/print`.
The e2e suite covers the journey through the Caddy edge.

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 8 of the roadmap. The pay rule is `payroll.services.rules.PAYS`, the amount `session_amount`,
and payslips come only from `build`; the session lock is scheduling's (`lock_sessions`,
`refuse_if_paid`). Never restate any of them. Scheduling never imports payroll or billing.

## Follow-ups (from Plans 4–7)

- Changing the academy timezone leaves already-generated sessions at their old UTC instant.
- Deactivated students and teachers keep generating sessions until the subscription expires.
- A renewal that starts today can duplicate a slot session that already started today on the old subscription.
- The teacher, course and student pickers in list filters, forms and the Rates page cap at 100.
- Restore is allowed on any cancelled session, even inside a pause or on an ended subscription.
- A teacher's attendance controls open within a minute of the start (the list re-reads each minute), not at the exact second.
- `seed_dev` marks and reports past sessions in every academy, not only the demo one.
- A teacher or family in a far timezone sees "Today" and "This week" roll over at the academy's midnight, not their own (PM6).
- A subscription edited after its invoice keeps the invoice's amount; subscriptions created by seeds or services are not invoiced.
- A session completed after its month's payslip was issued is never paid; generate names the teacher under "unpaid sessions" and the admin adds a bonus on a later month (corrections are adjustments). The warning keeps showing on every regenerate of that month, even after the bonus.
- An adjustment created and deleted while an issue is running can fail the issue with a 500 (very narrow window; not fixed).
- The adjustment dialog labels an old-currency amount in its old currency when the teacher is beyond the 100-person picker cap.
- Adjustments left in a currency the teacher is no longer paid in stay pending until edited (generate names them).
- Reports stay writable on a payroll-locked session (staff notes, not pay).
- Payslip notifications are Plan 8; incentives, per-student rates, fixed salary, balances and salaries as expenses are B4.
- No session or unpaid-invoice reminders yet (Plan 8, B5). No gateways, refunds or family accounts (B1, B3).

## Standing warnings

- Deploy is not wired yet: no staging, no production. Wildcard TLS (`*.domain`) needs a DNS-01 ACME challenge — handled in the deploy plan.
- Deploy order (infra `scripts/ship.sh`): `migrate` + `bootstrap_platform` run from the new image before the new colour starts. Production refuses to boot without `DJANGO_S3_BUCKET` (+ AWS keys, public-read bucket policy; see `infra/.env.production.example`).
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
