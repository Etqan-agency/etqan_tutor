# Phase C3c — STUN/TURN Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a self-hosted TURN relay with per-user ephemeral credentials, deliver them to the client on the join grant, and move the signaling capability token out of the URL query string — so that C3d has everything it needs to open a call that actually connects.

**Architecture:** `coturn` runs as a shared (non-blue/green) host-networked container on the staging VPS, authenticating with the TURN REST `use-auth-secret` scheme so it holds no user state. Django mints `username = "<expiry>:<user-id>"` / `password = base64(HMAC-SHA1(secret, username))` in a pure function and hands the resulting ICE servers back on the existing `POST /api/v1/scheduling/sessions/<id>/join/` response, which is already authenticated, participant-guarded and window-guarded. Alongside, the capability token moves from `?t=` into `Sec-WebSocket-Protocol`, the grant's expiry becomes the room's own window close, and a room records which deploy colour's signaling host it belongs to.

**Tech Stack:** Django 5 / DRF, Starlette (signaling, Django-free per ADR-0035), coturn 4.6, Docker Compose + Traefik, pytest, Vitest/zod (dashboard).

**Spec:** `docs/superpowers/specs/2026-09-06-phase-c3c-turn-design.md`

## Global Constraints

- **Three repos, three branches, three PRs.** `backend` (`feat/phase-c3c-turn`), `infra` (`feat/phase-c3c-turn`), `dashboard` (`feat/phase-c3c-ice-schema`), then a meta PR carrying docs + submodule pointer bumps. Trunk is `main` in submodules, `master` in meta (ADR-0028). Never commit to a trunk. Never `--no-verify`; if pre-commit fails on the pip proxy, use `PIP_CONFIG_FILE=/dev/null git commit …`.
- **Coverage floors are ratchets (ADR-0026).** Backend floor is `97.7` in `backend/pyproject.toml`. Measure with `pytest --cov=kaleem --cov=signaling` — **never a bare `pytest --cov`**, which omits unimported files and reads ~0.55 high. Dashboard floors are `93.5 / 90 / 86.5 / 93.5` in `vitest.config.ts`. Raise a floor if the run clears it; lowering one requires an ADR. `precision = 1` in `pyproject.toml` is load-bearing — do not remove it.
- **No new e2e flows.** CI has no coturn, no media, and C3c has no user-facing behaviour. e2e stays at 33.
- **No business logic on models; services in `services.py` / dedicated service modules; typed exceptions, never bare `Exception` stringified; no `print()`.** See CLAUDE.md "don't do this".
- **Module boundaries:** `signaling` must not import `kaleem.*`. `kaleem` importing `signaling.tokens` is the one allowed direction and is already contracted in `.importlinter`. Run `lint-imports` before every commit that moves an import.
- **Exact new setting names:** `DJANGO_TURN_SECRET` → `settings.TURN_SECRET`; `DJANGO_TURN_URLS` → `settings.TURN_URLS`.
- **Exact subprotocol constant:** `kaleem.signaling.v1`.
- **Exact per-colour env names:** `WS_BLUE_DOMAIN`, `WS_GREEN_DOMAIN`. `WS_DOMAIN` is retired.
- **Never commit a real secret.** `.env.production.example` is a template; `gitleaks` blocks merges.

---

### Task 1: TURN credential minting

A pure function, no Django, no ORM. This is the whole cryptographic surface of the phase.

**Files:**
- Create: `backend/kaleem/scheduling/providers/turn.py`
- Create: `backend/kaleem/scheduling/tests/test_turn.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `IceServer` — frozen dataclass, fields `urls: tuple[str, ...]`, `username: str = ""`, `credential: str = ""`.
  - `turn_credential(*, secret: str, user_id: int, expires_at: int) -> tuple[str, str]` returning `(username, password)`.
  - `ice_servers(*, urls: str, secret: str, user_id: int, expires_at: int) -> tuple[IceServer, ...]` where `urls` is the raw comma-separated setting value.

- [ ] **Step 1: Write the failing tests**

Create `backend/kaleem/scheduling/tests/test_turn.py`:

```python
"""The TURN REST credential scheme, and the ICE payload built from it.

Pure functions with no Django in them: everything here is a string in and a
string out, which is what lets the crypto be tested without a database.
"""

import base64
import hashlib
import hmac

from kaleem.scheduling.providers.turn import IceServer
from kaleem.scheduling.providers.turn import ice_servers
from kaleem.scheduling.providers.turn import turn_credential

SECRET = "test-turn-secret-not-a-real-one"
URLS = (
    "stun:turn.example.test:3478,"
    "turn:turn.example.test:3478?transport=udp,"
    "turn:turn.example.test:3478?transport=tcp"
)


def test_the_username_is_expiry_colon_user_id():
    username, _ = turn_credential(secret=SECRET, user_id=7, expires_at=1_900_000_000)
    assert username == "1900000000:7"


def test_the_password_is_the_hmac_sha1_of_the_username():
    """Recomputed independently, not asserted against a golden string: a
    golden string would pass just as happily if the implementation and the
    test both drifted to the wrong input."""
    username, password = turn_credential(
        secret=SECRET, user_id=7, expires_at=1_900_000_000
    )
    expected = base64.b64encode(
        hmac.new(SECRET.encode(), username.encode(), hashlib.sha1).digest()
    ).decode()
    assert password == expected


def test_a_different_secret_produces_a_different_password():
    _, mine = turn_credential(secret=SECRET, user_id=7, expires_at=1_900_000_000)
    _, theirs = turn_credential(secret="other", user_id=7, expires_at=1_900_000_000)
    assert mine != theirs


def test_two_users_get_different_credentials():
    _, one = turn_credential(secret=SECRET, user_id=7, expires_at=1_900_000_000)
    _, two = turn_credential(secret=SECRET, user_id=8, expires_at=1_900_000_000)
    assert one != two


def test_stun_urls_are_grouped_without_credentials():
    """A STUN server takes no credential, and sending one is not merely
    redundant -- it hands the credential to a server that never needed it."""
    servers = ice_servers(
        urls=URLS, secret=SECRET, user_id=7, expires_at=1_900_000_000
    )
    stun = next(s for s in servers if s.urls[0].startswith("stun:"))
    assert stun.username == ""
    assert stun.credential == ""


def test_turn_urls_are_grouped_with_one_credential():
    servers = ice_servers(
        urls=URLS, secret=SECRET, user_id=7, expires_at=1_900_000_000
    )
    turn = next(s for s in servers if s.urls[0].startswith("turn:"))
    assert turn.urls == (
        "turn:turn.example.test:3478?transport=udp",
        "turn:turn.example.test:3478?transport=tcp",
    )
    assert turn.username == "1900000000:7"
    assert turn.credential == turn_credential(
        secret=SECRET, user_id=7, expires_at=1_900_000_000
    )[1]


