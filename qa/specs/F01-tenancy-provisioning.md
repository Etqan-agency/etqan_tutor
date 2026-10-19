# F01: Tenancy and academy provisioning, plus the dev-environment build

Author: Agent 1 (research and test strategy). This spec approves nothing.
Written 2026-10-17 from backend adff9c9, dashboard 5ed775d, infra b16332f, marketing 1c87b0a and the
meta repo at 85a5160. Log: `qa/logs/F01/agent1.md`.

Sources read:
- Code: `backend/etqan/tenants/{models,services,admin,middleware,views}.py`, its
  `management/commands/`, `academy/services.py` (`ensure_settings`), `identity/services.py`
  (`create_academy_admin`, `_reset_link`), `access/services.py`, `site/services.py`,
  `platform/{features,tenancy,frontend,permissions,validators,views}.py`,
  `etqan_billing/services/invoices.py` (`may_suspend`), `integrations/services/resolver.py`,
  `config/settings/base.py`, `config/urls_public.py`, `caddy/Caddyfile.local`,
  `infra/caddy/Caddyfile`, and the dev stage of each Dockerfile.
- Docs: `docs/features/tenancy.md`, `docs/features/feature-toggles.md`,
  `docs/guide/runbooks/operations.md`.
- Existing tests: `backend/etqan/tenants/tests/*`, `dashboard/e2e/{tenant-login,journey,features,academy-sites}.spec.ts`.

---

## 1. What the code does

### Data
- **`public.tenants_academy`** has these columns: `id`, `schema_name`, `name`, `subdomain`
  (unique, nullable), `status` (`active`/`suspended`), `timezone`, `currency`, `plan_label`,
  `plan_notes`, `features` (jsonb), `etqan_defaults_suspended`, `created_at`. The public row is
  `id=1`, `schema_name=public`.
- **`public.tenants_domain`** has `domain` (unique), `tenant_id`, `is_primary`, `status`
  (`pending`/`active`/`disabled`), `is_custom`, `verified_at`.
- **What a new schema `academy_<sub>` should contain.** The baseline is `academy_other` today:
  - 143 tables and 171 rows in `django_migrations`;
  - 1 row in `academy_academysettings` (`UTC|USD|ar`);
  - 1 row each in `academy_site_branding`, `academy_site_landingcontent` and
    `academy_site_sitesettings`;
  - 43 rows in `identity_tag` (21 student, 22 teacher);
  - 1 `access_staffrole` row, "Supervisor", with 20 permission codes;
  - 1 admin `identity_user` and 1 `account_emailaddress` (primary, verified).

### `create_academy`
`tenants/services.py:create_academy` is `@transaction.atomic`. It runs in this order:
1. `validate_subdomain`.
2. `Academy.save()`, which creates and migrates the schema.
3. The primary `Domain`.
4. Inside `tenant_context`:
   - `ensure_settings(timezone, currency)`;
   - `ensure_site_defaults(name)`;
   - `create_academy_admin`, whose invite is queued by `transaction.on_commit` and is sent only
     when no password is given;
   - `ensure_preset_tags`;
   - `ensure_supervisor_preset`.

### Subdomain rules
- Regex `^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$`, so 1 to 32 characters. The value is `.strip()`ed
  but **not lowercased**.
- Reserved: `www admin api app public static media mail flower sites etqan`.
- Also refused: a subdomain that is already taken, and one whose schema `academy_<sub with _>` or
  domain `<sub>.etqan.localhost` already exists.

### Entry points
- **Admin form:** `AcademyAdmin` with `AcademyCreationForm`. Its fields are name, subdomain,
  timezone, currency, plan_label, plan_notes, admin_email (`EmailField`) and admin_full_name.
- **Command:** `manage.py create_academy --name --subdomain --admin-email [--admin-name
  --timezone --currency]`. It does not take a password.

### Middleware and routing
- **`ActiveDomainTenantMiddleware`:** resolves the tenant from the Host header, lowercased with the
  port stripped and `www.` kept. Only `status=active` rows count; anything else is a 404.
- **`SuspendedAcademyMiddleware`:** answers 403 `{"detail": "This academy is suspended. Please
  contact Etqan.", "code": "tenant.suspended"}` for every path except those starting with
  `/health/`.
- **Public schema (`etqan.localhost`, `localhost`, `127.0.0.1`):** uses `config/urls_public.py`,
  which serves only `admin/`, `health/live/`, `health/ready/`, `internal/tls-allowed`,
  `api/v1/webhooks/zoom/` and `api/v1/webhooks/stripe-connect/`.
- **Local Caddy edge:**
  - Academy hosts and the catch-all `http://` route `/api /accounts /health /media /__debug__` to
    Django, `/app` to the dashboard and everything else to marketing. `/internal/*` gets a 404 at
    the edge.
  - `http://etqan.localhost` sends everything to Django except `/internal/*`, which gets a 404.
  - **The Django container's port 8000 is also published on the host.** `localhost:8000` bypasses
    Caddy, but that is only true in the dev stack.

### Suspension
- `set_status(ids, status)` never touches the public row.
- Admin actions suspend and reactivate academies, and the change form also exposes `status`.
- `for_each_academy` skips suspended academies. `academy_context`, used for queued tasks, does
  **not** skip them.

### `etqan_defaults_suspended`
- It is switched in the academy change form. Turning it on needs
  `etqan_billing.may_suspend(academy)`: an issued invoice with `total>0` and
  `(now - issued_at).days >= 30`.
- Lifting it is always allowed.
- `integrations/services/resolver.py:_etqan_default` reads it and answers `suspended`.

### Custom domains (admin only, no REST)
- `add_custom_domain` normalises the hostname (strip, lower, drop the trailing dot) and checks
  `HOSTNAME_RE`. It refuses the base domain and anything under it, and refuses duplicates. New rows
  are `pending`, `is_custom=True`, not primary.
- `check_dns`: OK only if the domain's resolved addresses are a subset of
  addresses(`EDGE_HOSTNAME`) ∪ {`EDGE_PUBLIC_IP`}. It activates the row and sets `verified_at`.
- `make_primary`: active rows only.
- `disable_domain`: custom rows only. It promotes the subdomain first if needed.
- `is_tls_allowed`: true for active rows only.

### Features
- The registry has 88 features in 6 groups.
- 7 are on by default: `families`, `parents`, `session_reports`, `invoices`,
  `auto_notifications`, `teacher_attendance`, `export`.
- 2 are unbuilt: `free_sessions` and `public_links`.
- 9 `requires` pairs. The code matches `feature-toggles.md`.
- **Writing switches:** Django admin checkboxes (only changed boxes are stored), the "Copy
  features from" action, and `set_features <subdomain> --on/--off`.
- **Reading switches:** `GET /api/v1/academy/features/` (admin only, through `HasCode` with no
  codes) and `me.features`. There is no write API.

### Environment facts (probed read-only on 2026-10-17)
- **No user exists in `public.identity_user`.** No Etqan staff account has been created yet.
- **Inside the django container:**
  - `sites.etqan.localhost` does not resolve, and `DJANGO_EDGE_PUBLIC_IP` is unset. As a result
    `check_domain_dns` can **never** succeed locally.
  - `localtest.me` resolves to 127.0.0.1 and ::1.
- **`pgrep` is not in the django image.** Check for a running pytest like this:
  ```
  dc.sh exec -T django sh -c 'for p in /proc/[0-9]*; do tr "\0" " " < $p/cmdline 2>/dev/null | grep -q "bin/pytest" && echo "$(basename $p)"; done'
  ```
  At 18:2xZ, baseline pytest PID 142 was still running.

## 2. Docs and code disagree

| # | Doc says | Code does | Impact |
|---|---|---|---|
| D1 | `tenancy.md` lists timezone and currency as plain `create_academy` arguments, and says `--timezone --currency` exist. | Neither the admin form, the command nor `ensure_settings` validates them. `clean_timezone` and `clean_currency` are imported in `academy/services.py` but not used on creation. | Suspected defect S1 |
| D2 | `tenancy.md` §Custom domains: "Staff add a domain in the admin. This calls `add_custom_domain`: it validates the hostname". | `DomainCreationForm.clean` checks only the base-domain rule. `add_custom_domain` raises an etqan `ValidationError` inside `save_model`, and the admin doesn't catch it. | Suspected S2 (500) |
| D3 | `tenancy.md` lists the Academy's `timezone` and `currency`. | The admin change form edits `Academy.timezone/currency`, but the academy reads `AcademySettings`, which is only seeded from the Academy row once (`get_settings` self-heal). A later admin edit has no effect. | Suspected S4 (silent no-op) |
| D4 | "The marketing site maps that code to a 503 page." | That is true for marketing. The dashboard has **no** handling for `tenant.suspended`: there is no match in `dashboard/src`. | UX gap, TC-071 |
| D5 | "Background jobs skip suspended academies." | That holds for beat loops (`for_each_academy`). Tasks queued through `academy_context` (emails etc.) still run for a suspended academy. | Low risk. Recorded in coverage-gaps. |
| D6 | The QA task's suggested `dc.sh exec -T django pgrep -f pytest`. | `pgrep` isn't installed. | Use the `/proc` loop above. |
| D7 | `operations.md`: "suspend an academy: set its status". | Correct. There's also no documented way to remove a test or throwaway academy: the admin can't delete one, and no command exists. | Cleanup gap, see §8 |

## 3. Suspected defects for Agent 2 to confirm (not filed; Agent 2 owns the register)

| ID | Hypothesis | Confirming case | Suggested severity if confirmed |
|---|---|---|---|
| S1 | An invalid timezone (`Mars/Phobos`) or currency (`usd`, `US`, `1$`) is accepted when an academy is created. `AcademySettings.timezone` and the admin user's timezone get the bad value. Per-academy-local-time jobs (`scheduling.run_daily`) and `ZoneInfo` users then fail for that academy. | TC-052, TC-053, TC-054 | P2 (P1 if `run_daily` fails every hour for that academy) |
| S2 | Adding a custom domain with an invalid hostname (`bad_host`, `nodot`, `-x.com`) in the Domain admin gives an HTTP 500 instead of a form error. | TC-084 | P3 |
| S3 | Two simultaneous creations of the same subdomain: one wins, and the other gets an `IntegrityError` or 500 instead of "already taken". | TC-062 | P3 |
| S4 | Editing timezone or currency on the academy's change page changes nothing the academy uses. | TC-055 | P3 |
| S5 | A suspended academy's dashboard shows a generic error or login failure, not a "suspended, contact Etqan" message. | TC-071 | P3 |

## 4. Setup Agent 2 must do first (in this order)

Run one heavy job at a time. Each new schema runs about 170 migrations, so give it up to 5
minutes, as `journey.spec.ts` does. Check that no pytest is running first (the `/proc` loop in §1).

**SETUP-1: Etqan staff superuser (public schema).** Use the command below; `manage.py` defaults to
the public schema. Record the account in `qa/environment.md`.
```
dc.sh exec -T -e DJANGO_SUPERUSER_PASSWORD='QA-Etqan-Staff-2026!' django python manage.py createsuperuser --noinput --email ops@qa.etqan.test
```

**SETUP-2: a non-superuser Etqan staff member** (used by TC-133 and TC-134). Use `shell`:
```
User.objects.create_user(email="ops-view@qa.etqan.test", password=..., is_staff=True)
```
Then give it only `tenants.view_academy` and `tenants.view_domain`. Also create
`ops-noperm@qa.etqan.test` with `is_staff=True` and no permissions.

**SETUP-3: academy `qa` through the browser.** This is TC-011 and the realistic onboarding flow.
Run it with Playwright `--workers=1` or headed.
- Name: Etqan QA Academy. Subdomain: `qa`. Timezone: `Africa/Cairo`. Currency: `EGP`.
- Plan label: `QA Tier 1`.
- Admin email: `qa-admin@qa.etqan.test`. Admin full name: `QA Admin`.

Then complete the invite from Mailpit with password `QA-Admin-2026!` (TC-016 to TC-018).

**SETUP-4: academy `qaother` by command** (TC-026). Leave its admin's **invite unaccepted** until
TC-110 has run, then accept it with password `QA-Other-2026!`.
```
dc.sh exec -T django python manage.py create_academy --name "Etqan QA Other" --subdomain qaother --admin-email qaother-admin@qa.etqan.test --admin-name "QA Other Admin"
```

**SETUP-5: QA people in `qa`** (for the role matrix in TC-117 to TC-124, TC-108 and TC-109).
Create them as the qa admin through the dashboard or API, then accept each invite from Mailpit.
- `qa-staff-nocode@qa.etqan.test`: staff with a role that has no codes, via
  `POST /api/v1/access/roles/` with `permissions: []`, then `POST /api/v1/access/staff/`.
- `qa-staff-codes@qa.etqan.test`: staff with a role that holds `student.view` and
  `student.view_any`.
- `qa-supervisor@qa.etqan.test`: staff holding the preset "Supervisor" role.
- `qa-teacher@qa.etqan.test`, `qa-student@qa.etqan.test` and `qa-parent@qa.etqan.test`:
  `POST /api/v1/people/{teachers,students,parents}/` with these emails.

Use password `QA-People-2026!` for all of them. Reads in demo with the seeded accounts are an
acceptable fallback for read-only role checks (admin@, sara = supervisor, bilal = teacher,
yusuf = student, omar = parent). **Never write to demo or other.**

**SETUP-6: feature state of `qa`.** Per feature-inventory, every built switch is on in qa. Turn on
every built feature (all except `free_sessions` and `public_links`) with
`dc.sh exec -T django python manage.py set_features qa --on <codes...>`.
- Record the before and after `features` JSON.
- **Do this after** TC-120 and TC-125, which need qa's untouched defaults. Or use qaother for
  those default checks.

**SETUP-7: throwaway academies.**
- **Planned:**
  - `qa-tmp-1` holds the suspension, defaults-suspended and custom-domain cases;
  - `qa-tmp-tz` probes S1 and may be left broken;
  - `qa-tmp-race-a` and `qa-tmp-race-b` are for TC-062;
  - `qa-tmp-kill` should leave nothing behind.
- Admin emails are `qa-tmp-<x>-admin@qa.etqan.test`.
- Keep them few, because each one migrates a whole schema.

**Recording:** record qa and qaother, their schemas, domains, admin credentials and feature state
in `qa/environment.md` and in `qa/feature-inventory.md` § QA academies.

Snapshot commands (read-only), with `Q='docker exec etqan_tutor-postgres-1 psql -U etqan -d etqan -At -c'`:
```
$Q "select id,schema_name,subdomain,status,timezone,currency,plan_label,etqan_defaults_suspended,features::text,created_at from public.tenants_academy order by id"
$Q "select id,domain,tenant_id,status,is_primary,is_custom,verified_at from public.tenants_domain order by id"
$Q "select nspname from pg_namespace where nspname like 'academy_%' order by 1"
```
Mailpit API: `curl -s 'http://localhost:8025/api/v1/search?query=to:qa-admin@qa.etqan.test'`.

## 5. Test data

| Item | Value |
|---|---|
| Etqan staff | `ops@qa.etqan.test` (superuser), `ops-view@qa.etqan.test` (view-only), `ops-noperm@qa.etqan.test` (is_staff, no permissions) |
| Academy A | `qa`, "Etqan QA Academy", `academy_qa`, `qa.etqan.localhost`, Africa/Cairo, EGP |
| Academy B | `qaother`, "Etqan QA Other", `academy_qaother`, `qaother.etqan.localhost`, UTC, USD |
| Throwaways | `qa-tmp-*` (schema `academy_qa_tmp_*`) |
| Bad subdomains | `""`, `"   "`, `QA`, `-qa`, `qa-`, `q_a`, `q.a`, `qa a`, `قا` (Arabic), `a`×33, `www`, `admin`, `api`, `app`, `public`, `static`, `media`, `mail`, `flower`, `sites`, `etqan`, `demo` (taken), `qa` (taken after SETUP-3) |
| Boundary subdomains (valid) | `a` is valid by the regex but is **not created**: it is only checked through the form error path and `validate_subdomain` in a shell. `a`×32 and `0-9` patterns are checked the same way. |
| Custom domains | `qa-academy.test` (unresolvable), `localtest.me` (resolves to 127.0.0.1 and ::1), `www.qa-academy.test`, `QA-Academy.TEST.` (normalisation), `bad_host`, `nodot`, `qa.etqan.localhost` and `x.etqan.localhost` (under the base domain) |

---

## 6. Test cases

Field legend:
- **Pri:** priority.
- **Tag:** the expected provider tag.
- **Cov:** existing automated coverage. "none" means the case needs new execution.

Unless a case says otherwise, every case:
- needs no feature switch (tenancy is not switch-gated);
- runs as **Etqan staff** in the admin on `http://etqan.localhost/admin/`;
- is checked in the DB through `$Q`.

### A. Dev environment and ETQAN-QA-001

#### F01-TC-001: Dashboard dev image builds with a host GID that already exists in Alpine (GID=20)
- **Pri:** P2. **Risk:** every Mac developer is blocked. **Tag:** REAL.
- **Preconditions:** Agent 3's Dockerfile fix is applied, and no other heavy job is running.
- **Steps:** build under a separate tag, without compose and without recreating containers:
  ```
  docker build --target dev --build-arg UID=501 --build-arg GID=20 -t etqan-qa001-dashboard:gid20 dashboard
  ```
  The dashboard may need the `GH_TOKEN` build secret, as `dc.sh` exports it.
- **Expected:** exit 0.
- **Assertions:**
  - `docker run --rm --entrypoint id etqan-qa001-dashboard:gid20` prints `uid=501` and `gid=20`.
  - `docker run --rm --entrypoint sh etqan-qa001-dashboard:gid20 -c 'stat -c %u:%g /app'` prints
    `501:20`.
- **Cov:** none.
- **Cleanup:** `docker rmi etqan-qa001-dashboard:gid20`.

#### F01-TC-002: Marketing dev image builds with GID=20
- **Pri:** P2. **Tag:** REAL. Same as TC-001, with `marketing/` and tag `etqan-qa001-marketing:gid20`.

#### F01-TC-003: Backend dev image builds with GID=20 (Debian `dialout`)
- **Pri:** P2. **Tag:** REAL. Same as TC-001, with `backend/` and tag `etqan-qa001-backend:gid20`. Also check
  `id app` and `ls -ld /app`, and that `python manage.py check` runs as `app` inside the image
  (`docker run --rm ... python -c 'import django'`).

