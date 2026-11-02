#!/usr/bin/env bash
# bump-submodules.sh (just bump) and check-submodule-pins.sh, against a meta
# repo whose dashboard, marketing and tokens submodules are local bare repos.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scripts="$here/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
g() { git -c protocol.file.allow=always -c init.defaultBranch=main "$@"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A repo <name>.git with one commit on main; <name>-work pushes to it.
repo() {
  g init -q --bare "$tmp/$1.git"
  g clone -q "$tmp/$1.git" "$tmp/$1-work" 2>/dev/null
  commit "$1" first
}
commit() {
  echo "$2" >"$tmp/$1-work/$2"
  g -C "$tmp/$1-work" add -A
  g -C "$tmp/$1-work" commit -q -m "$2"
  g -C "$tmp/$1-work" push -q origin HEAD:main
}
pin_tokens() { # <consumer> <tag>
  printf '{ "dependencies": { "@etqan/tokens": "github:o/tokens#%s" } }\n' "$2" \
    >"$tmp/$1-work/package.json"
  commit "$1" "pin-$2"
}

repo tokens
g -C "$tmp/tokens-work" tag -a v1 -m v1 && g -C "$tmp/tokens-work" push -q origin v1
for c in dashboard marketing; do repo "$c"; pin_tokens "$c" v1; done

g init -q --bare "$tmp/meta.git"
g clone -q "$tmp/meta.git" "$tmp/meta" 2>/dev/null
meta="$tmp/meta"
mkdir -p "$meta/scripts"
cp "$scripts/bump-submodules.sh" "$scripts/check-submodule-pins.sh" "$scripts/check-token-pin.mjs" "$meta/scripts/"
for s in dashboard marketing tokens; do g -C "$meta" submodule add -q "$tmp/$s.git" "$s" 2>/dev/null; done
g -C "$meta/tokens" checkout -q v1
g -C "$meta" add -A
g -C "$meta" commit -q -m init
g -C "$meta" branch -q -m master
g -C "$meta" push -q -u origin master

# A fake gh records what it was asked to do.
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "$@" >>"%s/gh.log"\n' "$tmp" >"$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
check() { (cd "$meta" && bash scripts/check-submodule-pins.sh); }
bump() { (cd "$meta" && bash scripts/bump-submodules.sh); }

# Every pointer on main: the check passes quietly, and there is nothing to bump.
out="$(check 2>&1)" || fail "check failed on pointers at main: $out"
out="$(bump 2>&1)" || fail "bump failed with nothing to do: $out"
grep -q "already" <<<"$out" || fail "bump did not say nothing moved: $out"
[ "$(g -C "$meta" branch --show-current)" = master ] || fail "bump left a branch behind with nothing to do"
[ ! -e "$tmp/gh.log" ] || fail "bump opened a PR with nothing to do"

# main moves on: the check warns but passes, and bump moves the pointer.
commit dashboard feature
out="$(check 2>&1)" || fail "check failed on a pointer behind main: $out"
grep -q "dashboard is 1 commit(s) behind" <<<"$out" || fail "no behind-main warning: $out"
bump >/dev/null 2>&1 || fail "bump failed"
branch="$(g -C "$meta" branch --show-current)"
[[ "$branch" == chore/bump-submodules-* ]] || fail "bump is on '$branch'"
[ "$(g -C "$meta" rev-parse HEAD:dashboard)" = "$(g -C "$tmp/dashboard-work" rev-parse HEAD)" ] ||
  fail "dashboard pointer did not move to main"
g -C "$meta" log -1 --format=%B | grep -q "dashboard: .* (1 commit" || fail "commit body lacks the dashboard range"
g -C "$tmp/meta.git" rev-parse -q --verify "refs/heads/$branch" >/dev/null || fail "branch not pushed"
grep -q "pr create --repo Etqan-agency/etqan_tutor --base master --head $branch" "$tmp/gh.log" ||
  fail "no meta PR opened: $(cat "$tmp/gh.log")"

# tokens follows the tag the consumers pin, not main.
g -C "$meta" switch -q master && rm -f "$tmp/gh.log"
commit tokens unreleased
g -C "$tmp/tokens-work" tag -a v2 -m v2 HEAD~0 && g -C "$tmp/tokens-work" push -q origin v2
commit tokens after-v2
for c in dashboard marketing; do pin_tokens "$c" v2; done
bump >/dev/null 2>&1 || fail "bump failed on a tokens release"
[ "$(g -C "$meta" rev-parse HEAD:tokens)" = "$(g -C "$tmp/tokens-work" rev-parse 'v2^{commit}')" ] ||
  fail "tokens pointer is not the pinned tag v2"

# A half-done token bump (consumers disagree) stops before anything is committed.
g -C "$meta" switch -q master && rm -f "$tmp/gh.log"
pin_tokens marketing v1
if out="$(bump 2>&1)"; then fail "bump passed with consumers on different tokens: $out"; fi
grep -q "disagree" <<<"$out" || fail "bump did not report the token disagreement: $out"
[ "$(g -C "$meta" branch --show-current)" = master ] || fail "a failed bump left its branch checked out"
[ ! -e "$tmp/gh.log" ] || fail "a failed bump opened a PR"
pin_tokens marketing v2

# A pointer to a commit only on an unmerged branch fails the check.
g -C "$meta/dashboard" fetch -q origin main
g -C "$meta/dashboard" checkout -q --detach origin/main
echo wip >"$meta/dashboard/wip" && g -C "$meta/dashboard" add wip && g -C "$meta/dashboard" commit -q -m wip
g -C "$meta/dashboard" push -q origin HEAD:refs/heads/feat/wip
g -C "$meta" add dashboard
if out="$(check 2>&1)"; then fail "check passed on a pointer not on main: $out"; fi
grep -q "dashboard points at .* not on its origin/main" <<<"$out" || fail "wrong error: $out"

# bump refuses to move a submodule that has uncommitted changes.
g -C "$meta" reset -q && echo dirty >>"$meta/dashboard/first"
if out="$(bump 2>&1)"; then fail "bump moved a dirty submodule: $out"; fi
grep -q "uncommitted changes in dashboard" <<<"$out" || fail "wrong refusal: $out"
echo "submodules_test: ok"
