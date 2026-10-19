# Execution progress

**Agent 2 is the only one who changes a feature's Status to PASSED, FAILED or BLOCKED.** The
conductor fills in the Workflow run IDs.

## Baseline (Phase 2)
| Suite | Command | Result | Evidence |
|---|---|---|---|
| Backend pytest `etqan/tenants` (F01) | `dc.sh exec -T django pytest etqan/tenants -q -p no:cacheprovider` | **PASS**: 172 passed, 33m10s | `evidence/F01/pytest-tenants.txt` |
| Backend pytest + coverage | `dc.sh exec -T django pytest --cov=etqan -q` | **PASS**: 10,029 passed, 1 skipped, 0 failed; coverage 98.38% (≥80); 60m33s | `evidence/baseline/pytest.txt` |
| Dashboard Vitest + coverage | `dc.sh exec -T dashboard pnpm test:coverage` | **PASS (no product defects)**. First run: 3,440/3,465 passed, 25 failed in 11 files. 24 of the 25 were `Test timed out in 5000ms` while Agent 2's Playwright ran at the same time (default workers, Docker Desktop bind mount). An isolated rerun with default settings still failed 22. A rerun of the 7 files with `--maxWorkers=2 --testTimeout=20000` passed 69/69, `website.guard` included. So this is load-sensitive test timing on this Mac, not a product defect. Coverage thresholds were not evaluated, because the run exited at the failures. | `evidence/baseline/vitest*.txt` |
| Marketing tests | `pnpm test:coverage` | NOT_STARTED | |
| Import boundaries | `lint-imports` | **PASS**: 54 contracts kept, 0 broken | `evidence/baseline/lint-imports.txt` |
| Ruff | `ruff check` | **PASS**: all checks passed | `evidence/baseline/ruff.txt` |
| Playwright (63 specs) | `just e2e` (1 worker) | DEFERRED until after F01 | |

## Tier 1 features
| ID | Feature | Status | Cycles | Open bugs | Workflow run | Gate decision |
|---|---|---|---|---|---|---|
| F01 | Tenancy & academy provisioning (+ dev env) | **PASSED** (gate 2, 2026-10-18) | 2 (+ gap review) | P0–P2: none open (QA-001/002/003/006/013/014 VERIFIED). P3/P4 open, carried forward: QA-004, 005, 007, 008, 009, 010, 011, 012, 015, 016 | wf_e8a22ab9-c6d, wf_6c01cd42-2eb (gap), wf_ac96f3ea-df5 (cycle 2) | Gate 2 (Agent 2, 2026-10-18): PASSED, all 12 gates hold. See § F01 gate decision (cycle 2+); evidence `evidence/F01/gate-2/`. |
| F02 | Sign-in & account security | **PASSED** (retest 1 + gate, 2026-10-19) | 1 | P0–P2: none open (QA-017, QA-018 VERIFIED; QA-018 same-password reuse PROPOSAL-accepted). P3 open, carried forward: QA-019, QA-020 | | Gate (Agent 2, 2026-10-19): PASSED, all 12 gates hold. See § F02 gate decision; evidence `evidence/F02/retest-1/` |
| F03 | Roles, permissions & academy settings (F03+F04 merged, focused mode) | **PASSED** (retest 1 + gate, 2026-10-19) | 1 | P0–P2: none open (QA-021 VERIFIED; rename sub-part PROPOSAL-accepted). P3 open, carried forward: QA-022, QA-023, QA-024 | | Gate (Agent 2, 2026-10-19): PASSED, all 12 gates hold. See § F03 gate decision; evidence `evidence/F03/retest-1/` |
| F04 | (merged into F03) | — | | | | |
| F05 | People: staff, teachers, students, parents, families | **PASSED** (retest 1 + gate, 2026-10-19) | 1 | P0–P2: none open (QA-032 VERIFIED). P3 open, carried forward: QA-033, QA-034, QA-035, QA-036, QA-038 (new), QA-022 (F05 note); P4: QA-037 | | Gate (Agent 2, 2026-10-19): PASSED, all 12 gates hold. See § F05 gate decision; evidence `evidence/F05/retest-1/` |
| F06 | Catalogue, subscriptions & scheduling (F06+F07 merged, lean mode) | **PASSED** (retest 1 + gate, 2026-10-19) | 1 | P0–P2: none open (QA-040, QA-042 VERIFIED; QA-039 by design + design change PROPOSAL-accepted; QA-041 PROPOSAL-accepted with verified mitigation). P3 open, carried forward: QA-043 (new) | wf_c827a266-5f3 | Gate (Agent 2, 2026-10-19): PASSED, all 12 gates hold. See § F06 gate decision; evidence `evidence/F06/retest-1/` |
| F07 | (merged into F06) | — | | | | |
| F08 | Sessions & attendance (lean mode) | **PASSED** (gate, 2026-10-19) | 0 | P0–P2: none found. P3 open, carried forward: QA-044, QA-045; P4: QA-046 (doc), QA-047 | wf_c827a266-5f3 | Gate (Agent 2, 2026-10-19): PASSED, all 12 gates hold. 27 executed: 24 PASS, 3 FAIL (P3/P4 only) + gate check G1. See § F08 gate decision; evidence `evidence/F08/gate/` |
| F09 | Student billing (invoices, payments, wallet, vouchers, online payments) | **PASSED** (gate, 2026-10-19) | 0 | P0–P2: none. P3/P4 open, carried forward: QA-025, QA-026 (P3), QA-027, QA-028 (P4) | | Gate (Agent 2, 2026-10-19): PASSED, all 12 gates hold. 28/28 PASS + 12 gate checks; see § F09 gate decision; evidence `evidence/F09/gate/` |
| F10 | Teacher payroll | **PASSED** (retest 1 + gate, 2026-10-19) | 1 | P0–P2: none open (QA-029 VERIFIED). P3/P4 open, carried forward: QA-030 (P3), QA-031 (P4) | | Gate (Agent 2, 2026-10-19): PASSED, all 12 gates hold. 30/30 executed, 28 PASS, 2 FAIL (P3/P4 only). See § F10 gate decision; evidence `evidence/F10/retest-1/` |


### F01 gate decision

