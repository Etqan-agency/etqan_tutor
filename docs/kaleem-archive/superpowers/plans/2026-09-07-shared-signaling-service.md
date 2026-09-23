# Shared Signaling Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop a session becoming permanently unjoinable after a deploy, by making signaling a shared service on one hostname instead of a per-colour one.

**Architecture:** `signaling-blue` and `signaling-green` collapse into a single `signaling` service in the shared block beside `traefik`, `postgres`, `redis`, `flower` and `coturn`, on one `${WS_DOMAIN}`. Both Djangos then hand out the same `DJANGO_SIGNALING_URL`, so `Room.signaling_url` can never disagree with the live deployment and a stale room row self-heals — the relay creates its room on first connect. A one-off data migration ends the `ACTIVE` rows that still carry a per-colour host.

**Tech Stack:** Django 5 + DRF, Starlette/uvicorn (signaling), Docker Compose, Traefik, pytest, import-linter.

**Spec:** `docs/superpowers/specs/2026-09-07-shared-signaling-service-design.md`

## Global Constraints

- **Two repos.** Backend work goes in the `backend` submodule on `feat/shared-signaling`; infra work goes in the `infra` submodule on `feat/shared-signaling`. The meta repo gets docs plus submodule pointer bumps. All three via `feat → PR → trunk` (ADR-0028). **Never commit to a trunk.**
- **`${WS_DOMAIN:?WS_DOMAIN is required}` — the `:?` form is mandatory.** A bare `${WS_DOMAIN}` expands an unset variable to the empty string, making `DJANGO_SIGNALING_URL` the truthy string `wss://`, which defeats `SignalingProvider`'s own fail-closed guard and persists a broken pin. This was a real Critical in C3c. Every reference uses `:?`.
- **`--log-config signaling/logconf.json` is not optional** on the signaling command. Without it uvicorn logs the handshake path including the capability token — a replayable grant to a child's lesson sitting in `docker logs`. Also a real Critical.
- **Do not touch the drain.** A deploy still drops calls in progress; that needs a join-routing switch that does not exist. `docs/runbook/signaling.md`'s "deploy between lessons" rule stands.
- **`Room.signaling_url` is kept.** Do not delete the column or start reading `settings.SIGNALING_URL` at join time.
- **Backend coverage floor is 97.7** (`pyproject.toml` `[tool.coverage.report]`). Measure with `pytest --cov=kaleem --cov=signaling`, **never a bare `pytest --cov`** — the bare form omits files no test imports and reads ~0.55 high. `precision = 1` in that file is load-bearing; do not remove it.
- **import-linter must stay green.** ADR-0035's contract: `kaleem` may import `signaling.tokens`; `signaling` may never import `kaleem`.
- Commands from `backend/`: `pytest`, `ruff check .`, `mypy .`, `lint-imports`.
- **Nothing in this plan is verifiable by CI.** The `e2e` job runs its own signaling on `:9000` and never exercises Traefik routing or blue-green. Task 6 is a live staging check and is as much the deliverable as the code.

---

## File Structure

**Modified — `infra`**

| File | Change |
| --- | --- |
| `docker-compose.production.yml` | `signaling-blue` + `signaling-green` → one `signaling` in the shared block; both Djangos get `DJANGO_SIGNALING_URL=wss://${WS_DOMAIN:?…}` |
| `scripts/ship.sh` | `signaling` joins the shared `up -d` (step 4); leaves the colour start/stop/rollback lists (steps 5, 6, 6b, 8); health check retargets `kaleem-signaling-1` |
| `.env.production.example` | `WS_BLUE_DOMAIN`/`WS_GREEN_DOMAIN` → `WS_DOMAIN`, with the reasoning rewritten |

**Created — `backend`**

| File | Responsibility |
| --- | --- |
| `kaleem/scheduling/migrations/0009_end_active_rooms.py` | One-off: end every `ACTIVE` room, so rows pinned to a per-colour host stop being reused |
| `kaleem/scheduling/tests/test_migration_0009.py` | Proves the migration ends active rooms and that `_ensure_room` then mints a fresh one |

