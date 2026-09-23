# etqan_tutor — current state

Keep this under ~40 lines: current position only.

## Where we are

Plan 1 (fork, strip, tenancy) merged 2026-09-23. Next: per-academy branding + marketing pages (new scope, being specified), then Plan 2 (people & catalogue).

## Next

Plan 2: people & catalogue (spec §9 milestone 3).

## Standing warnings

- Deploy is not wired yet: no staging, no production. Wildcard TLS (`*.domain`) needs a DNS-01 ACME challenge — handled in the deploy plan.
- Kaleem's staging passwords are in this repo's git history (inherited). Never reuse them.
