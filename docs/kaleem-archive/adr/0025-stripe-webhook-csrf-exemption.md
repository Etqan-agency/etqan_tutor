---
number: 0025
title: Stripe webhook CSRF exemption
status: accepted
date: 2026-07-30
---

## Context

Phase B (billing) adds `POST /api/v1/billing/webhook/`: Stripe's server-to-server
callback for checkout completion, subscription updates/cancellation, and invoice
events. This request has no browser, no session cookie, and no CSRF token — Stripe's
servers call it directly.

Our global rule, non-negotiable since the rebuild started, is CSRF always on. The old
MVP disabled CSRF wholesale to work around exactly this kind of integration pain, and
that is explicitly on the "don't do this" list in `CLAUDE.md`. We need a callback Stripe
can reach without a session, without reopening that hole for the rest of the API.

## Decision

Exempt exactly one endpoint, `POST /api/v1/billing/webhook/`, and nothing else:

- `StripeWebhookView` carries `@method_decorator(csrf_exempt, name="dispatch")`,
  `authentication_classes = []`, and `permission_classes = [AllowAny]`.
- In place of a session/CSRF token, the request is authenticated by verifying the
  `Stripe-Signature` header as an HMAC against `DJANGO_STRIPE_WEBHOOK_SECRET`, inside
  `billing.services.handle_webhook`, **before** any state change. A missing or invalid
  signature raises `ValidationError`, mapped to HTTP 400 by the shared DRF exception
  handler (`kaleem/platform/drf.py`); no row is read or written on that path.
- Every handler is additionally idempotent via `StripeEventLog`: each Stripe event id is
  recorded and replays are a no-op, so a retried delivery (Stripe retries on non-2xx, and
  operators may replay events from the Stripe dashboard) cannot double-apply.
- The view carries an inline docstring stating it is CSRF-exempt by design, the only such
  endpoint in the codebase, and that the pattern must never be copied to a
  session-authenticated endpoint.

## Consequences

**Positive:**
- The rest of the API keeps CSRF enabled with no exceptions; the exemption is scoped to
  one URL, one view, with the reasoning inline where the next reader will see it.
- Signature verification plus idempotency means a replayed or duplicated delivery is
  provably safe, not just assumed safe.

**Costs / risks:**
- A leaked `DJANGO_STRIPE_WEBHOOK_SECRET` is equivalent to an attacker forging arbitrary
  billing state (activate/cancel subscriptions, mark invoices paid) — there is no second
  factor. The secret is rotated via env var and Stripe's dashboard, no code change
  required, and standard secret-handling rules (never logged, never committed) apply.
  See ADR-0023 for how we already treat secrets and PII as sensitive by default.
- Any future provider callback (a second payment processor, an OAuth webhook, etc.) needs
  its own threat model and its own ADR — this decision covers Stripe's webhook only, not
  "CSRF exemptions" as a general pattern.
- Reviewers must treat `csrf_exempt` anywhere outside this one view as a red flag; it
  should never appear on a cookie-authenticated endpoint.