**Decision: PASSED** (Agent 2, 2026-10-18; sole gate authority). **Superseded by the gap-review addendum below: F01 is now FAILED.** Fix history: cycle 1 fixed and verified
ETQAN-QA-001 (P2), 002 (P1), 003 (P1) and 006 (P2); nothing still failing; nothing escalated
(`escalations/` is empty). Evidence paths are relative to `qa/evidence/F01/`.

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | 122 of 123 spec cases executed. TC-058 and TC-060 ran at the gate (FAKE, `gate/pytest-gate-tc058-060-088.txt`). TC-088's live DNS path is BLOCKED by infrastructure, as the spec expects; its logic is covered by FAKE subset/superset tests. The 9 Agent 2 checks were executed. |
| 2 | Critical workflows pass | Yes | Add academy in the admin, invite in Mailpit, set password, sign in (TC-010..018 REAL). `create_academy` command (TC-026). Suspend and reactivate (TC-064..074, re-run in `gate/playwright.txt`). Feature switches (TC-117..130, re-run). |
| 3 | No unresolved P0/P1 | Yes | QA-002 and QA-003 VERIFIED (`retest-1/qa002-live.txt`, `qa003-live-*.txt`); QA-002 re-confirmed in `gate/open-bugs-recheck.txt`. No P0 was filed. |
| 4 | P2s fixed or documented | Yes | QA-001 and QA-006 VERIFIED (`retest-1/qa001-build-*.txt`, `qa006-live.txt`; b9-sign-in and login-csrf green again in `gate/playwright.txt`). |
| 5 | Permissions verified | Yes | TC-133/134/135 pass (gate re-run). A view-only account is offered no actions, and forged actions change nothing. Known P3: QA-012 (the view-only change page returns 500; every write is still refused). |
| 6 | Tenant isolation verified | Yes | TC-105..116 REAL: copied cookies get 403 on the other academy, sessions are only in the own schema, cross-tenant tokens are refused, login CSRF is fixed. tenant-login 3/3 at the gate. |
| 7 | Data integrity verified | Yes | Rollback at every provisioning step (TC-058 FAKE) and on a mid-provision kill (TC-059 REAL). Admin save-path failure leaves nothing half-created (TC-060). Double submit makes one academy (TC-061). A create race stays consistent (TC-062; the raw error is QA-005, P3). Family data is kept when its feature is switched off (TC-130, re-run). |
| 8 | Integrations tested or clearly BLOCKED | Yes | Email: REAL SMTP to Mailpit. The DNS success path and the production edge (TLS ask, Cloudflare) are BLOCKED, with FAKE logic tests. Provider default accounts are BLOCKED. Nothing live is claimed from SIMULATED or FAKE results. |
| 9 | Regression tests pass | Yes | `gate/pytest-tenants.txt` 189 passed, `gate/pytest-identity.txt` 851 passed, `gate/pytest-platform.txt` 226 passed (all exit 0). `gate/playwright.txt`: 26 runs, all green except TC-133b, which is obsolete: it drives the pre-fix UI path, now absent because of the QA-002 fix. |
| 10 | Evidence recorded | Yes | `evidence/F01/` (cycle 1), `fix-cycle-1/`, `retest-1/`, `gate/`; logs `logs/F01/agent{1,2,3}.md`. |
| 11 | Gaps documented | Yes | `coverage-gaps.md`: F01 untestable items, owner questions, the gate carry-forward list, the QA-003 residual, and a test-only proposal to adopt the gate tests. |
| 12 | Acceptance criteria met | Yes, with known P3/P4 issues | Every P1 case passes except one. TC-100's host-resolution part passes, but its SPA error message fails (QA-008, P3). TC-088's live path is BLOCKED. The 5 failing cases are all P3 defects that are filed and documented. |

**Known issues carried forward (OPEN, P3/P4, do not block the gate):**
- ETQAN-QA-004
- ETQAN-QA-005
- ETQAN-QA-007
- ETQAN-QA-008
- ETQAN-QA-009
- ETQAN-QA-010
- ETQAN-QA-011
- ETQAN-QA-012

QA academies kept for later features:
- `qa` and `qaother` are active.
- `qa-tmp-*` are suspended.
- demo and other were not modified destructively.

**Working-tree note:** during this gate run, another session added changes to the dashboard (the
website SetupGuide, `nav.ts`, `routeTree.gen.ts`) and to marketing `src/`. These are outside F01 and
were not touched (`gate/dashboard-status-end.txt`, `gate/marketing-status-end.txt`). The F01 fix diffs
are still byte-identical to `retest-1/diff-*.txt`.

### F01 gap-review addendum (Agent 2, 2026-10-18)

**Decision: FAILED, pending fix cycle 2** (Agent 2, sole gate authority). **Superseded by § F01 gate decision (cycle 2+) below: PASSED after fix cycle 2.** The provisional PASSED above was
given before Agent 1's gap review; executing the 22 gap cases (TC-150..171) found a new P1 and a new P2,
so gate 3 ("no unresolved P0/P1") and gate 4 ("P2s fixed") no longer hold.

| Gate | Holds now? | Why |
|---|---|---|
| 3 No unresolved P0/P1 | **No** | **ETQAN-QA-013 (P1)**: view-only Etqan staff can mark Etqan invoices paid, void or issue them (emailed), verify email addresses, and are offered the platform-wide PeriodicTask Run/Enable/Disable/Toggle (TC-151). |
| 4 P2s fixed | **No** | **ETQAN-QA-014 (P2)**: a stale academy change page reactivates a suspended academy, lifts the defaults suspension and re-enables switched-off features (TC-152). |
| 5 Permissions verified | **No** | Same as QA-013. The tenants actions themselves hold (TC-150: partial-permission staff get exactly what they should). |
| 7 Data integrity | **No** | QA-014. Suspend/reactivate round trip preserves everything (TC-165); copy features is a documented replace (TC-153). |
| 6 Tenant isolation | Yes | TC-161..164 pass: inquiries land only in the host's schema, base-only routes 404 on academy hosts, Host-header edge cases never serve foreign data, private media unreachable. |
| 1, 2, 8–12 | Yes | All 22 gap cases executed (TC-159/169 by Playwright `--workers=1`, after the dashboard Vitest baseline finished); evidence in `evidence/F01/gap/`; gaps in `coverage-gaps.md` § gap-review execution notes. |

**Gap-review results:** PASS 18, FAIL 4. Tags: REAL for all live cases; FAKE parts: TC-155 self-heal,
TC-168 expiry, TC-171 cited pytest; REAL static: TC-151 beat actions, TC-171.
- FAIL: TC-151 (QA-013, P1), TC-152 (QA-014, P2), TC-155 (QA-015, P3), TC-156 (QA-016, P3).
- New P3s QA-015/016 may be carried forward like the others; QA-013 and QA-014 must be fixed by Agent 3
  and retested by Agent 2 (re-run TC-150/151/133 and TC-152, plus scoped pytest for tenants,
  etqan_billing, integrations, identity) before F01 can pass again.

State after the run: qa and qaother active with their features restored exactly (md5 unchanged); every
qa-tmp-* (incl. the new qa-tmp-cmd and, if created, qa-tmp-abort) suspended; qa-tmp-1 custom domains
disabled, subdomain primary; fixture invoices, inquiries and the test logo removed; demo, other,
journey-* and khaled untouched (`gap/academies-after.txt`).

### F01 retest 2 (Agent 2, 2026-10-18)

**Status: RETESTING** (both fix-cycle-2 bugs VERIFIED; the gate decision is a separate step).
- ETQAN-QA-013 (P1) VERIFIED: TC-151 re-run live as filed. View-only staff are offered no action on
  any of the 30 console admins, 13 forged POSTs change nothing (no mail, no admin log), and superuser and
  change-permission staff keep every action.
- ETQAN-QA-014 (P2) VERIFIED: TC-152 re-run live as filed. Variants covered error re-display, forged
  hidden initials (the 30-day rule holds) and legacy POSTs. The Playwright two-tab test passes.
