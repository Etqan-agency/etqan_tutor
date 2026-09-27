#!/usr/bin/env bash
# Does a pull request need the staging simulation (spec §5)? Prints true or
# false. True when the meta diff since <base> touches the infra pointer, the
# workflows, the Caddyfiles or the deploy and simulation scripts, or when a
# backend, dashboard or marketing pointer moves what shapes its image (the
# Dockerfile, .dockerignore, nginx.conf or requirements/) or what the
# simulation itself exercises: dashboard's e2e/ and playwright.config.ts, or
# backend's seed_dev.py, seed_staging.py, config/settings/production.py and
# base.py. Master pushes always run the simulation; the workflow does not
# ask.
#   scripts/staging-sim-needed.sh <base-sha>
set -euo pipefail

BASE="${1:?Usage: staging-sim-needed.sh <base-sha>}"
changed="$(git diff --name-only "$BASE" HEAD)"
if grep -qE '^(infra$|\.github/workflows/|caddy/|scripts/(deploy-staging|staging-sim))' <<< "$changed"; then
    echo true
    exit 0
fi
for repo in backend dashboard marketing; do
    grep -qx "$repo" <<< "$changed" || continue
    old="$(git rev-parse "${BASE}:${repo}")"
    git -C "$repo" cat-file -e "${old}^{commit}" 2>/dev/null ||
        git -C "$repo" fetch -q --depth=1 origin "$old"
    pattern='^(Dockerfile|\.dockerignore|nginx\.conf|requirements/)'
    case "$repo" in
        backend) pattern+='|^etqan/tenants/management/commands/seed_(dev|staging)\.py$|^config/settings/(production|base)\.py$' ;;
        dashboard) pattern+='|^e2e/|^playwright\.config\.ts$' ;;
    esac
    if git -C "$repo" diff --name-only "$old" HEAD |
        grep -qE "$pattern"; then
        echo true
        exit 0
    fi
done
echo false
