# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 11 (family accounts and payer, B1 plan 2 of 4) built and in review: branch `feat/families` in
backend, dashboard and meta (spec `docs/superpowers/specs/2026-09-27-families-design.md`, plan
`docs/superpowers/plans/2026-09-27-plan-11-families.md`). In `etqan.identity`: a `Family` (name,
notes, active, a payer) and `StudentProfile.family`, one column, so one family per student; the
account type is derived from it (`services.account_type`), never stored. A payer is one of the
family's students or an active parent of one (F-2); `payer_needs_choosing` is computed on every
read (`families_queryset`'s two EXISTS annotations), never stored, and a flagged or retired family
supplies no payer. Linking goes through `_claim`, a conditional UPDATE, so two admins racing for
one student get a 400, never a move. The API adds `people/families/` (list, create, read, patch; no
PUT or DELETE) and `families/payers/?students=`; students gain `account_type` and `family` in
rows, CSV and `me/`, the `account_type` and `family` filters, and the bulk `create_family`,
`add_to_family` and `remove_from_family` (skipped students reported, never moved). Billing's
`payer_options` puts `identity_services.family_payer` first, then guardians, then the student,
deduplicated; existing invoices never change. The id filters are junk-safe (`as_int`: `int()` in
`try`, so a 5000-digit id no longer 500s). The dashboard has People → Families (dialogs, retire and
restore, a family page), the account type and family chip, filters and bulk actions on students,
"Family payer" on the invoice form and the family on the profile card. The e2e suite covers the
journey through the Caddy edge.

## Next

Open the PRs (backend, dashboard → `main`; meta → `master`), get meta CI green, merge backend then
dashboard, bump the meta pointers, merge meta; nothing merges without the user's approval. Then
Plan 12 (roles and permissions). The family rules live only in `etqan.identity.services`
(`_family_students`, `_payer_for`, `_claim`, `payer_needs_choosing`, `family_payer`); billing
asks `family_payer` and nothing else. Never restate them elsewhere.

## Follow-ups (from Plans 4–9)

- Staging uploads are linked at the S3 store's in-network address (`http://s3:9000/...`), so
  browsers cannot load them until staging uses real S3 or a public custom domain (STAGING.md §7).
- MinIO's images are no longer pullable; the overlay uses RustFS 1.0.0 (service `s3`).
- `deploy-staging` declares `environment: staging`; if the org's plan has no environments for
  private repos, drop that line and use repository secrets (STAGING.md §3); the master-only
  branch policy on manual dispatch is lost with it.
- GitHub keeps only the newest pending deploy per concurrency group: start a rollback when no
  deploy is waiting.
- The production deploy workflow, monitoring alerts, backups and restore drills are not built.
- Plan 9's open review follow-ups (all minor, deferred; none blocking): `ship_test.sh` doesn't pin
  overlay-line edge cases (last-line-wins, CRLF, quotes) though `ship.sh` handles them; `manage.sh`
  takes no stdin (`-i`); `ship.sh`'s banner names `ghcr.io` even under `ETQAN_REGISTRY`;
  `deploy-staging.sh`'s rsync `-e` escapes with `printf %q` (backslashes, which rsync's `-e` parser
  ignores), so a key or known-hosts path with spaces breaks it; `staging-sim-needed.sh` fails closed
  on a brand new submodule (the CI step runs the simulation whenever the script fails or prints
  anything but true/false); the simulation rebuilds the images rather than pulling the ones `images`
  pushed; CI's "Server logs" step is not scanned by `no_secret_in`; the PR gate misses
  dashboard/marketing `package.json`, lockfiles and `vite.config`, and backend changes the sim
  exercises beyond the listed files (`master` still runs the sim every time); check a built image
  once for leaked `x-access-token` git URLs.
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
- The students list's Family filter and "Family to add to" cap at 100 families (D10).
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
- No session or unpaid-invoice reminders yet (Plan 8, B5). No gateways, refunds, combined family invoices or family wallets (B3).

## Standing warnings

- No staging server or domain yet: `deploy-staging` skips until the `staging` secrets exist (infra/STAGING.md). No production deploy workflow. Wildcard TLS (`*.domain`) uses Cloudflare DNS-01 (`TLS_MODE=cloudflare`, the default).
- Deploy order (infra `scripts/ship.sh`): `migrate` + `bootstrap_platform` run from the new image before the new colour starts. Production refuses to boot without `DJANGO_S3_BUCKET` (+ AWS keys, public-read bucket policy; see `infra/.env.production.example`).
- A new NOT NULL column needs `db_default=` (Django's DB-side default), so the old colour keeps
  serving reads with the old model while `ship.sh` migrates and the new colour starts (Plan 10 M4).
- Notifications (Plan 8) decide who is told what only in `etqan.notifications` (`finders.FINDERS`,
  `recipients.resolve`, `text.render`, `links.path_for`); no other app imports it (the dev seeds
  excepted), and a new notice type is a finder there, never a call from a domain app. Never restate
  the pay rule, the session lock, `derive` or `overdue`.
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