**Modified — meta:** `docs/runbook/signaling.md`, `ISSUES.md`, `STATE.md`, the spec's front matter, `docs/superpowers/journal/2026-W36.md`, and the `infra`/`backend` pointers.

---

### Task 1: The one-off migration that ends stale rooms

Do this first. It is independent of the infra change, it is what unbreaks sessions 3 and 5, and it must be on `main` before the per-colour hosts are deleted.

**Files:**
- Create: `backend/kaleem/scheduling/migrations/0009_end_active_rooms.py`
- Create: `backend/kaleem/scheduling/tests/test_migration_0009.py`

**Interfaces:**
- Consumes: `Room` from `kaleem.scheduling.models` — fields `session`, `provider`, `external_id`, `signaling_url`, `status` (`Room.Status.ACTIVE` = `"active"`, `Room.Status.ENDED` = `"ended"`), `created_at`, `ended_at`. Latest existing migration is `0008_calldiagnostic`.
- Produces: migration `scheduling.0009_end_active_rooms`.

- [ ] **Step 1: Write the failing test**

```python
# backend/kaleem/scheduling/tests/test_migration_0009.py
import pytest
from django.utils import timezone

from kaleem.scheduling.models import Room


@pytest.mark.django_db
def test_migration_ends_every_active_room(migrator, session_factory):
    """Rows pinned to a per-colour host must not survive as ACTIVE.

    The host they name stops routing the moment the per-colour services are
    deleted, and `_ensure_room` reuses an ACTIVE row forever -- so the session
    would be permanently unjoinable with no error naming the cause.
    """
    old = migrator.apply_initial_migration(("scheduling", "0008_calldiagnostic"))
    Session = old.get_model("scheduling", "Session")
    OldRoom = old.get_model("scheduling", "Room")
    session = Session.objects.get(pk=session_factory().pk)
    OldRoom.objects.create(
        session=session,
        provider="signaling",
        external_id=f"session-{session.pk}",
        signaling_url="wss://ws-green-staging.kaleem.academy",
        status="active",
    )

    new = migrator.apply_tested_migration(("scheduling", "0009_end_active_rooms"))
    NewRoom = new.get_model("scheduling", "Room")

    row = NewRoom.objects.get()
    assert row.status == "ended"
    assert row.ended_at is not None


@pytest.mark.django_db
def test_already_ended_rooms_are_left_alone(migrator, session_factory):
    """An ENDED row already has an `ended_at`; the migration must not stamp a
    new one over it and rewrite history."""
    old = migrator.apply_initial_migration(("scheduling", "0008_calldiagnostic"))
    Session = old.get_model("scheduling", "Session")
    OldRoom = old.get_model("scheduling", "Room")
    session = Session.objects.get(pk=session_factory().pk)
    stamped = timezone.now()
    OldRoom.objects.create(
        session=session,
        provider="signaling",
        external_id=f"session-{session.pk}",
        signaling_url="wss://ws-blue-staging.kaleem.academy",
        status="ended",
        ended_at=stamped,
    )

    new = migrator.apply_tested_migration(("scheduling", "0009_end_active_rooms"))
    NewRoom = new.get_model("scheduling", "Room")

    assert NewRoom.objects.get().ended_at == stamped


@pytest.mark.django_db
def test_a_fresh_room_is_minted_after_the_migration(settings, session_factory):
    """The point of ending them: the next join creates a row at the currently
    configured host rather than reusing the dead pin."""
    from kaleem.scheduling.rooms import _ensure_room

    settings.SIGNALING_URL = "wss://ws-staging.kaleem.academy"
    session = session_factory()
    Room.objects.create(
        session=session,
        provider="signaling",
        external_id=f"session-{session.pk}",
        signaling_url="wss://ws-green-staging.kaleem.academy",
        status=Room.Status.ENDED,
        ended_at=timezone.now(),
    )

    room = _ensure_room(session)

    assert room.signaling_url == "wss://ws-staging.kaleem.academy"
```

