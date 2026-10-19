# Etqan Tutor QA campaign — Tier 1 (started 2026-10-17)

The persistent state of the three-agent QA campaign. Approved plan:
`~/.claude/plans/streamed-chasing-bear.md`. Everything here is uncommitted on purpose: the owner
reviews before anything is recorded.

| File | Owner | Purpose |
|---|---|---|
| `environment.md` | conductor | Stack, versions, backup, accounts, workarounds |
| `feature-inventory.md` | Agent 1 | Every discovered feature, its switches and Tier |
| `test-matrix.md` | Agent 1 | Index of test cases per feature (detail in `specs/`) |
| `specs/<FNN>-<slug>.md` | Agent 1 | Full test specification per feature |
| `execution-progress.md` | **Agent 2 only** | Status per feature and per test case, gate decisions |
| `bug-register.md` | Agent 2 files, Agent 3 adds the root cause and fix, Agent 2 verifies | `ETQAN-QA-NNN` |
| `coverage-gaps.md` | Agent 1, plus Agent 3's proposals | Untested areas, blocked items, proposals needing owner approval |
| `escalations/ETQAN-QA-NNN.md` | Agent 3 → Agent 2 | Structured root-cause escalation after 3 failed attempts |
| `logs/<FNN>/agent{1,2,3}.md` | each agent | Time-stamped activity log: actions, commands, results |
| `evidence/<FNN>/` | Agent 2 | Playwright reports and traces, API JSON, DB query output, logs |
| `final-report.md` | conductor | Checkpoint report |

## Rules every agent follows
1. **Only Agent 2 sets a feature PASSED**, and only after it has retested every fix itself.
   Agent 1 never approves. Agent 3 never verifies its own fix.
2. A feature passes only on real behaviour: UI **and** API **and** DB persistence, business rules,
   permissions, tenant isolation and money correctness. A green UI test alone is never enough.
3. Every executed test carries a provider tag:
   - `REAL`: real code path, real DB and services. Local mailpit counts as REAL SMTP delivery to a
     local sink.
   - `SIMULATED`: the product's own simulator, e.g. `GATEWAYS_SIMULATE` or `ETQAN_AI_FAKE`.
   - `FAKE`: a test stub or fake provider.
   - `BLOCKED`: needs credentials or infrastructure we don't have.

   Live outside-service coverage is never claimed from SIMULATED or FAKE results.
4. Keep the MacBook's load low:
   - one docker stack;
   - Playwright with `--workers=1`;
   - one heavy job at a time (never pytest while e2e runs);
   - pytest scoped to the relevant app (`pytest etqan/<app>`) except at baseline and the checkpoint.
5. Before fixing anything, Agent 3 confirms the expected behaviour in `docs/features/*.md`,
   `docs/superpowers/specs/` or the code's documented intent. If the product is right, the test or
   the expectation is fixed, never the product.
6. Nothing is committed or pushed. Migrations, breaking API changes and major refactors are
   **proposals** in `coverage-gaps.md` and wait for owner approval.
7. When a P0/P1 bug survives 3 fix attempts, Agent 3 writes `escalations/ETQAN-QA-NNN.md` (symptom,
   hypotheses tried and evidence, suspected root cause, options). The feature becomes BLOCKED or
   FAILED, never PASSED.
8. Never use real customer data, send to real recipients, or make real payments. Every test email
   is `@qa.etqan.test` or the seeded `*.test` addresses, and is caught by mailpit.

Statuses: NOT_STARTED · RESEARCHING · READY_FOR_TEST · TESTING · FIXING · RETESTING · PASSED · FAILED · BLOCKED
Severity: P0 security/data loss/outage · P1 major functional/financial · P2 significant workflow ·
P3 minor · P4 cosmetic

## Focused mode (owner decision 2026-10-18, applies from F02 on)
- **Spec size:** about 40–60 cases per feature, mostly P1, built around real academy-owner
  workflows, money, permissions and tenant isolation. P2 only where the risk is real. P3/P4 aren't
  hunted for: if you run into one, file it, and stop there.
- **Merged features:**
  - F03 + F04 → **F03 Roles, permissions & academy settings**
  - F06 + F07 → **F06 Catalogue, subscriptions & scheduling**
  - Remaining order: F02 → F03 → F05 → F06 → F08 → F09 → F10.
- **Gap review** looks only for missed P1/P2 risks; it isn't a new full sweep.
- **Unchanged:** Agent 2 alone sets PASSED and retests every fix itself; UI + API + DB evidence; the
  REAL/SIMULATED/FAKE tags; fixes only for P0–P2; no commits; the 3-attempt escalation rule.

## Lean mode (owner decision 2026-10-18 evening: finish Tier 1 in about 10 hours with low token use)
This supersedes the case counts in Focused mode.
- **Specs:** Agent 1 writes all 7 remaining specs in parallel, read-only, with 20–30 cases each,
  about 80% of them P1.
- **Execution:** Agent 2 tests API + DB first. Each feature gets at most 2–3 Playwright UI smoke
  cases.
- **Fix cycles:**
  - One fix cycle for P0–P2.
  - A second cycle only for P0/P1.
  - Agent 2's retest and gate are combined into one run, and Agent 2 still retests every fix
    itself.
- **Gap review:** a checklist inside the gate, not a separate agent.
- **Dropped:**
  - The full 63-spec Playwright baseline; each feature runs only its own specs.
  - The 300-student seed and the performance runs.
  Both are recorded as coverage gaps.

## Scope cut (owner decision 2026-10-18 23:45: weekly usage was at 25%)
- **Execute this week:** F02 sign-in, F03 roles/permissions/settings, F09 student billing,
  F10 payroll, in that order.
- **Deferred to next week:** F05, F06 and F08. Their specs are written now, so next week starts
  straight at execution.

## Resume (owner 2026-10-19 morning)
- F05, F06 and F08 are back in scope this week. They run in lean mode, in the order F05 → F06 → F08.
- After them come the integrated scenarios B–E (enrolment → sessions → attendance → invoice →
  payroll → one simulated month).

## Paused (2026-10-19 08:17, owner)
- **F05:** PASSED.
- **F06:** paused at RETESTING. QA-039..042 are FIXED-UNVERIFIED; Agent 2's retest and gate have
  not run. **F06 is not PASSED.**
- **To resume:** run Workflow resume on `wf_08361870-d2b`, with the script
  `qa-lean-execute-wf_5eb97fa9-0b0.js` and the same args (F05, F06, F08). The cached F05 and F06
  steps replay, then the F06 retest+gate runs, then F08. After that come scenarios B–E, then the
  checkpoint report update.

## Resumed (2026-10-19 19:30)
- The new session couldn't resume run `wf_08361870-d2b`, so a fresh run, `wf_c827a266-5f3`
  (`qa-lean-finish-tier1`), continues the work.
- Its order: F06 retest + gate (fix cycle 1 was already done), then F08, then the integrated
  scenarios B–E (spec, execute, fix, gate).
- Its script is under `~/.claude-project1/projects/.../workflows/scripts/`.

## Committed (2026-10-20)
- The QA records are now committed to the meta repo.
- Local tokens and cookies in the evidence were redacted (`REDACTED-QA`), and gitleaks is clean.
- The QA Playwright specs moved from `dashboard/e2e/qa/` to `qa/e2e-specs/` so the dashboard's CI
  doesn't run them; they need the local `qa`/`qaother` academies.
- To run one again, copy it back into `dashboard/e2e/qa/` and run
  `E2E_MANAGE=~/.etqan-qa-tools/manage-wrap.sh just e2e e2e/qa/<file>`.
