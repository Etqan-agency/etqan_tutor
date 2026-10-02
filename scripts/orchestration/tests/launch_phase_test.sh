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

# A second launch of the same phase is refused.
if (cd "$main" && bash scripts/orchestration/launch-phase.sh b3 b3b-other 3 2>/dev/null); then fail "relaunch accepted"; fi
echo "launch_phase_test: ok"
