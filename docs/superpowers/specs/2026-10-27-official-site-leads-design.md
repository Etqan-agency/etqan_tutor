# Official-site requests (`etqan.leads`) — design

Date: 2026-10-27 · Revised 2026-11-19 against the current code (academy creation now
builds in the background) · Status: approved 2026-11-19

## Why

The official Etqan Tutor site (`website/`, served on the bare base domain) has four
forms. Every one of them POSTs JSON to `/api/v1/leads/`, an endpoint that does not
exist, so every submit ends on the site's "couldn't send" error.

Etqan sells academies through a conversation, not a sign-up. Someone fills in the
academy application. Etqan's person contacts them by email or WhatsApp, works out the
details, and creates the academy by hand in Django admin. The site already promises
this ("Your academy hasn't been created yet — we'll send your sign-in details once it's
ready"). This feature fills the gap between the form and that conversation:

- receive and keep every request,
- tell Etqan's team that a request arrived,
- confirm receipt to the visitor,
- let the team follow each request to an outcome in Django admin, and
- turn an agreed application into an academy without retyping it.

One person handles requests today.

## Goals

1. `POST /api/v1/leads/` on the base domain accepts all four forms exactly as
   `website/src/components/LeadFormScript.astro` sends them, stores each request, and
   answers `201`. The site's existing success panel then shows; the site needs no
   functional change.
2. Each stored request triggers one email to Etqan's team.
3. Each stored request that has an email address triggers one confirmation email to the
   visitor, in the language they used on the site.
4. A **Requests** section in Django admin (base domain, `/admin/`) lists requests and
   filters them by form and status. Each request shows everything that was submitted and
   has an editable status and notes.
5. An academy application whose conversation succeeded can be turned into an academy
   from its admin page, through the existing academy creation form filled in from the
   request. The request then records which academy it became.

## Non-goals

- Self-serve sign-up or creating an academy automatically. A person always decides.
- Assigning requests to staff, or multiple handlers. One person handles them now.
- Alerting the team by WhatsApp, SMS or push. Email only.
- Syncing to a CRM or spreadsheet.
- Checking whether the subdomain is free while the visitor types. It's checked when
  the academy is created.
- Replying from inside admin. The team replies from their own email or WhatsApp.
- Any change to the academy dashboard (`/app/`). It belongs to academies, not Etqan.
- Changing the website forms' fields. The backend accepts what the site sends today.
- A retention or auto-delete job.

## Anti-goals (failure even if it "works")

- **A request lost because an email failed.** The request is saved first; emails go
  out after commit, and an email error never turns a stored request into an error
  response.
- **A fake success.** If the request isn't stored, the response isn't `2xx`. The one
  deliberate exception is bot traps (below), which must look successful to the bot.
- **The endpoint reachable on an academy host.** It's Etqan's own intake and lives in
  the public URLconf only.
- **Arbitrary data stored from the internet.** Only the known fields of each form are
  kept (allowlist), with length caps.
- **The response echoing stored data.** It returns `{"ok": true}` and nothing else.

## What the site sends

Every form sends these common keys:

| Key | Meaning |
| --- | --- |
| `kind` | `academy_request`, `demo`, `contact` or `callback` |
| `locale` | `ar` or `en` (the page's `<html lang>`) |
| `source_page` | path of the page, e.g. `/en/start/` |
| `utm` | object of `utm_*` query params (may be empty) |
| `consent` | boolean; the site requires the box, the backend requires `true` |
| `website` | honeypot; must be empty |
| `elapsed_ms` | ms between page load and submit |

Then the form's own fields. Multi-choice fields arrive as arrays of option values.
Single choices and text fields arrive as strings. The form pages are the source of
truth for field names and which are required (`required` attribute):
`website/src/pages/[lang]/start.astro` (`academy_request`), `demo.astro` (`demo`),
`contact.astro` (`contact` and `callback`). At the time of writing:

- **academy_request** — required: `full_name`, `email`, `country`,
  `preferred_language`, `academy_name`, `lesson_format`, `students_range`,
  `teachers_range`, `monthly_hours_range`. Optional: `phone`, `timezone`,
  `desired_subdomain` (site pattern `^[a-z0-9](?:[a-z0-9-]{1,28}[a-z0-9])$`),
  `academy_type[]`, `multi_timezone`, `parents_involved`, `current_tools[]`, `needs[]`,
  `online_payments`, `own_zoom`, `own_email_domain`, `custom_domain`, `start_when`,
  `heard_from`, `notes`.
- **demo** — required: `full_name`, `email`, `academy_name`, `country`,
  `students_range`, `main_challenge`. Optional: `timezone`, `teachers_range`,
  `preferred_times[]`, `message`.
- **contact** — required: `full_name`, `email`, `category`, `message`.
- **callback** — required: `full_name`, `phone`. Optional: `academy_name`,
  `preferred_times[]`. (No email field.)

The builder re-reads those pages when building the per-kind allowlist; this list is a
guide, not the contract.

## Behaviour

### The endpoint

- `POST /api/v1/leads/`, registered in `backend/config/urls_public.py` only. Caddy
  already sends `/api/*` on the bare domain to Django (`caddy/Caddyfile.local`,
  `infra/caddy/Caddyfile`), so no edge change is needed.
- Same shape as the academy-site inquiry endpoint `etqan.site.api.views.InquiryCreateView`:
  `authentication_classes = []`, `AllowAny`, IP and email throttles. DRF's `APIView` is
  CSRF-exempt and only `SessionAuthentication` enforces CSRF, so a staff member logged
  into admin can still submit. The CSRF middleware stays on.
- Server-side validation (never trust the site): `kind` is one of the four; `locale` is
  `ar`/`en`; the kind's required fields are present and non-blank; `email` is a valid
  address; `consent` is `true`. Unknown keys are dropped. Strings are trimmed and capped
  (*my call:* 200 chars for single values, 4000 for `notes`/`message`, 20 items per
  array, 64 chars per array item).
- **`desired_subdomain` is not checked at intake** (*my call*), beyond being trimmed,
  lowercased and capped. Not even its format: the site already enforces the pattern
  before sending, so a malformed value can only come from outside the site, and storing
  it costs nothing. `tenants.services.validate_subdomain` also rejects reserved and
  taken names. If intake used it, a serious applicant who picked a taken name would get
  a `400`, see only the site's generic error, and the request would be lost. The
  subdomain is a wish, and the Academy creation form validates it when staff create the
  academy.
- **Bot traps** answer `201 {"ok": true}` and store nothing: a non-empty `website`, or
  `elapsed_ms` under 3000 (*my call:* 3 s).
- **Throttles** follow `etqan/site/throttling.py` (`SimpleRateThrottle`, per IP and
  per email) **without `InternalExemptMixin`**. `DJANGO_TRUST_INTERNAL_HEADER` is on in
  staging and production, and the base-domain Caddy blocks don't strip
  `X-Etqan-Internal`. With the mixin, anyone sending that header could skip the limits
  and make Etqan's sender mail any address. The static site makes no server-side calls,
  so nothing legitimate needs the exemption. The cache keys need no schema prefix
  because the endpoint only runs in `public`. New scopes in `DEFAULT_THROTTLE_RATES`:
  `lead_ip` and `lead_email`, *my call:* `10/hour` and `5/hour`, matching inquiries.
  Over the limit ⇒ `429`.
- Success ⇒ `201 {"ok": true}`. Validation errors ⇒ `400` with DRF's usual field
  errors (the site only shows its generic message, but the details help debugging).

### What gets stored

A new app `etqan.leads` in **SHARED_APPS**. *My call:* this is Etqan's own data, kept
in the `public` schema like `tenants` and `etqan_billing`. The project rule "new
business apps go in TENANT_APPS" is about academies' data, and this isn't academy
data.

One model, `Lead` (*my call* on the shape):

- columns the team filters, searches or needs at a glance: `kind`, `status`,
  `full_name`, `email` (blank allowed), `phone` (blank allowed), `academy_name` (blank
  allowed), `locale`;
- `answers` (JSON): every other allowlisted field of that kind, as submitted;
- `source_page`, `utm` (JSON), `consented_at` (UTC timestamp of the submit);
- `notes` (staff-only text, blank);
- `academy` (nullable relation to `tenants.Academy`, declared by the string
  `"tenants.Academy"` so no models are imported, `on_delete=SET_NULL`): the academy this
  application became. A relation, not an integer, because a failed academy is meant to
  be deleted and added again (`tenants.services.may_delete`). `SET_NULL` clears the link
  instead of leaving an id that points at nothing;
- `created_at`, `updated_at` (UTC).

`status`: `new` → `contacted` → `won` / `lost`. Staff move it by hand. Saving the
academy creation form from the request sets it to `won` (decided 2026-11-19, see
Approaches). For contact and callback messages, `won` and `lost` just mean "closed";
nobody asked for more statuses.

Logic lives in `etqan/leads/services.py` (create from validated data, mark converted);
the view and admin call it.

### Emails

All through `etqan.integrations.services.queue_email`, queued with
`transaction.on_commit` after the request is saved. They use Etqan's default sender in
the public schema; `meter_email` already records nothing there, because Etqan's own
mail has no academy to bill. They render on the existing branded layout
(`etqan/templates/email/layout.html` / `layout.txt`), with templates under
`etqan/templates/email/leads/`. `brand_email` doesn't fit here, because in `public` it
gives plain text and needs an academy's site data. The pattern to copy is the existing
public-schema HTML email in `etqan/etqan_billing/tasks.py` (~lines 99-115), which renders
`email/layout.html` with an Etqan context of its own. `queue_email` doesn't wrap itself
in `on_commit`, so `leads.services` does that. With `ATOMIC_REQUESTS=True`, the callback
catches and logs any exception, so an email error never reaches the response.

- **To the team.** Recipients come from a new env setting `LEADS_NOTIFY_EMAILS`
  (comma-separated, django-environ), added to `infra/.env.staging.example` and
  `infra/.env.production.example`. If it's empty, skip and log a warning; the request
  is still stored. Subject (*my call*): `New academy application — <academy_name>`,
  `New demo request — <academy_name>`, `New message — <full_name>`,
  `Callback request — <full_name>`. The body has the request's main details and an
  absolute link to its admin change page (built from `settings.FRONTEND_URL` +
  `ADMIN_URL`; on the public schema `frontend_url()` returns `FRONTEND_URL`, which
  the builder confirms is the base domain in staging and production). *My call:*
  `Reply-To` is the visitor's email when there is one, so the team can answer straight
  from the alert. Team emails are in English (*my call*).
- **To the visitor.** Only when the request has an email (so never for `callback`).
  Written in the request's `locale`. The text says what that form's thank-you screen
  says (`successTitle` / `successText` per form in `website/src/i18n/{ar,en}.ts`):
  received, our team will contact you, and for applications "your academy hasn't been
  created yet". `Reply-To` is the first `LEADS_NOTIFY_EMAILS` address. If that list is
  empty, the visitor email is sent without a `Reply-To`.

### Django admin: Requests

Registered in `etqan/leads/admin.py`, visible to staff with the usual model
permissions.

- **List:** newest first; columns: received, form (`kind`), name, academy name, email,
  phone, status. Filters: kind, status. Search: name, email, phone, academy name.
- **Detail:** the submitted fields and `answers` as a readable, read-only list (label:
  value, arrays joined), plus source page, UTM tags, consent time. Editable: `status`
  and `notes` only.
- **Create academy** (academy applications only, while `academy` is empty): a
  button that opens the existing Academy add page (`tenants/admin.py`,
  `AcademyCreationForm`) pre-filled from the request: `name` ← `academy_name`,
  `subdomain` ← `desired_subdomain`, `timezone` ← `timezone`, `admin_email` ← `email`,
  `admin_full_name` ← `full_name`. Staff set currency and plan, and fix anything the
  conversation changed. The form's existing validation catches a bad timezone or a
  taken subdomain. Saving only queues the academy's build:
  `AcademyAdmin.save_model` → `tenants.services.request_academy` saves the row with
  status `provisioning`, and `provision_academy` builds it in the background. The build
  ends `active` or `failed`. At that save, the request gets the link and status `won`.
  The build reports nothing back to leads. The owner's set-password email is sent by the
  existing flow only after a successful build.
  Once linked, the button becomes a link to that academy, shown with the academy's
  current build status (building / ready / failed), read live from the linked row. If a
  failed academy is deleted, `SET_NULL` clears the link and the "Create academy" button
  comes back. The status stays as it was until staff change it.
  How the pre-fill and the link-back are wired (Django admin's GET-param initial
  values plus a `lead` parameter that the Academy admin's save hands to
  `leads.services`, or something else) is the builder's call. It must pass
  `lint-imports`, and no app may import another app's models.

## Constraints

- Spec → plan → code; TDD; backend coverage ≥ 80% (`CLAUDE.md`).
- Business logic in `services.py`; apps talk only through services; `lint-imports`
  passes (add `etqan.leads` to the contracts as needed).
- Route under `/api/v1/`; stored instants UTC.
- Email only via `integrations.services.queue_email`.
- Migrations via `migrate_schemas` (the new app migrates into `public` only).
- Follow `docs/guide/adding-a-feature.md` and add the feature to
  `docs/features/README.md`.

## Tests the builder must cover

- Each kind: a valid submit stores one `Lead` with the right columns and `answers`;
  each missing required field ⇒ `400`; unknown keys are not stored.
- Bad email, `consent` false or missing, bad `locale`, bad `kind` ⇒ `400`.
- A malformed `desired_subdomain` is stored (normalized), not rejected.
- Honeypot filled, or `elapsed_ms` < 3000 ⇒ `201` and nothing stored, no email.
- Throttles ⇒ `429` after the limit, per IP and per email, including when the request
  carries `X-Etqan-Internal: 1`.
- A taken or reserved `desired_subdomain` is stored, not rejected.
- The route answers on the base domain and is `404` on an academy host.
- Emails: team email queued on commit to `LEADS_NOTIFY_EMAILS` with the admin link
  and `Reply-To`; visitor email in `ar` and in `en`; no visitor email for `callback`;
  empty `LEADS_NOTIFY_EMAILS` ⇒ no team email, warning logged, request still stored;
  an email failure doesn't fail the request.
- Admin: list, filters and search work; status and notes save; the other fields are
  read-only; "Create academy" pre-fills the form, and saving links the request and sets
  `won`; the button is absent for non-application kinds and for already-linked requests;
  the linked academy's build status shows; deleting the linked academy clears the link
  and the button comes back.

## Delivery

- **backend** (`feat/site-leads`): the app, endpoint, emails, admin, settings, tests.
- **website** (`feat/site-leads`): no code change. Update the `LeadFormScript.astro`
  header comment and the "Forms" line in `website/README.md`, which still say the
  endpoint is planned. Branch from `origin/main`: the local checkout is behind it (the
  forms are the same on both).
- **infra** (`feat/site-leads`): `LEADS_NOTIFY_EMAILS` in both env examples.
- **meta repo**: this spec, the plan, then bump the submodule pointers.
- End-to-end check: with `just dev`, submit each of the four forms on the local base
  domain. The success panel shows, the request appears in admin, and both emails show
  up in the local mail catcher.

## Approaches

Scope (decided 2026-11-19). The four forms share one endpoint, so fixing only the
contact form isn't worth doing on its own. Three scopes were considered:

1. **This whole spec** (chosen).
2. The spec without "Create academy".
3. Storage, team alert and an admin list only.

When an application counts as `won`, now that academy creation builds in the
background (decided 2026-11-19):

1. **At save, with a nullable link that clears itself** (chosen). The admin shows the
   academy's build status live. If a failed academy is deleted, the button comes back.
   `tenants` never needs to know about leads.
2. Only once the build succeeds. Rejected: the build would have to report back to
   leads, which couples `tenants` to `leads` and adds a failure path to build and test.

## Left to the builder

- Exact email wording within the rules above (mirror the site's own copy).
- How the answers are laid out on the admin detail page.
- The wiring of "Create academy" pre-fill and link-back, within the boundaries rule.
- Confirm that a string-referenced FK to `tenants.Academy` passes `lint-imports`. If a
  contract forbids it, keep the relation's behaviour (the link clears on delete) by
  another route.
