---
number: 0016
title: Transactional email via AWS SES (SMTP)
status: accepted
date: 2026-06-10
---

## Context

Identity uses django-allauth with `ACCOUNT_EMAIL_VERIFICATION = "mandatory"`, so
registration sends a verification email. Locally this uses the console backend. In
production `EMAIL_BACKEND` defaulted to Django's SMTP backend but **no SMTP host was
ever read from env**, so the send tried `localhost:25`, failed, and `POST
/api/identity/register/` returned 500 on staging while health checks stayed green.

We need a real transactional email provider for verification and password-set/reset
mail, and a settings path that reads its configuration from env.

## Decision

Use **AWS SES over SMTP**. The backend reads provider-agnostic SMTP settings from env
(`DJANGO_EMAIL_HOST`, `DJANGO_EMAIL_PORT`, `DJANGO_EMAIL_HOST_USER`,
`DJANGO_EMAIL_HOST_PASSWORD`, `DJANGO_EMAIL_USE_TLS`) plus a verified
`DJANGO_DEFAULT_FROM_EMAIL`; defaults are Django's own so an unset config is inert
rather than wrong. Production points these at SES SMTP
(`email-smtp.<region>.amazonaws.com:587`, STARTTLS) via `.env.production`.

SMTP (not the SES API / django-anymail) because the app runs on a self-hosted VPS with
no EC2 instance role — SES SMTP credentials work from anywhere and keep the settings
provider-agnostic (switching providers is an env change, not a code change).

## Alternatives considered

- **Resend / Postmark / Mailgun** — simpler onboarding and good DX, but SES is cheapest
  at scale and was the chosen provider. The SMTP settings are provider-agnostic, so a
  later switch is just env vars.
- **django-anymail + SES API (boto3)** — AWS-native, adds delivery webhooks/tracking,
  but needs IAM credentials and a dependency; unnecessary for verification mail on a
  non-AWS host. Can revisit if we want event tracking.
- **Leave console backend in production** — rejected; users never receive verification
  links.

## Consequences

- Register/verification/password emails work in production once the SES env vars are set
  on the VPS.
- Operational prerequisites (one-time, owner: ops): verify the sending domain in SES
  (SPF/DKIM DNS records), request removal from the SES sandbox, and create SMTP
  credentials. Until the domain is verified and the account is out of the sandbox, SES
  only delivers to verified addresses.
- `DEFAULT_FROM_EMAIL` must be an SES-verified sender; mismatches are rejected at send.
- Secrets live only in `.env.production` on the VPS (never committed).
- Follow-up: allauth email branding still uses the default Site name; set the `Site`
  record's domain/name for correct branding (the confirm link itself uses the request
  host, so it already targets the right domain).
