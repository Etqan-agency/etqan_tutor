# ADR-0038: CI runs only what the change can break

**Status:** Accepted, amended in part by ADR-0042
**Date:** 2026-09-08 (justification corrected 2026-09-11 — see *Correction*)
**Amended:** 2026-09-13 — ADR-0042 removes the docs-only skip from the `security` job
alone. A secret scan tests the bytes of a commit, not the code, and this project's only
two observed leaks were both root-level `.md` files. Every other clause stands.
**Related:** ADR-0028 (trunk-based, a merge to the meta trunk is a deploy), ADR-0029 (API
versioning enforcement, the previous CI-as-gate change), `docs/superpowers/specs/2026-09-08-ci-cost-optimization-design.md`

## Context

`ci.yml` ran the full eight-job suite — backend lint, backend tests, dashboard lint,
dashboard build, marketing build, `e2e`, `security`, `deploy-staging` — on every pull request
and again on every merge to `master`, regardless of what changed. Twenty-six of the last
sixty meta pull requests (43%) touched only `docs/**` or a root Markdown file, and each of
them ran the same suite that proves a backend model migrated correctly. Every merge then
re-ran the whole suite a second time on a tree its own pull request had already proved green,
because a `pull_request` event and the `push` event that follows its merge check out the same
content.

**What that costs is wall-clock and attention, not money.** A docs pull request waited ~15
minutes for eight jobs that could not have learned anything about it, and every merge spent
another ~18 re-deriving a result it already had. Both numbers are measured medians over 11
pre-change runs, not a single sample. The change is worth making for the feedback loop and
for the signal-to-noise of a check row that means something; the monthly invoice for this
repository has been **$0.00 in every month on record** (see *Correction*).

There is one secondary, real cost argument, and it only became true after the fact: this
repository was public when the change was designed, and was made private by the repo owner
at some point between 2026-09-08 and 2026-09-11 (the exact date was not recorded; anonymous
access 404s as of 2026-09-11).
Actions minutes on a private repository under the org's Free plan are metered against a
2,000-minute monthly allowance, and September 2026 already used **2,098**. The change keeps a
now-metered repository inside an allowance its own usage sits exactly on top of. That is a
genuine benefit, and it is small — overage bills at $0.006/minute.

There is no branch protection anywhere in this repository (`GET
/repos/kaleem-lms/Kaleem/branches/master/protection` returns empty), so there is also no
required-check mechanism CI could lean on — anything CI decides not to run is not enforced by
GitHub, only by whether someone looks.

## Decision

A single `triage` job runs first on every event and emits two outputs: `code` (`false` iff
every changed path is `docs/**` or a root `*.md`) and `verified` (`true` iff a green run
already tested this exact git tree — always the empty string on a pull request, since the
lookup only runs on `push`). All seven gate jobs share one condition —
`needs.triage.outputs.code == 'true' && needs.triage.outputs.verified != 'true'` — so a
documentation-only change or an already-proven tree skips them.

The two questions are one job, not two, because a job skipped by `if:` also skips its
dependents: a separate guard job would have to run on pull requests too, and would add a
job's worth of queue-and-setup latency to every run. Merged into `triage`, the guard is
close to free.

The guard is a content-addressed tree-hash comparison, not a branch or commit check.
`record-verified-tree` uploads a tiny artifact named `verified-tree-<hash>` when every gate
passes on a pull request's merge ref. On the following push, `triage` computes the same hash
and queries the Actions API for an unexpired artifact of that name. A tree hash includes
submodule gitlinks and is identical under merge, squash or rebase, so this works regardless
of how the PR lands.

Every job gets `timeout-minutes` set to roughly 3× its measured wall clock. `ci.yml` had none
anywhere — GitHub's default is 360 minutes per job, so one hung process would hold a runner
for six hours and, on the now-private repository, consume three times the monthly allowance
by itself. `dependabot.yml` is trimmed to the one ecosystem that produces anything
(`github-actions`) and moved from daily to weekly. Lighthouse and the Stripe test-clock
harness move from nightly to weekly, since both measure external drift rather than our own
commits.

## Correction (2026-09-11): the original justification was arithmetic on a bill that does not exist

This ADR was first written to a stated target of "get the monthly Actions bill down", with a
modelled baseline of ~10,040 minutes/month at ~$64 and an after-figure of ~$21. **Every one of
those dollar figures was modelled and none was ever read.** The spec said so at the time and
recorded the reason: `GET /orgs/kaleem-lms/settings/billing/actions` returns `410 This
endpoint has been moved`, and the move was taken as the end of the road.

It was not. The replacement, `GET /organizations/kaleem-lms/settings/billing/usage`, answers
with the `repo` scope this project's token already had. It reports, for this repository:

