#!/usr/bin/env bash
# docker compose for the local stack, with the ETQAN-QA-001 GID workaround (HOST_GID=1000).
cd "/Users/khaledsakr/Documents/Etqan tutor/etqan_tutor"
export HOST_UID=$(id -u) HOST_GID=1000
export GH_TOKEN="${GH_TOKEN:-$(env -u GH_TOKEN -u GITHUB_TOKEN gh auth token 2>/dev/null)}"
exec docker compose -f docker-compose.local.yml "$@"
