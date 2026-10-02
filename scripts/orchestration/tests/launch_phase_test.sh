#!/usr/bin/env bash
# launch-phase.sh and bootstrap-ledger.sh against throwaway repos (spec 2026-10-02 §3, §6.1).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scripts="$here/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git() { command git -c protocol.file.allow=always -c init.defaultBranch=main "$@"; }

# Remotes: three submodules on main, a meta repo on master.
for sub in backend dashboard marketing; do
  git init -q --bare "$tmp/remotes/$sub.git"
  git clone -q "$tmp/remotes/$sub.git" "$tmp/seed-$sub"
  echo "$sub" >"$tmp/seed-$sub/README"
  echo ".env" >"$tmp/seed-$sub/.gitignore"  # as backend/.gitignore does
  git -C "$tmp/seed-$sub" add README .gitignore && git -C "$tmp/seed-$sub" commit -qm init && git -C "$tmp/seed-$sub" push -q origin main
done
git init -q --bare "$tmp/remotes/meta.git"
git clone -q "$tmp/remotes/meta.git" "$tmp/seed-meta"
git -C "$tmp/seed-meta" switch -q -c master
for sub in backend dashboard marketing; do git -C "$tmp/seed-meta" submodule add -q "$tmp/remotes/$sub.git" "$sub"; done
mkdir -p "$tmp/seed-meta/scripts" && cp -r "$scripts" "$tmp/seed-meta/scripts/orchestration"
printf '.env.*\n__pycache__/\n' >"$tmp/seed-meta/.gitignore"  # as the meta .gitignore does
git -C "$tmp/seed-meta" add . && git -C "$tmp/seed-meta" commit -qm init && git -C "$tmp/seed-meta" push -q origin master

# The main checkout, as a developer has it.
git clone -q --recurse-submodules -b master "$tmp/remotes/meta.git" "$tmp/etqan_tutor"
echo "SECRET=1" >"$tmp/etqan_tutor/backend/.env"
main="$tmp/etqan_tutor"
export ETQAN_WT_ROOT="$tmp/wt"

# bootstrap-ledger is idempotent.
(cd "$main" && bash scripts/orchestration/bootstrap-ledger.sh >/dev/null)
(cd "$main" && bash scripts/orchestration/bootstrap-ledger.sh >/dev/null)
[ -f "$tmp/wt/_ledger/orchestration/ledger.json" ] || fail "no ledger"
[ "$(git -C "$tmp/wt/_ledger" branch --show-current)" = orchestration ] || fail "ledger not on orchestration"
[ "$(git -C "$tmp/wt/_ledger" log --format=%s | wc -l)" -eq 1 ] || fail "second bootstrap wrote again"

# bootstrap-ledger.sh prunes a stale worktree registration (left behind if a
# previous ledger directory was removed without `git worktree remove`) before
# giving up, so the next run isn't blocked (fix round 1, Task 5 review).
main2="$tmp/etqan_tutor2"
git clone -q --recurse-submodules -b master "$tmp/remotes/meta.git" "$main2"
root2="$tmp/wt2"
ledger2="$root2/_ledger"
mkdir -p "$root2"
git -C "$main2" worktree add -q -b scratch-temp "$ledger2" >/dev/null
rm -rf "$ledger2"  # simulate a ledger dir removed without `git worktree remove`
if (cd "$main2" && ETQAN_WT_ROOT="$root2" bash scripts/orchestration/bootstrap-ledger.sh >/dev/null 2>/dev/null); then
  fail "bootstrap should have failed against a stale worktree registration"
fi
(cd "$main2" && ETQAN_WT_ROOT="$root2" bash scripts/orchestration/bootstrap-ledger.sh >/dev/null) \
  || fail "bootstrap did not recover after pruning the stale registration"
[ -f "$ledger2/orchestration/ledger.json" ] || fail "no ledger after recovering from a stale registration"

