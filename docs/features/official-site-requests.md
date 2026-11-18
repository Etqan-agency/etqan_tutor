---
title: "Official-site requests"
---

This page covers the requests sent from the official Etqan Tutor site (`website/`, on the bare base domain):
academy applications, demo requests, contact messages and callback requests. Spec:
`docs/superpowers/specs/2026-10-27-official-site-leads-design.md`.

`etqan.leads` lives in the **public schema** (SHARED_APPS). Requests are Etqan's own data, not an academy's.

## Intake

`POST /api/v1/leads/` is in `config/urls_public.py` only, so it answers on the base domain and is `404` on an
academy host. The site's `LeadFormScript.astro` sends `kind` (`academy_request`, `demo`, `contact` or
`callback`), `locale`, `source_page`, `utm`, `consent`, the honeypot `website`, `elapsed_ms`, and the form's own
fields.

- Each kind's fields are an allowlist (`etqan/leads/fields.py`). Unknown keys are dropped. Values are trimmed
  and capped (200 characters, or 4000 for `notes` and `message`; at most 20 list items of 64 characters each).
  A field may arrive as a string or a list.
- `consent` must be JSON `true`. The email must be valid. `desired_subdomain` is only lowercased, because the
  Academy form checks it when the academy is created.
- Bot traps (a filled honeypot, or under 1.5 s on the page) answer `201` and store nothing.
- Throttles: `lead_ip` 10/hour and `lead_email` 5/hour. They never honour `X-Etqan-Internal`.
- The answer is `201 {"ok": true}`, `400` with field errors, or `429`.

## Emails

After commit, `etqan/leads/emails.py` queues two emails on Etqan's default account. Neither is metered.

- **Team alert:** goes to `LEADS_NOTIFY_EMAILS` (an env setting, comma-separated). It holds every field and a
  link to the request in admin, with `Reply-To` set to the visitor. If the setting is empty, a warning is logged
  and the request is still stored.
- **Receipt:** goes to the visitor in their site language, with the site's own thank-you text and nothing the
  visitor typed (not even their name). Otherwise the public endpoint would let anyone send any address their
  own words from Etqan's sender. At most 100 receipts go out per hour, site-wide. Callback requests have no
  email, so they get no receipt.

An email error is logged and never fails the request.

## Admin

**Django admin → Requests** lists requests newest first. It filters by form and status, and searches name,
email, phone and academy name. Staff edit only `status` (`new`, `contacted`, `won`, `lost`) and `notes`.

An academy application has a **Create academy** button. It opens the Academy add page filled in from the
request (`?lead=<id>` in the URL). On save, `tenants/admin.py` calls `leads.services.link_academy`, which links
the request and marks it `won`. The academy then builds in the background. The request shows the academy's
status: being created, active or failed. If a failed academy is deleted, the link clears (`SET_NULL`) and the
button comes back.