def test_whitespace_and_empty_entries_are_tolerated():
    """The setting is hand-edited in a .env file on a VPS; a trailing comma
    must not produce an ICE server with an empty URL that every browser then
    fails to parse."""
    servers = ice_servers(
        urls=" stun:a.test:3478 , , turn:b.test:3478 ,",
        secret=SECRET,
        user_id=7,
        expires_at=1_900_000_000,
    )
    assert [s.urls for s in servers] == [("stun:a.test:3478",), ("turn:b.test:3478",)]


def test_an_empty_url_list_yields_no_servers():
    assert ice_servers(urls="", secret=SECRET, user_id=7, expires_at=1) == ()


def test_a_group_with_no_members_is_omitted_entirely():
    servers = ice_servers(
        urls="stun:a.test:3478", secret=SECRET, user_id=7, expires_at=1
    )
    assert servers == (IceServer(urls=("stun:a.test:3478",)),)
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_turn.py -v
```
Expected: collection error — `ModuleNotFoundError: No module named 'kaleem.scheduling.providers.turn'`.

- [ ] **Step 3: Write the implementation**

Create `backend/kaleem/scheduling/providers/turn.py`:

```python
"""ICE servers for a lesson: STUN, and a TURN relay with an ephemeral credential.

Roughly one connection in six cannot go peer-to-peer -- symmetric NAT,
carrier-grade NAT, corporate egress filtering -- and fails outright with no
relay to fall back on. These are the credentials that let it fall back.

Pure functions on purpose: no settings read, no ORM, no clock. The caller
supplies the secret, the URL list and the expiry, which is what makes the
crypto testable without a database and keeps one expiry in the system rather
than a second one invented here.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
from dataclasses import dataclass
from dataclasses import field


@dataclass(frozen=True)
class IceServer:
    """One entry of an `RTCConfiguration.iceServers` array.

    `username`/`credential` are empty for STUN: a STUN server takes no
    credential, and attaching one hands it to a server that never needed it.
    """

    urls: tuple[str, ...]
    username: str = ""
    credential: str = ""


def turn_credential(*, secret: str, user_id: int, expires_at: int) -> tuple[str, str]:
    """coturn's `use-auth-secret` (TURN REST) scheme.

    HMAC-SHA1 is MANDATED BY THE SCHEME, not chosen -- coturn computes exactly
    this and nothing else, and everything else in this repository signs with
    SHA-256. It is an HMAC, so SHA-1's collision weakness does not apply: an
    attacker needs the secret, not a collision.

    coturn holds only `static-auth-secret` and has no account table, so there
    is nothing to revoke. The expiry embedded in the username IS the whole
    revocation story -- which is why the caller ties it to the room's own
    lifetime rather than inventing a duration here.
    """
    username = f"{expires_at}:{user_id}"
    digest = hmac.new(
        secret.encode(),
        username.encode(),
        hashlib.sha1,  # noqa: S324 -- mandated by coturn's REST scheme; see docstring
    ).digest()
    return username, base64.b64encode(digest).decode()


def ice_servers(
    *, urls: str, secret: str, user_id: int, expires_at: int
) -> tuple[IceServer, ...]:
    """Build the ICE server list from the raw comma-separated setting.

    Tolerant of whitespace and empty entries because the setting is hand-edited
    in a `.env` file on a VPS: a trailing comma must not become an ICE server
    with an empty URL that every browser then fails to parse.
    """
    parsed = tuple(part.strip() for part in urls.split(",") if part.strip())
    stun = tuple(url for url in parsed if url.startswith("stun:"))
    turn = tuple(url for url in parsed if not url.startswith("stun:"))

    servers: list[IceServer] = []
    if stun:
        servers.append(IceServer(urls=stun))
    if turn:
        username, credential = turn_credential(
            secret=secret, user_id=user_id, expires_at=expires_at
        )
        servers.append(IceServer(urls=turn, username=username, credential=credential))
    return tuple(servers)
```

Note: the `field` import above is unused — delete it before committing; ruff will flag it.

- [ ] **Step 4: Run the tests and the linters**

```bash
cd backend && pytest kaleem/scheduling/tests/test_turn.py -v && ruff check kaleem/scheduling/providers/turn.py && mypy kaleem/scheduling/providers/turn.py
```
Expected: 9 passed, ruff clean, mypy clean.

- [ ] **Step 5: Commit**

```bash
cd backend && git add kaleem/scheduling/providers/turn.py kaleem/scheduling/tests/test_turn.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): mint ephemeral TURN credentials (C3c)"
```

---

### Task 2: The grant's expiry becomes the room's window close

Delete `GRANT_TTL`. Do this before wiring ICE in, so the TURN credential inherits the corrected expiry rather than being written twice.

**Files:**
- Modify: `backend/kaleem/scheduling/rooms.py` (the `GRANT_TTL` constant, `_authorize_and_ensure_room`, `join_session`)
- Test: `backend/kaleem/scheduling/tests/test_rooms_service.py`

**Interfaces:**
- Consumes: `join_window(session) -> tuple[dt.datetime, dt.datetime]` (already exists).
- Produces: `_authorize_and_ensure_room(actor, session_id, now) -> tuple[ProviderRoom, Participant, dt.datetime]` — the third element is the window close. `GRANT_TTL` no longer exists; any import of it is now an error.

- [ ] **Step 1: Write the failing tests**

Append to `backend/kaleem/scheduling/tests/test_rooms_service.py`. Read the top of that file first and reuse its existing fixtures for building a joinable session (do not invent new ones):

```python
def test_the_grant_expires_when_the_room_closes(joinable_session, student):
    """The flat 30-minute TTL was wrong in both directions at once: minted at
    the window's open it died 40 minutes before a 60-minute lesson ended, and
    minted at the window's close it outlived the window by 30."""
    _, closes = rooms.join_window(joinable_session)
    grant = rooms.join_session(student, joinable_session.id)
    assert grant.expires_at == closes


def test_a_longer_lesson_gets_a_longer_grant(joinable_session, student):
    joinable_session.duration_minutes = 120
    joinable_session.save(update_fields=["duration_minutes"])
    _, closes = rooms.join_window(joinable_session)
    grant = rooms.join_session(student, joinable_session.id)
    assert grant.expires_at == closes


def test_the_grant_does_not_outlive_the_window_when_minted_late(
    joinable_session, student
):
    _, closes = rooms.join_window(joinable_session)
    grant = rooms.join_session(
        student, joinable_session.id, now=closes - dt.timedelta(seconds=1)
    )
    assert grant.expires_at == closes


def test_grant_ttl_is_gone():
    """A constant reconciled against another constant is two places for the
    truth to live. The window is computed in one place; the grant derives."""
    assert not hasattr(rooms, "GRANT_TTL")
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_rooms_service.py -k "grant" -v
```
Expected: FAIL — `expires_at` is `now + 30 minutes`, and `GRANT_TTL` still exists.

- [ ] **Step 3: Implement**

In `backend/kaleem/scheduling/rooms.py`, delete the `GRANT_TTL` constant and its comment block, then:

```python
        opens, closes = join_window(session)
        if now < opens:
            raise ConflictError("This session's room is not open yet.")
        if now > closes:
            raise ConflictError("This session's room has closed.")

        return _ensure_room(session), participant, closes
