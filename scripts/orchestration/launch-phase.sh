#!/usr/bin/env bash
# Create one phase's worktrees and stack settings (spec 2026-10-02 §3.2-3.3),
# then print the command that starts its orchestrator session.
#   launch-phase.sh <phase e.g. B3 or b3> <branch suffix e.g. b3a-pricing> <slot 1-4>
# Undo with teardown-phase.sh <phase>.
set -euo pipefail
[ $# -eq 3 ] || { echo "usage: launch-phase.sh <phase> <branch-suffix> <slot 1-4>" >&2; exit 2; }
# The phase as `ledger.py eligible` prints it (B3) or lower-case (b3).
phase="$(tr '[:upper:]' '[:lower:]' <<<"$1")"; suffix="$2"; slot="$3"
# Checked before anything is created (stream-env.sh checks them again).
[[ "$phase" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "phase must be letters, digits and dashes: $1" >&2; exit 2; }
[[ "$slot" =~ ^[1-4]$ ]] || { echo "slot must be 1-4: $slot" >&2; exit 2; }
git check-ref-format --branch "feat/$suffix" >/dev/null 2>&1 || { echo "not a valid branch suffix: $suffix" >&2; exit 2; }
main="$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd)"
root="${ETQAN_WT_ROOT:-$(dirname "$main")/etqan_tutor-wt}"
dir="$root/$phase"
branch="feat/$suffix"
code="$(tr '[:lower:]' '[:upper:]' <<<"$phase")"
[ ! -e "$dir" ] || { echo "already exists: $dir" >&2; exit 1; }
mkdir -p "$root"

# Not atomic by itself (several worktrees across several repos): if a later
# step fails, undo whatever THIS run created so a retry isn't blocked by a
# half-made phase and the main checkout's submodules stay healthy.
meta_worktree_added=false
subs_added=()
cleanup() {
  local status=$?
  [ "$status" -eq 0 ] && return
  for sub in "${subs_added[@]:-}"; do
    [ -n "$sub" ] || continue
    git -C "$main/$sub" worktree remove --force "$dir/$sub" >/dev/null 2>&1 || true
    git -C "$main/$sub" branch -D "$branch" >/dev/null 2>&1 || true
  done
  if [ "$meta_worktree_added" = true ]; then
    git -C "$main" worktree remove --force "$dir" >/dev/null 2>&1 || true
    git -C "$main" branch -D "$branch" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

git -C "$main" fetch -q origin
git -C "$main" worktree add -q -b "$branch" "$dir" origin/master
meta_worktree_added=true
for sub in backend dashboard marketing; do
  git -C "$main/$sub" fetch -q origin
  git -C "$main/$sub" worktree add -q -b "$branch" "$dir/$sub" origin/main
  subs_added+=("$sub")
done
# stream-env.sh also points the copy's DATABASE_URL/CELERY_BROKER_URL at the
# stream's own Postgres/Redis, so host-side manage.py never writes main's.
if [ -f "$main/backend/.env" ]; then cp "$main/backend/.env" "$dir/backend/.env"; fi
bash "$main/scripts/orchestration/stream-env.sh" "$phase" "$slot" "$dir" >/dev/null
cat <<EOF
Phase $code is ready in $dir (slot $slot, http://demo.etqan.localhost:$((8080 + slot * 100))/).
Start its orchestrator in a new terminal:

  cd $dir && claude "\$(sed -e 's/{{PHASE}}/$code/g' -e 's/{{SLOT}}/$slot/g' scripts/orchestration/PHASE_PROMPT.md)"
EOF
