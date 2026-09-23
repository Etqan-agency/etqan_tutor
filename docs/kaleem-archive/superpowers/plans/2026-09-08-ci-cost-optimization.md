# CI Cost Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the meta repo's GitHub Actions bill by roughly half by never running a gate that cannot tell us anything — documentation-only changes, and merges re-proving a tree a green PR already proved.

**Architecture:** One `triage` job classifies the diff and looks up whether a green run already tested this exact git tree; all seven gate jobs hang off its two outputs. A `record-verified-tree` job publishes the tree hash a green PR proved, as a named artifact. Nothing about *what* any gate checks changes — only *when* it runs.

**Tech Stack:** GitHub Actions workflow YAML, Bash, `gh` CLI (preinstalled on runners), `actions/upload-artifact@v4`.

**Spec:** `docs/superpowers/specs/2026-09-08-ci-cost-optimization-design.md`

## Global Constraints

- **Trunk-based, no exceptions (ADR-0028, D15).** All work on `feat/ci-cost-optimization`, PR into `master`. Never commit to `master`. Check `git branch --show-current` before every commit.
- **A merge to meta `master` IS a staging deploy.** The final task deliberately merges to exercise the guard; do not merge casually before then.
- **Pre-commit is blocked by a dead pip proxy.** Prefix every `git commit` with `PIP_CONFIG_FILE=/dev/null`. Never use `--no-verify` (D5).
- **The classifier's default must be `code`.** Every branch that is not provably documentation returns `true`. A path nobody anticipated runs the full suite.
- **Documentation-only means:** every changed path matches `docs/**` or a **root-level** `*.md`. Nothing else. `.github/**`, `.gitleaksignore`, and every submodule pointer (`backend`, `dashboard`, `marketing`, `infra`, `tokens`) are code.
- **Repo is `kaleem-lms/Kaleem`**, org on GitHub Free (no branch protection exists — do not assume a required check will stop anything).
- Commit message trailer: `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`

---

### Task 1: The change classifier and its self-test

The classifier is the only thing standing between a code change and a skipped gate, so it is built test-first and ships with a test that runs in CI on every single run.

**Files:**
- Create: `.github/scripts/classify-changes.sh`
- Create: `.github/scripts/test-classify-changes.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `.github/scripts/classify-changes.sh <base-ref> <head-ref>` prints exactly `true` or `false` on stdout (`true` = contains code). Also accepts `--paths-from-stdin`, reading newline-separated paths. `.github/scripts/test-classify-changes.sh` exits 0 on pass, 1 on any failure.

- [ ] **Step 1: Write the failing test**

Create `.github/scripts/test-classify-changes.sh`:

```bash
#!/usr/bin/env bash
# Table-driven tests for classify-changes.sh.
#
# This runs as a step of the `triage` job, so the thing that decides what CI
# skips is itself checked on every run. That is deliberate: the recurring
# failure of the last phase was a verifier that was itself unverified.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
classify="$here/classify-changes.sh"
fail=0

# Assert the classification of a literal list of paths.
expect_paths() {
	local want="$1" name="$2"
	shift 2
	local got
	got="$(printf '%s\n' "$@" | "$classify" --paths-from-stdin)"
	if [ "$got" != "$want" ]; then
		echo "FAIL: $name -- want code=$want, got code=$got"
		fail=1
	else
		echo "ok: $name"
	fi
}

expect_paths false "docs and root markdown only" \
	"docs/superpowers/specs/2026-09-08-ci-cost-optimization-design.md" "STATE.md"
expect_paths false "every root markdown file we keep" \
	"README.md" "CLAUDE.md" "ISSUES.md" "AGENTS.md"
expect_paths true "docs plus a submodule pointer" "STATE.md" "backend"
expect_paths true "a submodule pointer alone" "dashboard"
expect_paths true "a workflow change alone" ".github/workflows/ci.yml"
expect_paths true "the gitleaks allowlist alone" ".gitleaksignore"
expect_paths true "an unrecognised top-level file" "justfile"
expect_paths true "a nested non-docs path" "infra/docker-compose.production.yml"
expect_paths true "a docs-named file outside docs/" "src/docs/thing.md"

# An empty diff is not evidence that nothing changed -- it is evidence that we
# could not see what changed. Run everything.
got="$(printf '' | "$classify" --paths-from-stdin)"
if [ "$got" != "true" ]; then
	echo "FAIL: empty diff -- want code=true, got code=$got"
	fail=1
else
	echo "ok: empty diff"
fi

# A force-push or a brand-new branch gives an all-zero `before` SHA.
zero="0000000000000000000000000000000000000000"
got="$("$classify" "$zero" HEAD)"
if [ "$got" != "true" ]; then
	echo "FAIL: all-zero base -- want code=true, got code=$got"
	fail=1
else
	echo "ok: all-zero base"
fi

