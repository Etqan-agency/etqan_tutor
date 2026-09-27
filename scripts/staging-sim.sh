#!/usr/bin/env bash
# The staging deploy, proven against a simulated server (spec §5).
#   scripts/staging-sim.sh all        up, build, run, then down (`just staging-sim`)
#   scripts/staging-sim.sh up         a local registry and the simulated server
#   scripts/staging-sim.sh build      build the three images, tagged for the registry
#   scripts/staging-sim.sh run        push, deploy A (+ seed, smoke), deploy B under
#                                     a health poll, a failing deploy, then the full
#                                     journey; no secret may show in the output
#   scripts/staging-sim.sh down       remove everything `up` made
# CI runs up, builds with its layer cache (images tagged $(image <name>)), then
# run, and down always.
#
# The server is infra/staging-sim: sshd and Docker-in-Docker, privileged. Its
# registry stand-in is registry:3 with a password, so the deploy's registry
# login is exercised too. Hosts are <sub>.staging.test; the runner reaches the
# server's 443 on 127.0.0.1:$SIM_HTTPS_PORT (curl --connect-to, Chromium
# --host-resolver-rules), so Host headers and SNI are the real names.
#
# Environment (all optional):
#   SIM_SHA          tag A, default the meta repo's HEAD
#   SIM_DIR          work directory (keys, passwords, logs), default
#                    /tmp/etqan-staging-sim; its name must contain staging-sim
#   SIM_HTTPS_PORT, SIM_SSH_PORT, SIM_REGISTRY_PORT, SIM_MAILPIT_PORT
#                    host ports, default 18443, 12222, 15000, 18025 (loopback only)
#   TOKENS_TOKEN_FILE   for `build`: a token that reads the private @etqan/tokens
#                    repo, default `gh auth token`
set -euo pipefail
set +x

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR="${SIM_DIR:-/tmp/etqan-staging-sim}"
SIM_HTTPS_PORT="${SIM_HTTPS_PORT:-18443}"
SIM_SSH_PORT="${SIM_SSH_PORT:-12222}"
SIM_REGISTRY_PORT="${SIM_REGISTRY_PORT:-15000}"
SIM_MAILPIT_PORT="${SIM_MAILPIT_PORT:-18025}"
SHA_A="${SIM_SHA:-$(git -C "$ROOT" rev-parse HEAD)}"
# B is A's images under another tag: a second deploy of the same code.
SHA_B="$(printf '%s-b' "$SHA_A" | sha1sum | cut -c1-40)"
BASE_DOMAIN=staging.test
ACADEMY_URL="https://demo.${BASE_DOMAIN}"
NET=etqan-sim
SERVER=etqan-sim-server
REGISTRY_CONTAINER=etqan-sim-registry
IMAGES=(backend dashboard marketing)

# SIM_DIR is removed with rm -rf and chmodded: refuse anything that does not
# look like a simulation work directory.
check_sim_dir() {
    local dir="${1%/}"
    if [ -z "$dir" ] || [ "$dir" = "${HOME%/}" ] || [[ "$(basename "$dir")" != *staging-sim* ]]; then
        echo "ERROR: SIM_DIR='$1' is not a staging-sim work directory (its name must contain staging-sim; never / or \$HOME)." >&2
        exit 2
    fi
}
check_sim_dir "$SIM_DIR"

# The name a host-side tag pushes to; the server pulls the same repository
# as registry:5000/etqan-agency/<name> (ETQAN_REGISTRY in its env).
image() {
    echo "localhost:${SIM_REGISTRY_PORT}/etqan-agency/$1"
}

ssh_opts() {
    printf '%s\n' -i "${SIM_DIR}/id_ed25519" -p "$SIM_SSH_PORT" -o IdentitiesOnly=yes \
        -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="${SIM_DIR}/known_hosts"
}

on_server() {
    local opts
    mapfile -t opts < <(ssh_opts)
    # shellcheck disable=SC2029 # the arguments are the remote command line
    ssh "${opts[@]}" deploy@127.0.0.1 "$@"
}

