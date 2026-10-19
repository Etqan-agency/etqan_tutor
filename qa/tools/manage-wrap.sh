#!/usr/bin/env bash
# E2E_MANAGE target: manage.py in the running django container. One word with no spaces works
# around ETQAN-QA-009 (manage.ts splits E2E_MANAGE on whitespace).
# manage.ts shell-quotes every argument for a remote shell (ssh semantics), so parse them like a
# shell would before handing them to docker compose.
eval "set -- $*"
exec "$(dirname "$0")/dc.sh" exec -T django python manage.py "$@"