# launch-phase creates every worktree on the branch.
out="$(cd "$main" && bash scripts/orchestration/launch-phase.sh b3 b3a-pricing 2)"
dir="$tmp/wt/b3"
for repo in "" /backend /dashboard /marketing; do
  [ "$(git -C "$dir$repo" branch --show-current)" = feat/b3a-pricing ] || fail "$dir$repo not on feat/b3a-pricing"
done
[ -z "$(git -C "$dir" status --porcelain)" ] || fail "meta worktree dirty: $(git -C "$dir" status --porcelain)"
grep -qx "SECRET=1" "$dir/backend/.env" || fail "backend/.env not copied"
grep -qx "ETQAN_HTTP_PORT=8280" "$dir/.env.stream" || fail "no slot-2 .env.stream"
grep -q "PHASE_PROMPT.md" <<<"$out" || fail "no session command printed: $out"
grep -q "B3" <<<"$out" || fail "phase code not in the command: $out"

# Submodule corruption guard: a read-only submodule command inside the phase
# (linked) meta worktree must never rewrite the main checkout's submodule
# worktree config (see justfile's `setup` guard, Task 1).
git -C "$dir" submodule status >/dev/null
git -C "$dir" status --porcelain >/dev/null
for sub in backend dashboard marketing; do
  worktree="$(git -C "$main" config -f ".git/modules/$sub/config" core.worktree)"
  [ "$worktree" = "../../../$sub" ] || fail "main's $sub core.worktree corrupted: $worktree"
done
git -C "$main/backend" status --porcelain >/dev/null || fail "main backend worktree broken after phase submodule status"

# ledger.py honours $ETQAN_WT_ROOT (already exported above) from inside the
# phase worktree, with no --dir flag, so a plain `ledger.py show` finds the
# ledger bootstrap-ledger.sh created (fix round 1, Task 5 review).
(cd "$dir" && python3 scripts/orchestration/ledger.py show >/dev/null) || fail "ledger.py show did not find the ledger from the phase worktree"

# A second launch of the same phase is refused.
if (cd "$main" && bash scripts/orchestration/launch-phase.sh b3 b3b-other 3 2>/dev/null); then fail "relaunch accepted"; fi

# launch-phase.sh is not atomic across its several worktrees: a mid-run
# failure (here, marketing's branch name already exists so its `worktree add
# -b` fails) must undo everything THIS run created and leave a retry free to
# succeed (fix round 1, Task 5 review).
git -C "$main/marketing" branch -q feat/b4a-pricing
if (cd "$main" && bash scripts/orchestration/launch-phase.sh b4 b4a-pricing 2 2>/dev/null); then fail "launch with a conflicting branch should have failed"; fi
[ ! -e "$tmp/wt/b4" ] || fail "phase dir left behind after a failed launch: $tmp/wt/b4"
if git -C "$main" rev-parse --verify -q feat/b4a-pricing >/dev/null; then fail "leftover meta branch after a failed launch"; fi
if git -C "$main/backend" rev-parse --verify -q feat/b4a-pricing >/dev/null; then fail "leftover backend branch after a failed launch"; fi
if git -C "$main/dashboard" rev-parse --verify -q feat/b4a-pricing >/dev/null; then fail "leftover dashboard branch after a failed launch"; fi
[ -z "$(git -C "$main" worktree list --porcelain | grep -F "$tmp/wt/b4" || true)" ] || fail "leftover worktree registration after a failed launch"
for sub in backend dashboard marketing; do
  worktree="$(git -C "$main" config -f ".git/modules/$sub/config" core.worktree)"
  [ "$worktree" = "../../../$sub" ] || fail "main's $sub core.worktree corrupted after a failed launch: $worktree"
done
out4="$(cd "$main" && bash scripts/orchestration/launch-phase.sh b4 b4b-pricing 2)"
grep -q "B4" <<<"$out4" || fail "retry after a failed launch did not succeed: $out4"
echo "launch_phase_test: ok"
