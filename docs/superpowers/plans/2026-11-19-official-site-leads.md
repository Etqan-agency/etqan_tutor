# Official-site requests (`etqan.leads`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `POST /api/v1/leads/` on the base domain stores the official site's four forms,
emails the team and the visitor, and gives staff a Requests admin that can turn an
application into an academy.

**Architecture:** A new shared app `etqan.leads` (public schema): one `Lead` model, an
allowlist of fields per form kind, a DRF view mounted only in `config/urls_public.py`,
emails queued on commit through `integrations.services.queue_email`, a Django admin. The
Academy admin's add page links the new academy back to the request through
`leads.services.link_academy`.

**Tech Stack:** Django 5, DRF, django-tenants, pytest-django, import-linter.

**Spec:** `docs/superpowers/specs/2026-10-27-official-site-leads-design.md`

## Global Constraints

- Route `POST /api/v1/leads/`, in `backend/config/urls_public.py` only; `404` on an academy host.
- `etqan.leads` goes in `SHARED_APPS`; migrations only into `public`.
- Success ⇒ `201 {"ok": true}` and nothing else; validation ⇒ `400` DRF field errors; throttled ⇒ `429`.
- Bot traps (non-empty `website`, or `elapsed_ms` < 3000) ⇒ `201 {"ok": true}`, nothing stored, no email.
- Caps: 200 chars per single value, 4000 for `notes`/`message`, 20 items per array, 64 chars per array item.
- Throttle scopes `lead_ip` `10/hour`, `lead_email` `5/hour`; **no** `InternalExemptMixin`; no schema prefix in cache keys.
- Email only via `etqan.integrations.services.queue_email`, `from_email=settings.DEFAULT_FROM_EMAIL`, queued with `transaction.on_commit`; an email error never fails the request.
- `LEADS_NOTIFY_EMAILS` env (comma-separated list, default empty).
- `status`: `new` → `contacted` → `won` / `lost`; linking an academy sets `won`.
- `academy`: nullable FK `"tenants.Academy"`, `on_delete=SET_NULL`; no app imports another app's models.
- TDD; backend coverage ≥ 80%; `ruff`, `lint-imports`, `mypy` pass (`just lint`).

## Review Focus

1. A field the site sends as a string where the allowlist expects an array (or the reverse) — e.g. a checkbox group with one box. Expected: stored, not `400`. Test in Task 2 (`test_single_and_list_values_are_both_accepted`).
2. A non-object JSON body (`[]`, `"x"`). Expected `400`, not `500` (email throttle must not crash). Test in Task 2.
3. Arabic text and emoji in names/messages. Expected: stored and emailed intact. Test in Task 3 (Arabic visitor email asserts Arabic body and name).
4. `LEADS_NOTIFY_EMAILS` with spaces/empty items (`"a@x.test, ,b@x.test"`). Expected: two recipients. Test in Task 3.
5. `?lead=` on the Academy add page pointing at a non-application or already-linked request, or garbage. Expected: the academy is created, the request is not linked/changed. Test in Task 4.

---

### Task 1: App, model, settings, contracts

**Files:**
- Create: `backend/etqan/leads/__init__.py`, `apps.py`, `models.py`, `migrations/0001_initial.py` (via `makemigrations`), `tests/__init__.py`, `tests/test_models.py`
- Modify: `backend/config/settings/base.py` (SHARED_APPS after `etqan.etqan_billing`; `LEADS_NOTIFY_EMAILS = env.list("LEADS_NOTIFY_EMAILS", default=[])` next to `ETQAN_BILLING_PAYMENT_INSTRUCTIONS`; throttle rates `"lead_ip": "10/hour"`, `"lead_email": "5/hour"`)
- Modify: `backend/pyproject.toml` (add `"etqan.leads"` to "platform imports no business modules" under the integrations lines; new contracts "leads imports no tenants, identity or site" — forbidden `etqan.tenants`, `etqan.identity`, `etqan.site` — and "other apps reach leads only through its services" — source `etqan.tenants`, forbidden `etqan.leads.models`, `etqan.leads.api`, `etqan.leads.admin`)