up() {
    mkdir -p "$SIM_DIR"
    chmod 700 "$SIM_DIR"
    rm -f "${SIM_DIR}/id_ed25519" "${SIM_DIR}/id_ed25519.pub"
    ssh-keygen -q -t ed25519 -N "" -C etqan-staging-sim -f "${SIM_DIR}/id_ed25519"
    # The registry's one user, with a password nobody sees.
    (umask 077 && openssl rand -hex 24 > "${SIM_DIR}/registry-password")
    printf '%s\n' "$(cat "${SIM_DIR}/registry-password")" |
        docker run -i --rm caddy:2.11.4-alpine caddy hash-password |
        sed 's/^/sim:/' > "${SIM_DIR}/htpasswd"

    docker network create "$NET" >/dev/null
    docker run -d --name "$REGISTRY_CONTAINER" --network "$NET" --network-alias registry \
        -p "127.0.0.1:${SIM_REGISTRY_PORT}:5000" \
        -v "${SIM_DIR}/htpasswd:/auth/htpasswd:ro" \
        -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=etqan-sim \
        -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
        registry:3.1.2 >/dev/null

    docker build -q -t etqan-staging-sim "${ROOT}/infra/staging-sim" >/dev/null
    docker run -d --privileged --name "$SERVER" --network "$NET" \
        -p "127.0.0.1:${SIM_SSH_PORT}:22" -p "127.0.0.1:${SIM_HTTPS_PORT}:443" \
        -e AUTHORIZED_KEY="$(cat "${SIM_DIR}/id_ed25519.pub")" \
        etqan-staging-sim >/dev/null
    for _ in $(seq 1 60); do
        docker exec "$SERVER" docker info >/dev/null 2>&1 && break
        sleep 1
    done
    docker exec "$SERVER" docker info >/dev/null
    # known_hosts from the server's own key, as STAGING_KNOWN_HOSTS would be.
    echo "[127.0.0.1]:${SIM_SSH_PORT} $(docker exec "$SERVER" cat /etc/ssh/ssh_host_ed25519_key.pub | cut -d' ' -f1-2)" \
        > "${SIM_DIR}/known_hosts"
    echo "Simulated server up: ssh on 127.0.0.1:${SIM_SSH_PORT}, https on 127.0.0.1:${SIM_HTTPS_PORT}."
}

build() {
    local token_file="${TOKENS_TOKEN_FILE:-}" cleanup=0 name
    if [ -z "$token_file" ]; then
        token_file="$(mktemp)"
        cleanup=1
        env -u GH_TOKEN -u GITHUB_TOKEN gh auth token > "$token_file"
    fi
    docker build -q -t "$(image backend):${SHA_A}" "${ROOT}/backend" >/dev/null
    for name in dashboard marketing; do
        docker build -q --secret "id=tokens_token,src=${token_file}" \
            -t "$(image "$name"):${SHA_A}" "${ROOT}/${name}" >/dev/null
    done
    if [ "$cleanup" = 1 ]; then rm -f "$token_file"; fi
    echo "Built the three images as ${SHA_A}."
}

# The server's .env.production, from .env.staging.example: fresh secrets,
# the test base domain and the local registry. It is written once, on the
# server only, and any CHANGE_ME left over fails the run (the template must
# stay complete).
write_env() {
    local env
    env="$(sed \
        -e "s|CHANGE_ME_SECRET_KEY|$(openssl rand -hex 32)|" \
        -e "s|CHANGE_ME_DB_PASSWORD|$(openssl rand -hex 16)|g" \
        -e "s|CHANGE_ME_S3_SECRET|$(openssl rand -hex 16)|" \
        -e "s|CHANGE_ME_DEMO_PASSWORD|$(openssl rand -hex 16)|" \
        -e "s|^BASE_DOMAIN=.*|BASE_DOMAIN=${BASE_DOMAIN}|" \
        -e "s|^ETQAN_REGISTRY=.*|ETQAN_REGISTRY=registry:5000/etqan-agency|" \
        "${ROOT}/infra/.env.staging.example")"
    if grep -v '^#' <<< "$env" | grep -q CHANGE_ME; then
        echo "ERROR: .env.staging.example has a placeholder this script does not fill." >&2
        exit 1
    fi
    on_server 'umask 077 && mkdir -p /opt/etqan && cat > /opt/etqan/.env.production' <<< "$env"
}

deploy() { # deploy <sha> <seed 0|1>
    STAGING_SSH_HOST=127.0.0.1 STAGING_SSH_USER=deploy STAGING_SSH_PORT="$SIM_SSH_PORT" \
        STAGING_SSH_KEY_FILE="${SIM_DIR}/id_ed25519" \
        STAGING_KNOWN_HOSTS_FILE="${SIM_DIR}/known_hosts" \
        STAGING_BASE_URL="$ACADEMY_URL" \
        REGISTRY=registry:5000 REGISTRY_USER=sim \
        REGISTRY_TOKEN="$(cat "${SIM_DIR}/registry-password")" \
        SEED="$2" SMOKE_CONNECT_TO="::127.0.0.1:${SIM_HTTPS_PORT}" \
        bash "${ROOT}/scripts/deploy-staging.sh" "$1"
}

