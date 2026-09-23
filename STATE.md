# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 1 (fork, strip, tenancy) merged 2026-09-23. Plan 2 (academy sites) in review: branch
`feat/academy-sites` in backend, dashboard, marketing, infra and meta (spec
`docs/superpowers/specs/2026-09-23-academy-sites-design.md`). Every academy host serves its
marketing site at `/`, the dashboard at `/app/`, the API at `/api/`, behind Caddy.

## Next

Open PRs, get meta CI green, then merge in order: marketing, backend, dashboard, infra; bump
meta pointers; merge meta. After that: people & catalogue (v1 spec §9 milestone 3).

## Standing warnings

- Deploy is not wired yet: no staging, no production. Wildcard TLS (`*.domain`) needs a DNS-01 ACME challenge — handled in the deploy plan.
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
