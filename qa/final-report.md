# Etqan Tutor QA: Tier 1 final report (2026-10-19)

The original Tier 1 scope is complete. It covers every core feature an academy runs on, plus the
integrated scenarios. Nothing has been committed or pushed. Every change is uncommitted, on branch
`qa/campaign-2026-10` in backend, dashboard and marketing, plus docs in the meta repo.

## Executive summary
- **All 8 Tier 1 features and the integrated scenarios PASSED the quality gate.** Agent 2 is the
  sole gate authority and retested every fix itself.
- **47 defects were filed:** 3 P1, 12 P2, 25 P3, 7 P4. **No P0** (data loss, outage or
  cross-tenant leak).
- **All 3 P1 and 10 of the 12 P2 are fixed and verified live.** The other two P2 are owner
  decisions, not unfixed bugs:
  - QA-039 is the documented design.
  - QA-041 needs a re-scheduling change you have to approve; its interim warning is verified.
- **32 P3/P4 remain open.** They are filed with exact repro steps for triage.
- **Integrated scenarios B–E passed 18/18 (REAL):**
  - family + students → subscription → generated sessions → teacher attendance and reports →
    the parent sees only their own children;
  - one month of invoices and payments (partial, full, wallet) → payroll from the completed
    sessions.
  - Every count and minor-unit total reconciles across attendance, billing and payroll.
- **Tenant isolation held in every test** (host, session, schema, tokens, IDs, `/internal`).
- **Main security wins:**
  - The Etqan staff console let view-only staff run state-changing actions on academies, Etqan
    invoices and scheduled tasks (QA-002, QA-013).
  - Login CSRF (QA-006).
  - Sign-outs that didn't stick (QA-017).
  - Weak passwords accepted (QA-018).
  - Role escalation (QA-021).

## Feature coverage
| ID | Feature | Status | Executed | Fix cycles | P1/P2 fixed and verified |
|---|---|---|---|---|---|
| F01 | Tenancy & provisioning (+ dev env) | **PASSED** | 122 + 9 + 22 gap review | 2 | QA-001, 002, 003, 006, 013, 014 |
| F02 | Sign-in & account security | **PASSED** | 31 | 1 | QA-017, 018 |
| F03 | Roles, permissions & settings | **PASSED** | 27 | 1 | QA-021 |
| F05 | People & families | **PASSED** | 31 | 1 | QA-032 |
| F06 | Catalogue, subscriptions & scheduling | **PASSED** | 29 | 1 | QA-040, 042 (QA-039, 041: owner decisions) |
| F08 | Sessions & attendance | **PASSED** | 27 | 0 | none needed (no P0–P2) |
| F09 | Student billing | **PASSED** | 28 (28/28) | 0 | none needed |
| F10 | Teacher payroll | **PASSED** | 30 | 1 | QA-029 |
| SCN | Integrated scenarios B–E | **PASSED** | 18 (18/18) | 0 | none needed |

Scenario A (a new academy) is covered in F01, REAL, in a browser. Scenario F (multi-tenant
security) is covered across F01, F02, F03 and F05.

## Test statistics
- **Executed:** about 370 cases. Every result carries a provider tag in its spec's Results table.
  - The large majority are REAL: live stack, real DB, mailpit as the SMTP sink.
  - The F09 online payments are SIMULATED (`GATEWAYS_SIMULATE`).
  - A few logic-only cases are FAKE.
  - The live DNS, Zoom, Google and SMS paths are BLOCKED.
- **Baselines:**
  - backend pytest: 10,029 passed, 98.38% coverage;
  - lint-imports: 54/0;
  - ruff: clean;
  - Vitest: no product defects. Load timeouts passed on an isolated rerun; coverage thresholds
    were not evaluated.
- **Checkpoint 1** (after F01–F10): full backend pytest 10,110 passed, 1 failed. The failure is not
  QA's: the hero-slides routes from the owner's other session are missing from the access route
  table.
- **Checkpoint 2** (after F05, F06, F08 and the scenarios, 2026-10-19): full backend pytest
  **10,121 passed, 1 failed, 1 skipped** (47 min, `evidence/checkpoint/pytest-full-2.txt`).
  - The one failure is the same as at checkpoint 1: the six hero-slides routes from the owner's
    other session aren't in the access route table.
  - QA caused no regression.

## Severity breakdown
| Severity | Filed | Fixed and verified | Owner decision | Open |
|---|---|---|---|---|
| P0 | 0 | 0 | 0 | 0 |
| P1 | 3 | 3 | 0 | 0 |
| P2 | 12 | 10 | 2 (QA-039, QA-041) | 0 |
| P3 | 25 | 0 | — | 25 |
| P4 | 7 | 0 | — | 7 |

## Security findings (fixed, verified live)
- **QA-002 / QA-013 (P1): admin actions ignored permissions.** View-only Etqan staff could:
  - suspend, reactivate or copy features to academies;
  - mark Etqan invoices paid, void or issue them;
  - verify emails;
  - run platform-wide scheduled tasks.

  The fix requires `change` permission on every action. A registry-wide test now guards this.
- **QA-006 (P2): login CSRF.**
- **QA-017 (P2): sign-outs that didn't stick.** A refused session came back once the condition
  cleared.
- **QA-018 (P2): weak passwords accepted** on change and on reset by link.
- **QA-021 (P2): role escalation.** A role editor could retire a stronger role and strip its
  members.
- **QA-014 (P2): stale page reverts newer changes.** Saving a stale academy page silently
  reactivated a suspended academy.
