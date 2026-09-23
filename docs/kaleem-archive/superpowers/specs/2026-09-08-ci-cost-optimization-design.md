---
name: ci-cost-optimization
phase: 0
modules: []
status: shipped
created: 2026-09-08
closed: 2026-09-08
---

## ⚠ Correction (2026-09-11): every cost figure below is wrong, and the change stands anyway

**Read this before any number in this document.** This spec's stated target — "get the
monthly Actions bill down" — was arithmetic on a bill that does not exist, and the figures
were out by roughly 5×.

The spec records that the real invoice could not be read, because
`GET /orgs/kaleem-lms/settings/billing/actions` returns `410 This endpoint has been moved`.
The move was taken as the end of the road. It was not: the replacement,
`GET /organizations/kaleem-lms/settings/billing/usage`, answers with the `repo` scope this
project's token already had. What it reports for this repository:

| Month | Actions minutes | Gross | Discount | **Net** |
| --- | --- | --- | --- | --- |
| 2026-04 | 115 | $0.69 | $0.69 | **$0.00** |
| 2026-05 | 114 | $0.68 | $0.68 | **$0.00** |
| 2026-06 | 351 | $2.11 | $2.11 | **$0.00** |
| 2026-08 | 72 | $0.43 | $0.43 | **$0.00** |
| 2026-09 | 2,098 | $12.59 | $12.59 | **$0.00** |

- Modelled baseline ~10,040 min/month vs **2,098 actual** in the month the change landed.
- Amount actually paid: **$0.00, every month on record** — the included allowance covers it.
- Overage rate is **$0.006/min**, not the $0.008 used below.

Everything below this banner is left unedited as the record of what was designed and why,
including the figures now known to be wrong. The *mechanism* is unaffected and was verified on
a real merge; the justification is rewritten in **ADR-0038 → Correction**, around wall-clock
and signal plus keeping a now-private repository inside its 2,000-minute allowance.

A first attempt at this correction (2026-09-08) replaced the false premise with a second false
one — "the repo is public, so runners are free". It was public then and is private now, but
that was never why the bill was zero. The reading behind it, `billable.total_ms: 0` from
`actions/runs/<id>/timing`, returns 0 on this repository **while private too**, including on a
full eight-job 501-second run. That field is not evidence of anything.

---

## Goal

CI runs the full eight-job suite on every pull request and then runs it again on the merge
to `master`, regardless of what changed. Forty-three per cent of the meta repo's pull
requests touch only documentation, and every one of them runs the backend test suite,
Playwright, three container builds and a full-history secret scan to prove that a Markdown
file did not break anything.

This spec stops CI doing work that cannot tell us anything, without weakening a gate that
can. It has one measurable target: get the monthly Actions bill down, and say honestly how
far down it gets — which is *not* to zero.

## What it costs today

Measured, not estimated, from run `34177257278` (a push to `master`, 2026-09-08). GitHub
bills each job separately and **rounds every job up to a whole minute**, so the billed figure
is materially higher than the wall-clock sum:

| Job | Wall clock | Billed |
| --- | --- | --- |
| `dashboard-lint` | 4.50 min | 5 |
| `deploy-staging` | 3.03 min | 4 |
| `e2e` | 3.00 min | 3 |
| `backend-test` | 1.52 min | 2 |
| `security` | 0.73 min | 1 |
| `dashboard-build` | 0.67 min | 1 |
| `backend-lint` | 0.52 min | 1 |
| `marketing-build` | 0.42 min | 1 |
| **push to `master`** | | **18** |
| **pull request** (same minus deploy) | | **14** |

Within `dashboard-lint`, 238 of its 270 seconds are `vitest --coverage`. Within
`deploy-staging`, 101 seconds are three uncached `docker build` invocations.

Run volume over the last seven days: **151 runs** — 84 `pull_request`, 57 `push`, 3 nightly
Lighthouse, 3 nightly Stripe test clock, 3 manual dispatches, 1 Dependabot. That is
**~2,260 billed minutes/week ≈ 9,700/month**.

Activity is bursty: the last 30 days as a whole hold only 159 runs, because nearly all of it
landed in the final week. The 9,700 figure is the *current* pace, not a historical average.
It is the right number to design against, because the pace is the working rhythm of the
project, not an anomaly.

