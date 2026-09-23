---
number: 0018
title: Transactional email sent via Celery
status: accepted
date: 2026-06-10
---

## Context

Account emails (verification, resend-verification, password reset) were sent
synchronously inside the request via SMTP/SES. Each send added ~2s of latency
(observed on staging) and coupled request success to SES availability — a slow or
failing provider would slow or 500 the request. We already run Celery + Flower, so
email is a natural fit for a background task.

A related latent bug surfaced: `config/__init__.py` never imported the Celery app, so
`@shared_task` bound to Celery's *default* (unconfigured) app in the web process and in
tests. `.delay()` from gunicorn would not reach the configured Redis broker — tasks
would be silently lost. The workers happened to work only because they are launched with
`-A config.celery_app`.

## Decision

Send all allauth account emails via a Celery task.

- A custom adapter, `kaleem.identity.adapter.CeleryAccountAdapter` (set as
  `ACCOUNT_ADAPTER`), overrides `send_mail`: it still **renders** the message in the
  request (rendering needs the request/Site context to build correct links), then hands
  the rendered message to `kaleem.platform.tasks.send_email_message.delay(...)`. Only the
  SMTP send runs in the worker.
- `send_email_message` rebuilds the `EmailMultiAlternatives` and sends it, with
  `autoretry_for=(Exception,)` + backoff (3 tries) for transient SES failures.
- `config/__init__.py` now imports the Celery app so it is the default whenever Django
  loads (web, tests, worker). Tests run with `CELERY_TASK_ALWAYS_EAGER` +
  `CELERY_TASK_EAGER_PROPAGATES` so task failures surface loudly.

## Alternatives considered

- **Keep sending synchronously** — simplest, but every register/resend/reset blocks ~2s
  on SES and fails the request if SES is down. Rejected.
- **Override `send_messages` / a custom email backend that enqueues** — would also catch
  non-allauth mail, but serializing an arbitrary `EmailMessage` for the broker is
  fiddlier; the adapter is the precise, allauth-blessed seam. Revisit if non-allauth
  email appears (e.g. the future `notifications` module).

## Consequences

- Register/resend/reset return immediately (register dropped from ~2.0s to ~0.12s);
  delivery happens in the worker and retries on failure.
- Email sends are now visible and monitorable in Flower.
- The web process correctly enqueues to the Redis broker (the `config/__init__.py` fix is
  required for *any* `.delay()` from gunicorn to work).
- Rendering still happens in-request; if a future email is expensive to render, move the
  render into the task too (passing only the context).
