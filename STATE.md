# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 8 (notifications, B0 milestone 8) built and in review: branch `feat/notifications` in backend,
dashboard and meta (spec `docs/superpowers/specs/2026-09-26-notifications-design.md`, plan
`docs/superpowers/plans/2026-09-26-plan-8-notifications.md`). New tenant app `etqan.notifications`:
a beat job (`notifications.scan`, every minute, `for_each_academy`) runs one finder per type (session
reminders, lateness, absences, low and expired subscriptions, issued and overdue invoices, missing
reports) through scheduling's, billing's and identity's read-only services, writes one row per
recipient under a unique `dedupe_key`, renders it once in the recipient's language and time zone,
and emails it once on the branded layout (`notifications.deliver_email`, 3 tries). Every role has a
bell (unread count polled every minute), a Notifications page, and admins a Notifications section in
the academy settings. `manage.py scan_notifications` runs the scan now (the e2e suite uses it).
The e2e suite covers the journey through the Caddy edge. Review fixes on the branch: scheduling's
`missing_reports` takes an optional `now`, and the `report.missing` finder passes the scan's one
instant; the email task fails any non-`OSError` immediately (recorded), and email subjects — the
academy name prefix included — are stripped of line breaks; the settings PATCH answers an unknown
`type` with a 400 on `type`; mark-read returns the fresh row in one read. Final-review fixes: a
subscription handed over to a live renewal is never announced as ended or low; overdue reminders stop
90 days after the due date; each email is queued robustly and every scan re-queues rows pending 5 min
to 24 h; the beat scan expires after 55 s; the low text is worded per count; the Notifications page
returns to page 1 after "Mark all read"; each settings switch names its type.

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
the next milestone of the roadmap. Notifications decide who is told what only in
`etqan.notifications` (`finders.FINDERS`, `recipients.resolve`, `text.render`, `links.path_for`);
no other app imports it (the dev seeds excepted), and a new notice type is a finder there, never a
call from a domain app. Never restate the pay rule, the session lock, `derive` or `overdue`.

## Follow-ups (from Plans 4–8)

- A notice is rendered once: a recipient who changes language or time zone keeps the old text on old
  notices; one whose email is removed before delivery gets `skipped`.
- A guardian linked after a once-per-object notice (a reminder, a low subscription) does not get it.
- `invoice.issued` looks back on `created_at`; an invoice voided within the minute is never announced.
- The bell polls every minute (no push); per-user preferences, WhatsApp and editable templates are B5.
- Scanner cost grows with history: `report.missing` and `subscription.low` (and the pending-email
  re-queue) scan every minute; add an index-served bound or run the state types less often.
- Tail academies can starve past the scan's 240 s soft limit; rotate the order or fan out per academy.
- Scan inserts take FK KEY SHARE on user rows (a possible deadlock with an admin deactivating a user,
  retried next minute); mark-read can wait up to `EMAIL_TIMEOUT` on a row the email task holds.
- Overdue reminders stop 90 days after the due date (`OVERDUE_FOR_DAYS`; the owner may change it).
- `session.late` reaches families 5 min after the start by default; the owner may want a larger one.

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