### Correction, added at close: the 14/18-minute baseline was one run, and the job varies 3.5x

The table above quotes a 14-minute PR run and an 18-minute push run from a single sample,
run `34177257278`. Measured across 11 pre-change runs while building this spec (Task 5):

| | n | median | range |
| --- | --- | --- | --- |
| PR run | 6 | **15** | 13–16 |
| push run | 5 | **18** | 17–19 |

The push figure was correct; the PR figure was one minute low. The cause is `dashboard-lint`'s
"Tests with coverage" step, which took **83–296 seconds for identical work** — verified
identical, not assumed: 112 test files passed and coverage read 95.84/91.99/88.14/95.84 in
both the fastest and the slowest of the 11 runs, against the same `dashboard` submodule
pointer. That is a 3.5x swing on the single largest job in the suite, worth 2 to 5 billed
minutes depending on which side of a minute boundary it lands, and the original baseline was
sampled at the slow end of that range.

Corrected model, same method as below: baseline **~10,040 min/month (~$64)**, after
**~4,650 min/month (~$21)**. **The 54% headline is unchanged** — the savings in this spec come
entirely from not running jobs at all, and job-duration variance does not touch that; a slower
or faster `dashboard-lint` changes the *baseline* cost, not the *fraction* this change removes
from it. The 14/18 figures and the ~$62/~$19 figures elsewhere in this spec are corrected to
15/18 and ~$64/~$21 accordingly; where they appear as inline numbers below they are left as
the values used to design the change, since correcting every occurrence would rewrite
arithmetic that this document also needs to remain checkable against the run it was computed
from.

### The billing figures in this spec are modelled, not read

The org is on **GitHub Free**: `GET /repos/kaleem-lms/Kaleem/rulesets` returns
`403 Upgrade to GitHub Pro or make this repository public`, and
`GET /repos/kaleem-lms/Kaleem/branches/master/protection` returns empty. Free for
organizations documents 2,000 included Actions minutes per month, with Linux overage at
$0.008/minute.

**The actual invoice was not read.** `GET /orgs/kaleem-lms/settings/billing/actions` returns
`410 This endpoint has been moved`, and its replacement needs the `admin:org` scope, which
this session's token does not have. Every dollar figure below is
`run count × measured per-job billed minutes × published rate`. Treat them as a model whose
*inputs* are measured and whose *output* has never been checked against a bill. Confirming
one month's real invoice against this model is a task in the test plan, not an assumption.

Modelled: ~9,700 min/month, ~7,700 over the allowance, **~$62/month**.

## Where the money goes

Three findings, in order of size.

**1. Documentation pays the full price.** Twenty-six of the last sixty pull requests
(`#187, #181, #180, #179, #177, #175, #173, #171, #168, #161 …`) touched only `docs/**` and
root Markdown. There are no path filters anywhere in `ci.yml`. Each costs 14 minutes on the
PR and 18 more on the merge.

**2. Every merge pays twice.** For a `pull_request` event, `actions/checkout` checks out the
*merge ref* — master with the branch merged in. That is the same content the merge commit
will have. The push run re-derives a result the PR run already has, at 14 minutes a time,
57 times a week.

**3. Dependabot bills six minutes to fail.** `.github/dependabot.yml` is the unmodified
cookiecutter-django file: nine ecosystems on `interval: daily`, seven of them pointed at
`compose/local/django/`, `compose/production/traefik/` and similar — **all seven confirmed
absent** from this repo — plus a `pip` entry for a root `requirements*` that does not exist.
Only the `github-actions` entry produces anything, and those PRs can never pass: a Dependabot
pull request cannot read `secrets.SUBMODULE_TOKEN`, so the recursive submodule checkout dies
in every job. Run `34107074396` billed 6 minutes across six jobs that each failed inside 31
seconds. Three such runs on 2026-09-07 alone.

## The change

### 1. A single `triage` job

A job that is skipped by an `if:` condition causes its dependents to skip as well. So change
detection and the deploy guard cannot be two jobs — the guard would have to run on pull
requests too, and GitHub's **one-minute floor per job** would charge for it every time.
They are one job:

```text
triage   (always runs, ~15s wall, bills 1 min, no submodules)
  outputs:
    code      "false" iff every changed path is docs/** or a root *.md
    verified  "true"  iff a green run already tested this exact tree
              (always "false" on a pull_request event — the lookup runs only on push)
```