#### F01-TC-004: Regression: the default GID=1000 and UID=1000 still build for all three images
- **Pri:** P2. **Tag:** REAL.
- **Steps:** repeat TC-001 to TC-003 with `--build-arg UID=1000 --build-arg GID=1000` and tag
  `:gid1000`.
- **Expected:** builds, and `id` shows 1000:1000.
- **Note:** node:22-alpine has the user `node` at 1000:1000. The existing `deluser node` must keep
  working.

#### F01-TC-005: A host UID that collides with an existing image user (UID=1, `daemon`) is handled or fails clearly
- **Pri:** P3. **Tag:** REAL.
- **Expected:** either the build succeeds and runs as UID 1, or it fails with a clear message.
- **Note:** this is an edge case only. Record the behaviour; it is not a blocker.

#### F01-TC-006: The justfile path works unmodified on macOS
- **Pri:** P2. **Tag:** REAL.
- **Steps:** with the separate tag approach only, run
  `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml build dashboard`
  **only if** it can be done without `up`/recreate. Otherwise mark it SIMULATED by TC-001 to
  TC-003 and note it.
- **Expected:** the build succeeds. Do **not** run `up`.

#### F01-TC-007: The running stack is untouched by the verification
- **Pri:** P2. **Tag:** REAL.
- **Assertions:** `docker ps --format '{{.Names}} {{.Image}} {{.CreatedAt}}'` is the same before
  and after TC-001 to TC-006 (same container IDs and created times).

### B. Customer onboarding through the Django admin (real browser)

#### F01-TC-010: Etqan staff can sign in to the staff console on the base domain
- **Pri:** P1. **Role:** Etqan staff (SETUP-1). **Tag:** REAL.
- **Steps:** open `http://etqan.localhost/admin/`, sign in as `ops@qa.etqan.test`.
- **Expected:** the "Etqan — academies" header is shown, with Academies and Domains listed.
- **Assertions:**
  - The UI header text.
  - `Set-Cookie sessionid` is host-only for `etqan.localhost`, with no `Domain=` attribute.
  - `public.django_session` has a new row; `academy_qa.django_session` does not exist yet.
- **Cov:** `test_admin.py::test_admin_is_served_on_the_public_host` uses `force_login`, not the
  real login.

#### F01-TC-011: Add academy "Etqan QA Academy" (`qa`) through the Add form: the happy path (SETUP-3)
- **Pri:** P1. **Risk:** the realistic owner-onboarding entry point has no e2e today. **Tag:** REAL.
- **Data:** see SETUP-3.
- **Steps:**
  1. Admin → Academies → Add.
  2. Check that the form shows exactly these fields: name, subdomain, timezone, currency, plan
     label, plan notes, admin email, admin full name. There must be no Domains inline and no
     feature checkboxes.
  3. Fill the form and click Save. Time the POST.
- **Expected:**
  - Redirect to the changelist with the success message "The academy “Etqan QA Academy” was added
    successfully".
  - The row appears with status Active and currency EGP.
- **Assertions (DB):**
  - `tenants_academy`: a row with `schema_name=academy_qa`, `subdomain=qa`, `status=active`,
    `timezone=Africa/Cairo`, `currency=EGP`, `plan_label='QA Tier 1'`, `features='{}'`,
    `etqan_defaults_suspended=f`.
  - `tenants_domain`: `qa.etqan.localhost`, `is_primary=t`, `status=active`, `is_custom=f`,
    `verified_at` null.
  - The schema `academy_qa` exists, with 143 tables and the same `django_migrations` count as
    `academy_other` (171 today).
- **Assertions (UI):** the change page shows the Domains inline (read-only) with
  `qa.etqan.localhost`, and the feature fieldsets.
- **Timing:** record the duration. If it is over 60 s, note the production risk against
  gunicorn `--timeout 120` in `coverage-gaps.md`.
- **Cov:** `test_admin.py::test_adding_an_academy_through_admin_creates_it` covers the test
  client, not a browser.
- **Cleanup:** none; this is the kept QA academy.

#### F01-TC-012: Provisioning wrote every per-academy default (`academy_qa`)
- **Pri:** P1. **Tag:** REAL.
- **Assertions:**
  - `academy_qa.academy_academysettings`: 1 row, `timezone=Africa/Cairo`,
    `default_currency=EGP`, `default_language=ar`.
  - `academy_site_branding`: 1 row, `name_ar = name_en = 'Etqan QA Academy'`.
  - `academy_site_landingcontent`: 1 row with the `DEFAULT_HERO` titles ("تعلّم مع أفضل المعلمين"
    and "Learn with great teachers").
  - `academy_site_sitesettings`: 1 row.
  - `identity_tag`: 43 rows (21 student, 22 teacher), matching `academy_other`.
  - `access_staffrole`: 1 row, `name_en=Supervisor`, whose permissions equal `academy_other`'s
    Supervisor (20 codes).
- **Cov:** `test_services.py::test_create_academy_records_its_settings`, `…seeds_the_preset_tags`
  and `…seeds_the_supervisor_role`.

#### F01-TC-013: The first admin row is correct
- **Pri:** P1. **Tag:** REAL.
- **Assertions:**
  - `academy_qa.identity_user`: exactly 1 row: `email=qa-admin@qa.etqan.test`,
    `full_name='QA Admin'`, `role=admin`, `is_active=t`, `preferred_language=ar`,
    `timezone=Africa/Cairo`, and a `password` starting with `!` (unusable).
  - `account_emailaddress`: `primary=t`, `verified=t`.
  - `public.identity_user` has no `qa-admin` row.
- **Cov:** `test_services.py::test_create_academy_makes_schema_domain_and_admin`, partly.