**Note on `migrator`:** this repo may not have `django-test-migrations` installed. Check first — `grep -rn "django_test_migrations\|migrator" backend/` and look in `backend/requirements/`. **If it is absent, do not add a dependency for this.** Rewrite the first two tests to call the migration's forward function directly instead:

```python
from kaleem.scheduling.migrations import _end_active_rooms_module_name as m  # see Step 3
```

— that is, import the module by its real path and call `end_active_rooms(apps, schema_editor)` with `django.apps.apps` and `None`. State in your report which form you used and why.

- [ ] **Step 2: Run the tests and watch them fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_migration_0009.py -v
```

Expected: FAIL — migration `0009_end_active_rooms` does not exist.

- [ ] **Step 3: Write the migration**

```python
# backend/kaleem/scheduling/migrations/0009_end_active_rooms.py
from django.db import migrations
from django.utils import timezone


def end_active_rooms(apps, schema_editor):
    """One-off. Ends every ACTIVE room, once.

    Rooms carry `signaling_url`, pinned at creation to whichever deploy colour
    created them. `ship.sh` removes the old colour's signaling container on
    every flip -- and Traefik's router lives on that container -- so a row
    written before a deploy names a host that no longer routes. `_ensure_room`
    reuses an ACTIVE row indefinitely, which turned that into a session that
    was permanently unjoinable, with no close code and nothing naming the
    cause. Hit on staging twice on 2026-09-07.

    Ending rather than rewriting the URL: room membership lives in the
    signaling process, which is long gone for any of these rows, so `active`
    is already a false statement about them. The next join mints a fresh row
    at the configured host.

    This is NOT a recurring deploy step. Once signaling is a shared service on
    one hostname (ADR-0037) a stale row is harmless -- its URL stays correct
    and the relay recreates the room on first connect. Only rows written under
    the per-colour scheme need this, and they exist only now.
    """
    Room = apps.get_model("scheduling", "Room")
    Room.objects.filter(status="active").update(status="ended", ended_at=timezone.now())


class Migration(migrations.Migration):
    dependencies = [("scheduling", "0008_calldiagnostic")]

    operations = [
        # No reverse: un-ending a room would resurrect a pin to a host that no
        # longer exists, which is the defect this removes.
        migrations.RunPython(end_active_rooms, migrations.RunPython.noop),
    ]
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
cd backend && pytest kaleem/scheduling/tests/test_migration_0009.py -v
```

Expected: PASS.

- [ ] **Step 5: Run the full suite, the linters and the boundary check**

```bash
cd backend && pytest --cov=kaleem --cov=signaling && ruff check . && mypy . && lint-imports
```

Expected: all pass, coverage at or above 97.7.

- [ ] **Step 6: Commit**

```bash
git add kaleem/scheduling/migrations/0009_end_active_rooms.py kaleem/scheduling/tests/test_migration_0009.py
git commit -m "fix: end ACTIVE rooms pinned to a per-colour signaling host

