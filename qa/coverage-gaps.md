# Coverage gaps, blocked items and proposals

## Blocked by missing credentials (live integration coverage NOT claimed)
| Integration | What is still tested | Tag |
|---|---|---|
| Stripe / PayPal (academy keys), Stripe Connect | the checkout simulator, refunds, webhook handling with simulated events | SIMULATED |
| Zoom S2S | Jitsi fallback (REAL link generation); Zoom flows only with fake providers | FAKE / BLOCKED |
| WhatsApp Cloud API | fake provider only | FAKE / BLOCKED |
| Twilio (phone codes) | `SMS_BACKEND` console/locmem | FAKE / BLOCKED |
| Google sign-in | no OAuth client | BLOCKED |
| Web push (VAPID) | Tier 2 | — |
| AI (Anthropic) | `ETQAN_AI_FAKE` | SIMULATED (Tier 2) |

## Proposals needing owner approval (migrations, API changes, refactors)
_Earlier proposals sit under their feature below. F06 fix cycle 1 (Agent 3, 2026-10-19):_

- **PROPOSAL, ETQAN-QA-041 (re-anchor sessions on a timezone change).** Today a timezone change keeps
  every generated session at its old UTC instant, so one weekly slot shows two local times. Fix needing
  approval: when `timezone` changes, replace the untouched generated future sessions of every live
  subscription (the slot-edit pattern: `rules.delete_untouched(rules.regenerable(occurs_on__gte=today))`
  then `generate_horizon()`), or recompute their `starts_at` in place. Blockers: `etqan.academy` may not
  import `etqan.scheduling` (lint-imports contract "academy imports no other business module"), so it
  needs a new seam (the settings view calling a scheduling service, or a settings-changed hook);
  session ids change (Zoom meetings already provisioned for tomorrow, reminders and notifications keyed
  on them); marked, hand-added and postponed sessions would still keep the old time, and the office must
  be told which. No migration needed. **Mitigation done (no API change):** the settings form shows a
  warning while a new timezone is selected ("Lessons already on the schedule keep their current time…",
  ar/en/es), documented in `docs/features/academy-settings.md`.
- **PROPOSAL (owner decision), ETQAN-QA-039 design change.** The duplicate lesson after an early renewal
  over a marked old lesson is the documented design (B2b spec §10, B2a; `test_renewal.py`,
  `test_today.py`). If the owner prefers one lesson: in `generation.generate`, skip a renewal's
  (slot, date) when its `renewed_from` holds a non-cancelled session at the same UTC start (or postponed
  from it), counting it in `skipped_existing`; amend B2b §10 and the two tests. Prototype written and
  then reverted in fix cycle 1 (it broke exactly those two tests). Meanwhile the overlap is reported in
  the renew answer's `conflicts` (ETQAN-QA-042 fix).
- **Follow-up, ETQAN-QA-042 UI.** The create and renew 201 answers now carry `conflicts`, but
  `SubscriptionForm` / `RenewDialog` navigate straight to the detail page and don't show them. Showing
  them as `BundleForm` does (stay on a result panel when `conflicts.length`) is a small dashboard change;
  not done in this cycle to keep it to the API fix.
- **Owner confirmation, ETQAN-QA-040.** Implemented as "a deactivated student or the date's teacher gets
  no new sessions; existing ones stay; reactivating refills the horizon" (matching create, renew and a
  hand-added session, which already refuse inactive people). If the owner wants deactivation to keep
  scheduling (e.g. a short leave), revert `rules.person_inactive` and its two call sites.

## Untested areas
_Agent 1 adds the per-feature gaps here._

### F01: Tenancy & provisioning (Agent 1, 2026-10-17)

**Untestable locally:**

| Gap | Why | What covers it instead | Tag |
|---|---|---|---|
| The custom-domain "Check DNS and activate" success path (TC-088) | Inside the django container `sites.etqan.localhost` does not resolve, and `DJANGO_EDGE_PUBLIC_IP` is unset, so `check_domain_dns` can never pass locally. Changing the env would mean recreating the container, which isn't allowed. | pytest with a fake resolver (`test_domains.py`, `test_domain_admin.py`). Routing after activation is tested REAL via `services.activate_domain` in a shell (TC-089). | FAKE / BLOCKED |
| Production edge (`infra/caddy/Caddyfile`): the `127.0.0.1:8099` TLS-ask listener, on-demand TLS, Cloudflare wildcard, HSTS | There is no production or staging edge here. | Static review only. The local `caddy/Caddyfile.local` `/internal/*` 404 is tested REAL (TC-096). | BLOCKED |
| The `localhost:8000` dev port publishes Django directly, so `/internal/tls-allowed` is reachable on the host | This is a dev-only compose port mapping and does not exist in production. | Recorded, not a defect. | — |
| Live Etqan default provider accounts under `etqan_defaults_suspended` (TC-079) | There are no provider credentials and possibly no `PlatformAccount` rows. | The integrations resolver pytest. | SIMULATED / BLOCKED |
| Gunicorn `--timeout 120` against schema-migration time on the Add-academy POST | Production uses gunicorn, while local uses runserver, which has no timeout. | TC-011 records the local duration. Above about 60 s it is a production risk to raise with the owner. | — |
| Partial failure at every provisioning step other than admin creation | It can't be induced against the running stack without changing code. | TC-058 needs a new parametrised pytest (FAKE). TC-059, which kills the process mid-provision, is the REAL check. | FAKE |

**Product questions for the owner (not defects yet):**
- **Cleaning up throwaway academies.** The admin has no delete and there is no command, so test
  academies such as `journey-<stamp>` (from the e2e) and `qa-tmp-*` pile up, each with a whole
  schema. Should there be a supported "drop academy" path?
- **Reserved subdomains.** Should `status`, `support`, `docs`, `billing`, `staging` and `e2e` be
  reserved too (TC-040)?
- **Suspended academies and the TLS ask.** `is_tls_allowed` still returns 200 for a suspended
  academy's active domain (TC-097). Is that intended, so the suspended page is served over TLS?
- **Queued tasks for suspended academies.** Tasks queued through `academy_context` (emails etc.)
  still run for a suspended academy. Only `for_each_academy` skips them.
- **The status actions leave no audit trail.** Suspend and reactivate don't write
  `django_admin_log` entries (TC-138). Should they?
- **Timezone and currency on the academy change page.** These fields don't propagate to
  `AcademySettings` (S4 / TC-055). Should they be read-only, sync the settings row, or be removed?

**Tooling note:** `pgrep` is not in the django image. To check for a running pytest, use the
`/proc` loop in `specs/F01-tenancy-provisioning.md` §1.

### F01: gate decision carry-forward (Agent 2, 2026-10-18)
F01 PASSED at the gate with these **known open P3/P4 defects** (in `bug-register.md`, still OPEN, for a
later fix cycle; none blocks a critical workflow, tenant isolation or data integrity):
- ETQAN-QA-004 (P3): the Domain admin returns 500 for an invalid hostname (TC-084).
- ETQAN-QA-005 (P3): two simultaneous creates of one subdomain: the loser gets a raw IntegrityError; the data stays consistent (TC-062).
- ETQAN-QA-007 (P3): the Suspend/Reactivate actions write no admin history (TC-138).
- ETQAN-QA-008 (P3): sign-in on an unknown academy host fails silently (TC-100, SPA part only).
- ETQAN-QA-009 (P3): `manage()` in e2e breaks when the checkout path contains a space (harness).
- ETQAN-QA-010 (P4): domain action messages capitalise hostnames, and Make primary/Disable confirm nothing.
- ETQAN-QA-011 (P3): the set-password page shows a raw English validator message in Arabic (TC-141).
- ETQAN-QA-012 (P3): a view-only Etqan staff member opening an academy change page gets a 500 (not a privilege escalation: every write is still refused).

