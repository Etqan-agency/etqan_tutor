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
cp "$scripts/../../justfile" "$tmp/seed-meta/justfile"
printf '.env.*\n__pycache__/\n' >"$tmp/seed-meta/.gitignore"  # as the meta .gitignore does
git -C "$tmp/seed-meta" add . && git -C "$tmp/seed-meta" commit -qm init && git -C "$tmp/seed-meta" push -q origin master

# The main checkout, as a developer has it.
git clone -q --recurse-submodules -b master "$tmp/remotes/meta.git" "$tmp/etqan_tutor"
printf 'DATABASE_URL=postgres://etqan:etqan@localhost:5432/etqan\nSECRET=1\nCELERY_BROKER_URL=redis://localhost:6379/0\n' \
  >"$tmp/etqan_tutor/backend/.env"
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
# Host-side manage.py and e2e in the phase reach the phase's database and
# broker, never the main stack's (final review I1).
grep -qx "DATABASE_URL=postgres://etqan:etqan@localhost:5632/etqan" "$dir/backend/.env" \
  || fail "backend/.env DATABASE_URL not on slot 2: $(cat "$dir/backend/.env")"
grep -qx "CELERY_BROKER_URL=redis://localhost:6579/0" "$dir/backend/.env" \
  || fail "backend/.env CELERY_BROKER_URL not on slot 2: $(cat "$dir/backend/.env")"
grep -q "5432" "$main/backend/.env" || fail "main backend/.env was changed"
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

# Stub docker: records each call with the compose project it would act on.
stub="$tmp/stub"; mkdir -p "$stub"
cat >"$stub/docker" <<'STUB'
#!/usr/bin/env bash
echo "${COMPOSE_PROJECT_NAME:-none} $*" >>"$STUB_LOG"
STUB
export STUB_LOG="$tmp/docker.log"
chmod +x "$stub/docker"

# `just e2e` sets E2E_MANAGE to `just --justfile <justfile> _stack-manage`;
# e2e/manage.ts runs it from dashboard/ with every argument shell-quoted.
(cd "$dir/dashboard" && PATH="$stub:$PATH" just --justfile "$dir/justfile" _stack-manage \
  "'set_features'" "'demo'" "'--on'" "'it'\\''s two'") || fail "_stack-manage failed"
expected="etqan-b3 compose -f docker-compose.local.yml exec -T django python manage.py set_features demo --on it's two"
[ "$(tail -n 1 "$tmp/docker.log")" = "$expected" ] || fail "_stack-manage ran: $(tail -n 1 "$tmp/docker.log")"

# `just stream-down` refuses in the main checkout (the owner's volumes).
if (cd "$main" && PATH="$stub:$PATH" just stream-down 2>/dev/null); then fail "stream-down ran in the main checkout"; fi
[ "$(wc -l <"$tmp/docker.log")" -eq 1 ] || fail "stream-down called docker in the main checkout"

# A launch takes the phase as eligible prints it (B5) and checks its
# arguments before creating anything (final review M4).
for args in "b5 b5a-x 0" "b5 b5a-x 9" "b/5 b5a-x 1" "b5 'bad suffix' 1"; do
  # shellcheck disable=SC2086
  if (cd "$main" && eval bash scripts/orchestration/launch-phase.sh $args 2>/dev/null); then fail "launch accepted: $args"; fi
done
for made in "$tmp/wt"/*; do
  case "${made##*/}" in _ledger | b3) ;; *) fail "a refused launch created: $made" ;; esac
done
out5="$(cd "$main" && bash scripts/orchestration/launch-phase.sh B5 b5a-x 3)"
[ -d "$tmp/wt/b5" ] || fail "uppercase phase not lowercased: $out5"
grep -qx "COMPOSE_PROJECT_NAME=etqan-b5" "$tmp/wt/b5/.env.stream" || fail "b5 .env.stream wrong"

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

# Teardown (CONDUCTOR.md step 6, final review I4): the stack goes down with
# its volumes under the phase's own project, then every worktree and every
# feat/<phase>… branch of the phase, and the main checkout stays healthy.
git -C "$main/backend" branch -q feat/b3b-later  # a later slice's branch
git -C "$main/backend" branch -q feat/b30-unrelated  # not b3's
: >"$tmp/docker.log"
(cd "$main" && PATH="$stub:$PATH" bash scripts/orchestration/teardown-phase.sh B3 >/dev/null) || fail "teardown failed"
[ "$(cat "$tmp/docker.log")" = "etqan-b3 compose -f docker-compose.local.yml down -v --remove-orphans" ] \
  || fail "stack not taken down under etqan-b3: $(cat "$tmp/docker.log")"
[ ! -e "$dir" ] || fail "phase dir left behind: $(ls -A "$dir")"
for repo in "" /backend /dashboard /marketing; do
  if git -C "$main$repo" worktree list --porcelain | grep -qF "$dir"; then fail "worktree left in main$repo"; fi
  left="$(git -C "$main$repo" branch --list 'feat/b3[a-z]*')"
  [ -z "$left" ] || fail "branches left in main$repo: $left"
done
git -C "$main/backend" rev-parse --verify -q feat/b30-unrelated >/dev/null || fail "teardown deleted another phase's branch"
for sub in backend dashboard marketing; do
  worktree="$(git -C "$main" config -f ".git/modules/$sub/config" core.worktree)"
  [ "$worktree" = "../../../$sub" ] || fail "main's $sub core.worktree corrupted by teardown: $worktree"
  git -C "$main/$sub" status --porcelain >/dev/null || fail "main $sub broken after teardown"
done
[ -d "$tmp/wt/b4" ] && [ -d "$tmp/wt/b5" ] || fail "teardown touched other phases"
if (cd "$main" && PATH="$stub:$PATH" bash scripts/orchestration/teardown-phase.sh b3 2>/dev/null); then fail "second teardown accepted"; fi
echo "launch_phase_test: ok"