They name a host that stops routing on the next colour flip, and
_ensure_room reuses an ACTIVE row forever -- so the session was
permanently unjoinable with no error naming the cause."
```

---

### Task 2: One shared `signaling` service in compose

**Files:**
- Modify: `infra/docker-compose.production.yml`

**Interfaces:**
- Consumes: `${WS_DOMAIN}` from `.env.production` (Task 4 documents it).
- Produces: a compose service named `signaling` (container `kaleem-signaling-1`), Traefik router `signaling`, listening on port 9000.

- [ ] **Step 1: Replace the two per-colour services with one shared service**

Delete the `signaling-blue` and `signaling-green` blocks entirely. Add a single service in the **shared** part of the file — beside `traefik`, `postgres`, `redis`, `flower`, `coturn`, and with **no `profiles:` key**, which is what makes it shared rather than colour-scoped:

```yaml
  # Shared, NOT per-colour, and NOT in a profile -- see ADR-0037.
  #
  # Per-colour signaling made a room outlive its host: `Room.signaling_url` is
  # pinned at creation, `ship.sh` removes the old colour's container (and with
  # it Traefik's router) on every flip, and `_ensure_room` reuses an ACTIVE row
  # forever. A session created before a deploy became permanently unjoinable,
  # with no close code and nothing naming the cause.
  #
  # With one host that cannot happen: both Djangos hand out the same URL, so a
  # stale row still names a live host and the relay recreates its room on the
  # first connect. It also makes the C3c straddle unreachable -- two
  # participants cannot be given different hosts when only one exists.
  #
  # The cost is no independent rollback for signaling: roll forward, or
  # `up -d signaling` on a pinned older image. Same terms `coturn` already
  # runs on, and every deploy already drops live calls regardless.
  signaling:
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    # --log-config is NOT optional. Without it uvicorn logs every handshake
    # path INCLUDING its query string, and that query string is the room
    # capability token -- a replayable grant to one child's lesson, sitting in
    # `docker logs` for its full life. See backend/signaling/logconf.py.
    command: >
      uvicorn signaling.app:app --host 0.0.0.0 --port 9000
      --log-config signaling/logconf.json
    restart: unless-stopped
    env_file:
      - .env.production
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:9000/health/live/"]
      interval: 15s
      timeout: 5s
      retries: 3
    labels:
      - "traefik.enable=true"
      # `:?` is load-bearing: an unset WS_DOMAIN would otherwise expand to the
      # empty string, and this router would match `Host()` -- while
      # django's DJANGO_SIGNALING_URL below became the truthy string `wss://`,
      # defeating SignalingProvider's own fail-closed guard.
      - "traefik.http.routers.signaling.rule=Host(`${WS_DOMAIN:?WS_DOMAIN is required}`)"
      - "traefik.http.routers.signaling.entrypoints=websecure"
      - "traefik.http.routers.signaling.tls.certresolver=letsencrypt"
      - "traefik.http.services.signaling.loadbalancer.server.port=9000"
```

- [ ] **Step 2: Point both Djangos at the one host**

In `django-blue`'s environment, replace:

```yaml
      - DJANGO_SIGNALING_URL=wss://${WS_BLUE_DOMAIN:?WS_BLUE_DOMAIN is required}
```

with:

```yaml
      # Both colours get the SAME host now (ADR-0037). That identity is the
      # fix: `Room.signaling_url` can no longer disagree with the live
      # deployment, so a room cannot outlive its signaling host and two
      # participants cannot be handed different ones.
      - DJANGO_SIGNALING_URL=wss://${WS_DOMAIN:?WS_DOMAIN is required}