All seven gate jobs carry the *same* condition, which is what makes it cheap to extend:

```yaml
if: >-
  needs.triage.outputs.code == 'true'
  && needs.triage.outputs.verified != 'true'
  && github.actor != 'dependabot[bot]'
```

The third clause is explained in part 5.

### 2. The classifier is an allowlist that fails toward running

`.github/scripts/classify-changes.sh` takes a base and a head ref and emits `code=true|false`.
A change is documentation-only **only if every** path matches `docs/**` or a root-level
`*.md`. The `case` statement's default branch is `code`, so a path nobody anticipated runs
the full suite rather than being silently skipped.

Explicitly classified as **code**, not docs:

- anything under `.github/**` — a CI change must be tested by the CI it changes
- any submodule pointer (`backend`, `dashboard`, `marketing`, `infra`, `tokens`) — a pointer
  bump *is* a code change, and it is the whole reason the gates exist in the meta repo
- `.gitleaksignore` — it changes what the `security` job considers green

Diff ranges: `merge-base(base, head)..head` for a pull request,
`github.event.before..github.sha` for a push. When `github.event.before` is the all-zero SHA
(new branch, force-push) the classifier returns `code`.

`.github/scripts/test-classify-changes.sh` holds table-driven cases and runs **as a step of
the `triage` job itself** — about a second, no separate job, no extra billed minute. The
thing that decides what to skip is therefore checked on every single run. This is deliberate:
the recurring failure of the last phase was a verifier that was itself unverified.

### 3. The deploy guard compares tree hashes

A tree hash is content-addressed and includes submodule gitlinks. Two commits with identical
content have identical tree hashes regardless of how they were produced — so this works the
same under merge, squash and rebase merges.

On a pull request, `actions/checkout` gives us the merge ref, so `git rev-parse HEAD^{tree}`
**is** the tree that was tested. A new job records it:

```text
record-verified-tree
  needs: [triage, backend-lint, backend-test, dashboard-lint,
          dashboard-build, marketing-build, e2e, security]
  if:    github.event_name == 'pull_request' && needs.triage.outputs.code == 'true'
         && all gates succeeded
  → uploads a ~20-byte artifact named  verified-tree-<hash>,  retention 7 days
```

On a push to `master`, `triage` computes `HEAD^{tree}` and queries
`GET /repos/{owner}/{repo}/actions/artifacts?name=verified-tree-<hash>`:

- **found** → `verified=true`; the seven gates skip, `deploy-staging` runs
- **not found** → `verified=false`; the full suite runs, then `deploy-staging`

A direct push to `master`, a force-push, a merge of a PR whose green run has aged past the
7-day artifact retention, and a merge where `master` moved underneath the PR all produce a
tree with no recorded green run, and all therefore run the full suite. Nothing about this
requires a human to remember a rule.

The `record-verified-tree` job is skipped on a documentation-only PR, because its gates were
skipped. That is correct and self-consistent: the matching documentation-only push has
`code=false`, so it skips the gates *and* the deploy.

### 4. `deploy-staging` needs explicit result checks

Its `needs:` list will now routinely contain legitimately skipped jobs, and GitHub's default
`if:` semantics ("every needed job succeeded") would skip the deploy along with them. It
becomes explicit:

```yaml
if: >-
  !cancelled()
  && !contains(needs.*.result, 'failure')
  && github.ref == 'refs/heads/master'
  && github.event_name == 'push'
  && needs.triage.outputs.code == 'true'
```

This is the fiddliest expression in the change. It is verified by execution on a real branch
before the pull request opens, not by reading documentation — see the test plan.

### 5. Dependabot and the nightlies

`.github/dependabot.yml` is rewritten: delete the seven phantom Docker ecosystems and the
root `pip` entry, keep `github-actions`, move it from `daily` to `weekly`.

Dependabot's PRs still cannot read `secrets.SUBMODULE_TOKEN`, so they would still bill six
minutes to fail. **All seven gate jobs check out submodules recursively** — not four, as an
earlier reading of `ci.yml` suggested — so every one of them is unrunnable for a Dependabot
actor, and every one of them already carries the identical `if:` from part 1. The
`&& github.actor != 'dependabot[bot]'` clause therefore costs one line in an expression that
is repeated seven times regardless; no third `triage` output is needed.