#### F01-TC-014: The set-password (invite) email reaches Mailpit only after the commit, and exactly once
- **Pri:** P1. **Tag:** REAL (Mailpit).
- **Steps:** search Mailpit for `qa-admin@qa.etqan.test`.
- **Expected:** exactly 1 message. It is in Arabic (the academy's language is `ar`), branded
  "Etqan QA Academy", and sent from the configured sender.
- **Assertions:**
  - The body has a link on its own line:
    `http://qa.etqan.localhost/app/reset-password?uid=<b64>&token=<tok>`. The host is the qa
    host, **not** `etqan.localhost`.
  - Subject prefix `[Etqan]` if one is applied.
  - The message's `Date` is after `tenants_academy.created_at`.
- **Cov:** `test_services.py::test_the_admin_invite_waits_for_the_commit` and
  `test_frontend_url.py` use the locmem backend (FAKE).

#### F01-TC-015: The invite email renders RTL and with correct Arabic
- **Pri:** P3. **Tag:** REAL.
- **Assertions:** the Mailpit HTML part has `dir="rtl"` (or equivalent) and no mojibake. The link
  is clickable and not wrapped.

#### F01-TC-016: The first admin sets a password from the invite link
- **Pri:** P1. **Role:** anonymous, then admin. **Tag:** REAL.
- **Steps:** open the link in a fresh browser context, enter the new password
  `QA-Admin-2026!`, and submit.
- **Expected:** "you can now sign in".
- **Assertions:**
  - API: `POST /api/v1/identity/password/reset/confirm/` returns 200.
  - DB: `academy_qa.identity_user.password` now starts with `pbkdf2_`/`argon2`, not `!`.
- **Cov:** `journey.spec.ts` covers the command-created path.

#### F01-TC-017: The first admin signs in at `http://qa.etqan.localhost/app/` and lands on the dashboard
- **Pri:** P1. **Role:** admin. **Tag:** REAL.
- **Assertions:**
  - UI: the user menu shows "QA Admin", and the academy branding name is "Etqan QA Academy".
  - API: `GET /api/v1/identity/me/` is 200 with `email=qa-admin@qa.etqan.test`, role admin and a
    `features` list equal to the 7 defaults.
  - DB: `academy_qa.django_session` has 1 row; `last_login` is set.

#### F01-TC-018: The invite link is single-use, and a wrong token is refused
- **Pri:** P2. **Tag:** REAL.
- **Steps:** after TC-016, POST the same uid/token again. Then POST a token with one character
  altered.
- **Expected:** 400 both times. The password is unchanged (same hash as after TC-016).

#### F01-TC-019: The Add form rejects bad input with a form error, and nothing is created
- **Pri:** P1. **Tag:** REAL.
- **Data:** subdomain `QA2` (uppercase), `-qa2`, `qa2-`, `q_a`, `q.a`, `قا`, 33×`a`, empty,
  `"   "`.
- **Expected:**
  - Each one shows the inline error "Use 1-32 lowercase letters, digits or hyphens; it cannot start
    or end with a hyphen." The page status is 200, and the entered values are preserved.
- **Assertions (DB):** after each attempt, the counts of `tenants_academy` and `tenants_domain`
  and the list of `academy_%` schemas are unchanged, and Mailpit shows no new invite.
- **Cov:** `test_services.py::test_invalid_subdomain_is_rejected` covers the service only.

#### F01-TC-020: Reserved subdomains are refused in the Add form (each of the 11)
- **Pri:** P1. **Tag:** REAL.
- **Data:** `www admin api app public static media mail flower sites etqan`.
- **Expected:** "This subdomain is reserved." and nothing is created.
- **Cov:** the service covers 6 names (`test_reserved_subdomain_is_rejected`); the admin covers 1
  (`test_admin_rejects_a_reserved_subdomain`). `static`, `media`, `flower`, `etqan` and `app` are
  not covered.

#### F01-TC-021: A taken subdomain is refused (`demo`, and `qa` after TC-011)
- **Pri:** P1. **Tag:** REAL.
- **Expected:** "This subdomain is already taken." Nothing changes, and demo is untouched (same
  `features` JSON and row).
- **Cov:** service only.

#### F01-TC-022: The admin email is validated and required
- **Pri:** P2. **Tag:** REAL.
- **Data:** empty, `not-an-email`, `a@b`.
- **Expected:** a form error on admin_email, and no academy is created.

#### F01-TC-023: Name boundaries
- **Pri:** P3. **Tag:** REAL.
- **Data:** an empty name gives a required error. A 201-character name gives a max-length error.
  Arabic names and emoji are accepted (in a qa-tmp throwaway only, optional).
- **Expected:** errors without a 500, and nothing is created on error.

#### F01-TC-024: Leading or trailing whitespace in the subdomain is stripped
- **Pri:** P3. **Tag:** REAL, via a form-error-path probe without creating.
- **Steps:** in a shell, run `validate_subdomain("  qa-tmp-x  ")`. It returns `qa-tmp-x`.
- **Note:** do not create a schema just for this.

#### F01-TC-025: Only the add form creates; the change page cannot alter `subdomain` or `schema_name`
- **Pri:** P2. **Tag:** REAL.
- **Steps:** open the qa change page. `subdomain`, `schema_name` and `created_at` are read-only.
  Forge a POST with `subdomain=hacked`, built from the change form's data.
- **Expected:** `subdomain` stays `qa`, and the domain row is unchanged.

### C. `create_academy` command and service

#### F01-TC-026: The `create_academy` command creates `qaother` (SETUP-4)
- **Pri:** P1. **Tag:** REAL.
- **Expected:** stdout `Created Etqan QA Other at qaother.etqan.localhost`, exit 0.
- **Assertions:** the same DB checks as TC-011 to TC-013, for `academy_qaother` with `UTC/USD`.
  Mailpit has 1 invite to `qaother-admin@qa.etqan.test` whose link host is
  `qaother.etqan.localhost`.
- **Cov:** `test_commands.py::test_create_academy_command`, and the journey e2e.

#### F01-TC-027: The command refuses reserved, taken and invalid subdomains with a `CommandError`
- **Pri:** P2. **Tag:** REAL.
- **Data:** `--subdomain www`, `--subdomain qa`, `--subdomain Bad`.
- **Expected:** a non-zero exit with the error message on stderr, no traceback, and no rows or
  schema created.

#### F01-TC-028: The command requires its arguments
- **Pri:** P3. **Tag:** REAL.
- **Expected:** a missing `--admin-email` makes argparse exit 2 with a usage message.

#### F01-TC-029: A hyphenated subdomain gets an underscored schema
- **Pri:** P2. **Tag:** REAL. Observed through `qa-tmp-1`.
- **Assertions:** `schema_name=academy_qa_tmp_1` and domain `qa-tmp-1.etqan.localhost`.
- **Cov:** `test_services.py::test_hyphenated_subdomain_gets_underscored_schema`.

#### F01-TC-030: A leftover schema blocks the subdomain
- **Pri:** P2. **Tag:** FAKE, by pytest.
- **Cov:** `test_services.py::test_subdomain_with_a_leftover_schema_is_rejected` and
  `…leftover_domain…`.
- **Execution:** run `pytest etqan/tenants -q -p no:cacheprovider`.
- **Optional REAL form:** a shell probe, `validate_subdomain` on a name whose schema
  `academy_qa_tmp_ghost` was created with `CREATE SCHEMA` and is then dropped. This is
  **owner-sensitive DDL**, so skip it unless the owner agrees, and record that.

#### F01-TC-031: The same admin email in two academies is allowed (users are per schema)
- **Pri:** P2. **Tag:** REAL.
- **Steps:** in `qa-tmp-1`, use `qa-admin@qa.etqan.test` as the admin email. That email is
  already qa's admin.
- **Expected:** creation succeeds. Each schema has its own user row, and the two passwords are
  independent.
- **Isolation:** setting qa-tmp-1's password must not change qa's (compare the hashes).
- **Cov:** `test_models.py::test_users_are_per_schema`.

#### F01-TC-032: An academy created with a password gets no invite email
- **Pri:** P3. **Tag:** FAKE.
- **Cov:** `test_services.py::test_admin_with_password_gets_no_email`. There is no CLI or admin
  path with a password.

#### F01-TC-033: `bootstrap_platform` is idempotent
- **Pri:** P3. **Tag:** REAL.
- **Steps:** run it twice.
- **Expected:** "public tenant ready: etqan.localhost, localhost, 127.0.0.1", and the
  `tenants_domain` count is unchanged.
- **Cov:** `test_commands.py`.

### D. Subdomain validation, edge cases (service and form)

#### F01-TC-036: Length boundaries
- **Pri:** P2. **Tag:** REAL, as a shell probe through `validate_subdomain`, which creates nothing.
- **Data:** 1 character `z` passes; 32×`z` passes; 33×`z` fails; 2 characters `z-` fails.
- **Cov:** 33 characters is covered by pytest.

#### F01-TC-037: Unicode and look-alike input is refused
- **Pri:** P2. **Tag:** REAL.
- **Data:** `qа` (a Cyrillic а), `ｑａ` (full-width), `qa\n`, `qa\t`, `qa%00`.
- **Expected:** all refused. The trailing-newline case matters because `fullmatch` with `$` is
  used: verify that `"qa\n"` is **refused**. After `.strip()` it would become `qa` (taken), so use
  `"zz\n"`. Expected: `strip` gives `zz`, which is accepted, but only after stripping, which is
  intended.

#### F01-TC-038: Double hyphens and digits
- **Pri:** P3. **Tag:** REAL, by shell probe.
- **Data:** `a--b` and `123` are accepted by the regex. Document the result; don't create them.

#### F01-TC-039: Reserved names are checked case-sensitively but uppercase is refused anyway
- **Pri:** P3. **Tag:** REAL, by probe.
- **Data:** `WWW` is refused by the regex.

#### F01-TC-040: Names that collide with the edge or infra but are not reserved
- **Pri:** P3. **Tag:** REAL (static review plus a probe).
- **Data:** `status`, `support`, `docs`, `billing`, `staging`, `e2e`.
- **Expected:** accepted today. Record them as a product question in `coverage-gaps.md`; this is
  not a defect.

### E. Timezone and currency defaults and validation

#### F01-TC-050: Defaults, when timezone and currency are omitted
- **Pri:** P2. **Tag:** REAL (qaother).
- **Assertions:** `Academy.timezone=UTC` and `currency=USD`. `AcademySettings` is `UTC/USD/ar`,
  and the admin user's timezone is UTC.
- **Cov:** `test_services.py::test_create_academy_records_its_settings`.

#### F01-TC-051: A valid non-default timezone and currency propagate (qa: Africa/Cairo / EGP)
- **Pri:** P1. **Tag:** REAL.
- **Assertions:**
  - The DB as in TC-012 and TC-013.
  - `GET http://qa.etqan.localhost/api/v1/academy/settings/` (as the qa admin) returns
    `timezone=Africa/Cairo` and `default_currency=EGP`.
  - The dashboard Settings → General page shows Cairo and EGP.

#### F01-TC-052: An invalid timezone is refused at creation (S1)
- **Pri:** P1. **Tag:** REAL.
- **Steps:** submit the Add form with subdomain `qa-tmp-tz`, timezone `Mars/Phobos`, currency
  `EGP`.
- **Expected (per the `clean_timezone` contract):** a form error "Unknown timezone." and nothing
  created.
- **Likely actual (S1):** the academy is created with `Mars/Phobos`. If so:
  1. Record `academy_qa_tmp_tz.academy_academysettings.timezone` and the user's timezone.
  2. Sign in as that admin and open Settings and the Today/schedule page. Capture any 500.
  3. Run the hourly job against that academy only: in a shell,
     `with tenant_context(...)`: call the per-academy part of `scheduling.run_daily`, or invoke
     the Celery task and read the worker log for "failed for academy academy_qa_tmp_tz".
  4. File the bug. Leave `qa-tmp-tz` **suspended** afterwards (TC-064) so beat skips it.
- **Cov:** none.

#### F01-TC-053: An invalid or lowercase currency at creation (S1)
- **Pri:** P2. **Tag:** REAL.
- **Data:** `usd` (should be normalised to `USD` or refused), `US`, `1$`.
- **Steps:** use the Add form's error path. If it accepts the value, **don't** create more
  schemas: one created probe is enough (reuse `qa-tmp-tz`'s form submission with both bad values
  at once if S1 is confirmed there).
- **Expected:** refused with "Use a three-letter currency code, like EGP.", or normalised to
  upper case.

#### F01-TC-054: Command-line parity for S1
- **Pri:** P2. **Tag:** REAL.
- **Steps:** `create_academy ... --timezone Nowhere/City`, using the error path only if the form
  already confirmed S1. You can use `--subdomain` taken, which fails first, so this checks the
  order. **Note:** subdomain validation runs first, so an invalid timezone with a taken subdomain
  says "taken". Report the order.

#### F01-TC-055: Editing timezone or currency on the academy change page (S4)
- **Pri:** P3. **Tag:** REAL (qa-tmp-1).
- **Steps:** change the timezone to `Asia/Riyadh` and save.
- **Assertions:** `tenants_academy.timezone` changes, but `academy_qa_tmp_1.academy_academysettings.timezone`
  doesn't, and neither does the dashboard Settings page.
- **Expected:** document this as a confusing no-op, or as by design. Ask the owner.

#### F01-TC-056: The academy admin changes the timezone in the dashboard; the value is validated
- **Pri:** P2. **Role:** qa admin. **Tag:** REAL.
- **Steps:**
  - `PATCH /api/v1/academy/settings/ {"timezone":"Mars/Phobos"}` returns 400 on `timezone`.
  - `{"default_currency":"egp"}` returns 200, stored as `EGP` (or 400).
- **Cleanup:** restore `Africa/Cairo` and `EGP`. This contrasts with S1 and belongs to F04 too.

### F. Rollback, partial failure and concurrency

#### F01-TC-058: A failure at each provisioning step rolls back everything
- **Pri:** P1. **Tag:** FAKE (pytest monkeypatch).
- **Cov:** `test_services.py::test_failure_after_schema_creation_leaves_nothing_behind` covers
  only the `create_academy_admin` step.
- **New test needed:** parametrise over `ensure_settings`, `ensure_site_defaults`,
  `ensure_preset_tags`, `ensure_supervisor_preset` and `Domain.objects.create`. Assert:
  - no schema;
  - no Academy or Domain row;
  - no email sent (`mail.outbox` empty after `on_commit`).

  Agent 3 can add this as a test-only change.

#### F01-TC-059: Killing the process mid-provision leaves nothing behind
- **Pri:** P1. **Tag:** REAL.
- **Steps:**
  1. Start
     `dc.sh exec -T django python manage.py create_academy --name "QA Tmp Kill" --subdomain qa-tmp-kill --admin-email qa-tmp-kill-admin@qa.etqan.test`
     in the background.
  2. After about 5 s, while migrations run, kill it:
     `dc.sh exec -T django sh -c 'kill -INT <pid>'`, finding the pid with the `/proc` loop and
     `create_academy`.
- **Expected:**
  - The Postgres transaction is rolled back. There is no `academy_qa_tmp_kill` schema, and no
    `tenants_academy` or `tenants_domain` row.
  - Mailpit has no message to `qa-tmp-kill-admin@`.
  - Afterwards `validate_subdomain('qa-tmp-kill')` passes.
- **Assertions:** also check `pg_stat_activity` for leftover idle-in-transaction sessions.

#### F01-TC-060: A failure in the admin save path gives no half-created academy, and the admin shows the error
- **Pri:** P2. **Tag:** FAKE.
- **New pytest:** monkeypatch `services.create_academy` to raise inside the admin `save_model`.
  Expect a 500, or a handled error, and no rows.
- **Note:** this documents the current behaviour only.

#### F01-TC-061: Double-submitting the Add form creates one academy
- **Pri:** P2. **Tag:** REAL.
- **Steps:** in the browser, submit the qa-tmp-race-a form and press Back then Resubmit, or
  double-click Save quickly.
- **Expected:** exactly one academy. The second POST shows "already taken", not a 500.

#### F01-TC-062: Two concurrent creates of the same subdomain (S3)
- **Pri:** P2. **Tag:** REAL.
- **Steps:** start two `create_academy --subdomain qa-tmp-race-b` commands in parallel, with
  different admin emails. This is a medium-heavy job: run nothing else alongside it.
- **Expected:** exactly one succeeds. The other gets a clean "already taken" `CommandError`, or an
  IntegrityError. Record which.
- **Assertions:** exactly one row, one domain and one schema. Exactly one invite in Mailpit, to
  the winner's email.

### G. Suspension and reactivation

#### F01-TC-064: Suspend `qa-tmp-1` with the admin action
- **Pri:** P1. **Tag:** REAL.
- **Steps:** Academies changelist → select qa-tmp-1 → "Suspend selected academies" → Go.
- **Expected:** the message "Suspended 1 academies." and the status column shows Suspended.
- **Assertions (DB):** `status=suspended` for qa-tmp-1 only. qa, qaother, demo, other and public
  are unchanged.
- **Cov:** `test_admin.py::test_suspend_action`.

#### F01-TC-065: A suspended academy's API answers 403 `tenant.suspended`
- **Pri:** P1. **Tag:** REAL.
- **Steps:** with `curl -s -i -H 'Host: qa-tmp-1.etqan.localhost' http://localhost/...`:
  - `GET /api/v1/identity/csrf/`;
  - `POST /api/v1/identity/login/` with valid credentials;
  - `GET /api/v1/site/branding/` (or any public site endpoint);
  - `GET /accounts/` and `GET /media/x`.
- **Expected:** every one returns 403 with the JSON body
  `{"detail":"This academy is suspended. Please contact Etqan.","code":"tenant.suspended"}`.
- **Assertions (DB):** no session row is created in `academy_qa_tmp_1.django_session`, and
  `last_login` is unchanged.
- **Cov:** `test_middleware.py::test_suspended_academy_api_is_blocked`.

#### F01-TC-066: A suspended academy still answers its health checks
- **Pri:** P1. **Tag:** REAL.
- **Expected:**
  - `GET /health/live/` returns 200 and `GET /health/ready/` returns 200
    `{"status":"ok",...}` on the qa-tmp-1 host.
  - `GET /health/` returns 404, not 403.
  - `GET /healthx/` returns 403 (not under `/health/`).
- **Cov:** `test_middleware.py::test_suspended_academy_still_answers_health`.

#### F01-TC-067: A session that already exists is cut off at suspension
- **Pri:** P1. **Role:** qa-tmp-1 admin, signed in before the suspension. **Tag:** REAL.
- **Steps:**
  1. Sign in on the qa-tmp-1 dashboard before TC-064. `me` returns 200.
  2. Suspend the academy.
  3. Reload.
- **Expected:** API calls return 403 `tenant.suspended` straight away, with no grace period.

#### F01-TC-068: The suspended academy's public site shows the suspended page (marketing returns 503)
- **Pri:** P2. **Role:** anonymous. **Tag:** REAL.
- **Steps:** `GET http://qa-tmp-1.etqan.localhost/`.
- **Expected:** HTTP 503 with the suspended page text, and nothing of the academy's content.
- **Cov:** marketing unit tests for `site.ts`.

#### F01-TC-069: Suspension does not affect other academies
- **Pri:** P1. **Tag:** REAL.
- **Steps:** while qa-tmp-1 is suspended, call qa's `me` (signed in) and qaother's csrf.
- **Expected:** 200 for both. The demo login page loads too.
- **Cov:** `test_middleware.py::test_active_academy_is_not_blocked`.

#### F01-TC-070: Background jobs skip a suspended academy
- **Pri:** P2. **Tag:** REAL.
- **Steps:** with qa-tmp-1 suspended, run `for_each_academy(lambda: None, name="qa-probe")` from
  a shell.
- **Expected:** the result dict has no `academy_qa_tmp_1` key, but does include `academy_qa`.
- **Cov:** platform tests, which Agent 2 should cite if found (`etqan/platform/tests`).

#### F01-TC-071: What the suspended academy's dashboard shows (S5)
- **Pri:** P3. **Role:** the qa-tmp-1 admin. **Tag:** REAL.
- **Steps:** open `http://qa-tmp-1.etqan.localhost/app/login` and try to sign in.
- **Expected:** a clear "academy suspended" message. Record the actual UI and its a11y (an
  `role=alert` announcement).

#### F01-TC-072: Reactivate restores access
- **Pri:** P1. **Tag:** REAL.
- **Steps:** use the "Reactivate selected academies" action.
- **Expected:** "Reactivated 1 academies.", `status=active`, and the API returns 200 again. Data
  is intact: the user rows and settings are the same as before the suspension.

#### F01-TC-073: The public row can't be suspended or opened
- **Pri:** P1. **Tag:** REAL.
- **Steps:**
  - The changelist does not list "Etqan" (public).
  - `GET /admin/tenants/academy/1/change/` is a redirect or "doesn't exist".
  - Forge a changelist action POST with `_selected_action=1&action=suspend_academies`.
- **Expected:** the message "Suspended 0 academies." The public status stays active, and
  `etqan.localhost/admin/` still works.
- **Cov:** `test_services.py::test_set_status_never_suspends_public` covers the service only.

#### F01-TC-074: Suspending through the change form's `status` field behaves like the action
- **Pri:** P2. **Tag:** REAL (qa-tmp-1).
- **Expected:** the same 403 behaviour. Reactivate afterwards.

#### F01-TC-075: Academies cannot be deleted (offboarding is suspension)
- **Pri:** P2. **Tag:** REAL.
- **Expected:**
  - No delete action in the changelist, and no Delete button on the change page.
  - `GET /admin/tenants/academy/<qa-tmp-1>/delete/` returns 403.
  - The same holds for Domains.
- **Cov:** `test_admin.py::test_academies_cannot_be_deleted_from_admin` and
  `…offers_no_delete_action`.

### H. `etqan_defaults_suspended` (the Etqan default accounts)

#### F01-TC-076: Turning on "Suspend Etqan's defaults" with no unpaid invoice is refused
- **Pri:** P1. **Tag:** REAL (qa-tmp-1).
- **Expected:** the help text shows "No unpaid Etqan invoice.". Ticking the box and saving gives
  the form error "…only once an Etqan invoice is unpaid 30 days after issue." The DB stays `f`.
- **Cov:** `test_admin_suspend.py::test_suspending_before_30_days_is_refused`.

#### F01-TC-077: Boundary: an invoice issued 29 days and 23 hours ago is refused; 30 days and 1 minute is allowed
- **Pri:** P1. **Tag:** REAL, with fixture data inserted by shell.
- **Fixture:** in a shell, create an `EtqanInvoice(academy=qa-tmp-1, status="issued",
  total=250, issued_at=now-29d23h, ...)`, with a unique number `ETQ-QA-TMP-0001`.
- **Steps:** try to suspend: refused, and the help text shows "issued 29 days ago". Update
  `issued_at` to now-30d-1min and try again: allowed.
- **Assertions:** `etqan_defaults_suspended=t`. The admin history (`django_admin_log`) records the
  change.
- **Cleanup:** delete the fixture invoice (it is our own row) after TC-079.
- **Cov:** `test_admin_suspend.py::test_etqan_suspends_an_academys_defaults_from_30_days_unpaid`.

#### F01-TC-078: A zero-total invoice, or a draft or paid one, never allows suspending
- **Pri:** P2. **Tag:** FAKE (pytest), with REAL optional.
- **Cov:** `test_admin_suspend.py::test_a_zero_invoice_never_allows_suspending`. Draft and paid
  invoices are **not** covered, so a new pytest case is needed.

#### F01-TC-079: With the defaults suspended, the integrations status is `suspended`; the academy's own accounts still work
- **Pri:** P2. **Role:** the qa-tmp-1 admin. **Tag:** SIMULATED/FAKE, since there are no provider
  credentials.
- **Steps:** `GET http://qa-tmp-1.etqan.localhost/api/v1/integrations/`.
- **Expected:** each Etqan default service whose platform account is enabled reports
  `suspended`. Record what is returned when no `PlatformAccount` exists (likely `disabled`, so the
  suspended path is not observable). If none exist, mark it BLOCKED for the live part and rely on
  the integrations pytest.
- **Note:** check that the set-password and reset emails still reach Mailpit, by sending a
  password reset for the qa-tmp-1 admin. Record whether email depends on a platform account.

#### F01-TC-080: Lifting the defaults suspension is always allowed
- **Pri:** P2. **Tag:** REAL.
- **Expected:** untick and save gives `f`, even with the invoice still unpaid.
- **Cov:** `test_admin_suspend.py::test_lifting_a_suspension_is_always_allowed`.

#### F01-TC-081: Defaults suspension is separate from academy suspension
- **Pri:** P2. **Tag:** REAL.
- **Assertions:** with `etqan_defaults_suspended=t` and `status=active`, the API answers 200 (not
  `tenant.suspended`).

### I. Custom domains and the TLS ask

All of these run on `qa-tmp-1`. Never touch demo's or other's domains.

#### F01-TC-082: Add a custom domain: it is created pending
- **Pri:** P1. **Tag:** REAL.
- **Steps:** Domains → Add, with tenant qa-tmp-1 and domain `QA-Academy.TEST.`.
- **Expected:**
  - The help text names `sites.etqan.localhost`.
  - The row is created as `qa-academy.test` (normalised): `status=pending`, `is_custom=t`,
    `is_primary=f`, `verified_at` null.
- **Assertions:** the tenant dropdown does not offer "Etqan" (public).
- **Cov:** `test_domain_admin.py::test_add_custom_domain_via_admin` and
  `test_domains.py::test_add_custom_domain_is_pending`.

#### F01-TC-083: Etqan subdomains and the base domain are refused as custom domains
- **Pri:** P1. **Tag:** REAL.
- **Data:** `etqan.localhost`, `x.etqan.localhost`, `qa.etqan.localhost`.
- **Expected:** the form error "Use the academy's own domain, not an Etqan subdomain."
- **Cov:** `test_domain_admin.py::test_admin_rejects_etqan_subdomain`.

#### F01-TC-084: An invalid hostname is refused with a form error, not a 500 (S2)
- **Pri:** P2. **Tag:** REAL.
- **Data:** `bad_host`, `nodot`, `-x.com`, `a..com`, `http://x.com`, and 254 characters.
- **Expected:** a form error "Enter a domain like academy-name.com.", with HTTP 200.
- **Likely actual:** HTTP 500, because the etqan `ValidationError` is raised in `save_model`.
- **Assertions:** no `tenants_domain` row is created either way.
- **Cov:** `test_domains.py::test_add_custom_domain_rejects_bad_hosts` covers the service only.

#### F01-TC-085: A duplicate custom domain is refused (same or other tenant)
- **Pri:** P1. **Tag:** REAL.
- **Steps:** add `qa-academy.test` again, for qa-tmp-1 and then for qa.
- **Expected:** a uniqueness error, with no 500 and no second row. Also try `localhost`, which is a
  public row: also refused.

#### F01-TC-086: A pending custom domain does not resolve
- **Pri:** P1. **Tag:** REAL.
- **Steps:**
  - `curl -i -H 'Host: qa-academy.test' http://localhost/api/v1/identity/csrf/` returns 404.
  - `GET /` returns 404 "Site not found" from marketing.
- **Cov:** `test_domains.py::test_pending_domain_404s`.

#### F01-TC-087: "Check DNS and activate" on an unresolvable or wrong domain
- **Pri:** P1. **Tag:** REAL.
- **Steps:** run the action on `qa-academy.test`, then on a newly added `localtest.me`.
- **Expected:**
  - For `qa-academy.test`: "resolves to nothing, expected sites.etqan.localhost." as a warning.
  - For `localtest.me`: "resolves to 127.0.0.1, ::1, expected sites.etqan.localhost."
  - Both stay pending, with `verified_at` null.

#### F01-TC-088: The successful "Check DNS" path
- **Pri:** P1. **Tag:** BLOCKED locally, because `EDGE_HOSTNAME` doesn't resolve in the container
  and `EDGE_PUBLIC_IP` is unset. Changing the env would need a container recreate, which is not
  allowed. FAKE coverage is
  `test_domain_admin.py::test_check_dns_action_activates` and
  `test_domains.py::test_check_dns_compares_with_edge` and `…mismatch`.
- **Gap:** a resolver that returns a *subset* (one of the edge IPs) versus a *superset* (edge IP
  plus a foreign IP, which must fail). Check that pytest has the superset case. If it is missing,
  add it (Agent 3, as a test-only change).

#### F01-TC-089: An active custom domain serves its academy (activation by service)
- **Pri:** P1. **Tag:** REAL routing, with the DNS step bypassed. Label it as such.
- **Steps:** in a shell, run `services.activate_domain(Domain.objects.get(domain="qa-academy.test"))`.
  Then:
  - `curl -H 'Host: qa-academy.test' http://localhost/api/v1/identity/csrf/` returns 200;
  - `GET /api/v1/site/branding/` returns qa-tmp-1's name.
- **Assertions:** `status=active` and `verified_at` set. The response contains no data from qa or
  qaother.
- **Cov:** `test_domains.py::test_active_domain_serves_its_academy`.

#### F01-TC-090: Host matching is case-insensitive, ignores the port, and does not strip `www.`
- **Pri:** P2. **Tag:** REAL.
- **Steps:**
  - `Host: QA-ACADEMY.TEST:80` returns 200.
  - `Host: www.qa-academy.test` returns 404 until the `www.` row is added and activated
    separately. Then it returns 200.
- **Cov:** `test_domains.py::test_www_custom_domain_resolves` and
  `…resolves_case_insensitively`.

#### F01-TC-091: Make primary moves `is_primary`; emails follow the primary domain
- **Pri:** P1. **Tag:** REAL.
- **Steps:**
  1. Select the active `qa-academy.test` → "Make primary".
  2. Then trigger a password reset for the qa-tmp-1 admin:
     `POST http://qa-tmp-1.etqan.localhost/api/v1/identity/password/reset/`.
- **Expected:**
  - DB: exactly one `is_primary=t` row for qa-tmp-1, and it is `qa-academy.test`.
  - The Mailpit link host is `http://qa-academy.test/app/reset-password?...`.
  - Other tenants' primaries are unchanged.
- **Cov:** `test_domain_admin.py::test_make_primary_action` and
  `test_frontend_url.py::test_password_reset_email_links_to_the_academy_host`.

#### F01-TC-092: Make primary on a pending or disabled domain is refused
- **Pri:** P2. **Tag:** REAL.
- **Expected:** the error message "<domain>: Only an active domain can be primary." The primary
  doesn't change.
- **Cov:** `test_domains.py::test_make_primary_requires_active`.

#### F01-TC-093: Disabling the primary custom domain restores the subdomain as primary, and the domain stops resolving
- **Pri:** P1. **Tag:** REAL.
- **Expected:**
  - `qa-academy.test` is `disabled` with `is_primary=f`, and `qa-tmp-1.etqan.localhost` has
    `is_primary=t`.
  - `Host: qa-academy.test` returns 404.
  - The reset-email link uses the subdomain again.
- **Cov:** `test_domains.py::test_disabling_primary_custom_domain_restores_the_subdomain_as_primary`.

#### F01-TC-094: The academy's own subdomain can't be disabled
- **Pri:** P1. **Tag:** REAL.
- **Expected:** "The academy's own subdomain cannot be disabled." The row stays active.
- **Cov:** `test_domains.py::test_disable_domain_rejects_the_academy_subdomain`.

#### F01-TC-095: A disabled domain can be re-checked; an active row is skipped
- **Pri:** P3. **Tag:** REAL (the failure path), FAKE (the success path).
- **Cov:** `test_domain_admin.py::test_check_dns_action_reenables_a_disabled_domain` and
  `…reports_already_active_rows`.

#### F01-TC-096: `/internal/tls-allowed` can't be reached from outside the edge
- **Pri:** P1. **Tag:** REAL.
- **Steps:** use curl through Caddy on port 80 with each of these Host headers:
  `etqan.localhost`, `qa.etqan.localhost`, `qa-academy.test`, `localhost`, `127.0.0.1`. Request
  `/internal/tls-allowed?domain=qa.etqan.localhost`. Also try these variants: `/INTERNAL/tls-allowed`,
  `//internal/tls-allowed`, `/internal/../internal/tls-allowed` (with `--path-as-is`) and
  `/%69nternal/tls-allowed`.
- **Expected:** a 404 from the edge every time. The body is never `ok`.
- **Note:** `localhost:8000` (Django's port, published only in dev) **does** answer. Record this as
  a dev-only exposure, not a production defect; in production the ask listener is
  `127.0.0.1:8099`.
- **Cov:** none at the edge level. `test_domains.py::test_tls_not_served_on_academy_hosts` checks
  that the academy URLconf has no such route.

#### F01-TC-097: The TLS ask's answers (direct to Django, dev port only)
- **Pri:** P2. **Tag:** REAL.
- **Steps:** `curl -H 'Host: 127.0.0.1' 'http://localhost:8000/internal/tls-allowed?domain=…'`.
- **Expected:**
  - 200 `ok` for `qa.etqan.localhost`, for the active `qa-academy.test`, and for `QA.ETQAN.LOCALHOST`
    (lowercased).
  - 404 for a pending or disabled custom domain, for an unknown host, for an empty value, and for
    no parameter at all.
  - A suspended academy's domain: record the result. The code says 200, because only the domain
    status is checked. Note this in coverage-gaps as a question.
- **Cov:** `test_domains.py::test_tls_allowed`.

### J. Host resolution

#### F01-TC-100: An unknown subdomain answers 404 on the API, and "Site not found" on `/`
- **Pri:** P1. **Role:** anonymous. **Tag:** REAL.
- **Steps:**
  - `Host: nope-qa.etqan.localhost`: `/api/v1/identity/csrf/` returns 404.
  - `/` returns 404 "Site not found".
  - `/app/`: the SPA loads (Vite). Record what the login page does: it should show an error, not
    hang.
- **Cov:** `test_isolation.py::test_unknown_academy_host_is_404` and
  `academy-sites.spec.ts` ("an unknown academy host shows Site not found").

#### F01-TC-101: The bare base domain serves only Django's public URLs
- **Pri:** P1. **Tag:** REAL.
- **Steps:** on `http://etqan.localhost`:
  - `/admin/` returns 302 to the login page;
  - `/health/live/` returns 200;
  - `/api/v1/identity/csrf/` returns 404;
  - `/api/v1/academy/features/` returns 404;
  - `/app/` returns 404 from Django, not the dashboard;
  - `/` returns 404 from Django, not marketing.
- **Cov:** `test_isolation.py::test_academy_api_is_not_served_on_the_public_host`.

#### F01-TC-102: The staff admin is not served on academy hosts
- **Pri:** P1. **Tag:** REAL.
- **Steps:** `http://qa.etqan.localhost/admin/` is routed by Caddy to marketing, which returns
  404. `Host: localhost` through port 80 (the catch-all academy block) `/admin/` gives
  marketing, not the Django admin.
- **Cov:** `test_admin.py::test_admin_is_not_served_on_an_academy_host`.

#### F01-TC-103: A spoofed `X-Forwarded-Host` doesn't change the academy
- **Pri:** P1. **Tag:** REAL.
- **Steps:** as the signed-in qa admin, send
  `curl -H 'Host: qa.etqan.localhost' -H 'X-Forwarded-Host: qaother.etqan.localhost' /api/v1/identity/me/`.
- **Expected:** the qa user, because `USE_X_FORWARDED_HOST` is unset. Also send an unauthenticated
  `GET /api/v1/site/branding/` with that header: it returns qa's branding.

#### F01-TC-104: A suspended or pending host takes precedence correctly
- **Pri:** P3. **Tag:** REAL.
- **Expected:** a pending domain of a suspended academy gives 404 (the domain is checked first),
  and an active domain of a suspended academy gives 403.

### K. Cross-tenant isolation (host and schema level)

#### F01-TC-105: The qa admin cannot sign in on qaother
- **Pri:** P1. **Tag:** REAL.
- **Steps:** UI login at `http://qaother.etqan.localhost/app/login` with `qa-admin@qa.etqan.test`
  and `QA-Admin-2026!`.
- **Expected:** an error alert, and the URL stays on `/app/login`. The API returns 400.
- **Assertions:** no session row in `academy_qaother.django_session` for that attempt.
- **Cov:** `tenant-login.spec.ts` (demo vs other) and `test_isolation.py`.

#### F01-TC-106: A session cookie from qa is anonymous on qaother, even when copied by hand
- **Pri:** P1. **Tag:** REAL.
- **Steps:**
  1. Sign in on qa and capture the `sessionid` and `csrftoken` values.
  2. Send `curl -H 'Host: qaother.etqan.localhost' -b 'sessionid=<qa value>' /api/v1/identity/me/`.
- **Expected:** 401 or 403.
- **Assertions:**
  - `academy_qaother.django_session` has no row with that `session_key`.
  - The browser does not send qa's cookie to qaother: the cookies are host-only, with no
    `Domain=.etqan.localhost`.
  - `SESSION_COOKIE_DOMAIN` and `CSRF_COOKIE_DOMAIN` are unset in the settings.
- **Cov:** `test_isolation.py::test_session_from_one_academy_is_anonymous_on_another` uses a forced
  login.

#### F01-TC-107: Same user pk, different academies: the qa session is not "user 1" on qaother
- **Pri:** P1. **Tag:** REAL.
- **Note:** the qa admin and the qaother admin are both `identity_user.id=1` in their schemas.
- **Steps:** as TC-106, but also try copying a **qaother** `session_key` into qa's
  `django_session` table. **Do not** do that write. Instead, record that sessions live in each
  schema (`academy_qa.django_session` and `academy_qaother.django_session` are separate tables).
  That is the isolation mechanism.
- **Assertions:**
  - `SELECT count(*) FROM academy_qaother.django_session WHERE session_key='<qa key>'` returns 0.
  - `SELECT count(*) FROM public.django_session WHERE session_key='<qa key>'` returns 0.

#### F01-TC-108: Every role's qa session is anonymous on qaother and on the public host
- **Pri:** P1. **Roles:** qa admin, staff without codes, staff with codes, supervisor, teacher,
  student, parent. **Tag:** REAL.
- **Steps:** for each role, sign in on qa, then call `GET /api/v1/identity/me/` with the copied
  cookie on `qaother.etqan.localhost` and on `etqan.localhost`.
- **Expected:** 401 or 403 on qaother, 404 on public, and 200 on qa.

#### F01-TC-109: Etqan staff's admin session gives nothing on academy hosts
- **Pri:** P1. **Role:** Etqan staff. **Tag:** REAL.
- **Steps:** copy the `sessionid` from `etqan.localhost` to `qa.etqan.localhost`
  `/api/v1/identity/me/`.
- **Expected:** 401 or 403. A public-schema superuser is not a qa user.

#### F01-TC-110: qa's invite token is refused on qaother, where an admin with the same pk is still pending
- **Pri:** P1. **Tag:** REAL.
- **Preconditions:** qaother's admin has **not** yet accepted the invite (SETUP-4), and you have a
  fresh qa reset token: either the original invite before TC-016, or a new
  `password/reset/` for `qa-admin`.
- **Steps:** `POST http://qaother.etqan.localhost/api/v1/identity/password/reset/confirm/` with
  qa's `uid`/`token` and a new password.
- **Expected:** 400.
- **Assertions:** `academy_qaother.identity_user` id 1 still has an unusable password (`!…`), and
  the qa admin's password is unchanged.

#### F01-TC-111: Data written in qa is invisible in qaother (API and DB)
- **Pri:** P1. **Tag:** REAL.
- **Steps:** as the qa admin, create a tag (`POST /api/v1/people/tags/`, `name_en="QA-ISO-<stamp>"`).
  As the qaother admin, `GET /api/v1/people/tags/` and `GET /api/v1/people/tags/<qa tag id>/`.
- **Expected:** the tag is absent from the list, and the detail returns 404. The DB row exists only
  in `academy_qa.identity_tag`.
- **Cleanup:** delete the tag in qa.

#### F01-TC-112: The academy admin cannot reach the Etqan console
- **Pri:** P1. **Role:** qa admin. **Tag:** REAL.
- **Steps:** sign in to `http://etqan.localhost/admin/login/` with `qa-admin@qa.etqan.test` and
  `QA-Admin-2026!`.
- **Expected:** "Please enter the correct email and password for a staff account". The user is
  not in the public schema.

#### F01-TC-113: An academy-schema user with `is_staff` or `is_superuser` cannot use the console
- **Pri:** P2. **Tag:** REAL, by static check plus TC-102.
- **Note:** the admin is not routed on academy hosts, so a tenant `is_staff` flag is inert. Record
  this; no write is needed.

#### F01-TC-114: The CSRF token from qa is rejected on qaother for writes
- **Pri:** P2. **Tag:** REAL.
- **Steps:** a POST to qaother `/api/v1/identity/login/` with qa's `csrftoken` cookie and header,
  plus `Referer: http://qa.etqan.localhost/app/`.
- **Expected:** 403 CSRF (an origin or referrer mismatch), or 400 for bad credentials. Record which.

#### F01-TC-115: The journey e2e path (a command-created academy, then invite, then first month) still passes
- **Pri:** P2. **Tag:** REAL.
- **Cov:** `dashboard/e2e/journey.spec.ts`. Run it with `--workers=1`, alone. It creates a
  `journey-<stamp>` academy, so note the leftover schema.

#### F01-TC-116: The existing tenant-login e2e (demo vs other) passes
- **Pri:** P2. **Tag:** REAL.
- **Cov:** `dashboard/e2e/tenant-login.spec.ts`. Run it with `--workers=1`.

### L. Feature switches

#### F01-TC-117: `GET /api/v1/academy/features/` as the qa admin
- **Pri:** P1. **Role:** admin. **Tag:** REAL.
- **Expected:** 200 with 88 items, each with `code`, `label_ar`, `label_en`, `group`, `on`,
  `built` and `held_by`. Groups appear in the order people, teaching, money, communication,
  content, platform.
- **Assertions:**
  - On defaults, `on=true` for exactly the 7 default codes.
  - `built=false` only for `free_sessions` and `public_links`.

#### F01-TC-118: Role matrix for the features endpoint
- **Pri:** P1. **Tag:** REAL.
- **Expected:**

  | Caller | Expected |
  |---|---|
  | admin | 200 |
  | staff with no codes | 403 |
  | staff with student codes | 403 |
  | supervisor | 403 |
  | teacher | 403 |
  | student | 403 |
  | parent | 403 |
  | anonymous | 401 or 403 |
  | Etqan staff session (public cookie) | 401 or 403 |

- **Fallback:** a read-only run in demo with the seeded accounts.
- **Cov:** academy app tests. Agent 2 should cite `etqan/academy/tests` if they cover this.

#### F01-TC-119: There is no write path for switches through the academy API
- **Pri:** P1. **Role:** qa admin. **Tag:** REAL.
- **Steps:**
  - `POST`, `PUT`, `PATCH` and `DELETE /api/v1/academy/features/` each return 405.
  - `PATCH /api/v1/academy/settings/ {"supervision_enabled": true, "features": {"chat": true}}`
    returns 200 or 400 with no effect.
- **Assertions:** `tenants_academy.features` for qa is unchanged (compare the JSON).

#### F01-TC-120: `me.features` lists the effective switches, for every role
- **Pri:** P1. **Tag:** REAL.
- **Expected:** for each role in qa, `GET /api/v1/identity/me/` → `features` is the same list,
  equal to `[f.code for f in REGISTRY if is_on(...)]`, in registry order. On defaults, that is the
  7 codes.

#### F01-TC-121: `set_features` switches by subdomain and prints each stored switch
- **Pri:** P1. **Tag:** REAL (qa).
- **Steps:** `set_features qa --on chat --off families`. Then `set_features qa --on families`.
- **Expected:**
  - The first prints `qa: chat=on, families=off`; the DB JSON has `"chat": true, "families": false`.
  - qa's `me.features` reflects the change on the next request, without a restart.
  - qaother and demo stay unchanged.
- **Cov:** `test_admin_features.py::test_the_command_switches_features_by_subdomain`.

#### F01-TC-122: `set_features` refuses what it can't do
- **Pri:** P2. **Tag:** REAL.
- **Data:**
  - no flags: "Name at least one feature with --on or --off.";
  - `--on x --off x`: "A feature can't be switched both on and off.";
  - an unknown code `--on nosuch`: "Unknown feature: nosuch.";
  - an unknown subdomain `nope`: "No academy has the subdomain 'nope'.".
- **Expected:** exit non-zero, and no DB change.
- **Cov:** `test_admin_features.py::test_the_command_refuses_what_it_cannot_do`.

#### F01-TC-123: `requires`: a switched-on feature held off by its prerequisite
- **Pri:** P1. **Tag:** REAL (qa).
- **Steps:** run `set_features qa --on online_payments --off invoices`.
- **Expected:**
  - stdout `online_payments=on, invoices=off` (the stored switch, not the effective state).
  - The API features item `online_payments` has `on=false` and `held_by=["invoices"]`.
  - `me.features` lacks `online_payments`.
  - The admin change page's checkbox help text says "Held off: needs Invoices".
  - Online-payment routes return 404.
- **Cleanup:** restore with `--on invoices`.
- **Cov:** `test_admin_features.py::test_the_command_prints_the_switch_not_the_effective_state`.

#### F01-TC-124: A switched-off feature's API is 404 for admins, but 403 for callers without the code
- **Pri:** P1. **Tag:** REAL (qa).
- **Steps:** switch `families` off. Then:
  - as the admin, `GET /api/v1/people/families/` returns 404 "This feature is not enabled for this
    academy.";
  - as a teacher, the same call returns 403 (the code check comes first).
- **Cleanup:** switch `families` back on.

#### F01-TC-125: Admin change page: the feature fieldsets by group, and only changed boxes stored
- **Pri:** P1. **Tag:** REAL (browser, qaother).
- **Steps:**
  1. Open the qaother change page. There are 6 fieldsets, "Features: People" through
     "Features: Platform". The first shows the note "Only Etqan switches these…". Unbuilt items say
     "Takes effect when built.". The labels are bilingual.
  2. Tick only "Chat" and save.
- **Assertions:**
  - The DB `features` equals `{"chat": true}`; no other keys are written.
  - `django_admin_log` has a change entry.
  - qaother's `GET /api/v1/academy/features/` shows chat on.
- **Cleanup:** untick it, which stores `{"chat": false}`. Record that the key stays, which is
  expected.
- **Cov:** `test_admin_features.py::test_the_change_page_shows_the_features_by_group` and
  `…switches_a_feature_and_the_history_records_it`.

#### F01-TC-126: "Copy features from another academy"
- **Pri:** P2. **Tag:** REAL.
- **Steps:**
  1. Select qa-tmp-1, choose "Copy features from" = qa, and run the action. The message is "Copied
     the features of Etqan QA Academy to 1 academies."
  2. Run it again without choosing a source: the error "Choose the academy to copy the features
     from."
  3. Select qa itself as both the target and the source: it reports 0 academies.
- **Assertions:** the qa-tmp-1 JSON equals qa's JSON, qa is unchanged, and `django_admin_log` has
  an entry.
- **Never** use demo or other as the target.
- **Cov:** `test_admin_features.py::test_etqan_copies_features_from_another_academy` and
  `test_copying_needs_an_academy_to_copy_from`.

#### F01-TC-127: The "Copy features from" source dropdown lists no public tenant
- **Pri:** P3. **Tag:** REAL.

#### F01-TC-128: The academy admin sees switches read-only in the dashboard
- **Pri:** P2. **Role:** qa admin. **Tag:** REAL.
- **Steps:** open `/app/settings/features`.
- **Expected:**
  - A grouped list with On/Off states and "Managed by Etqan".
  - No toggle controls: no `role=switch` or checkbox inputs.
  - Matches the API.
  - Staff, teachers, students and parents see the NoAccess screen when they open it directly.
- **Cov:** `features.spec.ts` covers demo, admin only.

#### F01-TC-129: A switched-off nav item disappears, and its direct URL shows FeatureOff
- **Pri:** P2. **Tag:** REAL.
- **Cov:** `features.spec.ts` (demo families). Rerun it as is with `--workers=1`. It restores demo
  in `finally`. **Or** replicate it on qa to avoid touching demo, which is preferred.

#### F01-TC-130: Feature data is kept when a feature is switched off
- **Pri:** P2. **Tag:** REAL (qa).
- **Steps:** create a family in qa, switch `families` off and then on.
- **Expected:** the family is unchanged: same id, same members.

### M. Etqan console access control ("only Etqan staff can change switches")

#### F01-TC-133: A view-only Etqan staff member can't change switches or status
- **Pri:** P1. **Role:** `ops-view@qa.etqan.test`. **Tag:** REAL.
- **Expected:**
  - The academy change page renders read-only with no Save button.
  - Forging a POST to `/admin/tenants/academy/<qa>/change/` returns 403.
  - The actions (suspend, reactivate, copy) are not offered, or are refused.
  - Adding an academy (`/admin/tenants/academy/add/`) returns 403.
- **Assertions:** qa's `features` and `status` are unchanged.

#### F01-TC-134: `is_staff` with no permissions: the admin index shows nothing, and every tenants URL returns 403
- **Pri:** P1. **Role:** `ops-noperm@qa.etqan.test`. **Tag:** REAL.

#### F01-TC-135: Anonymous access to admin URLs redirects to the login page
- **Pri:** P2. **Tag:** REAL.
- **Steps:** `GET /admin/tenants/academy/` returns 302 to `/admin/login/?next=…`.

#### F01-TC-136: The admin login is CSRF-protected and its session is host-only
- **Pri:** P3. **Tag:** REAL.

#### F01-TC-137: The Domains admin hides public domains, refuses delete, and its change page is read-only
- **Pri:** P2. **Tag:** REAL.
- **Expected:** `etqan.localhost`, `localhost` and `127.0.0.1` are not listed. Opening their
  change URL by id gives "doesn't exist".
- **Cov:** `test_domain_admin.py::test_domain_admin_hides_public_domains`.

#### F01-TC-138: The admin history records Etqan staff changes
- **Pri:** P3. **Tag:** REAL.
- **Assertions:** `public.django_admin_log` has rows for the academy add, feature changes, copy,
  domain add and defaults suspension, with the correct `user_id` (ops).
- **Note:** suspend and reactivate use `message_user` only. Record whether the status actions are
  logged. The code suggests they are **not**, so that would be an audit gap, P3.

### N. UX, a11y and RTL basics

#### F01-TC-140: The Add-academy form is usable
- **Pri:** P3. **Tag:** REAL.
- **Assertions:**
  - The help text on admin email ("gets a set-password email") is visible.
  - Errors appear next to their fields.
  - Labels are associated with their fields (Django admin default).
  - Timezone is a free text box: there is no picker or choice list. Record this as a UX note
    linked to S1.

#### F01-TC-141: The first-admin set-password page is RTL in Arabic, keyboard-operable, and its error is announced
- **Pri:** P3. **Tag:** REAL.
- **Assertions:**
  - `html[dir=rtl]` is set when the locale is `ar`.
  - Focus order runs from the password field to submit.
  - A weak password shows an error with `role=alert` or `aria-live`.

#### F01-TC-142: Login branding per academy
- **Pri:** P3. **Tag:** REAL.
- **Expected:** the qa login shows "Etqan QA Academy", and the qaother login shows "Etqan QA Other".
- **Cov:** `academy-sites.spec.ts` ("the dashboard login is branded per academy") covers demo and
  other.

#### F01-TC-143: The new academy's public site renders with the defaults
- **Pri:** P3. **Tag:** REAL.
- **Steps:** `GET http://qa.etqan.localhost/`.
- **Expected:** 200, the Arabic hero "تعلّم مع أفضل المعلمين", `dir=rtl`, and the name "Etqan QA
  Academy".

---

## 7. Coverage summary

| Area | Cases | Existing automated cover | Needs new execution |
|---|---|---|---|
| A Dev env / QA-001 | 001–007 | none | all |
| B Admin onboarding | 010–025 | service and test-client only | all (browser) |
| C Command/service | 026–033 | `test_services.py`, `test_commands.py`, journey e2e | 026–029, 031, 033 |
| D Subdomain edges | 036–040 | partly | 036–040 (probes) |
| E Timezone/currency | 050–056 | defaults only | 051–056 (S1, S4) |
| F Rollback/concurrency | 058–062 | one step only | 058 (new pytest), 059, 061, 062 |
| G Suspension | 064–075 | `test_middleware.py`, `test_admin.py` | 064–074 REAL |
| H Defaults suspended | 076–081 | `test_admin_suspend.py` | 077, 079, 081; 078 new pytest |
| I Custom domains/TLS | 082–097 | `test_domains.py`, `test_domain_admin.py` | 084 (S2), 086–097 REAL; 088 BLOCKED |
| J Host resolution | 100–104 | `test_isolation.py`, `academy-sites.spec.ts` | 100–104 |
| K Isolation | 105–116 | `test_isolation.py`, `tenant-login.spec.ts` | 105–114 |
| L Features | 117–130 | `test_admin_features.py`, `features.spec.ts` | 117–130 on qa |
| M Console access control | 133–138 | `test_admin*.py`, superuser only | 133–138 |
| N UX/a11y/RTL | 140–143 | partly | all |

**Counts:** 123 cases in total: 57 P1, 45 P2 and 21 P3.

**Expected tags:**
- Mostly REAL.
- FAKE: 030, 032, 058, 060 and 078.
- SIMULATED or BLOCKED: 079.
- BLOCKED: 088 (the DNS success path).

**Top risks:**
1. The real Add-academy browser flow and its invite, end to end (TC-011 to TC-017). This is the
   customer entry point, and there is no e2e for it.
2. Cross-tenant session, credential and token isolation (TC-105 to TC-110).
3. S1: an invalid timezone or currency is accepted at creation (TC-052 to TC-054).
4. Suspension completeness: every Django path, existing sessions, health (TC-064 to TC-073).
5. The edge-level unreachability of `/internal/tls-allowed` (TC-096).
6. Console access control for staff who are not superusers (TC-133 and TC-134).
7. Rollback when the process is killed mid-provision (TC-059).

## 8. Cleanup plan

- **Kept:**
  - qa and qaother, with their admins and QA people;
  - the `ops@`, `ops-view@` and `ops-noperm@` Etqan staff accounts. Record them in
    `qa/environment.md`.
- **Restore after each case:**
  - qa's feature switches, to the SETUP-6 state;
  - qa-tmp-1's domains: leave `qa-academy.test` disabled and the subdomain primary;
  - fixture invoices: delete them;
  - QA tags: delete them.
- **Throwaway academies:** they can't be deleted from the admin, by design. At the end, suspend
  every `qa-tmp-*` academy (so beat skips them) and list them in `environment.md`. Physically
  dropping a schema (`Academy.delete(force_drop=True)` in a shell) is a destructive DDL step.
  Do it only with the owner's go-ahead, and never for demo or other.
- **Docker:** remove the `etqan-qa001-*` images built in TC-001 to TC-005.
- **Never:** suspend, re-feature or write demo or other.
  - Exception: TC-129, if it is rerun as the existing spec. That spec restores demo itself.
    Running it on qa is preferred.


---

## Added by Agent 2 (execution checks, 2026-10-17)

Critical review of the spec: it is sound and well grounded in the code. Corrections made while executing
(the product was right, the expectation was not): TC-019 (slug error message), TC-066 (`/healthx/` is
routed to marketing at the edge), TC-055 (documented seed-only behaviour), TC-111 (tags have no detail
GET and no DELETE), TC-117 (API order is registry order), TC-121/125 (the code is `internal_chat`),
TC-141 (visitors start in English), TC-143 (`/` is a locale redirect). Added checks:

- **F01-A2-01 (P1):** a view-only Etqan staff member runs each changelist action from the real UI
  (Copy features, Suspend, Reactivate) and the Domain actions; expected refused.
- **F01-A2-02 (P2):** the sign-in API is CSRF-protected for anonymous callers (no token, foreign
  Origin, form-encoded); expected 403 (ADR-0003, architecture.md).
- **F01-A2-03 (P2):** with Etqan's defaults suspended and no own email account, does transactional
  email (password reset) still go out? Record against SUSPEND_HELP.
- **F01-A2-04 (P3):** `/internal/tls-allowed` answer for an active domain of a suspended academy.
- **F01-A2-05 (P3):** the e2e harness (`manage()` via `E2E_MANAGE`) works from a checkout path with a
  space.
- **F01-A2-06 (P3):** punycode (`xn--…`) subdomains: accepted or reserved?
- **F01-A2-07 (P1):** a broken academy (bad timezone) must not break platform-wide commands/jobs for the
  others (`scan_notifications`, `run_daily`, `notifications.scan`).
- **F01-A2-08 (P4):** domain action messages show the hostname as stored and confirm success.

## Results (Agent 2, run 2026-10-17, F01 cycle 1)

Environment: local stack (backend adff9c9, dashboard 5ed775d), Playwright 1.62.1 Chromium, 1 worker
(`just e2e`), Mailpit, psql on :5433. Evidence paths are relative to `qa/evidence/F01/`. Specs:
`dashboard/e2e/qa/f01-{helpers,onboarding,invite,create-edge,console,features-admin,dashboard}.spec.ts`
(each console/features-admin test is run alone with `--grep`, in the order of this table, because
API/DB checks run between them; `f01-onboarding` and `f01-create-edge` create academies and are
one-shot). Scoped pytest: `pytest etqan/tenants` 172 passed (`pytest-tenants.txt`).

**Counts (spec cases, 123):** executed 117, PASS 105, FAIL 12, BLOCKED 6; tags REAL 115, FAKE 2,
SIMULATED 0, BLOCKED 6. **Added checks (8):** PASS 3, FAIL 5 (all REAL).
**Gate:** F01 is **not passed**: TESTING → needs Agent 3 (ETQAN-QA-001..011), then Agent 2 retest.

| Case | Result | Tag | Evidence | Notes |
|---|---|---|---|---|
| TC-001 | FAIL | REAL | tc001-003-qa001-repro.txt | ETQAN-QA-001 reproduced: the dashboard dev-stage user line (`deluser node; addgroup -g 20 app`) fails in node:22-alpine: "addgroup: gid '20' in use" (group 20 = dialout). Full image build not run: the dev stage needs the private tokens BuildKit secret before this line. Retest after Agent 3's fix. |
| TC-002 | FAIL | REAL | tc001-003-qa001-repro.txt | Same Alpine line as the dashboard (marketing/Dockerfile:49); same failure. ETQAN-QA-001. |
| TC-003 | FAIL | REAL | tc001-003-qa001-repro.txt | `docker build --target dev --build-arg UID=501 --build-arg GID=20 -t etqan-qa001-backend:gid20 backend`: "groupadd: GID '20' already exists", exit 1. ETQAN-QA-001. |
| TC-004 | BLOCKED | BLOCKED | - | Regression of the fix; no fix yet (Agent 3). The current images were built with 1000:1000 (environment.md setup log). |
| TC-005 | BLOCKED | BLOCKED | - | Edge case of the fix; run after Agent 3's change. |
| TC-006 | BLOCKED | BLOCKED | - | `docker compose build` would retag the running stack's images; run after the fix with separate tags only (SIMULATED by 001-003). |
| TC-007 | PASS | REAL | tc007-docker-ps-before.txt, tc007-docker-ps-after.txt, tc007-diff.txt | Container IDs, created times and image IDs identical (sorted) before/after the builds. |
| TC-010 | PASS | REAL | pw/tc010-login.json, pw/tc010-admin-index.png | Real browser login; header "Etqan — academies"; Academies + Domains; `sessionid` host-only on etqan.localhost, no `Domain=`. |
| TC-011 | PASS | REAL | pw/tc011-add.json, pw/tc011-add-form-fields.json, pw/tc011-change-page.json, pw/tc011-*.png, tc011-013-db-qa.txt | Exactly the 8 fields, no inline/feature boxes; POST 302 after 14.9 s; success message; row Active/EGP; DB row, primary domain, schema 143 tables / 171 migrations; change page has 6 feature fieldsets + read-only Domains inline; subdomain/schema/created_at read-only. |
| TC-012 | PASS | REAL | tc011-013-db-qa.txt | Settings Africa/Cairo/EGP/ar; branding; DEFAULT_HERO; sitesettings; 43 tags (21/22); Supervisor with 20 codes, permissions md5 equal to academy_other. |
| TC-013 | PASS | REAL | tc011-013-db-qa.txt | 1 admin user (ar, Africa/Cairo, unusable `!` password); email primary+verified; no public row. |
| TC-014 | PASS | REAL | tc014-mailpit-search.json, tc014-invite-message.json | 1 Arabic invite, subject "[Etqan QA Academy] …", from noreply@etqan.academy, link on its own line with the qa host; sent after commit (19:49:37 > created_at 19:49:22); the retry that hit "already taken" sent nothing. |
| TC-015 | PASS | REAL | tc014-invite-message.json | HTML part `dir="rtl"`, Arabic intact, link unwrapped. Note: `<html>` has no lang (cosmetic, not filed). |
| TC-016 | PASS | REAL | pw/tc016-confirm.json, tc016-017-db.txt | Confirm 200, "you can now sign in", hash now argon2. |
| TC-017 | PASS | REAL | pw/tc017-me.json, pw/tc017-dashboard.png, tc016-017-db.txt | h1 "QA Admin"; login page branded; me 200 (email, admin, 7 default features); 1 session row; last_login set; cookies host-only. |
| TC-018 | PASS | REAL | pw/tc018-reuse.json, tc024-036-040-validate-probe.txt | Reuse 400 and altered token 400 "Invalid or expired reset link."; password still QA-Admin-2026!. |
| TC-019 | PASS | REAL | pw/tc019-022-form-errors.json, tc019-db-before.txt | 12 bad subdomains → 200 with an inline error and value kept. Spec correction: `.`, space, Arabic and Cyrillic input fail the model SlugField first ("Enter a valid “slug”…"), not the regex message. Nothing created, no probe mail. |
| TC-020 | PASS | REAL | pw/tc019-022-form-errors.json | All 11 reserved names → "This subdomain is reserved." |
| TC-021 | PASS | REAL | pw/tc019-022-form-errors.json, tc024-036-040-validate-probe.txt | demo, qaother (form) and qa (service) → "already taken"; demo row unchanged. |
| TC-022 | PASS | REAL | pw/tc019-022-form-errors.json | Empty → required; `not-an-email`, `a@b` → "Enter a valid email address." |
| TC-023 | PASS | REAL | pw/tc019-022-form-errors.json | Empty → required; 201 chars → "at most 200 characters (it has 201)". Arabic/emoji names (optional) not run. |
| TC-024 | PASS | REAL | tc024-036-040-validate-probe.txt | `"  qa-tmp-x  "` → `qa-tmp-x`. |
| TC-025 | PASS | REAL | pw/tc025-forged-subdomain.json, tc080-055-025.txt | Forged subdomain/schema_name ignored; qa row and domain unchanged. |
| TC-026 | PASS | REAL | tc026-create-qaother.txt, tc026-schema-qaother-vs-other.txt, tc026-mailpit-invite.txt | exit 0, 18 s; defaults equal academy_other; 1 invite with qaother host. |
| TC-027 | PASS | REAL | tc027-028-033-054-commands.txt | www/qa/Bad → CommandError, exit 1, no traceback, nothing created. |
| TC-028 | PASS | REAL | tc027-028-033-054-commands.txt | Missing --admin-email → argparse exit 2. |
| TC-029 | PASS | REAL | tc029-031-create-qa-tmp-1.txt | `academy_qa_tmp_1`, `qa-tmp-1.etqan.localhost`. |
| TC-030 | PASS | FAKE | pytest-tenants.txt | `test_subdomain_with_a_leftover_schema_is_rejected` and `…leftover_domain…` pass (172 passed). Optional REAL DDL probe skipped (owner-sensitive). |
| TC-031 | PASS | REAL | tc029-031-create-qa-tmp-1.txt | Same admin email in qa-tmp-1; separate rows; qa hash unchanged; each password only works on its own academy. |
| TC-032 | PASS | FAKE | pytest-tenants.txt | `test_admin_with_password_gets_no_email` passes. |
| TC-033 | PASS | REAL | tc027-028-033-054-commands.txt | Twice "public tenant ready: …", exit 0, domain count unchanged. |
| TC-036 | PASS | REAL | tc024-036-040-validate-probe.txt | z, 32×z accepted; 33×z, `z-` refused. |
| TC-037 | PASS | REAL | tc024-036-040-validate-probe.txt | Cyrillic, full-width, %00, NUL refused; `qa\n`/`qa\t` strip to taken `qa`; `zz\n` → `zz` (strip, intended). |
| TC-038 | PASS | REAL | tc024-036-040-validate-probe.txt | `a--b`, `123` accepted (documented). |
| TC-039 | PASS | REAL | tc024-036-040-validate-probe.txt | `WWW` refused by the regex. |
| TC-040 | PASS | REAL | tc024-036-040-validate-probe.txt | status/support/docs/billing/staging/e2e/grafana/signoz accepted: product question in coverage-gaps. |
| TC-050 | PASS | REAL | tc026-schema-qaother-vs-other.txt | qaother UTC/USD; settings UTC/USD/ar; admin UTC. |
| TC-051 | PASS | REAL | tc056-051-settings.txt, pw/tc051-settings-ui.json, pw/tc051-settings.png | API Africa/Cairo/EGP; dashboard Settings → Academy shows Cairo and EGP. |
| TC-052 | FAIL | REAL | pw/tc052-053-submit.json, tc052-*.txt | ETQAN-QA-003: `Mars/Phobos` accepted; Today and invoices 500; run_lifecycle raises; notifications.scan fails every minute. |
| TC-053 | FAIL | REAL | tc052-db.txt | ETQAN-QA-003: `usd` stored lowercase (not normalised, not refused). `US`/`1$` not created (one probe only, per spec). |
| TC-054 | PASS | REAL | tc027-028-033-054-commands.txt | Order recorded: subdomain is validated first (taken + bad timezone → "already taken"). Command parity for S1 is static (same service; no extra schema created). |
| TC-055 | PASS | REAL | pw/tc055-timezone-edit.json, tc080-055-025.txt | Academy row → Asia/Riyadh; AcademySettings and the API stay UTC. This is documented (`academy-settings.md`: the Academy fields only seed settings). Spec corrected; UX question in coverage-gaps. |
| TC-056 | PASS | REAL | tc056-051-settings.txt | PATCH Mars/Phobos → 400 "Unknown timezone."; `egp` → 200 stored EGP; `1$` → 400. Restored Africa/Cairo/EGP. |
| TC-058 | BLOCKED | BLOCKED | pytest-tenants.txt | Needs Agent 3's new parametrised rollback pytest (test-only). The existing one-step test passes (FAKE). |
| TC-059 | PASS | REAL | tc059-kill.txt, tc059-create-output.txt | SIGINT after 45 migrations: exit 130; no row, domain, schema, idle-in-transaction session or mail; subdomain valid again. |
| TC-060 | BLOCKED | BLOCKED | - | Needs Agent 3's new admin save-path pytest (FAKE). |
| TC-061 | PASS | REAL | pw/tc061-double-submit.json, pw/tc061-double-submit.png | Double-click Save: 1 POST, 1 academy, no 500. |
| TC-062 | FAIL | REAL | tc062-race.txt, tc062-proc1.txt, tc062-proc2.txt | ETQAN-QA-005: loser crashes with a raw IntegrityError traceback. Data consistent (1 row/domain/schema/invite). |
| TC-064 | PASS | REAL | pw/tc064-suspend.json, pw/tc064-suspended.png, tc064-pre.txt | "Suspended 1 academies."; only qa-tmp-1 changed. |
| TC-065 | PASS | REAL | tc065-069-suspended-http.txt | csrf, login, branding, /accounts/, /media/x, me → 403 `tenant.suspended` JSON; no new session; last_login unchanged. |
| TC-066 | PASS | REAL | tc065-069-suspended-http.txt | /health/live/ and /health/ready/ 200; /health/ 404. Spec correction: `/healthx/` goes to marketing at the edge (Caddy routes only /health/*), which answers 503 suspended page, not Django's 403. |
| TC-067 | PASS | REAL | tc064-pre.txt, tc065-069-suspended-http.txt | A session signed in before suspension gets 403 tenant.suspended immediately. |
| TC-068 | PASS | REAL | tc065-069-suspended-http.txt, tc068-suspended-site.html | 503 "This site is temporarily unavailable / الموقع غير متاح مؤقتاً", no academy content. |
| TC-069 | PASS | REAL | tc065-069-suspended-http.txt | qa me 200, qaother csrf 200, demo login page 200. |
| TC-070 | PASS | REAL | tc070-for-each-academy.txt | for_each_academy skips academy_qa_tmp_1, includes academy_qa. |
| TC-071 | PASS | REAL | pw/tc071-suspended-ui.json, pw/tc071-*.png | S5 refuted: after Sign in a `role=alert` reads "This academy is suspended. Please contact Etqan." (no up-front notice before submitting; noted). |
| TC-072 | PASS | REAL | pw/tc072-reactivate.json, tc072-after.txt | "Reactivated 1 academies."; API 200; user hash and settings unchanged; the old session works again. |
| TC-073 | PASS | REAL | pw/tc073-075-127-137.json | Public row not listed; /1/change/ → "doesn't exist"; forged action → "Suspended 0 academies."; public stays active. |
| TC-074 | PASS | REAL | tc074-db-http.txt, pw/tc074-change-form-suspend.json | Change-form status=suspended → 403 tenant.suspended, health 200; reactivated through the form. |
| TC-075 | PASS | REAL | pw/tc073-075-127-137.json | No delete action/link; academy and domain delete URLs 403. |
| TC-076 | PASS | REAL | pw/tc076-defaults-refused.json | Help "No unpaid Etqan invoice."; form error "…unpaid 30 days after issue."; DB f. |
| TC-077 | PASS | REAL | tc077.txt, pw/tc077a-29d.json, pw/tc077b-30d.json | 29d23h: "issued 29 days ago", refused; 30d+1min: allowed, flag t, admin history row by ops@. Fixture invoice deleted. |
| TC-078 | PASS | REAL | tc078-draft-paid-zero.txt | Draft, paid and zero-total invoices aged 40 days: oldest_unpaid_days None, may_suspend False (service-level, real DB). pytest has no draft/paid case (gap). |
| TC-079 | PASS | REAL | tc079-081.txt | Integrations: email default_status `suspended` (the only enabled platform account); others `disabled`. Live provider path BLOCKED (no credentials). With defaults suspended the password-reset email is not sent ("Email not sent: not set up"): matches SUSPEND_HELP; owner question in coverage-gaps. |
| TC-080 | PASS | REAL | pw/tc080-lift.json, tc080-055-025.txt | Untick with the invoice still unpaid → saved, flag f. |
| TC-081 | PASS | REAL | tc079-081.txt | Defaults suspended + active: csrf 200, me 200. |
| TC-082 | PASS | REAL | tc082-domains-after.txt, pw/tc082-085-domain-add.json | `QA-Academy.TEST.` stored as `qa-academy.test` pending, custom, not primary; help names sites.etqan.localhost; tenant list has no "Etqan". |
| TC-083 | PASS | REAL | pw/tc082-085-domain-add.json | Base domain and Etqan subdomains → "Use the academy's own domain, not an Etqan subdomain." |
| TC-084 | FAIL | REAL | pw/tc082-085-domain-add.json, pw/tc084-first-attempt.png, tc089-activate.txt | ETQAN-QA-004: 5 invalid hosts → HTTP 500. The 254-character case was truncated to 253 by the browser maxlength (harness); service refuses 254 chars (tc089-activate.txt). |
| TC-085 | PASS | REAL | pw/tc082-085-domain-add.json | Duplicate (same/other tenant) and `localhost` → "Domain with this Domain already exists.", no 500. |
| TC-086 | PASS | REAL | tc086-104-pending-host.txt | Pending domain: API 404, `/` 404 Site not found. |
| TC-087 | PASS | REAL | pw/tc087-092.json | "resolves to nothing / resolves to 127.0.0.1, ::1, expected sites.etqan.localhost."; both stay pending (hostname capitalised in messages: ETQAN-QA-010). |
| TC-088 | BLOCKED | BLOCKED | pytest-tenants.txt | DNS success path cannot run locally. FAKE tests pass; no superset (edge IP + foreign IP) test exists: gap for Agent 3. |
| TC-089 | PASS | REAL | tc089-activate.txt | Activated by service (DNS step bypassed, labelled): csrf 200, branding "QA Tmp One"; verified_at set. |
| TC-090 | PASS | REAL | tc089-activate.txt | `QA-ACADEMY.TEST:80` 200; `www.` 404 until its own row is activated, then 200. |
| TC-091 | PASS | REAL | tc091-primary.txt, pw/tc091-make-primary.json | One primary for qa-tmp-1; reset-email link follows the primary (www., then qa-academy.test); other primaries unchanged. No success message (ETQAN-QA-010). |
| TC-092 | PASS | REAL | pw/tc087-092.json | "Only an active domain can be primary." |
| TC-093 | PASS | REAL | tc093-after.txt, pw/tc093-094-095.json | Disabled, not primary; subdomain primary again; host 404; reset link back to the subdomain. |
| TC-094 | PASS | REAL | pw/tc093-094-095.json | "The academy's own subdomain cannot be disabled." |
| TC-095 | PASS | REAL | pw/tc093-094-095.json | Disabled domain re-checked (DNS fails, stays disabled); active row "skipped, already active". Success path FAKE (pytest). |
| TC-096 | PASS | REAL | tc096-097-tls-ask.txt | 42 host/path variants through Caddy :80 → 404, never `ok`. |
| TC-097 | PASS | REAL | tc096-097-tls-ask.txt, tc089-activate.txt, tc093-after.txt | :8000 (dev only): qa / QA uppercase / active custom → ok; pending, disabled, unknown, empty, missing → 404. Suspended academy's subdomain → 200 ok (recorded; question in coverage-gaps). |
| TC-100 | FAIL | REAL | tc100-103-host-resolution.txt, pw/tc100-unknown-host-spa.json | API 404, `/` Site not found (pass), but the SPA login on the unknown host fails silently: ETQAN-QA-008. |
| TC-101 | PASS | REAL | tc100-103-host-resolution.txt | /admin/ 302, /health/live/ 200, API/app/root/accounts/media 404 from Django. |
| TC-102 | PASS | REAL | tc100-103-host-resolution.txt | Admin on qa/localhost/127.0.0.1 → marketing 404. |
| TC-103 | PASS | REAL | tc100-103-host-resolution.txt | X-Forwarded-Host ignored (USE_X_FORWARDED_HOST False). |
| TC-104 | PASS | REAL | tc086-104-pending-host.txt | Pending domain of a suspended academy 404; its active subdomain 403. |
| TC-105 | PASS | REAL | pw/tc105-login-qaother.json, pw/tc105-qaother-refused.png | 400 "Invalid credentials.", alert, stays on /app/login, 0 qaother sessions. |
| TC-106 | PASS | REAL | tc106-109-session-isolation.txt, pw/tc017-me.json | Copied qa cookie → 403 on qaother; cookies host-only; SESSION/CSRF_COOKIE_DOMAIN None. |
| TC-107 | PASS | REAL | tc106-109-session-isolation.txt | User id 1 in both schemas; qa session keys only in academy_qa.django_session. |
| TC-108 | PASS | REAL | tc106-109-session-isolation.txt | 7 roles: 200 on qa, 403 on qaother, 404 on public. |
| TC-109 | PASS | REAL | tc106-109-session-isolation.txt | Etqan staff session on qa → 403 "Authentication credentials were not provided." |
| TC-110 | PASS | REAL | pw/tc110-cross-tenant-token.json, tc018-105-110-db.txt | qa uid/token on qaother (pending admin id 1) → 400; qaother password still unusable. |
| TC-111 | PASS | REAL | tc111-112-114.txt | qa tag absent from qaother list, DB row only in academy_qa. Spec correction: tag detail has no GET (405); tags have no DELETE, so cleanup was by ORM. |
| TC-112 | PASS | REAL | tc111-112-114.txt | "Please enter the correct email and password for a staff account." |
| TC-113 | PASS | REAL | tc100-103-host-resolution.txt | Static + TC-102: the admin is not routed on academy hosts. |
| TC-114 | FAIL | REAL | tc111-112-114.txt | qa's token + qa Origin on qaother login → 200; no token at all → 200: ETQAN-QA-006 (login CSRF). |
| TC-115 | PASS | REAL | pw/journey-run.txt, pw/journey-run1-blocked-by-qa003.txt | Passed (1.0 m) after qa-tmp-tz was suspended; the two earlier runs failed on ETQAN-QA-003's knock-on. Leftover academies journey-1792270407267/…459368/…543395. |
| TC-116 | PASS | REAL | pw/tenant-login-run.txt | 3/3 passed. |
| TC-117 | PASS | REAL | tc117-118-120-features.txt, tc117-features.json | 200, 88 items with the 7 keys, 7 defaults on, unbuilt free_sessions/public_links. Spec correction: the API is in registry order (first appearance …, platform, content), the admin fieldsets and dashboard group People…Platform. |
| TC-118 | PASS | REAL | tc117-118-120-features.txt | admin 200; every other role, anonymous and the Etqan staff cookie 403. |
| TC-119 | PASS | REAL | tc119-no-write-path.txt | POST/PUT/PATCH/DELETE 405; settings PATCH with features has no effect. |
| TC-120 | PASS | REAL | tc117-118-120-features.txt | me.features = the 7 defaults for all 7 roles, registry order. |
| TC-121 | PASS | REAL | tc121-123-set-features.txt | Spec correction: the code is `internal_chat` (`chat` → "Unknown feature: chat."). `--on internal_chat --off families` → stored and reflected in me without restart; demo/qaother unchanged. |
| TC-122 | PASS | REAL | tc121-123-set-features.txt | All four refusals, exit 1, no DB change. |
| TC-123 | PASS | REAL | tc121-123-set-features.txt | online_payments stored on, API on=false held_by [invoices], absent from me, admin help "Held off: needs Invoices and receipts.", gateways routes 404. Restored. |
| TC-124 | PASS | REAL | tc121-123-set-features.txt | families off: admin 404 "not enabled"; teacher and staff-codes 403. Restored. |
| TC-125 | PASS | REAL | pw/tc125-fieldsets.json, pw/tc125-change-page.png, tc125-126-076.txt | 6 fieldsets, note, 88 boxes, unbuilt text, bilingual labels; tick → `{"internal_chat": true}`, history row, API on; untick → `{"internal_chat": false}` (key kept). |
| TC-126 | PASS | REAL | pw/tc126-copy.json, tc125-126-076.txt | Copied qa → qa-tmp-1 (JSON equal), no-source error, self → 0; history row. |
| TC-127 | PASS | REAL | pw/tc073-075-127-137.json | Copy-from list has no "Etqan". |
| TC-128 | PASS | REAL | pw/tc128-features-ui.json, pw/tc128-features-page.png | Grouped read-only list equal to the API, "Managed by Etqan", no switches. Staff/supervisor see NoAccess; teacher/student/parent land on their home (not NoAccess): acceptable, spec note. |
| TC-129 | PASS | REAL | pw/tc129-feature-off.png, pw/f01-dashboard-TC-129.txt | On qa: Families nav gone, direct URL shows FeatureOff; restored. |
| TC-130 | PASS | REAL | pw/tc130-family-kept.json | Family 1 identical before/after off/on. |
| TC-133 | FAIL | REAL | pw/tc133-view-only.json, pw/tc133b-view-only-actions.json, tc133-db.txt, tc133b-db.txt, tc133c-view-only-domain-actions.txt | ETQAN-QA-002: change/add/save refused (403) but Suspend/Reactivate/Copy (and domain actions) offered and executed; qa got suspended (restored). |
| TC-134 | PASS | REAL | pw/tc134-noperm.json | Index "don't have permission"; every tenants URL 403. |
| TC-135 | PASS | REAL | pw/tc135-anon.json | 302 to /admin/login/?next=. |
| TC-136 | PASS | REAL | tc136-138-admin-audit.txt, pw/tc010-login.json | Login POST without token 403; session host-only, HttpOnly, Lax. |
| TC-137 | PASS | REAL | pw/tc073-075-127-137.json | Public domains not listed; /domain/1/change/ redirects; delete 403. |
| TC-138 | FAIL | REAL | tc136-138-admin-audit.txt | ETQAN-QA-007: adds, switches, copies, domain adds and form edits are logged; action-driven suspend/reactivate are not. |
| TC-140 | PASS | REAL | pw/tc011-add-form-fields.json, pw/tc011-add-form.png | Admin-email help visible, errors next to fields, labels associated; timezone is a free text input (UX note, linked to ETQAN-QA-003). |
| TC-141 | FAIL | REAL | pw/tc141-ar-reset.json, pw/tc141-ar-reset-page.png | dir=rtl lang=ar once Arabic is chosen (visitors start in English by design), focus order password → show → submit, error has role=alert, but the message is the raw English zod text: ETQAN-QA-011. |
| TC-142 | PASS | REAL | pw/tc017-me.json, pw/tc105-login-qaother.json | qa login shows "Etqan QA Academy", qaother "Etqan QA Other". |
| TC-143 | PASS | REAL | pw/tc143-public-site.json, pw/tc143-public-site.png, tc143-locale-redirect.txt | `/` redirects by Accept-Language (default /ar/); /ar/ 200, rtl, Arabic hero, academy name. Spec correction: `/` is a 302, not 200. |
| A2-01 | FAIL | REAL | pw/tc133b-view-only-actions.json | View-only staff runs Copy/Suspend/Reactivate from the UI (ETQAN-QA-002). |
| A2-02 | FAIL | REAL | tc111-112-114.txt | Anonymous login accepts no-token cross-site POST (ETQAN-QA-006). |
| A2-03 | PASS | REAL | tc079-081.txt | Defaults suspended stops the reset email (by design per SUSPEND_HELP; owner question). |
| A2-04 | PASS | REAL | tc096-097-tls-ask.txt | TLS ask answers ok for a suspended academy's domain (code intent; owner question). |
| A2-05 | FAIL | REAL | pw/f01-dashboard-run1.txt | e2e manage() breaks with a space in the checkout path (ETQAN-QA-009). |
| A2-06 | PASS | REAL | a2-07-punycode-probe.txt | `xn--` (punycode) subdomains are accepted: product question (homograph risk) in coverage-gaps. |
| A2-07 | FAIL | REAL | pw/journey-run1-blocked-by-qa003.txt, tc052-celery-log.txt | One bad-timezone academy makes `scan_notifications` fail platform-wide (part of ETQAN-QA-003). |
| A2-08 | FAIL | REAL | pw/tc087-092.json, pw/tc091-make-primary.json | Domain action messages capitalise hostnames; Make primary/Disable confirm nothing (ETQAN-QA-010, P4). |

## Retest 1 (Agent 2, 2026-10-17/18, fix cycle 1: ETQAN-QA-001, 002, 003, 006)

Environment: same stack; backend/dashboard/marketing working trees with Agent 3's uncommitted fix
(diffs saved in `retest-1/diff-*.txt`, unchanged at the end of the retest). Evidence under
`qa/evidence/F01/retest-1/`. Scoped pytest with the fix: `etqan/tenants` 189 passed (31m38s),
`etqan/identity` 851 passed, `etqan/platform` 226 passed, all exit 0; Agent 3 regression files 60
passed. Playwright `--workers=1`: f01-login-csrf 2/2, tenant-login 3/3, f01-console TC-133 + TC-134,
b9-sign-in 4/4. No regressions found.

| Case | Cycle 1 | Retest 1 | Tag | Evidence | Notes |
|---|---|---|---|---|---|
| TC-001 | FAIL | PASS | REAL | qa001-build-dashboard-gid20.txt | Dashboard dev build UID 501 / GID 20 exit 0; app joins dialout(20); /app and node_modules 501:20. QA-001 VERIFIED. |
| TC-002 | FAIL | PASS | REAL | qa001-build-marketing-gid20.txt | Marketing dev build, same result. |
| TC-003 | FAIL | PASS | REAL | qa001-build-backend-gid20.txt | Backend dev build exit 0; `manage.py check` runs as app. |
| TC-004 | BLOCKED | PASS | REAL | qa001-build-*-gid1000.txt | 1000:1000 still creates its own `app` group, all three exit 0. |
| TC-005 | BLOCKED | PASS | REAL | qa001-build-backend-uid1.txt | UID clash fails with a clear message ("useradd: UID 1 is not unique"). |
| TC-006 | BLOCKED | PASS (separate tags) | REAL | qa001-build-*.txt | Built with separate tags, not `docker compose build` (would retag the running stack). |
| TC-007 | PASS | PASS | REAL | qa001-tc007-diff.txt | docker ps and stack image IDs identical before/after; test images removed. |
| TC-052 | FAIL | PASS | REAL | qa003-live-negative.txt | `Mars/Phobos`, `africa/cairo` → form error "Unknown timezone."; command CommandError; nothing created. QA-003 VERIFIED. |
| TC-053 | FAIL | PASS | REAL | qa003-live-negative.txt, qa003-live-positive.txt | `US`, `E1P` refused; `egp` stored `EGP`. |
| TC-114 | FAIL | PASS | REAL | qa006-live.txt, playwright.txt, playwright-b9-sign-in.txt | Cross-site / no-token / replayed-token login → 403; same-origin flow 200. QA-006 VERIFIED. |
| TC-133 | FAIL | PASS | REAL | qa002-live.txt, playwright.txt | View-only: no actions offered; 7 forged actions change nothing (DB md5s identical). QA-002 VERIFIED. The change page GET is a 500 (new ETQAN-QA-012, pre-existing). |
| A2-01 | FAIL | PASS | REAL | qa002-live.txt | As TC-133. |
| A2-02 | FAIL | PASS | REAL | qa006-live.txt | As TC-114. |
| A2-07 | FAIL | PASS (prevented) | REAL | qa003-live-negative.txt | A bad timezone can no longer be created; `scan_notifications` itself still fails platform-wide if such data exists (residual, owner note in QA-003). |
| A2-09 (new) | - | FAIL | REAL | qa012-view-only-change-500.txt | View-only staff opening an academy change page → 500 KeyError (ETQAN-QA-012, P3). |

**Gate:** F01 stays **not passed** (RETESTING): ETQAN-QA-004, 005, 007, 008, 009, 010, 011, 012 are open.

## Gate run (Agent 2, 2026-10-18)

Environment: same stack and code (backend adff9c9 + Agent 3 fix, dashboard 5ed775d + fix; F01 diffs
byte-identical to `retest-1/diff-*.txt`). Evidence under `qa/evidence/F01/gate/`. Host load was high
(other desktop apps), so pytest ran slower than in retest 1.

- Scoped pytest: `etqan/tenants` 189 passed, `etqan/identity` 851 passed, `etqan/platform` 226 passed,
  all exit 0 (`gate/pytest-{tenants,identity,platform}.txt`).
- The never-executed FAKE cases ran as an out-of-repo pytest (`gate/test_f01_gate.py.txt`, run from
  the container's `/tmp`, then removed; nothing added to the repo): 11 passed
  (`gate/pytest-gate-tc058-060-088.txt`).
- Playwright `--workers=1` (`gate/playwright.txt`, `gate/pw/`): f01-login-csrf + tenant-login +
  b9-sign-in 9/9; f01-console TC-064/071/072/074/074b/073/133/134/135, then TC-064 again so qa-tmp-1
  ends suspended; f01-features-admin TC-125/125b/126/076/080/055/025; f01-dashboard
  TC-051/128/129-130/143/100/141. All passed except TC-133b, the cycle-1 test that drives the bug:
  it times out because a view-only staff member is no longer offered an action checkbox, which is the
  QA-002 fix holding (qa-tmp-1 unchanged). TC-100 and TC-141 only record what they see; their output
  confirms that QA-008 and QA-011 are still open.

| Case | Before | Gate | Tag | Evidence | Notes |
|---|---|---|---|---|---|
| TC-058 | BLOCKED | PASS | FAKE | pytest-gate-tc058-060-088.txt | A failure at each of the 6 steps (Domain create, ensure_settings, ensure_site_defaults, create_academy_admin, ensure_preset_tags, ensure_supervisor_preset) leaves no schema, no Academy or Domain row and no mail, and the subdomain is free again. TC-059 is the REAL counterpart (passed in cycle 1). |
| TC-060 | BLOCKED | PASS | FAKE | pytest-gate-tc058-060-088.txt | A failure inside the admin `save_model` gives HTTP 500 (unhandled; this records the current behaviour) and nothing half-created: no schema, no rows, no mail. |
| TC-088 | BLOCKED | BLOCKED (live) | FAKE logic + BLOCKED | pytest-gate-tc058-060-088.txt | `check_domain_dns`: a subset of the edge IPs passes; a superset with a foreign IP, no address, or an unresolvable edge are all refused. The live DNS success path stays BLOCKED (no edge resolver locally). |
| TC-133b | FAIL (bug) | n/a | REAL | playwright.txt | Obsolete after the QA-002 fix: no action checkbox is offered, so the UI path doesn't exist. TC-133 is the case of record and passes. |
| TC-100 | FAIL | FAIL (P3) | REAL | pw/tc100-unknown-host-spa.json | Host resolution passes (API 404, "Site not found"). The SPA still fails silently after Sign in: ETQAN-QA-008, P3. |
| TC-141 | FAIL | FAIL (P3) | REAL | pw/tc141-ar-reset.json | RTL, focus order and role=alert pass; the raw English zod message is still shown: ETQAN-QA-011, P3. |
| A2-09 | FAIL | FAIL (P3) | REAL | open-bugs-recheck.txt | ETQAN-QA-012 still reproduces: ops-view gets 500, ops gets 200. |

**Final counts (123 spec cases):** executed 122 + 1 live-BLOCKED with FAKE logic cover; PASS 117,
FAIL 5 (TC-062 QA-005, TC-084 QA-004, TC-100 QA-008, TC-138 QA-007, TC-141 QA-011, all P3),
BLOCKED 1 (TC-088 live). Tags: REAL 118, FAKE 4 (030, 032, 058, 060), SIMULATED 0, BLOCKED 1.
**Agent 2 checks (9):** PASS 6, FAIL 3 (A2-05 QA-009, A2-08 QA-010, A2-09 QA-012).
**Gate decision:** PASSED, with 8 known P3/P4 issues carried forward (see `execution-progress.md` § F01 gate decision).

---

## Gap review (Agent 1, 2026-10-18)

Coverage review after the F01 gate. This section approves nothing and does not reopen the gate:
Agent 2 decides whether and when these run. Sources: the Results, Retest 1 and Gate sections above,
`bug-register.md` (QA-001..012), and a read-only code review of `tenants/admin.py`,
`tenants/services.py`, the `create_academy`/`seed_*` commands, `academy/services.py`
(`get_settings`), `platform/validators.py`, `identity/api/views.py`, `identity/signin.py`,
`site/api/views.py`, `etqan_billing/admin.py`, `integrations/admin.py`, `identity/admin.py`, the
installed `django_celery_beat` 2.9.0 and allauth 65.20.0 admins, and `config/settings/production.py`.
Log: `qa/logs/F01/agent1.md`.

**What the executed cases left open:**
- **QA-002 (actions ignored permissions):** the fix and its tests cover the six tenants actions.
  Nobody checked the other public-schema admins that have actions, and no non-superuser staff member
  holding *some* permissions was tested live.
- **QA-003 (bad timezone or currency at creation):** only the add paths were fixed. The academy
  change form still writes `Academy.timezone/currency` unvalidated, and `get_settings` self-heals
  `AcademySettings` from that row. The command still skips the form-only checks (email, name).
- **QA-006 (login CSRF):** login was checked on `<sub>.etqan.localhost` only. Not checked: a custom
  domain or `www.` host, the CSRF-token rotation after sign-in, and the other anonymous POSTs.
- **Copy features:** the action replaces the target's stored switches; it does not merge them. No case
  checked `requires` pairs, a forged `copy_from`, or a target that already had stored keys.
- **State transitions and integrity:** no case checked what survives a suspend and reactivate, a
  stale change form, domain work on a suspended academy, or the defaults flag after its invoice is
  paid.

**Suspected defects, from reading the code** (not filed; for Agent 2 to confirm):

| ID | Hypothesis | Case | Severity if confirmed |
|---|---|---|---|
| S6 | The QA-002 pattern recurs elsewhere. None of these actions declares `permissions=`: `EtqanInvoiceAdmin` (issue, email again, mark paid, void), `PlatformAccountAdmin.test_accounts`, `TeacherProfileAdmin.send_password_set_email`, django_celery_beat's `PeriodicTask` enable/disable/toggle/run, and allauth's `EmailAddress.make_verified`. So a view-only staff member can mark an Etqan invoice paid or void it, which changes `may_suspend`, or run a platform-wide beat task for every academy. | TC-151 | P1 for invoices and beat, P3 for the rest |
| S7 | A stale academy change form silently reverts newer changes. The ModelForm saves `status` and `etqan_defaults_suspended` as the page showed them. Feature boxes are compared with the *current* row, not the one the staff member saw, so a box that differs is written again. Example: a suspended academy is reactivated by an unrelated plan-notes edit. | TC-152 | P2 |
| S8 | `AcademyChangeForm` accepts `Mars/Phobos` or `usd` for an existing academy, the path QA-003 did not fix. The bad value reaches `AcademySettings` whenever `get_settings` self-heals. | TC-155 | P3 (P2 if the self-heal path is reachable in the product) |
| S9 | The `create_academy` command doesn't validate the admin email or the name, which only the admin form checks. `--admin-email not-an-email` creates a whole academy whose first admin can never get the invite. A 201-character name crashes with a raw `DataError`. | TC-156 | P3 |

**Rules for these cases:**
- Use only `qa`, `qaother` and the `qa-tmp-*` throwaways.
- Never touch `demo`, `other`, `journey-*` or `khaled`. `khaled` is a non-QA academy found in
  `tenants_academy` on 2026-10-18.
- A suspended throwaway that a case reactivates must be suspended again at the end.
- Create new academies only where a case says so, because each one migrates a whole schema.
- Playwright `--workers=1`; one heavy job at a time.

### O. Gap review: regression around QA-002 (console permissions)

#### F01-TC-150: Partially privileged Etqan staff (gap review)
- **Pri:** P1. **Tag:** REAL. **Why:** QA-002's live checks used only a superuser, a view-only user
  and a no-permission user. The "has change, so actions are offered" branch has pytest cover only.
- **Setup:** three public staff accounts, created the way SETUP-2 creates its accounts. Record them in
  `environment.md`.
  - `ops-change@qa.etqan.test`: `view_academy`, `change_academy`, `view_domain`.
  - `ops-add@qa.etqan.test`: `view_academy`, `add_academy`.
  - `ops-domain@qa.etqan.test`: `view_academy`, `view_domain`, `change_domain`.
- **Expected:**

  | Account | Academy actions | Academy change page | Add academy | Domain actions |
  |---|---|---|---|---|
  | ops-change | all 3 offered; Suspend/Reactivate work on qa-tmp-1 | 200, saves (no QA-012 500) | 403 | none offered; a forged POST changes nothing |
  | ops-add | none offered | read-only or 403 (record, cross-check QA-012) | 200; record what happens after Save (redirect without change permission) | none |
  | ops-domain | none offered; a forged suspend changes nothing | read-only or 403 | 403 | all 3 offered, and they run on qa-tmp-1's domains |

- **Assertions:**
  - The md5 of every academy row other than qa-tmp-1 is the same before and after.
  - Each change made by a permitted action is the only change in the DB.
- **Do not** let ops-add actually create an academy unless Agent 2 accepts the schema cost. If it
  does, use the subdomain `qa-tmp-add` and suspend it afterwards.
- **Cleanup:** qa-tmp-1 ends suspended.

#### F01-TC-151: View-only staff on the other public admins with actions (S6) (gap review)
- **Pri:** P1. **Tag:** REAL.
- **Setup:** create `ops-view-all@qa.etqan.test`, `is_staff`, holding every `view_*` permission
  of the public-schema apps (etqan_billing, integrations, identity, django_celery_beat, account,
  tenants) and no other permission.
- **Steps:**
  1. Open each changelist and record the actions offered:
     - Etqan invoices;
     - Platform accounts;
     - Teacher profiles;
     - Periodic tasks;
     - Email addresses.
  2. Forge the action POST (`action=<name>&_selected_action=<id>`) for the actions that can't harm
     anything outside QA:
     - `mark_paid` and `void_invoices` on a QA fixture `EtqanInvoice` for qa-tmp-1 (created by ops@,
       as in TC-077, then deleted);
     - `issue_invoices` on a QA draft for qa-tmp-1;
     - `make_verified` on an `EmailAddress` row of an `ops-*` account.
- **Expected:**
  - No state-changing action is offered. Per QA-002 and `feature-toggles.md` §1, view-only means
    view.
  - Every forged POST changes nothing: the invoice status, `paid_on`, `voided_at` and
    `EmailAddress.verified` are all unchanged.
  - No email reaches Mailpit.
- **Never** execute a `PeriodicTask` "Run selected tasks", Enable or Toggle, even forged. The tasks
  loop over every academy, demo, other and khaled included. Record only whether they are offered,
  and check whether a forged POST is accepted by reading `ModelAdmin.get_actions()` in a Django
  shell with a `RequestFactory` request for this user. Tag that part REAL (static).
- **Cleanup:** delete the fixture invoices; restore `verified` if it changed.

#### F01-TC-152: A stale academy change form doesn't overwrite newer changes (S7) (gap review)
- **Pri:** P2. **Tag:** REAL (browser, qa-tmp-1).
- **Steps:**
  1. As ops@, reactivate qa-tmp-1 and open its change page in tab A.
  2. In tab B (or with the command), change three things:
     - suspend qa-tmp-1 with the action;
     - run `set_features qa-tmp-1 --off families`;
     - if a fixture invoice allows it (TC-077), turn on `etqan_defaults_suspended`.
  3. In tab A, change only `plan_notes` and Save.
- **Expected:** only `plan_notes` changes. `status` stays `suspended`, `families` stays off, and the
  defaults flag stays on. Failing that, the save is refused as stale.
- **Assertions:**
  - The DB row before and after.
  - The `django_admin_log` change message lists only what tab A changed.
- **Cleanup:**
  - restore families to qa's SETUP-6 state;
  - lift the defaults flag and delete the fixture invoice;
  - qa-tmp-1 ends suspended.

#### F01-TC-153: "Copy features from" with `requires` pairs, replace semantics and forged sources (gap review)
- **Pri:** P2. **Tag:** REAL.
- **Preconditions:**
  - Source: run `set_features qaother --on online_payments --off invoices`. qaother is a QA academy
    that is not otherwise in use; restore it afterwards.
  - Target: run `set_features qa-tmp-1 --off families`, so that the target has a stored key the
    source lacks.
- **Steps:**
  1. Copy features from qaother to qa-tmp-1.
  2. Copy again with `copy_from` forged to `1` (the public row), then to a non-existent id. Expect
     "Choose the academy to copy the features from." and no change.
  3. Copy with both qaother and qa-tmp-1 selected and qaother as the source. Expect qaother to be
     skipped and the count to be 1.
  4. Copy from a suspended academy (qa-tmp-r1ok). Record whether that is allowed.
- **Expected:**
  - Target `features` JSON == source JSON exactly. The target's stored `families: false` is gone,
    so families is on again by default. Record this, because copying is a replace, not a merge.
  - On the target (reactivated briefly to read the API): `online_payments` has `on=false`,
    `held_by=["invoices"]`; `me.features` is identical to qaother's; online-payment routes return
    404; the admin help text says "Held off: needs Invoices and receipts."
  - One `django_admin_log` row per changed target.
- **Cleanup:** restore qaother (`--on invoices --off online_payments`, then compare with the JSON
  you recorded first); qa-tmp-1 ends suspended.

#### F01-TC-154: A feature key that is no longer in the registry doesn't break anything (gap review)
- **Pri:** P3. **Tag:** REAL (qa-tmp-1).
- **Steps:** use the ORM to add `"retired_feature": true` to qa-tmp-1's `features`. Then:
  - open the change page and save it with one box changed;
  - run `set_features qa-tmp-1 --on internal_chat`;
  - copy qa-tmp-1 to nowhere (self → 0);
  - reactivate qa-tmp-1 briefly and call `GET academy/features/` and `me`.
- **Expected:**
  - No 500 anywhere.
  - The API and `me` list only registry codes.
  - Record whether the unknown key is kept or dropped on save.
- **Cleanup:** remove the key; qa-tmp-1 ends suspended.

### P. Gap review: regression around QA-003 (timezone and currency)

#### F01-TC-155: The academy change form's timezone and currency for an existing academy (S8) (gap review)
- **Pri:** P3. **Tag:** REAL for the form, FAKE for the self-heal path.
- **Steps:**
  1. On qa-tmp-1's change page as ops@, set timezone `Mars/Phobos` and currency `usd`, then Save.
  2. Self-heal path, as a pytest (Agent 3, test-only): delete the `AcademySettings` row in a test
     academy whose `Academy.timezone` is bad, then call `get_settings()`.
- **Expected (QA-003's contract):**
  - The form refuses the values with "Unknown timezone." and "Use a three-letter currency code,
    like EGP.".
  - If the product keeps these fields seed-only (TC-055), the form must still not store a value
    that a later self-heal would copy into `AcademySettings`.
- **Assertions:**
  - `academy_qa_tmp_1.academy_academysettings` is unchanged.
  - Record the `Academy` row.
- **Cleanup:** put back the original timezone and currency.

#### F01-TC-156: `create_academy` command input parity beyond the subdomain (S9) (gap review)
- **Pri:** P3. **Tag:** REAL.
- **Probes:** subdomain `qa-tmp-cmd` for all of them. Run them one at a time, and stop at the first
  probe that creates anything.
  - `--admin-email not-an-email`
  - `--name ""`
  - `--name` with 201 characters
  - `--timezone " Africa/Cairo"` (with the leading space)
  - `--currency " egp "`
- **Expected:**
  - Invalid input gives a clean `CommandError`, exit 1, no traceback.
  - Nothing is created: no row, domain, schema or invite.
  - `" egp "` is normalised to `EGP`. Probe that one with a deliberately bad timezone so that
    nothing is created, or use `clean_currency` in a shell.
- **If a probe creates `qa-tmp-cmd`:** that is S9 confirmed. Record the row, suspend it, and run no
  further creating probes.

#### F01-TC-157: Unusual but valid timezones and currencies (gap review)
- **Pri:** P3. **Tag:** REAL (service and validator level in a shell; no academy is created).
- **Data:** check `clean_timezone` and `clean_currency` with these values:
  - timezones `Etc/GMT-3`, `America/Argentina/Buenos_Aires`, `US/Eastern` (a legacy link), `UTC`,
    `GMT`;
  - currencies `XXX` and `ZZZ` (not real ISO 4217 codes).
- **Expected:**
  - Record which are accepted.
  - If a non-ISO currency passes, raise a product question in `coverage-gaps.md`: invoices would be
    issued in `ZZZ`.

### Q. Gap review: regression around QA-006 (login CSRF) and the other anonymous POSTs

#### F01-TC-158: Sign-in on an active custom domain and on its `www.` host after the CSRF fix (gap review)
- **Pri:** P1. **Tag:** REAL.
- **Why:** `CsrfChecked` compares Origin with the request host. A custom domain is a different
  host from the subdomain, and the browser fetches the token from whichever host it is on.
- **Steps:**
  1. Reactivate qa-tmp-1.
  2. Activate `qa-academy.test` and `www.qa-academy.test` through the service, as TC-089/090 did,
     labelled as bypassing DNS.
  3. Use `curl --resolve qa-academy.test:80:127.0.0.1` (through Caddy):
     - `GET /api/v1/identity/csrf/`, then `POST login/` with the token and
       `Origin: http://qa-academy.test`;
     - the same with `Origin: http://qa-tmp-1.etqan.localhost`;
     - the same with `Origin: http://evil.example`;
     - the token from the subdomain replayed on the custom domain.
- **Expected:**
  - The same-origin login gives 200 and `me` returns 200.
  - Every cross-origin variant and the replayed token give 403.
  - The same holds on `www.qa-academy.test`.
- **Cleanup:**
  - disable both custom domains, so the subdomain is primary again;
  - restore qa-tmp-1's admin password if it changed;
  - suspend qa-tmp-1.
- **Production HTTPS** (Origin `https://…` behind Caddy's `X-Forwarded-Proto`) can't be tested
  here; see `coverage-gaps.md`.

#### F01-TC-159: The CSRF token after sign-in, sign-out and a second sign-in in the same SPA page (gap review)
- **Pri:** P2. **Tag:** REAL (Playwright `--workers=1`, qa).
- **Steps:**
  1. Sign in as the qa admin and **without reloading** create a tag (`POST people/tags/`).
  2. Sign out, then sign in as `qa-supervisor@` in the same page and make an allowed write.
  3. Two tabs: tab B signs in while tab A is on the login page; then tab A signs in.
- **Expected:**
  - Every step succeeds. No "CSRF Failed" appears, although Django rotates the token at login.
  - The login POST and the first write each carry `X-CSRFToken`, matching the current
    `csrftoken` cookie.
- **Cleanup:** delete the QA tags through the ORM.

#### F01-TC-160: CSRF and session behaviour of every other anonymous POST (gap review)
- **Pri:** P2. **Tag:** REAL (qa, with SETUP-6's features on).
- **Endpoints:**
  - `identity/password/reset/` and `password/reset/confirm/`;
  - `password/code/`, `password/code/verify/` and `password/code/reset/`;
  - `identity/resend-verification` and `identity/verify-email/`;
  - `registration/` register;
  - `site/inquiries/` and the article and video beacons;
  - consultations `book/` and the `manage/<token>/pay|reschedule|review`;
  - the gateways public-link checkout.

  Use the paths from `config/api_router.py`.
- **Variants:**
  - (a) Anonymous, same-origin, no token.
  - (b) A cross-site form-encoded POST with `Origin: http://evil.example`.
  - (c) The same host while signed in to `/app/` (the session cookie is sent), with no token.
  - (d) On suspended qa-tmp-1 with no token: expect 403 `tenant.suspended`, never "CSRF Failed".
    The dashboard's suspended message (TC-071) depends on that code.
- **Expected:**
  - No variant sets a `sessionid` cookie: none of these may create a session (no login CSRF).
  - Inquiry and beacons accept (a) and (c), by design (`authentication_classes = []`, JSON-only
    beacons). The beacons refuse (b) with 415.
  - For default-authentication views, (c) is refused by DRF's session CSRF. Check that the real
    clients still work while signed in on the same host: the marketing `ContactForm` sends no
    token, so it relies on the inquiry view's design; the dashboard register and booking pages must
    send `X-CSRFToken`. A real client flow refused with 403 is a defect.
  - Record (b) for each endpoint. The policy belongs to F02; QA-006's note already lists reset,
    resend and registration as still CSRF-exempt.
- **Data:** only `@qa.etqan.test` addresses; reset and code emails are caught by Mailpit. Delete
  the QA inquiries, registrations and bookings through the ORM afterwards.

### R. Gap review: tenant isolation

#### F01-TC-161: Public anonymous writes land only in the host's academy (gap review)
- **Pri:** P1. **Tag:** REAL.
- **Steps:** `POST /api/v1/site/inquiries/` (JSON, the ContactForm body, a QA email) to these
  hosts:
  - `qa.etqan.localhost`;
  - `qaother.etqan.localhost`;
  - `etqan.localhost` (the base domain);
  - suspended `qa-tmp-1.etqan.localhost`;
  - an unknown subdomain.

  Then `GET` the inquiries list as each academy's admin.
- **Expected:**
  - qa and qaother: 201, and the row sits only in that academy's `academy_<x>.academy_site_inquiry`,
    with `source_host` equal to the host.
  - The base domain and the unknown host: 404.
  - The suspended academy: 403 `tenant.suspended` and no row.
  - Neither admin sees the other's inquiry.
- **Cleanup:** delete the QA inquiries through the ORM.

#### F01-TC-162: Base-domain-only routes aren't served on academy hosts (gap review)
- **Pri:** P2. **Tag:** REAL.
- **Steps:** on `qa.etqan.localhost`, send `POST /api/v1/webhooks/zoom/` and
  `POST /api/v1/webhooks/stripe-connect/` with an empty JSON body. On `localhost:8000` (dev only),
  send `GET /internal/tls-allowed?domain=qa.etqan.localhost` with `Host: qa.etqan.localhost`.
- **Expected:**
  - 404 on the academy host: the webhooks live only in `urls_public.py`.
  - The TLS ask is not served under the academy URLconf.
  - Nothing is written to `integrations_*` webhook tables.

#### F01-TC-163: Host-header edge cases in tenant resolution (gap review)
- **Pri:** P2. **Tag:** REAL (curl through Caddy :80 and direct to :8000).
- **Data:**
  - `Host: qa.etqan.localhost.` (a trailing dot);
  - `Host: qa.etqan.localhost:443`;
  - two `Host` headers (qa and qaother);
  - an absolute-form request line `GET http://qa.etqan.localhost/api/v1/identity/me/` sent with
    `Host: qaother.etqan.localhost` and qaother's session cookie;
  - `Host: qa.etqan.localhost` with qaother's session cookie.
- **Expected:**
  - Never a 200 carrying data from an academy the cookie doesn't belong to.
  - The trailing dot either resolves to qa or gives 404/400; record which.
  - Duplicate Host headers give 400.
- **Note:** TC-090 and TC-103 cover case, port and `X-Forwarded-Host` only.

#### F01-TC-164: Public media of one academy fetched through another academy's host (gap review)
- **Pri:** P3. **Tag:** REAL.
- **Steps:** as the qa admin, upload a site logo (dashboard Website or Branding). Note the path
  `/media/tenants/academy_qa/site/...`, then GET it on these hosts:
  - `qaother.etqan.localhost`;
  - `etqan.localhost`;
  - a suspended academy's host.

  Also try `/media/../private_media/` traversal.
- **Expected:**
  - Record the cross-host behaviour. These are public assets: Django's dev `static()` serves them,
    and production uses S3.
  - Private media is never reachable under `/media/`: traversal gives 404.
- **Cleanup:** remove the logo.

### S. Gap review: state transitions and integrity

#### F01-TC-165: Suspend and reactivate preserve everything, and tokens survive (gap review)
- **Pri:** P2. **Tag:** REAL (qa-tmp-1).
- **Preconditions:** qa-tmp-1 is reactivated with:
  - an active custom domain as primary (as in TC-158);
  - stored features;
  - a fresh reset token for its admin (from `password/reset/`, caught in Mailpit).
- **Steps:**
  1. Snapshot the academy row, its domains and `academy_settings`.
  2. Suspend qa-tmp-1, then:
     - `POST password/reset/confirm/` with the token, which should get 403 `tenant.suspended`;
     - call the API on the custom domain, which should get 403 `tenant.suspended`, not 404;
     - open its `/`, which should be marketing's 503.
  3. Suspend it again; record the message count.
  4. Reactivate qa-tmp-1 and confirm the same token, which should get 200.
  5. Reactivate it again; record the count.
- **Expected:**
  - The token is not consumed by the refused confirm.
  - Features, `etqan_defaults_suspended`, `plan_*` and the domains (status, primary, `verified_at`)
    are identical before and after.
- **Cleanup:** disable the custom domain; qa-tmp-1 ends suspended.

#### F01-TC-166: The defaults flag after its invoice is paid or voided (gap review)
- **Pri:** P2. **Tag:** REAL (qa-tmp-1).
- **Steps:**
  1. Create a fixture `EtqanInvoice` issued 31 days ago, unpaid. Turn on `etqan_defaults_suspended`
     (allowed).
  2. Mark the invoice paid with the admin action as ops@.
  3. Reopen the change page.
  4. Lift the flag, then try to turn it on again.
  5. Repeat steps 1–4 with Void instead of Mark paid.
- **Expected:**
  - The flag stays on after payment: "never automatic" (SUSPEND_HELP).
  - The help text now says "No unpaid Etqan invoice."
  - Lifting is allowed. Turning it on again is refused.
  - The integrations email status goes from `suspended` back to the platform default after the
    flag is lifted.
- **Cleanup:** delete the fixture invoices; flag off.

#### F01-TC-167: Domain operations on a suspended academy (gap review)
- **Pri:** P3. **Tag:** REAL (qa-tmp-1, suspended).
- **Steps:** while qa-tmp-1 is suspended, as ops@:
  - add `qa-tmp1-susp.test`;
  - run "Check DNS" on it (fails locally);
  - activate it through the service;
  - Make primary;
  - Disable.

  Then reactivate qa-tmp-1 and request a password reset.
- **Expected:**
  - Record whether each step is allowed while suspended.
  - The host of a suspended academy's active domain gives 403 `tenant.suspended`, and the TLS ask
    answers as in A2-04.
  - After reactivation, the reset link uses the current primary.
- **Cleanup:** disable the domain, so the subdomain is primary again; qa-tmp-1 ends suspended.

### T. Gap review: failure modes

#### F01-TC-168: Recovering a lost or expired first-admin invite (gap review)
- **Pri:** P2. **Tag:** REAL for the recovery, FAKE for the expiry.
- **Preconditions:** a throwaway academy whose admin never accepted the invite: `qa-tmp-r1ok`, from
  retest 1, is suspended; reactivate it. Check that its admin password is still unusable (`!`).
- **Steps:**
  1. On `qa-tmp-r1ok.etqan.localhost/app/`, click "Forgot password" for its admin email.
  2. Use the emailed link to set a password, then sign in.
  3. Retry the original invite link from Mailpit.
  4. Expiry, as a pytest (Agent 3, test-only) with time frozen past `PASSWORD_RESET_TIMEOUT`: the
     invite link is refused, and "Forgot password" still recovers the account.
- **Expected:**
  - The first admin's address is primary and verified, so step 1 sends a **reset** email, not an
    invite (`request_password_reset`). Its link is on the academy's host.
  - Step 2 succeeds.
  - Step 3 gives 400 "Invalid or expired reset link."
  - Etqan staff have no console action to resend a first admin's invite. Record this:
    "Forgot password" is the only recovery path.
- **Cleanup:** suspend qa-tmp-r1ok again. Record its admin password in `environment.md`.

#### F01-TC-169: The Add-academy POST is abandoned by the browser mid-provision (gap review)
- **Pri:** P3. **Tag:** REAL (Playwright).
- **Steps:**
  1. Submit the Add form for subdomain `qa-tmp-abort`, valid data, an `@qa.etqan.test` admin.
  2. About 3 s in (provisioning takes about 15 s), close the page or abort the request.
  3. Wait 30 s, then submit the same form again.
- **Expected:**
  - The server finishes (runserver keeps going) or rolls back. Either way, exactly one academy, one
    domain, one schema and at most one invite.
  - The resubmit shows "This subdomain is already taken."
  - Record this UX: staff get no success message for the first submit.
- **Cleanup:** suspend `qa-tmp-abort` if it was created.

#### F01-TC-170: The invite email fails after the commit (gap review)
- **Pri:** P3. **Tag:** FAKE (pytest, Agent 3, test-only).
- **Steps:** `create_academy` with the email send raising, through `queue_email`, the
  backend or the provider.
- **Expected:**
  - The academy, domain, settings and admin are kept: the invite is sent after the commit (TC-014).
  - The failure is logged.
  - "Forgot password" (TC-168) recovers the account.
- **The REAL SMTP outage isn't run.** It would mean stopping Mailpit in the only stack; see
  `coverage-gaps.md`.

#### F01-TC-171: The QA-003 fix doesn't break the seed commands (gap review)
- **Pri:** P3. **Tag:** REAL (static) plus FAKE.
- **Steps:** read `seed_dev` and `seed_staging`. Both call `create_academy` with the default
  `UTC`/`USD`, so the new validation passes. Cite or add a pytest that runs `seed_staging`'s
  create path against the validated service, with no schema left behind (test DB).
- **Expected:** no seed path passes a value that the validators refuse.
- **Never** run `seed_dev` or `seed_staging` against the live DB for this case: it would top up
  demo and other.

**Gap-review counts:** 22 new cases (TC-150 to TC-171):
- **P1 (4):** 150, 151, 158, 161.
- **P2 (9):** 152, 153, 159, 160, 162, 163, 165, 166, 168.
- **P3 (9):** 154, 155, 156, 157, 164, 167, 169, 170, 171.

**Expected tags:** mostly REAL. FAKE: 155 (self-heal part), 168 (expiry part), 170, 171. Parts
that are static REAL: 151 (`PeriodicTask`), 171.

**Suggested order:** the P1 cases first (150, 151, 158, 161), because they test the three P1/P2 fixes
from new angles. Then 152 and 153, which touch the same qa-tmp-1 row, and then the rest.

## Gap-review results (Agent 2, run 2026-10-18; TC-159/169 run at gate 2)
Written at gate 2 from the gap-run log (`logs/F01/agent2.md` 04:44-05:09Z) and the evidence. Until now only
summary counts were recorded, although `coverage-gaps.md` pointed here. Evidence is in `evidence/F01/gap/`
unless a row says otherwise. "Now" is the status after fix cycle 2 and retest 2.

| Case | Pri | First run | Now | Tag | Evidence / note |
|---|---|---|---|---|---|
| TC-150 partially privileged staff | P1 | PASS | PASS (re-checked in retest 2) | REAL | `tc150-actions.txt`; the change page 500 for ops-add/ops-domain is QA-012 (P3) |
| TC-151 view-only staff, other console admins | P1 | FAIL (QA-013) | **PASS** (QA-013 VERIFIED) | REAL | `tc151-*.txt`; `retest-2/tc151-*`; gate-2 Playwright R2-TC-151 |
| TC-152 stale change page | P2 | FAIL (QA-014) | **PASS** (QA-014 VERIFIED) | REAL | `tc152-stale-form.txt`; `retest-2/tc152-*`; `gate-2/r2-tc152-rerun.txt` |
| TC-153 copy features (requires, replace, forged) | P2 | PASS | PASS | REAL | `tc153-copy.txt`; copy = replace (owner question) |
| TC-154 retired feature key | P3 | PASS | PASS | REAL | `tc154-retired-key.txt` |
| TC-155 change-form timezone/currency | P3 | FAIL (QA-015) | FAIL, QA-015 OPEN P3 | REAL (+FAKE self-heal probe) | `tc155-change-form-tz.txt` |
| TC-156 `create_academy` input parity | P3 | FAIL (QA-016) | FAIL, QA-016 OPEN P3 | REAL | `tc156-command-parity.txt` |
| TC-157 unusual valid timezones/currencies | P3 | PASS | PASS (`XXX`/`ZZZ` accepted: owner question) | REAL | `tc157-validators.txt` |
| TC-158 sign-in on custom domain + www. | P1 | PASS | PASS | REAL | `tc158-custom-domain-csrf.txt` |
| TC-159 CSRF token across sign-in/out in one SPA page | P2 | not run (wrongly counted) | PASS (gate 2) | REAL | `gate-2/playwright-tc159.txt`, `gate-2/pw/tc159-csrf-rotation.json` |
| TC-160 other anonymous POSTs | P2 | PASS | PASS (CSRF-exempt form POSTs recorded for F02) | REAL | `tc160-anonymous-posts.txt` |
| TC-161 public writes land in the host's academy | P1 | PASS | PASS | REAL | `tc161-inquiry-isolation.txt` |
| TC-162 base-only routes on academy hosts | P2 | PASS | PASS | REAL | `tc162-public-routes.txt` |
| TC-163 Host-header edge cases | P2 | PASS | PASS | REAL | `tc163-host-edge.txt` |
| TC-164 media across academy hosts | P3 | PASS | PASS | REAL | `tc164-media.txt` |
| TC-165 suspend/reactivate round trip | P2 | PASS | PASS (misleading "1 academies" count recorded) | REAL | `tc165-suspend-roundtrip.txt` |
| TC-166 defaults flag after paid/void invoice | P2 | PASS | PASS | REAL | `tc166-defaults-flag.txt` |
| TC-167 domain operations while suspended | P3 | PASS | PASS | REAL | `tc167-domains-suspended.txt` |
| TC-168 lost/expired first-admin invite | P2 | PASS | PASS | REAL (+FAKE expiry) | `tc168-invite-recovery.txt` |
| TC-169 Add POST abandoned mid-provision | P3 | not run (wrongly counted) | PASS (gate 2; no success message is shown, UX recorded) | REAL | `gate-2/tc169-abort.txt`, `gate-2/playwright-tc169.txt` |
| TC-170 invite email fails after commit | P3 | PASS | PASS | REAL (SMTP 553 refusal seen in TC-156) | `tc156-command-parity.txt`; FAKE pytest is a test-only proposal |
| TC-171 QA-003 fix vs seed commands | P3 | PASS | PASS | REAL static + FAKE (cited pytest) | `tc171-seed-static.txt` |

Totals now: 22 executed, PASS 20, FAIL 2 (TC-155, TC-156: both P3, open, carried forward). Every gap P1 (150, 151,
158, 161) passes. Every gap P2 passes.

## Retest 2 (Agent 2, 2026-10-18, fix cycle 2: ETQAN-QA-013, ETQAN-QA-014)
Evidence: `evidence/F01/retest-2/`. Both fixes are VERIFIED.

| Case | Result | Tag | Evidence |
|---|---|---|---|
| TC-151 view-only staff and the other console admins (QA-013 repro as filed) | **PASS** (was FAIL) | REAL (live forged POSTs, UI, DB, Mailpit) | `tc151-forged-view-all.txt`, `tc151-positive-superuser.txt`, `tc151-get-actions-static.txt`, `pw/r2-tc151-*` |
| TC-150 partial-permission staff (re-check) | PASS | REAL static (`get_actions`) | `tc151-get-actions-static.txt` |
| TC-133 view-only staff, tenants actions (re-check) | PASS (forged suspend/reactivate refused) | REAL | `tc151-forged-view-all.txt` |
| TC-152 stale change page (QA-014 repro as filed) | **PASS** (was FAIL) | REAL (curl replaying the rendered form; Playwright two tabs) | `tc152-stale-form.txt`, `tc152-variants.txt`, `tc152-forged-initials.txt`, `pw/r2-tc152-*` |
| Regression tests without the fix | 12 fail / 23 pass (in-container copy) | FAKE (test DB) | `regression-fails-without-fix.txt` |
| Scoped pytest with the fix | regression 61, etqan_billing 137, integrations 391, platform 226, identity 851, tenants 197: all pass | FAKE (test DB) | `pytest-*.txt` |
| ruff / format / lint-imports | clean; 54 kept, 0 broken | REAL static | `ruff.txt`, `lint-imports.txt` |

Notes: the R2-TC-152 Playwright run failed once on a harness race (message read before the page loaded);
the wait was fixed and the test re-run with `--retries=0`: pass. QA-012 still reproduces (P3, OPEN).
State after: every fixture removed, academies md5 identical to the start (`cleanup.txt`).