```

and:

```python
def join_session(actor, session_id: int, *, now: dt.datetime | None = None):
    """Authorize `actor` for this session's room and mint them a join URL.

    The grant expires exactly when the room stops being enterable. There is no
    separate TTL: a constant that has to be reconciled against the join window
    is a second place for the truth to live, and the old flat 30 minutes was
    wrong in both directions at once. The TURN credentials on the grant derive
    from the same instant, so nothing in the system can disagree about when
    this person's access ends.
    """
    now = now or timezone.now()
    room, participant, closes = _authorize_and_ensure_room(actor, session_id, now)
    return get_provider().get_join_url(room, participant, expires_at=closes)
```

Update the module docstring line referencing `GRANT_TTL` if one exists, and grep for other readers:

```bash
cd backend && grep -rn "GRANT_TTL" . --include='*.py'
```
Every hit must be removed or updated.

- [ ] **Step 4: Run the full scheduling suite**

```bash
cd backend && pytest kaleem/scheduling -q
```
Expected: all pass. Some pre-existing tests assert a 30-minute expiry — update them to assert the window close, and update their comments to say why.

- [ ] **Step 5: Commit**

```bash
cd backend && git add -A kaleem/scheduling
PIP_CONFIG_FILE=/dev/null git commit -m "fix(scheduling): a join grant expires when its room closes, not 30 minutes in (C3c)"
```

---

### Task 3: ICE servers ride on the join grant

**Files:**
- Modify: `backend/kaleem/scheduling/providers/__init__.py` (`JoinGrant`)
- Modify: `backend/kaleem/scheduling/providers/signaling_provider.py`
- Modify: `backend/kaleem/scheduling/providers/fake_provider.py`
- Modify: `backend/config/settings/base.py` (after the `SIGNALING_URL` block)
- Modify: `backend/kaleem/scheduling/api/booking_serializers.py`
- Test: `backend/kaleem/scheduling/tests/test_signaling_provider.py`, `test_video_providers.py`, `test_rooms_api.py`

**Interfaces:**
- Consumes: `IceServer`, `ice_servers(...)` from Task 1; `expires_at` = window close from Task 2.
- Produces: `JoinGrant(join_url: str, expires_at: dt.datetime, ice_servers: tuple[IceServer, ...] = ())`. `settings.TURN_SECRET`, `settings.TURN_URLS`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/kaleem/scheduling/tests/test_signaling_provider.py`:

```python
from kaleem.scheduling.providers.turn import turn_credential

TURN_SECRET = "test-turn-secret"
TURN_URLS = "stun:turn.example.test:3478,turn:turn.example.test:3478?transport=udp"

SIGNALING = {
    "SIGNALING_SECRET": SECRET,
    "SIGNALING_URL": "wss://ws.example.test",
    "TURN_SECRET": TURN_SECRET,
    "TURN_URLS": TURN_URLS,
}


@override_settings(**SIGNALING)
def test_the_grant_carries_ice_servers(room_request):
    provider = SignalingProvider()
    room = provider.create_room(room_request)
    expires_at = timezone.now() + dt.timedelta(minutes=30)

    grant = provider.get_join_url(
        room,
        Participant(user_id=7, display_name="Amina", is_teacher=False),
        expires_at=expires_at,
    )

    turn = next(s for s in grant.ice_servers if s.urls[0].startswith("turn:"))
    assert (turn.username, turn.credential) == turn_credential(
        secret=TURN_SECRET, user_id=7, expires_at=int(expires_at.timestamp())
    )


@override_settings(**SIGNALING)
def test_the_turn_credential_expires_with_the_grant(room_request):
    """One expiry in the system. If these two can drift apart, a relay
    credential outlives the room it was minted for -- or dies inside it."""
    provider = SignalingProvider()
    room = provider.create_room(room_request)
    expires_at = timezone.now() + dt.timedelta(minutes=30)
    grant = provider.get_join_url(
        room,
        Participant(user_id=7, display_name="Amina", is_teacher=False),
        expires_at=expires_at,
    )
    turn = next(s for s in grant.ice_servers if s.urls[0].startswith("turn:"))
    assert turn.username.split(":")[0] == str(int(expires_at.timestamp()))


@override_settings(**{**SIGNALING, "TURN_SECRET": ""})
def test_a_missing_turn_secret_fails_closed():
    """TURN is not optional -- one connection in six needs it. 'Not optional'
    has to be the process refusing to start, not a sentence in a runbook."""
    with pytest.raises(ImproperlyConfigured, match="DJANGO_TURN_SECRET"):
        SignalingProvider()


@override_settings(**{**SIGNALING, "TURN_URLS": ""})
def test_a_missing_turn_url_list_fails_closed():
    with pytest.raises(ImproperlyConfigured, match="DJANGO_TURN_URLS"):
        SignalingProvider()
```

Every pre-existing `@override_settings(SIGNALING_SECRET=SECRET, SIGNALING_URL=...)` in this file must become `@override_settings(**SIGNALING)`, or the constructor's new fail-closed check turns them red.

Append to `backend/kaleem/scheduling/tests/test_video_providers.py`:

```python
def test_the_fake_provider_offers_no_ice_servers():
    """The fake has no relay and must not pretend it does: an empty list is
    the honest answer, and a caller that needs a relay fails visibly."""
    provider = FakeVideoProvider()
    room = provider.create_room(
        RoomRequest(
            session_id=1,
            subject_name="Quran",
            starts_at=timezone.now(),
            duration_minutes=60,
        )
    )
    grant = provider.get_join_url(
        room,
        Participant(user_id=1, display_name="X", is_teacher=False),
        expires_at=timezone.now(),
    )
    assert grant.ice_servers == ()
```

