#!/usr/bin/env bash
# Point every submodule at its origin/main and open one meta PR (just bump).
# Merging that PR is what deploys: CI builds every image from these pointers
# and deploys staging (infra/STAGING.md). tokens is the exception: it follows
# the tag dashboard and marketing pin, never main, because the pin is what
# installs (check-token-pin.mjs).
#
# Works on a detached origin/master, so nothing local is touched until the
# bump passes check-token-pin.mjs and check-submodule-pins.sh; only then is
# the branch made, pushed and the PR opened. On any failure, or when nothing
# moved, it goes back to where it started.
#   scripts/bump-submodules.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

paths=()
while read -r _ path; do paths+=("$path"); done < <(git config -f .gitmodules --get-regexp '\.path$')

if [ -n "$(git status --porcelain --untracked-files=no --ignore-submodules=all)" ]; then
    echo "ERROR: the meta repo has uncommitted changes; commit or stash them first." >&2
    exit 1
fi
for path in "${paths[@]}"; do
    if [ -n "$(git -C "$path" status --porcelain --untracked-files=no)" ]; then
        echo "ERROR: uncommitted changes in $path; commit or stash them first." >&2
        exit 1
    fi
done

git fetch -q origin master
git checkout -q --detach origin/master
trap 'git reset -q; git checkout -q -' EXIT

for path in "${paths[@]}"; do
    [ "$path" = tokens ] && continue
    git -C "$path" fetch -q origin main
    git -C "$path" checkout -q --detach origin/main
done
tag="$(node -p 'require("./dashboard/package.json").dependencies["@etqan/tokens"].split("#")[1]')"
git -C tokens fetch -q --tags origin
git -C tokens checkout -q --detach "$tag"
git add "${paths[@]}"

if git diff --cached --quiet; then
    echo "Every submodule already points at its main; nothing to bump."
    exit 0
fi
node scripts/check-token-pin.mjs
bash scripts/check-submodule-pins.sh

body=""
for path in "${paths[@]}"; do
    old="$(git rev-parse "HEAD:$path")"
    new="$(git rev-parse ":$path")"
    [ "$old" = "$new" ] && continue
    count="$(git -C "$path" rev-list --count "$old..$new" 2>/dev/null || echo "?")"
    body+="- $path: ${old:0:7}..${new:0:7} ($count commit(s))"$'\n'
done
git commit -q -m "chore: point submodules at their main" -m "$body"
branch="chore/bump-submodules-$(git rev-parse --short HEAD)"
git switch -q -c "$branch"
trap - EXIT

git push -q -u origin "$branch"
gh pr create --repo Etqan-agency/etqan_tutor --base master --head "$branch" \
    --title "chore: point submodules at their main" \
    --body "Merging this deploys every repo's main to staging.

$body"
