# Bug register

Format: one `## ETQAN-QA-NNN` section per bug, with these fields:
- Title, Feature, Severity (P0–P4), Priority, Environment, Provider tag
- Preconditions, Reproduction steps, Expected, Actual, Evidence
- Root cause, Fix (files), Regression tests
- Verification status (OPEN · FIXING · FIXED-UNVERIFIED · VERIFIED · ESCALATED · WONT_FIX-approved),
  Verified by (Agent 2 run id and evidence path)

Next ID: **ETQAN-QA-044**

---

## ETQAN-QA-001: `just rebuild` / `just setup` fail on macOS (host GID 20 is already taken in the image)
- **Feature:** F00 dev environment
- **Severity:** P2 (blocks every Mac developer from building the stack). **Priority:** high
- **Environment:** macOS (host user `staff`, GID 20), Docker Desktop, `docker-compose.local.yml`.
  **Tag:** REAL
- **Repro:** run `just rebuild` in the meta repo on a Mac.
- **Expected:** every image builds.
- **Actual:**
  - The dashboard `dev` stage fails: `addgroup -g 20 app` → `addgroup: gid '20' in use`. In Alpine,
    GID 20 is `dialout`.
  - `marketing/Dockerfile:49` has the same pattern.
  - `backend/Dockerfile:23` (`groupadd -g ${GID}`) hits the same collision on Debian, where GID 20
    is `dialout`.