**Residual noted in QA-003:** `scan_notifications` / `notifications.scan` still fail for every academy
if one academy already has a bad timezone (`qa-tmp-tz`, suspended, so skipped). Creation now refuses a
bad value; making the global loop tolerate one bad academy is a proposal for the owner.

**Test-only proposal (Agent 3, no owner approval needed):** adopt Agent 2's out-of-repo gate test
(`qa/evidence/F01/gate/test_f01_gate.py.txt`: TC-058 rollback per step, TC-060 admin save path,
TC-088 DNS subset/superset) into `backend/etqan/tenants/tests/`. Also retire or invert
`dashboard/e2e/qa/f01-console.spec.ts` TC-133b, which drives the pre-fix UI path.

### F01: Agent 2 execution findings (2026-10-17), not defects / owner questions
- **Throwaway academies cannot be removed** (no delete by design, no command). F01 left `qa-tmp-1`,
  `qa-tmp-tz`, `qa-tmp-race-a`, `qa-tmp-race-b` suspended and the journey e2e left three active
  `journey-<stamp>` academies. Each costs a schema migrated on every `migrate_schemas`. Proposal (owner
  approval): an Etqan-only `drop_academy --subdomain … --yes` command for QA/journey academies.
- **Admin academy creation is synchronous**: the Add-form POST took 14.9 s locally (gunicorn `--timeout 120`;
  fine today, grows with migrations).
- **Academy change form edits `timezone`/`currency` that only seed settings** (documented in
  academy-settings.md): staff see an editable field that changes nothing the academy uses. Suggest
  read-only or a help text.
- **Etqan defaults suspended ⇒ password-reset and invite emails stop** for an academy without its own
  email account (`Email not sent: not set up`). Matches SUSPEND_HELP, but locks users out of password
  recovery. Owner to confirm.
- **`/internal/tls-allowed` answers `ok` for a suspended academy's domains** (only the domain status is
  checked). Probably intended (the suspended page is still served over TLS); owner to confirm.
- **Subdomain names**: `status`, `support`, `docs`, `billing`, `staging`, `e2e`, `grafana`, `signoz` and
  punycode `xn--…` are accepted. Consider reserving infra names and refusing `xn--` (homographs).
- **pytest gaps** (test-only, Agent 3): parametrised rollback per provisioning step (TC-058), admin
  save-path failure (TC-060), DNS superset case (TC-088), draft/paid invoice for `may_suspend` (TC-078),
  and any non-superuser staff in the tenants admin tests (ETQAN-QA-002).
- **Host e2e install**: `pnpm install` on the host cannot fetch the private `@etqan/tokens` git dependency;
  Agent 2 used a standalone `@playwright/test@1.62.1` symlinked into `dashboard/node_modules` (see
  environment.md). Also a partial `dashboard/node_modules/.pnpm` was left by the failed install
  (gitignored).

### F01: gap review (Agent 1, 2026-10-18)
The new cases are F01-TC-150 to TC-171 in `specs/F01-tenancy-provisioning.md` § Gap review. The
items below can't be run, or can't be run safely, against the local stack.

| Gap | Why | What covers it instead | Tag |
|---|---|---|---|
| The QA-001 fix on the **running** stack: `just rebuild` / `docker compose build` with `HOST_GID=20`, then `up` | Recreating the only stack's containers is not allowed during QA. Setup step 5 showed that named volumes created by an older image (`dashboard_node_modules`) give EACCES once the user changes. Switching from the `HOST_GID=1000` workaround to GID 20 will likely hit the same thing on every Mac (node_modules volumes, and possibly bind-mounted `media/`). | TC-001..007 (separate tags, REAL). Proposal: at the next planned rebuild, run `just rebuild` on macOS without `dc.sh`, and record whether `dashboard_node_modules` / `marketing_node_modules` need recreating. If they do, document it in the runbook or add a volume-ownership fix-up to the dev entrypoint (owner approval). | BLOCKED (procedural) |
| Login CSRF over **HTTPS in production**. `CsrfChecked` compares Origin `https://<host>` with the request, which relies on `SECURE_PROXY_SSL_HEADER` plus Caddy's `X-Forwarded-Proto`. Custom domains are not in `CSRF_TRUSTED_ORIGINS` (default `[]`). | No TLS edge locally; the local stack is http only. | TC-158 (custom domain over http, REAL), and a static review of `config/settings/production.py` (the header is set) and `infra/caddy/Caddyfile`. A broken header would refuse **every** production login with 403 "CSRF Failed: Origin checking failed", so a staging smoke sign-in on a subdomain and on a custom domain should precede the next deploy. | BLOCKED |
| django_celery_beat "Run selected tasks" / Enable / Toggle by a view-only staff member (S6), actually executed | The tasks loop over every academy, including demo, other and the non-QA `khaled`, so running one would write data that must not be modified. | TC-151 records whether the actions are offered, plus a `get_actions()` check in a shell (static REAL). A pytest with a dummy task (Agent 3, test-only) would cover execution. | REAL (static) / FAKE |
| An SMTP outage while the first-admin invite is sent | It would mean stopping Mailpit in the only stack. | TC-170 (FAKE pytest), and TC-168 (the REAL recovery through "Forgot password"). | FAKE |
| Expiry of the invite and reset tokens (`PASSWORD_RESET_TIMEOUT`) | It needs time travel. | TC-168's expiry part as a frozen-time pytest. | FAKE |
| Tasks queued through `academy_context` before a suspension and run after it (D5) | There is no way to hold a queued task across a suspension without stopping the worker. | Owner question already recorded (F01, 2026-10-17). A pytest could enqueue, suspend, then run the task eagerly (Agent 3, test-only). | FAKE |
| `PeriodicTask` and other public admins for staff holding **change** permissions: the rights of `change_user` / `add_user` in `identity.User` (the default ModelAdmin shows every field, including `is_superuser`, `user_permissions` and `groups`) | That is Django's design (change_user amounts to superuser), not a defect. Recorded so that the owner grants `identity.change_user` only to superusers. | none | — |

**Product questions from the gap review (owner):**
- **Copying features replaces, it doesn't merge.** A target's own stored switches are dropped
  (TC-153). Is that intended? The action's description ("give each target exactly source's stored
  switches") says yes. The admin message doesn't tell staff.
- **Non-ISO currency codes.** `clean_currency` checks only the three-letter shape (TC-157). Should
  it check ISO 4217?
- **No console action resends a first admin's invite.** "Forgot password" on the academy host is
  the only recovery path (TC-168). Should the Academy admin get a "Resend admin invite" action
  (with `permissions=["change"]`)?

### F01: gap-review execution notes (Agent 2, 2026-10-18)
Results are in `specs/F01-tenancy-provisioning.md` § Gap-review results; evidence `evidence/F01/gap/`.
- **Product questions above, now confirmed by execution:** copy = replace (TC-153: the target's
  stored `families: false` was dropped); `XXX` and `ZZZ` pass `clean_currency` (TC-157); no console
  action resends a first admin's invite (TC-168). Still owner questions, not defects.