| Month | Actions minutes | Gross | Discount | **Net** |
| --- | --- | --- | --- | --- |
| 2026-04 | 115 | $0.69 | $0.69 | **$0.00** |
| 2026-05 | 114 | $0.68 | $0.68 | **$0.00** |
| 2026-06 | 351 | $2.11 | $2.11 | **$0.00** |
| 2026-08 | 72 | $0.43 | $0.43 | **$0.00** |
| 2026-09 | 2,098 | $12.59 | $12.59 | **$0.00** |

Two errors, not one. The modelled baseline was roughly **5× the actual usage** in the very
month the change landed, and the amount actually paid has been **zero in every month on
record** — the included allowance covers it. The published overage rate is $0.006/minute, not
the $0.008 the spec used.

A first attempt at this correction, on 2026-09-08, replaced the false premise with a second
false one: that the repository was public and therefore its runners free. It was public then
and is private now, but that was never the reason the bill was zero — the invoice above shows
metered, fully-discounted minutes. The reading that supposedly proved "public", `billable.
total_ms: 0` from `actions/runs/<id>/timing`, returns **0 on this repository while private
too**, including on a full eight-job 501-second run. That field is not evidence of anything.

The lesson is the one this project keeps re-learning at one level up each time. C3b: the
suite could not represent the thing it claimed to test. C3d: the e2e passed under a deleted
override and could never have passed in CI. Here: the measurement was careful, the premise
under it was never checked — and then the *correction* to the premise was not checked either.
The endpoint that would have settled it on day one was one call away and was written off
after a single `410`.

**The mechanism in this ADR is unaffected and stays.** It was verified on a real merge and it
does what it says. What changed is why it is worth having: wall-clock and signal, plus
keeping a newly-private repository inside an allowance it is already brushing against.

## Alternatives considered

**Workflow-level `paths-ignore`.** The simplest possible fix, and rejected for a specific
reason: a required check that `paths-ignore` causes to never run stays pending forever on a
protected branch, which would matter the instant branch protection is enabled on this repo.
The `triage`-and-skip design instead makes every job run and report a real (skipped) status,
so it degrades safely into a future with branch protection rather than needing to be revisited
first.

**Merging the seven gate jobs into roughly four**, to stop paying checkout-and-toolchain-setup
seven times over. Each job pays 30–40 seconds before doing any work. Deferred; the diff for
this change stays reviewable because it changes *when* jobs run, not *what* they do.

**A self-hosted runner.** Would take metered minutes to zero for a fixed ~$6–12/month — which,
against a bill of $0.00, is a straight loss and was rejected on cost even before the other
objection: it puts CI on infrastructure this project maintains, and the natural place to host
it, the staging box, would put CI in resource contention with staging itself.

## Consequences

**A code pull request costs about two extra jobs.** `triage` and `record-verified-tree` each
run on every PR, even a tiny one, adding queue-and-setup latency and two metered minutes. The
guard is paid for on pull requests and redeemed on merges — net positive only because merges
are frequent here, which they are.

**The push run stops being a second chance to notice a red gate.** Before this change, a
merge to `master` re-ran the full suite, so a gate that was somehow wrong on the PR (a flaky
pass, a reviewer merging before the run finished) got one more shot at going red before
`deploy-staging` shipped it. That second run is now skipped whenever the guard matches. With
no branch protection anywhere on this repository, "green CI before merge" (D5) has always been
a habit rather than an enforced gate — this change does not create that gap, but it makes the
habit's absence more consequential, because the push run is no longer there to catch a lapse
in it.

**`security` (gitleaks) now skips on documentation-only changes, and root `*.md` counts as
documentation.** This project's one previous leaked secret was `portal-snapshot.md` — a
root-level Markdown file, caught by the first `security` run. Gating that particular job on
`code == 'true'` delays the scan of exactly the file shape that has leaked here before, until
the next code pull request. The saving is one job; the exposure window is unbounded. This
clause should be dropped from `security` alone — tracked in `ISSUES.md`.

**Dependabot PRs now report green where they previously reported red, and that is a real
regression, not a wash.** Every gate already carried `github.actor != 'dependabot[bot]'`
because Dependabot cannot read `secrets.SUBMODULE_TOKEN` and every job died in checkout
anyway — six minutes to fail, testing nothing. Skipping those jobs outright is cheaper and no
less honest about what got tested. But GitHub counts a *skipped* required status check as
satisfying that check, where a *failed* one does not. If branch protection is ever turned on,
a Dependabot PR would appear mergeable with a clean row of green checks and zero verification
behind any of them — worse than today's red-and-obviously-broken state, because it looks
trustworthy. Three such PRs are open right now: #182 (`setup-python` 5→7), #183
(`upload-artifact` 4→7), #184 (`setup-node` 6→7). `ci.yml` pins `upload-artifact@v4`, so #183
is a real version upgrade this repository has not taken yet, and it deserves a deliberate look
rather than a merge on the strength of a green tick that tested nothing.
