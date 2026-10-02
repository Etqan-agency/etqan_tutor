#!/usr/bin/env bash
# Create the shared ledger worktree on an orphan `orchestration` branch and
# initialise the ledger (spec 2026-10-02 §4.1). Safe to run again.
set -euo pipefail
main="$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd)"
root="${ETQAN_WT_ROOT:-$(dirname "$main")/etqan_tutor-wt}"
ledger="$root/_ledger"
mkdir -p "$root"
if [ ! -d "$ledger" ]; then
  if git -C "$main" show-ref -q --verify refs/heads/orchestration; then
    git -C "$main" worktree add -q "$ledger" orchestration
  elif git -C "$main" ls-remote -q --exit-code --heads origin orchestration >/dev/null 2>&1; then
    git -C "$main" fetch -q origin orchestration:orchestration
    git -C "$main" worktree add -q "$ledger" orchestration
  else
    git -C "$main" worktree add -q --orphan -b orchestration "$ledger"
  fi
fi
if [ ! -f "$ledger/orchestration/ledger.json" ]; then
  python3 "$main/scripts/orchestration/ledger.py" --dir "$ledger" init
fi
echo "ledger: $ledger"