- **Cross-site form POSTs accepted (record for F02's CSRF policy, TC-160 (b)):** reset, reset
  confirm, the three code endpoints, resend-verification, verify-email, registration, consultations
  `public/book/` and `public/manage/<token>/{pay,reschedule,review}/`, and the pay-link checkout all
  accept a form-encoded POST with `Origin: http://evil.example`. None creates a session (no login
  CSRF), and the beacons refuse it with 415.
- **Misleading counts:** Suspend/Reactivate report "Suspended 1 academies." / "Reactivated 1
  academies." for an academy already in that state (TC-165). Cosmetic; same family as QA-010.
- **Disabling the primary custom domain** makes the subdomain primary even when another custom domain
  (`qa-academy.test`) is active (TC-167). Probably intended (the subdomain is the safe fallback);
  owner to confirm.
- **Forged `copy_from` values** (`1`, `99999`, `abc`) give "No action selected." instead of "Choose
  the academy to copy the features from." because the action form is invalid; nothing changes.
  Forged-only path, not a defect.
- **Test-only proposals (Agent 3):** a pytest that walks `admin.site._registry` with a view-only staff
  user and asserts no action is offered (would have caught QA-002 and QA-013); the TC-170 FAKE pytest
  (invite send raises after commit); a dummy-task pytest for the beat actions.
- **Correction (Agent 2, gate 2, 2026-10-18):** TC-159 and TC-169 had not actually been executed in the
  gap-review run (no evidence, no log result), although the addendum said so; the real count then was 20
  executed (PASS 16, FAIL 4). Both were run at gate 2 (REAL, Playwright `--workers=1 --retries=0`) and pass:
  `evidence/F01/gate-2/playwright-tc159.txt`, `tc169-abort.txt`. TC-169 UX recorded: staff who abandon the Add
  page get no success message, although the server finishes provisioning (one academy, one invite).
- **Stale `*_node_modules` volumes confirmed (gate 2):** the marketing container had exited at start-up
  (`EACCES rmdir /app/node_modules/.vite/deps`): `etqan_tutor_marketing_node_modules` was created on
  2026-10-12 by the pre-QA image and is root-owned, while the image now runs as `app` (501:1000). This is
  the case predicted in the QA-001 row above. Removing the regenerable `.vite` cache brought the site back
  (vite's dependency optimiser still logs EACCES, but SSR serves 200). It strengthens the proposal there: a
  documented volume recreate, or a volume-ownership fix-up in the dev entrypoint (owner approval).
  Evidence `evidence/F01/gate-2/marketing-recovery.txt`.

### F08
- **Zoom (BLOCKED live):** meeting creation, pool host booking, host/start link from Zoom, `meeting.ended` webhook and `etqan_billing` metering have no credentials. Only FAKE (pytest monkeypatch) cover; TC-018 checks the access rules and the no-credentials fallback only.
- **Jitsi:** link generation is REAL; whether the room opens on meet.jit.si is not tested.
- **"Late" attendance** is not a supported status (present/absent/excused only). Owner to confirm if it is wanted (S9).
- **Notifications from sessions** (`sessions_starting`, `sessions_running_late`, `absences_marked`, `reports_missing`) are driven by the notifications per-minute scan and are not covered by F08; belong to the notifications feature.
- **Payroll lock end to end** needs payroll switches and rates set up; TC-003/004 depend on F-payroll data. Dashboard UI beyond the TC-001 smoke (simplified view, archive screen, revert dialog) is not exercised.
- **Clock-dependent windows** (24h missing-report threshold, 10-minute supervision window, 15-minute early stamp) are tested by creating sessions at the right offsets, not by freezing time.
- **Gate checklist (Agent 2, gate 2026-10-19):**
  - Roles: admin, staff no codes, staff with `student.view` only, supervisor, teacher, second teacher, student, parent, anonymous,
    impersonating admin (TC-011, 012, 016, 018, 020, 024). No untested role.
  - Tenant isolation: qa <-> qaother on 16 session routes + bulk mixed ids + cross-host cookies + CSV (TC-013); gate G1 re-checked
    `subscriptions/84/` from qaother → 404 and from a foreign student → 404 (`gate/g1-overconsumption.txt`).
  - Money: consumption matrix incl. both academy switches (TC-002), extra/pays_teacher pay in integer minor units (TC-003), payslip
    lock on every write path (TC-004), retroactive re-mark (TC-027). Gate G1 (cheap, was missing): marking past the package total
    gives used 9 / remaining −1 / `extra_sessions` 1 / progress 1.0 = DB count 9, by design (`rules.derive`, extra = max(0, −remaining));
    undo + delete restores 1/7 exactly, 0 rows left.
  - State transitions: scheduled/completed/cancelled/at_disposal, make-up freeze, postpone incl. DST, archive, revert (TC-005..010,
    019..021, 025, 026). Nothing cheap left to execute.
- **Still not covered (documented, not cheap):** live Zoom (BLOCKED); notifications from sessions (notifications feature); dashboard
  screens beyond the 3 smoke cases (simplified view, archive screen, revert dialog, Arabic/RTL); `late` status (S9, owner); whether an
  over-consumed package (negative remaining) should warn the office or block marking (by design today; owner to confirm, links to the
  F06 QA-039 double-consumption risk); time-frozen clock windows.

### F03
- **Roles editor UI matrix**: only one end-to-end UI smoke (TC-023); per-route `PermissionGate`/`NoAccess` for every dashboard route is not walked (API matrix TC-008/009 covers the server side).
- **Per-feature `FeatureOn` for all 88 switches**: only sampled (invoices, payment_receipts, quick_translate, system_status, supervision, families, quick_login, parents). Each feature's own spec owns the rest.
- **`feature-off = 403` in the brief**: code and docs say 404; spec asserts 404 and reports the mismatch (S7). Owner to confirm intent.
- **Quick-login links by email/WhatsApp (S-11)**: mail goes to mailpit (REAL sink); WhatsApp delivery is BLOCKED (no credentials).
- **Etqan staff editing switches in the Django admin**: F01/F02 territory, not repeated.
- **Themes**: browser-local (`localStorage`), no backend; checked only in the optional smoke TC-025. Visual palette contrast not judged.
- **2000-row translation cap and 1-hour stale `JobRun`**: need direct SQL/shell seeding; run FAKE (not through normal UI).
- **Suspended-academy system-status run (`academy_context`)**: FAKE direct task call at best.
- **Settings concurrency (S5)**: race observed statistically only; cannot be forced deterministically from the API.

### F06
- **Celery beat itself:** the hourly `scheduling.run_daily` schedule and `provision_meetings` are called as functions, not through beat/worker timing. The clock-driven path (a real hour passing) is untestable in a short run.
- **Real time passing:** expiry after grace, pause start/end across midnight and the DST change on 2026-10-29/30 need the clock; we create past-dated subscriptions and, for DST, use `POST /schedule/generate/ {from,to}` over the date range instead.
- **Zoom/Jitsi meeting links and WhatsApp/push notices** from running-low/expired subscriptions: BLOCKED (no credentials); only the notice reads are checked.
- **Online payment of the invoices a subscription issues:** out of F06 (billing/gateways feature).
- **Concurrency beyond two parallel requests** (lock order, deadlocks across bundle actions): only the two-way renewal race (TC-016) is run.
- **Spanish/Arabic RTL rendering of catalogue and scheduling screens:** not covered (UI smoke is English only).
- **Gate checklist (Agent 2, retest 1, 2026-10-19):**
  - Roles: admin, staff with catalogue+subscription codes (role 32), staff view-only (role 33), staff no codes, supervisor, teacher,
    student, parent, anonymous (TC-026..028); retest re-checked teacher 403 on create. No untested role.
  - Tenant isolation: qa ↔ qaother (TC-004, TC-027 id collisions, cleanup counts); retest G1 on the touched endpoints: qaother
    renew/generate with a qa id → 404, qaother Today board empty, qa cookie on the qaother host → 403 (`retest-1/gate-checks.txt`).
  - Money: bigint minor units, invoice per subscription in the subscription currency, country prices (TC-005..009, TC-006 UI);
    retest: one invoice per new subscription/renewal at the package price (6/6). State transitions: active/paused/expired/cancelled,
    renew/cancel-renewal/archive, pause past renewal, DST generation (TC-010..017, TC-029, TC-014 UI rerun).
  - Nothing cheap left to execute.
- **Still not covered (documented, not cheap):** the dashboard display of create/renew conflicts (ETQAN-QA-043, P3); re-anchoring on
  a timezone change (QA-041 proposal) and the one-lesson design change after an early renewal (QA-039 proposal) wait for the owner;
  deactivation during an active substitution is covered only by the unit test `test_an_active_substitute_still_covers_a_deactivated_teacher`;
  conflict-row payload size/queries for a teacher with many clashes not measured (lean mode dropped performance).

### F10
- **No clock control on a live stack:** `month_over` and `paid_on` use the real date (today 2026-10-18), so the exact month-end boundary in the academy timezone can only be tested with `occurs_on` dates on 09-30 and 10-01, not by moving the clock. The pinned-clock unit tests (`payroll/tests/test_issue.py`) are the only coverage of the instant-level boundary.
- **No real payout rail:** paying a payslip or withdrawal is a manual record (cash, bank transfer done outside the product). There is nothing live to test; every F10 case is REAL against the local DB only.
- **Exchange-rate estimate in projection:** `exchange_rates` uses the product's stored/simulated rates; no live rate provider is covered.
- **Quick-login (impersonation) sessions:** reachable only if the dashboard/dev quick-login is available on `qa`; TC-017/TC-021 mark the impersonation steps BLOCKED if it is not.
- **True multi-process races** (TC-007 step 2, TC-020) depend on how many Django workers the local stack runs; with one worker the race is serialised and proves less. Record the worker count in the evidence.

- **Gate checklist (Agent 2, retest 1, 2026-10-19):** roles: admin, staff (no codes, payroll read-only, create-only,
  update-without-view), supervisor, teacher (own/other), student, parent, anonymous, impersonated sessions (TC-022/023, 29
  endpoints × 11 roles, TC-017 S3) → no untested role. Tenant isolation qa ↔ qaother (TC-024) ok. Money: integer minor units,
  rounding, CSV sum = DB, expense per currency, net-0, races (TC-001/002/010/018/028/030) ok; retest added the `paid_on` lower
  bound for mark-paid and pay-to-balance (API + DB + UI). State transitions draft→issued→paid/paid-to-balance→acknowledged,
  withdrawals under_review→approved→paid / rejected / cancelled (TC-017/019/020/021) ok. Nothing cheap left to execute.
- **Still not covered (documented, not cheap):** clock-moved month-end instant and the "issue before month end" path (pinned-clock
  unit tests only); multi-worker races (local django worker count not instrumented, so races may be serialised); the dashboard
  date picker does not pre-limit `paid_on` to the payslip's month (server refuses, UI shows the field error - acceptable).
- **Test data note:** `e2e/qa/f10-payroll.spec.ts` TC-025/TC-026 consume their fixtures (March T13 slip, T8's unacknowledged paid
  slip); a rerun fails at the data precondition, not the product (gate run: S4 passed, TC-025/026 precondition failures).

### F05
- **Live delivery of invites and alerts:** Mailpit is a local sink (REAL SMTP), so deliverability to real mailboxes, SPF/DKIM and the WhatsApp/SMS invite channels are BLOCKED (no credentials); only content, link and count are checked.
- **Not exercised here:** 2FA admin-disable and quick-login link emails (F02 sign-in), staff role/permission definitions and the stronger-account guard (F03), invoices consuming the family payer (F09), self-registration (F10 registration), payroll use of `pay_currency` (F10 payroll). F05 checks only the identity side.
- **Dropped by lean mode:** the 300-student seed and any list/CSV performance measurement; pagination is tested on about 60 students only.
- **Private-file storage:** contracts use the local `FileSystemStorage`; the S3 private bucket, its `private/` prefix fallback and warning `etqan.W901` are untestable locally.
- **Time-based person rules:** age-group boundaries at the academy midnight (TC-025) cannot move the clock; static DOBs are used, unit tests (`test_ages`) hold the instant-level cover.
- **Multi-process races:** TC-023 depends on the number of Django workers on the local stack; with one worker the races are serialised. Record the worker count in the evidence.
- **Cross-feature scoping of a parent/student** (their sessions, invoices, chat) is covered by each owning feature, not F05.
- **Gate checklist (Agent 2, retest 1, 2026-10-19):**
  - Roles: admin, staff no-code, staff `codes`, staff partial codes, supervisor, teacher, student, parent, anonymous, impersonated
    session (TC-013/014/015/018/019/031). No untested role.
  - Tenant isolation: TC-016 both directions; gate G1 added the QA-032 path (an address taken in `qa` is free in `qaother`, a race
    there leaves `qa` row count unchanged). Ok.
  - Money: F05 only stores the teacher's pay currency and payout details (TC-003, TC-019); amounts are F09/F10. Ok.
  - State transitions: invite → active, active ↔ inactive, email none → set → pending → promoted, family active → retired, payer
    lifecycle, contract states, switches off → on (TC-001..012, 021, 026). Gate G2 added the parallel signed-in email change →
    ETQAN-QA-038 (P3).
  - Not cheap, still open: the race on `register_person` (self-registration) is covered by the shared `_build_person` code and its
    unit test only, not by an API race (self-registration is a separate feature); multi-worker races (one runserver process here);
    UI double-submit of Save not driven in Playwright (API race covers the backend).

### F02
- **Google sign-in (live):** no Google OAuth client. BLOCKED. The consent redirect and callback are not run; only the switch, `sign-in-options`, the write-only settings and encrypted storage are (TC-028). Logic stays covered by `test_google.py` with a faked Google.
- **SMS delivery:** `SMS_BACKEND=console` is FAKE. TC-021 reads the text from the logs. The Twilio path (`_send_twilio`, error handling) can't be exercised live. The 200-a-day cap is covered only by `test_the_academy_texts_at_most_its_daily_cap`.
- **Clock-dependent limits** (24 h quick-login token, 10 min reset code, 5 min pending sign-in, 1 h impersonation): the live stack can't move the clock. The spec edits session or `identity_resetcode` rows where possible (TC-013, 017, 022); the 24 h token expiry stays unit-test only.
- **Production cookie flags** (`Secure`, `SameSite=Lax`, `SESSION_COOKIE_SECURE`) are set only in `config/settings/production.py`; the dev stack can't show them (TC-029 records the dev values).
- **Concurrency races** (double link exchange, in-flight 2FA attempts, concurrent reservations) depend on the worker count; covered by existing `test_concurrent_exchange_signs_in_once` and `test_in_flight_*`.
- **Idle session timeout:** none exists (Django default 14 days). Product decision, not a test gap.
- **Etqan staff console login** (public-schema Django admin) belongs to F01; none of the identity routes exist on the base domain.

- **Gate checklist (Agent 2, retest 1 + gate, 2026-10-19):** P1 risks of F02 rechecked for gaps.
  - Roles: admin, staff (with/without codes), supervisor, teacher, student, parent, Etqan staff, anonymous are all exercised (TC-016, 026, 014, 019, 025); the QA-017 fix was retested for the admin actor, the staff actor (role-code removal) and the parent switch. No untested role.
  - Tenant isolation: TC-024 covers sessions, credentials, every token kind and counters across `qa`/`qaother`. The QA-017 middleware deletes only the key the same request's authenticator recorded, through `request.session` on the current tenant's schema; a qaother quick-login refusal was not run live because qaother has no student (would need a new fixture). Accepted as a gap: low risk, structural, and the `django_session` table is per schema.
  - Money: none in F02 (no money paths).
  - State transitions: switch off→on (quick_login, parents), role code removed→restored, deactivate/reactivate (TC-006), 2FA on/off (TC-012), password changed (TC-017 g1) all covered; after the fix every refused session stays ended (retest-1).
  - Not re-run at the gate: `pytest etqan/tenants` (≈25 min; Agent 3 ran platform+tenants, 423 passed, `fix-cycle-1/pytest-platform-tenants.txt`). Agent 2 re-ran identity 861, platform 226, access (below).
- **PROPOSAL-accepted (owner approval), ETQAN-QA-018 sub-part:** change password and reset by link still accept the current password as the new one. No `AUTH_PASSWORD_VALIDATORS` entry, doc or spec forbids reuse; NIST 800-63B does not require it. Risk: low (a person "rotating" after a suspected leak could keep the same value). If wanted: a check in `services._validate_new_password` comparing `user.check_password(new)`; no migration, no API shape change.
- **Owner heads-up, not F02:** `pytest etqan/access` 2049 passed, 1 failed: `test_routes.py::test_every_route_declares_its_code_or_is_named_exempt` lists 6 new `api/v1/site/admin/hero-slides/` routes with no permission-code table entry. They come from the owner's in-progress `etqan/site/*` work (not reviewed or touched by QA; `evidence/F02/retest-1/pytest-access.txt`).
- **Open P3 carried forward:** ETQAN-QA-019 (500 on non-object JSON body), ETQAN-QA-020 (self-service reset for accounts that can't sign in). Lean mode fixes only P0–P2.

### F09
- **Live Stripe and PayPal:** no credentials. Checkout, return, webhook and capture run through the `GATEWAYS_SIMULATE` simulator (SIMULATED) and hand-signed Stripe events; real provider behaviour (3-D Secure, async payment methods, Stripe Connect `application_fee_amount`, PayPal order/capture/verify) is BLOCKED.
- **Provider refunds:** billing and wallet "refund" only mark rows; no provider API is called by design. A real money-back path is not testable and not built (see S2/S4 in the spec).
- **Scheduled jobs:** `gateways.expire_checkouts` (daily 03:20) and the minute `notifications.scan` overdue/new-invoice notices depend on the clock; covered by pytest only, not by a live clock run.
- **Academy-midnight boundaries:** `issued_on`/`paid_on`/revenue month near Cairo midnight need a controllable clock; TC-001 and TC-009 only prove them when run between 22:00 and 24:00 UTC.
- **Race tests** (parallel payments, double spend, double redeem) depend on the number of Django workers on the local stack; one worker serialises them and proves less.
- **Country-priced packages** (`country_pricing`), `donations` links and `recorded_courses` playlist codes are other features' switches and are not exercised here.
- **Email/WhatsApp content of invoice notices** belongs to the notifications feature; F09 only checks that a code-paid invoice produces no new-invoice notice.
- **Printed/PDF invoice fidelity** (fonts, RTL) is checked by eye in the UI smoke only.
- **Gate checklist (Agent 2, gate, 2026-10-19):** P1 risks of F09 rechecked for gaps.
  - Roles: all 9 roles plus Narrow staff, family payer P3 and other family covered (TC-012/013); gate G1 added the
    cross-family wallet path (404/403, DB unchanged). No untested role.
  - Tenant isolation: TC-014 both directions; no gap.
  - Money: per-currency minor units, fees, rounding, reconciliation, ledger and races covered; no gap beyond live providers.
  - State transitions: covered; gate G2 added feature off→on for `balances`, `system_codes`, `invoices` (404, writes refused, restored).
  - Remaining (not cheap): live Stripe/PayPal BLOCKED; clock-driven expiry/notices and Cairo-midnight boundaries; multi-worker races (above).

### SCN
- **Gate checklist (Agent 2, gate 2026-10-19 ~17:20Z):**
  - Roles: admin, staff office, supervisor, teacher T1/T2/T3, deactivated teacher, parent PA/PB, students SA1/SA2/SB1,
    qaother admin, anonymous (TC-001..013, 016). Gate G1 re-checked renew as T1 403, parent 403, qaother cookie on the qa
    host 403. No untested role.
  - Tenant isolation: TC-005 chain (both directions, cross-host cookie, payload identity), TC-010/011 FAM-B 404; gate G1
    renewal invoice 153 → PB 404, T1 403, qaother 404; qaother schema holds only its own TC-005 fixture (`scn-other-s`).
  - Money: TC-015 partial/wallet/full, TC-016 payslip 45000 + expense, TC-018 revenue/receivables/wallet reconcile. Cheap
    check that was missing: **G1 renewal chain** (TC-003 only ran regenerate, not renew). SUB2 86 → renewal 89 (starts
    11-19, `renewed_from` 86), exactly one invoice 153 (150000 EGP, payer PA = family payer = SUB2 invoice payer), 0
    same-instant duplicates, second renew 409 `scheduling.already_renewed`, delete refused 409 until void; cleaned up (void +
    delete, 0 renewal rows). REAL, `evidence/SCN/gate/g1-renewal.txt`, `g1b-renewal.txt`. **G2 invariants re-check at gate
    time:** 0 paid/unpaid/overpaid status mismatches academy-wide, INV1 paid 150000 = payments, 0 wallets ≠ entries, payslip
    43 paid 45000 = 9 lines + 1 expense 45000, M1..M9 locked / M10..M11 not, no 5xx (`gate/g2-invariants.txt`).
  - State transitions: subscription active/cancelled/renewed, session scheduled/completed/cancelled, invoice
    unpaid/partial/paid/void, payslip draft/issued/paid/acknowledged (TC-003..016 + G1). Nothing cheap left.
- **Observation (by design, owner question):** `sessions_used` is derived live from the current
  `absent_consumes_session` / `excused_consumes_session` switches (`docs/features/subscriptions.md`, `rules.derive`). The
  SCN run measured SUB3 7/1 with absent=off; after settings were restored (absent=on) the same closed September month
  reads 8/0 (M8 absent now consumes) and SUB1 2/6. Payroll is unaffected (lines locked). Flipping the switch therefore
  rewrites the package balance of past, closed months. Owner to confirm this is wanted or whether the switch should apply
  only to sessions marked after the change.
- **Still not covered (documented, not cheap):** renewal session generation for 89 (the 62-day generate cap refused a
  10-19..12-31 window; renewal non-duplication is covered by F06 QA-039/QA-042); scenario A (new academy setup) and F
  (multi-tenant security) are outside this run; time-frozen month closing; notifications other than the absence notice;
  live payment gateways (F09 SIMULATED); Arabic/RTL dashboard beyond the two smoke specs; 300-student seed and performance
  (lean mode drop).

## F03 (Agent 2, execution run 1, 2026-10-19)
- TC-025 (themes/language per browser, P2) not run in lean mode.
- TC-018 step 3 (duplicate settings singleton row) not run.
- TC-010 payslip row scope not exercised (no payslips in `qa`; covered by F10).
- Cross-academy role-id probe in TC-006 not meaningful: role ids are per schema.

### F03
- **Gate checklist (Agent 2, retest 1 + gate, 2026-10-19):** P1 risks of F03 rechecked for gaps.
  - Roles: admin, staff without codes / with partial codes / role editor / all 881 codes, supervisor preset, teacher,
    student, parent, anonymous exercised (TC-001..010, 014, 026, 027); retest 1 re-ran the retire/restore guard for
    the staff editor (stronger role, own-held role, Supervisor preset) and the admin. Etqan staff switch editing is F01.
    No untested role.
  - Tenant isolation: TC-011 (roles, cookies, Host replay, sign-in, currency) plus retest step 19 (Ed's cookie on
    `qaother` 403, qaother roles unchanged). Cross-academy role ids are per schema, so not meaningful.
  - Money: TC-016/TC-028 (currency switch never re-denominates; totals per currency in exact minor units); settings
    fields that drive money (auto-invoice, due days, consumes-session) persist (TC-015/017). Residual: QA-022 (non-ISO
    currency, P3) and QA-023 (concurrent PATCH lost update, P3), both OPEN, lean mode fixes only P0–P2.
  - State transitions: role retire/restore (staff and admin), code change on a live session, staff deactivate/
    reactivate, feature switch off/on, impersonation start/stop, job run queued→ok/failed (stale) all covered.
  - Not executed (documented): TC-025 (P2 themes/language per browser), TC-018 step 3 (duplicate singleton row),
    payslip row scope (F10), dashboard error display for the new retire 403 (API-only retest; the existing UI smoke
    passes 2/2).
- **PROPOSAL-accepted (owner approval), ETQAN-QA-021 rename sub-part:** staff with `role.update` can rename a stronger
  role. No access changes (verified live). Risk: misleading label for an admin (P3 level); admin can rename back. If
  wanted: extend the `update_role` guard to `name_*` for staff (one line, no migration, no API shape change).
- **New P3:** ETQAN-QA-024 (staff editor can retire their own only role and lock themselves out; rule 5 analogue).
- **Owner heads-up, not F03:** `pytest etqan/access` still has 1 failure from the owner's `etqan/site/admin/*` routes
  (`evidence/F03/retest-1/pytest-access.txt`).


## M02 manual, Agent 3 fix cycle 1 (2026-10-27): proposals, not built
- **PROPOSAL (API change), ETQAN-QA-049:** `POST identity/login/` answers a wrong password with the bare English text
  `{"non_field_errors": ["Invalid credentials."]}` and no `code`. Fix 1 maps that exact text to `auth.invalidCredentials`
  in `LoginForm` (the same approach it already uses for "not verified"). The durable fix is additive: add
  `"code": "identity.invalid_credentials"` (and `identity.email_unverified` for the unverified 400) and let the dashboard
  key off the code. No migration.
- **PROPOSAL (refactor), ETQAN-QA-061:** no Radix `Direction.Provider` wraps the app, so every Radix primitive defaults
  to `ltr` under an Arabic page. Fix 1 passes `dir` to `RadioCardGroup` only (the reported component). `DropdownMenu`
  (user menu, row menus) has the same default. Wrapping the app in `Direction.Provider` from `DirectionProvider` would
  fix it everywhere, but it changes the alignment of every dropdown in Arabic, so it needs its own pass with screenshots.
- **PROPOSAL (refactor), ETQAN-QA-048 / QA-011 family:** Fix 1 gives every identity schema (login, 2FA, forgot, reset,
  change password, add email, set primary, profile) i18n keys rendered through `useFieldError`. About 25 other
  feature schemas still use bare `z.string().min(1)` / `z.email()` without a key, so they can show zod's English
  default. A global `z.config({ customError })` that returns `common`-level keys, plus `useFieldError` in every
  `Field`, would close the family. Needs a sweep across areas.
- **Follow-up (small), ETQAN-QA-060:** Fix 1 changes `Input` (`[unicode-bidi:plaintext]` + `text-start`) and isolates the
  name in the header `UserMenu`. `Textarea` and other places that print a user name in Arabic chrome (tables, cards)
  were not changed.
- **Agent 2 gate M02 (2026-10-27):** all four above are **PROPOSAL-accepted** (P3 only, none blocks M02). QA-049 interim mapping is acceptable until the API code lands; QA-061 provider and the QA-048 schema sweep need their own cross-area pass with screenshots; QA-060 follow-up: Latin names in Arabic tables still read e.g. "cmd+" (seen on staff students list, `qa/manual/screens/M02/fix/g-smoke-staff-ar.png`).
- **PROPOSAL (API change), M02-F-021 / ETQAN-QA-065 (Agent 2 final gate M02, 2026-10-27):** the "Last sign-in" line on student/teacher pages has no date or time; B9b S-8 defines it as "device · IP · zone" and `identity/api/payloads.py::user_payload` has no `last_login`. If wanted: add `last_login` (ISO, UTC) to the people payload and show it first, formatted in the academy time zone. P3, not blocking; the Arabic order of the existing parts is filed separately as ETQAN-QA-065 (easy).

## M06 manual, Agent 3 fix cycle 1 (2026-10-27): proposals, not built
- **PROPOSAL (refactor), ETQAN-QA-204 family:** the root cause (an `sr-only` header label is `position:absolute`;
  inside a non-positioned `overflow-x-auto` scroller it escapes and widens the page to the table's width in RTL) is
  fixed only on the subscriptions list (`relative` on its scroller). About 19 other tables use the same
  `overflow-x-auto rounded-lg border` wrapper with `sr-only` text inside (`SessionsList`, `TrialsList`,
  `MySupervision`, `StaffList`, `RolesList`, `FamiliesList`, curriculum, recorded, homework, certificates, …). A
  shared `TableScroller` component (or `relative` on that wrapper class everywhere) would close the family; needs a
  375px RTL sweep with screenshots.
- **PROPOSAL (API change), ETQAN-QA-206 family:** `scheduling` services raise `ValidationError` with English prose and
  no `code` (`add_pause` "End the pause on or after its start.", availability `_validated` "End the window after it
  starts.", "Choose a day from Monday to Sunday.", "This window overlaps another one on the same day.", …). Fix 1 checks
  the two reported cases in the dashboard before sending, so they never reach the server. Durable fix (additive, no
  migration): give these field errors a `code` (`scheduling.pause_order`, `scheduling.window_order`,
  `scheduling.window_overlap`) and map codes to keys in `errorText`/`applyServerErrors`. The overlap message is still
  English in Arabic today.
- **Follow-up (small), ETQAN-QA-207 family:** fix 1 adds `scheduling/bits.ZonedDateTime` (day and time each in
  `<bdi>`) and uses it on the trials list and trial page. Other places still join an Arabic `dayIn(...)` and
  `wallTime(...)` in one string or under `dir="ltr"` and can show the same "2720:00 2026/10/" scramble:
  `MissingReports.tsx` (`when`), `registration/admin/bits.ts`, `SessionPage.tsx` (postponed-from `when`),
  `FamilySessions.tsx`, `TeacherSessionTable.tsx`, `MySupervision.tsx`, `SessionSupervision.tsx`. Not changed (not
  reported, other areas); worth one sweep.
- **Follow-up (small), ETQAN-QA-211:** the bundle page now has the Subscriptions item highlighted (new `NavItem.also`),
  a back link and a "<kind> bundle" card title. The page header and browser title are still the route's generic
  "Subscription bundle": naming the owner there needs the route to read the bundle (its query is cached, so cheap), a
  small change to `routes/_authed/scheduling.bundles.$bundleId.tsx`.
- **Agent 2 gate decision (2026-10-27):** all four are **PROPOSAL-accepted**, P3 only (no P0-P2 behind any of them). The 204 family needs a 375px RTL sweep of the other tables. The 206 family (error codes) also covers the window-overlap message, which is still English in Arabic. The 207 family is a sweep of the other day+time joins. The 211 header/title naming is cosmetic. The fixes in cycle 1 are VERIFIED and do not depend on these proposals. Separate from them, the expanded calendar's name wrapping is filed as ETQAN-QA-216 (easy P3, next fix cycle).


## M04 manual, Agent 3 fix cycle 1 (2026-10-27): proposals, not built
- **PROPOSAL (API change), ETQAN-QA-157:** `identity.services` (`This email is already in use.`, 4 places) and
  `platform/uploads.check_upload` (`This type of file is not allowed.`) raise `ValidationError` with fixed English text
  and no `code`; the backend has no `.po` translations. Fix 1 maps those two exact sentences to `errors.server.*` keys in
  one dashboard table (`src/lib/server-messages.ts`, used by `useFieldError`, `errorText` and `ContractDialog`). The
  durable fix is additive: give these errors codes (`identity.email_in_use`, `uploads.file_type`, `uploads.too_large`
  with `max_mb`) and key the dashboard off the code, retiring the table. No migration.
- **PROPOSAL (API change), ETQAN-QA-172:** `POST identity/verify-email/` answers a bare 200, so the confirmation page
  can't tell "you can sign in now" from "your registration waits for approval". Fix 1 rewords `auth.verified` so it is
  true in both cases. Durable fix: return `{"can_sign_in": user.is_active}` (identity's own field, no registration
  import) and show "تم تأكيد بريدك. سنراسلك عندما توافق الأكاديمية على تسجيلك." when false. No migration.
- **Follow-up (small), ETQAN-QA-151:** Fix 1 folds Arabic spelling variants (أ/إ/آ/ٱ→ا, ة→ه, ى→ي, tatweel and harakat
  dropped) in the people search (`?q=` on students/parents/teachers/admins) and the families search
  (`etqan/platform/search.py`, computed in the query; no stored column, no migration). Other searches (contracts, study
  groups, subscriptions, invoices, library, chat contacts) still use plain `icontains`; each can adopt
  `with_folded`/`folded_q` in one line. If lists grow large, a stored normalised column with a trigram index would be
  the next step (migration, owner approval).
- **Follow-up (small), ETQAN-QA-156:** the button now reads "إعادة إرسال الدعوة". The create toast still says only
  "تم الحفظ."; saying "Invite emailed" there would need the create response to say whether an invite went out (it is
  skipped for an email-less student), so it is left for the people-forms pass.
- **Note, ETQAN-QA-155:** `es/notifications.json` has no `preferences` section at all (falls back to English); not part
  of the bug, left for the Spanish sweep.

## M03 fix-1 proposals (Agent 3, 2026-10-27T19:51:23Z)
- **ETQAN-QA-102 follow-up (backend, not built):** notification text stores amounts as `1,500.00 EGP` and dates as ISO in every language. Proposal: format `amount`/`due_on`/`from`/`to`/`time` per recipient language in `notifications/text.py` (Arabic currency name/digits policy to be decided by the owner), or store the raw facts and render on read (changes spec N8-4 "rendered once"). Needs a spec decision; isolation alone (done) already fixes the scrambled order.

## M08 manual, Agent 3 fix cycle 1 (2026-10-28): proposals, not built
- **PROPOSAL (API change), ETQAN-QA-314:** the New invoice form lists students from `GET people/students/`, gated by
  `student.view_any`, so a billing clerk with `invoice.create` alone can never issue an invoice. Fix 1 (dashboard only)
  stops the silent 403: without `student.view_any` the form says why ("Issuing an invoice needs permission to view
  students…") instead of an empty picker, the subscription list is asked only with `subscription.view_any`, and the
  invoice page links "Open the subscription" only with `subscription.view`. Durable fix: a billing-owned lookup
  `GET billing/students/?q=` gated by `invoice.create` (id + full name only, active students, through
  `identity.services`), like `billing/payers/`; or a role-editor hint that `invoice.create` needs `student.view_any`.
  No migration. Owner decision on which.
- **PROPOSAL (product decision), ETQAN-QA-307 currency part:** English shows USD as "$85.00" (Intl's symbol) next to
  "EGP 1,200.00"/"KWD 3.000" (codes, no English symbol); Arabic shows "US$". Making it uniform means a
  `currencyDisplay` choice in `lib/money.formatMoney` that changes every amount in the app (e.g. "code" everywhere, or
  "USD" only for ambiguous dollar symbols). Not built: app-wide display change. Fix 1 did the table layout part.
- **Follow-up (small), ETQAN-QA-313:** the server freezes checkout descriptions in English at start
  (`wallet/topup_purpose.py` "Wallet top-up · <name>", `recorded/purpose.py` "Recorded course <code>",
  `consultations/purpose.py` "Consultation <ref>"). Fix 1 translates them on the Online payments list from `purpose`
  (the frozen prefix is replaced, the name/code kept). A durable fix would store only the subject and let each reader
  render the label; the CSV export still carries the English text.

## M12 manual, Agent 3 fix cycle 1 (2026-10-28): proposals, not built
- **PROPOSAL (UI reshape), ETQAN-QA-506 follow-up:** fix 1 translates the anti-escalation refusals
  (`access/services.py`), shows the refusal above the matrix plus a toast, and names the changed codes the staff editor
  doesn't hold ("صلاحيات لا تملكها: الفواتير: عرض الكل."). Durable: for a staff editor, disable (or mark) the boxes of
  codes they don't hold, from `me.permissions`, so the refusal can't happen. Also a stable `code` on these 403s
  (`access.unheld_add` etc.) instead of matching the English sentence in `lib/server-messages.ts` (additive API change).
- **PROPOSAL (list order), ETQAN-QA-508 follow-up:** fix 1 only fixes the Arabic status word ("موقوف"). Active roles
  first: `access.services.roles_queryset()` orders by `name_en, id`; ordering by `-is_active, name_en, id` (or a
  default "Active" filter in `RolesList`) changes the list's API order and the seed/tenant tests that read it; plus a
  name search (`?search=`). Owner decision.
- **PROPOSAL (API), ETQAN-QA-510 follow-up:** `JobRun.error` stores English text ("Timed out.", "Academy
  suspended.", or an exception's text). Fix 1 maps the two fixed reasons to i18n keys in `SystemStatusPage`. Durable: an
  `error_code` field on `JobRun` (migration) or fixed codes in `error`, with the exception text kept for staff only.
- **PROPOSAL (API), ETQAN-QA-515 follow-up:** the `notifications.bad_placeholder` 400 carries an English field
  sentence. Fix 1 shows one translated message under the field and names the bad `{name}` from the client's own copy of
  the placeholders. Durable: return the bad names as data (`{"code": …, "names": ["foo"]}`) so no sentence is parsed.
- **Note, ETQAN-QA-512:** the server now refuses a text emoji on create/change ("Use one emoji, like ⭐."); older tags
  that already hold text (e.g. "ب", "abc" on qa) keep it until edited. A data clean-up would be a one-off script.
- **Note, ETQAN-QA-505:** the hint explains view vs view all; whether ticking "view" alone should ever be offered for a
  list-only resource is part of ETQAN-QA-504's editor reshape.

## M15 manual, Agent 3 fix cycle 1 (2026-10-28): proposals, not built
- **PROPOSAL (backend rule), ETQAN-QA-451 follow-up:** fix 1 makes an unpaid self-booking read "بانتظار الدفع" with
  "ادفع الآن" on the family list (from the existing `actions.pay`), so it can't pass for the paid one. Still open:
  `consultations/services/unpaid.py:_checkout_open` skips any request with a `pending` checkout, and an abandoned Stripe
  checkout stays `pending` until `gateways.expire_checkouts` (~25 h), so abandoned holds stay listed (family and office
  queue) for a day. Options (owner decision, consultations.md §5 says "skipping any with an open checkout"): (a) when the
  hold runs out, expire the request's own pending checkouts at the provider (`gateways.services.expire_local` /
  provider expire) and then cancel; or (b) cancel on hold expiry and let a late `complete` refund or move the money
  to the wallet. Either changes a documented rule and the gateway flow; needs tests in `test_unpaid.py` and the
  purpose's `complete`.
- **PROPOSAL (API), ETQAN-QA-464 follow-up:** `clean_contact` raises English sentences with no `code`
  ("Enter a WhatsApp number.", "Enter the person's name.", "Enter a valid email."). Fix 1 marks WhatsApp required when
  the account has no phone, blocks Pay until it is filled and shows the WhatsApp refusal from the catalogue. Durable:
  codes such as `consultations.whatsapp_required` on these field errors.
- **Note, ETQAN-QA-459:** fix 1 adds an additive read-only `starts_at` to the review endpoints' session object
  (`learning/api/serializers.py:_session_ref`); no migration, no input change.

## M05 manual, Agent 3 fix cycle 1 (2026-10-28): proposals, not built
- **PROPOSAL (backend behaviour), ETQAN-QA-562 follow-up:** the 114 Qur'an chapters are loaded only by "مزامنة السور"
  (`learning/services/quran.py:sync_chapters`, curriculum.md "Reference data"); nothing loads them when an academy is
  created, so a new academy's level-topic surah picker is empty. Fix 1 shows a hint in the picker with a link to the
  Qur'an chapters page. Durable: call `sync_chapters` from academy provisioning (`tenants` create flow, inside
  `tenant_context`) and once for existing academies (a data step, e.g. a management command over all schemas). No
  schema change, but it changes the documented "load by hand" behaviour, so it needs the owner's nod.
- **PROPOSAL (API), ETQAN-QA-561 follow-up:** the level-topic verse rule raises
  `f"Verses run from 1 to {verses_count}, first to last."` (English, with a number) and the recorded slug rule
  "Use lower-case letters, digits and dashes." with no `code`. Fix 1 checks both in the dialog before saving (Arabic
  text) and maps the fixed sentences in `dashboard/src/lib/server-messages.ts`. Durable: codes such as
  `learning.verses_out_of_range` (with `last` as data) and `recorded.slug_invalid` on these field errors.
- **Note, ETQAN-QA-570:** `consultations/services/products.py` now checks "a description in Arabic or English" itself
  before `full_clean`, so the API answers "Write a description in Arabic or English." on `description_en` (same field
  as before) instead of Django's translated constraint text; the dialog also checks it before sending.
- **Note, ETQAN-QA-567:** the same bare "https://" in Arabic text is in `ar/website.json` (`url`, `urlInvalid`, social
  `tip`) and `ar/scheduling.json` (`urlInvalid`); outside M05, left for those areas.
- **M05 gate (Agent 2, 2026-10-28) on the above:** 562 follow-up = PROPOSAL-accepted as a backlog item for the owner
  (P3, behaviour change, not a blocker: the in-picker hint fixes the confusion); 561 follow-up = PROPOSAL-accepted
  (API codes, P3, deferred); 567 note acknowledged (other areas' strings). None is P0–P2.

## M16 manual, Agent 3 fix cycle 1 (2026-10-28): proposals, not built
- **PROPOSAL (API + new site sections), ETQAN-QA-770 (P2):** the home page never shows live courses, packages or
  teachers, and the admin switches "إظهار الدورات / الباقات / المعلمين" (`landing.show_courses/packages/teachers`) do
  nothing. Root cause: the public site payload (`site/api/serializers.py:landing_payload`, `sections.courses/packages/
  teachers`) carries only the three flags; there is no public catalogue/teacher payload, and
  `marketing/src/pages/[lang]/index.astro` renders only `sections.testimonials` and `sections.contact` (academy-sites
  spec §3.2 marks these sections as Plan 3). Durable: (1) public read-only endpoints (or fields in the landing payload)
  for active courses (name pair, description, image), active packages (name, lessons, price minor + currency) and
  teachers who opt in to be listed (name, photo, short bio; no contact data), each behind its switch and the site
  status, served through `catalogue.services` / `identity.services` (no cross-app model import); (2) three marketing
  sections + cards. Needs the owner's call on which teacher fields are public (privacy). Interim option (owner's
  choice, not built, the form belongs to M13): hide the three switches or mark them "قريبًا" in `HomePageForm.tsx`.
- **PROPOSAL (API), ETQAN-QA-757/756/761 follow-up:** registration's field refusals ("Invalid code.", "Choose a date
  from today on.", "Choose a time in the future for the call.", "A date of birth can't be in the future.") carry no
  `code`; fix 1 maps the fixed sentences in `dashboard/src/lib/server-messages.ts` (and the form checks dates itself
  first). Durable: codes such as `registration.code_invalid`, `registration.date_past`, `registration.dob_future`.
- **Note, ETQAN-QA-772:** `site/api/views.py:InquirySerializer.validate_phone` now refuses free text (digits with an
  optional +, spaces, dashes, dots, brackets; 6-15 digits). Local numbers ("01001234567") stay accepted, as the public
  form is not the registration form. No model or migration change.
- **Note, ETQAN-QA-756:** `registration/services.py:_clean_preferences` now refuses `start_on` before the academy's
  yesterday (one day of slack for a registrant in a zone behind the academy) and `intro_call_at` not after now. Input
  shape unchanged.

## M01 manual, Agent 3 fix cycle 1 (2026-10-28): proposals, not built
- **PROPOSAL (middleware behaviour), ETQAN-QA-804 rest:** a suspended academy's login header shows the host name
  because `tenants/middleware.py:SuspendedAcademyMiddleware` answers 403 to the public branding request too. Option:
  let the public, unauthenticated branding read (`site` branding/name endpoint) through for a suspended academy so the
  login keeps its name and logo. A policy call for the owner (what a suspended academy still exposes), so not built;
  fix 1 only translates the `tenant.suspended` message and shows it on the login at once.
- **Note, ETQAN-QA-801/802:** the confirmation step is a shared console helper (`etqan/platform/admin_confirm.py`,
  `templates/admin/etqan_confirm_action.html`); the domain actions (ETQAN-QA-010) can use the same helper later.
  `services.void` stays idempotent; the admin itself reports an already-void invoice.
- **Note, ETQAN-QA-812:** the help texts are set on the admin forms, not on the model fields, so no migration.