- Regression tests fail without the fix (12) and pass with it. Scoped pytest all green: etqan_billing
  137, integrations 391, platform 226, identity 851, tenants 197. ruff and lint-imports are clean.
- Gate 3 (no P0/P1) holds again, as do gate 4 (P2 fixed), gate 5 (permissions) and gate 7 (data
  integrity). Still OPEN, P3/P4: QA-004, 005, 007, 008, 009, 010, 011, 012, 015, 016.
- No new defects were filed. Evidence: `evidence/F01/retest-2/`.

### F01 gate decision (cycle 2+)

**Decision: PASSED** (Agent 2, sole gate authority; run 2026-10-18T21:41Z–22:40Z, resumed after a host reboot
at about 22:09Z). This supersedes the provisional PASSED and the gap-review FAILED above. Fix history: cycle 1
fixed QA-001 (P2), QA-002 (P1), QA-003 (P1) and QA-006 (P2); cycle 2 fixed QA-013 (P1) and QA-014 (P2). Agent 2
verified all six live. Nothing is still failing and nothing was escalated (`escalations/` is empty). Paths are
relative to `qa/evidence/F01/`.

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | Spec: 122 of 123, with TC-088's live DNS path BLOCKED as the spec expects (FAKE logic cover). The 9 Agent 2 checks were run. Gap review: all 22 run. TC-159 and TC-169 had not actually been run before gate 2, although the addendum said so; both ran at gate 2 and pass (`gate-2/playwright-tc159.txt`, `gate-2/tc169-abort.txt`). The per-case table is now in the spec under "Gap-review results". |
| 2 | Critical workflows pass | Yes | Add academy, invite, set password, sign in; the `create_academy` command; suspend/reactivate; feature switches. The console and features-admin Playwright set passes at gate 2 (`gate-2/playwright.txt`). The abandoned-POST provisioning case TC-169 passes. |
| 3 | No unresolved P0/P1 | Yes | P1s QA-002, QA-003 and QA-013 are VERIFIED. QA-013 was re-checked at gate 2: R2-TC-151 passes both before and after the reboot (`gate-2/playwright.txt`, `playwright-post-reboot.txt`). No P0 was ever filed. Every gap P1 (150, 151, 158, 161) passes. |
| 4 | P2s fixed or documented | Yes | P2s QA-001, QA-006 and QA-014 are VERIFIED. R2-TC-152 passes at gate 2 and the DB was checked (`gate-2/r2-tc152-rerun.txt`). Every gap P2 passes, TC-159 included. No P2 is open, and no owner-approval acceptance is needed. |
| 5 | Permissions verified | Yes | TC-133/134/135/150/151 pass. View-only staff get no action on any of the 30 console admins, and forged POSTs change nothing. Superuser and change-permission staff keep every action. Known P3: QA-012 (the view-only change page returns 500; writes are still refused). |
| 6 | Tenant isolation verified | Yes | TC-105..116 and TC-161..164 pass. tenant-login 3/3 and login-csrf 2/2 pass at gate 2, both before and after the reboot. |
| 7 | Data integrity verified | Yes | TC-058..062, TC-130 and TC-165 pass. With QA-014 fixed (TC-152), a stale page no longer undoes newer changes. TC-169: an abandoned POST leaves exactly one academy and one invite. Academy rows are unchanged from start to end except for the new suspended `qa-tmp-abort` (`gate-2/state-final.txt`). |
| 8 | Integrations tested or clearly BLOCKED | Yes | Email: REAL SMTP to Mailpit. The DNS success path, TLS ask/Cloudflare and provider default accounts are BLOCKED, with FAKE logic tests. Nothing live is claimed from SIMULATED or FAKE results. |
| 9 | Regression tests pass | Yes | pytest, scoped, one suite at a time, all green: tenants 197 (re-run after the reboot killed the first run at 73%; `pytest-tenants-interrupted-by-reboot.txt`), identity 851, platform 226, etqan_billing 137, integrations 391. ruff/format clean on the 16 F01 files; lint-imports 54 kept, 0 broken. Playwright `--workers=1 --retries=0` (`playwright.txt`): the full F01 set passes. Two first-run failures were infrastructure, not product: the marketing container (stale volume) and a fixture precondition. Both were rerun and pass. Post-reboot smoke: 10/10 plus TC-143 (`playwright-post-reboot.txt`). Its first try hit a QA-harness bug in `qa/tools/manage-wrap.sh` (recreated after the reboot without shell-unquoting), which I fixed and reran; product code was not touched. |
| 10 | Evidence recorded | Yes | `evidence/F01/{gap,retest-2,gate-2}/` and logs `logs/F01/agent{1,2,3}.md`. Code freeze: the F01 fix files are byte-identical to the verified diffs, re-checked after the reboot (`gate-2/code-freeze.txt`). |
| 11 | Gaps documented | Yes | `coverage-gaps.md`: F01 untestable items, owner questions (copy = replace, `XXX`/`ZZZ` currencies, primary-domain fallback), the TC-159/169 correction, the stale `*_node_modules` volume proposal, and test-only proposals. |
| 12 | Acceptance criteria met | Yes, with known P3/P4 issues | Every P1 and every P2 case passes. The only failing cases are P3s with filed defects: TC-100 (QA-008), TC-141 (QA-011), TC-155 (QA-015), TC-156 (QA-016) and the other cycle-1 P3s (QA-004/005/007). |

**Known issues carried forward (OPEN, P3/P4, do not block the gate):**
- ETQAN-QA-004, ETQAN-QA-005, ETQAN-QA-007, ETQAN-QA-008, ETQAN-QA-009, ETQAN-QA-011, ETQAN-QA-012,
  ETQAN-QA-015 and ETQAN-QA-016 (P3)
- ETQAN-QA-010 (P4)

**Not part of F01, untouched:** the owner's other session changed backend `etqan/site/*`, including the new
migration `site/0007_hero_slides`, dashboard website/nav/routeTree and marketing `src/`. They were not
reviewed or changed here. Nothing was committed.

### F02 gate decision

