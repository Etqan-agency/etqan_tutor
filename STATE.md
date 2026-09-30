# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 12b (session supervision, B1 plan 3 of 4, second half) built and in review: branch
`feat/supervision` in backend, dashboard and meta (spec
`docs/superpowers/specs/2026-09-28-roles-permissions-design.md`, plan
`docs/superpowers/plans/2026-09-29-plan-12b-supervision.md`). Plan 12a (staff roles and permissions)
is merged. `AcademySettings.supervision_enabled` ("General supervision", off by default) gates it all:
while off, no supervisor field is sent, the supervision routes and the session PATCH answer 404, and a
`supervisor_id` in a subscription body is ignored; the stored values are kept. A supervisor is an
active staff account holding `session.supervise` through an active role
(`access.services.supervisors_queryset` / `get_supervisor`). `Subscription.supervisor` and
`Session.supervisor` / `supervisor_attendance` / `opened_by_supervisor_at` are new (nullable or
`db_default`). The rules live in `scheduling.services.supervision`: generated sessions copy the
subscription's supervisor; a subscription change moves only its unstarted sessions (resetting their
supervisor attendance and opening); the session PATCH overrides one session, `supervisor_id` behind
`session.update` and `supervisor_attendance` behind `attendance.update`; Open works from 10 minutes
before the start until the end (UTC instants) and records the first opening; the supervisor marks
only their own attendance. `supervision/`, `supervision/<id>/open/`, `supervision/<id>/attendance/`
(`session.supervise`, now in `registry.IN_USE`) and `supervision/supervisors/` (the pickers) are new.
The dashboard has the switch in Settings → Academy, the supervisor on the subscription form, Edit
dialog, summary, session page and sessions list, and My supervision (`/scheduling/supervision`, in
the nav for a staff supervisor while the switch is on); Open also shows the meeting link as a real
`<a>` once known, since a mutation's `window.open` can be silently blocked on Safari/iOS. `demo`
seeds supervision on, with Sara on Yusuf's Tajweed subscription. A staff editor may now remove a
role only if they hold its codes, whether removed through `role_ids` on a staff account or directly
from a role's own `permissions` (Plan 12a's open finding, closed in the final review: emptying a
role's codes used to check only additions). Beyond the plan: Open and the supervisor's attendance
look the session up by supervisor only, with no date filter, so a supervisor can open a session
running past the academy's midnight and mark attendance late with no end (D4); My supervision lists
soonest first and keeps a session that is still running past the academy's local midnight on the
list too. The e2e suite covers the journey through the Caddy edge.

## Next

Open the PRs (backend, dashboard → `main`; meta → `master`), get meta CI green, merge backend then
dashboard, bump the meta pointers, merge meta; nothing merges without the user's approval. Then
Plan 13 (feature toggles), which absorbs "General supervision" into the academy's toggles. The
supervision rules live only in `etqan.scheduling.services.supervision`, and who may supervise only in
`access.services.supervisors_queryset`; never restate them elsewhere.

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
- Supervisors get no notifications either (R-7); a supervisor learns of an assignment from My
  supervision only.
- A subscription's supervisor change overwrites a per-session override on its unstarted sessions (the
  latest decision wins), and resets their supervisor attendance and opening.
- The supervisor pickers list every supervisor, unpaged; an academy with hundreds would want a search.
- Sessions inside the 10-minute pre-start window still count as unstarted, so a subscription
  supervisor change or a regeneration resets an opening/attendance recorded minutes earlier
  (consistent with D3).
- Dashboard `test:coverage` once hit timeouts in `StudentsList.test.tsx` and `PageEditor.test.tsx`
  under load (clean on rerun, not reproduced in 3 focused runs); watch CI, raise `testTimeout` if it
  recurs.
- RatesPage without `teacher.view_any`: a teacher with no counting rate can't have rates added or
  edited by that user (currency unknown).
- Decided (final review, Plan 12a): the students bulk action `create_family` needs `student.update`
  *and* `family.create` for staff (admins pass on `student.update` alone); `add_to_family` and
  `remove_from_family` stay on `student.update` alone. Subscription create/renew keep issuing their
  derived invoice without `invoice.create`, by design — the invoice there is derived, not a fresh one
  the caller chose to create.
- Payments ride inside the invoice detail, so `invoice.view` shows them without `payment.view_any`;
  the Supervisor sees a subscription's `payment_status` through `is_office` (D7). Owner to confirm.
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
