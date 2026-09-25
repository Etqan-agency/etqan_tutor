# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 6 (billing: invoices and manual payments, B0 milestone 6) built and in review: branch
`feat/billing` in backend, dashboard and meta (spec `docs/superpowers/specs/2026-09-25-billing-design.md`,
plan `docs/superpowers/plans/2026-09-25-plan-6-billing.md`). New tenant app `etqan.billing`: creating
or renewing a subscription through the API invoices it in the same transaction (switch and due days in
academy settings); admins issue, edit and void invoices, record and delete payments (status follows,
overpaying refused), see revenue this month per currency and overdue invoices, and export CSV;
parents and students see their invoices and print a branded invoice or receipt at `/app/invoices/<id>/print`.
The e2e suite covers the journey through the Caddy edge.

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 7 of the roadmap. Invoice status goes through `billing.services` (`status_for`, `add_payment`,
`delete_payment`, `void_invoice`), numbers through `next_number`, the payer through `payer_choices`;
never restate any of them. Scheduling's services never import billing.

## Follow-ups (from Plans 4–6)

- Changing the academy timezone leaves already-generated sessions at their old UTC instant.
- Deactivated students and teachers keep generating sessions until the subscription expires.
- A renewal that starts today can duplicate a slot session that already started today on the old subscription.
- The teacher, course and student pickers in list filters and forms cap at 100.
- Restore is allowed on any cancelled session, even inside a pause or on an ended subscription.
- A teacher's attendance controls open within a minute of the start (the list re-reads each minute), not at the exact second.
- `seed_dev` marks and reports past sessions in every academy, not only the demo one.
- A teacher or family in a far timezone sees "Today" and "This week" roll over at the academy's midnight, not their own (PM6).
- Auto-invoicing is on for existing academies at deploy (the migration defaults it on); an academy that doesn't want it switches it off in Settings → Academy.
- `just seed` on an existing database backfills invoices only for academies that have none.
- A subscription edited after its invoice keeps the invoice's amount; the admin edits or voids it by hand (spec §9).
- Subscriptions created by the seeds or by services (not the API) are not invoiced automatically.
- No payroll locks yet (Plan 7): nothing freezes a marked session.
- Refunds, payment gateways, session and unpaid-invoice reminders, and family accounts are later phases (reminders Plan 8/B5; gateways, refunds, family accounts B1/B3).

## Standing warnings

- Deploy is not wired yet: no staging, no production. Wildcard TLS (`*.domain`) needs a DNS-01 ACME challenge — handled in the deploy plan.
- Deploy order (infra `scripts/ship.sh`): `migrate` + `bootstrap_platform` run from the new image before the new colour starts. Production refuses to boot without `DJANGO_S3_BUCKET` (+ AWS keys, public-read bucket policy; see `infra/.env.production.example`).
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