# An unreachable base ref (history rewritten under us) must not crash the job.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp"
: > "$tmp/STATE.md"
git -C "$tmp" add STATE.md
git -C "$tmp" -c user.email=t@example.com -c user.name=t commit -qm "seed"
got="$(cd "$tmp" && "$classify" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef HEAD)"
if [ "$got" != "true" ]; then
	echo "FAIL: unreachable base -- want code=true, got code=$got"
	fail=1
else
	echo "ok: unreachable base"
fi

if [ "$fail" -ne 0 ]; then
	echo "classify-changes.sh: FAILURES"
	exit 1
fi
echo "classify-changes.sh: all cases pass"
```

Make it executable:

```bash
chmod +x .github/scripts/test-classify-changes.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `.github/scripts/test-classify-changes.sh`

Expected: FAIL — `classify-changes.sh: No such file or directory` (the script under test does not exist yet).

- [ ] **Step 3: Write the classifier**

Create `.github/scripts/classify-changes.sh`:

```bash
#!/usr/bin/env bash
# Classify a change as documentation-only or code.
#
#   classify-changes.sh <base-ref> <head-ref>
#   classify-changes.sh --paths-from-stdin      (newline-separated paths)
#
# Prints "true" if the change contains code, "false" if every changed path is
# documentation. Callers skip CI gates only on "false".
#
# THE DEFAULT IS "true". A path nobody anticipated, an unreadable diff, an
# empty diff and an all-zero base SHA all return "true" and run the full
# suite. Skipping a gate we needed is unrecoverable; running one we did not
# need costs a minute.
set -euo pipefail

readonly ZERO_SHA="0000000000000000000000000000000000000000"

# Documentation is `docs/**` and root-level `*.md`, and nothing else.
# Ordering matters: the `*/*` arm catches every nested non-docs path
# (.github/workflows/ci.yml, infra/..., src/docs/x.md) before the `*.md` arm
# can mistake it for root markdown.
is_docs_path() {
	case "$1" in
	docs/*) return 0 ;;
	*/*) return 1 ;;
	*.md) return 0 ;;
	*) return 1 ;;
	esac
}

main() {
	local paths

	if [ "${1:-}" = "--paths-from-stdin" ]; then
		paths="$(cat)"
	else
		local base="${1:-}" head="${2:-}"
		if [ -z "$base" ] || [ -z "$head" ] || [ "$base" = "$ZERO_SHA" ]; then
			echo "true"
			return 0
		fi
		if ! paths="$(git diff --name-only "$base" "$head" 2>/dev/null)"; then
			echo "true"
			return 0
		fi
	fi

	if [ -z "$paths" ]; then
		echo "true"
		return 0
	fi

	while IFS= read -r path; do
		[ -z "$path" ] && continue
		if ! is_docs_path "$path"; then
			echo "true"
			return 0
		fi
	done <<<"$paths"

	echo "false"
}

main "$@"
```

Make it executable:

```bash
chmod +x .github/scripts/classify-changes.sh
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `.github/scripts/test-classify-changes.sh`

Expected: PASS — twelve `ok:` lines, then `classify-changes.sh: all cases pass`, exit 0.

- [ ] **Step 5: Mutation-check the default**

The whole design rests on the default arm being `code`. Prove the test would catch it if it were not.

Edit `is_docs_path` in `classify-changes.sh`, changing the last arm from `*) return 1 ;;` to `*) return 0 ;;`, then run:

Run: `.github/scripts/test-classify-changes.sh`

Expected: FAIL — at minimum `FAIL: an unrecognised top-level file` and `FAIL: the gitleaks allowlist alone`.

**Now revert that edit** (restore `*) return 1 ;;`) and re-run to confirm green again. Do not proceed while the mutation is in place.

- [ ] **Step 6: Verify the scripts are committed executable**

Run: `git add .github/scripts && git diff --cached --summary`

Expected: two `create mode 100755` lines. If either says `100644`, run `chmod +x` on it and `git add` again — a non-executable script fails in CI with `Permission denied`.

- [ ] **Step 7: Commit**

```bash
PIP_CONFIG_FILE=/dev/null git commit -m "$(cat <<'EOF'
ci: add the change classifier and its self-test