- **QA-032 (P2): duplicate-email race.** Two simultaneous saves of one email returned 500; it is
  now a clean 400.

## Financial and scheduling integrity
- **Billing (F09):** 28/28, and the scenarios reconcile across billing, payroll and attendance.
- **Payroll, QA-029 (P2, fixed):** a payslip could be marked paid into a closed period.
- **QA-003 (P1, fixed):** an invalid timezone or currency at creation broke the academy's pages,
  its invoices and the global jobs.
- **Scheduling (F06):**
  - **QA-040 fixed:** deactivated teachers and students no longer get new sessions.
  - **QA-042 fixed:** a double-booking is now reported by the API. The dashboard doesn't show it
    yet (QA-043, P3).
- **Open P3 items that touch money:**
  - QA-026: a three-decimal-currency invoice loses online payment when the service fee is off.
  - QA-030: one oversized rate breaks Generate for the whole month.
  - QA-022: currency isn't checked against ISO 4217.
  - QA-025: misleading error message.

## Decisions the owner needs to make
1. **QA-041 timezone re-anchoring.**
   - Today, changing the academy timezone keeps existing sessions at their old instant. The
     settings form now warns about this.
   - Approve a re-generation of untouched future sessions? That needs a new academy → scheduling
     seam, and session ids change (Zoom links, reminders).
2. **QA-039 early renewal.** An early renewal over a marked session creates a second lesson, which
   is the documented design (B2b §10). Keep it, or change it to one lesson? A prototype exists; it
   changes two documented tests.
3. **QA-040 intent.** A deactivated person gets no new sessions, and reactivating refills them.
   Confirm, or keep scheduling during a short leave?
4. **Sub-part proposals:**
   - Password reuse on change or reset (QA-018).
   - Renaming a stronger role (QA-021).
5. **Product questions** (`coverage-gaps.md`):
   - a `drop_academy` command for test academies;
   - reserved subdomains and refusing `xn--`;
   - audit entries for suspend/reactivate;
   - tolerating one bad academy in the global jobs.

## Performance and UX
- **Performance was not measured** (lean mode); there are no claims. Academy creation is about
  15 s synchronous, and the backend suite is about 31 to 60 min on this Mac.
- **UX items:**
  - QA-011: an English validator message in the Arabic set-password screen.
  - QA-008: a silent failure on an unknown academy host.
  - QA-043: the double-booking list isn't shown in the dashboard.
  - Several missing confirmations.
- No full a11y, responsive or RTL sweep was done; that is Tier 2.

## Remaining risks and blocked items
- **No live integration coverage:** Stripe, Stripe Connect, PayPal, Zoom, WhatsApp, Twilio,
  Google sign-in and web push. Their logic is SIMULATED or FAKE.
- **The production edge is untested:** HTTPS CSRF origin, the Caddy TLS ask. Sign in on staging
  over HTTPS before the next deploy.
- **The running stack still uses the GID-1000 workaround.** The QA-001 fix was verified on
  separately tagged images.
- **Leftover test data:** the `qa-tmp-*` academies are suspended, and the `journey-*` academies are
  e2e leftovers. Fixtures live in `qa` and `qaother`.

## Changed files (uncommitted, for owner review)
- **backend:**
  - `Dockerfile`
  - `config/settings/base.py`
  - `etqan/{tenants,etqan_billing,integrations,identity}/admin.py`, plus the new
    `platform/admin.py`
  - `tenants/services.py`
  - `identity/{api/views,api/serializers,authentication,services}.py`
  - `platform/permissions.py`
  - `access/services.py`
  - `payroll/services/payslips.py`
  - `scheduling/{api/payloads,api/views,services/__init__,services/board,services/generation,services/rules}.py`
  - Regression tests in every touched app. The new test files are:
    - `tenants/tests/test_admin_permissions.py`
    - `tenants/tests/test_admin_stale_change.py`
    - `etqan_billing/tests/test_admin_permissions.py`
    - `identity/tests/test_login_csrf.py`
    - `scheduling/tests/test_generation_guards.py`
- **dashboard:**
  - `Dockerfile`
  - `src/features/identity/api.ts` and its test
  - `src/features/quicklogin/api.ts` and a new test
  - `src/features/academy/AcademySettingsForm.tsx` and its test (the QA-041 warning)
  - `src/locales/{ar,en,es}/academySettings.json`
  - QA Playwright specs in `e2e/qa/`
- **marketing:** `Dockerfile`.
- **meta repo docs:** `docs/features/*.md`, updated per fix (tenancy, feature-toggles, etqan-billing,
  integrations, sign-in, roles-permissions, payroll, subscriptions, academy-settings).
- **Not QA's:** the website, nav, routeTree and site changes in backend, dashboard and marketing
  belong to the owner's other session.
- **QA artefacts:** `qa/` (specs, evidence, logs, register, tools).

## Final recommendation
- **The core operating loop of an academy is validated end to end on the local stack:**
  onboarding, sign-in, permissions, people, packages, subscriptions, scheduling, sessions,
  attendance, billing and payroll.
- **Before production:**
  1. Review and commit these fixes.
  2. Decide on QA-041, QA-039 and QA-040.
  3. Add the hero-slides routes to the access route table, in the other session's work.
  4. Run one live Stripe test payment, a Zoom check and an HTTPS sign-in on staging.
  5. Triage the open P3s, starting with QA-026, QA-030, QA-034, QA-043 and QA-011.
- **Tier 2 can follow as a light loop:** notifications, chat, learning, certificates, recorded
  courses, consultations, the website, Etqan billing and integrations.
- This does not claim the platform is bug-free; it covers the tested scope only.