- **Evidence:** the conductor's setup log in `qa/environment.md`. Build output: `#33 0.473 addgroup:
  gid '20' in use`. Reproduced by F01 Agent 2 (2026-10-17, before any fix):
  `evidence/F01/tc001-003-qa001-repro.txt` (backend `docker build --target dev --build-arg GID=20`:
  "groupadd: GID '20' already exists", exit 1; node:22-alpine running the dashboard/marketing
  dev-stage line: "addgroup: gid '20' in use", group 20 = dialout). Running stack untouched
  (`evidence/F01/tc007-diff.txt`).
- **Workaround in use:** build with `HOST_GID=1000` (scratchpad `dc.sh`).
- **Root cause (Agent 3, F01 fix attempt 1):** the dev stages create the app group with a fixed
  `groupadd -g ${GID} app` (backend, Debian) / `addgroup -g ${GID} app` (dashboard, marketing,
  Alpine). `just` passes `HOST_GID=$(id -g)`, which is 20 (`staff`) on macOS, and GID 20 already
  exists in both base images as `dialout`, so the command fails and the build stops.
- **Fix (files):** `backend/Dockerfile`, `dashboard/Dockerfile`, `marketing/Dockerfile` (dev stage
  only). If a group with the host GID already exists, the `app` user joins it; otherwise the `app`
  group is created as before. Ownership (`chown`, backend `COPY --chown`) uses the numeric
  `UID:GID`, so it no longer depends on the group's name. Production stages are unchanged.
  `qa/environment.md`'s `HOST_GID=1000` workaround (dc.sh) can be dropped once this is verified;
  the running stack was not rebuilt.
- **Regression tests:** no automated Docker build test exists in the repos (CI builds on Linux,
  where GID 1000 is free). Verified by building the dev targets under separate tags, without
  touching the running containers: `etqan-qa001/{backend,dashboard,marketing}:gid20` with
  `--build-arg UID=501 --build-arg GID=20` all exit 0; the user is `uid=501(app) gid=20(dialout)`
  and `/app` (and `node_modules`) are owned `501:20` (`evidence/F01/fix-cycle-1/qa001-backend-build-gid20.txt`,
  `evidence/F01/fix-cycle-1/qa001-dashboard-build-gid20.txt`, `evidence/F01/fix-cycle-1/qa001-marketing-build-gid20.txt`). The Linux default
  still gets its own `app` group (`evidence/F01/fix-cycle-1/qa001-backend-build-gid1000.txt`). The Alpine line checked for
  501/20, 1000/1000, 1001/1001 (`evidence/F01/fix-cycle-1/qa001-alpine-line-after.txt`). Before:
  `evidence/F01/fix-cycle-1/qa001-repro-before.txt`. Stack untouched: `evidence/F01/fix-cycle-1/qa001-docker-ps-before.txt` / `-after.txt`.
  Agent 2 can repeat with: `docker build --target dev --build-arg UID=$(id -u) --build-arg GID=20
  -t etqan-qa001/backend:gid20 backend` (dashboard/marketing also need
  `--secret id=tokens_token,env=GH_TOKEN`). Remove the `etqan-qa001/*` images afterwards.
- **Verification status:** VERIFIED
- **Verified by:** Agent 2, F01 retest-1 (2026-10-17/18), REAL. Diff reviewed: dev stage only in all three Dockerfiles, production stages unchanged (`evidence/F01/retest-1/diff-{backend,dashboard,marketing}.txt`). Own builds under separate tags `etqan-qa001-r1/*`: backend, dashboard and marketing `--target dev` with UID=501 GID=20 all exit 0; user `uid=501(app) gid=20(dialout)`; `/app` (and `node_modules`) owned 501:20 and writable; `manage.py`/`pnpm` run as app (`evidence/F01/retest-1/qa001-build-*-gid20.txt`). 1000:1000 still creates its own `app` group, all three exit 0 (`qa001-build-*-gid1000.txt`). UID=1 fails clearly ("useradd: UID 1 is not unique"), acceptable for TC-005 (`qa001-build-backend-uid1.txt`). Running stack untouched: docker ps and `etqan_tutor-*` image IDs identical before/after (`qa001-tc007-diff.txt`). The `etqan-qa001-r1/*` and Agent 3 `etqan-qa001/*` images were removed (`qa001-images-after.txt`). The dc.sh `HOST_GID=1000` workaround may be dropped at the next planned rebuild (not done here: it would recreate the running containers).

---

## ETQAN-QA-002: A view-only Etqan staff member can suspend, reactivate and copy features to any academy (admin actions ignore permissions)
- **Feature:** F01 Tenancy (Etqan console access control). **Severity:** P1 (privilege escalation inside the
  staff console: a read-only account can take a customer academy offline or change its switches).
  **Priority:** high
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9, dashboard 5ed775d), macOS, Chromium via Playwright 1.62.1 (1 worker). **Tag:** REAL
- **Preconditions:** public-schema user `ops-view@qa.etqan.test`, `is_staff=True`, not superuser, with only
  `tenants.view_academy` and `tenants.view_domain`.
- **Reproduction steps:**
  1. Sign in at `http://etqan.localhost/admin/` as `ops-view@qa.etqan.test`.
  2. Academies changelist: the row checkboxes and the action list "Suspend selected academies",
     "Reactivate selected academies", "Copy features from another academy" are offered.
  3. Tick "QA Tmp One", choose "Copy features from" = Etqan QA Other, run "Copy features…"; then run
     "Suspend selected academies".
  4. Also: a POSTed changelist action `action=suspend_academies&_selected_action=5` (qa).
  5. Domains changelist: "Check DNS and activate" (and Make primary / Disable) also run.
- **Expected:** a view-only staff member cannot change anything: no state-changing actions offered, a
  forged action is refused (403 or "No action selected"). `docs/features/feature-toggles.md` §1 "Only
  Etqan staff change switches, in the platform admin"; spec TC-133 ("The actions (suspend, reactivate,
  copy) are not offered, or are refused"). The change view already refuses this user (403), so only
  the actions bypass it.
- **Actual:** "Copied the features of Etqan QA Other to 1 academies.", "Suspended 1 academies.",
  "Reactivated 1 academies." The forged POST suspended the kept QA academy `qa` (status → suspended,
  restored by Agent 2). The suspends leave no `django_admin_log` row (see ETQAN-QA-007). Domain
  `check_dns` runs for this user (it would activate a domain whose DNS is right).
- **Evidence:** `evidence/F01/pw/tc133-view-only.json` (forgedAction 200 "Suspended 1 academies."),
  `evidence/F01/pw/tc133b-view-only-actions.json`, `evidence/F01/pw/tc133b-view-only-suspended.png`,
  `evidence/F01/tc133-db.txt` (qa status active→suspended), `evidence/F01/tc133b-db.txt` (admin log
  rows by user 2), `evidence/F01/tc133c-view-only-domain-actions.txt`, Playwright
  `dashboard/e2e/qa/f01-console.spec.ts` "TC-133", "TC-133b".
- **Hint:** `tenants/admin.py` `@admin.action(...)` has no `permissions=["change"]` on
  `suspend_academies`, `reactivate_academies`, `copy_features`, `check_dns`, `make_primary_action`,
  `disable_action`. No test covers a non-superuser staff member.
- **Root cause (Agent 3, F01 fix attempt 1):** Django runs a ModelAdmin action for anyone who can
  open the changelist (view permission) unless the action declares the permission it needs. None of
  the six `@admin.action`s in `backend/etqan/tenants/admin.py` set `permissions=`, so a view-only
  staff member was offered them and a POSTed action ran. The change view was already protected by
  `has_change_permission`; only the actions bypassed it.
- **Fix (files):** `backend/etqan/tenants/admin.py`: `permissions=["change"]` on
  `suspend_academies`, `reactivate_academies`, `copy_features` (AcademyAdmin) and `check_dns`,
  `make_primary_action`, `disable_action` (DomainAdmin). Django then leaves them out of
  `get_actions()`, so they are not offered and a forged POST does nothing. Doc:
  `docs/features/tenancy.md` § Suspension.
- **Regression tests:** `backend/etqan/tenants/tests/test_admin_permissions.py` (8 tests: no
  actions offered to view-only staff on academies and domains; forged suspend, reactivate, copy
  features and all three domain actions change nothing; a non-superuser with `change_academy` /
  `change_domain` is still offered every action and can suspend). 6 of 8 fail on the unfixed
  admin (`evidence/F01/fix-cycle-1/qa002-regression-fails-before-fix.txt`), all pass with the fix. Live, REAL
  (`evidence/F01/fix-cycle-1/qa002-live-after.txt`): ops-view@ sees no actions; forged suspend/reactivate on qa-tmp-1
  and check_dns change nothing (qa-tmp-1 stays suspended, qa active); ops@ still has the actions.
  Before: `evidence/F01/fix-cycle-1/qa002-repro-before.txt`. Full `pytest etqan/tenants`: `evidence/F01/fix-cycle-1/pytest-tenants.txt`.
  Not fixed here: the missing history row for suspend/reactivate (ETQAN-QA-007).
- **Verification status:** VERIFIED
- **Verified by:** Agent 2, F01 retest-1, REAL. Filed steps rerun live (`evidence/F01/retest-1/qa002-live.txt`): `ops-view@` is offered 0 actions and 0 row checkboxes on Academies and Domains; 7 forged action POSTs (suspend on qaother and qa (filed step 4), reactivate and copy features on qa-tmp-1, check_dns, make_primary, disable) change nothing: academy row md5s, domains and `django_admin_log` count identical before and after. `ops-noperm@` 403. Superuser `ops@` is still offered all 6 actions, and a reactivate→suspend round trip on qa-tmp-1 works. Playwright `--workers=1`: `f01-console.spec.ts` TC-133 and TC-134 pass (`retest-1/playwright.txt`). Regression tests `test_admin_permissions.py` 8/8 pass (`retest-1/pytest-regression.txt`); scoped `pytest etqan/tenants` 189 passed, exit 0 (`retest-1/pytest-tenants.txt`). Diff: only `permissions=["change"]` on the six actions; nothing else weakened. New, pre-existing defect found while retesting: ETQAN-QA-012 (view-only change page 500).

---

## ETQAN-QA-003: An invalid timezone or currency is accepted when an academy is created; the academy's Today page, invoices and background jobs then fail
- **Feature:** F01 Tenancy (create_academy, admin Add form, `create_academy` command). **Severity:** P1
  (a new academy is broken from its first sign-in, and its jobs fail every minute/hour; a realistic
  typo such as `africa/cairo` is enough). **Priority:** high
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9, dashboard 5ed775d), macOS, Chromium via Playwright 1.62.1 (1 worker). **Tag:** REAL
- **Preconditions:** Etqan staff `ops@qa.etqan.test`.
- **Reproduction steps:**
  1. `http://etqan.localhost/admin/tenants/academy/add/`: name "QA Tmp TZ", subdomain `qa-tmp-tz`,
     timezone `Mars/Phobos`, currency `usd`, admin `qa-tmp-tz-admin@qa.etqan.test`. Save.
  2. Accept the invite, sign in, call `GET /api/v1/schedule/today/` and `GET /api/v1/billing/invoices/`
     on `qa-tmp-tz.etqan.localhost`.
  3. Watch `dc.sh logs celery_worker`.
- **Expected:** the form (and command) refuse it: "Unknown timezone." / "Use a three-letter currency
  code, like EGP." (the contract of `platform/validators.py:clean_timezone/clean_currency`, which
  `docs/features/academy-settings.md` says `update_settings` uses; `tenancy.md` documents timezone and
  currency as creation inputs). Nothing is created.
- **Actual:** "The academy “QA Tmp TZ” was added successfully." `tenants_academy` and
  `academy_qa_tmp_tz.academy_academysettings` hold `Mars/Phobos|usd`; the admin user's timezone is
  `Mars/Phobos`. `schedule/today/` and `billing/invoices/` → HTTP 500 `ZoneInfoNotFoundError`;
  `scheduling.run_lifecycle` raises for that academy (hourly `run_daily`); `notifications.scan`
  logs "failed for academy academy_qa_tmp_tz" every minute. The academy admin's own settings PATCH
  validates (400 "Unknown timezone."), so the only way in is creation.
- **Evidence:** `evidence/F01/pw/tc052-053-submit.json`, `evidence/F01/pw/tc052-first-attempt-created.png`,
  `evidence/F01/tc052-db.txt`, `evidence/F01/tc052-api-as-tz-admin.txt`, `evidence/F01/tc052-django-log.txt`,
  `evidence/F01/tc052-run-lifecycle-probe.txt`, `evidence/F01/tc052-celery-log.txt`,
  `evidence/F01/tc056-051-settings.txt` (contrast: the settings API validates).
  Knock-on: while `qa-tmp-tz` was active, `manage.py scan_notifications` exited
  "CommandError: The scan failed in at least one academy." and the existing `journey.spec.ts`
  failed twice (`evidence/F01/pw/journey-run1-blocked-by-qa003.txt`); it passed once qa-tmp-tz was
  suspended (`evidence/F01/pw/journey-run.txt`). One mistyped academy breaks a platform-wide command.
- **Hint:** `tenants/services.py:create_academy` / `academy/services.py:ensure_settings` never call
  `clean_timezone`/`clean_currency`; `AcademyCreationForm` has no clean for either. The command
  shares the service (static; parity not re-created to save a schema).
- **Root cause (Agent 3, F01 fix attempt 1):** `tenants/services.py:create_academy` stored the
  `timezone` and `currency` arguments as given, on `Academy` and through
  `academy_services.ensure_settings` on `AcademySettings` (and so on the first admin). It never ran
  `platform/validators.py:clean_timezone` / `clean_currency`, which `academy.update_settings`
  uses. `AcademyCreationForm` had no clean for either field, and the `create_academy` command calls
  the same service. Both entry points therefore accepted any string up to the column length.
- **Fix (files):** `backend/etqan/tenants/services.py`: `create_academy` runs `clean_timezone` and
  `clean_currency` (field `currency`) right after `validate_subdomain`, before anything is saved.
  The currency is normalised to upper case, the same as the settings API, so `usd` is stored as
  `USD`. `backend/etqan/tenants/admin.py`: `AcademyCreationForm.clean_timezone` /
  `clean_currency` call the same validators, so the Add form shows "Unknown timezone." / "Use a
  three-letter currency code, like EGP." as field errors. The command already maps the etqan
  ValidationError to `CommandError`. Doc: `docs/features/tenancy.md` § Creating an academy.
- **Regression tests:** `backend/etqan/tenants/tests/test_services.py`
  (`test_bad_timezone_or_currency_is_rejected_and_nothing_is_created` x4: no row, schema or
  domain; `test_create_academy_stores_the_currency_upper_case`), `test_commands.py`
  (`test_create_academy_command_refuses_an_unknown_timezone`), `test_admin.py`
  (`test_admin_rejects_a_bad_timezone_or_currency` x3). All 9 fail on the unfixed code
  (`evidence/F01/fix-cycle-1/qa003-regression-fails-before-fix.txt`). Live, REAL (`evidence/F01/fix-cycle-1/qa003-live-after.txt`): the Add form as
  ops@ returns 200 with the field error for `Mars/Phobos`, `africa/cairo` and `US`; the command
  exits `CommandError: Unknown timezone.`; no `qa-tmp-v` row or schema. Before:
  `evidence/F01/fix-cycle-1/qa003-repro-before.txt`.
  Existing data is not repaired: the suspended throwaway `qa-tmp-tz` still holds `Mars/Phobos`.
  Any academy created before the fix with a bad value would need a one-off correction through its
  settings (the owner may want a check of production data).
- **Verification status:** VERIFIED
- **Verified by:** Agent 2, F01 retest-1, REAL. Filed step 1 rerun in the live admin Add form as `ops@` (`evidence/F01/retest-1/qa003-live-negative.txt`): `Mars/Phobos`, `africa/cairo` → 200 with "Unknown timezone." on `id_timezone`; `US`, `E1P` → "Use a three-letter currency code, like EGP."; empty → required. `create_academy` command with a bad timezone or currency → `CommandError`, exit 1. DB: no academy row, domain, schema, user or invite created. Positive path (`qa003-live-positive.txt`): Add form `Africa/Cairo` + `egp` → 302, `EGP` stored on Academy and AcademySettings, admin timezone Africa/Cairo, 1 invite in Mailpit; the throwaway `qa-tmp-r1ok` was then suspended. Regression tests pass (`retest-1/pytest-regression.txt`, 60 passed incl. test_services/test_commands/test_admin); `pytest etqan/tenants` 189 passed (`retest-1/pytest-tenants.txt`). Validation reuses `platform.validators` (same as `update_settings`); nothing weakened. Residual (not part of this fix, noted for the owner): existing bad data is not repaired (suspended `qa-tmp-tz` still holds `Mars/Phobos`), and `scan_notifications` still exits non-zero platform-wide if an active academy holds a bad timezone (A2-07); with creation validated, the settings API already validating, this can no longer arise through the product.

---

## ETQAN-QA-004: Domain admin returns HTTP 500 for an invalid hostname instead of a form error
- **Feature:** F01 Tenancy (custom domains). **Severity:** P3. **Priority:** medium
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9, dashboard 5ed775d), macOS, Chromium via Playwright 1.62.1 (1 worker). **Tag:** REAL
- **Reproduction steps:** `http://etqan.localhost/admin/tenants/domain/add/` as `ops@`, tenant "QA Tmp One",
  domain `bad_host` (also `nodot`, `-x.com`, `a..com`, `http://x.com`). Save.
- **Expected:** HTTP 200 with the form error "Enter a domain like academy-name.com." (`tenancy.md`
  §Custom domains: `add_custom_domain` "validates the hostname"; spec TC-084).
- **Actual:** HTTP 500, Django debug page "ValidationError at /admin/tenants/domain/add/ Enter a domain
  like academy-name.com." No row is created.
- **Evidence:** `evidence/F01/pw/tc082-085-domain-add.json` (TC-084 rows: status 500),
  `evidence/F01/pw/tc084-first-attempt.png`, `evidence/F01/tc082-domains-after.txt`.
- **Hint:** `DomainCreationForm.clean` checks only the base-domain rule; the etqan `ValidationError`
  from `add_custom_domain` in `DomainAdmin.save_model` is not turned into a form error.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN
- **F01 gate (Agent 2, 2026-10-18):** carried forward as a known P3/P4 issue; it does not block the F01 gate (no P0/P1/P2 open). TC-084 still fails (not retested by a fix: no Agent 3 attempt). Evidence: `evidence/F01/gate/`.

---

## ETQAN-QA-005: Two simultaneous creations of the same subdomain: the loser crashes with a raw IntegrityError
- **Feature:** F01 Tenancy (create_academy). **Severity:** P3. **Priority:** low
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9, dashboard 5ed775d), macOS, Chromium via Playwright 1.62.1 (1 worker). **Tag:** REAL
- **Reproduction steps:** start two `dc.sh exec -T django python manage.py create_academy --subdomain
  qa-tmp-race-b ...` at the same moment with different admin emails.
- **Expected:** one succeeds; the other gets the clean `CommandError: This subdomain is already taken.`
  (spec TC-062; the admin form path would otherwise show a 500).
- **Actual:** winner exit 0 ("Created QA Tmp Race B1…"); loser exit 1 with a full traceback
  `django.db.utils.IntegrityError: duplicate key value violates unique constraint
  "tenants_academy_schema_name_key"`. Data stays consistent: 1 row, 1 domain, 1 schema, 1 invite
  (to the winner).
- **Evidence:** `evidence/F01/tc062-race.txt`, `evidence/F01/tc062-proc1.txt`, `evidence/F01/tc062-proc2.txt`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN
- **F01 gate (Agent 2, 2026-10-18):** carried forward as a known P3/P4 issue; it does not block the F01 gate (no P0/P1/P2 open). TC-062 still fails; data stays consistent (1 row/domain/schema/invite). Evidence: `evidence/F01/gate/`.

---

## ETQAN-QA-006: The sign-in API accepts a cross-site login with no CSRF token (login CSRF)
- **Feature:** F02 Sign-in (found by F01 TC-114, cross-tenant CSRF). **Severity:** P2 (security: an
  attacker page can sign a victim's browser into an attacker-controlled academy account). **Priority:** medium
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9, dashboard 5ed775d), macOS, Chromium via Playwright 1.62.1 (1 worker). **Tag:** REAL
- **Reproduction steps:**
  `curl -i -H 'Origin: http://evil.example' --data-urlencode email=qaother-admin@qa.etqan.test
  --data-urlencode 'password=QA-Other-2026!' http://qaother.etqan.localhost/api/v1/identity/login/`
  (form-encoded, no csrftoken cookie, no X-CSRFToken). Also JSON with qa's csrftoken and
  `Origin: http://qa.etqan.localhost`.
- **Expected:** 403 CSRF failure. `docs/guide/architecture.md` ("the dashboard authenticates with Django
  session cookies and CSRF"), ADR-0003 "Session cookies with real CSRF protection … CSRF-exempt
  sessions: rejected". Authenticated writes already enforce it (`POST people/tags/` without a token →
  403 "CSRF Failed: CSRF token missing.").
- **Actual:** 200 with the user JSON and a `sessionid` cookie. DRF's `SessionAuthentication` only
  enforces CSRF for an already-authenticated request, so the anonymous `LoginView` is CSRF-exempt.
- **Evidence:** `evidence/F01/tc111-112-114.txt` (TC-114 and follow-up).
- **Root cause (Agent 3, F01 fix attempt 1):** DRF wraps every APIView in `csrf_exempt` and
  checks CSRF only inside `SessionAuthentication.authenticate`, that is only when the request
  already carries a signed-in session. `LoginView` is `AllowAny` and is called before anyone is
  signed in, so no CSRF check ever ran on it. The same applied to the other two views that create a
  session: `LoginTwoFactorView` and `QuickLoginExchangeView`. The dashboard never fetched the
  cookie before signing in, so a fresh browser had no token to send.
- **Fix (files):** `backend/etqan/platform/permissions.py`: new `CsrfChecked` permission, which
  runs DRF's own `SessionAuthentication().enforce_csrf(request)` (Django's `CsrfViewMiddleware`
  rules: token, plus Origin against the host; safe methods pass). `backend/etqan/identity/api/views.py`:
  `permission_classes = [AllowAny, CsrfChecked]` on `LoginView`, `LoginTwoFactorView`,
  `QuickLoginExchangeView`. Dashboard: `dashboard/src/features/identity/api.ts` (`login`,
  `loginTwoFactor`) and `dashboard/src/features/quicklogin/api.ts` (`exchange`) GET
  `identity/csrf/` first, the pattern the file already uses for the reset and verify POSTs. Doc:
  `docs/features/sign-in.md`. The request and response shapes are unchanged; a client that does
  not send the token now gets 403 `CSRF Failed: ...`. The dashboard is the only client
  (ADR-0003), and its tests already skip CSRF (`APIClient` default).
- **Regression tests:** `backend/etqan/identity/tests/test_login_csrf.py` (8 tests with
  `APIClient(enforce_csrf_checks=True)`: no token, a cross-site form post, a valid token with
  another Origin, a wrong token, 2FA step and quick-login exchange without a token are 403; login
  with the cookie token works and `me` is 200; the exchange with a token reaches the link check).
  6 fail on the unfixed views (`evidence/F01/fix-cycle-1/qa006-regression-fails-before-fix.txt`). Vitest:
  `dashboard/src/features/identity/api.test.ts` ("identityApi sign-in steps", 2) and
  `dashboard/src/features/quicklogin/api.test.ts` (new, 1); biome, `tsc --noEmit` and 22 identity
  and quicklogin test files (201 tests) green (`evidence/F01/fix-cycle-1/qa006-dashboard-checks.txt`). Playwright
  `dashboard/e2e/qa/f01-login-csrf.spec.ts` (`--workers=1`, 2 passed: a fresh browser signs in at
  qaother and its login POST carries `X-CSRFToken`; a form on another page gets 403 and no session)
  (`evidence/F01/fix-cycle-1/qa006-playwright.txt`, `evidence/F01/fix-cycle-1/pw/qa006-*.json`). Live curl (`evidence/F01/fix-cycle-1/qa006-live-after.txt`): the
  TC-114 cross-site POST, a POST without the cookie and qa's token replayed on qaother are 403;
  the dashboard's flow is 200. Before: `evidence/F01/fix-cycle-1/qa006-repro-before.txt`.
  Not covered (for F02): the other anonymous POSTs (password reset and code reset, resend
  verification, registration) remain CSRF-exempt. They do not create a session, so this is not
  login CSRF.
- **Verification status:** VERIFIED
- **Verified by:** Agent 2, F01 retest-1, REAL. Filed curl repro rerun (`evidence/F01/retest-1/qa006-live.txt`): cross-site form POST with no token and `Origin: http://evil.example` → 403; qa's csrftoken replayed on qaother → 403; no cookie → 403; correct token with a cross-site Origin → 403; 2FA step and quick-login exchange without a token → 403; same-origin flow (GET csrf, POST with token) → 200 + `me` 200; a signed-in write without a token is still 403. Playwright `--workers=1`: `f01-login-csrf.spec.ts` 2/2, `tenant-login.spec.ts` 3/3 (`retest-1/playwright.txt`), and the existing `b9-sign-in.spec.ts` 4/4 (2FA code sign-in, phone sign-in, sign-in-as, emailed quick-login link; `retest-1/playwright-b9-sign-in.txt`). Regression tests `test_login_csrf.py` 8/8 (`retest-1/pytest-regression.txt`); `pytest etqan/identity` 851 passed and `etqan/platform` 226 passed (`retest-1/pytest-{identity,platform}.txt`). Dashboard biome, tsc and vitest (22 files, 201 tests) green (`retest-1/dashboard-checks.txt`). The dashboard (`identity/api.ts`, `quicklogin/api.ts`) is the only caller of the three endpoints (grep). Other anonymous POSTs (reset, resend, registration) remain CSRF-exempt by DRF; they create no session; left for F02.

---

## ETQAN-QA-007: Suspending or reactivating an academy leaves no entry in the admin history
- **Feature:** F01 Tenancy (suspension, audit). **Severity:** P3 (audit gap; with ETQAN-QA-002 a suspend
  by a read-only account is untraceable). **Priority:** medium
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9, dashboard 5ed775d), macOS, Chromium via Playwright 1.62.1 (1 worker). **Tag:** REAL
- **Reproduction steps:** run "Suspend selected academies" then "Reactivate selected academies" on QA Tmp
  One; query `public.django_admin_log`.
- **Expected:** each status change is recorded with the staff user, as feature switches, copies,
  domain adds and change-form edits are (spec TC-138; `copy_features` itself calls `log_change`).
- **Actual:** no rows for the action-driven suspends (by `ops@` and by `ops-view@`); only change-form
  status edits appear.
- **Evidence:** `evidence/F01/tc136-138-admin-audit.txt`, `evidence/F01/pw/tc064-suspend.json`,
  `evidence/F01/pw/tc133b-view-only-actions.json`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN
- **F01 gate (Agent 2, 2026-10-18):** carried forward as a known P3/P4 issue; it does not block the F01 gate (no P0/P1/P2 open). TC-138 still fails. Evidence: `evidence/F01/gate/`.

---

## ETQAN-QA-008: Dashboard sign-in on an unknown academy host fails silently
- **Feature:** F01 Tenancy (host resolution). **Severity:** P3. **Priority:** low
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9, dashboard 5ed775d), macOS, Chromium via Playwright 1.62.1 (1 worker). **Tag:** REAL
- **Reproduction steps:** open `http://nope-qa.etqan.localhost/app/login`, enter any email/password,
  click Sign in.
- **Expected:** an error the user can act on (spec TC-100 "it should show an error, not hang"); the
  marketing site on the same host says "Site not found".
- **Actual:** the normal login form renders (header shows the raw host), and after Sign in nothing
  happens: no alert, no message; the console shows three 404s from `/api/v1/…`.
- **Evidence:** `evidence/F01/pw/tc100-unknown-host-spa.json`, `evidence/F01/pw/tc100-unknown-host-login.png`,
  `evidence/F01/tc100-103-host-resolution.txt`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN
- **F01 gate (Agent 2, 2026-10-18):** carried forward as a known P3/P4 issue; it does not block the F01 gate (no P0/P1/P2 open). Re-confirmed 2026-10-18 (gate/pw/tc100-unknown-host-spa.json: no alert after Sign in). Evidence: `evidence/F01/gate/`.

---

## ETQAN-QA-009: `just e2e` specs that call `manage()` fail when the checkout path contains a space
- **Feature:** F00 dev environment (e2e harness). **Severity:** P3 (every manage-driven e2e, e.g.
  `journey.spec.ts`, `features.spec.ts`, fails on this Mac). **Priority:** medium
- **Environment:** macOS, checkout at `~/Documents/Etqan tutor/etqan_tutor`. **Tag:** REAL
- **Reproduction steps:** `just e2e e2e/qa/f01-dashboard.spec.ts --grep TC-129` (any spec calling
  `manage("set_features", …)`).
- **Expected:** `manage()` runs the command in the stack (justfile `e2e` sets
  `E2E_MANAGE="just --justfile {{justfile()}} _stack-manage"`).
- **Actual:** `error: Path-prefixed recipes may not be used with --working-directory or --justfile.`
  `dashboard/e2e/manage.ts` splits `E2E_MANAGE` on whitespace, so the justfile path
  `/Users/…/Etqan tutor/…` becomes two words.
- **Evidence:** `evidence/F01/pw/f01-dashboard-run1.txt` (TC-129 failure). Workaround used:
  `E2E_MANAGE=<scratchpad>/manage-wrap.sh`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN
- **F01 gate (Agent 2, 2026-10-18):** carried forward as a known P3/P4 issue; it does not block the F01 gate (no P0/P1/P2 open). Workaround still required for the gate run (E2E_MANAGE=scratchpad/manage-wrap.sh). Evidence: `evidence/F01/gate/`.

---

## ETQAN-QA-010: Domain admin actions: hostnames are capitalised in messages, and Make primary / Disable confirm nothing
- **Feature:** F01 Tenancy (custom domains). **Severity:** P4 (cosmetic). **Priority:** low
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9, dashboard 5ed775d), macOS, Chromium via Playwright 1.62.1 (1 worker). **Tag:** REAL
- **Reproduction steps:** Domains changelist → "Check DNS and activate" on `qa-academy.test`; then
  "Make primary" on an active domain; then "Disable".
- **Expected:** messages name the domain as stored (`qa-academy.test`) and a successful Make primary /
  Disable says so (as Suspend/Reactivate do).
- **Actual:** "Qa-academy.test: resolves to nothing, …", "Qa-tmp-1.etqan.localhost: The academy's own
  subdomain cannot be disabled."; successful Make primary and Disable show no message at all.
- **Evidence:** `evidence/F01/pw/tc087-092.json`, `evidence/F01/pw/tc091-make-primary.json`,
  `evidence/F01/pw/tc093-094-095.json`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN
- **F01 gate (Agent 2, 2026-10-18):** carried forward as a known P3/P4 issue; it does not block the F01 gate (no P0/P1/P2 open). Not re-run. Evidence: `evidence/F01/gate/`.

---

## ETQAN-QA-011: The set-password page shows a raw English validator message, also in Arabic
- **Feature:** F01 Tenancy (first-admin onboarding; the same form serves every reset). **Severity:** P3
  (i18n/UX on the first screen a new academy admin sees). **Priority:** medium
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9, dashboard 5ed775d), macOS, Chromium via Playwright 1.62.1 (1 worker). **Tag:** REAL
- **Reproduction steps:** open `http://qa.etqan.localhost/app/reset-password?uid=MQ&token=x`, switch the
  language to العربية, type `123` in the new-password field, press Enter.
- **Expected:** a translated, human message in the page language (the dashboard ships `ar` and `en`
  catalogues, `docs/features/academy-settings.md` §Languages); the error is announced (`role=alert`,
  spec TC-141).
- **Actual:** the alert (correctly `role=alert`, page `dir=rtl lang=ar`) reads "Too small: expected
  string to have >=8 characters" in both English and Arabic: the zod default message.
- **Evidence:** `evidence/F01/pw/tc141-ar-reset.json`, `evidence/F01/pw/tc141-ar-reset-page.png`,
  `evidence/F01/pw/tc016-confirm.json` (English run, same text), `evidence/F01/pw/tc141-weak-password.png`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN
- **F01 gate (Agent 2, 2026-10-18):** carried forward as a known P3/P4 issue; it does not block the F01 gate (no P0/P1/P2 open). Re-confirmed 2026-10-18 (gate/pw/tc141-ar-reset.json: "Too small: expected string to have >=8 characters"). Evidence: `evidence/F01/gate/`.

---

## ETQAN-QA-012: A view-only Etqan staff member opening an academy's change page gets HTTP 500 (KeyError)
- **Feature:** F01 Tenancy (Etqan console access control). **Severity:** P3 (a read-only console
  account cannot look at any academy; no data is changed or exposed, local DEBUG shows a traceback).
  **Priority:** medium
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9 + fix cycle 1 working
  tree), macOS, curl. **Tag:** REAL
- **Found by:** Agent 2, F01 retest-1 (2026-10-17), while retesting ETQAN-QA-002. Pre-existing: the
  failing lines are unchanged at backend HEAD (`git show HEAD:etqan/tenants/admin.py`, lines 108/113);
  not caused by fix cycle 1.
- **Preconditions:** `ops-view@qa.etqan.test` (`is_staff`, only `tenants.view_academy` and
  `tenants.view_domain`).
- **Reproduction steps:** sign in at `http://etqan.localhost/admin/` as `ops-view@`, open
  `http://etqan.localhost/admin/tenants/academy/5/change/` (any academy; 4, 5 and 6 tried).
- **Expected:** Django's read-only change view (HTTP 200, fields shown read-only), as the Domain change
  page already does for the same user (`/admin/tenants/domain/12/change/` → 200); or a deliberate 403.
  `docs/features/feature-toggles.md` §1: only Etqan staff with change rights change switches; viewing
  is what the view permission grants.
- **Actual:** HTTP 500. `etqan/tenants/admin.py`, `_AcademyChangeForm.__init__`:
  `suspend = self.fields["etqan_defaults_suspended"]` → `KeyError: 'etqan_defaults_suspended'`. For a
  user without change permission Django makes every field read-only and leaves it out of the form, so
  the form's `__init__` (which also indexes `self.fields[feature_field(code)]`) fails. Superuser
  `ops@` gets 200 on the same URL. (Cycle 1 recorded the change page as "refused (403)" for this
  user; the GET is in fact a 500.)
- **Evidence:** `evidence/F01/retest-1/qa012-view-only-change-500.txt` (status codes, django log
  excerpt, HEAD code lines), `evidence/F01/retest-1/qa002-live.txt` ("change view still refused" line).
- **Hint:** guard the field lookups in `_AcademyChangeForm.__init__` (`if "etqan_defaults_suspended"
  in self.fields`, and skip feature fields that are absent), or show the computed values through
  read-only display methods. Add a test with a view-only staff client (the fixture in
  `tenants/tests/test_admin_permissions.py` already exists).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN
- **F01 gate (Agent 2, 2026-10-18):** carried forward as a known P3/P4 issue; it does not block the F01 gate (no P0/P1/P2 open). Re-confirmed 2026-10-18 (gate/open-bugs-recheck.txt: ops-view 500, ops 200). Evidence: `evidence/F01/gate/`.

---

## ETQAN-QA-013: View-only Etqan staff can run state-changing actions in the other console admins (invoices, beat tasks, provider tests, emails)
- **Feature:** F01 Tenancy, Etqan console access control (same pattern as ETQAN-QA-002, outside `tenants`).
  **Severity:** P1 (authorization bypass with money impact: a view-only staff member can mark an Etqan
  invoice paid or void it, which changes `may_suspend` and the defaults-suspension rule; issue a draft
  and email it to the academy's admins; and the same user is offered the platform-wide
  `PeriodicTask` "Run/Enable/Disable/Toggle"). **Priority:** high
- **Environment:** local docker stack `docker-compose.local.yml` (backend adff9c9 + fix cycle 1 working
  tree), macOS, curl + Django shell. **Tag:** REAL (the beat-task part is REAL static: offered and
  accepted by `get_actions()`, never executed).
- **Found by:** Agent 2, F01 gap review TC-151 (2026-10-18), suspected as S6 by Agent 1.
- **Preconditions:** `ops-view-all@qa.etqan.test` / `QA-Etqan-ViewAll-2026!`: `is_staff`, only the
  `view_*` permissions of etqan_billing, integrations, identity, django_celery_beat, account and
  tenants. Fixture `EtqanInvoice` rows for `qa-tmp-1` (one issued 31 days ago, one draft), an
  `EmailAddress` row (`verified=False`) for an `ops-*` account.
- **Reproduction steps:**
  1. Sign in at `http://etqan.localhost/admin/` as `ops-view-all@`.
  2. Open `/admin/etqan_billing/etqaninvoice/`: the action bar offers Issue, Email again, Mark paid,
     Void. `/admin/account/emailaddress/` offers Make verified;
     `/admin/django_celery_beat/periodictask/` offers Enable, Disable, Toggle, Run;
     `/admin/integrations/platformaccount/` offers Test.
  3. POST `action=mark_paid&_selected_action=<issued id>&paid_on=2026-10-01&method=cash` to the
     invoice changelist (or choose it in the UI). Repeat with `void_invoices`, `issue_invoices` (on the
     draft) and, on the EmailAddress changelist, `make_verified`.
- **Expected:** view-only means view (`docs/features/feature-toggles.md` §1; the QA-002 fix applied the
  same rule to the tenants actions with `permissions=["change"]`). No state-changing action is offered,
  and a forged action POST is refused by Django.
- **Actual:**
  - "· ETQ-2025-01-0001: marked paid." The invoice became `paid`, `paid_on` 2026-10-01, method cash.
  - "· ETQ-2025-01-0001: voided." The invoice became `void`, `voided_at` set.
  - "· ETQ-2025-02-0001: issued; the PDF goes to its admins." The draft was issued, and the invoice
    email reached `qa-admin@qa.etqan.test` in Mailpit (`emailed_at` set).
  - "Marked ops-view-all@qa.etqan.test as verified." `EmailAddress.verified` f→t.
  - None of these wrote a `django_admin_log` row.
  - `get_actions()` for this user (and for `ops-view@`) returns
    `etqan_billing.etqaninvoice: [email_again, issue_invoices, mark_paid, void_invoices]`,
    `django_celery_beat.periodictask: [disable_tasks, enable_tasks, run_tasks, toggle_tasks]`,
    `integrations.platformaccount: [test_accounts]`, `identity.teacherprofile:
    [send_password_set_email]`, `account.emailaddress: [make_verified]`. None declares `permissions=`.
- **Evidence:** `evidence/F01/gap/tc151-forged.txt`, `evidence/F01/gap/tc151-get-actions-static.txt`.
  Fixtures were deleted afterwards.
- **Hint:** add `permissions=["change"]` to the actions in `etqan_billing/admin.py`,
  `integrations/admin.py` and `identity/admin.py`. For the third-party admins
  (`django_celery_beat.PeriodicTaskAdmin`, allauth `EmailAddressAdmin`), unregister and re-register
  them with subclasses whose actions require `change`, or filter `get_actions()` by
  `has_change_permission`. Extend `tenants/tests/test_admin_permissions.py`'s view-only fixture to every
  registered `ModelAdmin` (a test that walks `admin.site._registry` would stop the pattern recurring).
  Consider logging the invoice actions (`log_change`) as well.
- **Root cause (Agent 3, fix cycle 2, 2026-10-18):** Django offers an admin action to everyone who may
  view the changelist unless the action declares `permissions=`; the posted action is validated only
  against `get_actions()`. QA-002 fixed this for the tenants actions only. Six project actions
  (`etqan_billing` issue_invoices, email_again, mark_paid, void_invoices; `integrations` test_accounts;
  `identity` send_password_set_email) and two third-party admins (django-celery-beat 2.9.0
  `PeriodicTaskAdmin`: enable/disable/toggle/run; allauth 65.20.0 `EmailAddressAdmin`: make_verified)
  declared none. Reproduced before any change (REAL static, live DB): `get_actions()` for `ops-view-all@`
  and `ops-view@` returns exactly the five sets above (`evidence/F01/fix-cycle-2/qa013-repro-before.txt`).
  Expected behaviour: `docs/features/tenancy.md` (actions need the model's change permission),
  `feature-toggles.md` §1 and the Django permission model.
- **Fix:** `permissions=["change"]` on the six project actions (`backend/etqan/etqan_billing/admin.py`,
  `integrations/admin.py`, `identity/admin.py`). New `backend/etqan/platform/admin.py`: unregisters
  `PeriodicTask` and `EmailAddress` and registers them again with subclasses of the third-party admins
  plus a `ChangeToRunActions` mixin (`get_actions` keeps only `delete_selected`, which has its own delete
  permission, unless `has_change_permission`). It works because `etqan.platform` comes after
  `allauth.account` and `django_celery_beat` in `INSTALLED_APPS`, so autodiscovery imports it after
  theirs. No migration, no API change. Staff with the change permission and superusers keep every action
  (`qa013-live-after.txt`). Docs: `docs/features/tenancy.md`, `etqan-billing.md`, `integrations.md`. Not
  done: `log_change` for the invoice actions (a separate audit improvement, not needed to close the bypass).
- **Regression tests:** `backend/etqan/tenants/tests/test_admin_permissions.py` (+4: a walk over every
  registered admin (`apps.get_models()` + `admin.site.get_model_admin`) as staff holding every `view_*`
  permission expects no action anywhere; forged beat enable/toggle/run; forged make_verified;
  change-permission staff keep the third-party actions), new
  `backend/etqan/etqan_billing/tests/test_admin_permissions.py` (6: nothing offered; forged issue,
  email again, mark paid and void change nothing and send no mail; change-permission staff are offered
  and run them), `backend/etqan/integrations/tests/test_admin.py::test_view_only_staff_cannot_run_the_test_action`.
  With the fix taken out, 9 of these fail (`regression-fails-before-fix-final.txt`, together with QA-014's 3);
  with it they pass (`qa013-regression-after-fix.txt`). ruff, format and lint-imports (54 kept, 0 broken)
  are clean (`ruff.txt`, `lint-imports.txt`); scoped suites all pass (`pytest-*.txt`: etqan_billing 137, integrations 391, platform 226, identity admin 8, tenants 197). Tag: REAL (Django test
  client against the test DB; live static `get_actions()`). Agent 2 should re-run TC-151 (forged POSTs as
  `ops-view-all@`) live.
- **Verification status:** VERIFIED
- **Verified by:** Agent 2, retest 2 (2026-10-18), evidence `evidence/F01/retest-2/`. Diff reviewed
  (`diff-backend-qa013-014.txt`): no validation weakened, no test special-casing, no migration/API change;
  `INSTALLED_APPS` order allauth.account < django_celery_beat < etqan.platform confirmed, and the live
  registry shows `EtqanPeriodicTaskAdmin` in place. TC-151 re-run live as filed (REAL,
  `tc151-forged-view-all.txt`): `ops-view-all@` is offered no action and no checkbox on the invoice,
  email address, periodic task, platform account, teacher profile, academy and domain lists; 13 forged
  POSTs (mark_paid, void_invoices, email_again, issue_invoices, make_verified, enable/disable/toggle/run
  tasks, test_accounts, send_password_set_email, suspend, reactivate) leave every row md5 unchanged,
  send 0 mails and write 0 admin_log rows. Control (`tc151-positive-superuser.txt`): superuser `ops@` is
  offered and runs them all (marked paid, issued + emailed to qa-admin@ in Mailpit, verified,
  task enabled then disabled). Static walk (`tc151-get-actions-static.txt`): view-all / view / noperm 0 of
  30 admins with actions; ops-change and ops-domain keep exactly their tenants actions (TC-150/133
  unchanged); a transient change-permission user (rolled back) keeps all 5 action sets. Playwright
  `--workers=1` R2-TC-151 pass (`playwright.txt`, `pw/r2-tc151-*`). Agent 3's regression tests: 12 fail
  with the fix removed in an in-container copy (`regression-fails-without-fix.txt`), pass with it
  (`pytest-regression.txt`, 61 passed). Scoped suites all exit 0: etqan_billing 137, integrations 391,
  platform 226, identity 851, tenants 197. ruff/format clean on the 9 files; lint-imports 54 kept, 0
  broken. Residual (not part of this bug): the invoice actions still write no admin history (`log_change`),
  noted as an audit improvement like QA-007.

---

## ETQAN-QA-014: A stale academy change page silently reverts newer changes (reactivates a suspended academy, lifts the defaults suspension, re-enables switched-off features)
- **Feature:** F01 Tenancy (Etqan console, academy change page). **Severity:** P2 (significant
  workflow/data integrity: an unrelated edit undoes a suspension or a defaults suspension Etqan applied
  for non-payment, without warning). **Priority:** high
- **Environment:** local docker stack (backend adff9c9 + fix cycle 1 working tree), macOS, curl
  replaying the admin form exactly as the browser submits it. **Tag:** REAL
- **Found by:** Agent 2, F01 gap review TC-152 (2026-10-18), suspected as S7 by Agent 1.
- **Preconditions:** `qa-tmp-1` active, `features` stored with `families: true`; a fixture
  `EtqanInvoice` issued 31 days ago (so the defaults flag may be set).
- **Reproduction steps:**
  1. As `ops@`, open `/admin/tenants/academy/6/change/` in tab A.
  2. In tab B: Suspend qa-tmp-1 with the changelist action; run
     `manage.py set_features qa-tmp-1 --off families`; on a fresh change page tick
     "Suspend Etqan's defaults" and Save. Row now: `suspended`, flag `t`, `families: false`.
  3. In tab A (still showing the old values), change only Plan notes and Save.
- **Expected:** only `plan_notes` changes (status stays suspended, flag stays on, families stays off),
  or the save is refused as stale.
- **Actual:** 302 "changed successfully". Row after: `status=active`, `etqan_defaults_suspended=f`,
  `features.families=true`, `plan_notes` set. The admin log row lists
  `["Status", "Plan notes", "Suspend Etqan's defaults", "Family accounts (…)"]`. Cause: the ModelForm
  saves `status` and `etqan_defaults_suspended` as the page showed them, and `save()` compares the
  feature boxes with the current row, so every box that differs from the current row is written back.
- **Evidence:** `evidence/F01/gap/tc152-stale-form.txt`.
- **Hint:** take `status` out of the change form (status changes only through the Suspend/Reactivate
  actions, which already exist), or carry the loaded values in hidden fields / an `updated_at`
  version and refuse the save when the row changed since the page was rendered. For the feature boxes,
  compare against the values the page was rendered with (hidden initial values), not the current row.
- **Root cause (Agent 3, fix cycle 2, 2026-10-18):** `_AcademyChangeForm` is a plain ModelForm. On POST,
  Django builds it with the row as it is now, so `changed_data` means "differs from the current row", not
  "changed on this page". `construct_instance` writes every posted model field, and the feature merge in
  `save()` writes every box in `changed_data`. A stale page therefore writes back each value that changed
  elsewhere since it was rendered. A second symptom of the same cause: a stale page that still shows the
  defaults suspended, saved untouched after the suspension was lifted, is refused by the 30-day rule on a
  box nobody touched. Reproduced by the regression test before the fix: status back to `active`, flag
  lifted (`regression-fails-before-fix-final.txt`). Expected behaviour: the reporter's expectation (only
  the edited field changes), `feature-toggles.md` ("Only changed checkboxes are written") and
  `etqan-billing.md` (the suspension is Etqan's deliberate act, "never automatic").
- **Fix (`backend/etqan/tenants/admin.py`, no migration):** every change-form field gets
  `show_hidden_initial`, so the page carries the values it showed and `changed_data` compares against
  them (Django's built-in mechanism, which also propagates the shown values when the form is re-displayed
  with errors). `clean()` gives each model field the user didn't change the row's current value, and
  `clean_etqan_defaults_suspended` skips the 30-day check when the box wasn't changed on the page. The
  feature merge needs no change: it already writes only `changed_data`, which is now page-relative. The
  admin history also lists only what really changed ("Changed Plan notes."). A POST without the hidden
  values, such as a page rendered before this change, is compared with the row as before. Two edits of
  the same field are still last-writer-wins, by design: the later page's user explicitly chose that
  value. Status stays editable on the page. Taking it out of the form (the hint's other option) would
  change the documented UI and isn't needed. Docs: `docs/features/tenancy.md`, `feature-toggles.md`.
- **Regression tests:** new `backend/etqan/tenants/tests/test_admin_stale_change.py` (4; it posts the
  rendered HTML the way a browser does, hidden initials included): a stale page changing only Plan notes
  leaves suspended, the flag and families off as they are, and logs only Plan notes; what the user did
  change on a stale page (name, a feature box) is saved; a fresh page still reactivates, lifts the
  suspension and switches a feature on; an untouched stale suspend box neither re-suspends nor is
  refused. 3 fail before the fix (the "fresh page" control passes both ways); all pass after. The
  existing `test_admin_features.py` and `test_admin_suspend.py`, whose helpers post without hidden
  initials, still pass (`qa014-regression-after-fix.txt`, 44 tenants admin tests). Tag: REAL (Django test
  client, test DB). Agent 2 should re-run TC-152 live in two tabs.
- **Verification status:** VERIFIED
- **Verified by:** Agent 2, retest 2 (2026-10-18), evidence `evidence/F01/retest-2/`. Diff reviewed:
  Django's own `show_hidden_initial`; `clean()` only replaces values of fields not changed on the page
  with the row's current value; the 30-day rule is skipped only when the box wasn't changed. TC-152 re-run
  live as filed (REAL, `tc152-stale-form.txt`): after suspend, `set_features --off families` and the
  defaults flag on in tab B, the stale tab A plan-notes save leaves `suspended | t | families false`,
  saves only plan_notes, and logs "Changed Plan notes.". Variants (`tc152-variants.txt`): a stale page
  re-displayed with an error carries the shown initials and its resubmit still undoes nothing; an
  explicit name edit on a stale page is saved; a fresh page reactivates and lifts the flag. Forged hidden
  initials (`tc152-forged-initials.txt`): `initial-etqan_defaults_suspended=True` + box ticked cannot
  bypass the 30-day rule (flag stays off); a real tick and a legacy POST without initials are refused with
  the 30-day message; a legacy plan-notes save still works. Playwright two-tab UI (R2-TC-152, `--workers=1`,
  `playwright.txt`, `pw/r2-tc152-*`): pass, DB `suspended | families off | plan notes saved`, history
  "Changed Family accounts" then "Changed Plan notes" (first attempt was a harness race reading the
  message before load; fixed the wait and re-ran with `--retries=0`). Regression tests: 3 fail with the
  fix removed, pass with it; existing feature/suspend admin tests pass; tenants 197 passed. Known by
  design: two edits of the same field are last-writer-wins; a stale page can't re-tick a box it already
  shows ticked (it shows the old state). QA-012 (view-only change page 500) unchanged, still OPEN P3.

---

## ETQAN-QA-015: The academy change page accepts an unknown timezone and a malformed currency for an existing academy
- **Feature:** F01 Tenancy (residual of ETQAN-QA-003). **Severity:** P3 (all product readers use
  `AcademySettings`, so the bad value has no effect until `get_settings()` self-heals a missing settings
  row, which then copies it). **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + fix cycle 1 working tree), macOS, curl
  replaying the admin form; Django shell for the self-heal part. **Tag:** REAL (form), FAKE (self-heal:
  forced state inside a rolled-back transaction)
- **Found by:** Agent 2, F01 gap review TC-155 (2026-10-18), suspected as S8 by Agent 1.
- **Reproduction steps:**
  1. As `ops@`, open `/admin/tenants/academy/6/change/`, set Timezone `Mars/Phobos`, Currency `usd`,
     Save.
  2. (Self-heal) In a shell, inside `transaction.atomic()` (rolled back): delete the academy's
     `AcademySettings` row and call `academy.services.get_settings()` in its tenant context.
- **Expected:** the QA-003 contract: "Unknown timezone." and "Use a three-letter currency code, like
  EGP.", nothing stored (`clean_timezone` / `clean_currency`, as the Add form and the command do now).
- **Actual:** 302 saved; `tenants_academy` row `Mars/Phobos|usd`. A valid lowercase `egp` is also
  stored lowercase (not normalised). `AcademySettings` itself is unchanged, but the self-heal creates
  settings with `timezone='Mars/Phobos'`, `default_currency='usd'` (the state QA-003 showed breaks
  schedule/invoice pages and the hourly jobs).
- **Evidence:** `evidence/F01/gap/tc155-change-form-tz.txt`. Values restored afterwards.
- **Hint:** add `clean_timezone` / `clean_currency` methods to `_AcademyChangeForm` (the same
  validators `AcademyCreationForm` got in fix cycle 1), or make the two fields read-only on the change
  page since they only seed settings (TC-055).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-016: `create_academy` command doesn't validate the admin email or the name (creates an academy whose admin can never be invited; raw DataError)
- **Feature:** F01 Tenancy (provisioning command; input parity with the Add form). **Severity:** P3
  (operator tool; the result is a fully migrated academy nobody can sign in to, and a traceback
  instead of an error). **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + fix cycle 1 working tree), macOS,
  `dc.sh exec -T django python manage.py create_academy …`. **Tag:** REAL
- **Found by:** Agent 2, F01 gap review TC-156 (2026-10-18), suspected as S9 by Agent 1.
- **Reproduction steps:**
  1. `manage.py create_academy --name "QA Tmp Cmd" --subdomain qa-tmp-cmd --admin-email not-an-email`
  2. `manage.py create_academy --name "<201 characters>" --subdomain qa-tmp-cmd2 --admin-email
     qa-cmd2@qa.etqan.test`
- **Expected:** a clean `CommandError` ("Enter a valid email address.", a name-length message), exit 1,
  nothing created, the same checks the admin Add form applies.
- **Actual:**
  1. Exit 0, "Created QA Tmp Cmd at qa-tmp-cmd.etqan.localhost": row, domain and a migrated schema
     `academy_qa_tmp_cmd`; first admin `not-an-email` with an unusable password. The invite then fails
     in Celery: `SMTPRecipientsRefused({'not-an-email': (553, '5.1.3 The address is not a valid RFC
     5321 address')})`. Nobody can ever accept or reset it.
  2. Raw traceback `django.db.utils.DataError: value too long for type character varying(200)`
     (nothing created, because the INSERT fails before the schema).
- **Evidence:** `evidence/F01/gap/tc156-command-parity.txt`. `qa-tmp-cmd` (id 17) is suspended.
- **Hint:** validate in `services.create_academy` (so the command, the admin and any future caller
  share it): `django.core.validators.validate_email` on `admin_email`, a non-blank name of at most
  200 characters, raising `ValidationError` (the command already turns that into `CommandError`).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-017: A session refused on re-check is not really signed out; it comes back when the condition clears (quick-login revocation and the `parents` switch)
- **Feature:** F02 Sign-in & account security (`identity/authentication.py`, impersonation re-checks,
  `services.sign_in_refusal`). **Severity:** P2 (security: revoking quick-login or parent access is not
  durable). **Priority:** high
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F02 TC-017 / TC-025 (2026-10-19). Not in Agent 1's S-list.
- **Preconditions:** `quick_login` and `parents` on; admin `qa-admin@`, staff `f02-staff-ql@` (role 4
  "F02 QL Full": `quick_login.create` + `student/teacher/parent.view`), student id 10, parent `qa-parent@`.
- **Reproduction steps:**
  1. Admin `POST /api/v1/people/students/10/quick-login/` (200). Note the new `sessionid` value K.
  2. `manage.py set_features qa --off quick_login`; `curl -H "Cookie: sessionid=K" .../identity/me/` → 403.
  3. `manage.py set_features qa --on quick_login`; replay the same cookie K → **200**, still the student,
     `impersonator: {id:1}`.
  4. Same with the staff actor: start, `PATCH /access/roles/4/` removing `quick_login.create` → 403; restore
     the code → the old cookie is **200** again.
  5. Parent `qa-parent@` signs in (cookie P); `--off parents` → 403; `--on parents` → cookie P is **200**.
  6. `select count(*) from academy_qa.django_session where session_key='K'` stays 1 after the 403, and the
     decoded row still holds `_auth_user_id=10` and `etqan.impersonator`.
- **Expected:** `docs/features/sign-in.md` § Quick login ("On every request, `SessionAuthentication`
  re-checks `impersonation.session_valid`…") and the module docstring of `identity/authentication.py`
  ("is signed out on its next request"): the refused session is logged out for good (row deleted /
  flushed), so a later switch-on or role restore cannot revive it.
- **Actual:** the 403 is returned but the session row survives unchanged; the session revives as soon as
  the condition clears (within the 1-hour impersonation window, or the 14-day session for a parent).
  Refusals that end sessions by other code paths (actor or target deactivated: `_end_sessions`) do delete
  the row.
- **Evidence:** `evidence/F02/tc017.txt` (sections "TC-017 extra" and "(d) resurrection check"),
  `evidence/F02/tc025.txt` ("parents back on, ORIGINAL cookie replay: 200").
- **Hint (not a root-cause claim):** `ATOMIC_REQUESTS = True` (`config/settings/base.py:31`) and
  `authenticate()` calls `logout(request._request)` and then the view answers 403 via an exception, so
  DRF's `set_rollback()` likely rolls back the session DELETE done by `session.flush()`.
- **Root cause (Agent 3, 2026-10-19, confirmed):** the hint is right. `SessionAuthentication.authenticate`
  (`identity/authentication.py`) runs inside the view, so inside the `ATOMIC_REQUESTS` transaction.
  `logout()` → `session.flush()` deletes the `django_session` row, then the anonymous request is answered
  403 by DRF's exception handler, which calls `set_rollback()`: the DELETE is rolled back. The response
  still deletes the browser's cookie, which is why the UI looks signed out and the existing test
  (`test_a_signed_in_parent_is_signed_out_on_the_next_request`) passed; a replayed cookie revives.
  Reproduced in pytest (`evidence/F02/fix-cycle-1/qa017-before.txt`: row still exists after the 403).
- **Fix (FIXED-UNVERIFIED):** `authenticate()` keeps the refused session key on the Django request
  (`REFUSED_SESSION_KEY`) before `logout()`; new `EndRefusedSessionMiddleware` (same module, registered
  in `config/settings/base.py` right after `AuthenticationMiddleware`) deletes that row with
  `request.session.delete(key)` after the view returns, i.e. outside the request transaction. No
  migration, no API change. Files: `etqan/identity/authentication.py`, `config/settings/base.py`.
- **Regression tests:** `identity/tests/test_impersonation.py::test_a_refused_session_does_not_come_back`
  (quick_login off → row gone → on → replayed cookie still 403) and
  `identity/tests/test_features.py::TestParentsOff::test_the_old_session_cookie_stays_signed_out`. Both
  fail before, pass after. `pytest etqan/identity` 861 passed; ruff + format + lint-imports (54 kept)
  clean. Live REAL check on the stack (parents switch): row count 0, replay after `--on parents` → 403
  (`evidence/F02/fix-cycle-1/live-after.txt`). Agent 2 to retest the role-code (staff) variant live.
- **Retest (Agent 2, retest 1, 2026-10-18T23:51Z, REAL):** original repro rerun live in academy `qa`
  (`evidence/F02/retest-1/qa017-retest.txt`). (1) admin quick-login to student 10, `--off quick_login` →
  replay 403, `django_session` row count 0; `--on` → replay still 403. (2) staff `f02-staff-ql@` (role 4):
  removing `quick_login.create` → 403, row 0; role restored (permissions identical before/after) →
  replay still 403; a fresh staff start works again (200). (3) parent `qa-parent@`: `--off parents` →
  403, row 0; `--on` → replay 403; fresh login 200. (4) a refused cookie on an AllowAny endpoint
  (`sign-in-options/`, 200 anonymous) also ends the row. Controls: seeded demo/qaother admins sign in;
  normal logout unaffected. Regression tests (13 incl. all `TestParentsOff`) pass, `pytest etqan/identity`
  861, `etqan/platform` 226, ruff/format/lint-imports clean; F02 Playwright 3/3. Diff reviewed: no
  validation weakened, no test special-casing; the middleware only deletes the key the authenticator
  recorded, after the view's transaction (`retest-1/diff-reviewed.patch`, `code-freeze.txt`).
- **Verification status:** VERIFIED (Agent 2, 2026-10-19)

## ETQAN-QA-018: Change-password and reset-by-link skip the password validators (accept `12345678`, `password`, the email, the same password, 200 000 chars)
- **Feature:** F02 Sign-in & account security (`identity/services.change_password`,
  `confirm_password_reset`; serializers `ChangePasswordSerializer`, `PasswordResetConfirmSerializer`).
  **Severity:** P2 (security: weak passwords on the two most-used paths). **Priority:** high
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F02 TC-010 / TC-008 (S1 confirmed).
- **Reproduction steps:**
  1. Sign in as `f02-a@qa.etqan.test` / `F02-Pass-2026!`.
  2. `POST /api/v1/identity/me/password/` `{"current_password":"F02-Pass-2026!","new_password":"12345678"}`
     → 200; then `"password"` → 200; then `"f02-a@qa.etqan.test"` → 200; the same value again → 200;
     then a 200 000-character password → 200.
  3. Reset by link: `POST /identity/password/reset/` for `f02-d@`, then `password/reset/confirm/` with
     `"new_password":"12345678"` → 200, and the login with `12345678` → 200.
  4. Compare: reset by code `POST /identity/password/code/reset/` with `"12345678"` → 400
     `{"new_password":["This password is too common."]}`.
- **Expected:** the settings' `AUTH_PASSWORD_VALIDATORS` (UserAttributeSimilarity, MinimumLength,
  CommonPassword, Numeric) apply to every place a person chooses a password, as code reset
  (`codereset.py:250`) and account creation (`services._set_new_password`, `services.py:745`) already do;
  a sane `max_length` on password fields.
- **Actual:** only `min_length=8` is checked on change and link reset; no upper bound anywhere.
- **Evidence:** `evidence/F02/tc010.txt`.
- **Root cause (Agent 3, 2026-10-19):** `services.change_password` and `services.confirm_password_reset`
  call `user.set_password()` directly; only the serializers' `min_length=8` stood in front of them, while
  `codereset._set_password` and `services._set_new_password` run `validate_password`. Neither serializer
  had `max_length` (code reset's has 128). Intent confirmed: the settings' validators plus the two
  sibling paths that already enforce them; no doc exempts these two paths.
- **Fix (FIXED-UNVERIFIED):** new `services._validate_new_password(user, password)` (`validate_password`
  → `ValidationError(field="new_password")`), called in `change_password` after the current-password check
  and in `confirm_password_reset` after the token check (an invalid link still answers the token error
  first). `ChangePasswordSerializer` / `PasswordResetConfirmSerializer` `new_password` get
  `max_length=128`, matching `CodeResetSerializer`. Same 400 shape `{"new_password": [...]}` as before, so
  the dashboard's field errors keep working. Not changed: "same password as now" is accepted; no
  `AUTH_PASSWORD_VALIDATORS` entry or spec forbids reuse, so this is an owner decision, not part of this fix.
- **Regression tests:** `identity/tests/test_password_management.py::TestNewPasswordsAreValidated`
  (change and link reset × `12345678`, `password`, the email, 129 chars; also asserts the old password
  still works). 8 failed before (`evidence/F02/fix-cycle-1/qa018-before.txt`), pass after;
  `pytest etqan/identity` 861 passed. Live REAL: change-password answers 400 for all four
  (`evidence/F02/fix-cycle-1/live-after.txt`). Agent 2 to retest reset-by-link live.
- **Retest (Agent 2, retest 1, 2026-10-18T23:53Z, REAL):** original repro rerun live
  (`evidence/F02/retest-1/qa018-retest.txt`). Change password as `f02-a@`: `12345678`, `password`,
  the email, 129 chars and 200 000 chars all 400 with the validator/length message; wrong current
  password still answers the `current_password` error; DB hash unchanged after the refusals; login with
  `12345678` 400; a strong change 200 (old password then refused) and restored. Reset by link as
  `f02-d@` (link from mailpit): the same four 400, bad token + weak → token error first, hash unchanged,
  strong value 200, token reuse 400; password restored by a second link. UI: Account → Change password
  shows "This password is too common." under New password (`retest-1/playwright-qa018-ui.txt`,
  `qa018-ui.png`). All `set_password` callers outside tests now validate (services ×3, codereset;
  `models.create_user` is the manager). Regression tests 8/8 pass.
- **Same password as the current one:** still accepted (200). Agent 2 accepts this as a
  **PROPOSAL-accepted (owner approval)**, not a defect of this fix: no configured validator, doc or spec
  forbids reuse, NIST 800-63B does not require it, and the risk is low (the person already knows the
  password; nothing weakens). Recorded in `coverage-gaps.md` § F02.
- **Verification status:** VERIFIED (Agent 2, 2026-10-19); reuse sub-part PROPOSAL-accepted

## ETQAN-QA-019: `password/reset/` and `resend-verification/` answer 500 to a JSON body that isn't an object
- **Feature:** F02 Sign-in (`platform/throttling.py` `EmailScopedThrottle.get_cache_key`, line 42:
  `request.data.get("email")`). **Severity:** P3 (anonymous input → unhandled `AttributeError`, debug page
  locally, error noise in production; no data impact). **Priority:** medium
- **Environment:** local docker stack, backend adff9c9. **Tag:** REAL
- **Found by:** Agent 2, F02 TC-027 (S2 confirmed).
- **Reproduction steps:** with a CSRF token, `POST /api/v1/identity/password/reset/` (or
  `/identity/resend-verification/`) with `Content-Type: application/json` and body `[]`, `"str"`,
  `null` or `123`.
- **Expected:** 400 with a JSON error, like the other 5 identity endpoints in the same sweep.
- **Actual:** 500, `AttributeError: 'list' / 'str' / 'NoneType' / 'int' object has no attribute 'get'`
  (16 of 16 such requests; 30 new tracebacks in the django log).
- **Evidence:** `evidence/F02/tc027.txt`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-020: Self-service password resets are offered to accounts that can't sign in (deactivated by link; parent while `parents` is off by link and code)
- **Feature:** F02 Sign-in (`services.request_password_reset` / `confirm_password_reset`,
  `codereset.eligible`). **Severity:** P3 (no access is gained, but a deactivated person or a parent of an
  academy with parents off receives reset mail and can change the password and mark the email verified).
  **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F02 TC-006 (S3 confirmed) and TC-025.
- **Reproduction steps:**
  1. Admin `POST /api/v1/people/students/8/deactivate/`. Anonymous `POST /identity/password/reset/`
     `{"email":"f02-a@qa.etqan.test"}` → 200 and a reset mail arrives; `password/reset/confirm/` → 200
     (password changed, `is_active` still false). The admin-sent reset for the same person answers 400
     "Activate this account first."
  2. `set_features qa --off parents`; `POST /identity/password/code/` for `f02-parent@` → a code mail;
     `code/verify/` lists the parent; `POST /identity/password/reset/` for `qa-parent@` → a reset mail.
- **Expected:** the admin-sent reset already refuses inactive accounts; `docs/features/sign-in.md`
  § Password reset says code reset is "only for active students and parents". Self-service reset should
  refuse (silently, same 200/202) accounts that are inactive or that `sign_in_refusal` would refuse.
- **Actual:** mail is sent and the reset succeeds.
- **Evidence:** `evidence/F02/tc006.txt` ("S3 check"), `evidence/F02/tc025.txt` (add-on).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-021: A staff role editor can retire (and rename) a role whose permissions they don't hold, stripping a stronger staff member's access
- **Feature:** F03 Roles & permissions (`access/services.py:update_role`). **Severity:** P2 (privilege
  boundary: no access is gained, but a weaker staff account can revoke a stronger account's access at once
  and cannot be stopped; only an admin can undo it). **Priority:** high
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F03 TC-005 (spec S1 confirmed).
- **Preconditions:** role `F03 Role editor` (id 8) = `role.view_any, role.view, role.create, role.update,
  staff.view_any, staff.view, staff.create, staff.update, student.view_any`, held by staff Ed
  (`f03-ed@qa.etqan.test`, id 21). Role `F03 Money` (id 9) = `invoice.view_any, payment.view_any,
  payslip.view_any`, held by staff Mo (`f03-mo@qa.etqan.test`, id 22).
- **Reproduction steps:**
  1. Mo `GET /api/v1/billing/invoices/` → 200.
  2. Ed `PATCH /api/v1/access/roles/9/` `{"is_active":false}` → **200**, `is_active=false`, `members=1`.
  3. Mo `GET /api/v1/billing/invoices/` → 403; Mo `GET /identity/me/` → `permissions: []`.
  4. Ed `PATCH /api/v1/access/roles/9/` `{"is_active":true}` → 403 "You can only restore a role whose
     permissions you hold yourself." (so Ed cannot undo it).
  5. Ed `PATCH /api/v1/access/roles/9/` `{"name_en":"F03 Renamed by Ed","name_ar":"F03 أعاد"}` → 200 (rename
     of a stronger role is also unguarded).
- **Expected:** `docs/features/roles-permissions.md` § Anti-escalation rules: staff can remove only codes they
  hold (rule 1), and can remove a role from someone only if they hold all of its codes (rule 3, the
  tightened removal guard). Retiring a role removes every one of its codes from every member at once, so a
  staff editor should get 403 (field `is_active`) unless they hold every code the role grants, exactly as the
  restore branch already checks. Renaming a stronger role should follow the same rule. Admins stay
  unlimited.
- **Actual:** only the restore branch is guarded (`if fields.get("is_active") and not role.is_active and
  role_of(by) == "staff"`); retire and rename of any role, including the Supervisor preset or a role holding
  every code, succeed for any staff holding `role.update`.
- **Evidence:** `evidence/F03/tc003-005.txt` (§ TC-005 (S1)).
- **Root cause (Agent 3, fix cycle 1, 2026-10-19):** `access/services.py:update_role` guarded only the
  restore direction of `is_active` (`fields.get("is_active") and not role.is_active`). Retiring was missed:
  it removes every code from every member at once, so it is the same removal that rule 1 and rule 3 of the
  anti-escalation rules already limit for codes and role assignments.
- **Fix:** `update_role` now checks any real flip of `is_active` (retire or restore). A staff editor must hold
  every code the role will grant (the new `permissions` if sent in the same request, otherwise the current
  ones), or the call returns 403 on field `is_active` ("You can only retire/restore a role whose permissions you
  hold yourself."). Sending `is_active` with the value it already has is not a flip and is not checked. Admins
  stay unlimited. No migration and no API shape change. **Rename: no code change, by design.** Renaming changes
  no one's access, and rule 1 already lets staff edit a stronger role's held codes. `docs/features/roles-permissions.md`
  rule 2 now says retire and restore are guarded and rename is not. If the owner wants renaming guarded too, it is
  a one-line follow-up.
- **Regression tests:** `etqan/access/tests/test_roles.py::TestEscalation::test_staff_retire_a_role_only_if_they_hold_all_its_codes`
  (fails before, passes after), `test_staff_retire_a_role_whose_codes_they_hold`, `test_a_no_op_active_flag_is_not_a_retire`,
  `test_admins_retire_any_role`; `etqan/access/tests/test_access_api.py::TestRoles::test_a_staff_editor_retires_only_a_role_whose_codes_it_holds`
  (API 403 on `is_active`, fails before). Evidence: `evidence/F03/fix-cycle-1/qa021-before.txt` (2 failed) and
  `qa021-after.txt` (etqan/access: 2054 passed; ruff clean; lint-imports 54 kept, 0 broken). The 1 remaining
  failure, `test_routes.py::test_every_route_declares_its_code_or_is_named_exempt`, is on the `api/v1/site/admin/*`
  routes from the owner session's uncommitted `etqan/site` work, not from this fix. Tag: REAL (pytest test DB). Agent 2
  still needs to retest live: the F03 fixtures were cleaned up, so Ed and Mo must be reactivated.
- **Retest (Agent 2, retest 1, 2026-10-19T00:29Z, REAL, academy `qa`):** Ed (21) and Mo (22) reactivated, roles 8/9/10
  restored by the admin, fixture passwords set by `tenant_command shell`. Original repro: Ed retire Money (9) → **403**
  `is_active` "You can only retire…", DB `is_active=t`, Mo invoices still 200, Mo `me.permissions` unchanged. Related:
  retire + same perms 403; retire + stripped perms 403 on `permissions`; `"false"` / `0` coercions 403; Ed retire
  Supervisor (1) 403; Ed retires and restores role 10 whose codes he holds 200/200; no-op `is_active:true` 200; admin
  retire/restore 200; old restore guard still 403 for Ed; Ed's cookie on `qaother` 403, qaother roles untouched.
  Regression tests 38 passed (`-k "Escalation or TestRoles"`); `etqan/access` 2054 passed, 1 failed (owner's
  `site/admin/hero-slides` routes, not F03); ruff/format clean, lint-imports 54 kept. Diff review: only the guard
  condition and message changed; no validation weakened, no test special-casing, no boundary change. Playwright F03
  2/2. Evidence `evidence/F03/retest-1/` (`qa021-retest.txt`, `pytest-*.txt`, `ruff-lint.txt`, `playwright.txt`,
  `diff-reviewed.patch`, `code-freeze.txt`, `cleanup.txt`).
- **Rename part (Agent 3: not a bug):** accepted by Agent 2 as **PROPOSAL-accepted (owner approval)**: renaming changes
  no access (verified: Mo's codes unchanged after Ed's rename); residual risk is a misleading label (P3 level), the
  admin can rename back; the spec now documents it. One-line guard available if the owner wants it.
- **Verification status:** VERIFIED (retire/restore guard); rename sub-part PROPOSAL-accepted

## ETQAN-QA-022: Academy and invoice currency accept any three letters (`ZZZ`, `XXX`), not ISO 4217 codes
- **Feature:** F03 Academy settings (`platform/validators.py:clean_currency`), also billing invoice create.
  **Severity:** P3 (API only: the dashboard's currency field is a select; a typo through the API makes every
  new subscription and invoice use a currency that doesn't exist). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F03 TC-016 (spec S2 confirmed).
- **Reproduction steps:**
  1. Admin `PATCH /api/v1/academy/settings/` `{"default_currency":"ZZZ"}` → 200, DB
     `academy_qa.academy_academysettings.default_currency='ZZZ'`; `{"default_currency":"XXX"}` → 200.
  2. Admin `POST /api/v1/billing/invoices/` `{"student":5,"amount_minor":100,"currency":"ZZZ","due_on":"<+7d>",
     "description":"F03 zzz"}` → 201, `billing_invoice.currency='ZZZ'`; `GET /billing/summary/` then lists an
     overdue group `{"currency":"ZZZ",...}`.
- **Expected:** `docs/features/academy-settings.md` § Data model: `default_currency` is "ISO 4217". A code
  outside ISO 4217 (and the non-currency `XXX`) should be a 400 on the field.
- **Actual:** `clean_currency` only checks `^[A-Z]{3}$` after upper-casing; `US`, `USDD`, `U$D`, `123`, `""`,
  `null` are refused, `" usd "` becomes `USD` (fine).
- **Evidence:** `evidence/F03/tc015-016.txt` (currency loop, "explicit ZZZ", overdue summary).
- **Also seen in F05 (Agent 2, 2026-10-19, TC-024 / spec S5):** `TeacherProfile.pay_currency` goes through the same
  `clean_currency`: admin `PATCH /api/v1/people/teachers/118/ {"profile":{"gender":"female","pay_currency":"XXX"}}` → 200 and
  `{"pay_currency":"EGB"}` → 200 (`identity_teacherprofile.pay_currency='EGB'`); `eg`, `EGPP`, `""`, `123` → 400. A typo in a
  teacher's pay currency would only surface in payroll. Evidence `evidence/F05/tc024-025.txt`. No separate ID (same root cause).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-023: Two concurrent partial settings PATCHes lose one of the updates (whole-row save)
- **Feature:** F03 Academy settings (`academy/services.py:update_settings`). **Severity:** P3 (needs two
  saves within milliseconds; the field silently reverts, and some of the fields drive money: invoice due
  days, auto-invoice, consumes-session). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F03 TC-018 (spec S5 confirmed).
- **Reproduction steps:** two admin sessions on `qa`. Reset to horizon 14 / grace 7, then fire in parallel
  `PATCH /api/v1/academy/settings/ {"generation_horizon_days":<h>}` and
  `PATCH /api/v1/academy/settings/ {"renewal_grace_days":<g>}`; read the row. Repeat 20 times.
- **Expected:** both disjoint partial updates persist (a PATCH changes only the fields it sends).
- **Actual:** 20/20 rounds lost one of the two values (e.g. expected `21,2`, got `14,2`; expected `24,5`, got
  `24,7`). `update_settings` loads the row, sets the fields and `save()`s every column, so the later write
  restores the other request's stale value.
- **Evidence:** `evidence/F03/tc018.txt`.
- **Suggested direction (Agent 3 decides):** `save(update_fields=[...changed])` or `select_for_update()`
  inside the transaction.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-024: A staff role editor can retire their own (only) role and lock themselves out
- **Feature:** F03 Roles & permissions (`access/services.py:update_role`). **Severity:** P3 (self-inflicted; no access
  gained, no one else affected; an admin restores it). **Priority:** low
- **Environment:** local docker stack, backend adff9c9 + fix cycle 1, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F03 retest 1 (step 13 of `evidence/F03/retest-1/qa021-retest.txt`).
- **Reproduction steps:** staff Ed (21), whose only role is `F03 Role editor` (8, holds all its codes), sends
  `PATCH /api/v1/access/roles/8/ {"is_active":false}` → 200; Ed now has no codes and cannot restore it.
- **Expected:** `docs/features/roles-permissions.md` rule 5: staff can never change their own roles or deactivate
  themselves. Retiring the role you are a member of is the same self-change; a 403 on `is_active` would match it.
  May be accepted as by design (owner decision).
- **Actual:** 200, the editor loses every code at once.
- **Evidence:** `evidence/F03/retest-1/qa021-retest.txt` (steps 13, 13b).
- **Root cause / Fix / Regression tests:** _Agent 3 (P3: not fixed in lean mode)_
- **Verification status:** OPEN

---

## ETQAN-QA-025: Reversing an already-reversed top-up answers "balance does not cover this" instead of "already refunded"
- **Feature:** F09 Wallet (`wallet/services/ledger.py:reverse_topup`). **Severity:** P3 (wrong refusal reason; no money
  moves, but the office is told to top up instead of being told the top-up is already reversed). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F09 TC-018 step 3 (spec S8 confirmed).
- **Preconditions:** S1 (user 5) EGP wallet holds a 100 000 000 cash top-up (payment 19) plus ~49 505.
- **Reproduction steps:**
  1. Admin `POST /api/v1/wallet/payments/19/reverse/ {}` → 201, entry `reversal -100000000`, payment 19 `refunded`,
     balance 49 505.
  2. Same call again → **409 `{"code":"wallet.insufficient_balance","detail":"The balance does not cover this."}`**.
- **Expected:** `docs/features/wallet.md` § Reverse a top-up and billing's refund rule: a payment that is already
  refunded answers 409 `billing.already_refunded` (as `POST /billing/payments/<id>/refund/` does twice). The status
  check should come before the balance check (`ledger.py:246` reads the balance first).
- **Actual:** 409 `wallet.insufficient_balance` whenever the balance is below the original amount; only a wallet that
  still holds the amount gets `billing.already_refunded`.
- **Evidence:** `evidence/F09/tc018.txt` ("reverse again (balance now < amount) -> S8 probe").
- **Root cause / Fix / Regression tests:** _Agent 3 (P3: not fixed in lean mode)_
- **Verification status:** OPEN

## ETQAN-QA-026: A three-decimal-currency invoice silently loses online payment when the service fee is off
- **Feature:** F09 Online payments (`gateways/services/fees.py:fee_for`). **Severity:** P3 (KWD/BHD/OMR/JOD/TND
  academies only; the family sees no Pay online button and nobody is told why). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`, Stripe test account, `GATEWAYS_SIMULATE`. **Tag:** SIMULATED
- **Found by:** Agent 2, F09 TC-027 (spec S6 confirmed).
- **Reproduction steps:**
  1. Fee on (500 bp): invoice `{"currency":"KWD","amount_minor":12345}` → `can_pay_online:["stripe"]`, checkout
     `amount 12345 + fee 625` = 12 970 (rounded up to a multiple of 10, as documented).
  2. `PATCH /api/v1/gateways/settings/ {"fee":{"enabled":false}}`; a second KWD 12345 invoice →
     **`can_pay_online: []`** (also with `basis_points:0`, and for a payment link with `add_fee=false`).
- **Expected:** `docs/features/online-payments.md` § Service fee: "For three-decimal currencies, the total is rounded
  up to a multiple of 10." The docs never say the provider disappears. Either document the rule (and tell the office
  on the invoice/link form that this amount cannot be paid online) or round the total some other way.
- **Actual:** `fee_for` returns `None` when the fee is 0 and the total isn't a multiple of 10, so `providers_for` drops
  Stripe without a message.
- **Evidence:** `evidence/F09/tc027.txt` ("KWD start", "S6 KWD fee off can_pay_online []").
- **Root cause / Fix / Regression tests:** _Agent 3 (P3: docs or UX decision; not fixed in lean mode)_
- **Verification status:** OPEN

## ETQAN-QA-027: billing.md says an invoice is voided "only when it has no payments", but refunded-only invoices void
- **Feature:** F09 Billing docs (`docs/features/billing.md` line 52 vs `billing/services/rules.py:refuse_if_paid_into`).
  **Severity:** P4 (docs). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F09 TC-007 E4 (spec S1 confirmed).
- **Reproduction steps:** invoice 22 (5000 EGP), pay 5000 cash, `POST /api/v1/billing/payments/<id>/refund/` → 200;
  `POST /api/v1/billing/invoices/22/void/` → **200 `status=void`**.
- **Expected:** the product follows billing.md line 83 ("A refunded payment stops counting"), so the behaviour is
  right; line 52 ("only when the invoice has no payments") should read "no completed payments".
- **Actual:** docs contradict themselves; code voids an invoice whose payments are all refunded/credited.
- **Evidence:** `evidence/F09/tc007.txt` ("void 22 200").
- **Root cause / Fix / Regression tests:** _Agent 3 (docs only)_
- **Verification status:** OPEN

## ETQAN-QA-028: Payment-link tokens are 22 characters, docs say 32
- **Feature:** F09 Payment links (`gateways/services/links.py:225` `secrets.token_urlsafe(16)`). **Severity:** P4 (docs;
  128 bits of entropy is enough). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F09 TC-025.
- **Reproduction steps:** `POST /api/v1/gateways/links/ {"kind":"payment","title":"Registration fee","student":5,
  "provider":"stripe","amount_minor":25000,"add_fee":true}` → `url .../app/pay/link/CFQfOhgO917UhPs61Ez-Tw` (22 chars).
- **Expected:** `docs/features/online-payments.md` § Data model: "single-use link with a 32-character token".
- **Actual:** 22-character URL-safe token. Fix the docs (or use `token_urlsafe(24)` if 32 was intended).
- **Evidence:** `evidence/F09/tc025.txt` ("tokens 22 … 22").
- **Root cause / Fix / Regression tests:** _Agent 3 (docs only)_
- **Verification status:** OPEN

## ETQAN-QA-029: A payslip can be marked paid on any past date, booking the salary expense into a closed period
- **Feature:** F10 Payroll, payment (`payroll/services/payslips.py:_pay`, `salary_expenses.post_salary`). **Severity:** P2
  (financial reporting: a salary lands in a month that is already closed, even before the month it pays). **Priority:** medium
- **Environment:** local docker stack, backend adff9c9, academy `qa` (EGP, Africa/Cairo), switches `salary_expenses` + `expenses` on. **Tag:** REAL
- **Found by:** Agent 2, F10 TC-018 (spec suspected defect S1).
- **Preconditions:** teacher T7 (user 41) with a 6000 EGP/h rate and one completed 60-minute session on 2026-09-15.
- **Reproduction steps:**
  1. `POST /api/v1/payroll/payslips/generate/ {"year":2026,"month":9}`, then `POST /api/v1/payroll/payslips/4/issue/` on 2026-10-19 → 200, issued.
  2. `POST /api/v1/payroll/payslips/4/mark-paid/ {"paid_on":"2026-01-01","notes":"S1"}`.
- **Expected:** `paid_on` is refused (400 on `paid_on`) when it is before the payslip was issued (and so before the month it pays
  was over), the same way a withdrawal's `paid_on` must fall "between the request day and today" (`docs/features/payroll.md`
  § Withdrawals; `B4c` spec). `docs/features/payroll.md` § Lifecycle says only "`paid_on` can't be in the future", and the
  expense it posts uses `paid_on` as `spent_on`, so a lower bound is needed to keep finance periods correct.
- **Actual:** 200 `{"status":"paid","paid_on":"2026-01-01"}` and `finance_expense` row id 3 `salaries 6000 EGP spent_on 2026-01-01`
  (title "... إيصال PAY-000004"): a September 2026 salary is booked in January 2026.
- **Evidence:** `evidence/F10/tc018.txt` ("S1 backdated ... 200", "S1 expense 4|6000|EGP|2026-01-01"), `evidence/F10/tc028.txt`
  (CSV row PAY-000004 paid on 2026-01-01).
- **Root cause:** `payroll/services/payslips.py:_pay` (shared by `mark_paid` and `pay_to_balance`) checked only the upper bound
  (`paid_on > clock.today()`); no lower bound existed in code or spec (`docs/features/payroll.md` § Lifecycle, payroll spec §4.4,
  B4c C-1), and `salary_expenses.post_salary` books `spent_on = paid_on`, so any past date became the expense's period.
- **Fix (Agent 3, cycle 1, 2026-10-19):** `_pay` now also refuses `paid_on` before the first day of the payslip's own month
  (`rules.month_bounds(year, month)[0]`, academy calendar) with 400 on `paid_on` "A payslip can't be paid before the month it pays."
  Applies to mark-paid and pay-to-balance; raised before any write, so no expense is posted. Bound chosen deliberately as the month
  start, not the issue day suggested above: payslips can only be issued after the month ends, and payments are routinely recorded
  after the fact (the existing suite pays a June payslip on 30 June before issuing it on 1 July, `test_pay_to_balance.PAID_ON`), so
  an issue-day bound would force the office to misdate real cash payments. The month-start bound still blocks the reported case
  (a Sept salary booked in Jan) and any booking into a period before the one the salary pays. No migration, no API shape change.
  Docs: `docs/features/payroll.md` § Lifecycle updated. Dashboard date picker not changed (server is authoritative).
- **Regression tests:** `etqan/payroll/tests/test_pay_to_balance.py::test_a_payslip_is_not_paid_before_the_month_it_pays[mark_paid|pay_to_balance]`
  (31 May and 1 Jan refused for a June payslip, status stays issued, no expense; 1 June accepted and expense `spent_on` 1 June);
  `test_api.py::test_refusals_are_coded_409s_and_field_400s` (mark-paid `2026-05-31` → 400 `paid_on`). Fail before (3 failed) /
  pass after (3 passed); payroll+finance 582 passed; ruff clean; lint-imports 54 kept 0 broken.
  Evidence: `evidence/F10/fix-cycle-1/ETQAN-QA-029-{before,after,live}.txt`, `ETQAN-QA-029.diff`, `pytest-payroll-finance.txt`,
  `ruff.txt`, `lint-imports.txt`. Live (REAL): payslip 13 (Jul 2026, issued) mark-paid 2026-01-01 and 2026-06-30 → 400, still issued.
- **Verification status:** VERIFIED (Agent 2, retest 1, 2026-10-19, REAL). Original repro on issued Aug payslip 19:
  mark-paid `2026-01-01` + notes S1 → 400 `paid_on` "A payslip can't be paid before the month it pays.", DB still issued, 0
  expenses; 07-31 → 400; tomorrow → 400 (future rule intact); 08-01 → 200, expense `6000|EGP|2026-08-01`; repeat → 409.
  Pay-to-balance on July payslip 24: 06-30 and 01-01 → 400, balance unchanged; 07-01 → 200, `paid_to_balance`, expense
  `4000|EGP|2026-07-01`, balance 4000. Payslip 13 paid today → expense today. UI (Playwright, REAL): Mark paid dialog with
  2026-01-31 shows the field error and the payslip stays issued; 2026-02-01 → "Payslip marked paid.", DB PAY-000038
  paid 2026-02-01 + expense 6000 EGP 2026-02-01. Regression tests 3 passed; `pytest etqan/payroll etqan/finance` 582 passed;
  ruff + format clean; lint-imports 54 kept. Diff limited to `payslips.py` + 2 test files (+ docs Lifecycle line); no weakened
  validation, no test special-casing. Month-start bound (instead of issue day) accepted: it blocks every booking into a period
  before the one the salary pays and keeps after-the-fact cash dates valid. Evidence `evidence/F10/retest-1/`.

## ETQAN-QA-030: No upper bound on payroll money inputs; one teacher's oversized rate makes Generate fail for the whole month
- **Feature:** F10 Payroll, rates / adjustments / fixed salaries / generate (`payroll/api/serializers.py` money fields set only
  `min_value`; `services/payslips.py:generate`). **Severity:** P3 (needs an absurd value, but then the month cannot be generated
  for anyone and the error does not say who). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F10 TC-029 (spec suspected defect S2).
- **Reproduction steps:**
  1. `POST /api/v1/payroll/rates/ {"teacher":48,"hourly_rate_minor":9223372036854775807}` → 201 (also 201 for
     `adjustments` `amount_minor` and `fixed-salaries` `monthly_minor` at int64 max).
  2. Teacher 48 (T14) has two completed 60-minute April 2026 sessions; teacher 47 (T13) has one completed April session at 6000/h.
  3. `POST /api/v1/payroll/payslips/generate/ {"year":2026,"month":4}`.
- **Expected:** money inputs have a sane upper bound (400 on the field at entry), and generate never fails for every teacher
  because of one teacher's numbers; at worst it names the teacher. `CLAUDE.md` "Money is integer minor units" and the F10 spec
  (TC-029: "a 500 (DB overflow) is a defect"; "error body names a field").
- **Actual:** generate → 400 `{"gross_minor":["Ensure this value is less than or equal to 9223372036854775807."]}`; no draft is
  created or rebuilt for anyone that month (T13's April draft missing, `select count(*) from payroll_payslip where teacher_id=14
  and month=4` = 0). Fixed salary int64 max → 400 on `net_minor`; plus a max bonus → 400 on `bonuses_minor`. No 500, no partial rows.
- **Evidence:** `evidence/F10/tc029.txt` (TC-029 and TC-029b blocks).
- **Root cause / Fix / Regression tests:** _Agent 3_ (suggested: `max_value` on every payroll money field, e.g. 10^12 minor units).
- **Verification status:** OPEN

## ETQAN-QA-031: No "Request cancelled." confirmation after a teacher cancels a withdrawal
- **Feature:** F10 Payroll dashboard, My balance (`dashboard/src/features/payroll/CancelWithdrawal.tsx`, `MyBalance.tsx:121`).
  **Severity:** P4 (cosmetic; the cancel itself works). **Priority:** low
- **Environment:** local docker stack, dashboard 5ed775d (branch qa/campaign-2026-10), Chromium (Playwright 1.62.1), locale en. **Tag:** REAL
- **Found by:** Agent 2, F10 TC-026 (Playwright `e2e/qa/f10-payroll.spec.ts`).
- **Reproduction steps:** sign in as `qa-teacher@qa.etqan.test`, open `/app/teaching/balance`, Request a withdrawal of 10.00,
  then Cancel request → Cancel this request.
- **Expected:** the success toast `payroll.withdrawals.cancelled` ("Request cancelled.") shows, as the code asks
  (`CancelWithdrawal.tsx` `onSuccess` toast), like every other payroll action.
- **Actual:** the request becomes Cancelled (API `status: cancelled`, DB row 13), but no toast appears within 4 s. Likely cause: the
  per-call `mutate(..., {onSuccess})` callback is dropped because the row stops being `under_review` and `CancelWithdrawal`
  unmounts after the hook's `invalidateQueries` refetch, before the per-call callback runs (TanStack Query skips per-call callbacks
  of an unmounted observer). The office's row actions may behave the same.
- **Evidence:** `evidence/F10/pw/tc026-cancel-toast.json` (`toastSeen: false`), `evidence/F10/pw/tc026-balance.png`,
  `evidence/F10/pw-run5.txt`; earlier runs `pw-run3.txt`/`pw-run4.txt` (assertion on the toast failed while the DB row was cancelled).
- **Root cause / Fix / Regression tests:** _Agent 3_ (suggested: show the toast from the hook-level `onSuccess`, or keep the
  confirm mounted until it settles).
- **Verification status:** OPEN

## ETQAN-QA-032: Two simultaneous saves of the same email (create or edit a person) return HTTP 500
- **Feature:** F05 People (`identity/services.py` `_build_person` / `update_person`: `_email_taken` pre-check, then `user.save()`
  with no `IntegrityError` handling). **Severity:** P2 (a double-submitted Save, two office users or a retried request get a 500
  instead of the field error; data stays correct thanks to the unique indexes). **Priority:** medium
- **Environment:** local docker stack, backend adff9c9 (branch qa/campaign-2026-10), academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F05 TC-023 (spec S1 confirmed).
- **Preconditions:** admin session on `qa` (`qa-admin@qa.etqan.test`).
- **Reproduction steps:**
  1. Fire 5 parallel `POST /api/v1/people/students/` with `{"user":{"full_name":"QA5 RaceC <n>","email":"f05-racec1@qa.etqan.test"},"profile":{}}`
     (same CSRF session; script `evidence/F05/scripts/race.sh`: 5 background curls).
  2. Fire 2 parallel `PATCH /api/v1/people/students/<a>/` and `/<b>/` with `{"user":{"email":"f05-racep1@qa.etqan.test"}}` (two different people).
- **Expected:** exactly one 201/200; every other request 400 `{"user":{"email":["This email is already in use."]}}` (the
  sequential behaviour, `docs/features/people.md` § Rules "Duplicate check"; tags already map `IntegrityError` to a 400).
- **Actual:** create race: 1×201 + **4×500**, three rounds out of three; edit race: 1×200 + **1×500**, three rounds out of three. Django log:
  `IntegrityError: duplicate key value violates unique constraint "identity_user_email_key"` at `PATCH /api/v1/people/students/102/`.
  DB stays consistent: one `identity_user` row per email, no orphan profile/`account_emailaddress` rows, one invite mail.
- **Evidence:** `evidence/F05/tc023-race.txt`, `evidence/F05/tc020-023.txt` (first PATCH race, `95 500`).
- **Expected behaviour confirmed:** `docs/features/people.md` § Rules 1 ("Duplicate emails are refused") and the sequential
  `_email_taken` path both say the loser gets the 400 field error; a 500 is a defect, not product intent. No spec change needed.
- **Root cause (Agent 3, 2026-10-19):** `_email_taken` is a read-only pre-check. Two requests for one address both pass it
  (READ COMMITTED, neither row committed yet), both `INSERT`/`UPDATE identity_user`; the second blocks on the unique index
  until the first commits, then raises `IntegrityError` (`identity_user_email_key` / `identity_user_email_ci_unique`), which
  nothing in `_build_person` or `change_person_email` (never-signed-in branch) caught, so it reached DRF as a 500.
  (The signed-in branch only adds an unverified non-primary `EmailAddress`, which has no unique index, so it cannot hit this.)
- **Fix (FIXED-UNVERIFIED, no migration, no API change):** `backend/etqan/identity/services.py` new `_save_claiming_email(user,
  address, update_fields=...)`: the user save runs in a savepoint; on `IntegrityError` it re-runs `_email_taken(address,
  exclude_user_id=user.pk)` and, if the address is now taken, raises the same `ValidationError("This email is already in use.",
  field="email")`; any other integrity error is re-raised unchanged (same pattern as `_save_tag`). Used by `_build_person`
  (create + self-registration) when an address is given, and by `change_person_email`'s replace branch.
- **Regression tests:** `etqan/identity/tests/test_people_services.py::TestConcurrentEmailClaim` (create + edit; the race is
  made deterministic by letting the pre-check miss once — exactly what the losing request sees). Before the fix: 2 failed with
  `IntegrityError identity_user_email_ci_unique` / `identity_user_email_key` (`evidence/F05/fix-cycle-1/qa032-before.txt`);
  after: identity suite 863 passed (`qa032-after-pytest-identity.txt`); ruff clean, lint-imports 54 kept / 0 broken
  (`qa032-ruff-lint-imports.txt`). API replay of the reporter's race (2 rounds × 5 parallel POST, 3 rounds × 2 parallel PATCH):
  exactly one 201/200 each round, all others 400 `{"user":{"email":["This email is already in use."]}}`, 0 IntegrityError lines
  in the django log (`qa032-api-race.txt`, REAL; whether each 400 came from the pre-check or the new catch is not observable).
- **Verification status:** **VERIFIED** (Agent 2, F05 retest 1, 2026-10-19T04:34Z–04:37Z). Original repro rerun as filed, REAL:
  3 rounds × 5 parallel `POST people/students/` → 1×201 + 4×400 `{"user":{"email":["This email is already in use."]}}` each round,
  1 row per address; a mixed-case variant (`F05-RT-CI@QA.ETQAN.TEST` vs lower) → 1×201 + 4×400, 1 row; 3 rounds × 2 parallel `PATCH`
  of two never-signed-in people → 1×200 + 1×400, loser keeps its own primary `EmailAddress`. 0 IntegrityError/500 lines in the django
  log, while postgres logged 19 unique violations (17 `identity_user_email_key`, 2 `identity_user_email_ci_unique`), so every loser
  reached the index and was caught by the new savepoint path, not only by the pre-check. One invite mail per address. Sequential
  duplicates (student create, student edit, teacher create, upper-case) still 400; valid create/edit/email-less create still 201/200.
  Regression tests 2/2 pass; with `_save_claiming_email` swapped in memory for a plain `user.save` both fail with the reported
  IntegrityError (tests catch the bug, no file changed). `pytest etqan/identity etqan/employment` 890 passed (888 + 2); ruff + format
  clean; lint-imports 54 kept / 0 broken; Playwright `e2e/qa/f05-people.spec.ts` 3/3. Diff review: only `_save_claiming_email` and
  its two call sites (the `_validate_new_password` hunks in the same file are the F02 QA-018 fix); validation not weakened (the
  pre-check stays, non-email integrity errors are re-raised), no test special-casing, no migration/API change, inside identity.
  Tenant check: the same address in `qaother` is still free (1×201 + 3×400 there, `qa` untouched). Residual found by the gate:
  ETQAN-QA-038 (P3). Evidence `evidence/F05/retest-1/` (`qa032-api-repro.txt`, `qa032-regression-tests.txt`,
  `pytest-identity-employment.txt`, `ruff-lint-imports.txt`, `playwright.txt`, `gate-checks.txt`).

## ETQAN-QA-033: Students can be added to a retired family (bulk "Add to family" and family edit)
- **Feature:** F05 People, families (`identity/services.py:bulk_family` loads `Family.objects.filter(pk=...)` with no `is_active` check;
  the family `PATCH student_ids` path behaves the same). **Severity:** P3 (the dashboard's family picker is the main guard; through
  the API a student silently joins a family that supplies no payer, and is then blocked from joining an active family as
  "already in another family"). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F05 TC-007 (spec S2 confirmed).
- **Reproduction steps:**
  1. `POST /api/v1/people/families/ {"name":"QA5 Retired Fam","student_ids":[76],"payer_id":76}` → 201 (id 4); `PATCH /api/v1/people/families/4/ {"is_active":false}`.
  2. `POST /api/v1/people/students/bulk/ {"ids":[74,75],"action":"add_to_family","family_id":4}` → 200 `{"updated":2,"skipped":[]}`.
  3. `PATCH /api/v1/people/families/4/ {"student_ids":[76,77]}` → 200 on the retired family.
- **Expected:** `docs/features/people.md` § Data model: "retired families keep their students but supply no payer" — a retired
  family is closed; adding new students to it should be refused (400 `family_id` "Choose a family from the list."), as the
  dashboard only offers active families.
- **Actual:** both calls succeed; `identity_studentprofile.family_id=4` for 74, 75; `services.family_payer(74)` → `None`.
- **Evidence:** `evidence/F05/tc006b-007.txt` (S2 block), `evidence/F05/tc007b-008.txt`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-034: Deactivating a person does not revoke their invite/reset link; a reset still sets the password and verifies the email
- **Feature:** F05 People / F02 password reset (`identity` `confirm_password_reset`, `deactivate_person`). **Severity:** P3 (the account
  stays inactive and cannot sign in; but whoever holds an old invite link chooses the password that will be live the moment an
  admin reactivates the account, and the forgot-password flow mails a reset link to deactivated accounts). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`, Mailpit. **Tag:** REAL
- **Found by:** Agent 2, F05 TC-012 / TC-027 (spec S6 confirmed).
- **Reproduction steps:**
  1. Admin creates student `f05-invd@qa.etqan.test` (id 130, invite mailed), then `POST /api/v1/people/students/130/deactivate/` → 200.
  2. Anonymous `POST /api/v1/identity/password/reset/confirm/` with the uid/token from the invite mail and a strong password → **200**.
  3. DB: `is_active=false`, password now usable, `account_emailaddress.verified=true`. Sign-in → 400 "Invalid credentials.".
  4. Deactivate the signed-in student 114, anonymous `POST /api/v1/identity/password/reset/ {"email":"f05-pend@qa.etqan.test"}` → 200 and a
     new reset mail arrives in Mailpit (1 → 2 messages).
- **Expected:** a deactivated account's outstanding invite/reset links stop working (400 "Invalid or expired reset link."), and
  forgot-password sends nothing to an inactive account; sign-in already refuses them (`docs/features/sign-in.md` step 1 "The
  account is active").
- **Actual:** as above; no activation side effect (the account stays inactive).
- **Evidence:** `evidence/F05/tc011-012-027.txt` (TC-012 block).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-035: Student and teacher date of birth accept the future and year 0001
- **Feature:** F05 People (`StudentProfile.date_of_birth`, no range validator; `TeacherProfile.date_of_birth` has the same field but was not exercised). **Severity:** P3
  (a typo such as 2030 makes the student a "child" in age filters and reports). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F05 TC-024 (spec S7 confirmed).
- **Reproduction steps:** `PATCH /api/v1/people/students/103/ {"profile":{"date_of_birth":"2030-01-01"}}` → 200, `age_group:"child"`;
  `{"profile":{"date_of_birth":"0001-01-01"}}` → 200. (`2012-02-30` → 400, correct.)
- **Expected:** a date of birth in the future (by the academy's today) or implausibly old is a 400 on `profile.date_of_birth`.
- **Actual:** both stored; `default_meeting_url` part of S7 is **refuted** (`javascript:` and >200 chars are 400).
- **Evidence:** `evidence/F05/tc024-025.txt`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-036: A contract upload named `.docx` is accepted for any ZIP file
- **Feature:** F05 Contracts (`platform/uploads.py` signature check: first bytes `PK` only). **Severity:** P3 (files are private,
  served as attachments with `nosniff`; impact is a wrong file type on record). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`, `contracts` on. **Tag:** REAL
- **Found by:** Agent 2, F05 TC-021 (spec S8 confirmed).
- **Reproduction steps:** build a ZIP containing only `hello.txt`, name it `notdocx.docx`; admin multipart
  `POST /api/v1/contracts/ teacher=7 reference=S8 file=@notdocx.docx` → 201 `has_file:true` (contract 2; deleted afterwards).
- **Expected:** `contracts.accepted` says "PDF, Word (.docx) or an image"; a `.docx` without `[Content_Types].xml`/`word/` should be
  400 "The file's content does not match its type." like a text file renamed `.pdf` (which is refused).
- **Actual:** accepted.
- **Evidence:** `evidence/F05/tc021.txt` (S8 block).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-037: People API minor inconsistencies: lower-case `country` filter finds nothing; re-invite of a deactivated person gives the wrong reason
- **Feature:** F05 People (`identity/api/people_filters.py:_student_filters`; `services.resend_invite`). **Severity:** P4 (API only;
  the dashboard sends upper-case country codes from a select, and the re-invite button is hidden for inactive people). **Priority:** low
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F05 TC-008 and TC-012 (spec S10 confirmed).
- **Reproduction steps:**
  1. `GET /api/v1/people/students/?country=eg` → `count: 0`; `?country=EG` → `count: 64` (writes upper-case `eg` → `EG`).
  2. Invite student 130, deactivate it, `POST /api/v1/people/students/130/invite/` → 400 `{"email":["Only someone who has not set a
     password yet can be re-invited."]}` although the person never set a password.
- **Expected:** (1) the filter normalises like the write path (`docs/features/people.md` lists `country` as a filter); (2) the
  message names the real reason (the account is deactivated).
- **Actual:** as above.
- **Evidence:** `evidence/F05/tc007b-008.txt` (`country=eg -> 0 0  SQL 64`), `evidence/F05/tc011-012-027.txt` (TC-012 invite 400).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-038: Two parallel email changes of signed-in people to one address leave the loser with a dead "pending" email
- **Feature:** F05 People (`identity/services.py` `change_person_email`, signed-in branch: `_email_taken` pre-check, then an unverified
  non-primary `EmailAddress`, which has no unique index). **Severity:** P3 (no 500 and no duplicate account: the second confirmation is
  refused; the loser only keeps a stale `pending_email` that can never be confirmed). **Priority:** low
- **Environment:** local docker stack, backend adff9c9 + QA-032 fix, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F05 retest 1 gate check G2.
- **Reproduction steps:** students 74 and 75 (usable passwords) — 2 parallel `PATCH people/students/<id>/` with
  `{"user":{"email":"f05-rt-pend2@qa.etqan.test"}}`; then `POST identity/verify-email/` with each of the 2 mailed keys.
- **Expected:** as sequentially: the second change is refused with the email field error, or its pending address is dropped when the
  first one is confirmed.
- **Actual:** both PATCH 200, two pending `EmailAddress` rows and two confirmation mails; first key 200 (74 promoted), second key 400
  "Invalid or expired verification key."; 75 keeps `pending_email=f05-rt-pend2@qa.etqan.test` indefinitely. 0 500s.
- **Evidence:** `evidence/F05/retest-1/gate-checks.txt` (G2).
- **Root cause / Fix / Regression tests:** _Agent 3_ (likely: clear other users' pending rows for the address on promotion)
- **Verification status:** OPEN

## ETQAN-QA-039: An early renewal over a marked session creates a second lesson for the same student, teacher and time
- **Feature:** F06 Catalogue, subscriptions & scheduling (`scheduling/services/subscriptions.py` `renew_subscription`, `generation`).
  **Severity:** P2 (duplicate lesson in the schedule; if the office marks both, the student consumes 2 sessions and the teacher is paid
  twice; no conflict is reported, so the owner gets no signal). **Priority:** high
- **Environment:** local docker stack, backend adff9c9, academy `qa` (Africa/Cairo), 2026-10-19. **Tag:** REAL
- **Found by:** Agent 2, F06 TC-015 (suspected defect S3 confirmed).
- **Preconditions:** subscription A (QA6 Student 3 / QA teacher / QA6 Arabic / package 3, slot Mon 06:00, `starts_on` 2026-10-05), its
  2026-10-19 06:00 session (id 121) marked present/present (status `completed`).
- **Reproduction steps:** `POST /api/v1/subscriptions/27/renew/ {"starts_on":"2026-10-19"}` (201, renewal 28), then
  `POST /schedule/generate/ {"from":"2026-10-19","to":"2026-11-02","subscription":28}`; query
  `select occurs_on,starts_at,student_id,teacher_id,count(*) from academy_qa.scheduling_session where status<>'cancelled' group by 1,2,3,4 having count(*)>1`.
- **Expected:** one lesson per student, teacher and time. Docs (`docs/features/subscriptions.md` §5 Renew): "The old subscription's
  untouched sessions from the renewal start go now"; generation for the old term stops the day before the renewal: the renewal should
  not add a lesson on a date and time the old term already delivered (or the clash must at least be reported, P4-9).
- **Actual:** two sessions at 2026-10-19 06:00 for the same student and teacher: 27/completed/present (kept, as it is marked) and
  28/scheduled/not_set (created by the renewal; a past-dated, markable lesson). The renew response and generate report `conflicts: []`.
- **Evidence:** `evidence/F06/tc015.txt`, script `evidence/F06/scripts/t15.sh`.
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-19):**
  - **Expected behaviour checked first: the duplicate is the documented design.** B2b spec §10
    (`docs/superpowers/specs/2026-10-03-b2b-times-postponement-design.md`): a marked old lesson on or after the renewal's
    start "is kept, and the renewal also generates that date (as B2a does for marked generated sessions)". Two existing
    tests assert it: `test_renewal.py::test_old_untouched_sessions_from_the_new_start_are_removed` (marked 8 June kept on
    the old one AND generated on the renewal) and `test_today.py::test_a_session_always_shows_even_after_its_renewal_took_over`.
    A skip-the-date prototype broke exactly those two tests, so it was reverted: changing the design is an owner decision
    (coverage-gaps Proposals). The F06 spec TC-015 expectation is corrected.
  - **The real defect was the missing signal**, which the docs do require (P4-9): fixed through ETQAN-QA-042. The renew
    201 answer now lists the overlap (renewal session vs the kept old one, same teacher) in `conflicts`.
  - **Regression test:** `etqan/scheduling/tests/test_generation_guards.py::test_a_renewal_over_a_kept_lesson_reports_the_overlap`
    (fails before: no `conflicts` key; passes after).
  - **Evidence:** `evidence/F06/fix-cycle-1/` (`fix.diff`, `dashboard-fix.diff`, `regression-before.txt` 9 failed, `regression-after.txt` 9 passed, `pytest-scheduling-catalogue.txt` 1460 passed, `ruff.txt`, `lint-imports.txt` 54 kept, `dashboard-*.txt`).
- **Retest 1 (Agent 2, 2026-10-19 ~16:27Z, REAL):** original repro on fresh data (sub 77, student 215 / teacher 7, Mon 05:00
  from 2026-10-05; 10-19 session 222 marked present/present; `POST /subscriptions/77/renew/ {"starts_on":"2026-10-19"}` → 201,
  renewal 78). The duplicate still exists (77 completed/present + 78 scheduled/not_set at 2026-10-19 05:00), and the renew answer
  now carries `conflicts` with exactly that pair (session 227 vs other 222). Agent 2 read B2b spec line 193 itself ("is kept, and the
  renewal also generates that date"): the duplicate is the documented design, so Agent 3's NOT_A_BUG verdict is accepted. Remaining
  risk (accepted as owner PROPOSAL): if the office marks both lessons the student consumes 2 sessions and the teacher is paid twice;
  the signal is in the API answer only (dashboard display = ETQAN-QA-043, P3). Evidence `evidence/F06/retest-1/` `r1-api-db.txt`.
- **Verification status:** NOT_A_BUG accepted (by design, B2b §10) + overlap reporting VERIFIED via ETQAN-QA-042; design change
  PROPOSAL-accepted (owner decision). Verified by Agent 2, retest 1.

## ETQAN-QA-040: A deactivated teacher or student keeps getting new sessions from the hourly job
- **Feature:** F06 (`scheduling/services/generation.py` `_lock_live` / `generate_horizon`; `identity.services.deactivate`).
  **Severity:** P2 (the Today board and calendars fill with lessons for people who left; the teacher's payroll counts depend on the
  office not marking them). **Priority:** medium
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F06 TC-017 (suspected defect S2 confirmed).
- **Preconditions:** subscription 34 (QA6 Student 2 user 213 / QA6 Teacher C user 218, slot every day 10:00, from 2026-10-19), 15 sessions.
- **Reproduction steps:** `POST /people/teachers/218/deactivate/` and `POST /people/students/213/deactivate/` (both 200,
  `is_active=false`); remove 2 future untouched sessions (2026-10-25, 2026-10-26) so the horizon has gaps; run the hourly job
  (`tenant_command shell --schema=academy_qa -c "from etqan.scheduling.services import run_lifecycle; print(run_lifecycle())"`).
- **Expected:** an inactive person gets no new sessions (the product already refuses them on create and renew: "Choose an active
  teacher." / "Choose an active student."), or the owner is told. The intent isn't written in `docs/features/people.md`
  (deactivate = sign-out only), so Agent 3 must confirm it with the owner before fixing.
- **Actual:** `run_lifecycle` → `{'created': 2}`; both sessions are re-created after the deactivation timestamp for the inactive teacher
  and student, and the subscription's rows show on `GET /schedule/today/` (Teacher C listed). Create and renew with them → 400 (correct).
- **Evidence:** `evidence/F06/tc017.txt`, script `evidence/F06/scripts/t17.sh`. Both people were re-activated afterwards (`tc018.txt`).
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-19):**
  - **Intent:** not written for deactivation (people.md: sign-out only), but the code's intent is consistent everywhere
    else: create, renew and a hand-added regular session refuse an inactive student/teacher (B2a spec §A-6 "Student
    inactive: 400"). Implemented that rule for generation; **owner confirmation still requested** (coverage-gaps).
  - **Root cause:** `generation._lock_live` / `generate` select subscriptions by status and schedule state only; nothing
    reads `User.is_active`. The Today board lists every active slot that "would generate" the same way.
  - **Fix (no migration, additive API):** `rules.person_inactive(sub, day)` — student inactive, or the date's teacher
    (the substitute's inside a substitution, G-5) inactive. `generation.generate` skips those dates into a new
    `skipped_inactive` count (also in the `/schedule/generate/` answer); `board.today_board` drops the *missing* row for
    them (an existing session still shows). Existing sessions are not deleted; reactivating fills the horizon again.
    Board queries stay constant (one prefetch of substitutions).
  - **Regression tests** (`test_generation_guards.py`): `test_the_job_gives_a_deactivated_teacher_no_new_sessions`,
    `..._deactivated_student_...` (via `run_lifecycle`), `test_an_active_substitute_still_covers_a_deactivated_teacher`,
    `test_the_today_board_leaves_out_a_deactivated_persons_missing_row`, `test_reactivating_fills_the_horizon_again`;
    all fail before, pass after.
  - **Evidence:** `evidence/F06/fix-cycle-1/` (`fix.diff`, `dashboard-fix.diff`, `regression-before.txt` 9 failed, `regression-after.txt` 9 passed, `pytest-scheduling-catalogue.txt` 1460 passed, `ruff.txt`, `lint-imports.txt` 54 kept, `dashboard-*.txt`).
- **Retest 1 (Agent 2, 2026-10-19 ~16:28Z, REAL):** original repro (sub 34, teacher 218 + student 213 deactivated, 3 untouched
  sessions 10-19/10-27/10-28 removed, `run_lifecycle`): job `created: 0`; scoped `POST /schedule/generate/` → `created 0,
  skipped_inactive 3`; 0 sessions created after the deactivation instant (DB); Today board 0 rows for sub 34 while inactive;
  renew still 400 "Choose an active student.". Teacher-only inactive (student re-activated): still skipped 3. Teacher re-activated:
  board shows the `missing` row again and generate refills exactly 10-19, 10-27, 10-28 (`created 3`). Regression tests 9/9, scoped
  pytest 1502 passed. Diff limited to `rules.person_inactive` + 2 call sites + additive `skipped_inactive` key; no validation
  weakened, no special-casing, board queries constant (substitutions prefetched, users select_related). Intent still for the owner
  to confirm (coverage-gaps Proposals); the reversal path is documented. Evidence `evidence/F06/retest-1/` `r1-api-db.txt`, `regression-tests.txt`.
- **Verification status:** VERIFIED (Agent 2, retest 1, 2026-10-19); owner intent confirmation pending (documented, reversible)

## ETQAN-QA-041: Changing the academy timezone leaves existing sessions at the old instant: one weekly slot shows two local times
- **Feature:** F06 / academy settings (`academy/services.update_settings`, `scheduling/services/generation.py`, `dates.to_utc`).
  **Severity:** P2 (an academy that fixes a wrong timezone, the realistic case on day one, gets every already-generated lesson hours
  off while new ones are right; no warning). **Priority:** medium
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F06 TC-012 (suspected defect S1 confirmed).
- **Preconditions:** subscription 23 (QA6 Student 3 / QA6 Teacher B, slot Mon 18:00), sessions to 2026-11-23 generated at 18:00 Cairo
  (15:00Z / 16:00Z).
- **Reproduction steps:** `PATCH /academy/settings/ {"timezone":"America/New_York"}` (200, no warning field), run `run_lifecycle`,
  `POST /subscriptions/23/renew/ {}` (renewal 26), `POST /schedule/generate/ {"from":"2026-10-19","to":"2026-12-14","subscription":26}`.
- **Expected:** `ScheduleSlot.start_time` is "on the academy's wall clock" (`docs/features/subscriptions.md` Concepts), so after the
  change the slot's untouched future sessions should be at 18:00 New York (re-anchored), or the owner must be warned that existing
  sessions keep their time.
- **Actual:** existing sessions stay at 16:00Z = 11:00 New York; the renewal's new sessions are 23:00Z = 18:00 New York. The same
  Monday 18:00 slot chain shows 11:00 and 18:00. Nothing recalculates `starts_at`; generate skips existing (slot, date).
- **Evidence:** `evidence/F06/tc012.txt`, script `evidence/F06/scripts/t12.sh`. Timezone restored to Africa/Cairo.
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-19):**
  - **Root cause:** `Session.starts_at` is resolved once (`generation._new_session`, `dates.to_utc(day, start_time,
    academy.timezone)`) and nothing recomputes it when `AcademySettings.timezone` changes; `academy.services.update_settings`
    cannot reach scheduling (lint-imports: "academy imports no other business module"). Docs promise slot times on the
    academy's wall clock, so the behaviour is a gap.
  - **Not implemented (PROPOSAL):** re-anchoring needs a new cross-app seam and replaces session ids (Zoom links,
    reminders); see coverage-gaps Proposals.
  - **Mitigation implemented (no API change):** `dashboard/src/features/academy/AcademySettingsForm.tsx` shows a warning
    (`academySettings.timezoneChangeWarning`, ar/en/es) while a timezone other than the saved one is selected: existing
    lessons keep their time, only lessons created after saving use the new zone. Doc: `docs/features/academy-settings.md`.
  - **Regression test:** `AcademySettingsForm.test.tsx` "warns that existing lessons keep their time when the time zone
    changes" (fails before, passes after; biome + tsc clean).
  - **Evidence:** `evidence/F06/fix-cycle-1/` (`fix.diff`, `dashboard-fix.diff`, `regression-before.txt` 9 failed, `regression-after.txt` 9 passed, `pytest-scheduling-catalogue.txt` 1460 passed, `ruff.txt`, `lint-imports.txt` 54 kept, `dashboard-*.txt`).
- **Retest 1 (Agent 2, 2026-10-19, REAL UI):** mitigation verified on the live stack: `e2e/qa/f06-retest1.spec.ts` (settings page,
  select Asia/Riyadh → `role=status` warning "…keep their current time…", back to Africa/Cairo → gone, nothing saved, no 5xx) 1/1;
  screenshot `qa041-warning.png`; vitest `src/features/academy` 14 passed, biome clean (`dashboard-vitest-biome.txt`). The diff is
  display-only (form + 3 locale keys + doc). Re-anchoring is a cross-app change that replaces session ids, so Agent 2 accepts it as an
  owner PROPOSAL. Documented risk: an owner who changes the timezone after sessions exist still gets old instants for the untouched
  generated lessons (hours off) until renewal/regeneration; the warning tells them to check upcoming lessons. P2 → acceptable as a
  proposal (not P0/P1). Evidence `evidence/F06/retest-1/` `pw-qa041.txt`.
- **Verification status:** PROPOSAL-accepted (owner approval); mitigation VERIFIED (Agent 2, retest 1, 2026-10-19)

## ETQAN-QA-042: Creating or renewing a subscription never reports a teacher's double-booking (P4-9 "reported, never blocked")
- **Feature:** F06 (`scheduling/api/views.py` SubscriptionListView/RenewView, `api/payloads.py`; `generation.conflicts`).
  **Severity:** P2 (the most common booking path silently double-books a teacher; the warning only exists on generate, bundles,
  teacher change, substitution and manual sessions). **Priority:** medium
- **Environment:** local docker stack, backend adff9c9, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F06 TC-018.
- **Preconditions:** QA teacher (user 7) already teaches subscriptions 16–19 on Mon/Thu 18:00.
- **Reproduction steps:** `POST /subscriptions/ {"student":215,"course":3,"teacher":7,"package":4,"starts_on":"2026-10-19","slots":[{"weekdays":[3],"start_time":"18:00"}]}`
  (201, id 35): the response has no `conflicts` key; then `POST /schedule/generate/` for the range → `created:0`, `conflicts: []`
  (the sessions already exist, so they are never compared). Same for renew. The subscription form (`SubscriptionForm`) shows nothing.
- **Expected:** Plan 4 P4-9 and `docs/features/sessions.md` ("conflicts are never blocked", reported as warnings): the create and renew
  answers list the teacher's overlapping sessions like `/schedule/generate/` and bundle create do.
- **Actual:** no report anywhere. Control: deleting the new session and re-running generate does report it (`tc018.txt`: K4 08:35
  vs 08:00/08:45/09:00), and back-to-back sessions are correctly not reported.
- **Note:** student double-booking (S5) is not checked anywhere, but the docs define conflicts per teacher only, so it isn't filed.
- **Evidence:** `evidence/F06/tc018.txt`, scripts `evidence/F06/scripts/t18.sh`, `t18b.sh`.
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-19):**
  - **Root cause:** `SubscriptionListView.post` and `RenewView.post` return only `detail()`; generation's
    `GenerationResult.conflicts` from `create_subscription`'s `generate_horizon` is dropped, and a later generate run
    skips existing sessions, so nothing ever compares them (P4-9 "reported, never blocked").
  - **Fix (additive key, no migration):** new `generation.subscription_conflicts(sub)` (exported from
    `scheduling.services`) runs `generation.conflicts` over the subscription's non-cancelled sessions; `views.detail()`
    takes `conflicts=` and both 201 answers add `conflicts: [{session, other}]` in the same shape as bundle create
    (`bundle_payloads.conflict_rows`). Never blocks. Docs: `docs/features/subscriptions.md` API table.
  - **Not done:** the dashboard forms don't display the list yet (follow-up in coverage-gaps Proposals).
  - **Regression tests** (`test_generation_guards.py`): `test_create_reports_the_teachers_double_booking` (3 pairs),
    `test_create_without_a_clash_reports_none` (`[]`), `test_renew_reports_the_teachers_double_booking`; all fail before
    (KeyError), pass after.
  - **Evidence:** `evidence/F06/fix-cycle-1/` (`fix.diff`, `dashboard-fix.diff`, `regression-before.txt` 9 failed, `regression-after.txt` 9 passed, `pytest-scheduling-catalogue.txt` 1460 passed, `ruff.txt`, `lint-imports.txt` 54 kept, `dashboard-*.txt`).
- **Retest 1 (Agent 2, 2026-10-19 ~16:27Z, REAL):** original repro as filed (teacher 7 Thu 18:00, new student 216):
  `POST /subscriptions/` 201 with `conflicts` = 9 pairs, identical to an independent DB overlap query (same teacher, non-cancelled,
  interval overlap); control without clash (teacher 217 Sat 03:00) → `conflicts: []`; renew of the clashing sub → 5 pairs, renew of
  the control → `[]`; GET detail unchanged (no key); teacher role still 403 on create; one invoice per new subscription at the package
  price/currency (money unchanged, `gate-checks.txt`). Diff: additive key, reuses `generation.conflicts` and `bundle_payloads.conflict_rows`
  (same shape as bundles), never blocks. The dashboard still does not display the list on create/renew: split off as ETQAN-QA-043
  (P3) because the API signal now exists, conflicts are non-blocking by design and the overlap is visible on the teacher's calendar.
  Evidence `evidence/F06/retest-1/` `r1-api-db.txt`, `regression-tests.txt`, `pytest-scheduling-catalogue-academy.txt`.
- **Verification status:** VERIFIED (API, Agent 2, retest 1, 2026-10-19); dashboard display → ETQAN-QA-043 (P3, OPEN)

## ETQAN-QA-043: The subscription form and renew dialog don't show the double-booking list the API now returns
- **Feature:** F06 (dashboard `SubscriptionForm`, `RenewDialog`). **Severity:** P3 (missing warning display; conflicts are reported
  by the API and never block by design; the overlap is visible on the calendar). **Priority:** medium
- **Environment:** local docker stack, backend/dashboard working tree on `qa/campaign-2026-10` with the F06 fix cycle 1. **Tag:** REAL
- **Found by:** Agent 2, F06 retest 1 (follow-up of ETQAN-QA-042, already noted by Agent 3 in coverage-gaps Proposals).
- **Reproduction steps:** in the dashboard, create a subscription for teacher QA teacher on Thu 18:00 (already held by subs 16-19),
  or renew one; the API 201 answer carries `conflicts` (9 pairs in retest 1) but the UI navigates straight to the detail page.
- **Expected:** like `BundleForm` / `GenerateDialog`, stay on a result panel listing the clashes when `conflicts.length > 0`.
- **Actual:** no warning in the UI; the owner sees the clash only on the calendar/Today board.
- **Evidence:** `evidence/F06/retest-1/r1-api-db.txt` (API side); code reading `dashboard/src/features/scheduling/` (conflicts shown
  only in BundleForm, GenerateDialog, AddSession/Postpone/Substitute/ScheduleTeacher/ScheduleTrial dialogs).
- **Verification status:** OPEN (P3, carried forward; no fix cycle for P3 in lean mode)


## ETQAN-QA-044: The office can mark a supervisor "present" on a session that hasn't started or was cancelled
- **Feature:** F08 (backend `scheduling/services/supervision.py` `_set_attendance`, route `PATCH /api/v1/sessions/<id>/`). **Severity:** P3
  (a wrong record on a record-only field; `supervisor_attendance` feeds no payroll or billing code, checked with grep). **Priority:** low
- **Environment:** local docker stack, backend working tree `qa/campaign-2026-10`, academy `qa`, `supervision` on. **Tag:** REAL
- **Found by:** Agent 2, F08 TC-016 (suspected defect S6 from Agent 1's code reading).
- **Reproduction steps:** as `qa-admin`, assign supervisor 4 to a session starting in 2 h (280) and to a cancelled one (283), then
  `PATCH /api/v1/sessions/280/ {"supervisor_attendance":"present"}` and the same on 283.
- **Expected:** the same rules as the supervisor's own `POST /supervision/<id>/attendance/`, which refuses a session that is not open
  yet (409 `scheduling.supervision_not_open`) or is cancelled (409 `scheduling.session_cancelled`). Plan 12b §4.4 gives the office the
  field but doesn't say it may record attendance for a session that hasn't happened, so **intent to confirm with the owner**.
- **Actual:** both 200; DB `supervisor_attendance='present'` on a future and on a cancelled session. The payroll lock isn't checked
  either (on locked P6 the call stops only because there's no supervisor).
- **Evidence:** `evidence/F08/tc016.txt`; code `supervision.py:140-150` (only "Assign a supervisor first").
- **Verification status:** OPEN (P3: no fix cycle in lean mode)

## ETQAN-QA-045: Undoing a completed session's attendance keeps its report: a "scheduled" session shows `has_report` and its report can't be edited
- **Feature:** F08 (backend `scheduling/services/attendance.py` undo to `not_set`, `reports.py`). **Severity:** P3. **Priority:** low
- **Environment:** local docker stack, backend working tree `qa/campaign-2026-10`, academy `qa`, `session_reports` on. **Tag:** REAL
- **Found by:** Agent 2, F08 TC-026 (suspected defect S5).
- **Reproduction steps:** session 239 is completed/present with a report. As admin
  `POST /api/v1/sessions/239/attendance/ {"student_attendance":"not_set"}`, then `GET /sessions/239/`,
  `GET /sessions/239/report/`, `PUT /sessions/239/report/ {...}`, `GET /reports/missing/`.
- **Expected:** a report exists only for a completed session (`reports.py`: "A report is written once the session is completed").
  Either the undo is refused while a report exists, or the report is kept but hidden until the session is completed again.
- **Actual:** status `scheduled` with `has_report=true`; GET report 200; PUT 409 `scheduling.not_completed`; not in the missing list.
  Re-marking restores consistency.
- **Evidence:** `evidence/F08/tc021-026.txt` (section S5).
- **Verification status:** OPEN (P3)

## ETQAN-QA-046: The sessions feature doc says an archived session refuses edits; the design (B2d D-7) and the code accept them
- **Feature:** F08 (doc `docs/features/sessions.md` line 96-97). **Severity:** P4 (documentation). **Priority:** low
- **Environment:** docs at the campaign working tree; behaviour on the local stack. **Tag:** REAL
- **Found by:** Agent 2, F08 TC-026 (suspected defect S1).
- **Reproduction steps:** archive completed sessions 239 and 248, then mark attendance, toggle pays-teacher, record times,
  cancel/restore, write a report and run a bulk action on them: all 200, and the consumption (6→7) and projection (−6000) move.
- **Expected (doc):** "While the archive is on, an archived session refuses edits until it is unarchived."
- **Actual:** behaviour matches `docs/superpowers/specs/2026-10-03-b2d-archives-design.md` D-7 ("Archived sessions still take writes:
  attendance, cancel, restore, reports and bulk"; only postpone, and restore of a still-future start, are refused). The product is
  right, so the fix is the doc sentence.
- **Evidence:** `evidence/F08/tc021-026.txt`; `scheduling/services/rules.py:200` docstring.
- **Verification status:** OPEN (P4, doc only)

## ETQAN-QA-047: Session payloads still show `has_report` while the `session_reports` switch is off
- **Feature:** F08 (backend `scheduling/api/payloads.py`). **Severity:** P4. **Priority:** low
- **Environment:** local docker stack, academy `qa`. **Tag:** REAL
- **Found by:** Agent 2, F08 TC-014.
- **Reproduction steps:** with a report on session 239, `set_features qa --off session_reports`, then as admin `GET /api/v1/sessions/239/`.
- **Expected:** with a switch off, the feature is hidden (Plan 13 FT-4, "off hides the feature"): its routes 404 (they do) and its
  fields are left out.
- **Actual:** `has_report: true` is still in the payload.
- **Evidence:** `evidence/F08/tc014.txt`.
- **Verification status:** OPEN (P4)