Documentation is docs/** and root *.md; everything else -- .github/**,
.gitleaksignore, every submodule pointer -- is code. The default arm
returns code, so an unanticipated path, an unreadable diff, an empty diff
and an all-zero base SHA all run the full suite.

The test runs as a step of the triage job, so the thing deciding what CI
skips is checked on every run. Mutation-checked: flipping the default arm
to docs turns it red.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: The `triage` job, inert

`triage` is added and its outputs are proven on a real branch **before** anything depends on them. No gate changes in this task — if the classifier or the artifact lookup is wrong, this task is where it shows up harmlessly.

**Files:**
- Modify: `.github/workflows/ci.yml` (add a `permissions:` block after `concurrency:`, add the `triage` job as the first entry under `jobs:`)

**Interfaces:**
- Consumes: `.github/scripts/classify-changes.sh`, `.github/scripts/test-classify-changes.sh` from Task 1.
- Produces: `needs.triage.outputs.code` (`"true"`/`"false"`) and `needs.triage.outputs.verified` (`"true"`/`"false"`, and **empty string on `pull_request` events**, because the lookup step is skipped there). Consumers must therefore test `!= 'true'`, never `== 'false'`.

- [ ] **Step 1: Add an explicit permissions block**

In `.github/workflows/ci.yml`, immediately after the `concurrency:` block and before `jobs:`, insert:

```yaml
# The artifact lookup in `triage` reads the Actions API. Declaring permissions
# explicitly also drops the token from the repo-default (write) to the least
# set these jobs need; `deploy-staging` authenticates to GHCR and the VPS with
# its own secrets, not with this token.
permissions:
  actions: read
  contents: read
```

- [ ] **Step 2: Add the `triage` job**

In `.github/workflows/ci.yml`, make `triage` the **first** job under `jobs:` (before `backend-lint`):

```yaml
  # One job, two questions, because a job skipped by `if:` also skips its
  # dependents -- so a separate guard job would have to run on pull requests
  # too, and GitHub bills a ONE MINUTE FLOOR per job. Merged, the guard is free.
  triage:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:
      # "false" iff every changed path is docs/** or a root *.md.
      code: ${{ steps.classify.outputs.code }}
      # "true" iff a green run already tested this exact git tree. EMPTY on a
      # pull_request event, because the lookup step is skipped there --
      # consumers must test `!= 'true'`, never `== 'false'`.
      verified: ${{ steps.guard.outputs.verified }}
    steps:
      # fetch-depth 0: the classifier diffs `before..sha`, which the default
      # shallow checkout cannot reach. No submodules: the classifier reads path
      # names, and `git rev-parse HEAD^{tree}` reads the commit's tree object --
      # which already contains the submodule gitlinks whether or not they are
      # checked out.
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - name: Self-test the classifier
        run: .github/scripts/test-classify-changes.sh

      # On a pull_request, actions/checkout gives us the MERGE REF, so HEAD^1 is
      # the base branch and HEAD is the merged result -- diffing those two is
      # exactly the PR's net change, with no dependence on the event payload.
      - name: Classify the change
        id: classify
        run: |
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            code="$(.github/scripts/classify-changes.sh HEAD^1 HEAD)"
          else
            code="$(.github/scripts/classify-changes.sh \
              "${{ github.event.before }}" "${{ github.sha }}")"
          fi
          echo "code=$code" >> "$GITHUB_OUTPUT"
          echo "::notice::code=$code"

      # A tree hash is content-addressed and includes submodule gitlinks, so a
      # merge commit and the PR merge ref that produced it have the SAME tree --
      # under merge, squash or rebase alike. If a green run recorded this tree,
      # the gates have already run against this exact content.
      - name: Look for a green run of this exact tree
        id: guard
        if: github.event_name == 'push'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          tree="$(git rev-parse HEAD^{tree})"
          count="$(gh api \
            "/repos/${{ github.repository }}/actions/artifacts?name=verified-tree-$tree" \
            --jq '[.artifacts[] | select(.expired == false)] | length')"
          if [ "$count" -gt 0 ]; then verified=true; else verified=false; fi
          echo "verified=$verified" >> "$GITHUB_OUTPUT"
          echo "::notice::tree=$tree verified=$verified"
```

- [ ] **Step 3: Verify the workflow still parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml parses')"`

Expected: `ci.yml parses`. A YAML error here means an indentation mistake — `triage` must be indented two spaces under `jobs:`, matching `backend-lint`.

- [ ] **Step 4: Commit and push to the branch**

```bash
PIP_CONFIG_FILE=/dev/null git add .github/workflows/ci.yml
PIP_CONFIG_FILE=/dev/null git commit -m "$(cat <<'EOF'
ci: add the triage job, not yet wired to any gate

Classifies the diff and, on a push, looks up whether a green run already
recorded this exact tree hash. Nothing depends on its outputs yet, so a
wrong answer here is visible and harmless.

One job rather than two: a job skipped by `if:` skips its dependents, so a
separate guard job would have to run on pull requests as well, and GitHub
bills a one-minute floor per job.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin feat/ci-cost-optimization
```

- [ ] **Step 5: Read the real outputs on a real runner**

This branch's push run is a **code** change (it touches `.github/**`), so the expected answer is known.

Run: `gh run list --branch feat/ci-cost-optimization --limit 1 --json databaseId --jq '.[0].databaseId'`, then `gh run view <id> --log --job triage 2>/dev/null | grep -E "notice|ok:|FAIL"`

Expected:
- twelve `ok:` lines from the self-test
- `::notice::code=true`
- `::notice::tree=<40 hex chars> verified=false` (no artifact has ever been recorded)

**Do not start Task 3 until you have seen `code=true` on this run.** If the classify step errored on `HEAD^1` the checkout is not a merge ref — stop and diagnose rather than gating jobs on a broken output.

- [ ] **Step 6: Prove the classifier is live, not hard-coded**

Commit a documentation-only change on this branch and confirm `triage` flips to `code=false`:

```bash
printf '\n<!-- triage probe, reverted in the next commit -->\n' >> ISSUES.md
PIP_CONFIG_FILE=/dev/null git commit -am "docs: probe the triage classifier"
git push
```

Run: `gh run view <new-id> --log --job triage | grep "::notice::code"`

Expected: `::notice::code=false`.

Then revert the probe and push again:

```bash
git revert --no-edit HEAD
git push
```

Expected on the revert's run: `::notice::code=false` again (reverting a docs change is still a docs change).

---

### Task 3: Gate the seven jobs and fix `deploy-staging`

**Files:**
- Modify: `.github/workflows/ci.yml` — add `needs:` + `if:` to `backend-lint`, `backend-test`, `dashboard-lint`, `dashboard-build`, `marketing-build`, `e2e`, `security`; replace `deploy-staging`'s `needs:` and `if:`; add `timeout-minutes` to every job.

**Interfaces:**
- Consumes: `needs.triage.outputs.code`, `needs.triage.outputs.verified` from Task 2.
- Produces: seven gate jobs that skip when the change is documentation-only, when the tree is already verified, or when the actor is Dependabot.

- [ ] **Step 1: Add the shared gate condition to all seven gate jobs**

Every one of the seven gets **this identical block**, placed directly under `runs-on: ubuntu-latest`:

```yaml
    needs: triage
    # `verified != 'true'` and not `== 'false'`: the guard step is skipped on
    # pull_request events, so this output is the EMPTY STRING there, not "false".
    #
    # A Dependabot PR cannot read secrets.SUBMODULE_TOKEN, so every one of these
    # jobs dies in `actions/checkout` -- six billed minutes to fail. It is not
    # newly untested; it was never testable here. See the spec.
    if: >-
      needs.triage.outputs.code == 'true'
      && needs.triage.outputs.verified != 'true'
      && github.actor != 'dependabot[bot]'
```

`dashboard-build` already has `needs: dashboard-lint`. Its `needs:` becomes the list — do **not** drop the existing dependency:

```yaml
    needs: [triage, dashboard-lint]
```

- [ ] **Step 2: Add `timeout-minutes` to every job**

`ci.yml` currently sets none, so GitHub's default of **360 minutes** applies — one hung job bills six hours, more than a fortnight of this spec's savings. Add to each job, at roughly 3× measured wall clock:

| Job | `timeout-minutes` |
| --- | --- |
| `triage` | 5 (already added in Task 2) |
| `backend-lint` | 10 |
| `backend-test` | 10 |
| `dashboard-lint` | 15 |
| `dashboard-build` | 10 |
| `marketing-build` | 10 |
| `e2e` | 15 |
| `security` | 10 |
| `deploy-staging` | 20 |

- [ ] **Step 3: Replace `deploy-staging`'s `needs:` and `if:`**

Its `needs:` list will now routinely contain legitimately skipped jobs, and the default `if:` semantics ("every needed job succeeded") would skip the deploy along with them.

Replace the existing `needs:` block and `if:` line with:

```yaml
    needs:
      [
        triage,
        backend-lint,
        backend-test,
        dashboard-lint,
        dashboard-build,
        e2e,
        marketing-build,
        security,
      ]
    # `!cancelled()` opts out of the default "all needs succeeded" rule, which
    # would treat a deliberately SKIPPED gate as a reason not to deploy. The
    # explicit failure check is what still stops a red gate reaching staging.
    # `triage` itself is never skipped, so `code` is always readable here.
    if: >-
      !cancelled()
      && !contains(needs.*.result, 'failure')
      && github.ref == 'refs/heads/master'
      && github.event_name == 'push'
      && needs.triage.outputs.code == 'true'
```

- [ ] **Step 4: Verify the workflow parses and every job is gated**

Run:

```bash
python3 - <<'PY'
import yaml
w = yaml.safe_load(open('.github/workflows/ci.yml'))
gates = ["backend-lint","backend-test","dashboard-lint","dashboard-build",
         "marketing-build","e2e","security"]
for name in gates:
    job = w["jobs"][name]
    assert "triage" in str(job.get("needs")), f"{name}: missing needs: triage"
    cond = job.get("if","")
    for frag in ["outputs.code == 'true'", "outputs.verified != 'true'",
                 "dependabot[bot]"]:
        assert frag in cond, f"{name}: condition missing {frag!r}"
for name, job in w["jobs"].items():
    assert "timeout-minutes" in job, f"{name}: no timeout-minutes"
d = w["jobs"]["deploy-staging"]["if"]
assert "!cancelled()" in d and "'failure'" in d, "deploy-staging: condition wrong"
print(f"all {len(gates)} gates wired; all {len(w['jobs'])} jobs have a timeout")
PY
```

Expected: `all 7 gates wired; all 9 jobs have a timeout`

Nine, not ten: `record-verified-tree` does not exist until Task 4. If this prints 10, you are running these tasks out of order.

- [ ] **Step 5: Commit and push**

```bash
PIP_CONFIG_FILE=/dev/null git add .github/workflows/ci.yml
PIP_CONFIG_FILE=/dev/null git commit -m "$(cat <<'EOF'
ci: gate the seven jobs on triage, and cap every job's runtime

The gates now skip for a documentation-only change, for a tree a green run
already proved, and for Dependabot (whose PRs cannot read SUBMODULE_TOKEN
and so died in checkout for six billed minutes a time).

deploy-staging needs !cancelled() plus an explicit failure check, because
its needs: list now legitimately contains skipped jobs and the default rule
would skip the deploy with them.

timeout-minutes on every job: there were none, so the default 360 applied
and one hung job could bill six hours.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

- [ ] **Step 6: Confirm the gates still run for a code change**

This push touches `.github/**`, so `code=true` and nothing is verified — the full suite must run.

Run: `gh run view <new-id> --json jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'`

Expected: `triage success` plus all seven gates with a real conclusion (`success`, or `failure` you then fix). **If any gate reads `skipped` here, the condition is wrong — stop and fix before Task 4.**

---

### Task 4: Record the verified tree

**Files:**
- Modify: `.github/workflows/ci.yml` — add the `record-verified-tree` job after `security` and before `marketing-build` (placement is cosmetic; ordering in the file does not affect execution).

**Interfaces:**
- Consumes: `needs.triage.outputs.code`, and the success of all seven gates.
- Produces: an artifact named `verified-tree-<40-hex-tree-hash>`, retention 7 days — the exact name `triage`'s guard step queries in Task 2.

- [ ] **Step 1: Add the job**

```yaml
  # Publishes "these gates went green against this exact content" so the push
  # that merges this PR does not have to prove it again.
  #
  # No submodules and no token: `git rev-parse HEAD^{tree}` reads the commit's
  # tree object, which already carries the submodule gitlinks whether or not
  # they are checked out. Checking them out would produce the same hash more
  # slowly.
  record-verified-tree:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    needs:
      [
        triage,
        backend-lint,
        backend-test,
        dashboard-lint,
        dashboard-build,
        e2e,
        marketing-build,
        security,
      ]
    # Deliberately NOT `!cancelled()`: unlike deploy-staging, this job must run
    # only when every gate actually ran and passed. A skipped gate means this
    # tree was never fully proved, so recording it would let a later push skip
    # gates on the strength of a run that did not perform them.
    if: >-
      github.event_name == 'pull_request'
      && needs.triage.outputs.code == 'true'
    steps:
      - uses: actions/checkout@v7

      - name: Compute the tree this run proved
        id: tree
        run: |
          tree="$(git rev-parse HEAD^{tree})"
          echo "$tree" > verified-tree.txt
          echo "tree=$tree" >> "$GITHUB_OUTPUT"
          echo "::notice::recording verified tree $tree"

      - uses: actions/upload-artifact@v4
        with:
          name: verified-tree-${{ steps.tree.outputs.tree }}
          path: verified-tree.txt
          retention-days: 7
```

- [ ] **Step 2: Verify the central claim locally — a merge commit's tree equals the merge ref's tree**

The entire guard rests on this. `record-verified-tree` computes the hash on a `pull_request` (the merge ref); `triage` computes it on the `push` of the resulting merge commit. If those differ, the guard never fires and the change is pointless.

Prove it on a throwaway repo, where a real merge can be constructed:

```bash
tmp="$(mktemp -d)" && git init -q "$tmp" && cd "$tmp"
git config user.email t@example.com && git config user.name t
echo base > f.txt && git add f.txt && git commit -qm base
git checkout -qb feat && echo change > g.txt && git add g.txt && git commit -qm feat
git checkout -q master 2>/dev/null || git checkout -q main
# What CI tests on a pull_request: the merge ref, built without committing it.
merge_ref_tree="$(git merge-tree --write-tree HEAD feat)"
# What CI sees on the push: the real merge commit.
git merge -q --no-ff -m merge feat
merge_commit_tree="$(git rev-parse HEAD^{tree})"
echo "merge ref:    $merge_ref_tree"
echo "merge commit: $merge_commit_tree"
[ "$merge_ref_tree" = "$merge_commit_tree" ] && echo "MATCH" || echo "MISMATCH"
cd - >/dev/null && rm -rf "$tmp"
```

Expected: two identical 40-character hashes and `MATCH`.

**If this prints `MISMATCH`, stop — the guard cannot work and the design needs revisiting.** (`git merge-tree --write-tree` needs git 2.38+; if it is unavailable, the runner check in Task 6 Step 3 is the fallback proof, comparing the hash `triage` logs against the one Step 2 of that task recorded.)

- [ ] **Step 3: Verify the workflow parses**

Run: `python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/ci.yml')); j=w['jobs']['record-verified-tree']; assert 'pull_request' in j['if']; assert '!cancelled' not in j['if']; print('record-verified-tree wired')"`

Expected: `record-verified-tree wired`

- [ ] **Step 4: Commit and push**

```bash
PIP_CONFIG_FILE=/dev/null git add .github/workflows/ci.yml
PIP_CONFIG_FILE=/dev/null git commit -m "$(cat <<'EOF'
ci: record the tree hash a green PR run proved

A 20-byte artifact named verified-tree-<hash>, 7 days retention, which is
what triage's guard step queries on the following push.

Not !cancelled() here, unlike deploy-staging: this job must run only when
every gate actually ran and passed, or it would let a later push skip gates
on the strength of a run that never performed them.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

- [ ] **Step 5: Confirm the artifact appears**

Run: `gh run view <new-id> --json jobs --jq '.jobs[] | select(.name=="record-verified-tree") | .conclusion'` and then `gh api "/repos/kaleem-lms/Kaleem/actions/artifacts" --jq '.artifacts[] | select(.name|startswith("verified-tree-")) | "\(.name) expired=\(.expired)"'`

Expected: `success`, and one `verified-tree-<hash> expired=false` line.

Note: this run is a **push** to the feature branch, not a `pull_request` event, so `record-verified-tree` will be **skipped**. That is correct. To see it run, open the PR in Task 6 — or open a draft PR now and re-check.

---

### Task 5: Dependabot and the nightly schedules

**Files:**
- Modify: `.github/dependabot.yml` (replace the file)
- Modify: `.github/workflows/lighthouse.yml:20` (the `cron` line)
- Modify: `.github/workflows/stripe-clock.yml:12` (the `cron` line)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other jobs read.

- [ ] **Step 1: Confirm the phantom directories really are absent**

Do not delete config on the strength of the plan saying so.

Run:

```bash
for d in compose/local/django compose/local/docs compose/local/node \
         compose/production/aws compose/production/django \
         compose/production/postgres compose/production/traefik; do
  [ -d "$d" ] && echo "EXISTS $d" || echo "missing $d"
done
ls requirements* 2>/dev/null || echo "no root requirements*"
```

Expected: seven `missing` lines and `no root requirements*`. **If anything reads `EXISTS`, stop** — that ecosystem is real and must be kept.

- [ ] **Step 2: Replace `.github/dependabot.yml`**

```yaml
# Trimmed 2026-09-08 (see docs/superpowers/specs/2026-09-08-ci-cost-optimization-design.md).
#
# This was the unmodified cookiecutter-django file: nine ecosystems on a daily
# interval, seven of them pointing at compose/local/django, compose/production/
# traefik and similar -- none of which exist in this repo -- plus a pip entry
# for a root requirements* that does not exist either. Only the github-actions
# entry ever produced a pull request.
#
# Those PRs cannot pass CI: a Dependabot pull request cannot read
# secrets.SUBMODULE_TOKEN, so every job that checks out submodules dies at
# checkout. ci.yml now short-circuits them (`github.actor != 'dependabot[bot]'`)
# rather than billing six minutes to fail. An Actions version bump is therefore
# reviewed by hand -- which is what already happened, just without the six
# minutes.
#
# The submodules (backend, dashboard, marketing, infra, tokens) have their own
# dependency surfaces and no CI of their own; updating them is not this file's
# job.
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
```

- [ ] **Step 3: Move the nightlies to weekly**

In `.github/workflows/lighthouse.yml`, change `- cron: "41 3 * * *"` to:

```yaml
    # Weekly, not nightly (2026-09-08): 56 billed minutes a week became 8. This
    # measures a deployed environment against ratchet floors that move when we
    # move them, not on a 24-hour cycle.
    - cron: "41 3 * * 1"
```

In `.github/workflows/stripe-clock.yml`, change `- cron: "17 3 * * *"` to:

```yaml
    # Weekly, not nightly (2026-09-08). The trade is explicit: a renewal-path
    # regression is now caught within 7 days rather than 24 hours. It watches
    # for drift in an external payload shape, which is not a daily event.
    - cron: "17 3 * * 4"
```

(Different days on purpose — a red Monday and a red Thursday are unambiguous about which harness failed.)

- [ ] **Step 4: Verify all three files parse and the crons changed**

Run:

```bash
python3 - <<'PY'
import yaml
d = yaml.safe_load(open('.github/dependabot.yml'))
assert len(d['updates']) == 1, d['updates']
assert d['updates'][0]['schedule']['interval'] == 'weekly'
for f, want in [('.github/workflows/lighthouse.yml', '41 3 * * 1'),
                ('.github/workflows/stripe-clock.yml', '17 3 * * 4')]:
    w = yaml.safe_load(open(f))
    # `on:` parses as the boolean True in YAML 1.1
    got = w[True]['schedule'][0]['cron']
    assert got == want, f"{f}: cron is {got!r}, want {want!r}"
print("dependabot trimmed to 1 ecosystem; both nightlies now weekly")
PY
```

Expected: `dependabot trimmed to 1 ecosystem; both nightlies now weekly`

- [ ] **Step 5: Commit and push**

```bash
PIP_CONFIG_FILE=/dev/null git add .github/dependabot.yml .github/workflows/lighthouse.yml .github/workflows/stripe-clock.yml
PIP_CONFIG_FILE=/dev/null git commit -m "$(cat <<'EOF'
ci: trim dependabot to what exists, move the nightlies to weekly

dependabot.yml was the untouched cookiecutter-django file: seven Docker
ecosystems pointed at directories this repo does not have, plus a pip entry
for a root requirements* that does not exist. Verified absent before
deleting.

Lighthouse and the Stripe test clock go nightly -> weekly, on different
days so a red run names itself. 56 billed minutes a week becomes 8. The
trade is stated: renewal-path drift is now caught within 7 days, not 24
hours.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 6: Prove the guard in both directions, then close

The guard is the one change that can skip a gate. A guard hard-wired to `true` looks identical to a working one until it lets something through, so **both** directions are checked on real runs. This task deliberately merges to `master` twice — each merge is a staging deploy (ADR-0028).

**Files:**
- Create: `docs/adr/0038-ci-runs-only-what-the-change-can-break.md`
- Create: `docs/runbook/ci.md`
- Modify: `docs/superpowers/specs/2026-09-08-ci-cost-optimization-design.md` (frontmatter `status: shipped`, `closed: 2026-09-08`)
- Modify: `STATE.md`, `docs/superpowers/journal/2026-W37.md`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: the closed spec.

- [ ] **Step 1: Open the PR**

```bash
gh pr create --base master --title "ci: run only what the change can break" --body "$(cat <<'EOF'
Implements `docs/superpowers/specs/2026-09-08-ci-cost-optimization-design.md`.

Documentation-only changes stop running the full eight-job suite, and a merge
stops re-proving the tree its PR already proved. Nothing changes about what any
gate checks — only when it runs.

Modelled at ~54% off (~$62/mo → ~$19/mo). The dollar figures are a model: the
Actions invoice was never read, because the billing API needs an `admin:org`
scope this session does not have. The spec says so in its own section.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 2: Confirm the PR run records a tree**

Run: `gh pr checks --watch` then `gh api "/repos/kaleem-lms/Kaleem/actions/artifacts" --jq '.artifacts[] | select(.name|startswith("verified-tree-")) | "\(.id) \(.name)"'`

Expected: all jobs green, and a `verified-tree-<hash>` artifact. **Record the hash** — Step 3 checks the merge commit produces the same one.

- [ ] **Step 3: Merge, and confirm the push SKIPS the gates**

```bash
gh pr merge --merge --delete-branch
```

Run: `gh run list --branch master --limit 1 --json databaseId --jq '.[0].databaseId'`, then `gh run view <id> --json jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'`

Expected:
- `triage success`, and its log shows `::notice::tree=<same hash as Step 2> verified=true`
- all seven gates `skipped`
- `deploy-staging success`

**If the tree hash differs from Step 2**, `master` moved under the PR — that is the guard working correctly, not a bug. Note it and repeat with a fresh PR.

- [ ] **Step 4: Confirm staging actually received the deploy**

A skipped gate must not mean a skipped deploy.

Run: `gh run view <id> --log --job deploy-staging | grep -E "Deploy to staging|ship.sh"`

Expected: the SSH deploy step ran. Then confirm staging is serving the new build (`curl -sf -o /dev/null -w '%{http_code}' https://app-staging.kaleem.academy/`, expect `200`).

- [ ] **Step 5: Prove the OTHER direction — no artifact means the full suite**

This is the half that catches a guard hard-wired to `true`. Open a small second PR (a one-line `ISSUES.md` addition recording anything noticed during this work, so the PR is real), let it go green, then **delete its artifact before merging**:

```bash
gh api "/repos/kaleem-lms/Kaleem/actions/artifacts" \
  --jq '.artifacts[] | select(.name|startswith("verified-tree-")) | "\(.id) \(.name)"'
gh api -X DELETE "/repos/kaleem-lms/Kaleem/actions/artifacts/<id>"
gh pr merge --merge --delete-branch
```

Deleting the artifact is exactly what its 7-day expiry does, so this is the real failure path, not a simulation — and it avoids pushing an untested commit straight to `master`, which ADR-0028 forbids.

Run: `gh run view <new-master-run-id> --json jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'`

Expected: `triage` logs `verified=false`, **all seven gates run** (not `skipped`), then `deploy-staging` runs.

**If the gates skip here, the guard is broken.** Stop; do not close the spec.

- [ ] **Step 6: Confirm a documentation-only push costs one minute**

The docs PR that closes this spec (Step 7) is itself the test.

Expected on both its PR run and its `master` push run: `triage` only — one job, `code=false`, every gate and `deploy-staging` skipped.

- [ ] **Step 7: Write ADR-0038, the runbook, and close the spec**

Create `docs/adr/0038-ci-runs-only-what-the-change-can-break.md` following `docs/templates/adr.md`, covering: the context (43% of PRs are docs-only; every merge paid twice; the org is on GitHub Free with no branch protection); the decision (change detection plus a tree-hash guard); alternatives (a `paths-ignore` filter at workflow level — rejected because a required check that never runs stays pending forever, which matters if branch protection is ever enabled; merging jobs; a self-hosted runner); and consequences, including the two honest ones — **a code PR costs two minutes more**, and **the push run stops being a second chance to notice a red gate**.

Create `docs/runbook/ci.md` covering at minimum:
- what `triage`'s two outputs mean, and that `verified` is the empty string on PRs
- **that a PR merged more than 7 days after going green runs the full suite, because the artifact expired — this is correct behaviour and will look like the guard is broken**
- how to force a full run: delete the `verified-tree-*` artifact before merging
- that `deploy-staging` is skipped entirely for a documentation-only push

Set the spec's frontmatter to `status: shipped` and `closed: 2026-09-08`.

- [ ] **Step 8: Update `STATE.md` and the journal, then commit**

Add to `STATE.md`'s "Recently verified" section, and to `docs/superpowers/journal/2026-W37.md`, recording specifically: the measured before/after per-run costs, that the guard was mutation-checked by deleting the artifact, and that **the dollar figures are modelled and no invoice was read**.

```bash
PIP_CONFIG_FILE=/dev/null git add docs/ STATE.md
PIP_CONFIG_FILE=/dev/null git commit -m "$(cat <<'EOF'
docs: close the CI cost optimization spec, ADR-0038

Guard mutation-checked in both directions on real runs: a merge whose tree
a green PR recorded skips the seven gates and still deploys; the same merge
with its artifact deleted runs the full suite.

Dollar figures remain modelled -- the Actions invoice was never read. The
runbook records the one behaviour that will look like a bug: a PR merged
more than 7 days after going green runs everything, because the artifact
expired.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 9: Set a reminder to check the model against a real bill**

Add to `ISSUES.md` under **Someday**:

```markdown
- **The CI cost model has never met an invoice.** `docs/superpowers/specs/2026-09-08-ci-cost-optimization-design.md`
  projects ~$19/month after the change, from run counts × measured job durations ×
  the published $0.008/min. The billing API needs an `admin:org` scope. Read one real
  month's Actions bill and correct the number in the spec if it is wrong.
```

---

## Notes for the executor

**Task order is a safety property, not a preference.** Task 2 puts `triage` in place with nothing depending on it, and Task 2 Step 5 reads its real outputs off a real runner before Task 3 gates anything on them. Do not merge those tasks.

**One deliberate deviation from the spec's test plan.** The spec asks for `deploy-staging`'s `if:` to be verified "on a scratch branch with the job's body replaced by `echo`, across all four combinations". This plan verifies it on real runs instead — Task 3 Step 6 (gates run), Task 6 Step 3 (gates skipped, deploy must still run), Task 6 Step 5 (gates run again after the artifact is deleted), Task 6 Step 6 (docs-only, nothing runs). The fourth nominal combination, "gates skipped *and* documentation-only", is degenerate: `code == 'false'` already stops the deploy on its own clause.

Real runs are better evidence than an `echo` stub, and both failure modes of a wrong condition are cheap and loud — either the deploy is skipped when it should run (visible immediately, nothing shipped) or it runs on a docs-only push (it redeploys byte-identical images). Neither can damage staging. If you would rather have the stub, it costs about four minutes; nothing downstream depends on the choice.

**Two conditions in this plan look similar and are deliberately different:**
- `deploy-staging` uses `!cancelled()` — it must run *despite* skipped gates.
- `record-verified-tree` does not — it must run only when every gate actually ran and passed.

Swapping them would record a tree as verified when the gates never executed, and the next merge of that content would skip its gates on the strength of a run that proved nothing. That is the one mistake in this plan that fails silently.
