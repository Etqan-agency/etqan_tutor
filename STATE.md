# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 10 (student and teacher profile depth, B1 plan 1 of 4) built and in review: branch
`feat/profile-depth` in backend, dashboard and meta (spec
`docs/superpowers/specs/2026-09-27-profile-depth-design.md`, plan
`docs/superpowers/plans/2026-09-27-plan-10-profile-depth.md`). In `etqan.identity`: editable emoji
`Tag`s per academy (21 student and 22 teacher presets from `presets.py`, seeded by migration
`0014_preset_tags` in every academy schema and by `create_academy`; unique per kind in either
language, case-insensitively; retire and restore, never delete), `StudentProfile.xp` and
`.nationality`, and an age group derived on the academy's calendar (`ages.py`, never stored).
People take `profile.tag_ids` (a retired tag already on a person stays), the students bulk action
takes `add_tag`/`remove_tag`, the lists filter by `tag`, `nationality` and `age_group` and export
them, and `me/` shows a student's own tags, XP and age group, a parent's children's, and a
teacher's own tags. Nationality is admin-only. The dashboard has Settings → Tags, a tag picker on
the forms, chips, filters and bulk tagging on the lists, and the profile card on `/account`.
The e2e suite covers the journey through the Caddy edge. Post-plan hardening: a concurrent
duplicate-name save maps to a 400, never a 500 (`_save_tag`); `tag_ids` are coerced to integers and
capped at 100 (`_tag_ids()`); a test pins the age group to the academy's calendar in a non-UTC zone
(Pacific/Auckland); the dashboard's tag filter is single-select, though `?tag=` is repeatable on the
API (`ANY` match).

## Next

Open the PRs (backend, dashboard → `main`; meta → `master`), get meta CI green, merge backend then
dashboard, bump the meta pointers, merge meta; nothing merges without the user's approval. Then
Plan 11 (family accounts and payer). Tags, XP, nationality and the age group live only in
`etqan.identity`: the age group is `ages.age_group`/`ages.born_lookups` on `clock.today()`, never a
stored column; the presets are `presets.PRESETS` and `presets.seed`; assignment rules are
`_tags_to_assign` and `_bulk_tag`. Never restate them elsewhere.

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