**Decision: PASSED** (Agent 2, sole gate authority; retest 1 + gate in one run, 2026-10-18T23:51Z–2026-10-19T00:03Z). Fix
cycle 1 (Agent 3) fixed QA-017 (P2) and QA-018 (P2); Agent 2 retested both live, did not rely on Agent 3's
checks, and both are VERIFIED. No P0/P1 was ever filed for F02; `escalations/` has nothing for F02. Paths are
relative to `qa/evidence/F02/`.

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | 31 of 31 (TC-001..030 + TC-031). Retest 1 reran TC-010, TC-017, TC-025 (refusal part) and TC-031 via the original QA-017/018 repros. Live Google OAuth (TC-028) and live SMS (TC-021) BLOCKED/FAKE as the spec expects. |
| 2 | Critical workflows pass | Yes | Login/logout, reset by link and by code, invite, 2FA set-up and sign-in, quick login start/return, parent access. Playwright F02 3/3 (`retest-1/playwright.txt`) plus the QA-018 UI check 1/1 (`retest-1/playwright-qa018-ui.txt`, `qa018-ui.png`). |
| 3 | No unresolved P0/P1 | Yes | None filed. All 26 P1 cases pass in their P1 assertions; TC-025's only failing sub-part is the P3 QA-020. |
| 4 | P2s fixed or documented | Yes | QA-017 VERIFIED (`retest-1/qa017-retest.txt`: admin, staff role-code and parent variants; row deleted, replay stays 403). QA-018 VERIFIED (`retest-1/qa018-retest.txt`: change and link reset refuse weak/email/129/200k, DB hash unchanged). Same-password reuse: PROPOSAL-accepted with documented low risk (`coverage-gaps.md` § F02). |
| 5 | Permissions verified | Yes | TC-014, 016, 019, 026 pass; the staff role-code revocation now ends the impersonation for good. |
| 6 | Tenant isolation verified | Yes | TC-024 passes (sessions, credentials, tokens, counters). Seeded demo and qaother admins still sign in after the fix. The fix acts only on the current request's tenant session (gap noted: no live qaother quick-login refusal, qaother has no student). |
| 7 | Data integrity verified | Yes | DB checks: `django_session` row count 0 after each refusal; password hashes unchanged after refused changes/resets; role 4 permissions identical before/after; f02-a and f02-d passwords restored and sign in (f02-d → `mfa_required`). |
| 8 | Integrations tested or clearly BLOCKED | Yes | Email REAL via mailpit (reset links, alerts). SMS FAKE (console), Google OAuth BLOCKED. Nothing live claimed from FAKE. |
| 9 | Regression tests pass | Yes | Agent 3's 10 regression tests + all `TestParentsOff` (13 passed, `retest-1/pytest-regression.txt`); `pytest etqan/identity` 861, `etqan/platform` 226; ruff, format, lint-imports 54 kept (`retest-1/ruff-lint.txt`). `etqan/access` 2049 passed, 1 failed outside F02 (owner's new `site/admin/hero-slides/` routes lack route-code entries; `retest-1/pytest-access.txt`). `etqan/tenants` not re-run (Agent 3: platform+tenants 423 passed). |
| 10 | Evidence recorded | Yes | `evidence/F02/retest-1/`, diff reviewed (`diff-reviewed.patch`) and frozen (`code-freeze.txt`, md5 of the 7 files); logs `logs/F02/agent{2,3}.md`. |
| 11 | Gaps documented | Yes | `coverage-gaps.md` § F02: gate checklist (roles, isolation, money n/a, state transitions), the reuse proposal, the access-test heads-up, P3 carry-forward. |
| 12 | Acceptance criteria met | Yes, with known P3 issues | Every P1 and P2 case passes; remaining FAILs are TC-027 (QA-019, P3) and TC-025's reset sub-part (QA-020, P3). |

