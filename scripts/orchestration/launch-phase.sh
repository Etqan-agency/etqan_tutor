#!/usr/bin/env bash
# Create one phase's worktrees and stack settings (spec 2026-10-02 §3.2-3.3),
# then print the command that starts its orchestrator session.
#   launch-phase.sh <phase e.g. b3> <branch suffix e.g. b3a-pricing> <slot 1-4>
set -euo pipefail
[ $# -eq 3 ] || { echo "usage: launch-phase.sh <phase> <branch-suffix> <slot 1-4>" >&2; exit 2; }
phase="$1"; suffix="$2"; slot="$3"
main="$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd)"
root="${ETQAN_WT_ROOT:-$(dirname "$main")/etqan_tutor-wt}"
dir="$root/$phase"
branch="feat/$suffix"
code="$(tr '[:lower:]' '[:upper:]' <<<"$phase")"
[ ! -e "$dir" ] || { echo "already exists: $dir" >&2; exit 1; }
mkdir -p "$root"
git -C "$main" fetch -q origin
git -C "$main" worktree add -q -b "$branch" "$dir" origin/master
for sub in backend dashboard marketing; do
  git -C "$main/$sub" fetch -q origin
  git -C "$main/$sub" worktree add -q -b "$branch" "$dir/$sub" origin/main
done
if [ -f "$main/backend/.env" ]; then cp "$main/backend/.env" "$dir/backend/.env"; fi
bash "$main/scripts/orchestration/stream-env.sh" "$phase" "$slot" "$dir" >/dev/null
cat <<EOF
Phase $code is ready in $dir (slot $slot, http://demo.etqan.localhost:$((8080 + slot * 100))/).
Start its orchestrator in a new terminal:

  cd $dir && claude "\$(sed -e 's/{{PHASE}}/$code/g' -e 's/{{SLOT}}/$slot/g' scripts/orchestration/PHASE_PROMPT.md)"
EOF