**Interfaces:**
- Produces: `Lead` with `Kind` (`ACADEMY_REQUEST="academy_request"`, `DEMO="demo"`, `CONTACT="contact"`, `CALLBACK="callback"`), `Status` (`NEW`, `CONTACTED`, `WON`, `LOST`; default `NEW`), fields `kind`, `status`, `full_name` (200), `email` (EmailField, blank), `phone` (200, blank), `academy_name` (200, blank), `locale` (2), `answers` (JSON, default dict), `source_page` (200, blank), `utm` (JSON, default dict), `consented_at` (DateTime), `notes` (Text, blank), `academy` (FK `"tenants.Academy"`, null, blank, `SET_NULL`, `related_name="+"`), `created_at` (auto_now_add), `updated_at` (auto_now). `Meta.ordering = ["-created_at"]`, `verbose_name = "request"`.

- [ ] **Step 1: Failing test** `test_models.py::test_deleting_the_academy_clears_the_link`: in public schema create an `Academy` row directly (`Academy.objects.create(name=..., subdomain="leadlink", schema_name="academy_leadlink", status=FAILED)`, `auto_create_schema=False`), a `Lead` linked to it with `status=WON`; delete the academy; `lead.refresh_from_db()`; assert `lead.academy is None` and `lead.status == "won"`. (Test files may import `etqan.tenants.models`; add `"etqan.leads.tests.* -> etqan.tenants.*"` to the leads contract's `ignore_imports`.)
- [ ] **Step 2:** `pytest etqan/leads -q` → FAIL (no app).
- [ ] **Step 3:** App, model, settings, contracts; `python manage.py makemigrations leads`.
- [ ] **Step 4:** `pytest etqan/leads -q --create-db` → PASS; `lint-imports` → all kept.
- [ ] **Step 5:** Commit `feat(leads): Lead model in the public schema`.

### Task 2: Intake endpoint

**Files:**
- Create: `backend/etqan/leads/fields.py`, `services.py`, `throttling.py`, `api/__init__.py`, `api/serializers.py`, `api/views.py`, `tests/test_api.py`
- Modify: `backend/config/urls_public.py` (`path("api/v1/leads/", LeadCreateView.as_view(), name="leads")`)

**Interfaces:**
- `fields.KINDS: dict[str, tuple[tuple[str, ...], tuple[str, ...]]]` — kind → (required, optional), copied from the spec's "What the site sends" (re-checked against `website/src/pages/[lang]/{start,demo,contact}.astro`). `fields.LONG = {"notes", "message"}`. Column fields: `full_name`, `email`, `phone`, `academy_name`; every other allowlisted field goes to `answers`.
- `api.serializers.LeadSerializer(data)`: `.is_valid()`; `.validated_data` → `{"kind", "locale", "source_page", "utm", "fields": dict[str, str | list[str]], "trap": bool}`. Values: a string is trimmed and capped; a list keeps string items, each trimmed/capped, at most 20, empties dropped; either shape accepted for any field (*call:* never lose a request over shape). Required ⇒ non-blank. `email` validated with Django's `validate_email` when present. `desired_subdomain` lowercased. `consent` must be `True`. `utm`: dict of `utm_*` str keys, capped. `trap = bool(website) or elapsed_ms < 3000` (missing/invalid `elapsed_ms` counts as 0 → trap).
- `services.create_lead(*, kind: str, locale: str, source_page: str, utm: dict, fields: dict) -> Lead` — saves, `consented_at=timezone.now()`, then `transaction.on_commit(partial(emails.send_lead_emails, lead.pk), robust=True)` (Task 3 adds `emails`; in this task the on_commit line is added in Task 3).
- `throttling.LeadIPThrottle` / `LeadEmailThrottle(SimpleRateThrottle)`: scopes `lead_ip`/`lead_email`; email key `None` when body isn't a Mapping or has no email.
- `api.views.LeadCreateView(APIView)`: `authentication_classes = []`, `AllowAny`, both throttles, `post` → 201 `{"ok": True}`.

- [ ] **Step 1: Failing tests** in `test_api.py` (host `etqan.localhost`, `APIClient`, `cache.clear()` autouse, a `payload(kind, **over)` helper filling each kind's required fields, `consent=True`, `elapsed_ms=5000`, `locale="en"`):
  - `test_each_kind_is_stored` (parametrized over 4 kinds): 201, `resp.json() == {"ok": True}`, one `Lead` with right `kind`, columns, `answers` (e.g. academy_request `answers["country"]`).
  - `test_missing_required_field_is_rejected` (parametrized over every (kind, required field)): 400.
  - `test_unknown_keys_are_not_stored`: `answers` has no `"evil"`.
  - `test_bad_inputs_are_rejected` (bad email, `consent` false, `consent` missing, `locale="fr"`, `kind="spam"`): 400.
  - `test_malformed_and_taken_subdomains_are_stored`: `"Bad_Sub!"` stored as `"bad_sub!"`; `"admin"` stored.
  - `test_single_and_list_values_are_both_accepted`: `needs="x"` and `needs=["x","y"]` both 201.
  - `test_non_object_body_is_rejected`: `[]` ⇒ 400.
  - `test_values_are_capped`: 300-char `full_name` stored as 200; 5000-char `message` as 4000; 25-item list kept as 20.
  - `test_bot_traps_store_nothing` (`website="x"`; `elapsed_ms=100`): 201 `{"ok": True}`, no `Lead`.
  - `test_ip_throttle` (11th ⇒ 429, different emails) and `test_email_throttle` (6th same email ⇒ 429, from different `REMOTE_ADDR`), both also with `HTTP_X_ETQAN_INTERNAL="1"` and `settings.TRUST_INTERNAL_HEADER=True`.
  - `test_not_served_on_an_academy_host`: host `testserver` ⇒ 404.
- [ ] **Step 2:** `pytest etqan/leads/tests/test_api.py -q` → FAIL.
- [ ] **Step 3:** Implement the interfaces above.
- [ ] **Step 4:** Tests PASS.
- [ ] **Step 5:** Commit `feat(leads): POST /api/v1/leads/ on the base domain`.

### Task 3: Emails

**Files:**
- Create: `backend/etqan/leads/emails.py`, `backend/etqan/templates/email/leads/` only if used (*call:* plain-text bodies built in Python and wrapped in `email/layout.html`, like `etqan_billing/tasks.py::_html`; no new templates), `tests/test_emails.py`
- Modify: `backend/etqan/leads/services.py` (the on_commit line)

**Interfaces:**
- `emails.send_lead_emails(lead_id: int) -> None`: team email, then visitor email; each in its own `try/except Exception: logger.exception(...)`.
- `emails.team_recipients() -> list[str]`: `LEADS_NOTIFY_EMAILS` stripped, empties dropped.
- Team: subjects `New academy application — <academy_name>`, `New demo request — <academy_name>`, `New message — <full_name>`, `Callback request — <full_name>`; English; body lists the columns and answers (label: value, lists joined `", "`) and the link `f"{settings.FRONTEND_URL.rstrip('/')}/{settings.ADMIN_URL}leads/lead/{pk}/change/"`; `reply_to=[lead.email]` when present. Empty list ⇒ `logger.warning("... LEADS_NOTIFY_EMAILS is empty ...")`, no team email.
- Visitor (only when `lead.email`): subject and text = the form's `successTitle` / `successText` in `lead.locale` (copy verbatim from `website/src/i18n/{en,ar}.ts`, keys at en.ts:438-495 / ar.ts:525-582), greeting with `full_name`; `reply_to=[team_recipients()[0]]` or none; `dir="rtl"` for `ar`.
- Both: `queue_email(subject=..., body=..., from_email=settings.DEFAULT_FROM_EMAIL, to=[...], alternatives=[(html, "text/html")], reply_to=...)`.

- [ ] **Step 1: Failing tests** (`monkeypatch.setattr(emails.integrations, "queue_email", calls.append-ish fake)`, `django_capture_on_commit_callbacks(execute=True)`, posting through the API from Task 2):
  - `test_team_email_on_commit`: `LEADS_NOTIFY_EMAILS=["a@x.test"," ","b@x.test"]` ⇒ one team call to `["a@x.test","b@x.test"]`, subject `New academy application — Nour`, `reply_to == ["v@x.test"]`, body contains `/admin/leads/lead/<pk>/change/`.
  - `test_visitor_email_en` and `test_visitor_email_ar`: subject `Application received — thank you` / `وصلنا طلبك، شكرًا لك`; Arabic body has the Arabic name; reply_to `["a@x.test"]`.
  - `test_no_visitor_email_for_callback`.
  - `test_empty_notify_list_logs_and_still_stores` (`caplog` warning; `Lead` exists; visitor email has no `reply_to`).
  - `test_email_failure_does_not_fail_the_request`: fake raises ⇒ response 201, `Lead` exists.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(leads): team alert and visitor confirmation emails`.

### Task 4: Requests admin and "Create academy"

**Files:**
- Create: `backend/etqan/leads/admin.py`, `tests/test_admin.py`
- Modify: `backend/etqan/leads/services.py`, `backend/etqan/tenants/admin.py` (`save_model` add branch)

**Interfaces:**
- `services.academy_prefill(lead: Lead) -> dict[str, str]`: `name`←`academy_name`, `subdomain`←`answers.desired_subdomain`, `timezone`←`answers.timezone`, `admin_email`←`email`, `admin_full_name`←`full_name`, `lead`←`str(pk)`; blanks omitted.
- `services.link_academy(lead_id: str | int | None, academy_id: int) -> bool`: links and sets `WON` only for an existing `academy_request` with `academy_id` null; otherwise `False`, nothing changed; never raises on garbage ids.
- `tenants/admin.py::save_model` (add branch, after `created.save(...)`): `leads.link_academy(request.GET.get("lead"), created.pk)` with `from etqan.leads import services as leads`. The add form posts back to its own URL, so the query string is there on POST; `get_changeform_initial_data` fills the form from the same GET.
- `LeadAdmin`: `list_display` (created_at, kind, full_name, academy_name, email, phone, status), `list_filter` (kind, status), `search_fields` (full_name, email, phone, academy_name), `fields` = read-only summary + `status`, `notes`; `readonly_fields` include `submitted` (format_html list of columns + answers + source_page + utm + consented_at) and `academy_link`: for `academy_request` without academy ⇒ "Create academy" link to `reverse("admin:tenants_academy_add") + "?" + urlencode(academy_prefill(lead))`; with academy ⇒ link to `reverse("admin:tenants_academy_change", args=[academy_id])` showing name and `academy.get_status_display()`; else empty. `has_add_permission` ⇒ False.

- [ ] **Step 1: Failing tests** (`staff_client` like `tenants/tests/test_admin.py`, public host):
  - `test_list_filters_and_search`: changelist 200 with `?kind=demo`, `?status=new`, `?q=Nour`.
  - `test_status_and_notes_save_others_read_only`: POST change with `status=contacted`, `notes=x`, `full_name=Hacker` ⇒ status/notes saved, name unchanged.
  - `test_create_academy_link_prefills_the_add_form`: change page has the link; GET it ⇒ 200 and the form shows `value="nour"` subdomain and the email.
  - `test_saving_the_academy_links_the_request` (with `django_capture_on_commit_callbacks(execute=True)`, POST `/admin/tenants/academy/add/?lead=<pk>`) ⇒ `lead.academy_id == academy.pk`, `status == "won"`; change page then shows the academy link and its status text.
  - `test_link_ignores_bad_leads` (parametrized: demo lead, already-linked lead, `"abc"`, missing id) ⇒ academy created, no lead changed.
  - `test_no_button_for_other_kinds`.
  - `test_deleting_a_failed_academy_brings_the_button_back` (link, delete academy row, change page shows "Create academy").
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS; `pytest etqan/tenants -q` still PASS.
- [ ] **Step 5:** Commit `feat(leads): Requests admin; create an academy from an application`.

### Task 5: Docs, env, full gate

**Files:**
- Modify: `docs/features/README.md` (meta; add the feature), `website/src/components/LeadFormScript.astro` header comment and `website/README.md` "Forms" line (the endpoint exists), `infra/.env.staging.example` and `infra/.env.production.example` (`LEADS_NOTIFY_EMAILS=`)

- [ ] **Step 1:** Edits above.
- [ ] **Step 2:** Backend gate: `ruff check . && ruff format --check . && lint-imports && mypy etqan && pytest -n 4 --cov=etqan -q` → all pass, coverage ≥ 80.
- [ ] **Step 3:** Website gate: `pnpm check && pnpm build` in `website/`.
- [ ] **Step 4:** Commit per repo on `feat/site-leads`.

### Task 6: Ship

- [ ] Push `feat/site-leads` in backend, website, infra; open PRs; CI green; merge.
- [ ] Meta: `just bump` (pointers to each `main`), plan + docs commit, PR `--repo Etqan-agency/etqan_tutor`, CI green, merge ⇒ auto-deploy to production.
- [ ] Set `LEADS_NOTIFY_EMAILS` in the production env on the server if not set; restart Django.
- [ ] Smoke: POST each kind to `https://tutor.etqanpp.com/api/v1/leads/` ⇒ 201; open the contact page and submit; request visible in admin; delete the test requests.