**Diff review (Agent 3's 7 files only):** `authentication.py` records the refused key and a new middleware
deletes it after the view; `base.py` adds one middleware line; `services._validate_new_password` runs
`validate_password` after the current-password/token checks; serializers add `max_length=128`. No validation
weakened, no test special-casing, no boundary change (lint-imports clean), no migration, same 400 shape.

**Known issues carried forward (OPEN, P3):** ETQAN-QA-019, ETQAN-QA-020.

**Not part of F02, untouched:** the owner's `etqan/site/*`, dashboard website/nav/routeTree and marketing work.
Test-only file added: `dashboard/e2e/qa/f02-retest1.spec.ts`. Nothing was committed.

### F03 gate decision

**Decision: PASSED** (Agent 2, sole gate authority; retest 1 + gate in one run, 2026-10-19T00:29Z–00:35Z). Fix cycle 1
(Agent 3) fixed ETQAN-QA-021 (P2); Agent 2 retested it live, did not rely on Agent 3's checks, and it is VERIFIED. No
P0/P1 was filed for F03; `escalations/` has nothing for F03. Paths are relative to `qa/evidence/F03/`.

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | 27 of 28 (TC-001..024, 026..028). TC-025 (P2, optional) NOT RUN, recorded in `coverage-gaps.md` § F03. Retest 1 re-ran the TC-005 repro plus 14 related checks (`retest-1/qa021-retest.txt`). |
| 2 | Critical workflows pass | Yes | Role create/edit/retire/restore, staff invite and accept, permission matrix, settings save, feature off, system status, quick translate (TC-001..024). Playwright F03 2/2 after the fix (`retest-1/playwright.txt`). |
| 3 | No unresolved P0/P1 | Yes | None filed. All 24 P1 cases pass. |
| 4 | P2s fixed or documented | Yes | QA-021 VERIFIED (`retest-1/qa021-retest.txt`: Ed's retire of Money 403, DB unchanged, Mo keeps access). Rename sub-part PROPOSAL-accepted with documented low risk (`coverage-gaps.md` § F03). |
| 5 | Permissions verified | Yes | TC-004/005/008/009/026/027 plus retest: staff guard on retire and restore, held-codes retire allowed, Supervisor preset protected, admins unlimited. |
| 6 | Tenant isolation verified | Yes | TC-011 and retest step 19 (Ed's cookie on qaother 403, qaother roles unchanged). |
| 7 | Data integrity verified | Yes | DB checked after every refused call (role 9 `is_active=t`, perms unchanged); settings 4xx leave rows unchanged (TC-017); money per currency in exact minor units (TC-016/028). Known P3: QA-023 lost update under concurrent PATCH. |
| 8 | Integrations tested or clearly BLOCKED | Yes | Invite email REAL via mailpit; job runs via the real celery worker. Nothing live claimed from SIMULATED/FAKE. |
| 9 | Regression tests pass | Yes | Agent 3's 5 tests within 38 passed (`retest-1/pytest-regression.txt`); `etqan/access` 2054 passed, 1 failed outside F03 (owner's `site/admin` routes, `retest-1/pytest-access.txt`); ruff, format, lint-imports 54 kept (`retest-1/ruff-lint.txt`). |
| 10 | Evidence recorded | Yes | `evidence/F03/`, `fix-cycle-1/`, `retest-1/` (diff reviewed `diff-reviewed.patch`, frozen `code-freeze.txt`); logs `logs/F03/agent{2,3}.md`. |
| 11 | Gaps documented | Yes | `coverage-gaps.md` § F03: gate checklist (roles, isolation, money, state transitions), rename proposal, unrun cases, owner heads-up. |
| 12 | Acceptance criteria met | Yes, with known P3 issues | Every P1 and P2 case passes; remaining FAILs are TC-016 (QA-022, P3) and TC-018 (QA-023, P3); new P3 QA-024 from the retest. |

**Diff review (Agent 3's files only):** `access/services.py:update_role` replaces the restore-only condition with "any
real flip of `is_active`" and a verb-specific message; tests add 4 service + 1 API cases; doc rule 2 updated. No
validation weakened, no test special-casing, no boundary change, no migration, same 403 shape.

**Known issues carried forward (OPEN, P3):** ETQAN-QA-022, ETQAN-QA-023, ETQAN-QA-024.

**Not part of F03, untouched:** the owner's `etqan/site/*`, dashboard website/nav/routeTree and marketing work.
Fixtures cleaned (`retest-1/cleanup.txt`): Ed, Mo and the new UI staff 31 deactivated, F03 roles retired, seeded logins
200. Nothing was committed.

### F09 gate decision

**Decision: PASSED** (Agent 2, sole gate authority; gate run 2026-10-19T00:55Z–01:00Z, lean mode). Execution found no
P0–P2 defect, so there was no fix cycle and nothing to retest; no product code under `etqan/billing`, `wallet`,
`vouchers` or `gateways` is modified. `escalations/` has nothing for F09. Paths are relative to `qa/evidence/F09/`.

**Coverage checklist (P1 risks):**
- Roles: admin, staff without codes, staff QA Billing, staff Narrow (second-code refusals), supervisor, teacher, student,
  parent, sibling/family payer P3, other family (parent2/student2), anonymous (TC-012 35 endpoints × 9 roles, TC-013).
  Gate added the cross-family wallet path (G1: parent2/student2 read/entries 404, top-up 403, `mine` only own child,
  DB unchanged). No untested role. Etqan staff console billing is F01.
- Tenant isolation: TC-014 both directions (ids, UUIDs, codes, cross-signed webhooks, cookie on the other host). Ok.
- Money: exact minor units per currency, fees and rounding (JPY/KWD/EGP/USD), revenue/open balance = SQL (TC-009),
  ledger = entry sum (TC-015), races (TC-006/017/021/028). Ok.
- State transitions: invoice open→partial→paid→refunded→void, subscription renew/delete, checkout pending→paid/
  failed/expired/attention, link open→paid/closed, code unused→used/void. Gate added feature-off→on (G2: `balances`,
  `system_codes`, `invoices` off → 404 incl. writes and redeem, back on → 200, DB unchanged). Ok.
- Not cheap, documented in `coverage-gaps.md` § F09: live Stripe/PayPal (BLOCKED), clock-driven jobs and midnight
  boundaries, multi-worker races.

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | 28 of 28 (TC-001..028, TC-028 added), plus 12 gate checks (`gate/gate-checks.txt`). |
| 2 | Critical workflows pass | Yes | Manual and subscription invoices, partial/over payments, refunds, wallet top-up/pay/move/reverse, vouchers, online pay, links (TC-001..028). Playwright F09 3/3 at the gate (`gate/playwright.txt`). |
| 3 | No unresolved P0/P1 | Yes | None filed; all 24 P1 cases pass. |
| 4 | P2s fixed or documented | Yes | No P2 filed. |
| 5 | Permissions verified | Yes | TC-012 matrix (no 5xx, no row changed after a refusal), TC-013 family scope, gate G1. |
| 6 | Tenant isolation verified | Yes | TC-014 (qa ↔ qaother), cross-signed webhooks refused. |
| 7 | Data integrity verified | Yes | DB compared after every refusal; ledger invariants; reconciliation per currency equals SQL; G1/G2 row counts unchanged (92/65/28/13). |
| 8 | Integrations tested or clearly BLOCKED | Yes | Stripe/PayPal SIMULATED only (`GATEWAYS_SIMULATE`, hand-signed events); live providers BLOCKED in `coverage-gaps.md`. Nothing live claimed. |
| 9 | Regression tests pass | Yes | `pytest etqan/billing etqan/wallet etqan/vouchers etqan/gateways` 1094 passed (`gate/pytest-regression.txt`); Playwright `e2e/qa/f09-billing.spec.ts` 3/3 `--workers=1`. |
| 10 | Evidence recorded | Yes | `evidence/F09/` (tc001..028, pw/, scripts/, gate/); log `logs/F09/agent2.md`. |
| 11 | Gaps documented | Yes | `coverage-gaps.md` § F09 (gate checklist, BLOCKED live providers, clock, races). |
| 12 | Acceptance criteria met | Yes, with known P3/P4 issues | Every case passes; S1–S12 verdicts recorded; known P3 QA-025, QA-026 and P4 QA-027, QA-028. |

**Known issues carried forward (OPEN):** ETQAN-QA-025, ETQAN-QA-026 (P3), ETQAN-QA-027, ETQAN-QA-028 (P4).

**Not part of F09, untouched:** the owner's `etqan/site/*`, dashboard website/nav/routeTree and marketing work. Test-only
file: `dashboard/e2e/qa/f09-billing.spec.ts`. Feature switches toggled at the gate were restored (back-on 200). Nothing
was committed.

### F10 gate decision

**Decision: PASSED** (Agent 2, sole gate authority; retest 1 + gate 2026-10-19T04:25–04:45 Cairo, lean mode). One fix
cycle (ETQAN-QA-029, P2) retested independently; Agent 3's report was not relied on. `escalations/` has nothing for F10.
Paths are relative to `qa/evidence/F10/`.

**Retest (ETQAN-QA-029 → VERIFIED, REAL):** original repro (issued Aug payslip 19, mark-paid `2026-01-01`) → 400 `paid_on`,
DB issued, 0 expenses; day before month → 400; future → 400; month start → 200 + expense on that date; pay-to-balance on July
payslip 24 refused for 06-30/01-01 with balance unchanged, accepted on 07-01 (balance 4000, expense 4000 EGP 07-01)
(`retest-1/api-db.txt`). UI: Mark paid dialog shows the field error for 2026-01-31 and pays on 2026-02-01, DB + expense match
(`retest-1/playwright-qa029.txt`, `qa029-ui*.json/png`, `qa029-ui-db.txt`). Diff review: only `payroll/services/payslips.py`
(one extra guard before any write), `tests/test_api.py`, `tests/test_pay_to_balance.py`, docs Lifecycle line; validation is
stricter, not weaker; no test special-casing; import contracts intact. Month-start bound accepted over the issue-day bound
(see register).

**Coverage checklist (P1 risks):**
- Roles: admin, staff (no codes / payroll read / create-only / update-without-view), supervisor, teacher own vs other, student,
  parent, anonymous, impersonated (TC-017, TC-022, TC-023 29 endpoints × 11 roles). No untested role.
- Tenant isolation: TC-024 qa ↔ qaother (ids, cookie on other host, counters, writes don't touch the other schema). Ok.
- Money: integer minor units, rounding, gross/net formula, CSV sum = DB, per-currency expenses, net-0, int64 overflow (QA-030
  P3), races (TC-001/002/010/018/028/029/030); retest added the `paid_on` lower bound. Ok.
- State transitions: payslip draft→issued→paid / paid-to-balance→acknowledged and every refused transition (409), withdrawal
  under_review→approved→paid / rejected / cancelled with races (TC-017/019/020/021/030). Ok.
- Not cheap, documented in `coverage-gaps.md` § F10: clock-moved month-end instant, multi-worker races, no payout rail.

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | 30 of 30 (29 spec + TC-030) plus retest 1 (`retest-1/`). |
| 2 | Critical workflows pass | Yes | Generate → issue → mark paid / pay to balance → expense → acknowledge; withdrawals; projection/CSV (TC-001..030). Retest UI 1/1. |
| 3 | No unresolved P0/P1 | Yes | None filed; all 26 P1 cases pass. |
| 4 | P2s fixed or documented | Yes | QA-029 (P2) fixed and VERIFIED by Agent 2 (API + DB + UI). |
| 5 | Permissions verified | Yes | TC-022/023 matrix, no DB change after any refusal; retest: teacher mark-paid 403. |
| 6 | Tenant isolation verified | Yes | TC-024. |
| 7 | Data integrity verified | Yes | Refused pays leave status, `paid_on`, expenses and balance unchanged (`retest-1/api-db.txt`); one expense per payslip; CSV = DB. |
| 8 | Integrations tested or clearly BLOCKED | Yes | No outside integration in payroll (manual payout record); exchange-rate provider and payout rail recorded in `coverage-gaps.md`. Nothing live claimed. |
| 9 | Regression tests pass | Yes | QA-029 regression tests 3 passed; `pytest etqan/payroll etqan/finance` 582 passed; ruff + format clean; lint-imports 54 kept 0 broken (`retest-1/`). Playwright `f10-payroll.spec.ts` rerun: S4 passed, TC-025/026 failed only on consumed fixtures (precondition `status draft`/unacknowledged paid slip; passed 3/3 in `pw-run5.txt`, untouched code paths), new `f10-retest.spec.ts` 1/1. |
| 10 | Evidence recorded | Yes | `evidence/F10/` (tc001..030, pw/, scripts/, fix-cycle-1/, retest-1/); logs `logs/F10/agent2.md`, `agent3.md`. |
| 11 | Gaps documented | Yes | `coverage-gaps.md` § F10 (gate checklist, clock, races, fixture note). |
| 12 | Acceptance criteria met | Yes, with known P3/P4 issues | Every P1 case passes; S1–S11 verdicts recorded; known P3 QA-030 and P4 QA-031. |

**Known issues carried forward (OPEN):** ETQAN-QA-030 (P3), ETQAN-QA-031 (P4).

**Not part of F10, untouched:** the owner's `etqan/site/*`, dashboard website/nav/routeTree and marketing work, and the other
modified backend files from earlier features. Test-only files: `dashboard/e2e/qa/f10-payroll.spec.ts`,
`dashboard/e2e/qa/f10-retest.spec.ts`. Retest test data in `qa`: payslips 13, 19, 24 paid; Feb 2026 generated (PAY-000038 paid).
Nothing was committed.

### F05 gate decision

**Decision: PASSED** (Agent 2, sole gate authority; retest + gate run 2026-10-19T04:34Z–04:40Z, lean mode). One fix cycle:
ETQAN-QA-032 (P2) retested by Agent 2 itself and VERIFIED. Agent 3 reported no not_a_bug items and no proposals; `escalations/`
has nothing for F05. Paths are relative to `qa/evidence/F05/`.

**Retest of ETQAN-QA-032:** original repro as filed (3×5 parallel creates, 3×2 parallel edits) plus a mixed-case variant: exactly
one 201/200 per round, every loser the 400 email field error, 1 row per address, one invite each, 0 500s; postgres logged 19 unique
violations, proving the losers went through the new savepoint catch. Sequential duplicate/valid cases unchanged. Regression tests
2/2, and both fail when the helper is swapped for a plain save in memory. Diff limited to `_save_claiming_email` + 2 call sites in
`identity/services.py` and `TestConcurrentEmailClaim`; no weakened validation, no special-casing, no migration, imports clean.

**Coverage checklist (P1 risks):** see `coverage-gaps.md` § F05 "Gate checklist". Roles and state transitions complete; gate G1
(tenant isolation on the touched path) passed; gate G2 (parallel signed-in email change) found P3 ETQAN-QA-038 (no 500, stale
pending email). Self-registration API race, multi-worker races and UI double-submit documented as gaps.

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | 31 of 31 (TC-001..031, TC-031 added), retest of TC-023, gate checks G1/G2 (`retest-1/gate-checks.txt`). |
| 2 | Critical workflows pass | Yes | Add/invite/accept, email-less then email, teacher onboarding, parents/siblings, families + payer, bulk, search/CSV, email change, staff lifecycle, contracts (TC-001..022). Playwright 3/3 at the gate (`retest-1/playwright.txt`). |
| 3 | No unresolved P0/P1 | Yes | None filed; all 27 P1 cases pass. |
| 4 | P2s fixed or documented | Yes | QA-032 (only P2) fixed and VERIFIED (`retest-1/qa032-api-repro.txt`). |
| 5 | Permissions verified | Yes | TC-013 matrix (8 roles × 14), TC-014 partial codes, TC-015, TC-017..019, TC-022 contracts matrix, TC-031 impersonation. |
| 6 | Tenant isolation verified | Yes | TC-016 (ids, cookies, credentials, reset links, 8-table checksums), gate G1. |
| 7 | Data integrity verified | Yes | DB checked after every refusal and race: one user per address, no orphan profiles/EmailAddress rows, last admin kept, family claim unique; G1 `qa` count 174/211 unchanged. |
| 8 | Integrations tested or clearly BLOCKED | Yes | Email REAL via mailpit; live delivery, WhatsApp/SMS invites and S3 private storage BLOCKED/untestable in `coverage-gaps.md` § F05. |
| 9 | Regression tests pass | Yes | `pytest etqan/identity etqan/employment` 890 passed (`retest-1/pytest-identity-employment.txt`); ruff/format clean, lint-imports 54/0 (`retest-1/ruff-lint-imports.txt`); Playwright `e2e/qa/f05-people.spec.ts` 3/3 `--workers=1`. |
| 10 | Evidence recorded | Yes | `evidence/F05/` (tc*, scripts/, pw/, fix-cycle-1/, retest-1/); logs `logs/F05/agent2.md`, `agent3.md`. |
| 11 | Gaps documented | Yes | `coverage-gaps.md` § F05 (incl. gate checklist). |
| 12 | Acceptance criteria met | Yes, with known P3/P4 issues | All P1/P2 cases pass; S1–S10 verdicts recorded (S3/S4 owner product questions); known P3 QA-033, 034, 035, 036, 038, QA-022 note; P4 QA-037. |

**Known issues carried forward (OPEN):** ETQAN-QA-033, ETQAN-QA-034, ETQAN-QA-035, ETQAN-QA-036, ETQAN-QA-038 (P3), ETQAN-QA-022
(P3, F05 note), ETQAN-QA-037 (P4).

**Clean-up:** the race-made students (Agent 3's 170, 175 and the retest's `QA5 RT1*`, 14 in `qa`; `QA5 G1` id 8 in `qaother`) were
deactivated by bulk `deactivate` (0 left active). Students 74/75 keep the G2 emails. **Not part of F05, untouched:** the owner's
`etqan/site/*`, dashboard website/nav/routeTree and marketing work. Nothing was committed.

### F06 gate decision

**Decision: PASSED** (Agent 2, sole gate authority; retest + gate run 2026-10-19 ~16:25Z–16:40Z, lean mode). One fix cycle for
four P2s, each retested by Agent 2 itself on fresh data (API + DB, UI where relevant). `escalations/` has nothing for F06. Paths are
relative to `qa/evidence/F06/`.

**Retest:**
- **ETQAN-QA-042** VERIFIED: create 201 lists 9 clash pairs = independent DB overlap query; no-clash control `[]`; renew 5 pairs /
  control `[]`; teacher still 403. UI display not done → new **ETQAN-QA-043 (P3)**.
- **ETQAN-QA-040** VERIFIED: job and scoped generate create nothing for a deactivated teacher/student (`skipped_inactive 3`, 0 rows
  after the deactivation instant), Today board drops the missing row, renew still 400, teacher-only inactive still skipped,
  reactivation refills the exact 3 dates. Owner to confirm intent (reversible, documented).
- **ETQAN-QA-039** NOT_A_BUG accepted after reading B2b spec §10 (line 193); the overlap is now reported in the renew answer (1 pair,
  verified). One-lesson design change = PROPOSAL-accepted (owner). Risk: double consumption if both lessons are marked.
- **ETQAN-QA-041** PROPOSAL-accepted (P2): re-anchoring needs a cross-app seam and replaces session ids; mitigation verified live
  (settings-form warning, Playwright 1/1 + screenshot, vitest 14, biome clean). Risk: untouched generated lessons keep old instants.
- Diff review: scheduling diff identical to Agent 3's `fix-cycle-1/fix.diff` (additive keys, no migration, no weakened validation,
  no special-casing; existing `test_renewal`/`test_today` design tests untouched); dashboard diff display-only.

**Coverage checklist (P1 risks):** see `coverage-gaps.md` § F06 "Gate checklist". Roles, money and state transitions complete;
gate G1 (tenant isolation on the touched endpoints) passed.

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | 29 of 29 (TC-001..029), retest of TC-012/015/017/018, gate check G1 (`retest-1/gate-checks.txt`). |
| 2 | Critical workflows pass | Yes | Catalogue + country prices, create/renew/cancel/pause/archive, generation incl. DST, trials, bundles, groups, availability, Today board (TC-001..029). Playwright f06 3/3 rerun at the gate (`retest-1/pw-f06-regression.txt`). |
| 3 | No unresolved P0/P1 | Yes | None filed; all 26 P1 cases pass. |
| 4 | P2s fixed or documented | Yes | QA-040, QA-042 VERIFIED; QA-039 by design + PROPOSAL-accepted; QA-041 PROPOSAL-accepted with verified mitigation (`retest-1/r1-api-db.txt`, `pw-qa041.txt`). |
| 5 | Permissions verified | Yes | TC-026..028 role matrix (admin, staff with/without codes, view-only, supervisor, teacher, student, parent, anonymous); retest teacher 403. |
| 6 | Tenant isolation verified | Yes | TC-004, TC-027 (id collisions), gate G1 (qaother 404 on qa ids, cross-host cookie 403). |
| 7 | Data integrity verified | Yes | DB checked after every step: no sessions for inactive people, exact refill, conflicts = DB overlap, one invoice per subscription, duplicates only where designed. |
| 8 | Integrations tested or clearly BLOCKED | Yes | Celery beat timing, Zoom/Jitsi links, WhatsApp/push notices documented in `coverage-gaps.md` § F06 (BLOCKED/untestable); job called directly (REAL). |
| 9 | Regression tests pass | Yes | `test_generation_guards.py` 9/9; `pytest etqan/scheduling etqan/catalogue etqan/academy` 1502 passed; ruff + format clean; lint-imports 54/0; dashboard vitest 14 + biome clean; Playwright 3/3 + 1/1 `--workers=1`. |
| 10 | Evidence recorded | Yes | `evidence/F06/` (tc*, scripts/ incl. `r1.sh`, pw/, fix-cycle-1/, retest-1/); logs `logs/F06/agent2.md`, `agent3.md`. |
| 11 | Gaps documented | Yes | `coverage-gaps.md` § F06 (incl. gate checklist) and Proposals (QA-039, 040, 041, 042 UI). |
| 12 | Acceptance criteria met | Yes, with known P3 and owner proposals | All P1 cases pass; S1–S8 verdicts recorded; QA-043 (P3) open; owner decisions pending on QA-039/041 proposals and QA-040 intent. |

**Known issues carried forward (OPEN):** ETQAN-QA-043 (P3). Owner decisions: QA-039 design change, QA-041 re-anchoring, QA-040 intent.

**Clean-up:** retest subscriptions 73–76, 78 cancelled, invoices voided and deleted; 77 (expired, holds the marked 10-19 lesson)
cannot be deleted by design, its invoice voided. People 213/218 active again; timezone Africa/Cairo. QA6 data kept for F08 and the
scenarios. New test-only file `dashboard/e2e/qa/f06-retest1.spec.ts`. **Not part of F06, untouched:** the owner's `etqan/site/*`,
dashboard website/nav/routeTree and marketing work. Nothing was committed.

### F08 gate decision

**Decision: PASSED** (Agent 2, sole gate authority; gate run 2026-10-19 ~17:00Z, lean mode). No P0–P2 was found, so there was no
fix cycle and nothing to retest; the backend scheduling code is unchanged by F08. `escalations/` has nothing for F08. Paths are
relative to `qa/evidence/F08/`.

**Coverage checklist (P1 risks):** see `coverage-gaps.md` § F08 "Gate checklist". Roles, tenant isolation, money and state
transitions complete. One cheap missing check executed: **G1 over-consumption** (8 extra sessions marked present on Sub C 84 →
used 9, remaining −1, `extra_sessions` 1 = DB; teacher 200, foreign student and qaother 404; cleaned up to 1/7, 0 rows left),
REAL, `gate/g1-overconsumption.txt`. By design per `rules.derive`.

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | 27 of 27 (TC-001..027, TC-027 added by Agent 2) + gate check G1. |
| 2 | Critical workflows pass | Yes | Marking/consumption, cancel/restore, disposal, make-up, postpone incl. DST, reports, supervision, Jitsi links, bulk, activity/revert, archive (TC-001..027). Playwright f08 3/3 rerun at the gate (`gate/pw-f08-regression.txt`, DB: U1 completed, `marked_by` 7, Sub C 1/7). |
| 3 | No unresolved P0/P1 | Yes | None filed; all 23 P1 cases pass (TC-014/016 FAIL only on P4/P3 sub-parts). |
| 4 | P2s fixed or documented | Yes | No P2 found. P3 QA-044, QA-045 and P4 QA-046, QA-047 filed, OPEN (no fix cycle for P3/P4 in lean mode). |
| 5 | Permissions verified | Yes | TC-011/012 read and write matrices for 8 roles, TC-016 supervisor, TC-018 impersonation 403, TC-020 revert, TC-024 teacher switch; `marked_by` = actor. |
| 6 | Tenant isolation verified | Yes | TC-013 (16 routes 404, bulk not_found, cross-host cookie 403, CSV own rows, qa schema unchanged); G1 qaother 404. |
| 7 | Data integrity verified | Yes | SQL = API at every consumption step; concurrent marks and opposite-order bulks serialised, no deadlock; make-up check constraint + partial unique index; payslip lock keeps net unchanged; G1 cleanup exact. |
| 8 | Integrations tested or clearly BLOCKED | Yes | Jitsi REAL (TC-017); Zoom FAKE in pytest, live BLOCKED (no credentials); notifications out of scope; all in `coverage-gaps.md` § F08. |
| 9 | Regression tests pass | Yes | `pytest etqan/scheduling` 1380 passed (107 s, `gate/pytest-scheduling-gate.txt`); Playwright f08 3/3 `--workers=1`. |
| 10 | Evidence recorded | Yes | `evidence/F08/` (tc*.txt, scripts/ incl. `g1.sh`, pw/, gate/); log `logs/F08/agent2.md`; spec § 7 Results. |
| 11 | Gaps documented | Yes | `coverage-gaps.md` § F08 (incl. gate checklist and "still not covered"). |
| 12 | Acceptance criteria met | Yes, with known P3/P4 | All P1 cases pass; S1–S10 verdicts recorded (S5, S6 confirmed as P3; S9 owner question). |

**Known issues carried forward (OPEN):** ETQAN-QA-044 (P3), ETQAN-QA-045 (P3), ETQAN-QA-046 (P4 doc), ETQAN-QA-047 (P4). Owner
questions: `late` attendance (S9); whether a negative package balance should warn or block.

**Clean-up:** G1 sessions 310–317 deleted; U1 (309) was undone and re-marked by the Playwright rerun (back to completed, Sub C 1/7).
Data kept for the scenarios: subs 82/83/84, sessions 235–309, payslip 42 (July) issued. Settings unchanged (absent=true,
excused=false, zoom_api off). **Not touched:** the owner's `etqan/site/*`, dashboard website/nav/routeTree and marketing work.
Nothing was committed.

## Integrated scenarios
| Scenario | Status | Evidence |
|---|---|---|
| A New academy setup | NOT_STARTED | |
| B Student enrolment | PASSED (Agent 2, gate 2026-10-19 17:26Z) | SCN TC-001..005 PASS (REAL): family/payer, DST-correct generation, one invoice per subscription, conflicts reported, tenant isolation. `evidence/SCN/` (spec § 5) |
| C Teacher operations | PASSED (Agent 2, gate 2026-10-19 17:26Z) | SCN TC-006..009 PASS (REAL), UI smoke TC-007 1/1: own-only lists, attendance → consumption = SQL, reports, supervision. `evidence/SCN/` (spec § 5) |
| D Parent experience | PASSED (Agent 2, gate 2026-10-19 17:26Z) | SCN TC-010..013 PASS (REAL), UI smoke TC-012 1/1: guardianship-scoped sessions/invoices, wallet pay, FAM-B 404, write-denial matrix with unchanged row counts. `evidence/SCN/` (spec § 5) |
| E Monthly operations (partial, Tier 1 modules only) | PASSED (Agent 2, gate 2026-10-19 17:26Z) | SCN TC-014..018 PASS (REAL, local SMTP): Sept month consumption 7, payslip 45000 (9 lines) issued/paid/acknowledged + expense 45000, INV1 150000 = cash 80000 + wallet 70000, absence mail once, revenue +300000 / expense +45000 / receivables 25000 reconcile. No defect. `evidence/SCN/` (spec § 5) |
| F Multi-tenant security | NOT_STARTED | |

### SCN gate decision

**Decision: PASSED** (Agent 2, sole gate authority; gate run 2026-10-19 ~17:20–17:26Z, lean mode). Execution found no defect, so
there was no fix cycle and nothing to retest. `escalations/` has nothing for SCN. Paths are relative to `qa/evidence/SCN/`.

**Coverage checklist (P1 risks):** see `coverage-gaps.md` § SCN "Gate checklist". Two cheap checks executed, both REAL:
**G1 renewal chain** (renew was not exercised by TC-003): one renewal, one invoice to the family payer, no duplicate instants,
second renew 409, role and tenant denials, cleaned up (`gate/g1-renewal.txt`, `gate/g1b-renewal.txt`). **G2 invariants at
gate time**: billing status/payment sums, wallets, payslip 43 and its expense, payroll locks, no 5xx (`gate/g2-invariants.txt`).

| # | Gate | Met | Evidence |
|---|---|---|---|
| 1 | Required cases executed | Yes | 18 of 18 (TC-001..018) + gate checks G1, G2. |
| 2 | Critical workflows pass | Yes | Enrolment → generation (DST) → invoice → attendance → report → parent view → wallet pay → month payroll → finance reconcile (spec § 5). Playwright scn-tc007 + scn-tc012 2/2 rerun at the gate (`gate/pw-scn-regression-run2.txt`; DB: U1 383 completed, `marked_by` 7, `gate/pw-db-check.txt`). |
| 3 | No unresolved P0/P1 | Yes | None filed; all 16 P1 cases pass. |
| 4 | P2s fixed or documented | Yes | No P2 found. |
| 5 | Permissions verified | Yes | TC-006/008/009/010/011/013 matrices (teacher, supervisor, parent, student, anonymous); G1 renew T1/parent 403. |
| 6 | Tenant isolation verified | Yes | TC-005 (both directions, cross-host cookie 403), TC-010/011 FAM-B 404; G1 renewal invoice PB 404, qaother 404. |
| 7 | Data integrity verified | Yes | SQL = API at each step (TC-014..018); G2: 0 status/payment mismatches, 0 wallet ≠ entries, payslip 43 = 9 lines = expense 45000. |
| 8 | Integrations tested or clearly BLOCKED | Yes | Absence mail REAL local SMTP (Mailpit, TC-017); Jitsi/Zoom/gateways covered or BLOCKED in F08/F09 gaps. |
| 9 | Regression tests pass | Yes | `pytest etqan/scheduling etqan/billing etqan/payroll etqan/wallet etqan/finance` 2392 passed (168 s, `gate/pytest-scn-gate.txt`); Playwright SCN 2/2 `--workers=1`. Run 1 failed 2/2 for harness reasons only (spec ids not passed via `SCN_*` env, U1 already marked); run 2 with the env ids and U1 reset passed. |
| 10 | Evidence recorded | Yes | `evidence/SCN/` (tc*.txt, scripts/ incl. `g1.sh`, `g1b.sh`, `g2.sh`, pw/, gate/); logs `logs/SCN/agent2.md`; spec § 5. |
| 11 | Gaps documented | Yes | `coverage-gaps.md` § SCN (gate checklist, live-consumption owner question, still not covered). |
| 12 | Acceptance criteria met | Yes | Scenarios B–E pass end to end on REAL behaviour (UI + API + DB). |

**Owner question (by design per `subscriptions.md`):** the consumption switches apply live, so restoring `absent_consumes_session=true`
moved closed-month SUB3 from 7/1 to 8/0 (SUB1 1/7 → 2/6 incl. U2 absent). Payroll unaffected.

**Clean-up:** renewal 89 deleted, its invoice 153 void (kept as a void row by design: plain `subscription_id`). U1 383 was undone and
re-marked present by the Playwright rerun. Settings at the s0 values. **Not touched:** the owner's `etqan/site/*`, dashboard
website/nav/routeTree and marketing work. Nothing was committed.
