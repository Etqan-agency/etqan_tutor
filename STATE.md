# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 4 (subscriptions & scheduling, B0 milestone 4) in review: branch `feat/subscriptions-scheduling`
in backend, dashboard and meta (spec `docs/superpowers/specs/2026-09-24-subscriptions-scheduling-design.md`,
plan `docs/superpowers/plans/2026-09-24-plan-4-subscriptions-scheduling.md`). Admins create
subscriptions with weekly slots and pauses, sessions generate ahead, an hourly job per academy
pauses, resumes and expires them, and renewals carry extra sessions over. Today board and
generate-for-range are live; teacher/student/parent screens are Plan 5.

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 5: attendance, session reports and the teacher, student and parent screens. It must use
`scheduling.services` (the `CONSUMING` rule and `untouched_sessions`) rather than re-deriving them.

## Follow-ups (from Plan 4)

- Changing the academy timezone leaves already-generated sessions at their old UTC instant.
- Deactivated students and teachers keep generating sessions until the subscription expires.
- A renewal that starts today can duplicate a slot session that already started today on the old subscription.
- The teacher and course pickers in the subscription forms cap at 100.

## Standing warnings

- Deploy is not wired yet: no staging, no production. Wildcard TLS (`*.domain`) needs a DNS-01 ACME challenge — handled in the deploy plan.
- Deploy order (infra `scripts/ship.sh`): `migrate` + `bootstrap_platform` run from the new image before the new colour starts. Production refuses to boot without `DJANGO_S3_BUCKET` (+ AWS keys, public-read bucket policy; see `infra/.env.production.example`).
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
