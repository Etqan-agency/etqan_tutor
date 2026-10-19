# Feature inventory

Built from the code at backend adff9c9 and dashboard 5ed775d, plus `docs/features/*.md` (audit of
2026-10-17). Agent 1 refines each row when it researches the feature.

## Customer journey entry point
- Etqan's own sales site (`../etqan_tutor_website`, Astro) is in progress. Its forms post to
  `POST /api/v1/leads/`, which **does not exist yet** (no `etqan.leads` app). This is a known
  in-progress project and is recorded as a limitation, not a defect.
- So the journey starts where the product starts today:
  1. An Etqan staff member creates the academy in the Django admin
     (`etqan.localhost/admin/` → Academies → Add), or with `manage.py create_academy`.
  2. The first admin gets a set-password email.
  3. Etqan staff set the feature switches.
- There is no self-signup. `registration.md` covers students and parents joining an existing
  academy.
- The per-academy contact form (`POST /api/v1/site/inquiries/`) is the academy's own inquiry inbox,
  not Etqan's.

## Tier 1 (this campaign)
| ID | Feature | Backend apps | Dashboard areas | Switches | Docs |
|---|---|---|---|---|---|
| F01 | Tenancy & provisioning (+ dev env build, ETQAN-QA-001) | tenants (models, services, admin, middleware, `tls_allowed`, commands `create_academy` / `set_features` / `bootstrap_platform`), platform (`tenancy.for_each_academy` / `academy_context`, `frontend.frontend_url`, `features` registry, `permissions.FeatureOn`), and provisioning hooks in academy, site, identity and access; `etqan_billing.may_suspend` gates `etqan_defaults_suspended` | Django admin on `etqan.localhost/admin/` (Academies: add, change with 6 feature fieldsets, suspend / reactivate / copy-features actions; Domains: add, check DNS, make primary, disable); dashboard `/app/settings/features` (read-only); edge `caddy/Caddyfile.local` | none gate tenancy itself; it writes all 88 switches (7 default on, `free_sessions` / `public_links` unbuilt, 9 `requires` pairs) | tenancy.md, feature-toggles.md, runbooks/operations.md. Spec: `qa/specs/F01-tenancy-provisioning.md` |
| F02 | Sign-in | identity (allauth, mfa) | login, reset, verify, quick-login, account | two_factor, phone_login, quick_login, google_sign_in, code_reset | sign-in.md |
| F03 | Roles & permissions | access, platform.permissions | settings.roles, people.admins/staff | supervision | roles-permissions.md |
| F04 | Settings & switches | academy, tenants.features, systemstatus, translations | settings.* | themes, spanish, quick_translate, system_status | academy-settings.md, feature-toggles.md |
| F05 | People | identity, academy | people.* | families, parents, contracts | people.md, employment.md |
| F06 | Catalogue | catalogue | catalogue.* | country_pricing | catalogue.md |
| F07 | Subscriptions & scheduling | scheduling | scheduling.subscriptions/schedules/trials/bundles | trial_sessions, teacher_availability, study_groups, weekly_schedules, *_subscriptions, subscription_archive | subscriptions.md, scheduling-tools.md |
| F08 | Sessions & attendance | scheduling, integrations (meetings) | scheduling.sessions/today/supervision, teaching.sessions | session_reports, teacher_attendance, postponement, activity_log, session_archive, manual/extra/compensation_sessions, disposal_status, session_times, simplified_sessions, zoom_api | sessions.md, meetings.md |
| F09 | Student billing | billing, gateways, wallet, vouchers | billing.*, learning.invoices/wallet/codes | invoices, payment_receipts, online_payments, payment_links, balances, system_codes | billing.md, online-payments.md, wallet.md, vouchers.md |
| F10 | Teacher payroll | payroll | payroll.*, teaching.balance/payslips | incentives_deductions, student_teacher_rate, report_deductions, fixed_teacher_salary, payroll_rules, bulk_teacher_rates, teacher_balance, payslip_acknowledgement, salary_projections | payroll.md |

## Tier 2 (after the checkpoint, needs owner go-ahead)
- Notifications, email and WhatsApp, broadcasts, web push and PWA
- Chat
- Curriculum, levels, Qur'an chapters, homework and content, reviews and honour board
- Certificates
- Student reports and AI
- Recorded courses
- Consultations
- Registration and the waiting list
- Finance (expenses, donations, exchange rates)
- Library and private files
- Per-academy website and website content
- Etqan billing (metering and invoices)
- Integrations (Zoom, Stripe Connect)
- System status
- The full localization and RTL sweep
- The full accessibility sweep

## Feature switches (88): QA academy state
_Filled in during Phase 1:_ every built switch is on in `qa`, except where noted. `free_sessions`
and `public_links` are unbuilt, so they stay off.

## QA academies
Created by F01 Agent 2 on 2026-10-17. Never write to demo or other; use these instead.

| Academy | Subdomain / schema | How created | Timezone / currency | Admin (password) | Features |
|---|---|---|---|---|---|
| Etqan QA Academy (id 5) | `qa` / `academy_qa`, `http://qa.etqan.localhost/app/` | Django admin Add-academy form in a real browser (TC-011), invite accepted from Mailpit | Africa/Cairo / EGP, plan "QA Tier 1" | `qa-admin@qa.etqan.test` (`QA-Admin-2026!`) | defaults + stored `{"families": true, "invoices": true, "internal_chat": false, "online_payments": true}` (SETUP-6 "all built on" not applied yet) |
| Etqan QA Other (id 4) | `qaother` / `academy_qaother`, `http://qaother.etqan.localhost/app/` | `manage.py create_academy` (TC-026) | UTC / USD | `qaother-admin@qa.etqan.test` (`QA-Other-2026!`) | defaults (stored `{"internal_chat": false}`) |

QA people in `qa` (password `QA-People-2026!`, invites accepted): `qa-staff-nocode@` (role "QA No Codes", no codes),
`qa-staff-codes@` (role "QA Student View": student.view, student.view_any), `qa-supervisor@` (preset Supervisor),
`qa-teacher@`, `qa-student@`, `qa-parent@` (all `@qa.etqan.test`). Family "QA Family F01" (id 1, student QA student).

Etqan staff (public schema, `http://etqan.localhost/admin/`): `ops@qa.etqan.test` superuser (`QA-Etqan-Staff-2026!`),
`ops-view@qa.etqan.test` view_academy+view_domain only (`QA-Etqan-View-2026!`),
`ops-noperm@qa.etqan.test` is_staff, no permissions (`QA-Etqan-NoPerm-2026!`).

Throwaway academies (F01, cannot be deleted from the admin by design; suspended at the end of F01 execution):
| Subdomain | Purpose | Admin |
|---|---|---|
| `qa-tmp-1` (id 6) | suspension, defaults-suspended, custom domains (all custom domains left disabled; subdomain primary), timezone edit Asia/Riyadh on the Academy row | `qa-admin@qa.etqan.test` (`QA-Tmp1-2026!`) |
| `qa-tmp-tz` (id 7) | ETQAN-QA-003 evidence: timezone `Mars/Phobos`, currency `usd` (deliberately broken) | `qa-tmp-tz-admin@qa.etqan.test` (`QA-TmpTz-2026!`) |
| `qa-tmp-race-a` (id 8) | TC-061 double submit | invite not accepted |
| `qa-tmp-race-b` (id 10) | TC-062 race winner | invite not accepted |
