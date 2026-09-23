---
number: 0042
title: The secret scan does not skip documentation-only changes
status: accepted
date: 2026-09-13
amends: ADR-0038 (CI runs only what the change can break) — for the `security` job alone
---

## Context

ADR-0038 made the seven gate jobs skip when `triage` reports a change as
documentation-only, and it counts root-level `*.md` as documentation. That is correct for
the gates it was reasoning about: a change to `STATE.md` cannot break a Django test or a
Playwright flow, and running them proves nothing.

`security` (gitleaks + `pip-audit`) rode along with the others, and for gitleaks the
reasoning does not transfer. A secret scan is not a test of the code — it is a test of the
**bytes of the commit**, and a documentation file is exactly as capable of carrying a
credential as a settings module.

This is not a hypothetical risk. It is this project's *only* observed leak, and it had
precisely that shape:

- `portal-snapshot.md` — a root-level `.md` — was caught by the first `security` run ever
  to execute here (ADR-0030).
- Live staging passwords sat in `STATE.md` on a then-public `master` for at least three
  days in September 2026. `STATE.md` is a root-level `.md`. Under ADR-0038 as written,
  the commit that put them there would have been scanned **only** when some later,
  unrelated code change happened to merge.

So the one file shape that has actually leaked here twice is the one shape the skip
exempts, and the exposure window is unbounded: it closes when the next code PR lands,
which could be days or never.

## Decision

**The `security` job drops the `code == 'true'` clause.** It runs on every push and pull
request, whatever the change touches.

The `verified != 'true'` clause **stays**. A tree whose exact content a PR already proved
green has already been scanned by this same job; re-scanning identical bytes is the waste
ADR-0038 correctly removed.

The dependabot clause stays for the reason ADR-0038 gives: those runs cannot read
`SUBMODULE_TOKEN` and die in `actions/checkout` regardless.

`pip-audit` shares this job and therefore also stops skipping. That is incidental rather
than intended — it is a dependency scan and genuinely cannot be affected by a docs change
— but splitting the job to separate them would cost a whole extra billed job minute to
save a few seconds. Not worth it.

## Consequences

- One extra job per documentation-only change. Measured against a **real invoice**, not a
  model: this repo's net Actions spend is **$0.00/month** in every month on record
  (ADR-0038 Correction). September 2026 used 2,098 of 2,000 free minutes, so the margin is
  not infinite — but a docs PR costs roughly two minutes against a scan for the failure
  mode with the worst realised outcome in this project's history.
- `record-verified-tree` and `deploy-staging` both `needs: security`. They now wait for a
  real run on docs-only pushes instead of a skip. No chain changes.
- ADR-0038's mechanism is otherwise untouched. This narrows one job's predicate; it does
  not reopen the question the ADR settled.

## What this does not fix

Submodule git *histories* are still unscanned (ADR-0030's stated gap, tracked in
`ISSUES.md`). This ADR is about *when* the scan runs, not *what* it can see.

And it is not retroactive. The passwords already in `master`'s history stay there; the
remedy for those is rotation, tracked in `ISSUES.md` under **Blocks launch**.