```

Make the identical change in `django-green`. Keep the surrounding comments about why `:?` matters.

- [ ] **Step 3: Verify compose resolves, and that the guard still bites**

```bash
cd infra
WS_DOMAIN=ws-staging.kaleem.academy docker compose -f docker-compose.production.yml --env-file .env.production.example config >/dev/null && echo "resolves OK"
```

Then prove the `:?` guard fails the deploy rather than producing a broken router:

```bash
cd infra
WS_DOMAIN= docker compose -f docker-compose.production.yml --env-file .env.production.example config 2>&1 | grep -i 'WS_DOMAIN is required' && echo "guard bites"
```

Expected: the first prints `resolves OK`, the second prints `guard bites`. If the second resolves successfully, the `:?` was dropped somewhere — fix it before continuing.

- [ ] **Step 4: Confirm no per-colour signaling reference survives**

```bash
cd infra && grep -n 'signaling-blue\|signaling-green\|WS_BLUE_DOMAIN\|WS_GREEN_DOMAIN' docker-compose.production.yml
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.production.yml
git commit -m "feat: one shared signaling service on WS_DOMAIN (ADR-0037)"
```

---

### Task 3: `ship.sh` stops treating signaling as colour-scoped

**Files:**
- Modify: `infra/scripts/ship.sh`

**Interfaces:**
- Consumes: the `signaling` service and container name `kaleem-signaling-1` from Task 2.

- [ ] **Step 1: Add `signaling` to the shared services line (step 4)**

Change the echo and the `up -d` to include it, and extend the existing comment — that comment already explains that the list is explicit and a service missing from it is simply never started, which is exactly the trap here:

```bash
echo "Ensuring shared services (traefik, postgres, redis, flower, coturn, signaling) are up..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d traefik postgres redis flower coturn signaling
```

Add to the comment block above it:

```bash
# `signaling` joined this list in ADR-0037. It used to be per-colour and was
# stopped and removed on every flip -- which orphaned every room pinned to it
# and made those sessions permanently unjoinable. It holds no deploy-versioned
# client contract beyond the `kaleem.signaling.v1` subprotocol, and its room
# membership is process-local, so recreating it drops live calls exactly as the
# old scheme already did.
```

- [ ] **Step 2: Remove `signaling-${NEW}` and `signaling-${CURRENT}` from every colour list**

Four places: the rollback `stop` and `rm -f` after the main health check (step 6), the rollback `stop` and `rm -f` after the signaling health check (step 6b), and the drain `stop --timeout 30` and `rm -f` in step 8. Each becomes:

```bash
        "django-${NEW}" "celery-worker-${NEW}" "celery-beat-${NEW}"
```

and for step 8:

```bash
        "django-${CURRENT}" "celery-worker-${CURRENT}" "celery-beat-${CURRENT}"
```

**Step 8 is the one that caused the bug.** Removing signaling from it is the operational half of this fix.

- [ ] **Step 3: Retarget the signaling health check (step 6b)**

```bash
echo "Checking signaling..."
SIGNALING_OK=false
for i in $(seq 1 $HEALTH_RETRIES); do
    if docker exec "kaleem-signaling-1" curl -sf http://localhost:9000/health/live/ > /dev/null 2>&1; then
        SIGNALING_OK=true
        break
    fi
    sleep $HEALTH_DELAY
done
```

Its rollback branch still stops the new colour's Django trio — a shared signaling that will not come up is still a reason not to promote the new colour — but it must **not** stop `signaling` itself, which may be serving the current colour perfectly well.

Leave the existing comment about the check being container-local and unable to see a dead Traefik router. That limitation is unchanged and still true.

- [ ] **Step 4: Shellcheck and a dry read**

```bash
cd infra && shellcheck scripts/ship.sh || true
grep -n 'signaling' scripts/ship.sh
```

Expected: every remaining mention is either the shared `up -d` line, the health check on `kaleem-signaling-1`, or a comment. **No `signaling-${NEW}` or `signaling-${CURRENT}` anywhere.** If `shellcheck` is not installed, say so in your report rather than skipping the read.

- [ ] **Step 5: Commit**

```bash
git add scripts/ship.sh
git commit -m "fix: never stop signaling on a colour flip

