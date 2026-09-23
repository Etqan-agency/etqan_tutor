# Email & privacy cleanup — design

**Status:** approved (design decisions made autonomously per the user's "do all of them" directive on the `tasks.todo` backlog; this is a bug-fix/hardening slice with well-understood root causes).
**Date:** 2026-06-19
**Slice:** 1 of 4 in the post-verification backlog campaign (this → toasts → registration polish → password management).

## Goal

Stop kaleem's outbound emails from (a) showing the wrong/placeholder domain in the
subject and body, and (b) echoing personal data (email addresses, user identifiers)
into email bodies. Back the change with a data-privacy ADR (GDPR/EU by design).

## Backlog items addressed

- `tasks.todo`: "email verify email has invalid domain in subject"
- `tasks.todo`: "for security alert email and confirm request we send email in email body … violates data privacy"
- `tasks.todo`: "create adr to ensure everything we build should follow data privacy laws like GDPR and eu laws"

## Root causes (verified in code)

1. **Invalid domain in subject/body.** The project ships no email templates, so
   django-allauth uses its defaults. allauth's `format_email_subject`
   (`account/adapter.py:154`) prepends `"[{site.name}] "` whenever
   `ACCOUNT_EMAIL_SUBJECT_PREFIX` is `None` — and it is unset in `config/settings/base.py`.
   The default Django `Site` (`SITE_ID = 1`) has name **and** domain `example.com`, so every
   allauth email subject reads `[example.com] …` and the bodies say
   "register an account on example.com" / "Thank you for using example.com"
   (`current_site.name` / `current_site.domain` in `base_message.txt` +
   `email_confirmation_message.txt`).

2. **PII in email bodies.**
   - `kaleem/identity/services.py:206-218` (`_send_email_security_alert`) puts the literal
     changed email address into the alert body — and the "added" / "set_primary" alerts are
     sent to the **current/previous primary**, which can be a *different* address than the one
     named in the body. That discloses one address to the holder of another over plain email.
   - allauth's confirmation message body echoes `{{ user_display }}` (which, with
     `ACCOUNT_USER_MODEL_USERNAME_FIELD = None`, is the user's email).

## Design decisions

- **Subject prefix** → set `ACCOUNT_EMAIL_SUBJECT_PREFIX = env("DJANGO_EMAIL_SUBJECT_PREFIX", default="[Kaleem] ")`
  in `base.py`. This removes `site.name` from *all* allauth subjects in one line, independent of
  environment. (`"[Kaleem] "` keeps the trailing space allauth expects.)
- **Site row** → an identity data migration sets `Site(id=SITE_ID)` to
  `name="Kaleem"`, `domain="kaleem.academy"` (sane defaults; operators may override per-env in
  the admin). Fixes the body domain and the admin display. We do not read env at migration time
  — the default is a constant; per-env domains are an operator concern, not a code concern.
- **Confirmation email body** → override `account/email/email_confirmation_message.txt`
  (and `…_signup_message.txt` → `{% include %}` it) under `kaleem/templates/` to drop the
  `user_display` echo and read cleanly ("You requested to confirm this address for your Kaleem
  account."). The address being confirmed is the recipient's own, but we still avoid restating
  identifiers in the body as a matter of policy.
- **Security alert body** → redact. The alert no longer names the changed address. It states
  *that* a change occurred, how to react (change password / contact support), and links to the
  authenticated dashboard (`{FRONTEND_URL}/account`) where the user can see full detail behind
  auth. The `changed_email` parameter is removed from `_send_email_security_alert` and both
  callers updated. **Decision: omit, not mask** — masking still transmits a fingerprint of the
  address; omission + an authenticated link is the data-minimal choice and matches the user's
  framing.
- **ADR-0023** → records the principle: kaleem is built GDPR/EU-data-protection-by-default;
  concretely, outbound email bodies carry the minimum necessary and never disclose one user's
  personal data to a different recipient; detail lives behind authentication. Lightweight —
  engineering principles, not legal advice.

## Files

- **Modify** `backend/config/settings/base.py` — add `ACCOUNT_EMAIL_SUBJECT_PREFIX`.
- **Modify** `backend/.env.example` — document `DJANGO_EMAIL_SUBJECT_PREFIX`.
- **Create** `backend/kaleem/identity/migrations/0003_set_site_name_domain.py` — data migration.
- **Create** `backend/kaleem/templates/account/email/email_confirmation_message.txt`
- **Create** `backend/kaleem/templates/account/email/email_confirmation_signup_message.txt`
- **Modify** `backend/kaleem/identity/services.py` — redact `_send_email_security_alert`,
  drop `changed_email`, update callers `add_email_address` / `set_primary_email`.
- **Modify** `backend/kaleem/identity/tests/test_email_management.py` — flip the body assertions.
- **Create** `backend/kaleem/identity/tests/test_email_branding.py` — subject prefix + Site + body.
- **Create** `docs/adr/0023-data-privacy-by-default-and-email-minimization.md`.

## Testing

- `mail.outbox[0].subject` starts with `"[Kaleem] "` and never contains `example.com`
  (trigger a confirmation via the resend-verification endpoint; tests have
  `ACCOUNT_EMAIL_VERIFICATION="none"`, so registration alone won't send one).
- Confirmation body contains "Kaleem", contains the `activate_url`, and does **not** contain the
  user's email address.
- Security-alert body for "added" and "set_primary": recipient is correct, body does **not**
  contain the changed address, body contains the dashboard link.
- Migration: after migrate, `Site.objects.get(pk=settings.SITE_ID).name == "Kaleem"`.
- 100% line+branch coverage maintained; ruff + mypy + import-linter green.

## Out of scope

- Branding/HTML email templates (text emails stay; visual identity is the paused brand slice).
- Password-reset email copy (slice 4 owns those templates).
- Per-environment Site domain automation (operator sets it in admin if staging needs a distinct
  domain in bodies; subjects are already env-independent).
