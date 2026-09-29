# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 12a (staff roles and permissions, B1 plan 3 of 4) built and in review: branch `feat/roles` in
backend, dashboard and meta (spec `docs/superpowers/specs/2026-09-28-roles-permissions-design.md`,
plan `docs/superpowers/plans/2026-09-28-plan-12a-roles.md`). `User.Role` gains `staff`. A new tenant
app `etqan.access` holds the permission registry (`registry.py`: 22 resources × TutorHamster's 12
verbs, 4 greyed pages, 5 widgets; `IN_USE` is exactly what the routes declare), `StaffRole` (names,
codes, active, members; retired, never deleted) and the Supervisor preset (migration `0002` and
`create_academy`). Every `/api/v1/` route declares its code in `permission_codes`, checked by
`platform.permissions.HasCode`; `access/tests/test_routes.py` holds the route table and fails on any
route left out. Admins pass everything; staff pass with a code one of their active roles holds, loaded
once per request through the loader `AccessConfig.ready()` registers; past the check they see what
admins see (`is_office`). `access/` serves the registry, roles and staff (invited through identity)
with the §4.2 escalation guards as 403s that name their field; `me/` carries `permissions` and
`is_super_admin`. Two escalation guards go beyond the plan: a staff user may restore a retired role
only if they hold all its codes, and may change the email of, deactivate, or reactivate only a staff
account whose codes they hold — counting retired roles; reactivation included (prevents takeover via
email change, or via reactivating an account an admin deactivated once its stronger role is retired
and later restored). The dashboard's `can()`/`useCan()` gates
the nav, every office screen (`staticData.permission`; `PermissionGate` says "You don't have access
to this page.") and every write action; a screen's secondary lookups (tags, courses, teachers,
students, parents, invoices/sessions panels, filters) are fetched only when the user holds their
code, otherwise current values show read-only or the dependent control is hidden, and a read-only
form disables every control. Settings → Roles (the matrix editor) and People → Staff are new. `demo`
seeds Sara Supervisor. The e2e suite covers the journey through the Caddy edge.

## Next

Open the PRs (backend, dashboard → `main`; meta → `master`), get meta CI green, merge backend then
dashboard, bump the meta pointers, merge meta; nothing merges without the user's approval. Then
Plan 12b (session supervision), which switches `session.supervise` into `registry.IN_USE` with its
routes. A new route declares its code in `permission_codes` and a row in
`access/tests/test_routes.py`; a new office screen names `staticData.permission`. The escalation
rules live only in `etqan.access.services` (`_clean_codes`, `_roles_to_assign`, `update_staff`);
never restate them elsewhere.

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
- A staff account holding a form's write code but not its pickers' list codes (teachers, courses,
  students) sees an empty picker; the Supervisor preset holds the list codes it needs. This
  "empty picker" limitation applies only to create/edit forms (SubscriptionForm, InvoiceForm,
  AdjustmentDialog, RateDialog); other screens' secondary lookups are gated on the viewer's code
  instead (STATE.md's Plan 12a paragraph).
- On a read-only rich-text body (site pages, the home page) typing is blocked, but the toolbar
  buttons still reformat it (nothing saves). The roles picker and the staff Role filter cap at 100
  roles.
- Staff receive no notifications (R-7); admins alone are told.
- RatesPage without `teacher.view_any`: a teacher with no counting rate can't have rates added or
  edited by that user (currency unknown).
- Decided (final review, Plan 12a): the students bulk action `create_family` needs `student.update`
  *and* `family.create` for staff (admins pass on `student.update` alone); `add_to_family` and
  `remove_from_family` stay on `student.update` alone. Subscription create/renew keep issuing their
  derived invoice without `invoice.create`, by design — the invoice there is derived, not a fresh one
  the caller chose to create.
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