Step 8 removed the old colour's signaling container, and Traefik's router
lives on that container -- which is what orphaned every room pinned to it."
```

---

### Task 4: The environment variable and its documentation

**Files:**
- Modify: `infra/.env.production.example`
- Modify: `docs/runbook/signaling.md` (meta repo)

- [ ] **Step 1: Replace the two variables with one**

Delete `WS_BLUE_DOMAIN` and `WS_GREEN_DOMAIN` and their paragraph — including the note that the two "must also DIFFER from each other", which no longer applies. Add:

```bash
# WS_DOMAIN — the signaling service's single hostname. ONE host, shared by both
# deploy colours (ADR-0037), not one per colour.
#
# It was per-colour until 2026-09-07. `Room.signaling_url` pins a room to the
# host that created it, `ship.sh` removed the old colour's signaling container
# on every flip, and `_ensure_room` reuses an ACTIVE row forever -- so a
# session created before a deploy became permanently unjoinable, with no close
# code and nothing naming the cause. One host removes the condition entirely.
#
# `docker-compose.production.yml`'s `${WS_DOMAIN:?...}` guard aborts
# `docker compose config`/`up` outright when this is unset -- a hard failure
# before any container starts, rather than a router matching `Host()` and a
# Django handing out the truthy string `wss://`. Not optional.
WS_DOMAIN=ws-staging.kaleem.academy
```

Update the "Video / signaling" header block below it, which currently names `WS_BLUE_DOMAIN / WS_GREEN_DOMAIN` as compose-only and describes them building "each colour's Traefik Host() rule and each Django colour's per-colour DJANGO_SIGNALING_URL". Rewrite for the single variable; `DJANGO_SIGNALING_URL` is still compose-only and still not set in this file.

- [ ] **Step 2: Update the runbook**

In `docs/runbook/signaling.md` (meta repo), rewrite two sections:

- **"Deployment: single replica per colour"** — retitle and rewrite. Signaling is now one shared replica, started with the other shared services and never stopped by a colour flip. The single-replica constraint itself still holds and still matters: room membership is a process-local dict, so two replicas would split a room.
- **"Deploys drop live calls, and can split a room"** — the split-room half is now impossible: one host means two participants cannot be handed different ones. **The dropped-calls half is unchanged and must stay**, including "deploy between lessons". Say plainly which half changed and which did not.

Also update the "Environment variables" section for `WS_DOMAIN`.

- [ ] **Step 3: Check nothing else references the old names**

```bash
cd /home/abdulkhalek/Projects/kaleem
grep -rn 'WS_BLUE_DOMAIN\|WS_GREEN_DOMAIN' --include='*.yml' --include='*.yaml' --include='*.sh' --include='*.py' --include='*.md' . | grep -v node_modules | grep -v 'docs/superpowers/'
```

Expected: no output outside `docs/superpowers/` (specs and plans are historical records and keep their original wording) and `ISSUES.md`/`STATE.md`, which Task 7 updates.

- [ ] **Step 4: Commit** (two repos, two commits)

```bash
cd infra && git add .env.production.example && git commit -m "docs: WS_DOMAIN replaces the per-colour signaling hosts"
cd .. && git add docs/runbook/signaling.md && git commit -m "docs: runbook for shared signaling"
```

---

### Task 5: Prove the provider hands out one host for both colours

The behaviour this whole change rests on deserves a test, even though the real proof is Task 6.

**Files:**
- Modify: `backend/kaleem/scheduling/tests/test_signaling_provider.py`

- [ ] **Step 1: Write the failing test**

```python
def test_the_pin_matches_the_configured_host_for_every_colour(settings, session_factory):
    """Both Djangos are configured with the same SIGNALING_URL now (ADR-0037),
    so a room created by either colour names a host both can serve.

    This is the property the fix rests on: when the pin can never disagree
    with the live deployment, a stale ACTIVE row is harmless -- its URL is
    still correct and the relay recreates the room on first connect.
    """
    settings.SIGNALING_URL = "wss://ws-staging.kaleem.academy"
    provider = SignalingProvider()

    room = provider.create_room(
        RoomRequest(
            session_id=5,
            subject_name="Tafsir",
            starts_at=timezone.now(),
            duration_minutes=30,
        )
    )

    assert room.signaling_url == "wss://ws-staging.kaleem.academy"


