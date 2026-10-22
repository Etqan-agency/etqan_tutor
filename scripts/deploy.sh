#!/usr/bin/env bash
# Deploy one image tag to a server (staging or production) and check it from
# outside (spec §3.2). The deploy workflow and scripts/staging-sim.sh both run
# exactly this:
#   1. copy infra/ to /opt/etqan/ (never .env.production or .active-color);
#   2. log the server in to the registry, when a token is given;
#   3. run ship.sh <sha> there (blue/green);
#   4. seed the demo academy, when SEED=1;
#   5. run infra/scripts/smoke.sh here, against DEPLOY_ACADEMY_URL.
#
#   scripts/deploy.sh <40-character meta commit SHA>
#
# Environment:
#   DEPLOY_SSH_HOST, DEPLOY_SSH_USER     the server and its deploy user
#   DEPLOY_SSH_PORT                      optional, default 22
#   DEPLOY_SSH_KEY_FILE                  a file holding the private key
#   DEPLOY_KNOWN_HOSTS_FILE              a file holding the server's host key(s)
#   DEPLOY_ACADEMY_URL                   an academy's URL (https://demo.staging.example.com)
#   REGISTRY_TOKEN                       optional: a read-only registry token, sent
#                                        on stdin, never on a command line
#   REGISTRY, REGISTRY_USER              the registry (default ghcr.io) and its user
#   SEED                                 optional, 1 runs seed_staging before the smoke check
#   SMOKE_CONNECT_TO                     optional, passed on to smoke.sh
#
# Nothing here prints a secret: the key and known hosts are files, the token
# goes through a pipe, and the server's .env.production is never read.
set -euo pipefail
set +x

SHA="${1:?Usage: deploy.sh <commit-sha>}"
if ! [[ "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: expected a full 40-character commit SHA, got '${SHA}'." >&2
    exit 2
fi
: "${DEPLOY_SSH_HOST:?}" "${DEPLOY_SSH_USER:?}" "${DEPLOY_SSH_KEY_FILE:?}"
: "${DEPLOY_KNOWN_HOSTS_FILE:?}" "${DEPLOY_ACADEMY_URL:?}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SSH=(ssh -i "$DEPLOY_SSH_KEY_FILE" -p "${DEPLOY_SSH_PORT:-22}"
    -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20
    -o ServerAliveInterval=15 -o ServerAliveCountMax=4
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$DEPLOY_KNOWN_HOSTS_FILE")
TARGET="${DEPLOY_SSH_USER}@${DEPLOY_SSH_HOST}"
remote() {
    "${SSH[@]}" "$TARGET" "$@"
}

echo "── 1/5 Copy infra/ to ${TARGET}:/opt/etqan/"
# No --delete: files only the server has (backups, notes) stay. The two
# server-owned files are excluded even if a stray copy sits in infra/.
rsync -rlt --itemize-changes \
    --exclude=.git --exclude=/.env.production --exclude=/.active-color \
    -e "$(printf '%q ' "${SSH[@]}")" \
    "${ROOT}/infra/" "${TARGET}:/opt/etqan/"

echo "── 2/5 Registry login"
if [ -n "${REGISTRY_TOKEN:-}" ]; then
    printf '%s' "$REGISTRY_TOKEN" |
        remote docker login "${REGISTRY:-ghcr.io}" -u "${REGISTRY_USER:?}" --password-stdin
    unset REGISTRY_TOKEN
else
    echo "No REGISTRY_TOKEN: using the server's existing registry login."
fi

echo "── 3/5 ship.sh ${SHA}"
remote bash /opt/etqan/scripts/ship.sh "$SHA"

echo "── 4/5 Seed"
if [ "${SEED:-0}" = 1 ]; then
    remote bash /opt/etqan/scripts/manage.sh seed_staging
else
    echo "Not asked to seed."
fi

echo "── 5/5 Smoke check ${DEPLOY_ACADEMY_URL}"
CA="$(mktemp)"
trap 'rm -f "$CA"' EXIT
remote bash /opt/etqan/scripts/edge-ca.sh > "$CA"
if [ -s "$CA" ]; then
    echo "The edge uses its internal CA; trusting its root for the check."
    export SMOKE_CACERT="$CA"
fi
bash "${ROOT}/infra/scripts/smoke.sh" "$DEPLOY_ACADEMY_URL"
