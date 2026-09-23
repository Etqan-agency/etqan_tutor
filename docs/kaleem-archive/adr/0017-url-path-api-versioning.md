---
number: 0017
title: URL-path API versioning (/api/v1/)
status: accepted
date: 2026-06-10
---

## Context

The API shipped unversioned (`/api/identity/...`). Once a frontend (and later a
mobile client) depends on it, breaking changes need a migration path that doesn't
strand existing clients. We need a versioning scheme before more endpoints land.

## Decision

**URL-path versioning** via DRF `URLPathVersioning`. Each major version is mounted at a
literal path prefix — today `path("api/v1/", include(api_router))` — with
`ALLOWED_VERSIONS = ["v1"]` and `DEFAULT_VERSION = "v1"`. `request.version` is populated
(defaulting to `v1`) and available to views/serializers for future per-version
branching. A literal prefix (rather than a `<version>` capture) keeps `reverse()` working
for the Swagger/ReDoc views, which live under the same prefix. A new major is purely
additive: add `path("api/v2/", ...)` and `"v2"` to `ALLOWED_VERSIONS`.

What is versioned:
- **Business API** — `/api/v1/identity/...` (and every future module).
- **Schema + docs** — `/api/v1/schema/`, `/api/v1/docs/`, `/api/v1/redoc/`, so the docs
  always describe the version in their own path.

What stays unversioned:
- **Health** — `/health/live/`, `/health/ready/` (infra liveness, not the product API).
- **allauth** — `/accounts/...` (third-party-managed verification/reset flows).

Policy: additive, backward-compatible changes stay within a version. A breaking change
introduces a new major prefix (`/api/v2/`) while the previous one keeps working; support
the current and one prior major.

## Alternatives considered

- **Accept-header / custom-header versioning** — keeps URLs clean but the version is
  invisible in logs/proxies, harder to curl and cache (needs `Vary`), and easy for
  clients to forget. Rejected for a web SPA + future mobile where explicit, cacheable
  URLs win.
- **Query-param versioning** (`?version=v1`) — discouraged by DRF; muddies caching and
  bookmarking. Rejected.
- **No versioning** — leaves no migration path for breaking changes. Rejected.

## Consequences

- All API URLs gain a `/v1` segment; the frontend API client base becomes `/api/v1`.
- Existing endpoint tests update to the `/api/v1/` prefix (mechanical).
- `SPECTACULAR_SETTINGS["SCHEMA_PATH_PREFIX"]` becomes `/api/v[0-9]+` so the version
  segment is stripped from operation grouping.
- Traefik routing is unchanged (`/api/v1/...` is still under `/api/`).
- Introducing `v2` later is purely additive: add it to `ALLOWED_VERSIONS` and branch
  only the endpoints that change.
