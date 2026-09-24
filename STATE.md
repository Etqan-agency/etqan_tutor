# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 3 (people & catalogue, B0 milestone 3) in review: branch `feat/people-catalogue` in backend,
dashboard and meta (spec `docs/superpowers/specs/2026-09-24-people-catalogue-design.md`, plan
`docs/superpowers/plans/2026-09-24-plan-3-people-catalogue.md`). Admins manage students, parents,
teachers, admins, courses, packages and academy settings; invites arrive in each person's language.
Self-registration and parent-created children are gone (returns in B9).

## Next

Open PRs, get meta CI green, merge backend then dashboard, bump meta pointers, merge meta. Then
Plan 4: subscriptions, weekly slots and session generation. It must call
`etqan.catalogue.services.sessions_total` and add the "course/package has subscriptions" delete guard.

## Standing warnings

- Deploy is not wired yet: no staging, no production. Wildcard TLS (`*.domain`) needs a DNS-01 ACME challenge — handled in the deploy plan.
- Deploy order (infra `scripts/ship.sh`): `migrate` + `bootstrap_platform` run from the new image before the new colour starts. Production refuses to boot without `DJANGO_S3_BUCKET` (+ AWS keys, public-read bucket policy; see `infra/.env.production.example`).
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
