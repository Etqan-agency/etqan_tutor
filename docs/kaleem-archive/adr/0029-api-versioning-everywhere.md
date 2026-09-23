---
number: 0029
title: Every API surface is versioned, and every client reaches it through a versioned base
status: accepted
date: 2026-09-04
extends: ADR-0017
---

## Context

ADR-0017 (2026-06-10) chose URL-path versioning and mounted the API at `/api/v1/`. It
settled the *scheme*. It did not make the rule general or checkable, and three gaps have
since become visible as more modules landed:

1. **It reads as a description of `identity`, not a rule for every module.** Each new module
   (`billing`, `scheduling`, and the seven still to come) mounts its own router. Nothing
   states that they must, and nothing fails if one does not.
2. **Nothing enforces it.** A `path("api/notifications/", …)` added to `config/urls.py`
   would work perfectly, ship, and be discovered only when a client needed a v2. The cost of
   this mistake is paid entirely in the future, which is exactly the kind of mistake nobody
   catches in review.
3. **It says nothing about clients.** The dashboard happens to be correct — `VITE_API_URL`
   carries `/api/v1/` and `src/lib/api.ts` cites the ADR — but that is one developer's care,
   not a rule. A mobile client is planned for v2 (ADR-0011), and "don't hardcode URLs" (the
   CLAUDE.md don't-do-this list, #10) does not say "and include the version".

## Decision

**Every API surface is versioned, every client reaches it through a versioned base, and CI
proves it.**

1. **Every module's API mounts under the current version prefix.** `/api/v1/<module>/…`,
   via `config.api_router`. A module that adds routes anywhere else is a defect, not a
   style choice. This covers all ten business modules, present and future.

2. **The unversioned allowlist is closed and explicit.** Exactly three things live outside
   the prefix, for stated reasons:
   - `/health/live/`, `/health/ready/` — infrastructure liveness, consumed by the deploy's
     blue-green probe, not by product clients.
   - `/accounts/…` — allauth's own third-party-managed flows.
   - the Django admin at `settings.ADMIN_URL` — an operator surface, not an API.

   Adding a fourth entry requires an ADR. The point of an allowlist is that it is short and
   growing it is deliberate.

3. **CI enforces it.** A test walks the resolved URLconf and asserts every registered route
   is either under `/api/v<n>/` or in the allowlist above. This turns a convention that was
   previously kept by attention into one kept by the build — the same move ADR-0026 made for
   coverage, for the same reason: a rule nobody can violate accidentally is worth more than
   a rule everybody agrees with.

4. **Clients never construct an unversioned base.** The version belongs in the configured
   base URL, not sprinkled through call sites:
   - `dashboard`: `VITE_API_URL` includes `/api/v1/`; `src/lib/api.ts` is the only place it
     is read. No feature module builds its own base.
   - any future client (the v2 mobile app) does the same.
   - Per-call paths are relative — `identity/me/`, not `/api/v1/identity/me/` — so a version
     bump is one config change, not a find-and-replace across a codebase.

5. **Deprecation policy, restated so it is somewhere enforceable.** Additive,
   backward-compatible changes stay within a version. A breaking change adds `/api/v2/`
   while `v1` keeps working; we support the current major and one prior. Dropping a major
   requires an ADR recording who still uses it.

## Consequences

**Good**

- The rule now covers the nine modules not yet built, not just the one that existed when
  ADR-0017 was written.
- The failure mode this prevents — an unversioned route shipping and being discovered only
  when a v2 is needed — becomes a red build instead of a future migration problem.
- A version bump stays a configuration change on each client rather than a code change.
- The allowlist makes the three deliberate exceptions legible, instead of leaving future
  readers to guess whether `/health/` was an oversight.

**Bad / costs**

- One more CI check to maintain, and it will occasionally be the thing standing between
  someone and a legitimately unversioned endpoint. That is the intended friction: the answer
  is an ADR entry, not a bypass.
- URL-path versioning's known cost stands (ADR-0017): a genuine `v2` means duplicated route
  trees for the overlap period, not a header flip.
- The enforcement test is coupled to the URLconf's shape and will need care if routing is
  ever restructured.

## Alternatives considered

- **Leave ADR-0017 as-is and rely on review.** Rejected: review is precisely what would not
  catch this, because an unversioned endpoint works perfectly today and costs nothing until
  a v2 exists. The whole hazard is that the mistake is invisible at the moment it is made.
- **Enforce with a lint rule / grep over `urls.py`.** Rejected: it inspects source text
  rather than the resolved URLconf, so it misses anything included dynamically and produces
  false confidence.
- **Version per module** (`/api/identity/v1/…`). Rejected: clients would track N version
  numbers, and the whole point of one prefix is one migration decision per client.
