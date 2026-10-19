# F02: Sign-in and account security

Author: Agent 1 (research and test strategy), LEAN mode. This spec approves nothing.
Written 2026-10-18 from backend adff9c9 and dashboard 5ed775d.

Sources read: `docs/features/sign-in.md`; `backend/etqan/identity/{signin,limits,twofactor,impersonation,links,codereset,authentication}.py`,
`identity/api/{views,serializers,urls,people_urls,people_views}.py`, `identity/services.py` (password, email, `_end_sessions`, `sign_in_refusal`),
`platform/{permissions,throttling,sms,features}.py`, `config/settings/{base,production}.py`.
Existing tests (cited as "T:"): `identity/tests/test_{signin,login_2fa,login_csrf,limits,impersonation,quick_login_links,code_reset,password_management,email_management,twofactor_api,phone_login,google}.py`.
Those are unit/API tests on a fake clock and locmem mail. This spec adds what they can't show: the live stack (Caddy, Redis, Celery, mailpit, Postgres), two real academies, real sessions in `academy_qa.django_session`.

Counts: 30 cases. P1 25, P2 5. UI smoke: TC-001, TC-011, TC-015 (Playwright, `--workers=1`). Everything else is API-first.

## Setup

Academy `qa` (`qa.etqan.localhost`, schema `academy_qa`) and `qaother` already exist (environment.md). Run once, and again after any Redis wipe:

```bash
DC=/private/tmp/claude-501/-Users-khaledsakr-Documents-Etqan-tutor/55afddca-abb7-4698-b08b-38df7f0acb0e/scratchpad/dc.sh
# 1. Switches on academy qa (all default off). parents is needed for the parent role.
$DC exec -T django python manage.py set_features qa --on two_factor phone_login quick_login code_reset parents
$DC exec -T django python manage.py set_features qaother --on two_factor quick_login   # only for TC-024/TC-019
# 2. Clear all failure counters / throttles between cases (sessions live in Postgres, so this is safe).
reset_limits(){ $DC exec -T django python manage.py shell -c "from django.core.cache import cache; cache.clear()"; }
```

curl helpers (cookie jar per actor; the CSRF cookie is the only extra step on public POSTs):

```bash
Q=http://qa.etqan.localhost/api/v1 ; QO=http://qaother.etqan.localhost/api/v1
csrf(){ curl -s -c $1 -b $1 -o /dev/null $2/identity/csrf/; awk '$6=="csrftoken"{print $7}' $1; }   # csrf JAR BASE -> token
post(){ # post JAR BASE PATH JSON  (adds X-CSRFToken from the jar; prints "BODY\nHTTP_CODE")
  t=$(awk '$6=="csrftoken"{print $7}' $1); curl -s -w '\n%{http_code}\n' -c $1 -b $1 -H "X-CSRFToken: $t" -H 'Content-Type: application/json' -d "$4" $2$3; }
get(){ curl -s -w '\n%{http_code}\n' -c $1 -b $1 $2$3; }
login(){ csrf $1 ${4:-$Q} >/dev/null; post $1 ${4:-$Q} /identity/login/ "{\"identifier\":\"$2\",\"password\":\"$3\",\"timezone\":\"Africa/Cairo\"}"; }
# jars: /tmp-free, keep them in the scratchpad
J=/private/tmp/claude-501/-Users-khaledsakr-Documents-Etqan-tutor/55afddca-abb7-4698-b08b-38df7f0acb0e/scratchpad/f02 ; mkdir -p $J
login $J/admin.jar qa-admin@qa.etqan.test 'QA-Admin-2026!'
for r in staff-nocode staff-codes supervisor teacher student parent; do login $J/$r.jar qa-$r@qa.etqan.test 'QA-People-2026!'; done
```

Fixture people (create once as admin; the body is `{"user":{...},"profile":{...}}`, confirm profile fields in `GET /api/schema/`):
- `POST /api/v1/people/students/` `{"user":{"full_name":"F02 Student A","email":"f02-a@qa.etqan.test","phone":"+201000000001"},"profile":{}}` creates an invited student (unusable password). Same for `f02-b` (phone `+201000000001`, shared with A), `f02-c`, `f02-d`, `f02-e`; a parent `f02-parent@`, a teacher `f02-teacher@`.
- Give a fixture a known password through the real flow: `POST /identity/password/reset/` `{"email":...}`, read the link from mailpit (`curl -s localhost:8025/api/v1/messages` then `/message/<ID>`), then `POST /identity/password/reset/confirm/` `{"uid","token","new_password":"F02-Pass-2026!"}`. This is also TC-009.
- Staff with codes: `qa-staff-codes@` needs `quick_login.create`, `student.view`, `teacher.view`, `parent.view`. Check with `GET /me/` `permissions`; if missing, grant through the staff role in `/api/v1/access/` (F03 owns roles, so only read here).
- Look up ids: `GET /api/v1/people/students/?search=f02`, or `psql -h localhost -p 5433 -U etqan -d etqan -c "set search_path=academy_qa; select id,email,role,is_active from identity_user order by id"`.
- TOTP code generator (stdlib only), save as `$J/totp.py`: `import sys,hmac,hashlib,struct,time,base64;k=base64.b32decode(sys.argv[1].upper()+'='*(-len(sys.argv[1])%8));c=int(time.time())//30;h=hmac.new(k,struct.pack('>Q',c),hashlib.sha1).digest();o=h[-1]&15;print('%06d'%((struct.unpack('>I',h[o:o+4])[0]&0x7fffffff)%10**6))`. If a code lands on a 30 s boundary, retry.
- Session surgery (TC-013/017/029), schema `academy_qa`: `$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "<python>"` (decode with `Session.objects.get(pk=KEY).get_decoded()`, edit through `SessionStore(KEY)`).
- Mail: mailpit API `http://localhost:8025/api/v1/messages`. Delete between cases: `curl -s -X DELETE localhost:8025/api/v1/messages`.
- SMS is `console` backend = FAKE: read texts with `$DC logs --since 2m django celery | grep "SMS to"`. `sms.phone_available()` is true because DEBUG is on.
- DB checks: `psql -h localhost -p 5433 -U etqan -d etqan` with `set search_path=academy_qa;`.

Cleanup rule for every case: delete mailpit messages, `reset_limits`, restore any switch changed, re-activate/restore any fixture changed, and leave the seeded `qa-*` passwords as in environment.md. Fixture `f02-*` people may stay (the academy is a QA academy).

---

## Cases