push() { # push <sha>: A's images, under the tag <sha>
    local name
    for name in "${IMAGES[@]}"; do
        if [ "$1" != "$SHA_A" ]; then
            docker tag "$(image "$name"):${SHA_A}" "$(image "$name"):$1"
        fi
        docker push -q "$(image "$name"):$1" >/dev/null
    done
}

# PIDs of background jobs run_steps starts, so stop_background (its EXIT
# trap) can always find and kill them, however run_steps exits.
POLLER_PID=""
TUNNEL_PID=""

stop_background() {
    if [ -n "$POLLER_PID" ]; then
        touch "${SIM_DIR}/stop-polling" 2>/dev/null || true
        kill "$POLLER_PID" 2>/dev/null || true
        wait "$POLLER_PID" 2>/dev/null || true
        POLLER_PID=""
    fi
    if [ -n "$TUNNEL_PID" ]; then
        kill "$TUNNEL_PID" 2>/dev/null || true
        wait "$TUNNEL_PID" 2>/dev/null || true
        TUNNEL_PID=""
    fi
}

run_steps() {
    local codes before after
    trap stop_background EXIT
    docker login "localhost:${SIM_REGISTRY_PORT}" -u sim --password-stdin \
        < "${SIM_DIR}/registry-password" >/dev/null
    push "$SHA_A"
    write_env

    echo "━━ Deploy A (${SHA_A}), seed, smoke"
    deploy "$SHA_A" 1

    echo "━━ Uploads: the S3 store takes a file and serves it publicly"
    on_server bash /opt/etqan/scripts/manage.sh shell -c \
        "'from django.core.files.base import ContentFile; from django.core.files.storage import default_storage as s; s.save(\"tenants/staging-sim/check.txt\", ContentFile(b\"ok\"))'"
    if [ "$(on_server docker exec etqan-s3-1 curl -s \
        "http://127.0.0.1:9000/etqan-staging-media/tenants/staging-sim/check.txt")" != ok ]; then
        echo "ERROR: the uploaded file was not readable back from the S3 store." >&2
        exit 1
    fi

    echo "━━ Deploy B (${SHA_B}) while /health/ready/ is polled"
    push "$SHA_B"
    on_server bash /opt/etqan/scripts/edge-ca.sh > "${SIM_DIR}/root.crt"
    before="$(on_server cat /opt/etqan/.active-color)"
    : > "${SIM_DIR}/polls"
    rm -f "${SIM_DIR}/stop-polling"
    # stdout/stderr point straight at polls (the file the assertion below
    # reads), not at run_steps' own fds: those feed run()'s tee, and a
    # background job that still holds that pipe open (because a step after
    # it failed and exited early) would keep tee from ever seeing EOF.
    (
        while [ ! -f "${SIM_DIR}/stop-polling" ]; do
            curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 \
                --cacert "${SIM_DIR}/root.crt" --connect-to "::127.0.0.1:${SIM_HTTPS_PORT}" \
                "${ACADEMY_URL}/health/ready/" || true
            sleep 0.2
        done
    ) >> "${SIM_DIR}/polls" 2>&1 &
    POLLER_PID=$!
    deploy "$SHA_B" 0
    touch "${SIM_DIR}/stop-polling"
    wait "$POLLER_PID"
    POLLER_PID=""
    after="$(on_server cat /opt/etqan/.active-color)"
    codes="$(sort "${SIM_DIR}/polls" | uniq -c | tr -s ' ')"
    echo "Colour ${before} → ${after}; polls:${codes}"
    if [ "$before" = "$after" ]; then
        echo "ERROR: the active colour did not flip." >&2
        exit 1
    fi
    if [ "$(wc -l < "${SIM_DIR}/polls")" -lt 50 ] || grep -qv '^200$' "${SIM_DIR}/polls"; then
        echo "ERROR: a health poll during the switch was not 200 (or too few ran)." >&2
        exit 1
    fi

    echo "━━ A deploy that fails (no images for its SHA) leaves ${after} serving"
    if deploy 0000000000000000000000000000000000000000 0; then
        echo "ERROR: a deploy of images that do not exist succeeded." >&2
        exit 1
    fi
    if [ "$(on_server cat /opt/etqan/.active-color)" != "$after" ]; then
        echo "ERROR: the failed deploy changed the active colour." >&2
        exit 1
    fi
    if [ "$(curl -s -o /dev/null -w '%{http_code}' --cacert "${SIM_DIR}/root.crt" \
        --connect-to "::127.0.0.1:${SIM_HTTPS_PORT}" "${ACADEMY_URL}/health/ready/")" != 200 ]; then
        echo "ERROR: the edge did not answer 200 after the failed deploy." >&2
        exit 1
    fi
    echo "Still serving from ${after}."

    echo "━━ The full journey against the deployed stack"
    local opts
    mapfile -t opts < <(ssh_opts)
    ssh "${opts[@]}" -N -L "127.0.0.1:${SIM_MAILPIT_PORT}:127.0.0.1:8025" deploy@127.0.0.1 &
    TUNNEL_PID=$!
    sleep 2
    if ! (
        cd "${ROOT}/dashboard"
        E2E_BASE_URL="https://${BASE_DOMAIN}" \
            E2E_MAILPIT_URL="http://127.0.0.1:${SIM_MAILPIT_PORT}" \
            E2E_MANAGE="ssh ${opts[*]} deploy@127.0.0.1 bash /opt/etqan/scripts/manage.sh" \
            E2E_HOST_RESOLVER_RULES="MAP *.${BASE_DOMAIN} 127.0.0.1:${SIM_HTTPS_PORT}, MAP ${BASE_DOMAIN} 127.0.0.1:${SIM_HTTPS_PORT}" \
            E2E_IGNORE_HTTPS_ERRORS=1 \
            npx pnpm@10 exec playwright test e2e/journey.spec.ts --retries=0
    ); then
        exit 1
    fi
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
    TUNNEL_PID=""
}

# Fails when any secret the run handled shows in its output: the registry
# password and the server's generated secrets (read on the server, never
# printed).
no_secret_in() {
    local secret found=0 count=0
    while IFS= read -r secret; do
        [ -n "$secret" ] || continue
        count=$((count + 1))
        if grep -qF -- "$secret" "$1"; then
            found=1
        fi
    done < <(
        cat "${SIM_DIR}/registry-password"
        on_server "sed -n -E 's/^(DJANGO_SECRET_KEY|POSTGRES_PASSWORD|AWS_SECRET_ACCESS_KEY|DJANGO_STAGING_DEMO_PASSWORD)=//p' /opt/etqan/.env.production"
    )
    if [ "$found" = 1 ]; then
        echo "ERROR: a secret appeared in the run's output." >&2
        return 1
    fi
    # The registry password and the server's four: fewer means the check
    # read nothing to compare with.
    if [ "$count" -lt 5 ]; then
        echo "ERROR: only $count of 5 secrets were read; the output was not checked." >&2
        return 1
    fi
    echo "No secret in the run's output."
}

run() {
    local status=0
    # run_steps in a fresh bash process, not on the left of this run()'s own
    # `|| status=$?`: with `set -e`, a command on the left of `|` or `||`
    # inside run_steps would never actually stop it (errexit is suspended for
    # any command whose exit status is about to be tested), so a failing
    # step's checks would be silently ignored and the run would report
    # success. PIPESTATUS[0] is the fresh process's real exit code.
    set +e
    bash "${BASH_SOURCE[0]}" run-steps 2>&1 | tee "${SIM_DIR}/run.log"
    status="${PIPESTATUS[0]}"
    set -e
    no_secret_in "${SIM_DIR}/run.log"
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi
    echo "Staging simulation passed."
}

# The server, the registry and the work directory. The built images stay,
# so CI's retry can run again without rebuilding.
down() {
    docker rm -fv "$SERVER" "$REGISTRY_CONTAINER" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    docker logout "localhost:${SIM_REGISTRY_PORT}" >/dev/null 2>&1 || true
    rm -rf "$SIM_DIR"
    echo "Simulated server removed."
}

remove_images() {
    local name
    for name in "${IMAGES[@]}"; do
        docker image ls -q "$(image "$name")" | sort -u | xargs -r docker rmi -f >/dev/null 2>&1 || true
    done
}

case "${1:-all}" in
    up) up ;;
    build) build ;;
    run) run ;;
    # Internal: run() execs this in a fresh process so `set -euo pipefail`
    # actually applies to it (see run()'s comment).
    run-steps) run_steps ;;
    down) down ;;
    all)
        trap 'down; remove_images' EXIT
        up
        build
        run
        ;;
    *)
        echo "Usage: staging-sim.sh [all|up|build|run|down]" >&2
        exit 2
        ;;
esac