Append to `backend/kaleem/scheduling/tests/test_rooms_api.py` (reuse that file's existing joinable-session fixtures and authenticated client):

```python
def test_the_join_response_carries_ice_servers(client_as_student, joinable_session):
    with override_settings(
        VIDEO_PROVIDER="kaleem.scheduling.providers.signaling_provider.SignalingProvider",
        SIGNALING_SECRET="s",
        SIGNALING_URL="wss://ws.example.test",
        TURN_SECRET="t",
        TURN_URLS="turn:turn.example.test:3478?transport=udp",
    ):
        response = client_as_student.post(
            f"/api/v1/scheduling/sessions/{joinable_session.id}/join/"
        )
    assert response.status_code == 200
    [server] = response.json()["ice_servers"]
    assert server["urls"] == ["turn:turn.example.test:3478?transport=udp"]
    assert server["username"]
    assert server["credential"]
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_signaling_provider.py kaleem/scheduling/tests/test_video_providers.py kaleem/scheduling/tests/test_rooms_api.py -v
```
Expected: FAIL — `JoinGrant` has no `ice_servers`, settings do not exist.

- [ ] **Step 3: Implement**

In `backend/config/settings/base.py`, directly after the `SIGNALING_URL` block:

```python
# TURN -- the relay for the ~1 connection in 6 that cannot go peer-to-peer
# (C3c). The secret is shared with coturn's `static-auth-secret`; the URL list
# is comma-separated ICE URLs. Empty in dev, where FakeVideoProvider is the
# default and nothing dials out; SignalingProvider fails closed without them.
TURN_SECRET = env("DJANGO_TURN_SECRET", default="")
TURN_URLS = env("DJANGO_TURN_URLS", default="")
```

In `backend/kaleem/scheduling/providers/__init__.py`:

```python
from kaleem.scheduling.providers.turn import IceServer


@dataclass(frozen=True)
class JoinGrant:
    """A capability with an expiry. Never persisted, never logged."""

    join_url: str
    expires_at: dt.datetime
    # Empty for a provider with no relay of its own. Defaulted rather than
    # required so `FakeVideoProvider` states "no relay" by saying nothing.
    ice_servers: tuple[IceServer, ...] = ()
```

Move `import datetime as dt` out of the `TYPE_CHECKING` block in that file if `dt` is only imported there — a dataclass field annotation is fine under `from __future__ import annotations`, so check before changing anything.

In `signaling_provider.py`, extend the constructor guard and build the servers:

```python
        if not settings.SIGNALING_SECRET or not settings.SIGNALING_URL:
            raise ImproperlyConfigured(
                "SignalingProvider requires both DJANGO_SIGNALING_SECRET and "
                "DJANGO_SIGNALING_URL to be set."
            )
        # TURN is not optional: roughly one connection in six cannot go
        # peer-to-peer and fails outright with no relay. Fail closed here, not
        # at the point a student cannot hear their teacher.
        if not settings.TURN_SECRET or not settings.TURN_URLS:
            raise ImproperlyConfigured(
                "SignalingProvider requires both DJANGO_TURN_SECRET and "
                "DJANGO_TURN_URLS to be set."
            )
```

and inside `get_join_url`, before the return:

```python
        servers = ice_servers(
            urls=settings.TURN_URLS,
            secret=settings.TURN_SECRET,
            user_id=participant.user_id,
            expires_at=int(expires_at.timestamp()),
        )
```
passing `ice_servers=servers` to `JoinGrant`. Import as `from kaleem.scheduling.providers.turn import ice_servers`.

In `booking_serializers.py`:

```python
class IceServerSerializer(serializers.Serializer):
    """One `RTCConfiguration.iceServers` entry. `username`/`credential` are
    blank for STUN, which takes no credential."""

    urls = serializers.ListField(child=serializers.CharField())
    username = serializers.CharField(allow_blank=True)
    credential = serializers.CharField(allow_blank=True)


class JoinGrantSerializer(serializers.Serializer):
    """Minted per request, for one participant. Never stored, never logged."""

    join_url = serializers.CharField()
    expires_at = serializers.DateTimeField()
    ice_servers = IceServerSerializer(many=True)
```

- [ ] **Step 4: Run the suite**

```bash
cd backend && pytest kaleem/scheduling -q && ruff check kaleem && mypy kaleem && lint-imports
```
Expected: all pass, all clean, `lint-imports` reports the existing kept contracts with 0 broken.

- [ ] **Step 5: Commit**

```bash
cd backend && git add -A kaleem config
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): deliver ICE servers on the join grant (C3c)"
```

---

### Task 4: The capability token moves to `Sec-WebSocket-Protocol`

The signaling side. Land this before Task 5 so the service accepts the new transport before anything mints it.

**Files:**
- Modify: `backend/signaling/app.py`
- Test: `backend/signaling/tests/test_app.py`

**Interfaces:**
- Consumes: `signaling.tokens.verify` (unchanged).
- Produces: `signaling.app.SUBPROTOCOL = "kaleem.signaling.v1"`. The endpoint no longer reads `websocket.query_params`.

- [ ] **Step 1: Write the failing tests**

In `backend/signaling/tests/test_app.py`, replace the `url()` helper and add tests:

```python
from signaling.app import SUBPROTOCOL


def url(room="session-1"):
    return f"/ws/rooms/{room}"


def offer(room="session-1", token=None):
    """What a browser sends: the protocol name first, then the credential."""
    return [SUBPROTOCOL, token if token is not None else token_for(room)]


def test_the_selected_subprotocol_is_the_protocol_name_never_the_token():
    """Echoing the token would move the credential from the request headers
    into the RESPONSE headers -- the same leak, one hop later."""
    token = token_for()
    with TestClient(app).websocket_connect(
        url(), subprotocols=offer(token=token)
    ) as ws:
        assert ws.accepted_subprotocol == SUBPROTOCOL
        assert ws.accepted_subprotocol != token


def test_a_connection_with_no_subprotocol_is_refused():
    with TestClient(app).websocket_connect(url()) as ws:
        with pytest.raises(WebSocketDisconnect) as excinfo:
            ws.receive_text()
    assert excinfo.value.code == CLOSE_UNAUTHORIZED


def test_a_connection_offering_only_the_protocol_name_is_refused():
    with TestClient(app).websocket_connect(url(), subprotocols=[SUBPROTOCOL]) as ws:
        with pytest.raises(WebSocketDisconnect) as excinfo:
            ws.receive_text()
    assert excinfo.value.code == CLOSE_UNAUTHORIZED


def test_a_refused_connection_still_gets_the_selected_subprotocol():
    """The assertion that matters, and the one a TestClient-only suite is
    structurally able to miss. RFC 6455: a client that offered subprotocols
    and receives an accept selecting NONE must fail the connection -- the
    browser then surfaces a generic handshake error and the whole
    4400/4401/4409/4410 vocabulary C3b built becomes unreadable."""
    with TestClient(app).websocket_connect(
        url(), subprotocols=offer(token="not-a-token")
    ) as ws:
        assert ws.accepted_subprotocol == SUBPROTOCOL
        with pytest.raises(WebSocketDisconnect) as excinfo:
            ws.receive_text()
    assert excinfo.value.code == CLOSE_UNAUTHORIZED


def test_a_token_in_the_query_string_is_no_longer_accepted():
    """A clean break, not a fallback: C3d does not exist yet, so there is no
    client to keep compatible and the alternative is a dual path forever."""
    with TestClient(app).websocket_connect(f"{url()}?t={token_for()}") as ws:
        with pytest.raises(WebSocketDisconnect) as excinfo:
            ws.receive_text()
    assert excinfo.value.code == CLOSE_UNAUTHORIZED
```

Then update **every** existing `websocket_connect(url(...))` call in the file to pass `subprotocols=offer(...)`. Read the whole file and convert each one; the expired-token, wrong-room, room-full, replaced-socket, relay and bad-frame tests all connect and all need it.

- [ ] **Step 2: Run to verify they fail**

```bash
cd backend && pytest signaling/tests/test_app.py -v
```
Expected: many FAIL — the endpoint still reads `?t=` and accepts with no subprotocol.

- [ ] **Step 3: Implement**

In `backend/signaling/app.py`, add the constant beside the close codes:

```python
# The WebSocket subprotocol. A browser cannot set headers on a WS handshake,
# but it CAN offer subprotocols -- so the credential rides here rather than in
# a query string, which would leak to `Referer`, browser history, and every
# proxy or CDN hop we ever add. The values are RFC 7230 tokens and our token
# is base64url plus a dot separator, so every character is a valid `tchar`
# and no escaping layer is needed.
SUBPROTOCOL = "kaleem.signaling.v1"
```

Add the reader:

```python
def _offered_token(websocket: WebSocket) -> str:
    """The credential the client offered alongside the protocol name.

    Returns "" for anything that is not exactly `[SUBPROTOCOL, token]`, which
    the caller refuses like any other bad credential -- there is no partial
    acceptance here and no new close code.
    """
    raw = websocket.headers.get("sec-websocket-protocol", "")
    offered = [part.strip() for part in raw.split(",") if part.strip()]
    if len(offered) != 2 or offered[0] != SUBPROTOCOL:
        return ""
    return offered[1]
```

In `room_endpoint`, replace the query-param read and every `await websocket.accept()` — **including the two on the refusal paths**:

```python
async def room_endpoint(websocket: WebSocket) -> None:
    room_id = websocket.path_params["room_id"]
    raw = _offered_token(websocket)

    try:
        token = verify(raw, _secret())
    except TokenError as exc:
        logger.warning("refused join to room %s: %s", room_id, exc)
        # Accept-then-close, so the browser sees the application close code
        # instead of a bare handshake failure it cannot distinguish -- and the
        # accept MUST select the subprotocol. RFC 6455 requires a client that
        # offered subprotocols to fail the connection if the server selects
        # none, which would destroy the close-code vocabulary above.
        await websocket.accept(subprotocol=SUBPROTOCOL)
        await websocket.close(code=CLOSE_UNAUTHORIZED)
        return
```

and likewise for the wrong-room branch and the main `await websocket.accept()`.

- [ ] **Step 4: Run the signaling suite**

```bash
cd backend && pytest signaling -q && ruff check signaling && lint-imports
```
Expected: all pass. `lint-imports` still 0 broken — nothing here imports Django.

- [ ] **Step 5: Commit**

```bash
cd backend && git add -A signaling
PIP_CONFIG_FILE=/dev/null git commit -m "feat(signaling): carry the capability token in Sec-WebSocket-Protocol (C3c)"
```

---

### Task 5: The provider stops embedding the token in the URL

**Files:**
- Modify: `backend/kaleem/scheduling/providers/__init__.py` (`JoinGrant.token`)
- Modify: `backend/kaleem/scheduling/providers/signaling_provider.py`
- Modify: `backend/kaleem/scheduling/providers/fake_provider.py`
- Modify: `backend/kaleem/scheduling/api/booking_serializers.py`
- Test: `backend/kaleem/scheduling/tests/test_signaling_provider.py`, `test_video_providers.py`, `test_rooms_api.py`

**Interfaces:**
- Consumes: `SUBPROTOCOL` semantics from Task 4 (the client passes `token` as the second subprotocol).
- Produces: `JoinGrant(join_url, expires_at, ice_servers=(), token="")`; response body gains `token`.

- [ ] **Step 1: Write the failing tests**

Replace `test_the_join_url_carries_a_token_signaling_would_accept` in `test_signaling_provider.py` with:

```python
@override_settings(**SIGNALING)
def test_the_grant_carries_a_token_signaling_would_accept(room_request):
    provider = SignalingProvider()
    room = provider.create_room(room_request)
    expires_at = timezone.now() + dt.timedelta(minutes=30)

    grant = provider.get_join_url(
        room,
        Participant(user_id=7, display_name="Amina", is_teacher=False),
        expires_at=expires_at,
    )

    assert grant.join_url == "wss://ws.example.test/ws/rooms/session-42"
    token = verify(grant.token, SECRET, now=0)
    assert token.room_id == "session-42"
    assert token.user_id == 7
    assert token.is_teacher is False
    assert token.expires_at == int(expires_at.timestamp())


@override_settings(**SIGNALING)
def test_the_join_url_carries_no_credential(room_request):
    """A query string leaks to `Referer`, to browser history, and to every
    proxy or CDN hop we ever add. Each new hop is a new leak to find."""
    provider = SignalingProvider()
    room = provider.create_room(room_request)
    grant = provider.get_join_url(
        room,
        Participant(user_id=7, display_name="Amina", is_teacher=False),
        expires_at=timezone.now() + dt.timedelta(minutes=30),
    )
    assert "?" not in grant.join_url
    assert grant.token not in grant.join_url
```

Fix `test_two_participants_get_different_tokens` to compare `grant.token` rather than `grant.join_url` — the URLs are now identical for both participants, which is the point, and the old assertion would fail for the right reason but test the wrong thing.

In `test_rooms_api.py`:

```python
def test_the_join_response_carries_the_token_separately(
    client_as_student, joinable_session
):
    response = client_as_student.post(
        f"/api/v1/scheduling/sessions/{joinable_session.id}/join/"
    )
    body = response.json()
    assert "?t=" not in body["join_url"]
    assert body["token"]
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_signaling_provider.py kaleem/scheduling/tests/test_rooms_api.py -v
```
Expected: FAIL — `JoinGrant` has no `token`, `join_url` still contains `?t=`.

- [ ] **Step 3: Implement**

`JoinGrant` gains:

```python
    # Separate from `join_url` since C3c: the client passes this as the second
    # WebSocket subprotocol rather than in a query string. Empty for a
    # provider whose URL is not a signaling endpoint.
    token: str = ""
```

`SignalingProvider.get_join_url` returns:

```python
        base = settings.SIGNALING_URL.rstrip("/")
        return JoinGrant(
            join_url=f"{base}/ws/rooms/{room.external_id}",
            token=token,
            expires_at=expires_at,
            ice_servers=servers,
        )
```
and its `?t=` comment block is replaced with one explaining the subprotocol.

`FakeVideoProvider` keeps its opaque hash but moves it off the URL for the same shape:

```python
        return JoinGrant(
            join_url=f"https://video.kaleem.test/{room.external_id}",
            token=token,
            expires_at=expires_at,
        )
```

`JoinGrantSerializer` gains `token = serializers.CharField(allow_blank=True)`.

- [ ] **Step 4: Run everything**

```bash
cd backend && pytest -q && ruff check . && mypy kaleem signaling && lint-imports
```
Expected: all pass. Fix any test elsewhere that asserted the old URL shape.

- [ ] **Step 5: Commit**

```bash
cd backend && git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): hand the client its token beside the join URL, not inside it (C3c)"
```

---

### Task 6: A room is pinned to one deploy colour

**Files:**
- Modify: `backend/kaleem/scheduling/models.py` (`Room`)
- Create: `backend/kaleem/scheduling/migrations/0007_room_signaling_url.py` (via `makemigrations`)
- Modify: `backend/kaleem/scheduling/providers/__init__.py` (`ProviderRoom`)
- Modify: `backend/kaleem/scheduling/providers/signaling_provider.py`
- Modify: `backend/kaleem/scheduling/rooms.py` (`_ensure_room`)
- Test: `backend/kaleem/scheduling/tests/test_rooms_service.py`, `test_room_models.py`

**Interfaces:**
- Consumes: `_ensure_room(session) -> ProviderRoom` (existing), which already runs under the session row lock.
- Produces: `ProviderRoom(external_id: str, provider: str, signaling_url: str = "")`; `Room.signaling_url` — `CharField(max_length=255, blank=True, default="")`.

- [ ] **Step 1: Write the failing tests**

Append to `test_rooms_service.py`:

```python
def test_the_room_remembers_which_signaling_host_it_belongs_to(
    joinable_session, student
):
    with override_settings(
        VIDEO_PROVIDER="kaleem.scheduling.providers.signaling_provider.SignalingProvider",
        SIGNALING_SECRET="s",
        SIGNALING_URL="wss://ws-blue.example.test",
        TURN_SECRET="t",
        TURN_URLS="turn:turn.example.test:3478",
    ):
        rooms.join_session(student, joinable_session.id)
    room = Room.objects.get(session=joinable_session)
    assert room.signaling_url == "wss://ws-blue.example.test"


def test_a_second_participant_gets_the_first_ones_colour(
    joinable_session, student, teacher
):
    """The whole point. `django-blue` and `django-green` BOTH claim
    Host(API_DOMAIN) during a deploy, so two participants can be served their
    grants by different colours. Pinning the hostname alone would still let
    them straddle; pinning the ROOM cannot."""
    base = {
        "VIDEO_PROVIDER": "kaleem.scheduling.providers.signaling_provider.SignalingProvider",
        "SIGNALING_SECRET": "s",
        "TURN_SECRET": "t",
        "TURN_URLS": "turn:turn.example.test:3478",
    }
    with override_settings(**base, SIGNALING_URL="wss://ws-blue.example.test"):
        first = rooms.join_session(student, joinable_session.id)
    with override_settings(**base, SIGNALING_URL="wss://ws-green.example.test"):
        second = rooms.join_session(teacher, joinable_session.id)

    assert first.join_url == second.join_url
    assert "ws-blue" in second.join_url


def test_a_room_created_before_the_pin_falls_back_to_the_setting(
    joinable_session, student
):
    """Staging has live rooms. The column is nullable-by-default and a row
    written before this migration must read as 'unpinned' and use the
    configured host, not raise."""
    Room.objects.create(
        session=joinable_session,
        provider="signaling",
        external_id=f"session-{joinable_session.id}",
        signaling_url="",
    )
    with override_settings(
        VIDEO_PROVIDER="kaleem.scheduling.providers.signaling_provider.SignalingProvider",
        SIGNALING_SECRET="s",
        SIGNALING_URL="wss://ws-green.example.test",
        TURN_SECRET="t",
        TURN_URLS="turn:turn.example.test:3478",
    ):
        grant = rooms.join_session(student, joinable_session.id)
    assert "ws-green" in grant.join_url
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd backend && pytest kaleem/scheduling/tests/test_rooms_service.py -k "colour or signaling_host or pin" -v
```
Expected: FAIL — `Room` has no `signaling_url`.

- [ ] **Step 3: Implement**

On `Room`, after `external_id`:

```python
    # Which signaling host this room lives on, captured at creation. NOT read
    # from settings at join time: `django-blue` and `django-green` both claim
    # Host(API_DOMAIN) during a deploy, so two participants of one lesson can
    # be served by different colours and would otherwise be handed different
    # signaling hosts -- each landing alone in a one-peer room, with no
    # `peer-joined`, no error and no close code. Blank for a provider that has
    # no signaling host, and for rows written before this column existed.
    signaling_url = models.CharField(max_length=255, blank=True, default="")
```

`ProviderRoom` gains `signaling_url: str = ""`. `SignalingProvider.create_room` returns it populated from `settings.SIGNALING_URL`; `get_join_url` uses `room.signaling_url or settings.SIGNALING_URL` as the base — the fallback is what keeps pre-migration rows working.

In `rooms._ensure_room`, the existing-room branch reconstructs the pin, and the create branch persists it:

```python
    existing = Room.objects.filter(session=session, status=Room.Status.ACTIVE).first()
    if existing is not None:
        return ProviderRoom(
            external_id=existing.external_id,
            provider=existing.provider,
            signaling_url=existing.signaling_url,
        )
    ...
    Room.objects.create(
        session=session,
        provider=created.provider,
        external_id=created.external_id,
        signaling_url=created.signaling_url,
    )
```

Generate the migration:

```bash
cd backend && python manage.py makemigrations scheduling -n room_signaling_url
```

- [ ] **Step 4: Run everything**

```bash
cd backend && pytest -q && python manage.py makemigrations --check --dry-run && ruff check . && mypy kaleem signaling && lint-imports
```
Expected: all pass; `--check` reports no missing migrations.

- [ ] **Step 5: Commit**

```bash
cd backend && git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "fix(scheduling): pin a room to one deploy colour's signaling host (C3c)"
```

---

### Task 7: Backend coverage ratchet and PR

**Files:**
- Modify: `backend/pyproject.toml` (`[tool.coverage.report] fail_under`)

- [ ] **Step 1: Measure coverage correctly**

```bash
cd backend && pytest --cov=kaleem --cov=signaling --cov-report=term-missing -q
```

**Never a bare `pytest --cov`.** It falls back to the `include` filter, omits files no test imports, reads roughly 0.55 high, and set a false floor that turned CI red in C3a.

- [ ] **Step 2: Raise the floor**

If the measured total exceeds the current `fail_under = 97.7`, raise it to the measured value rounded **down** to one decimal. Do not touch `precision = 1`; coverage.py rounds to `precision` before comparing, and without it a fractional floor compares `97.28` as `97`.

If the total is *below* 97.7, do not lower it — find the uncovered lines and test them.

- [ ] **Step 3: Verify the floor is enforced**

```bash
cd backend && pytest --cov=kaleem --cov=signaling -q
```
Expected: exits 0. Then temporarily bump `fail_under` by 1.0, re-run, confirm it exits non-zero, and revert — the floor must be proven to bite.

- [ ] **Step 4: Commit and open the PR**

```bash
cd backend && git add pyproject.toml
PIP_CONFIG_FILE=/dev/null git commit -m "chore: raise the backend coverage floor (C3c)"
git push -u origin feat/phase-c3c-turn
gh pr create --base main --title "C3c: TURN credentials, subprotocol token, room colour pin" --body "Implements docs/superpowers/specs/2026-09-06-phase-c3c-turn-design.md (backend half)."
```

---

### Task 8: coturn in infra

**Files:**
- Create: `infra/coturn/turnserver.conf`
- Modify: `infra/docker-compose.production.yml` (new `coturn` service; `signaling-blue` / `signaling-green` router rules; `django-blue` / `django-green` `environment:` blocks)
- Modify: `infra/.env.production.example`
- Create: `docs/runbook/turn.md` (in the **meta** repo — see Task 10)

**Interfaces:**
- Consumes: `DJANGO_TURN_SECRET` from Task 3 (same value as coturn's `static-auth-secret`).
- Produces: env vars `TURN_REALM`, `TURN_SECRET`, `WS_BLUE_DOMAIN`, `WS_GREEN_DOMAIN`. `WS_DOMAIN` retired.

- [ ] **Step 1: Write `infra/coturn/turnserver.conf`**

```conf
# coturn — the TURN relay for kaleem lessons (C3c).
#
# Roughly one connection in six cannot go peer-to-peer and fails outright
# without this. It is not optional infrastructure.

listening-port=3478
fingerprint

# TURN REST ("use-auth-secret"): the credential is
#   username = "<unix-expiry>:<user-id>"
#   password = base64(HMAC-SHA1(static-auth-secret, username))
# computed by Django in kaleem/scheduling/providers/turn.py. coturn keeps NO
# user table, so there is nothing to provision and nothing to revoke — the
# expiry in the username is the whole revocation story.
use-auth-secret
static-auth-secret=${TURN_SECRET}
realm=${TURN_REALM}

# Bounded on purpose. Stock coturn suggests ~10k ports; a 1-on-1 platform
# needs hundreds, and a tight range is a firewall rule a human can verify.
min-port=49152
max-port=49999

# ── Hardening. An unfenced TURN server is two things at once: an SSRF pivot
# that will happily relay a packet into the private Docker network, and a
# DDoS amplifier carrying somebody else's return address. ─────────────────
no-multicast-peers
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=224.0.0.0-255.255.255.255

# One credential must not be able to exhaust the relay range.
user-quota=12
total-quota=1200

# No CLI listener at all: it is a plaintext admin socket and nothing here
# needs it.
no-cli

# Quiet by default. A per-session log line for every allocation would carry
# the ephemeral username, which encodes a kaleem user id.
no-stdout-log
syslog
```

- [ ] **Step 2: Add the service to `docker-compose.production.yml`**

Place it beside `redis`, **outside** any `profiles:` block — it holds no deploy-versioned code, and restarting it on every ship would drop live relay allocations for nothing:

```yaml
  coturn:
    image: coturn/coturn:4.6
    # host networking, not port mappings: a TURN relay hands out its own
    # address in ICE candidates, and Docker's userland proxy would advertise
    # an address the peer cannot reach. It also needs ~850 UDP ports, which
    # is not a port-mapping list anyone should maintain.
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro
    environment:
      - TURN_SECRET=${DJANGO_TURN_SECRET}
      - TURN_REALM=${TURN_REALM}
    command: ["-c", "/etc/coturn/turnserver.conf"]
```

- [ ] **Step 3: Give each colour its own WS hostname**

Change `signaling-blue`'s router rule to `Host(`${WS_BLUE_DOMAIN}`)` and `signaling-green`'s to `Host(`${WS_GREEN_DOMAIN}`)`. Add to **each Django colour** an `environment:` block below its `env_file:` (compose gives `environment:` precedence, which is exactly the override we want):

```yaml
    environment:
      # Overrides .env.production. Each Django colour hands out ITS OWN
      # colour's signaling host, so a room created by blue cannot be joined
      # through green. Combined with Room.signaling_url on the backend, a room
      # cannot straddle a deploy.
      - DJANGO_SIGNALING_URL=wss://${WS_BLUE_DOMAIN}
```
(and `WS_GREEN_DOMAIN` for green).

- [ ] **Step 4: Update `.env.production.example`**

Replace the `WS_DOMAIN` block with `WS_BLUE_DOMAIN=ws-blue-staging.kaleem.academy` and `WS_GREEN_DOMAIN=ws-green-staging.kaleem.academy`, keeping the existing comment's warning about an unset value causing a `Host(``)` rule and a full-colour rollback — it still applies, now to two variables. Delete `DJANGO_SIGNALING_URL` from the template (it is set per colour in compose now) and say so in a comment. Add:

```bash
# ─── TURN (C3c) ──────────────────────────────────────────────────────────
# Shared with coturn's `static-auth-secret`. Generate: openssl rand -base64 48
# NEVER commit a real value here. SignalingProvider fails closed without it.
DJANGO_TURN_SECRET=CHANGE_ME_GENERATE_A_LONG_RANDOM_STRING
TURN_REALM=kaleem.academy
# Comma-separated ICE URLs. The host must be a DNS-ONLY (grey cloud)
# Cloudflare record: Cloudflare cannot proxy UDP and a proxied record breaks
# every allocation with no error a client can interpret.
DJANGO_TURN_URLS=stun:turn-staging.kaleem.academy:3478,turn:turn-staging.kaleem.academy:3478?transport=udp,turn:turn-staging.kaleem.academy:3478?transport=tcp
```

- [ ] **Step 5: Validate and commit**

```bash
cd infra && docker compose -f docker-compose.production.yml --profile blue config >/dev/null && echo OK
```
Expected: `OK` with no unresolved-variable warnings other than for secrets you have not exported locally.

```bash
cd infra && git add -A
PIP_CONFIG_FILE=/dev/null git commit -m "feat: coturn relay and per-colour signaling hostnames (C3c)"
git push -u origin feat/phase-c3c-turn
gh pr create --base main --title "C3c: coturn + per-colour WS hosts" --body "Implements docs/superpowers/specs/2026-09-06-phase-c3c-turn-design.md (infra half)."
```

---

### Task 9: Dashboard grant schema

Small but required: the zod schema must accept the new fields or C3d starts by fixing this.

**Files:**
- Modify: `dashboard/src/features/booking/schemas.ts`
- Test: `dashboard/src/features/booking/schemas.test.ts`

**Interfaces:**
- Consumes: the response body from Task 3 and Task 5 — `{join_url, token, expires_at, ice_servers: [{urls, username, credential}]}`.
- Produces: the parsed grant type consumed by `JoinButton` today and by C3d's call client later.

- [ ] **Step 1: Write the failing test**

Append to `dashboard/src/features/booking/schemas.test.ts`:

```ts
it("keeps the token and the ICE servers off the join URL", () => {
	const grant = joinGrantSchema.parse({
		join_url: "wss://ws-blue-staging.kaleem.academy/ws/rooms/session-1",
		token: "abc.def",
		expires_at: "2026-09-06T12:00:00Z",
		ice_servers: [
			{ urls: ["stun:turn.example.test:3478"], username: "", credential: "" },
			{
				urls: ["turn:turn.example.test:3478?transport=udp"],
				username: "1900000000:7",
				credential: "c2ln",
			},
		],
	});
	expect(grant.token).toBe("abc.def");
	expect(grant.ice_servers).toHaveLength(2);
	expect(grant.join_url).not.toContain("?");
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd dashboard && pnpm vitest run src/features/booking/schemas.test.ts
```
Expected: FAIL — `token` and `ice_servers` are stripped by the existing schema.

- [ ] **Step 3: Implement**

In `dashboard/src/features/booking/schemas.ts`, beside the existing grant schema:

```ts
const iceServerSchema = z.object({
	urls: z.array(z.string()),
	username: z.string(),
	credential: z.string(),
});
```
and add `token: z.string()` plus `ice_servers: z.array(iceServerSchema)` to the join-grant schema. Follow the file's existing naming and export style; read it before editing.

- [ ] **Step 4: Run the suite with coverage**

```bash
cd dashboard && pnpm vitest run --coverage
```
Expected: all pass, floors (`93.5 / 90 / 86.5 / 93.5`) green. Raise any floor the run clears.

- [ ] **Step 5: Commit and open the PR**

```bash
cd dashboard && git add -A
git commit -m "feat(booking): accept the token and ICE servers on a join grant (C3c)"
git push -u origin feat/phase-c3c-ice-schema
gh pr create --base main --title "C3c: join grant schema" --body "Implements docs/superpowers/specs/2026-09-06-phase-c3c-turn-design.md (dashboard half)."
```

---

### Task 10: Runbook, ISSUES rewrite, docs

**Files:**
- Create: `docs/runbook/turn.md`
- Modify: `docs/runbook/signaling.md`
- Modify: `ISSUES.md`
- Modify: `CLAUDE.md` (the D3 e2e table)
- Modify: `docs/architecture/scheduling.md`

- [ ] **Step 1: Write `docs/runbook/turn.md`**

Cover, each as a numbered step a tired human can follow at 23:00: generating `DJANGO_TURN_SECRET` and pasting the *same* value into `.env.production` (it feeds both Django and coturn from one entry); creating the **DNS-only / grey-cloud** `turn-staging` A record and why a proxied record silently breaks every allocation; opening `3478/udp`, `3478/tcp` and `49152-49999/udp` at the provider firewall; verifying with `turnutils_uclient`; and the symptom table — allocations succeed but no media means the relay range is open in coturn and closed at the firewall.

- [ ] **Step 2: Update `docs/runbook/signaling.md`**

Replace `WS_DOMAIN` with the two per-colour variables. Keep the "deploy between lessons" interim rule — C3c narrows the split-room window but does **not** implement the drain, and a runbook that implies otherwise is worse than none. Add: a room pinned to a stopped colour now fails a rejoin loudly rather than splitting silently, and that is the intended trade.

- [ ] **Step 3: Rewrite the `ISSUES.md` entries**

- *A deploy drops every live call, and the colour overlap can split a room in two*: delete the split-room half (fixed by per-colour hosts **plus** `Room.signaling_url`) and keep the drop-every-live-call half, restated as its own entry under **Blocks launch**. Say explicitly that fix (a) alone was insufficient because both Django colours also claim `Host(API_DOMAIN)`, so the record shows *why* the room-level pin exists.
- *The capability token still travels in a URL query string*: delete it — done. **Replace it with a new entry**: Traefik's `RequestPath` stays dropped and cannot be restored, because `allauth.urls` serves `/accounts/confirm-email/<key>/` and `/accounts/password/reset/key/<uidb36>-<key>/` — single-use account-takeover credentials in the **path**. Record the compensating control (dashboard and marketing container access logs) as the actual remedy.
- *A video join grant is never validated, expired, or revoked* and *`GRANT_TTL` is unrelated to the join window*: both closed — delete.
- **Add** under *Blocks launch*: no `turns:` on 5349 or 443, so users behind a TLS-443-only egress filter still cannot call. Note that Traefik owns 443 on this box, so the fix is either a second IP or a dedicated TURN host.
- **Add** under *Blocks launch*: the `turn-staging` record is DNS-only, which publishes the origin IP that the proxied records currently hide.

- [ ] **Step 4: Update `CLAUDE.md`'s D3 e2e table**

Add a row: `signaling` (C3c) → `❌ by design` → "TURN credentials and the subprotocol handshake have no user-facing behaviour and CI has no coturn; verified live with `turnutils_uclient` and a throwaway relay-only harness". Update the backend coverage floor in the same table to whatever Task 7 set.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "docs: C3c runbook, ISSUES triage, D3 table"
```

---

### Task 11: Live verification — the part no suite can do

C3b shipped a Critical that every green suite was structurally unable to see: the bug lived in uvicorn and every test ran through `TestClient`. The same shape of blind spot applies here — nothing in Python proves a UDP packet traverses coturn.

**Files:**
- Create (throwaway, **not committed**): a single HTML file in the scratchpad directory.

- [ ] **Step 1: Deploy to staging**

Merge the backend, infra and dashboard PRs, then the meta PR carrying the pointer bumps. A merge to meta `master` **is** the deploy. Before merging, confirm the VPS `.env.production` already carries `DJANGO_TURN_SECRET`, `TURN_REALM`, `DJANGO_TURN_URLS`, `WS_BLUE_DOMAIN` and `WS_GREEN_DOMAIN`, and that `ws-blue-staging.kaleem.academy` / `ws-green-staging.kaleem.academy` DNS records exist with issued certificates — it is hand-managed, and a missing `WS_*_DOMAIN` now aborts the deploy outright via `docker-compose.production.yml`'s `${VAR:?message}` guard (not the "failed health check + colour rollback" this line used to claim — `ship.sh`'s signaling health check is container-local and cannot see a dead Traefik router).

- [ ] **Step 2: Prove the relay allocates**

```bash
# On the VPS, with a credential minted by Django for a real user:
turnutils_uclient -T -u '<expiry>:<user-id>' -w '<password>' -p 3478 turn-staging.kaleem.academy
```
Expected: allocation succeeds and packets round-trip. A `401` here means the HMAC kaleem computes is not the one coturn expects — check that one `DJANGO_TURN_SECRET` feeds both.

- [ ] **Step 3: Prove a media path end to end**

Write a throwaway page in the scratchpad holding two `RTCPeerConnection`s with `iceTransportPolicy: "relay"`, fed the `ice_servers` from a real join response. Relay-only forces every candidate through coturn, so a successful connection proves the whole path. Do **not** commit it to `dashboard/` — C3d owns the real client and must not inherit a scaffold written before its design.

- [ ] **Step 4: Mutation-check both**

Change one character of the secret used to mint the credential and re-run Steps 2 and 3. Both must fail. A verification that cannot fail has verified nothing.

- [ ] **Step 5: Prove the room pin**

Join the same staging session as the student and as the teacher, and confirm both grants name the same `ws-*-staging` host and that neither `join_url` contains `?`.

- [ ] **Step 6: Close the phase**

Run `/ship` and walk D9: spec closed, plan done, tests passing, boundary check green, coverage floors green, e2e green at 33, manual click-through done, staging deployed, `docs/architecture/scheduling.md` updated, journal entry in `docs/superpowers/journal/2026-W36.md`, `STATE.md` updated.