### TC-001 Admin session lifecycle: login, me, logout, replay (UI smoke)
- Priority P1. Provider REAL. Role admin. Switches none.
- Steps (API): `login admin.jar qa-admin@qa.etqan.test 'QA-Admin-2026!'`, then `GET /identity/me/`, then `POST /identity/logout/`, then replay the old `sessionid` with `GET /identity/me/`.
- Steps (UI): Playwright opens `http://qa.etqan.localhost/app/login`, fills email and password, lands on the dashboard, opens the user menu, signs out, and presses Back.
- Expected: login 200 with the `me` payload (`role:"admin"`, `is_super_admin:true`, `permissions` non-empty, `features` lists the enabled codes, `impersonator:null`). Logout 200. The replayed cookie gets 403 on `me/`. The UI returns to `/app/login` and Back doesn't show data.
- Assert API: `Set-Cookie sessionid` has `HttpOnly`; `csrftoken` has no `HttpOnly`.
- Assert DB: after login `identity_user.last_login_ip` is `127.0.0.1` or the Docker gateway (not null), `last_login_device` is set, `last_login_timezone='Africa/Cairo'`, `last_login` is fresh. After logout the `django_session` row is gone (`select count(*) from django_session where session_key=<key>` is 0). `identity_user.timezone` is unchanged.
- Cleanup: none.

### TC-002 Login CSRF regression (ETQAN-QA-006)
- Priority P1. Provider REAL. Role anonymous.
- Steps: `POST /identity/login/` with a valid body and no `X-CSRFToken` (fresh jar, no cookie); then with a token but `Origin: http://evil.example`; then with the token and no Origin.
- Expected: the first two give 403 `CSRF Failed: ...` with no `sessionid` set; the third gives 200.
- Assert DB: after the two refusals `last_login` of the user is unchanged and there is no new `django_session` row.
- Existing: T `test_login_csrf.py` (8 tests). This is the one live regression through Caddy.
- Cleanup: logout.

### TC-003 Credential failures: no account enumeration, deactivated user
- Priority P1. Provider REAL. Role anonymous. Data: `f02-a` with a known password, one deactivated student `f02-e`.
- Steps: `login` with (a) wrong password, (b) unknown email, (c) email in upper case `F02-A@QA.ETQAN.TEST` with the right password, (d) the email with leading and trailing spaces, (e) the deactivated student with the right password, (f) the deactivated student with a wrong password, (g) `identifier` as `email` alias key, (h) empty password, (i) missing identifier.
- Expected: (a), (b), (e), (f) are all 400 `{"non_field_errors":["Invalid credentials."]}` with identical bodies and similar timing. (c) 200. (d) record the result, either 200 or the same 400 as (b), but never 500. (g) 200. (h) and (i) are 400 field errors.
- Assert DB: `last_login` is unchanged for failed attempts. A deactivated person who is not a registrant never gets `registration.*` or `identity.email_unverified` codes.
- Cleanup: `reset_limits`.

### TC-004 Per-identifier lockout (10 failures an hour)
- Priority P1. Provider REAL. Role anonymous.
- Steps: 10 wrong passwords for `f02-a@` from one jar; 11th attempt with the correct password; the same with a different spelling of the email; then `qa-student@` with the right password; then `f02-a@` against `qaother` (`$QO`) with its own wrong password; clear and repeat after a success.
- Expected: failures 1..10 are 400; the 11th (correct password) is 429 with a `Retry-After` of about 3600 and no session. Another spelling (upper case) is also 429 (shared counter). `qa-student` still signs in (200). `qaother` is not locked (400, not 429). A success before the 10th resets the counter (11 failures spread over two runs interrupted by a success never lock).
- Assert: Redis keys are hashed (`$DC exec -T redis redis-cli --scan --pattern 'failures:*'` shows only digests, no email).
- Existing: T `test_signin.py::test_ten_failures_on_one_identifier_lock_it`, `test_limits.py`. Live value: Redis, cache key prefix per tenant, `Retry-After`.
- Cleanup: `reset_limits`.

### TC-005 Per-IP lockout (50 failures) and X-Forwarded-For spoofing through Caddy
- Priority P1 (security). Provider REAL. Role anonymous.
- Steps: send 51 failed logins, each for a different unknown email, from one IP; then one more attempt with a correct password for `qa-student@`. Repeat with every request carrying a random `X-Forwarded-For: 10.<n>.<n>.<n>` header (and again with a header chain `1.2.3.4, 5.6.7.8`).
- Expected: the 51st failure leaves the IP blocked; the next request, even with correct credentials, is 429. With spoofed `X-Forwarded-For` the IP key must NOT change, because the stack trusts `NUM_PROXIES=1` and Caddy must overwrite or append, never pass the client value through. If rotating the header resets the counter, the spray limit is bypassable: file P1 (see S5).
- Assert: `LOGIN_ID` still limits any single account to 10 failures even when the IP limit is bypassed (so the bypass is only a spray problem).
- Cleanup: `reset_limits`.

### TC-006 Deactivate and reactivate a student with a live session
- Priority P1. Provider REAL. Role admin acts, student is the target. Data: `f02-a`, signed in on two jars (`a1.jar`, `a2.jar`).
- Steps: admin `POST /api/v1/people/students/<id>/deactivate/`; then `GET /identity/me/` on both student jars; then the student logs in again; then admin `POST .../activate/` and the student logs in; then admin tries to deactivate their own account and `qa-admin` as the last admin (`POST /api/v1/people/admins/<admin_id>/deactivate/`; confirm the kind in `people_urls.py` KIND).
- Expected: deactivate 200; both student sessions get 403 on the next request (immediately, not at expiry); relogin is 400 "Invalid credentials."; activate 200 then login 200. Self and last-admin deactivation are refused (400, not a 500).
- Assert DB: `identity_user.is_active` flips; `django_session` rows for that user are gone after deactivation (`select count(*) from django_session` decreases by 2).
- Existing: T `test_signin.py::test_inactive_is_invalid_credentials`, `test_people_services.py` (deactivate). Live value: both sessions die.
- Cleanup: student reactivated.

### TC-007 Email verification and resend
- Priority P1. Provider REAL (mailpit). Role student `f02-a` (signed in), anonymous for verify.
- Steps: `POST /identity/me/emails/` `{"email":"f02-a-second@qa.etqan.test","current_password":"F02-Pass-2026!"}`; read the mail and take the key from `/app/verify-email?key=<KEY>`; `POST /identity/verify-email/` `{"key":"<KEY>"}`; repeat the same key; a garbage key; the key from a `qaother` mail at `qa`; `POST /identity/resend-verification/` for an unknown, a verified and an unverified address; spam resend 6 times for one address; with DB edit (`update account_emailaddress set verified=false where ...primary`) log in by email.
- Expected: add 201 with `verified:false` and a security alert mail to the primary; verify 200 then `GET /me/emails/` shows `verified:true`; second use and garbage key 400 `Invalid or expired verification key.`; foreign-academy key 400; resend always 200 (same body for unknown, verified, unverified), 6th within the hour 429; primary unverified makes the email login 400 `Email address is not verified.` while the password is right; wrong current password 400 on add.
- Assert DB: `account_emailaddress.verified`, `account_emailconfirmation` row consumed or deleted, `identity_user.email` unchanged until set-primary. Only one mail per resend.
- Existing: T `test_email_management.py`. Live value: mailpit delivery, cross-academy key.
- Cleanup: restore `verified=true` on the primary; remove the second address (`DELETE /identity/me/emails/<id>/`).