def test_a_stale_pin_is_still_honoured_over_settings(settings):
    """The pin still wins over settings -- do NOT "fix" this to re-read
    settings at join time. That is the split-room bug C3c removed: during a
    deploy each Django believes its own colour is live, so two participants
    would re-pin in opposite directions and each land alone in a one-peer
    room. One host makes the pin always agree; it does not make it ignorable.
    """
    settings.SIGNALING_URL = "wss://ws-staging.kaleem.academy"
    provider = SignalingProvider()
    room = ProviderRoom(
        external_id="session-5",
        provider="signaling",
        signaling_url="wss://ws-old.kaleem.academy",
    )

    grant = provider.get_join_url(
        room,
        Participant(user_id=1, is_teacher=False),
        expires_at=timezone.now() + timedelta(minutes=30),
    )

    assert grant.join_url.startswith("wss://ws-old.kaleem.academy/")
```

Match the file's existing fixture and import style rather than the sketch above — read it first.

- [ ] **Step 2: Run and watch the first fail, the second pass**

```bash
cd backend && pytest kaleem/scheduling/tests/test_signaling_provider.py -v
```

The second test documents existing behaviour and should pass immediately; that is intended — it is a guard against a future "simplification", not a change. If the **first** already passes too, no production change is needed here; say so in your report rather than inventing one.

- [ ] **Step 3: Run the full suite, linters and boundary check**

```bash
cd backend && pytest --cov=kaleem --cov=signaling && ruff check . && mypy . && lint-imports
```

- [ ] **Step 4: Verify the ADR-0035 contract by breaking it, both ways**

Add `import kaleem` to a file under `backend/signaling/`, run `lint-imports`, confirm it FAILS, then revert. This repo's convention is that a contract is only known-good once it has been seen to fail.

- [ ] **Step 5: Commit**

```bash
git add kaleem/scheduling/tests/test_signaling_provider.py
git commit -m "test: pin the one-host property the shared signaling fix rests on"
```

---

### Task 6: The live staging check — the actual verification

CI cannot catch this bug. This task is the proof, and the plan is not done without it.

**Files:** none. This is an operational procedure; its output is a written record.

- [ ] **Step 1: Add the DNS record and confirm the certificate**

Point `ws-staging.kaleem.academy` at the VPS, set `WS_DOMAIN` in the VPS's hand-managed `/opt/kaleem/.env.production`, deploy, then:

```bash
curl -sS -o /dev/null -m 12 -w 'http=%{http_code} tls=%{ssl_verify_result}\n' \
  https://ws-staging.kaleem.academy/health/live/
