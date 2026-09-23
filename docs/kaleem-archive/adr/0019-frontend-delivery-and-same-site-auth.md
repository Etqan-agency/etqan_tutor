---
number: 0019
title: Frontend delivery and same-site auth
status: accepted
date: 2026-06-13
---

## Context

The backend deployed as a GHCR image behind Traefik with blue-green via `ship.sh`. The
frontend had no equivalent: the React dashboard was only build-checked in CI; the Astro
marketing site had no CI at all. Neither was deployable.

We also chose separate subdomains — `app-` for the dashboard, `api-` for the API — which
makes the two cross-origin. The prior roadmap and `CLAUDE.md` stated "same-origin
frontend/backend", which is no longer accurate.

## Decision

1. **Hosts per environment.** Three one-label hosts (Cloudflare cert covers one wildcard
   level): `app[-staging].kaleem.academy` (dashboard), `api[-staging].kaleem.academy`
   (API), `kaleem.academy` + `www` / `staging.kaleem.academy` (marketing). The backend
   moves off `staging.kaleem.academy` to `api-staging.kaleem.academy`.

2. **Same-site session auth (not same-origin).** `app-` and `api-` share the registrable
   domain, so cookies scoped `Domain=.kaleem.academy; SameSite=Lax` flow on
   cross-subdomain XHR without requiring `SameSite=None`. Django is configured with a
   CORS allow-list (`CORS_ALLOWED_ORIGINS`) with credentials, and
   `CSRF_TRUSTED_ORIGINS` covers the dashboard origin. This supersedes the
   "same-origin frontend/backend" wording in `CLAUDE.md` and the roadmap.

3. **Serving — option A (chosen).** Each frontend (`dashboard`, `marketing`) is a
   multi-stage image: `pnpm build` → copy output into `nginx:alpine` → push to GHCR.
   Deployed as a Compose singleton behind Traefik (no blue-green: static, no
   migrations). Cloudflare edge-caches the immutable `/assets/*` hashed bundle.
   Option B (Cloudflare Pages / CDN-first) is reserved as escape hatch **E2** if
   measured app-shell latency demands it.

4. **Process.** Every feature now ships its frontend slice end-to-end. A feature is not
   "done" until the slice is deployed to staging and verified in the browser. The spec
   template gains a mandatory `## Frontend` section.

## Consequences

**Positive:**
- One deploy mental model for all three services (backend, dashboard, marketing).
- Frontend delivery is first-class: dashboard and marketing are deployable on every CI
  green.
- Near-CDN asset latency via Cloudflare for the immutable hashed bundles.

**Costs / risks:**
- Cross-subdomain cookie configuration is subtle; misconfiguring `Domain=` or `SameSite=`
  will silently break auth. Covered by the end-to-end staging gate.
- Static `docker compose up -d` recreates the container — a brief service blip (typically
  a few seconds), not zero-downtime. Acceptable for static assets already cached at the edge.
- Production `www` handling and a production environment are deferred; this ADR covers
  staging first.
- `CLAUDE.md`'s auth bullet is updated to reflect this decision.