### TC-008 Password reset by link, end to end
- Priority P1. Provider REAL (mailpit). Role student `f02-a` (verified), anonymous.
- Steps: sign in on `a1.jar`; `POST /identity/password/reset/` `{"email":"f02-a@qa.etqan.test"}` (also an unknown address and an unverified one); take `uid` and `token` from the mail link (`/app/reset-password?uid=..&token=..`); `POST /identity/password/reset/confirm/` `{"uid","token","new_password":"F02-New-2026!"}`; reuse the same token; log in with the old and the new password; `GET /me/` on `a1.jar`; send the request 6 times for one email; use a `qaother` token at `qa`.
- Expected: reset request is 200 with the same body for known, unknown and unverified emails, and a mail only for the verified one. Confirm 200 and then the old password fails, the new works. Second use of the token 400 `Invalid or expired reset link.`. The pre-existing session `a1.jar` is dead (403). Security alert "password changed" arrives at the primary. 6th request in an hour 429 (5 per hour per email, counted even for unknown addresses). Foreign-academy token 400.
- Assert DB: `identity_user.password` hash changed; `account_emailaddress.verified` true for the primary.
- Existing: T `test_password_management.py`. Live value: sessions, mail, throttle through Redis.
- Cleanup: set the password back with the same flow.

### TC-009 Invite acceptance by reset link (new student onboarding)
- Priority P1. Provider REAL. Role admin invites, new student accepts.
- Steps: admin `POST /api/v1/people/students/` for `f02-new@qa.etqan.test`; `GET /identity/me/` as that person is impossible, so `POST /identity/login/` first (must fail); admin `POST /api/v1/people/students/<id>/invite/`; the student takes the link from the mail and `POST /identity/password/reset/confirm/`; student logs in; the student `POST /identity/password/reset/` while still invited (before accepting) on a second person `f02-new2`.
- Expected: login before the invite is 400 "Invalid credentials."; invite mail arrives once; confirm 200 and sets the password and `verified=true` on the primary; **no** "password changed" alert (first activation); login 200. For `f02-new2`, "Forgot password" re-sends the invite instead of a reset mail. Invite re-send for an already active student is 400 (`Only someone who has not set a password yet can be re-invited.`).
- Assert DB: `identity_user.password` goes from unusable (`!` prefix) to a hash; `account_state` is active.
- Cleanup: none.

### TC-010 Change password and password quality
- Priority P1. Provider REAL. Role student (two jars: `a1`, `a2`).
- Steps: `POST /identity/me/password/` with (a) wrong current, (b) `new_password` of 7 chars, (c) `"12345678"`, (d) `"password"`, (e) `"f02-a@qa.etqan.test"`, (f) the current password again, (g) a 200 000-character password, (h) a valid new one; then `GET /me/` on `a1` and `a2`; then anonymous and teacher without a session.
- Expected: (a) 400 `Incorrect password.` on `current_password`; (b) 400. (c), (d), (e) should be refused by Django validators (common/numeric/similar), because the settings define `AUTH_PASSWORD_VALIDATORS` and code reset applies them. If any returns 200, file it (S1). (f) record the behaviour. (g) must be 400 or 413, never a slow 200 (S1). (h) 200; the session that changed the password stays valid, the other session is 403; old password no longer logs in; a security alert goes to the primary address; a refused change sends no mail.
- Assert DB: `identity_user.password` changes only on success.
- Existing: T `test_password_management.py` (length, alerts). No test covers validators or max length.
- Cleanup: restore the password.