```

Expected: `http=200 tls=0`. A `tls` other than `0` means Let's Encrypt has not issued yet — wait and retry before going further.

- [ ] **Step 2: Confirm the shared container exists and no per-colour one does**

```bash
ssh kaleem 'docker ps -a --filter name=signaling --format "{{.Names}}\t{{.Status}}"'
```

Expected: exactly `kaleem-signaling-1`, up and healthy. No `-blue-1`, no `-green-1`.

- [ ] **Step 3: Create a room, then flip the colour under it**

This is the reproduction of the original bug, run against the fix.

```bash
ssh kaleem 'cat /opt/kaleem/.active-color'
```

Join a session in a browser so a `Room` row is created, and record its pin:

```bash
ssh kaleem 'docker exec kaleem-django-$(cat /opt/kaleem/.active-color)-1 python manage.py shell -c "
from kaleem.scheduling.models import Room
print([(r.session_id, r.status, r.signaling_url) for r in Room.objects.filter(status=Room.Status.ACTIVE)])
"'
```

Then deploy again to flip the colour, and **join that same session**.

- [ ] **Step 4: Record the result**

**Pass:** the session joins, the WebSocket opens, `peer-joined` arrives. **Fail:** the socket never opens — the bug is not fixed; stop and report rather than patching around it.

Also re-run Step 2 and confirm `kaleem-signaling-1` was **not** recreated by the flip (its `Status` uptime should span the deploy). If it was recreated, it is still colour-scoped somewhere.

- [ ] **Step 5: Mutation-check the fix**

Confirm the same scenario fails on the current production code — the `ISSUES.md` entry and this plan's spec both record it failing on 2026-09-07, with the evidence table. Cite that rather than deliberately breaking staging again. Say in your report which of the two you did.

- [ ] **Step 6: Write the result into the journal**

Record what you ran and what you saw in `docs/superpowers/journal/2026-W36.md`, including the container uptime spanning the deploy. A live check whose result is not written down cannot be relied on by the next session.

---

### Task 7: Close out the docs

**Files (meta repo):** `ISSUES.md`, `STATE.md`, `docs/superpowers/specs/2026-09-07-shared-signaling-service-design.md`, `docs/superpowers/journal/2026-W36.md`, plus the `backend` and `infra` submodule pointers.

- [ ] **Step 1: Remove the fixed `ISSUES.md` entry**

Delete *"An ACTIVE room outlives the colour it was pinned to (C3a/C3c)"*. `ISSUES.md` is a backlog of open problems; a fixed one is deleted, not struck through.

**Leave these, all still open:** the deploy-drops-live-calls entry (the drain), `Room.provider` being stored but never read, and the join endpoint's missing throttle. Edit the drain entry only where it references per-colour signaling hosts, which no longer exist.

- [ ] **Step 2: Set the spec to shipped**

`status: shipped`, `closed:` today's date.

- [ ] **Step 3: Update `STATE.md`**

Say plainly what is verified and what is not: the fix is verified by a live staging colour flip (Task 6) and **not** by CI, which cannot reach Traefik routing or blue-green at all. Keep the file to its stated ~60-line target — it is the current position, not a history.

- [ ] **Step 4: Bump both submodule pointers and open the meta PR**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add backend infra docs ISSUES.md STATE.md
git commit -m "docs: close the shared signaling service change, bump backend and infra"
```

Push the `backend` and `infra` branches and merge their PRs **before** merging the meta PR — meta CI builds from the pinned submodule SHAs, so an unpushed pointer fails the build.

⚠ **A merge to meta `master` is a deploy** (ADR-0028), and this one changes the signaling topology. Merge between lessons.

---

## Self-Review

**Spec coverage.** Every section maps to a task: the compose collapse → Task 2; `ship.sh` → Task 3; `${WS_DOMAIN:?}` and the env var → Tasks 2 and 4; `Room.signaling_url` stays → enforced by Task 5's second test and by the Global Constraints; existing rows → Task 1; sequencing → the task order plus Task 6's steps; what it gives up and the runbook → Task 4; the test plan → Tasks 1, 5; "what this spec cannot prove" → Task 6, which exists because CI cannot.

**One gap found and closed while reviewing:** the spec's sequencing says "stand up the shared signaling, confirm it serves, *then* repoint both Djangos, *then* migrate, *then* delete the per-colour services" — but compose cannot hold both schemes at once without keeping `WS_BLUE_DOMAIN`/`WS_GREEN_DOMAIN` alive through the transition. Task 2 deletes them in one commit, so the safe ordering is enforced at **deploy** time, not at commit time: Task 6 Step 1 requires DNS and the certificate to exist *before* the deploy that switches. The migration (Task 1) is ordered first and is independently safe, since ending stale rooms is correct under either scheme. Task 6 Step 1's certificate check is what stops a deploy landing before Let's Encrypt has issued.

**Placeholder scan.** No TBDs. The one conditional is Task 1 Step 1's `migrator` fixture, which names the exact check to run and the exact fallback, and requires the implementer to report which was used.

**Type consistency.** `Room.Status.ACTIVE`/`ENDED` are the literals `"active"`/`"ended"`, used consistently — the migration uses the string form because historical models in `apps.get_model` have no `Status` enum, which is correct and deliberate. `signaling_url`, `external_id`, `ended_at` match the model. The compose service name `signaling` and container name `kaleem-signaling-1` agree between Tasks 2, 3 and 6. `WS_DOMAIN` is spelled identically in Tasks 2, 4 and 6.