A Dependabot PR is then `triage` alone: one billed minute, and the only check it can
meaningfully pass — the classifier self-test, which needs neither submodules nor a secret.
The trade is stated plainly: **a Dependabot action bump is no longer tested by this CI before
it is merged.** That is not a regression, because today it is not tested either — it fails at
checkout — it is just no longer six minutes of failing to test it. Reviewing an Actions
version bump by hand is the compensating control, and it is what already happens.

### 6. A cost ceiling: `timeout-minutes` on every job

`ci.yml` sets **no `timeout-minutes` anywhere** — `grep -c` returns 0. GitHub's default is
**360 minutes per job**. One hung `pnpm install`, one `curl` waiting on a dead host, one
Playwright process that never exits, and a single job bills six hours: more than two full
weeks of the savings this spec is built to produce.

Every job gets a `timeout-minutes` at roughly 3× its measured wall clock — enough headroom
that a slow runner never trips it, low enough that a hang is capped:

| Job | Measured | `timeout-minutes` |
| --- | --- | --- |
| `triage`, `record-verified-tree` | ~0.3 min | 5 |
| `backend-lint`, `marketing-build`, `dashboard-build`, `security` | 0.4–0.7 min | 10 |
| `backend-test` | 1.5 min | 10 |
| `e2e` | 3.0 min | 15 |
| `dashboard-lint` | 4.5 min | 15 |
| `deploy-staging` | 3.0 min | 20 |

This is insurance, not a saving — it changes nothing about a healthy run. It is in this spec
because it is a one-line-per-job change to the same file, and because a single hung job costs
more than everything else here saves in a fortnight.

Lighthouse and the Stripe test clock move from nightly to weekly (`cron` day-of-week pinned).
Both measure external drift, not our own commits; ADR-0030 and the Stripe harness spec both
justify them as out-of-merge-path signals, and neither argument depends on a 24-hour period.
56 billed minutes a week becomes 8.

The Stripe harness's unique value is narrower than "the `past_due` → `unpaid` path," and
stretching its cadence only stretches detection of that narrower thing. The harness also
exercises the **local** `past_due` → `unpaid` state machine, not only Stripe's `dahlia` payload
shape — but that local logic is already covered on every pull request by
`backend/kaleem/billing/tests/`: `test_invoice_payment_failed_marks_past_due`,
`test_past_due_is_still_entitled`, `test_unpaid_is_not_entitled`,
`test_past_due_keeps_access_through_the_provider_retry_schedule`, and
`test_unpaid_is_still_live_but_no_longer_entitled`. So a regression in the state machine itself
would still be caught within minutes, on the PR that introduced it, regardless of this cadence
change. What the weekly move actually stretches detection *for* is the thing nothing else
covers: whether a real Stripe webhook, shaped by Stripe's own API version, still parses and
drives that machine correctly. That is the harness's real, narrower job, and it is the reason
moving it to weekly is an acceptable trade rather than a silent widening of a gap.

## What this buys, and what it does not

| | now | after |
| --- | --- | --- |
| documentation-only PR run | 14 min | **1** |
| code PR run | 14 min | 16 |
| push to `master`, tree verified | 18 min | **5** |
| documentation-only push | 18 min | **1** |
| Dependabot PR | 6 min | 1 |
| nightlies | 56 min/wk | 8 min/wk |
| **per week** | ~2,260 | **~1,035** |
| **per month (modelled)** | ~9,700 · **~$62** | ~4,430 · **~$19** |

A 54% cut. The weekly figure is
`34×1 (docs PR runs) + 50×16 (code PR runs) + 23×1 (docs pushes) + 34×5 (verified pushes) + 8
(nightlies) = 1,035`, against a measured baseline of 84 PR runs and 57 pushes per week.

**This table's "now" column and dollar figures are the design-time baseline, corrected above.**
The corrected sample (11 runs, not 1) puts the baseline nearer ~10,040 min/month (~$64) and the
after-figure nearer ~4,650 min/month (~$21) — see "Correction, added at close" earlier in this
document. The 54% cut and every per-row minute figure in this table are unaffected: they come
from not running a job at all, which is a property of `code`/`verified`, not of how long any
one job happens to take on a given runner.