### TC-011 2FA set-up and sign-in with a TOTP code (UI smoke)
- Priority P1. Provider REAL. Role teacher `qa-teacher@`. Switch `two_factor` on.
- Steps (API): teacher signs in; `GET /identity/me/2fa/` (enabled false); `POST /identity/me/2fa/setup/`; `POST /identity/me/2fa/confirm/` with `{"code":"000000"}`; then with the code from `totp.py <secret>`; `GET /identity/me/2fa/`; `POST /identity/logout/`; `login` again; `GET /identity/me/` with that half-open jar; `POST /identity/login/2fa/` `{"code":"<code>"}`; log out and repeat with the same code in the same 30 s window; `POST /identity/me/2fa/setup/` while enabled.
- Steps (UI): Playwright `/app/account` enables 2FA with the secret shown, then logs out and in through the `TwoFactorStep`.
- Expected: setup 200 returns `secret`, `otpauth_url`, `qr_svg`; confirm wrong code 400, right code 200 with 10 recovery codes; `me/2fa/` shows `enabled:true, recovery_codes_left:10`; relogin answers `{"mfa_required":true}` and `GET /me/` is 403 until step 2; `login/2fa` 200 with `me`; the same TOTP code can't be replayed (400); a second setup is 409 `identity.mfa_enabled`.
- Assert DB: `mfa_authenticator` has one `totp` and one `recovery_codes` row for the user; the stored `data` does not contain the plain base32 secret (Fernet token); the setup secret in `django_session.session_data` isn't plain either.
- Existing: T `test_twofactor_api.py`, `test_login_2fa.py`. Live value: real TOTP clock, encryption with the stack's `ETQAN_SECRETS_KEY`.
- Cleanup: disable 2FA at the end of TC-012 (keep the teacher's secret for TC-012 to TC-014).

### TC-012 Recovery codes, regenerate, disable, switch off and on
- Priority P1. Provider REAL. Role teacher from TC-011.
- Steps: log in with a recovery code instead of TOTP; reuse the same recovery code; `POST /identity/me/2fa/recovery-codes/` `{"code":"<totp>"}` and then use an old code; `POST /identity/me/2fa/disable/` with a wrong code and with a right code; with 2FA enabled again, `set_features qa --off two_factor`: try `GET /identity/me/2fa/`, log in, then `--on` again.
- Expected: a recovery code signs in once; its reuse is 400; after regenerating, all 10 old codes are dead and `recovery_codes_left` is 10; disable with a wrong code 400, with a right one 204 and the next login is direct (no `mfa_required`). With the switch off: `me/2fa/*` are 404, login is direct and ignores the authenticator, the `mfa_authenticator` rows still exist; with the switch back on, login asks for the code again.
- Assert DB: `mfa_authenticator` rows per step; `recovery_codes` data changes on regenerate.
- Existing: T `test_twofactor_api.py`, `test_login_2fa.py::test_switch_off_ignores_authenticators`.
- Cleanup: 2FA disabled; `two_factor` on.

### TC-013 2FA brute force: pending limit, person budget, expiry
- Priority P1 (security). Provider REAL. Role teacher with 2FA on (enable again).
- Steps: (a) password step, then 5 wrong `login/2fa` codes then a correct one; (b) 10 wrong codes spread over several fresh logins, then the correct code; (c) password step, wait 5 minutes (or edit `etqan.mfa_pending.expires` to the past in the session row), then the right code; (d) password step, change the teacher's password through a second session (or admin password-reset link), then the right code; (e) password step, admin deactivates the teacher, then the right code; (f) lock the identifier (10 bad passwords) while a pending step is open.
- Expected: (a) the fifth wrong code gives 403 `identity.mfa_locked` and the correct sixth code is refused until a new password step; (b) after 10 wrong codes in the hour, even the right code is 429 with `Retry-After` (note S4: an attacker who only knows the password can lock a victim out of 2FA for an hour); (c), (d), (e) 403 `identity.mfa_expired` or the refusal, no session; (f) 429 at the second step.
- Assert: after each refusal `GET /me/` is 403. Budget counters live under `failures:mfa_user:*` and `failures:mfa_pending:*` hashed.
- Existing: T `test_login_2fa.py` covers each rule on a fake clock. Live: real session surgery and Redis.
- Cleanup: `reset_limits`; reactivate; reset the password.

### TC-014 Lost device: admin turns off another person's 2FA
- Priority P1. Provider REAL. Roles admin, staff with codes, teacher, student, qaother admin. Data: teacher with 2FA on, student `f02-a` with 2FA on.
- Steps: as each role `POST /api/v1/people/teachers/<id>/two-factor/disable/` (and `students/<id>/...`); admin on own id (`/people/admins/<admin_id>/two-factor/disable/`); `qaother` admin on a `qa` id (`$QO` with the same numeric id); then the target logs in; `set_features --off two_factor` and retry.
- Expected: admin 204 and a `SecurityEvent` is logged; staff (even with all quick-login codes) 403; teacher and student 403; anonymous 403; own account 400 `Use your recovery codes to turn off your own.`; `qaother` admin 404 or 403 for an id that exists only in `qa`, and never affects `qa`; the target's next login has no `mfa_required`; with the switch off the route is 404.
- Assert DB: `mfa_authenticator` rows of the target are gone; `identity_securityevent` has a row `kind='mfa_disabled'`, `actor_id`=admin, `target_id`=target, `ip` set.
- Cleanup: re-enable 2FA if later cases need it.

### TC-015 Quick login workflow: admin opens a student's dashboard and returns (UI smoke)
- Priority P1. Provider REAL. Role admin. Switch `quick_login` on. Data: `f02-a`.
- Steps (API): admin `POST /api/v1/people/students/<id>/quick-login/`; `GET /identity/me/`; with that jar try `POST /identity/me/password/`, `POST /identity/me/emails/`, `PATCH /identity/me/` `{"phone":"+201999999999"}`, `POST /identity/me/2fa/setup/`, `POST /api/v1/people/students/<other>/quick-login/`; `GET /api/v1/identity/me/` for a read-only action; `POST /identity/impersonation/stop/`; `GET /identity/me/`.
- Steps (UI): in Playwright open the student's page, press "Sign in as", see the `ImpersonationBanner`, and press return.
- Expected: start 200 with the student's `me` payload and `impersonator:{id:<admin>,full_name}`; credential and phone routes 403 `identity.impersonating`; nested start 400 `Return to your own account first.`; stop 200 with the admin payload and `impersonator:null`; stop on a normal session 400.
- Assert DB: `identity_user.last_login` and `last_login_ip` of the student are unchanged (quick login is not their sign-in); `identity_securityevent` has `impersonate` then `return` with the right actor and target; the session key changes at start and at stop.
- Existing: T `test_impersonation.py` (about 40 tests). This is the live smoke.
- Cleanup: none.

### TC-016 Quick login permission matrix
- Priority P1. Provider REAL. Roles admin, staff with codes, staff without codes, staff with `quick_login.create` but no `student.view`, supervisor, teacher, student, parent, anonymous. Targets: student, teacher, parent, admin, staff, self, a `qaother` person id.
- Steps: for each role, `POST /api/v1/people/<kind>/<id>/quick-login/` for the three allowed kinds; admin and staff targets use `/people/admins/<id>/quick-login/` and expect no route; then `POST /api/v1/people/quick-login-links/` is TC-018. Run with `parents` off for the parent row.
- Expected: admin 200 for teacher, student and parent (parent needs `parents` on, else 404 or 400). Staff with `quick_login.create` and the kind's `view` 200; staff missing either code 403; supervisor follows its role codes (expect 403 unless it holds the codes); teacher, student, parent 403; anonymous 403 (not 401 with a challenge). Admins and staff are not valid targets (404 no route). A `qaother` id is 404 in `qa`. A deactivated target gets 400 `identity.quick_login_refused`. Switch off: 404.
- Assert DB: only the 200 rows create an `impersonate` SecurityEvent; no event for refusals.
- Existing: T `test_impersonation.py` (admin, staff, teacher 403, parents off, inactive). Matrix compresses live roles.
- Cleanup: `return` each started session.

### TC-017 Impersonation sessions end on every re-check
- Priority P1 (security). Provider REAL. Roles admin acts; staff with codes acts for the code-revoked row.
- Steps: for each trigger start a fresh impersonation then trigger it and call `GET /identity/me/`: (a) the actor's password changes in another session; (b) the actor is deactivated; (c) `set_features qa --off quick_login`; (d) staff loses `quick_login.create` (edit the role); (e) 1 hour passes (edit `etqan.impersonator.since` back by 3700 s in the session row); (f) the staff actor loses `student.view` only; (g) the target's password is changed or the target is deactivated by someone else.
- Expected: (a) to (e) and (g) give 403 on the next request and the session row is removed or invalid; (f) record the behaviour (S8: the target kind's `view` code is not re-checked, so the session survives). After each, stop returns 403 and nobody is left as the actor.
- Assert DB: `django_session` rows for the impersonated session are deleted or logged out (`_auth_user_id` missing).
- Existing: T `test_impersonation.py` (each of a, b, c, d, e, g). Live: real session table and switch toggling through `set_features`.
- Cleanup: switch `quick_login` on; restore passwords and roles.

### TC-018 Quick-login links by email
- Priority P1. Provider REAL (mailpit). Roles admin and staff with codes send; recipients anonymous. Data: students `f02-a`, `f02-c`, teacher `f02-teacher`, parent `f02-parent`.
- Steps: admin `POST /api/v1/people/quick-login-links/` `{"user_ids":[a,c,teacher,parent,admin_id,999999]}`; again immediately; staff-with-codes sends including an admin id; staff without `parent.view` includes a parent; take a token from the mail (`/app/quick-login?token=<uid>.<token>`) and `POST /identity/quick-login/` `{"token":"<uid>.<token>","timezone":"Africa/Cairo"}` (with CSRF); reuse the same token; use a token after the student logs in by password or changes the password; use a token for a user with 2FA on; 21 invalid tokens from one IP.
- Expected: first call returns `sent` for the 4 eligible people and `skipped` entries with `reason` (admin id is `role`, the missing id is `not_found`); the second call within 5 minutes skips them as `recent`; staff including an admin or a kind without `view` get 403 for the whole batch and no mail; a link signs in once (`me` payload), the second use is 400 `Invalid or expired link.`; after a password change or another sign-in the link is dead; a 2FA user gets `{"mfa_required":true}` and the link is only spent after the code; the 21st failure is 429.
- Assert DB: `identity_securityevent` rows `link_sent` per recipient (actor admin) and `link_used`; `last_login` stamped by the use; exactly one mail per recipient.
- Existing: T `test_quick_login_links.py` (about 25 tests). Live value: delivered link, real token exchange.
- Cleanup: `reset_limits`; delete mails.

### TC-019 Security log: who sees what, and isolation
- Priority P1. Provider REAL. Roles admin, staff with codes, supervisor, teacher, student, anonymous, `qaother` admin.
- Steps: after TC-014, TC-015 and TC-018 each role `GET /api/v1/identity/security-log/` and `?page=2`; `qaother` admin reads its own log; switch `quick_login` off and read again.
- Expected: admin 200 with `kind` in `impersonate|return|link_sent|link_used|mfa_disabled`, newest first, with actor and target names and `ip`; staff (even with `quick_login.create`), supervisor, teacher, student 403; anonymous 403; switch off 404. `qaother` sees none of the `qa` events.
- Assert DB: the page's `count` equals `select count(*) from identity_securityevent`.
- Cleanup: switch on.

### TC-020 Reset by code (email) for a student: full workflow
- Priority P1. Provider REAL (mailpit; Celery task runs for real). Role anonymous. Switch `code_reset` on. Data: `f02-a` (verified email), a teacher, an admin, a staff user, a deactivated student, an unverified-email student.
- Steps: `POST /identity/password/code/` `{"channel":"email","identifier":"f02-a@qa.etqan.test"}` and for each ineligible identifier and for an unknown address; read the 6-digit code from mailpit; `POST /identity/password/code/verify/` `{"channel":"email","identifier":...,"code":"<code>"}`; `POST /identity/password/code/reset/` `{"channel":"email","identifier":...,"code":"<code>","account_id":<id>,"new_password":"F02-Code-2026!"}`; reuse; with `f02-a` signed in on `a1.jar` before; also `new_password` `"12345678"`.
- Expected: every request is 202 with an empty body, and only the eligible active student gets a mail (a teacher, admin, staff, inactive, unverified get none). Verify 200 lists `{accounts:[{id,full_name}]}` and does not spend the code. Reset 204, does not sign in (no `Set-Cookie sessionid`), the old session is dead, the old password fails, the new one works, and an alert mail follows. The same code again is 400 `Invalid or expired code.`. A weak password is 400 and does not spend the code. A code from `qa` at `qaother` is 400.
- Assert DB: `identity_resetcode` has one row per (channel, target), `code_hash` is a 64-char hex HMAC (not the 6 digits), `used_at` set after reset, `tries` counts wrong attempts.
- Existing: T `test_code_reset.py` (about 30 tests). Live value: Celery task and real mail, plus the 202 uniformity across the wire (compare body and timing for known vs unknown).
- Cleanup: `reset_limits`; delete mails.

### TC-021 Reset by code over SMS (console backend)
- Priority P1. Provider FAKE (SMS console; no Twilio). Role anonymous. Data: `f02-a` and `f02-b` share `+201000000001`; teacher with the same phone.
- Steps: `GET /identity/sign-in-options/` (`code_reset.phone`); `POST /identity/password/code/` `{"channel":"phone","identifier":"+20 100 000 0001"}`; read the text from the django/celery logs; verify; reset for `account_id` of `f02-b`; reuse; fire 201 SMS requests in a loop against different numbers only if the cap is cheaply reachable (else mark the cap as not executed, see coverage-gaps).
- Expected: `code_reset.phone:true` (console backend with DEBUG). The SMS text is in the user's language; verify lists both students but not the teacher; reset changes only the chosen account; the other sibling's password is untouched; the cap can't be exercised end to end without 200 requests, so the 201st behaviour is covered by T `test_the_academy_texts_at_most_its_daily_cap`.
- Assert DB: `identity_resetcode` row with `channel='phone'`, `target` in E.164; only `f02-b.password` changes.
- Live SMS delivery is BLOCKED (no Twilio keys).
- Cleanup: `reset_limits`.

### TC-022 Reset by code: abuse limits and a victim lock-out
- Priority P1 (security). Provider REAL. Role anonymous (attacker), student (victim).
- Steps: (a) request 4 codes for one email within the hour; (b) request one code, send 5 wrong codes, then the right code; (c) 21 wrong codes from one IP across different targets; (d) 11 requests from one IP; (e) victim requests a code, attacker requests another for the same email, victim uses the first code; (f) edit `identity_resetcode.expires_at` into the past and use the code.
- Expected: (a) the 4th request still answers 202 but sends nothing (3 per identifier an hour), so an attacker can keep the victim from ever receiving a code (S4); (b) after 5 wrong tries the right code is 400; (c) the 21st attempt is 429; (d) the 11th is 429; (e) the first code is dead because the newer code replaces it (S4: anonymous interference with a victim's reset); (f) 400.
- Assert DB: `tries`, `expires_at`, and that older rows are deleted when a new code is issued.
- Existing: T `test_code_reset.py` covers each limit. The live run is for the interference scenario and Redis keys.
- Cleanup: `reset_limits`; delete mails.

### TC-023 Phone login
- Priority P1. Provider REAL (no SMS involved). Role anonymous. Switch `phone_login` on. Data: `f02-a` (phone `+201000000001`, password A), `f02-b` (same phone, password B), `f02-c` (phone `+201000000003`, active, password C), a deactivated student with phone `+201000000004`, an invited student with phone and no password.
- Steps: `login` with `identifier` as `+201000000003`, `+20 100 000 0003`, `01000000003`; with the shared phone and password A, with B, and with a password matching neither; with the deactivated student's phone; with the invited student's phone; with the switch off; 10 wrong phone attempts spelled in two different ways; `GET /identity/sign-in-options/`.
- Expected: formatting variants of the same number sign in (record which formats are accepted: `01000000003` without `+20` may be refused by `clean_phone`, which isn't a defect unless it 500s); the shared phone signs in the account whose password matched (A or B); if both accounts had the same password the attempt is refused (400, never an arbitrary account); deactivated and invited are 400 "Invalid credentials."; switch off gives 400 and `sign-in-options.phone_login:false`; the two spellings share one counter (429 at the 11th). The phone path doesn't check email verification (S6): note the outcome for an account with a usable password and an unverified primary email.
- Assert DB: `last_login_ip` set for the account that matched; the other account's `last_login` untouched.
- Existing: T `test_phone_login.py`.
- Cleanup: `reset_limits`; switch on.

### TC-024 Cross-academy isolation of sessions, credentials, tokens and counters
- Priority P1 (security). Provider REAL. Roles admin of `qa`, admin of `qaother`, student of `qa`.
- Steps: (a) take the `sessionid` of `qa-admin` and present it to `qaother` (`curl -H 'Cookie: sessionid=<id>' $QO/identity/me/`) and to the same host with the `Host` header of the other academy; (b) `login` with `qa-admin@` credentials at `$QO`, and `qaother-admin@` credentials at `$Q`; (c) the Etqan staff superuser `ops@qa.etqan.test` at both academies; (d) take a reset token, a verify key, a quick-login token and a reset code from `qa` and use each at `qaother`; (e) lock `qa-student@` and try the same email at `qaother`; (f) from the `qaother` admin call `GET /api/v1/people/students/` and the quick-login endpoint with a `qa` student id; (g) the CSRF cookie of one host sent to the other.
- Expected: (a) 403, no data from the other academy; (b) and (c) 400 "Invalid credentials."; (d) every one is 400 invalid; (e) `qaother` isn't locked; (f) lists only `qaother` people, and a `qa` id is 404; (g) 403 `CSRF Failed` or the token simply isn't honoured.
- Assert DB: `academy_qaother.django_session` has no row for the `qa` key; no `SecurityEvent` is written in the wrong schema; `academy_qa.identity_user` and `academy_qaother.identity_user` have separate id spaces.
- Existing: T `test_limits.py::test_academies_count_separately`, `test_quick_login_links.py::test_a_token_from_another_academy_is_invalid`. This is the end-to-end proof through Caddy.
- Cleanup: `reset_limits`.

### TC-025 Parent account and the `parents` switch
- Priority P2. Provider REAL. Role parent `qa-parent@`. Switch `parents`.
- Steps: parent logs in with `parents` on; `set_features qa --off parents`; parent `GET /identity/me/` on the live session; fresh login; admin quick login as the parent; code reset and quick-login links for the parent; `--on` again.
- Expected: with `parents` off the live session is logged out on the next request (403), the login is 403 `Parent access is not enabled for this academy.`, quick login and links skip or refuse the parent; `me` of others has no `children`. With it on again everything returns.
- Assert DB: parent's `is_active` never changes; no `last_login` stamp on a refused login.
- Existing: T `test_signin.py::test_parent_with_parents_off_is_refused`, `test_login_2fa.py`, `test_impersonation.py`.
- Cleanup: `parents` on.

### TC-026 Identity endpoints by role: compressed permission matrix
- Priority P1. Provider REAL. Roles anonymous, student, parent, teacher, supervisor, staff with codes, staff no codes, admin.
- Steps: call each of these as each role and tabulate the status: `GET csrf/`, `GET sign-in-options/`, `GET me/`, `PATCH me/` (name only), `POST logout/`, `POST me/password/`, `GET me/emails/`, `GET me/2fa/`, `GET security-log/`, `GET google/settings/`, `PATCH google/settings/` `{"client_id":"x"}`, `POST impersonation/stop/`, `POST password/code/` (anonymous). Add `GET /api/v1/identity/me/` with a plain `GET` through Playwright is not needed.
- Expected: `csrf/` and `sign-in-options/` are 200 for all (no private data in `sign-in-options`, only booleans); `me*` need a session (anonymous 403, never 500); `logout/` anonymous 403; `security-log/` and `google/settings` admin only (the rest 403; `google/settings` 404 while `google_sign_in` is off, which is the default); `impersonation/stop/` on a normal session 400, anonymous 403; `PATCH me/` can't change `role`, `email`, `is_active` or `is_staff` (send them and check they are ignored or 400, with the DB unchanged).
- Assert DB: `identity_user.role/is_active/email` unchanged after the mass-assignment attempt.
- Cleanup: none.

### TC-027 Malformed and hostile input never gives a 500
- Priority P2. Provider REAL. Role anonymous.
- Steps: `POST` these to `/identity/login/`, `/identity/password/reset/`, `/identity/resend-verification/`, `/identity/password/code/`, `/identity/quick-login/`, `/identity/login/2fa/`, `/identity/verify-email/`: a JSON array body `[]`; a JSON string body; `{"email":["a@b.c"]}`; `{"email":{"x":1}}`; `identifier` of 255 chars; null bytes; non-UTF-8 bytes; form-encoded body; an empty body; a 3 MB body.
- Expected: always a 4xx (400, 413 or 415) with a JSON error and no stack trace. The two throttled endpoints (`password/reset/`, `resend-verification/`) read `request.data.get("email")` before validation, so a JSON array or string body can raise `AttributeError` and answer 500 (S2). Check Celery and Django logs for tracebacks.
- Assert: `$DC logs django | grep -c Traceback` doesn't grow for the valid-shape cases.
- Cleanup: `reset_limits`.

### TC-028 Google sign-in (switch, settings, no live client)
- Priority P2. Provider BLOCKED for the live flow (no Google client); settings storage REAL.
- Steps: with `google_sign_in` off: `GET /identity/google/start/`, `GET /identity/google/settings/` (admin); switch on without a client: `GET sign-in-options/` and `GET google/start/`; admin `PATCH /identity/google/settings/` `{"client_id":"qa-fake.apps.googleusercontent.com","client_secret":"qa-fake-secret"}` then `GET`; staff and teacher on the same routes; clear the client.
- Expected: off gives 404 on all; on without a client `google:false` in `sign-in-options` and start does not redirect to Google; after saving, `sign-in-options.google` is true, `GET google/settings/` never returns the secret (write-only, shows `redirect_uri` only), staff and teacher 403. The redirect to accounts.google.com and the callback are not executed (BLOCKED).
- Assert DB: `identity_googlesignin` single row (pk 1); the secret column is a Fernet token (starts with `gAAAA`), not the plain text.
- Existing: T `test_google.py` (about 40 tests with a faked Google).
- Cleanup: remove the fake client and switch off.

### TC-029 Session cookie, fixation and expiry
- Priority P2. Provider REAL. Role student.
- Steps: note the `sessionid` before login (from `csrf/` it should have none) and after; log in twice on one jar; edit `django_session.expire_date` into the past for a live session; read the cookie attributes of `/identity/login/` through Caddy; check `SESSION_COOKIE_AGE` with `$DC exec -T django python -c` and note whether a rolling or idle timeout exists.
- Expected: the key changes at login (no fixation); an expired session is 403 and the row is cleaned up by `clearsessions` or on use; production settings set `Secure` and `SameSite=Lax`, the dev stack doesn't (record the observation); the session lasts the Django default of 14 days with no idle timeout, which is a product note rather than a defect.
- Assert DB: `django_session.expire_date` is about 14 days ahead after login.
- Cleanup: none.

### TC-030 Email addresses: primary switch, login by non-primary address, removal
- Priority P2. Provider REAL (mailpit). Role student `f02-c`.
- Steps: add and verify `f02-c-new@qa.etqan.test` (TC-007 flow); log in with it while it is still a secondary; `POST /identity/me/emails/<id>/primary/` `{"current_password":...}` with a wrong password, with an unverified address, with the verified one; log in with the old and the new address; `DELETE /identity/me/emails/<primary_id>/`; delete the old one; add more than 5 addresses; use an address owned by another student, or by a `qaother` user.
- Expected: the primary change needs the password and a verified address and alerts the old primary; the new address logs in; the docs call the primary the login address, so check whether the OLD address and a verified secondary can still sign in (the allauth backend matches any verified `EmailAddress`; S7); deleting the primary is 400; the 6th address is 400 (`ACCOUNT_MAX_EMAIL_ADDRESSES=5`); an address in use by another person is 400 `This email is already in use.`; another academy's address is allowed (separate schema).
- Assert DB: `identity_user.email` follows the primary; exactly one `primary=true` row in `account_emailaddress` for the user.
- Existing: T `test_email_management.py`.
- Cleanup: restore the original primary.

---

## Suspected defects from code reading (for Agent 2)

- **S1 No password-strength rules on change and link-reset.** `ChangePasswordSerializer` and `PasswordResetConfirmSerializer` only have `min_length=8`; `services.change_password` and `confirm_password_reset` never call `validate_password`, although `AUTH_PASSWORD_VALIDATORS` is set and code reset applies it. `12345678` and `password` should be accepted on change and reset-by-link but refused on reset-by-code. There's also no `max_length` on any password field. TC-010, TC-008.
- **S2 Throttle can answer 500.** `EmailScopedThrottle.get_cache_key` calls `request.data.get("email")`; a JSON array or string body makes `request.data` a list or str, so `password/reset/` and `resend-verification/` can raise `AttributeError`. TC-027.
- **S3 Self-service reset ignores `is_active`.** `request_password_reset` mails a link for any verified address, and `confirm_password_reset` sets the password and marks the primary email verified without checking the account is active (the admin-sent reset does refuse inactive accounts). Probably minor; TC-006 can add the step.
- **S4 Lock-out of a victim by anyone who knows the address.** (a) 10 failed passwords lock the identifier for 1 hour for the real owner too; (b) with the password known, 10 wrong second-factor codes lock the person's 2FA for 1 hour; (c) three code requests an hour for an email stop the victim from getting a code, and a newer request replaces the victim's valid code. All by design in the spec, so file as a risk (P3) unless owner wants a CAPTCHA or per-device approach. TC-004, TC-013, TC-022.
- **S5 IP limit could be bypassed by a forged `X-Forwarded-For`** if Caddy passes the client header through (DRF reads the last entry with `NUM_PROXIES=1`). Check `caddy/Caddyfile.local` and production. TC-005.
- **S6 Phone login skips the verified-email check.** Only an email identifier is checked in `LoginView`; a person with a usable password and an unverified primary email can sign in by phone while `ACCOUNT_EMAIL_VERIFICATION="mandatory"`. Reachability unclear (invited accounts have no password), so record it. TC-023.
- **S7 A non-primary verified address (and the old primary) may still sign in.** `ACCOUNT_LOGIN_METHODS={"email"}` with allauth's backend resolves any verified `EmailAddress`, while the docs call the primary the login address; after `set_primary_email` the old address may still work. TC-030.
- **S8 Impersonation does not re-check the target kind's `view` code.** `session_valid` re-checks `quick_login.create` only, so staff who lose `student.view` keep the session until it expires (1 hour). Minor. TC-017.
- **S9 Reset-code `eligible()` for phone requires `email__isnull=False`.** A student with a phone but no email gets no SMS, even though the phone login path doesn't require an email. Needs a product ruling; low. TC-021.

## Not covered or only partly (also listed in coverage-gaps.md)
Google live OAuth (BLOCKED); live SMS delivery (FAKE console); the 200 SMS daily cap and 24 h token expiry (clock-dependent, unit tests only); production cookie flags (`Secure`, `SameSite`) on the dev stack; concurrency races (T `test_concurrent_exchange_signs_in_once`, `test_in_flight_*`); allauth pages are not mounted (nothing to test).

---

## Added by Agent 2 (2026-10-19)

### TC-031 A refused session stays signed out when the condition clears
- Priority P1 (security). Provider REAL. Roles admin and staff `f02-staff-ql@` act; parent `qa-parent@`.
- Steps: start a quick login (or sign the parent in) and keep the `sessionid` value; make the re-check fail
  (`--off quick_login`, remove `quick_login.create` from the role, `--off parents`) and call `GET me/`;
  then clear the condition (switch on, role restored) and replay the same cookie.
- Expected: 403 at the refusal and still 403 afterwards; the `django_session` row is deleted or carries
  no `_auth_user_id` (docs/features/sign-in.md § Quick login; `identity/authentication.py` docstring).
- Why added: TC-017 asserted only the next request; the row and a later replay were not checked.

### Spec corrections after checking the documented intent
- TC-026: `google/settings/` is gated on admins only, not on `google_sign_in` (sign-in.md line 113:
  "GET, PATCH | `google/settings/` | admins"). Admin 200 while the switch is off is correct.
- TC-015: a nested start while impersonating a student answers 403 (the impersonated student has no
  `quick_login.create`), not 400 `Return to your own account first.`; both refuse, the 400 is reachable
  only when the impersonated account itself could start one.
- TC-023: the local form `01000000003` and `00201000000003` are not accepted; only E.164 with or without
  spaces. Not a defect (no 500), recorded.
- TC-029: logging in again on a jar that is already signed in as the same user keeps the session key
  (Django's `login()` cycles only an anonymous session or flushes for another user). A planted
  pre-login key never becomes authenticated, so there is no fixation.
- S6 (phone login skips the email check) and S7 (a verified secondary or old primary address signs in)
  match the docs: sign-in.md step 4.3 "When signing in by email, that address must be verified" (any
  verified address); no doc calls the primary the only login address. Not filed.
- S9 matches docs/features/people.md ("No email means no login"). Not filed.
- S4 (a)(b)(c) and S8 behave as documented (limits in sign-in.md; S-9a re-check list in
  `impersonation.session_valid` is `quick_login.create` only). Recorded as product risks, not filed.

## Results (Agent 2, 2026-10-19, backend adff9c9, dashboard 5ed775d, branch qa/campaign-2026-10)

Evidence root: `qa/evidence/F02/`. Playwright: `dashboard/e2e/qa/f02-signin.spec.ts` (3/3 passed,
`pw-run3.txt`, JSON in `pw/`).

| Case | Result | Tag | Evidence | Notes |
|---|---|---|---|---|
| TC-001 | PASS | REAL (API + UI) | `tc001-002-api.txt`, `pw/tc001-ui.json` | HttpOnly sessionid, csrftoken not HttpOnly, row deleted at logout, replay 403, Back → login |
| TC-002 | PASS | REAL | `tc001-002-api.txt` | no token / evil Origin 403, no session, `last_login` unchanged |
| TC-003 | PASS | REAL | `tc003.txt` | identical 400 bodies, 137–151 ms; padded email 200 |
| TC-004 | PASS | REAL | `tc004.txt` | 11th 429 `Retry-After: 3599`; keys hashed and tenant-prefixed in Redis db 1 |
| TC-005 | PASS | REAL | `tc005.txt` | 51st 429; rotating/chained `X-Forwarded-For` does not reset the IP key. **S5 refuted** (Caddy has no `trusted_proxies`) |
| TC-006 | PASS | REAL | `tc006.txt` | both sessions die at once; **S3 confirmed → ETQAN-QA-020 (P3)**. Last-admin-by-another-admin not executable (one admin); self 400 |
| TC-007 | PASS | REAL (mailpit) | `tc007.txt` | verify once, foreign key 400, resend 6th 429, unverified primary 400 |
| TC-008 | PASS | REAL (mailpit) | `tc008.txt` | uniform 200, mail only for verified, old session 403, alert, 6th 429, qaother token 400 |
| TC-009 | PASS | REAL (mailpit) | `tc009-invite.txt` | `!` → argon2, primary verified, no alert, re-invite active 400 |
| TC-010 | **FAIL** | REAL | `tc010.txt` | **S1 confirmed → ETQAN-QA-018 (P2)**; (a)(b)(h) correct |
| TC-011 | PASS | REAL (API + UI) | `tc011-api.txt`, `pw/tc011-ui.json` | Fernet in DB and session; replay 400; second setup 409 |
| TC-012 | PASS | REAL | `tc012.txt` | recovery once; regenerate kills old; switch off 404 + rows kept |
| TC-013 | PASS | REAL | `tc013.txt` | 5th 403 `mfa_locked`; 10/h → 429; expiry, password change, deactivation, identifier lock all refuse. S4(b) as documented |
| TC-014 | PASS | REAL | `tc014.txt` | staff/teacher/student/anon 403, own 400, qaother 404, `mfa_disabled` events actor 1 |
| TC-015 | PASS | REAL (API + UI) | `tc015-api.txt`, `pw/tc015-ui.json` | 403 `identity.impersonating` on all credential routes; key rotates at start and stop |
| TC-016 | PASS | REAL | `tc016.txt` | full 9-role × 6-target matrix; 6 events for 6 starts |
| TC-017 | **FAIL** | REAL | `tc017.txt` | (a)–(e),(g) 403 on next request, but the refused session revives → **ETQAN-QA-017 (P2)**. **S8 confirmed** (session kept after losing `student.view`; new start refused), as designed |
| TC-018 | PASS | REAL (mailpit) | `tc018.txt` | sent/skipped reasons, `recent`, 403 batches, 2FA link spent after code, 21st 429 |
| TC-019 | PASS | REAL | `tc019.txt` | count 35 = DB; non-admins 403; qaother 0 events |
| TC-020 | PASS | REAL (mailpit, Celery) | `tc020.txt` | 202 uniform ~70 ms; HMAC hash; reset 204 without session |
| TC-021 | PASS | FAKE (SMS console) | `tc021.txt` | verify lists siblings not teacher; only f02-b changed. **S9 refuted** (people.md). Live SMS BLOCKED |
| TC-022 | PASS | REAL | `tc022.txt` | newer code replaces older; 4th silent; 5 tries; 21st/11th 429; expiry 400. S4(c) as documented |
| TC-023 | PASS | REAL | `tc023.txt` | ambiguous shared phone refused; shared counter 429. **S6 confirmed but per docs** |
| TC-024 | PASS | REAL | `tc024.txt` | sessions, creds, reset/verify/link/code tokens, counters, ids all isolated |
| TC-025 | **FAIL** | REAL | `tc025.txt` | live session 403, login 403, quick login 404; but session revives (ETQAN-QA-017) and resets still sent (ETQAN-QA-020) |
| TC-026 | PASS | REAL | `tc026.txt` | matrix as expected after correction; mass assignment ignored |
| TC-027 | **FAIL** | REAL | `tc027.txt` | **S2 confirmed → ETQAN-QA-019 (P3)**; the other 5 endpoints never 500 |
| TC-028 | PASS | REAL (settings); live OAuth BLOCKED | `tc028.txt` | secret Fernet `gAAAA`, never returned; staff/teacher 403 |
| TC-029 | PASS | REAL | `tc029.txt` | 14 days, no idle timeout; prod sets Secure + Lax; no fixation |
| TC-030 | PASS | REAL (mailpit) | `tc030.txt` | primary needs pw + verified; max 5; in-use 400. **S7 confirmed but per docs** |
| TC-031 | **FAIL** | REAL | `tc017.txt`, `tc025.txt` | ETQAN-QA-017 |

Totals: 31 executed (30 + TC-031), 26 PASS, 5 FAIL, 0 BLOCKED (TC-028 live OAuth and TC-021 live SMS
sub-parts BLOCKED, coverage-gaps). Tags: REAL 30 · FAKE 1 (TC-021). No money in this feature (no amounts).
Open: ETQAN-QA-017 (P2), ETQAN-QA-018 (P2), ETQAN-QA-019 (P3), ETQAN-QA-020 (P3).
Not run: scoped pytest `etqan/identity` (lean mode; no fix to retest yet).

### Retest 1 (Agent 2, 2026-10-19, after fix cycle 1; evidence `evidence/F02/retest-1/`)
| Case | Result | Tag | Note |
|---|---|---|---|
| TC-010 | PASS | REAL (API + DB + UI) | QA-018 VERIFIED; same-password reuse PROPOSAL-accepted |
| TC-017 | PASS | REAL | QA-017 VERIFIED (switch and staff role-code variants) |
| TC-025 | PASS for the refusal (QA-017); reset sub-part still FAIL (QA-020, P3) | REAL | |
| TC-031 | PASS | REAL | row deleted, replay 403 for admin, staff and parent |
| TC-008 (link reset quality) | PASS | REAL (mailpit) | weak values 400, token error first |

