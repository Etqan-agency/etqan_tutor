# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 5 (sessions, attendance & reports, B0 milestone 5) built and in review: branch
`feat/sessions-attendance` in backend, dashboard and meta (spec
`docs/superpowers/specs/2026-09-25-sessions-attendance-design.md`, plan
`docs/superpowers/plans/2026-09-25-plan-5-sessions-attendance.md`). Teachers mark attendance
on their own sessions once they start and write staff-only reports; admins list, filter, export,
bulk-mark, cancel and restore sessions and see missing reports; students and parents see their
sessions and progress. `sessions_used` now follows the one counting rule with the academy's
absent/excused switches. The e2e suite covers the journey through the Caddy edge.

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 6 of the roadmap. Counting goes through `scheduling.services` (`rules.consuming` inside
`derive`) and attendance through `mark_attendance`; never restate either.

## Follow-ups (from Plans 4–5)

- Changing the academy timezone leaves already-generated sessions at their old UTC instant.
- Deactivated students and teachers keep generating sessions until the subscription expires.
- A renewal that starts today can duplicate a slot session that already started today on the old subscription.
- The teacher and course pickers in the subscription and session filters cap at 100.
- Restore is allowed on any cancelled session, even inside a pause or on an ended subscription.
- A teacher's attendance controls open within a minute of the start (the list re-reads each minute), not at the exact second.
- `seed_dev` marks and reports past sessions in every academy, not only the demo one.
- No payroll locks yet (Plan 7): nothing freezes a marked session.
- No session reminders yet (Plan 8).

## Standing warnings

- Deploy is not wired yet: no staging, no production. Wildcard TLS (`*.domain`) needs a DNS-01 ACME challenge — handled in the deploy plan.
- Deploy order (infra `scripts/ship.sh`): `migrate` + `bootstrap_platform` run from the new image before the new colour starts. Production refuses to boot without `DJANGO_S3_BUCKET` (+ AWS keys, public-read bucket policy; see `infra/.env.production.example`).
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