One soft input: the 43% documentation-only figure is measured over *pull requests*, and the
split is applied here to *runs*. A branch that gets three pushes produces three runs, and code
branches are pushed to more often than documentation branches, so 43% of PRs is probably fewer
than 43% of runs. The model uses 40% to lean against that, but it is the least solid number in
this spec — and it is the one the real invoice will correct.

**Two things this table is not hiding.** A code pull request gets *more* expensive, by two
minutes: `triage` and `record-verified-tree` each pay the one-minute floor. The guard is paid
for on pull requests and redeemed on pushes; it nets strongly positive only because merges
are frequent here.

And **this does not reach $0.** The residual ~2,430 overage minutes are two things: every one
of the seven jobs pays 30–40 seconds of checkout-with-five-recursive-submodules plus toolchain
setup before it does any work, and `vitest --coverage` takes 238 seconds. Both are real and
both are out of scope here — see below.

## Out of scope

Deliberately excluded, so the diff stays reviewable and the risky work is its own decision:

- **Merging the seven gate jobs into roughly four** to stop paying checkout-and-setup seven
  times over. Real savings, but it rewrites every job and trades wall-clock for minutes.
- **Caching pip, the Playwright browser, and Docker layers.** Worth less than it looks under
  per-job minute rounding — a job going from 1.52 to 1.1 minutes still bills 2 — so it only
  pays where it crosses a minute boundary.
- **Making `vitest --coverage` faster.** The largest single line item, and the one most likely
  to change what "green" means. It deserves its own spec.
- **A self-hosted runner.** Would take Actions minutes to zero for a fixed ~$6–12/month, but
  puts CI on infrastructure we maintain and, if hosted on the staging box, in contention with
  staging.
- **Per-repository gate granularity** — skipping `backend-test` when only the `marketing`
  pointer moved. Tempting, but `e2e` and `lint-imports` span repositories, and getting it
  wrong skips a gate that mattered. One boolean now.
- **Changing any coverage floor, e2e flow, or scanner.** Nothing in this spec alters what a
  gate checks; it only changes *when* a gate runs.

## Test plan

The classifier and the guard are the two things that can silently skip a gate, so both are
verified by breaking them, not by watching them pass.

**Classifier, automated.** `test-classify-changes.sh` runs in `triage` on every run and must
cover: docs-only; docs plus a submodule pointer; a submodule pointer alone; a `.github/**`
change alone; a `.gitleaksignore` change alone; an unrecognised top-level path; an empty diff;
and the all-zero `before` SHA. Mutation check: invert the default branch of the `case`
statement to `docs` and confirm the suite goes red.

**Classifier, on a real branch.** Push a docs-only commit and confirm exactly one job runs.
Push a commit touching one submodule pointer and confirm all seven gates run.

**Guard, both directions.** This is the D9 manual check and it is the one that matters:

1. Open a code PR, let it go green, merge it. Confirm the `master` push run skips the seven
   gates, that `deploy-staging` still runs, and that staging receives the new images.
2. On a second code PR, let it go green, then **delete its `verified-tree-<hash>` artifact**
   (`gh api -X DELETE /repos/{owner}/{repo}/actions/artifacts/{id}`) before merging. Confirm
   `triage` reports `verified=false` and the **full suite runs** on the push. Without this
   half, a guard hard-wired to `true` would look identical to a working one.

   Deleting the artifact is exactly what its 7-day expiry does, so this is the real failure
   path and not a simulation of one. It is used **instead of pushing an untested commit
   straight to `master`**, which is what an earlier draft of this test plan called for and
   which ADR-0028 forbids.
3. Confirm a documentation-only push to `master` runs neither the gates nor the deploy.

**`deploy-staging`'s `if:` expression.** Verified by execution, on a scratch branch with the
job's body replaced by `echo`, across all four combinations of (gates skipped / gates run) ×
(code / docs). GitHub's `needs.*.result` semantics around skipped jobs are exactly the kind of
thing that reads correctly and behaves otherwise.

**The billing model.** After one full month, read the real invoice — with a token carrying
`admin:org`, or from the billing page — and compare it against this spec's ~$19 projection.
If the model is wrong, the number to correct is in this file.

## What this spec cannot prove

