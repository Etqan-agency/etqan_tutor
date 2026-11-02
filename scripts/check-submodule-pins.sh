#!/usr/bin/env bash
# Every submodule pointer must be a commit on that repo's origin/main. The
# deploy builds every image from these pointers, so a pointer to an unmerged
# branch ships code no review merged: that fails. A pointer behind main only
# warns: the work merged there is not deployed yet, and `just bump` moves it.
# Reads the INDEX, as check-token-pin.mjs does, so a staged bump is checked
# before it is committed.
#   scripts/check-submodule-pins.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

bad=0
while read -r _ path; do
    pin="$(git ls-files -s "$path" | awk '{print $2}')"
    git -C "$path" fetch -q origin main
    if ! git -C "$path" merge-base --is-ancestor "$pin" origin/main 2>/dev/null; then
        echo "ERROR: $path points at ${pin:0:10}, which is not on its origin/main." \
            "Merge that work in $path first, then point at main (just bump)." >&2
        bad=1
        continue
    fi
    behind="$(git -C "$path" rev-list --count "$pin..origin/main")"
    if [ "$behind" -gt 0 ]; then
        echo "${GITHUB_ACTIONS:+::warning::}$path is $behind commit(s) behind its main," \
            "which is merged but not deployed: run just bump."
    fi
done < <(git config -f .gitmodules --get-regexp '\.path$')
exit "$bad"
