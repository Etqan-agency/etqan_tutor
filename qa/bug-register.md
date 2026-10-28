# Bug register

Format: one `## ETQAN-QA-NNN` section per bug, with these fields:
- Title, Feature, Severity (P0–P4), Priority, Environment, Provider tag
- Preconditions, Reproduction steps, Expected, Actual, Evidence
- Root cause, Fix (files), Regression tests
- Verification status (OPEN · FIXING · FIXED-UNVERIFIED · VERIFIED · ESCALATED · WONT_FIX-approved),
  Verified by (Agent 2 run id and evidence path)

Next ID: **ETQAN-QA-067**
(Parallel manual run: M01 used ETQAN-QA-800 … 830; next free in the M01 range is ETQAN-QA-831.)
(Parallel manual run: M13 used ETQAN-QA-700 … 718; next free in the M13 range is ETQAN-QA-719.)

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
- **M01 gate (Agent 2, 2026-10-28):** still OPEN, re-confirmed: `ops-view@` → `/admin/tenants/academy/22/change/` → 500 KeyError 'etqan_defaults_suspended' (`qa/manual/screens/M01/fix/g-view-academy-readonly.png`). The M01 gate counts it as blocking for the view-only role (the role's main job, looking at an academy, fails); the guard in `_AcademyChangeForm.__init__` is an easy fix.

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
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27; covered by the ETQAN-QA-048 fix). AR `/app/reset-password` with `123` shows "استخدم 8 أحرف على الأقل.". Evidence `qa/manual/screens/M02/fix/ETQAN-QA-011-after.png`.
- **F01 gate (Agent 2, 2026-10-18):** carried forward as a known P3/P4 issue; it does not block the F01 gate (no P0/P1/P2 open). Re-confirmed 2026-10-18 (gate/pw/tc141-ar-reset.json: "Too small: expected string to have >=8 characters"). Evidence: `evidence/F01/gate/`.
- **M02 note (Agent 3, 2026-10-27):** addressed by the ETQAN-QA-048 fix (`resetPasswordSchema` now uses `auth.errors.passwordShort`, rendered with `useFieldError` on `/app/reset-password`). Status stays with QA-048's verification.

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
- **Root cause (Agent 3, fix cycle 2, 2026-10-28):** `_AcademyChangeForm.__init__` indexed `self.fields["etqan_defaults_suspended"]` and every `feature_<code>` field; without the change permission Django leaves all fields out of the form and renders them read-only, so the lookup raised KeyError. The feature switches also had nothing to display read-only (not model attributes).
- **Fix:** `etqan/tenants/admin.py`: the form sets up each field only if present (`self.fields.get`); `AcademyAdmin` gains one `@admin.display(boolean=True)` method per feature (`feature_<code>`, label "EN (AR)"), which Django's read-only change view looks up on the ModelAdmin. A view-only user now gets the standard read-only page (200, no save buttons) with the suspended state and every switch shown as on/off icons.
- **Regression test:** `etqan/tenants/tests/test_admin_permissions.py::test_view_only_staff_sees_an_academy_read_only` (failed with the KeyError before). Evidence `qa/manual/evidence/M01/fix-2/`.
- **Verification status:** VERIFIED (Agent 2 final gate, cycle 2, 2026-10-28)
- **Retest (Agent 2, M01 final gate cycle 2, 2026-10-28, REAL):** original steps as `ops-view@`: `/admin/tenants/academy/19/change/` → 200 "View academy", 0 submit buttons, 0 checkboxes, every field read-only; "Etqan defaults suspended" and all 89 switches as on/off icons; the 7 "on" icons are exactly the 7 switches checked on the superuser's page for the same academy (parents, contracts, session_reports, teacher_attendance, invoices, auto_notifications, export). All 18 academy change pages + Domains list → 200 for ops-view@. Forged change POST from ops-view@ → 403, academy unchanged (QA-002 still holds). Label is the model name "Etqan defaults suspended" on the read-only page (cosmetic, accepted). Before `qa/manual/screens/M01/fix/g-view-academy-readonly.png` (500), after `qa/manual/screens/M01/fix/ETQAN-QA-012-after.png`, `qa/manual/screens/M01/fix/g2-012-view-list.png`, `qa/manual/screens/M01/fix/g2-012-forged-post.png`, `qa/manual/screens/M01/fix/g2-012-superuser-same-academy.png`. Tests: `qa/manual/evidence/M01/gate-2/pytest-scoped.txt` (54 passed).
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

---

## ETQAN-QA-048: Form validation messages are raw zod developer text ("Too small: expected string to have >=1 characters", "Invalid email address"), in English on Arabic screens
- **Feature:** M02 Sign-in & account (login, forgot password, account change-password forms). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-001); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. AR: open `/app/login`, click "تسجيل الدخول" with both fields empty.
  2. AR: open `/app/forgot-password`, click "إرسال رابط الإعادة" with the email empty.
  3. EN, signed in as student.ind5: `/app/account` → Change password, current password correct, new `123`, Enter.
- **Expected:** A short human message in the page language ("هذا الحقل مطلوب", "Password must be at least 8 characters").
- **Actual:** (1) "Too small: expected string to have >=1 characters" under both login fields on the Arabic page; (2) "Invalid email address" in English on the Arabic forgot page; (3) "Too small: expected string to have >=8 characters" on the account page (developer wording in English too).
- **Evidence:** `qa/manual/screens/M02/M02-F-001-login-empty-raw-zod-ar.png`, `qa/manual/screens/M02/M02-F-001b-account-newpw-raw-zod-en.png`, `qa/manual/screens/M02/M02-F-001c-forgot-empty-english-in-ar.png`, `qa/manual/screens/M02/triage/t001-login-empty-ar.png`, `qa/manual/screens/M02/triage/t003-forgot-empty-ar.png`, `qa/manual/screens/M02/triage/t008-account-newpw-123-en.png`
- **Notes:** Same root cause as ETQAN-QA-011 (zod default messages; no translated error map), but on other screens: fix both together (one i18n zod error map or translated messages in the schemas).
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: the identity zod schemas (`features/identity/schemas.ts`: login, 2FA, forgot, reset, change password, add email, set primary, profile) used `.min(1)` / `.min(8)` / `z.email()` with no message, so zod's English developer default reached the UI, and `LoginForm`, `forgot-password`, `ChangePasswordCard`, `reset-password`, `AddEmailForm` and `SetPrimaryDialog` rendered `error.message` without `t()`. Fix: each rule now carries an i18n key (`auth.errors.required|email|passwordShort`, added in ar/en/es `auth.json`) and those forms render field errors through `useFieldError()` (the existing convention). This also covers the set-password page of ETQAN-QA-011 (`resetPasswordSchema`). Other features' schemas: proposal in coverage-gaps.md. Regression tests: `features/identity/schemas.test.ts` ("identity schema messages": every schema answers with catalogue keys), `LoginForm.test.tsx` ("shows empty fields and wrong credentials in Arabic"), `ChangePasswordCard.test.tsx` ("words a short new password…"), `routes/forgot-password.test.tsx` ("shows a translated email error…"). Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27). AR login empty: "هذا الحقل مطلوب." under both fields; AR forgot empty: "أدخل بريدًا إلكترونيًا صحيحًا."; EN account new password `123`: "Use at least 8 characters.". Before/after `qa/manual/screens/M02/fix/ETQAN-QA-048-after.png`; also `ETQAN-QA-048-after-forgot-ar.png`, `ETQAN-QA-048-after-account-en.png`.

---

## ETQAN-QA-049: "Invalid credentials." is shown in English on the Arabic login page
- **Feature:** M02 Sign-in (`identity/api/views.py` INVALID_CREDENTIALS, `LoginForm`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-002); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. AR: `/app/login`, email student.ind5@qa.etqan.test, password `nope-123`, "تسجيل الدخول". (Same on qaother with a qa account.)
- **Expected:** An Arabic error, like the other errors on this page (lockout "محاولات كثيرة، حاول لاحقًا.", 2FA "الرمز غير صحيح").
- **Actual:** "Invalid credentials." in English; in RTL the period jumps to the start (".Invalid credentials"). Network: 400 POST /api/v1/identity/login/.
- **Evidence:** `qa/manual/screens/M02/M02-F-002-invalid-credentials-english-in-ar.png`, `qa/manual/screens/M02/M02-F-002b-qaother-invalid-credentials-english.png`, `qa/manual/screens/M02/triage/t002-invalid-credentials-ar.png`
- **Notes:** The backend returns the literal string `INVALID_CREDENTIALS = "Invalid credentials."` (views.py:143) with no code the dashboard translates.
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: `LoginView` returns the fixed English `INVALID_CREDENTIALS` text with no code, and `LoginForm` showed any server message as is (the key `auth.invalidCredentials` existed in ar/en/es but was never used). Fix (dashboard only, no API change): `LoginForm` maps that exact server text to `t("auth.invalidCredentials")` ("بيانات الدخول غير صحيحة."). Proposal for an additive `code` in coverage-gaps.md. Regression test: `LoginForm.test.tsx` "shows empty fields and wrong credentials in Arabic (ETQAN-QA-048, QA-049)". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27). AR wrong password: "بيانات الدخول غير صحيحة." (400 POST login); EN on qaother with a qa account: "Invalid credentials.". Interim client mapping accepted; the API `code` is PROPOSAL-accepted (coverage-gaps). Before/after `qa/manual/screens/M02/fix/ETQAN-QA-049-after.png`; `qa/manual/screens/M02/fix/g-smoke-cross-qaother.png`.

---

## ETQAN-QA-050: Saving the profile switches the interface to the stored "Preferred language" even when the user did not change it; the "Saved." toast then shows in the old language
- **Feature:** M02 Account page (`ProfileEditForm.tsx` onSubmit). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-003); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Student whose stored preferred language is Arabic switches the UI to English with the header toggle.
  2. `/app/account` → change only Full name (or Phone) → "Save changes".
- **Expected:** The edited field is saved and the page stays in English (the language changes only when the user changes "Preferred language").
- **Actual:** The whole app turns Arabic/RTL at once; the toast reads "Saved." in English inside the Arabic UI. The "Preferred language" select showed العربية while the UI was English, so any save applies it.
- **Evidence:** `qa/manual/screens/M02/M02-F-003-save-profile-flips-ui-to-arabic.png`, `qa/manual/screens/M02/triage/t009-profile-save-flips-lang.png`
- **Notes:** Applying the language on save is intended (B9d L-5, `ProfileEditForm.tsx:53`), but it fires on every save, not only when the field changed; the toast uses `t` from the old language.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-051: Account emails: verification subject has a double prefix "[Etqan QA Academy] [Etqan]" and every account email repeats the academy name ("Etqan QA Academy · Etqan QA Academy")
- **Feature:** M02 Account emails (allauth adapter / email layout). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-004); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Student `/app/account` → Add email address → aisha.tri@qa.etqan.test + password → Add address.
  2. Open the mail in Mailpit.
- **Expected:** Subject "[Etqan QA Academy] تأكيد عنوان البريد الإلكتروني"; academy name once in header and footer.
- **Actual:** Subject "[Etqan QA Academy] [Etqan] تأكيد عنوان البريد الإلكتروني" (allauth's site-name prefix on top of ours); header "Etqan QA Academy Etqan QA Academy ·", footer "Etqan QA Academy · Etqan QA Academy". The duplicated header/footer is also in the reset-link, reset-code and sign-in-link emails (re-checked on the reset-link mail).
- **Evidence:** `qa/manual/screens/M02/M02-F-004-verify-email-double-prefix.png`, `qa/manual/screens/M02/triage/t013-verify-email-double-prefix.png`
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: (1) allauth's `format_email_subject` adds `ACCOUNT_EMAIL_SUBJECT_PREFIX` (`DJANGO_EMAIL_SUBJECT_PREFIX="[Etqan] "` in `.env`) before `brand_email` adds `[<academy>] `, giving two prefixes. Test settings set the prefix to "", so tests never saw it. (2) `templates/email/layout.{txt,html}` always print `name_en · name_ar`, even when both names are the same. Fix: `CeleryAccountAdapter.format_email_subject` returns the subject unprefixed (`brand_email` alone prefixes it, and it still adds `[Etqan] ` in the public schema). The layouts print the Arabic name only when it is set and differs from the English one. Regression tests: `identity/tests/test_email_branding.py::test_confirmation_subject_has_only_the_academy_prefix` (with the prefix overridden to `[Etqan] `), `site/tests/test_emails.py::test_an_academy_named_alike_in_both_languages_is_named_once` and `::test_two_names_are_both_shown`. Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27). New verification mail: subject "[Etqan QA Academy] تأكيد عنوان البريد الإلكتروني" (one prefix); header and footer show "Etqan QA Academy" once (HTML and text). Before/after `qa/manual/screens/M02/fix/ETQAN-QA-051-after.png`.

---

## ETQAN-QA-052: Change password: two quick clicks send two requests, show two "Password updated." toasts and send two security-alert emails
- **Feature:** M02 Account page (`ChangePasswordCard.tsx`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-005); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Student `/app/account` → Change password: current correct, new `Aisha-Tri-2026!x`.
  2. Click "Update password" twice before the first response (e.g. a fast double-click).
- **Expected:** The button blocks a second submit: one change, one toast, one email.
- **Actual:** Two 200 POST /api/v1/identity/me/password/, two toasts, two "تنبيه أمني" emails 17 ms apart (Mailpit 18:54:34.106/.123; Agent 1 got the same at 18:27:38.805/.831). A Playwright dblclick and a second click 60 ms later were both blocked; two clicks in the same task (before React re-renders `isSubmitting`) go through, which a fast human double-click can hit (Agent 1 did).
- **Evidence:** `qa/manual/screens/M02/M02-F-005-double-submit-two-password-toasts.png`, `qa/manual/screens/M02/triage/t010c-double-submit-sync.png`, `qa/manual/screens/M02/triage/t010b-double-submit-password.png` (slower double click: one toast)
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-053: Opening an email-verification link a second time says "invalid or expired" although the address is verified
- **Feature:** M02 Email verification (`/app/verify-email`, `identity/verify-email/`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-006); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Add a secondary email; open the verify link from Mailpit (shows "تم تأكيد البريد").
  2. Open the same link again (e.g. clicking it twice in the mail app).
- **Expected:** "This email is already confirmed" (or the same success).
- **Actual:** Red "رابط التأكيد غير صالح أو منتهي الصلاحية."; the card has an empty title area. Network: 400 POST /api/v1/identity/verify-email/.
- **Evidence:** `qa/manual/screens/M02/M02-F-006-used-verify-link-says-invalid.png`, `qa/manual/screens/M02/triage/t014a-verify-first.png`, `qa/manual/screens/M02/triage/t014b-verify-second-invalid.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-054: Removing an email address gives no confirmation toast
- **Feature:** M02 Account page, Email addresses card. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-007); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Student `/app/account` with a secondary address → Remove → confirm Remove in the dialog.
- **Expected:** A toast like the rest of the page ("Saved.", "Password updated.", "Verification link sent…").
- **Actual:** The row disappears silently.
- **Evidence:** `qa/manual/screens/M02/M02-F-007-remove-email-no-confirmation.png`, `qa/manual/screens/M02/triage/t015-remove-email-no-toast.png`
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: `RemoveEmailDialog` called `remove.mutate(id)` with no `onSuccess`/`onError`, so neither success nor failure was reported. Fix: a success toast `account.removed` ("{{email}} was removed.", ar/en/es) and an error toast `account.genericError`. Regression tests: `RemoveEmailDialog.test.tsx` "confirms the removal with a toast" and "says so when the removal fails". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27). AR remove aisha.tri → toast "تمت إزالة aisha.tri@qa.etqan.test.". Before/after `qa/manual/screens/M02/fix/ETQAN-QA-054-after.png`.

---

## ETQAN-QA-055: A used reset link still shows the new-password form; the error appears only after submitting and offers no "request a new link" action
- **Feature:** M02 Password reset by link (`/app/reset-password`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-008); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Request a reset link for student.ind5, use it once (success).
  2. Open the same link again → type `Aisha-Reset-2027!` → "إعادة تعيين كلمة المرور".
- **Expected:** The page says at once the link is no longer valid, with a button to request a new one.
- **Actual:** Normal form shown; after submit "الرابط غير صالح أو منتهي الصلاحية. يرجى طلب رابط جديد." with only "العودة إلى تسجيل الدخول". 400 POST /api/v1/identity/password/reset/confirm/. The reset email also doesn't say how long the link lasts (the code email says 10 minutes).
- **Evidence:** `qa/manual/screens/M02/M02-F-008a-used-reset-link-shows-form.png`, `qa/manual/screens/M02/M02-F-008b-used-reset-link-error-after-submit.png`, `qa/manual/screens/M02/triage/t019b-used-reset-link-shows-form.png`, `qa/manual/screens/M02/triage/t019c-used-reset-link-error.png`
- **Notes:** A "Request a new link" button is a small change; checking the token before showing the form needs an API call.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-056: Forgot password: the subtitle always says "we'll send you a reset link", and the method cards stay on screen through the code step and after success
- **Feature:** M02 Forgot password (`routes/forgot-password.tsx`). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-009); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. EN `/app/forgot-password` → "A code by email" → email → submit.
- **Expected:** Copy matches the chosen method; once the code is sent / password reset, the method chooser is gone.
- **Actual:** "Enter your email and we'll send you a reset link." stays for code and SMS; the three method cards remain above "Enter the code" and above "Password reset — you can now sign in.".
- **Evidence:** `qa/manual/screens/M02/M02-F-009-forgot-subtitle-and-cards-in-code-step.png`, `qa/manual/screens/M02/M02-F-009b-cards-still-shown-after-success.png`, `qa/manual/screens/M02/triage/t020-forgot-code-step-cards.png`
- **Notes:** `PageHeader description={t("auth.forgotPasswordSubtitle")}` and the RadioCardGroup are outside the flow state.
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: in `routes/forgot-password.tsx`, the `PageHeader` description was always `auth.forgotPasswordSubtitle`, and the `RadioCardGroup` depended only on the methods offered, not on how far the flow had got (the step state lived inside `CodeResetFlow`/`ResetLinkForm`). Fix: the subtitle follows the method (`codeReset.subtitle.email|phone`, ar/en/es). `CodeResetFlow` gets `onStarted(started)`, called on every step change, and `ResetLinkForm` gets `onSent`. The page hides the method cards once a code or link is sent and shows them again if the person goes back to the first step. Regression tests: `routes/forgot-password.test.tsx` "words the subtitle for the chosen method and drops the cards once sent" and "drops the method cards once the reset link is sent". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27). EN code-by-email: subtitle "…send you a 6-digit code.", cards hidden in the code step; "Use a different email" brings the cards back; after a link is sent the cards are gone. Before/after `qa/manual/screens/M02/fix/ETQAN-QA-056-after.png`; `qa/manual/screens/M02/fix/ETQAN-QA-056-after-link-sent.png`.

---

## ETQAN-QA-057: Quick sign-in link page: after a refresh the button is disabled with no explanation; after a used-link error the Sign in button stays active
- **Feature:** M02 Quick-login links (`features/quicklogin/QuickLoginPage`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-010); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Admin → student 246 → "Send sign-in link"; open the link from Mailpit (the token is removed from the address bar).
  2. Press reload before clicking.
  3. Separately open an already-used link → Sign in.
- **Expected:** After reload, a message to reopen the link from the email; after the error, no active Sign in button.
- **Actual:** Reload: greyed-out button, text still "اضغط الزر لتسجيل الدخول", no message. Used link: "This link is invalid or has expired…" with the green Sign in button still active (400 POST /api/v1/identity/quick-login/).
- **Evidence:** `qa/manual/screens/M02/M02-F-010-quick-login-refresh-dead-button.png`, `qa/manual/screens/M02/M02-F-010b-used-link-button-still-active.png`, `qa/manual/screens/M02/triage/t022-quick-login-after-refresh.png`, `qa/manual/screens/M02/triage/t022c-quick-login-used-link.png`
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: `QuickLoginPage` always rendered the Sign in button (only disabled when the in-memory token was gone after a reload, with no message) and kept it active after a 400 used/invalid-link error. Fix: with no token, an alert `quickLogin.noToken` ("Open the link from your email again, or sign in with your password", ar/en/es) and the Go to sign in link, with no button and no "select the button" hint. After a 400 the link is marked spent and the button goes away. A 429 keeps it (waiting is not a dead link). Regression tests: `QuickLoginPage.test.tsx` "explains a page without its token…", the invalid-link test (button gone), and the throttled test (button stays). Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27). Fresh link for student 246, reload → noToken alert, no button; first use → Home; reuse in a fresh browser → 400, "هذا الرابط غير صالح…", no button. Before/after `qa/manual/screens/M02/fix/ETQAN-QA-057-after.png`; `ETQAN-QA-057-after-used.png`, `ETQAN-QA-057-after-first-use.png`.

---

## ETQAN-QA-058: The page asked for while signed out is forgotten: after sign-in the user lands on Home, not the deep link
- **Feature:** M02 Sign-in redirect (`requireAuth`, `routes/login.tsx` onSuccess → `/`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-011); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Signed out, open http://qa.etqan.localhost/app/people/teachers → redirected to /app/login.
  2. Sign in as qa-admin.
- **Expected:** Land on Teachers (links from emails, bookmarks).
- **Actual:** Lands on Home `/app/`; the login URL carries no return address and `onSuccess` always navigates to `/`.
- **Evidence:** `qa/manual/screens/M02/M02-F-011-deeplink-lost-after-login.png`, `qa/manual/screens/M02/triage/t006-deeplink-after-login.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-059: When the session has ended, saving shows the raw "لم يتم تزويد بيانات الدخول." and the page still looks signed in
- **Feature:** M02 Dashboard API client (no global handling of an expired session). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-012); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Student AR `/app/account`, change Full name.
  2. End the session (POST /api/v1/identity/logout/ from the page, as an expiry or a sign-out in another tab would).
  3. Click "حفظ التغييرات".
- **Expected:** "Your session has ended, please sign in again" and a way to the login page (ideally back here after).
- **Actual:** "لم يتم تزويد بيانات الدخول." (DRF "Authentication credentials were not provided.") under the form; header, menu and name stay signed in. 403 PATCH /api/v1/identity/me/.
- **Evidence:** `qa/manual/screens/M02/M02-F-012-session-lost-raw-auth-error.png`, `qa/manual/screens/M02/triage/t016-session-lost-save.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-060: Latin text in the Arabic UI is laid out RTL: a name "Aisha R." shows as ".Aisha R" (field and header), emails/phones right-aligned in inputs
- **Feature:** M02 Shared inputs / user name display (RTL). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-013); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. AR account page, Full name `Aisha R.` → save; look at the field and the header user menu.
- **Expected:** Latin names, emails and phones keep their own direction (`dir="auto"` / `<bdi>`): "Aisha R.".
- **Actual:** ".Aisha R" in the input and in the header button; emails typed in login/account inputs are right-aligned.
- **Evidence:** `qa/manual/screens/M02/M02-F-013-latin-text-rtl-punctuation.png`, `qa/manual/screens/M02/triage/t009-profile-save-flips-lang.png`, `qa/manual/screens/M02/triage/t016-session-lost-save.png`
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: the shared `ui/input.tsx` forced `rtl:text-right`, and neither inputs nor the header name isolated their text, so a Latin value took the page's RTL base direction ("Aisha R." shown as ".Aisha R", emails right-aligned). `dir="auto"` was ruled out for inputs because Chromium resolves an empty `dir=auto` input to LTR, which would move Arabic placeholders and the caret to the left (probed). Fix: `Input` uses `text-start [unicode-bidi:plaintext]`. Each value takes its direction from its first strong letter, and an empty field keeps the page's (probed: an empty Arabic placeholder stays right; "Aisha R.", an email and "+20 100 123 4567" read LTR; Arabic stays RTL). The header `UserMenu` name has `dir="auto"`. Textarea and other name displays: follow-up in coverage-gaps.md. Regression test: `ui/input.test.tsx` "lets each value keep its own direction". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27). AR account: "Aisha R." in field and header, phone +201001234567 LTR, an Arabic value stays right; an empty Arabic placeholder (staff students search) stays right. Textarea/table names: PROPOSAL-accepted follow-up. Before/after `qa/manual/screens/M02/fix/ETQAN-QA-060-after.png`; `ETQAN-QA-060-after-arabic-value.png`, `g-smoke-staff-ar.png`. Profile restored (Aisha Rahman, no phone).

---

## ETQAN-QA-061: RadioCardGroup renders left-to-right in Arabic (reset-method cards: text left-aligned, check mark on the right, card order mirrored), desktop and mobile
- **Feature:** M02 Shared UI `ui/radio-card-group.tsx` (seen on forgot password). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-014); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. AR `/app/forgot-password` at 375x812 (also 1440x900) → choose "رمز عبر رسالة نصية".
- **Expected:** RTL cards: text right-aligned, check mark at the inline end per RTL, first card on the right.
- **Actual:** Titles/descriptions aligned left, periods at the wrong end, check mark on the right, first card on the left. The radiogroup element carries `dir="ltr"` (eval: `ltr|ltr`): Radix RadioGroup defaults to ltr without a `dir` prop or DirectionProvider, overriding the page's `dir=rtl`. Every RadioCardGroup in the app is affected, not just mobile.
- **Evidence:** `qa/manual/screens/M02/M02-F-014-mobile-method-cards-ltr-in-ar.png`, `qa/manual/screens/M02/triage/t005-mobile-method-cards-ar.png`, `qa/manual/screens/M02/triage/t004-forgot-sms-ar.png`
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: Radix `RadioGroup.Root` defaults `dir` to `ltr` when there is no `dir` prop or Radix `Direction.Provider`, and it writes `dir="ltr"` on the group, overriding the page's `rtl`. The app has no Radix direction provider. Fix: a new `useDir()` in `lib/direction.tsx` (from the current language), and `RadioCardGroup` passes `dir={dir}` to `RadioGroup.Root`. This fixes every RadioCardGroup. An app-wide Radix provider is a proposal in coverage-gaps.md. Regression test: `ui/radio-card-group.test.tsx` "follows the language's direction" (ar → `dir=rtl`, en → `ltr`). Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27). AR radiogroup `dir=rtl`; mobile and desktop: text right, check at the inline end (mirror of EN), first card on the right. Before/after `qa/manual/screens/M02/fix/ETQAN-QA-061-after.png`; EN reference `ETQAN-QA-061-after-en-ref.png`.

---

## ETQAN-QA-062: Arabic phone hint shows the example number backwards: "4567 123 100 20+"
- **Feature:** M02 Forgot password by SMS (`codeReset` ar copy). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-015); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. AR `/app/forgot-password` → "رمز عبر رسالة نصية" (desktop and mobile).
- **Expected:** "رقمك مع رمز الدولة، مثل +20 100 123 4567."
- **Actual:** Rendered "…مثل 4567 123 100 20+.": the leading LRM in the string does not isolate the number, so the groups are reordered and the plus goes to the end; a user may type it that way.
- **Evidence:** `qa/manual/screens/M02/M02-F-015-phone-example-reversed-ar-desktop.png`, `qa/manual/screens/M02/triage/t004-forgot-sms-ar.png`, `qa/manual/screens/M02/triage/t005-mobile-method-cards-ar.png`
- **Notes:** Wrap the number in LRI…PDI (U+2066/U+2069) or a `<bdi dir="ltr">`.
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: `ar/codeReset.json` `phoneHint` put only an LRM before `+20 100 123 4567`. In an RTL paragraph the spaces between the digit groups resolve RTL, so the groups were reordered and the plus moved to the end. Fix: the number is wrapped in LRI…PDI (U+2066/U+2069). Measured in the live page, the glyphs now run left to right as `+`, `20` … `4567`, left of `مثل`. Regression test: new `locales/bidi.test.ts` (no Arabic string marks a spaced Latin number with LRM alone; the phone example is isolated). Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** CLOSED, not a bug on retest (Agent 2 gate M02, 2026-10-27). Upscaled crops of the BEFORE (`triage/t004`) and AFTER shots render identically and correctly ("+20 100 123 4567" left to right, the period at the sentence end). The old LRM already made the number run L (UBA W7), and the triage read the RTL line wrongly. Agent 3's LRI/PDI isolation is harmless hardening and is kept; glyph x positions after: + 652, 20 660, 100 680, 4567 737. Evidence `qa/manual/screens/M02/fix/ETQAN-QA-062-after.png`, `qa/manual/screens/M02/fix/ETQAN-QA-062-after-zoom.png`.

---

## ETQAN-QA-063: Lockout message doesn't say how long to wait
- **Feature:** M02 Sign-in throttle (429 with Retry-After). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-017); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. 10 wrong passwords in a row for a throwaway (student.ind6), then sign in again (even with the right password).
- **Expected:** "Too many attempts. Try again in about N minutes" (the API already sends `Retry-After`), ideally with the reset link.
- **Actual:** Only "محاولات كثيرة، حاول لاحقًا." (429 POST /api/v1/identity/login/). Refusing the correct password during the lock is intended and not part of this bug.
- **Evidence:** `qa/manual/screens/M02/M02-F-017-lockout-no-wait-time.png`, `qa/manual/screens/M02/triage/t023-lockout-no-wait-time.png`
- **Root cause / Fix / Regression tests (Agent 3, fix cycle 1, 2026-10-27):** Root cause: `parseApiError` dropped the 429's `Retry-After` header, so `LoginForm` could only say "try again later". Fix: `ParsedApiError.retryAfter` (seconds, from `Retry-After`) and `throttledMessage()` in `features/identity/api.ts`. The login form shows `signIn.throttledWait` ("Too many attempts. Try again in about N minutes.", with Arabic plural forms and es), and falls back to the old text when there is no header. Regression test: `LoginForm.test.tsx` "says how long to wait when the server sends Retry-After" (290 s → "about 5 minutes"). Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M02/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate M02, 2026-10-27). Throwaway student.ind6 (429): "محاولات كثيرة. حاول مرة أخرى بعد 3 دقائق تقريبًا.". Before/after `qa/manual/screens/M02/fix/ETQAN-QA-063-after.png`.

---

## ETQAN-QA-064: Sign-in copy is student-only ("Sign in to continue your studies.") for every role, and the 2FA code step keeps the sign-up / forgot-password links
- **Feature:** M02 Login page (`routes/login.tsx`, `auth.signInSubtitle`). **Severity:** P4. **Type:** copy. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M02 (M02-F-020); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; student.ind5@qa.etqan.test / `QA-People-2026!` for account steps; anonymous for public pages.
- **Reproduction steps:**
  1. Open `/app/login` (any role signs in here).
  2. Sign in with a 2FA account to reach the code step.
- **Expected:** Neutral copy for all roles; on the code step only code-related links.
- **Actual:** Subtitle "Sign in to continue your studies." / "سجّل الدخول لمتابعة دراستك." for admins/teachers/staff; the PageHeader and the "New here?" + "Forgot your password?" links sit outside `LoginForm`, so they stay under the 2FA code form.
- **Evidence:** `qa/manual/screens/M02/M02-F-020-2fa-step-student-copy-and-signup-links.png`, `qa/manual/screens/M02/triage/t001-login-empty-ar.png`
- **Notes:** 2FA step confirmed from Agent 1's screenshot plus code (login.tsx:36-79); not re-run to avoid another 2FA enrol/disable on the throwaway.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-065: Arabic "Last sign-in" line on a person's page reads in the wrong order ("آخر دخول: Africa/Cairo · حاسوب · 192.168.65.1"): the time zone comes first and reads like a place
- **Feature:** M02 Quick login / sign-in technical fields (`features/quicklogin/LastSignIn.tsx`, B9b S-8). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (dashboard branch `qa/manual-2026-10`, uncommitted fix cycle 1), Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL
- **Found by:** Agent 1, M02 confirmation sweep (M02-F-021); reproduced by Agent 2 (final gate) on 2026-10-27.
- **Preconditions:** academy `qa`, admin qa-admin@qa.etqan.test; student 246 (student.ind5) has signed in at least once.
- **Reproduction steps:**
  1. AR UI: open `/app/people/students/246`, scroll to the "الحساب" (Account) card.
  2. Compare with the EN UI on the same page.
- **Expected:** In Arabic the parts read in the same order as the spec and English (device · IP · zone), right to left: "آخر دخول: حاسوب · 192.168.65.1 · Africa/Cairo".
- **Actual:** The value is wrapped in one `<span dir="ltr">`, so the three parts are laid out left-to-right inside the RTL line; an Arabic reader meets "Africa/Cairo" first, then "حاسوب", then the IP. EN is correct ("Last sign-in: Desktop · 192.168.65.1 · Africa/Cairo").
- **Evidence:** `qa/manual/screens/M02/sweep/M02-F-021-last-signin-no-time-ar.png`, `qa/manual/screens/M02/triage/t032-last-signin-ar.png`, `qa/manual/screens/M02/triage/t033-last-signin-en.png`
- **Notes:** The other half of M02-F-021 (no date/time of the last sign-in) is **not a bug**: B9b S-8 defines the line as "device · IP · zone" and `user_payload` has no `last_login` field. Adding the time needs an API field, so it is logged as a PROPOSAL (P3) in `qa/coverage-gaps.md`, not as part of this fix. Suggested fix: drop the outer `dir="ltr"` and isolate only the Latin parts (IP, zone) with `<bdi>`/`dir="ltr"` per part.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-066: Arabic sign-in page says "جديد على إتقان؟" (New to Etqan?) on an academy's white-label login; English and Spanish say "New here?"
- **Feature:** M02 Login page, sign-up off (`routes/login.tsx`, locale `ar/auth.json` key `auth.newToEtqan`). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (dashboard branch `qa/manual-2026-10`, uncommitted fix cycle 1), Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL
- **Found by:** Agent 1, M02 confirmation sweep (M02-F-022); reproduced by Agent 2 (final gate) on 2026-10-27.
- **Preconditions:** academy `qaother` (self sign-up off); anonymous visitor.
- **Reproduction steps:**
  1. Open `http://qaother.etqan.localhost/app/login` in Arabic.
  2. Switch to English.
- **Expected:** Neutral wording that matches EN/ES, e.g. "جديد هنا؟ اطلب من أكاديميتك إنشاء حساب لك". A student of "Etqan QA Other" signs in on the academy's own brand and need not know the platform.
- **Actual:** AR "جديد على إتقان؟ اطلب من أكاديميتك إنشاء حساب لك"; EN "New here? Ask your academy for an account"; ES "¿Eres nuevo? Pide una cuenta a tu academia". Only Arabic names the platform.
- **Evidence:** `qa/manual/screens/M02/sweep/M02-F-022-new-to-etqan-ar.png`, `qa/manual/screens/M02/triage/t030-qaother-new-to-etqan-ar.png`, `qa/manual/screens/M02/triage/t031-qaother-new-here-en.png`
- **Notes:** Not a dup of ETQAN-QA-064 (that one is the student-only subtitle and the 2FA-step links). Fix is the Arabic string only (the key name `newToEtqan` can stay).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## --- M06 manual bugs ---

## ETQAN-QA-200: A renewal that hasn't started yet shows as a second identical "Active" subscription (admin list, expanded calendar, student/parent pages)
- **Feature:** M06 Subscriptions (renewal chain display: `SubscriptionsList`, expanded weekly calendar, `learning.subscriptions`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-008; also M06-F-021 and the calendar part of M06-F-009); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. Sub 96 (Ibrahim, 27/10–01/12) → "جدّد" with the default start 02/12/2026 (creates 97). Sub 94 (Mona) renewed early from 02/11 (creates 98).
  2. AR `/app/scheduling/subscriptions`, search "إبراهيم".
  3. `/app/scheduling/schedules/calendar`.
  4. Sign in as student.ind1@ (Mona) → `/app/learning/subscriptions`.
- **Expected:** The future period is recognisably "upcoming / starts 02/12" (badge or start-date column), and the calendar/student page don't show it as a second running subscription for the same weeks.
- **Actual:** (2) two rows "إبراهيم حسن / حفظ القرآن الكريم / Ahmad / 0 من 8 حصة / نشط / غير مدفوع" that differ only by the end date; no start column. (3) Mona appears twice on Wednesday and Saturday 17:00, Ibrahim twice on Thursday 17:00. (4) two identical "نشط" cards differing only in "ينتهي في". Status "active" for a not-started renewal is the data model (status has no "upcoming"; the old one expires when the job reaches the renewal start, subscriptions.md §5), so the defect is the display: nothing tells the office or the family which period is current.
- **Not part of this bug:** the renewal invoice due date (issued at renewal + `invoice_due_days`, billing.md) is by design.
- **Evidence:** `qa/manual/screens/M06/M06-F-008-renewal-two-active-rows.png`, `qa/manual/screens/M06/M06-F-021-student-two-identical-active-subs.png`, `qa/manual/screens/M06/triage/t004-list-ibrahim-renewal-two-active.png`, `qa/manual/screens/M06/triage/t005-calendar-mona-twice.png`, `qa/manual/screens/M06/triage/t006-student-two-active-cards.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-201: Early renewal: the renew dialog gives no warning and the old period still shows "الحصص المتبقية 8" though only 2 of its lessons remain
- **Feature:** M06 Subscriptions (`RenewDialog`, `SubscriptionDetail` summary). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-009); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. Sub 94 (Mona, 27/10–26/11, Wed+Sat 17:00) → "جدّد" → start 02/11/2026 → "جدّد" (creates 98).
  2. Open sub 94.
- **Expected:** The renew dialog says that starting before the current end removes the current period's lessons from that date; the old period's summary reflects what it still delivers.
- **Actual:** No warning. Sub 94: "نشط", ينتهي 26/11, "الحصص المتبقية 8", "0 من 8 حصة", upcoming only 28/10 and 31/10. The 6 other paid lessons silently move out (deleted from the old term per subscriptions.md §5; `carried_over` counts only the overrun). The office can't see where they went.
- **Evidence:** `qa/manual/screens/M06/M06-F-009-early-renewal-old-period-remaining-8.png`, `qa/manual/screens/M06/M06-F-009b-early-renewal-new-period.png`, `qa/manual/screens/M06/triage/t003-sub94-detail-ar.png`
- **Notes:** The deletion itself is documented behaviour; whether unused lessons should carry over is an owner decision. This bug is the missing warning and the misleading count.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-202: New subscription "Student" dropdown stops at the first 100 students with no hint; Arabic-named students are unreachable without the search box
- **Feature:** M06 New subscription (`SubscriptionForm` student choices). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-001); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR `/app/scheduling/subscriptions/new`, open "الطالب" without typing in "ابحث عن طالب".
  2. `eval` the select's options.
- **Expected:** Every active student reachable, or a visible "showing the first 100, type to search" hint.
- **Actual:** 101 options (100 + "—"), last "QA5 UI 947767"; no Arabic-named student (منى السيد, حمزة القاضي…), no hint. Only the separate search box finds them.
- **Evidence:** `qa/manual/screens/M06/M06-F-001-student-list-cut-at-100.png`, `qa/manual/screens/M06/triage/t001-new-sub-form-ar.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-203: Family subscription picker offers retired families
- **Feature:** M06 New subscription, type "عائلي" (family choices). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-012); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR `/app/scheduling/subscriptions/new` → "عائلي" → list the "العائلة" options.
- **Expected:** Only active families (people.md: a retired family supplies no payer). Related to ETQAN-QA-033 (adding students to a retired family), different place.
- **Actual:** All four retired families are offered: "QA5 Retired Fam" (id 4), "QA5 UI Family 947767" (7), "QA5 UI Family 526170" (9), "M04 عائلة عبد الرحمن" (16) (`identity_family.is_active=false`).
- **Evidence:** `qa/manual/screens/M06/M06-F-012-retired-family-offered.png`, `qa/manual/screens/M06/triage/t010-family-picker.png` (options list in the step output)
- **Root cause:** `BundleForm` asked `useFamilies` with `{ is_active: "true" }`, but the families list filters on `?active=` (`identity/api/people_filters.filter_families`); the unknown key was ignored, so retired families came back.
- **Fix (Agent 3, cycle 1, 2026-10-27):** `BundleForm.tsx`: a separate `ACTIVE_FAMILIES = { active: "true", page_size: 100 }` for the family picker (students and groups keep `is_active`, which their endpoints read).
- **Regression test:** `BundleForm.test.tsx` "offers only active families (ETQAN-QA-203)". Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. Family picker lists only the 11 active families (retired 4, 7, 9, 16 gone; matches `identity_family.is_active` in the DB). BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-203-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-204: Mobile (375px) subscriptions list widens the whole page to 666px and opens scrolled to a blank area
- **Feature:** M06 Subscriptions list (`SubscriptionsList` table). **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, viewport 375x812, AR. **Tag:** REAL
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Found by:** Agent 1, manual M06 (M06-F-022); reproduced by Agent 2 on 2026-10-27.
- **Reproduction steps:**
  1. AR, 375x812, `/app/scheduling/subscriptions`; `eval [scrollWidth, clientWidth, scrollX]`.
- **Expected:** The table scrolls inside its own box (as on the trials list); header, tabs, filters and "اشتراك جديد" visible.
- **Actual:** `[666, 375, -290]`; the first screen shows only the user button, a lone "ملغى" tab, empty input slivers and table edges.
- **Evidence:** `qa/manual/screens/M06/M06-F-022-mobile-list-page-scrolled-blank.png`, `qa/manual/screens/M06/M06-F-022b-mobile-list-666px-wide.png`, `qa/manual/screens/M06/triage/t016-mobile-list-overflow.png`
- **Root cause:** The "Actions" column header holds an `sr-only` span (`position:absolute`). Its scroller (`overflow-x-auto`) is not positioned, so the span escapes the scroll box and is placed against the page at the table's far (RTL) edge: the document grows to 666px and opens scrolled to it. Measured live: the only absolute element inside the table was that span at x=-291.
- **Fix (Agent 3, cycle 1, 2026-10-27):** `SubscriptionsList.tsx`: `relative` on the table scroller, so the span stays inside it. Same pattern elsewhere is a proposal in `qa/coverage-gaps.md` (M06 section).
- **Regression test:** `SubscriptionsList.test.tsx` "shows a short Archive row action ... keeps the sr-only header inside its scroller (ETQAN-QA-204, ETQAN-QA-214)". Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. AR 375x812 `/app/scheduling/subscriptions`: `[scrollWidth, clientWidth, scrollX] = [375, 375, 0]`; header, tabs, filters, "اشتراك جديد" visible, table scrolls in its box. BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-204-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-205: Slot "Stop" (أوقف) and pause "End early" act on one click with no confirmation or feedback
- **Feature:** M06 Subscription detail (`SlotsPanel`, `PausesPanel`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-007, M06-F-023); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR sub 96 → weekly slot "الخميس الساعة 17:00" → "أوقف".
  2. EN sub 105 → Add pause Oct 27–Oct 29 (pause "Now", 4 of 7 freeze days left) → "End early".
- **Expected:** A confirmation saying what happens (upcoming Thursday lessons removed / the pause ends today), then a toast, like cancel, archive and pause do.
- **Actual:** (1) No dialog, no toast; slot "متوقف", the Thursday lessons leave "القادمة". (2) No dialog, no toast; "No pauses.", "7 of 7 freeze days left". "أوقف" is also easy to confuse with the subscription freeze ("إيقاف").
- **Not part of this bug:** removing a pause that started today on "End early" is documented (subscriptions.md §3: "the pause is deleted if it started today").
- **Evidence:** `qa/manual/screens/M06/M06-F-007-slot-stop-no-confirm.png`, `qa/manual/screens/M06/M06-F-023a-pause-now-before.png`, `qa/manual/screens/M06/M06-F-023b-end-early-pause-vanished.png`, `qa/manual/screens/M06/triage/t007-slot-stop-no-confirm.png` (slot restarted after: `qa/manual/screens/M06/triage/t007b-slot-restarted.png`), `qa/manual/screens/M06/triage/t008b-pause-now.png`, `qa/manual/screens/M06/triage/t008c-end-early-no-confirm.png`
- **Root cause:** `SlotsPanel` and `PausesPanel` call the mutation straight from the button's `onClick` with only an `onError` toast; no confirm and no success feedback.
- **Fix (Agent 3, cycle 1, 2026-10-27):** Both now go through the shared `Confirm` (outline trigger, same accessible names as before): Stop says the slot's upcoming unmarked lessons are removed and it can be restarted; End early says the pause ends yesterday, unused freeze days come back, and a pause that started today is removed (subscriptions.md §3). Success toasts "The <day> slot is stopped." / "Pause ended." `Confirm` gained optional `triggerVariant`, `triggerName`, `actionName` (defaults unchanged). Keys in en/ar/es `scheduling.json`.
- **Regression test:** `SlotsPanel.test.tsx` "stops, restarts and deletes" and `PausesPanel.test.tsx` "shows freeze days left, ends the current pause ...": the API is not called before the dialog's confirm; the toast shows. Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. Sub 96 "أوقف" (Monday slot) opens "أوقف موعد الاثنين" with the consequence text; confirm -> toast "تم إيقاف موعد الاثنين."; restarted afterwards. Sub 105: added a pause 27-29/10, "أنهِ مبكرًا" opens "أنهِ الإيقاف اليوم"; confirm -> toast "تم إنهاء الإيقاف.", freeze days back to 7 of 7. BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-205-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-206: Raw English server messages in the Arabic UI: bundle pause "End the pause on or after its start." and teacher availability "End the window after it starts."
- **Feature:** M06 Bundle pause (`scheduling/services/subscriptions.py:542`) and teacher availability (`scheduling/services/availability.py:91`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-013, M06-F-020); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR `/app/scheduling/bundles/8` → "أوقف الحزمة مؤقتًا" → من 20/11/2026, إلى 18/11/2026 → submit.
  2. Teacher ahmad.haddad@, AR `/app/teaching/availability` → الثلاثاء "+" → 10:00 to 09:00 → "حفظ المواعيد".
- **Expected:** Arabic messages under the field ("يجب أن تكون النهاية بعد البداية"), ideally checked before sending; for a bundle, not attributed to only one member.
- **Actual:** (1) "سلمى النجار (Salma Al-Najjar) (التجويد للمبتدئين): .End the pause on or after its start", naming only one of two members (400 POST /api/v1/bundles/8/pause/). (2) ".End the window after it starts" (400 PUT /api/v1/schedule/availability/). In RTL the period jumps to the start. Same class as ETQAN-QA-049 (server text with no translated mapping); separate sites.
- **Evidence:** `qa/manual/screens/M06/M06-F-013-bundle-pause-english-error.png`, `qa/manual/screens/M06/M06-F-020-availability-english-error.png`, `qa/manual/screens/M06/triage/t011-bundle-pause-english-error.png`, `qa/manual/screens/M06/triage/t017-availability-english-error.png`
- **Root cause:** The server's `ValidationError`s carry English prose and no `code`. A subscription's own pause is checked in the dashboard first (`pauseFormSchema`), but the bundle pause dialog and the availability form sent the dates/times unchecked, so the server's English came back (the bundle version was also attributed to one member by `refusalText`).
- **Fix (Agent 3, cycle 1, 2026-10-27):** Checked before sending, in the UI's words: `BundleActions` PauseAction shows `scheduling.errors.pauseOrder` under "To" and does not call the API; `availabilityFormSchema` refines `end_time > start_time` with new `availability.errors.endAfterStart` (en/ar; `es` has no availability file and falls back to en by design). No backend change. Durable codes for these server messages: proposal in `qa/coverage-gaps.md`.
- **Regression test:** `BundleActions.test.tsx` "checks the pause dates before sending ... (ETQAN-QA-206)", `AvailabilityEditor.test.tsx` "checks the end is after the start before saving (ETQAN-QA-206)". Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. Bundle 8 pause 20/11 -> 18/11: Arabic field error "اجعل نهاية الإيقاف في يوم بدايته أو بعده.", no request sent. Teacher ahmad.haddad@ availability Tuesday 10:00 -> 09:00: "اجعل نهاية الفترة بعد بدايتها.", no PUT. (The window-overlap server message is still English: accepted proposal, see coverage-gaps M06.) BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-206-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-207: Trial date/time is scrambled in Arabic: "27‏/10‏/2026 20:00" shows as "2720:00 2026/10/"
- **Feature:** M06 Trials list and trial detail (session date-time cell, "التاريخ المرغوب"). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-014); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR `/app/scheduling/trials` (column "الحصة").
  2. AR `/app/scheduling/trials/2` ("التاريخ المرغوب", "الحصة").
- **Expected:** "2026/10/27 20:00" (date then time, readable), as elsewhere in the app.
- **Actual:** "2720:00 2026/10/", "3118:00 2026/10/", "1907:00 2026/10/": the day number glues onto the hour. Text content is right; only the bidi display is wrong.
- **Evidence:** `qa/manual/screens/M06/M06-F-014-trial-datetime-scrambled-rtl.png`, `qa/manual/screens/M06/M06-F-014b-trial-detail-datetime-scrambled.png`, `qa/manual/screens/M06/triage/t012-trials-datetime-rtl.png`, `qa/manual/screens/M06/triage/t013-schedule-trial-not-prefilled.png` (trial 2 detail)
- **Root cause:** `dayIn(..., "ar")` returns "27‏/10‏/2026" with RLM marks. The trials list joined it with the time in one string, and the trial page wrapped both in `dir="ltr"`; the bidi algorithm then glued the day onto the hour. Probe: `qa/manual/evidence/M06/fix-1/207-bidi-probe.png` (plain, isolated, forced-LTR).
- **Fix (Agent 3, cycle 1, 2026-10-27):** New `scheduling/bits.ZonedDateTime`: the day and the time each in a `<bdi>`, no forced direction. Used for the trials list session cell, the trial page "Desired date" and the session line.
- **Regression test:** `bits.test.tsx` "isolates the day from the time", `TrialsList.test.tsx` (two isolates in the row). Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. Trials list row reads "2026/10/27 20:00" and the trial page "18:00 2026/10/31" (day and time each in a `<bdi>`), not "2720:00 2026/10/". BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-207-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-208: Count grammar: Arabic "0 من 8 حصة", "8 حصة … خلال 1 شهر", "(5 يوم)", "متبقٍ 2 من 7 يوم تجميد"; English "over 1 months"
- **Feature:** M06 Subscriptions copy (`locales/{ar,en}/scheduling.json` keys `progress`, `packageFacts`, `days`, `months`, `pausedDays`, `left`, `range`, `carries`; `catalogue.json totalShort`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-002); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR subscriptions list (progress column), sub 94 detail (caption under the bar, pauses card), sub 96 ("يشمل 5 يوم إيقاف"), New subscription after picking a package (summary). EN New subscription with a 1-month package.
- **Expected:** Arabic plural forms (i18next `_one/_two/_few/_many/_other`): "8 حصص", "شهر واحد", "5 أيام", "7 أيام تجميد"; English "1 month".
- **Actual:** Single fixed strings: "{{used}} من {{total}} حصة", "{{count}} يوم", "{{count}} شهر", "{{count}} months"; no plural keys in scheduling.json.
- **Evidence:** `qa/manual/screens/M06/M06-F-002-arabic-count-grammar-list.png`, `qa/manual/screens/M06/M06-F-002b-arabic-count-grammar-form.png`, `qa/manual/screens/M06/s020.png`, `qa/manual/screens/M06/s062.png`, `qa/manual/screens/M06/triage/t003-sub94-detail-ar.png`, `qa/manual/screens/M06/triage/t007-slot-stop-no-confirm.png`
- **Root cause:** Single fixed strings with `{{count}}`/`{{total}}`/`{{allowed}}` and no plural keys, so i18next could not pick a form.
- **Fix (Agent 3, cycle 1, 2026-10-27):** Plural keys (`_one/_other` en/es; `_zero/_one/_two/_few/_many/_other` ar) for `scheduling.progress`, `summary.pausedDays`, `form.packageFacts`, `form.days`, `form.months`, `pauses.left`, `pauses.range`, `renew.carries` and `catalogue.packages.totalShort`; call sites pass `count` (`bits.SubscriptionProgress` count=total, `TermFields` count=sessions, `PausesPanel` count=allowed). Now "0 من 8 حصص", "خلال شهر واحد", "5 أيام", "over 1 month".
- **Regression test:** New `scheduling/countCopy.test.ts`; `SubscriptionForm.test.tsx` updated to "over 1 month". Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. AR: "0 من 8 حصص", "8 حصص، مدة كل منها 45 دقيقة، خلال شهر واحد", "(3 أيام)", "يشمل 5 أيام إيقاف", "متبقٍ 4 من 7 أيام تجميد"; EN: "8 sessions of 45 minutes over 1 month". BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-208-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-209: Mixed Arabic/Latin person names wrap with the hyphen and parenthesis on the wrong side: "الشيخ أحمد الحداد (-Ahmad Al" / "Haddad)"
- **Feature:** M06 Subscription summary, session page, trial detail, subscriptions list (name cells). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-004); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR sub 94 or 96 detail, "المعلم"; also session 445 and trial 2 ("المعلم"); list rows for Ibrahim at 1440 (all-rows view).
- **Expected:** "الشيخ أحمد الحداد" / "(Ahmad Al-Haddad)" with the Latin part isolated (`<bdi>` / `unicode-bidi: isolate` on the parenthesised part).
- **Actual:** "الشيخ أحمد الحداد (-Ahmad Al" on line 1, "Haddad)" on line 2; list rows show "إبراهيم حسن (Ibrahim / Hassan)" split the same way. Related to ETQAN-QA-060 (Latin text in inputs/header), different components.
- **Evidence:** `qa/manual/screens/M06/M06-F-004-teacher-name-bidi-wrap.png`, `qa/manual/screens/M06/triage/t003-sub94-detail-ar.png`, `qa/manual/screens/M06/triage/t014-attendance-unlabeled.png`, `qa/manual/screens/M06/triage/t002-list-ibrahim-two-active-ar.png`
- **Root cause:** Names were printed as one run in RTL, so the Latin "(Ahmad Al-Haddad)" part's brackets and hyphen resolved to the paragraph direction when the line wrapped. Probe: `qa/manual/evidence/M06/fix-1/209-bidi-probe.png`.
- **Fix (Agent 3, cycle 1, 2026-10-27):** New `scheduling/bits.PersonName`: each "(…)" part in a `<bdi>` (the element form of M03's `lib/bidi.bidiName`, without invisible marks so link names and copies stay plain). Used for student/teacher names on the subscriptions list, subscription summary, session page and trial page.
- **Regression test:** `bits.test.tsx` "isolates the parenthesised Latin part of a name", "leaves a plain name alone". Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. Sub 94 summary: "الشيخ أحمد الحداد (Ahmad Al-" / "Haddad)" (bracket and hyphen in place); same on the list (desktop and 375px), session 445 and trial 2. The expanded weekly calendar was not in this bug's scope and still wraps wrongly: filed as ETQAN-QA-216. BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-209-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-210: No timezone shown for weekly slot times on the create form, the slot list and the sessions table
- **Feature:** M06 New subscription (`SlotFields` "وقت البدء"), subscription detail slot list and sessions table. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-003); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR `/app/scheduling/subscriptions/new` → "المواعيد الأسبوعية" → "وقت البدء".
  2. Sub 94 detail: "الأربعاء الساعة 17:00", sessions table "17:00".
- **Expected:** "(بتوقيت الأكاديمية)" / "academy time", as the slot edit dialog, the trial dialog and the availability page already say (slot times are on the academy wall clock, subscriptions.md Concepts).
- **Actual:** Bare time field and bare times.
- **Evidence:** `qa/manual/screens/M06/M06-F-003-no-timezone-on-slot-time.png`, `qa/manual/screens/M06/triage/t001-new-sub-form-ar.png`, `qa/manual/screens/M06/triage/t003-sub94-detail-ar.png`
- **Root cause:** The labels/columns are plain "Start time" / "Time"; only the slot edit dialog body mentioned the academy clock.
- **Fix (Agent 3, cycle 1, 2026-10-27):** `scheduling.slots.startTime` → "Start time (academy time)" / "وقت البدء (بتوقيت الأكاديمية)"; `sessions.columns.time` → "Time (academy time)" (sessions table and session page); new `slots.zoneNote` under the Weekly slots title. en/ar/es.
- **Regression test:** `SlotsPanel.test.tsx` (note + label), `SessionsPanel.test.tsx` (column header "Time (academy time)"). Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. Create form label "وقت البدء (بتوقيت الأكاديمية)" / "Start time (academy time)"; slot panel note "الأوقات بتوقيت الأكاديمية." / "Times are in academy time."; sessions column "الوقت (بتوقيت الأكاديمية)". BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-210-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-211: Bundle page has no active sidebar item, no back link and a generic title
- **Feature:** M06 Bundle detail (`/app/scheduling/bundles/<id>`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-011); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR `/app/scheduling/bundles/8` (or 7).
- **Expected:** "الاشتراكات" highlighted in the sidebar and a back link like the archive page ("العودة إلى القائمة").
- **Actual:** No sidebar item highlighted, no back link, title "حزمة اشتراكات" only.
- **Evidence:** `qa/manual/screens/M06/M06-F-011-bundle-page-no-nav-highlight.png`, `qa/manual/screens/M06/triage/t011-bundle-pause-english-error.png` (background)
- **Root cause:** The sidebar marks an item only when the path starts with its `to`; `/scheduling/bundles/…` matches none. The page had no back link and its card title was the bare kind.
- **Fix (Agent 3, cycle 1, 2026-10-27):** `NavItem.also` (new, optional) with `/scheduling/bundles` on Subscriptions and My subscriptions; `AppSidebar` sets `aria-current` on also-paths (M03's role-label changes kept). `BundlePage`: back link ("Back to the list": office → `/scheduling/subscriptions`, else `/learning/subscriptions`) and card title "<kind> bundle". Page header still generic: follow-up in `qa/coverage-gaps.md`.
- **Regression test:** `AppSidebar.test.tsx` "keeps Subscriptions active on a bundle's page (ETQAN-QA-211)", `BundlePage.test.tsx` (title + back link). Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. `/app/scheduling/bundles/7` (EN) and `/8` (AR): sidebar "Subscriptions"/"الاشتراكات" has aria-current=page, "Back to the list" goes to `/app/scheduling/subscriptions`, card title "Multi-course bundle" / "حزمة عائلية". Page header and browser title stay generic (accepted proposal). BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-211-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-212: "Schedule trial" dialog doesn't prefill the requested date/time and has no Cancel button
- **Feature:** M06 Trials (`ScheduleTrialDialog.tsx`: `defaultValues: EMPTY`; footer has only the SubmitButton). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-015); confirmed by Agent 2 on 2026-10-27 from Agent 1's screenshot and the code (trial 2 has since been scheduled, so the button is gone; no new trial was created).
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. Create a trial request with "التاريخ المرغوب" 31/10/2026 18:00 → detail → "جدولة".
- **Expected:** Date and time prefilled from the request (still editable); an "إلغاء" button like the other dialogs.
- **Actual:** Empty dd/mm/yyyy and --:-- fields; only "جدولة"; closing needs Esc or a click outside.
- **Evidence:** `qa/manual/screens/M06/M06-F-015-schedule-trial-not-prefilled.png`; code `dashboard/src/features/scheduling/ScheduleTrialDialog.tsx` lines 42, 102, 343-347.
- **Root cause:** `ScheduleTrialDialog` used `defaultValues: EMPTY` and reset to `EMPTY`; the footer had only the submit button.
- **Fix (Agent 3, cycle 1, 2026-10-27):** `startingValues(trial, academyZone)` fills the day and time from `desired_at` on the academy clock (editable; empty when none) and is used for both default and reset; a Cancel (`DialogClose`) button sits before Schedule.
- **Regression test:** `ScheduleTrialDialog.test.tsx` "opens on the requested day and time, and has Cancel (ETQAN-QA-212)". Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. Trial 4 (created by the gate, desired 03/11/2026 19:30): "جدولة" opens with 03/11/2026 and 19:30 (after the DST change, still correct); "إلغاء" closes it; reopening after editing the time resets to 19:30. BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-212-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-213: Session page attendance: the student and teacher dropdowns have no visible labels
- **Feature:** M06/sessions Session page, section "الحضور". **Severity:** P3. **Type:** a11y. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-016); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR `/app/scheduling/sessions/445` → "الحضور".
- **Expected:** Visible labels "حضور الطالب" / "حضور المعلم".
- **Actual:** Two identical selects side by side ("حاضر" / "حاضر"); the role is only in aria-label ("حضور الطالب فاطمة الزهراء…", "حضور المعلم مع …"); no `<label>`.
- **Evidence:** `qa/manual/screens/M06/M06-F-016-attendance-selects-unlabeled.png`, `qa/manual/screens/M06/triage/t014-attendance-unlabeled.png`
- **Root cause:** `AttendanceControls` gives each select only an `aria-label`; fine in a table row under column headers, unlabeled on the session page.
- **Fix (Agent 3, cycle 1, 2026-10-27):** New `labelled` prop renders a visible `<label for>` ("Student attendance" / "Teacher attendance", ar "حضور الطالب" / "حضور المعلم", es) above each select; `SessionPage` passes it. Tables unchanged.
- **Regression test:** `AttendanceControls.test.tsx` "shows a visible label on each select when labelled (ETQAN-QA-213)" and "shows no labels in a table row". Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. Session 445 AR/EN: visible labels "حضور الطالب"/"حضور المعلم" and "Student attendance"/"Teacher attendance", each a `<label for>` bound to its select. BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-213-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-214: Subscriptions list: the long red "Archive (delete keeping records)" row button squeezes the table, so dates and names wrap over 2–3 lines
- **Feature:** M06 Subscriptions list (`ArchiveActions` row button). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-017); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. EN and AR `/app/scheduling/subscriptions` (All tab) at 1440.
- **Expected:** A compact "Archive" row action (the confirm dialog already explains it); dates on one line.
- **Actual:** "Archive (delete keeping records)" / "أرشفة (حذف مع الاحتفاظ بالسجلات)" as a large danger button on every ended row; "Dec / 20, / 2026" over 3 lines, teacher names over 3 lines.
- **Evidence:** `qa/manual/screens/M06/M06-F-017-en-list-ends-wraps-archive-label.png`, `qa/manual/screens/M06/s002.png`, `qa/manual/screens/M06/triage/t015-en-list-archive-label.png`, `qa/manual/screens/M06/triage/t002-list-ibrahim-two-active-ar.png`
- **Root cause:** Spec B2d §7 names the action "Archive (delete keeping records)" and the list row used that full text as a destructive button, squeezing the other columns; the Ends cell could wrap.
- **Fix (Agent 3, cycle 1, 2026-10-27):** `ArchiveSubscriptionButton compact` on list rows: visible "Archive" / "أرشفة" / "Archivar" (new `archives.subscriptions.rowAction`), with the spec's full label kept as the accessible name and tooltip; the detail page keeps the full label. Ends and Archived cells `whitespace-nowrap`.
- **Regression test:** `SubscriptionsList.test.tsx` (same test as QA-204: visible text "Archive", name "Archive (delete keeping records)", nowrap Ends). Evidence: `qa/manual/evidence/M06/fix-1/` (tsc.txt exit 0, vitest.txt 526/527 then vitest-bits-rerun.txt + vitest-names-rerun.txt green, biome.txt clean). Dashboard branch `qa/manual-2026-10`, not committed.
- **Verification (Agent 2, gate cycle 1, 2026-10-27):** re-walked in the browser. EN list rows show a compact "Archive" button, Ends on one line ("Dec 18, 2026"); AR cancelled tab shows "أرشفة" with accessible name and tooltip "أرشفة (حذف مع الاحتفاظ بالسجلات)"; the confirm still explains. Archived the gate's own sub 106 through it. BEFORE/AFTER: `qa/manual/screens/M06/fix/ETQAN-QA-214-after.png`. Diff reviewed (root cause, no test weakened); scoped Vitest 71 files / 523 tests pass, tsc 0 (`qa/manual/evidence/M06/gate-1/vitest-tsc.txt`).
- **Verification status:** VERIFIED

---

## ETQAN-QA-215: Price label shows empty parentheses "السعر ()" / "Price ()" until a package is picked
- **Feature:** M06 New subscription (individual and family course rows). **Severity:** P4. **Type:** copy. **Easy P3:** no (P4). **Priority:** low
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + parallel manual fixes), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M06 (M06-F-006); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `QA-People-2026!`. Test data from M06 Agent 1: subs 94–98, 103–105, bundles 7–8, trials 2–3.
- **Reproduction steps:**
  1. AR `/app/scheduling/subscriptions/new` (individual or "عائلي").
- **Expected:** "السعر" alone (or the academy currency) before a package is chosen.
- **Actual:** "السعر ()"; after a package, "السعر (EGP)".
- **Evidence:** `qa/manual/screens/M06/M06-F-006-price-label-empty-parens.png`, `qa/manual/screens/M06/triage/t001-new-sub-form-ar.png`, `qa/manual/screens/M06/triage/t010-family-picker.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-216: Expanded weekly calendar: mixed Arabic/Latin names wrap with the bracket and hyphen on the wrong side ("Adam Al-) آدم النجار" / "(Najjar")
- **Feature:** M06 Weekly schedules, expanded calendar (`ScheduleCalendar.tsx` event cards: student line and "course · teacher" line). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + manual fix cycle 1, branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900, AR. **Tag:** REAL
- **Found by:** Agent 2, M06 gate cycle 1 (calendar smoke after the ETQAN-QA-209 fix).
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; realistic students and teachers from `qa/manual/data.md`.
- **Reproduction steps:**
  1. AR `/app/scheduling/schedules/calendar` (desktop).
  2. Look at the cards for Mona, Adam, Khalid, Salma, Hamza and at the teacher lines (Ahmad, Maryam, Yousef).
- **Expected:** As after the ETQAN-QA-209 fix: "منى السيد (Mona Al-" / "Sayed)", with the "(Latin)" part kept whole and in order.
- **Actual:** "Mona Al-) منى السيد" / "(Sayed", "Adam Al-) آدم النجار" / "(Najjar", teacher lines "أحمد الحداد (-Ahmad Al" / "(Haddad". The narrow calendar cards make every such name wrap.
- **Evidence:** `qa/manual/screens/M06/triage/t020-calendar-name-bidi-wrap.png` (crop, 2x), `qa/manual/screens/M06/fix/smoke-cal-ar.png`
- **Notes:** Same class as ETQAN-QA-209 (fixed with `bits.PersonName` on the list, summary, session and trial pages). The calendar cards were not listed in 209 and don't use it. Fix: `PersonName` for the student and teacher names in `ScheduleCalendar`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-217: Deleting a pause or a stopped weekly slot happens on one click, with no confirmation and no message
- **Feature:** M06 Subscription detail (`PausesPanel` "حذف"/"Delete" on a pause row, `SlotsPanel` "حذف"/"Delete" on a stopped slot). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + manual fix cycle 1, branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900, AR. **Tag:** REAL
- **Found by:** Agent 1, M06 confirmation sweep (M06-F-024); reproduced by Agent 2 at the final gate on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR `/app/scheduling/subscriptions/105` → "أضف إيقافًا" 10/11–12/11/2026, reason "M06-gate2 delete test" → row "من 2026/11/10 إلى 2026/11/12 (3 أيام)", "قادم", "متبقٍ 4 من 7 أيام تجميد".
  2. Click the pause row's red "حذف".
  3. (Agent 1, sub 107) Stop a weekly slot ("أوقف", which now confirms) → on the "متوقف" row click "حذف".
- **Expected:** The same confirmation the ETQAN-QA-205 fix added for "أوقف" and "أنهِ مبكرًا" (e.g. "احذف هذا الإيقاف؟" / "احذف موعد الجمعة؟" with what happens and a Cancel button), then a success toast.
- **Actual:** The pause disappears at once: no dialog (0 `[role=dialog]`), no toast; "لا توجد إيقافات." and "متبقٍ 7 من 7 أيام تجميد". The stopped slot row also disappears at once (Agent 1). Deleting is permanent, unlike stop/restart.
- **Evidence:** `qa/manual/screens/M06/triage/t023d-pause-before-delete.png`, `qa/manual/screens/M06/triage/t023e-pause-deleted-no-confirm.png`, `qa/manual/screens/M06/M06-F-024a-pause-before-delete.png`, `qa/manual/screens/M06/M06-F-024b-pause-deleted-no-confirm.png`, `qa/manual/screens/M06/M06-F-024c-stopped-slot-deleted-no-confirm.png`
- **Notes:** Same pattern as ETQAN-QA-205 (fixed for Stop and End early only). The code shows it: `PausesPanel.tsx:221` and `SlotsPanel.tsx:289` call `remove.mutate(id, { onError: fail })` straight from the button. Fix: wrap both in the shared `Confirm` (as 205 did) and add success toasts. Related ETQAN-QA-160/165 (M04, same class elsewhere).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-218: Weekly schedules list and admin Sessions list (AR): "Arabic (Latin)" names wrap with the bracket and hyphen on the wrong side ("Hamza Al-) حمزة القاضي" / "(Qadi")
- **Feature:** M06 `/app/scheduling/schedules` (`SchedulesList.tsx`: student/bundle column and the slot line "… · teacher") and `/app/scheduling/sessions` (`SessionsList.tsx`: student and teacher columns). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9, dashboard 5ed775d + manual fix cycle 1, branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900, AR. **Tag:** REAL
- **Found by:** Agent 1, M06 confirmation sweep (M06-F-025); reproduced by Agent 2 at the final gate on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; realistic students and teachers from `qa/manual/data.md`.
- **Reproduction steps:**
  1. AR `/app/scheduling/schedules`, tab "نشطة".
  2. AR `/app/scheduling/sessions` (today).
- **Expected:** As on the subscriptions list after ETQAN-QA-209: "حمزة القاضي (Hamza Al-" / "Qadi)", with the "(Latin)" part whole and in order.
- **Actual:** (1) Student column "Hamza Al-) حمزة القاضي" / "(Qadi", "Fatima Al-) فاطمة الزهراء" / "(Zahra"; family row slot lines end "(Yousef" / "(Al-Mansouri" and "(Maryam" / "(Al-Khatib". (2) Student "Hamza Al-) حمزة القاضي" / "(Qadi"; teacher "Ahmad Al-) الشيخ أحمد الحداد" / "(Haddad", "Maryam Al-) الأستاذة مريم الخطيب" / "(Khatib".
- **Evidence:** `qa/manual/screens/M06/triage/t021-weekly-schedules-names.png`, `qa/manual/screens/M06/triage/t022-sessions-list-names.png`, `qa/manual/screens/M06/M06-F-025-weekly-schedules-name-parens-broken.png`, `qa/manual/screens/M06/M06-F-025b-admin-sessions-list-name-parens-broken.png`
- **Notes:** Same class as ETQAN-QA-209 (list/summary/session/trial), ETQAN-QA-111 (teacher table) and ETQAN-QA-216 (calendar). `bits.PersonName` is used only in SubscriptionsList, SubscriptionDetail, SessionPage, TrialPage and TeacherSessionTable; SchedulesList and SessionsList still render the bare string. Fix: `PersonName` there (Agent 3 may do it together with 216).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## --- M03 manual bugs ---

## ETQAN-QA-100: Arabic admin Home: the exchange-rate note glues "لـ" to the Latin codes ("أضف أسعار الصرف لـ KWD, USD" shows as "KWD, USD J")
- **Feature:** M03 Home / finance card (RTL). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack, academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL
- **Found by:** Agent 1, manual M03 (M03-F-001); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, language AR; KWD/USD revenue without exchange rates.
- **Reproduction steps:** 1. Sign in (AR) → `/app/`. 2. Card "المصروفات والتبرعات", line under "صافي ربح هذا الشهر".
- **Expected:** "أضف أسعار الصرف لـ KWD وUSD لعرض التقدير", reading naturally right to left (codes isolated, Arabic list joiner).
- **Actual:** "أضف أسعار الصرف ... KWD, USD J لعرض التقدير": the kashida "لـ" sticks to the Latin run and looks like a Latin "J"; the codes are joined with a Latin comma (`finance.json` `missing`: "لـ {{codes}} …").
- **Evidence:** `qa/manual/screens/M03/M03-F-001-fx-note-bidi-ar.png`, `qa/manual/screens/M03/triage/t001-admin-home-ar.png`
- **Root cause:** `FinanceSummaryCard`/`ProjectionsPage` joined the codes with a Latin `", "` and the Arabic text put a lone kashida `لـ ` before the Latin run (`finance.json` `estimate.missing`), so in RTL the lam-tatweel stood beside the Latin and read as "J".
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** New `dashboard/src/lib/bidi.ts` (`isolate`, `listOf`): the codes are joined with `Intl.ListFormat` in the UI language ("KWD وUSD", "KWD and USD"), each code an FSI…PDI isolate; Arabic text now "أضف أسعار الصرف للعملات {{codes}} لعرض التقدير" (no lone لـ).
- **Regression test:** `src/lib/bidi.test.ts`; `FinanceSummaryCard.test.tsx` "names the missing currencies in Arabic with each code isolated" (+ EN expectations updated); `ProjectionsPage.test.tsx`. Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** AR admin Home: note reads "أضف أسعار الصرف للعملات KWD وUSD لعرض التقدير", no stray J. `qa/manual/screens/M03/fix/ETQAN-QA-100-before-after.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-101: Admin Home repeats every sidebar item as ~69 tiles in an order unrelated to the sidebar groups; only "Account" has a description
- **Feature:** M03 Home (office). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** as ETQAN-QA-100, EN and AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-002); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** qa-admin, academy `qa` (all switches on).
- **Reproduction steps:** 1. Sign in (EN) → `/app/`. 2. Scroll below the money cards.
- **Expected:** a short, grouped set of shortcuts (or tiles in the sidebar's groups), described consistently.
- **Actual:** 69 links in `main`, page 3,931 px tall; order mixes groups (Today, Sessions, Missing reports, Subscriptions, Invoices, Payslips, Rates, Adjustments, Students …, Trials, Study groups …). "Rates"/"Adjustments" lack their Payroll context. Only the last tile "Account" has a description, leaving it alone on its own row.
- **Evidence:** `qa/manual/screens/M03/M03-F-002-home-tiles-no-order-en.png`, `qa/manual/screens/M03/triage/t009-admin-home-tiles-en.png`
- **Root cause / Fix / Regression tests:** _Agent 3 (design proposal; not an easy fix)_
- **Verification status:** OPEN

## ETQAN-QA-102: Notification texts mix Latin names, amounts and ISO dates into Arabic without isolation ("لـSCN Student B1" shows as "SCN Student B1J", date "26-10-2026.", raw "1,500.00 EGP"), title and body aligned differently
- **Feature:** M03 Notifications (bell + `/app/notifications`). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** as ETQAN-QA-100. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-003, body part of M03-F-007); reproduced by Agent 2 on 2026-10-27.
- **Note:** the Arabic language of the texts in the English UI is by design (notifications.md: rendered once in the recipient's `preferred_language`; qa-admin's is `ar`). This bug is only the rendering/formatting.
- **Preconditions:** qa-admin with overdue-invoice notifications.
- **Reproduction steps:** 1. Sign in (EN or AR) → `/app/notifications` (or open the bell).
- **Expected:** names, invoice numbers, amounts and dates isolated in the Arabic text (e.g. `<bdi>`/`dir="auto"` on the body, FSI/PDI around placeholders) and formatted like the rest of the app (locale date, "‏1,500.00 ج.م.‏"); title and body share one alignment.
- **Actual:** "كانت الفاتورة INV-000149 لـSCN Student B1 (50.00 EGP) مستحقة في 2026-10-26." renders as "…SCN Student B1J …", the ISO date reads "26-10-2026.", the amount uses the raw "50.00 EGP" form; on the EN page the title is left-aligned and the body right-aligned in the same card. In the AR bell the amount's brackets split across lines.
- **Evidence:** `qa/manual/screens/M03/M03-F-003-notifications-arabic-in-english-ui.png`, `qa/manual/screens/M03/triage/t006-notifications-page-en.png`, `qa/manual/screens/M03/triage/t002-bell-panel-ar.png`
- **Root cause:** Backend `notifications/text.py` `render()` dropped Latin names, numbers, amounts and ISO dates into Arabic templates bare, so the bidi algorithm reordered them ("لـSCN Student B1" → "…B1J", brackets of the amount split). Dashboard `NotificationText` gave the title and the body each their own `dir="auto"` (title inline inside a LTR row, body a block), so they aligned on different sides.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Backend: in Arabic every filled-in value is wrapped in FSI…PDI (`text.isolate`), English unchanged (stored text is never re-rendered, N8-4: only notices created after the fix change). Dashboard `notifications/bits.tsx`: one `dir="auto"` on the whole notice (title + body share it), the time line keeps the UI's direction (`useDir`). Not done (proposal-level): locale-formatted amounts/dates inside stored notification text.
- **Regression test:** pytest `notifications/tests/test_text.py::test_arabic_text_isolates_every_value_and_english_is_unchanged` (+ Arabic expectations in test_text/test_scan/test_chat_notice updated; notifications+devices+chat 729 passed); Vitest `notifications/bits.test.tsx` "gives the title and body one direction from their text". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** new rows created through the real renderer (`scan._row`, invoice INV-000149, ids 564 AR / 565 EN, email skipped). Fixed part: the Arabic body now keeps its order ("(50.00 EGP)" stays in its brackets, "2026-10-26." with the full stop at the end), and title + body now align on one side in the EN UI. **Still failing:** the template's lone "لـ" sits right before the isolated Latin name, so it still renders glued to it and reads "SCN Student B1J" (the first symptom in this bug's title). Same remedy as ETQAN-QA-100: change the Arabic notification templates so the lam is not alone before a filled value (e.g. "للطالب {student}" / "لـ {student}" with a word). `qa/manual/screens/M03/fix/ETQAN-QA-102-before-after.png`, `qa/manual/screens/M03/fix/g22-zoom-new-row-ar.png`, `qa/manual/screens/M03/fix/g22-notifications-new-ar.png`. The follow-up proposal (format amounts/dates in each recipient's language, N8-4) is **PROPOSAL-accepted** (in `qa/coverage-gaps.md`; not a defect of the reported symptoms).
- **M10 dup (Agent 2, 2026-10-28):** M10-F-012: absence notice and email still read "في ⁨2026-10-28 03:30 (Africa/Cairo)⁩" — ISO date plus the English IANA id in Arabic text (bell, `/notifications`, email; also postpone/make-up). Part of this bug's open locale-date proposal, not re-filed. Evidence `qa/manual/screens/M10/triage/t012-parent-notifications.png`, `qa/manual/screens/M10/triage/t014-absence-email.png`.
- **Verification status:** OPEN (reopened by gate; easy P3, queue for next fix cycle)

## ETQAN-QA-103: The bell list is taller than the window (≈1,104 px on 900 px): "See all" is off-screen and a normal click on it fails
- **Feature:** M03 Top bar / notifications panel. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** as ETQAN-QA-100, EN and AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-004); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** a user with many notifications (qa-admin, 99+ unread).
- **Reproduction steps:** 1. `/app/` → click the bell. 2. Try to reach "See all".
- **Expected:** the panel's height is capped to the viewport and the list scrolls inside it; "See all" stays visible.
- **Actual:** panel top 58 px, height 1,104 px, `scrollHeight == clientHeight` (no inner scroll); "See all" is below the fold and Playwright's normal click times out while the menu is open.
- **Evidence:** `qa/manual/screens/M03/M03-F-004-bell-panel-taller-than-screen.png`, `qa/manual/screens/M03/M03-F-004b-bell-see-all-only-after-scroll.png`, `qa/manual/screens/M03/triage/t002-bell-panel-ar.png`
- **Root cause:** `NotificationBell` `DropdownMenu.Content` had no max height and no scroll container, so ten notices made it ≈1,100 px tall.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Content is a flex column capped at Radix's `--radix-dropdown-menu-content-available-height`; header, separators and "See all" are `shrink-0`, the list sits in a `min-h-0 flex-1 overflow-y-auto` box.
- **Regression test:** `NotificationBell.test.tsx` "caps the panel's height and scrolls only the list". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** AR bell panel 58→900 px on a 900 px window, list scrolls (998/736), header + "عرض الكل" always visible. `qa/manual/screens/M03/fix/ETQAN-QA-103-before-after.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-104: Arabic UI: the account menu and the notifications panel open left-to-right (dir="ltr", glued to the left edge); the bell time stamps come out scrambled ("2721:15 ،2026/10/")
- **Feature:** M03 Top bar menus (RTL). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** as ETQAN-QA-100, AR, desktop and 375x812. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-006, M03-F-007 is its consequence); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** any signed-in user, language AR.
- **Reproduction steps:** 1. `/app/` (AR) → click the user button. 2. Click the bell.
- **Expected:** both popovers inherit RTL: items right-aligned with icons on the right, "الإشعارات" on the right and "تعليم الكل كمقروء" on the left, a gap from the window edge; time "2026/10/27، 21:15".
- **Actual:** computed `direction: ltr`, popover `left: 0`; items left-aligned with icons on the left; bell header mirrored; every time stamp shows "2721:15 ،2026/10/" (the RTL date string laid out in an LTR box). Same on the phone.
- **Evidence:** `qa/manual/screens/M03/M03-F-006-account-menu-ltr-in-arabic.png`, `qa/manual/screens/M03/M03-F-006b-bell-panel-ltr-in-arabic.png`, `qa/manual/screens/M03/M03-F-007-bell-time-garbled-ar.png`, `qa/manual/screens/M03/M03-F-007b-mobile-bell-garbled-ar.png`, `qa/manual/screens/M03/triage/t003-account-menu-ar.png`, `qa/manual/screens/M03/triage/t002-bell-panel-ar.png`
- **Root cause:** Radix primitives read direction from Radix's own `DirectionProvider`; the app set only `<html dir>`, so every portalled DropdownMenu (account menu, bell) defaulted to `ltr` and stamped `dir="ltr"` on its content (the RTL date string in a LTR box gave "2721:15 ،2026/10/").
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `lib/direction.tsx` `DirectionProvider` now also wraps the app in Radix `Direction.Provider` with the current dir, so all Radix menus/popovers follow the language (complements M02's per-component `useDir`, QA-061).
- **Regression test:** `lib/direction.test.tsx` "opens Radix menus right-to-left in Arabic". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** AR account menu and bell panel `dir=rtl`, anchored under their buttons; bell time reads "2026/10/27، 21:15". `qa/manual/screens/M03/fix/ETQAN-QA-104-before-after.png`, `qa/manual/screens/M03/fix/g02-bell-ar.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-105: An unknown `/app/...` address shows a blank page with the English words "Not Found" (no app shell, no Arabic, no way back)
- **Feature:** M03 Routing / 404. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** as ETQAN-QA-100, AR and EN. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-008); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** signed in (any role).
- **Reproduction steps:** 1. Open `http://qa.etqan.localhost/app/this-does-not-exist`.
- **Expected:** a translated not-found page inside the app layout ("الصفحة غير موجودة" + "العودة إلى الرئيسية"), like the existing NoAccess/FeatureOff pages.
- **Actual:** cream page, only "Not Found" (TanStack Router default) in the top corner. The router has no `notFoundComponent` (`grep` in `dashboard/src`).
- **Evidence:** `qa/manual/screens/M03/M03-F-008-404-bare-not-found.png`, `qa/manual/screens/M03/triage/t004-404-ar.png`
- **Root cause:** No route matched unknown paths and no not-found component existed, so TanStack Router's default bare "Not Found" rendered outside the shell.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** New catch-all `routes/_authed/$.tsx` (inside the signed-in layout, so the shell and auth guard apply) rendering new `shell/NotFound.tsx` (InfoScreen: translated title/body + "Back to home"); keys `access.notFound.*` en/ar/es; `routeTree.gen.ts` regenerated by the plugin.
- **Regression test:** `routes/_authed/$.test.tsx` (EN + AR). Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** `/app/this-does-not-exist` (AR) and `/app/people/nope/deeper` (EN) show the translated not-found screen inside the app shell with "Back to home". `qa/manual/screens/M03/fix/ETQAN-QA-105-before-after.png`, `qa/manual/screens/M03/fix/g05-404-en.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-106: Opening a record that doesn't exist: the student page spins forever; the invoice page retries the 404 four times before "couldn't be found"
- **Feature:** M03 Detail pages (people, billing). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** as ETQAN-QA-100. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-009); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** qa-admin.
- **Reproduction steps:** 1. `/app/people/students/999999` (AR), wait 6 s. 2. `/app/billing/invoices/999999` (EN), look at once.
- **Expected:** at once "This student/invoice doesn't exist or was deleted" with a link back to the list; no retries for a 404.
- **Actual:** (1) heading "الطالب", a spinner that never ends, and a "الرصيد" card with "تعذّر تحميل الرصيد."; 404s for people/students, chat/access, notifications/preferences, wallet/students. (2) spinner while `GET billing/invoices/999999/` is retried (4× per Agent 1; 2 already within the first second), then "This invoice couldn't be found." without a back link.
- **Evidence:** `qa/manual/screens/M03/M03-F-009-missing-student-spinner-ar.png`, `qa/manual/screens/M03/M03-F-009b-missing-invoice-spinner-en.png`, `qa/manual/screens/M03/triage/t005-missing-student-ar.png`, `qa/manual/screens/M03/triage/t007-missing-invoice-early-en.png`
- **Root cause / Fix / Regression tests:** _Agent 3_ (query retry on 4xx; student detail has no error state)
- **Verification status:** OPEN

## ETQAN-QA-107: Top bar cuts the user's name to ~100 px even with plenty of room ("QA Staff NoC…", "QA Other Ad…", "الأستاذة مريم الـ…")
- **Feature:** M03 Top bar / user menu. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** as ETQAN-QA-100, 1440x900. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-010); reproduced by Agent 2 on 2026-10-27. (The "ellipsis at the wrong end" part is no longer seen after ETQAN-QA-060's `dir="auto"`.)
- **Preconditions:** qa-staff-nocode@ (AR); maryam.khatib@; qaother-admin.
- **Reproduction steps:** 1. Sign in → look at the user button in the top bar.
- **Expected:** the full name when the bar has room (a larger max-width, truncation only on narrow screens), with the full name as a tooltip.
- **Actual:** "QA Staff NoC…", "QA Other Ad…", "الأستاذة مريم الـ…", "محمود الشريف (…" on a 1440 px wide bar with most of it empty.
- **Evidence:** `qa/manual/screens/M03/M03-F-010-user-name-truncated-ar.png`, `qa/manual/screens/M03/triage/t010-staff-nocode-home-ar.png`, `qa/manual/screens/M03/triage/t014-maryam-home-ar.png`, `qa/manual/screens/M03/triage/t018-parent-home-en.png`
- **Root cause:** `UserMenu` name span capped at `max-w-[12ch]` on every width.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Cap `12ch` only at `sm`, `20ch` at `md`, `32ch` at `lg`; full name as `title` tooltip (M02's `dir="auto"` kept).
- **Regression test:** `UserMenu.test.tsx` "hides the name on the smallest screens…" (width classes + title). Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** Full names shown at 1440 px: "QA Staff NoCode", "الأستاذة مريم الخطيب (Maryam Al-Khatib)". `qa/manual/screens/M03/fix/ETQAN-QA-107-before-after.png`, `qa/manual/screens/M03/fix/g11-maryam-home-ar.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-108: A staff member with no permissions lands on a nearly empty Home with no explanation
- **Feature:** M03 Home (office, no codes). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** as ETQAN-QA-100, AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-011); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** qa-staff-nocode@qa.etqan.test / `QA-People-2026!` (staff with no role codes).
- **Reproduction steps:** 1. Sign in → `/app/`.
- **Expected:** an empty-state line such as "No screens are assigned to your role yet. Ask an admin." (wording like NoAccess: "أدوارك لا تشمل هذه الشاشة. اطلب من أحد المديرين…").
- **Actual:** greeting + two tiles (المحادثات without description, الحساب with one) and nothing else.
- **Evidence:** `qa/manual/screens/M03/M03-F-011-staff-no-permissions-empty-home-ar.png`, `qa/manual/screens/M03/triage/t010-staff-nocode-home-ar.png`
- **Root cause:** Home rendered only greeting + ungated tiles; nothing explained an empty role set.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Home shows an Alert `home.noScreens` (en/ar/es, NoAccess-style wording) for staff whose visible tiles include no permission-gated screen.
- **Regression test:** `routes/_authed/index.test.tsx` "tells staff whose roles open no screen why Home is empty" / "says nothing of the kind to staff with a screen". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** staff-nocode (AR) Home shows "لا تفتح أدوارك أي شاشة بعد…"; staff-codes and supervisor Homes show no such alert. `qa/manual/screens/M03/fix/ETQAN-QA-108-before-after.png`, `qa/manual/screens/M03/fix/g07-staffc-home-ar.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-109: Student detail shows the family as a link to staff who can't open families; it leads to "no permission"
- **Feature:** M03/People student detail. **Severity:** P3. **Type:** permission. **Easy P3:** yes. **Priority:** low
- **Environment:** as ETQAN-QA-100, AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-012); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** qa-staff-codes@ (role with `student.view`, `student.view_any`, no family codes).
- **Reproduction steps:** 1. `/app/people/students/232` → click "عائلة الشريف" under "العائلة".
- **Expected:** plain text when the user can't open families (the sidebar already hides Families).
- **Actual:** opens `/app/people/families/13` → "ليس لديك صلاحية الوصول إلى هذه الصفحة." (data stays protected).
- **Evidence:** `qa/manual/screens/M03/M03-F-012-family-link-shown.png`, `qa/manual/screens/M03/M03-F-012b-family-link-no-permission.png`, `qa/manual/screens/M03/triage/t011-codes-family-link-ar.png`
- **Root cause:** `StudentForm` (and the `StudentsList` account-type chip) always rendered the family as a `<Link>` to `/people/families/$id` (route needs `family.view`).
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Link only when `can("family.view")`, else plain text (StudentsList chip: plain chip; M04's `<bdi>` kept).
- **Regression test:** `people/StudentForm.test.tsx` "shows the family as plain text without family.view". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** staff-codes on student 232: "عائلة الشريف" is plain text (no link); admin still gets the link to /app/people/families/13. `qa/manual/screens/M03/fix/ETQAN-QA-109-before-after.png`, `qa/manual/screens/M03/fix/g09-admin-family-ar.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-110: Teacher Home "Today's sessions": two attendance dropdowns per row with no visible label (student vs teacher)
- **Feature:** M03 Teacher Home. **Severity:** P3. **Type:** a11y. **Easy P3:** yes. **Priority:** medium
- **Environment:** as ETQAN-QA-100, EN and AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-014); reproduced by Agent 2 on 2026-10-27. (The "I'm in" button on past sessions is by design: TimesPanel "the server decides whether it is time (ruling P10)"; not part of this bug.)
- **Preconditions:** maryam.khatib@qa.etqan.test / `QA-People-2026!` with sessions today.
- **Reproduction steps:** 1. Sign in → Home → column "Attendance".
- **Expected:** each select labelled visibly ("Student" / "Teacher"), like the supervisor page ("Student: … · Teacher: …").
- **Actual:** two identical "Not set" selects stacked under one header; the names exist only as aria-labels.
- **Evidence:** `qa/manual/screens/M03/M03-F-014-teacher-home-two-unlabeled-attendance-en.png`, `qa/manual/screens/M03/triage/t013-maryam-home-en.png`
- **Root cause:** `TeacherSessionTable` rendered `AttendanceControls` without visible labels; the column header only says "Attendance".
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Pass `labelled` (the visible-label mode M06 added for ETQAN-QA-213) in the teacher table: each select shows "Student attendance"/"Teacher attendance" (aria-labels with the name kept).
- **Regression test:** `scheduling/TeacherSessions.test.tsx` "labels the two attendance selects in each row on screen". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** maryam (EN) Today's sessions: each row labels "Student attendance" / "Teacher attendance" (AR: حضور الطالب / حضور المعلم). `qa/manual/screens/M03/fix/ETQAN-QA-110-before-after.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-111: Arabic UI: "Arabic (English)" names in tables and greetings wrap with the brackets on the wrong side ("Fatima Al-( فاطمة الزهراء" / "(Zahra")
- **Feature:** M03 Teacher Home / tables / greeting (RTL). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** as ETQAN-QA-100, AR, desktop and 375x812. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-015 incl. mobile greeting); reproduced by Agent 2 on 2026-10-27. Related: ETQAN-QA-060's accepted follow-up "table names".
- **Preconditions:** maryam.khatib@ (AR); ahmad.haddad@ on a phone.
- **Reproduction steps:** 1. Home (AR) → "حصص اليوم" → student cell of the 20:00 row.
- **Expected:** each person name isolated (`<bdi>`/`dir="auto"`), so "فاطمة الزهراء (Fatima Al-Zahra)" keeps its brackets.
- **Actual:** "Fatima Al-( فاطمة الزهراء" / "(Zahra"; on the phone the greeting "(Ahmad Al-" / "(Haddad" and "حمزة القاضي )Hamza Al-(Qadi".
- **Evidence:** `qa/manual/screens/M03/M03-F-015-teacher-home-name-parens-broken-ar.png`, `qa/manual/screens/M03/M03-F-015b-mobile-greeting-parens-broken-ar.png`, `qa/manual/screens/M03/triage/t014-maryam-home-ar.png`
- **Root cause:** Mixed "Arabic (Latin)" names were rendered as one bare string; when a line wraps inside the Latin part, the brackets resolve to the paragraph's RTL and mirror onto the wrong sides.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Teacher table student cell uses `scheduling/bits` `PersonName` (bracketed part in `<bdi>`, M06 QA-209); Home greeting interpolates `bidiName()` (name isolated, its "(…)" part isolated with its brackets).
- **Regression test:** `TeacherSessions.test.tsx` "isolates the bracketed part of a student's name"; `index.test.tsx` "isolates a mixed-script name in the greeting"; `lib/bidi.test.ts`. Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** maryam (AR): wrapped cell reads "فاطمة الزهراء (Fatima Al-" / "Zahra)" with brackets on the right sides; greeting correct. `qa/manual/screens/M03/fix/ETQAN-QA-111-before-after.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-112: Student Home / My sessions (AR): the "student · course · teacher" line is scrambled ("QA teacher · قرآن QA student · F03")
- **Feature:** M03 Student Home, `/app/learning/sessions` (RTL). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** as ETQAN-QA-100, AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-016); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** qa-student@qa.etqan.test / `QA-People-2026!`.
- **Reproduction steps:** 1. Sign in (AR) → Home → card "الحصة القادمة".
- **Expected:** "QA student · F03 قرآن · QA teacher" (the DOM order), each part isolated.
- **Actual:** "QA teacher · قرآن QA student · F03": the course name is torn apart and the parts are reordered.
- **Evidence:** `qa/manual/screens/M03/M03-F-016-next-session-bidi-ar.png`, `qa/manual/screens/M03/M03-F-016b-student-sessions-bidi-ar.png`, `qa/manual/screens/M03/triage/t015-student-home-ar.png`
- **Root cause:** `scheduling.family.sessionLine` interpolated student, course and teacher bare; Latin/Arabic runs merged across the " · " separators and reordered.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `FamilyHome` and `FamilySessions` pass each part isolated (`bidiName` / `isolate`).
- **Regression test:** `scheduling/FamilyHome.test.tsx` "isolates each part of the session line". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** qa-student (AR) Home and My sessions: "QA student · F03 قرآن · QA teacher" in order. `qa/manual/screens/M03/fix/ETQAN-QA-112-before-after.png`, `qa/manual/screens/M03/fix/g13-student-sessions-ar.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-113: Arabic session counts use the wrong noun form: "0 من 8 حصة"
- **Feature:** M03 Student Home cards, admin Today "التقدم" (translation). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** low
- **Environment:** as ETQAN-QA-100, AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-017); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** qa-student@ (or qa-admin → `/app/scheduling/today`).
- **Reproduction steps:** 1. Student Home (AR) → subscription cards.
- **Expected:** Arabic plural agreement ("0 من 8 حصص"; 3–10 حصص, 11+ حصة …) via i18next plural keys.
- **Actual:** "0 من 8 حصة" everywhere: `locales/ar/scheduling.json` `"progress": "{{used}} من {{total}} حصة"` has no plural forms.
- **Evidence:** `qa/manual/screens/M03/M03-F-017-arabic-count-grammar-ar.png`, `qa/manual/screens/M03/triage/t015-student-home-ar.png`
- **Root cause:** `scheduling.progress` had one Arabic form "… حصة" and the call passed `total`, not `count`.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Already fixed by M06's ETQAN-QA-208 change in the same branch (plural keys `progress_zero…_other` en/ar/es, `SubscriptionProgress` passes `count`). No further change by M03.
- **Regression test:** `scheduling/countCopy.test.ts` (QA-208): `0 من 8 حصص`, `3 من 12 حصة`. Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** qa-student Home "0 من 8 حصص"; admin Today progress "0 من 8 حصص", "0 من 6 حصص". `qa/manual/screens/M03/fix/ETQAN-QA-113-before-after.png`, `qa/manual/screens/M03/fix/g14-admin-today-ar.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-114: A 5xx from `identity/me/` (server reload/deploy) signs the user out visually: the login page appears, with the host name instead of the academy name
- **Feature:** M03 Auth guard / app shell. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** as ETQAN-QA-100, AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-018, seen during real 502s from parallel reloads); reproduced by Agent 2 on 2026-10-27 by answering `identity/me/` and `site/branding/` with 502 via Playwright request interception (scratchpad script), signed-in student session.
- **Preconditions:** a signed-in user; the API briefly answers 502/503.
- **Reproduction steps:** 1. Signed in as qa-student@, open `/app/learning/homework` while `GET /api/v1/identity/me/` returns 502.
- **Expected:** stay on the page with "Connection problem, retrying…"; only a 401/403 means signed out (sign-in.md: requireAuth redirects when `me/` fails — it should distinguish auth failure from server failure).
- **Actual:** redirect to `/app/login`; header shows "qa.etqan.localhost" (branding also failed) and the "EN" toggle; the session is in fact still valid, and the requested page is lost (see ETQAN-QA-058).
- **Evidence:** `qa/manual/screens/M03/M03-F-018-502-shows-login-with-hostname-ar.png`, `qa/manual/screens/M03/triage/t020-502-shows-login-ar.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-115: The parent's menu and pages speak as if the parent were the student ("My learning", "My progress", "My homework", "My certificates"; AR "تعلّمي", "تقدّمي", "واجباتي", "شهاداتي")
- **Feature:** M03 Parent navigation (copy). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** as ETQAN-QA-100, EN and AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-019); reproduced by Agent 2 on 2026-10-27. The shared `learning` nav group for student+parent is by design (B6-11); the first-person wording for parents is not specified anywhere.
- **Preconditions:** parent.sharif@qa.etqan.test / `QA-People-2026!` (3 children) or qa-parent@.
- **Reproduction steps:** 1. Sign in → Home and sidebar; open "My progress".
- **Expected:** parent labels ("My children's learning", "Children's progress", "Children's homework" / "تعلّم أبنائي", "تقدّم أبنائي" …).
- **Actual:** student first-person labels in the sidebar, tiles and page titles. (Suggestion, not part of the easy fix: Home could list each linked child, also those without a subscription — proposal.)
- **Evidence:** `qa/manual/screens/M03/M03-F-019-parent-home-student-wording-ar.png`, `qa/manual/screens/M03/M03-F-019b-parent-home-student-wording-en.png`, `qa/manual/screens/M03/triage/t018-parent-home-en.png`
- **Root cause:** Student and parent share the `learning` nav group and items whose labels are first-person ("My progress"…); nothing varied them by role.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `nav.ts` `roleLabelKey(key, role)` maps the first-person learning labels and the group heading to `nav.parent.*` (en/ar/es: "My children's …" / "… أبنائي"); used by `AppSidebar` (new `role` prop), the Home tiles, and the page titles of learning sessions/subscriptions/progress/recorded.
- **Regression test:** `shell/nav.test.ts` `roleLabelKey` (incl. every first-person learning item has a parent wording); `index.test.tsx` "words a parent's learning tiles about their children". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** parent.sharif AR/EN: "تعلّم أبنائي", "تقدّم أبنائي", "My children's progress" etc. in sidebar, tiles and page title; student keeps "تقدّمي". `qa/manual/screens/M03/fix/ETQAN-QA-115-before-after.png`, `qa/manual/screens/M03/fix/g15-parent-home-en.png`, `qa/manual/screens/M03/fix/g17-parent-progress-ar.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Reopened (Agent 2 final gate, 2026-10-27, from M03-F-025):** the AR sidebar item and Home tile `reviews.nav.rate` still read "قيّم حصصك" (rate YOUR sessions) for a parent; it was in the original finding's list but is missing from `PARENT_LABELS` in `features/shell/nav.ts` (EN "Rate lessons" is neutral, so the EN-based regression test did not catch it). Remedy: map `reviews.nav.rate` → `nav.parent.rate` (AR "قيّم حصص أبنائي", EN may stay "Rate lessons") and extend the test to the AR wording. Evidence: `qa/manual/screens/M03/M03-F-025-parent-rate-your-sessions-ar.png`, `qa/manual/screens/M03/triage/t022-parent-rate-wording-ar.png`. Still easy P3, next fix cycle.
- **Verification status:** REOPENED

## ETQAN-QA-116: Home tiles ignore the nav's academy-setting filter (qaother shows a "Local payment methods" tile the sidebar hides), and the money card says "Expenses and donations" while donations are off
- **Feature:** M03 Home (office) / nav consistency. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** low
- **Environment:** academy `qaother` (most switches off), AR. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-020); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** qaother-admin@qa.etqan.test / `QA-Other-2026!`.
- **Reproduction steps:** 1. Sign in at `qaother.etqan.localhost/app/` → compare tiles with the sidebar's Billing group. 2. Read the second card's title.
- **Expected:** tiles and sidebar list the same screens; the card is titled "المصروفات" / "Spending" when donations are off.
- **Actual:** the tile "طرق الدفع المحلية" (`/billing/local-methods`) is shown, the sidebar item is hidden (nav.ts entry has `setting: "localPayment"`, which the tiles don't apply); the card is "المصروفات والتبرعات" with no donations column.
- **Evidence:** `qa/manual/screens/M03/M03-F-020-qaother-tile-not-in-sidebar-ar.png`, `qa/manual/screens/M03/M03-F-020b-local-methods-page-no-sidebar-item-ar.png`, `qa/manual/screens/M03/triage/t019-qaother-home-ar.png`
- **Root cause:** Home built its tiles from `visibleNavItems` only, while `AppShell` additionally applied `withSettings` (localPayment) and the chat filter; the finance card title was fixed to "Spending and giving".
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** New `shell/useNavItems.ts`: the one gated list (features, codes, settings, chat) used by both `AppShell` and Home. `FinanceSummaryCard` titles itself `finance.home.titleExpenses`/`titleDonations` when only one of the two is on (en/ar/es).
- **Regression test:** `index.test.tsx` "hides/shows the local methods tile while the academy's setting is off/on"; `FinanceSummaryCard.test.tsx` "titles the card after what it shows". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** qaother admin (AR): no "طرق الدفع المحلية" tile or item; tiles = sidebar; card titled "المصروفات" (donations off). `qa/manual/screens/M03/fix/ETQAN-QA-116-before-after.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-117: Phone: the menu drawer can't be scrolled, so every item below the first screen is unreachable (admin: Billing onwards; student: Chat, Account)
- **Feature:** M03 Mobile navigation drawer. **Severity:** P2. **Type:** mobile. **Easy P3:** no (P2). **Priority:** high
- **Environment:** as ETQAN-QA-100, 375x812 touch, AR (same EN). **Tag:** REAL
- **Found by:** Agent 1 (M03-F-021); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** qa-admin (or qa-student) on a phone viewport.
- **Reproduction steps:** 1. `/app/` → tap "افتح القائمة". 2. Swipe/wheel over the drawer. 3. Try to reach "الحساب".
- **Expected:** the drawer list scrolls inside itself (overflow-y auto, height = viewport).
- **Actual:** drawer `clientHeight` 812, `scrollHeight` 3,589, no scrollable element inside; the page behind is scroll-locked; "الحساب" stays at y≈3,533. Only ~14 admin items are reachable.
- **Evidence:** `qa/manual/screens/M03/M03-F-021-mobile-drawer-cannot-scroll-ar.png`, `qa/manual/screens/M03/M03-F-021b-mobile-student-drawer-cut-ar.png`, `qa/manual/screens/M03/triage/t016-mobile-drawer-admin-ar.png`
- **Root cause:** The drawer `Dialog.Content` was `fixed inset-y-0` (height = viewport) with the nav as a plain child and no overflow; Radix scroll-locks the page, so nothing could scroll.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Drawer is a flex column; the close button row is `shrink-0` and the sidebar sits in a `min-h-0 flex-1 overflow-y-auto overscroll-contain` box.
- **Regression test:** `shell/AppShell.test.tsx` "lets the drawer's list scroll on its own". Evidence: `qa/manual/evidence/M03/fix-1/`.
- **Retest (Agent 2 gate, 2026-10-27):** 375x812 drawer, real mouse-wheel: admin AR scrolls 2777/2777 and "الحساب" taps through to /app/account; parent EN reaches "Account" too. `qa/manual/screens/M03/fix/ETQAN-QA-117-before-after.png`, `qa/manual/screens/M03/fix/g20-drawer-wheel-bottom-ar-clicked.png`, `qa/manual/screens/M03/fix/g21-drawer-wheel-bottom-parent-en.png` Gate re-ran: Vitest 31 files / 324 tests pass, tsc 0, pytest etqan/notifications 401 pass (`qa/manual/evidence/M03/gate/`); diff reviewed (root-cause fixes, no test hacks).
- **Verification status:** VERIFIED

## ETQAN-QA-118: Phone: the teacher's "Today's sessions" table hides Attendance, Report and "I'm in" off-screen to the side
- **Feature:** M03 Teacher Home (mobile). **Severity:** P3. **Type:** mobile. **Easy P3:** no. **Priority:** medium
- **Environment:** as ETQAN-QA-100, 375x812, EN (same AR). **Tag:** REAL
- **Found by:** Agent 1 (M03-F-022); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** ahmad.haddad@qa.etqan.test / `QA-People-2026!` with a session today.
- **Reproduction steps:** 1. Sign in on a phone viewport → Home.
- **Expected:** a card per session on narrow screens (time, student, attendance, "I'm in"), or a sticky first column with a visible scroll hint.
- **Actual:** an 8-column table 706 px wide in a 341 px box; only When/Student/Course/Status visible, date in four lines; the teacher's daily actions are off-screen with no hint.
- **Evidence:** `qa/manual/screens/M03/M03-F-022-mobile-teacher-actions-offscreen-en.png`, `qa/manual/screens/M03/M03-F-022b-mobile-teacher-actions-after-sideways-scroll-en.png`, `qa/manual/screens/M03/triage/t017-mobile-teacher-table-en.png`
- **Root cause / Fix / Regression tests:** _Agent 3 (layout change; proposal)_
- **Verification status:** OPEN

## ETQAN-QA-119: Detail pages have only a generic title ("Student", "Invoice", "Teacher") and no breadcrumb/back link; every browser tab reads the same
- **Feature:** M03 Detail pages / titles. **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** as ETQAN-QA-100, EN (same AR). **Tag:** REAL
- **Found by:** Agent 1 (M03-F-023); reproduced by Agent 2 on 2026-10-27. No spec requires breadcrumbs; filed as a usability defect.
- **Preconditions:** qa-admin.
- **Reproduction steps:** 1. Open `/app/people/students/232`, `/app/billing/invoices/154`.
- **Expected:** a title naming the record ("Omar Al-Sharif", "INV-000154") and a "← Students" link.
- **Actual:** H1 "Student", tab "Student · Etqan QA Academy"; no breadcrumb element (`nav[aria-label*=readcrumb]` absent), no back link.
- **Evidence:** `qa/manual/screens/M03/M03-F-023-detail-generic-title-no-breadcrumb-en.png`, `qa/manual/screens/M03/triage/t008-student-detail-title-en.png`
- **Root cause / Fix / Regression tests:** _Agent 3 (proposal)_
- **Verification status:** OPEN

## ETQAN-QA-120: English UI: an "Arabic (English)" name is shown with the bracket part first ("Assalamu alaikum, (Maryam Al-Khatib) الأستاذة مريم الخطيب"); regression of the QA-111/112 name isolation
- **Feature:** M03 Home greeting, account-menu button, family "Next session" line (EN, LTR). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** as ETQAN-QA-100 (dashboard branch `qa/manual-2026-10` with fix cycle 1), EN, 1440x900 and 375x812. **Tag:** REAL (regression introduced by fix cycle 1)
- **Found by:** Agent 1 (M03-F-024, confirmation sweep); reproduced by Agent 2 on 2026-10-27 (final gate).
- **Preconditions:** maryam.khatib@qa.etqan.test or parent.sharif@qa.etqan.test / `QA-People-2026!`, English UI.
- **Reproduction steps:** 1. Sign in (EN) → Home. 2. Read the H1 and the account-menu button; as parent also the "Next session" line.
- **Expected:** "الأستاذة مريم الخطيب (Maryam Al-Khatib)", the stored order, as before cycle 1 and as the table cells still show.
- **Actual:** "(Maryam Al-Khatib) الأستاذة مريم الخطيب"; parent: "(Mahmoud Al-Sharif) محمود الشريف" and "(Omar Al-Sharif) عمر الشريف · Quran Memorization · (Ahmad Al-Haddad) الشيخ أحمد الحداد"; on a phone the line wraps as "(Ahmad Al- الشيخ أحمد الحداد" / "Haddad)". Arabic UI is correct. DOM text: `⁨الأستاذة مريم الخطيب ⁨(Maryam Al-Khatib)⁩⁩`.
- **Evidence:** `qa/manual/screens/M03/M03-F-024-en-greeting-name-order-flipped.png`, `qa/manual/screens/M03/M03-F-024b-parent-en-greeting-nextsession-flipped.png`, `qa/manual/screens/M03/M03-F-024c-mobile-parent-nextsession-scrambled-en.png`, `qa/manual/screens/M03/triage/t021-maryam-home-en-name-order.png` (before cycle 1: `qa/manual/screens/M03/step-036-maryam-home-en.png`)
- **Root cause (Agent 2 analysis):** `dashboard/src/lib/bidi.ts` `bidiName()` wraps the whole name in FSI…PDI. FSI takes its direction from the first strong character, which is Arabic, so the whole name becomes an RTL isolate even in the LTR English sentence; inside it the LTR "(…)" isolate is laid out to the left of the Arabic. Fix direction: isolate the outer name with the UI's direction (LRI in LTR UI / RLI in RTL UI, or `<bdi dir>` per language) instead of FSI, or only isolate the bracketed part; add an EN test.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-121: Phone, family invoices list: the status badge ("Void", "Partly paid", "Paid") floats mid-card under the balance, aligned to nothing
- **Feature:** M03 mobile layout, `/app/learning/invoices` (`features/billing/FamilyInvoices.tsx`). **Severity:** P4. **Type:** mobile. **Easy P3:** no (P4). **Priority:** low
- **Environment:** as ETQAN-QA-100, EN (same in AR mirrored), 375x812. **Tag:** REAL
- **Found by:** Agent 1 (M03-F-026); reproduced by Agent 2 on 2026-10-27 (final gate).
- **Preconditions:** parent.sharif@qa.etqan.test / `QA-People-2026!`.
- **Reproduction steps:** 1. Phone → Home → Invoices.
- **Expected:** the badge aligned with the card content (start edge) or in the top corner, as on the Home subscription cards.
- **Actual:** under "Balance: …" the badge sits ~95 px in, right-aligned to the balance line's width.
- **Evidence:** `qa/manual/screens/M03/M03-F-026-mobile-invoice-badge-floating-en.png`, `qa/manual/screens/M03/triage/t023-mobile-parent-invoices-badge-en.png`
- **Root cause (Agent 2 analysis):** the right-hand block is `flex flex-col items-end`; when `flex-wrap` moves it onto its own line at phone width, the block shrinks to the balance text and the badge is end-aligned inside it. Cosmetic.
- **Root cause / Fix / Regression tests:** _Agent 3 (optional, P4)_
- **Verification status:** OPEN

## --- M04 manual bugs ---

## ETQAN-QA-150: Students list (AR): the search placeholder is cut off ("ابحث بالاسم أو البريد أو الها…"); the search box is the narrowest field in the filter row
- **Feature:** M04 People, students list filter row (`StudentsList.tsx`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-001); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. Open `/app/people/students` in Arabic at 1440x900 (and at 375x812).
- **Expected:** The full hint "ابحث بالاسم أو البريد أو الهاتف" is readable; the main search control is at least as wide as the selects.
- **Actual:** The placeholder is cut at "…أو الها" on desktop and at "…أو الـ" on the phone.
- **Evidence:** `qa/manual/screens/M04/M04-F-001-search-placeholder-cut.png`, `qa/manual/screens/M04/triage/t001-students-list-ar.png`, `qa/manual/screens/M04/triage/t030a-mobile-filters.png`
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `PeopleList` gave the search box `min-w-48 flex-1` in the same wrapping row as up to nine `w-auto` selects, so it shrank to 192 px, narrower than its hint. Fix: `min-w-72` (288 px; the row still fits 343 px on a phone). Regression test: `StudentsList.test.tsx` "keeps the search box wide enough for its hint". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-150-after.png (search hint "ابحث بالاسم أو البريد أو الهاتف" fully visible, 1440 AR). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-151: Arabic search ignores spelling variants: "ابراهيم" does not find "إبراهيم" (hamza/alef forms, ة/ه, ى/ي)
- **Feature:** M04 People search (`identity/api/people_filters.py:72` uses plain `icontains` on full_name/email/phone). **Severity:** P2. **Type:** functional. **Easy P3:** no. **Priority:** high
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-002); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/students`, type `إبراهيم` in the search box → 1 row (student 243 "إبراهيم حسن (Ibrahim Hassan)").
  2. Clear it and type `ابراهيم` (no hamza), as most Arabic users type.
- **Expected:** Both spellings find student 243: the search normalises Arabic letter variants (أ/إ/آ→ا, ة→ه, ى→ي, tatweel/diacritics) on both sides.
- **Actual:** `ابراهيم` gives an empty list ("لا يوجد طلاب بعد."). Any name with أ/إ (أحمد، إسلام، أسماء…) is affected, in every people list that uses `q`.
- **Evidence:** `qa/manual/screens/M04/M04-F-002-search-no-hamza.png`, `qa/manual/screens/M04/triage/t002-search-no-hamza-empty.png`
- **Notes:** P2: finding a student by name is the main daily workflow of an Arabic academy, and the miss looks like "no such student". Fix needs a normalised search (DB function/annotation or a stored normalised column), so not an easy P3.
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `filter_people` (and `filter_families`) matched the name with plain `icontains`, so hamza/alef forms, taa marbuta, alef maqsura and marks had to be typed exactly. Fix: new `etqan/platform/search.py` folds both sides the same way (أ/إ/آ/ٱ→ا, ة→ه, ى→ي, tatweel and harakat dropped): `fold()` for the typed text, `TRANSLATE(REGEXP_REPLACE(col))` aliased in the query for the column; used for `?q=` on the name in every people list and `?search=` on families. No migration, no API shape change (email/phone matching unchanged). Regression tests: `platform/tests/test_search.py`; `identity/tests/test_people_api.py::test_search_folds_arabic_spelling_variants` (ابراهيم/إبراهيم/ابرَاهيم/Ibrahim) and `::test_search_folds_taa_marbuta_and_alef_maqsura`; `test_families_api.py::...::test_search_folds_arabic_spelling_variants`. Live: AR search `ابراهيم` now lists "إبراهيم حسن (Ibrahim Hassan)" (`qa/manual/screens/M04/fix/a3-151-search-no-hamza.png`). Other app searches: follow-up in coverage-gaps. Branch `qa/manual-2026-10` (dashboard + backend); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-151-after.png ("ابراهيم" finds "إبراهيم حسن (Ibrahim Hassan)"); families ?search "عائله عبد الرحمن" finds "M04 عائلة عبد الرحمن" (raw-165-list.png). Tests re-run: `qa/manual/evidence/M04/gate-1/`. PROPOSAL-accepted (follow-up, not blocking): adopt with_folded/folded_q in the other app searches; stored folded column + trigram index only if lists grow.

## ETQAN-QA-152: An empty search result says "لا يوجد طلاب بعد." ("No students yet.") instead of "no matches"
- **Feature:** M04 People lists empty state. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-003); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/students`, search `ابراهيم` or `ZZQ nobody` (also EN).
- **Expected:** A filtered-empty state such as "لا يوجد طلاب مطابقون للبحث" / "No students match your search" with a way to clear the filters.
- **Actual:** "لا يوجد طلاب بعد." / "No students yet.", which reads as if the academy has no students.
- **Evidence:** `qa/manual/screens/M04/M04-F-003-empty-state-says-no-students-yet.png`, `qa/manual/screens/M04/M04-F-003b-empty-search-en.png`, `qa/manual/screens/M04/triage/t002-search-no-hamza-empty.png`
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `PeopleList` always rendered the list's own `emptyLabel` ("لا يوجد طلاب بعد.") whatever the search/filters. Fix: when any param besides `page` is set, it shows the new `people.noMatches` ("لا توجد نتائج مطابقة للبحث أو عوامل التصفية.", en/es too); applies to students, parents and teachers. Regression test: `StudentsList.test.tsx` "says nothing matches when a search or filter empties the list" (the unfiltered "No students yet." test still passes). Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-152-after.png (AR "لا توجد نتائج مطابقة للبحث أو عوامل التصفية."), raw-152-en.png (EN "No one matches your search or filters."). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-153: People tables (AR): Latin names that start or end with punctuation are mirrored ("+cmd" → "cmd+", "-5 days" → "days 5-", "Aisha R." → ".Aisha R")
- **Feature:** M04 People list name cells (`StudentsList.tsx`/`PeopleList.tsx`). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-004); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/students` page 1 in Arabic (rows `+cmd`, `-5 days`, `=HYPERLINK("http://x")`, `@SUM(1)` from Tier 1 tests).
- **Expected:** Each name shows as typed (cells isolate their text: `dir="auto"` / `<bdi>`).
- **Actual:** Shown as `cmd+`, `days 5-`, `HYPERLINK("http://x")=`, `SUM(1)@`. A real name ending in a dot or bracket ("Aisha R.", "John (Jr)") is affected the same way.
- **Evidence:** `qa/manual/screens/M04/M04-F-004-latin-name-punctuation-flipped-rtl.png`, `qa/manual/screens/M04/triage/t001-students-list-ar.png`
- **Notes:** Same family as ETQAN-QA-060 (inputs/header, fixed) and ETQAN-QA-111 / ETQAN-QA-209 (other tables); this is the people tables, not covered by those fixes.
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: name cells printed `full_name` as bare text inside an RTL table, so a Latin name's leading/trailing punctuation took the row's direction. Fix: the name is isolated in `<bdi>` in the students, parents, teachers, staff and admins lists, the family chip, and the families list (payer and students); joined lists (children, courses) go through the new `components/NameList` (each name in `<bdi>`, the reader's comma). Regression test: `StudentsList.test.tsx` "isolates each student's name and family"; `components/NameList.test.tsx`. Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-153-after.png ("+cmd", "-5 days", "@SUM(1)" keep their punctuation in AR rows; also staff-codes and supervisor lists). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-154: Person form time-zone picker is a raw list of 419 English IANA ids (UTC, Africa/Abidjan…, old ids like Africa/Asmera) in the Arabic UI
- **Feature:** M04 People forms (`UserFieldsSection`), timezone select. **Severity:** P3. **Type:** translation. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-006); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/students/new` (same on the student/teacher detail form), open "المنطقة الزمنية".
- **Expected:** Localised, searchable names (e.g. "القاهرة (GMT+2)", "الرياض"), with common zones first.
- **Actual:** A plain `<select>` with 419 options starting `UTC|Africa/Abidjan|Africa/Accra|Africa/Addis_Ababa`; finding Riyadh means scrolling hundreds of English ids. Choosing Country = Saudi Arabia leaves Africa/Cairo with no hint.
- **Evidence:** `qa/manual/screens/M04/M04-F-006-timezone-raw-iana-list.png`, `qa/manual/screens/M04/triage/t005-new-student-xp.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-155: Student notification preferences (admin view): "التغييرات على جدولك." speaks to the admin, and "القاربة على الانتهاء" is not correct Arabic
- **Feature:** M04 Student detail, notification preferences card (`locales/ar/notifications.json:113-114`). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-008); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. Open any student, e.g. `/app/people/students/256`, card "تفضيلات الإشعارات".
- **Expected:** Neutral wording that fits an admin editing someone else's settings ("التغييرات على الجدول"), and correct Arabic ("الاشتراكات التي قاربت على الانتهاء").
- **Actual:** "التغييرات على جدولك." and "الفواتير والمدفوعات المتأخرة والاشتراكات القاربة على الانتهاء."
- **Evidence:** `qa/manual/screens/M04/M04-F-008-notif-prefs-copy.png`, `qa/manual/screens/M04/triage/t007-student-detail-full.png`
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: copy in `locales/ar/notifications.json` (`preferences.hint`) was written for the person's own settings and had a grammar slip. Fix: "التغييرات على الجدول." and "…والاشتراكات التي قاربت على الانتهاء."; EN "Changes to the timetable." (es has no preferences section; falls back to EN, noted in coverage-gaps). Regression test: `src/locales/people-copy.test.ts` "keeps the notification hints neutral and correct". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-155-after.png (student 256: "التغييرات على الجدول." and "التي قاربت على الانتهاء."). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-156: Right after a student is created (invite already emailed) the Account card offers "إرسال دعوة" (Send invite) as if none was sent
- **Feature:** M04 Student detail, `AccountActions.tsx` (state `invited` → `people.account.sendInvite`). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-009); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. Create a student with an email (e.g. `M04 مكرر فرز`, `M04-Sara@qa.etqan.test` → student 256); the invite arrives in Mailpit.
  2. Look at the "الحساب" card.
- **Expected:** "الدعوة معلّقة" with "إعادة إرسال الدعوة" / "Resend invite" (and ideally the date of the last invite); the create toast says the invite was emailed.
- **Actual:** Badge "الدعوة معلّقة" and button "إرسال دعوة"; the save toast only says "تم الحفظ.". An owner will send it again.
- **Evidence:** `qa/manual/screens/M04/M04-F-009-invite-button-label.png`, `qa/manual/screens/M04/triage/t007-student-detail-full.png`
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `AccountActions` labelled the `invited` state's action with `people.account.sendInvite`, though `invited` means an invite was already emailed (backend action is `resend_invite`). Fix: new key `people.account.resendInvite` ("إعادة إرسال الدعوة" / "Resend invite" / "Reenviar invitación"); `sendInvite` stays for the admin-invite dialog. Create toast wording left as a follow-up (coverage-gaps). Regression test: `AccountActions.test.tsx` "offers to resend the invite while it is pending". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-156-after.png (AR "إعادة إرسال الدعوة"); raw-en-256.png (EN "Resend invite" → toast "Invite sent."). Tests re-run: `qa/manual/evidence/M04/gate-1/`. PROPOSAL-accepted (follow-up): create toast to say whether an invite was emailed.

## ETQAN-QA-157: Raw English server messages in Arabic people screens: duplicate email "This email is already in use." and contract upload "This type of file is not allowed."
- **Feature:** M04 People/Contracts (`identity/services.py:458,662,805,944`, `platform/uploads.py:136`; dashboard passes server text through `useFieldError`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-010, M04-F-019); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/students/new`, name `M04 مكرر فرز 2`, email `m04-sara@qa.ETQAN.test` (already used by student 256) → حفظ → scroll up.
  2. `/app/people/contracts?teacher=251` → "إضافة عقد" → upload a `notes.txt` → حفظ.
- **Expected:** Arabic field errors ("هذا البريد مستخدم بالفعل.", "نوع الملف غير مسموح. ارفع PDF أو Word أو صورة.").
- **Actual:** ".This email is already in use" (400 POST /api/v1/people/students/) and ".This type of file is not allowed" (400 POST /api/v1/contracts/), in English with the period at the start. Django's own messages are translated (300-char name → Arabic).
- **Evidence:** `qa/manual/screens/M04/M04-F-010-duplicate-email-english-message.png`, `qa/manual/screens/M04/M04-F-019-contract-filetype-english-error.png`, `qa/manual/screens/M04/triage/t010-dup-email-english.png`, `qa/manual/screens/M04/triage/t019-contract-filetype-english.png`
- **Notes:** Same class as ETQAN-QA-049 and ETQAN-QA-206 (availability message, filed by M06; M04-F-015 is a duplicate of it). Fix together: one mapping of these server texts to i18n keys (or backend gettext).
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: the backend raises `ValidationError` with fixed English sentences and no code (no backend translations exist), and the dashboard shows field errors verbatim. Fix (dashboard only, like QA-049): `src/lib/server-messages.ts` maps "This email is already in use." and "This type of file is not allowed." to `errors.server.emailInUse` / `errors.server.fileTypeNotAllowed` (ar/en/es); used by `useFieldError` (all people forms), `errorText` (toasts) and `ContractDialog`. API `code` proposed in coverage-gaps. Regression tests: `lib/field-error.test.ts` "translates a known server sentence", `lib/form-errors.test.ts` "translates the duplicate-email refusal", `ContractDialog.test.tsx` "shows the server's file-type refusal in the reader's words". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-157-after.png (dup email → "هذا البريد مستخدم بالفعل."), ETQAN-QA-157b-after.png (contract notes.txt → "نوع هذا الملف غير مسموح."). Tests re-run: `qa/manual/evidence/M04/gate-1/`. Interim text map accepted; PROPOSAL-accepted: error codes on the backend ValidationErrors (qa/coverage-gaps.md M04).

## ETQAN-QA-158: A server-side form error appears above the visible area: after "حفظ" nothing seems to happen (no scroll, no focus, no toast)
- **Feature:** M04 People forms (`StudentForm`, `TeacherForm`, applyServerErrors). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-011); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/students/new`, name + an email already in use (or a 300-char name), scroll to the bottom, press "حفظ".
- **Expected:** The page scrolls/focuses to the first invalid field, or a toast says "تحقق من الحقول المظللة".
- **Actual:** The view stays at the Save button (scrollY 529); the red message sits next to the email field off-screen; no toast. 400 POST /api/v1/people/students/.
- **Evidence:** `qa/manual/screens/M04/M04-F-011-server-error-offscreen-no-feedback.png`, `qa/manual/screens/M04/triage/t011-dup-email-viewport.png`
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `applyServerErrors` (`src/lib/form-errors.ts`) called `setError` without `shouldFocus`, so a server field error was set but the view stayed at Save. Fix: the first refused field is set with `{ shouldFocus: true }`, which focuses and scrolls to it (every form using `applyServerErrors`). Regression tests: `lib/form-errors.test.ts` "focuses the first refused field only"; `StudentForm.test.tsx` "shows a nested server error under the email field" now asserts the email input has focus. Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-158-after.png (Save pressed at the bottom: page back at top, focus on user.email with the message). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-159: A deactivated student without login looks exactly like an active one: list and Account card both say "بلا تسجيل دخول"
- **Feature:** M04 People account state (`identity/services.py:account_state` returns `no_login` before `inactive`; `AccountStateChip`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-012); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. Open email-less student 249 "M04 يوسف بلا بريد" → "تعطيل" (toast "تم التعطيل.").
  2. Look at the Account card badge and the list row (filter "أي حساب" = "معطّل" lists it).
- **Expected:** A visible "معطّل" state, as for a student with an email (e.g. 250 shows "معطّل").
- **Actual:** Badge stays "بلا تسجيل دخول"; only the button changes to "تفعيل". In the list the account column is identical to an active email-less student.
- **Evidence:** `qa/manual/screens/M04/M04-F-012a-deactivated-list-shows-no-login.png`, `qa/manual/screens/M04/M04-F-012b-deactivated-detail-shows-no-login.png`, `qa/manual/screens/M04/triage/t012-249-deactivated-no-confirm.png`
- **Notes:** people.md lists the states but not that `no_login` hides `inactive`. Student 249 was reactivated after the repro.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-160: "تعطيل" (deactivate) acts on one click with no confirmation, on the person page and in bulk
- **Feature:** M04 People `AccountActions.tsx:151-157`, `StudentsList.tsx:253` (bulk). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-013); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. Open student 249 → "تعطيل" (red, next to the other account buttons).
  2. Or list → tick rows → bulk "تعطيل".
- **Expected:** A confirm dialog naming the person(s) and the effect (signed out everywhere, quick-login sessions end).
- **Actual:** Deactivated at once, toast "تم التعطيل."; bulk deactivates every selected row with one click.
- **Evidence:** `qa/manual/screens/M04/M04-F-013-deactivate-no-confirm.png`, `qa/manual/screens/M04/triage/t012-249-deactivated-no-confirm.png`
- **Notes:** Same pattern as ETQAN-QA-205 (M06) and ETQAN-QA-165 (family retire).
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `AccountActions` and the students bulk bar called the deactivate action directly from the button. Fix: both go through the shared `Confirm` dialog: "تعطيل حساب {name}" / "تعطيل الحسابات المحددة" with the effect (signed out everywhere, sign-in links stop, until reactivated); the blocked (self / last admin) case keeps the disabled button with its reason. Regression tests: `AccountActions.test.tsx` "asks before deactivating and acts only on confirm"; `StudentsList.test.tsx` "asks before deactivating the selection". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-160-after.png (detail: dialog "تعطيل حساب M04 يوسف بلا بريد"), ETQAN-QA-160b-after.png (bulk, 6 selected: "تعطيل الحسابات المحددة"); cancelled, nothing deactivated. Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-161: Students CSV exported from the Arabic UI has English headers and raw English codes (`invited`, `no_login`, `paused`, `female`, `individual`)
- **Feature:** M04 People CSV export (`?format=csv`). **Severity:** P3. **Type:** translation. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-014); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. Arabic session, `/app/people/students` → search `M04` → "تصدير CSV" (`/api/v1/people/students/?q=M04&format=csv`).
- **Expected:** Column titles and values in the reader's language (or at least the same words as the table: "الدعوة معلّقة", "متوقف مؤقتًا", "أنثى", "فردي").
- **Actual:** `ID,Name,Email,Phone,Language,Account,Active,Status,Gender,Country,…` and values `invited`, `paused`, `female`, `EG`, `adult`, `individual`. (Good: UTF-8 BOM, filters respected, formula cells escaped.)
- **Evidence:** `qa/manual/screens/M04/M04-F-014-csv-export-english.png`, `qa/manual/screens/M04/M04-F-014-csv-export-english.csv`
- **Notes:** Re-fetched by Agent 2 from the AR session with `Accept-Language: ar`: same English output.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-162: Teacher availability week starts on Monday in the Arabic UI (Egypt academy)
- **Feature:** M04 Teachers, `features/scheduling/AvailabilityEditor.tsx`. **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-017); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/teachers/251`, card "المواعيد المتاحة".
- **Expected:** Week order familiar to the academy's region (Saturday or Sunday first in Egypt/Gulf), or an academy setting.
- **Actual:** الاثنين … الأحد (Monday first, Sunday last). No week-start setting is documented.
- **Evidence:** `qa/manual/screens/M04/M04-F-017-availability-week-starts-monday.png`, `qa/manual/screens/M04/triage/t017-availability-week.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-163: Contracts list (AR): the file name and the date are scrambled ("2026/10/ui-526170.pdf · 19", "عقد خالد.27 · 2026/10/pdf")
- **Feature:** M04 Contracts list card subtitle. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-018); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/contracts` (or `?teacher=251`), read the second line of each card (contract M04-CT-001 has file `عقد خالد.pdf`).
- **Expected:** "ui-526170.pdf · 19/10/2026" / "عقد خالد.pdf · 27/10/2026" readable: file name and date each isolated.
- **Actual:** The day number is split from month/year and glued to the file name; the Arabic file name's extension moves. The no-file card ("لا يوجد ملف · 2026/10/19") reads fine.
- **Evidence:** `qa/manual/screens/M04/M04-F-018-contract-date-filename-bidi.png`, `qa/manual/screens/M04/M04-F-018b-contract-arabic-filename-bidi.png`, `qa/manual/screens/M04/triage/t016-teacher-contracts-link.png`
- **Notes:** Same family as ETQAN-QA-207 (trial dates) and ETQAN-QA-104 (bell time stamps); different component.
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `ContractsList` built the subtitle as one string (`file_name + " · " + date`), so in RTL the Latin/Arabic file name, the dots and the date digits reordered across each other. Fix: teacher name, reference, file name (or "no file") and date are each in their own `<bdi>`. Regression test: `ContractsList.test.tsx` "isolates the file name and the date". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-163-after.png ("2026/10/19 · ui-526170.pdf", "عقد خالد.pdf · 2026/10/27" in order). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-164: "تعديل العائلة" shows the required payer as empty "—" although the family has a payer
- **Feature:** M04 Families, `FamilyDialog.tsx` (payer select reset before the payer options load). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-020); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/families/16` (payer 252 "M04 عبد الرحمن القحطاني") → "تعديل".
- **Expected:** الدافع pre-selected with the current payer.
- **Actual:** The select shows "—": `value=""` while option 252 exists (eval `/:—,248:…,249:…,252:M04 عبد الرحمن القحطاني (وليّ أمر)`). Saving untouched keeps the old payer (Agent 1), so the dialog misstates the saved data and invites a wrong re-pick.
- **Evidence:** `qa/manual/screens/M04/M04-F-020-family-edit-payer-blank.png`, `qa/manual/screens/M04/triage/t020-family-edit-payer-blank.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-165: "إيقاف" (retire) a family acts on one click with no confirmation
- **Feature:** M04 Families, `FamiliesList.tsx:FamilyActiveToggle`. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-021); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/families/16` (or the list row) → "إيقاف".
- **Expected:** A confirm explaining the effect (the family no longer supplies a payer for its students' invoices).
- **Actual:** Retired at once, toast "أُوقفت العائلة."; the button sits next to "تعديل". Confirmed in code: the button calls `update.mutate` directly.
- **Evidence:** `qa/manual/screens/M04/M04-F-021-family-retire-no-confirm.png`
- **Notes:** Same pattern as ETQAN-QA-160.
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `FamilyActiveToggle` called `update.mutate` on click. Fix: retiring goes through `Confirm` ("إيقاف {name}", body: the family stops paying its students' new invoices, students stay linked, can be restored); restoring stays one click (it undoes nothing). Regression test: `FamiliesList.test.tsx` "retires an active family and restores a retired one" now checks the dialog appears and nothing is sent before confirming. Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-165-after.png (family 16 restored, "إيقاف" opens a named Confirm; confirmed to put family 16 back to retired). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-166: Students of a retired family still show "عائلي" and the family chip with no "retired" mark
- **Feature:** M04 Students list / student detail family display. **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-022); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. Family 16 is retired (DB `is_active=f`). `/app/people/students` → search `M04`.
- **Expected:** The chip marks the family as retired (the family filter already labels such families "(موقوفة)"), since it no longer pays for them.
- **Actual:** Rows 248 and 249 show "عائلي" + "M04 عائلة عبد الرحمن" exactly like an active family.
- **Evidence:** `qa/manual/screens/M04/M04-F-022-retired-family-badge-not-marked.png`, `qa/manual/screens/M04/triage/t023-bulk-bar-preselected.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-167: Students bulk bar comes with a family ("QA Fam") and a tag already chosen, so "إضافة إلى عائلة" can act on a value the user never picked; no select-all
- **Feature:** M04 Students list bulk bar (`StudentsList.tsx:112-114`: `familyId = bulkFamily ?? activeFamilies[0]?.id`, same for tag). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-023); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/students` → search `M04` → tick one row.
- **Expected:** Empty "اختر عائلة…" / "اختر وسمًا…" placeholders, with the add buttons disabled until a value is chosen; a header select-all checkbox.
- **Actual:** Family select shows "QA Fam", tag select "📅 عضو منذ سنة" (eval: `نشط | 📅 عضو منذ سنة | QA Fam | …`); one click on "إضافة إلى عائلة" puts the child into a stranger's family. No select-all and no clear-selection control.
- **Evidence:** `qa/manual/screens/M04/M04-F-023-bulk-family-picker-preselected.png`, `qa/manual/screens/M04/triage/t023-bulk-bar-preselected.png`
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `StudentsList` defaulted the bulk family to `activeFamilies[0]` and the tag to the first active tag. Fix: no default; each select starts on "اختر عائلة…" / "اختر وسمًا…" and Add/Remove stay disabled until a value is picked. `PeopleList` gets a header checkbox that selects or clears every row on the page (students, parents, teachers). Regression tests: `StudentsList.test.tsx` "adds and removes a tag on the selected rows", "adds the selection to an active family and removes it from one" (empty pickers, disabled buttons), "selects every row on the page and clears them again". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-167-after.png (pickers show "اختر عائلة…"/"اختر وسمًا…", add buttons disabled; header select-all ticks 6 rows). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-168: Search boxes (AR): the clear "×" sits on top of Latin text ("×M04")
- **Feature:** M04 People list search inputs (students, teachers, staff). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-024); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/students` (or staff/teachers) → type `M04`.
- **Expected:** The clear button keeps its own space at the inline end; the text never touches it.
- **Actual:** Latin text is now left-aligned (each value takes its own direction since the ETQAN-QA-060 input change) and the "×" at the left edge touches the first letter.
- **Evidence:** `qa/manual/screens/M04/M04-F-024-search-clear-x-touches-latin-text.png`, `qa/manual/screens/M04/triage/t023-bulk-bar-preselected.png`
- **Notes:** Likely a side effect of the verified ETQAN-QA-060 fix (`[unicode-bidi:plaintext]` + `text-start` on `Input`): the search wrapper reserves padding only on one side. Fix: padding on both inline sides for the clear button.
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: confirmed side effect of ETQAN-QA-060 (`Input` now aligns a Latin value to the inline end in RTL, the same side as the native search clear button, which had no gap). Fix: `Input` adds `[&::-webkit-search-cancel-button]:ms-2`, a gap on the button's text side, for every search box. Regression test: `ui/input.test.tsx` "keeps the search clear button apart from the text". Live: `qa/manual/screens/M04/fix/a3-152-168-empty-search.png`. Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-168-after.png (gap between × and "M04 ZZQ nobody"). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-169: Admins page (AR): the invite button and dialog say "دعوة مشرف" (invite supervisor) instead of invite admin
- **Feature:** M04 Admins (`locales/ar/people.json:163-164`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-025); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/admins` in Arabic (EN: "Invite admin").
- **Expected:** "دعوة مدير" and "أرسل دعوة مدير…", matching the page title "المديرون".
- **Actual:** "دعوة مشرف"; "مشرف" is also the name of a staff role (qa-supervisor), so the owner may think he is inviting a supervisor.
- **Evidence:** `qa/manual/screens/M04/M04-F-025-invite-admin-says-supervisor.png`, `qa/manual/screens/M04/triage/t025-admins-invite-supervisor.png`
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: Arabic copy used "مشرف" (supervisor, a staff role) for admin in `people.admins.invite/inviteBody` and `people.account.blocked.last_admin`. Fix: "دعوة مدير", "أرسل دعوة مدير…", "…إلى مدير نشط واحد على الأقل." (matches the page title "المديرون"). Regression test: `src/locales/people-copy.test.ts` "calls an admin an admin in Arabic". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-169-after.png (button + dialog "دعوة مدير"). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-170: Study groups list (AR): student names joined with a Latin comma and reordered ("سارة عبد الرحمن العتيبي M04 Adam Brooks, M04")
- **Feature:** M04 Study groups list, students cell. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-026); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/groups`, row "M04 حلقة الفجر" (students M04 Adam Brooks + M04 سارة عبد الرحمن العتيبي).
- **Expected:** "M04 Adam Brooks، M04 سارة عبد الرحمن العتيبي" in order: Arabic comma (as the teachers list already uses) and each name isolated.
- **Actual:** Latin ", " separator and the pieces visually reordered.
- **Evidence:** `qa/manual/screens/M04/M04-F-026-group-students-latin-comma-bidi.png`, `qa/manual/screens/M04/triage/t026-groups-latin-comma.png`
- **Notes:** Side note (not filed): only the new group has a delete button, labelled with the whole name inside it ("احذف M04 حلقة الفجر"); other rows have none, with no explanation.
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `StudyGroupsList` joined member names with a Latin ", " into one string. Fix: the new `components/NameList` (each name in `<bdi>`, "، " in Arabic, ", " otherwise); also used for parents' children and teachers' courses (which hard-coded "،" even in English). Regression test: `components/NameList.test.tsx` "isolates each name and uses the reader's comma". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-170-after.png (AR "M04 Adam Brooks، M04 سارة…" in order with the Arabic comma); raw-en-groups.png / raw-en-teachers.png (EN joins with ", "). Tests re-run: `qa/manual/evidence/M04/gate-1/`.

## ETQAN-QA-171: Registration review panel hides the registrant's phone, date of birth, gender and country; no link to the created student after approval
- **Feature:** M04 Self-registrations, `RegistrationDetail.tsx`. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-027); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. Admin `/app/people/registrations?status=approved` → "عرض" on "M04 تسجيل ذاتي ريم" (registered with phone +201055556666, DOB 1995-06-01, أنثى, مصر).
- **Expected:** Everything the person entered (phone, age, gender, country) to decide before approving; after approval, a link to the new student.
- **Actual:** Only name, email, type, status, dates, code and preferences. Type reads "متعلّم بالغ" (masculine) for a female registrant. No link to student 254.
- **Evidence:** `qa/manual/screens/M04/M04-F-027-registration-review-missing-phone-dob.png`, `qa/manual/screens/M04/triage/t027-registration-review.png`
- **Notes:** The fields exist on the student (CSV row 254 has phone, female, EG, 1995-06-01); the panel may need them in the registration payload (possible API addition, proposal).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-172: Email-confirmation page says "يمكنك الآن تسجيل الدخول" although the registration still waits for approval; sign-in then refuses
- **Feature:** M04 Self-registration, `routes/verify-email.tsx:31` (`auth.verified`, same text for every case). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-028); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. Anonymous `/app/register` (self, adult) with `registration_waitlist` on → open the verify link from Mailpit.
  2. Press "اذهب إلى تسجيل الدخول" and sign in.
- **Expected:** "تم تأكيد بريدك. سنراسلك عندما توافق الأكاديمية على تسجيلك." when the registration is pending (registration.md step 3).
- **Actual:** "تم تأكيد البريد. يمكنك الآن تسجيل الدخول." + sign-in button; sign-in answers "تسجيلك بانتظار موافقة الأكاديمية." (403 POST /api/v1/identity/login/).
- **Evidence:** `qa/manual/screens/M04/M04-F-028-verify-says-can-sign-in-while-pending.png`
- **Notes:** Agent 2 confirmed from Agent 1's screenshot plus code (the page always shows `auth.verified`); a new self-registration was not created again to keep test data small.
- **Root cause / Fix / Regression tests (Agent 3, M04 fix cycle 1, 2026-10-27):** Root cause: `routes/verify-email.tsx` shows `auth.verified` ("يمكنك الآن تسجيل الدخول") for every confirmation, and the API's bare 200 doesn't say whether the account is active. Fix (copy only, no API change): `auth.verified` now reads "تم تأكيد البريد. سجّل الدخول، وإن كان تسجيلك ينتظر موافقة الأكاديمية فسنراسلك فور الموافقة عليه." (en/es too), true for both cases. Precise message needs `can_sign_in` in the response: proposal in coverage-gaps. Regression test: `routes/verify-email.test.tsx` "does not promise sign-in to a registration awaiting approval". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M04/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-27). Evidence: `qa/manual/screens/M04/fix/` ETQAN-QA-172-after.png (new self-registration m04-gate-reg@ verified: no claim that sign-in works now; sign-in then says "تسجيلك بانتظار موافقة الأكاديمية."; approval sends the welcome email, so the promise is true). Tests re-run: `qa/manual/evidence/M04/gate-1/`. Interim rewording accepted; PROPOSAL-accepted: verify-email returns can_sign_in so the page can say exactly "awaiting approval".

## ETQAN-QA-173: Phone (375): students list: nine filters fill the first screen and the 705 px table is squeezed into 341 px with a hidden sideways scroll
- **Feature:** M04 Students list, mobile. **Severity:** P3. **Type:** mobile. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-030); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. 375x812, `/app/people/students`; then search `M04` and scroll to the table.
- **Expected:** Filters behind a "تصفية" button (or one chip row) so the list shows on the first screen; rows as cards on a phone.
- **Actual:** First screen = tabs + 9 selects of uneven widths; the first row starts at the bottom. Table scrollWidth 705 vs box 341: names wrap one word per line, emails break at the hyphen ("m04-" / "adam@qa.etqan.test"), the phone column is cut, with no sign the table scrolls.
- **Evidence:** `qa/manual/screens/M04/M04-F-030a-mobile-filters-fill-screen.png`, `qa/manual/screens/M04/M04-F-030b-mobile-table-squeezed.png`, `qa/manual/screens/M04/triage/t030a-mobile-filters.png`, `qa/manual/screens/M04/triage/t030b-mobile-table.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-174: Leaving a half-filled person form loses everything with no warning
- **Feature:** M04 People forms (no unsaved-changes guard anywhere in the dashboard: no `useBlocker`/`beforeunload`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M04 (M04-F-031); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!` unless noted; AR interface.
- **Reproduction steps:**
  1. `/app/people/students/new` → name `M04 نصف مكتوب فرز`, email `m04-half2@qa.etqan.test` → click "المعلمون" in the menu → browser Back.
- **Expected:** "لديك تغييرات غير محفوظة، هل تريد المغادرة؟" (or the draft kept).
- **Actual:** Navigates at once; Back shows an empty form (eval: both inputs `""`). Same for the long teacher form.
- **Evidence:** `qa/manual/screens/M04/M04-F-031-unsaved-form-lost-no-warning.png`, `qa/manual/screens/M04/triage/t031-unsaved-form-lost.png`
- **Notes:** App-wide pattern; fix likely a shared form guard (proposal).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-175: Person form: the "leave the email empty…" hint sits under the time-zone field, two rows away from the email field (also shown to read-only viewers)
- **Feature:** M04/People student form (also teacher form). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** qa academy, admin AR + EN, 1440x900; supervisor / staff-codes read-only. **Tag:** REAL
- **Found by:** Agent 1 (M04-F-032, confirmation sweep); reproduced by Agent 2 on 2026-10-27.
- **Reproduction steps:** 1. `/app/people/students/new` (or any student page, `/app/people/teachers/251`).
- **Expected:** "اترك البريد فارغًا لطالب بلا تسجيل دخول. إضافته لاحقًا ترسل دعوة." directly under "البريد الإلكتروني"; not shown when the viewer can't edit.
- **Actual:** email input at top-left (y 174–218); the hint is a full-width row at y 394 under "المنطقة الزمنية", reading as a time-zone note. Read-only viewers (supervisor, staff with codes) see it too.
- **Evidence:** `qa/manual/screens/M04/M04-F-032-email-hint-under-timezone.png`, `qa/manual/screens/M04/triage/t032-email-hint-under-tz.png`, read-only: `qa/manual/screens/M04/triage/t034-readonly-student-double-gap.png`
- **Root cause (Agent 2 pointer):** `dashboard/src/features/people/UserFieldsSection.tsx` renders `emailHint` as the last child of the grid (`sm:col-span-2` after the time-zone Field) instead of as the email Field's description; no read-only check.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-176: Families list: on retired families the "تعديل" / "استعادة" buttons wrap onto two lines (rows twice as tall)
- **Feature:** M04/People families list. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** qa academy, admin AR, 1440x900. **Tag:** REAL
- **Found by:** Agent 1 (M04-F-033); reproduced by Agent 2 on 2026-10-27.
- **Reproduction steps:** 1. `/app/people/families` → rows with status "موقوفة" (M04 عائلة عبد الرحمن, QA5 Retired Fam, QA5 UI Family 526170).
- **Expected:** both buttons side by side, as "تعديل" / "إيقاف" on active rows.
- **Actual:** "استعادة" drops under "تعديل"; retired rows measure 109 px vs 65 px for active rows.
- **Evidence:** `qa/manual/screens/M04/M04-F-033-retired-family-actions-wrap.png`, `qa/manual/screens/M04/triage/t033-retired-family-actions-wrap.png`
- **Root cause (Agent 2 pointer):** `features/people/FamiliesList.tsx` action cell: the plain restore `Button` and the Confirm-wrapped retire trigger size differently; the cell is not `whitespace-nowrap`/flex-nowrap.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-177: Read-only student page: double gap between "أولياء الأمور" and "تفضيلات الإشعارات" (empty wallet wrapper keeps its margin)
- **Feature:** M04/People student detail. **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes (trivial). **Priority:** low
- **Environment:** qa academy, supervisor AR (also staff-codes), 1440x900. **Tag:** REAL
- **Found by:** Agent 1 (M04-F-034); reproduced by Agent 2 on 2026-10-27.
- **Reproduction steps:** 1. As qa-supervisor@ open `/app/people/students/258`, scroll below the guardians card.
- **Expected:** the normal 24 px between cards.
- **Actual:** ~72 px gap (guardians card ends ≈1167, prefs card starts ≈1240); DOM has an empty `div.mt-6` (height 0).
- **Evidence:** `qa/manual/screens/M04/M04-F-034-readonly-student-double-gap.png`, `qa/manual/screens/M04/triage/t034-readonly-student-double-gap.png`
- **Root cause (Agent 2 pointer):** `routes/_authed/people.students.$personId.tsx` wraps `StudentWalletCard` in `<div className="mt-6">`; the card returns null without wallet permission but the wrapper stays.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-178: Parents list (EN): the "Invite pending" account pill wraps onto two lines
- **Feature:** M04/People parents list. **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes (trivial). **Priority:** low
- **Environment:** qa academy, admin EN, 1440x900. **Tag:** REAL
- **Found by:** Agent 1 (M04-F-035); reproduced by Agent 2 on 2026-10-27.
- **Reproduction steps:** 1. `/app/people/parents` (EN) → Account column.
- **Expected:** one-line pill like "Active" / "No login".
- **Actual:** "Invite / pending" wraps inside the pill; those rows are 67 px vs 50 px (M04 عبد الرحمن القحطاني, QA5 Parent Two, QA5 Reuse old).
- **Evidence:** `qa/manual/screens/M04/M04-F-035-parents-invite-pending-wraps.png`, `qa/manual/screens/M04/triage/t035-parents-invite-pending-wraps.png`
- **Root cause (Agent 2 pointer):** account badge (`people.json` `invited`) has no `whitespace-nowrap`; the Account column is the narrowest.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## --- M14 manual bugs ---

## ETQAN-QA-400: Teacher "I'm in" (دخلت) is active on sessions days away; pressing it only shows a toast about attendance
- **Feature:** M14 Teacher My sessions / Home (`TimesPanel.tsx` TeacherTimes; `scheduling/services/times.py:_gate`). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-001); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/sessions` → "هذا الأسبوع" → first row (28/10 10:00) → "دخلت".
- **Expected:** The button is disabled (or hidden) until 15 minutes before the start (B2b B-2), with a hint like the attendance selects' "يُفتح تسجيل الحضور عند موعد البدء."; any refusal speaks about check-in, not attendance.
- **Actual:** Every future row has an active green "دخلت"; pressing it → 409 POST /api/v1/sessions/52/times/ (`scheduling.not_started`) → red toast "يُفتح تسجيل الحضور عند بدء الحصة." (talks about attendance).
- **Evidence:** `qa/manual/screens/M14/M14-F-001-im-in-on-future-session.png`, `qa/manual/screens/M14/triage/t003-im-in-future.png`
- **Root cause (Agent 2 pointer):** TeacherTimes renders the button whenever `teacher_in_at` is empty; the times refusal reuses the attendance code text.
- **Root cause (Agent 3):** `TeacherTimes` (dashboard `scheduling/TimesPanel.tsx`) rendered an active button whenever `teacher_in_at` was empty and left the start gate to the server; the 409 `scheduling.not_started` was shown with the shared attendance text.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** The button is disabled until the server's gate opens (`has_started`, or for "I'm in" 15 min before `starts_at`, mirroring `times.py:_gate` EARLY_STAMP), with a hint under it (`sessionTimes.times.notOpen` / `outNotOpen`, en/ar/es) linked by `aria-describedby`; a `scheduling.not_started` refusal now uses the same check-in wording.
- **Regression test:** `TimesPanel.test.tsx` "teacher: I'm in is disabled with a hint until 15 minutes before the start (ETQAN-QA-400)" + updated 409 test. Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** AR week tab: every future row shows a dimmed 'دخلت' with 'يُفتح تسجيل الدخول قبل بدء الحصة بـ15 دقيقة.'; EN Today tab 'Check-in opens 15 minutes before the session starts.' After: `qa/manual/screens/M14/fix/ETQAN-QA-400-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-400-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-401: Session report dialog and teacher Postpone dialog have no Cancel button
- **Feature:** M14 Teacher My sessions / Reports (`SessionReportDialog`, postpone dialog). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-002); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/sessions` → "السجل" → "تعديل التقرير" on QA6 Student 1 26/10 17:00. Also EN This week → Postpone.
- **Expected:** An "إلغاء"/Cancel button next to the submit button, like the withdrawal and homework dialogs (and ETQAN-QA-212's fix).
- **Actual:** Only "حفظ التقرير" (Postpone dialog: only Postpone); the way out is Esc or a click outside (on a phone only tapping outside). The subtitle is a question ending in a period and doesn't name the session date.
- **Evidence:** `qa/manual/screens/M14/M14-F-002-report-dialog-no-cancel.png`, `qa/manual/screens/M14/M14-F-002b-postpone-dialog-no-cancel.png`, `qa/manual/screens/M14/triage/t006-report-dialog.png`
- **Root cause (Agent 3):** `ReportForm` (used by `ReportDialog`) and `PostponeDialog` footers had only the submit button.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** `ReportForm` takes an optional `onCancel` and shows Cancel next to Save; `ReportDialog` passes it (both write and edit). `PostponeDialog` footer gets a `DialogClose` Cancel (the ETQAN-QA-212 pattern).
- **Regression test:** `ReportDialog.test.tsx` "has a Cancel that closes without saving", `PostponeDialog.test.tsx` "has a Cancel that closes without postponing". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Report dialog (desktop + 375 phone) and Postpone dialog now have 'إلغاء'. After: `qa/manual/screens/M14/fix/ETQAN-QA-401-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-401-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-402: Teacher Home with no sessions today says only "لا توجد حصص هنا.": no next session and no link to My sessions
- **Feature:** M14 Teacher Home (Today's sessions card). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-003); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/` as qa-teacher (no sessions on 27/10; three tomorrow).
- **Expected:** An empty state that points forward: "لا حصص اليوم" + the next session or a link "عرض حصص هذا الأسبوع".
- **Actual:** Empty card "لا توجد حصص هنا." (generic wording, also on the "اليوم" tab); no hint of tomorrow's sessions.
- **Evidence:** `qa/manual/screens/M14/M14-F-003-home-empty-no-next-session.png`, `qa/manual/screens/M14/triage/t001-home-ar.png`
- **Root cause (Agent 3):** `TeacherSessionTable` used one generic empty title (`scheduling.mine.empty`) for every tab and Home gave no way forward.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** Per-tab empty titles `scheduling.mine.emptyWhen.{today,week,past}` ("لا حصص اليوم.") and, on Home (`TeacherHome` → `linkWhenEmpty`), a "عرض حصصك القادمة" button linking to `/teaching/sessions`. en/ar/es.
- **Regression test:** `TeacherSessions.test.tsx` "on Home, an empty day links to My sessions" (+ updated empty-state test). Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** AR Home with no sessions today: 'لا حصص اليوم.' + button 'عرض حصصك القادمة' → /teaching/sessions. After: `qa/manual/screens/M14/fix/ETQAN-QA-402-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-402-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-403: Payslip session lines are frozen text: ISO dates "2026-07-15" in both languages and the course in the generation language ("F03 قرآن" on the English payslip)
- **Feature:** M14 Payroll payslip detail / print (`payroll/services/build.py:describe_session`). **Severity:** P3. **Type:** translation. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-004 (+F-027)); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/payslips/42` (PAY-000039); EN `/app/teaching/payslips/1` (PAY-000001); also the print page.
- **Expected:** Session date in the UI's date format (19/10/2026 style in AR, "Sep 3, 2026" in EN) and the course name in the interface language, like My sessions.
- **Actual:** "2026-07-15 — تجويد — QA student" (AR) while the paid date shows 2026/10/27; EN shows "2026-09-03 — F03 قرآن — QA student".
- **Evidence:** `qa/manual/screens/M14/M14-F-004-payslip-iso-dates.png`, `qa/manual/screens/M14/M14-F-027-payslip-arabic-course-in-english.png`, `qa/manual/screens/M14/triage/t008-payslip-ar.png`, `qa/manual/screens/M14/triage/t010-payslip-en.png`, `qa/manual/screens/M14/triage/t009-print.png`
- **Root cause (Agent 2 pointer):** `describe_session` stores `f"{occurs_on.isoformat()} — {course} — {student}"` in the academy language at generation; the UI prints the stored string. Fix needs structured fields (date, course id) on the line or rendering from the session (API change → proposal).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-404: Withdrawal amount rejects Arabic-Indic digits: "٥" gives "أدخل مبلغًا أكبر من صفر"
- **Feature:** M14 Teacher My balance (`WithdrawalDialog` amount parsing). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-005); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/balance` → "طلب سحب" → amount `٥` → "إرسال الطلب".
- **Expected:** ٥ is read as 5 (Arabic phone keyboards type these digits), or a message asking for 0–9.
- **Actual:** Red "أدخل مبلغًا أكبر من صفر، مثل 150 أو 150.50.": tells the teacher 5 is not above zero.
- **Evidence:** `qa/manual/screens/M14/M14-F-005-arabic-digits-rejected.png`, `qa/manual/screens/M14/triage/t014-withdraw-arabic-digit.png`
- **Root cause (Agent 2 pointer):** Normalise ٠-٩ / ۰-۹ (and ٫) before parsing money input.
- **Root cause (Agent 3):** Money parsing (`billing/schemas.ts amount()`/`looseAmount`, `lib/money.ts toMinor`) used ASCII `\d` and `Number()`, so Arabic-Indic digits failed the pattern and read as NaN.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** New `latinDigits()` in `lib/money.ts` maps ٠-٩, ۰-۹ and the Arabic decimal point ٫ to 0-9/"."; used by `toMinor`, `amount()`, `looseAmount` and the invoice/record precision checks, so every money field (withdrawal included) accepts them.
- **Regression test:** `lib/money.test.ts` "reads Arabic-Indic digits and the Arabic decimal point", `payroll/schemas.test.ts` "reads Arabic-Indic and Persian digits as 0-9", `MyBalance.test.tsx` types "٢٠" and expects 2000 minor. Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Typed '١٫٥' → request created for 1.50 ج.م. (then cancelled, note 'M14-G إعادة اختبار'). After: `qa/manual/screens/M14/fix/ETQAN-QA-404-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-404-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-405: Teacher's own withdrawal dialog speaks about "المعلم" in the third person
- **Feature:** M14 Teacher My balance (`WithdrawalDialog` description, shared with the office). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-006); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/balance` → "طلب سحب".
- **Expected:** Addressed to the teacher: "اسحب من رصيدك بإحدى عملاته…".
- **Actual:** "اسحب من رصيد المعلم بإحدى عملاته. لا يمكن أن يزيد المبلغ على المتاح." (office wording).
- **Evidence:** `qa/manual/screens/M14/M14-F-006-withdraw-copy-third-person.png`, `qa/manual/screens/M14/triage/t014-withdraw-arabic-digit.png`
- **Root cause (Agent 3):** `WithdrawalDialog` used the office sentence `payroll.withdrawals.body` for both callers.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** Teacher mode uses new `payroll.withdrawals.bodyOwn` ("اسحب من رصيدك بإحدى عملاته…"); the office keeps `body`. en/ar (es has no payroll withdrawals section; falls back to en).
- **Regression test:** `MyBalance.test.tsx` "requests a withdrawal for themselves…" asserts "Withdraw from your balance". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** AR 'اسحب من رصيدك بإحدى عملاته…'; EN 'Withdraw from your balance in one of its currencies…'. After: `qa/manual/screens/M14/fix/ETQAN-QA-405-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-405-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-406: Cancel-request confirmation offers "إلغاء" and "إلغاء هذا الطلب" side by side
- **Feature:** M14 Teacher My balance (`CancelWithdrawal`). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-007); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/balance` → request 1.00 → "إلغاء الطلب".
- **Expected:** Distinct labels, e.g. "تراجع" (keep) and "نعم، ألغِ الطلب".
- **Actual:** Dialog titled "إلغاء هذا الطلب" with buttons "إلغاء" (= keep it) and red "إلغاء هذا الطلب"; easy to press the wrong one.
- **Evidence:** `qa/manual/screens/M14/M14-F-007-cancel-vs-cancel-request.png`, `qa/manual/screens/M14/triage/t015-cancel-vs-cancel.png`
- **Root cause (Agent 3):** Shared `components/Confirm.tsx` always labels the dialog buttons `people.cancel` and the title; for "Cancel this request" both read as إلغاء.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** `Confirm` gains optional `keepLabel`/`confirmLabel` (defaults unchanged for other callers); `CancelWithdrawal` passes "تراجع" / "نعم، ألغِ الطلب" (`payroll.withdrawals.keep`/`confirmCancel`, en/ar).
- **Regression test:** `MyBalance.test.tsx` "cancels a request under review…" checks "Keep it" and confirms with "Yes, cancel the request"; `WithdrawalsPage.test.tsx` updated. Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Confirm shows 'تراجع' and 'نعم، ألغِ الطلب'. After: `qa/manual/screens/M14/fix/ETQAN-QA-406-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-406-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-407: Availability overlap error is raw English: "This window overlaps another one on the same day."
- **Feature:** M14 Teacher availability (`scheduling/services/availability.py:94`, `AvailabilityEditor`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-008); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/availability` (Mon 16:00–20:00 saved) → Monday "+" → 18:00–22:00 → "حفظ المواعيد".
- **Expected:** An Arabic message under the window, checked before sending like ETQAN-QA-206's end-after-start check.
- **Actual:** 400 PUT /api/v1/schedule/availability/ → ".This window overlaps another one on the same day" (period jumps to the start in RTL). ETQAN-QA-206 fixed only "End the window after it starts."; its gate noted this one as a proposal (coverage-gaps M06).
- **Evidence:** `qa/manual/screens/M14/M14-F-008-overlap-error-english.png`, `qa/manual/screens/M14/triage/t019-overlap-english.png`
- **Root cause (Agent 2 pointer):** Add an overlap refine to `availabilityFormSchema` with an `availability.errors.overlap` key (en/ar).
- **Root cause (Agent 3):** The overlap rule lived only in `scheduling/services/availability.py:_validated`, whose English field error was shown verbatim; ETQAN-QA-206 only moved the end-after-start check to the client.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** `availabilityFormSchema` adds a `superRefine` with the server's exact rule (same weekday, `start < other.end && other.start < end`; touching windows allowed) → `availability.errors.overlap` (en/ar) under the later row. As a fallback the sentence is also mapped in `lib/server-messages.ts` (ETQAN-QA-157 mechanism).
- **Regression test:** `AvailabilityEditor.test.tsx` "checks overlaps before saving (ETQAN-QA-407)". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** AR 'هذه الفترة تتداخل مع فترة أخرى في اليوم نفسه.' / EN 'This window overlaps another one on the same day.' under the row. After: `qa/manual/screens/M14/fix/ETQAN-QA-407-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-407-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-408: Availability: a refused save shows nothing where the teacher is looking (error at the top, view stays at the bottom, no toast)
- **Feature:** M14 Teacher availability (`AvailabilityEditor`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-009); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. As ETQAN-QA-407; "حفظ المواعيد" sits under seven day cards, so the page is scrolled down when it is pressed.
- **Expected:** Scroll/focus to the first error or a toast (ETQAN-QA-158 fixed this for person forms via `applyServerErrors` shouldFocus).
- **Actual:** scrollY stays 362; the viewport shows only empty days and the button; the error under Monday is off-screen. Success does toast "تم حفظ المواعيد.".
- **Evidence:** `qa/manual/screens/M14/M14-F-009-availability-error-offscreen.png`, `qa/manual/screens/M14/triage/t018-overlap-offscreen.png`
- **Root cause (Agent 2 pointer):** The availability form's server-error path doesn't go through the QA-158 focus fix (per-window field errors).
- **Root cause (Agent 3):** The server error is keyed `windows.<i>` (a row, not an input), so `applyServerErrors`' `shouldFocus` (ETQAN-QA-158) had nothing to focus and the view stayed at the bottom.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** `AvailabilityEditor.onSubmit` reads the refused row index from the parsed field errors and `setFocus('windows.<i>.start_time')`, which scrolls that row (and its message) into view.
- **Regression test:** `AvailabilityEditor.test.tsx` "puts the server's refusal under its row, in view (ETQAN-QA-408)" asserts focus on the refused row's start. Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Overlap on Saturday (bottom of page): view scrolls to the row, error and focused field visible. After: `qa/manual/screens/M14/fix/ETQAN-QA-408-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-408-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-409: After "دخلت"/"خرجت" the row never shows the recorded times; the button just disappears
- **Feature:** M14 Teacher Home / My sessions (`TeacherSessionTable`, `TimesPanel` TeacherTimes). **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-010); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. maryam.khatib@ AR `/app/` → row Aisha Rahman 27/10 15:00 → "دخلت" → "خرجت" (done by Agent 1 at 23:05 Cairo).
- **Expected:** The row shows "دخلت 23:05 · خرجت 23:06" (or similar) so the teacher can see what was recorded.
- **Actual:** Toast "تم التسجيل." (info icon); the button flips, then disappears; nothing on the row shows a time. (Stamping 8 h late is allowed by design: B2b B-1/B-2, times are a record only, not read by pay; not part of this bug.)
- **Evidence:** `qa/manual/screens/M14/M14-F-010-im-in-hours-late.png`, `qa/manual/screens/M14/s034-row.png`, `qa/manual/screens/M14/triage/t036-maryam-home.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-410: My balance shows a total with no explanation of how it is made
- **Feature:** M14 Teacher My balance (`MyBalance`). **Severity:** P4. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-012); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/balance`.
- **Expected:** One line saying the balance = payslips paid to balance − paid withdrawals (payroll.md "Balance"), ideally with a link to My payslips.
- **Actual:** Card "EGP / الرصيد: 159.00 ج.م. / المتاح: 159.00 ج.م." and the request list; nothing ties it to payslips (raw "EGP" header above "ج.م." amounts).
- **Evidence:** `qa/manual/screens/M14/M14-F-012-balance-no-explanation.png`, `qa/manual/screens/M14/triage/t013-balance.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-411: Reports to write: every row repeats the teacher's own name, and there is no count
- **Feature:** M14 Teacher Reports to write. **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-013); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/reports`.
- **Expected:** Rows show student, date, course; a total ("24 تقريرًا").
- **Actual:** "QA teacher · قرآن F03 · 10:00 2026/08/12" on every row; long list, no count.
- **Evidence:** `qa/manual/screens/M14/M14-F-013-reports-own-name-repeated.png`, `qa/manual/screens/M14/triage/t007-reports.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-412: My sessions history: past sessions with no attendance still show a green "مجدولة", identical to future ones; nothing flags them
- **Feature:** M14 Teacher My sessions → السجل. **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-014); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/sessions` → "السجل".
- **Expected:** Past sessions without attendance stand out ("بحاجة لتسجيل الحضور") or can be filtered.
- **Actual:** Sessions from 26/10 (and earlier) show green "مجدولة" + "لم يُحدَّد" like future sessions; 5 pages, no filter; "كتابة التقرير" appears only after marking.
- **Evidence:** `qa/manual/screens/M14/M14-F-014-history-past-still-scheduled.png`, `qa/manual/screens/M14/triage/t005-history.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-413: Homework session picker lists bare dates, many identical ("19/10/2026" ×14)
- **Feature:** M14 Teacher Homework create / detail dialogs. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-015); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/homework` → "واجب جديد" → QA student → تجويد → open "الحصة (اختياري)".
- **Expected:** Each option identifies one session (date + time, maybe status).
- **Actual:** "بلا حصة|30/10/2026|29/10/2026|…|19/10/2026" ×14|…: no time, so identical options.
- **Evidence:** `qa/manual/screens/M14/M14-F-015-homework-session-dates-only.png`, `qa/manual/screens/M14/triage/t022-hw-instructions-english.png`
- **Root cause (Agent 2 pointer):** Option label uses only the date.
- **Root cause (Agent 3):** `NewHomeworkDialog`/`HomeworkDialog` session options rendered `formatDay(occurs_on)` only.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** New `useSessionLabel()` in `homework/bits.ts`: day + start time on the viewer's clock (`wallTime`, me.timezone), each part FSI/PDI-isolated (an `<option>` can't hold `<bdi>`, cf. ETQAN-QA-207). Used by both pickers.
- **Regression test:** `NewHomeworkDialog.test.tsx` "offers recent sessions first…" asserts the option text has day · time. Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Session picker lists '30/10/2026 · 21:00' etc. (date + time). After: `qa/manual/screens/M14/fix/ETQAN-QA-413-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-413-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-414: Delete-homework confirmation opens over the homework dialog without dimming it; the two cards blend
- **Feature:** M14 Teacher Homework detail dialog. **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-016); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. Homework → "فتح" → "حذف الواجب".
- **Expected:** The confirmation stands out (overlay over the first dialog).
- **Actual:** A second card with the same background in the middle of the first; fields above/below stay bright; the title repeats.
- **Evidence:** `qa/manual/screens/M14/M14-F-016-homework-delete-confirm-overlap.png`, `qa/manual/screens/M14/triage/t028-hw-delete-confirm.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-415: Answered homework is not flagged for the teacher: same grey "غير مكتمل" as unanswered
- **Feature:** M14 Teacher Homework list. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-017); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. Teacher creates a text homework for QA student; qa-student answers it (`/app/learning/homework`); teacher opens `/app/teaching/homework`.
- **Expected:** Answered-but-not-complete homework stands out ("بانتظار المراجعة" badge or filter); a count on the menu item would help.
- **Actual:** Status stays the grey "غير مكتمل" exactly like unanswered ones; the only hint is the "تمت الإجابة" date. (Agent 1's 3-line row wrap was with a long title; not seen with a short one.)
- **Evidence:** `qa/manual/screens/M14/M14-F-017-homework-answered-not-flagged.png`, `qa/manual/screens/M14/triage/t027-hw-answered-not-flagged.png`
- **Root cause (Agent 2 pointer):** `answered_at` is in the payload (homework-content.md: "Answered" means answered_at IS NOT NULL); the list doesn't use it for the status.
- **Root cause (Agent 3):** `HomeworkList` chose the chip only from `status`, ignoring `answered_at`.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** Incomplete + `answered_at` shows a primary-coloured "بانتظار المراجعة" chip (`homework.status.awaitingReview`, en/ar); unanswered stays grey "غير مكتمل".
- **Regression test:** `HomeworkList.test.tsx` "flags answered homework for review… (ETQAN-QA-415, ETQAN-QA-426)". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Answered homework row shows green 'بانتظار المراجعة' / 'Awaiting review'. After: `qa/manual/screens/M14/fix/ETQAN-QA-415-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-415-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-416: Students' levels: the level picker is empty ("اختر مستوى" only) with no explanation
- **Feature:** M14 Teacher My students' levels (progress dialog). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-018); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/levels` → "فتح التقدّم" on QA student F03 → "تحديد المستوى الأول".
- **Expected:** A list of levels, or "لم تُضبط مستويات لهذه الدورة؛ اطلب من الإدارة".
- **Actual:** Select has only "اختر مستوى"; "حفظ" disabled; every row "بلا مستوى … 0 / 0". Minor: filter says "بدون مستوى", rows "بلا مستوى"; placeholder "بحث عن الطلاب" vs "ابحث عن الطلاب" on Homework.
- **Evidence:** `qa/manual/screens/M14/M14-F-018-levels-empty-picker.png`, `qa/manual/screens/M14/triage/t030-levels-empty-picker.png`
- **Root cause (Agent 3):** `ProgressPanel` rendered the level `<Select>` even when the course has no active level.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** With no active level the form is replaced by a sentence: teacher `curriculum.progress.noLevels` ("…اطلب من الإدارة إضافتها"), office `noLevelsOffice` (keys shared with a parallel area's edit of the same file; values theirs).
- **Regression test:** `ProgressPanel.test.tsx` "says why there is no level to choose (ETQAN-QA-416)". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Progress dialog: 'لا توجد مستويات لهذه الدورة بعد. اطلب من الإدارة إضافتها.' instead of an empty picker. After: `qa/manual/screens/M14/fix/ETQAN-QA-416-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-416-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-417: Honour board tells the teacher "كرّم الطلاب المتميزين كل شهر." but teachers can't add anyone
- **Feature:** M14 Teacher Honour board. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-019); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/honour`.
- **Expected:** Teacher wording such as "الطلاب المكرَّمون هذا الشهر" (only the office writes entries, reviews-honour.md).
- **Actual:** Imperative subtitle + empty state, no button.
- **Evidence:** `qa/manual/screens/M14/M14-F-019-honour-subtitle-no-action.png`, `qa/manual/screens/M14/triage/t031-honour.png`
- **Root cause (Agent 3):** The teacher (and student) honour routes reused the office subtitle `honour.subtitle` (imperative).
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** `teaching.honour.tsx` and `learning.honour.tsx` use new `honour.subtitleReader` ("الطلاب المكرَّمون لتميزهم كل شهر.", en/ar); the office page keeps its own.
- **Regression test:** `routes/_authed/teaching.honour.test.tsx` (new). Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Teacher honour subtitle: 'الطلاب المكرَّمون لتميزهم كل شهر.' After: `qa/manual/screens/M14/fix/ETQAN-QA-417-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-417-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-418: "حذف الواجب" is offered on answered homework; it fails only after the teacher confirms
- **Feature:** M14 Teacher Homework detail (`learning` delete_homework). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-020); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. Homework 3 (answered by qa-student) → "فتح" → "حذف الواجب" → confirm.
- **Expected:** No delete for the teacher once answered (homework-content.md: the teacher can delete only while unanswered), or disabled with the reason.
- **Actual:** 409 DELETE /api/v1/learning/homework/3/ → toast "تمت الإجابة عن هذا الواجب: لا يمكن حذفه الآن إلا من المكتب.".
- **Evidence:** `qa/manual/screens/M14/M14-F-020-delete-answered-homework-offered.png`, `qa/manual/screens/M14/triage/t029-hw-delete-answered-409.png`
- **Root cause (Agent 3):** `HomeworkDialog` set `canDelete = isTeacher || can(...)`, ignoring the documented rule (homework-content.md: the teacher deletes only while unanswered).
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** `canDelete = isTeacher ? answered_at === null : can('homework.delete')`; the office keeps Delete at any time.
- **Regression test:** `HomeworkDialog.test.tsx` "offers the teacher Delete only while unanswered" and "lets the teacher delete an unanswered homework". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Answered homework dialog offers no delete (only Close/Save/Mark complete). After: `qa/manual/screens/M14/fix/ETQAN-QA-418-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-418-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-419: New homework: "Instructions are required for a text homework." in English, and the field isn't marked required
- **Feature:** M14 Teacher Homework create (`learning` model check / serializer). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-021); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR "واجب جديد" → QA student / تجويد / title "M14-T2 واجب بلا تعليمات" / "إجابة كتابية" / empty التعليمات → "إضافة واجب".
- **Expected:** Arabic message, checked before sending; "التعليمات" shows * for a written-answer homework (the file kind shows * on الملف).
- **Actual:** 400 POST /api/v1/learning/homework/ → ".Instructions are required for a text homework" under the field (RTL period first). (Native file input text "Choose FileNo file chosen" is headless Chromium, not filed.)
- **Evidence:** `qa/manual/screens/M14/M14-F-021-homework-instructions-english-error.png`, `qa/manual/screens/M14/triage/t022-hw-instructions-english.png`
- **Root cause (Agent 2 pointer):** Same class as ETQAN-QA-206 (server English text), different message.
- **Root cause (Agent 3):** The "instructions required for a text homework" rule existed only in `learning/services/homework.py` (English field error); the form neither checked it nor marked the field.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** `NewHomeworkDialog` and `HomeworkDialog` check it before sending (`homework.required.instructions`, en/ar) and mark Instructions `required` while the kind is the written answer.
- **Regression test:** `NewHomeworkDialog.test.tsx` "asks for instructions on a written-answer homework before sending", `HomeworkDialog.test.tsx` "asks for instructions on a written-answer homework". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Empty instructions: AR 'اكتب التعليمات للواجب ذي الإجابة المكتوبة.' / EN 'Write the instructions for a written-answer homework.'; field marked *. After: `qa/manual/screens/M14/fix/ETQAN-QA-419-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-419-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-420: Payslip print page has no way back
- **Feature:** M14 Payroll print page `/app/payslips/<id>/print`. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-022); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/payslips/42` → "طباعة" (same tab).
- **Expected:** A "رجوع" link (hidden when printing) or open in a new tab.
- **Actual:** Bare page with only "طباعة"; only the browser back button returns (hard in an installed app / phone).
- **Evidence:** `qa/manual/screens/M14/M14-F-022-print-page-no-way-back.png`, `qa/manual/screens/M14/triage/t009-print.png`
- **Root cause (Agent 3):** The shared `PrintSheet` (branding) toolbar had only Print.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** `PrintSheet` adds a Back button (hidden when printing): `history.back()` when the router can go back (`useCanGoBack`), else home. Applies to every print page (payslip, invoice, certificates, reports). `common.back` en/ar/es.
- **Regression test:** `PayslipPrint.test.tsx` "has a way back, home when opened fresh (ETQAN-QA-420)". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Print page has 'رجوع'; opened fresh, Back goes to /app/. After: `qa/manual/screens/M14/fix/ETQAN-QA-420-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-420-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-421: "Confirm receipt" is a red danger-style button
- **Feature:** M14 Teacher My payslips (`ConfirmReceipt`). **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-023); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. qa-teacher13@ EN `/app/teaching/payslips` (paid, unconfirmed payslips).
- **Expected:** A positive/neutral style: confirming pay isn't destructive.
- **Actual:** Red "Confirm receipt" on each card (and red confirm in the dialog per Agent 1), the colour of delete/cancel.
- **Evidence:** `qa/manual/screens/M14/M14-F-023-confirm-receipt-red.png`, `qa/manual/screens/M14/triage/t012-confirm-receipt-red.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-422: Payslip list doesn't show which payslips were confirmed
- **Feature:** M14 Teacher My payslips list. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-024); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. qa-teacher EN `/app/teaching/payslips` (PAY-000001 and PAY-000039 are confirmed).
- **Expected:** A "Receipt confirmed" badge/date on the card (the detail page shows it).
- **Actual:** Cards show only number, month, net, Paid / Paid to balance; confirmed and unconfirmable look the same.
- **Evidence:** `qa/manual/screens/M14/M14-F-024-receipt-state-not-in-list.png`, `qa/manual/screens/M14/triage/t011-payslips-list-en.png`
- **Root cause (Agent 3):** `TeacherPayslips` cards ignored `acknowledged_at` (only `ConfirmReceipt`, which hides itself when acknowledged).
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** An acknowledged payslip shows a green "تم تأكيد الاستلام" chip (`payroll.receipt.confirmed`) in place of the button.
- **Regression test:** `TeacherPayslips.test.tsx` "offers Confirm receipt…" now asserts the chip on the confirmed one only. Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** Payslip list shows 'تم تأكيد الاستلام' chip on confirmed payslips. After: `qa/manual/screens/M14/fix/ETQAN-QA-422-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-422-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-423: Status "تحت تصرف الإدارة" / "At the administration's disposal" is shown to the teacher with no explanation
- **Feature:** M14 Teacher My sessions (status badge). **Severity:** P4. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-026); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR `/app/teaching/sessions` → "هذا الأسبوع" → row 29/10 21:30 QA student تجويد.
- **Expected:** A short hint for the teacher (e.g. tooltip: "الحصة لا تُحتسب ولا تُدفع؛ راجع الإدارة").
- **Actual:** Red badge, no explanation; Postpone hidden. ("دخلت" on an at-disposal session is by design, B2b B-2, not part of this bug.)
- **Evidence:** `qa/manual/screens/M14/M14-F-026-admin-disposal-status-ar.png`, `qa/manual/screens/M14/M14-F-026-admin-disposal-status-en.png`, `qa/manual/screens/M14/triage/t004-disposal-row.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-424: Payslip number in the display font reads "PAY-oooo39": old-style zeros look like the letter o
- **Feature:** M14 Payslip detail card title (display serif font). **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-028); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. EN `/app/teaching/payslips/1`, AR `/payslips/42` (also phone; also "Fo3" in the levels dialog title).
- **Expected:** Lining figures for reference numbers (`font-variant-numeric: lining-nums`).
- **Actual:** "PAY-000001" renders with old-style figures: 0 like o, 1 like ı; the list shows it in the normal font.
- **Evidence:** `qa/manual/screens/M14/M14-F-028-payslip-number-oldstyle-zeros.png`, `qa/manual/screens/M14/triage/t010-payslip-en.png`, `qa/manual/screens/M14/triage/t008-payslip-ar.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-425: Phone: availability row puts "إلى" after the start field and the end field on the next line without a label
- **Feature:** M14 Teacher availability (`AvailabilityEditor`), 375x812. **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-029); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR 375x812 `/app/teaching/availability`.
- **Expected:** "من [ ]" and "إلى [ ]" kept together, each label with its field.
- **Actual:** Line 1 "من [04:00 PM] إلى", line 2 "[08:00 PM] ×"; Save is under seven cards.
- **Evidence:** `qa/manual/screens/M14/M14-F-029-mobile-availability-to-label-detached.png`, `qa/manual/screens/M14/triage/t035-m-availability.png`
- **Root cause (Agent 3):** `AvailabilityEditor` put both labels and both inputs as siblings in one `flex-wrap` row, so wrapping split "إلى" from its field.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** Each label + input pair is wrapped in its own non-wrapping `span.flex`, so a phone wraps between pairs.
- **Regression test:** `AvailabilityEditor.test.tsx` "keeps each label with its time field (ETQAN-QA-425)". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** 375px: 'من' + start on one line, 'إلى' + end + × on the next. After: `qa/manual/screens/M14/fix/ETQAN-QA-425-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-425-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-426: Phone: Homework page widens to ~588px and opens scrolled sideways onto a blank area
- **Feature:** M14 Teacher Homework list, 375x812. **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-030); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR 375x812 `/app/teaching/homework` with one row; `eval [scrollWidth, clientWidth, scrollX]`.
- **Expected:** Table scrolls in its own box; title, filters and "واجب جديد" visible.
- **Actual:** `[588, 375, -213]`; the first screen shows only "النوع"/"تمت الإجابة" and white space. Same pattern as ETQAN-QA-204 (sr-only header span outside an unpositioned scroller), different page.
- **Evidence:** `qa/manual/screens/M14/M14-F-030-mobile-homework-page-wide.png`, `qa/manual/screens/M14/triage/t032-m-homework.png`
- **Root cause (Agent 2 pointer):** Likely the QA-204 root cause: add `relative` to the table scroller.
- **Root cause (Agent 3):** Same root cause as ETQAN-QA-204: the table scroller in `HomeworkList` wasn't positioned, so the absolutely placed sr-only header escaped and widened the page.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** `relative` added to the scroller.
- **Regression test:** `HomeworkList.test.tsx` asserts the scroller has `relative overflow-x-auto`. Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** 375px: scrollWidth 375, scrollX 0; table scrolls inside its own box. After: `qa/manual/screens/M14/fix/ETQAN-QA-426-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-426-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-427: Phone: payslip line runs rate and amount together ("60.00 ج.م.60.00 ج.م.")
- **Feature:** M14 Payslip detail, 375x812. **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-031); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR 375x812 `/app/teaching/payslips/42`.
- **Expected:** Minutes, rate and amount readable as separate columns.
- **Actual:** "60 60.00 ج.م.60.00 ج.م." with no gap; description breaks "— 2026-07-15" / "تجويد — QA student".
- **Evidence:** `qa/manual/screens/M14/M14-F-031-mobile-payslip-amounts-glued.png`, `qa/manual/screens/M14/triage/t034-m-payslip.png`
- **Root cause (Agent 3):** `PayslipBody` session table cells had only vertical padding (`py-2`), so on a phone adjacent money cells touched and wrapped.
- **Fix (Agent 3, dashboard branch `qa/manual-2026-10`, uncommitted):** Number cells/headers get `ps-3` and money cells `whitespace-nowrap`.
- **Regression test:** `PayslipBody.test.tsx` "keeps a gap before each number and money on one line (ETQAN-QA-427)". Evidence: `qa/manual/evidence/M14/fix-1/` (vitest, tsc, biome).
- **Retest (Agent 2 gate, 2026-10-28):** 375px: rate '60.00 ج.م.' and amount '60.00 ج.م.' in separate columns with spacing. After: `qa/manual/screens/M14/fix/ETQAN-QA-427-after.png`; before/after: `qa/manual/screens/M14/fix/ETQAN-QA-427-before-after.png`. Scoped vitest `qa/manual/evidence/M14/gate-1/vitest.txt` (all M14 tests pass).
- **Verification status:** VERIFIED

## ETQAN-QA-428: Phone: students' levels table cuts the "فتح التقدّم" button at the screen edge and wraps names over 3 lines
- **Feature:** M14 Teacher My students' levels, 375x812. **Severity:** P3. **Type:** mobile. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M14 (M14-F-032); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` unless noted.
- **Reproduction steps:**
  1. AR 375x812 `/app/teaching/levels`.
- **Expected:** The row action visible (cards on phone).
- **Actual:** Only "فت" of the button shows at the left edge; "QA Student Three" takes 3 lines; reachable only by scrolling the table sideways. Same layout problem as ETQAN-QA-118 (Home table), different component.
- **Evidence:** `qa/manual/screens/M14/M14-F-032-mobile-levels-button-cut.png`, `qa/manual/screens/M14/triage/t033-m-levels.png`
- **Root cause (Agent 2 pointer):** Layout change (card view on narrow screens) → proposal, as ETQAN-QA-118.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-429: Teacher "هذا الأسبوع": the two "opens at…" hints repeat under every future row, so only 3 sessions fit on a desktop screen
- **Feature:** M14 Teacher My sessions, week tab (`AttendanceControls.tsx` `opensAtStart` + `TimesPanel.tsx` `sessionTimes.notOpen`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`. **Tag:** REAL
- **Found by:** Agent 1, M14 confirmation sweep (M14-F-033), after the ETQAN-QA-400 fix; reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher ahmad.haddad@qa.etqan.test / `QA-People-2026!` with several sessions this week.
- **Reproduction steps:**
  1. AR 1440x900 `/app/teaching/sessions` → "هذا الأسبوع".
- **Expected:** the rule said once (e.g. one line above the table, or as the disabled button's tooltip) so the week list stays scannable.
- **Actual:** every future row carries "يُفتح تسجيل الحضور عند موعد البدء." under the attendance selects and "يُفتح تسجيل الدخول قبل بدء الحصة بـ15 دقيقة." under the dimmed "دخلت"; rows are ~185 px, only 3 of 7 sessions fit on the first screen.
- **Evidence:** `qa/manual/screens/M14/M14-F-033-week-hints-repeated.png`, `qa/manual/screens/M14/triage/t040-week-hints.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-430: Phone: teacher Homework table hides "الحالة", "تاريخ التكليف" and the only action "فتح" off-screen to the side
- **Feature:** M14 Teacher Homework list (`HomeworkList`), 375x812. **Severity:** P3. **Type:** mobile. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`. **Tag:** REAL
- **Found by:** Agent 1, M14 confirmation sweep (M14-F-034), after the ETQAN-QA-426 fix; reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher qa-teacher@qa.etqan.test / `QA-People-2026!` with open homework.
- **Reproduction steps:**
  1. AR 375x812 `/app/teaching/homework` (غير مكتمل).
- **Expected:** the teacher can open a homework from the first screen (cards on phone, or the action visible).
- **Actual:** page no longer widens (scrollWidth 375 — ETQAN-QA-426 holds), but the table is 578 px in a 341 px scroller; only Student/Course/Title/Type/"تمت الإجابة" show, status, date and "فتح" are off the left edge with no scroll hint; the title wraps over 4 lines. Same layout class as ETQAN-QA-118 (Home) and ETQAN-QA-428 (levels), different page.
- **Evidence:** `qa/manual/screens/M14/M14-F-034-mobile-homework-open-offscreen.png`, `qa/manual/screens/M14/triage/t042-m-homework-open-offscreen.png`
- **Root cause (Agent 2 pointer):** Layout change (card view on narrow screens) → proposal, as ETQAN-QA-118/428.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## --- M09 manual bugs ---

## ETQAN-QA-350: Payslips list: "إظهار أعداد الحصص" squeezes the table so every payslip number breaks over two lines ("PAY-" / "000014")
- **Feature:** M09 Payslips list (`PayslipsList.tsx` number cell). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-001); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/payslips` (September 2026).
  2. Tick "إظهار أعداد الحصص".
- **Expected:** The four extra columns fit or the table scrolls; the number stays on one line.
- **Actual:** Every number wraps at the hyphen, doubling row height; the same wrap shows on a phone without the toggle (see ETQAN-QA-369). The toggle is remembered between visits.
- **Evidence:** `qa/manual/screens/M09/M09-F-001-payslip-number-wraps.png`, `qa/manual/screens/M09/triage/T-F001-number-wraps.png`
- **Root cause (Agent 2 pointer):** `whitespace-nowrap` on the number cell.
- **Root cause:** `PayslipsList.tsx` number cell had no `whitespace-nowrap`; with the four counter columns (and on a phone) the table squeezed it, and the browser broke "PAY-000014" at the hyphen.
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** number `<td>` gets `whitespace-nowrap` (the table already scrolls sideways in its `overflow-x-auto` wrapper).
- **Regression test:** `PayslipsList.test.tsx` "keeps each payslip number on one line". Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). AR /payroll/payslips Sep 2026 + 'إظهار أعداد الحصص': every number on one line (cell h≈50px, was ~67px). Note: Oct (5 counter columns) now wraps teacher names over 3 lines; table scrolls, not filed. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-350-after.png` (before | after), raw shots `fix/ETQAN-QA-350-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-351: Payslip page: payment notes float with no label, and there is no way back to the payslips list
- **Feature:** M09 Payslip detail (`PayslipPage.tsx` / `PayslipBody.tsx`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-002); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/payslips/43` (PAY-000040, paid, notes "scn").
- **Expected:** Notes under a label ("ملاحظات الدفع"); a back link or breadcrumb to "كشوف الرواتب".
- **Actual:** "scn" sits alone between the header fields and "الحصص" with no label; the page title is the generic "كشف راتب" and only the sidebar/browser Back returns to the list.
- **Evidence:** `qa/manual/screens/M09/M09-F-002-unlabelled-notes-no-back.png`, `qa/manual/screens/M09/M09-F-002b-long-notes-unlabelled.png`, `qa/manual/screens/M09/triage/T-F002-notes-unlabelled.png`
- **Root cause:** `PayslipPage.tsx` printed `payslip.notes` as a bare `<p>` outside the facts list, and the page had no link to its list (the route header is a plain `PageHeader`).
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** notes are a labelled entry in the facts `<dl>` ("ملاحظات الدفع" / "Payment notes", full width, keeps line breaks); a `BackLink` nav above the actions (and above the not-found alert) goes to `/payroll/payslips` for the office or `/teaching/payslips` for the teacher. New keys `payroll.payslip.{notes,back,links}` in en/ar/es.
- **Regression test:** `PayslipPage.test.tsx` "labels the payment notes and links back to the payslips" (office and teacher hrefs). Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** OPEN (reopened 2026-10-28, Agent 2 gate-1: half fixed). Back link 'العودة إلى كشوف الرواتب' works (office /app/payroll/payslips, teacher /app/teaching/payslips, also on 375px) and the label 'ملاحظات الدفع' is there. But the value `<dd dir="auto">` spans the whole row (`lg:col-span-4`), so a Latin note ('scn') renders at the far LEFT edge, ~1,000px from its right-aligned label, which looks as detached as before. Other Latin values ('SCN Payroll Teacher') stay under their labels. Fix: keep the block in the page direction and isolate only the text (e.g. `<dd><span dir="auto">…</span></dd>` or `text-start` + `unicode-bidi:plaintext` on an inline span). Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-351-after.png`.

## ETQAN-QA-352: Rates page is one 8,400-px column of teacher cards with no search or filter; per-student rates are only at the very bottom
- **Feature:** M09 Payroll rates (`RatesPage.tsx`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-004); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/rates`.
  2. `eval` `document.documentElement.scrollHeight` and count search inputs.
- **Expected:** A teacher search/filter (or a compact table) and the per-student rates reachable without scrolling past every teacher.
- **Actual:** Page height 8,421 px, 27 teacher cards, 0 search inputs; "أجور حسب الطالب" appears after the last card.
- **Evidence:** `qa/manual/screens/M09/M09-F-004-rates-page-no-search.png`, `qa/manual/screens/M09/triage/T-F004-rates-top.png`
- **Root cause (Agent 2 pointer):** Layout/feature change → likely a proposal.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-353: Rates page (AR): "لـ" glues to the Latin teacher name in buttons and dialog titles ("QA6 Teacher BJ إزالة الراتب الثابت"); full names inside row buttons
- **Feature:** M09 Payroll rates (`FixedSalary.tsx`, `StudentRates.tsx`, `RateDialog`/fixed-salary dialog titles). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-005); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/rates` → QA6 Teacher B card, fixed-salary row.
  2. QA6 Teacher C → "تعيين راتب ثابت" (dialog title).
  3. Bottom section: student-rate row buttons.
- **Expected:** Short buttons ("إزالة", like "حذف السعر الافتراضي"), the name only in an aria-label; titles read "… لـ QA6 Teacher C" in the right order.
- **Actual:** Red button renders "QA6 Teacher BJ إزالة الراتب الثابت" (221 px wide); dialog title "QA6 Teacher Cلـ تعيين راتب ثابت"; student-rate buttons "(Omar Al-Sharif) حذف أجر عمر الشريف". Same class as ETQAN-QA-100 (glued "لـ"), different strings.
- **Evidence:** `qa/manual/screens/M09/M09-F-005-remove-salary-button-name.png`, `qa/manual/screens/M09/triage/T-F005-remove-salary-button.png`, `qa/manual/screens/M09/triage/T-F007-month-field.png`
- **Root cause (Agent 2 pointer):** Reword the Arabic keys (no lone "لـ" before an isolated Latin name) as in the QA-100 fix.
- **Root cause:** Arabic keys put a lone "لـ" before `{{name}}` (`fixed.setFor/editFor/remove`, `rates.addFor/editFor/editTitle`, `adjustments.editFor`), so in RTL the lam-tatweel sat beside the Latin name (read as "J"); and the row buttons used the full-name sentence as visible text (`FixedSalary` remove via `Confirm action`, `StudentRates` delete, `StudentRateDialog` edit trigger).
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** Arabic reworded to "… للمعلم {{name}}"; dialog titles pass the name through `bidiName` (FSI…PDI isolate, the QA-100 helper). Row buttons are now short ("إزالة"/"حذف"/"تعديل") with the full sentence as the accessible name (`Confirm actionName` / `aria-label`). New keys `fixed.removeShort`, `studentRates.deleteShort` (en/ar/es).
- **Regression test:** `FixedSalary.test.tsx` "shows a short Remove button named in full" + "reads the dialog in Arabic" (title isolated, no لـ); `RatesPage.test.tsx` "reads in Arabic, its dialog too" (title isolated). Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). AR rates: row button 'إزالة' (46px) with aria-label 'إزالة الراتب الثابت للمعلم F10 Teacher Eight'; dialog title 'تعيين راتب ثابت للمعلم ⁨QA6 Teacher C⁩'; student-rate buttons 'حذف' named 'حذف أجر …'. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-353-after.png` (before | after), raw shots `fix/ETQAN-QA-353-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-354: Fixed salary "من شهر" is a native month input: "--------- ----" with no hint, English month names when filled, and no support in Firefox/Safari desktop
- **Feature:** M09 Payroll rates, fixed salary dialog (`FixedSalary.tsx` `<input type=month>`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-007); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/rates` → QA6 Teacher C → "تعيين راتب ثابت".
  2. `eval` the dialog inputs' types.
- **Expected:** An Arabic month picker like the payslips page (month + year selects).
- **Actual:** Inputs `text`, `month`; the month field shows "--------- ----"; Agent 1 saw "October 2026" in English when editing. `type=month` falls back to a free-text box on Firefox and desktop Safari.
- **Evidence:** `qa/manual/screens/M09/M09-F-007-month-field-dashes.png`, `qa/manual/screens/M09/triage/T-F007-month-field.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-355: "إصدار" is offered on a draft that can't be issued (missing rate, month not over, negative net); the refusal comes only after confirming an "irreversible" action
- **Feature:** M09 Payslip detail (`PayslipPage.tsx` issue action; `payslips.issue` 409s). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-008); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/payslips/46` (PAY-000043, Oct 2026, "سعر ناقص"): the page already says "إحدى الحصص بلا سعر، فلا يمكن إصدار كشف الراتب هذا…".
  2. Click "إصدار" → dialog "…لا يمكن التراجع عن ذلك" → "إصدار كشف الراتب هذا".
  3. Open `/app/payroll/payslips/45` (PAY-000042, net −1,000).
- **Expected:** Issue disabled or hidden with the reason (missing rate / month not over / net below zero) before any confirmation.
- **Actual:** 409 POST /api/v1/payroll/payslips/46/issue/ → toast "لم ينتهِ هذا الشهر بعد…". PAY-000042 shows an active red "إصدار" and no warning that a negative net can't be issued (payroll.md: issue refuses `month_not_over`, `missing_rate`, `negative_net`).
- **Evidence:** `qa/manual/screens/M09/M09-F-008a-issue-offered-though-blocked.png`, `qa/manual/screens/M09/M09-F-008b-issue-refused-month-not-over.png`, `qa/manual/screens/M09/triage/T-F008a-issue-confirm.png`, `qa/manual/screens/M09/triage/T-F008b-issue-409.png`, `qa/manual/screens/M09/triage/T-F014-negative-net.png`
- **Root cause (Agent 2 pointer):** The payload already has `missing_rate`, `net_minor`, year/month: derive `canIssue` client-side.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-356: Generate summary (AR): plural agreement for one teacher ("لم يعودوا يتقاضون بها", "كشف راتبهم") and "لـ" glued to the Latin name
- **Feature:** M09 Payslips list generate summary (`payroll.json` ar `list.*` keys). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-009); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/payslips` → September 2026 → "إنشاء".
  2. October 2026 → "إنشاء".
- **Expected:** Singular when one teacher ("لم يعد يتقاضى بها", "كشف راتبه"), or neutral wording; name order correct.
- **Actual:** Sep: "اكتملت حصص لـ QA teacher بعد إصدار كشف راتبهم." Oct: "الراتب الثابت لـF10 Teacher Eleven بعملة لم يعودوا يتقاضون بها…" rendered "F10 Teacher Elevenلـ".
- **Evidence:** `qa/manual/screens/M09/M09-F-009-plural-grammar.png`, `qa/manual/screens/M09/triage/T-F009-F010-generate-sep.png`, `qa/manual/screens/M09/triage/T-F013-oct-generate.png`
- **Root cause:** `PayslipsList.tsx` `GenerateSummary` joined names with plain `Intl.ListFormat` (no isolation) and passed no count, so the Arabic keys `list.unpaidSessions/staleFixedSalary/otherCurrency` had one plural wording ("راتبهم", "لم يعودوا") and a glued "لـ{{names}}".
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** names go through `listOf` (each isolated, joined in the UI language) and `count` is passed; Arabic keys split into `_one/_two/_few/_many/_other/_zero` (singular "للمعلم … كشف راتبه", dual, plural) with "للمعلم/للمعلمين" instead of "لـ". en/es unchanged wording (they read for one or several).
- **Regression test:** `PayslipsList.test.tsx` "words the generate summary for one teacher or two in Arabic" (singular, dual, no لـ); EN expectations updated for the isolates. Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). AR generate Sep: 'اكتملت حصص للمعلم ⁨QA teacher⁩ بعد إصدار كشف راتبه'; Oct: 'الراتب الثابت للمعلم ⁨F10 Teacher Eleven⁩ بعملة لم يعد يتقاضى بها، فلم يُحتسب' — singular agreement, names isolated. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-356-after.png` (before | after), raw shots `fix/ETQAN-QA-356-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-357: "Sessions completed after the payslip was issued" warning names only the teacher: no dates, count or amount to build the adjustment
- **Feature:** M09 Payslips generate (`payslips.generate` `unpaid_sessions` = people only; `PayslipsList.tsx`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-010); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/payslips` → September 2026 → "إنشاء".
- **Expected:** The late sessions listed (date, student, minutes, amount) or at least count and amount, ideally a prefilled adjustment.
- **Actual:** Only "اكتملت حصص لـ QA teacher بعد إصدار كشف راتبهم. أضف تسوية في شهر لاحق لدفع أجرها. إضافة تسويات"; the link opens an empty adjustment form. The API returns only `person(user)` per teacher (`payroll/api/payloads.py:159`).
- **Evidence:** `qa/manual/screens/M09/M09-F-010-unpaid-sessions-warning-vague.png`, `qa/manual/screens/M09/triage/T-F009-F010-generate-sep.png`
- **Root cause (Agent 2 pointer):** Needs the session ids in the generate result → API change → proposal.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-358: Raw English server messages in Arabic payroll pay dialogs: mark paid, pay to balance, pay withdrawal
- **Feature:** M09 `MarkPaidDialog.tsx`, `WithdrawalActions.tsx` pay; server `payroll/services/payslips.py:332-335`, `withdrawals.py:146-149`. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-011); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR issued payslip `/app/payroll/payslips/3` → "تسجيل الدفع" → date 15/08/2026 → submit.
  2. Same → "الدفع إلى الرصيد" → 29/10/2026 → submit.
  3. `/app/payroll/withdrawals` → an approved request → "دفع" → 26/10/2026 (request made 27/10).
- **Expected:** Arabic field errors, ideally checked before sending (the month start, today, the request date are known client-side).
- **Actual:** ".A payslip can't be paid before the month it pays", ".A payslip can't be paid in the future", ".A request can't be paid before it was made" (full stop flipped). 400s on `payslips/3/mark-paid/`, `payslips/3/pay-to-balance/`, `withdrawals/19/pay/`. Same class as ETQAN-QA-206/157, new sites.
- **Evidence:** `qa/manual/screens/M09/M09-F-011-mark-paid-english-error.png`, `qa/manual/screens/M09/M09-F-011b-pay-balance-future-english.png`, `qa/manual/screens/M09/M09-F-011c-withdrawal-pay-english.png`, `qa/manual/screens/M09/triage/T-F011a-mark-paid-english.png`, `qa/manual/screens/M09/triage/T-F011b-pay-balance-english.png`, `qa/manual/screens/M09/triage/T-F011c-withdrawal-pay-english.png`
- **Root cause (Agent 2 pointer):** Pre-validate dates in the dialogs (as the QA-206 fix); codes are the existing proposal.
- **Root cause:** The server's `ValidationError`s on `paid_on` are fixed English prose with no code (`payroll/services/payslips.py` `_pay`, `withdrawals.py` `pay_withdrawal`); `MarkPaidDialog` and `PayWithdrawalDialog` sent any date and showed the reply verbatim.
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** both dialogs check the two rules before sending and show Arabic/English field errors (`payroll.errors.paidFuture`, `paidBeforeMonth`, `paidBeforeRequest`; en/ar/es); `MarkPaidDialog` input also gets `min` = first day of the payslip's month. The four fixed server sentences are mapped in `lib/server-messages.ts` (the QA-157 table) so a reply the client check missed still reads translated. No backend change; a code on these errors stays the existing coverage-gaps proposal.
- **Regression test:** `PayslipPage.test.tsx` "refuses a day before the payslip's month, or after today, in Arabic" (no request sent) and "shows the server's refusal of a future date on the field" (server sentence → translated); `WithdrawalsPage.test.tsx` "checks the payment day against the request day and today". Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). AR PAY-000003 mark paid 15/08/2026 → 'اختر يومًا في الشهر الذي يدفعه كشف الراتب أو بعده.'; pay-to-balance 05/11/2026 → 'لا يمكن أن يكون تاريخ الدفع بعد اليوم.'; withdrawal pay 27/10 for a 28/10 request → 'لا يمكن أن يكون تاريخ الدفع قبل يوم تقديم الطلب.' No request sent; server sentences mapped in lib/server-messages.ts. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-358-after.png` (before | after), raw shots `fix/ETQAN-QA-358-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-359: Adjustments list doesn't flag adjustments in a currency the teacher is no longer paid in (they will never be paid)
- **Feature:** M09 Adjustments (`AdjustmentsList.tsx`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-012); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/adjustments` → row 10/09/2026 F10 Teacher Eleven, bonus 15.00 ج.م., "لم تُستخدم بعد" (teacher now paid in USD).
- **Expected:** An "old currency: not counted" badge like the rates page shows for a stale fixed salary.
- **Actual:** Shown as a normal pending bonus; only the generate summary says adjustments were excluded (payroll.md: "A row left in an old currency does not count").
- **Evidence:** `qa/manual/screens/M09/M09-F-012-adjustment-old-currency-not-flagged.png`, `qa/manual/screens/M09/triage/T-F012-adjustments.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-360: Arabic: negative amounts put the currency on the other side ("ج.م. ‎-4,000.00" under "3,000.00 ج.م.")
- **Feature:** M09 money formatting of negative values (`PayslipBody.tsx`, `ProjectionsPage.tsx`; `@/lib/money` format). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-014); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/payslips/45` (PAY-000042).
  2. AR `/app/payroll/projections`.
- **Expected:** Same order as positives with a minus ("‎-4,000.00 ج.م.").
- **Actual:** The deduction line and the net read "ج.م. -4,000.00" / "ج.م. -1,000.00" while every positive amount reads "3,000.00 ج.م."; same in the projection row.
- **Evidence:** `qa/manual/screens/M09/M09-F-014-negative-amount-currency-flips.png`, `qa/manual/screens/M09/triage/T-F014-negative-net.png`, `qa/manual/screens/M09/triage/T-F015-projection-total.png`
- **Root cause (Agent 2 pointer):** Text is "‏‎-1,000.00 ج.م.‏": the LRM before the minus flips the run; isolate the number or put the sign inside the formatted value.
- **Root cause:** `formatMoney` (`lib/money.ts`) returns Intl's Arabic negative "RLM LRM -1,000.00 ج.م. RLM"; the LRM makes "-1,000.00" its own LTR run, so inside the `dir=ltr` `Money` span the currency lands on the opposite side from positives (measured in Chromium: positive currency x<digits, negative currency x>digits).
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** for a negative whose Intl text has "LRM-", format the absolute value (same layout as a positive) and wrap the signed number as LRI "-1,000.00" PDI. Measured in Chromium: currency on the same side as positives, minus directly before the digits. Other languages keep Intl's output ("-$1,000.00").
- **Regression test:** `lib/money.test.ts` "keeps the currency where a positive has it for an Arabic negative". Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). AR PAY-000042: deduction and net render as 'ج.م. ⁦-1,000.00⁩' on the same side as positives; projections row -1,000.00 same side. EN unchanged ('-EGP 1,000.00'). Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-360-after.png` (before | after), raw shots `fix/ETQAN-QA-360-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-361: Salary projection total subtracts a teacher's negative net (−1,000) from the academy's payroll total
- **Feature:** M09 Projections (`services/projections.py` totals; `ProjectionsPage.tsx`). **Severity:** P3. **Type:** data. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-015); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. After PAY-000042 (net −1,000) exists, AR `/app/payroll/projections` (October 2026).
- **Expected:** A negative net (which can't be issued) shown as 0 to pay and flagged; the total = what the academy will pay.
- **Actual:** QA6 Teacher B −1,000.00 so far/projected; EGP totals 8,585.46 / 13,387.57 include it (5,000+67+3,000+60+60+123.46+1,275−1,000 = 8,585.46), so the total is 1,000 lower than the positive nets.
- **Evidence:** `qa/manual/screens/M09/M09-F-015-projection-negative-net-in-total.png`, `qa/manual/screens/M09/en-projections.png`, `qa/manual/screens/M09/triage/T-F015-projection-total.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-362: Withdrawals list (AR): the rejection reason is pushed to the far side of the Amount cell, away from the amount and note
- **Feature:** M09 Withdrawals list (`WithdrawalsPage.tsx` amount cell). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-016); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/withdrawals` → rejected rows 5.00 and 119.00.
- **Expected:** "السبب: …" aligned with the amount and the note.
- **Actual:** Note sits under the amount at the right; "السبب: M09 الرصيد محجوز لشهر قادم" / "السبب: race" sit at the left edge of the cell, next to the teacher column.
- **Evidence:** `qa/manual/screens/M09/M09-F-016-reject-reason-misaligned.png`, `qa/manual/screens/M09/triage/T-F016-F020-F021-withdrawals.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-363: Withdrawals: "موافقة" (approve) is red like a destructive action and looks identical to "إلغاء الطلب"; "رفض الطلب" is the green primary
- **Feature:** M09 Withdrawals (`WithdrawalActions.tsx` button variants). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-020); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. Teacher creates a request; AR `/app/payroll/withdrawals` → row actions.
  2. "رفض" → dialog.
- **Expected:** Approve/pay = primary (green); reject/cancel = destructive (red).
- **Actual:** Row shows red "موافقة", outline "رفض", red "إلغاء الطلب"; approve dialog confirm is red; reject dialog confirm "رفض الطلب" is green. (Teacher's red "Confirm receipt" is ETQAN-QA-421.)
- **Evidence:** `qa/manual/screens/M09/M09-F-020-approve-red.png`, `qa/manual/screens/M09/M09-F-020b-reject-green.png`, `qa/manual/screens/M09/triage/T-F020-approve-red.png`, `qa/manual/screens/M09/triage/T-F020b-reject-green.png`
- **Root cause:** `Confirm` always rendered a destructive trigger and confirm button, so "موافقة" (approve) used it as-is; `RejectDialog`'s submit used the default primary variant.
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** `Confirm` gains an additive `confirmVariant` prop and `triggerVariant` accepts "primary" (defaults unchanged for every other caller); approve uses primary for both; the reject submit is `variant="destructive"`. Cancel request stays destructive.
- **Regression test:** `WithdrawalsPage.test.tsx` "colours approve as primary and reject as destructive". Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). AR withdrawals row: موافقة green rgb(14,124,102), رفض outline, إلغاء الطلب red; approve confirm green; reject submit 'رفض الطلب' red rgb(172,87,78). EN 'Pay' green. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-363-after.png` (before | after), raw shots `fix/ETQAN-QA-363-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-364: Paid withdrawals never show the payment date (office list and teacher list)
- **Feature:** M09 Withdrawals (`WithdrawalsPage.tsx`, `MyBalance.tsx`; payload has `paid_on`). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-021); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/withdrawals` → the 20.00 "مدفوع" row; teacher `/app/teaching/balance`.
- **Expected:** "دُفع في 27/10/2026" (the date the office entered).
- **Actual:** Only "تاريخ الطلب" and the "مدفوع" chip; `paid_on` is in the API payload but shown nowhere.
- **Evidence:** `qa/manual/screens/M09/M09-F-021-withdrawal-paid-date-missing.png`, `qa/manual/screens/M09/triage/T-F016-F020-F021-withdrawals.png`, `qa/manual/screens/M09/triage/T-F017-balance-no-history.png`
- **Root cause:** `paid_on` is in the withdrawal payload but `WithdrawalStatusChip` (shared by `WithdrawalsPage` and `MyBalance`) showed only the status.
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** `WithdrawalStatusChip` takes `paidOn` and, for a paid request, adds "دُفع في {{day}}" / "Paid on {{day}}" under the chip (`formatDay`); both lists pass `row.paid_on`. New key `withdrawals.paidOn` (en/ar/es).
- **Regression test:** `WithdrawalsPage.test.tsx` "shows the day a paid request was paid" (same component renders the teacher's `MyBalance` list). Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). Office AR 'دُفع في 2026/10/27' / EN 'Paid on Oct 27, 2026' under the Paid chip; teacher /teaching/balance shows 'دُفع في 2026/10/27'. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-364-after.png` (before | after), raw shots `fix/ETQAN-QA-364-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-365: Opening a payslip that is out of scope or unknown spins forever (404/403 retried) instead of saying "not found"
- **Feature:** M09 Payslip detail and print (`PayslipPage.tsx`, `PayslipPrint.tsx`, teacher `/teaching/payslips/$id`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-022); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. Teacher qa-teacher, AR `/app/teaching/payslips/43` (another teacher's), wait 6 s.
  2. Also `/app/payslips/43/print`; student → print (403).
- **Expected:** At once "كشف الراتب غير موجود" with a link back; no retries on 4xx.
- **Actual:** Title "كشف راتب" + endless spinner; 3× 404 GET /api/v1/payroll/payslips/43/. No data leaks. Same class as ETQAN-QA-106 (student/invoice pages), new pages.
- **Evidence:** `qa/manual/screens/M09/M09-F-022-payslip-not-found-spinner.png`, `qa/manual/screens/M09/M09-F-022b-print-not-found-spinner.png`, `qa/manual/screens/M09/M09-F-022c-admin-unknown-payslip-spinner.png`, `qa/manual/screens/M09/triage/T-F022-not-found-spinner.png`
- **Root cause (Agent 2 pointer):** Error state on the payslip queries; share the QA-106 no-retry-on-4xx fix.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-366: English projection column "Paid so far" for money nothing has paid yet (Arabic says "المستحق حتى الآن")
- **Feature:** M09 Projections (`locales/en/payroll.json` `paidSoFar`, also the intro sentence). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-023); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. EN `/app/payroll/projections`.
- **Expected:** "Earned so far" / "Due so far", matching the Arabic.
- **Actual:** Column "Paid so far" and "the projection can be below the pay so far" — reads as if October salaries were already paid.
- **Evidence:** `qa/manual/screens/M09/en-projections.png`, `qa/manual/screens/M09/triage/T-F023-en-paid-so-far.png`
- **Root cause:** `locales/en/payroll.json` `projections.columns.paidSoFar` = "Paid so far" and the explanation "below the pay so far": the value is what the month has earned so far, nothing is paid (Arabic already "المستحق حتى الآن").
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** EN reads "Earned so far" and "below what is earned so far" (es has no projections file and falls back to en).
- **Regression test:** `ProjectionsPage.test.tsx` "names the server's month, explains itself…" asserts the "Earned so far" header and no "Paid so far". Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). EN /payroll/projections: column 'Earned so far', note '…can be below what is earned so far'. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-366-after.png` (before | after), raw shots `fix/ETQAN-QA-366-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-367: Office "New request" for a teacher with no balance: label "Amount ()", currency "No balance yet." as a value, form still enabled
- **Feature:** M09 Withdrawals office dialog (`WithdrawalDialog.tsx`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-024); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. EN `/app/payroll/withdrawals` → "New request" → Teacher "QA6 Teacher B" (paid directly, no balance).
- **Expected:** "This teacher has no balance" message and Send disabled; no empty "()".
- **Actual:** Currency select shows "No balance yet.", label "Amount ()", amount/notes/"Send request" active. Same "()" pattern as ETQAN-QA-215 (subscriptions), different dialog.
- **Evidence:** `qa/manual/screens/M09/M09-F-024-amount-empty-parens.png`, `qa/manual/screens/M09/triage/T-F024-amount-empty-parens.png`
- **Root cause:** `WithdrawalDialog.tsx` always rendered the form: with no balances the currency select showed "No balance yet." as an option, the label interpolated an empty currency ("Amount ()"), and Send stayed enabled.
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** once the chosen teacher's (or the teacher's own) balances have loaded empty, the dialog shows "This teacher has no balance to withdraw from." / "You have no balance to withdraw from yet." instead of the fields, and Send is disabled; the amount label is plain "Amount" until a currency is chosen. New keys `withdrawals.{amountPlain,noBalance,noBalanceOwn}` (en/ar/es).
- **Regression test:** `WithdrawalsPage.test.tsx` "says a teacher has no balance and offers no request". Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). EN New request → QA6 Teacher B: 'This teacher has no balance to withdraw from.', Send request disabled, no 'Amount ()'. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-367-after.png` (before | after), raw shots `fix/ETQAN-QA-367-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-368: Salary expense title calls the payslip a "receipt" ("إيصال PAY-000044")
- **Feature:** M09 Finance side (`payroll/services/salary_expenses.py` TITLES). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-025); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/billing/expenses` → rows of type رواتب.
- **Expected:** "راتب المعلم – <name> – كشف راتب PAY-…" / "Teacher salary – <name> – payslip PAY-…", the word the payroll screens use.
- **Actual:** "راتب المعلم – QA teacher – إيصال PAY-000039" etc. (legacy Kaleem word; payroll everywhere says "كشف راتب"). Not a bug: the title is stored in the academy's default language (D11/D22), so it stays Arabic in the EN UI; a link to the payslip is an enhancement.
- **Evidence:** `qa/manual/screens/M09/M09-F-025a-expense-title-receipt.png`, `qa/manual/screens/M09/M09-F-025b-expense-title-arabic-in-en.png`, `qa/manual/screens/M09/triage/T-F025-expense-title.png`
- **Root cause (Agent 2 pointer):** Affects new expenses only; existing titles stay.
- **Root cause:** `backend/etqan/payroll/services/salary_expenses.py` `TITLES` used the legacy Kaleem word "receipt"/"إيصال" (also quoted in the B4/B4c specs), while every payroll screen calls it "payslip"/"كشف راتب". `docs/features/payroll.md` doesn't fix the wording.
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** titles are "Teacher salary – {name} – payslip {number}" / "راتب المعلم – {name} – كشف راتب {number}". New expenses only; already-posted expenses keep their stored title. Spec text (`docs/superpowers/specs/2026-10-08-b4c-balance-payouts-design.md` line 70, `…b4-payroll-depth-design.md` line 109) still says "receipt": owner to confirm the wording and update the spec.
- **Regression test:** `etqan/payroll/tests/test_pay_to_balance.py` title tests updated (ar, en, es fallback, long-name cut); payroll pytest 439 passed, ruff clean, lint-imports 54 kept. Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). Marked PAY-000003 (F10 Teacher Three, Sep, test teacher) paid 2026-10-28: expense 'راتب المعلم – F10 Teacher Three – كشف راتب PAY-000003', 120.00 ج.م. = payslip net. Older expenses keep 'إيصال' (documented). Spec-wording proposal ACCEPTED as PROPOSAL for the owner. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-368-after.png` (before | after), raw shots `fix/ETQAN-QA-368-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-369: Phone (375): office payslips and withdrawals tables hide net, status and the action buttons behind a hidden sideways scroll
- **Feature:** M09 Payslips list / Withdrawals list at 375x812. **Severity:** P3. **Type:** mobile. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-027); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR 375x812 `/app/payroll/payslips`; `eval` table scrollWidth vs container.
  2. AR 375x812 `/app/payroll/withdrawals`.
- **Expected:** Net, status and approve/reject/pay visible (card layout) or a visible scroll hint.
- **Actual:** Payslips: table 892 px in a 341 px box — only الرقم (wrapped "PAY-"/"000014"), المعلم, الحصص visible. Withdrawals: 490/341 — actions column off-screen. Same layout class as ETQAN-QA-118/173, other tables.
- **Evidence:** `qa/manual/screens/M09/M09-F-027a-mobile-payslips-net-hidden.png`, `qa/manual/screens/M09/M09-F-027b-mobile-withdrawals-actions-hidden.png`, `qa/manual/screens/M09/triage/T-F027a-mobile-payslips.png`, `qa/manual/screens/M09/triage/T-F027b-mobile-withdrawals.png`
- **Root cause (Agent 2 pointer):** Card view on narrow screens → proposal, as QA-118.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-370: "تعيين لعدة معلمين" dialog shows the per-student-rates sentence as its description; mixes "الأجور" and "الأسعار"
- **Feature:** M09 Rates bulk dialog (`BulkRatesDialog.tsx` / `payroll.json` ar). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-028); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/rates` → "تعيين لعدة معلمين".
- **Expected:** A description of bulk assignment ("يُطبَّق السعر نفسه على المعلمين المختارين…"), one term ("الأسعار") as on the page.
- **Actual:** Title "تعيين الأجور لعدة معلمين", description "أجر الطالب يحل محل أجر المادة والأجر الافتراضي للمعلم مع هذا الطالب." (the student-rate text).
- **Evidence:** `qa/manual/screens/M09/M09-F-028-bulk-dialog-copy.png`, `qa/manual/screens/M09/triage/T-F028-bulk-dialog-copy.png`
- **Root cause:** `BulkRatesDialog.tsx` reused `payroll.studentRates.hint` (the per-student sentence) as its description; the Arabic `bulk.*` keys said "الأجور" while the rates page says "الأسعار".
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** new `payroll.bulk.body` (en/ar/es) describing bulk assignment; Arabic `bulk.title/addRow/defaultRate/rate/done` use "الأسعار/السعر".
- **Regression test:** `BulkRatesDialog.test.tsx` "offers only teachers of the chosen currency…" asserts the bulk description and no per-student sentence. Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). AR bulk dialog: title 'تعيين الأسعار لعدة معلمين', own description 'تُطبَّق الأسعار نفسها على كل معلم تختاره…'. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-370-after.png` (before | after), raw shots `fix/ETQAN-QA-370-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-371: "إضافة أجر لطالب": student dropdown lists only the first 100 of 149 students, no search
- **Feature:** M09 Rates per-student (`StudentRateDialog.tsx` `usePeople("students")` first page). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-029); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/rates` → bottom "إضافة أجر لطالب".
  2. `eval` options of the dialog's selects and `fetch('/api/v1/people/students/?page_size=1')` count.
- **Expected:** Every active student reachable (search / async select).
- **Actual:** Student select 101 options (100 + empty), academy count 149; no search input. Same class as ETQAN-QA-202 (subscription form), different component.
- **Evidence:** `qa/manual/screens/M09/triage/T-F029-student-rate-dropdown.png`, `qa/manual/screens/M09/s069.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-372: Payslips list: a filter with no match says "لا توجد كشوف رواتب لهذا الشهر."; month/status/teacher are not in the URL, so refresh/Back drop them
- **Feature:** M09 Payslips list (`PayslipsList.tsx` empty state and filter state). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-030); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/payslips` → September 2026 (12 payslips) → status "مسودة" → teacher "QA teacher".
  2. `eval` `location.search`.
- **Expected:** "لا توجد نتائج مطابقة" with a way to clear filters; filters kept in the URL (as fixed for people lists in ETQAN-QA-152).
- **Actual:** Empty card "لا توجد كشوف رواتب لهذا الشهر."; `location.search` empty. (The CSV link does carry the filters: `?status=draft&teacher=7&year=2026&month=9&format=csv`.)
- **Evidence:** `qa/manual/screens/M09/M09-F-030-filter-empty-says-no-payslips.png`, `qa/manual/screens/M09/triage/T-F030-filter-empty.png`
- **Root cause (Agent 2 pointer):** Empty-state text is easy; URL search params are the bigger part.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-373: "تعديل التسوية" dialog doesn't show which teacher the adjustment belongs to
- **Feature:** M09 Adjustments (`AdjustmentDialog.tsx` edit mode). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M09 (M09-F-032); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!`. M09 test data (Agent 1): QA6 Teacher B rate 75.50, fixed 3,000 from 09/2026, deduction 4,000 (15/10), PAY-000042 (id 45) Oct draft net −1,000; PAY-000043 (id 46) Maryam Oct draft with missing rate; PAY-000003 (id 3, F10 Teacher Three, Sep) issued by Agent 2 at triage.
- **Reproduction steps:**
  1. AR `/app/payroll/adjustments` → "تعديل" on the first row (QA6 Teacher B deduction 4,000).
- **Expected:** Teacher shown read-only in the title or form ("تعديل تسوية QA6 Teacher B").
- **Actual:** Title "تعديل التسوية", fields النوع/المبلغ/التاريخ/السبب only; the table behind is dimmed, so the office can't confirm the row.
- **Evidence:** `qa/manual/screens/M09/M09-F-032-edit-adjustment-no-teacher.png`, `qa/manual/screens/M09/triage/T-F032-edit-adjustment.png`
- **Root cause:** `AdjustmentDialog.tsx` edit mode hides the teacher select and its title was the generic `adjustments.editTitle`.
- **Fix (Agent 3, cycle 1, 2026-10-27, branch qa/manual-2026-10, uncommitted):** edit title is `adjustments.editTitleFor` ("تعديل تسوية المعلم {{name}}" / "Edit adjustment for {{name}}" / es), the name isolated with `bidiName`. Arabic `adjustments.editFor` (button label) also drops the glued "لـ".
- **Regression test:** `AdjustmentsList.test.tsx` "edits an unused one…" asserts the titled heading. Evidence: `qa/manual/evidence/M09/fix-1/` (vitest.txt, tsc.txt, backend.txt).
- **Verification status:** VERIFIED (2026-10-28, Agent 2 gate-1). AR edit adjustment: title 'تعديل تسوية المعلم ⁨QA6 Teacher B⁩'. Evidence: `qa/manual/screens/M09/fix/ETQAN-QA-373-after.png` (before | after), raw shots `fix/ETQAN-QA-373-after*-new.png`; tests `qa/manual/evidence/M09/gate-1/`.

## ETQAN-QA-374: Approve, pay and cancel-request dialogs for a withdrawal don't say which request (teacher, amount) they act on
- **Feature:** M09 Withdrawals (`WithdrawalActions.tsx` approve/pay, `CancelWithdrawal.tsx` office + teacher "My balance"). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL
- **Found by:** Agent 1, M09 confirmation sweep (M09-F-035); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** academy `qa`; admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@qa.etqan.test / `QA-People-2026!` with available balance.
- **Reproduction steps:**
  1. Teacher AR `/app/teaching/balance` → "طلب سحب" 1.00, note "M09-G2 فرز" → "إلغاء الطلب" on that card.
  2. Admin AR `/app/payroll/withdrawals` → row "M09-G2 فرز" → "موافقة"; confirm; then "دفع".
- **Expected:** Each confirmation names the request, e.g. "دفع ‎1.00 ج.م.‎ إلى QA teacher" / "إلغاء طلب سحب ‎1.00 ج.م.‎؟" (same idea as the fixed ETQAN-QA-373 for adjustments), since the row behind is dimmed and these actions move money.
- **Actual:** Teacher cancel: "إلغاء هذا الطلب / يعود المبلغ إلى الرصيد المتاح." — no amount (with two pending requests the teacher can't confirm the row). Office approve: "الموافقة على هذا الطلب / يبقى المبلغ محجوزًا…"; office pay: "دفع هذا الطلب / سجّل تاريخ الدفع للمعلم. يُخصم المبلغ من الرصيد." + date only — no teacher, no amount.
- **Evidence:** `qa/manual/screens/M09/M09-F-035-pay-dialog-no-amount.png`, `qa/manual/screens/M09/M09-F-035b-cancel-dialog-which-request.png`, `qa/manual/screens/M09/triage/T-F035-pay-dialog.png`, `qa/manual/screens/M09/triage/T-F035b-cancel-dialog.png`
- **Root cause (Agent 2 pointer):** fixed i18n keys `payroll.withdrawals.payTitle/payBody`, `cancelTitle`, approve title, with no interpolation; pass `withdrawal.amount_minor/currency` (+ teacher name for the office, isolated with `bidiName`) into the titles.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-375: Teacher "رصيدي" (AR): in a request card with a long note, the amount is not lined up with the date and note
- **Feature:** M09/M14 teacher My balance (`MyBalance.tsx` request card). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no (P4). **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c + uncommitted QA fixes, dashboard 626d0e7 on branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL
- **Found by:** Agent 1, M09 confirmation sweep (M09-F-036); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher qa-teacher@qa.etqan.test / `QA-People-2026!`; requests with a note wider than the amount (e.g. "M14-G إعادة اختبار", "M14- سحب تجريبي للتحويل البنكي", rejected rows with a reason).
- **Reproduction steps:**
  1. Teacher AR `/app/teaching/balance` → "طلباتي".
- **Expected:** amount, date and note all start at the card's right edge.
- **Actual:** the amount "1.50 ج.م." starts ~25 px left of the date's right edge on such cards (7.50, 5.00, 119.00, 120.00 cards too), so the amounts in the list don't line up. Office list sibling: ETQAN-QA-362.
- **Evidence:** `qa/manual/screens/M09/M09-F-036-balance-amount-misaligned.png`, `qa/manual/screens/M09/triage/T-F036-card.png`, `qa/manual/screens/M09/triage/T-F036-balance.png`
- **Root cause (Agent 2 pointer):** the three spans share one column as wide as the widest child; the amount span is `dir="ltr"` (Money), so its text is left-aligned inside that width while the date/note align right. Give the amount `text-align: end`/`self-end` or wrap it in an inline element.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## --- M07 manual bugs ---

Common fields for every M07 bug below unless stated: **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL. **Preconditions:** admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; people `@qa.etqan.test` / `QA-People-2026!`. **Found by:** Agent 1, manual M07; reproduced by Agent 2 on 2026-10-27.

## ETQAN-QA-250: Session page shows the label "الرابط" / "Link" with nothing under it when a session has no meeting link
- **Feature:** M07 session detail, teacher "حصصي" Link column. **Severity:** P3. **Type:** copy (missing empty state). **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-001.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions/362` (27/10 17:00, generated after it had ended). 2. Teacher Maryam `/app/teaching/sessions` tab "اليوم".
- **Expected:** "لا يوجد رابط بعد" / "No link yet" (and, for the office, a hint that links are made automatically up to 24 h ahead).
- **Actual:** the label "الرابط" with a blank value; the teacher's Link column is empty with no dash.
- **Evidence:** `qa/manual/screens/M07/M07-F-001-no-meeting-link.png`, `qa/manual/screens/M07/M07-F-001b-teacher-link-empty.png`, `qa/manual/screens/M07/triage/t001-link-blank-362.png`
- **Notes:** Provisioning itself works: DB shows Jitsi links on every scheduled session from 28/10 (52, 232, 457, 422 …) and the teacher's "This week" rows show "Join" (`triage/t007b-teacher-week-im-in-future.png`). Today's sessions had none because they were generated at 21:22 after they ended, and `provision_meetings` only fills sessions that have not ended (meetings.md step 4) — by design. Only the empty state is the bug.
- **Root cause:** `JoinLink` (`dashboard/src/features/scheduling/bits.tsx`) returned `null` when `meeting_url` was empty, so the session page's "Link" fact and the teacher table's cell rendered blank.
- **Fix:** `JoinLink` takes `showEmpty`; with it, a non-cancelled session without a link shows "لا يوجد رابط بعد" / "No link yet". Used on the session page and the teacher's "حصصي" table. The office (`session.update`) also sees "تُنشأ الروابط تلقائيًا قبل موعد البدء بمدة تصل إلى 24 ساعة." while the session is scheduled and hasn't started (no hint on ended sessions, which provisioning never fills). New keys `scheduling.session.noLink/noLinkHint` (ar/en/es).
- **Regression test:** `SessionPage.test.tsx` "says when there is no link yet (ETQAN-QA-250)".
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-250-after.png`; shots `qa/manual/screens/M07/fix/` g250a-362.png, g250b-412.png, g255b-maryam-week.png, g-mobile-412.png. Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-251: No confirmation message after marking attendance, cancelling, placing at disposal or restoring a session
- **Feature:** M07 session detail, teacher "حصصي", simplified view. **Severity:** P3. **Type:** UI (missing message). **Easy P3:** yes. **Priority:** medium
- **Found by:** M07-F-002.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions/362` → "حضور المعلم" = "حاضر". 2. Wait 700 ms.
- **Expected:** a toast "تم تسجيل الحضور." like the ones after "حفظ التقرير" ("حُفظ التقرير."), postpone and "دخلت" ("تم التسجيل.").
- **Actual:** no toast (`[data-sonner-toast]` count 0), only the dropdown value changes; same on the teacher list and after cancel / disposal / restore (Agent 1, sessions 465/466).
- **Evidence:** `qa/manual/screens/M07/M07-F-002-no-confirmation-attendance.png`, `qa/manual/screens/M07/M07-F-002b-cancel-no-toast.png`, `qa/manual/screens/M07/triage/t002-mark-no-toast.png`
- **Root cause:** the attendance select (`AttendanceControls.tsx`), Cancel / Restore / Disposal on `SessionPage.tsx` and the simplified view's marks only had `onError` toasts; success was silent.
- **Fix:** success toasts "تم تسجيل الحضور." / "أُلغي تسجيل الحضور." (AttendanceControls, so session page and teacher list), "أُلغيت الحصة.", "استُرجعت الحصة.", "وُضعت الحصة تحت تصرف الإدارة." (session page), and "تم تسجيل الحضور." on the simplified view (with ETQAN-QA-270). Keys `scheduling.attendance.saved/cleared`, `scheduling.session.cancelled/restored/placedAtDisposal` (ar/en/es).
- **Regression test:** `AttendanceControls.test.tsx` "confirms a saved mark (ETQAN-QA-251)"; `SessionPage.test.tsx` cancel / restore / disposal tests now expect the toast.
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-251-after.png`; shots `qa/manual/screens/M07/fix/` g251-mark-toast.png, g251c-cancel-toast.png, g251d-restore-toast.png, g270c-simple-toast.png. Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-252: Undoing attendance (back to "لم يُحدَّد") happens on one dropdown change with no confirmation, and is logged as "تسجيل الحضور"
- **Feature:** M07 session detail attendance. **Severity:** P3. **Type:** functional (missing confirmation). **Easy P3:** yes. **Priority:** medium
- **Found by:** M07-F-003.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions/362`, set teacher attendance "حاضر", then set it back to "لم يُحدَّد". 2. Scroll to "النشاط".
- **Expected:** "هل تريد إلغاء تسجيل الحضور؟" before an undo (for a student mark it gives a lesson back to the subscription and reopens the session); an activity title that says it was an undo.
- **Actual:** applied immediately, no dialog, no toast; the activity entry is titled "تسجيل الحضور" exactly like the mark (only the before/after table shows the difference). Agent 1 saw the same on 409 (completed → scheduled, remaining 7 → 8).
- **Evidence:** `qa/manual/screens/M07/M07-F-003-undo-one-click.png`, `qa/manual/screens/M07/triage/t003-undo-one-click-activity.png`
- **Notes:** Same one-click pattern as ETQAN-QA-160 / 205 / 217 (other screens).
- **Root cause:** `AttendanceControls.save()` sent any picked value straight to `markAttendance`, "not_set" included; the activity title came from `entry.action` only (`attendance` for both mark and undo).
- **Fix:** picking "لم يُحدَّد" over a set mark opens an AlertDialog "إلغاء تسجيل الحضور؟" (student body says the lesson goes back to the subscription and the session reopens; teacher body plain) with "إبقاء"/"إلغاء تسجيل الحضور"; nothing is sent until confirmed. New `entryTitle()` in `activityFormat.ts` titles an attendance entry whose marks all go to `not_set` "إلغاء تسجيل الحضور" (used by `SessionActivity` and `RevertDialog`). Frontend only; no API change.
- **Regression test:** `AttendanceControls.test.tsx` "asks before setting a mark back to Not set (ETQAN-QA-252)"; `SessionActivity.test.tsx` "titles an undo of attendance as such (ETQAN-QA-252)".
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-252-after.png`; shots `qa/manual/screens/M07/fix/` g252a-undo-dialog.png, g252b-undo-toast.png, g252c-student-undo-dialog.png, g253-activity-full.png, g-mobile-362-undo-dialog.png. Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-253: Session activity log (AR): the "who · when" line is scrambled ("23:30 2026/10/QA Admin · 27")
- **Feature:** M07 session detail "النشاط". **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-004.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions/362` (or 409) → "النشاط".
- **Expected:** "QA Admin · 27/10/2026 23:30" read right to left in a sensible order.
- **Actual:** shows "23:30 2026/10/QA Admin · 27" (text content is "QA Admin · 27‏/10‏/2026 23:30"; the Latin name and the date are not isolated).
- **Evidence:** `qa/manual/screens/M07/M07-F-004-activity-meta-scrambled.png`, `qa/manual/screens/M07/triage/t003-undo-one-click-activity.png`
- **Notes:** Same family as ETQAN-QA-104 (bell) and ETQAN-QA-207 (trials); different component (`RevertDialog`/`activityFormat.ts` area).
- **Root cause:** `SessionActivity.tsx` interpolated the raw actor name and the date into "{{actor}} · {{when}}"; in an RTL line the Latin name's run absorbed the date's digits.
- **Fix:** actor through `bidiName()` and the date through `isolate()` (`src/lib/bidi.ts`, FSI…PDI), so each lays out on its own.
- **Regression test:** `SessionActivity.test.tsx` "isolates the actor and the date in an Arabic line (ETQAN-QA-253)" (+ existing meta assertions updated).
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-253-after.png`; shots `qa/manual/screens/M07/fix/` g253-activity-full.png (crop g253-activity-crop.png). Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-254: Session dialogs (postpone, report, add session, make-up, student postpone) have no Cancel / close button
- **Feature:** M07 dialogs. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-005.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions/362` → "تأجيل". 2. Admin EN `/app/scheduling/sessions` → "Add session". 3. Student Adam `/app/learning/sessions` → "تأجيل".
- **Expected:** a "إلغاء" button (and/or ✕), like the cancel-session, disposal and homework dialogs.
- **Actual:** only the submit button ("تأجيل", "Add session", "حفظ التقرير"); the only way out is Esc or clicking outside.
- **Evidence:** `qa/manual/screens/M07/M07-F-005-report-dialog-no-close.png`, `qa/manual/screens/M07/M07-F-005b-postpone-no-cancel.png`, `qa/manual/screens/M07/M07-F-005c-makeup-no-cancel.png`, `qa/manual/screens/M07/triage/t005-postpone-dialog-no-cancel.png`, `qa/manual/screens/M07/triage/t012-add-session-dialog.png`, `qa/manual/screens/M07/triage/t009-postpone-english-error.png`
- **Notes:** Related to ETQAN-QA-212 (trial dialog, M06) — likely the same dialog pattern; fix together.
- **Root cause:** the form footers of `AddSessionDialog.tsx` and `MakeUpDialog.tsx` held only the submit button (DialogClose only on the "done" screen). The postpone dialog (also the student's, via `PostponeAction`) and the report dialog were fixed in the same way by ETQAN-QA-401 (M14) — not touched again here.
- **Fix:** a `DialogClose` "إلغاء" (outline) before the submit in both dialogs.
- **Regression test:** `AddSessionDialog.test.tsx` "closes with Cancel without adding (ETQAN-QA-254)"; `SessionClasses.test.tsx` "closes the make-up dialog with Cancel (ETQAN-QA-254)".
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-254-after.png`; shots `qa/manual/screens/M07/fix/` g254a-add-dialog.png, g254c-add-cancelled.png, g254e-makeup-dialog.png, g254f-makeup-closed.png, g257b-postpone-ar-error.png (student postpone, M14 part). Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-255: Teacher's "حصصي": "I'm in" / "دخلت" is offered on future sessions where it always fails, and "أُغلق التأجيل عند …" stays on lessons that are over
- **Feature:** M07 teacher My sessions. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Found by:** M07-F-007.
- **Reproduction steps:** 1. qa-teacher@ EN `/app/teaching/sessions` → "This week". 2. Click "I'm in" on Oct 29 10:00.
- **Expected:** the button appears only from 15 minutes before the start (B2b B-2), like the attendance hint "Attendance opens at the start time." on the same row; no postponement note on past lessons.
- **Actual:** every future row has a green "I'm in"; clicking gives the red toast "Attendance opens when the session starts." (`409 POST /api/v1/sessions/4/times/`). Maryam AR "اليوم" shows "أُغلق التأجيل عند 13:00 / 16:00 / 18:00" on lessons already finished.
- **Evidence:** `qa/manual/screens/M07/M07-F-007-past-session-actions.png`, `qa/manual/screens/M07/M07-F-007b-im-in-future-error.png`, `qa/manual/screens/M07/triage/t007b-teacher-week-im-in-future.png`, `qa/manual/screens/M07/triage/t007c-im-in-future-refused.png`, `qa/manual/screens/M07/triage/t007-teacher-today-past-actions.png`
- **Root cause:** (a) "I'm in" on future rows: same root cause and fix as ETQAN-QA-400 (M14, `TimesPanel.tsx` `stampOpen`, already in the tree) — not changed again. (b) `postponeClosed()` (`dashboard/src/features/scheduling/postponing.ts`) only checked that the deadline had passed, so the "أُغلق التأجيل عند …" line stayed on lessons that were over.
- **Fix:** `postponeClosed()` is false once the session is no longer `scheduled` or its end (`starts_at + minutes`) has passed.
- **Regression test:** `postponing.test.ts` "postponeClosed on a finished lesson (ETQAN-QA-255)"; `TeacherSessions.test.tsx` deadline test now uses a lesson not yet over.
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-255-after.png`; shots `qa/manual/screens/M07/fix/` g255a-maryam-today.png, g255c-maryam-history.png, g255d-qateacher-today.png. Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

- **Final verification (conductor, 2026-10-28):** the full Vitest run caught `FamilySessions.test.tsx` › "says when the server's deadline has passed". Its fixture lesson (2026-06-01) is in the past, so the line is now rightly hidden. The test now pins `Date` between the deadline and the lesson start. 11 tests pass. No product change.
## ETQAN-QA-256: Today board calls a scheduled session "مولَّدة" (generated) while the Sessions list calls it "مجدولة"
- **Feature:** M07 Today page. **Severity:** P4. **Type:** copy. **Easy P3:** yes (one string). **Priority:** low
- **Found by:** M07-F-008.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/today`; compare with `/app/scheduling/sessions` (Today).
- **Expected:** user words: "مجدولة" (or "تم إنشاؤها") for a generated session; "مولَّدة" is internal jargon.
- **Actual:** green chip "مولَّدة" on every scheduled row (`locales/ar/scheduling.json` `today.state.generated`).
- **Evidence:** `qa/manual/screens/M07/M07-F-008-today-generated-vs-scheduled.png`, `qa/manual/screens/M07/triage/t008-today-generated-chip.png`
- **Notes:** The column is the generation state (generated/missing) by design; only the wording is the bug.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-257: Postpone dialog (AR) shows the raw English server error "Choose a time further ahead and within two weeks."
- **Feature:** M07 postpone (student/parent/teacher). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Found by:** M07-F-009.
- **Reproduction steps:** 1. Student Adam AR `/app/learning/sessions` → 2nd "تأجيل" (30/10 18:00) → day 25/11/2026, time 18:00 → "تأجيل".
- **Expected:** Arabic message, ideally the limits shown up front (at least 2 h ahead, at most 14 days after the old time).
- **Actual:** ".Choose a time further ahead and within two weeks" in English under the day field (`400 POST /api/v1/sessions/412/postpone/`).
- **Evidence:** `qa/manual/screens/M07/M07-F-009-postpone-english-error.png`, `qa/manual/screens/M07/triage/t009-postpone-english-error.png`
- **Notes:** Same class as ETQAN-QA-157/206 (verified with the `src/lib/server-messages.ts` map); this message is not in the map yet. Also check the sibling postpone messages (`too_late_to_postpone`, `teacher_busy`).
- **Root cause:** `postpone.py` raises plain-sentence `ValidationError`s on `occurs_on` with no code; `src/lib/server-messages.ts` didn't map them, so `useFieldError` showed the English text.
- **Fix:** mapped the four fixed postpone sentences ("Choose a time in the future.", "…term and outside its pauses.", "…further ahead and within two weeks.", "Choose a day and a time.") to `errors.server.postpone*` (ar/en/es). The coded refusals (`too_late_to_postpone`, `teacher_busy`, …) were already translated. Showing the limits up front would need the limit in the API: left out (backend codes on these errors stay the ETQAN-QA-157 proposal).
- **Regression test:** `PostponeDialog.errors.test.tsx` "shows the two-weeks refusal in Arabic".
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-257-after.png`; shots `qa/manual/screens/M07/fix/` g257b-postpone-ar-error.png. Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-258: Session activity log: "Before"/"After" columns sit at a different position in every entry
- **Feature:** M07 session detail "Activity". **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-010.
- **Reproduction steps:** 1. Admin EN `/app/scheduling/sessions/409` → Activity (full page).
- **Expected:** aligned columns (fixed table layout / column widths).
- **Actual:** each entry's table auto-sizes, so "Before"/"After" jump horizontally from entry to entry.
- **Evidence:** `qa/manual/screens/M07/M07-F-010-activity-columns-misaligned.png`, `qa/manual/screens/M07/triage/t011-session-409-en-full.png`, `qa/manual/screens/M07/triage/t003-undo-one-click-activity.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-259: Session page doesn't show which subscription it belongs to or how many lessons are left
- **Feature:** M07 session detail. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Found by:** M07-F-011.
- **Reproduction steps:** 1. Admin EN `/app/scheduling/sessions/409` (Adam, sub 91).
- **Expected:** a link to the subscription and its progress ("1 of 8", remaining), so the office can check the count after marking.
- **Actual:** no subscription, package or progress anywhere on the page (the session payload has `subscription`). Numbers themselves are right (sub 91: 7 left / 1 used after present; back after undo).
- **Evidence:** `qa/manual/screens/M07/M07-F-011-no-subscription-on-session.png`, `qa/manual/screens/M07/triage/t011-session-409-en-full.png`
- **Root cause / Fix / Regression tests:** _Agent 3_ (may need the API to return the subscription's counts: proposal if so)
- **Verification status:** OPEN

## ETQAN-QA-260: "Add a session": the Subscription list shows many identical "Student — Course" entries with nothing to tell them apart
- **Feature:** M07 Add session dialog. **Severity:** P3. **Type:** UI. **Easy P3:** no. **Priority:** medium
- **Found by:** M07-F-012.
- **Reproduction steps:** 1. Admin EN `/app/scheduling/sessions` → "Add session" → open "Subscription".
- **Expected:** each option carries its dates (and teacher/status), e.g. "QA student — Tajweed QA (01/10–31/10)".
- **Actual:** 50 options; "QA6 Student 4 — QA6 Quran" six times, "QA student — Tajweed QA" repeatedly. DB: QA student has 10 live `active` subscriptions (ids 3, 4, 7, 9, 10, 11, 12, 82, 83…) of the same course, some starting 19/11 (future renewals). Picking the wrong one puts the lesson on the wrong package.
- **Evidence:** `qa/manual/screens/M07/M07-F-012-identical-subscriptions.png`, `qa/manual/screens/M07/triage/t012-add-session-dialog.png`
- **Notes:** Related to ETQAN-QA-200 (future renewal looks like a second identical active subscription), different screen.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-261: Session kind wording differs: list tabs "Core / أساسية" vs session page and Add dialog "Regular / عادية"; "المقرر" vs "الدورة"
- **Feature:** M07 sessions list, detail, Add dialog. **Severity:** P4. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-013.
- **Reproduction steps:** 1. Admin EN `/app/scheduling/sessions` (tabs) → "Add session" (Kind) → any session page (card title).
- **Expected:** one word per kind and per field.
- **Actual:** tabs "Core", Kind select "Regular", card "Regular"/"عادية"; AR column "المقرر" next to the filter "كل الدورات" and the detail label "الدورة".
- **Evidence:** `qa/manual/screens/M07/M07-F-013-kind-terms.png`, `qa/manual/screens/M07/triage/t012-add-session-dialog.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-262: Bulk "أرشفة" / "استرجاع" act at once with no confirmation, and the result only says "تم: 1. تُخطّي: 0."
- **Feature:** M07 sessions list bulk bar, archive page. **Severity:** P3. **Type:** UI (missing confirmation/message). **Easy P3:** yes. **Priority:** medium
- **Found by:** M07-F-014.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions`, period "القادمة", status "تحت تصرف الإدارة". 2. Tick session 465 → "أرشفة". 3. (Restore) "الأرشيف" → tick it → "استرجاع".
- **Expected:** "أرشفة 1 حصة؟" confirmation; then a message naming the action ("أُرشفت حصة واحدة").
- **Actual:** no dialog; the row vanishes; the only feedback is "تم: 1. تُخطّي: 0." (same after "استرجاع" and bulk present).
- **Evidence:** `qa/manual/screens/M07/M07-F-014-archive-one-click.png`, `qa/manual/screens/M07/triage/t014-archive-one-click.png`, `qa/manual/screens/M07/triage/t014c-unarchived.png`
- **Notes:** 465 was unarchived again by Agent 2 after the repro.
- **Root cause:** `SessionBulkBar.tsx` ran archive/unarchive straight from the button, and the summary used one generic "scheduling.bulk.result" for every action.
- **Fix:** Archive / Restore go through `Confirm` (outline trigger) "أرشفة الحصص المحددة؟" / "استرجاع الحصص المحددة؟" with the count; the summary names the action: "سُجّل الحضور / سُجّل الغياب / أُلغيت / أُرشفت / استُرجعت: N. تُخطّي: M." (`scheduling.bulk.outcome.*`, ar/en/es).
- **Regression test:** `SessionsList.test.tsx` archive and restore tests (confirm dialog, no call before confirming, named summary); present/cancel tests expect the named summaries.
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-262-after.png`; shots `qa/manual/screens/M07/fix/` g262b-archive-confirm.png, g262c-archived-summary.png, g262e-restore-confirm.png, g262f-restored-summary.png. Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-263: Student "حصصي" starts every row with the student's own name; a postponed lesson has no "postponed" mark
- **Feature:** M07 student My sessions. **Severity:** P4. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-015.
- **Reproduction steps:** 1. Student Adam AR `/app/learning/sessions`.
- **Expected:** for a student "course · teacher" (the parent view keeps the child's name); a "مؤجلة" chip on 04/11 17:00 (moved from 03/11).
- **Actual:** "آدم النجار (Adam Al-Najjar) · التجويد للمبتدئين · الأستاذة مريم الخطيب …" on every row; the moved lesson looks like any other.
- **Evidence:** `qa/manual/screens/M07/M07-F-015-own-name-repeated.png`, `qa/manual/screens/M07/triage/t009-postpone-english-error.png`
- **Notes:** Not ETQAN-QA-112 (that is the order of the parts, fixed); this is the content.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-264: "مستويات طلابي": the first-level dialog shows an empty picker with no explanation when the course has no levels
- **Feature:** M07 student levels (teacher). **Severity:** P3. **Type:** UI (missing empty state). **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-018.
- **Reproduction steps:** 1. Teacher Maryam AR `/app/teaching/levels` → Aisha Rahman, "اللغة العربية للناطقين بغيرها" → "فتح التقدّم".
- **Expected:** "لا توجد مستويات لهذه الدورة بعد. اطلب من الإدارة إضافتها." instead of the picker.
- **Actual:** "تحديد المستوى الأول" with a select whose only option is "اختر مستوى" and a disabled "حفظ".
- **Evidence:** `qa/manual/screens/M07/M07-F-018-level-empty-dropdown.png`, `qa/manual/screens/M07/triage/t018-level-empty-dropdown.png`
- **Root cause / Fix:** same as ETQAN-QA-416 (M14), fixed in the same file by M14's Agent 3 (`curriculum/ProgressPanel.tsx`: with no active level the picker is replaced by "لا توجد مستويات لهذه الدورة بعد. اطلب من الإدارة إضافتها." / office variant). Not changed again; M07 Agent 3 only added the office key `curriculum.progress.noLevelsOffice` (ar/en) the component reads.
- **Regression test:** `ProgressPanel.test.tsx` "says why there is no level to choose (ETQAN-QA-416)" (passes).
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-264-after.png`; shots `qa/manual/screens/M07/fix/` g264b-no-levels.png (teacher AR), g264c-office-en.png (office EN). Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-265: Double-clicking "إرسال الطلب" (level upgrade) makes the second POST crash with HTTP 500 (IntegrityError) while the user sees success
- **Feature:** M07 level-upgrade requests. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Found by:** M07-F-019.
- **Reproduction steps:** 1. Teacher Maryam AR `/app/teaching/levels` → Aisha Rahman / التجويد للمبتدئين (level "M07 المستوى 1") → "فتح التقدّم" → "طلب ترقية" → note → double-click "إرسال الطلب".
- **Expected:** one request; the button disabled while sending, and a duplicate answered 409 `learning.request_pending`.
- **Actual:** toast "تم طلب الترقية." and one pending request, but the second call is `500 POST /api/v1/learning/level-upgrades/`; django log: `IntegrityError: duplicate key value violates unique constraint "learning_one_pending_request"`.
- **Evidence:** `qa/manual/screens/M07/M07-F-019-upgrade-double-submit-500.png`, `qa/manual/screens/M07/triage/t019-upgrade-double-submit-500.png`
- **Root cause (Agent 2 pointer):** `backend/etqan/learning/services/upgrades.py:request_upgrade` checks `exists()` then `create()` with no lock, so two concurrent requests both pass the check; the DB constraint then raises unhandled. Catch the IntegrityError (→ ConflictError `learning.request_pending`) or lock; also disable the submit button while pending.
- **Notes:** Data is protected by the constraint (no duplicate rows). Agent 2's repro request was rejected afterwards ("M07 triage cleanup"); Aisha stays on M07 Level 1.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-266: Homework linked to a session never shows which session (no column in the list, nothing on the session page)
- **Feature:** M07 homework ↔ sessions. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Found by:** M07-F-021.
- **Reproduction steps:** 1. Teacher Maryam AR `/app/teaching/homework` (homework "M07-واجب 1 أحكام النون", linked to 27/10). 2. Admin `/app/scheduling/sessions/409`.
- **Expected:** the session date in the list (`session_on` exists in the model) and a homework line on the session page.
- **Actual:** columns are الطالب / الدورة / العنوان / النوع / تمت الإجابة / الحالة / تاريخ التكليف; the session page has no homework section.
- **Evidence:** `qa/manual/screens/M07/M07-F-021-homework-no-session.png`, `qa/manual/screens/M07/triage/t020-file-input-english.png` (list behind the dialog)
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-267: Homework page: subtitle grammar "الأعمال التي تُكلَّف بها الطالب" and an empty "تمت الإجابة" cell
- **Feature:** M07 homework list. **Severity:** P4. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-021.
- **Reproduction steps:** 1. Teacher Maryam AR `/app/teaching/homework`.
- **Expected:** "الأعمال التي يُكلَّف بها الطالب بعد حصصه."; "لا" / "—" when there is no answer.
- **Actual:** feminine "تُكلَّف" (`locales/ar/homework.json` `subtitle`); the "تمت الإجابة" cell is blank.
- **Evidence:** `qa/manual/screens/M07/M07-F-021-homework-no-session.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-268: Phone (375): admin "اليوم" table is 519 px in a 341 px box; names wrap into 3–5 lines and "التقدم"/"الحصة" are off-screen
- **Feature:** M07 Today page. **Severity:** P3. **Type:** mobile. **Easy P3:** no. **Priority:** low
- **Found by:** M07-F-022.
- **Reproduction steps:** 1. Admin AR `--viewport 375x812` `/app/scheduling/today`.
- **Expected:** cards or a readable row with the status visible.
- **Actual:** "QA6 Teacher B" in 3 lines, "الشيخ أحمد الحداد (Ahmad Al-Haddad)" in 5; progress cut at the left edge ("1 من 8"); the status column needs a hidden sideways scroll (table 519 px, box 341 px).
- **Evidence:** `qa/manual/screens/M07/M07-F-022-mobile-today-cut.png`, `qa/manual/screens/M07/triage/t022-mobile-today.png`
- **Notes:** Same pattern as ETQAN-QA-118 (teacher table) and ETQAN-QA-173 (students list) — layout proposal.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-269: Session page header: the office note (e.g. "M07-makeup-1") and the cancel/disposal reason float under "المعلم" with no label
- **Feature:** M07 session detail. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-023.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions/466`.
- **Expected:** a label "ملاحظات" / "Notes" (and "سبب الإلغاء" etc.).
- **Actual:** "M07-makeup-1" alone under the teacher name.
- **Evidence:** `qa/manual/screens/M07/M07-F-023-session-ref-mirrored.png`, `qa/manual/screens/M07/triage/t023-session-ref-mirrored.png`
- **Notes:** The other half of M07-F-023 ("الحصة #465" shown as "465# الحصة") is not a bug: in an RTL line the "#" correctly sits between "الحصة" and the number, which is how "الحصة #465" reads right to left.
- **Root cause:** `SessionPage.tsx` printed `session.notes` as a bare muted paragraph under the facts; the reasons were sentences ("ملغاة: …").
- **Fix:** the note, cancel reason and disposal reason are labelled facts in a second `<dl>`: "ملاحظات", "سبب الإلغاء", "سبب وضعها تحت تصرف الإدارة" (`scheduling.session.notes/cancelReason/disposalReason`, ar/en/es).
- **Regression test:** `SessionPage.test.tsx` "labels the office note (ETQAN-QA-269)"; restore / disposal tests check the labelled reasons.
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-269-after.png`; shots `qa/manual/screens/M07/fix/` g269-466-cancel-reason.png, g254b-465.png (EN disposal reason). Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-270: Simplified view: "حاضر"/"غائب" don't say they mark the student, act with no message, and the date field stretches across the page
- **Feature:** M07 sessions simplified view. **Severity:** P3. **Type:** UI. **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-024.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions` → "العرض المبسّط".
- **Expected:** "الطالب حاضر" / "الطالب غائب" (the card shows both student and teacher marks), a toast after the tap, a normal-width date input.
- **Actual:** plain "حاضر"/"غائب"; no message (Agent 1 marked QA6 Student 2); the "اليوم" date input is ~1,100 px wide.
- **Evidence:** `qa/manual/screens/M07/M07-F-024-simple-view-buttons.png`, `qa/manual/screens/M07/triage/t024-simple-view.png`
- **Root cause:** `SimpleSessions.tsx` buttons used `archives.simple.present/absent` ("حاضر"/"غائب"), the mark had no `onSuccess`, and the date `Input` sat in a stretching `flex-col`.
- **Fix:** texts "الطالب حاضر"/"الطالب غائب" (aria "الطالب حاضر: {{name}}", label-in-name kept), success toast "تم تسجيل الحضور.", `items-start` on the day field's wrapper.
- **Regression test:** `SimpleSessions.test.tsx` marks test (button text, toast, new names).
- **Fixed by:** Agent 3, M07 cycle 1, 2026-10-27 (dashboard branch `qa/manual-2026-10`, uncommitted). Evidence: `qa/manual/evidence/M07/fix-1/`.
- **Verification status:** VERIFIED (M07 Agent 2 gate, 2026-10-27T21:07:50Z). Re-walked in the browser; before/after `qa/manual/screens/M07/fix/ETQAN-QA-270-after.png`; shots `qa/manual/screens/M07/fix/` g270a-simple.png, g270c-simple-toast.png. Scoped vitest 16 files 172/172 + tsc 0 (`qa/manual/evidence/M07/gate/`). Diff reviewed: root-cause fix, no test hacks.

## ETQAN-QA-271: Sessions CSV from the Arabic UI: English headers, raw codes (`regular`, `completed`, `not_set`, `no`) and start/end only in UTC
- **Feature:** M07 sessions export. **Severity:** P3. **Type:** translation. **Easy P3:** no. **Priority:** low
- **Found by:** M07-F-025.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions` (اليوم) → "تصدير CSV" (= `GET /api/v1/sessions/?when=today&format=csv`).
- **Expected:** headers and values in the UI language and a local-time column ("بتوقيت الأكاديمية").
- **Actual:** `ID,Date,Starts at (UTC),Ends at (UTC),…`; the Cairo 08:00 lesson is `2026-10-27 05:00:00+00:00`; only `Date` is local.
- **Evidence:** `qa/manual/screens/M07/M07-F-025-sessions-csv-sample.txt`, `qa/manual/screens/M07/M07-F-025-csv-export-button.png`, `qa/manual/screens/M07/triage/t025-sessions-csv-ar.txt`
- **Notes:** Same family as ETQAN-QA-161 (students CSV); the UTC-only time is specific to sessions. Fix with QA-161.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-272: Wording of two cycle-1 strings: the attendance-undo dialog's keep button says "إبقاؤها", and an ended session with no link says "لا يوجد رابط بعد"
- **Feature:** M07 session detail, teacher "حصصي". **Severity:** P4. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Found by:** M07 Agent 2 during the gate retest, 2026-10-27T21:07:50Z.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions/362`, set "حضور المعلم" to "حاضر" and then to "لم يُحدَّد". 2. Teacher Maryam AR `/app/teaching/sessions`, open "السجل".
- **Expected:** a keep button that fits the mark (for example "إبقاء التسجيل" or "تراجع"); on a lesson that is over, "بلا رابط" or "—" rather than "not yet".
- **Actual:** the button reuses `scheduling.session.keep` "إبقاؤها", which refers to the session. The finished 27/10 15:00 lesson shows "لا يوجد رابط بعد".
- **Evidence:** `qa/manual/screens/M07/fix/g252a-undo-dialog.png`, `qa/manual/screens/M07/fix/g255c-maryam-history.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-273: "إضافة حصة" with kind "إضافية": the Student list stops at the first 100 active students, with no search; Arabic-named students can't get an extra session
- **Feature:** M07 Sessions list → "إضافة حصة" (`AddSessionDialog`, kind extra). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Found by:** M07-F-026 (Agent 1, confirmation sweep #2); reproduced by Agent 2 on 2026-10-28.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions` → "إضافة حصة". 2. النوع = "إضافية". 3. Open "الطالب" (or `eval` the options of `select[name=student]`).
- **Expected:** every active student can be chosen, e.g. a "ابحث عن طالب" box like the "عادية" kind has above its Subscription list.
- **Actual:** 101 options (100 + blank), last "QA5 UI 526170"; Adam Al-Najjar (236), Omar Al-Sharif (232) are absent; no search input in the dialog. The code asks `usePeople("students", {is_active, page_size: 100})` with no `q`.
- **Evidence:** `qa/manual/screens/M07/M07-F-026-extra-student-list-capped.png`, `qa/manual/screens/M07/triage/t026-extra-student-list.png` (eval: n=101, has236=false, has232=false, search=false)
- **Notes:** Same family as ETQAN-QA-202 (new subscription) and ETQAN-QA-371 (student rate); different dialog. A shared searchable student picker would fix all three. Workaround for the office: none for the "extra" kind (make-up from a session page is a different kind).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-274: "إضافة حصة" (إضافية): "الدقائق" is required but has no asterisk and no hint, while for "عادية" it is optional
- **Feature:** M07 "إضافة حصة" (`AddSessionDialog` / `SessionFields`). **Severity:** P4. **Type:** UI (form). **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-027; reproduced by Agent 2 on 2026-10-28.
- **Reproduction steps:** 1. Admin AR "إضافة حصة" → النوع "إضافية". 2. Leave every field empty and press "إضافة الحصة".
- **Expected:** "الدقائق" carries the red * like the other required fields (or empty uses the course's usual length, as for "عادية").
- **Actual:** red "بين 15 و240 دقيقة." under an unstarred "الدقائق"; the regular kind shows "اتركها فارغة للمدة المعتادة" for the same field.
- **Evidence:** `qa/manual/screens/M07/M07-F-027-extra-minutes-required-no-star.png`, `qa/manual/screens/M07/triage/t027-extra-minutes-no-star.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-275: Cancelled session page still shows the "الرابط" / "Link" label with nothing under it
- **Feature:** M07 session detail header (`JoinLink` in `bits.tsx`, used with `showEmpty` by `SessionPage`). **Severity:** P4. **Type:** UI (empty state). **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-028; reproduced by Agent 2 on 2026-10-28.
- **Reproduction steps:** 1. Admin AR `/app/scheduling/sessions/474` (extra session, cancelled, archived; M07 test data).
- **Expected:** on a cancelled session hide the "الرابط" fact, or show "—" / "لا رابط".
- **Actual:** the heading "الرابط" with a blank value. `JoinLink` returns `null` for `status === "cancelled"` before the ETQAN-QA-250 `showEmpty` branch, so the label stays and the value is empty.
- **Evidence:** `qa/manual/screens/M07/M07-F-028-link-blank-cancelled.png`, `qa/manual/screens/M07/triage/t028-cancelled-link-blank.png`
- **Notes:** A gap left by the ETQAN-QA-250 fix (which covered non-cancelled sessions and is VERIFIED). Fix together with ETQAN-QA-272 (wording on ended sessions).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-276: Simplified view: "Student present" / "Student absent" are greyed out on sessions that haven't started, with no reason given
- **Feature:** M07 sessions simplified view (`SimpleSessions.tsx` `QuickMark`). **Severity:** P3. **Type:** UI (missing hint). **Easy P3:** yes. **Priority:** low
- **Found by:** M07-F-029; reproduced by Agent 2 on 2026-10-28.
- **Reproduction steps:** 1. Admin EN `/app/scheduling/sessions/simple` on 28/10 before the first lesson.
- **Expected:** the same hint the session page and the teacher's list give: "Attendance opens at the start time." / "يُفتح تسجيل الحضور عند موعد البدء."
- **Actual:** all 18 buttons (9 cards) disabled, no text on the page explains why.
- **Evidence:** `qa/manual/screens/M07/M07-F-029-simple-disabled-no-hint.png`, `qa/manual/screens/M07/triage/t029-simple-disabled-no-hint.png` (eval: 18 buttons, 18 disabled, no "opens" text)
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## --- M08 manual bugs ---

## ETQAN-QA-300: KWD payment with 4 decimals says "enter an amount greater than zero, like 150 or 150.50"
- **Feature:** M08 Invoice → Record payment (`PaymentDialog`). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-001); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin qa-admin@qa.etqan.test / `QA-Admin-2026!`; an unpaid KWD invoice (Agent 2 used INV-000174, KWD 10.000).
- **Reproduction steps:**
  1. AR `/app/billing/invoices/174` → "تسجيل دفعة" → amount `1.2345` → "تسجيل الدفعة".
- **Expected:** a message about the real problem (KWD takes at most 3 decimals), with an example in the invoice's currency (150.500).
- **Actual:** "أدخل مبلغًا أكبر من صفر، مثل 150 أو 150.50." although 1.2345 is above zero; the example has 2 decimals on a 3-decimal currency; on wrap the final period lands before ".150.50". Same key `billing.amountInvalid`/`amountOrZero` for all failures.
- **Evidence:** `qa/manual/screens/M08/M08-F-001-decimals-msg.png`, `qa/manual/screens/M08/triage/F-001-repro.png`
- **Root cause (Agent 3, fix cycle 1):** `billing/schemas.amount()` (and the invoice/record forms' `superRefine`) used one key, `billing.errors.amountInvalid`/`amountOrZero` ("above zero, like 150 or 150.50"), for every failure, including a well-formed number with more decimals than the currency's minor units; the Arabic examples were not isolated, so the final period jumped on wrap.
- **Fix:** a well-formed positive number with too many decimals now gets `billing.errors.decimals{0,2,3}` from `decimalsMessage(minorDigits(currency))` ("Use at most 3 decimal places, like 150.500." / "استخدم 3 أرقام عشرية على الأكثر، مثل 150.500."), in `amount()`, `invoiceFormSchema` and `recordFormSchema`; payroll forms that reuse `amount()` get the same. Arabic examples wrapped in U+2066/U+2069. ar/en/es keys added. (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `billing/schemas.test.ts` "says a well-formed amount has too many decimals for its currency (ETQAN-QA-300)" (KWD 1.2345 → decimals3, JPY → decimals0, abc/0 → amountInvalid); updated expectations in `recordSchemas.test.ts`, `InvoicePage.test.tsx`, `InvoiceForm.test.tsx`, `payroll/schemas.test.ts`, `payroll/RatesPage.test.tsx`, `payroll/AdjustmentsList.test.tsx`. Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). AR INV-000174 → Record payment 1.2345 shows "استخدم 3 أرقام عشرية على الأكثر، مثل 150.500.". Evidence `qa/manual/screens/M08/fix/ETQAN-QA-300-after.png` (before `qa/manual/screens/M08/triage/F-001-repro.png`).

## ETQAN-QA-301: Payment row actions are all solid red danger buttons (incl. "Move to balance"); delete reads "حذف دفعة بقيمة 2.500 د.ك."
- **Feature:** M08 Invoice detail payments list; Payment records table. **Severity:** P3. **Type:** UI. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-002, red-button part of M08-F-007); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin; an invoice with a cash payment.
- **Reproduction steps:**
  1. AR `/app/billing/invoices/174` → record 2.5 cash → look at the payment row.
  2. EN `/app/billing/payments` → look at the row actions.
- **Expected:** only Delete looks destructive; "Move to balance"/"Mark refunded" are secondary; delete label short ("حذف"/"Delete", amount kept for the aria-label only).
- **Actual:** three identical solid red buttons "نقل إلى الرصيد", "تحديد كمستردة", "حذف دفعة بقيمة 2.500 د.ك."; EN "Delete payment of KWD 5.500". Payment records: red "Mark refunded" + "Delete" stacked on each row. Same class as ETQAN-QA-421 (another screen).
- **Evidence:** `qa/manual/screens/M08/M08-F-002-payment-row-buttons.png`, `qa/manual/screens/M08/triage/F-002-repro.png`, `qa/manual/screens/M08/triage/F-004-repro.png`, `qa/manual/screens/M08/triage/F-007-repro.png`
- **Root cause (Agent 3, fix cycle 1):** every payment-row action used `Confirm` with its default destructive trigger, and the invoice's delete trigger text was the full `billing.payments.delete` sentence with the amount.
- **Fix:** `Confirm` (already extended for ETQAN-QA-205/214) gets `triggerVariant="outline"` for Mark refunded (`InvoicePage`, `PaymentRecordsPage`) and Move to balance (`wallet/MoveToWallet`, confirm button `primary`); Delete stays destructive with visible text `billing.payments.deleteAction` ("Delete"/"حذف"/"Eliminar") and the full "Delete payment of KWD 5.500" as its accessible name (`actionName`). (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `InvoicePage.test.tsx` "draws only Delete as destructive, with a short label (ETQAN-QA-301)"; `MoveToWallet.test.tsx` (trigger and confirm not `bg-destructive`); `PaymentRecordsPage.test.tsx` "keeps numbers on one line and Mark refunded not destructive". Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). INV-000171/174 AR+EN and Payment records: Move to balance / Mark refunded are outline, only the short "Delete"/"حذف" is red. Evidence `qa/manual/screens/M08/fix/ETQAN-QA-301-after.png`, `qa/manual/screens/M08/fix/ETQAN-QA-303-after.png`, `qa/manual/screens/M08/fix/ETQAN-QA-307-after.png`.

## ETQAN-QA-302: Invoice print view lists refunded and moved-to-balance payments as plain amounts (listed payments add up to more than the invoice); no way back
- **Feature:** M08 Invoice print (`_print/invoices.$invoiceId.print.tsx`). **Severity:** P3. **Type:** UI. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-003); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin; INV-000171 (KWD 12.345) with payments 5.500 refunded, 6.845 moved to balance, 3.000 balance, 1.000 cash, 8.345 Stripe.
- **Reproduction steps:**
  1. AR `/app/invoices/171/print`.
- **Expected:** non-counting payments (refunded/credited) visibly excluded (struck out, muted, or a separate list), so the printed payments match "المدفوع"; a link back to the invoice.
- **Actual:** "الدفعات" lists 5.500, 6.845, 3.000, 1.000, 8.345 in one plain column (24.690 on a 12.345 invoice, paid 12.345); the status word is only a bold word in the description. Page has only "طباعة" (same pattern as ETQAN-QA-420 for payslips).
- **Evidence:** `qa/manual/screens/M08/M08-F-003-print-refunded-amounts.png`, `qa/manual/screens/M08/triage/F-003-repro.png`
- **Root cause (Agent 3, fix cycle 1):** `InvoicePrint` rendered every payment the same way; only a bold status word marked refunded/credited ones. The missing way back was the shared `PrintSheet` (already fixed for ETQAN-QA-420 by M09's fixer: Back button, home when opened fresh).
- **Fix:** payments whose status is not `completed` are struck out and muted (`text-muted-foreground line-through`) on the print sheet, so the counted amounts match "Paid". Back comes from the shared `PrintSheet` change (ETQAN-QA-420). (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `InvoicePrint.test.tsx` "strikes out payments that no longer count, so the list adds up to Paid (ETQAN-QA-302)". Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). AR `/app/invoices/171/print`: refunded 5.500 and moved 6.845 struck out and muted; listed counting payments 3.000+1.000+8.345 = Paid 12.345; "رجوع" button present. Evidence `qa/manual/screens/M08/fix/ETQAN-QA-302-after.png`.

## ETQAN-QA-303: English invoice page uses "Balance" both for the amount still owed and for the student's wallet
- **Feature:** M08 Invoice detail (EN). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-004); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin, EN.
- **Reproduction steps:**
  1. EN `/app/billing/invoices/171`.
- **Expected:** "Balance due"/"Remaining" for the invoice; "Wallet"/"Credit balance" for the stored money (AR already separates "المتبقي" / "الرصيد").
- **Actual:** summary "Balance KWD 0.000" (= owed) next to "Pay from balance", "Move to balance", chip "Moved to balance", method "KWD 3.000 · Balance" (= wallet).
- **Evidence:** `qa/manual/screens/M08/M08-F-004-balance-two-meanings.png`, `qa/manual/screens/M08/triage/F-004-repro.png`
- **Root cause (Agent 3, fix cycle 1):** `en/billing.json` `columns.balance` = "Balance", the same word the English UI uses for the wallet (`methods.wallet`, Pay from balance, Move to balance).
- **Fix:** `columns.balance` → "Balance due" (en), "Saldo pendiente" (es); `errors.overBalance` → "That is more than the balance due." (en/es). The wallet keeps "Balance". Arabic already separated them. (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `InvoicePage.test.tsx` "links the subscription only for a reader who may open it, and says 'Balance due'"; `FamilyInvoices.test.tsx` ("Balance due:"). Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). EN INV-000174 shows "Balance due KWD 7.500", distinct from "Pay from balance". Evidence `qa/manual/screens/M08/fix/ETQAN-QA-303-after.png`.

## ETQAN-QA-304: A second invoice for an already-invoiced subscription is created with no warning
- **Feature:** M08 New invoice (`InvoiceForm`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-005); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin; Omar Al-Sharif (student 232), subscription 90 already invoiced by INV-000154 (EGP 1,200, paid).
- **Reproduction steps:**
  1. EN `/app/billing/invoices/new` → Find "Omar" → Student Omar Al-Sharif → Subscription "Quran Memorization, from Oct 27, 2026".
  2. (Agent 1) Create invoice → INV-000173 created (voided afterwards).
- **Expected:** a notice that the subscription already has INV-000154 (paid) before a second bill is issued (an extra charge may be legitimate, so warn, don't block).
- **Actual:** form prefills 1200.00 and the description with no hint; creation succeeds silently.
- **Evidence:** `qa/manual/screens/M08/M08-F-005-second-sub-invoice-no-warning.png`, `qa/manual/screens/M08/triage/F-005-repro.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-305: The payment "Reference" typed on an invoice is not shown in Payment records and search can't find it
- **Feature:** M08 Payment records (`services/records.py` search, records table). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-006); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin.
- **Reproduction steps:**
  1. AR `/app/billing/invoices/174` → "تسجيل دفعة" 2.5, المرجع `M08-T2-REF` → save (invoice row shows "M08-T2-REF · 2026/10/27").
  2. EN `/app/billing/payments` → row INV-000174: Transaction column empty; search `M08-T2-REF`.
- **Expected:** the reference appears on the record (Transaction or its own column) and the search finds it.
- **Actual:** blank Transaction cell; search returns nothing. `Payment.reference` is a separate field from `transaction_number`; the search Q in `records.py:73-77` covers names, transaction_number and invoice number only.
- **Evidence:** `qa/manual/screens/M08/M08-F-006-reference-not-found.png`, `qa/manual/screens/M08/triage/F-006-repro.png`, `qa/manual/screens/M08/triage/F-007-repro.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-306: Filtered empty results say "none yet": Payment records search ("No payment records yet.") and Online payments "needs attention" tab ("لا مدفوعات إلكترونية بعد.")
- **Feature:** M08 Payment records, Online payments. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-006 empty-state part, M08-F-015 empty-state part); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin.
- **Reproduction steps:**
  1. EN `/app/billing/payments` → search `M08-T2-REF`.
  2. AR `/app/billing/checkouts` → tab "تحتاج إلى متابعة".
- **Expected:** "No matching payment records." / "لا شيء يحتاج إلى متابعة."
- **Actual:** "No payment records yet." with 4 pages of records; "لا مدفوعات إلكترونية بعد." on the attention tab while the list is full. Same class as ETQAN-QA-152 (students).
- **Evidence:** `qa/manual/screens/M08/triage/F-006-repro.png`, `qa/manual/screens/M08/M08-F-015-attention-empty.png`
- **Root cause (Agent 3, fix cycle 1):** `PaymentRecordsPage` and `CheckoutsList` always showed the "none yet" empty text, whatever the search, filter or tab.
- **Fix:** `finance/shared.useListParams` returns `filtered` (any param but `page` set). Records: `billing.records.emptyFiltered` when filtered. Online payments: `gateways.checkouts.emptyAttention` on the Needs-attention tab, `emptyFiltered` when filtered. ar/en/es. (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `PaymentRecordsPage.test.tsx` "says a search with no match is no match, not 'none yet' (ETQAN-QA-306)"; `CheckoutsList.test.tsx` "says a filtered or attention list has no match". Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). EN Payment records search `zz-no-such-M08` → "No payment records match your search or filters."; AR Online payments attention tab → "لا شيء يحتاج إلى متابعة.". Evidence `qa/manual/screens/M08/fix/ETQAN-QA-306-after-records.png`, `qa/manual/screens/M08/fix/ETQAN-QA-306-after-attention.png`.

## ETQAN-QA-307: Payment records table at 1440 px: invoice numbers and names wrap over 2–4 lines while the Transaction column is wide; "To" filter alone on a second row; USD shown as "$85.00" while others show codes
- **Feature:** M08 Payment records (EN). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-007); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin, EN.
- **Reproduction steps:**
  1. EN `/app/billing/payments`.
- **Expected:** "INV-000171" on one line, names on at most 2 lines, filters on one row; one currency style.
- **Actual:** "INV-/000174", "Oct/27,/2026", "ليلى الشريف (Layla/Al-Sharif)/Student"; Transaction column ~300 px; "To" wraps under the search; "$85.00"/"$0.00" next to "EGP 1,200.00"/"KWD 3.000" (AR invoice list/home show "US$"). Red buttons: see ETQAN-QA-301.
- **Evidence:** `qa/manual/screens/M08/M08-F-007-payment-records-layout.png`, `qa/manual/screens/M08/triage/F-007-repro.png`
- **Root cause (Agent 3, fix cycle 1):** the records table cells had no wrapping rules (dates, invoice numbers and amounts broke, the transaction id column took the slack), and From/To were separate flex items so "To" wrapped alone.
- **Fix:** date, invoice, amount and fee cells `whitespace-nowrap`; customer `min-w-40`; transaction `max-w-48 break-all`; From and To in one wrapping group. The USD "$" vs codes part is an app-wide `formatMoney` display choice: PROPOSAL in `qa/coverage-gaps.md` (M08 section), not built. (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `PaymentRecordsPage.test.tsx` "keeps numbers on one line and Mark refunded not destructive (ETQAN-QA-307, ETQAN-QA-301)". Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28) for layout: dates, INV numbers, amounts on one line, transaction capped, From/To together. USD "$" vs code part PROPOSAL-accepted (product decision, changes every amount; coverage-gaps). Evidence `qa/manual/screens/M08/fix/ETQAN-QA-307-after.png`.

## ETQAN-QA-308: Arabic payment-link page says the payment is "لصالح" (in favour of) the payer
- **Feature:** M08 Public payment link (`gateways.json` `for`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-008); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** a payment link for payer "M08 ولي أمر زائر" (token `YEwsi8Xej75BBWLTTUhryg`).
- **Reproduction steps:**
  1. Signed out, AR: `/app/pay/link/YEwsi8Xej75BBWLTTUhryg`.
- **Expected:** "مطلوب من: M08 ولي أمر زائر" / "الدافع: …" (EN "For …" is also ambiguous: "Billed to …").
- **Actual:** "الدفع لصالح M08 ولي أمر زائر" = payment in favour of the payer. Key `ar/gateways.json` `"for": "الدفع لصالح {{name}}"`.
- **Evidence:** `qa/manual/screens/M08/M08-F-008-link-payer-wording.png`, `qa/manual/screens/M08/triage/F-008-repro.png`
- **Root cause (Agent 3, fix cycle 1):** `ar/gateways.json` `link.for` = "الدفع لصالح {{name}}" (in favour of the payer); en "For {{name}}" ambiguous.
- **Fix:** ar "مطلوب من: {{name}}", en "Billed to {{name}}", es "Facturado a {{name}}". (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `PublicLinkPage.test.tsx` (EN "Billed to Abu Khalid"; AR "مطلوب من: Abu Khalid", no "لصالح"). Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). Signed out: AR "مطلوب من: M08 ولي أمر زائر", EN "Billed to M08 ولي أمر زائر". Evidence `qa/manual/screens/M08/fix/ETQAN-QA-308-after.png`, `qa/manual/screens/M08/fix/ETQAN-QA-308-after-en.png`.

## ETQAN-QA-309: Payment-link return page is a dead end: decline shows only "لم يتم الدفع." (no retry, no amount); success shows an unrelated consultation hint
- **Feature:** M08 `/pay/return` (`ReturnPage`) for anonymous link payers. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-009); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** Agent 2 created link "M08-T2 رابط" (EGP 50, token `CCgqNymFVJzYM4kbo46O8w`, now paid).
- **Reproduction steps:**
  1. Signed out, AR: open the link → "الدفع عبر Stripe" → simulator "ارفض".
  2. Open the link again → Stripe → simulator "ادفع".
- **Expected:** decline: "Payment not completed" + "Try again" back to the link + what/how much; success: title, amount, reference, academy.
- **Actual:** decline: title "دفعتك" + red "لم يتم الدفع." only. Success: "تم الدفع — شكرًا لك." + "حجزت استشارة؟ افتحها من الرابط الذي نرسله إلى بريدك بعد الدفع." (consultations key) for a registration fee. A signed-in parent paying an invoice gets "حاول مرة أخرى"/"العودة إلى الفاتورة", so only link payers are stuck. Admin side correct.
- **Evidence:** `qa/manual/screens/M08/M08-F-009-declined-dead-end.png`, `qa/manual/screens/M08/triage/F-009-repro-decline.png`, `qa/manual/screens/M08/triage/F-009-repro-success.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-310: Parent wallet "شحن" (top-up) dialog opens with no buttons: no Cancel, no close, pay button hidden until an amount is typed
- **Feature:** M08 Parent/student wallet top-up dialog. **Severity:** P3. **Type:** UI. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-010); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** parent parent.najjar@ (session from Agent 1).
- **Reproduction steps:**
  1. AR `/app/learning/wallet` → "شحن" on Adam.
- **Expected:** "ادفع عبر Stripe" (disabled until an amount) and "إلغاء", like the other dialogs.
- **Actual:** only title, amount, currency; no button at all; Enter does nothing. Same class as ETQAN-QA-212/401/254 (dialogs without Cancel), different dialog.
- **Evidence:** `qa/manual/screens/M08/M08-F-010-topup-no-buttons.png`, `qa/manual/screens/M08/triage/F-010-repro.png`
- **Root cause (Agent 3, fix cycle 1):** `wallet/OnlineTopUpDialog` has no footer; provider buttons render only once the amount is valid and providers load, so the dialog opened with no button at all.
- **Fix:** a `DialogFooter` with Cancel (`gateways.pay.cancel`), and a hint `wallet.family.enterAmount` ("Type an amount to see the ways to pay.") until a valid amount is typed; the pay buttons still depend on the amount (providers are asked per amount). ar/en (wallet has no es file). (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `OnlineTopUpDialog.test.tsx` "opens with a way out and says to type an amount first (ETQAN-QA-310)". Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). Parent najjar AR wallet → شحن: dialog shows hint "اكتب المبلغ لتظهر طرق الدفع." and an "إلغاء" button. Evidence `qa/manual/screens/M08/fix/ETQAN-QA-310-after.png`.

## ETQAN-QA-311: Signed amounts in Arabic put the sign or currency at the wrong end: wallet "200.00 ج.م.+" / "200.00 ج.م.-"; home negative net profit "ج.م. -618.36"
- **Feature:** M08 Wallet statement (`features/wallet/Statement.tsx` prepends "+"/"-" to `formatMoney`), Home money card (negative `formatMoney`). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-011, M08-F-012); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** parent parent.najjar@ (Adam's wallet: +200 top-up, −200 on INV-000166); admin for Home.
- **Reproduction steps:**
  1. AR parent `/app/learning/wallet` → statement column "المبلغ".
  2. AR admin Home with a negative net profit. Net profit is positive again now (parallel data), so Agent 2 rendered `Intl.NumberFormat("ar",{style:"currency",currency:"EGP"}).format(-618.36)` (= "‏‎-618.36 ج.م.‏", what `formatMoney` returns) into the net-profit cell.
- **Expected:** "+200.00 ج.م." / "−200.00 ج.م." and "−618.36 ج.م.", number then currency like every other amount.
- **Actual:** "200.00 ج.م.+", "200.00 ج.م.-"; "ج.م. -618.36" (the LRM before the minus splits the run).
- **Evidence:** `qa/manual/screens/M08/M08-F-011-plus-sign.png`, `qa/manual/screens/M08/M08-F-012-negative-amount-order.png`, `qa/manual/screens/M08/triage/F-011-repro.png`, `qa/manual/screens/M08/triage/F-012-repro.png`
- **Root cause (Agent 3, fix cycle 1):** `wallet/Statement.Signed` glued "+"/"-" in front of `formatMoney`'s Arabic text (RLM … currency), so the sign landed after the currency; the home negative came from `formatMoney`'s Arabic negative (RLM LRM "-"), the same root as ETQAN-QA-360.
- **Fix:** new `lib/money.formatSignedMoney` (Intl `signDisplay: "always"`; in Arabic the sign and number are one isolated run U+2066…U+2069 like the QA-360 negative); `Statement` uses it. Home negative net profit: fixed at the root by the ETQAN-QA-360 change to `formatMoney` (M09 fixer, same file, kept). Browser probe: `qa/manual/evidence/M08/fix-1/bidi-signed-probe.png` (old "+" at the far end, new "+200.00 ج.م."). (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `lib/money.test.ts` "signs a statement amount on the number's side" (ar +/−, en "+EGP 300.00", KWD 3 decimals); `Statement.test.tsx` unchanged and passing. Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). Parent wallet statement AR: measured glyph x-positions show signed amounts laid out exactly like the unsigned balance (currency left, sign on the number: ⁦-200.00⁩ / ⁦+200.00⁩ ج.م.). Home negative net profit not reproducible with live data (positive); covered by money.test.ts + Agent 3 probe `qa/manual/evidence/M08/fix-1/bidi-signed-probe.png`. Evidence `qa/manual/screens/M08/fix/ETQAN-QA-311-after.png`, `qa/manual/screens/M08/fix/ETQAN-QA-311-after-table.png`.

## ETQAN-QA-312: Exchange rates (AR): the rate reads "EGP تساوي 1 KWD 160.5"; date cell repeats "آخر تحديث"; empty "الحالة" column
- **Feature:** M08 Exchange rates list. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-013); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin; rates KWD 160.5, SAR 13, USD 48.75.
- **Reproduction steps:**
  1. AR `/app/billing/exchange-rates`.
- **Expected:** "1 KWD تساوي 160.5 EGP"; date cell just the date; a status value or no column.
- **Actual:** "EGP تساوي 1 KWD 160.5" (number detached from EGP), "آخر تحديث 2026/10/27" in every cell, "الحالة" empty on all rows. Related to ETQAN-QA-100 (Latin codes in Arabic text).
- **Evidence:** `qa/manual/screens/M08/M08-F-013-rate-sentence-scrambled.png`, `qa/manual/screens/M08/triage/F-013-repro.png`
- **Root cause (Agent 3, fix cycle 1):** the rate line was rendered `dir="auto"` (first strong char Latin → LTR) around an Arabic sentence with Latin codes; the date cell used `finance.rates.updated` ("آخر تحديث {{date}}") under a header with the same words; the status cell rendered nothing for a usable rate.
- **Fix:** rate line follows the page direction and `ar` `rates.line` isolates "⁦1 {{from}}⁩ تساوي ⁦{{rate}} {{base}}⁩"; the date cell shows the date only; a usable rate shows a `finance.rates.current` chip ("حديث"/"Current"/"Vigente"). Browser probe: `qa/manual/evidence/M08/fix-1/bidi-rate-probe.png` (reads "1 KWD تساوي 160.5 EGP"). (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `ExchangeRatesList.test.tsx` "shows the date alone under 'Last update' and 'Current' for a usable rate (ETQAN-QA-312)" and the Arabic test now asserts the isolated sentence. Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). AR exchange rates: "1 KWD تساوي 160.5 EGP" reads correctly, date cell shows 2026/10/27 only, status shows "حديث". Evidence `qa/manual/screens/M08/fix/ETQAN-QA-312-after.png`.

## ETQAN-QA-313: Online payments (AR): wallet top-ups are labelled in English "Wallet top-up · …"
- **Feature:** M08 Online payments list; label frozen in `backend/etqan/wallet/services/topup_purpose.py:49`. **Severity:** P3. **Type:** translation. **Easy P3:** yes (the payload has `purpose`; the list can translate by purpose). **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-014); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin; a completed parent top-up.
- **Reproduction steps:**
  1. AR `/app/billing/checkouts` → column "مقابل".
- **Expected:** "شحن الرصيد · آدم النجار (Adam Al-Najjar)".
- **Actual:** "Wallet top-up · آدم النجار (Adam Al-Najjar)".
- **Evidence:** `qa/manual/screens/M08/M08-F-014-wallet-topup-english.png`, `qa/manual/screens/M08/triage/F-014-repro.png`
- **Root cause (Agent 3, fix cycle 1):** the checkout description is frozen in English when the checkout starts (`backend/etqan/wallet/services/topup_purpose.py:49` "Wallet top-up · <name>"; same for recorded courses and consultations), and `CheckoutsList` printed it as is in an LTR cell.
- **Fix:** `CheckoutsList` renders those purposes from `gateways.checkouts.purpose.<purpose>` with the name/code kept ("شحن الرصيد · آدم النجار …"); the cell is LTR only for invoice numbers. ar/en/es. Durable server-side change: follow-up in `qa/coverage-gaps.md`. (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `CheckoutsList.test.tsx` "names a wallet top-up in the reader's language (ETQAN-QA-313)". Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). AR Online payments shows "شحن الرصيد · آدم النجار (Adam Al-Najjar)". Server-side label + CSV follow-up PROPOSAL-accepted (P3 follow-up, coverage-gaps). Evidence `qa/manual/screens/M08/fix/ETQAN-QA-313-after.png`.

## ETQAN-QA-314: Staff with invoice create but no student view gets the "New invoice" form with an empty student list and no explanation; invoice page links to a subscription they can't open
- **Feature:** M08 New invoice / invoice detail with a custom role. **Severity:** P2. **Type:** permission. **Easy P3:** no. **Priority:** high
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-016); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** role 34 "M08 محاسب فواتير" (invoice.view, view_any, create, update, payment.create); staff m08.clerk@qa.etqan.test (session copied from Agent 1).
- **Reproduction steps:**
  1. AR clerk `/app/billing/invoices/new` → "ابحث عن طالب" = "الشريف".
  2. (Agent 1) `/app/billing/invoices/172` → "افتح الاشتراك".
- **Expected:** the form explains that student access is needed (or the payer/student picker uses an endpoint gated by `invoice.create`, like `billing/payers/`), or the role editor warns; the subscription is plain text without access.
- **Actual:** "الطالب" offers only "—"; every search silently gets `403 GET /api/v1/people/students/?is_active=true&page_size=100[&q=…]`; the clerk can never issue an invoice and isn't told why. Subscription link → "ليس لديك صلاحية…" (pattern of ETQAN-QA-109).
- **Evidence:** `qa/manual/screens/M08/M08-F-016-clerk-empty-student-picker.png`, `qa/manual/screens/M08/M08-F-016-clerk-subscription-link.png`, `qa/manual/screens/M08/triage/F-016-repro.png`
- **Root cause (Agent 3, fix cycle 1):** the New invoice form always queries `people/students/` (needs `student.view_any`) and ignored the 403; the invoice page linked "Open the subscription" for any admin view.
- **Fix:** dashboard only: without `student.view_any` the form shows `billing.form.noStudentAccess` ("Issuing an invoice needs permission to view students. Ask an academy admin to add it to your role.") and asks nothing; the subscription list is asked only with `subscription.view_any`; the subscription link shows only with `subscription.view`. The real enabler (a billing-owned student lookup gated by `invoice.create`) is an API change: PROPOSAL in `qa/coverage-gaps.md`, not built. (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `InvoiceForm.test.tsx` "explains, instead of an empty picker, when the role can't see students (ETQAN-QA-314)"; `InvoicePage.test.tsx` "links the subscription only for a reader who may open it…". Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28) for the dashboard: clerk m08.clerk@ (role 34) on New invoice sees "إصدار فاتورة يحتاج إلى صلاحية عرض الطلاب…" instead of an empty picker (no silent 403 search); INV-000172 has no subscription link. Remaining API part (billing-owned student lookup gated by invoice.create) PROPOSAL-accepted: not a P0/P1, the gap is now explained and an admin can grant student.view_any; needs an API change (outside Agent 3 rules). Evidence `qa/manual/screens/M08/fix/ETQAN-QA-314-after-form.png`, `qa/manual/screens/M08/fix/ETQAN-QA-314-after-sublink.png`.

## ETQAN-QA-315: Phone (375): invoices table is 754 px in 341 px (status, balance, due off-screen); filters fill the first screen; long transaction id runs past the card padding
- **Feature:** M08 Admin invoices list and parent invoice detail, 375x812. **Severity:** P3. **Type:** mobile. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-017); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin; parent parent.najjar@ (INV-000166 paid online).
- **Reproduction steps:**
  1. AR 375x812 `/app/billing/invoices` → `[table.scrollWidth, parent.clientWidth]`.
  2. AR 375x812 parent `/app/learning/invoices/166` → payments card.
- **Expected:** a phone layout showing number, student, amount and status (cards, like the parent list); ids wrap inside the card.
- **Actual:** `[754, 341]`: only الرقم/الطالب/باسم/part of المبلغ visible ("1,200.00 ج.م" clipped), names over 4–5 lines; "pi_sim_2548b…" reaches x≈20 of 375, past the card padding, and "· 2026/10/27 ·" breaks with a dot at the line start. Same family as ETQAN-QA-173 (students list).
- **Evidence:** `qa/manual/screens/M08/M08-F-017-mobile-invoice-list.png`, `qa/manual/screens/M08/M08-F-017-mobile-txn-overflow.png`, `qa/manual/screens/M08/triage/F-017-repro-list.png`, `qa/manual/screens/M08/triage/F-017-repro-txn.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-316: Parent's invoice list doesn't show what an invoice is for or its total: two "Adam, due 2026/11/03" invoices look identical
- **Feature:** M08 Parent invoices list (`/learning/invoices`). **Severity:** P3. **Type:** UI. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-018); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** parent parent.najjar@.
- **Reproduction steps:**
  1. AR `/app/learning/invoices`.
- **Expected:** each card shows the description (course — package) and the amount.
- **Actual:** only number, "لآدم النجار (Adam Al-Najjar)، تستحق في 2026/11/03", "المتبقي" and status; INV-000166 and INV-000155 are indistinguishable without opening.
- **Evidence:** `qa/manual/screens/M08/M08-F-018-parent-list-no-description.png`, `qa/manual/screens/M08/triage/F-018-repro.png`
- **Root cause (Agent 3, fix cycle 1):** `FamilyInvoices` cards showed only number, student/due line, balance and status, though the list payload carries `description` and `amount_minor`.
- **Fix:** each card shows the description and "Amount: <total>" above "Balance due". (dashboard branch `qa/manual-2026-10`, uncommitted.)
- **Regression test:** `FamilyInvoices.test.tsx` "says what each invoice is for and its total (ETQAN-QA-316)". Checks: `pnpm tsc --noEmit` clean, touched Vitest files plus billing/wallet/gateways/finance/payroll/vouchers suites green, biome clean; evidence qa/manual/evidence/M08/fix-1/ (tsc.txt, vitest.txt, vitest-wide.txt, vitest-rerun.txt, vitest-payroll.txt, vitest-final.txt, biome.txt).
- **Verification status:** VERIFIED (Agent 2 gate M08, 2026-10-28). Parent invoice cards show description and "المبلغ: 1,200.00 ج.م." above "المتبقي" (desktop and 375 px). Evidence `qa/manual/screens/M08/fix/ETQAN-QA-316-after.png`, `qa/manual/screens/M08/fix/ETQAN-QA-316-after-mobile.png`.

## ETQAN-QA-317: System codes (EN, 1440 px): the code wraps over two lines "SYS-NZE8E-" / "D46F1"
- **Feature:** M08 System codes list. **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 (M08-F-019); reproduced by Agent 2 on 2026-10-27.
- **Preconditions:** admin, EN.
- **Reproduction steps:**
  1. EN `/app/billing/codes` → search `NZE8E`.
- **Expected:** the code on one line (`whitespace-nowrap`), as in AR.
- **Actual:** "SYS-NZE8E-" / "D46F1"; "Course · package" header also wraps.
- **Evidence:** `qa/manual/screens/M08/M08-F-019-code-wraps.png`, `qa/manual/screens/M08/triage/F-019-repro.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN


## ETQAN-QA-318: New payment link (AR): KWD 5.125 via Stripe is refused with raw English "This payment method cannot take this amount." under the gateway field, no reason or hint
- **Feature:** M08 Payment links → New link (`gateways/services/links.py:241`; same text `checkouts.py:205`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 confirmation sweep (M08-F-020); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** admin qa-admin@ (AR); Stripe gateway on.
- **Reproduction steps:**
  1. AR `/app/billing/links` → "إنشاء رابط" → payer "شخص آخر", name "M08-G2 زائر", email, currency KWD, amount `5.125`, title "M08-G2 رابط دينار", untick "إضافة رسوم الخدمة", gateway Stripe → "إنشاء رابط".
- **Expected:** an Arabic message that names the problem and the fix (e.g. the gateway only takes KWD in steps of 0.010: use 5.120 or 5.130), placed on the amount. 5.120 is accepted.
- **Actual:** 400 on `POST /api/v1/gateways/links/`; red English "This payment method cannot take this amount." under "بوابة الدفع" (server text shown as-is). Same class as ETQAN-QA-206 / 157 / 358 / 257 (raw English server messages), new screen.
- **Evidence:** `qa/manual/screens/M08/M08-F-020-link-amount-english-error.png`, `qa/manual/screens/M08/triage/F-020-repro.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-319: Office staff see the family-worded "ادفع محليًا / Pay locally" box on the invoice page ("…ثم أخبر الأكاديمية لتسجّل دفعتك.")
- **Feature:** M08 Invoice detail (office, `/app/billing/invoices/<id>`), local payment methods. **Severity:** P3. **Type:** UI/copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 confirmation sweep (M08-F-021); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** local payments on, an active method for the student's country (method "M08 إنستاباي", EG).
- **Reproduction steps:**
  1. Admin AR `/app/billing/invoices/178`; also EN.
- **Expected:** per `docs/features/billing.md` the local methods are "shown to families"; the office sees nothing, or an office-worded note ("طرق الدفع المحلية التي تظهر للعائلة").
- **Actual:** a card "ادفع محليًا — ادفع بإحدى هذه الطرق، ثم أخبر الأكاديمية لتسجّل دفعتك." (EN "Pay locally — Pay with one of these, then tell the academy so it can record your payment.") tells the office to pay and to tell the academy, on the screen where they record payments.
- **Evidence:** `qa/manual/screens/M08/M08-F-021-admin-sees-family-local-pay-box.png`, `qa/manual/screens/M08/triage/F-021-repro.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-320: Arabic toast after applying a discount code ends with two full stops: "طُبّق خصم بقيمة 100.00 ج.م.."
- **Feature:** M08 Family invoice → "استخدام كود" (`locales/ar/vouchers.json` "done": "طُبّق خصم بقيمة {{amount}}."). **Severity:** P4. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 confirmation sweep (M08-F-022); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** student عمر الشريف (student.sharif1@ / `QA-People-2026!`); unused EGP discount code (Agent 2 used SYS-DSNF8-SCZYH, 100.00 ج.م.); unpaid EGP invoice (INV-000178).
- **Reproduction steps:**
  1. Student AR `/app/learning/invoices/178` → "استخدام كود" → `SYS-DSNF8-SCZYH` → "تطبيق".
- **Expected:** "طُبّق خصم بقيمة 100.00 ج.م." (one stop). Amounts are right: paid 20.00 + 100.00 = 120.00, 80.00 left.
- **Actual:** toast "طُبّق خصم بقيمة 100.00 ج.م.." – the EGP symbol ends with a dot and the string adds another. Any AR message ending in an EGP amount does the same.
- **Evidence:** `qa/manual/screens/M08/M08-F-022-toast-double-period.png`, `qa/manual/screens/M08/triage/F-022-repro.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## ETQAN-QA-321: English UI: Arabic local-method instructions are laid out LTR and scrambled (phone number jumps before "ثم أرسل … واتساب")
- **Feature:** M08 Invoice detail "Pay locally" card (office and family). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend adff9c9 + uncommitted QA fixes, dashboard 5ed775d + branch `qa/manual-2026-10`), academy `qa` (Africa/Cairo, EGP), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M08 confirmation sweep (M08-F-023); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** method "M08 إنستاباي" with instructions "حوّل المبلغ إلى m08@instapay ثم أرسل صورة الإيصال على واتساب 01000000000".
- **Reproduction steps:**
  1. Admin EN `/app/billing/invoices/178` → "Pay locally" card.
- **Expected:** the instructions keep their own direction (`dir="auto"` / plaintext bidi), reading as in AR.
- **Actual:** the line is left-aligned in LTR base direction and renders as "حوّل المبلغ إلى m08@instapay 01000000000 ثم أرسل صورة الإيصال على واتساب" – the phone number sits mid-sentence.
- **Evidence:** `qa/manual/screens/M08/M08-F-023-local-method-instructions-scrambled-en.png`, `qa/manual/screens/M08/triage/F-023-repro.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

## --- M12 manual bugs ---

## ETQAN-QA-500: Branding form validation is English in the Arabic UI: colour "Use a colour like #RRGGBB." and raw zod "Too small: expected string to have >=1 characters" for an empty name
- **Feature:** M12 Settings (website branding). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-001); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: open `/app/website/branding` (الهوية).
  2. Type `red` in اللون الأساسي, click "حفظ التغييرات" (refused, nothing saved).
  3. Clear اسم الأكاديمية (العربية), click "حفظ التغييرات".
- **Expected:** Arabic messages under the fields (e.g. "استخدم لونًا مثل ‎#RRGGBB", "هذا الحقل مطلوب.").
- **Actual:** ".Use a colour like #RRGGBB" (English, full stop mirrored) and "Too small: expected string to have >=1 characters".
- **Evidence:** `qa/manual/screens/M12/M12-F-001-colour-error-english.png`, `qa/manual/screens/M12/triage/t001-colour-error.png`, `qa/manual/screens/M12/triage/t001b-empty-name.png`
- **Notes:** `dashboard/src/features/website/schemas.ts:17` hard-codes the English colour message and the name rules use bare `.min(1)`. Same family as ETQAN-QA-048, whose fix covered only the identity schemas; not a re-file (different form). Also: no colour swatch/picker, only a text box.
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: `brandingSchema` (`dashboard/src/features/website/schemas.ts`) hard-coded the English colour sentence and used bare `.min(1)` / `z.url()` / `z.email()`, so zod's English default reached the form; `BrandingForm` and `BilingualField` rendered `error.message` without `t()`. Fix: the colour, required-name, URL and email rules carry i18n keys (`website.branding.errors.colour|required|url|email`, ar/en/es; the URL/email key is on both the inner check and the union, since zod reports either), and `BrandingForm` + `BilingualField` render field errors through `useFieldError()` (server sentences still pass through). Regression test: `BrandingForm.test.tsx` "in Arabic › words a bad colour and an empty name in Arabic, not English or zod". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-500-after.png` (AR colour "استخدم لونًا مثل #RRGGBB."), `qa/manual/screens/M12/fix/ETQAN-QA-500-after-b.png` (AR "هذا الحقل مطلوب."), `qa/manual/screens/M12/fix/ETQAN-QA-500-after-en.png` (EN). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-501: Branding (AR): the LinkedIn, Snapchat and SoundCloud labels are left in English while the other six social labels are Arabic
- **Feature:** M12 Settings (website branding). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-002); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/website/branding`, scroll to the social links.
- **Expected:** Arabic labels like the rest (لينكدإن، سناب شات، ساوند كلاود).
- **Actual:** "LinkedIn", "Snapchat", "SoundCloud" in English under فيسبوك، إنستغرام، يوتيوب، إكس، تيك توك، تيليغرام.
- **Evidence:** `qa/manual/screens/M12/M12-F-002-social-labels-untranslated.png`, `qa/manual/screens/M12/triage/t001-colour-error.png`
- **Notes:** `dashboard/src/locales/ar/website.json` lines 60-62 hold the English words.
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: `locales/ar/website.json` held the English words for `branding.social.linkedin|snapchat|soundcloud`. Fix: لينكدإن، سناب شات، ساوند كلاود (es keeps falling back to the English brand names, as the copy-check test requires). Regression test: `BrandingForm.test.tsx` "in Arabic › labels LinkedIn, Snapchat and SoundCloud in Arabic". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-500-after.png` (لينكدإن / سناب شات / ساوند كلاود). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-502: Branding: logo, favicon and share-image pickers are bare native file inputs with no preview of the current image and no format/size hint
- **Feature:** M12 Settings (website branding). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-003); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/website/branding`; look at الشعار / أيقونة الموقع / صورة المشاركة.
- **Expected:** A styled upload control in the page language, a preview of the current image, and the allowed types/size.
- **Actual:** Three raw `<input type=file>` boxes ("No file chosen Choose File" in an English-language browser), no preview, no hint.
- **Evidence:** `qa/manual/screens/M12/M12-F-003-file-inputs-english.png`, `qa/manual/screens/M12/triage/t001-colour-error.png`
- **Notes:** The button wording of a native file input follows the browser's language, so an Arabic Chrome shows Arabic; the missing preview/hint holds in any browser. Logo upload itself was not exercised (Agent 1: not covered).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-503: Features page tells the academy an off feature "تعمل عند بنائها" (works once it is built)
- **Feature:** M12 Settings (features). **Severity:** P4. **Type:** copy. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-004); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/features`, scroll to المالية.
- **Expected:** An off feature reads as off (and, ideally, who to contact to switch it on); internal build status is not shown to customers.
- **Actual:** "نظام الحصص المجانية للمشتركين" (and "نظام الروابط العامة") show "متوقفة" with the note "تعمل عند بنائها".
- **Evidence:** `qa/manual/screens/M12/M12-F-004-features-built-copy.png`, `qa/manual/screens/M12/triage/t004-features-built.png`
- **Notes:** feature-toggles.md: `built=False` switches (`free_sessions`, `public_links`) are an Etqan-console notion; the academy's read-only list exposes it. Contact/request link is a suggestion, not part of the bug.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-504: Role editor is an ~11,000 px wall of 1,892 checkboxes, 592 of them "(غير مستخدم بعد)"; columns don't line up between groups
- **Feature:** M12 Settings (roles). **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-005); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/roles` → "إضافة دور" (`/app/settings/roles/new`).
  2. Scroll through the الموارد tab.
- **Expected:** Only permissions that do something, in a compact grid where each action sits in the same column for every resource.
- **Actual:** Page height 10,960 px (24,788 px on a 375 phone, Agent 1); 592 labels say "(غير مستخدم بعد)" ("إجبار حذف أي", "استنساخ", …); because unused verbs take slots, "عرض"/"عرض الكل"/"تعديل" land in different columns per group (e.g. الوسوم, الدخول السريع).
- **Evidence:** `qa/manual/screens/M12/M12-F-005-role-matrix-unused.png`, `qa/manual/screens/M12/M12-F-005c-role-editor-mobile.png`, `qa/manual/screens/M12/triage/t005-role-editor.png`
- **Notes:** The registry exposes `in_use` per verb (roles-permissions.md), so hiding unused verbs and fixing a column per verb is possible client-side, but it reshapes the editor (not easy). Related to ETQAN-QA-021/024 (role editor limits) but a different defect.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-505: Role editor never explains "عرض" vs "عرض الكل": a role with teachers "عرض" only opens nothing
- **Feature:** M12 Settings (roles). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-006); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`; staff qa-staff-nocode@qa.etqan.test / `QA-People-2026!`.
- **Reproduction steps:**
  1. Admin AR: give role "M12 مشاهد الطلاب" (student view + view_any, teacher view) to QA Staff NoCode (`/app/people/staff` → تعديل).
  2. Sign in as qa-staff-nocode@ and open `/app/people/teachers`.
- **Expected:** Either the editor states that "عرض" opens one record and the list needs "عرض الكل", or ticking "عرض" gives a usable result.
- **Actual:** Sidebar has no المعلمون; the URL shows "ليس لديك صلاحية الوصول إلى هذه الصفحة." Nothing in the editor tells the owner why.
- **Evidence:** `qa/manual/screens/M12/M12-F-006-teacher-view-no-access.png`, `qa/manual/screens/M12/triage/t006-teacher-view-no-access.png`
- **Notes:** Permission behaviour is as designed (view = detail, view_any = list); the defect is the missing explanation (a legend / hint under the matrix). Test state undone: nocode back to no roles.
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: the role editor shows the registry's verb labels with no legend; `view` (one record) vs `view_any` (the list and its menu item) is by design but never explained. Fix: a hint above the Resources matrix (`access.roles.verbHint`, ar/en/es): «عرض» يفتح سجلًا واحدًا…، و«عرض الكل» يفتح القائمة وعنصرها في القائمة الجانبية. اختر الاثنين…. Permission behaviour unchanged. Regression test: `RoleEditor.test.tsx` "in Arabic › explains عرض against عرض الكل above the matrix". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-505-after.png` (hint above matrix, as nocode), `qa/manual/screens/M12/fix/g041-role-edit-mobile.png` (375 px). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-506: Role editor: the anti-escalation refusal is raw English "You can only add permissions you hold yourself." shown ~9,000 px below the box that caused it
- **Feature:** M12 Settings (roles). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-007); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** staff qa-staff-nocode@ holding a role with role.* + student.view/view_any + teacher.view.
- **Reproduction steps:**
  1. As that staff member (AR) open `/app/settings/roles/new`, fill both names.
  2. In الفواتير tick "عرض الكل" (y≈1,560 px), click "حفظ الدور".
- **Expected:** An Arabic refusal near the box (or the toast/scroll to the error), ideally naming the codes the user doesn't hold; ungrantable boxes disabled or marked.
- **Actual:** 403 `POST /api/v1/access/roles/`; ".You can only add permissions you hold yourself" in English under the last group (page at scrollY 10,060), nothing marks the offending box; all groups stay tickable although the user holds 9 codes.
- **Evidence:** `qa/manual/screens/M12/M12-F-007-role-escalation-msg-english.png`, `qa/manual/screens/M12/triage/t007-escalation-after-save.png`
- **Notes:** Server text from `backend/etqan/access/services.py:122` (also 126, 207, 265, 271, 295, 313 for the sibling refusals). Easy part: translate the message and show it at the top / as a toast. Disabling ungrantable codes is a follow-up proposal.
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: `access/services.py` refuses with a fixed English sentence on `permissions`; `RoleEditor` showed that field error as is, after the last matrix group (far from the boxes and the top). Fix (dashboard only): the four refusal sentences map to i18n keys in `lib/server-messages.ts` (`access.roles.errors.addUnheld|removeUnheld|retireUnheld|restoreUnheld`, ar/en/es), the permissions error now sits above the tabs, a refusal not on a name field is also toasted (visible by Save), and the changed codes the staff editor doesn't hold are named (`access.roles.errors.unheldList`: "صلاحيات لا تملكها: الفواتير: عرض الكل."). Disabling ungrantable boxes + an API code: proposal in coverage-gaps.md. Regression tests: `RoleEditor.test.tsx` "in Arabic › says the refusal in Arabic above the matrix and names the codes the editor lacks" and the updated "shows the server's refusal…" (field + toast). Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-506-after.png` (BEFORE/AFTER; the toast by Save also shows), `qa/manual/screens/M12/fix/ETQAN-QA-506-after-top.png` (AR refusal above tabs + "صلاحيات لا تملكها: الفواتير: عرض الكل."); 403, no role created. BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-507: Retiring a role ("إيقاف") strips every member's access on one click, with no confirmation
- **Feature:** M12 Settings (roles). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-008); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/roles`, filter نشط, click "إيقاف" on a role with members (here "M12 مشاهد الطلاب", 1 member).
  2. As the member, open `/app/`.
- **Expected:** A confirm dialog naming the role and how many staff lose access.
- **Actual:** No dialog; toast "أُوقف الدور. يبقى لأعضائه لكنه لا يمنح شيئًا."; the member's Home now says "لا تفتح أدوارك أي شاشة بعد." "استعادة" is also one-click.
- **Evidence:** `qa/manual/screens/M12/M12-F-008-role-retire-no-confirm.png`, `qa/manual/screens/M12/triage/t008-retire-no-confirm.png`, `qa/manual/screens/M12/triage/t008b-member-lost-access.png`, `qa/manual/screens/M12/triage/t008a-restore-oneclick.png`
- **Notes:** Same pattern as ETQAN-QA-160/165/205/217 on other screens (the shared `components/Confirm.tsx` is available). Reversible by restore, so P3.
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: `RoleActiveToggle` (`features/access/RolesList.tsx`) sent `is_active:false` on the button click. Fix: retiring goes through the shared `components/Confirm.tsx` (outline trigger, same accessible name "إيقاف <name>"), titled "إيقاف <name>؟" and saying how many staff hold it (`access.roles.retireTitle|retireBody|retireBodyNone`, ar/en/es); restore stays one click (it gives access back). Regression tests: `RolesList.test.tsx` "retires and restores…" (nothing sent until confirmed) and "asks before retiring, naming the role and its members, in Arabic". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-507-after.png` (confirm "إيقاف M12 مشاهد الطلاب؟", 1 member), `qa/manual/screens/M12/fix/g030-retired.png` (retired via confirm), `qa/manual/screens/M12/fix/g010-restore.png` (restore one click). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-508: Roles list wording and order: status "متقاعد" vs action "إيقاف" / toast "أُوقف"; retired roles interleaved with active ones by default
- **Feature:** M12 Settings (roles). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-009); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/roles` (default filter "أي حالة").
- **Expected:** One word for state, action and toast (e.g. "موقوف"/"إيقاف"/"أُوقف"); active roles first (or default filter نشط).
- **Actual:** Status column "متقاعد" (a pensioner) beside "إيقاف"; the first page is mostly retired F03/test roles mixed with active ones; no search.
- **Evidence:** `qa/manual/screens/M12/M12-F-009-roles-list-wording.png`, `qa/manual/screens/M12/triage/t009-roles-list.png`
- **Notes:** Easy part: the Arabic status word. Sorting active-first and a search box are follow-ups.
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: `locales/ar/access.json` `roles.status.retired` (and `staff.retiredRole`) said "متقاعد" (a pensioner) beside the action "إيقاف". Fix: "موقوف" / "(موقوف)". Active-first order and a search box: proposal in coverage-gaps.md (changes the list API order). Regression test: `RolesList.test.tsx` "asks before retiring… in Arabic" (status reads موقوف, never متقاعد). Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-508-after.png` (نشط/موقوف + إيقاف/استعادة). Order part (active first) not changed: PROPOSAL-accepted (API list order, owner decides; filter نشط exists). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-509: Google sign-in: a client ID saves without the secret and shows "saved", while the card still says it isn't set up
- **Feature:** M12 Settings (sign-in). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-010); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (Google live BLOCKED, fake ID only).
- **Reproduction steps:**
  1. AR: `/app/settings/sign-in`, معرّف العميل = `m12t-test.apps.googleusercontent.com`, سر العميل empty, "حفظ".
  2. Reload.
- **Expected:** The form refuses a half setup when no secret is stored ("أدخل سر العميل أيضًا"), as the card text itself requires both.
- **Actual:** Saved toast; after reload the ID is stored while the card reads "تسجيل الدخول باستخدام Google غير مُعَدّ بعد: أدخل معرّف العميل وسر العميل كليهما."
- **Evidence:** `qa/manual/screens/M12/M12-F-010-google-half-saved.png`, `qa/manual/screens/M12/triage/t010-google-half-saved.png`, `qa/manual/screens/M12/triage/t010b-google-cleared.png`
- **Notes:** Restored to empty and verified after reload. Fix needs to know whether a secret is already stored (secret is write-only), hence not easy.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-510: System status: a failed run shows the English server text "Timed out." in the Arabic UI
- **Feature:** M12 Settings (system status). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-013); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/system-status`, look at "آخر عمليات التشغيل" (the 19/10/2026 1:15 ص failed run).
- **Expected:** An Arabic reason ("انتهت المهلة دون اكتمال التشغيل.") and what to do next.
- **Actual:** Red "فشل" with ".Timed out" (English, full stop mirrored).
- **Evidence:** `qa/manual/screens/M12/M12-F-013-system-status-timed-out.png`, `qa/manual/screens/M12/triage/t013-system-status-timed-out.png`
- **Notes:** Stored by `backend/etqan/systemstatus/services.py:29`. The other half of M12-F-013 (only manual runs listed) is by design: academy-settings.md says `systemstatus.run_job` is on demand only and the hourly lifecycle runs under `scheduling.run_daily`.
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: `systemstatus/services.py` stores the English "Timed out." (and `tasks.py` "Academy suspended.") on `JobRun.error`, and `SystemStatusPage` printed it. Fix (dashboard): those fixed reasons map to `systemStatus.failure.timedOut|suspended` (ar/en/es: "استغرق التشغيل وقتًا طويلًا فأُوقف. شغّله مرة أخرى."); any other exception text is shown as is. Durable `error_code`: proposal in coverage-gaps.md. Regression test: `SystemStatusPage.test.tsx` "words the server's fixed failure reasons for people". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-510-after.png` (failed run "استغرق التشغيل وقتًا طويلًا فأُوقف. شغّله مرة أخرى."). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-511: Registration codes (AR): the code floats on the far left of the card, away from its description on the right
- **Feature:** M12 Settings (registration codes). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-014); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/registration-codes` (code `m12-code-01`).
- **Expected:** In RTL the code is the card's title on the right above its description, as it is in EN.
- **Actual:** `m12-code-01` sits at x≈120 (left) next to the status pill while the description and "مرات الاستخدام المتبقية" are on the right.
- **Evidence:** `qa/manual/screens/M12/M12-F-014-reg-code-layout.png`, `qa/manual/screens/M12/M12-F-014b-reg-code-retired.png`, `qa/manual/screens/M12/triage/t014-reg-code-layout.png`
- **Notes:** Likely an LTR `dir`/`text-align:left` on the code element. No copy/edit/restore buttons are suggestions, not part of the bug.
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: in `registration/admin/CodesPage.tsx` the code `<span dir="ltr">` is a stretched flex-column item, so its LTR text starts on the left edge of an RTL card. Fix: `self-start max-w-full` keeps the code at the card's start (right in Arabic) above its description, still truncating. Regression test: `CodesPage.test.tsx` "keeps an LTR code at the start of its card…". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-511-after.png` (code at start above its description). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-512: Tags: the emoji field accepts any text ("abc" becomes the icon) and tags without an emoji start their name in the emoji column
- **Feature:** M12 Settings (tags). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-015); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/tags` → "إضافة وسم", الرمز التعبيري `abc`, names "M12 وسم اختبار"/"M12 test tag", save.
  2. Look at the list end.
- **Expected:** The field takes one emoji (or is refused); names line up whether or not a tag has an emoji.
- **Actual:** "abc  M12 وسم اختبار"; "QA5 وسم", "QA5 متقاعد", "ب adm" start in the emoji slot so names are ragged.
- **Evidence:** `qa/manual/screens/M12/M12-F-015-tag-emoji-text.png`, `qa/manual/screens/M12/triage/t015-tags-emoji-text.png`
- **Notes:** Agent 1's test tag left retired. One-click retire of a tag keeps it on holders (low impact); not filed separately.
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: neither `tagFormSchema` nor `identity.services.create_tag/update_tag` checked what the emoji field holds (only its length), and `TagsSettings` rendered an empty emoji span with no width. Fix: the same rule on both sides, no letters and at least one pictograph/flag/keycap (Unicode So/Me): `people/schemas.ts isEmoji` + `people.tags.errors.emojiInvalid` (ar/en/es), and `identity/services.py _check_emoji` (400 on `emoji`, checked only when the emoji is set/changed so older tags can still be renamed; the sentence is mapped in `server-messages.ts`); the row's emoji slot has a fixed width so names line up. No migration. Regression tests: pytest `identity/tests/test_tags_api.py` (`test_an_emoji_field_refuses_text_qa_512`, `…_takes_real_emoji_qa_512`, `test_an_older_text_emoji_still_lets_the_tag_be_renamed_qa_512`); Vitest `TagsSettings.test.tsx` "refuses text as an emoji, in Arabic, and keeps an empty emoji slot". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-512-after.png` (abc refused, AR message, nothing saved), `qa/manual/screens/M12/fix/ETQAN-QA-512-after-list.png` (names aligned); backend shell check in rollback: abc/ب refused, ⭐/🇸🇦/1️⃣ accepted. Legacy abc/ب tags stay (note accepted). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-513: Notification templates page has no side gutter: header and cards touch the sidebar (and the screen edge on a phone)
- **Feature:** M12 Settings (notification templates). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-016); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/notification-templates` at 1440x900; also 375x812.
- **Expected:** The same page frame as other settings pages (≈24 px gap, normal width).
- **Actual:** h1 right edge = 1184 = sidebar edge; cards span x 512–1184 flush against the sidebar; on a phone the title's first letter touches the edge.
- **Evidence:** `qa/manual/screens/M12/M12-F-016-templates-no-gutter.png`, `qa/manual/screens/M12/M12-F-016b-templates-mobile-edge.png`, `qa/manual/screens/M12/triage/t016-templates-no-gutter.png`
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: the route `routes/_authed/settings.notification-templates.tsx` rendered `PageHeader` + `TemplatesPage` in a bare fragment, without the `PageContainer` every other settings route uses (px-4 / sm:px-6, max width). Fix: wrap it in `PageContainer`. Regression test: new `routes/_authed/settings.notification-templates.test.tsx` "sits in the settings page frame, with a side gutter". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-513-after.png` (1440), `qa/manual/screens/M12/fix/ETQAN-QA-513-after-mobile.png` (375, 16 px gutter). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-514: Notification group heading "الجلسات" where the whole app says "الحصص"; English mixes "Sessions" and "Lessons"
- **Feature:** M12 Settings (notifications). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-017); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/notification-templates` (and the الإشعارات section of `/app/settings/academy`).
  2. EN: `/app/settings/academy` timezone warning and the generation fields.
- **Expected:** One term: "الحصص" in Arabic, one English word.
- **Actual:** First heading "الجلسات" over "تذكير مبكر بالحصة", "انتهاء الحصة"…; EN warning says "Lessons already on the schedule…" above "Generate sessions ahead (days)".
- **Evidence:** `qa/manual/screens/M12/M12-F-017-sessions-heading-academy.png`, `qa/manual/screens/M12/triage/t016-templates-no-gutter.png`, `qa/manual/screens/M12/s010.png`
- **Notes:** `dashboard/src/locales/ar/notifications.json:41` (`"session": "الجلسات"`).
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: `locales/ar/notifications.json` `groups.session` = "الجلسات"; `en/es academySettings.json` `timezoneChangeWarning` said "Lessons"/"clases" beside "Generate sessions ahead". Fix: "الحصص"; EN "Sessions…", ES "sesiones…" (matching nav). Regression tests: `TemplatesPage.test.tsx` "in Arabic › heads the session notices الحصص"; `AcademySettingsForm.test.tsx` still passes on the warning. Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-513-after.png` (AR heading الحصص), `qa/manual/screens/M12/fix/ETQAN-QA-514-after-en-tz.png` (EN warning "Sessions…", not saved), `qa/manual/screens/M12/fix/ETQAN-QA-514-after-en.png`. BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-515: Template editor: an unknown placeholder gives two errors, the one under the field in English, and neither names the bad placeholder
- **Feature:** M12 Settings (notification templates). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-018); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/notification-templates` → "تعديل" on "تذكير مبكر بالحصة".
  2. الرسالة = `تبدأ حصة {course} مع {student} في {time} {foo}` → "معاينة" (nothing saved).
- **Expected:** One Arabic message under the field naming `{foo}`.
- **Actual:** 400 `POST /api/v1/notifications/templates/preview/`; Arabic line at the top plus ".Use only these placeholders: {student}, {course}, {time}. Write {{ and }} for a brace" under the textarea.
- **Evidence:** `qa/manual/screens/M12/M12-F-018-template-error-english.png`, `qa/manual/screens/M12/triage/t018-template-error.png`, `qa/manual/screens/M12/triage/t018a-dialog.png`
- **Notes:** Server text `backend/etqan/notifications/services/templates.py:42`. Minor: "إلغاء" sits alone on a row below "حفظ"/"معاينة". The ISO time in the preview is the known ETQAN-QA-102 family (not re-filed).
- **Root cause / Fix / Regression tests (Agent 3, M12 fix cycle 1, 2026-10-28):** Root cause: the `notifications.bad_placeholder` 400 carries an English field sentence plus a code; `applyServerErrors` put the sentence under the field and the translated code at the top, so two messages, one English, neither naming the bad name. Fix (dashboard, `TemplateDialog.tsx`): on that code, one message under each refused field, in the reader's language, naming the unknown `{names}` found against the row's own placeholders (`notifications.templates.errors.unknownPlaceholder`, ar/en/es; falls back to the code's sentence); no form-level copy. API returning the names: proposal in coverage-gaps.md. Regression test: `TemplatesPage.test.tsx` "in Arabic › gives one Arabic error under the field, naming the bad placeholder". Branch `qa/manual-2026-10`; evidence `qa/manual/evidence/M12/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28; diff reviewed, Vitest 27 files/168 + locale 13 passed, tsc 0, pytest tags 40 passed). After: `qa/manual/screens/M12/fix/ETQAN-QA-515-after.png` (one AR error naming {foo}, preview only). BEFORE/AFTER composite in `qa/manual/screens/M12/fix/<BUG>-after.png` (raw AFTER `*-after-raw.png` where named).

---

## ETQAN-QA-516: Integrations page contradicts itself: subtitle says every service runs on Etqan's default, cards say there is none; video shows "غير مُعدّة" though Jitsi works; online payments has no status
- **Feature:** M12 Settings (integrations). **Severity:** P3. **Type:** copy. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-019); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (live keys BLOCKED; nothing entered).
- **Reproduction steps:**
  1. AR: `/app/settings/integrations` (and `/app/settings/gateways`, state only).
- **Expected:** One status per service that matches reality (e.g. video: "غرفة Jitsi مجانية"; payments: "مفاتيح Stripe الخاصة بك (تجريبي)").
- **Actual:** Subtitle "تعمل كل خدمة على حساب إتقان الافتراضي حتى تربط حسابك الخاص." vs 4 cards "لا تقدّم إتقان حسابًا افتراضيًا لهذه الخدمة بعد."; الاجتماعات المرئية red "غير مُعدّة" while its text says a free Jitsi room is used; الدفع الإلكتروني has no pill although Stripe test keys are saved on بوابات الدفع.
- **Evidence:** `qa/manual/screens/M12/M12-F-019b-integrations-status.png`, `qa/manual/screens/M12/M12-F-019-gateways-no-status.png`, `qa/manual/screens/M12/triage/t019-integrations.png`
- **Notes:** integrations.md: `using=none` → "not set up"; for video the Jitsi fallback makes `none` still working, so the card needs its own state/wording.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-517: Etqan billing: "878 مستخدمة · 0 مجانية · 0.00 US$ حتى الآن" can't be understood (no price, zero free yet zero cost) and the pay line gives no payment details
- **Feature:** M12 Settings (Etqan billing). **Severity:** P3. **Type:** copy. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M12 (M12-F-020); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/etqan-billing` (also qaother).
- **Expected:** Per service: free allowance, unit price (or "مجانًا حاليًا" when no price is set) and running amount; where/how to pay.
- **Actual:** "878 مستخدمة · 0 مجانية · $US 0.00 حتى الآن" (currency also mirrored in AR); "ادفع بتحويل بنكي أو بأي وسيلة تقبلها إتقان" with no details or contact.
- **Evidence:** `qa/manual/screens/M12/M12-F-020-etqan-billing-usage.png`, `qa/manual/screens/M12/triage/t020-etqan-billing.png`
- **Notes:** No `Price` row → amount 0 (etqan-billing.md). The usage API has no unit price, so the fix needs `current_prices` on this page (not easy). Invoice list / overdue banner NOT COVERED (no Etqan invoices exist).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-518: Branding (AR): the empty WhatsApp field's example reads "966501234567+", with the plus sign at the wrong end
- **Feature:** M12 Settings (website branding). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL (side effect of the verified ETQAN-QA-060 fix)
- **Found by:** Agent 1, manual M12 confirmation sweep (M12-F-022); reproduced by Agent 2 (final gate) on 2026-10-28.
- **Preconditions:** qaother-admin@qa.etqan.test / `QA-Other-2026!`, academy `qaother`, WhatsApp field empty.
- **Reproduction steps:**
  1. AR: `/app/website/branding` (الهوية), look at the empty "رقم واتساب" field.
- **Expected:** The example reads "+966501234567", the way the admin has to type it.
- **Actual:** It shows "966501234567+". The input has `unicode-bidi: plaintext; direction: rtl`. The placeholder has no strong letter, so it takes the page's RTL direction and the leading "+" moves to the end. A typed value "+966501234567" displays correctly (LTR), so only the example is wrong. That can still lead an admin to copy the wrong format.
- **Evidence:** `qa/manual/screens/M12/M12-F-022-whatsapp-placeholder-plus.png`, `qa/manual/screens/M12/triage/fg022-whatsapp-field.png`, `qa/manual/screens/M12/triage/fg022-branding-form.png`, typed value OK: `qa/manual/screens/M12/triage/fg022b-whatsapp-typed.png`
- **Notes:** `dashboard/src/features/website/BrandingForm.tsx:353` `placeholder="+966501234567"`. The same pattern is likely in `features/registration/RegisterForm.tsx:278` (`+201001234567`), but that screen wasn't opened. Fix idea: give phone or number inputs `dir="ltr"` (or `type="tel"` with LTR placeholder styling), or prefix the placeholder with U+200E. Don't change the shared `Input` plaintext rule, because ETQAN-QA-060 depends on it.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## --- M10 manual bugs ---

## ETQAN-QA-600: Chat "محادثة جديدة" (New conversation) picker has no close or Cancel button
- **Feature:** M10 Chat. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-001); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (same for teacher/student).
- **Reproduction steps:**
  1. AR: open `/app/chat`.
  2. Click "محادثة جديدة".
- **Expected:** A visible ✕ or "إلغاء" to leave the picker without choosing anyone.
- **Actual:** The dialog has only the title, a search box and the list of people; no close or cancel control (only Esc or a click outside).
- **Evidence:** `qa/manual/screens/M10/M10-F-001-new-chat-dialog-no-close.png`, `qa/manual/screens/M10/triage/t001-new-chat-dialog.png`
- **Notes:** Same pattern as ETQAN-QA-254/401/212 (dialogs without Cancel), new dialog (`dashboard/src/features/chat/ContactsPicker.tsx`).
- **Root cause:** `ContactsPicker.tsx` rendered only title, search and list; no `DialogClose` control was ever added.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** A `DialogFooter` with an outline "إلغاء"/"Cancel" `DialogClose` (same pattern as QA-254/401); key `chat.contacts.cancel` (ar/en; chat has no es file, falls back to en).
- **Regression test:** `features/chat/ContactsPicker.test.tsx` "closes with a visible Cancel (ETQAN-QA-600)". Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR+EN: Cancel visible under the list; click closes the dialog (0 dialogs left), nothing started. Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-600-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-601: Chat thread is not its own scrolling panel: a long message or a few messages push the composer below the screen
- **Feature:** M10 Chat. **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-002); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`; conversation `c=1` (admin↔teacher) with 7+ messages.
- **Reproduction steps:**
  1. AR, 1440x900: open `/app/chat?c=1`.
  2. Measure the composer: `textarea.getBoundingClientRect().bottom`.
- **Expected:** The message list scrolls inside its own panel; the composer stays visible at the bottom.
- **Actual:** The whole page grows; composer bottom at 950 px on a 900 px window (cut at the bottom edge). After a 3,000-character message the composer is entirely below the fold and the user must scroll the page to type.
- **Evidence:** `qa/manual/screens/M10/M10-F-002-thread-pushes-composer-offscreen.png`, `qa/manual/screens/M10/s007.png`, `qa/manual/screens/M10/triage/t002-chat-thread.png`
- **Notes:** `dashboard/src/features/chat/Thread.tsx` / `ChatPage.tsx`: give the panes a viewport-bound height with `overflow-y-auto` on the message list; keep scroll-to-newest behaviour.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-602: Every own chat message carries a large solid red "حذف" (Delete) button, always visible
- **Feature:** M10 Chat. **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-003); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. Open `/app/chat?c=1`; look at your own messages.
- **Expected:** Delete reachable on each own message (spec B5e) but quiet: a small icon/menu or on hover.
- **Actual:** Each own bubble has a solid red "حذف" button under the text; a conversation becomes a column of red buttons (a confirmation does exist). Same red buttons in People → الرسائل.
- **Evidence:** `qa/manual/screens/M10/M10-F-003-red-delete-on-every-message.png`, `qa/manual/screens/M10/triage/t002-chat-thread.png`
- **Notes:** Delete itself is by design (B5e: delete on your own messages); only the styling is the bug. Same family as ETQAN-QA-301/214.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-603: Chat attachment size shows as "B 193" glued to the file name; unit untranslated
- **Feature:** M10 Chat. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-004); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`; conversation `c=1` has the PDF "M10-خطة الدرس.pdf" (193 bytes).
- **Reproduction steps:**
  1. AR: open `/app/chat?c=1`, look at the attachment line.
- **Expected:** "M10-خطة الدرس.pdf · 193 بايت" (Arabic unit, separated, isolated).
- **Actual:** "B 193 M10-خطة الدرس.pdf": English "B", number and unit reversed, sitting next to the name like part of it. In EN the Arabic file name is reordered ("M10-خطة الدرس.pdf" → "خطة الدرس.pdf-M10").
- **Evidence:** `qa/manual/screens/M10/M10-F-004-attachment-size-B.png`, `qa/manual/screens/M10/triage/t002-chat-thread.png`, `qa/manual/screens/M10/triage/t007-en-chat.png`
- **Notes:** `dashboard/src/features/chat/Thread.tsx` attachment row: localise the size (Intl unit / translation keys), isolate name and size (`<bdi>`/`dir=auto`).
- **Root cause:** `chat/schemas.ts formatSize()` returned hard-coded English `"193 B"`/`KB`/`MB`; `Thread.tsx DownloadLink` put it in a bare span right after the name, so in RTL the LTR run `193 B` reversed to "B 193" and read as part of the name.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `formatSize(bytes, t, locale)` now formats the number with `Intl.NumberFormat` and the unit through `chat.attachments.size.{b,kb,mb}` ("193 بايت"); the size is a `<bdi>` after a "·" separator. The file name keeps `dir=auto` (Latin-led names stay LTR by design, see QA-604 note).
- **Regression test:** `features/chat/Thread.test.tsx` "shows the size in Arabic, isolated from the name (ETQAN-QA-603)"; the EN "1.5 KB" test still passes. Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR: "193 بايت · M10-خطة الدرس.pdf" (unit Arabic, separated, isolated); EN "193 B". Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-603-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-604: Chat message text takes the page direction: Latin-led or mixed text is mirrored in AR ("!Thanks"), Arabic messages are scrambled in EN
- **Feature:** M10 Chat. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-005 (+F-007)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`; AR and EN sessions; conversation `c=1` has "وعليكم السلام، تم الاستلام. Thanks!" and Arabic messages.
- **Reproduction steps:**
  1. AR: open `/app/chat?c=1` (also the conversation list preview and People → الرسائل).
  2. EN: open the same thread.
- **Expected:** Each message (and its preview) shown in its own direction (`dir="auto"`), readable as typed.
- **Actual:** AR: "وعليكم السلام، تم الاستلام. Thanks!" shows "…!Thanks"; moderation row the same; "M15-…؟" mirrored. EN: ".السلام عليكم … بالعربية" (full stop on the wrong side), "!Thanks .وعليكم السلام…", group name "مجموعة حلقة التجويد-M10".
- **Evidence:** `qa/manual/screens/M10/M10-F-005-latin-punctuation-mirrored.png`, `qa/manual/screens/M10/M10-F-007-en-ui-arabic-messages-scrambled.png`, `qa/manual/screens/M10/triage/t002-chat-thread.png`, `qa/manual/screens/M10/triage/t007-en-chat.png`, `qa/manual/screens/M10/triage/t032-moderation.png`
- **Notes:** Same class as ETQAN-QA-060/153 (fixed for inputs/people tables), not covered there: chat bubbles, conversation list excerpts, group names, moderation message column (`features/chat/Thread.tsx`, `ConversationList.tsx`, `MessagesModerationPage.tsx`). M10-F-007 is the same root cause and is folded in here.
- **Root cause:** Checked: every place named already has `dir="auto"` (bubble body and sender in `Thread.tsx`, title and preview in `ConversationList.tsx`, body in `MessagesModerationPage.tsx`, group name in `GroupsPage.tsx`, and the composer `Textarea`). `dir=auto` sets each message's paragraph direction from its first strong letter (HTML/UAX #9). "وعليكم السلام، تم الاستلام. Thanks!" is an RTL paragraph, so the final "!" sits at the left end, after "Thanks" in reading order: this is the correct RTL display, the same as in the composer while typing and in WhatsApp etc. A Latin-led message ("M15-…؟", "M10-…") is an LTR paragraph by the same rule. The EN screenshot shows the same per-message direction (Arabic bubbles are RTL in the EN UI). Changing the rule (e.g. majority-script direction) would be a product decision, not a bug fix.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** None (no code change).
- **Regression test:** n/a Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** NOT-A-BUG accepted. Every cited surface has `dir="auto"`; the renderings ("!Thanks" at the left end of an Arabic-led line, the Latin-led "M15-…؟" as LTR, the same group name in AR and EN) are the UAX #9 result of first-strong direction and match what the writer sees in the composer (`fix/gate/g600-603-en-after-cancel.png`). Majority-script direction would be a product change, not a defect.
- **Verification status:** NOT-A-BUG (accepted at gate)

---

## ETQAN-QA-605: "قرأها 0" (read by 0) under every own message in a one-to-one chat
- **Feature:** M10 Chat. **Severity:** P4. **Type:** copy. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-006); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. Send a message in a direct conversation; look under it before and after the other person reads it.
- **Expected:** In a two-person chat a simple state ("لم تُقرأ" / "مقروءة"); a count only in groups.
- **Actual:** "قرأها 0" then "قرأها 1" (EN "Read by 1"): reads like a counter in a two-person chat; "قرأها 0" is awkward Arabic.
- **Evidence:** `qa/manual/screens/M10/M10-F-006-read-by-zero-copy.png`, `qa/manual/screens/M10/triage/t002-chat-thread.png`
- **Notes:** Read counts on own messages are by design (B5e); only the wording for direct conversations is the bug.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-606: Chat contact picker labels every staff member "مشرف" / "Supervisor"
- **Feature:** M10 Chat. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-008); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-teacher@qa.etqan.test / `QA-People-2026!` (also admin, student).
- **Reproduction steps:**
  1. AR: `/app/chat` → "محادثة جديدة" → type "QA".
- **Expected:** Staff labelled with the app's word for them ("موظف" / "Staff", as the sidebar "الموظفون"), so a student or teacher can tell who is who.
- **Actual:** "QA Staff Codes", "QA Staff NoCode", "QA Staff pay" … all tagged "مشرف"; M04/M08 staff (receptionist, accountant) too. The moderation filter "نوع المرسل" also says "مشرف" for all staff.
- **Evidence:** `qa/manual/screens/M10/M10-F-008-all-staff-labelled-supervisor.png`, `qa/manual/screens/M10/triage/t008-staff-supervisor.png`
- **Notes:** chat.md: the role code `supervisor` = staff (internal code, by design); only the visible label is wrong: `dashboard/src/locales/ar/chat.json:113` `"supervisor": "مشرف"` (and EN).
- **Root cause:** The visible labels for the internal role code `staff`/`supervisor` (chat.md: `supervisor` = staff) were translated as "مشرف"/"Supervisor" in `locales/{ar,en}/chat.json` (`roles.staff`, `moderation.types.supervisor`).
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Both labels now read "موظف"/"Staff" (matching the sidebar "الموظفون"); codes unchanged.
- **Regression test:** `features/chat/ContactsPicker.test.tsx` "labels staff as Staff, not Supervisor (ETQAN-QA-606)". Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR "موظف" on every QA Staff row; EN "Staff". Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-606-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-607: Chat group dialog: the group image picker is the bare native "Choose File / No file chosen" control
- **Feature:** M10 Chat groups. **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-009); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/people/chat-groups` → "إضافة مجموعة".
- **Expected:** An Arabic "اختر صورة" button / drop area with a preview.
- **Actual:** Native file input text "Choose FileNo file chosen" (browser language, words glued) inside the Arabic dialog.
- **Evidence:** `qa/manual/screens/M10/M10-F-009-group-image-native-english-file-input.png`, `qa/manual/screens/M10/triage/t009-010-group-dialog.png`
- **Notes:** Same pattern as ETQAN-QA-502 (branding pickers), other screen (`features/chat/GroupDialog.tsx`).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-608: Chat group dialog: empty-name error is the raw English server text "A group name is 1 to 120 characters." in the Arabic UI
- **Feature:** M10 Chat groups. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-010); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/people/chat-groups` → "إضافة مجموعة" → "حفظ" with an empty name (400 `POST /api/v1/chat/groups/`).
- **Expected:** An Arabic field error (e.g. "اكتب اسم المجموعة (حتى 120 حرفًا)."), ideally checked before sending.
- **Actual:** ".A group name is 1 to 120 characters" (English, full stop mirrored).
- **Evidence:** `qa/manual/screens/M10/M10-F-010-group-name-error-english.png`, `qa/manual/screens/M10/triage/t009-010-group-dialog.png`
- **Notes:** Class of ETQAN-QA-157/206/358 (raw server message), new screen.
- **Root cause:** `GroupDialog.tsx` had no client check on the name and showed `errors.name.message` raw; the server's fixed English `ValidationError` ("A group name is 1 to 120 characters.", `chat/services/groups.py`) went straight to the field.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** The name is validated before sending (trimmed 1–120) with key `chat.groups.dialog.nameInvalid` ("اكتب اسم المجموعة (حتى 120 حرفًا)."), the field error goes through `useFieldError`, and the server sentence is mapped to the same key in `lib/server-messages.ts` (QA-157 pattern).
- **Regression test:** `features/chat/GroupsPage.test.tsx` "refuses an empty name in the reader's language, before sending" and "translates the server's group-name refusal" (ETQAN-QA-608). Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR: empty/blank name → "اكتب اسم المجموعة (حتى 120 حرفًا)." under the field, no POST sent. Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-608-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-609: Notification emails (AR): header and footer are left-to-right while the body is right-to-left; the call to action is a bare URL
- **Feature:** M10 Notifications email. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-014); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** Absence email to qa-parent (Mailpit id `0G2CxFZI562miw8eU1WwnK`); broadcast email `3iApTORq53mZZVYjU6hFC2`.
- **Reproduction steps:**
  1. Open `http://localhost:8025/view/0G2CxFZI562miw8eU1WwnK.html`.
- **Expected:** One consistent RTL email (header and footer `dir="rtl"`) and a "افتح"/"عرض" button instead of a raw link.
- **Actual:** Header "Etqan QA Academy" and footer left-aligned (no `dir`), body `dir="rtl"`; "افتحه من هنا:" followed by the raw `http://qa.etqan.localhost/app/learning/sessions` link. Same in every notice/broadcast email.
- **Evidence:** `qa/manual/screens/M10/M10-F-014-absence-email-layout.png`, `qa/manual/screens/M10/triage/t014-absence-email.png`, `qa/manual/screens/M10/triage/t026-027-broadcast-email.png`
- **Notes:** Backend notification email template (`etqan/notifications/channels/email.py` + template): only the body cell carries `dir`/`lang`. ISO date/"(Africa/Cairo)" in the text is ETQAN-QA-102.
- **Root cause:** `templates/email/layout.html` set `dir`/`lang` only on the body cell, so the header and footer cells took the default LTR; the notification text template `email/notifications/message.{ar,en}.txt` ended with "افتحه من هنا:" plus the raw URL, which the HTML only `urlize`d.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `<html dir lang>` and the card table carry the email's direction (header/footer `text-align:start`); `site.emails.brand_email` takes optional `action_url`/`action_label` (backwards compatible): the HTML shows a branded button, the text part keeps "label:\nURL". `notifications/channels/email.compose` passes the link as the action (labels "افتحه من هنا"/"Open it here") instead of putting it in the body. Kept the parallel change on the same layout (single name when ar == en).
- **Regression test:** `backend/etqan/notifications/tests/test_email.py::test_an_arabic_email_is_rtl_throughout_with_an_open_button`; existing email/brand tests pass (link line still in the text body). Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** New gate broadcast email (Mailpit 0WkYYCGYNEEWHvzh3qCbX6): <html dir=rtl lang=ar>, header/footer right-aligned, "افتحه من هنا" button; text part keeps "افتحه من هنا:\nURL". Side effect filed as ETQAN-QA-623 (footer home URL now mirrored). Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-609-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-610: Notification template editor: "إلغاء" sits alone on its own row, opposite "حفظ"/"معاينة"
- **Feature:** M10 Notification templates. **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-017); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/notification-templates` → "تعديل" on "غياب الطالب".
- **Expected:** Save / Preview / Cancel together in one action row.
- **Actual:** Save + Preview on the right; Cancel on a separate line at the bottom-left.
- **Evidence:** `qa/manual/screens/M10/M10-F-017-template-dialog-cancel-alone.png`, `qa/manual/screens/M10/triage/t017-template-dialog.png`
- **Notes:** `dashboard/src/features/notifications/TemplateDialog.tsx`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-611: Notification log: a filter with no match says "لا توجد إشعارات بعد." (no notifications yet)
- **Feature:** M10 Notification log. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-020); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/people/notification-log` → النوع "غياب الطالب" → البريد الإلكتروني "فشل".
- **Expected:** "لا توجد إشعارات مطابقة." (as People → الرسائل says "لا توجد رسائل مطابقة.").
- **Actual:** "لا توجد إشعارات بعد." Filters are also not kept in the URL (as ETQAN-QA-372).
- **Evidence:** `qa/manual/screens/M10/M10-F-020-log-filter-empty-says-none-yet.png`, `qa/manual/screens/M10/triage/t020-log-empty-filter.png`
- **Notes:** Same pattern as ETQAN-QA-152/306/372, new screen (`features/notifications/NotificationLogPage.tsx`).
- **Root cause:** `NotificationLogPage.tsx` showed `broadcasts.log.empty` ("لا توجد إشعارات بعد.") for any empty page, filtered or not.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** With any filter set it shows the new `broadcasts.log.noMatch` ("لا توجد إشعارات مطابقة."). Filters-in-URL stays with ETQAN-QA-372.
- **Regression test:** `features/notifications/NotificationLogPage.test.tsx` "says no notices match when a filter finds none (ETQAN-QA-611)". Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR: type غياب الطالب + email فشل → "لا توجد إشعارات مطابقة." Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-611-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-612: Broadcasts: the audience field and column are labelled "الشخص المستهدف" (target person) for choices that are groups
- **Feature:** M10 Broadcasts. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-021); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/people/broadcasts` (filter label and table header), then "رسالة جماعية جديدة".
- **Expected:** "المستلمون" / "الفئة المستهدفة".
- **Actual:** "الشخص المستهدف" over "كل الفئات", "مديرو النظام", "مجموعة دراسية", "معلمون متعددون"….
- **Evidence:** `qa/manual/screens/M10/M10-F-021-broadcast-target-label.png`, `qa/manual/screens/M10/triage/t021-024-broadcast-list.png`, `qa/manual/screens/M10/triage/t022-composer.png`
- **Notes:** `dashboard/src/locales/ar/broadcasts.json`.
- **Root cause:** Arabic copy in `locales/ar/broadcasts.json` (`filter`, `columns.audience`, `composer.audience`) was "الشخص المستهدف" (one person) for group audiences.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** All three now read "الفئة المستهدفة".
- **Regression test:** `features/notifications/BroadcastsPage.test.tsx` "reads in Arabic: audience is a group label, reads are 'n من total' (ETQAN-QA-612/613)". Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR: filter, column and composer read "الفئة المستهدفة". Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-612-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-613: Broadcasts (AR): counters read backwards: "2000 / 0" characters, "3 / 0" read
- **Feature:** M10 Broadcasts. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-022); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`; broadcast "M10-بث…" to F10 group (3 recipients, 0 read).
- **Reproduction steps:**
  1. AR: `/app/people/broadcasts` → column "القراءة".
  2. "رسالة جماعية جديدة" → counter under the message.
- **Expected:** "0 / 2000" (or "0 من 2000") and "0 من 3".
- **Actual:** "2000 / 0" (and "2000 / 35" after typing) and "3 / 0" — reads as 2000 used of 0.
- **Evidence:** `qa/manual/screens/M10/M10-F-022-broadcast-counter-reversed.png`, `qa/manual/screens/M10/triage/t021-024-broadcast-list.png`, `qa/manual/screens/M10/triage/t022-composer.png`, `qa/manual/screens/M10/triage/t023-confirm.png`
- **Notes:** Numbers joined with "/" in an RTL run; use a translated pattern ("{n} من {max}") or isolate the run (`dir=ltr`). `BroadcastComposer.tsx`, `BroadcastsPage.tsx`.
- **Root cause:** `readCount` and `composer.counter` were `{{a}} / {{b}}`: in an RTL line the two numbers separated by " / " form separate runs and are laid out right-to-left, so "0 / 2000" displays as "2000 / 0".
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Arabic patterns are now "{{read}} من {{total}}" and "{{n}} من {{max}}" (English unchanged).
- **Regression test:** Same test as QA-612 ("2 من 5"). Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR: list "0 من 3", composer "66 من 2000". Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-613-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-614: Broadcast confirmation names only the audience kind ("مجموعة دراسية"), not which group
- **Feature:** M10 Broadcasts. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-023); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: "رسالة جماعية جديدة" → الشخص المستهدف "مجموعة دراسية" → "F10 group" → a message → "إرسال" (do not confirm).
- **Expected:** "تُرسل إلى: مجموعة دراسية · F10 group…" before an irreversible send (B5b: "Send, with a confirm naming the audience").
- **Actual:** "تُرسل إلى: مجموعة دراسية. لا يمكن تعديل الرسالة بعد إرسالها." — no group name (same for chosen people).
- **Evidence:** `qa/manual/screens/M10/M10-F-023-broadcast-confirm-no-group-name.png`, `qa/manual/screens/M10/triage/t023-confirm.png`
- **Notes:** A recipient-count preview is a B5b non-goal, so only the missing group/person name is filed. `BroadcastComposer.tsx`.
- **Root cause:** `BroadcastComposer.tsx` built the confirm text from `broadcasts.audiences.<kind>` only; the chosen group/people were never passed.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** The confirm uses `audienceText(kind, label)` with the selected study group's name (kept from the select) or the picked people as an `Intl.ListFormat` list, each name a bidi isolate.
- **Regression test:** `features/notifications/BroadcastComposer.test.tsx` (study group: "A study group · Morning circle"; students: "Several students · … Sara Student"). Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR: confirm reads "تُرسل إلى: مجموعة دراسية · F10 group." Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-614-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-615: Broadcasts: "فشل 0" is a red badge even when nothing failed
- **Feature:** M10 Broadcasts. **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-024); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/people/broadcasts` (list and "التفاصيل").
- **Expected:** Neutral or hidden failed chip when the count is 0.
- **Actual:** Red "فشل 0" next to green "مرسل 3" reads like an error.
- **Evidence:** `qa/manual/screens/M10/M10-F-024-failed-zero-red-badge.png`, `qa/manual/screens/M10/triage/t021-024-broadcast-list.png`, `qa/manual/screens/M10/triage/t025-026-detail.png`
- **Notes:** `BroadcastsPage.tsx` / `BroadcastDetail.tsx` status chips.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-616: Broadcast details (AR): the meta line scrambles the date with the group name ("2026/10/F10 group · 28")
- **Feature:** M10 Broadcasts. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-025); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/people/broadcasts` → "التفاصيل".
- **Expected:** "مجموعة دراسية · F10 group · 28/10/2026، 4:17 ص · QA Admin" with each part isolated.
- **Actual:** "مجموعة دراسية · 28 · 2026/10/F10 group، 4:17 ص · QA Admin" — the date is split around the Latin group name.
- **Evidence:** `qa/manual/screens/M10/M10-F-025-broadcast-detail-meta-scrambled.png`, `qa/manual/screens/M10/triage/t025-026-detail.png`
- **Notes:** Same pattern as ETQAN-QA-253/163 (who · when line), new screen: `features/notifications/BroadcastDetail.tsx` — wrap each part in `<bdi>`.
- **Root cause:** `BroadcastDetail.tsx` interpolated audience label, date and sender as plain text into `detail.meta`; in the RTL line the Latin group name and the date's digits/slashes merged into one bidi run and the date split around "F10 group".
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `isolate()` (FSI…PDI) in `BroadcastDetail.tsx`: `audienceText` isolates the stored label, the meta isolates the date and the sender.
- **Regression test:** `features/notifications/BroadcastDetail.test.tsx` "names the chosen person after the audience" (asserts each part is isolated); `BroadcastsPage.test.tsx` audience cell. Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR detail meta: "مجموعة دراسية · F10 group · 2026/10/28، 4:17 ص · QA Admin", date intact. Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-616-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-617: Broadcast message body is laid out in the page direction: a Latin-led mixed message is reordered in the details box and the email
- **Feature:** M10 Broadcasts. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-026); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`; broadcast "M10-بث: تذكير مهم … الساعة 5:00 PM. Please be on time 🙏".
- **Reproduction steps:**
  1. AR: broadcasts → "التفاصيل".
  2. Open the student's email `http://localhost:8025/view/3iApTORq53mZZVYjU6hFC2.html`.
- **Expected:** The message shown as typed (`dir="auto"` on the body, isolated inside the email).
- **Actual:** Details: "M10-" jumps to the end of the line glued to "5:00" ("…الساعة M10-5:00"); email: "…الساعة PM. Please be 5:00" then "on time" on the next line.
- **Evidence:** `qa/manual/screens/M10/M10-F-026-broadcast-body-reordered.png`, `qa/manual/screens/M10/triage/t025-026-detail.png`, `qa/manual/screens/M10/triage/t026-027-broadcast-email.png`
- **Notes:** Same idea as ETQAN-QA-604 (free text needs its own direction), different components: `BroadcastDetail.tsx`, broadcast list excerpt, and the email body cell.
- **Root cause:** Dashboard: details box and list excerpt already use `dir="auto"`, which is the same rule the composer textarea uses, so the details show the message exactly as it looked while typing (a Latin-led message is an LTR paragraph; not a bug, see QA-604). Email: the broadcast body sat inside the `dir=rtl` body cell, so the Latin-led line was reordered differently from the dashboard ("PM. Please be 5:00").
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `notifications/channels/email.compose`: for `broadcast` notices each line of the typed message is a first-strong isolate (`text.isolate`), so it keeps its own direction in the email like `dir=auto` in the dashboard. Templated notices unchanged.
- **Regression test:** `backend/etqan/notifications/tests/test_email.py::test_a_broadcast_line_keeps_its_own_direction`. Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** Email: each typed line is an FSI…PDI isolate (text and HTML); Latin-led line laid out LTR. Dashboard half accepted as Unicode-correct with dir=auto (the "M10-5:00" adjacency is UAX #9 W2: a European number after Arabic letters becomes an Arabic number), same as the writer's composer. Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-617-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-618: "تغيير التشغيل والتوقيت" on the templates page opens Academy settings at the top, not at the notifications section
- **Feature:** M10 Notification templates. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-029); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/settings/notification-templates` → link "تغيير التشغيل والتوقيت".
- **Expected:** Lands scrolled to "الإشعارات" (e.g. `/settings/academy#notifications`).
- **Actual:** `/app/settings/academy` at scrollY 0 (time zone, currency…); the notifications heading is at 1,443 px on a 5,029 px page.
- **Evidence:** `qa/manual/screens/M10/M10-F-029-templates-link-lands-top.png`, `qa/manual/screens/M10/triage/t029-settings-link.png`
- **Notes:** `TemplatesPage.tsx` link + an id/hash scroll on the notifications section of `settings.academy`.
- **Root cause:** `TemplatesPage.tsx` linked to `/settings/academy` with no anchor and the notifications section had no id; the section also renders below a form that loads first, so a plain hash could land early.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Link now goes to `/settings/academy#notifications`; `NotificationSettingsForm` has `id="notifications"` and scrolls itself into view once its settings have loaded when the hash is `notifications`.
- **Regression test:** `TemplatesPage.test.tsx` (href with `#notifications`); `NotificationSettingsForm.test.tsx` "scrolls to itself when the page opens at #notifications" / "does not scroll without the anchor" (ETQAN-QA-618). Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z): REOPENED.** The link now carries `#notifications`, but clicking it on the templates page (AR and EN, 4 of 5 runs) lands at scrollY 259 with the section 1,184 px down (off screen, `qa/manual/screens/M10/fix/ETQAN-QA-618-after.png`, `fix/gate/g618-ar-retry2.png`). Only a direct page load of `/app/settings/academy#notifications` lands near it (top −95 px). Likely cause: on in-app navigation the notification settings are ready before the academy form above has rendered, so `scrollIntoView` fires and the form then pushes the section down; scroll again after the page's content above has settled (or once both queries are ready). The jsdom test cannot see this.
- **Final gate (Agent 2, 2026-10-28T12:27:00Z):** re-tested with in-app navigation from the templates page, AR and EN (plus Agent 1's sweep): section top 0 every time (AR scrollY 1443, EN 1485). Same fix code as cycle 1 (no new change); the earlier 4-of-5 misses did not recur — if it comes back, the fix idea above (scroll after the form above settles) still applies. After: `qa/manual/screens/M10/triage/fg618-retest.png`, `qa/manual/screens/M10/triage/fg618-retest-en.png`.
- **Verification status:** VERIFIED (final gate)

---

## ETQAN-QA-619: Every notification type offers "أرسل على واتساب" with no hint that WhatsApp isn't set up (Integrations: "غير مُعدّة")
- **Feature:** M10 Notification settings. **Severity:** P3. **Type:** copy. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-030); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`; feature `whatsapp` on, no WhatsApp account (Integrations shows "غير مُعدّة").
- **Reproduction steps:**
  1. AR: `/app/settings/integrations` (WhatsApp not set up).
  2. `/app/settings/academy` → الإشعارات.
- **Expected:** While no WhatsApp account resolves, a hint such as "واتساب غير مربوط؛ لن يُرسل شيء حتى تربطه" (with a link to Integrations), or the boxes disabled.
- **Actual:** 22 enabled "أرسل على واتساب" boxes, nothing says messages will be skipped; the teacher's Account also shows a WhatsApp card.
- **Evidence:** `qa/manual/screens/M10/M10-F-030-whatsapp-option-while-not-set-up.png`, `qa/manual/screens/M10/M10-F-030b-integrations-whatsapp-not-set-up.png`, `qa/manual/screens/M10/triage/t030-whatsapp-boxes.png`
- **Notes:** The per-type column itself is by design (B5c: deliveries are `skipped` until an account exists); the missing explanation is the bug. Needs the integration status in the form (not a one-line fix). Related: ETQAN-QA-516.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-620: Phone (375): the bell panel runs flush against the right screen edge
- **Feature:** M10 Bell (mobile). **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-031); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-parent@qa.etqan.test / `QA-People-2026!`.
- **Reproduction steps:**
  1. AR, 375x812: `/app/` → bell.
- **Expected:** Panel inset from both edges (collision padding) or a full-width sheet.
- **Actual:** Panel left 55 px, right 375 px (= screen width): no right margin, border cut by the edge.
- **Evidence:** `qa/manual/screens/M10/M10-F-031-mobile-bell-panel-edge.png`, `qa/manual/screens/M10/triage/t031-mobile-bell.png`
- **Notes:** Residual of ETQAN-QA-104 (which fixed the RTL direction/placement): `NotificationBell.tsx` DropdownMenu.Content needs `collisionPadding`/`max-w-[calc(100vw-2rem)]`.
- **Root cause:** `NotificationBell.tsx` `DropdownMenu.Content` used Radix's default `collisionPadding` 0: when the 20rem panel is shifted to fit a 375 px screen it is pushed flush to the edge.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `collisionPadding={BELL_EDGE_GAP}` (16 px, matching the existing `max-w-[calc(100vw-2rem)]`).
- **Regression test:** `NotificationBell.test.tsx` "keeps the panel inside the screen with a gap on both sides" (checks the width cap and the gap constant; the real geometry needs a 375 px browser check by Agent 2, jsdom has no layout). Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** AR 375x812: panel left 39, right 359 of 375 (16 px gap both sides). Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-620-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-621: A student whose "يمكنه بدء المحادثات" is off sees only "لا توجد محادثات بعد": the New conversation button disappears with no explanation
- **Feature:** M10 Chat. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-033); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`; QA Student Three (`qa-student3@qa.etqan.test` / `QA-People-2026!`, person 33).
- **Reproduction steps:**
  1. Admin: `/app/people/students/33` → untick "يمكنه بدء المحادثات".
  2. Student Three: `/app/chat`.
  3. Restore the switch.
- **Expected:** A line such as "لا يمكنك بدء محادثة جديدة؛ سيراسلك معلمك أو الأكاديمية."
- **Actual:** Only "لا توجد محادثات بعد" and "اختر محادثة لقراءتها."; no button and no reason.
- **Evidence:** `qa/manual/screens/M10/M10-F-033-student-cannot-start-no-explanation.png`, `qa/manual/screens/M10/triage/t033-student-cannot-start.png`
- **Notes:** Hiding the button is by design (B5e); the missing message is the bug (`features/chat/ChatPage.tsx` / `ConversationList.tsx`). Switch restored to on (verified after reload).
- **Root cause:** `ChatPage.tsx` rendered the New conversation button only when `can_start`, with nothing in its place otherwise.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** When `can_start` is false a short line takes its place: `chat.cannotStart` ("لا يمكنك بدء محادثة جديدة؛ يمكنك الرد عندما يراسلك معلمك أو الأكاديمية.").
- **Regression test:** `features/chat/ChatPage.test.tsx` "hides New conversation when the user may not start one" (now also checks the line) and "shows no can't-start line to someone who may start". Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** Student Three (can_start off): "لا يمكنك بدء محادثة جديدة؛ يمكنك الرد عندما يراسلك معلمك أو الأكاديمية." Switch restored on (DB can_start=t). Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-621-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-622: Student chat switches and own notification preferences save silently, with no confirmation
- **Feature:** M10 Chat / Notification preferences. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M10 (M10-F-034); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`; qa-teacher for Account.
- **Reproduction steps:**
  1. Admin AR: `/app/people/students/33` → click "يمكنه بدء المحادثات".
  2. Teacher: `/app/account` → tick/untick "إشعارات المحادثات".
- **Expected:** A short "تم الحفظ" toast (other screens show one, e.g. "تم حفظ المجموعة.").
- **Actual:** The box changes and nothing else (0 toasts); the save did happen (verified by reload).
- **Evidence:** `qa/manual/screens/M10/M10-F-034-switch-saved-silently.png`, `qa/manual/screens/M10/triage/t034-switch-silent.png`
- **Notes:** `features/chat/StudentChatCard.tsx`, `features/notifications/PreferencesCard.tsx`. Same family as ETQAN-QA-054/251.
- **Root cause:** `StudentChatCard.tsx` and `PreferencesCard.tsx` call `mutate` with only an error toast; success had no feedback.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** A success toast on each save: `chat.access.saved` ("تم حفظ إعدادات المحادثة.") and `notifications.preferences.saved` ("تم حفظ تفضيلات الإشعارات.", ar/en/es).
- **Regression test:** `StudentChatCard.test.tsx` "shows two switches and saves a change" and `PreferencesCard.test.tsx` "saves an own toggle" now expect the toast (ETQAN-QA-622). Evidence: `qa/manual/evidence/M10/fix-1/` (tsc.txt, vitest.txt, backend.txt, pytest-email.txt).
- **Gate (Agent 2, 2026-10-28T02:18:15Z):** Admin toggling "يمكنه بدء المحادثات" → toast "تم حفظ إعدادات المحادثة."; teacher "إشعارات المحادثات" → toast "تم حفظ تفضيلات الإشعارات." Both restored (DB checked). Before/after: `qa/manual/screens/M10/fix/ETQAN-QA-622-after.png`; gate shots `qa/manual/screens/M10/fix/gate/`; tests `qa/manual/evidence/M10/gate-1/`.
- **Verification status:** VERIFIED

---

## ETQAN-QA-623: Arabic emails: the footer's home link is mirrored ("/http://qa.etqan.localhost") since the email became RTL
- **Feature:** M10 Notifications email (all branded emails). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack, branch qa/manual-2026-10 (uncommitted QA-609 fix), Mailpit. **Tag:** REAL
- **Found by:** Agent 2 at the M10 gate (2026-10-28T02:18:15Z), side effect of the ETQAN-QA-609 fix.
- **Reproduction steps:**
  1. Send any notice/broadcast to an Arabic recipient (gate: broadcast "M10-gate…" to F10 group).
  2. Open it in Mailpit (`http://localhost:8025/view/0WkYYCGYNEEWHvzh3qCbX6.html`).
- **Expected:** The home URL reads `http://qa.etqan.localhost/` (LTR, isolated) inside the RTL footer.
- **Actual:** `/http://qa.etqan.localhost` — the trailing slash jumps to the front because the footer cell is now `dir="rtl"` and the link has no `dir="ltr"`. Before QA-609 the footer was LTR, so this is new. The contact email/phone in the same line will be affected likewise.
- **Evidence:** `qa/manual/screens/M10/fix/gate/g609-617-email-ar.png`, `qa/manual/screens/M10/fix/ETQAN-QA-609-after.png`
- **Notes:** Fix idea: `dir="ltr"` (or `<bdi>`) on the home link and the contact address/phone in `backend/etqan/templates/email/layout.html`.
- **Verification status:** OPEN

---

## ETQAN-QA-624: Bell / notifications page: a Latin-led mixed broadcast body is laid out in the Arabic title's direction ("PM. Please be on 6:00 موعد الحصة")
- **Feature:** M10 Bell / notifications page. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`. **Tag:** REAL
- **Found by:** Agent 1, M10 confirmation sweep (M10-F-035); reproduced by Agent 2 at the final gate, 2026-10-28.
- **Preconditions:** qa-student@qa.etqan.test / `QA-People-2026!`; broadcast "M10-gate: موعد الحصة 6:00 PM. Please be on time" + second line "سطر ثانٍ بالعربية." sent to F10 group at the M10 gate.
- **Reproduction steps:**
  1. AR, 375x812 (same at 1440): `/app/` → bell (or `/app/notifications`).
- **Expected:** Each typed line keeps its own direction, as in the broadcast details box (`dir=auto`, what the writer saw while typing) and in the email since ETQAN-QA-617.
- **Actual:** The whole body takes the direction of the Arabic title "رسالة جديدة" (one `dir="auto"` wrapper for title + body, ETQAN-QA-102), so the Latin-led first line is an RTL paragraph: "M10-gate: موعد الحصة" / "PM. Please be on 6:00" / "time" — the time and "PM" are split and the sentence reads out of order.
- **Evidence:** `qa/manual/screens/M10/M10-F-035-bell-broadcast-body-reordered.png`, `qa/manual/screens/M10/triage/fg035-bell-mobile.png`
- **Notes:** Residual of ETQAN-QA-617 (it fixed the email; the dashboard details box was already `dir=auto`). Component: `dashboard/src/features/notifications/bits.tsx` `NotificationText` (shared by bell and page). Fix idea: for `broadcast` notices only, give the body its own per-line direction (`unicode-bidi: plaintext` / a `dir="auto"` element per line), keeping the QA-102 single direction for templated notices. An Arabic-led line (the older "M10-بث: … 5:00 PM. Please be on time 🙏") renders the same as in the composer and is not a bug.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-625: Chat group dialog: saving with no participants shows the raw English server text "A group has 1 to 200 participants." in the Arabic UI
- **Feature:** M10 Chat groups. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`. **Tag:** REAL
- **Found by:** Agent 1, M10 confirmation sweep (M10-F-036); reproduced by Agent 2 at the final gate, 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/people/chat-groups` → "إضافة مجموعة" → name "M10-final مجموعة بلا مشاركين", tick nobody ("تم اختيار 0") → "حفظ" (400 `POST /api/v1/chat/groups/`, nothing created).
- **Expected:** An Arabic error under "المشاركون" (e.g. "اختر مشاركًا واحدًا على الأقل (حتى 200)."), ideally checked before sending like the name since ETQAN-QA-608.
- **Actual:** ".A group has 1 to 200 participants" in red (English, full stop mirrored).
- **Evidence:** `qa/manual/screens/M10/M10-F-036-group-participants-error-english.png`, `qa/manual/screens/M10/triage/fg036-group-no-participants.png`
- **Notes:** Residual of ETQAN-QA-608 (same dialog, same raw-server-message class as QA-157): the 608 fix mapped only the name sentence. Server text from `backend/etqan/chat/services/groups.py:76`; add a client check in `GroupDialog.tsx` and map the sentence (it carries `MAX_PARTICIPANTS`) in `dashboard/src/lib/server-messages.ts`.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-626: A chat conversation with no messages opens as a blank thread (no "no messages yet" line)
- **Feature:** M10 Chat. **Severity:** P4. **Type:** copy. **Easy P3:** no (P4). **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`. **Tag:** REAL
- **Found by:** Agent 1, M10 confirmation sweep (M10-F-037); reproduced by Agent 2 at the final gate, 2026-10-28.
- **Preconditions:** group "M10-sweep مجموعة التأكيد" (c=4, QA teacher + QA student, no messages); qa-student@qa.etqan.test.
- **Reproduction steps:**
  1. Student, AR 1440: `/app/chat?c=4`.
- **Expected:** A short empty-state line in the thread (the groups list already has `chat.groups.noMessages` "لا رسائل بعد").
- **Actual:** Group name header, a large empty area and the composer; the list item has no preview line either.
- **Evidence:** `qa/manual/screens/M10/M10-F-037-empty-group-thread-blank.png`, `qa/manual/screens/M10/triage/fg037-empty-group-thread.png`
- **Notes:** Cosmetic: the composer is visible and works, so the member is not stuck. `dashboard/src/features/chat/` thread component.
- **Verification status:** OPEN

---

## --- M15 manual bugs ---

## ETQAN-QA-450: Receipt after an online payment shows 1,500.00 paid while 1,575.00 was charged: the service fee is missing from the receipt
- **Feature:** M15 Student & parent portal, invoice receipt (`/app/invoices/<id>/print`) after a Stripe (simulated) payment. **Severity:** P2. **Type:** functional. **Easy P3:** no (P2). **Priority:** high
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL (payments SIMULATED)
- **Found by:** Agent 1, manual M15 (M15-F-003); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@qa.etqan.test / `QA-People-2026!`, academy `qa`; INV-000144 paid through the simulator (payment 110: amount 150000, fee_minor 7500).
- **Reproduction steps:**
  1. AR `/app/learning/invoices/144` → the payment line reads "1,500.00 ج.م. · Stripe · رسوم 75.00 ج.م.".
  2. "طباعة" → `/app/invoices/144/print`.
- **Expected:** the receipt ("إيصال") states what the payer was charged: 1,500.00 + service fee 75.00 = 1,575.00, so it matches the card statement (checkout dialog showed الإجمالي 1,575.00).
- **Actual:** the receipt lists "Stripe · 2026/10/28 — 1,500.00", المبلغ 1,500.00, المدفوع 1,500.00; the 75.00 fee appears nowhere. A parent comparing it with the bank statement sees 75 more charged than the receipt.
- **Evidence:** `qa/manual/screens/M15/M15-F-003-receipt-omits-service-fee.png`, `qa/manual/screens/M15/M15-F-003b-checkout-total-1575.png`, `qa/manual/screens/M15/triage/t004-inv144.png`, `qa/manual/screens/M15/triage/t005-inv144-print.png`
- **Notes:** Data is right (`billing_payment.fee_minor` = 7500; billing.md: fee stored per payment, revenue counts amount + fee); only the receipt omits it. Applies to every gateway payment with a fee (parent INV-000156 too).
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `billing/InvoicePrint.tsx` lists each payment's `amount_minor` and the totals Amount/Paid/Balance only; `fee_minor` (stored per payment, billing.md) was never read on the receipt (the invoice page shows it). Fix (dashboard only): each payment line adds "رسوم 75.00 ج.م." (`billing.payments.fee`), and when completed payments carry fees the totals add "رسوم الخدمة" and "إجمالي المبلغ المدفوع" (Paid + fees = 1,575.00); new keys `billing.print.serviceFees`/`totalCharged` in ar/en/es. Regression tests: `InvoicePrint.test.tsx` "shows an online payment's service fee and the total charged (ETQAN-QA-450)" and "shows no fee rows when no payment had a fee". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): student AR+EN `/app/invoices/144/print`: payment line '· رسوم 75.00 ج.م.', 'رسوم الخدمة 75.00' and 'إجمالي المبلغ المدفوع 1,575.00' / EN 'Service fees', 'Total charged EGP 1,575.00'. Diff reviewed (fees summed over completed payments only). Evidence `qa/manual/screens/M15/fix/ETQAN-QA-450-after.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-451: Abandoned consultation bookings look exactly like the paid one ("قيد المراجعة"), can't be paid or told apart, and are not auto-cancelled while their abandoned checkout is pending
- **Feature:** M15 Student/parent consultations (`/app/learning/consultations`, `my/book/`, `cancel_unpaid`). **Severity:** P2. **Type:** functional. **Easy P3:** no (P2). **Priority:** high
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL (payments SIMULATED)
- **Found by:** Agent 1, manual M15 (M15-F-019); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@, consultation product 1 "M15- استشارة خطة الحفظ" (200 EGP), teacher 228.
- **Reproduction steps:**
  1. `/app/learning/consultations/book?product=1` → teacher → slot → WhatsApp → "ادفع عبر Stripe" → "المتابعة إلى Stripe" → leave the simulator without paying. Repeat for a second slot.
  2. Book a third slot and pay in the simulator.
  3. `/app/learning/consultations`.
  4. DB: `consultations_request` 1–3 and their `gateways_checkout` rows; wait past `hold_until` + the 15-minute `consultations.cancel_unpaid` run.
- **Expected:** only the paid booking is listed as booked, or unpaid ones are clearly "بانتظار الدفع" with a Pay action and disappear when the 30-minute hold ends (consultations.md: "A booking holds its slot for 30 minutes while unpaid").
- **Actual:** three identical cards "M15- استشارة خطة الحفظ · … 19:00 · لـ QA student — قيد المراجعة"; cards are not clickable (no pay/detail). Requests 1–2 have no payment; their checkouts stay `pending`, so `unpaid.py:cancel_unpaid` skips them (`_checkout_open`: any pending checkout) until `gateways.expire_checkouts` expires checkouts older than 25 h — the family list (and the office queue) shows abandoned attempts as live requests for more than a day. Slots themselves are freed after 30 min (`common.live_q` ignores expired holds) — see Notes.
- **Evidence:** `qa/manual/screens/M15/M15-F-019-unpaid-consult-holds-look-booked.png`, `qa/manual/screens/M15/triage/t020-consult-list.png`, `qa/manual/screens/M15/triage/t031-consult-slots-after-hold.png`
- **Notes:** Agent 1's follow-up "expired holds still block slots" was taken at ~01:30 UTC, before the holds ended (01:41 UTC); Agent 2 rechecked at 01:41:56 UTC: 29/10 and 31/10 19:00 are offered again, 02/11 19:00 (paid) is not (t031). Date line uses a Latin comma "2026/11/02, 19:00" and "لـ QA student" renders "QA student لـ" (QA-100 family, not re-filed). Setup leftovers: requests 1–2 (M15, unpaid).
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `consultations/FamilyConsultations.tsx` shows only `statuses.<status>`, and an unpaid self-booking is `pending_review` like a paid one, so abandoned checkouts read "قيد المراجعة"; the payload already had `actions.pay` (and the card already links to the request page, whose Pay button exists) but the list never used it. The auto-cancel delay is the documented rule (`unpaid.py:_checkout_open` skips any pending checkout, consultations.md §5) and changing it touches the gateway flow, so it is a proposal (coverage-gaps.md § M15). Fix (dashboard only): a row with `actions.pay` shows a warning chip "بانتظار الدفع" and "ادفع الآن" instead of the status; keys `consultations.family.awaitingPayment`/`payNow` (ar/en; no es catalogue for consultations). Regression test: `FamilyConsultations.test.tsx` "tells an unpaid booking from the paid one and points to Pay (ETQAN-QA-451)". Partial: the ~25 h auto-cancel delay is left for the owner (proposal). Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (UI part) + PROPOSAL-accepted (auto-cancel rule) (Agent 2, 2026-10-28): AR desktop and 375 px: requests 1-2 show 'بانتظار الدفع' + 'ادفع الآن', the paid one 'قيد المراجعة'; 'ادفع الآن' → CR-000002 → 'ادفع عبر Stripe' → simulator 'ادفع' (SIMULATED, 200.00) → the list then shows CR-000002 'قيد المراجعة'; EN 'Awaiting payment / Pay now'. The ~25 h delay before abandoned bookings are cancelled is a documented rule (consultations.md §5) and a gateway-flow change, so the owner decides (coverage-gaps.md § M15 Agent 3 fix cycle 1). Accepted as a proposal because families can now tell unpaid from paid and pay. Minor: the request page still says 'الحالة: قيد المراجعة' above 'لم يُدفع بعد' (not re-filed). Evidence `qa/manual/screens/M15/fix/ETQAN-QA-451-after.png`, `qa/manual/screens/M15/fix/r451-mobile.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-452: Buying a paid recorded course (210.00 charged) leaves the family no receipt or invoice anywhere in the portal
- **Feature:** M15 Recorded-course store purchase (`recorded_course` purpose → standalone `billing.Payment`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL (payments SIMULATED)
- **Found by:** Agent 1, manual M15 (M15-F-017); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@; course 2 "M15- حفظ جزء عمّ (مدفوعة)" (250 → 200 EGP) bought through the simulator (payment 115, invoice NULL, 20000 + fee 1000).
- **Reproduction steps:**
  1. `/app/learning/recorded/store/2` → terms → "اشترِ عبر Stripe" → simulator "ادفع" → "تم الدفع — شكرًا لك.".
  2. Sidebar "الفواتير", "الرصيد", "دوراتي المسجلة".
- **Expected:** a receipt for the 210.00 purchase the family can open/print (as for invoices), or a purchases list.
- **Actual:** invoices list unchanged (newest INV-000144), wallet has no row, success page shows no amount or reference; only the office sees payment 115 (standalone record via `record_link_payment`). Same for paid consultations (payment 116).
- **Evidence:** `qa/manual/screens/M15/M15-F-017-course-purchase-no-receipt.png`, `qa/manual/screens/M15/triage/t003-invoices-list.png`, `qa/manual/screens/M15/triage/t015-store-nav.png`
- **Notes:** recorded-courses.md: purchase → `billing.services.record_link_payment` (no invoice). No family read of standalone payments exists, so the fix needs an API (proposal-sized).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-453: Family never sees what it owes: no total due / unpaid filter on the invoices list and nothing about money on Home (student or parent)
- **Feature:** M15 Family invoices list (`FamilyInvoices`) and family Home. **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-005, M15-F-023); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@ (INV-000143 partly paid + overdue 680.00, INV-000093/085/… unpaid + overdue); parent.najjar@.
- **Reproduction steps:**
  1. AR `/app/learning/invoices`.
  2. AR `/app/` as the same student, and as parent.najjar@.
- **Expected:** at a glance "المستحق عليك الآن: X" with the overdue invoice and a Pay action; unpaid first or a filter.
- **Actual:** (1) a flat list by number, paid/void/partly paid/unpaid mixed, no total outstanding, no filter, no Pay button on the cards. (2) Home shows next lesson + subscription cards + tiles; no amount due or overdue invoice even with several overdue invoices.
- **Evidence:** `qa/manual/screens/M15/M15-F-005-invoice-list-no-total-owed.png`, `qa/manual/screens/M15/M15-F-023-parent-home-no-money-due.png`, `qa/manual/screens/M15/triage/t003-invoices-list.png`, `qa/manual/screens/M15/triage/t027-student-home-overdue.png`, `qa/manual/screens/M15/triage/t026-parent-home.png`
- **Notes:** Card description/amount was added by ETQAN-QA-316. The parent tile "قيّم حصصك" is ETQAN-QA-115 (reopened), not re-filed.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-454: Family "حصصي" past lessons with no attendance still show the green "مجدولة", identical to future ones
- **Feature:** M15 Family sessions (`scheduling/FamilySessions.tsx`, past card). **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-001); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@.
- **Reproduction steps:**
  1. AR `/app/learning/sessions` → "الحصص السابقة".
- **Expected:** a past lesson nobody marked reads as such ("لم يُسجَّل الحضور" / "بانتظار تسجيل الحضور"), not as scheduled.
- **Actual:** 26/10, 25/10, 22/10, 21/10 … carry the same green "مجدولة" as upcoming lessons. Marked lessons do show attendance as plain text ("غائب" 28/10 03:30/03:45, "حاضر" 19/10 19:48), so the spec §6 "past ones with the attendance" works for marked lessons only.
- **Evidence:** `qa/manual/screens/M15/M15-F-001-past-sessions-scheduled-no-attendance.png`, `qa/manual/screens/M15/triage/t001-sessions-ar.png`
- **Notes:** Family twin of ETQAN-QA-412 (teacher history), different component. Agent 1's "attendance never shown" is not accurate: it is shown once marked.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-455: Subscription cards: "0 من 8 حصص" doesn't say used or left; no remaining count or start date
- **Feature:** M15 Family subscriptions + Home subscription cards. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-002); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@ (also parent.najjar@).
- **Reproduction steps:**
  1. AR `/app/learning/subscriptions`.
- **Expected:** "استُخدمت 2 من 8 · متبقية 6" (the API has `sessions_remaining`, subscriptions.md) and the period start.
- **Actual:** "0 من 8 حصص" / "2 من 8 حصص" with a bar and "ينتهي في …"; nothing says these are used lessons or how many are left; no start date; nothing clickable.
- **Evidence:** `qa/manual/screens/M15/M15-F-002-subscriptions-no-remaining-no-renew.png`, `qa/manual/screens/M15/triage/t002-subscriptions.png`
- **Notes:** Not part of this bug: a renew button (renewal is office-only, subscriptions.md §5); identical cards for not-started renewals are ETQAN-QA-200.
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `scheduling/FamilySubscriptions.tsx` `SubscriptionCard` used only the shared `SubscriptionProgress` ("3 of 8 sessions") and "ينتهي في"; `sessions_remaining` and `starts_on` were in the payload but never shown. Fix (dashboard only, family card only; office lists unchanged): "المستخدمة: 2 · المتبقية: 6" (used = used + carried, left = max(0, sessions_remaining)) and "من <start> إلى <end>", grace notice kept on its own line; keys `scheduling.family.usedLeft`/`period` (ar/en; no es scheduling catalogue). Applies to Home's cards too (same component). Regression test: `FamilySubscriptions.test.tsx` "shows used of total, extras, the end date and the grace notice" (now asserts Used/Left and From…to). Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): student AR/EN `/app/learning/subscriptions`: 'المستخدمة: 2 · المتبقية: 6' / 'Used: 0 · Left: 8' and 'من 20/10/2026 إلى 19/11/2026'; parent Home on 375 px shows the same lines. Evidence `qa/manual/screens/M15/fix/ETQAN-QA-455-after.png`, `qa/manual/screens/M15/fix/r455-home-mobile.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-456: Wallet statement (AR): manual top-up details are English "Cash", "Cash · TC028"
- **Feature:** M15 Family wallet statement (`wallet/Statement.tsx`; note built in `wallet/services/ledger.py:123` from `billing METHOD_LABELS`). **Severity:** P3. **Type:** translation. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-008); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@.
- **Reproduction steps:**
  1. AR `/app/learning/wallet` → "كشف الحساب بـ EGP".
- **Expected:** method names in Arabic ("نقدًا · TC028").
- **Actual:** "Cash", "Cash · TC028", "Cash · TC018 prep" inside the Arabic table (the English label is frozen into `WalletEntry.note` at write time).
- **Evidence:** `qa/manual/screens/M15/M15-F-008-wallet-cash-english.png`, `qa/manual/screens/M15/triage/t008-wallet-ar.png`
- **Notes:** Not a bug: the blank details on "تسوية" rows — `wallet/api/payloads.py:entry_row` hides the office's adjustment reason from families on purpose. Same frozen-label family as ETQAN-QA-313 / ETQAN-QA-403.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-457: Phone (375): wallet statement table is 491 px in 293 px — amounts clipped, "الرصيد بعده" off-screen, invoice numbers broken over two lines
- **Feature:** M15 Family wallet statement, 375x812. **Severity:** P3. **Type:** mobile. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 375x812. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-028); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@.
- **Reproduction steps:**
  1. AR 375x812 `/app/learning/wallet` → `[documentElement.scrollWidth, table.scrollWidth, table.parentElement.clientWidth]`.
- **Expected:** a phone layout (one card per movement) or a visible sideways-scroll cue.
- **Actual:** `[375, 491, 293]`; "+200.00 ج.م" cut at the left edge, "الرصيد بعده" hidden, "INV-/000143" and "منقول/من/فاتورة" wrap over 2–3 lines.
- **Evidence:** `qa/manual/screens/M15/M15-F-028-mobile-wallet-table-cut.png`, `qa/manual/screens/M15/triage/t009-wallet-mobile.png`
- **Notes:** Same family as ETQAN-QA-315 (office invoices table) and ETQAN-QA-173.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-458: Student "واجباتي": an answered homework still shows the grey "غير مكتمل", same as an unanswered one
- **Feature:** M15 Student/parent homework list (`homework/MyHomework.tsx`). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-010); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@; homework "M14-sweep memorise Al-Mulk 1-5" answered with `M15-homework-answer.pdf` (answered_at 28/10 03:49).
- **Reproduction steps:**
  1. AR `/app/learning/homework`; open the homework.
- **Expected:** answered-but-not-reviewed reads "بانتظار المراجعة" (the key `homework.status.awaitingReview` added for ETQAN-QA-415).
- **Actual:** list badge "غير مكتمل" (dialog does say "تمت الإجابة في …").
- **Evidence:** `qa/manual/screens/M15/M15-F-010-homework-still-incomplete-after-submit.png`, `qa/manual/screens/M15/triage/t010-homework-list.png`, `qa/manual/screens/M15/triage/t011-homework-dialog.png`
- **Notes:** Student twin of ETQAN-QA-415 (fixed on the teacher list only). Not a bug: no due date (homework-content.md: "There is no due date and no grade").
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `homework/MyHomework.tsx` chose the chip from `status` only (complete vs incomplete); the ETQAN-QA-415 fix covered `HomeworkList` (teacher) only. Fix: an incomplete homework with `answered_at` shows "بانتظار المراجعة" (`homework.status.awaitingReview`, existing key), same rule as the teacher list. Regression test: `MyHomework.test.tsx` "marks an answered homework as awaiting review, not incomplete (ETQAN-QA-458)". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): AR/EN `/app/learning/homework`: answered 'M14-sweep memorise Al-Mulk 1-5' reads 'بانتظار المراجعة' / 'Awaiting review'; reviewed ones 'مكتمل'. Evidence `qa/manual/screens/M15/fix/ETQAN-QA-458-after.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-459: "قيّم حصصك": lessons are labelled date · course · teacher only; two lessons on 18/10 read the same
- **Feature:** M15 Rate lessons (`reviews` RateLessons, both "بانتظار التقييم" and "تقييماتي"). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-011); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@ (sessions 248 and 249, both 18/10 تجويد QA teacher).
- **Reproduction steps:**
  1. AR `/app/learning/reviews`.
- **Expected:** the lesson time on each card ("18/10/2026 10:00 · …").
- **Actual:** "2026/10/18 · تجويد · QA teacher" for both; after rating, "تقييماتي" shows two identical "2026/10/18 · تجويد" rows.
- **Evidence:** `qa/manual/screens/M15/M15-F-011-reviews-identical-rows.png`, `qa/manual/screens/M15/triage/t014-review-double-toast.png`
- **Notes:** Only the last 30 days and attended lessons are offered by design (reviews-honour.md WINDOW_DAYS); not part of this bug.
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: the review endpoints' session object (`learning/api/serializers.py:_session_ref`) carried `occurs_on` but no time, and `reviews/RateLessons.tsx` labelled cards with the day only. Fix: additive read-only `starts_at` in `_session_ref` (no migration, no input change; noted in coverage-gaps.md); `RateLessons` labels both "بانتظار التقييم" and "تقييماتي" cards (and the star group's name) as day + start time on the viewer's clock, each part isolated (FSI/PDI), and "تقييماتي" rows also name the teacher. Regression tests: `RateLessons.test.tsx` "tells two lessons on one day apart by their start time (ETQAN-QA-459)"; pytest `test_api_reviews.py::test_put_creates_then_replaces` and `::test_reviewable_student` assert `starts_at`. Branch `qa/manual-2026-10` (dashboard + backend); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): AR/EN `/app/learning/reviews`: cards and star groups read e.g. '16/10/2026 20:00 · تجويد · QA teacher'; the two 18/10 lessons in 'تقييماتي' now read 10:00 and 12:00 and name the teacher. Backend change is a read-only `starts_at` on `_session_ref` (no migration), reviewed. Evidence `qa/manual/screens/M15/fix/ETQAN-QA-459-after.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-460: Review comment has no 2000-character limit in the field; a long comment fails only after saving, with Django's ungrammatical "تأكد ان عدد الحروف في هذا الحقل لا تتجاوز 2000."
- **Feature:** M15 Rate lessons comment field. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-012); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@.
- **Reproduction steps:**
  1. AR `/app/learning/reviews` → first card → 4 stars → paste ~2,500 characters → double-click "حفظ التقييم".
- **Expected:** `maxLength=2000` with a counter (reviews-honour.md: comment ≤ 2000), or an Arabic message from the app's own catalogue.
- **Actual:** textarea `maxLength` −1; two `PUT /api/v1/learning/sessions/248/review/` → 400; red "تأكد ان عدد الحروف في هذا الحقل لا تتجاوز 2000." (no hamza, gender mismatch).
- **Evidence:** `qa/manual/screens/M15/M15-F-012-review-long-comment-limit-after-submit.png`, `qa/manual/screens/M15/triage/t013-review-long.png`
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `reviews/ReviewEditor.tsx` rendered the comment `<Textarea>` without `maxLength`, so only the server (`ReviewInput.comment max_length=2000`) refused, with Django's own Arabic sentence. Fix: `maxLength={2000}` (`COMMENT_MAX`) and a live counter "الأحرف: n من 2000" linked by `aria-describedby`; key `reviews.commentCount` (ar/en; no es reviews catalogue). Regression test: `RateLessons.test.tsx` "caps the comment at the server's 2000 characters and counts them (ETQAN-QA-460)". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): pasting 2,609 chars into the first comment keeps 2,000 (`maxLength` 2000) and shows 'الأحرف: 2000 من 2000'; EN 'Characters: 0 of 2000'. Evidence `qa/manual/screens/M15/fix/ETQAN-QA-460-after.png`, `qa/manual/screens/M15/fix/r460c.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-461: Double-clicking "حفظ التقييم" sends two saves and shows two "تم حفظ التقييم." toasts
- **Feature:** M15 Rate lessons save button. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-013); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@.
- **Reproduction steps:**
  1. AR `/app/learning/reviews` → first card → 5 stars → "M15- triage: حصة جيدة." → double-click "حفظ التقييم".
- **Expected:** the button is disabled while saving; one toast.
- **Actual:** two stacked "تم حفظ التقييم." toasts (and two notification announcements); one review row (PUT is create-or-replace, review 4 on session 248).
- **Evidence:** `qa/manual/screens/M15/M15-F-013-review-double-toast.png`, `qa/manual/screens/M15/triage/t014-review-double-toast.png`
- **Notes:** Same pattern as ETQAN-QA-052 (change password), different form.
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `ReviewEditor` disabled Save from `write.isPending`, which only takes effect after a re-render, so a double click submitted twice. Fix: a `saving` ref set before the request and cleared in `finally` drops the second submit at once (same pattern as `BroadcastComposer`). Regression test: `RateLessons.test.tsx` "saves once on a double click (ETQAN-QA-461)" (fails without the guard: 2 calls). Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): 5 stars + 'M15-gate: حصة ممتازة ومفيدة.' + double-click 'حفظ التقييم' → one toast 'تم حفظ التقييم.', one `learning_sessionreview` row (id 6, session 278). Evidence `qa/manual/screens/M15/fix/ETQAN-QA-461-after.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-462: Recorded-course store: "دوراتي المسجلة" and "متجر الدورات المسجلة" are both highlighted in the sidebar
- **Feature:** M15 Sidebar active state on `/app/learning/recorded/store*`. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-014); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@.
- **Reproduction steps:**
  1. AR sidebar → "متجر الدورات المسجلة" (`/app/learning/recorded/store`, also `/store/1`).
- **Expected:** only the store item active.
- **Actual:** both `/app/learning/recorded` and `/app/learning/recorded/store` links are active (fuzzy prefix match).
- **Evidence:** `qa/manual/screens/M15/M15-F-014-store-two-nav-items-active.png`, `qa/manual/screens/M15/triage/t015-store-nav.png`
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `shell/AppSidebar.tsx` gave every item fuzzy active matching (`exact` only for "/"), so `/learning/recorded` also matched `/learning/recorded/store…`. Fix: an item matches exactly when another nav item deeper under it (`<to>/…`) matches the current path, so the deeper item owns the page; other items keep fuzzy matching (detail pages). Regression test: `AppSidebar.test.tsx` "marks only the store active on a store page, not My recorded courses too (ETQAN-QA-462)". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): `aria-current=page` items: `/learning/recorded/store` and `/store/1` → only 'متجر الدورات المسجلة'; `/learning/recorded` → only 'دوراتي المسجلة'. Evidence `qa/manual/screens/M15/fix/ETQAN-QA-462-after.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-463: Recorded-course player logs React "Encountered two children with the same key, `1`"
- **Feature:** M15 Course player `/app/learning/recorded/<id>` (`recorded/CoursePlayer.tsx` / `Discussion.tsx`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-015); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@ enrolled in course 1 (one video, one comment).
- **Reproduction steps:**
  1. AR `/app/learning/recorded/1`, read the console.
- **Expected:** no console errors.
- **Actual:** 2× "Encountered two children with the same key, `1`…"; React may duplicate/omit list items (lessons or comments) once ids collide.
- **Evidence:** `qa/manual/screens/M15/M15-F-015-course-player-duplicate-key-error.png`, `qa/manual/screens/M15/triage/t016-player.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-464: Consultation booking (AR): WhatsApp is required but not marked, the hint says empty fields use account data, and the error is English "Enter a WhatsApp number."
- **Feature:** M15 Family consultation booking (`/app/learning/consultations/book`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-018); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@ (account has no phone); product 1, teacher 228.
- **Reproduction steps:**
  1. AR `/app/learning/consultations/book?product=1` → teacher → slot 29/10 20:30 → leave الاسم/البريد/واتساب empty → "ادفع عبر Stripe".
- **Expected:** WhatsApp marked required when the account has no phone (or the hint says so), Arabic error.
- **Actual:** inputs `required=false`; hint "اترك الحقل فارغًا لاستخدام بيانات حسابك."; `POST /api/v1/consultations/my/book/` → 400 and ".Enter a WhatsApp number" in red under واتساب (English, full stop on the wrong side). No booking created.
- **Evidence:** `qa/manual/screens/M15/M15-F-018-consult-whatsapp-english-error.png`, `qa/manual/screens/M15/triage/t023-consult-whatsapp.png`
- **Notes:** The raw IANA time-zone list on the same form is the ETQAN-QA-154 pattern (not re-filed).
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `consultations/BookingWizard.tsx` marked WhatsApp required only for visitors (`required={!signedIn}`), while the server (`booking.py:_contact_for`) falls back to the account's phone and refuses with the code-less English "Enter a WhatsApp number." when the account has none; the hint said all empty fields use account data. Fix (dashboard only): for a signed-in booker without `me.phone` WhatsApp is marked required, Pay stays disabled until it is filled, the hint says so (`consultations.book.accountHintNoPhone`), and a server WhatsApp refusal is shown as "أدخل رقم واتساب." (`consultations.book.whatsappRequired`); ar/en. Proposal for server codes in coverage-gaps.md. Regression test: `BookingWizard.test.tsx` "asks a signed-in booker without a phone for WhatsApp, in their language (ETQAN-QA-464)". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): qa-student@ (no phone) AR booking: hint 'حسابك بلا رقم هاتف، فأدخل رقم واتساب.', WhatsApp has the '*' and aria-required=true, 'ادفع عبر Stripe' disabled until WhatsApp is filled (checked enabled after filling; no booking made). The Arabic server-error text is covered by BookingWizard.test.tsx (not reachable from the UI any more). API error-code idea = PROPOSAL-accepted (low priority). Evidence `qa/manual/screens/M15/fix/ETQAN-QA-464-after.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-465: Progress (parent/student): a level card reads "0 / 0" with no unit and an empty bar; the chosen child isn't kept on refresh
- **Feature:** M15 `/app/learning/progress` course card. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-024); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** parent.najjar@ (Adam: "التجويد للمبتدئين", level "M07 المستوى 2" with no topics).
- **Reproduction steps:**
  1. AR `/app/learning/progress` (child آدم).
- **Expected:** "الموضوعات المكتملة: 0 من 0" or "لا موضوعات في هذا المستوى بعد" (curriculum.md: totals are "completed n / total" topics of active levels).
- **Actual:** bare "0 / 0" and an empty bar; switching to Salma and refreshing goes back to Adam.
- **Evidence:** `qa/manual/screens/M15/M15-F-024-parent-progress-0-of-0.png`, `qa/manual/screens/M15/triage/t028-parent-progress.png`
- **Notes:** Cross-family probes on progress/invoices answered 404 (OK).
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `curriculum/MyProgress.tsx` printed the office key `curriculum.progress.completedOf` ("{{completed}} / {{total}}") and a meter even with 0 topics, and kept the parent's chosen child only in component state. Fix (dashboard only): the family card reads "الموضوعات المكتملة: 1 من 2" (`curriculum.progress.topicsOf`) and a level with no topics says "لا موضوعات في هذا المستوى بعد." (`noTopics`) with no bar; the route `learning.progress` keeps the chosen child in `?student=` (replace navigation), and an id not among the parent's children is ignored. Regression tests: `MyProgress.test.tsx` "says a level has no topics…", "opens on the child kept in the URL and reports a new pick", "ignores a child id from another family in the URL" (all ETQAN-QA-465). Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): parent.najjar@ AR: Adam's empty level reads 'لا موضوعات في هذا المستوى بعد.' with no bar; picking Salma writes `?student=237` and a reload keeps Salma; `?student=232` (Sharif family) is ignored (Adam shown, no request for 232). Evidence `qa/manual/screens/M15/fix/ETQAN-QA-465-after.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-466: Certificate print pages have no way back, and the admin's Arabic message is set in synthetic italics
- **Feature:** M15 `_print/certificates.$id.print` and `_print/subject-certificates.$id.print`. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-025, print-page part of M15-F-016); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** parent.najjar@; certificate 1 (appreciation, Adam) with message "M15- مبارك يا آدم، نفخر بتقدّمك في التجويد.".
- **Reproduction steps:**
  1. AR `/app/learning/certificates` → "شهادة تقدير" (same tab) → `/app/certificates/1/print`.
- **Expected:** a "رجوع" button like the invoice print page (which has one); upright Arabic text.
- **Actual:** only "طباعة"; the message `<p>` is `font-style: italic`, slanting Arabic letters. Same on the recorded-course subject certificate print page.
- **Evidence:** `qa/manual/screens/M15/M15-F-025-certificate-print-only-no-back.png`, `qa/manual/screens/M15/M15-F-016b-earned-certificate.png`, `qa/manual/screens/M15/triage/t019-cert-print.png`
- **Notes:** Not a bug: no PDF download (certificates.md: "Printing and saving as PDF are done in the browser; there is no server-side PDF"). Side note: a parent opening another family's `/app/subject-certificates/1/print` gets 404s and "جارٍ التحميل" forever (data safe; ETQAN-QA-106 pattern), `qa/manual/screens/M15/triage/t018-subject-cert-print-asparent.png`.
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `certificates/CertificatePrint.tsx` (`CertificateSheet`, also used by `SubjectCertificatePrint`) had its own toolbar with Print only (the ETQAN-QA-420 back button is in `PrintSheet`, which certificates don't use), and set the message `<p>` in `italic` whatever its script. Fix: new shared `PrintBackButton` in `branding/PrintSheet.tsx` (history back, else home; `common.back`), placed beside Print in the certificate toolbar (hidden on paper); the message is italic only when it has no Arabic letters, with `dir="auto"`. `PrintSheet`'s own button left as is. Regression tests: `CertificatePrint.test.tsx` "offers a way back beside Print, off the paper (ETQAN-QA-466)", "sets an Arabic message upright and a Latin one in italics (ETQAN-QA-466)"; `SubjectCertificatePrint.test.tsx` asserts the Back button. Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** OPEN, fix rejected (Agent 2, 2026-10-28): the 'رجوع' button works (print → back to `/app/learning/certificates`) and the Arabic message is no longer slanted (font-style normal), BUT the new `dir="auto"` on the message makes it LTR whenever it starts with a Latin character: the issued certificate's message 'M15- مبارك يا آدم، نفخر بتقدّمك في التجويد.' now prints as 'M15- …التجويد' with the period pushed in front of 'مبارك' (computed direction ltr; it was correct RTL before). A message that starts with a Latin name, code or number gets scrambled punctuation on a printed certificate. Fix: drop `dir="auto"` (inherit the sheet's direction) or set dir from the same ARABIC_SCRIPT test. Evidence `qa/manual/screens/M15/fix/ETQAN-QA-466-after.png`, `qa/manual/screens/M15/fix/r466-msg.png`.

---

## ETQAN-QA-467: Family invoices list (AR): the invoice number floats away from the right edge (desktop) and toward the left on a phone
- **Feature:** M15 `FamilyInvoices` card header. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 375x812 and 1440x900. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-027); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@.
- **Reproduction steps:**
  1. AR 375x812 `/app/learning/invoices`; measure the "INV-000144" link vs its card.
- **Expected:** the number right-aligned with the description and due line under it.
- **Actual:** `<a dir="ltr">` spans x 118–334 inside a card 17–358, text starts at its left; on desktop it sits ~125 px in from the right edge (x≈920–1010 vs lines ending at 1135).
- **Evidence:** `qa/manual/screens/M15/M15-F-027-invoice-number-misaligned-mobile.png`, `qa/manual/screens/M15/triage/t030-invoices-mobile.png`, `qa/manual/screens/M15/triage/t003-invoices-list.png`
- **Notes:** Same family as ETQAN-QA-511 (registration code floats left). The floating status badge is ETQAN-QA-121 (not re-filed).
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: in `billing/FamilyInvoices.tsx` the `<Link dir="ltr">` invoice number is a stretched flex-column item, so its LTR text starts at the left of the column in an RTL card (same as ETQAN-QA-511). Fix: `self-start max-w-full` keeps the number at its own width at the card's start (right in Arabic), over its lines. Regression test: `FamilyInvoices.test.tsx` "keeps the LTR invoice number at the card's start, not stretched (ETQAN-QA-467)". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): AR 375 px `/app/learning/invoices`: 'INV-000144' right edge 334 vs card 359 (= card padding), aligned with the lines below. Evidence `qa/manual/screens/M15/fix/ETQAN-QA-467-after.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-468: Parent "الدورات المسجلة لأبنائي" empty state speaks to the parent as the student: "لست مشتركًا في أي دورة مسجلة بعد."
- **Feature:** M15 `recorded/MyCourses.tsx` (parent view). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-029); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** parent.najjar@; Salma enrolled in course 1 (enrolment 3), Adam in none.
- **Reproduction steps:**
  1. AR `/app/learning/recorded` (defaults to آدم).
- **Expected:** "لم يشترك آدم في أي دورة مسجلة بعد." (child-specific); ideally open on the child just enrolled.
- **Actual:** "لست مشتركًا في أي دورة مسجلة بعد." — a parent who just enrolled Salma reads it as "the enrolment failed".
- **Evidence:** `qa/manual/screens/M15/M15-F-029-parent-courses-you-not-enrolled.png`, `qa/manual/screens/M15/triage/t029-parent-courses.png`
- **Notes:** Same pattern as ETQAN-QA-115 (parent first-person labels), here an empty-state string not covered by that fix.
- **Root cause / Fix / Regression tests (Agent 3, M15 fix cycle 1, 2026-10-28):** Root cause: `recorded/MyCourses.tsx` used the student's first-person `recorded.my.empty` for a parent too. Fix: for a parent the empty state names the chosen child, "لا يوجد اشتراك في أي دورة مسجلة باسم <name> بعد." (`recorded.my.emptyChild`, name isolated with `bidiName`); student unchanged. Not done: opening on the child just enrolled (store flow). Regression test: `MyCourses.test.tsx` "names the chosen child in a parent's empty state (ETQAN-QA-468)". Branch `qa/manual-2026-10` (dashboard); evidence `qa/manual/evidence/M15/fix-1/`.
- **Verification status:** VERIFIED (Agent 2, 2026-10-28): parent.najjar@ AR 'لا يوجد اشتراك في أي دورة مسجلة باسم آدم النجار (Adam Al-Najjar) بعد.'; EN '… is not enrolled in any recorded course yet.'. Evidence `qa/manual/screens/M15/fix/ETQAN-QA-468-after.png`; tests: `qa/manual/evidence/M15/gate-1/` (vitest 33 files, all pass, with 3 consultations specs passing only serially at load 27; tsc 0; pytest learning -k review 69 passed).

---

## ETQAN-QA-469: Paid invoice shows the raw provider id "pi_sim_0a82e186b84a4b3981c30089652e36ef" to the family as the payment's main detail
- **Feature:** M15 Family invoice detail, payments card. **Severity:** P4. **Type:** copy. **Easy P3:** no (P4). **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL (SIMULATED id)
- **Found by:** Agent 1, manual M15 (M15-F-004); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@, INV-000144 paid online.
- **Reproduction steps:**
  1. AR `/app/learning/invoices/144` → "الدفعات".
- **Expected:** a short labelled reference ("المرجع: …0a82e1") or none; date first.
- **Actual:** second line "pi_sim_0a82e186b84a4b3981c30089652e36ef · 2026/10/28" — a 40-character unlabelled technical id ahead of the date.
- **Evidence:** `qa/manual/screens/M15/M15-F-004-raw-transaction-id.png`, `qa/manual/screens/M15/triage/t004-inv144.png`
- **Notes:** Its phone overflow is ETQAN-QA-315.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-470: Homework answer file picker is the bare native control (English "Choose File / No file chosen" in Chromium) with no allowed types or size hint
- **Feature:** M15 Student homework dialog (`homework/MyHomework.tsx:336`). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no (P4). **Priority:** low
- **Environment:** local docker stack (backend 68e95e1c, dashboard 626d0e7 + uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M15 (M15-F-009); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@.
- **Reproduction steps:**
  1. AR `/app/learning/homework` → "M14-sweep memorise Al-Mulk 1-5".
- **Expected:** an Arabic "اختر ملفًا" control with accepted types and size limit.
- **Actual:** native `<input type="file">` "Choose FileNo file chosen" (its label follows the browser's language, not the app's), left-aligned in the RTL dialog, no type/size hint.
- **Evidence:** `qa/manual/screens/M15/M15-F-009-homework-file-input-english.png`, `qa/manual/screens/M15/triage/t011-homework-dialog.png`
- **Notes:** Same pattern as ETQAN-QA-502 (branding pickers) and M10-F-009 (chat group image); one shared file-picker component would fix all.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-471: Consultation request page still says "موعدك محجوز حتى 28/10/2026, 13:30" hours after the hold ended
- **Feature:** M15 Family consultation request page (`/app/learning/consultations/<id>`, `consultations/ManagePage.tsx:141`). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL (payments SIMULATED)
- **Found by:** Agent 1, manual M15 confirmation sweep (M15-F-030, CR-000001); reproduced by Agent 2 on 2026-10-28 (CR-000004).
- **Preconditions:** qa-student@ / `QA-People-2026!`; consultation product 1 "M15- استشارة خطة الحفظ" (200 EGP).
- **Reproduction steps:**
  1. AR `/app/learning/consultations/book?product=1` → teacher → a slot → WhatsApp → "ادفع عبر Stripe"; open the request page and start the Stripe checkout, leave the simulator without paying.
  2. Let the 30-minute hold pass (Agent 2 moved `hold_until` back 2 h in the DB to stand in for the wait; Agent 1 saw it naturally after 8 h).
  3. Open `/app/learning/consultations/<id>`.
- **Expected:** once the hold has ended the page says so ("انتهت مدة حجز الموعد، ادفع الآن لتأكيده إن كان لا يزال متاحًا") or drops the line; never a past deadline worded as a live promise.
- **Actual:** "الحالة: قيد المراجعة · الدفع: لم يُدفع بعد · موعدك محجوز حتى 28/10/2026, 13:30." at 15:30 Cairo, then "ادفع عبر Stripe". The line is shown whenever `hold_until` is set, past or not. Data is safe: `paying.rehold` re-holds the slot on Pay or refuses with `slot_taken` if someone else booked it.
- **Evidence:** `qa/manual/screens/M15/M15-F-030-consult-held-until-past-time.png`, `qa/manual/screens/M15/triage/final/M15-F-030-repro-held-until-past.png`
- **Notes:** Side detail on this page (same `when()` helper, ManagePage.tsx:65): the date and time are joined with a Latin ", " ("02/11/2026, 20:30") where the rest of the Arabic portal uses "،"; fix together. The status line "قيد المراجعة" above "لم يُدفع بعد" was already noted under ETQAN-QA-451. The ~25 h auto-cancel delay is the ETQAN-QA-451 owner proposal. Data left: CR-000004 (unpaid, checkout expired in the simulator; `cancel_unpaid` cancels it).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-472: Phone receipt: payment amounts wrap onto their own line and read as belonging to the next payment
- **Feature:** M15 Invoice receipt `/app/invoices/<id>/print`, payments list (`billing/InvoicePrint.tsx:114`, `flex flex-wrap justify-between`). **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack, Chromium via `qa/manual/tools/step.mjs`, 375x812. **Tag:** REAL (payments SIMULATED)
- **Found by:** Agent 1, manual M15 confirmation sweep (M15-F-031); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-student@; INV-000143 paid by wallet 720 + system code 100 + Stripe 680 (fee 34).
- **Reproduction steps:**
  1. AR 375x812 `/app/invoices/143/print` → "الدفعات".
- **Expected:** each payment's amount stays on its row beside its label (the label wraps instead), or rows are separated so it is clear which amount is which.
- **Actual:** row 1 "28/10/2026 · الرصيد — 720.00" fits; row 2 "28/10/2026 · كود النظام · SYS-A2335-4PRJA" fills the width and its "100.00 ج.م." drops onto its own line; row 3 "28/10/2026 · Stripe · رسوم 34.00 ج.م." then "680.00 ج.م." alone. With no dividers the lone amounts sit right above the next label, so a parent checking the receipt pairs them wrongly. Totals block is fine.
- **Evidence:** `qa/manual/screens/M15/M15-F-031-phone-receipt-payment-amounts-wrap.png`, `qa/manual/screens/M15/triage/final/M15-F-031-repro-phone-receipt.png`
- **Notes:** The longer Stripe label comes from the ETQAN-QA-450 fee fix (correct content). Not ETQAN-QA-315 (admin invoices table) nor ETQAN-QA-469 (raw provider id on the invoice page). Likely fix: `flex-nowrap` row, `min-w-0` + wrapping on the label span, `shrink-0 whitespace-nowrap` on the amount.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## --- M05 manual bugs ---

## ETQAN-QA-550: Catalogue lists in Arabic are ordered by the hidden English name (courses and packages look randomly ordered)
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-001); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: open `/app/catalogue/courses` (also `/app/catalogue/packages`).
- **Expected:** The list is ordered by what the reader sees (Arabic name in Arabic, or newest first).
- **Actual:** Order is اللغة العربية للناطقين بغيرها, F03 قرآن, M05 دورة التلاوة المعدلة, عربي, قرآن, حفظ القرآن الكريم, scn, ... - the API sorts by `name_en` (Arabic for…, F03 Quran, M05…, QA6 Arabic…).
- **Evidence:** `qa/manual/screens/M05/M05-F-001-courses-order-ar.png`, `qa/manual/screens/M05/triage/t001-courses-order.png`
- **Notes:** `backend/etqan/catalogue/models.py:33` and `:64` `ordering = ["name_en", "id"]` for Course and Package; no locale-aware order in the list view or the dashboard.
- **Verification status:** OPEN

---

## ETQAN-QA-551: Status/yes-no filters have no visible label: bare "الكل / نعم / لا" dropdowns on courses, packages, recorded courses and consultations
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-002 (+F-024, F-029 filters)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: `/app/catalogue/courses`, choose "لا" in the dropdown next to the search box.
  2. Open `/app/catalogue/recorded` and `/app/catalogue/consultations`: three dropdowns each read "الكل".
- **Expected:** Each filter says what it filters ("الحالة: الكل / نشط / غير نشط", "منشورة", "خصم", ...).
- **Actual:** Courses/packages: options "الكل/نعم/لا", the closed box reads just "لا". Recorded: three boxes "الكل" (منشورة / اللغة / خصم exist only as aria-label); the Videos tab has two more; consultations three (طريقة التقديم / مميزة / الحالة). Two yes/no boxes are indistinguishable by sight.
- **Evidence:** `qa/manual/screens/M05/M05-F-002-status-filter-yes-no.png`, `qa/manual/screens/M05/triage/t002-filter-no.png`, `qa/manual/screens/M05/triage/t024-recorded-filters.png`, `qa/manual/screens/M05/triage/t029-consult-list.png`
- **Notes:** Recorded and consultation filters carry an aria-label, so only the visible text is missing; courses/packages filter has none. `CatalogueList` (catalogue) and the recorded/consultation list filters.
- **Root cause (Agent 3, fix cycle 1):** Each list toolbar rendered a bare native `<select>` with only an `aria-label` (courses/packages had a label of "نشط" and options نعم/لا), so nothing on screen said what the box filters.
- **Fix:** New shared `dashboard/src/components/FilterSelect.tsx`: the select with a visible `<label for>` above it. Used by `CatalogueList` (label "الحالة", options الكل / نشط / غير نشط), `recorded/PlaylistsAdmin` (منشورة / اللغة / خصم), `recorded/VideosTab` (الحالة / قابل للتنزيل) and `consultations/ProductsAdmin` (طريقة التقديم / مميزة / الحالة). New key `catalogue.status` ar/en/es. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `CatalogueList.test.tsx` "names the status filter visibly and offers Active/Inactive (ETQAN-QA-551)"; `PlaylistsAdmin.test.tsx` and `ProductsAdmin.test.tsx` "names every filter with a visible label (ETQAN-QA-551)"; `VideosTab.test.tsx` "shows a visible label on each filter (ETQAN-QA-551)". Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-551-before.png` vs `ETQAN-QA-551-after.png (courses AR, label الحالة, نشط/غير نشط), -after-recorded.png, -after-mobile-packages.png, ETQAN-QA-571-after(-en).png (consultations)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-552: Course/package search with no match says "لا توجد دورات بعد." (no courses yet)
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-003); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: `/app/catalogue/courses`, type `zzzxx` in ابحث بالاسم.
- **Expected:** "لا توجد نتائج مطابقة" with a way to clear the search/filter.
- **Actual:** "لا توجد دورات بعد." - reads as if the academy has no courses.
- **Evidence:** `qa/manual/screens/M05/M05-F-003-courses-no-match-says-none-yet.png`, `qa/manual/screens/M05/triage/t003-no-match.png`
- **Notes:** Same pattern as ETQAN-QA-152 (students) / QA-306 (payments) / QA-611 (notification log); new screen (`CatalogueList`, shared by packages).
- **Root cause (Agent 3, fix cycle 1):** `CatalogueList` always showed `catalogue.<kind>.empty` ("no courses yet") when the page came back empty, whatever the search or status filter.
- **Fix:** `CatalogueList` shows `catalogue.noMatch` ("لا توجد نتائج مطابقة للبحث أو عوامل التصفية.") with a "مسح البحث والتصفية" button when a search or status is set; the "none yet" text stays for an unfiltered empty list. Keys ar/en/es. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `CatalogueList.test.tsx` "says nothing matches (not 'no courses yet') when a search finds nothing (ETQAN-QA-552)" and "still says 'no courses yet' with no search or filter". Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-552-before.png` vs `ETQAN-QA-552-after.png (AR courses), -after-en-packages.png (EN packages)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-553: Deleting a course leaves the dead edit form on screen, with no message; the page then re-fetches a 404
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-004); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: `/app/catalogue/courses`, نسخ on any course → open the "(نسخة)" copy (`/app/catalogue/courses/<id>`).
  2. Click حذف → in "حذف الدورة" click حذف الدورة; wait 3 s.
- **Expected:** Back to the courses list with a "تم حذف الدورة." toast.
- **Actual:** Dialog closes; the deleted course's full form stays with حفظ/حذف enabled; URL unchanged; no toast; 3× `404 GET /api/v1/catalogue/courses/<id>/`.
- **Evidence:** `qa/manual/screens/M05/M05-F-004-course-delete-stays-on-form.png`, `qa/manual/screens/M05/triage/t004a-dup.png`, `qa/manual/screens/M05/triage/t004-delete-stays.png`
- **Notes:** Course 13 (my copy) deleted during repro. CourseForm delete mutation has no onSuccess navigate/toast.
- **Root cause (Agent 3, fix cycle 1):** `useDeleteCatalogueItem` invalidated the whole `["catalogue","courses"]` key, which includes the deleted course's own still-mounted detail query. The mutation waited for that refetch (404, then retries with back-off) before the per-call `onSuccess` could navigate, so the dead form stayed for seconds; and the delete had no success toast.
- **Fix:** `catalogue/queries.ts`: delete invalidates only the list queries. `CourseForm` delete shows "تم حذف الدورة." (`catalogue.courses.deleted`, ar/en/es) and returns to the list. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `CourseForm.test.tsx` "deletes an existing course after confirmation" now also asserts the landing on `/catalogue/courses`, the toast, and that the course is fetched only once. Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-553-before.png` vs `ETQAN-QA-553-after.png (copy 14 deleted: back on the list with 'تم حذف الدورة.', no 404 request)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-554: Opening a deleted or unknown course shows a spinner forever
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-005); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: open `/app/catalogue/courses/13` (a deleted course); wait 6 s.
- **Expected:** "الدورة غير موجودة" with a link back to the courses list.
- **Actual:** Title "الدورة" and a spinner that never stops; `404 GET /api/v1/catalogue/courses/13/` retried.
- **Evidence:** `qa/manual/screens/M05/M05-F-005-deleted-course-spins.png`, `qa/manual/screens/M05/triage/t005-deleted-course-spins.png`
- **Notes:** Same class as ETQAN-QA-106 (student page) and QA-365 (payslip); new page. Packages page likely the same (same route pattern).
- **Verification status:** OPEN

---

## ETQAN-QA-555: Courses CSV lists teachers as bare user IDs, with English headers and raw codes, also from the Arabic UI
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** data. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-006); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: `/app/catalogue/courses` → تصدير CSV (same as `GET /api/v1/catalogue/courses/?format=csv`, Accept-Language ar).
- **Expected:** Teacher names; Arabic headers and words (نشط/غير نشط, العربية/كلاهما) in the Arabic UI.
- **Actual:** `ID,Name (English),Name (Arabic),Language,Active,Teacher IDs` / `1,F03 Quran,F03 قرآن,ar,yes,7; 16; 36; 37; ...` - teachers only as internal ids.
- **Evidence:** `qa/manual/screens/M05/M05-F-006-courses-csv.png`, `qa/manual/screens/M05/triage/t006-courses-csv.png`, `qa/manual/evidence/M05/courses-csv-ar.txt`
- **Notes:** Headers/codes part is the ETQAN-QA-161/271 pattern; the teacher-id column is new and makes the file useless for an owner.
- **Verification status:** OPEN

---

## ETQAN-QA-556: Package form: "المدة" and its unit "وحدة المدة" sit on different rows, diagonally apart
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-007); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: `/app/catalogue/packages` → باقة جديدة.
- **Expected:** The duration number and its unit side by side.
- **Actual:** Row 1: الحصص أسبوعيًا · مدة الحصة · المدة ("1", far left); row 2: وحدة المدة ("أشهر", far right) · أيام التجميد · السعر.
- **Evidence:** `qa/manual/screens/M05/M05-F-007-duration-unit-split.png`, `qa/manual/screens/M05/triage/t007-package-form.png`
- **Notes:** `PackageForm` grid order.
- **Root cause (Agent 3, fix cycle 1):** `PackageForm` put all seven number fields in one flat 3-column grid, so pairs met only by position: duration fell at the end of row 1 and its unit at the start of row 2 (same for price/currency, and it shifted again with the custom-minutes field).
- **Fix:** Three grids: sessions/length(/custom minutes); duration + unit + freeze days; price + currency. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `PackageForm.test.tsx` "keeps duration with its unit and price with its currency, whatever the session length (ETQAN-QA-556)". Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-556-before.png` vs `ETQAN-QA-556-after.png (desktop AR), -after-mobile.png (375 AR, scrollWidth 375)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-557: A price with more decimals than the currency allows is silently truncated (EGP 1500.559 saved as 1,500.55)
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-008); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: open package `/app/catalogue/packages/20` (M05 باقة حدود, EGP).
  2. Set السعر to `1500.559`, click حفظ.
- **Expected:** A refusal ("الجنيه يقبل رقمين عشريين على الأكثر") or a visible rounding.
- **Actual:** "تم الحفظ."; API `price_minor` = 150055; list shows 1,500.55 ج.م. - the extra digit is dropped without a word (truncated, not even rounded).
- **Evidence:** `qa/manual/screens/M05/M05-F-008-price-truncated.png`, `qa/manual/screens/M05/triage/t008-price-3dec.png`
- **Notes:** `dashboard/src/lib/money.ts:48 toMinor` pads/slices the fraction to `minorDigits(currency)`; the package schema does not check precision (the invoice forms do, ETQAN-QA-30x). Shared helper - fix in the package/country-price schemas, not by changing toMinor.
- **Verification status:** OPEN

---

## ETQAN-QA-558: A package has no Delete action (courses do), although the API and docs offer DELETE with the in-use refusal
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-010); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. `/app/catalogue/packages/21`: buttons are only حفظ, إضافة دولة, حفظ الأسعار.
  2. Compare `/app/catalogue/courses/<id>`: حفظ + حذف.
- **Expected:** Same as courses: Delete, refused with "in use" (409 `catalogue.in_use`) when subscriptions exist (docs/features/catalogue.md, Delete vs deactivate).
- **Actual:** No delete; a mistaken package can only be deactivated and stays in the list forever.
- **Evidence:** `qa/manual/screens/M05/M05-F-010-package-no-delete.png`, `qa/manual/screens/M05/triage/t010-035-package21-main.png`
- **Notes:** Backend `delete_package` exists; dashboard `PackageForm` lacks the button.
- **Verification status:** OPEN

---

## ETQAN-QA-559: Editing a package doesn't say that existing subscriptions keep their old terms
- **Feature:** M05 Catalogue. **Severity:** P4. **Type:** copy. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-011); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. `/app/catalogue/packages/21` (used by subscription 108) → change السعر and الحصص أسبوعيًا → حفظ; open `/app/scheduling/subscriptions/108`.
- **Expected:** A note on the form, e.g. "التعديل يسري على الاشتراكات الجديدة فقط" (the country-price card already says so for its prices).
- **Actual:** Only "تم الحفظ."; subscription 108 keeps 16 sessions / 300 ر.س. (correct by design) with nothing telling the owner.
- **Evidence:** `qa/manual/screens/M05/M05-F-011-package-edit-no-notice.png`, `qa/manual/screens/M05/triage/t010-035-package21-main.png`
- **Notes:** Behaviour is documented (catalogue.md "Package edits never reach existing subscriptions"); only the hint is missing.
- **Verification status:** OPEN

---

## ETQAN-QA-560: Level dialog: English name comes first (right) and the required names have no "*"
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-012); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: `/app/catalogue/levels` → إضافة مستوى → حفظ with empty fields.
- **Expected:** الاسم (العربية) first as in course/package forms, both names marked required.
- **Actual:** "الاسم (بالإنجليزية)" is first/right, "الاسم (بالعربية)" second; no asterisk, yet both are required (same in sub-level and topic blocks). Wording "بالعربية" vs "(العربية)" elsewhere.
- **Evidence:** `qa/manual/screens/M05/M05-F-012-level-dialog-name-order.png`, `qa/manual/screens/M05/M05-F-012b-level-required-no-star.png`, `qa/manual/screens/M05/triage/t012-level-dialog.png`
- **Notes:** `LevelDialog`.
- **Root cause (Agent 3, fix cycle 1):** `LevelDialog` listed the English name before the Arabic one in the level, sub-level and topic blocks and passed no `required` to `Field`, although all six names are required (`learning/models.py` CharFields without `blank`). The ar labels said "(بالعربية)" unlike the course/package forms.
- **Fix:** Arabic name first in all three blocks, both marked required (`*` + `aria-required`); ar labels now "الاسم (العربية)" / "الاسم (الإنجليزية)". Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `LevelDialog.test.tsx` "puts the Arabic name first and marks both names required (ETQAN-QA-560)" (existing tests now match the label with a regex because of the `*`). Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-560-before.png` vs `ETQAN-QA-560-after.png (AR, Arabic first, all 6 names starred), -after-en.png` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-561: Raw English server messages in Arabic catalogue dialogs: level topic verses, course-material file type, recorded-course slug
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-013 (+F-019, F-025)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: levels → إضافة مستوى → course, names, إضافة مستوى فرعي, إضافة موضوع, السورة "بلا سورة", من 9 إلى 1 → حفظ.
  2. Same with السورة 1, من 1 إلى 20 → حفظ.
  3. Content → course → إضافة مادة, upload an `.exe` → إضافة مادة.
  4. Recorded → إضافة دورة, الرابط المختصر `م05 رابط` (rest valid) → حفظ.
- **Expected:** Arabic messages (e.g. "اختر السورة لتحديد الآيات.", "الآيات من 1 إلى 7.", "نوع هذا الملف غير مسموح.", "أحرف إنجليزية صغيرة وأرقام وشرطات") and a slug hint before saving.
- **Actual:** "Choose a chapter for a verse range.", "Verses run from 1 to 7, first to last.", "This type of file is not allowed.", "Use lower-case letters, digits and dashes." - English, with the full stop wrapped/mirrored in RTL. From 9 to 1 without a chapter is not questioned on its own.
- **Evidence:** `qa/manual/screens/M05/M05-F-013-level-topic-english-error.png`, `qa/manual/screens/M05/M05-F-019-material-upload-english-error.png`, `qa/manual/screens/M05/M05-F-025-recorded-slug-english-error.png`, `qa/manual/screens/M05/triage/t013-topic-english-error.png`, `qa/manual/screens/M05/triage/t017-surah-latin-verse-error.png`, `qa/manual/screens/M05/triage/t019-exe-english-error.png`, `qa/manual/screens/M05/triage/t025-slug-english.png`
- **Notes:** Same family as ETQAN-QA-157 ("This type of file is not allowed." is already mapped in `src/lib/server-messages.ts`, but the content dialog doesn't use `useFieldError`) and QA-608. Allowed types/size not shown in the material dialog; the bare native file control is the ETQAN-QA-470/607 pattern.
- **Root cause (Agent 3, fix cycle 1):** Three dialogs showed server field errors verbatim: `LevelDialog` set `parseApiError().fieldErrors` directly, and the shared `curriculum/errors.formErrors` (used by the content, recorded and consultation dialogs) passed field and orphan messages through untranslated, so even the already-mapped "This type of file is not allowed." (ETQAN-QA-157) stayed English. The verse sentence carries a number, so it can't be a fixed mapping.
- **Fix:** `formErrors` and `LevelDialog` now run every server sentence through `serverMessageKey` (new `serverText` in `curriculum/errors.ts`). New mappings in `lib/server-messages.ts`: "Choose a chapter for a verse range.", "Give both verses or neither.", "Choose a chapter.", "Use lower-case letters, digits and dashes.". `LevelDialog` checks verses before saving (needs a chapter; both or neither; 1 ≤ from ≤ to ≤ the surah's verse count, "آيات هذه السورة من 1 إلى 7…"). `PlaylistForm` checks the slug's characters before saving ("استخدم أحرفًا إنجليزية صغيرة وأرقامًا وشرطات فقط، مثل tajweed-1."). Keys ar/en (no es file for curriculum/recorded). Durable codes are proposed in `qa/coverage-gaps.md`. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `LevelDialog.test.tsx` "checks a topic's verses in words before saving (ETQAN-QA-561)"; `PlaylistForm.test.tsx` "checks the slug's characters in words before sending (ETQAN-QA-561)"; `curriculum/errors.test.ts` "formErrors in Arabic (ETQAN-QA-561)" (file type + slug in Arabic, unknown sentence kept). Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-561-before.png` vs `ETQAN-QA-561-after-verses.png (Arabic range sentence), -after-nochapter.png, -after-exe.png (server sentence now 'نوع هذا الملف غير مسموح.'), -after-slug.png` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-562: Level topic surah picker is empty ("بلا سورة" only) until someone presses "مزامنة السور" on another page; nothing says so
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-015); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. In an academy that never synced chapters (e.g. `qaother`: `academy_qaother.learning_quranchapter` has 0 rows; `qa` had 0 before Agent 1 synced): levels → إضافة مستوى → إضافة مستوى فرعي → إضافة موضوع → open السورة.
- **Expected:** The 114 bundled surahs present, or the picker says "لا توجد سور - زامنها من صفحة سور القرآن".
- **Actual:** Only "بلا سورة"; verse fields then fail with the English error of ETQAN-QA-561.
- **Evidence:** `qa/manual/screens/M05/M05-F-015-topic-surah-list-empty.png`
- **Notes:** curriculum.md: chapters are reference data loaded from the bundled JSON by `sync_chapters`; nothing loads them at academy creation. Repro by Agent 2 via DB counts (qa: 114 after sync, qaother: 0) + Agent 1's before-sync screenshot; the qa academy is already synced.
- **Root cause (Agent 3, fix cycle 1):** Chapters are reference data loaded only by `sync_chapters` (the "مزامنة السور" button, curriculum.md); academy creation doesn't load them, and `LevelDialog`'s picker then offered only "بلا سورة" with no explanation.
- **Fix:** When chapters are on and the list loaded empty, each topic block shows "لا توجد سور بعد. حمّلها بزر «مزامنة السور» في صفحة سور القرآن." with a link to `/catalogue/quran`. Loading them at academy creation is a proposal in `qa/coverage-gaps.md` (changes documented behaviour). Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `LevelDialog.test.tsx` "says where to load the chapters when there are none (ETQAN-QA-562)". Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-562-before.png` vs `ETQAN-QA-562-after.png (hint + link to /app/catalogue/quran; chapter list stubbed to [] in the browser because qa is synced and qaother has the levels feature off)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-563: Arabic UI shows surahs by Latin transliteration with a mirrored number ("Al-Fatihah .1") in the topic picker and the edit-names dialog title
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-016 (+F-017)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR: `/app/catalogue/quran` → first row تعديل الأسماء.
  2. Levels → إضافة مستوى → … إضافة موضوع → open السورة.
- **Expected:** "1. الفاتحة" (Arabic name, which exists in الاسم بالعربية), number in place.
- **Actual:** Dialog title "Al-Fatihah .1"; picker options "1. Al-Fatihah", "2. Al-Baqarah", selected value reads "Al-Fatihah .1".
- **Evidence:** `qa/manual/screens/M05/M05-F-016-surah-dialog-title.png`, `qa/manual/screens/M05/M05-F-017-surah-picker-latin.png`, `qa/manual/screens/M05/triage/t016-surah-dialog.png`, `qa/manual/screens/M05/triage/t017-surah-latin-verse-error.png`
- **Notes:** `ChaptersTable` dialog title and `LevelDialog` chapter options use `name_simple`; pick `name_arabic` for ar and isolate the number.
- **Root cause (Agent 3, fix cycle 1):** `LevelDialog` options and the `ChaptersTable` edit-names title rendered `{number}. {name_simple}` in every language; in an RTL line "1. Al-Fatihah" reorders to "Al-Fatihah .1".
- **Fix:** New `curriculum/chapterLabel.ts` → `curriculum.quran.chapterLabel`: ar "1 - الفاتحة" (Arabic name, no full stop to reorder), en "1. Al-Fatihah". Used by the picker and the dialog title. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `chapterLabel.test.ts` (ar/en); `ChaptersTable.test.tsx` "titles the edit dialog with the Arabic name in Arabic (ETQAN-QA-563)". Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-563-before.png` vs `ETQAN-QA-563-after.png (dialog title '1 - الفاتحة'); picker options '1 - الفاتحة' (AR) / '1. Al-Fatihah' (EN) checked live` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-564: Levels can be reordered only after filtering to one course; the default view shows no order controls and no hint
- **Feature:** M05 Catalogue. **Severity:** P4. **Type:** copy. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-018); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. `/app/catalogue/levels` ("كل الدورات"): rows have only تعديل/حذف.
  2. Filter to "M05 دورة التلاوة المعدلة": ↑/↓ appear.
- **Expected:** A hint "اختر دورة لترتيب مستوياتها" (ordering is per course).
- **Actual:** No order control and no hint on the default view.
- **Evidence:** `qa/manual/screens/M05/M05-F-018-level-order-hidden.png`, `qa/manual/screens/M05/triage/t012-level-dialog.png`, `qa/manual/screens/M05/triage/t018-level-order-after-filter.png`
- **Notes:** Per-course ordering is reasonable; only the hint is missing.
- **Verification status:** OPEN

---

## ETQAN-QA-565: Course materials list shows only "الملف"/"الرابط": no file name or URL, nothing to open
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-020); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. `/app/catalogue/content` → course M05 → look at "الملف / الرابط".
- **Expected:** File name (and size) or the URL, clickable so the admin can check what students get.
- **Actual:** Cell reads just "الملف"; no link in the table (0 anchors); the edit dialog shows an empty file picker for a file material.
- **Evidence:** `qa/manual/screens/M05/M05-F-020-material-file-not-openable.png`, `qa/manual/screens/M05/triage/t020-materials-list.png`
- **Notes:** Teachers get a تنزيل button on their page; admins don't.
- **Verification status:** OPEN

---

## ETQAN-QA-566: Educational content: the chosen course is forgotten on refresh (not in the URL)
- **Feature:** M05 Catalogue. **Severity:** P4. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-021); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. `/app/catalogue/content` → choose a course → reload.
- **Expected:** Same course still chosen (`?course=10`).
- **Actual:** "اختر دورة." with an empty picker.
- **Evidence:** `qa/manual/screens/M05/M05-F-021-content-course-lost-on-refresh.png`, `qa/manual/screens/M05/triage/t021-reload-loses-course.png`
- **Verification status:** OPEN

---

## ETQAN-QA-567: Arabic link hint is scrambled: "أدخل رابطًا يبدأ بـ https://." renders with "https://" broken and the stop misplaced
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-022); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. Content → إضافة مادة → الرابط → عنوان الرابط `not a url` → إضافة مادة.
- **Expected:** "https://" readable (LTR-isolated).
- **Actual:** The red hint shows "...بـ https:://."/"//:https" - bidi reordering of the Latin run and punctuation.
- **Evidence:** `qa/manual/screens/M05/M05-F-022-https-hint-scrambled.png`, `qa/manual/screens/M05/triage/t022-https-hint.png`
- **Notes:** Wrap the URL in an LTR isolate (`\u2066https://\u2069`) in the ar string.
- **Root cause (Agent 3, fix cycle 1):** `ar/content.json` `errors.urlInvalid` (and the same text in `ar/recorded.json` `videos.urlInvalid`) had a bare "https://." in an Arabic sentence; the bidi algorithm reorders the neutral ":", "/" and "." around it.
- **Fix:** "https://" wrapped in an LTR isolate (U+2066…U+2069) in both strings. The same pattern in `ar/website.json`/`ar/scheduling.json` (other areas) is noted in `qa/coverage-gaps.md`. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `dashboard/src/locales/catalogue-bidi.test.ts` (both hints isolate https://). Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-567-before.png` vs `ETQAN-QA-567-after.png, -after-zoom.png (text is 'بـ U+2066https://U+2069.', renders intact)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-568: Deleting a link material warns "سيُحذف ملفها أيضًا" (its file will be deleted) though a link has no file
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-023); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. Content → course → add a link material → حذف on its row.
- **Expected:** For a link: "هل تريد حذف هذه المادة؟" only.
- **Actual:** "هل تريد حذف هذه المادة؟ سيُحذف ملفها أيضًا."
- **Evidence:** `qa/manual/screens/M05/M05-F-023-link-delete-mentions-file.png`, `qa/manual/screens/M05/triage/t023-link-delete-mentions-file.png`
- **Notes:** My test link "M05T رابط" was deleted after the repro.
- **Root cause (Agent 3, fix cycle 1):** `ContentAdmin` used one confirm text, `content.deleteConfirm` ("…سيُحذف ملفها أيضًا."), for every material.
- **Fix:** A material with `has_file: false` (a link) uses the new `content.deleteConfirmLink` ("هل تريد حذف هذه المادة؟"); a file keeps the old text. ar/en. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `ContentAdmin.test.tsx` "warns about the file only when the material has one (ETQAN-QA-568)". Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-568-before.png` vs `ETQAN-QA-568-after.png (link material: 'هل تريد حذف هذه المادة؟', no file warning)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-569: Recorded-course videos: the "قابل للتنزيل" column is blank instead of نعم/لا
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-027); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. `/app/catalogue/recorded/3` → الفيديوهات → إضافة فيديو, النوع ملف, tiny mp4, المدة 00:00:03 → حفظ.
- **Expected:** "قابل للتنزيل" shows نعم/لا for every row.
- **Actual:** The cell is empty for both rows.
- **Evidence:** `qa/manual/screens/M05/M05-F-027-video-added-no-toast-empty-download.png`, `qa/manual/screens/M05/triage/t027-video-added.png`
- **Notes:** Not reproduced: "no toast" - "تم حفظ الفيديو." appears. Typing the duration by hand is the current design (no media probing), not filed. My test video M05TV2 was deleted.
- **Root cause (Agent 3, fix cycle 1):** `VideosTab` rendered the column title "قابل للتنزيل" for a downloadable video and an empty string otherwise, so not-downloadable rows were blank.
- **Fix:** The cell shows نعم / لا (`recorded.filters.yes`/`no`). Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `VideosTab.test.tsx` "lists rows in order…" now asserts No / Yes per row. Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-569-before.png` vs `ETQAN-QA-569-after.png (column shows لا)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-570: New consultation without a description fails with the raw DB constraint name 'انتهك القيد "consult_product_has_description"'; no field is marked required
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-028); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. `/app/catalogue/consultations` → إضافة استشارة; names + السعر 100; الحجز: المدة 45; المعلمون: tick Ahmad, 50 → حفظ; back to التفاصيل.
- **Expected:** A plain message "اكتب وصفًا بالعربية أو بالإنجليزية" (and the requirement shown before saving).
- **Actual:** Under الوصف (إنجليزي): `انتهك القيد "consult_product_has_description"`; `400 POST /api/v1/consultations/products/`. With an Arabic description only it saves, so the red text under the English field also misleads.
- **Evidence:** `qa/manual/screens/M05/M05-F-028-consult-raw-constraint.png`, `qa/manual/screens/M05/triage/t028-consult-raw-constraint.png`
- **Notes:** The serializer lets the DB check raise; validate "at least one description" in the product service/serializer with a coded message.
- **Root cause (Agent 3, fix cycle 1):** `create_product`/`update_product` left the "one description" rule to `full_clean`, which reports the DB check by name; Django translates that to 'انتهك القيد "consult_product_has_description"'. The dialog had no check of its own.
- **Fix:** Backend `consultations/services/products.py::_check_description` raises "Write a description in Arabic or English." on `description_en` (same field as before) before `full_clean`; mapped in `server-messages.ts`. `ProductDialog` checks it before sending and shows "اكتب وصفًا بالعربية أو بالإنجليزية." under the Arabic description. Backend + dashboard branches `qa/manual-2026-10`, not committed.
- **Regression test:** pytest `consultations/tests/test_products.py::test_missing_description_is_a_sentence_not_the_constraint_name`; Vitest `ProductDialog.test.tsx` "asks for a description in words before sending (ETQAN-QA-570)". Evidence: `qa/manual/evidence/M05/fix-1/` (pytest.txt 29 passed, ruff.txt clean, lint-imports.txt 54 kept) and the dashboard runs (tsc.txt, vitest-related.txt).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-570-before.png` vs `ETQAN-QA-570-after.png (dialog switches to التفاصيل with 'اكتب وصفًا بالعربية أو بالإنجليزية.'); pytest consultations 388 passed` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-571: Consultation products list: the name (the only way to edit) looks like plain black text, no edit action on the row
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-029); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. `/app/catalogue/consultations`.
- **Expected:** Name styled as a link (as on courses/packages) or a تعديل button.
- **Actual:** Name is a `<button>` with color rgb(25,28,27), no underline, cursor default.
- **Evidence:** `qa/manual/screens/M05/M05-F-029-consult-row-not-clickable-looking.png`, `qa/manual/screens/M05/triage/t029-consult-list.png`
- **Notes:** Unlabelled filters on this page are covered by ETQAN-QA-551.
- **Root cause (Agent 3, fix cycle 1):** `ProductsAdmin` styled the name button `font-medium` only: default text colour, no hover underline, no pointer cursor, unlike the course/package name links.
- **Fix:** The name button uses the same link look as `CatalogueList` (`text-primary-text`, hover underline, `cursor-pointer`). Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `ProductsAdmin.test.tsx` "styles the editable name as a link (ETQAN-QA-571)". Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-571-before.png` vs `ETQAN-QA-571-after.png (AR), -after-en.png: name in link colour` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-572: Consultation "المعلمون" tab lists only opted-in teachers with no explanation; "نصيب المعلم (٪)" has no hint
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-030); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. إضافة استشارة → tab المعلمون.
- **Expected:** A note: "يظهر هنا المعلمون الذين فعّلوا الاستشارات - فعّلها من صفحة المعلم", and what the share is taken from.
- **Actual:** One checkbox (Ahmad) out of ~25 teachers, no help text.
- **Evidence:** `qa/manual/screens/M05/M05-F-030-consult-only-one-teacher.png`, `qa/manual/screens/M05/triage/t030-consult-teachers-tab.png`
- **Notes:** Opt-in is by design (consultations.md: only opted-in Consultants); only the explanation is missing.
- **Root cause (Agent 3, fix cycle 1):** By design only opted-in teachers can be added (consultations.md, `Consultant.offers`), but the Teachers tab said so only when NO teacher had opted in, and the share field had no explanation.
- **Fix:** A note under the "المعلمون" legend (only teachers with «يقدم استشارات» on are listed; turn it on from the teacher's page) and a hint tied to "نصيب المعلم (٪)" by `aria-describedby` (part of each completed consultation's paid amount; empty = 0%). ar/en. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `ProductDialog.test.tsx` "explains who is listed on the Teachers tab and what the share is (ETQAN-QA-572)". Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-572-before.png` vs `ETQAN-QA-572-after.png (opt-in hint + share hint)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-573: Phone (375): Levels and Qur'an chapters pages are wider than the screen (451 px / 555 px), title and menu button cut off
- **Feature:** M05 Catalogue. **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-034); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. AR, 375x812: open `/app/catalogue/levels` and `/app/catalogue/quran`; `eval document.documentElement.scrollWidth`.
- **Expected:** scrollWidth 375; the table scrolls inside its own box (as fixed in ETQAN-QA-204/426).
- **Actual:** levels 451 (table 501 in a 341 box), quran 555 (table 601): page opens scrolled sideways, "ويات" title cut, hamburger off-screen.
- **Evidence:** `qa/manual/screens/M05/M05-F-034-mobile-levels-page-wider.png`, `qa/manual/screens/M05/M05-F-034b-mobile-quran-wider.png`, `qa/manual/screens/M05/triage/t034-mobile-levels.png`, `qa/manual/screens/M05/triage/t034-mobile-quran.png`
- **Notes:** Recorded courses and consultations are 375 wide with the table scrolling in its box - the accepted pattern, not part of this bug.
- **Root cause (Agent 3, fix cycle 1):** Same as ETQAN-QA-204: the table scrollers in `LevelsList` and `ChaptersTable` were not positioned, so the `sr-only` (absolute) span in the actions header escaped the scroll box and was placed against the page. Measured live at 375: the only off-screen elements were "تعديل المستوى" / "تعديل الأسماء" (scrollWidth 451 / 555).
- **Fix:** `relative` on both scrollers. Dashboard branch `qa/manual-2026-10`, not committed.
- **Regression test:** `LevelsList.test.tsx` and `ChaptersTable.test.tsx` "keeps the sr-only header inside its scroller on a phone (ETQAN-QA-573)". Before: `qa/manual/screens/M05/fix/ETQAN-QA-573-before-quran.png`. Evidence: `qa/manual/evidence/M05/fix-1/` (tsc.txt exit 0; vitest.txt 15 files, then vitest-errors-rerun.txt after a test-assertion fix; vitest-related.txt 55 files / 336 tests pass; biome.txt clean).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28). Before/after: `qa/manual/screens/M05/fix/ETQAN-QA-573-before.png` vs `ETQAN-QA-573-after.png (levels), -after-quran.png: scrollWidth 375 at 375x812 (was 451/555)` (all in `qa/manual/screens/M05/fix/`). Gate checks: `qa/manual/evidence/M05/gate-1/` (tsc exit 0, vitest 63 files / 384 tests pass); diff reviewed, root-cause fix, no test hacks.

---

## ETQAN-QA-574: New country-price row shows "السعر ()" with empty brackets and currency "—"
- **Feature:** M05 Catalogue. **Severity:** P4. **Type:** copy. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M05 (M05-F-035); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa` (M05 test data: course 10, packages 20/21, recorded course 3).
- **Reproduction steps:**
  1. `/app/catalogue/packages/21` → إضافة دولة.
- **Expected:** Label without empty brackets (and currency preset).
- **Actual:** "السعر () *" until a currency is chosen.
- **Evidence:** `qa/manual/screens/M05/M05-F-035-country-price-empty-parens.png`, `qa/manual/screens/M05/triage/t010-035-package21-main.png`
- **Notes:** Same pattern as ETQAN-QA-215 (subscription form), here in `CountryPricesCard`.
- **Verification status:** OPEN

---

## ETQAN-QA-575: Subscription form accepts fewer weekly slots than the package's sessions per week, with no hint; the term then can't deliver the promised total
- **Feature:** M05 Catalogue (package → subscription form). **Severity:** P3. **Type:** UX / functional. **Easy P3:** yes (dashboard-only hint). **Priority:** medium
- **Environment:** local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL
- **Found by:** Agent 1, M05 confirmation sweep (M05-F-036); reproduced by Agent 2 on 2026-10-28 (final gate).
- **Preconditions:** qa-admin@qa.etqan.test, package 22 "M05 باقة المسح" (3 sessions/week, 45 min, 2 months, 450.50 SAR → 24 sessions).
- **Reproduction steps:**
  1. `/app/scheduling/subscriptions/new` → فردي, حمزة القاضي, حفظ القرآن الكريم, الشيخ أحمد الحداد, الباقة "M05 باقة المسح", يبدأ 01/11/2026.
  2. المواعيد الأسبوعية: tick only السبت, 20:00, 45 → أنشئ الاشتراك.
- **Expected:** the form tells the admin the package is 3 sessions a week and warns when the chosen slots (1/week) cannot fit the 24 sessions before the end date (a warning, not a block, since the docs don't require a match).
- **Actual:** no hint at all; the summary reads "24 حصة، مدة كل منها 45 دقيقة، خلال شهرين". Subscription 110 is created with الحصص المتبقية 24, ends 31/12/2026, one Saturday slot (≈9 sessions possible in the term); invoice INV-000181 450.50 ر.س. bills all 24. The subscription form never reads `sessions_per_week` (only `catalogue/PackageForm.tsx` / `sessions-total.ts` do).
- **Evidence:** `qa/manual/screens/M05/M05-F-036-one-slot-for-3-per-week-form.png`, `qa/manual/screens/M05/M05-F-036-one-slot-for-3-per-week-sub.png`, `qa/manual/screens/M05/triage/t036-form-no-warning.png`, `qa/manual/screens/M05/triage/t036-sub110.png`
- **Notes:** `docs/features/subscriptions.md` / `catalogue.md` define the total as sessions_per_week × weeks but set no rule on slot count, so this is a missing warning rather than a broken rule. Suggested fix: under the slots, "الباقة: 3 حصص أسبوعيًا — اخترت 1" when the ticked weekdays across slot rows are fewer than `sessions_per_week`. The admin can still add slots later via "أضف مواعيد".
- **Verification status:** OPEN

---

## --- M01 manual bugs ---

ENV: local docker stack (backend + dashboard with uncommitted qa/manual-2026-10 fixes), Etqan staff console `http://etqan.localhost/admin/`, Chromium via `qa/manual/tools/step.mjs`, 1440x900, EN. **Tag:** REAL. Found by Agent 1 (M01), reproduced by Agent 2 on 2026-10-28. Accounts: `ops@qa.etqan.test` (superuser), `ops-view@qa.etqan.test` (view only).

## ETQAN-QA-800: Add user in the console stores the password as plain text (the new staff member can't sign in); the change page shows the hash in an editable box
- **Feature:** M01 Etqan console › Identity › Users (`identity/admin.py:UserAdmin` is a plain `ModelAdmin`). **Severity:** P1 (a credential stored unhashed in `identity_user.password`; no working way to create an Etqan staff account in the console; editing a user's hash box breaks that account). **Type:** data / security. **Easy P3:** no. **Priority:** high
- **Environment:** see ENV above.
- **Preconditions:** superuser `ops@`.
- **Reproduction steps:**
  1. `/admin/identity/user/add/` → the first field "Password:" is a plain visible text input. Type `Tmp-M01-Staff-2026!`, Email `qa-tmp-m01-staff@qa.etqan.test`, tick Is staff → SAVE (done by Agent 1, user id 9 kept).
  2. `select left(password,25) from identity_user where id=9` → `Tmp-M01-Staff-2026!` (plain text; id 2 shows `argon2$argon2id$v=19$m=10…`).
  3. `/admin/login/` with that email and password → "Please enter the correct email and password for a staff account."
  4. `/admin/identity/user/2/change/` → Password field holds `argon2$argon2id$v=19$m=102400,t=2,p=…` in an editable text box; Last login (and last-login ip/device/timezone, Date joined) editable too.
- **Expected:** Django's user admin pattern: `UserCreationForm` (password + confirm, hashed via `set_password`, validators run), change page with `ReadOnlyPasswordHashField` and a "change password" link; audit fields read-only.
- **Actual:** as above; the raw value is saved unhashed and the account can never sign in.
- **Evidence:** `qa/manual/screens/M01/triage/t024a-add-user-plain-password.png`, `qa/manual/screens/M01/triage/t024b-change-user-hash-editable.png`, `qa/manual/screens/M01/triage/t024c-new-staff-cannot-login.png`; Agent 1: `qa/manual/screens/M01/M01-F-024-user-password-hash-editable.png`, `M01-F-024b-new-staff-cannot-login.png`.
- **Notes:** Fix: base `UserAdmin` on `django.contrib.auth.admin.UserAdmin` (email as username) or add `add_form`/`form` with hashing; make last-login fields read-only. Cleanup: throwaway user id 9 holds a plain-text password; delete or reset it after the fix.
- **Root cause:** `identity/admin.py:UserAdmin` was a plain `ModelAdmin`, so the `password` model field was a text input saved as typed and the hash was editable on change.
- **Fix:** `UserAdmin` now extends `django.contrib.auth.admin.UserAdmin` with email-as-username forms (`AdminUserCreationForm` subclass: password + confirm, validators, `set_password`; `UserChangeForm`: read-only hash with the change-password link); sign-in/audit fields read-only. Throwaway user id 9 still holds a plain-text password: reset or delete it.
- **Regression test:** `backend/etqan/identity/tests/test_console_users.py` (add hashes + signs in; mismatch refused; hash field read-only).
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28); re-confirmed at M01 final gate cycle 2 (2026-10-28): Add user form has password1/password2 (+ usable_password), no plain password input; user 10 change page shows the read-only argon2 hash + Reset password; ids 9 and 10 hold argon2 hashes in the DB; qa-tmp-m01-gate@ signs in (no-permission home). Evidence `qa/manual/screens/M01/fix/g2-800-recheck-change.png`, `g2-800-recheck-login.png`.
- **Retest (Agent 2, 2026-10-28, REAL):** Add user: mismatch refused ("The two password fields didn't match."), match saved as argon2 hash (DB id 10), new staff signs in (no-perm home); change page shows read-only hash + Reset password; sign-in fields read-only. Cleanup done: throwaway id 9 reset through the console (now argon2). Evidence qa/manual/screens/M01/fix/ETQAN-QA-800-after.png (g-800-mismatch.png, g-800-saved.png, g-800-newstaff-login.png, g-800-reset-id9.png).

---

## ETQAN-QA-801: Suspend / Reactivate / Copy features run on one click with no confirmation page; "Suspended 1 academies."
- **Feature:** M01 Etqan console › Tenants › Academies actions (`tenants/admin.py` `suspend_academies`, `reactivate_academies`, `copy_features`). **Severity:** P2 (one mis-click with "select all" takes every academy offline or overwrites every academy's switches; no undo summary). **Type:** functional. **Easy P3:** no. **Priority:** high
- **Environment:** see ENV above.
- **Reproduction steps:**
  1. `/admin/tenants/academy/?q=qa-tmp-m01b` → tick QA Tmp M01b → Action "Suspend selected academies" → Run.
  2. Same with "Reactivate selected academies".
- **Expected:** an intermediate "Are you sure?" page listing the academies (and for Copy features, the source and what changes), like Django's delete action; correct plural ("1 academy").
- **Actual:** acted at once: "Suspended 1 academies.", "Reactivated 1 academies." (DB status suspended → active). The "Copy features from" select is always shown, even for Suspend/Reactivate, and lists academies in no order including suspended ones (ordering: see ETQAN-QA-814).
- **Evidence:** `qa/manual/screens/M01/triage/t006a-suspend-no-confirm.png`, `qa/manual/screens/M01/triage/t006b-reactivate-no-confirm.png`; Agent 1: `qa/manual/screens/M01/M01-F-006-suspend-no-confirm.png`.
- **Notes:** ETQAN-QA-007 (no history entry for these actions) and ETQAN-QA-010 (domain actions confirm nothing) are related and stay separate.
- **Root cause:** The three academy actions ran immediately (no intermediate page) and built the message with a fixed plural.
- **Fix:** New `etqan/platform/admin_confirm.py` + `templates/admin/etqan_confirm_action.html`: Suspend / Reactivate list the academies (subdomain, current status) and what happens; Copy features lists, per academy, which switches turn on/off; each runs only on `confirm=yes`. Messages use `plural()` ("1 academy").
- **Regression test:** `backend/etqan/tenants/tests/test_admin_console_qa.py` (status actions ask first then run; copy lists the changes and changes nothing before confirming); existing action tests now post `confirm=yes`.
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Suspend/Reactivate on qa-tmp-m01b open a confirmation page ("Suspend 1 academy?", subdomain + current status, note); DB unchanged until "Yes, suspend"; then "Suspended 1 academy."; reactivated the same way (now active). Copy features lists the switches that turn on (from qaother) or "no change" (from qa-tmp-m01a); "No, take me back" changed nothing (DB features identical). Evidence qa/manual/screens/M01/fix/ETQAN-QA-801-after.png (g-801-*.png).

---

## ETQAN-QA-802: An Etqan invoice is voided with no reason and no confirmation; voiding an already-void invoice also says "voided."
- **Feature:** M01 Etqan billing › Etqan invoices, action `void_invoices` (`etqan_billing/admin.py`, `services/invoices.py:void`). **Severity:** P2 (money: voiding an issued invoice frees the month and changes what the academy owes; irreversible and unexplained in the record). **Type:** functional. **Easy P3:** no. **Priority:** high
- **Environment:** see ENV above.
- **Reproduction steps:**
  1. `/admin/etqan_billing/etqaninvoice/` → tick ETQ-2026-09-0001 (void, qa-tmp-m01a; Agent 1 voided it from Draft the same way) → Action "Void the selected invoices (reason above)" → leave Void reason empty → Run.
- **Expected:** a reason is required (`etqan-billing.md` "`void(reason)`"; the invoice has a Void reason field) and the operator confirms; an already-void invoice is reported as such.
- **Actual:** "· ETQ-2026-09-0001: voided." at once; DB `void_reason = ''`. Repeating on the void invoice again says "voided." (the service silently no-ops).
- **Evidence:** `qa/manual/screens/M01/triage/t020-void-no-reason-no-confirm.png`; Agent 1: `qa/manual/screens/M01/M01-F-020-void-without-reason.png`.
- **Root cause:** `void_invoices` passed an empty reason through, had no confirmation, and `services.void` silently no-ops on a void invoice, so the admin printed "voided.".
- **Fix:** `etqan_billing/admin.py:void_invoices`: an empty reason is refused ("Enter the void reason… Nothing was voided."); a confirmation page lists number, academy, total, status and the reason; an already-void invoice reports "already void; nothing changed.".
- **Regression test:** `backend/etqan/etqan_billing/tests/test_admin_console_qa.py` (no reason; asks then voids; already void).
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Empty reason refused ("Enter the void reason… Nothing was voided."); with a reason a confirmation page lists number, academy, total, status and the reason; on a throwaway draft ETQ-2026-08-0001 (qa-tmp-m01b, created for this retest) "Yes, void" voided it with void_reason stored; an already-void invoice reports "already void; nothing changed.". Evidence qa/manual/screens/M01/fix/ETQAN-QA-802-after.png (g-802-*.png).

---

## ETQAN-QA-803: Add academy with a 200-character name (the field's own limit) crashes with a 500 DataError (varchar(120))
- **Feature:** M01 Etqan console › Add academy (`tenants/admin.py:AcademyCreationForm`; provisioning writes the name into a 120-character column, e.g. `site` `name_ar/name_en` max_length 120). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** see ENV above.
- **Reproduction steps:**
  1. `/admin/tenants/academy/add/` → Name "QA Tmp M01c " + "Long name "×20 (field cuts at 200) → Subdomain `qa-tmp-m01c` → Admin email `qa-tmp-m01c-admin@qa.etqan.test` → SAVE.
- **Expected:** a form error ("at most 120 characters") or the name accepted.
- **Actual:** HTTP 500 "DataError at /admin/tenants/academy/add/ — value too long for type character varying(120)". Nothing created (no row, no schema).
- **Evidence:** `qa/manual/screens/M01/triage/t007-after.png`; Agent 1: `qa/manual/screens/M01/M01-F-007-long-name-500.png`.
- **Notes:** Same class as ETQAN-QA-016 (the `create_academy` command), different entry point. Fix: cap the form's name at the shortest column it is copied to.
- **Verification status:** OPEN

---

## ETQAN-QA-804: A suspended academy's Arabic login shows the English "This academy is suspended. Please contact Etqan."; the header shows the host name; a signed-in user is logged out without a word
- **Feature:** M01 suspension, seen by the academy (`tenants/middleware.py` answers 403 `tenant.suspended`; the dashboard login doesn't map the code). **Severity:** P3. **Type:** translation. **Easy P3:** yes (map `tenant.suspended` to a translated message). **Priority:** medium
- **Environment:** see ENV above; dashboard AR.
- **Reproduction steps:**
  1. Suspend qa-tmp-m01b (console action).
  2. `http://qa-tmp-m01b.etqan.localhost/app/` in Arabic → fill an email and password → تسجيل الدخول.
- **Expected:** an Arabic message ("هذه الأكاديمية موقوفة حاليًا. تواصل مع إتقان.") and the academy name in the header; a user signed in at suspension time told why they were signed out.
- **Actual:** ".This academy is suspended. Please contact Etqan" in English inside the Arabic form (full stop at the wrong end); header "qa-tmp-m01b.etqan.localhost" (branding request 403); subtitle "سجّل الدخول لمتابعة دراستك". Agent 1: a signed-in admin is returned to the login page with no message.
- **Evidence:** `qa/manual/screens/M01/triage/t005-suspended-login-english-ar.png`; Agent 1: `qa/manual/screens/M01/M01-F-005-suspended-msg-english.png`.
- **Root cause:** `LoginForm` showed the middleware's English `detail` for 403 `tenant.suspended`; nothing told a user sent back to the login why.
- **Fix:** `dashboard/src/features/identity/components/LoginForm.tsx` maps `tenant.suspended` to `auth.academySuspended` (ar/en/es) on submit, and shows it at once when the sign-in options request is refused with that code (the case of a signed-in user logged out by the suspension). Header host name: not fixed (the branding request is blocked by the middleware): proposal in coverage-gaps.md.
- **Regression test:** `dashboard/src/features/identity/components/LoginForm.test.tsx` › "a suspended academy" (Arabic up front; mapped on submit).
- **Verification status:** VERIFIED (message) + PROPOSAL-accepted (header host name) (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Suspended qa-tmp-m01b: Arabic login shows "هذه الأكاديمية موقوفة حاليًا. تواصل مع إتقان." up front and on submit; English "This academy is suspended for now. Please contact Etqan.". Header host name (part 2) accepted as PROPOSAL (P3; policy call on letting the branding read through the suspension middleware; coverage-gaps.md). Evidence qa/manual/screens/M01/fix/ETQAN-QA-804-after.png (g-804-ar-upfront.png, g-804-ar-submit.png, g-804-en-upfront.png).

---

## ETQAN-QA-805: The first-admin (and every) invite link opens the "reset password" page: "تعيين كلمة مرور جديدة" / "إعادة تعيين كلمة المرور"
- **Feature:** M01 Add academy → invite → `dashboard/src/routes/reset-password.tsx` (also accepts invites, `sign-in.md`). **Severity:** P3. **Type:** copy. **Easy P3:** yes (neutral wording "عيّن كلمة المرور" / "Set your password" that fits both). **Priority:** medium
- **Environment:** see ENV above; dashboard AR.
- **Reproduction steps:**
  1. Mailpit: "[QA Tmp M01b] عيّن كلمة المرور" (the invite to `qa-tmp-m01b-admin@`, text "أُنشئ لك حساب. عيّن كلمة المرور للبدء").
  2. Open its link `/app/reset-password?uid=…&token=…` in Arabic (not submitted).
- **Expected:** wording for a new account that matches the email ("عيّن كلمة المرور").
- **Actual:** title "تعيين كلمة مرور جديدة", field "كلمة مرور جديدة", button "إعادة تعيين كلمة المرور"; Agent 1 saw success "تمت إعادة تعيين كلمة المرور".
- **Evidence:** `qa/manual/screens/M01/triage/t002-invite-opens-reset-page.png`; Agent 1: `qa/manual/screens/M01/M01-F-002-invite-says-reset.png`.
- **Root cause:** The reset-password page (also the invite landing) used reset-only wording in `auth.json`.
- **Fix:** Neutral wording in ar/en/es `auth.json`: title "عيّن كلمة المرور" / "Set your password", button "حفظ كلمة المرور" / "Save password", success "تم حفظ كلمة المرور…" / "Password saved…". Field label unchanged. e2e specs updated to the new button.
- **Regression test:** `dashboard/src/routes/reset-password.test.tsx` (Arabic invite wording; updated title/button).
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Real invite link from Mailpit (qa-tmp-m01b admin), not submitted: AR "عيّن كلمة المرور" / button "حفظ كلمة المرور"; EN "Set your password" / "Save password". Evidence qa/manual/screens/M01/fix/ETQAN-QA-805-after.png (g-805-ar.png, g-805-en.png).

---

## ETQAN-QA-806: Add academy: Subdomain isn't marked required and its rule only appears after an error
- **Feature:** M01 Etqan console › Add academy (`AcademyCreationForm`; the model field is `blank=True` for the public row). **Severity:** P3. **Type:** copy. **Easy P3:** yes (`required=True` + help text). **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/tenants/academy/add/` → clear Timezone and Currency → SAVE.
- **Expected:** Subdomain bold like the other required fields, with help text "1–32 lowercase letters, digits or hyphens; becomes <sub>.etqan…".
- **Actual:** labels with `required`: Name, Timezone, Currency, Admin email; "Subdomain:" plain; after submit "Use 1-32 lowercase letters, digits or hyphens; it cannot start or end with a hyphen."
- **Evidence:** `qa/manual/screens/M01/triage/t001-subdomain-not-marked.png`; Agent 1: `qa/manual/screens/M01/M01-F-001-subdomain-required-not-marked.png`.
- **Root cause:** `Academy.subdomain` is `blank=True` (public row), so the ModelForm field wasn't required and had no help text.
- **Fix:** `AcademyCreationForm.__init__` sets `subdomain.required = True` and a help text with the rule and the resulting address.
- **Regression test:** `test_admin_console_qa.py::test_add_academy_marks_subdomain_required_with_its_rule`.
- **Root cause (Agent 3, fix cycle 2, 2026-10-28):** (reopened) The admin outputs help text as HTML, so the literal `<subdomain>` was parsed as a tag and hidden.
- **Fix:** `AcademyCreationForm.__init__` builds the help text with `format_html(..., "<subdomain>", TENANT_BASE_DOMAIN)`, so the placeholder is escaped and shows as text.
- **Regression test:** `etqan/tenants/tests/test_admin_console_qa.py::test_add_academy_marks_subdomain_required_with_its_rule` now asserts on the rendered page: `becomes &lt;subdomain&gt;.` present and no raw `<subdomain>`. Evidence `qa/manual/evidence/M01/fix-2/`.
- **Verification status:** VERIFIED (Agent 2 final gate, cycle 2, 2026-10-28)
- **Retest 2 (Agent 2, M01 final gate cycle 2, 2026-10-28, REAL):** Add academy: Subdomain label `required` (bold); help text renders "…The academy's address becomes <subdomain>.etqan.localhost; it can't be changed later." (HTML `&lt;subdomain&gt;`); original step (clear Timezone/Currency → SAVE) shows "This field is required." with the help text still visible; nothing created. Before `qa/manual/screens/M01/fix/g-806-add-form.png`, after `qa/manual/screens/M01/fix/ETQAN-QA-806-after-cycle2.png`, `qa/manual/screens/M01/fix/g2-806-subdomain-row.png`, `qa/manual/screens/M01/fix/g2-806-submit-empty.png`.
- **Retest (Agent 2, 2026-10-28, REAL):** Subdomain is now bold/required (half fixed), but the help text renders as "…The academy's address becomes .etqan.localhost; it can't be changed later.": the literal `<subdomain>` in `AcademyCreationForm.__init__` help_text is output unescaped by the admin (help text is HTML) and the browser parses it as an element (`innerHTML` shows `<subdomain>.etqan.localhost…</subdomain>`), so the operator is told a wrong address. The regression test only checks `"1-32 lowercase letters" in help_text`, not the rendered page. Fix: escape it (`&lt;subdomain&gt;`, `format_html`/`escape`) or word it as "your-subdomain.etqan…", and assert on the rendered HTML. Evidence qa/manual/screens/M01/fix/ETQAN-QA-806-after.png (g-806-add-form.png).

---

## ETQAN-QA-807: Academy feature switches: labels squeezed into a ~170 px column, the bracketed Arabic name breaks across lines
- **Feature:** M01 Etqan console › Academy change page › Features fieldsets. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes (CSS: let the checkbox label use the row width / `white-space: nowrap` on the Arabic part). **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/tenants/academy/22/change/` → scroll to "Features: People" / "Features: Teaching".
- **Expected:** each switch on one line (≈1,000 px free), Arabic name kept whole.
- **Actual:** "Family accounts (نظام حسابات" / "العائلات)", "Student registration" / "waiting list (قائمة انتظار تسجيل" / "الطلاب)", "Teachers record" / "attendance (تسجيل المعلم" / "للحضور)". Page 6,160 px tall with 88 switch checkboxes.
- **Evidence:** `qa/manual/screens/M01/triage/t003-feature-labels-wrap.png`; Agent 1: `qa/manual/screens/M01/M01-F-003-feature-labels-wrap-brackets.png`.
- **Notes:** Agent 1's wish for per-switch descriptions and an "on" summary is an enhancement, not part of this bug.
- **Root cause:** Django's `.aligned label` is 160 px wide, also for checkbox labels.
- **Fix:** New `backend/etqan/templates/admin/base_site.html` (extends the original) with console CSS: checkbox labels use the row width (`width:auto; flex:1 1 auto`).
- **Regression test:** CSS only; no unit test (visual check by Agent 2).
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** qa-tmp-m01b change page: every switch on one line with its bracketed Arabic name whole ("Family accounts (نظام حسابات العائلات)"). Evidence qa/manual/screens/M01/fix/ETQAN-QA-807-after.png (g-807-features.png).

---

## ETQAN-QA-808: Academy history says "Changed Family accounts … and Contracts …" / "Changed Status." without saying which way
- **Feature:** M01 Etqan console › Academy › History (`django_admin_log` change messages). **Severity:** P3 (audit can't tell a switch-on from a switch-off). **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/tenants/academy/19/history/` (Agent 1 had ticked Contracts and unticked Family accounts in one save, then set Status Suspended).
- **Expected:** "Family accounts: on → off; Contracts: off → on", "Status: active → suspended".
- **Actual:** "Changed Family accounts (نظام حسابات العائلات) and Contracts (نظام العقود).", "Changed Status." Times show no zone (UTC).
- **Evidence:** `qa/manual/screens/M01/triage/t004-history-no-direction.png`; Agent 1: `qa/manual/screens/M01/M01-F-004-history-no-direction.png`.
- **Notes:** Related to ETQAN-QA-007 (action-driven suspends leave no entry at all).
- **Verification status:** OPEN

---

## ETQAN-QA-809: Domains list: one very long host name pushes Tenant, Status, Primary, Custom and Verified out of view
- **Feature:** M01 Etqan console › Tenants › Domains changelist. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes (CSS `word-break`/ellipsis on the domain column). **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/tenants/domain/` (no search).
- **Expected:** every column visible; long hosts wrap or ellipsize.
- **Actual:** only the DOMAIN header is visible; the `aaaa….bbbb…` row (QA Tmp One) widens the column past the table box; the other columns are off to the right. With a search the columns return.
- **Evidence:** `qa/manual/screens/M01/triage/t008-domains-long-host.png`; Agent 1: `qa/manual/screens/M01/M01-F-008-domains-long-host-hides-columns.png`.
- **Root cause:** A long host has no break opportunity, so the auto table layout widened the Domain column past the box.
- **Fix:** Same `admin/base_site.html`: `#changelist .field-domain { overflow-wrap: anywhere }`.
- **Regression test:** CSS only; fixer smoke shot `qa/manual/screens/M01/fix/fixer-smoke-domains.png` (not a verification).
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Domains list (no search): long aaaa….co host wraps inside the Domain column; Tenant/Status/Primary/Custom/Verified all visible (table scrollWidth 791 = box 791). Evidence qa/manual/screens/M01/fix/ETQAN-QA-809-after.png (g-809-table.png).

---

## ETQAN-QA-810: The domain change page is read-only but still shows Save / Save and add another / Save and continue editing
- **Feature:** M01 Etqan console › Domain change page (`DomainAdmin.get_readonly_fields`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes (hide the save row, e.g. `show_save*=False`, or show the DNS target/actions instead). **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** Domains → search `example.test` → open `www.qa-tmp-m01a.example.test`.
- **Expected:** no save buttons on a page with nothing editable; ideally the CNAME target (shown only on Add) and how to re-check DNS.
- **Actual:** all fields plain text, three save buttons; Save says "changed successfully" with nothing changed (Agent 1).
- **Evidence:** `qa/manual/screens/M01/triage/t009-domain-readonly-save-buttons.png`; Agent 1: `qa/manual/screens/M01/M01-F-009-domain-page-readonly-save-buttons.png`.
- **Notes:** A paid invoice's page (all read-only) shows the same three buttons (`t014a-invoice-inline-raw.png`).
- **Root cause:** Change pages with every field read-only still render Django's submit row.
- **Fix:** `DomainAdmin.change_view` and `EtqanInvoiceAdmin.change_view` pass `show_save*=False` (Django then shows Close).
- **Regression test:** `test_admin_console_qa.py::test_a_domain_page_has_no_save_buttons`; `etqan_billing/tests/test_admin_console_qa.py::test_an_invoice_page_has_no_save_buttons`.
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Domain page www.qa-tmp-m01a.example.test and paid invoice ETQ-2026-10-0001 show only Close, no Save buttons. Evidence qa/manual/screens/M01/fix/ETQAN-QA-810-after.png (g-810-domain-page.png, g-810-816-invoice-page.png).

---

## ETQAN-QA-811: Adding a domain another academy holds says only "Domain with this Domain already exists."
- **Feature:** M01 Etqan console › Add domain (`DomainCreationForm.clean`). **Severity:** P3. **Type:** copy. **Easy P3:** yes (message naming the owner and its status). **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/tenants/domain/add/` → Tenant QA Tmp M01b → Domain `www.qa-tmp-m01a.example.test` (held, disabled, by أكاديمية النور QA Tmp M01) → SAVE.
- **Expected:** "This domain already belongs to أكاديمية النور QA Tmp M01 (Disabled)."
- **Actual:** "Domain with this Domain already exists." Nothing says a disabled domain stays reserved (no delete on domains).
- **Evidence:** `qa/manual/screens/M01/triage/t010-domain-exists-no-owner.png`; Agent 1: `qa/manual/screens/M01/M01-F-010-domain-exists-no-owner.png`.
- **Notes:** Releasing a disabled domain is a design question (proposal), not part of the easy fix. Unordered Tenant select: ETQAN-QA-814.
- **Root cause:** The duplicate was caught only by the model's unique check (generic text).
- **Fix:** `DomainCreationForm.clean` looks up the holder: "This domain already belongs to <academy> (<status>)."
- **Regression test:** `test_admin_console_qa.py::test_a_held_domain_names_the_academy_holding_it`.
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Add domain www.qa-tmp-m01a.example.test for QA Tmp M01b → "This domain already belongs to أكاديمية النور QA Tmp M01 (Disabled)." (Arabic name intact); nothing created. Evidence qa/manual/screens/M01/fix/ETQAN-QA-811-after.png (g-811-held.png).

---

## ETQAN-QA-812: Etqan price / academy pricing forms: "Minor units per batch of units." with no currency and no batch size
- **Feature:** M01 Etqan billing › Prices, Academy pricing (help texts; `pricing.PER`, `ETQAN_BILLING_CURRENCY`). **Severity:** P3 (an operator can enter 150 meaning 150 USD per email; the list only later shows "1.50 USD per 1,000 emails"). **Type:** copy. **Easy P3:** yes (help text naming the currency and each unit's batch). **Priority:** medium
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/etqan_billing/price/add/`; and an Academy pricing record (QA Tmp M01b, Email/Email).
- **Expected:** "In USD cents per batch: email per 1,000 emails, meeting minute per minute, AI per 1,000 tokens… (150 = 1.50 USD)". Academy pricing explains Amount "-" = "uses Etqan's price".
- **Actual:** "Minor units per batch of units." / "Minor units per batch; blank uses Etqan's price."
- **Evidence:** `qa/manual/screens/M01/triage/t011a-price-form-no-currency.png`, `qa/manual/screens/M01/triage/t011b-academypricing-raw-repr.png`; Agent 1: `qa/manual/screens/M01/M01-F-011-price-form-no-currency-batch.png`.
- **Root cause:** The model help texts say only "Minor units per batch".
- **Fix:** Form-level help (no migration): `etqan_billing/admin.py:amount_help()` names Etqan's currency, every unit's batch (new `services.per_text`) and an example ("150 = 1.50 USD"); Academy pricing adds "Blank uses Etqan's price" and explains the free allowance.
- **Regression test:** `etqan_billing/tests/test_admin_console_qa.py::test_the_price_forms_name_the_currency_and_the_batch`.
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Price add and Academy pricing amount help: "In USD minor units (cents), per batch: per conversation, per 1,000 emails, per meeting minute, per 1,000,000 input tokens, per 1,000,000 output tokens. Example: 150 = 1.50 USD." (+ "Blank uses Etqan's price"); free allowance explained. Evidence qa/manual/screens/M01/fix/ETQAN-QA-812-after.png.

---

## ETQAN-QA-813: Console titles, breadcrumbs, messages and Recent actions show developer names: "Price<email/email from 2099-01-01>", "AcademyPricing<22 email/email>", "ConnectFee<22 250bp>", "PlatformAccount<ai, False>"
- **Feature:** M01 Etqan billing + Integrations (`__str__` of `Price`, `AcademyPricing`, `ConnectFee`, `UsageEvent`, `CollectedFee` in `etqan_billing/models.py`; `PlatformAccount` in integrations). **Severity:** P3. **Type:** copy. **Easy P3:** yes (readable `__str__`: "QA Tmp M01b — Email: Etqan price, 500 free a month"). **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** open an Academy pricing record, a Connect fee record and a Platform account; look at the console home "Recent actions".
- **Expected:** a name in words, with the academy's name rather than its database id.
- **Actual:** heading and breadcrumb "AcademyPricing<22 email/email>", "ConnectFee<22 250bp>", "PlatformAccount<ai, False>"; messages "The price "Price<email/email from 2099-01-01>" was added successfully."
- **Evidence:** `qa/manual/screens/M01/triage/t011b-academypricing-raw-repr.png`, `qa/manual/screens/M01/triage/t026-connect-fee-zz.png`, `qa/manual/screens/M01/triage/t021-platform-account-raw-title.png`, `qa/manual/screens/M01/triage/t027-console-home.png`; Agent 1: `M01-F-011b-price-raw-repr.png`, `M01-F-011c-academypricing-raw-repr.png`.
- **Notes:** Found in M01-F-011, F-021 and F-026. The invoice line's name is ETQAN-QA-816.
- **Root cause:** Developer `__str__` on Price, AcademyPricing, ConnectFee, UsageEvent, CollectedFee and PlatformAccount.
- **Fix:** Readable `__str__`: "Email price from 2099-01-01", "<academy>: Email terms", "<academy>: Connect fee", "<academy>: 2,500 Email", "<academy>: 1.50 USD", "Etqan's Email account".
- **Regression test:** `etqan_billing/tests/test_admin_console_qa.py::test_rows_are_named_in_words`; `integrations/tests/test_admin.py::test_each_service_page_explains_only_its_own_keys`.
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Titles/breadcrumbs: "QA Tmp M01b: Email terms", "QA Tmp M01b: Connect fee", "Etqan's AI account", "Etqan's Email account". Evidence qa/manual/screens/M01/fix/ETQAN-QA-813-after.png.

---

- **Final verification (conductor, 2026-10-28):** the full pytest caught `integrations/tests/test_models.py::test_the_rows_name_themselves`, which still expected the old developer `__str__` for PlatformAccount. Its expectation was updated to the intended `"Etqan's Email account"`, and the 6 tests pass. No product change.
## ETQAN-QA-814: Billing "By academy" filters list the platform row "Etqan"; academies appear in no order in every console picker
- **Feature:** M01 Etqan console (`Academy` has no `Meta.ordering`; billing `list_filter = academy` includes `schema_name="public"`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/etqan_billing/academypricing/` and `/admin/etqan_billing/etqaninvoice/` → FILTER › By academy; also the "Copy features from" select (Academies) and the Tenant select (Add domain).
- **Expected:** the 17 academies of the Academies list, sorted by name; never the platform row.
- **Actual:** first entry "Etqan" (the public schema row, absent from the Academies list), then "Etqan QA Other, Other Academy, QA Tmp R1 OK, E2E Journey…, …, Demo Academy, Etqan QA Academy, أكاديمية النور QA Tmp M01, QA Tmp M01b" (id order). The Connect fee academy select correctly excludes "Etqan".
- **Evidence:** `qa/manual/screens/M01/triage/t012-pricing-filter-etqan.png`, `qa/manual/screens/M01/triage/t013-017-invoice-list.png`; Agent 1: `qa/manual/screens/M01/M01-F-012-pricing-filter-etqan-public.png`.
- **Notes:** Also covers the ordering parts of M01-F-006 and M01-F-010.
- **Verification status:** OPEN

---

## ETQAN-QA-815: "etqan" in lower case across the billing console: "Add etqan invoice", "Select etqan invoice to change", "2 etqan invoices", "The etqan invoice line …"
- **Feature:** M01 Etqan billing (`EtqanInvoice` / `EtqanInvoiceLine` have no `verbose_name`). **Severity:** P4. **Type:** copy. **Easy P3:** yes (`verbose_name="Etqan invoice"`). **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/etqan_billing/etqaninvoice/`; the invoice-line list.
- **Expected:** "Etqan" capitalised, as in the sidebar.
- **Actual:** "Select etqan invoice to change", "ADD ETQAN INVOICE" (button capitalises), "2 etqan invoices", "Search etqan invoices", "Select etqan invoice line to view".
- **Evidence:** `qa/manual/screens/M01/triage/t013-017-invoice-list.png`, `qa/manual/screens/M01/triage/t015-lines-list-landing-raw-amounts.png`; Agent 1: `qa/manual/screens/M01/M01-F-013-etqan-lowercase.png`.
- **Verification status:** OPEN

---

## ETQAN-QA-816: Invoice lines show raw minor units: "Setup fee — رسوم الإعداد (1250 USD)" for a 12.50 USD line, unit amount "0", per "1000", list Amount "1250"
- **Feature:** M01 Etqan billing › Invoice page inline and Etqan invoice lines list (`EtqanInvoiceLine.__str__` = `f"{description} ({amount} {currency})"`, raw `amount` in `list_display`). **Severity:** P3 (reads as 1,250 USD; the bracket also lands in the middle of an Arabic description). **Type:** copy. **Easy P3:** yes (format with `services.money`, isolate the description). **Priority:** medium
- **Environment:** see ENV above.
- **Reproduction steps:** open ETQ-2026-10-0001 (QA Tmp M01b) → ETQAN INVOICE LINES; then `/admin/etqan_billing/etqaninvoiceline/`; console home Recent actions.
- **Expected:** "12.50 USD" everywhere, "per 1,000".
- **Actual:** inline group headers "Emails (0 USD)", "Setup fee — رسوم الإعداد (1250 USD)"; UNIT AMOUNT "0", PER "1000", AMOUNT "12.50 USD"; lines list AMOUNT "1250" next to CURRENCY "USD"; message/Recent actions "Setup fee — ( 1250) رسوم الإعداد".
- **Evidence:** `qa/manual/screens/M01/triage/t014a-invoice-inline-raw.png`, `qa/manual/screens/M01/triage/t015-lines-list-landing-raw-amounts.png`, `qa/manual/screens/M01/triage/t027-console-home.png`; Agent 1: `qa/manual/screens/M01/M01-F-014-invoice-lines-raw-amounts.png`.
- **Notes:** Also covers the message part of M01-F-015. Agent 1's remark that a current-month or pre-creation month invoice can be created by hand is not part of this bug (manual drafts are allowed by `etqan-billing.md`).
- **Root cause:** `EtqanInvoiceLine.__str__` and the inline/list columns used raw minor units; the Arabic description wasn't isolated.
- **Fix:** `__str__` = FSI description PDI + "(12.50 USD)"; inline shows "Unit price" via `price_text` instead of raw unit amount / per; lines list shows `money()`.
- **Regression test:** `etqan_billing/tests/test_admin_console_qa.py::test_an_invoice_line_shows_major_units_and_keeps_arabic_whole`.
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Invoice inline: "Setup fee — رسوم الإعداد (12.50 USD)" (Arabic kept whole, bracket at the end), Unit price "0.00 USD per 1,000 emails" / "—" for a manual line, Amount 12.50 USD; lines list Amount "12.50 USD". Evidence qa/manual/screens/M01/fix/ETQAN-QA-816-after.png (g-810-816-invoice-page.png, g-816-lines-list.png).

---

## ETQAN-QA-817: After adding a manual or credit line from an invoice, the operator lands on the global invoice-lines list, not back on the invoice
- **Feature:** M01 Etqan billing (`EtqanInvoiceLineAdmin` has no `response_add`; `has_change_permission` is False so Django falls back to the changelist). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** draft invoice → "Add a manual or credit line" (`/admin/etqan_billing/etqaninvoiceline/add/?invoice=<id>`) → Description, Amount → SAVE (Agent 1 on ETQ-2026-10-0001 while it was a draft).
- **Expected:** back on the invoice with the new line and the new total.
- **Actual:** "Select etqan invoice line to view" with every invoice's lines.
- **Evidence:** `qa/manual/screens/M01/triage/t015-lines-list-landing-raw-amounts.png` (the landing page); Agent 1: `qa/manual/screens/M01/M01-F-015-line-save-lands-on-lines-list.png`. Reproduced from code (no draft left to add to without new throwaway data).
- **Verification status:** OPEN

---

## ETQAN-QA-818: Etqan invoices list: five action inputs always shown in a cramped two-line bar, labels glued to the previous input; the table is cut off on the right
- **Feature:** M01 Etqan billing › Etqan invoices changelist (`InvoiceActionForm`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/etqan_billing/etqaninvoice/`.
- **Expected:** the extra inputs only for the action that needs them (or laid out with spacing), a date picker/format hint on "Paid on", all columns visible.
- **Actual:** "Action ▾Paid on [ ] / Method ▾Reference [ ] Void reason [ ] Run"; NUMBER wraps "ETQ-2026-" / "10-0001", TOTAL "12.50" / "USD", DUE AT cut, EMAILED AT and PAID ON off the right edge. Messages start with "· ".
- **Evidence:** `qa/manual/screens/M01/triage/t013-017-invoice-list.png`; Agent 1: `qa/manual/screens/M01/M01-F-017-invoice-list-cramped.png`.
- **Verification status:** OPEN

---

## ETQAN-QA-819: Etqan invoice email: sender "etqan" in lower case, plain text only, English only for an Arabic academy
- **Feature:** M01 Etqan billing › `tasks.send_invoice`. **Severity:** P3. **Type:** copy. **Easy P3:** no. **Priority:** low
- **Environment:** see ENV above; Mailpit.
- **Reproduction steps:** Mailpit → "[Etqan] Invoice ETQ-2026-10-0001 for October 2026" (to `qa-tmp-m01b-admin@`).
- **Expected:** From "Etqan", the branded HTML layout the academy emails use (the invite to the same admin has HTML and the academy's name as sender), the academy's language.
- **Actual:** From "etqan <noreply@etqan.academy>"; no HTML part (Text tab only); English body.
- **Evidence:** `qa/manual/screens/M01/triage/t018-invoice-email-lowercase-text-only.png`; Agent 1: `qa/manual/screens/M01/M01-F-018-invoice-email-sender-lowercase.png`.
- **Notes:** The generic "Pay by bank transfer to the account Etqan gave you" comes from `ETQAN_BILLING_PAYMENT_INSTRUCTIONS` (configuration, not a bug).
- **Verification status:** OPEN

---

## ETQAN-QA-820: Mark paid with a date typed 28/10/2026 says "No action selected." and clears the inputs
- **Feature:** M01 Etqan billing › action `mark_paid` (an invalid `InvoiceActionForm` makes Django's `response_action` report "No action selected."). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/etqan_billing/etqaninvoice/` → tick ETQ-2026-10-0001 → Action "Mark the selected invoices paid" → Paid on `28/10/2026` → Method Bank transfer → Run. (Invoice already paid; nothing ran.)
- **Expected:** "Enter a valid date (YYYY-MM-DD)." with the inputs kept.
- **Actual:** yellow "No action selected."; Paid on and Method emptied.
- **Evidence:** `qa/manual/screens/M01/triage/t019-mark-paid-bad-date.png`; Agent 1: `qa/manual/screens/M01/M01-F-019-mark-paid-bad-date-no-action-selected.png`.
- **Verification status:** OPEN

---

## ETQAN-QA-821: Platform account page: one help text for every service (email, Zoom, Stripe, AI) and a one-line box for a JSON secret
- **Feature:** M01 Integrations › Platform accounts (help texts in integrations admin). **Severity:** P3. **Type:** copy. **Easy P3:** yes (per-service help text, `Textarea` widget). **Priority:** low
- **Environment:** see ENV above (looked only; no keys entered — live BLOCKED).
- **Reproduction steps:** Integrations › Platform accounts → open AI (also Email, as Agent 1).
- **Expected:** help for the service on screen (which config keys and secret keys it needs).
- **Actual:** the Secret help lists email, Zoom, Stripe Connect and AI keys in one paragraph on every service's page; Secret is a single-line input; Last test ok shows a grey "?".
- **Evidence:** `qa/manual/screens/M01/triage/t021-platform-account-raw-title.png`; Agent 1: `qa/manual/screens/M01/M01-F-021-platform-account-raw-title-generic-help.png`.
- **Notes:** The raw title is ETQAN-QA-813. Email "Enabled" with no secrets while mail goes out locally is the dev SMTP fallback, not a bug.
- **Root cause:** One hard-coded secret help text for every service and a `PasswordInput`.
- **Fix:** `integrations/admin.py`: per-service `SECRET_HELP` / `CONFIG_HELP` (keys taken from the providers) set in the form's `__init__`; `SecretTextarea` (4 rows, never renders a value back). The grey "?" for an untested account is Django's null icon, left.
- **Regression test:** `integrations/tests/test_admin.py::test_each_service_page_explains_only_its_own_keys`, `::test_a_refused_secret_is_not_rendered_back_in_the_box`.
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** AI page: only the AI config/secret help (api_key, model); Email page: only SMTP keys; Secret is a 4-row empty textarea. Looked only, no keys entered (live BLOCKED). Evidence qa/manual/screens/M01/fix/ETQAN-QA-821-after.png.

---

## ETQAN-QA-822: Periodic tasks list shows code names and cron strings with no description; the Last run column is cut off
- **Feature:** M01 Etqan console › Periodic tasks (django-celery-beat admin; `PeriodicTask.description` empty). **Severity:** P4. **Type:** copy. **Easy P3:** no. **Priority:** low
- **Environment:** see ENV above (looked only; nothing run or toggled).
- **Reproduction steps:** `/admin/django_celery_beat/periodictask/`.
- **Expected:** each job says what it does; columns fit.
- **Actual:** `devices.push`, `scheduling.provision_meetings`, `etqan_billing.issue_due`…; scheduler `*/5 * * * * (m/h/dM/MY/d) UTC` over three lines; LAST RUN DATETIME cut "Oct. 28, 2026, 2:". Actions Delete / Enable / Disable / Toggle / Run offered to the superuser with no explanation (Delete has Django's confirmation; view-only staff see none, ETQAN-QA-013).
- **Evidence:** `qa/manual/screens/M01/triage/t022-periodic-tasks.png`; Agent 1: `qa/manual/screens/M01/M01-F-022-periodic-tasks-raw.png`.
- **Verification status:** OPEN

---

## ETQAN-QA-823: Console Users list: every Etqan staff account shows Role "Student"; no Staff / Superuser column
- **Feature:** M01 Identity › Users (`UserAdmin.list_display`; `User.role` defaults to student). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes (add `is_staff`, `is_superuser` columns; hide Role on the public schema). **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** `/admin/identity/user/`.
- **Expected:** staff identified as staff/superuser.
- **Actual:** all 8 rows (ops@, ops-view@, ops-noperm@, ops-change@, ops-add@, ops-domain@, ops-view-all@, qa-tmp-m01-staff@) ROLE "Student", FULL NAME "-"; columns ID, Email, Full name, Role, Is active, Date joined.
- **Evidence:** `qa/manual/screens/M01/triage/t023-staff-role-student.png`; Agent 1: `qa/manual/screens/M01/M01-F-023-staff-users-role-student.png`.
- **Root cause:** `UserAdmin.list_display` showed `role` (default student); the console runs only on the public schema where every account is Etqan staff.
- **Fix:** List shows Staff and Superuser instead of Role; filters is_staff / is_superuser / is_active / groups.
- **Regression test:** `identity/tests/test_console_users.py::test_the_list_shows_staff_and_superuser_not_an_academy_role`.
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** Users list: Is staff / Superuser status columns (ops@ superuser tick, others cross), filters By is staff / superuser / active; no Role column. Evidence qa/manual/screens/M01/fix/ETQAN-QA-823-after.png (g-823-users.png).

---

## ETQAN-QA-824: Staff without access to a console page get a bare "403 Forbidden" with no header or way back
- **Feature:** M01 Etqan console access (no `403.html` for the admin). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes (403 template extending `admin/base_site.html`, "You don't have permission … Home"). **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** sign in as `ops-view@` → open `/admin/identity/user/`.
- **Expected:** the console's own page with header, Log out and a link Home.
- **Actual:** white page, "403 Forbidden" in a default serif font only. Access control itself is right: the view-only Academies list has no action bar and no Add (`t025b-view-only-academies-readonly.png`).
- **Evidence:** `qa/manual/screens/M01/triage/t025-bare-403.png`, `qa/manual/screens/M01/triage/t025b-view-only-academies-readonly.png`; Agent 1: `qa/manual/screens/M01/M01-F-025-bare-403.png`.
- **Root cause:** No 403 template/handler on the public urlconf: Django's bare default.
- **Fix:** `config/urls_public.py` sets `handler403 = etqan.platform.views.console_permission_denied`: under `/admin/` for staff it renders `templates/admin/etqan_403.html` (console header, Log out, Home link); everything else keeps Django's default.
- **Regression test:** `identity/tests/test_console_users.py::test_a_refused_console_page_keeps_the_console_around_it`.
- **Verification status:** VERIFIED (Agent 2 gate, cycle 1, 2026-10-28)
- **Retest (Agent 2, 2026-10-28, REAL):** ops-view@ on /admin/identity/user/ and ops-noperm@ on /admin/tenants/academy/ get the console page "You don't have access to this page" with header, Log out, Home breadcrumb and "Back to the console home". Evidence qa/manual/screens/M01/fix/ETQAN-QA-824-after.png (g-824-view-403.png, g-824-noperm-403.png).

---

## ETQAN-QA-825: Connect fee currency accepts any text up to 3 characters ("zz" saved as "ZZ")
- **Feature:** M01 Etqan billing › Connect fees (`ConnectFee.currency` has no validator; `platform/validators.clean_currency` isn't used). **Severity:** P3. **Type:** data. **Easy P3:** no. **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** Connect fees › Add → QA Tmp M01b, Percent bp 250, Currency `zz` → SAVE (Agent 1); open the record.
- **Expected:** a three-letter ISO 4217 code (a select), like the rest of the product.
- **Actual:** saved and shown as "ZZ". Labels "Percent bp" (help "Basis points: 250 = 2.5 %.") and "Fixed amount — Minor units per payment." with no currency context.
- **Evidence:** `qa/manual/screens/M01/triage/t026-connect-fee-zz.png`; Agent 1: `qa/manual/screens/M01/M01-F-026-connect-fee-two-letter-currency.png`.
- **Notes:** Related to ETQAN-QA-022 (any three letters accepted for academy/invoice currency); here there is no check at all, on a different field. The raw title is ETQAN-QA-813.
- **Verification status:** OPEN

---

## ETQAN-QA-826: Console home lists ~30 framework admins around the handful an Etqan operator uses; Tenants comes last
- **Feature:** M01 Etqan console home and sidebar (allauth, MFA, Sites, Social accounts, Groups, celery-beat Clocked/Crontabs/Intervals/Solar events, empty identity profiles). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no. **Priority:** low
- **Environment:** see ENV above.
- **Reproduction steps:** sign in at `/admin/`.
- **Expected:** Academies, Domains, Etqan billing, Integrations first; internals hidden or grouped.
- **Actual:** alphabetical: ACCOUNTS, AUTHENTICATION AND AUTHORIZATION, ETQAN BILLING, IDENTITY (Guardianships, Parent/Student/Teacher profiles — empty on the platform), INTEGRATIONS, MFA, PERIODIC TASKS (5), SITES, SOCIAL ACCOUNTS (3), TENANTS last below the fold.
- **Evidence:** `qa/manual/screens/M01/triage/t027-console-home.png`; Agent 1: `qa/manual/screens/M01/M01-F-027-console-index-clutter.png`.
- **Verification status:** OPEN

## ETQAN-QA-827: On a phone, a suspended academy's login header (host name fallback) is wider than the screen: 397 px page on a 375 px phone
- **Feature:** M01 suspension effect on the academy login (dashboard login header). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** see ENV above; Chromium 375x812, AR. **Tag:** REAL
- **Found by:** Agent 1 confirmation sweep (M01-F-029); reproduced by Agent 2 gate 2 on 2026-10-28 on the already-suspended throwaway `qa-tmp-m01a` (no state change).
- **Preconditions:** a suspended academy (branding API answers 403, so the header falls back to the host name).
- **Reproduction steps:** open `http://qa-tmp-m01a.etqan.localhost/app/login` on a 375 px phone in Arabic.
- **Expected:** the header and card fit the phone; no sideways scroll.
- **Actual:** the header shows "qa-tmp-m01a.etqan.localhost" in the large serif title; it can't break inside the host, is clipped at the right ("qa-tmp-" cut), and `scrollWidth` 397 vs `clientWidth` 375, so the card's right edge is off-screen. Active academy `qa` measures 375.
- **Evidence:** `qa/manual/screens/M01/triage/t029-suspended-login-phone.png`; Agent 1: `qa/manual/screens/M01/M01-F-029-suspended-login-mobile-overflow.png`.
- **Notes:** The host name itself is the accepted PROPOSAL of ETQAN-QA-804 (and appears also on 5xx, ETQAN-QA-114); this bug is only the layout: let the header title wrap anywhere (`overflow-wrap:anywhere` / `min-w-0` / truncate) so any long fallback fits. Fallback comes from `dashboard/src/features/branding/queries.ts` (location.host).
- **Root cause (Agent 3, fix cycle 2, 2026-10-28):** `BrandWordmark` (the auth header title) was a flex item with the default `min-width:auto` and no wrap opportunity, so the one-word host-name fallback forced the header wider than the phone.
- **Fix:** `dashboard/src/features/branding/BrandProvider.tsx`: the wordmark gets `min-w-0 wrap-anywhere` (Tailwind 4.2 `overflow-wrap:anywhere`), so any long name breaks and shrinks; `src/ui/auth-layout.tsx`: header `gap-2`, toggles `shrink-0`. The host-name fallback itself stays the ETQAN-QA-804 proposal.
- **Regression test:** `dashboard/src/ui/auth-layout.test.tsx` "lets a long host-name wordmark wrap beside the toggles" (Vitest; the 375 px measurement is for Agent 2's browser retest). Evidence `qa/manual/evidence/M01/fix-2/`.
- **Verification status:** VERIFIED (Agent 2 final gate, cycle 2, 2026-10-28)
- **Retest (Agent 2, M01 final gate cycle 2, 2026-10-28, REAL):** suspended `qa-tmp-m01a` login at 375x812: AR scrollWidth 375 / clientWidth 375 (was 397), EN 375/375; the host name wraps onto 3 lines beside the toggles, card fully on screen. It breaks mid-word ("local/host"), expected for wrap-anywhere and acceptable for a fallback (the host name itself is 804's accepted PROPOSAL). No regression: active `qa` login 375/375 and 1440/1440; signed-in qa-admin top bar wordmark on one line. Before `qa/manual/screens/M01/triage/t029-suspended-login-phone.png`, after `qa/manual/screens/M01/fix/ETQAN-QA-827-after-ar.png`, `qa/manual/screens/M01/fix/ETQAN-QA-827-after-en.png`, `qa/manual/screens/M01/fix/g2-827-active-qa-375x812.png`, `qa/manual/screens/M01/fix/g2-827-topbar-qa-admin.png`. Vitest auth-layout/branding/shell 99 passed (`qa/manual/evidence/M01/gate-2/vitest.txt`).

## ETQAN-QA-828: Etqan invoice action messages start with a stray dot: "· ETQ-2026-10-0002: voided." / "· …: already void; nothing changed."
- **Feature:** M01 Etqan billing console (invoice actions Issue / Email again / Mark paid / Void). **Severity:** P4. **Type:** copy. **Easy P3:** yes (trivial). **Priority:** low
- **Environment:** see ENV above. **Tag:** REAL
- **Found by:** Agent 1 confirmation sweep (M01-F-030); reproduced by Agent 2 gate 2 on 2026-10-28 (Void on the already-void throwaway ETQ-2026-10-0002 → confirm → Yes; nothing changed, status stays void).
- **Reproduction steps:** Etqan invoices → tick a throwaway invoice → Void (reason) → Run → Yes, void.
- **Expected:** a plain sentence, e.g. "ETQ-2026-10-0002: voided." or "Voided 1 invoice: ETQ-2026-10-0002."
- **Actual:** "· ETQ-2026-10-0002: voided." / "· ETQ-2026-10-0002: already void; nothing changed." (also seen in F01 for marked paid / issued, quoted in ETQAN-QA-013's Actual, never filed).
- **Evidence:** `qa/manual/screens/M01/triage/t030-void-message-stray-dot.png`; Agent 1: `qa/manual/screens/M01/M01-F-030-void-message-stray-dot.png`.
- **Notes:** `etqan_billing/admin.py` `_each()` (and line ~530) prefixes "· " on purpose so Django's `message_user` capfirst doesn't change the number; pass the message without the prefix (invoice numbers are already upper case, so capfirst is harmless) or use `messages.add_message` directly.
- **Root cause (Agent 3, fix cycle 2, 2026-10-28):** `EtqanInvoiceAdmin._each()` and `EtqanInvoiceLineAdmin.delete_model` prefixed "· " on purpose to absorb the admin's `capfirst`; invoice numbers are upper case already, so the prefix only added a stray dot.
- **Fix:** `etqan/etqan_billing/admin.py`: messages are plain sentences (`"ETQ-…: voided."`, `exc.message`).
- **Regression test:** `etqan/etqan_billing/tests/test_admin_console_qa.py::test_voiding_a_void_invoice_says_it_is_already_void` asserts the exact message without the dot. Evidence `qa/manual/evidence/M01/fix-2/`.
- **Verification status:** VERIFIED (Agent 2 final gate, cycle 2, 2026-10-28)
- **Retest (Agent 2, M01 final gate cycle 2, 2026-10-28, REAL):** Void on the already-void throwaway ETQ-2026-10-0002 (confirm → Yes) → "ETQ-2026-10-0002: already void; nothing changed." (no dot); Issue on it → "ETQ-2026-10-0002: Only a draft invoice can change. …" (error path, no dot); status stays Void. Before `qa/manual/screens/M01/triage/t030-void-message-stray-dot.png`, after `qa/manual/screens/M01/fix/ETQAN-QA-828-after.png`, `qa/manual/screens/M01/fix/g2-828-issue-on-void.png`.

## ETQAN-QA-829: Etqan invoice page: a manual line shows Quantity 0 and Free quantity 0 next to Amount 12.50 USD
- **Feature:** M01 Etqan billing console (invoice lines inline / lines list). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** see ENV above. **Tag:** REAL
- **Found by:** Agent 1 confirmation sweep (M01-F-031); reproduced by Agent 2 gate 2 on 2026-10-28 (look only).
- **Reproduction steps:** open `/admin/etqan_billing/etqaninvoice/13/change/` (ETQ-2026-10-0001, qa-tmp-m01b, paid).
- **Expected:** a manual or credit line reads as one item: Quantity/Free quantity "—" (like its Unit price), so the row adds up.
- **Actual:** "Manual · Setup fee — رسوم الإعداد · 0 · 0 · — · 12.50 USD" (reads "0 × — = 12.50"). The usage row is clear.
- **Evidence:** `qa/manual/screens/M01/triage/t031-manual-line-qty0.png`; Agent 1: `qa/manual/screens/M01/M01-F-031-manual-line-quantity-zero.png`.
- **Notes:** Display only (ETQAN-QA-816 fixed the amounts; this is the quantity columns it left): show "—" for quantity/free quantity when the line kind is manual/credit. The missing "open the emailed PDF" link on the invoice page is an enhancement, not part of this bug.
- **Root cause (Agent 3, fix cycle 2, 2026-10-28):** `LineInline` showed the raw `quantity` / `free_quantity` model fields, which are 0 for a manual or credit line (one amount).
- **Fix:** `etqan/etqan_billing/admin.py`: `quantity_shown` / `free_quantity_shown` display methods show "—" for `manual` and `credit` lines (like Unit price) and the count (thousands separators) for usage / connect-fee lines.
- **Regression test:** `etqan/etqan_billing/tests/test_admin_console_qa.py::test_a_manual_or_credit_line_shows_no_quantities`. Evidence `qa/manual/evidence/M01/fix-2/`.
- **Verification status:** VERIFIED (Agent 2 final gate, cycle 2, 2026-10-28)
- **Retest (Agent 2, M01 final gate cycle 2, 2026-10-28, REAL):** invoice 13 (ETQ-2026-10-0001): Manual line "— · — · — · 12.50 USD"; Usage line keeps 1 · 1; invoice 16 usage line 2 · 0. No line ≥ 1,000 exists, so the thousands separator is checked by the regression test only. Before `qa/manual/screens/M01/triage/t031-manual-line-qty0.png`, after `qa/manual/screens/M01/fix/ETQAN-QA-829-after.png`, `qa/manual/screens/M01/fix/g2-829-invoice-page.png`.

## ETQAN-QA-830: Copy features / Suspend / Reactivate confirm pages show an Arabic-first academy name in the wrong order ("QA Tmp M01c أكاديمية الفجر")
- **Feature:** M01 academy action confirmation page (`admin/etqan_confirm_action.html`). **Severity:** P4. **Type:** UI-layout (bidi). **Easy P3:** yes. **Priority:** low
- **Environment:** see ENV above. **Tag:** REAL
- **Found by:** Agent 1 confirmation sweep (M01-F-032); reproduced by Agent 2 gate 2 on 2026-10-28 (qa-tmp-m01c → Copy features from Etqan QA Other → Run; confirm page left without confirming, nothing copied).
- **Expected:** the name reads as everywhere else in the (LTR) console: "أكاديمية الفجر QA Tmp M01c" (list, breadcrumb, domain tenant, invoice list).
- **Actual:** "QA Tmp M01c أكاديمية الفجر — turns on Payment links, …": the template wraps the name in `<bdi>`, whose automatic direction turns RTL on the first Arabic letter, so the Latin part is drawn first.
- **Evidence:** `qa/manual/screens/M01/triage/t032-copy-features-name-order.png`; Agent 1: `qa/manual/screens/M01/M01-F-032-copy-features-name-reversed.png`.
- **Notes:** `etqan/templates/admin/etqan_confirm_action.html` line 26: use `<bdi dir="ltr">` (still isolated from " — turns on …", same order as the rest of the console). The void confirm page shows the name in a plain LTR line and is correct.
- **Root cause (Agent 3, fix cycle 2, 2026-10-28):** `admin/etqan_confirm_action.html` wrapped each name in `<bdi>` with automatic direction, which turns RTL on an Arabic first letter.
- **Fix:** The template isolates the name with `<bdi dir="…">` set from `get_current_language_bidi` (ltr in the console), so the name reads in the page's order and stays isolated from its " — detail".
- **Regression test:** `etqan/tenants/tests/test_admin_console_qa.py::test_a_confirm_page_keeps_an_arabic_first_name_in_the_page_order`. Evidence `qa/manual/evidence/M01/fix-2/`.
- **Verification status:** VERIFIED (Agent 2 final gate, cycle 2, 2026-10-28)
- **Retest (Agent 2, M01 final gate cycle 2, 2026-10-28, REAL):** qa-tmp-m01c → Copy features from Etqan QA Other → Run: confirm page reads "أكاديمية الفجر QA Tmp M01c — turns on …" (`<bdi dir="ltr">`), same order as the list; left unconfirmed, nothing copied. Before `qa/manual/screens/M01/triage/t032-copy-features-name-order.png`, after `qa/manual/screens/M01/fix/ETQAN-QA-830-after.png`, `qa/manual/screens/M01/fix/g2-830-confirm-page.png`.

---

## --- M16 manual bugs ---

## ETQAN-QA-750: Public site footer shows an empty "بيانات التواصل" column when no contact details are set; "روابط سريعة" omits recorded courses and consultations
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-001); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor; academy `qaother` (no contact data).
- **Reproduction steps:**
  1. AR: open `http://qaother.etqan.localhost/ar/` and scroll to the bottom.
  2. Compare with `http://qa.etqan.localhost/ar/` footer quick links.
- **Expected:** The contact column is hidden when there is nothing to show; quick links cover the main pages the header offers.
- **Actual:** qaother: heading "بيانات التواصل" with nothing under it, "روابط سريعة" lists only "الرئيسية". On qa (contact set by M13) the column fills, but quick links are still only الرئيسية / المقالات / الفيديوهات / الأسئلة الشائعة - recorded courses and consultations (in the header) are missing.
- **Evidence:** `qa/manual/screens/M16/M16-F-001-footer-empty-contact.png`, `qa/manual/screens/M16/M16-F-001b-qaother-empty-contact-mobile.png`, `qa/manual/screens/M16/triage/t001-qaother-footer.png`
- **Notes:** marketing footer component: render the contact column only when one of email/phone/WhatsApp/address is set; add recorded-courses / consultations links when those features are on.
- **Root cause:** `marketing/src/components/Footer.astro` always rendered the "بيانات التواصل" column and built quick links from pages/articles/videos/FAQ only; it never asked `hasRecordedCourses`/`hasConsultations` as the header does.
- **Fix (Agent 3, fix-1, 2026-10-28):** Footer renders the contact column only when email, phone, WhatsApp or address is set, and adds الدورات المسجلة / الاستشارات links with the header's same flags.
- **Regression test:** `marketing/test/components.test.ts` "Footer contact column and quick links (ETQAN-QA-750)" (2 tests). Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** qaother (no contact): no 'بيانات التواصل' column; with a contact set temporarily on qaother (restored) the column shows email/phone/WhatsApp; qa quick links now include الدورات المسجلة + الاستشارات. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-750-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-751: Public site has no sign-up link: header, hero and footer offer only "تسجيل الدخول"; self-registration is reachable only through the sign-in page
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-002); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor; academy `qa` with self-registration on.
- **Reproduction steps:**
  1. AR/EN: open `/ar/`; look at the header, hero and footer (and the phone menu).
- **Expected:** A visible "سجّل الآن / إنشاء حساب" (to `/app/register`) while self-registration is on.
- **Actual:** Header links: الدورات المسجلة, الاستشارات, المقالات, الفيديوهات, الأسئلة الشائعة, English, تسجيل الدخول. No link to `/app/register` anywhere on the site; only the sign-in page has "جديد هنا؟ إنشاء حساب".
- **Evidence:** `qa/manual/screens/M16/M16-F-002-no-register-link-header.png`, `qa/manual/screens/M16/triage/t001-home-ar-full.png`
- **Notes:** The site payload would need a `registration_open` flag (registration switch) so the marketing header can show the link only when it works; hence not easy.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-752: "اشترِ الدورة" on a recorded course sends a visitor to a bare sign-in page with no word about the course and no way back to the site
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-003); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`, recorded course `m15-amma-paid`.
- **Reproduction steps:**
  1. AR: open `/ar/recorded-courses/m15-amma-paid`.
  2. Click "اشترِ الدورة".
- **Expected:** The visitor is told an account is needed to buy this course (sign-up as the main choice, the course named), with a link back to the site.
- **Actual:** Lands on `/app/login` "مرحبًا بعودتك / سجّل الدخول لمتابعة دراستك." - no course, no price, no back link; the hint under the button on the site says only "سجّل الدخول ثم افتح الدورات المسجلة". After signing in the deep link is lost (known ETQAN-QA-058).
- **Evidence:** `qa/manual/screens/M16/M16-F-003-buy-goes-to-plain-login.png`, `qa/manual/screens/M16/triage/t003-buy-login.png`
- **Notes:** Related: ETQAN-QA-058 (deep link lost after sign-in) - this bug is the missing context/back path, not the redirect.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-753: "احجز حصة تجريبية" opens the generic "تواصل معنا" form: nothing tells the visitor it is a trial request, and the success line is the contact one
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-004); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: `/ar/` → click the hero button "احجز حصة تجريبية".
  2. Fill the form and send.
- **Expected:** The form heading/success say it is a trial request (e.g. "اطلب حصة تجريبية" / "استلمنا طلب الحصة التجريبية").
- **Actual:** Scrolls to the same "ابدأ الآن / تواصل معنا" card; the hidden `kind` input is switched to `trial` by script (`ContactForm.astro:99-102`) so the office sees "طلب حصة تجريبية", but the visitor sees only "تم استلام رسالتك، سنتواصل معك قريباً.".
- **Evidence:** `qa/manual/screens/M16/M16-F-004-trial-cta-generic-contact.png`, `qa/manual/screens/M16/triage/t004-trial-cta.png`
- **Notes:** Small script change in `marketing/src/components/ContactForm.astro`: when the trial CTA sets kind=trial, also swap the heading and the success text.
- **Root cause:** `ContactForm.astro` only switched the hidden `kind` input to `trial`; heading, note and success text stayed the contact ones.
- **Fix (Agent 3, fix-1, 2026-10-28):** A `setKind()` helper swaps the heading to "اطلب حصة تجريبية", shows a trial note in the form, and the success line becomes "استلمنا طلب الحصة التجريبية…"; reset to contact after send and on pageshow. New strings in `marketing/src/lib/i18n.ts` (ar/en).
- **Regression test:** `marketing/test/components.test.ts` "tells the visitor a trial CTA opens a trial request (ETQAN-QA-753)". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR: hero 'احجز حصة تجريبية' -> heading 'اطلب حصة تجريبية' + trial note; send -> 'استلمنا طلب الحصة التجريبية…'; office list shows 'طلب حصة تجريبية'. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-753-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-754: Recorded-course cards and pages show the length as a bare "00:12:00" / "00:00:03" with no label
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-005); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR/EN: open `/ar/recorded-courses/` and a course page.
- **Expected:** "12 دقيقة" / "مدة الدورة: 12 دقيقة" (EN "12 min").
- **Actual:** Cards show a lone "00:12:00", "00:05:00", "00:00:03" under the description; the course page "درس واحد · 00:12:00" and each lesson "00:12:00". Reads like a clock.
- **Evidence:** `qa/manual/screens/M16/M16-F-005-raw-duration.png`, `qa/manual/screens/M16/triage/t005-recorded-durations.png`
- **Notes:** marketing recorded-course card/detail: format the duration in minutes/hours with a localized unit.
- **Root cause:** `marketing/src/lib/recorded.ts:durationText` printed `HH:MM:SS`.
- **Fix (Agent 3, fix-1, 2026-10-28):** `durationText(seconds, lang)` now uses a new `lengthText` in `lib/i18n.ts` with plural forms: "12 دقيقة", "ساعة واحدة و5 دقائق", "أقل من دقيقة" / "12 minutes"; used on the card, course page and each lesson.
- **Regression test:** `marketing/test/recorded.test.ts` "formats durations…" (ar/en cases) and "keeps Arabic-only course text… (ETQAN-QA-771/754)". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR cards '12 دقيقة', '5 دقائق', 'أقل من دقيقة'; EN course page '1 lesson · 12 minutes', lesson '12 minutes'. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-754-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-755: Registration: the phone placeholder "+201001234567" looks like a typed value, so the error "use the format like +201001234567" reads as contradictory; gender/country selects keep a normal border when in error
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-006); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/register` → التالي (نفسي) → leave everything empty → التالي.
- **Expected:** The example is clearly a hint (lighter, or "مثال: …" under the field); every field in error gets the red border.
- **Actual:** Phone box shows +201001234567 in dark grey (value is empty) and the red line under it says "استخدم الصيغة الدولية، مثل ‎+201001234567."; الجنس has a grey border and الدولة a green one while both show red errors.
- **Evidence:** `qa/manual/screens/M16/M16-F-006-phone-placeholder-looks-filled.png`, `qa/manual/screens/M16/triage/t006-phone-placeholder.png`
- **Notes:** RegisterForm phone input placeholder colour / wording; selects need the same `aria-invalid` error styling as inputs.
- **Root cause:** `RegisterForm.tsx` used the example number as the phone `placeholder` (muted grey reads as a value); `ui/select.tsx` had no `aria-invalid` styling, unlike `Input`.
- **Fix (Agent 3, fix-1, 2026-10-28):** Placeholder removed; the example is a hint line under the field (`registration.fields.phoneHint`, ar/en/es) linked by `aria-describedby`. `Select` gets the same `aria-invalid` red border/ring classes as `Input` (all forms).
- **Regression test:** `dashboard/src/features/registration/RegisterPage.test.tsx` "shows the phone example as a hint, not a placeholder (ETQAN-QA-755)". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR 375px empty step 2: phone has no placeholder, hint line under it; الجنس/الدولة selects get the red border. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-755-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-756: Registration accepts a preferred start date and an intro-call date/time in the past (2020-01-01 03:00)
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-008); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/register`, fill step 2 validly.
  2. Step 3: تاريخ البدء المفضّل = 2020-01-01, hours 3, السبت, تاريخ المكالمة التعريفية = 2020-01-01, وقت = 03:00 → التالي → submit.
- **Expected:** "اختر تاريخًا من اليوم فصاعدًا" on both dates (client and server).
- **Actual:** No error; registration 5 (m16-t2-adult@example.com) stored with `start_on=2020-01-01`, `intro_call_at=2020-01-01 01:00 UTC`. The office receives a request for an intro call six years ago.
- **Evidence:** `qa/manual/screens/M16/M16-F-008-past-dates-accepted.png`, `qa/manual/screens/M16/triage/t008-past-dates-step3.png`
- **Notes:** Add `min=today` on the two date inputs and a server check in `registration/services.py` (start_on >= today, intro_call_at > now).
- **Root cause:** No past check on `start_on` / intro call, neither in `registration/schemas.ts` nor in `registration/services.py:_clean_preferences`.
- **Fix (Agent 3, fix-1, 2026-10-28):** Client: `min=today` on both date inputs and schema issues `dateNotPast` / `introCallPast` (intro instant computed in the chosen zone). Server: `_clean_preferences(data, today)` refuses `start_on` before the academy's yesterday (one day of zone slack) and `intro_call_at <= now`; messages mapped in `lib/server-messages.ts`. Proposal for codes in coverage-gaps.md.
- **Regression test:** `dashboard/src/features/registration/schemas.test.ts` "refuses a start date or an intro call in the past (ETQAN-QA-756)"; `backend/etqan/registration/tests/test_services.py::test_no_start_date_or_intro_call_in_the_past` (3 cases) + `test_today_and_yesterday_start_dates_are_fine`. Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR: 2020-01-01 dates -> 'اختر تاريخًا من اليوم فصاعدًا.' / 'اختر موعدًا في المستقبل للمكالمة.' (min=2026-10-28); server API refuses start_on 2020-01-01 and intro_call_at 2020 (400). BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-756-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-757: Registration: a wrong registration code shows English "Invalid code." on the Arabic form
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-009); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: complete steps 1-3, step 4 رمز التسجيل = BADCODE-123, tick consent, تسجيل.
- **Expected:** Arabic, e.g. "رمز التسجيل غير صحيح أو منتهي."
- **Actual:** Red ".Invalid code" under the code box (400 POST /api/v1/registration/).
- **Evidence:** `qa/manual/screens/M16/M16-F-009-invalid-code-english.png`, `qa/manual/screens/M16/triage/t009-invalid-code.png`
- **Notes:** Same family as ETQAN-QA-157 (raw English server text passed through `useFieldError`); registration's code error needs a translated message / error code.
- **Root cause:** Server sends `{"code": ["Invalid code."]}` with no rule code; `useFieldError` passed the English sentence through.
- **Fix (Agent 3, fix-1, 2026-10-28):** `dashboard/src/lib/server-messages.ts` maps "Invalid code." to `registration.errors.codeInvalid` ("رمز التسجيل غير صحيح أو منتهي الصلاحية.", en/es too).
- **Regression test:** `RegisterPage.test.tsx` "offers the code with the waiting list and shows an invalid code" now expects the translated sentence. Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR step 4 BADCODE-123 -> 'رمز التسجيل غير صحيح أو منتهي الصلاحية.' BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-757-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-758: Phone (375px, Arabic): the registration page is 627px wide and opens scrolled onto a blank area; the form is cut off
- **Feature:** M16 Public pages. **Severity:** P2. **Type:** mobile. **Easy P3:** no. **Priority:** high
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-010); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`, 375x812.
- **Reproduction steps:**
  1. AR: open `/app/register` on a 375x812 phone.
  2. eval `[document.documentElement.scrollWidth, innerWidth, scrollX]`.
- **Expected:** The form fits the phone width, as in English.
- **Actual:** AR `627,627,-252`: the first screen shows only the theme/language buttons, the card's left edge, the check mark and "التالي" - title, options and texts are off-screen. EN on the same phone: `375,375,0`, fine.
- **Evidence:** `qa/manual/screens/M16/M16-F-010-mobile-register-overflow.png`, `qa/manual/screens/M16/M16-F-010b-mobile-register-overflow-full.png`, `qa/manual/screens/M16/triage/t010-mobile-register.png`, `qa/manual/screens/M16/triage/t010-mobile-register-en.png`
- **Notes:** Agent 1 saw the RadioCardGroup hidden inputs (absolute + transform) and the toast list sit at negative left positions in RTL. Same pattern as ETQAN-QA-426/204 (offscreen absolutely-positioned element widening an RTL page). Arabic phone is the main audience of self-registration, hence P2.
- **Root cause:** Radix `RadioGroup` inside a `<form>` adds a hidden native radio per item, `position:absolute; transform: translateX(-100%)`; in RTL that pushes it past the page's left edge (x=-252), so the phone layout viewport grew to 627px.
- **Fix (Agent 3, fix-1, 2026-10-28):** `dashboard/src/ui/radio-card-group.tsx`: the group is `relative` and `[&>input]:![transform:none]`, so the hidden radios stay in the group's box. Smoke: AR 375px now `[375,375,0]` (`qa/manual/screens/M16/fix/f758-after-smoke.png`).
- **Regression test:** `dashboard/src/ui/radio-card-group.test.tsx` "keeps Radix's hidden form radios inside the group (no RTL page overflow)". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR 375x812 /app/register: [375,375,0] on steps 1, 2 (adult and parent); form fully visible. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-758-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-759: Registration step 4: the consent "أوافق على شروط الأكاديمية…" points to terms the visitor can't read, and nothing summarises what will be sent
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-011); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: complete steps 1-3 → step 4 "التأكيد".
- **Expected:** "شروط الأكاديمية" opens the terms; the confirm step lists the entered name/email/children/preferences.
- **Actual:** Plain text "أوافق على شروط الأكاديمية وعلى احتفاظها بهذه البيانات." with no link, then only the code box and the checkbox.
- **Evidence:** `qa/manual/screens/M16/M16-F-011-terms-not-link-no-summary.png`, `qa/manual/screens/M16/triage/t009-invalid-code.png`
- **Notes:** There is no academy terms content type today (website.md), so a link needs a terms page/setting; the review summary is a suggestion. Not easy.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-760: After registering: "إذا أمكن استخدام البيانات، فقد أرسلنا رابط تأكيد…" is confusing and says nothing about the academy's approval
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-012); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa` (waiting list on).
- **Reproduction steps:**
  1. AR: complete an adult registration (m16-t2-adult@example.com) and submit.
- **Expected:** "أرسلنا رابط تأكيد إلى …. بعد التأكيد ستراجع الأكاديمية طلبك وسنراسلك عند الموافقة." (approval sentence only while the waiting list applies).
- **Actual:** "تحقّق من بريدك الإلكتروني للتأكيد — إذا أمكن استخدام البيانات، فقد أرسلنا رابط تأكيد إلى m16-t2-adult@example.com. افتحه للمتابعة." ("if the data could be used, we may have sent…"); the address breaks "m16-t2-" / "adult@example.com" across lines (bidi, cf. ETQAN-QA-060). Approval is mentioned only at sign-in.
- **Evidence:** `qa/manual/screens/M16/M16-F-012-register-success-wording.png`, `qa/manual/screens/M16/triage/t012-register-success.png`
- **Notes:** The hedge is deliberate anti-enumeration wording; it can stay neutral without the conditional ("إن لم يكن البريد مسجلًا من قبل فستصلك رسالة تأكيد…"). Wrap the email in `dir=ltr`/bdi. Related ETQAN-QA-172 (verify page, fixed).
- **Root cause:** `registration.doneBody` was a hedged conditional; the email was interpolated into Arabic text unisolated; nothing mentioned the approval step.
- **Fix (Agent 3, fix-1, 2026-10-28):** New neutral wording (still identical for a taken address, R-8) with the address in `<bdi dir=ltr>` via `Trans`; `RegisterForm` reports `review = waitlist && no code` and the page adds `registration.doneReview` ("بعد تأكيد بريدك ستراجع الأكاديمية طلبك…"), ar/en/es.
- **Regression test:** `RegisterPage.test.tsx` "tells a waiting-list registrant about the approval, the address isolated (ETQAN-QA-760)" and the no-approval assertion in the code test. Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR adult m16-gate-adult@example.com: new neutral sentence, address intact in one LTR run, approval line shown (waiting list, no code); Mailpit: 1 confirmation email. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-760-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-761: Parent registration: a child birth date in the future (2030-01-01) gives "يجب أن يكون عمر الطفل أقل من 18 عامًا."
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-013); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/register` → أبنائي → التالي → child 1 تاريخ الميلاد = 2030-01-01 → التالي.
- **Expected:** "تاريخ الميلاد لا يمكن أن يكون في المستقبل."
- **Actual:** Red "يجب أن يكون عمر الطفل أقل من 18 عامًا." - the parent who mistyped the year is told the child is too old.
- **Evidence:** `qa/manual/screens/M16/M16-F-013-future-dob-wrong-message.png`, `qa/manual/screens/M16/triage/t013-future-dob.png`
- **Notes:** Registration schema age check treats a negative age as failing the under-18 rule; add a separate future-date message. Admin-side future DOB is ETQAN-QA-035 (different form).
- **Root cause:** Schema (and server) folded `born > today` into the under-18 rule (`childTooOld`); an adult's future date fell into `tooYoung`.
- **Fix (Agent 3, fix-1, 2026-10-28):** Separate `dateOfBirthFuture` issue ("تاريخ الميلاد لا يمكن أن يكون في المستقبل.") for adult and child; server `_not_future()` in `registration/services.py` raises "A date of birth can't be in the future." (mapped in server-messages).
- **Regression test:** `schemas.test.ts` child case + "says a future birth date is in the future, for an adult too (ETQAN-QA-761)"; `test_services.py::test_a_future_birth_date_says_future_not_age`. Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR 375px parent, child DOB 2030-01-01 -> 'تاريخ الميلاد لا يمكن أن يكون في المستقبل.'; server API refuses a future adult DOB with the new sentence. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-761-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-762: Teacher avatar initial on consultation pages is "ا" (from the article of "الشيخ")
- **Feature:** M16 Public pages. **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-014); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: `/ar/consultations/1` (المعلمون card); also `/app/consult/1` teacher picker.
- **Expected:** A meaningful initial (skip "ال"/titles) or a photo.
- **Actual:** Green circle with a lone "ا" for "الشيخ أحمد الحداد (Ahmad Al-Haddad)", on the site and on the booking page.
- **Evidence:** `qa/manual/screens/M16/M16-F-014-avatar-initial-alif.png`, `qa/manual/screens/M16/triage/t014-consult-avatar.png`, `qa/manual/screens/M16/triage/t015-consult-booking-bare.png`
- **Notes:** Initial helper in marketing and dashboard (`BookingWizard`).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-763: Visitor consultation booking, checkout and manage pages (/app/consult/…) have no academy name, header, language switch or link back to the site
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** UI-layout. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-015 (+F-018 frame part)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: `/ar/consultations/1` → احجز استشارة → `/app/consult/1`.
  2. Continue to the checkout dialog; open a manage link `/app/consult/manage/<token>`.
- **Expected:** The academy frame (name/logo, AR/EN, back to the site) as on `/app/verify/…` and `/app/login`, so a parent trusts the page they pay on.
- **Actual:** A bare form on beige: no academy name, no header/footer, no language switch, native radio for the teacher, raw time-zone list (ETQAN-QA-154). The manage page is the same bare card. By contrast `/app/verify/…` shows the academy name and EN switch.
- **Evidence:** `qa/manual/screens/M16/M16-F-015-consult-booking-no-header.png`, `qa/manual/screens/M16/triage/t015-consult-booking-bare.png`, `qa/manual/screens/M16/triage/t016-checkout-no-appointment.png`, `qa/manual/screens/M16/triage/t018-manage-paid-mobile.png`, `qa/manual/screens/M16/triage/t021-verify-invalid.png`
- **Notes:** Wrap the public consult routes in the same public shell the verify/login routes use.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-764: Consultation checkout dialog doesn't repeat the chosen teacher, date and time before paying
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-016); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/consult/1` → pick the teacher → slot 29/10 20:30 → name, email, WhatsApp → ادفع عبر Stripe.
- **Expected:** A summary line "الشيخ أحمد · الخميس 29/10 · 20:30 (بتوقيت القاهرة)" in the dialog.
- **Actual:** Only "M15- استشارة خطة الحفظ 200.00 / رسوم الخدمة 0.00 / الإجمالي 200.00", the raw manage URL and "المتابعة إلى Stripe". Closing the dialog keeps the hold (known ETQAN-QA-451).
- **Evidence:** `qa/manual/screens/M16/M16-F-016-checkout-no-appointment.png`, `qa/manual/screens/M16/triage/t016-checkout-no-appointment.png`
- **Notes:** Add teacher + localized date/time (with weekday and zone) to the BookingWizard checkout dialog.
- **Root cause:** `BookingWizard.tsx` `Booked` (checkout card) received only the product and the checkout amounts.
- **Fix (Agent 3, fix-1, 2026-10-28):** The wizard passes teacher name, chosen slot and zone; the card shows المعلم and الموعد with weekday and zone (new `appointmentText` in `features/consultations/time.ts`, e.g. "الاثنين، 2 نوفمبر 2026 في 16:30 توقيت مصر").
- **Regression test:** `BookingWizard.test.tsx` "books a visitor…" asserts teacher and "Monday, October 12, 2026 at 19:00 …" in the pay sheet. Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR visitor booking CR-000008: pay sheet shows المعلم + 'الاثنين، 2 نوفمبر 2026 في 19:30 توقيت مصر'. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-764-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-765: Consultation manage page: a paid booking just says "قيد المراجعة" with no next step, and the time reads "16:30 ,2026/11/02" with no weekday or time zone
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-018); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor with the emailed manage link of paid CR-000006.
- **Reproduction steps:**
  1. Open `/app/consult/manage/YPxqL3YFeV7sozfyaF8KX0sp6zHRvgINdc1HI12K6yA` (AR, 375x812 and desktop).
- **Expected:** "تم الدفع. ستؤكد الأكاديمية الموعد وترسل رابط الاجتماع قبل الموعد." and a time like "الاثنين 2/11/2026، 16:30 (بتوقيت القاهرة)", plus who to contact.
- **Actual:** Title, CR-000006, الحالة "قيد المراجعة", المعلم, الموعد "16:30 ,2026/11/02", الدفع "مدفوع 200.00 ج.م.". No explanation of what happens next. (No cancel/reschedule here is by design: consultations.md "Bookers cannot cancel"; reschedule only once confirmed.)
- **Evidence:** `qa/manual/screens/M16/M16-F-018-manage-page-nothing-to-do.png`, `qa/manual/screens/M16/triage/t018-manage-paid-mobile.png`
- **Notes:** Copy + date formatting only; missing academy frame is ETQAN-QA-763.
- **Root cause:** `ManagePage.tsx` printed `dayIn + wallTime` (no weekday/zone) and had no line for a paid booking under review.
- **Fix (Agent 3, fix-1, 2026-10-28):** Times use `appointmentText` (weekday + zone); a paid `pending_review` booking shows `consultations.manage.nextPaidReview` ("تم الدفع. ستراجع الأكاديمية الحجز وتؤكد الموعد قريبًا…"), ar/en (no es consultations file exists; falls back to en).
- **Regression test:** `ManagePage.test.tsx` "tells a paid booking under review what happens next (ETQAN-QA-765)", "says nothing extra for an unpaid booking", and the weekday/zone assertion. Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** CR-000008 paid with the SIMULATOR: AR 375px and EN desktop show weekday+zone time and the next-step line (unpaid shows only the hold line). BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-765-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-766: Office inquiries list shows no received date/time and no WhatsApp mark, though the API returns `created_at` and `has_whatsapp`
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-019); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`; M16 inquiries from the public form.
- **Reproduction steps:**
  1. AR: `/app/website/inquiries`.
- **Expected:** Each card shows when it arrived and a WhatsApp mark/link next to the phone when ticked.
- **Actual:** Cards show name, email + phone, message, kind and buttons only. The trial inquiry was sent with "لدي واتساب على هذا الرقم" ticked (stored has_whatsapp=t) - no sign of it. Latin message "Do you teach adults in English?" shows as "?Do you teach…" (ETQAN-QA-060 follow-up).
- **Evidence:** `qa/manual/screens/M16/M16-F-019-inquiry-no-date-no-whatsapp.png`, `qa/manual/screens/M16/triage/t019-inquiries.png`
- **Notes:** `site/api/admin_serializers.py:486` already sends `created_at`, `has_whatsapp`, `locale`; the dashboard inquiries card just doesn't render them. (Owned screen is M13's; filed here because the visitor flow found it.)
- **Root cause:** `features/website/InquiriesList.tsx` never rendered `created_at` / `has_whatsapp`.
- **Fix (Agent 3, fix-1, 2026-10-28):** Each card shows "وصل في …" (`<time>`), email and phone as separate LTR runs, a WhatsApp link (wa.me built from digits) when ticked, and the message with `dir=auto`. Strings `website.inquiries.received/whatsapp` (ar/en, es received).
- **Regression test:** `InquiriesList.test.tsx` "shows when it arrived and links the WhatsApp the visitor ticked (ETQAN-QA-766)". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** Admin AR inquiries: 'وصل في …' time, email and phone as LTR runs, 'واتساب' link on the ticked trial inquiry, Latin message no longer starts with '?'. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-766-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-767: Paying a payment link sends the payer no receipt, and the paid link page shows no date or reference
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-020); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** link "M16 رسوم الكتاب" 300 EGP + fee 15 for m16-paylink@example.com, paid with the simulator by Agent 1.
- **Reproduction steps:**
  1. Open `/app/pay/link/rTQvSy4Qfhdd20tU46u5rg` (AR, 375x812).
  2. Mailpit search `m16-paylink`.
- **Expected:** An emailed receipt (amount, fee, date, academy) to the payer's address, and the paid date/reference on the link page.
- **Actual:** Page: amounts and "تم دفع هذا الرابط. شكرًا لك." only. Mailpit: 0 messages for m16-paylink. (Return-page dead end is ETQAN-QA-309; recorded-course receipt is ETQAN-QA-452.)
- **Evidence:** `qa/manual/screens/M16/M16-F-020-paid-link-no-receipt.png`, `qa/manual/screens/M16/triage/t020-paid-link.png`
- **Notes:** online-payments.md documents no payer notice for links; needs a notice on link `complete` plus paid fields in the public payload.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-768: Public site 404 page is a single heading "الصفحة غير موجودة": no explanation, no way home, footer floats mid-screen
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-022); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR/EN: open `/ar/does-not-exist` (also a bad course slug / consultation id).
- **Expected:** A short explanation and buttons (الرئيسية / الدورات / تواصل معنا), page filling the screen.
- **Actual:** Header, one bold line, the footer, then half a screen of empty background under the footer.
- **Evidence:** `qa/manual/screens/M16/M16-F-022-bare-404.png`, `qa/manual/screens/M16/triage/t022-404-ar.png`
- **Notes:** `marketing/src/components/PageNotFound.astro`: add text + links and min-height on main.
- **Root cause:** `marketing/src/components/PageNotFound.astro` rendered one `<h1>` in a short `<main>`.
- **Fix (Agent 3, fix-1, 2026-10-28):** 404 band with explanation, "العودة إلى الرئيسية" and (when the home has the contact section) "تواصل معنا" buttons, `min-h-[60vh]` so the footer sits low. Strings `pageNotFoundBody`, `backHome`.
- **Regression test:** `marketing/test/components.test.ts` "PageNotFound (ETQAN-QA-768)". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR desktop + EN 375px /does-not-exist: 404, explanation, home + contact buttons, footer at the bottom. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-768-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-769: Home "من نحن" section repeats its title (eyebrow "من نحن" and heading "من نحن"; EN "ABOUT US" / "About us")
- **Feature:** M16 Public pages. **Severity:** P4. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-023); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa` with an about text.
- **Reproduction steps:**
  1. AR: `/ar/`, scroll to the about block.
- **Expected:** Eyebrow and heading differ, like the other sections ("تعلّم في أي وقت / دورات مسجّلة بإتقان").
- **Actual:** "من نحن" twice, one above the other.
- **Evidence:** `qa/manual/screens/M16/M16-F-023-about-title-duplicated.png`, `qa/manual/screens/M16/triage/t023-about-dup.png`
- **Notes:** marketing i18n strings for the about SectionHeader.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-770: Home page never shows live courses, packages or teachers: the admin switches "إظهار الدورات / الباقات / المعلمين" do nothing
- **Feature:** M16 Public pages. **Severity:** P2. **Type:** functional. **Easy P3:** no. **Priority:** high
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-024); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor; academy `qa` with landing `show_courses/packages/teachers = true` and many active courses, packages, teachers.
- **Reproduction steps:**
  1. AR/EN: `/ar/`, scroll to the end.
- **Expected:** The academy's live courses, packages with prices and teachers on the home page when the switches are on (academy-sites spec §3.2: Plan 3 adds these sections).
- **Actual:** Sections rendered: hero, about, recorded courses, offers, consultations, articles, FAQ, contact. Nothing about live lessons, packages/prices or teachers - the academy's main product is invisible to a visiting parent. `marketing/src/pages/[lang]/index.astro` reads only `sections.testimonials` and `sections.contact`; the API sends `courses/packages/teachers` (`site/api/serializers.py:66-68`) but no catalogue/teacher data.
- **Evidence:** `qa/manual/screens/M16/M16-F-024-home-no-courses-teachers.png`, `qa/manual/screens/M16/triage/t001-home-ar-full.png`
- **Notes:** Needs public catalogue/teacher payloads + home sections (API change) - a proposal for the owner; until then the three switches should at least be hidden or labelled "قريبًا".
- **Root cause:** the public site has no catalogue/teacher data: `site/api/serializers.py:landing_payload` sends only the three `sections.courses/packages/teachers` flags and `marketing/src/pages/[lang]/index.astro` renders only testimonials and contact (academy-sites spec §3.2: Plan 3).
- **Fix (Agent 3, fix-1, 2026-10-28):** not built: needs new public payloads (API change) and an owner decision on public teacher fields. PROPOSAL written in `qa/coverage-gaps.md` § "M16 manual, Agent 3 fix cycle 1" (incl. the interim option to hide/label the three switches in M13's HomePageForm).
- **Regression test:** none (no code change).
- **Gate decision (Agent 2, 2026-10-28T14:58:46Z):** proposal accepted. Needs public catalogue and teacher payloads (an API change) and an owner decision on which teacher fields are public (academy-sites spec §3.2, Plan 3). Interim: hide or label the three switches in M13's HomePageForm.
- **Verification status:** PROPOSAL-accepted (owner decision)

---

## ETQAN-QA-771: English site: Arabic-only course titles and text are laid out LTR and scrambled ("M15- (مدفوعة) حفظ جزء عمّ"), in the Latin display serif
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-025); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`, course with Arabic-only text.
- **Reproduction steps:**
  1. EN: `/en/recorded-courses/m15-amma-paid` (also home cards in EN).
- **Expected:** Arabic fallback text keeps its own direction (`dir=auto`) and an Arabic-capable font: "M15- حفظ جزء عمّ (مدفوعة)".
- **Actual:** Hero title "M15- (مدفوعة) حفظ جزء عمّ" (parenthesis moved to the middle) in the serif; description and "M15- لا يُسترد المبلغ بعد بدء المشاهدة." left-aligned with the full stop at the wrong end.
- **Evidence:** `qa/manual/screens/M16/M16-F-025-en-arabic-title-scrambled.png`, `qa/manual/screens/M16/triage/t025-en-arabic-title.png`
- **Notes:** Same family as ETQAN-QA-321 (dashboard) but in the marketing app: add `dir="auto"` on content-derived text.
- **Root cause:** Content-derived text on the marketing site inherited the page's `ltr`; the EN display font stack (`Fraunces, Georgia`) had no Arabic face.
- **Fix (Agent 3, fix-1, 2026-10-28):** `dir="auto"` + `text-start` on course title/description/content/outline/reviews/terms (course page and card) and on article, video and consultation card titles/descriptions; `IBM Plex Sans Arabic` added after Fraunces in `styles/global.css`.
- **Regression test:** `marketing/test/recorded.test.ts` "keeps Arabic-only course text in its own direction on the EN site (ETQAN-QA-771/754)". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** dir=auto is in the served HTML and the IBM Plex Sans Arabic face loads on EN pages. An Arabic-first title is laid out RTL on /en/. The QA title 'M15- …' starts with Latin, so bidi correctly keeps it LTR, which is why that page looks unchanged (data, not code). BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-771-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-772: Contact / trial form accepts any text as the phone number ("not a phone !!") and sends it to the office
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-026); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. EN (AR same form): `/en/#contact` → Name, Email, Phone number = `not a phone !!`, message → Send.
- **Expected:** Phone validated (digits, +, spaces, dashes) with a clear message, like the registration form.
- **Actual:** "Thanks — we received your message and will get back to you soon."; the office inquiries list shows "m16-en-contact@example.com not a phone !!" (Agent 1's inquiry) - stored as is.
- **Evidence:** `qa/manual/screens/M16/M16-F-026-phone-accepts-text.png`, `qa/manual/screens/M16/triage/t026-phone-accepts-text.png`, `qa/manual/screens/M16/triage/t019-inquiries.png`
- **Notes:** `site` inquiry serializer: validate phone format (server) + `type=tel` pattern in `ContactForm.astro`.
- **Root cause:** `InquirySerializer` had no phone validation; the form's `type=tel` accepts any text.
- **Fix (Agent 3, fix-1, 2026-10-28):** Server `validate_phone` in `site/api/views.py`: digits with optional +, spaces, dashes, dots, brackets, 6-15 digits (local numbers still allowed). Client: same rule in `ContactForm.astro` with "أدخل رقم هاتف صحيحًا…" before sending.
- **Regression test:** `backend/etqan/site/tests/test_inquiries.py::test_phone_must_look_like_a_phone` (5) and `::test_local_and_international_phones_are_accepted` (4); `marketing/test/components.test.ts` "refuses free text as a phone number before sending (ETQAN-QA-772)". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR 'not a phone !!' refused before sending ('أدخل رقم هاتف صحيحًا…'); POST /api/v1/site/inquiries/ with it -> 400; '+20 100 123 4567' accepted. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-772-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-773: Phone (Arabic): the academy name in the site header is cut at its start ("…n QA Academy")
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-027); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`, 375x812.
- **Reproduction steps:**
  1. AR: `/ar/` (any site page) on 375x812.
- **Expected:** "Etqan QA Academy" fits, or is cut at the end ("Etqan QA Aca…").
- **Actual:** Header shows "...n QA Academy": the span has `direction: rtl; text-overflow: ellipsis` (scrollWidth 161 > 143), so the Latin name is cut on the left. EN shows the full name.
- **Evidence:** `qa/manual/screens/M16/M16-F-027-mobile-name-truncated-start.png`, `qa/manual/screens/M16/triage/t027-mobile-header-ar.png`
- **Notes:** `dir="auto"` (or `unicode-bidi: plaintext`) on the header name span.
- **Root cause:** Header name span inherited `direction: rtl`, so `text-overflow: ellipsis` cut a Latin name at its start.
- **Fix (Agent 3, fix-1, 2026-10-28):** `dir="auto"` + `text-start` on the name (and tagline) span in `Header.astro`; a Latin name now ends "Etqan QA Acad…" (`qa/manual/screens/M16/fix/f773-774-smoke.png`).
- **Regression test:** `marketing/test/components.test.ts` "Header name (ETQAN-QA-773)". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR 375px header now 'Etqan QA Acad…' (cut at the end). BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-773-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-774: Phone: an article's cover image is hidden behind the green title band; only its bottom strip shows
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-028); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`, 375x812.
- **Reproduction steps:**
  1. AR: `/ar/articles/` → open "M13 مقال تجريبي عن أحكام التجويد" (now `/ar/articles/m13-first-article-v2`).
- **Expected:** The whole cover visible under (or slightly overlapping) the title band, as on desktop.
- **Actual:** The hero band covers most of the cover; only the last rows of the picture peek out above the first paragraph. No "back to articles" link on the page.
- **Evidence:** `qa/manual/screens/M16/M16-F-028-mobile-article-cover-hidden.png`, `qa/manual/screens/M16/triage/t028-mobile-article-cover.png`
- **Notes:** Article page negative top margin on the cover is sized for desktop; reduce it below `md`.
- **Root cause:** The title band is `relative isolate` (positioned), the `<article>` after it with `-mt-28` was not positioned, so the band painted over the cover where they overlap (most of a short phone-width cover).
- **Fix (Agent 3, fix-1, 2026-10-28):** `<article>` in `pages/[lang]/articles/[slug].astro` is `relative`, so the cover paints above the band on every width. (No live article on qa at fix time to screenshot; the stacking rule is the root cause.)
- **Regression test:** Covered by `marketing/test/articles.test.ts` (page still renders); no DOM-level paint test possible in node, so Agent 2's phone screenshot is the check. Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** Temporary article with cover on qa (deleted afterwards): AR 375px and desktop show the whole cover over the band. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-774-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-775: Unknown or cancelled payment-link pages give no academy contact or next step (unknown link: not even the academy name)
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M16 (M16-F-029); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** anonymous visitor, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/pay/link/BOGUS-TOKEN-xyz`.
  2. AR: `/app/pay/link/WcVGyq8lhuAyALmGjAnJEg` (cancelled).
- **Expected:** Academy name and "تواصل مع الأكاديمية" (email/WhatsApp from branding) so the payer can ask for a new link.
- **Actual:** Unknown: one red line "رابط الدفع هذا غير موجود." in an empty page (404 GET /api/v1/gateways/pay/BOGUS-TOKEN-xyz/). Cancelled: card ends with "تم إلغاء هذا الرابط." and nothing else.
- **Evidence:** `qa/manual/screens/M16/M16-F-029-bad-paylink-bare.png`, `qa/manual/screens/M16/triage/t029-bogus-link.png`, `qa/manual/screens/M16/triage/t029-cancelled-link.png`
- **Notes:** `routes/pay.link.$token.tsx`: render branding name + contact (from `/api/v1/site/branding/`) on the error states.
- **Root cause:** `PublicLinkPage.tsx` returned a bare alert on 404 and only a note for a cancelled link; the public branding (name, contact) was never read.
- **Fix (Agent 3, fix-1, 2026-10-28):** New `AskAcademy` block (academy name via `useBrandName`, "لطلب رابط جديد أو لأي استفسار، تواصل مع الأكاديمية:" with mailto/tel/wa.me built from `site/branding` contact) on the unknown-link page and under a cancelled link. Strings `gateways.link.askAcademy/whatsapp`.
- **Regression test:** `PublicLinkPage.test.tsx` "names the academy and how to reach it on a dead-end link (ETQAN-QA-775)" and "offers the academy's contact under a cancelled link". Evidence: `qa/manual/evidence/M16/fix-1/` (marketing-vitest.txt, dashboard-vitest.txt, dashboard-tsc.txt, backend-pytest.txt, backend-lint.txt, *-biome.txt).
- **Gate retest (Agent 2, 2026-10-28T14:58:46Z):** AR 375px bogus link on qa shows the academy name; on qaother with a temporary contact (restored) also the 'تواصل مع الأكاديمية' line with mailto/tel/WhatsApp. Cancelled link with no contact set shows no empty block. BEFORE/AFTER `qa/manual/screens/M16/fix/ETQAN-QA-775-after.png`; tests re-run green (marketing 347/347, dashboard 30 files/228, pytest 188, tsc 0).
- **Verification status:** VERIFIED

---

## ETQAN-QA-776: Closed-site (maintenance) page shows the academy name twice: "Etqan QA Academy · Etqan QA Academy"
- **Feature:** M16 Public pages. **Severity:** P4. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa` (and `qaother` where noted), Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 2 at triage on 2026-10-28.
- **Preconditions:** academy `qa` while its site status was `maintenance` (set by another area during the run).
- **Reproduction steps:**
  1. Open `http://qa.etqan.localhost/en/` while the site is in maintenance.
- **Expected:** The name once when the Arabic and English names are the same (and ideally the academy's contact).
- **Actual:** "Etqan QA Academy · Etqan QA Academy" above "الموقع تحت الصيانة / Under maintenance" (503).
- **Evidence:** `qa/manual/screens/M16/triage/g001-closed-site-name-twice.png`
- **Notes:** `marketing/src/components/ClosedPage.astro:49` prints `pick(name,'ar') · pick(name,'en')` unconditionally.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-777: Article page: a category name that ends in Latin letters or digits mixes with the date ("فئة بوابة 1 · M16 أكتوبر 2026")
- **Feature:** M16 Public pages. **Severity:** P4. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack, academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 375x812 and 1440x900. **Tag:** REAL
- **Found by:** Agent 2 at the M16 gate, 2026-10-28T14:58:46Z (temporary article `m16-gate-cover` in category "فئة بوابة M16", since deleted).
- **Reproduction steps:**
  1. AR: open an article whose category name ends in Latin letters or digits (e.g. "المستوى 2", "فئة M16").
- **Expected:** The gold category chip shows its whole name, then "·" and the date.
- **Actual:** Bidi reorders the chip text with the date's leading digit: the chip is split in two gold pieces, "فئة بوابة" + "1" + "M16", and the date reads "أكتوبر 2026".
- **Evidence:** `qa/manual/screens/M16/fix/g774-article-cover-m.png`, `qa/manual/screens/M16/fix/g774-article-cover-d.png`
- **Notes:** `marketing/src/pages/[lang]/articles/[slug].astro:95-96`: isolate the chip and the date (`<bdi>`, `dir="auto"` + `inline-block`/`unicode-bidi: isolate`).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-778: After a trial request is sent, the form silently returns to "تواصل معنا" while the trial success line stays; a second send from the page goes in as a plain contact
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (marketing/dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`. **Tag:** REAL
- **Found by:** Agent 1, M16 confirmation sweep (M16-F-030); reproduced by Agent 2 at the final gate, 2026-10-28T15:22:46Z.
- **Preconditions:** anonymous visitor; follows the ETQAN-QA-753 fix.
- **Reproduction steps:**
  1. AR 375x812: `/ar/` → hero "احجز حصة تجريبية" (heading becomes "اطلب حصة تجريبية", trial note shown).
  2. Name + phone `+201001112255` → "إرسال".
- **Expected:** The form stays a trial request (or is replaced by a trial success state), so a parent sending again for a second child still sends a trial request.
- **Actual:** Under the button "استلمنا طلب الحصة التجريبية، سنتواصل معك قريبًا لتحديد الموعد.", but the heading is "تواصل معنا", the trial note is hidden and the hidden `kind` is `contact` (eval). A second send is stored as a contact inquiry.
- **Evidence:** `qa/manual/screens/M16/M16-F-030-trial-heading-resets.png`, `qa/manual/screens/M16/triage/t030-trial-heading-resets-ar-m.png`
- **Notes:** `marketing/src/components/ContactForm.astro` submit handler calls `setKind("contact")` after `form.reset()` (deliberate in the 753 fix). Keep `wasTrial` kind after a successful send (still reset on `pageshow`). Test data: inquiry "M16 بوابة نهائية" (trial) on qa.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-779: Contact/trial form: the phone error is shown in the success green under the button, the field is not marked, and "12" is told "digits only"
- **Feature:** M16 Public pages. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (marketing/dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`. **Tag:** REAL
- **Found by:** Agent 1, M16 confirmation sweep (M16-F-031); reproduced by Agent 2 at the final gate, 2026-10-28T15:22:46Z.
- **Preconditions:** anonymous visitor; follows the ETQAN-QA-772 fix.
- **Reproduction steps:**
  1. AR 375x812: `/ar/` → "احجز حصة تجريبية" → Name, Phone `12` → "إرسال".
- **Expected:** An error in the error colour, at (or tied to) the phone field, with wording that fits (e.g. too short: 6–15 digits).
- **Actual:** "أدخل رقم هاتف صحيحًا: أرقام فقط، ويمكن أن يبدأ بعلامة +." in `rgb(14, 124, 102)` (the primary green used for "استلمنا طلب…"), under the button; phone box unchanged. EN same ("digits only, optionally starting with +"). On a phone it reads like a sent confirmation.
- **Evidence:** `qa/manual/screens/M16/M16-F-031-phone-error-green-ar.png`, `qa/manual/screens/M16/M16-F-031-phone-error-green-en.png`, `qa/manual/screens/M16/triage/t031-phone-error-green-ar-m.png`
- **Notes:** `ContactForm.astro`: `[data-result]` is always `text-[var(--primary)]`; switch to the destructive colour when `role=alert`, set `aria-invalid` + focus on the phone input, and mention the 6–15 digit length in `phoneInvalid` (marketing `lib/i18n.ts` ar/en). The "contact method required" alert has the same colour.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-780: Visitor consultation booking: slot days are bare "2026/10/29" with no weekday
- **Feature:** M16 Public pages. **Severity:** P4. **Type:** UX. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (marketing/dashboard with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`. **Tag:** REAL
- **Found by:** Agent 1, M16 confirmation sweep (M16-F-032); reproduced by Agent 2 at the final gate, 2026-10-28T15:22:46Z.
- **Preconditions:** anonymous visitor; consultation 2 with open slots.
- **Reproduction steps:**
  1. AR 1440x900: `/app/consult/2` → pick "الشيخ أحمد الحداد" → "اختر موعدًا".
- **Expected:** Each day labelled with its weekday ("الخميس، 29 أكتوبر"), as the checkout already does since ETQAN-QA-764.
- **Actual:** Day headings "2026/10/29", "2026/10/31", "2026/11/02" only.
- **Evidence:** `qa/manual/screens/M16/M16-F-032-slot-dates-no-weekday.png`, `qa/manual/screens/M16/triage/t032-slot-dates-no-weekday.png`
- **Notes:** `dashboard/src/features/consultations/BookingSlots.tsx:43` groups by `dayIn(...)`; show a weekday + day-month label (e.g. `formatDay` / the `appointmentText` date part). `SlotPicker.tsx:49` (signed-in booking) uses the same `dayIn` heading and likely needs the same change.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## --- M11 manual bugs ---

## ETQAN-QA-650: Homework detail dialog shows grey "غير مكتمل" for an answered homework while the list row says "بانتظار المراجعة"
- **Feature:** M11 Homework detail dialog (office and teacher, `homework/HomeworkDialog.tsx:192`). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-004); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`; teacher qa-teacher@ / `QA-People-2026!`; a homework the student answered and nobody reviewed ("M11 عنوان طويل جدا …", id 7).
- **Reproduction steps:**
  1. AR: `/app/scheduling/homework` (or teacher `/app/teaching/homework`) → row "M11 عنوان طويل جدا …" → فتح.
- **Expected:** The dialog header shows the same "بانتظار المراجعة" chip as the list.
- **Actual:** List chip "بانتظار المراجعة" (purple); dialog chip grey "غير مكتمل" next to "أجاب: QA student · تمت الإجابة في …".
- **Evidence:** `qa/manual/screens/M11/M11-F-004-homework-dialog-status-not-awaiting-review.png`, `qa/manual/screens/M11/triage/t001-hw-dialog-admin.png`, `qa/manual/screens/M11/triage/t003-hw-dialog-footer.png`
- **Notes:** The list (QA-415) and the student list (QA-458) got the `awaitingReview` chip; the dialog still prints `homework.status.${hw.status}`.
- **Root cause:** `HomeworkDialog.tsx` printed `homework.status.${hw.status}` and never got the `awaitingReview` chip the list got in ETQAN-QA-415.
- **Fix (Agent 3, 2026-10-28, cycle 1):** The dialog shows the same chip as the list: answered and not complete gives "بانتظار المراجعة".
- **Regression test:** `HomeworkDialog.test.tsx` "shows an answered, unreviewed homework as awaiting review (ETQAN-QA-650)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-650-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-651: Homework dialogs and cards: titles, instructions, answers, comments and file names have no `dir="auto"`, so Arabic-led text in the English UI (and mixed file names in Arabic) is laid out in the page direction and its punctuation moves
- **Feature:** M11 Homework (`HomeworkDialog.tsx`, `MyHomework.tsx`, `HomeworkList.tsx`: title, instructions, answer text, teacher comment, `file_name`/`answer_file_name` spans). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-007); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher qa-teacher@ / `QA-People-2026!`, EN session; admin AR session; homework id 6 "M11 حفظ سورة الملك ١-١٠" with file "M11-ورقة-الواجب.pdf".
- **Reproduction steps:**
  1. EN teacher: `/app/teaching/homework` → All → Open on "M11 حفظ سورة الملك ١-١٠".
  2. To see an Arabic-led text (the test data all starts with Latin "M11"): in the open dialog the header was replaced in DevTools with "حفظ سورة الملك (١-١٠)." and the answer with "حفظت الآيات من ١ إلى ١٠ وسجلت التلاوة." (computed `direction: ltr` on both).
  3. AR admin: `/app/scheduling/homework` → الكل → فتح on the same homework; look at the file line next to تنزيل.
- **Expected:** Each user text and file name takes its own direction (`dir="auto"`, like chat in QA-603/604): an Arabic sentence reads right-to-left with its full stop at the left end; a Latin-led file name reads left-to-right.
- **Actual:** EN: "(١٠-١) حفظ سورة الملك." — brackets and full stop on the wrong ends, text left-aligned; the answer likewise. AR: "M11-ورقة-الواجب.pdf" shows as "pdf.ورقة-الواجب-M11" read left to right. Agent 1's own Latin-led examples ("M11 …") render as UAX #9 says and are not the defect by themselves.
- **Evidence:** `qa/manual/screens/M11/M11-F-007-en-homework-arabic-text-ltr.png`, `qa/manual/screens/M11/M11-F-002-homework-file-name-mirrored.png`, `qa/manual/screens/M11/triage/t007-en-teacher-hw-arabic.png`, `qa/manual/screens/M11/triage/t007b-en-arabic-led-text-ltr.png`, `qa/manual/screens/M11/triage/t002-hw-file-dialog-bottom.png`
- **Notes:** M11-F-002 (file name in AR) is the same fix and is folded in here. DOM eval: no element in the homework dialog has a `dir` attribute. Chat already uses `dir="auto"` (QA-604 NOT-A-BUG because it had it).
- **Root cause:** No element in the homework UI had `dir`, so user text took the page direction.
- **Fix (Agent 3, 2026-10-28, cycle 1):** `dir="auto"` on the title (DialogTitle, list cell, student card), instructions, answer text, teacher comment, file and answer-file names, and on the title/instructions/comment/answer inputs, in `HomeworkDialog.tsx`, `MyHomework.tsx`, `HomeworkList.tsx`.
- **Regression test:** `HomeworkDialog.test.tsx` "lets each user text and file name take its own direction (ETQAN-QA-651)"; `MyHomework.test.tsx` "lets the student's texts and file names take their own direction (ETQAN-QA-651)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-651-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-652: Homework detail dialog footer wraps to two rows: outline "حفظ" sits between "إغلاق" and the red "حذف الواجب", and the main "تحديد كمكتمل" drops alone below
- **Feature:** M11 Homework detail dialog (`HomeworkDialog.tsx` footer). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no (P4, small). **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-003); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR, 1440x1500: `/app/scheduling/homework` → فتح on any homework → look at the footer.
- **Expected:** One footer row: primary action(s) together, "إغلاق" secondary, delete set apart.
- **Actual:** Row 1 "حفظ" (outline) · "إغلاق" · solid red "حذف الواجب"; row 2 "تحديد كمكتمل" alone. Which button saves the comment is unclear.
- **Evidence:** `qa/manual/screens/M11/M11-F-003-homework-dialog-buttons-two-rows.png`, `qa/manual/screens/M11/triage/t003-hw-dialog-footer.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-653: New homework: Student and Course selects are blank boxes with no "اختر…" text, and the teacher's student list is unsorted
- **Feature:** M11 New homework dialog (`NewHomeworkDialog.tsx`, `homework/pickers.ts`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-005); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher qa-teacher@ / `QA-People-2026!`; also admin.
- **Reproduction steps:**
  1. AR teacher: `/app/teaching/homework` → واجب جديد → look at الطالب / الدورة; open الطالب.
- **Expected:** Placeholders "اختر طالبًا" / "اختر دورة" (course: "اختر الطالب أولًا"); students A→Z.
- **Actual:** Both selects are empty white boxes; options: "(blank) | QA6 Student 1 | QA6 Student 4 | QA6 Student 2 | QA6 Student SA | QA student | QA6 Student 3 | SCN Student A1 | QA Student Three | QA Student Two".
- **Evidence:** `qa/manual/screens/M11/M11-F-005-teacher-student-picker-unsorted-no-placeholder.png`, `qa/manual/screens/M11/triage/t005-teacher-new-hw-dialog.png`
- **Root cause:** `NewHomeworkDialog.tsx` rendered an empty `<option value="" />` in both selects; `pickers.ts` kept the teacher's students in subscription order.
- **Fix (Agent 3, 2026-10-28, cycle 1):** Placeholders `homework.dialog.pickStudent` ("اختر طالبًا"), `pickCourse` ("اختر دورة") and `pickStudentFirst` ("اختر الطالب أولًا") in ar/en; the teacher's students are sorted with `localeCompare`.
- **Regression test:** `NewHomeworkDialog.test.tsx` "says what to pick and lists a teacher's students by name (ETQAN-QA-653)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-653-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-654: Phone: the "تم إرسال الإجابة." toast lies over the homework dialog's "استبدال الإجابة" / "إلغاء" buttons for several seconds
- **Feature:** M11 Student homework dialog on a phone (global toaster position, `MyHomework.tsx`). **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-008); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** student qa-student@ / `QA-People-2026!`, 375x812.
- **Reproduction steps:**
  1. `/app/learning/homework` → open "M11 عنوان طويل…" → type an answer → استبدال الإجابة → open the same homework again at once.
- **Expected:** The toast doesn't cover controls (top on phones, or above the dialog's footer).
- **Actual:** The full-width toast sits on top of "استبدال الإجابة" and "إلغاء" at the bottom of the dialog until it times out.
- **Evidence:** `qa/manual/screens/M11/M11-F-008-mobile-toast-covers-dialog-buttons.png`, `qa/manual/screens/M11/triage/t008-mobile-toast-over-buttons.png`
- **Notes:** Agent 2 replaced the answer of homework 7 with "M11 الإدغام … (مراجعة Agent 2)".
- **Root cause:** The global toast viewport (`ui/toast.tsx`) sits full-width at the bottom below `sm`, the same edge as a phone dialog's footer.
- **Fix (Agent 3, 2026-10-28, cycle 1):** Below `sm` the viewport is at the top (`top-0`); from `sm` it stays in the bottom end corner (`sm:top-auto sm:bottom-0`). That also keeps it off a call's control bar, which the old `pb-24` was there for.
- **Regression test:** `ui/toast.test.tsx` "sits at the top on a phone, the bottom end corner from sm (ETQAN-QA-654)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-654-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-655: Materials shelf: a link material gets a tiny underlined "فتح" text while a file gets a bordered "تنزيل" button
- **Feature:** M11 Student/teacher course materials (`/app/learning/materials`, `/app/teaching/materials`). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no (P4, small). **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-011); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** student qa-student@ / `QA-People-2026!`; link material "M11 رابط تلاوة سورة الملك" (F03 قرآن).
- **Reproduction steps:**
  1. AR student: `/app/learning/materials`.
- **Expected:** The same kind of control for both (a button "فتح الرابط" / "تنزيل").
- **Actual:** Link row: small green underlined "فتح" at the far end; file row: a proper outline "تنزيل" button. The link is easy to miss.
- **Evidence:** `qa/manual/screens/M11/M11-F-011-materials-open-link-vs-download-button.png`, `qa/manual/screens/M11/triage/t011-student-materials.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-656: Level dialog: the topic block has no title and the sub-level's إزالة/تحريك row sits between its names and its topics; nothing says which block is a sub-level and which a topic
- **Feature:** M11 Level dialog (`curriculum/LevelDialog.tsx`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-012); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR, 1440x1300: `/app/catalogue/levels` → إضافة مستوى → إضافة مستوى فرعي → إضافة موضوع.
- **Expected:** Each block titled ("مستوى فرعي 1", "موضوع 1") or topics under a "الموضوعات" heading; each block's actions at its own top/bottom edge.
- **Actual:** Under "المستويات الفرعية": names, then the sub-level's "تحريك لأعلى / تحريك لأسفل / إزالة", then an unlabelled shaded block with the same two name fields plus السورة/من الآية/إلى الآية and its own إزالة. Only the surah fields hint that it is a topic.
- **Evidence:** `qa/manual/screens/M11/M11-F-012-level-dialog-sublevel-topic-unlabelled.png`, `qa/manual/screens/M11/triage/t012-level-dialog-blocks.png`
- **Root cause:** `LevelDialog.tsx` rendered each block's move/remove row after its name fields, with no block title.
- **Fix (Agent 3, 2026-10-28, cycle 1):** `RowButtons` now takes a title and sits as the block's top row: "المستوى الفرعي 1" / "الموضوع 1" (`curriculum.levels.subLevelN`/`topicN`) with its own تحريك/إزالة beside it, before the fields.
- **Regression test:** `LevelDialog.test.tsx` "titles each sub-level and topic block, its actions on its top row (ETQAN-QA-656)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-656-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-657: Progress panel shows a topic by name only; the surah and verse range the office set (الملك ١–١٠) are not shown to the teacher, the office drawer or the student
- **Feature:** M11 Student progress panel (teacher "مستويات طلابي", office student levels drawer, student "تقدّمي"). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-013); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher qa-teacher@ / `QA-People-2026!`; level "M11 المستوى الأول" with topic "M11 سورة الملك" = chapter 67, verses 1–10.
- **Reproduction steps:**
  1. AR teacher: `/app/teaching/levels` → فتح التقدّم on QA student · F03 قرآن → expand "M11 المستوى الأول".
- **Expected:** "M11 سورة الملك — الملك ١–١٠", so the teacher knows what to hear (curriculum.md: topics "point at a Qur'an chapter and a verse range").
- **Actual:** Only the checkbox, "M11 سورة الملك" and "أُنجز في 2026/10/28".
- **Evidence:** `qa/manual/screens/M11/M11-F-013-progress-topic-no-surah-verses.png`, `qa/manual/screens/M11/triage/t013-topic-no-surah.png`
- **Notes:** The level payload carries `chapter` (id) and verses (`learning/api/serializers.py:82`), but a teacher can't read the chapter list (GET quran-chapters needs `quran_chapter.view_any`/`level.*`), so showing the name likely needs the chapter name in the progress payload (API change → proposal).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-658: "طلب ترقية" form doesn't say to which level, and the student's current level card isn't marked in the ladder
- **Feature:** M11 Teacher progress panel, upgrade request form. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-014); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher qa-teacher@ / `QA-People-2026!`; QA Student Three · F03 قرآن set to "M11 المستوى الأول" by Agent 2.
- **Reproduction steps:**
  1. AR teacher: `/app/teaching/levels` → فتح التقدّم on QA Student Three · F03 قرآن → طلب ترقية.
- **Expected:** "ترقية من M11 المستوى الأول إلى M11 المستوى الثاني" above the note; the current level highlighted in the list.
- **Actual:** Only "ملاحظة" + "إرسال الطلب"/"إلغاء"; the target appears only after sending (office list "M11 المستوى الأول ← M11 المستوى الثاني"). Both level cards look identical.
- **Evidence:** `qa/manual/screens/M11/M11-F-014-upgrade-request-no-target-level.png`, `qa/manual/screens/M11/triage/t014-upgrade-form-no-target.png`
- **Notes:** `to_level` is "the next active level by position" (curriculum.md), which the panel already has.
- **Root cause:** `ProgressPanel.tsx` `UpgradeForm` got only student/course; level cards had no current marker.
- **Fix (Agent 3, 2026-10-28, cycle 1):** The form says "ترقية من {from} إلى {to}" (`curriculum.progress.upgradeFromTo`, `to` = the next active level the panel already computes); the current level card has `border-primary` and a "المستوى الحالي" chip.
- **Regression test:** `ProgressPanel.test.tsx` "names the target level in the upgrade form (ETQAN-QA-658)", "marks the student's current level card (ETQAN-QA-658)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-658-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-659: Level upgrade requests: the office sidebar item "طلبات الترقية" has no pending count, so a request is noticed only by opening the page
- **Feature:** M11 Office navigation / `/app/scheduling/level-upgrades`. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-015); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`; one pending request (QA Student Three, sent by Agent 2 as qa-teacher).
- **Reproduction steps:**
  1. Teacher sends an upgrade request.
  2. AR admin: look at the sidebar; open `/app/scheduling/level-upgrades`.
- **Expected:** A count badge like "التسجيلات 3".
- **Actual:** No badge on "طلبات الترقية"; the page tab says "قيد الانتظار (1)".
- **Evidence:** `qa/manual/screens/M11/M11-F-015-upgrades-no-sidebar-count-one-click-approve.png`, `qa/manual/screens/M11/triage/t015-upgrades-no-count.png`
- **Notes:** Not a bug: one-click "قبول" with no confirm. The row already shows from→to level, approval is the documented single action (`approve_request`), and the office can set any level from student levels, so it is reversible. Notifications `level.upgrade_requested` exist (curriculum.md).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-660: Student "تقدّمي" (and the teacher list): the count under the current level's name is the whole course ("1 من 1", full bar) though the new level 2 has no topics
- **Feature:** M11 Student progress card / teacher "مستويات طلابي" المنجز column. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-016); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** student qa-student@ / `QA-People-2026!`; QA student moved to "M11 المستوى الثاني" (0 topics) after completing the only topic of level 1.
- **Reproduction steps:**
  1. AR student: `/app/learning/progress`.
- **Expected:** The count labelled as the course total ("في الدورة: 1 من 1"), or the current level's own progress.
- **Actual:** "M11 المستوى الثاني" then "الموضوعات المكتملة: 1 من 1" and a 100% bar — reads as if level 2 is done.
- **Evidence:** `qa/manual/screens/M11/M11-F-016-progress-level2-shows-1-of-1-full-bar.png`, `qa/manual/screens/M11/triage/t016-student-progress-1of1.png`, `qa/manual/screens/M11/triage/t013a-teacher-progress.png`
- **Notes:** Totals are course-wide by design (curriculum.md "Totals count only topics of active levels"), so the fix is the label/layout, not the number.
- **Root cause:** The counts are course-wide by design (curriculum.md) but labelled as if per level ("الموضوعات المكتملة", column "المنجز").
- **Fix (Agent 3, 2026-10-28, cycle 1):** Label only: `curriculum.progress.topicsOf` = "موضوعات الدورة المكتملة: {n} من {m}" / "Course topics completed: …", `curriculum.progress.completed` = "المنجز في الدورة" / "Completed in the course" (teacher/office column header and the bar labels).
- **Regression test:** `MyProgress.test.tsx` "shows a student their own course card and its ladder" (asserts the course wording, ETQAN-QA-660). Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-660-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-661: Qur'an chapters "تعديل الأسماء": fields "الاسم المبسّط" / "الاسم المشكّل" (EN "Simple name"/"Complex name") both hold the Latin "Al-Mulk"; the labels don't say they are transliterations
- **Feature:** M11 Qur'an chapters (`curriculum/ChaptersTable.tsx`, `locales/{ar,en}/curriculum.json`). **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-017); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR/EN: `/app/catalogue/quran` → row 67 → تعديل الأسماء.
- **Expected:** Labels that say what each is (e.g. "الاسم اللاتيني (مبسّط)" / "الاسم اللاتيني (بعلامات النطق)"), maybe with a hint where it shows.
- **Actual:** "المشكّل" means "with Arabic diacritics" to an Arabic reader, but the field holds "Al-Mulk"; the table column "الاسم المبسّط" shows Latin names in the Arabic UI.
- **Evidence:** `qa/manual/screens/M11/M11-F-017-quran-names-labels-ar.png`, `qa/manual/screens/M11/M11-F-017b-quran-names-labels-en.png`, `qa/manual/screens/M11/triage/t017-018-surah-names-empty.png`
- **Notes:** Fields are `name_simple`/`name_complex` from the bundled quran.com data.
- **Root cause:** The labels translate quran.com's field names (`name_simple`/`name_complex`) literally.
- **Fix (Agent 3, 2026-10-28, cycle 1):** `curriculum.quran.simple` = "الاسم بالحروف اللاتينية" / "Latin name", `complex` = "الاسم اللاتيني بعلامات النطق" / "Latin name with accents".
- **Regression test:** `ChaptersTable.test.tsx` "shows the chapters and edits a chapter's names" (finds the field by the new label, ETQAN-QA-661). Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-661-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-662: Surah names: an empty Arabic name is refused only by the server, with Django's "لا يمكن لهذا الحقل ان يكون فارغاً."; no field is marked required
- **Feature:** M11 Qur'an chapters edit-names dialog. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-018); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/catalogue/quran` → row 67 → تعديل الأسماء → clear "الاسم بالعربية" → حفظ.
- **Expected:** The field marked required (*) and checked before sending, in the product's wording ("أدخل اسم السورة.").
- **Actual:** 400 PATCH `/api/v1/learning/quran-chapters/67/`, then Django's generic sentence ("ان" without hamza) under the field; no asterisks on any of the three names.
- **Evidence:** `qa/manual/screens/M11/M11-F-018-surah-empty-name-django-message.png`, `qa/manual/screens/M11/triage/t017-018-surah-names-empty.png`
- **Notes:** Dialog cancelled; no data changed.
- **Root cause:** `ChaptersTable.tsx` EditNames had no `required` and no client check; all three names are required by `ChapterNamesInput`.
- **Fix (Agent 3, 2026-10-28, cycle 1):** Each field is `required`; empty (after trim) shows `curriculum.quran.required` "أدخل هذا الاسم." before sending.
- **Regression test:** `ChaptersTable.test.tsx` "marks the names required and checks an empty one before sending (ETQAN-QA-662)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-662-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-663: "إضافة تكريم": the Student dropdown lists only the first 100 students, no search; Arabic-named students can't be honoured
- **Feature:** M11 Honour board dialog (`/app/people/honour`). **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-019); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`; academy qa has >100 active students.
- **Reproduction steps:**
  1. AR: `/app/people/honour` → إضافة تكريم → open الطالب (eval: option count).
- **Expected:** Every active student reachable (search box like the homework/certificate dialogs).
- **Actual:** 101 options (blank + 100), last "QA5 RT1 ok"; the dialog has no search input (inputs: text, text, month, checkbox).
- **Evidence:** `qa/manual/screens/M11/M11-F-019-honour-student-picker-100-no-search.png`, `qa/manual/screens/M11/triage/t019-021-honour-dialog.png`
- **Notes:** Same family as ETQAN-QA-202 / 273 / 371 (100-cap pickers, OPEN); the owner has a pending proposal for one shared searchable student picker.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-664: Dialog button order differs: the honour dialog puts "حفظ" on the right (start), while the homework, content, level and certificate dialogs put the primary button on the left
- **Feature:** M11 Honour board dialog vs other learning dialogs. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-021); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/people/honour` → إضافة تكريم; compare `/app/catalogue/levels` → إضافة مستوى and `/app/teaching/homework` → واجب جديد.
- **Expected:** One order across the app.
- **Actual:** Honour: "حفظ" right, "إلغاء" left. Levels/homework/content: "حفظ"/"إضافة واجب" left, "إلغاء" right.
- **Evidence:** `qa/manual/screens/M11/M11-F-021-dialog-button-order-inconsistent.png`, `qa/manual/screens/M11/triage/t019-021-honour-dialog.png`, `qa/manual/screens/M11/triage/t012-level-dialog-blocks.png`, `qa/manual/screens/M11/triage/t005-teacher-new-hw-dialog.png`
- **Root cause:** `HonourDialog.tsx` used its own `<div>` with Save before Cancel instead of `DialogFooter`.
- **Fix (Agent 3, 2026-10-28, cycle 1):** Uses `DialogFooter` with Cancel then Save, like the other dialogs.
- **Regression test:** `HonourAdmin.test.tsx` "orders the dialog buttons like the other dialogs (ETQAN-QA-664)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-664-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-665: "إصدار شهادة": a completion certificate for a course that doesn't grant them shows the raw English "Completion certificates are not enabled for this course." under الدورة
- **Feature:** M11 Issue certificate dialog (`/app/people/certificates`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-022); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`; course تجويد not ticked in the template's "الدورات التي تمنح شهادات".
- **Reproduction steps:**
  1. AR: `/app/people/certificates` → إصدار شهادة → search "QA student" → الطالب QA student → الدورة تجويد → النوع إتمام → إصدار شهادة.
- **Expected:** Arabic (the dialog already knows: "هذه الدورة لا تمنح شهادات إتمام."), ideally refused before sending.
- **Actual:** 400 POST `/api/v1/learning/certificates/`; red English text under الدورة with the full stop at the start (".course"), and the Arabic hint repeated under النوع.
- **Evidence:** `qa/manual/screens/M11/M11-F-022-cert-english-server-error.png`, `qa/manual/screens/M11/triage/t022-cert-english-error.png`
- **Notes:** Same class as ETQAN-QA-157/561 (server text mapping, `lib/server-messages.ts`). Dialog not saved.
- **Root cause:** The server sends a fixed English sentence with no code (`learning/services/certificates.py:307`) and the dialog sent the request although it already knew the course was off.
- **Fix (Agent 3, 2026-10-28, cycle 1):** `lib/server-messages.ts` maps it to `certificates.dialog.courseOff`; `IssueCertificateDialog.tsx` refuses a completion certificate in such a course before sending (error under الدورة).
- **Regression test:** `IssueCertificateDialog.test.tsx` "refuses a completion certificate in such a course before sending (ETQAN-QA-665)"; `certificates/errors.test.ts` "the server's course refusal (ETQAN-QA-665)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-665-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-666: Revoke certificate: the destructive "إلغاء الشهادة" sits next to "إلغاء" (cancel), and the confirm card opens over the bright certificate dialog
- **Feature:** M11 Certificate detail dialog → revoke confirmation. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-023); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/people/certificates` → فتح on an active QA student certificate → إلغاء الشهادة.
- **Expected:** Distinct verbs ("إبطال الشهادة" / "تراجع"); the confirm clearly above a dimmed dialog.
- **Actual:** Confirm "إلغاء هذه الشهادة؟" with buttons "إلغاء الشهادة" (red) and "إلغاء"; the footer of the dialog under it also has "إلغاء الشهادة", "حذف الشهادة", "إغلاق". The confirm overlaps the middle of the undimmed dialog.
- **Evidence:** `qa/manual/screens/M11/M11-F-023-revoke-cancel-same-word-no-dim.png`, `qa/manual/screens/M11/triage/t023-revoke-confirm.png`
- **Notes:** The overlay part is the same nested-confirm pattern as ETQAN-QA-414 (homework delete, OPEN P4); fix both together. Confirm not submitted.
- **Root cause:** Copy: Arabic "revoke" was "إلغاء", the same word as cancel. Overlay: `OVERLAY` was `z-40` under the positioner's `z-50`, so a nested confirm's scrim slid under the first dialog's panel (also the cause of ETQAN-QA-414).
- **Fix (Agent 3, 2026-10-28, cycle 1):** AR revoke wording is now "إبطال" (button "إبطال الشهادة", title "إبطال هذه الشهادة؟", status "مُبطَلة", etc. in `locales/ar/certificates.json`); `ui/dialog.tsx` `OVERLAY` is `z-50`, so a later overlay paints over the earlier panel.
- **Regression test:** `certificates/copy.test.ts` "revokes with a verb that isn't the cancel button's"; `ui/dialog.test.tsx` "scrims on the panel's own layer, so a nested confirm dims its dialog (ETQAN-QA-666)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-666-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-667: Student/parent "شهاداتي": the certificate card has no visible "عرض / طباعة" action; only clicking the whole card opens it
- **Feature:** M11 Student certificates list (`/app/learning/certificates`). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no (P4, small). **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-024); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** student qa-student@ / `QA-People-2026!`.
- **Reproduction steps:**
  1. AR, 375x812 and 1440: `/app/learning/certificates`.
- **Expected:** A visible "عرض الشهادة" button or an arrow.
- **Actual:** A plain card "شهادة إتمام · F03 قرآن · حصة مكتملة واحدة · 2026/10/28"; the whole card is one link to `/app/certificates/2/print` with no affordance.
- **Evidence:** `qa/manual/screens/M11/M11-F-024-student-cert-card-no-view-print-affordance.png`, `qa/manual/screens/M11/triage/t024-student-cert-card-mobile.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-668: Phone: the certificate print page shows only a ~230 px slice of the certificate; the top line, academy name, title, message, date and verification link are clipped
- **Feature:** M11 Certificate print page (`/app/certificates/<id>/print`), student and office. **Severity:** P2. **Type:** mobile. **Easy P3:** no. **Priority:** high
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-025); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** student qa-student@ / `QA-People-2026!`, 375x812.
- **Reproduction steps:**
  1. `/app/certificates/2/print` at 375 wide (or tap the card in شهاداتي).
- **Expected:** The whole certificate scaled to the screen width (print layout unchanged).
- **Actual:** Inside the frame only the photo, "QA student", "في دورة", "F03 قرآن" and "حصة مكتملة واحدة" show; "تُمنح هذه الشهادة إلى" is cut through at the top and everything else is hidden. Page itself is 375 wide (no scroll to reach it).
- **Evidence:** `qa/manual/screens/M11/M11-F-025-mobile-certificate-content-clipped.png`, `qa/manual/screens/M11/triage/t025-mobile-cert-print-clipped.png`
- **Notes:** P2: on a phone, the main device for students and parents, the student cannot see their own certificate.
- **Root cause:** The sheet had a fixed A4 shape (`aspect-[297/210]` + `overflow-hidden`) at every width, so at 375 px it was ~240 px tall and its text was clipped.
- **Fix (Agent 3, 2026-10-28, cycle 1):** `CertificatePrint.tsx`: the A4 shape applies from `sm` (`sm:aspect-[297/210]`, and `@media print` still sets 297x210 mm); below `sm` the sheet grows with its text, with `py-12` so the top line clears the frame. Phone look: `qa/manual/screens/M11/fix/a3-668-cert-mobile.png`.
- **Regression test:** `CertificatePrint.test.tsx` "keeps the A4 shape from sm up and lets a phone sheet grow (ETQAN-QA-668)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-668-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-669: Phone: the admin "الشهادات" page is 512 px wide and opens scrolled sideways (title, menu and student names off-screen)
- **Feature:** M11 Office certificates list, 375x812. **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-026); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR, 375x812: `/app/people/certificates` (eval `[scrollWidth, innerWidth, scrollX]`).
- **Expected:** The page fits; the table scrolls inside its box.
- **Actual:** `[512, 512, -137]`: filters cut, only النوع/الحصص/تاريخ الإ… visible, no title, no menu button.
- **Evidence:** `qa/manual/screens/M11/M11-F-026-mobile-admin-certificates-page-widened.png`, `qa/manual/screens/M11/triage/t026-mobile-admin-certs-wide.png`
- **Notes:** Same pattern as ETQAN-QA-426 (fixed with `relative` on the scroller) and QA-573; new screen.
- **Root cause:** Same as ETQAN-QA-573: the table's sr-only header escaped the `overflow-x-auto` box (no `relative`) and widened the page.
- **Fix (Agent 3, 2026-10-28, cycle 1):** `CertificatesList.tsx`: `relative` on the scroller. Phone check after the fix: `[375,375,0]`, `qa/manual/screens/M11/fix/a3-669-certs-mobile.png`.
- **Regression test:** `CertificatesList.test.tsx` "keeps the sr-only header inside its scroller on a phone (ETQAN-QA-669)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-669-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-670: Library "رفع ملف" (AR): the allowed-types line is reordered by bidi ("، نص، " jumps, "صور،" ends up at the line end); no size limit is given
- **Feature:** M11 Library upload dialog (`/app/library`). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-027); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/library` → رفع ملف.
- **Expected:** "صور، PDF، Word، Excel، PowerPoint، نص، CSV، MP3، M4A، MP4" in order, plus the maximum size.
- **Actual:** Rendered "CSV، MP3، ،PDF، Word، Excel، PowerPoint، نص، صور … M4A، MP4"-like order across two lines; no size anywhere.
- **Evidence:** `qa/manual/screens/M11/M11-F-027-library-types-list-scrambled.png`, `qa/manual/screens/M11/triage/t027-028-library-types-exe.png`
- **Notes:** innerText is in the right logical order; it is the display (Latin runs with Arabic commas). Isolate each item or use a list.
- **Root cause:** One string "صور، PDF، Word، …": Latin names joined by Arabic commas form one LTR run and are reordered.
- **Fix (Agent 3, 2026-10-28, cycle 1):** `UploadDialog.tsx` renders the list from a constant, each item in `<bdi>`, joined by `library.listSeparator`, then `library.maxSize` "حتى 20 ميغابايت للملف الواحد." (ar/en/es; `library.accepted` replaced by `typeImages`/`typeText`).
- **Regression test:** `UploadDialog.test.tsx` "isolates each allowed type and gives the size limit (ETQAN-QA-670)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-670-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-671: Library upload of a wrong type shows English ".This type of file is not allowed" in the Arabic dialog
- **Feature:** M11 Library upload dialog. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-028); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/library` → رفع ملف → file `M11-bad.exe` → رفع ملف.
- **Expected:** "نوع هذا الملف غير مسموح." (already mapped in `lib/server-messages.ts`).
- **Actual:** 400 POST `/api/v1/library/`; English sentence with the full stop at the start.
- **Evidence:** `qa/manual/screens/M11/M11-F-028-library-type-error-english.png`, `qa/manual/screens/M11/triage/t027-028-library-types-exe.png`
- **Notes:** Same server text as ETQAN-QA-157 / 561 (VERIFIED for people and catalogue); the library dialog doesn't pass server errors through the mapping.
- **Root cause:** `UploadDialog.tsx` put `fieldErrors.file` on screen raw, without the `server-messages` mapping.
- **Fix (Agent 3, 2026-10-28, cycle 1):** Field and form errors go through `serverMessageKey` ("نوع هذا الملف غير مسموح.").
- **Regression test:** `UploadDialog.test.tsx` "translates the server's file-type refusal (ETQAN-QA-671)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-671-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-672: Library list (AR): the meta line is scrambled "2026/10/PDF · 45 B · QA Admin · 28" and the size unit is English "B"
- **Feature:** M11 Library list row. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-029); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`; file "M11 triage ورقة مراجعة" (45 B PDF) uploaded by Agent 2.
- **Reproduction steps:**
  1. AR: `/app/library`.
- **Expected:** "PDF · 45 بايت · QA Admin · 2026/10/28" readable.
- **Actual:** The day "28" sits at one end and "2026/10/" at the other; "45 B".
- **Evidence:** `qa/manual/screens/M11/M11-F-029-library-meta-line-scrambled.png`, `qa/manual/screens/M11/triage/t029-library-meta-line.png`
- **Notes:** Same family as ETQAN-QA-163 / 603 (VERIFIED elsewhere: `<bdi>` per part, localised size).
- **Root cause:** The meta line was one text run, and `formatBytes` wrote English units.
- **Fix (Agent 3, 2026-10-28, cycle 1):** Each part in `<bdi>`; `formatBytes(bytes, t, locale)` uses `library.sizes.*` ("45 بايت") and locale digits.
- **Regression test:** `LibraryList.test.tsx` "lists name, human size, uploader and date" (bdi parts); `library/schemas.test.ts` "formats sizes in Arabic words (ETQAN-QA-672)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-672-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-673: Library "نسخ الرابط": when the clipboard is refused the user gets only "حدث خطأ ما. حاول مرة أخرى."; the link is never shown anywhere to copy or open by hand
- **Feature:** M11 Library list (`/app/library`). **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-030); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/library` → نسخ الرابط (headless Chromium, no clipboard permission).
  2. Same with `navigator.clipboard.writeText` stubbed to succeed.
- **Expected:** On failure the URL shown (dialog/field to copy) or an "فتح" link; the error says the copy failed.
- **Actual:** Failure: generic error toast, no URL, no open/preview action in the row (no `<a>` in main). Success (stub): copies the absolute `http://qa.etqan.localhost/media/tenants/academy_qa/library/<hash>.pdf` and toasts "تم نسخ الرابط." — the success path works.
- **Evidence:** `qa/manual/screens/M11/M11-F-030-library-copy-link-fails-no-fallback.png`, `qa/manual/screens/M11/triage/t030-copy-link-fails.png`, `qa/manual/screens/M11/triage/t030b-copy-link-success-stub.png`
- **Notes:** The page's whole job is getting a public link; clipboard refusal happens with permission policies, some browsers and embedded webviews.
- **Root cause:** `copyLink` caught a clipboard refusal with `errors.generic` and the row had no link.
- **Fix (Agent 3, 2026-10-28, cycle 1):** A failed copy toasts `library.copyFailed` with an "فتح" action; each row has an "فتح" link to the file (`target=_blank`).
- **Regression test:** `LibraryList.test.tsx` "says a refused copy failed and offers the link to open (ETQAN-QA-673)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-673-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-674: Library delete confirm: "حذف 1 ملف؟ ستتوقف الروابط المؤدية إليها عن العمل." (digit + singular noun, feminine "إليها" for ملف)
- **Feature:** M11 Library delete confirmation (`locales/ar/library.json`). **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-031); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/library` → حذف on a file.
- **Expected:** "حذف هذا الملف؟ ستتوقف الروابط المؤدية إليه عن العمل." (plural keys for the bulk case: ملفين / 3 ملفات).
- **Actual:** "حذف 1 ملف؟ … إليها …".
- **Evidence:** `qa/manual/screens/M11/M11-F-031-library-delete-1-file-grammar.png`, `qa/manual/screens/M11/triage/t031-library-delete-grammar.png`
- **Notes:** Family of ETQAN-QA-208/113 (plural keys). Confirm cancelled.
- **Root cause:** One non-plural key `library.confirmDelete` with `{{count}}` and a feminine pronoun.
- **Fix (Agent 3, 2026-10-28, cycle 1):** Single-row confirm uses `library.confirmDeleteOne` "حذف هذا الملف؟ … إليه …"; bulk `confirmDelete_*` and `deleted_*` have Arabic plural forms (ملف واحد / ملفين / 3 ملفات / 11 ملفًا) and en/es `_one/_other`.
- **Regression test:** `LibraryList.test.tsx` "asks before deleting one file; cancel keeps it"; `library/schemas.test.ts` "words the Arabic delete confirm by number (ETQAN-QA-674)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-674-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-675: Monthly report "اكتب بالذكاء الاصطناعي" is offered when no AI account is set up; the user learns it only after writing instructions and pressing إنشاء. The facts panel is titled "سجلات هذا الشهر" for the chosen (past) month
- **Feature:** M11 Student report form (`studentReports/ReportForm.tsx`, shared `ai/AiDraftButton.tsx`). **Severity:** P4. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-032); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`; academy qa has no AI account (academy or Etqan default).
- **Reproduction steps:**
  1. AR: `/app/people/student-reports/new` → search/select QA Student Three (month September 2026) → اكتب بالذكاء الاصطناعي → instructions → إنشاء.
- **Expected:** If AI isn't set up, say so on the button/before typing ("غير متاح – أعِدّه من التكاملات"); panel title naming the month.
- **Actual:** 409 POST `/api/v1/ai/drafts/`, then "الذكاء الاصطناعي غير مُعدّ لهذه الأكاديمية." + link to Integrations. Panel title "سجلات هذا الشهر".
- **Evidence:** `qa/manual/screens/M11/M11-F-032-ai-draft-not-configured-after-generate.png`, `qa/manual/screens/M11/triage/t032-ai-draft-not-set-up.png`
- **Notes:** The 409 itself is documented (ai.md: `integrations.resolve("ai")` None → 409 `ai.not_set_up`; `ETQAN_AI_FAKE` fakes the model, it still needs an account), and the message is clear Arabic. Same class as ETQAN-QA-619 (WhatsApp offered while not set up). Nothing saved.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-676: Monthly report print page repeats the student and month (header "التقرير الشهري / سبتمبر 2026 / QA student", then a fields row with both again); the header's month is centred while the name is start-aligned
- **Feature:** M11 Report print (`studentReports/ReportPrint.tsx`). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no (P4, small). **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-033); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`; report 1 (QA student, September 2026).
- **Reproduction steps:**
  1. AR: `/app/student-reports/1/print`.
- **Expected:** Student and month once, in an aligned header.
- **Actual:** As titled.
- **Evidence:** `qa/manual/screens/M11/M11-F-033-report-print-name-month-twice.png`, `qa/manual/screens/M11/triage/t033-report-print-twice.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-677: Certificate and report print pages spin "جارٍ التحميل" forever when the API refuses the record (403 to a teacher, 404 to another family's parent)
- **Feature:** M11 Print routes `/app/certificates/<id>/print`, `/app/student-reports/<id>/print`. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-034); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher qa-teacher@ / parent qa-parent@ (`QA-People-2026!`).
- **Reproduction steps:**
  1. AR teacher: `/app/certificates/2/print`, wait 6 s.
  2. AR teacher: `/app/student-reports/1/print`.
  3. AR parent: `/app/certificates/3/print` (another family's child).
- **Expected:** A "ليست لديك صلاحية…" / "الشهادة غير موجودة" message with a way back.
- **Actual:** Only a spinner / "جارٍ التحميل" on a blank page; the query retries (3×403, 4×403, 3×404) and never shows an error.
- **Evidence:** `qa/manual/screens/M11/M11-F-034-wrong-role-url-silent-redirect-home.png`, `qa/manual/screens/M11/triage/t034b-teacher-cert-print-spinner.png`, `qa/manual/screens/M11/triage/t034c-teacher-report-print.png`, `qa/manual/screens/M11/triage/t034d-parent-cert3-print.png`
- **Notes:** Narrowed from M11-F-034. Not a bug: office URLs (`/app/people/student-reports`, `/app/catalogue/content`, …) send teachers/students/parents to `/app/` — documented in roles-permissions.md ("requireOffice … Teachers, students and parents are sent to /"); data is refused server-side. The one-off landing on the public `/ar/` (with a 504 on the Astro entrypoint) did not reproduce (3/3 to `/app/`) and matches a parallel server reload. Similar to ETQAN-QA-554 (course spinner) on a different screen.
- **Root cause:** The app's QueryClient (`main.tsx`) used TanStack's default of 3 retries with backoff for every error, so a 403/404 spun ~7 s per try before the error; the error text also had no way back and no 403 wording.
- **Fix (Agent 3, 2026-10-28, cycle 1):** New `lib/query-retry.ts` `retryUnlessRefused`: no retry on 4xx, up to 3 on network/5xx, set as the default in `main.tsx`. Certificate, subject certificate and report print pages show `certificates.print.forbidden` / `studentReports.forbidden` on 403, and a Back button (`PrintBackButton`) with the error.
- **Regression test:** `lib/query-retry.test.ts`; `CertificatePrint.test.tsx` "says a refused certificate is not theirs, with a way back (ETQAN-QA-677)"; `ReportPrint.test.tsx` "says a refused report is not theirs, with a way back (ETQAN-QA-677)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-677-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-678: Progress panel: an empty level opens to blank space with no "لا توجد موضوعات في هذا المستوى"
- **Feature:** M11 Progress panel (teacher, office drawer). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-035); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher qa-teacher@ / `QA-People-2026!`; "M11 المستوى الثاني" has no sub-levels/topics.
- **Reproduction steps:**
  1. AR teacher: `/app/teaching/levels` → فتح التقدّم on QA student · F03 قرآن → expand "M11 المستوى الثاني".
- **Expected:** An empty-state line inside the level.
- **Actual:** The card opens to an empty box; with M11-F-016 nobody can tell whether level 2 has nothing to do or failed to load.
- **Evidence:** `qa/manual/screens/M11/M11-F-035-empty-level-no-empty-state.png`, `qa/manual/screens/M11/triage/t013a-teacher-progress.png`
- **Root cause:** `ProgressPanel.tsx` rendered a level's sub-levels only; nothing for none.
- **Fix (Agent 3, 2026-10-28, cycle 1):** A level with no topics shows `curriculum.progress.noTopics` "لا موضوعات في هذا المستوى بعد.".
- **Regression test:** `ProgressPanel.test.tsx` "says when a level has no topics (ETQAN-QA-678)". Evidence: `qa/manual/evidence/M11/fix-1/`.
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28): re-walked in the browser; BEFORE/AFTER `qa/manual/screens/M11/fix/ETQAN-QA-678-after.png`; scoped Vitest pass (`qa/manual/evidence/M11/gate-1/`).

---

## ETQAN-QA-679: Teacher "تقييماتي": an average of 4.5 is drawn as five full stars
- **Feature:** M11 Teacher reviews (`reviews/MyReviews.tsx:57` `Math.round(average)`). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no (P4, small). **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-036); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** teacher qa-teacher@ / `QA-People-2026!`; reviews 5, 4, 5, 4.
- **Reproduction steps:**
  1. AR teacher: `/app/teaching/reviews`.
- **Expected:** 4½ stars (or 4 + half), matching the number.
- **Actual:** "متوسط التقييم 4.5 ★★★★★".
- **Evidence:** `qa/manual/screens/M11/M11-F-036-teacher-average-4-5-shows-5-stars.png`, `qa/manual/screens/M11/triage/t036-avg-4-5-five-stars.png`
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-680: Homework cards: the status chip moves under the title when the title wraps (else at the far end); English says "Completed" to students and "Complete" to teachers/office
- **Feature:** M11 Student/parent homework list (`homework/MyHomework.tsx:112-123`, `locales/en/homework.json` `completed` vs `status.complete`). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no (P4, small). **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M11 (M11-F-037); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** parent qa-parent@ / `QA-People-2026!`; student EN.
- **Reproduction steps:**
  1. AR parent: `/app/learning/homework` (first card has a long title).
  2. EN: compare student list chip with teacher `/app/teaching/homework`.
- **Expected:** Chip always in the same corner; one word for the same status.
- **Actual:** Wrapped card: chip at the bottom start under the date; others at the far end. Student chip uses `homework.completed` = "Completed"; teacher/office `homework.status.complete` = "Complete".
- **Evidence:** `qa/manual/screens/M11/M11-F-037-homework-card-badge-jumps-complete-vs-completed.png`, `qa/manual/screens/M11/triage/t037a-parent-hw-cards.png`
- **Notes:** EN student session could not be re-created (login stayed on /login once); wording confirmed in code.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-681: Issue certificate dialog: Student and Course selects are blank boxes with no "اختر…" text (the ETQAN-QA-653 fix covered only the homework dialog)
- **Feature:** M11 Certificates, issue dialog (`certificates/IssueCertificateDialog.tsx`). **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL
- **Found by:** Agent 1, M11 confirmation sweep (M11-F-038); reproduced by Agent 2 on 2026-10-28 (final gate).
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/people/certificates` → إصدار شهادة → look at الطالب * / الدورة *.
- **Expected:** As in the new-homework dialog after ETQAN-QA-653: "اختر طالبًا" and "اختر دورة" (or "اختر الطالب أولًا") in the empty selects.
- **Actual:** Both required selects are empty white boxes; the first option of each is an empty string (student select 21 options, course select 10).
- **Evidence:** `qa/manual/screens/M11/M11-F-038-cert-dialog-student-course-blank.png`, `qa/manual/screens/M11/triage/t038-cert-issue-blank-selects.png`
- **Notes:** Reuse the `homework.dialog.pickStudent` / `pickCourse` pattern (certificates locale keys). Agent 1 also saw the Course select list every course in the academy, not only the student's; not filed as a bug (the office may issue a certificate for any course; the backend refuses a non-granting course with ETQAN-QA-665's message).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-682: Certificate detail dialog footer wraps to two rows: the main green "حفظ" drops alone under "إغلاق / إبطال الشهادة / حذف الشهادة"
- **Feature:** M11 Certificates, detail dialog (`certificates/CertificateDialog.tsx` footer). **Severity:** P4. **Type:** UI-layout. **Easy P3:** no (P4, small). **Priority:** low
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL
- **Found by:** Agent 1, M11 confirmation sweep (M11-F-039); reproduced by Agent 2 on 2026-10-28 (final gate).
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/people/certificates` → فتح on the "عمر الشريف" row → look at the footer.
- **Expected:** One row of actions, primary "حفظ" with the others; destructive actions set apart.
- **Actual:** Button tops: "حذف الشهادة"/"إبطال الشهادة"/"إغلاق" at y=666, "حفظ" alone at y=718.
- **Evidence:** `qa/manual/screens/M11/M11-F-039-cert-dialog-footer-two-rows.png`, `qa/manual/screens/M11/triage/t039-cert-detail-footer.png`
- **Notes:** Same shape as ETQAN-QA-652 (homework dialog footer); the two can share one footer layout fix.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-683: Certificates (AR): "Arabic (English)" student names wrap with the bracket and hyphen on the wrong side on the print page, the public verification page and the office list
- **Feature:** M11 Certificates (`certificates/CertificatePrint.tsx`, `VerifyCertificate.tsx`, `CertificatesList.tsx`). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`. **Tag:** REAL
- **Found by:** Agent 1, M11 confirmation sweep (M11-F-040); reproduced by Agent 2 on 2026-10-28 (final gate).
- **Preconditions:** certificate 4 (تقدير, "عمر الشريف (Omar Al-Sharif)", verify code `8JgMwHKuS4eLH7XKMDrMtg`).
- **Reproduction steps:**
  1. Anonymous, AR, 1440x900: `/app/verify/8JgMwHKuS4eLH7XKMDrMtg`.
  2. Admin, AR, 375x812: `/app/certificates/4/print`.
  3. Admin, AR, 375x812: `/app/people/certificates`.
- **Expected:** As after ETQAN-QA-209: "عمر الشريف (Omar Al-" / "Sharif)", the "(Latin)" part whole and in order.
- **Actual:** (1) "عمر الشريف (-Omar Al" / "(Sharif"; (2) "Omar Al-) عمر الشريف" / "(Sharif" in the big name line of the certificate; (3) "(Omar" / "Al-Sharif)" and "(Adam" / "Al-Najjar)" in the Student column. The certificate is what families print and share, and the verify page is public.
- **Evidence:** `qa/manual/screens/M11/M11-F-040-verify-page-name-brackets-flip.png`, `qa/manual/screens/M11/M11-F-040-cert-print-name-brackets-flip-mobile.png`, `qa/manual/screens/M11/M11-F-040-admin-cert-list-mobile-brackets.png`, `qa/manual/screens/M11/triage/t040a-verify-name-brackets.png`, `qa/manual/screens/M11/triage/t040b-print-name-brackets-m.png`, `qa/manual/screens/M11/triage/t040c-admin-list-m.png`
- **Notes:** Same class as ETQAN-QA-209/216/218 (fixed with `scheduling/bits.PersonName`); the certificate surfaces don't use it. Also check `MyCertificates.tsx`, `SubjectCertificatePrint.tsx` and `CertificateDialog.tsx` subtitle. EN verify reads correctly.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-684: Arabic UI: a title that starts with Latin text (file name "M11-photo.png") is pushed to the far left of its card, away from its checkbox and meta line (side effect of the ETQAN-QA-651/672 `dir="auto"` fix)
- **Feature:** M11 Library list (`library/LibraryList.tsx:166`) and student homework cards (`homework/MyHomework.tsx:104`). **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard main checkout with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900. **Tag:** REAL
- **Found by:** Agent 1, M11 confirmation sweep (M11-F-041); reproduced by Agent 2 on 2026-10-28 (final gate).
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`.
- **Reproduction steps:**
  1. AR: `/app/library` → رفع ملف → pick `M11-photo.png` (the name field defaults to the file name) → رفع ملف.
  2. Look at the new card.
- **Expected:** The title at the start (right) of the card above its meta line, next to its checkbox; only the text itself reads LTR.
- **Actual:** The title `<span dir="auto" class="truncate …">` is a block spanning x=282–1099 with computed `direction: ltr`, so its text sits at the far left next to "نسخ الرابط / فتح / حذف", while the checkbox and "PNG · 592 بايت · QA Admin · 2026/10/28" stay at the right. A Latin-led name is the usual case because the name defaults to the file name. Same on the student homework cards with a Latin-led title.
- **Evidence:** `qa/manual/screens/M11/M11-F-041-library-latin-title-jumps-to-far-side.png`, `qa/manual/screens/M11/triage/t041-library-latin-title-far-side.png`
- **Notes:** `dir="auto"` on a block-level (`truncate`/`block`) element also flips its alignment. Keep the alignment of the page direction (e.g. put `dir="auto"` on an inline `<bdi>` inside the block, or add `text-align: right` under `[dir=rtl]`). Test file deleted again after the repro.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## --- M13 manual bugs ---

## ETQAN-QA-700: Academy primary colour never reaches the public site: the tokens stylesheet, loaded after the academy's inline colour, sets `--primary` back to #146B50
- **Feature:** M13 Website admin. **Severity:** P2. **Type:** functional. **Easy P3:** no. **Priority:** high
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-002); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: `/app/website/branding`, set اللون الأساسي to `#7A1F5C`, click "حفظ التغييرات" (toast "تم الحفظ.").
  2. Wait 60 s, open `http://qa.etqan.localhost/ar/` and reload.
  3. In devtools: `getComputedStyle(document.documentElement).getPropertyValue('--primary')`.
- **Expected:** The header button, hero, "إرسال" etc. use the academy colour (setup guide step 1: "الشعار ولونا الهوية يلوّنان الموقع كله").
- **Actual:** The site stays green. The page contains the academy's inline `:root{--primary:#0E7C66}` (or the new colour), but `global.css` (which imports `@etqan/tokens/theme.css`) is applied after it and sets `:root{--primary: #146B50}` (and `#4FA082`), so computed `--primary` is always `#146B50` — even the default academy colour #0E7C66 is not the one shown. Tagline saved at the same time does show, so the save reaches the site.
- **Evidence:** `qa/manual/screens/M13/M13-F-002-primary-colour-not-applied.png`, `qa/manual/screens/M13/triage/t001-002-public-footer-primary.png`
- **Notes:** `marketing/src/layouts/Layout.astro:76,101` writes `brandCss` in a `<style>` in `<head>`; `marketing/src/styles/global.css:2-3` imports the tokens theme, which defines `--primary` on `:root` with the same specificity and comes later. Fix idea: raise the brand rule's precedence (e.g. `html:root{…}` or put the brand `<style>` after the stylesheet) — check `ClosedPage.astro:36` too. Every academy's branding colour is affected.
- **Root cause:** `marketing/src/layouts/Layout.astro` and `components/ClosedPage.astro` wrote the brand colours as `:root{--primary:…}`; the bundled `global.css` (tokens `theme.css`) sets the same `:root` vars with equal specificity and is emitted after the inline `<style>`, so it always won.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** The brand rule is now `html:root{…}` (specificity 0,1,1) in both templates, so it outranks the tokens' `:root` whatever the stylesheet order.
- **Regression test:** `marketing/test/layout.test.ts` (renders `html:root{--primary:`), `marketing/test/closed.test.ts` ("ETQAN-QA-700"). Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — computed --primary #7A1F5C on /ar/ and /en/ after saving the colour; restored #0E7C66. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-700-after.png` (before | after).

---

## ETQAN-QA-701: Branding colours are plain hex text boxes: no swatch of the current colour and no colour picker
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-003); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: open `/app/website/branding`; look at اللون الأساسي / اللون الثانوي.
- **Expected:** Each colour field shows a swatch of the current colour and offers a picker (an owner doesn't know hex codes).
- **Actual:** Two text inputs "#0E7C66" and "#C8962E"; nothing shows what colour that is.
- **Evidence:** `qa/manual/screens/M13/M13-F-003-colour-fields-no-swatch.png`, `qa/manual/screens/M13/triage/t000-login-branding.png`
- **Notes:** Mentioned as a note in ETQAN-QA-500 but never filed. A native `<input type="color">` beside the text box (kept in sync) is enough.
- **Root cause:** `BrandingForm.tsx` rendered both colours as plain text `Input`s.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** New `ColourField` in `BrandingForm.tsx`: the hex text box plus a native `<input type=color>` swatch/picker (aria-label `website.branding.pickColour`), both bound to the same form value via `useController`.
- **Regression test:** `BrandingForm.test.tsx` "offers a colour picker kept in sync with the hex box (ETQAN-QA-701)". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — swatch + picker beside each hex box, picker follows typed hex (#7a1f5c). Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-701-after.png` (before | after).

---

## ETQAN-QA-702: Website forms still show raw English zod / hard-coded English validation text in Arabic: tagline length, FAQ answer "Required", testimonial quote/stars, article publish date, category slug rule
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-004 (also F-011 rule text, F-016 message, F-021, gate G-001)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR `/app/website/branding`: type 250 characters in الشعار النصي (العربية), click "حفظ التغييرات".
  2. AR `/app/website/faqs`: fill both questions, leave answers empty, "إضافة سؤال".
  3. AR `/app/website/testimonials`: name only, النجوم `7`, "إضافة شهادة".
  4. AR `/app/website/articles` → مقال جديد: fill everything, tick منشور, leave تاريخ النشر empty, "حفظ المقال".
  5. AR `/app/website/articles/categories`: الرابط/العنوان = `M13 تجويد`, "إضافة فئة".
- **Expected:** Short Arabic messages ("الحد الأقصى 200 حرف", "هذا الحقل مطلوب.", "من 1 إلى 5 نجوم", "أحرف إنجليزية صغيرة وأرقام وشرطات فقط").
- **Actual:** (1) "Too big: expected string to have <=200 characters"; (2) "Required" under both answers; (3) "Too small: expected string to have >=1 characters" under both quotes and "Too big: expected number to be <=5"; (4) "Too small: expected string to have >=1 characters" under تاريخ النشر and "Required" under both article bodies; (5) "a-z, 0-9 and - only (max 60)". All English on the Arabic screen.
- **Evidence:** `qa/manual/screens/M13/M13-F-004-tagline-too-long-english.png`, `qa/manual/screens/M13/M13-F-016-faq-required-english.png`, `qa/manual/screens/M13/M13-F-021-stars-raw-english.png`, `qa/manual/screens/M13/M13-F-021-quote-raw-english.png`, `qa/manual/screens/M13/M13-F-011-category-slug-label.png`, `qa/manual/screens/M13/triage/t004-005-branding-errors.png`, `qa/manual/screens/M13/triage/t016-faq-required.png`, `qa/manual/screens/M13/triage/t021-022-testimonial-errors.png`, `qa/manual/screens/M13/triage/g001-article-date-raw-zod.png` (article: date "Too small…", body "Required"), `qa/manual/screens/M13/triage/t011-category-slug-label.png`
- **Notes:** Residue of ETQAN-QA-048 / ETQAN-QA-500: QA-500's fix covered only colour/required/url/email in `brandingSchema`; the tagline `.max(200)`, FAQ, testimonial, article and category schemas in `dashboard/src/features/website/schemas.ts` (and the forms rendering `error.message`) still have no i18n keys. Same `useFieldError()` convention.
- **Root cause:** `schemas.ts` used bare `.min(1)` / `.max(n)` / `"Required"` / English slug sentences, and most website forms rendered `error.message` raw instead of through `useFieldError`.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Every website schema message is now an i18n key (`website.errors.required|notNegative|stars|slug|max.<n>`, ar/en/es); all website forms (FAQs, ads, categories, articles, pages, videos, testimonials, slides, home, redirects, settings, branding files, blocks) render field/root errors through `useFieldError`.
- **Regression test:** `dashboard/src/features/website/websiteCopy.test.ts` (schemas give keys with Arabic text), `FaqsManager.test.tsx` "words empty answers in Arabic", `BrandingForm.test.tsx` "words a too-long tagline in Arabic". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — tagline 'الحد الأقصى 200 حرف'; FAQ/article body/publish date 'هذا الحقل مطلوب.'; stars 'اختر من 1 إلى 5 نجوم'; category slug rule in Arabic. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-702-after.png` (before | after).

---

## ETQAN-QA-703: Raw English server sentences in Arabic website screens: WhatsApp "Use E.164 format…", slide button "Fill in both labels…", page blocks "This field is required.", redirects, video file / YouTube
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-005 (also F-006, F-009, F-015, F-019)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR `/app/website/branding`: رقم واتساب `abc123`, "حفظ التغييرات" → 400.
  2. AR `/app/website/home` → شرائح الغلاف: image + titles, الزر "تواصل معنا", empty نص الزر, "أضف الشريحة" → 400.
  3. AR `/app/website/pages/new`: slug + titles, منشئ الصفحات, "إضافة عنوان" + "إضافة زر" empty, "حفظ التغييرات" → 400.
  4. AR `/app/website/redirects`: من المسار `old page`, التحويل إلى `javascript:alert(1)`, "إضافة تحويل" → 400.
  5. AR `/app/website/videos` → فيديو جديد: a text file named `fake.mp4` + cover, "حفظ الفيديو" → 400 (also رابط يوتيوب `https://vimeo.com/123`).
- **Expected:** Arabic messages ("أدخل الرقم بصيغة دولية مثل ‎+966501234567", "املأ نص الزر بالعربية والإنجليزية", "هذا الحقل مطلوب.", "ابدأ المسار بـ / ", "الملف ليس فيديو MP4 صالحًا"), ideally checked before sending, and the view on the first error.
- **Actual:** English with the full stop mirrored: ".Use E.164 format, e.g. +966501234567", ".Fill in both labels and where the button goes", "العنوان (العربية): This field is required." (page left scrolled at the bottom, no toast), ".Enter a path that starts with / (no ? or #)", ".Enter a path or an http(s) address", ".The file's content does not match its type", "Paste a YouTube link or video id.".
- **Evidence:** `qa/manual/screens/M13/M13-F-005-whatsapp-error-english.png`, `qa/manual/screens/M13/M13-F-006-slide-button-error-english.png`, `qa/manual/screens/M13/M13-F-009-block-errors-english.png`, `qa/manual/screens/M13/M13-F-015-redirect-errors-english.png`, `qa/manual/screens/M13/M13-F-019-video-file-error-english.png`, `qa/manual/screens/M13/M13-F-019-youtube-error-english.png`, `qa/manual/screens/M13/triage/t005-whatsapp-error.png`, `qa/manual/screens/M13/triage/t006-slide-button-error.png`, `qa/manual/screens/M13/triage/t009-block-errors.png`, `qa/manual/screens/M13/triage/t015-redirect-errors.png`, `qa/manual/screens/M13/triage/t019-video-file-error.png`
- **Notes:** Same family as ETQAN-QA-206/358/561 (server sentence → `serverMessageKey` mapping). Not a re-file: different forms. The javascript: target being refused is correct.
- **Root cause:** The backend's fixed English sentences (`admin_serializers.py`, `redirects.py`, `blocks.py`, `youtube.py`, `platform/uploads.py`, DRF "This field is required.") had no entry in `lib/server-messages.ts`, and block/list/root errors were printed raw.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Added the sentences to `SERVER_MESSAGES` → `website.serverErrors.*` / `errors.server.required|fileContentMismatch|invalidImage` (ar/en/es); block and list errors go through `useFieldError`; a refused page-builder save now shows a toast (`website.blocks.errorsToast`).
- **Regression test:** `dashboard/src/features/website/websiteCopy.test.ts` "ETQAN-QA-703" (each sentence maps to a key in ar/en/es with Arabic text). Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — WhatsApp, slide button, page blocks (+ toast 'لم يتم الحفظ'), redirects, video file content and YouTube link all Arabic. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-703-after.png` (before | after).

---

## ETQAN-QA-704: Pages list shows the address as "m13-about/" (mirrored) and not the real public path `/p/<slug>`
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** RTL. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-010); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: create a page slug `m13t2-page` (published) → `/app/website/pages`.
  2. Open `/ar/m13t2-page` (what the list suggests) and `/ar/p/m13t2-page`.
- **Expected:** The list shows the real address, left-to-right ("/p/m13t2-page"), ideally as a link.
- **Actual:** Under the title "m13t2-page/"; `/ar/m13t2-page` → 404, the real page is `/ar/p/m13t2-page` (200).
- **Evidence:** `qa/manual/screens/M13/M13-F-010-page-path-wrong.png`, `qa/manual/screens/M13/triage/t010-pages-list.png`
- **Notes:** `dashboard/src/features/website/PagesList.tsx`: render `/p/${slug}` in a `dir="ltr"`/`<bdi>` span (or a link to the public page).
- **Root cause:** `PagesList.tsx` printed `/{slug}` as plain text in an RTL row (mirrored, and not the real `/p/<slug>` path).
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Shows `/p/<slug>` in a `<bdi dir="ltr">` (`Ltr` in new `ListRow.tsx`).
- **Regression test:** `PagesList.test.tsx` "shows the real public path, left to right (ETQAN-QA-704)". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — list shows /p/m13g-page LTR (AR+EN); /ar/p/m13g-page 200. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-704-after.png` (before | after).

---

## ETQAN-QA-705: Website forms name the URL part differently on each form ("المعرّف (slug)", "العنوان", "العنوان (الرابط)") — "العنوان" is also the title — and several required fields have no *
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-011 (also F-014 wording, F-016 missing *, F-020)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: compare the slug field on `/app/website/pages/new`, articles → مقال جديد, `/articles/categories`, videos → فيديو جديد.
  2. Videos: save without a cover; FAQs: save without answers.
- **Expected:** One clear name for the URL part on every form (e.g. "رابط الصفحة (slug)" with a hint), and a red * on every required field.
- **Actual:** Pages: "المعرّف (slug)"; articles and categories: "العنوان" (next to "العنوان الرئيسي" = title; the slug-change box says "تغيير العنوان يكسر الروابط"); videos: "العنوان (الرابط)". SEO is "عنوان SEO" on articles but "عنوان السيو" on videos. Video "صورة الغلاف" and "ملف الفيديو (MP4)" and FAQ answers carry no * but saving says "اختر صورة الغلاف." / "Required".
- **Evidence:** `qa/manual/screens/M13/M13-F-011-category-slug-label.png`, `qa/manual/screens/M13/M13-F-014-slug-change-hint.png`, `qa/manual/screens/M13/M13-F-020-video-cover-required-no-star.png`, `qa/manual/screens/M13/triage/t011-category-slug-label.png`, `qa/manual/screens/M13/triage/t014-slug-hint.png`, `qa/manual/screens/M13/triage/t019-video-file-error.png`, `qa/manual/screens/M13/triage/t016-faq-required.png`
- **Notes:** Locale strings in `dashboard/src/locales/ar/website.json` (+ en/es) and the `required` prop on the label components.
- **Root cause:** Each form had its own slug label key (`pages.slug`, `articles.slug`, `videos.slug`) and video SEO used different words; rich-text answers/bodies and video files drew labels without the required mark.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** One key `website.slug.label` ("رابط الصفحة (slug)") on pages, articles, categories and videos; slug-change hint reworded; video SEO = "عنوان SEO"/"وصف SEO"; `RequiredMark` on FAQ answers, article/page bodies; `required` on video file (when needed), cover (new) and YouTube link.
- **Regression test:** `websiteCopy.test.ts` "ETQAN-QA-705"; label lookups updated in Articles/Categories/Pages/Videos tests. Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — 'رابط الصفحة (slug)' on pages/articles/categories/videos; new hint wording; * on FAQ answers, bodies, video file/cover; 'عنوان SEO' on videos. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-705-after.png` (before | after).

---

## ETQAN-QA-706: Website lists in Arabic lead with the English text: FAQ question, ad title, category name, testimonial quote (and their delete dialogs); mixed text is mirrored ("?M13T2 Is the trial free")
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** translation. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-012 (also F-017, F-018 list part, F-022 list part)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: add a category, a FAQ, an ad and a text testimonial (Arabic + English text); look at each list under the form.
  2. EN: the same FAQ list.
- **Expected:** In Arabic the Arabic text leads (as Pages/Videos/Slides already do); Latin text keeps its own direction; the kind/stars are shown.
- **Actual:** Bold "M13T2 Tajweed" with "M13T2 تجويد" grey under it and "m13t2-tajweed/"; FAQ "?M13T2 Is the trial free"; ad "M13T2 20% off" only (no kind); testimonial "Great teachers." in English, no kind/stars. EN UI: Arabic sub-line mirrored "؟هل … M13". Delete dialogs also use `_en`.
- **Evidence:** `qa/manual/screens/M13/M13-F-012-category-english-first.png`, `qa/manual/screens/M13/M13-F-017-faq-list-english-first.png`, `qa/manual/screens/M13/M13-F-017-faq-list-en-arabic-mirrored.png`, `qa/manual/screens/M13/M13-F-018-ad-list-english-title.png`, `qa/manual/screens/M13/M13-F-022-testimonials-named-certificates.png`, `qa/manual/screens/M13/triage/t012-category-list.png`, `qa/manual/screens/M13/triage/t017-faq-list.png`, `qa/manual/screens/M13/triage/t018-ad-past-date.png`, `qa/manual/screens/M13/triage/t022-testimonial-list.png`
- **Notes:** Hard-coded `_en`: `FaqsManager.tsx:69,276`, `AdsManager.tsx:68,275`, `ArticleCategoriesManager.tsx:80,280`, `TestimonialsManager.tsx:427`. Use `isAr ? x_ar : x_en` like `PagesList.tsx:102`, plus `dir="auto"` on the text spans.
- **Root cause:** FAQ, ad, category lists and their delete dialogs hard-coded `_en`; testimonial list showed `quote_en` only, no kind/stars; sub-lines forced `dir="rtl"`.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** New `useBilingual()` (`ListRow.tsx`): rows and delete dialogs lead with the reader's language, the other language as `dir="auto"` sub-line; ads show kind + date; testimonials show kind, stars and the reader's-language quote.
- **Regression test:** `FaqsManager.test.tsx` "leads the list and the delete dialog with the Arabic question", `AdsManager.test.tsx` "leads with the Arabic title…". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — FAQ, category, ad (kind + LTR date), testimonial (kind, stars, Arabic quote) lead with Arabic; delete dialog Arabic; EN leads with English. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-706-after.png` (before | after).

---

## ETQAN-QA-707: An ad can be saved with an expiry date already in the past: it is born "منتهي" and never shows, with the normal "تم الحفظ" toast
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-018); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR `/app/website/ads`: النوع خصم, titles/bodies, banner, تاريخ الانتهاء `2026-10-01` (today 2026-10-28), "إضافة إعلان".
- **Expected:** The date picker starts at today (min) or the form warns that the ad will never show.
- **Actual:** Saved with "تم الحفظ. يعرض الموقع العام تغييراتك خلال دقيقة تقريبًا."; the row reads 2026-10-01 · "منتهي".
- **Evidence:** `qa/manual/screens/M13/M13-F-018-ad-list-english-title.png`, `qa/manual/screens/M13/triage/t018-ad-past-date.png`
- **Notes:** `website-content.md`: an ad is active while `expires_on >= academy_today()`; saving a past date is never useful. `min` on `#expires_on` and a schema check in `AdsManager`.
- **Root cause:** `AdsManager` accepted any `expires_on`.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `min=today` on the date input and a check in `onSubmit` (when the date is new/changed) with `website.ads.errors.pastDate`; the server stays the authority.
- **Regression test:** `AdsManager.test.tsx` "refuses an expiry date before today (ETQAN-QA-707)". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — min=2026-10-28 on the date input; 2026-10-01 refused with Arabic message; 2026-12-31 saved 'ساري'. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-707-after.png` (before | after).

---

## ETQAN-QA-708: After saving a new article the screen is left blank: the form closes but the window keeps its scroll position far below the short list
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-013); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR `/app/website/articles` → مقال جديد, fill all fields incl. تاريخ النشر, scroll down, "حفظ المقال".
- **Expected:** Back at the top of the list, with the new article visible.
- **Actual:** Only the empty page background and the sidebar, plus the toast; scrollY 1340 of a page that is now short.
- **Evidence:** `qa/manual/screens/M13/M13-F-013-article-save-blank-view.png`, `qa/manual/screens/M13/triage/t013-article-save-blank.png`
- **Notes:** `ArticlesManager.tsx`: `window.scrollTo({top:0})` when the editor closes (same for VideosManager).
- **Root cause:** `ArticlesManager`/`VideosManager` swap the long editor for the list in place; the window kept its scroll offset.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Their `setEditing` now also calls `window.scrollTo({ top: 0 })`.
- **Regression test:** `ArticlesManager.test.tsx` "scrolls to the top when the editor closes (ETQAN-QA-708)". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — scrollY 2690 before save → 0 after; list visible. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-708-after.png` (before | after).

---

## ETQAN-QA-709: Article slug-change warning gives no old address and no way to add the redirect it asks for
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-014); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR `/app/website/articles` → تعديل → change the slug to `m13t2-first-article-v2`.
- **Expected:** The warning shows the old public address and offers "إضافة تحويل" (or a link to تحويل الروابط pre-filled old → new), or adds the redirect on save.
- **Actual:** Box "تغيير العنوان يكسر الروابط القديمة — أضف تحويلاً من العنوان القديم." with no link; the owner must remember the old slug and know the public path format `/ar/articles/<slug>` to add it by hand.
- **Evidence:** `qa/manual/screens/M13/M13-F-014-slug-change-hint.png`, `qa/manual/screens/M13/triage/t014-slug-hint.png`
- **Notes:** Wording of the same box is part of ETQAN-QA-705. Pre-filling the redirects form needs route state; not a pure copy change.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-710: Testimonials are called "الشهادات" (tab, form, home toggle) — the same word the sidebar uses for certificates
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-022); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR: open `/app/website/testimonials`; compare with the sidebar "الأشخاص → الشهادات" (certificates) and the page builder button "إضافة آراء العملاء".
- **Expected:** One clear word for testimonials, e.g. "آراء الطلاب" (setup guide step 6) / "آراء العملاء" (builder).
- **Actual:** Tab "الشهادات", fields "اسم صاحب الشهادة" / "نص الشهادة", button "إضافة شهادة", home switch "إظهار الشهادات" — reads as certificates.
- **Evidence:** `qa/manual/screens/M13/M13-F-022-testimonials-named-certificates.png`, `qa/manual/screens/M13/triage/t021-022-testimonial-errors.png`
- **Notes:** Locale strings only (`locales/ar/website.json`).
- **Root cause:** Arabic locale strings for testimonials used "الشهادة/الشهادات".
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** `locales/ar/website.json`: tab, home switch, form labels, buttons, empty state and delete dialog say "آراء الطلاب" / "الرأي" (setup guide wording).
- **Regression test:** `websiteCopy.test.ts` "ETQAN-QA-710". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — tab 'آراء الطلاب', form 'اسم صاحب الرأي'/'نص الرأي', 'إضافة رأي', home switch 'إظهار آراء الطلاب' (page-builder button still says 'إضافة آراء العملاء' — acceptable, no longer 'الشهادات'). Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-710-after.png` (before | after).

---

## ETQAN-QA-711: Inquiries inbox: email and phone are plain text, not mailto:/tel: links
- **Feature:** M13 Website admin. **Severity:** P4. **Type:** UI-layout. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-023 (remaining part; date/WhatsApp/mirroring = ETQAN-QA-766)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR `/app/website/inquiries`; `document.querySelectorAll('a[href^=mailto],a[href^=tel]').length`.
- **Expected:** Email opens the mail app, phone dials (the WhatsApp mark is already a link).
- **Actual:** 0 mailto/tel links; on a phone the owner must copy the number by hand.
- **Evidence:** `qa/manual/screens/M13/M13-F-023-inquiries-no-date.png`, `qa/manual/screens/M13/triage/t023-inquiries.png`
- **Notes:** The date, WhatsApp mark and Latin direction parts of M13-F-023 are ETQAN-QA-766 (already rendering in the working tree at triage).
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-712: "وضع علامة كمُعالج" acts on one click with no toast and no way back; the handled view doesn't show who handled it or when
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** functional. **Easy P3:** no. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-024); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. Send a contact inquiry from `/ar/`.
  2. AR `/app/website/inquiries` → "وضع علامة كمُعالج" on it.
  3. Filter → "تمت معالجته".
- **Expected:** A toast (ideally with تراجع), a way to re-open a handled inquiry, and who/when on handled rows.
- **Actual:** The row silently disappears (المجموع 5 → 4), no toast; in the handled list only a grey "تمت معالجته" chip. The API already returns `handled_by_email` (qa-admin@…) but the card doesn't show it; there is no re-open endpoint (`POST …/handle/` only).
- **Evidence:** `qa/manual/screens/M13/M13-F-024-inquiry-handled-no-undo.png`, `qa/manual/screens/M13/triage/t024a-handled-click.png`, `qa/manual/screens/M13/triage/t024-handled-view.png`
- **Notes:** Toast + showing `handled_by_email` are small dashboard changes; re-open/undo needs an API action (proposal) — hence not easy as a whole. `handled_at` isn't stored.
- **Root cause / Fix / Regression tests:** _Agent 3_
- **Verification status:** OPEN

---

## ETQAN-QA-713: Tracking ids: the error says "استخدم الصيغة الموضحة أسفل الحقل" but no format is under the field; the four formats sit in one list at the bottom of the card
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-025); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR `/app/website/settings` → التحليلات والإعلانات: GA4 `UA-123`, Meta Pixel `abc`, AdSense `pub-1` → حفظ.
- **Expected:** Each field shows its format right under it, or the message states it ("يبدأ بـ G-").
- **Actual:** Under each field "استخدم الصيغة الموضحة أسفل الحقل." while under it is the next field; formats ("G-XXXXXXX", "أرقام فقط", "ca-pub-0000000000", …) listed together below the last row. Nothing saved (correct).
- **Evidence:** `qa/manual/screens/M13/M13-F-025-tracking-format-hint-far.png`, `qa/manual/screens/M13/triage/t025-tracking-hint.png`
- **Notes:** `SiteSettingsForm.tsx`: move each hint into the field's description.
- **Root cause:** `SiteSettingsForm` listed all four formats in one list under the last row while the error said "below the field".
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Each tracking field now has its own hint paragraph right under it (`aria-describedby`), and the error repeats it: "القيمة غير صحيحة. {{hint}}".
- **Regression test:** `SiteSettingsForm.test.tsx` "puts each tracking format right under its field (ETQAN-QA-713)" + updated "rejects a malformed GA4 ID". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — each field has its own 'الصيغة: …' line and the error repeats it. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-713-after.png` (before | after).

---

## ETQAN-QA-714: Closed-site pages give visitors no way to reach the academy, call a system-only site "منطقة محظورة" (forbidden zone), and the editor closes the whole site on one click with no confirmation
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** copy. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-026 (name twice = ETQAN-QA-776)); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR `/app/website/settings` → حالة الموقع "تحت الصيانة" → حفظ; wait 60 s; open `/ar/` (503).
  2. Same with "النظام فقط" (403). Restore "يعمل".
- **Expected:** The closed page shows the academy's contact (WhatsApp/phone/email are set) and neutral wording (e.g. "الموقع غير متاح حاليًا"); switching to maintenance/system-only asks for confirmation.
- **Actual:** Bare page with Arabic and English blocks stacked; no contact even when set; system-only title "منطقة محظورة" / "Restricted area" + sign-in button. Saving the status takes effect for all visitors with no confirm.
- **Evidence:** `qa/manual/screens/M13/M13-F-026-maintenance-page.png`, `qa/manual/screens/M13/M13-F-026-system-only-page.png`
- **Notes:** Confirmed in code at triage (site not closed again, to spare the parallel areas): `marketing/src/components/ClosedPage.astro:45-56` renders only logo/name/title/body; `marketing/src/lib/i18n.ts:58` `restrictedTitle: "منطقة محظورة"`; `SiteSettingsForm.tsx:135-143` saves the status straight away. Name twice: ETQAN-QA-776.
- **Root cause:** `ClosedPage.astro` rendered only logo/name/title/body; `i18n.ts` `restrictedTitle` "منطقة محظورة"; `StatusCard` saved straight away.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Closed page lists the academy's email/phone/WhatsApp (safe links, same as Footer); system-only title "الموقع غير متاح حاليًا" / "This site is not available right now"; choosing maintenance/system-only now opens a confirm dialog before saving.
- **Regression test:** `marketing/test/closed.test.ts` "ETQAN-QA-714: … contact links" + restricted title; `SiteSettingsForm.test.tsx` "asks before closing the site…". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — confirm dialog before maintenance (cancelled on qa); closed page checked on qaother (site_status switched on briefly, then restored): title 'الموقع غير متاح حاليًا', mailto + wa.me links. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-714-after.png` (before | after).

---

## ETQAN-QA-715: Phone: the inquiries inbox is 656 px wide and opens scrolled sideways onto a blank area when an inquiry has a long unbroken name
- **Feature:** M13 Website admin. **Severity:** P2. **Type:** mobile. **Easy P3:** no. **Priority:** high
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-027); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. An inquiry exists with a long unbroken name ("M16 dbl IIII…", sent from the public form — any visitor can do this).
  2. AR 375x812: open `/app/website/inquiries`; `document.documentElement.scrollWidth`.
- **Expected:** Long names/emails/messages wrap or are cut with "…"; the page stays 375 px wide.
- **Actual:** scrollWidth 656, scrollX −280: only the edge of cards and a cut "ضع علامة كمُعالج" button are visible, the rest blank. One visitor's input breaks the owner's inbox on every phone.
- **Evidence:** `qa/manual/screens/M13/M13-F-027-inquiries-phone-overflow.png`, `qa/manual/screens/M13/triage/t027-inquiries-phone.png`
- **Notes:** `InquiriesList.tsx`: `min-w-0` on the card text column and `break-words`/`[overflow-wrap:anywhere]` on name, email and message. Same pattern as ETQAN-QA-758 (P2).
- **Root cause:** `InquiriesList` row: text column without `min-w-0` and no wrapping on name/email/message, so one unbroken string widened the page.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Row uses the shared `ROW`/`ROW_TEXT`/`ROW_ACTIONS` (stack on phone, `min-w-0`), and name, email, phone and message get `[overflow-wrap:anywhere]`.
- **Regression test:** `InquiriesList.test.tsx` "wraps a long unbroken name, email and message (ETQAN-QA-715)". Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — phone 375x812 inbox scrollWidth 375 with the long 'M16 dbl IIII…' name wrapped. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-715-after.png` (before | after).

---

## ETQAN-QA-716: Phone: hero slide titles run into the "تعديل" button in the slide list
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-028); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. Add a slide titled "M13T2 شريحة اختبار طويلة العنوان".
  2. AR 375x812: `/app/website/home`, scroll to the slide list.
- **Expected:** Title on its own line or truncated; buttons don't overlap text.
- **Actual:** The title prints over the "تعديل" button and past the card edge.
- **Evidence:** `qa/manual/screens/M13/M13-F-028-slide-title-overlaps-edit-phone.png`, `qa/manual/screens/M13/triage/t028-slide-title-phone.png`
- **Notes:** `HeroSlidesManager.tsx` row: `min-w-0` + wrap, buttons below the text on small screens.
- **Root cause:** `HeroSlidesManager` row kept text and buttons side by side; `truncate` on a shrink-to-content span inside `items-start` never truncated.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Row stacks on a phone (`ROW`), title wraps (`[overflow-wrap:anywhere]`, `dir=auto`).
- **Regression test:** New `dashboard/src/features/website/HeroSlidesManager.test.tsx`. Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — phone slide row: long title wraps, buttons below, no overlap. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-716-after.png` (before | after).

---

## ETQAN-QA-717: Phone: website list rows squeeze the text into a narrow column; slugs and dates break mid-word ("m13t2-first-/article", "2026-10-/01"); the article date reads "28-10-2026"; the 12 tabs take four rows
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** mobile. **Easy P3:** yes. **Priority:** low
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-029); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR 375x812: `/app/website/articles` and `/app/website/ads`, scroll to the list.
- **Expected:** Buttons move under the text on a phone; slug and date stay whole and left-to-right; tabs scroll in one row.
- **Actual:** Article title over 2 lines next to three buttons, "m13t2-first-/article · M13T2 تجويد · 28-10-2026"; ad "M13T2 / 20% off" and "2026-10- / 01". Tab bar ≈180 px on every website screen.
- **Evidence:** `qa/manual/screens/M13/M13-F-029-phone-article-row-squeezed.png`, `qa/manual/screens/M13/M13-F-029-phone-ad-date-broken.png`, `qa/manual/screens/M13/triage/t029-phone-article-row.png`, `qa/manual/screens/M13/triage/t029b-phone-ad-row.png`
- **Notes:** Row layout `flex-col sm:flex-row`; slug/date spans `dir="ltr"` + `whitespace-nowrap`; tabs `overflow-x-auto flex-nowrap`.
- **Root cause:** All website list rows were `flex items-center justify-between` with buttons beside the text; slug/date printed in RTL; tabs `flex-wrap`.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Shared row classes in `ListRow.tsx` used by pages, articles, ads, FAQs, categories, testimonials, videos, redirects, slides, inquiries; slugs/dates in `Ltr` (`<bdi dir=ltr>`, date nowrap); `routes/_authed/website.tsx` tabs one `overflow-x-auto` row on phones, wrapping from `sm`.
- **Regression test:** `routes/_authed/website.test.tsx` "keeps the tabs in one sideways-scrolling row on a phone (ETQAN-QA-717)"; row assertions in the 715/716 tests. Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — phone article row 'm13g-first-article · 2026-10-28' whole and LTR, buttons below; ad date LTR; tabs one sideways row; scrollWidth 375. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-717-after.png` (before | after).

---

## ETQAN-QA-718: Emptying the about text saves `<p></p>`, and the public home keeps an empty "من نحن" block that the owner cannot remove from the editor
- **Feature:** M13 Website admin. **Severity:** P3. **Type:** functional. **Easy P3:** yes. **Priority:** medium
- **Environment:** local docker stack (backend + dashboard + marketing with uncommitted qa/manual-2026-10 fixes), academy `qa`, Chromium via `qa/manual/tools/step.mjs`, 1440x900 unless noted. **Tag:** REAL
- **Found by:** Agent 1, manual M13 (M13-F-031); reproduced by Agent 2 on 2026-10-28.
- **Preconditions:** qa-admin@qa.etqan.test / `QA-Admin-2026!`, academy `qa`.
- **Reproduction steps:**
  1. AR `/app/website/home`: click into نبذة (العربية), type a letter, delete it (or select all + Backspace on existing text), "حفظ التغييرات".
  2. `GET /api/v1/site/admin/landing/` → `about_ar`.
  3. Wait 60 s, open `/ar/`.
- **Expected:** No text → no about block (as before any text was entered).
- **Actual:** `about_ar` = `"<p></p>"`; the home page shows the academy card and "من نحن / من نحن" with no text. Only a direct API save of `""` removes it (done to restore).
- **Evidence:** `qa/manual/screens/M13/M13-F-031-empty-about-still-shown.png`, `qa/manual/screens/M13/triage/t031a-about-cleared-saved.png`, `qa/manual/screens/M13/triage/t031-empty-about-public.png`, `qa/manual/screens/M13/triage/t031b-about-restored.png`
- **Notes:** Normalise empty rich text (`<p></p>`, `<p><br></p>`, whitespace) to "" — in `RichTextEditor` output or the backend sanitiser — so the marketing `about` check works. Also affects FAQ answers / page bodies.
- **Root cause:** `LandingContentSerializer.validate_about_*` only sanitised; an emptied TipTap editor sends `<p></p>`, stored as-is, so the marketing "about" check saw text.
- **Fix (Agent 3, cycle 1, branch qa/manual-2026-10, uncommitted):** Backend: blank sanitised HTML (`is_blank_html`) is stored as "" (`backend/etqan/site/api/admin_serializers.py`).
- **Regression test:** `backend/etqan/site/tests/test_admin_api.py::test_landing_blank_about_is_stored_empty` (4 blank shapes). Evidence: `qa/manual/evidence/M13/fix-1/` (dashboard-tsc/vitest/biome, backend-pytest/lint, marketing-vitest/biome).
- **Verification status:** VERIFIED (Agent 2 gate, 2026-10-28) — cleared نبذة in the editor and saved → about_ar '' in DB; public /ar/ has no 'من نحن'. Evidence: `qa/manual/screens/M13/fix/ETQAN-QA-718-after.png` (before | after).

---