- **That the modelled savings match a bill.** Every figure here is derived from run counts and
  measured job durations against the published rate. The invoice was never read (see above).
  The *shape* of the saving — 14 billed minutes becoming 1 on a docs PR — is arithmetic on
  measured values and is solid; the monthly dollar total depends on a run-rate that varies by
  a factor of six between the last 7 days and the last 90.
- **That a tree hash recorded by a green PR run means that PR was correct.** It means the same
  content passed the same gates. If a gate is weak, this change propagates that weakness one
  merge sooner; it does not create it.
- **That skipping gates on a verified push is safe against a compromised artifact.** Any actor
  who can upload an artifact to this repository can name it `verified-tree-<hash>` and cause a
  matching push to skip its gates. On a private repository with one collaborator this is not a
  meaningful threat, and it is strictly weaker than that actor's existing ability to push to
  `master` directly. It is recorded here rather than discovered later.

## Risks

- **The classifier is the only thing standing between a code change and a skipped gate.** It
  is 30 lines of shell. That is why it self-tests on every run and why its default is `code`.
- **There is no branch protection to fall back on.** GitHub Free provides none for private
  repositories, and none is configured. "Green CI before merge" (D5) is a habit, not an
  enforced gate, today and after this change. This spec does not make that worse, but it does
  make the habit's absence more consequential, because the push run stops being a second
  chance to notice.
- **Artifact retention is a silent expiry.** A PR that goes green and is merged eight days
  later runs the full suite. Correct behaviour, but it will look like the guard is broken.
  The runbook note must say so.

## Open questions

None. The one that was open at drafting — whether the Dependabot short-circuit should be a
`github.actor` clause or a third `triage` output — resolved on inspection: all seven gate jobs
already share one identical `if:` expression, so the clause is free and the extra output would
be indirection for its own sake.

## What shipped verified, and what did not

**Verified, on run `34206968953`** — a `push` to `master` at commit `480b78b`, the first merge
of the pull request that shipped this change (PR #190). The prediction — merge-ref tree
`e3bd1f1aa5ddae6d0772bc9e3f7e3636432724f5`, and an unexpired artifact of exactly that name
(id `10047768648`) already on record — was written down **before** the merge, so this is a
falsifiable result, not a post-hoc reading:

- `triage`: `code=true`, `tree=e3bd1f1aa5ddae6d0772bc9e3f7e3636432724f5 verified=true`
- all seven gates: `SKIPPED`
- `deploy-staging`: `success`, all 14 steps green, including the three image builds, the infra
  config sync, and the SSH `ship.sh` run
- staging live afterwards: `app-staging` 200, `api-staging` `/health/ready/` 200,
  `staging.kaleem.academy` 200, `ws-staging` `/health/live/` 200
- cost: **4 billed minutes**, against a baseline median of 18 for a `master` push — a 78% cut
  on this one merge, consistent with the modelled figure

The guard's positive-lookup mechanics (artifact naming and the content-addressed match) were
also exercised earlier and separately, on that pull request's own `pull_request` run:
`record-verified-tree` uploaded a tree, and a direct `gh api` query for that same artifact
name returned 1. That proved the naming and lookup were correct; it did not exercise the
guard step itself, since that step only runs on `push`. The push above is what closed that gap.

**Not verified, and left open rather than assumed.** The artifact-*miss* path — a code push
whose tree has no recorded `verified-tree-<hash>` artifact — has never run on a real push. The
mitigating evidence is real but partial: the guard's `gh api` query was observed, locally,
returning 0 for a name that does not exist and 1 for one that does; and `verified != 'true'`
is the same branch every PR run in this session already exercised, because `verified` is the
empty string there. Neither of those is the specific case of a `push` event where `triage`
computes a tree, queries for it, gets zero results, and the seven gates then actually run to
completion. That case is untested. The runbook (`docs/runbook/ci.md`) names the two ordinary
ways it will occur on its own — the 7-day artifact expiry, and `master` moving under a PR — and
how to force it deliberately by deleting the artifact before merging. The Dependabot path is
also untested in both its PR and push forms: three real Dependabot PRs are open (#182, #183
and #184), and none has been merged since this change shipped, so `github.actor !=
'dependabot[bot]'` has only been read, never exercised against a real Dependabot event.
