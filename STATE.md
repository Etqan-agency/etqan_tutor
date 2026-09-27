# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 9 (E2E and staging deploy, B0 milestone 9, the last) built and reviewed, not yet pushed: branch
`feat/staging` in infra, backend, dashboard and meta (spec
`docs/superpowers/specs/2026-09-27-staging-design.md`, plan
`docs/superpowers/plans/2026-09-27-plan-9-staging.md`). CI builds the three images after the tests
and, on `master`, pushes `ghcr.io/etqan-agency/<name>:<meta-sha>` and `:master`; the `staging-sim` job
deploys them twice (blue/green under a health poll), fails one deploy on purpose, seeds,
smoke-checks and walks `e2e/journey.spec.ts` on a simulated server (sshd + Docker-in-Docker,
`scripts/staging-sim.sh`, `just staging-sim`); `deploy-staging` (reusable, also run by hand for
rollback) deploys to the real server once the `staging` secrets exist and skips green until then.
The edge takes `TLS_MODE` (`cloudflare` default, byte-identical; `internal`), `ship.sh` takes
`ETQAN_OVERLAY=staging` from `.env.production` (S3 store and Mailpit overlay), and `seed_staging`
creates the demo academy once. The journey (Etqan creates an academy → parent reads the absence)
runs in the CI e2e job too. `infra/STAGING.md` documents going live: server, DNS, the six secrets
(a master-only deployment-branch policy on the `staging` environment guards manual dispatch, since
the workflow's own SHA-format/master-ancestry checks live in the same file a branch could edit),
`.env.production`, the first seeded deploy, rollback, and moving off the overlay.

## Next

The commits are made but not pushed. Next: the user approves the push (workflows go over SSH,
`git push git@github.com:Etqan-agency/etqan_tutor.git feat/staging`); then open one PR per repo
(infra, backend, dashboard → `main`; meta → `master`, first pointing submodules at their
`feat/staging` heads for meta CI); nothing merges without the user's approval. After that, check the
first hosted `master` run: `images` pushed the three packages, `staging-sim` green, `deploy-staging`
skipped green (its log shows "Staging not configured"). Then going live is configuration only
(infra/STAGING.md). Open review follow-ups (all minor, deferred; none blocking): `ship_test.sh`
doesn't pin overlay-line edge cases (last-line-wins, CRLF, quotes) though `ship.sh` handles them;
`manage.sh` takes no stdin (`-i`); `ship.sh`'s banner names `ghcr.io` even under `ETQAN_REGISTRY`;
`E2E_MANAGE` set-but-empty takes the remote branch and fails; `manage.ts`'s `execFileSync` has no
timeout; `deploy-staging.sh`'s rsync doesn't quote paths with spaces; `staging-sim.sh`'s cleanup
doesn't guard a user-set `SIM_DIR` before `rm -rf`; `staging-sim-needed.sh` fails closed on a brand
new submodule. Notifications (Plan 8) decide who is told what only in `etqan.notifications`
(`finders.FINDERS`, `recipients.resolve`, `text.render`, `links.path_for`); no other app imports it
(the dev seeds excepted), and a new notice type is a finder there, never a call from a domain app.
Never restate the pay rule, the session lock, `derive` or `overdue`.

## Follow-ups (from Plans 4–9)

- Staging uploads are linked at the S3 store's in-network address (`http://s3:9000/...`), so
  browsers cannot load them until staging uses real S3 or a public custom domain (STAGING.md §7).
- MinIO's images are no longer pullable; the overlay uses RustFS 1.0.0 (service `s3`).
- `deploy-staging` declares `environment: staging`; if the org's plan has no environments for
  private repos, drop that line and use repository secrets (STAGING.md §3).
- GitHub keeps only the newest pending deploy per concurrency group: start a rollback when no
  deploy is waiting.
- The production deploy workflow, monitoring alerts, backups and restore drills are not built.
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

- No staging server or domain yet: `deploy-staging` skips until the `staging` secrets exist (infra/STAGING.md). No production deploy workflow. Wildcard TLS (`*.domain`) uses Cloudflare DNS-01 (`TLS_MODE=cloudflare`, the default).
- Deploy order (infra `scripts/ship.sh`): `migrate` + `bootstrap_platform` run from the new image before the new colour starts. Production refuses to boot without `DJANGO_S3_BUCKET` (+ AWS keys, public-read bucket policy; see `infra/.env.production.example`).
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
