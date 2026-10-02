#!/usr/bin/env bash
# Remove a finished phase (spec 2026-10-02 §9; CONDUCTOR.md step 6), undoing
# launch-phase.sh, in the only order that works:
#   1. `just stream-down` in its worktree: its stack and volumes, under its
#      own compose project (.env.stream), freeing the slot;
#   2. the submodule worktrees, then the meta worktree (`--force`: once the
#      submodule worktrees are gone the meta worktree shows them deleted);
#   3. its local feat/<phase><letter>… branches in every repo;
#   4. a check that the main checkout's submodules still work.
#   teardown-phase.sh <phase e.g. B3 or b3>
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: teardown-phase.sh <phase>" >&2; exit 2; }
phase="$(tr '[:upper:]' '[:lower:]' <<<"$1")"
[[ "$phase" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "phase must be letters, digits and dashes: $1" >&2; exit 2; }
main="$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd)"
root="${ETQAN_WT_ROOT:-$(dirname "$main")/etqan_tutor-wt}"
dir="$root/$phase"
[ -d "$dir" ] || { echo "no phase worktree at $dir" >&2; exit 1; }

if [ -f "$dir/.env.stream" ]; then
  (cd "$dir" && just stream-down)
fi
for sub in backend dashboard marketing; do
  if git -C "$main/$sub" worktree list --porcelain | grep -qxF "worktree $dir/$sub"; then
    git -C "$main/$sub" worktree remove --force "$dir/$sub"
  fi
done
git -C "$main" worktree remove --force "$dir"
for repo in "" /backend /dashboard /marketing; do
  git -C "$main$repo" for-each-ref --format='%(refname:short)' "refs/heads/feat/" |
    { grep -E "^feat/${phase}[a-z]+-" || true; } |
    while read -r branch; do git -C "$main$repo" branch -q -D "$branch"; done
done
for sub in backend dashboard marketing; do
  git -C "$main/$sub" status --porcelain >/dev/null || {
    echo "main checkout's $sub is broken; fix .git/modules/$sub/config core.worktree before the next launch" >&2
    exit 1
  }
done
echo "phase ${phase^^} torn down: stack, worktrees and branches removed"
