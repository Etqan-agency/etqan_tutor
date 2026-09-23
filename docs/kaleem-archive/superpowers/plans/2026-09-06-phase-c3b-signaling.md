# Phase C3b — Signaling Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a separate, authenticated WebSocket service over which exactly the two participants in a lesson exchange WebRTC offers, answers and ICE candidates.

**Architecture:** A standalone Starlette/uvicorn ASGI app living at `signaling/` in the `backend` repository — its own container and command, sharing the image, importing no Django and holding no database connection (ADR-0035, escape hatch E5). Authentication crosses the process boundary as an HMAC-signed, room-scoped, expiring capability token minted by Django and verified by signaling, using a pure-stdlib codec both sides import. Room state is a process-local dict: at most two peers per room, deleted when the last one leaves.

**Tech Stack:** Python 3.13, Starlette, uvicorn, `hmac`/`hashlib`/`base64`/`json` from the stdlib, pytest, Docker Compose, Traefik.

**Spec:** `docs/superpowers/specs/2026-09-06-phase-c3b-signaling-design.md`

## Global Constraints

- **`signaling` must not import Django or `kaleem.*`.** No ORM, no settings, no database connection. Enforced by a new `import-linter` contract, and **that contract must be verified by breaking it** — a probe import turns it red, and the run is green once removed.
- **The dependency arrow is one-way:** `kaleem.scheduling` may import `signaling.tokens`; nothing under `signaling/` may import `kaleem`.
- **No message is persisted.** Signaling has no database by construction.
- **A room holds at most two peers** (1-on-1 is the product, ADR-0034). A third connection is refused with its own close code, never silently dropped.
- **Signaling relays; it does not interpret.** No SDP parsing, no ICE inspection. Opaque payloads between two authenticated peers.
- **The token is never logged.** It rides in the URL query string (browsers cannot set headers on a WebSocket handshake), so query strings must not reach the access log.
- **Secrets never enter the repository** (rule #11). `DJANGO_SIGNALING_SECRET` comes from the environment; `.env*` files are blocked by pre-commit and must not be committed.
- **No bare `except Exception` stringified into a response** (rule #8).
- **Backend coverage floor is a ratchet at 97.6** — and **measure it the way CI does, `pytest --cov=kaleem`**, never a bare `pytest --cov`, which omits files no test imports and reads ~0.55 higher. That mistake set a false floor once already (see the comment in `pyproject.toml`). Lowering a floor requires an ADR (ADR-0026).
- **TDD (D3):** failing test first, every task. **Never `--no-verify`.** Backend commits run as `PIP_CONFIG_FILE=/dev/null git commit` (a dead pip proxy otherwise breaks pre-commit).
- **Branch `feat/phase-c3b-signaling`** in `backend` and `infra`. Never commit to a trunk.

---

## File Structure

**backend** — new top-level package, deliberately outside `kaleem/`:
- `signaling/__init__.py` — **create**, empty.
- `signaling/tokens.py` — **create**: `RoomToken`, `mint`, `verify`, `TokenError`. Pure stdlib, Django-free, imported by both sides.
- `signaling/rooms.py` — **create**: `RoomRegistry` — the two-peer cap, join/leave, cleanup.
- `signaling/app.py` — **create**: the Starlette app, the WebSocket endpoint, the health route.
- `signaling/tests/` — **create**: `test_tokens.py`, `test_rooms.py`, `test_app.py`.
- `kaleem/scheduling/providers/signaling_provider.py` — **create**: mints real `wss://` join URLs.
- `config/settings/base.py` — **modify**: `SIGNALING_SECRET`, `SIGNALING_URL`.
- `pyproject.toml` — **modify**: import-linter root packages + contract, coverage `include`.
- `requirements/base.txt` — **modify**: `starlette`, `uvicorn`.
- `Dockerfile` — **modify**: nothing structural; confirm `signaling/` is copied by the existing `COPY . .`.

**meta / infra**:
- `docker-compose.local.yml` — **modify**: a `signaling` service.
- `infra/docker-compose.production.yml` — **modify**: `signaling-blue` / `signaling-green`.
- `infra/scripts/ship.sh` — **modify**: the new colour pair in start, health, rollback and stop.
- `docs/runbook/signaling.md` — **create**.

---

### Task 1: The token codec

**Files:**
- Create: `backend/signaling/__init__.py`, `backend/signaling/tokens.py`
- Create: `backend/signaling/tests/__init__.py`, `backend/signaling/tests/test_tokens.py`

**Interfaces:**
- Consumes: nothing.
- Produces, from `signaling.tokens`:
  - `RoomToken(room_id: str, user_id: int, is_teacher: bool, expires_at: int)` — a frozen dataclass
  - `mint(token: RoomToken, secret: str) -> str`
  - `verify(raw: str, secret: str, *, now: int | None = None) -> RoomToken` — raises `TokenError`
  - `TokenError(Exception)`

**Context:** Pure stdlib — `hmac`, `hashlib`, `base64`, `json`, `dataclasses`. **No Django, no third-party library, no JWT package.** Use `hmac.compare_digest` for the signature check; `==` on a signature is a timing oracle. `expires_at` is a unix timestamp in seconds.

- [ ] **Step 1: Write the failing tests**

Create `backend/signaling/tests/test_tokens.py`:

```python
import pytest

from signaling.tokens import RoomToken
from signaling.tokens import TokenError
from signaling.tokens import mint
from signaling.tokens import verify

SECRET = "test-secret-not-a-real-one"
LATER = 2_000_000_000


def a_token(**overrides) -> RoomToken:
    fields = {
        "room_id": "session-42",
        "user_id": 7,
        "is_teacher": False,
        "expires_at": LATER,
    }
    fields.update(overrides)
    return RoomToken(**fields)


def test_a_minted_token_verifies_back_to_the_same_claims():
    assert verify(mint(a_token(), SECRET), SECRET, now=LATER - 1) == a_token()


def test_a_token_signed_with_another_secret_is_refused():
    with pytest.raises(TokenError):
        verify(mint(a_token(), "a-different-secret"), SECRET, now=LATER - 1)


def test_an_expired_token_is_refused():
    with pytest.raises(TokenError):
        verify(mint(a_token(), SECRET), SECRET, now=LATER + 1)


def test_a_token_expiring_this_very_second_is_still_accepted():
    """The boundary is inclusive, so a clock landing exactly on the expiry
    does not strand a participant who clicked in time."""
    assert verify(mint(a_token(), SECRET), SECRET, now=LATER).user_id == 7


def test_a_tampered_payload_is_refused():
    payload, signature = mint(a_token(), SECRET).split(".")
    forged = mint(a_token(user_id=999), SECRET).split(".")[0]
    with pytest.raises(TokenError):
        verify(f"{forged}.{signature}", SECRET, now=LATER - 1)


def test_a_tampered_signature_is_refused():
    payload, signature = mint(a_token(), SECRET).split(".")
    with pytest.raises(TokenError):
        verify(f"{payload}.{signature[:-1]}x", SECRET, now=LATER - 1)


@pytest.mark.parametrize(
    "raw",
    ["", ".", "notbase64.notbase64", "onlyonepart", "a.b.c"],
)
def test_a_malformed_token_is_refused_rather_than_crashing(raw):
    with pytest.raises(TokenError):
        verify(raw, SECRET, now=LATER - 1)


def test_the_room_id_is_signed_not_merely_carried():
    """A valid signature over room A must not admit its holder to room B --
    the room is the whole point of the capability."""
    for_room_a = mint(a_token(room_id="session-1"), SECRET)
    assert verify(for_room_a, SECRET, now=LATER - 1).room_id == "session-1"


def test_the_teacher_flag_survives_the_round_trip():
    assert verify(mint(a_token(is_teacher=True), SECRET), SECRET, now=LATER - 1).is_teacher
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/test_tokens.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'signaling'`.

- [ ] **Step 3: Implement the codec**

Create `backend/signaling/__init__.py` (empty), then `backend/signaling/tokens.py`:

```python
"""The capability token the API mints and the signaling service verifies.

Pure stdlib and Django-free on purpose: signaling imports this and must not
import Django (ADR-0035), while `kaleem.scheduling` imports it too. One codec,
so the two processes cannot disagree about the format.

Not a JWT, and not a login. ADR-0003 forbids bearer tokens as user
authentication for the API, and that stands -- this is a capability scoped to
one room, one participant and a few minutes.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
from dataclasses import asdict
from dataclasses import dataclass


class TokenError(Exception):
    """The token is absent, malformed, expired, or not ours.

    Deliberately one exception for every failure: telling a caller *which*
    check failed tells an attacker which half to keep guessing at.
    """


@dataclass(frozen=True)
class RoomToken:
    room_id: str
    user_id: int
    is_teacher: bool
    expires_at: int


def _b64(raw: bytes) -> str:
    # Unpadded urlsafe: this rides in a query string.
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _unb64(raw: str) -> bytes:
    return base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))


def _sign(payload: str, secret: str) -> str:
    digest = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).digest()
    return _b64(digest)


def mint(token: RoomToken, secret: str) -> str:
    payload = _b64(json.dumps(asdict(token), sort_keys=True).encode())
    return f"{payload}.{_sign(payload, secret)}"


def verify(raw: str, secret: str, *, now: int | None = None) -> RoomToken:
    """Return the claims, or raise TokenError. Never returns None."""
    if now is None:
        import time

        now = int(time.time())

    parts = raw.split(".")
    if len(parts) != 2 or not all(parts):
        raise TokenError("malformed token")
    payload, signature = parts

    # compare_digest, not ==: a short-circuiting comparison leaks how much of
    # the signature was right, one byte at a time.
    if not hmac.compare_digest(signature, _sign(payload, secret)):
        raise TokenError("bad signature")

    try:
        claims = json.loads(_unb64(payload))
        token = RoomToken(**claims)
    except Exception as exc:  # noqa: BLE001 -- any decode failure is one answer
        raise TokenError("malformed payload") from exc

    if now > token.expires_at:
        raise TokenError("expired")
    return token
```

- [ ] **Step 4: Run them and watch them pass**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/test_tokens.py -v`
Expected: 11 passed.

- [ ] **Step 5: Commit**

```bash
git add signaling/
PIP_CONFIG_FILE=/dev/null git commit -m "feat(signaling): add the room capability token codec"
```

---

### Task 2: The room registry

**Files:**
- Create: `backend/signaling/rooms.py`
- Create: `backend/signaling/tests/test_rooms.py`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces, from `signaling.rooms`:
  - `RoomFull(Exception)`
  - `RoomRegistry()` with `join(room_id: str, peer) -> list` (returns the peers already present), `leave(room_id: str, peer) -> None`, `peers(room_id: str) -> list`, and `room_count() -> int`
  - `MAX_PEERS = 2`

**Context:** Plain in-memory state — a dict of room id to list of peer objects. A "peer" is opaque here (the app passes the WebSocket); the registry never calls it, so the tests use plain strings. Single replica per colour, so no locking and no Redis (spec decision 7).

**The property that matters most is cleanup.** A room must disappear when its last peer leaves. A registry that leaks rooms is the failure that ends in a restart at 3am, and `room_count()` exists so a test can assert it directly rather than inferring it from the absence of an error.

- [ ] **Step 1: Write the failing tests**

Create `backend/signaling/tests/test_rooms.py`:

```python
import pytest

from signaling.rooms import MAX_PEERS
from signaling.rooms import RoomFull
from signaling.rooms import RoomRegistry


def test_the_first_peer_finds_an_empty_room():
    assert RoomRegistry().join("r1", "alice") == []


def test_the_second_peer_is_told_who_is_already_there():
    registry = RoomRegistry()
    registry.join("r1", "alice")
    assert registry.join("r1", "bob") == ["alice"]


def test_a_third_peer_is_refused():
    registry = RoomRegistry()
    registry.join("r1", "alice")
    registry.join("r1", "bob")
    with pytest.raises(RoomFull):
        registry.join("r1", "eve")


def test_a_refused_peer_does_not_join_the_room():
    """The cap must not corrupt the room it protects."""
    registry = RoomRegistry()
    registry.join("r1", "alice")
    registry.join("r1", "bob")
    with pytest.raises(RoomFull):
        registry.join("r1", "eve")
    assert registry.peers("r1") == ["alice", "bob"]


def test_rooms_are_independent():
    registry = RoomRegistry()
    registry.join("r1", "alice")
    registry.join("r2", "bob")
    assert registry.peers("r1") == ["alice"]
    assert registry.peers("r2") == ["bob"]


def test_a_room_is_deleted_when_its_last_peer_leaves():
    """Asserted on the registry itself, not on the absence of an error: a
    leaked room is invisible until the process runs out of memory."""
    registry = RoomRegistry()
    registry.join("r1", "alice")
    registry.leave("r1", "alice")
    assert registry.room_count() == 0


def test_a_room_survives_one_of_two_peers_leaving():
    registry = RoomRegistry()
    registry.join("r1", "alice")
    registry.join("r1", "bob")
    registry.leave("r1", "alice")
    assert registry.peers("r1") == ["bob"]
    assert registry.room_count() == 1


def test_leaving_a_room_twice_is_harmless():
    """A disconnect handler can fire after an error path already cleaned up."""
    registry = RoomRegistry()
    registry.join("r1", "alice")
    registry.leave("r1", "alice")
    registry.leave("r1", "alice")
    assert registry.room_count() == 0


def test_leaving_a_room_that_never_existed_is_harmless():
    RoomRegistry().leave("nope", "alice")


def test_peers_of_an_unknown_room_is_empty():
    assert RoomRegistry().peers("nope") == []


def test_a_freed_slot_can_be_taken_again():
    registry = RoomRegistry()
    registry.join("r1", "alice")
    registry.join("r1", "bob")
    registry.leave("r1", "bob")
    assert registry.join("r1", "carol") == ["alice"]


def test_the_cap_is_two():
    assert MAX_PEERS == 2
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/test_rooms.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'signaling.rooms'`.

- [ ] **Step 3: Implement it**

Create `backend/signaling/rooms.py`:

```python
"""Process-local room membership.

A dict, deliberately. One replica per colour (ADR-0035), so two peers in a
room always land on the same process and there is nothing to synchronise. If
that ever stops being true, this is the file that grows a fan-out layer -- and
the constraint is stated in the spec so it is visible rather than discovered.
"""

from __future__ import annotations

MAX_PEERS = 2


class RoomFull(Exception):
    """A third connection to a 1-on-1 room."""


class RoomRegistry:
    def __init__(self) -> None:
        self._rooms: dict[str, list] = {}

    def join(self, room_id: str, peer) -> list:
        """Add `peer` and return whoever was already there.

        Returning the existing occupants (rather than None) is what lets the
        caller announce the pairing without a second lookup that could race.
        """
        existing = self._rooms.setdefault(room_id, [])
        if len(existing) >= MAX_PEERS:
            # Raise *before* mutating: the cap must not corrupt the room it
            # protects. Drop the empty room we may just have created, so a
            # refused join cannot leak one.
            if not existing:
                del self._rooms[room_id]
            raise RoomFull(room_id)
        already_here = list(existing)
        existing.append(peer)
        return already_here

    def leave(self, room_id: str, peer) -> None:
        """Remove `peer`, and the room with it if that was the last one.

        Idempotent: a disconnect handler can fire after an error path already
        cleaned up, and that must not raise.
        """
        peers = self._rooms.get(room_id)
        if peers is None:
            return
        if peer in peers:
            peers.remove(peer)
        if not peers:
            del self._rooms[room_id]

    def peers(self, room_id: str) -> list:
        return list(self._rooms.get(room_id, []))

    def room_count(self) -> int:
        """Exposed for tests: a leaked room is otherwise invisible."""
        return len(self._rooms)
```

- [ ] **Step 4: Run them and watch them pass**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/test_rooms.py -v`
Expected: 12 passed.

- [ ] **Step 5: Commit**

```bash
git add signaling/rooms.py signaling/tests/test_rooms.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(signaling): add the two-peer room registry"
```

---

### Task 3: The ASGI app — handshake authentication

**Files:**
- Create: `backend/signaling/app.py`
- Create: `backend/signaling/tests/test_app.py`
- Modify: `backend/requirements/base.txt`

**Interfaces:**
- Consumes: `signaling.tokens.verify`, `TokenError` (Task 1); `signaling.rooms.RoomRegistry`, `RoomFull` (Task 2).
- Produces, from `signaling.app`: `app` (a Starlette instance), `CLOSE_UNAUTHORIZED = 4401`, `CLOSE_ROOM_FULL = 4409`, `CLOSE_BAD_MESSAGE = 4400`, and `registry` (the module-level `RoomRegistry`).

**Context:** Starlette and uvicorn are new dependencies — add `starlette>=0.40` and `uvicorn[standard]>=0.30` to `requirements/base.txt` (production needs both; `local.txt` and `production.txt` both include `base.txt`). Rebuild the image after editing requirements, or the import fails: `docker compose -f docker-compose.local.yml build django && docker compose -f docker-compose.local.yml up -d django`.

Starlette's `TestClient.websocket_connect` is a synchronous context manager, which keeps these tests readable and free of event-loop plumbing.

**The secret comes from `os.environ`, never Django settings** — this process must not import Django. Read it at call time, not at import time, so tests can set it with `monkeypatch.setenv`.

Close codes are in the 4000–4999 application range. They are distinct per reason so the client (C3d) can tell "your token expired, get a new one" from "that room is full", which are different user-facing outcomes.

- [ ] **Step 1: Write the failing tests**

Create `backend/signaling/tests/test_app.py`:

```python
import time

import pytest
from starlette.testclient import TestClient

from signaling.app import CLOSE_ROOM_FULL
from signaling.app import CLOSE_UNAUTHORIZED
from signaling.app import app
from signaling.app import registry
from signaling.tokens import RoomToken
from signaling.tokens import mint

SECRET = "test-secret-not-a-real-one"


@pytest.fixture(autouse=True)
def _secret(monkeypatch):
    monkeypatch.setenv("DJANGO_SIGNALING_SECRET", SECRET)


@pytest.fixture(autouse=True)
def _clean_registry():
    """The registry is module-level state; a leaked room from one test would
    silently change the next one's answer."""
    yield
    registry._rooms.clear()


def token_for(room="session-1", user=1, teacher=False, ttl=300, secret=SECRET):
    return mint(
        RoomToken(
            room_id=room,
            user_id=user,
            is_teacher=teacher,
            expires_at=int(time.time()) + ttl,
        ),
        secret,
    )


def url(room="session-1", token=None):
    return f"/ws/rooms/{room}?t={token if token is not None else token_for(room)}"


def test_a_valid_token_connects():
    with TestClient(app).websocket_connect(url()) as ws:
        assert ws is not None


def test_a_missing_token_is_refused():
    with pytest.raises(Exception):  # noqa: B017 -- starlette raises on close
        with TestClient(app).websocket_connect("/ws/rooms/session-1"):
            pass


def test_a_token_for_another_room_is_refused():
    """The signature is valid and the claims are ours -- but the room in the
    URL is not the room in the token. Without this check the token is a
    platform-wide key instead of a capability."""
    other = token_for(room="session-999")
    client = TestClient(app)
    with pytest.raises(Exception), client.websocket_connect(url(token=other)):
        pass


def test_a_token_signed_with_another_secret_is_refused():
    bad = token_for(secret="not-our-secret")
    client = TestClient(app)
    with pytest.raises(Exception), client.websocket_connect(url(token=bad)):
        pass


def test_an_expired_token_is_refused():
    stale = token_for(ttl=-1)
    client = TestClient(app)
    with pytest.raises(Exception), client.websocket_connect(url(token=stale)):
        pass


def test_a_refused_connection_leaves_no_room_behind():
    client = TestClient(app)
    with pytest.raises(Exception), client.websocket_connect(url(token="garbage")):
        pass
    assert registry.room_count() == 0


def test_a_third_peer_is_refused_with_its_own_close_code():
    client = TestClient(app)
    with client.websocket_connect(url(token=token_for(user=1))):
        with client.websocket_connect(url(token=token_for(user=2))):
            with pytest.raises(Exception):
                with client.websocket_connect(url(token=token_for(user=3))):
                    pass


def test_the_close_codes_are_distinct():
    """The client must be able to tell 'get a new token' from 'that lesson is
    already full' -- they are different things to tell a user."""
    assert CLOSE_UNAUTHORIZED != CLOSE_ROOM_FULL
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/test_app.py -v`
Expected: FAIL — `ModuleNotFoundError` for `signaling.app` (or for `starlette`, until Step 3's rebuild).

- [ ] **Step 3: Add the dependencies and rebuild**

Append to `backend/requirements/base.txt`:

```
# Signaling runs as its own ASGI service from this same image (ADR-0035).
# In base, not local: production runs it too.
starlette>=0.40
uvicorn[standard]>=0.30
```

Then, from the meta root:

```bash
docker compose -f docker-compose.local.yml build django
docker compose -f docker-compose.local.yml up -d django
```

- [ ] **Step 4: Write the app**

Create `backend/signaling/app.py`:

```python
"""The signaling service: a WebSocket relay for one lesson's two participants.

Its own deployable, sharing the backend image and importing no Django
(ADR-0035). It has no database, no ORM and no settings module -- its entire
input is a socket and a signed token.
"""

from __future__ import annotations

import os

from starlette.applications import Starlette
from starlette.routing import WebSocketRoute
from starlette.websockets import WebSocket

from signaling.rooms import RoomFull
from signaling.rooms import RoomRegistry
from signaling.tokens import TokenError
from signaling.tokens import verify

# Application close codes (4000-4999). Distinct per reason so the client can
# tell "your token expired, fetch another" from "that lesson is already full".
CLOSE_UNAUTHORIZED = 4401
CLOSE_ROOM_FULL = 4409
CLOSE_BAD_MESSAGE = 4400

registry = RoomRegistry()


def _secret() -> str:
    # Read at call time, not import time: the process must fail loudly on a
    # missing secret rather than at import, and tests set it per-test.
    secret = os.environ.get("DJANGO_SIGNALING_SECRET", "")
    if not secret:
        message = "DJANGO_SIGNALING_SECRET is not set"
        raise RuntimeError(message)
    return secret


async def room_endpoint(websocket: WebSocket) -> None:
    room_id = websocket.path_params["room_id"]
    raw = websocket.query_params.get("t", "")

    try:
        token = verify(raw, _secret())
    except TokenError:
        # Accept-then-close, so the browser sees the application close code
        # instead of a bare handshake failure it cannot distinguish.
        await websocket.accept()
        await websocket.close(code=CLOSE_UNAUTHORIZED)
        return

    if token.room_id != room_id:
        # A valid signature over a different room. Without this the token is a
        # platform-wide key rather than a capability for one lesson.
        await websocket.accept()
        await websocket.close(code=CLOSE_UNAUTHORIZED)
        return

    await websocket.accept()
    try:
        others = registry.join(room_id, websocket)
    except RoomFull:
        await websocket.close(code=CLOSE_ROOM_FULL)
        return

    # Task 4 fills in the relay loop; for now hold the connection open so the
    # membership tests can observe the room.
    try:
        await _relay_loop(websocket, room_id, others)
    finally:
        # In `finally`, not after the loop: a client that vanishes mid-frame
        # must still free its slot, or the room stays full forever.
        registry.leave(room_id, websocket)


async def _relay_loop(websocket: WebSocket, room_id: str, others: list) -> None:
    while True:
        await websocket.receive_text()


app = Starlette(routes=[WebSocketRoute("/ws/rooms/{room_id}", room_endpoint)])
```

- [ ] **Step 5: Run them and watch them pass**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/test_app.py -v`
Expected: 8 passed.

- [ ] **Step 6: Commit**

```bash
git add signaling/app.py signaling/tests/test_app.py requirements/base.txt
PIP_CONFIG_FILE=/dev/null git commit -m "feat(signaling): authenticate the WebSocket handshake"
```

---

### Task 4: Presence and the relay

**Files:**
- Modify: `backend/signaling/app.py`
- Modify: `backend/signaling/tests/test_app.py` (append)

**Interfaces:**
- Consumes: everything from Task 3.
- Produces: the wire protocol — `{"type": "peer-joined"}`, `{"type": "peer-left"}`, and `{"type": "offer"|"answer"|"ice", "payload": <opaque>}` relayed to the other peer.

**Context:** Four message types, and the server understands none of their contents. `payload` is opaque — no SDP parsing, no ICE inspection (spec decision 5). Relay goes to *the other* peer, never back to the sender: echoing an offer to its author is how a client ends up negotiating with itself.

**A relay with no peer present is dropped, not queued.** WebRTC negotiation is not meaningful to replay at an absent peer, and a queue is a memory leak with extra steps.

Malformed JSON or an unknown type closes the connection with `CLOSE_BAD_MESSAGE`. Signaling has exactly one client — kaleem's own — so a bad frame is a bug or an attack, never version skew.

- [ ] **Step 1: Write the failing tests**

Append to `backend/signaling/tests/test_app.py`:

```python
from signaling.app import CLOSE_BAD_MESSAGE


def test_the_first_peer_is_told_when_the_second_arrives():
    client = TestClient(app)
    with client.websocket_connect(url(token=token_for(user=1))) as first:
        with client.websocket_connect(url(token=token_for(user=2))):
            assert first.receive_json() == {"type": "peer-joined"}


def test_the_second_peer_is_told_someone_is_already_there():
    client = TestClient(app)
    with client.websocket_connect(url(token=token_for(user=1))):
        with client.websocket_connect(url(token=token_for(user=2))) as second:
            assert second.receive_json() == {"type": "peer-joined"}


def test_the_remaining_peer_is_told_when_the_other_leaves():
    client = TestClient(app)
    with client.websocket_connect(url(token=token_for(user=1))) as first:
        with client.websocket_connect(url(token=token_for(user=2))):
            first.receive_json()
        assert first.receive_json() == {"type": "peer-left"}


def test_an_offer_reaches_the_other_peer_verbatim():
    client = TestClient(app)
    with client.websocket_connect(url(token=token_for(user=1))) as first:
        with client.websocket_connect(url(token=token_for(user=2))) as second:
            first.receive_json()
            second.receive_json()
            sent = {"type": "offer", "payload": {"sdp": "v=0 opaque", "n": 1}}
            first.send_json(sent)
            assert second.receive_json() == sent


def test_an_answer_and_an_ice_candidate_relay_too():
    client = TestClient(app)
    with client.websocket_connect(url(token=token_for(user=1))) as first:
        with client.websocket_connect(url(token=token_for(user=2))) as second:
            first.receive_json()
            second.receive_json()
            for kind in ("answer", "ice"):
                message = {"type": kind, "payload": {"k": kind}}
                second.send_json(message)
                assert first.receive_json() == message


def test_a_relay_is_never_echoed_back_to_its_sender():
    """Echoing an offer to its author makes a client negotiate with itself."""
    client = TestClient(app)
    with client.websocket_connect(url(token=token_for(user=1))) as first:
        with client.websocket_connect(url(token=token_for(user=2))) as second:
            first.receive_json()
            second.receive_json()
            first.send_json({"type": "offer", "payload": {"n": 1}})
            second.receive_json()
            second.send_json({"type": "answer", "payload": {"n": 2}})
            # If the offer had been echoed, this would read it instead.
            assert first.receive_json() == {"type": "answer", "payload": {"n": 2}}


def test_a_relay_with_nobody_listening_is_dropped_not_queued():
    """Queueing negotiation for an absent peer is a memory leak that also
    replays stale SDP at whoever arrives next."""
    client = TestClient(app)
    with client.websocket_connect(url(token=token_for(user=1))) as first:
        first.send_json({"type": "offer", "payload": {"n": 1}})
    with client.websocket_connect(url(token=token_for(user=2))) as second:
        with client.websocket_connect(url(token=token_for(user=3))) as third:
            second.receive_json()
            third.receive_json()
            third.send_json({"type": "ice", "payload": {"fresh": True}})
            assert second.receive_json() == {"type": "ice", "payload": {"fresh": True}}


def test_malformed_json_closes_the_connection():
    client = TestClient(app)
    with pytest.raises(Exception):
        with client.websocket_connect(url()) as ws:
            ws.send_text("{not json")
            ws.receive_json()


def test_an_unknown_message_type_closes_the_connection():
    client = TestClient(app)
    with pytest.raises(Exception):
        with client.websocket_connect(url()) as ws:
            ws.send_json({"type": "shutdown", "payload": {}})
            ws.receive_json()


def test_a_disconnect_frees_the_room():
    client = TestClient(app)
    with client.websocket_connect(url(token=token_for(user=1))):
        pass
    assert registry.room_count() == 0


def test_the_bad_message_close_code_is_distinct():
    assert CLOSE_BAD_MESSAGE not in (CLOSE_UNAUTHORIZED, CLOSE_ROOM_FULL)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/test_app.py -v`
Expected: FAIL — no `peer-joined` is ever sent.

- [ ] **Step 3: Implement presence and the relay**

In `backend/signaling/app.py`, replace `_relay_loop` and add the constant:

```python
import json

RELAYABLE = frozenset({"offer", "answer", "ice"})


async def _send_quietly(peer: WebSocket, message: dict) -> None:
    """Best-effort delivery to the other peer.

    A peer that has already gone away must not take this connection down with
    it: the disconnect handler will clean it up a moment later, and raising
    here would kill the surviving half of the call.
    """
    try:
        await peer.send_json(message)
    except Exception:  # noqa: BLE001 -- a dead socket is not this peer's problem
        return


async def _relay_loop(websocket: WebSocket, room_id: str, others: list) -> None:
    for peer in others:
        await _send_quietly(peer, {"type": "peer-joined"})
    if others:
        await websocket.send_json({"type": "peer-joined"})

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                message = json.loads(raw)
            except ValueError:
                await websocket.close(code=CLOSE_BAD_MESSAGE)
                return

            if not isinstance(message, dict) or message.get("type") not in RELAYABLE:
                # One client, ours. A frame we do not recognise is a bug or an
                # attack, never a version we should tolerate.
                await websocket.close(code=CLOSE_BAD_MESSAGE)
                return

            # To the OTHER peer only. Dropped, not queued, when nobody is there.
            for peer in registry.peers(room_id):
                if peer is not websocket:
                    await _send_quietly(peer, message)
    finally:
        for peer in registry.peers(room_id):
            if peer is not websocket:
                await _send_quietly(peer, {"type": "peer-left"})
```

- [ ] **Step 4: Run them and watch them pass**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/ -v`
Expected: all pass (Tasks 1–4 together).

- [ ] **Step 5: Commit**

```bash
git add signaling/app.py signaling/tests/test_app.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(signaling): relay offers, answers and ICE between two peers"
```

---

### Task 5: A health check that proves signing works

**Files:**
- Modify: `backend/signaling/app.py`
- Modify: `backend/signaling/tests/test_app.py` (append)

**Interfaces:**
- Consumes: `signaling.tokens.mint` / `verify` (Task 1).
- Produces: `GET /health/live/` → `200 {"status": "healthy"}`, or `503 {"status": "unhealthy"}` when the secret is missing or a self-minted token does not verify.

**Context:** ADR-0035 names this explicitly. A mismatched `DJANGO_SIGNALING_SECRET` between the Django container and the signaling container makes every join fail with a correct-looking token — a deployment failure mode that did not exist before this split. A health check that only reports "the port is open" would stay green through it, and the first person to find out would be a child in a lesson.

The check mints a token and verifies it. That proves the secret is present and the codec agrees with itself. It cannot prove the *other* container holds the same secret — say so in the comment rather than implying more assurance than it gives.

Path mirrors Django's `/health/live/` so the compose health check reads the same.

- [ ] **Step 1: Write the failing tests**

Append to `backend/signaling/tests/test_app.py`:

```python
def test_health_is_ok_when_the_secret_is_present():
    response = TestClient(app).get("/health/live/")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_health_fails_when_the_secret_is_missing(monkeypatch):
    """A missing secret must be red at deploy, not discovered by a student
    who cannot join their lesson."""
    monkeypatch.delenv("DJANGO_SIGNALING_SECRET", raising=False)
    assert TestClient(app).get("/health/live/").status_code == 503
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/test_app.py -k health -v`
Expected: FAIL — 404, there is no such route.

- [ ] **Step 3: Add the route**

In `backend/signaling/app.py`, add the imports and handler, and register the route:

```python
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

from signaling.tokens import RoomToken
from signaling.tokens import mint


async def health(request: Request) -> JSONResponse:
    """Prove the service can actually sign, not merely that the port is open.

    A mismatched DJANGO_SIGNALING_SECRET between this container and the API's
    makes every join fail with a correct-looking token -- a failure mode this
    split introduced. This catches a *missing* or unusable secret at deploy.
    It cannot prove the API holds the SAME secret; nothing here can, and the
    runbook says so.
    """
    try:
        probe = RoomToken(
            room_id="health", user_id=0, is_teacher=False, expires_at=2_000_000_000
        )
        secret = _secret()
        verify(mint(probe, secret), secret, now=0)
    except (RuntimeError, TokenError):
        return JSONResponse({"status": "unhealthy"}, status_code=503)
    return JSONResponse({"status": "healthy"})


app = Starlette(
    routes=[
        Route("/health/live/", health),
        WebSocketRoute("/ws/rooms/{room_id}", room_endpoint),
    ]
)
```

- [ ] **Step 4: Run them and watch them pass**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest signaling/tests/ -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add signaling/app.py signaling/tests/test_app.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(signaling): add a health check that verifies signing"
```

---

### Task 6: Boundary contract and coverage

**Files:**
- Modify: `backend/pyproject.toml`

**Interfaces:**
- Consumes: the `signaling` package (Tasks 1–5).
- Produces: an `import-linter` contract named `signaling imports nothing from kaleem`, and coverage that actually measures `signaling/`.

**Context — two traps, both easy to miss:**

1. **`[tool.importlinter] root_packages = ["kaleem"]`.** A contract about `signaling` does nothing until `signaling` is a root package too. Add it.
2. **`[tool.coverage.run] include = ["kaleem/**"]`.** As written, **every line of the new service is invisible to the coverage gate** — the floor would stay green with `signaling/` entirely untested. Add `signaling/**`, then re-measure and set the floor.

Measure with **`pytest --cov=kaleem --cov=signaling`**, and never a bare `pytest --cov`: the bare form falls back to the `include` filter and omits files nothing imports, which read ~0.55 high and set a false floor on the previous phase. CI's command must change to match — that is Task 9.

- [ ] **Step 1: Add the contract**

Append to `backend/pyproject.toml`, and change `root_packages`:

```toml
[tool.importlinter]
root_packages = ["kaleem", "signaling"]
```

```toml
[[tool.importlinter.contracts]]
name = "signaling imports nothing from kaleem"
type = "forbidden"
source_modules = ["signaling"]
# The whole point of ADR-0035: signaling is a separate service that shares an
# image, not a Django app. One Django import and it inherits settings, the ORM
# and a database connection it must not have. The arrow runs the other way --
# kaleem.scheduling imports signaling.tokens, which is allowed and deliberate.
forbidden_modules = [
    "kaleem.platform",
    "kaleem.identity",
    "kaleem.billing",
    "kaleem.scheduling",
    "kaleem.curriculum",
    "kaleem.assessment",
    "kaleem.content",
    "kaleem.messaging",
    "kaleem.notifications",
    "kaleem.engagement",
    "kaleem.analytics",
]
```

- [ ] **Step 2: Verify the contract by breaking it**

Add a probe import at the top of `backend/signaling/rooms.py`:

```python
from kaleem.platform.exceptions import KaleemError  # PROBE -- remove
```

Run: `docker compose -f docker-compose.local.yml exec -T django lint-imports`
Expected: **FAIL**, naming the `signaling imports nothing from kaleem` contract.

Now remove the probe line and re-run. Expected: 11 contracts kept, 0 broken.

Record both outputs in your report. A contract nobody has watched fail is not known to work — this project shipped one that never fired for months.

- [ ] **Step 3: Put `signaling` under coverage**

In `backend/pyproject.toml`:

```toml
[tool.coverage.run]
include = ["kaleem/**", "signaling/**"]
```

- [ ] **Step 4: Re-measure and set the floor**

```bash
docker compose -f docker-compose.local.yml exec -T django pytest --cov=kaleem --cov=signaling --cov-report=term-missing -q
```

Set `fail_under` to the achieved total **rounded down to one decimal**. It is currently 97.6.

⚠ **Leave `precision = 1` exactly as it is** — coverage.py rounds the total to that many decimals before comparing, and a fractional floor with precision 0 fails spuriously. The comment above it explains both this and the `--cov=` trap; do not delete either.

If the total came out **below** 97.6, do not lower the floor — that needs an ADR. Report BLOCKED with the uncovered lines.

- [ ] **Step 5: Run every gate**

```bash
docker compose -f docker-compose.local.yml exec -T django pytest --cov=kaleem --cov=signaling -q
docker compose -f docker-compose.local.yml exec -T django lint-imports
docker compose -f docker-compose.local.yml exec -T django ruff check .
docker compose -f docker-compose.local.yml exec -T django mypy kaleem config signaling
```
Expected: all green. `mypy` has one known pre-existing error in `config/settings/local.py`; anything new in `signaling/` is yours to fix.

- [ ] **Step 6: Commit**

```bash
git add pyproject.toml
PIP_CONFIG_FILE=/dev/null git commit -m "chore(backend): put signaling under the boundary and coverage gates"
```

---

### Task 7: The Django side — `SignalingProvider`

**Files:**
- Create: `backend/kaleem/scheduling/providers/signaling_provider.py`
- Modify: `backend/config/settings/base.py`
- Create: `backend/kaleem/scheduling/tests/test_signaling_provider.py`

**Interfaces:**
- Consumes: `signaling.tokens.RoomToken` / `mint` (Task 1); the `VideoProvider` Protocol, `RoomRequest`, `ProviderRoom`, `Participant`, `JoinGrant` from `kaleem.scheduling.providers` (shipped in C3a).
- Produces: `SignalingProvider` with `name = "signaling"`, plus settings `SIGNALING_SECRET` and `SIGNALING_URL`.

**Context:** Read `kaleem/scheduling/providers/fake_provider.py` first — this is its real sibling and must satisfy the same `VideoProvider` Protocol: `create_room`, `get_join_url`, `end_room`.

`FakeVideoProvider` stays the default in dev and CI (`DJANGO_VIDEO_PROVIDER`), so C3a's existing tests keep passing untouched. This provider is what staging and production select.

**This is the import that crosses the boundary in the allowed direction** — `kaleem.scheduling` importing `signaling.tokens`. The reverse is what Task 6's contract forbids.

The room id is the session id, prefixed. `end_room` has no caller anywhere (a known C3a gap in `ISSUES.md`) and stays a no-op here; a signaling room is process-local state that disappears when its peers leave, so there is nothing to release.

- [ ] **Step 1: Write the failing tests**

Create `backend/kaleem/scheduling/tests/test_signaling_provider.py`:

```python
import datetime as dt

import pytest
from django.test import override_settings
from django.utils import timezone

from kaleem.scheduling.providers import Participant
from kaleem.scheduling.providers import RoomRequest
from kaleem.scheduling.providers.signaling_provider import SignalingProvider
from signaling.tokens import verify

SECRET = "test-signaling-secret"


@pytest.fixture
def room_request():
    return RoomRequest(
        session_id=42,
        subject_name="Quran",
        starts_at=timezone.now(),
        duration_minutes=60,
    )


@override_settings(SIGNALING_SECRET=SECRET, SIGNALING_URL="wss://ws.example.test")
def test_the_room_id_is_derived_from_the_session(room_request):
    assert SignalingProvider().create_room(room_request).external_id == "session-42"


@override_settings(SIGNALING_SECRET=SECRET, SIGNALING_URL="wss://ws.example.test")
def test_the_join_url_carries_a_token_signaling_would_accept(room_request):
    provider = SignalingProvider()
    room = provider.create_room(room_request)
    expires_at = timezone.now() + dt.timedelta(minutes=30)

    grant = provider.get_join_url(
        room,
        Participant(user_id=7, display_name="Amina", is_teacher=False),
        expires_at=expires_at,
    )

    assert grant.join_url.startswith("wss://ws.example.test/ws/rooms/session-42?t=")
    token = verify(grant.join_url.split("t=")[1], SECRET, now=0)
    assert token.room_id == "session-42"
    assert token.user_id == 7
    assert token.is_teacher is False
    assert token.expires_at == int(expires_at.timestamp())


@override_settings(SIGNALING_SECRET=SECRET, SIGNALING_URL="wss://ws.example.test")
def test_two_participants_get_different_tokens(room_request):
    provider = SignalingProvider()
    room = provider.create_room(room_request)
    expires_at = timezone.now() + dt.timedelta(minutes=30)
    urls = {
        provider.get_join_url(
            room,
            Participant(user_id=uid, display_name="X", is_teacher=teacher),
            expires_at=expires_at,
        ).join_url
        for uid, teacher in ((7, False), (8, True))
    }
    assert len(urls) == 2


@override_settings(SIGNALING_SECRET=SECRET, SIGNALING_URL="wss://ws.example.test")
def test_the_join_url_carries_no_email(room_request):
    provider = SignalingProvider()
    room = provider.create_room(room_request)
    grant = provider.get_join_url(
        room,
        Participant(user_id=7, display_name="Amina", is_teacher=False),
        expires_at=timezone.now() + dt.timedelta(minutes=30),
    )
    assert "@" not in grant.join_url


@override_settings(SIGNALING_SECRET=SECRET, SIGNALING_URL="wss://ws.example.test")
def test_ending_a_room_is_a_no_op(room_request):
    """A signaling room is process-local state that vanishes with its peers;
    there is nothing to release."""
    provider = SignalingProvider()
    provider.end_room(provider.create_room(room_request))
```

- [ ] **Step 2: Run them and watch them fail**

Run: `docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling/tests/test_signaling_provider.py -v`
Expected: FAIL — `ModuleNotFoundError` for `signaling_provider`.

- [ ] **Step 3: Add the settings**

In `backend/config/settings/base.py`, next to the existing `VIDEO_PROVIDER` block:

```python
# The shared secret the API signs room tokens with and the signaling service
# verifies them with (ADR-0035). If the two containers disagree, every join
# fails authentication with a correct-looking token -- which is why signaling's
# health check mints and verifies a token rather than only opening a port.
SIGNALING_SECRET = env("DJANGO_SIGNALING_SECRET", default="")
# Public wss:// origin of the signaling service. Empty in dev, where
# FakeVideoProvider is the default and nothing dials out.
SIGNALING_URL = env("DJANGO_SIGNALING_URL", default="")
```

- [ ] **Step 4: Write the provider**

Create `backend/kaleem/scheduling/providers/signaling_provider.py`:

```python
"""The real video provider: hands out signed URLs to the signaling service.

This is the one import that crosses the ADR-0035 boundary, and it crosses it
in the allowed direction: kaleem imports `signaling.tokens`, never the reverse.
An import-linter contract enforces the other side of that arrow.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from django.conf import settings

from kaleem.scheduling.providers import JoinGrant
from kaleem.scheduling.providers import ProviderRoom
from signaling.tokens import RoomToken
from signaling.tokens import mint

if TYPE_CHECKING:
    import datetime as dt

    from kaleem.scheduling.providers import Participant
    from kaleem.scheduling.providers import RoomRequest


class SignalingProvider:
    name = "signaling"

    def create_room(self, request: RoomRequest) -> ProviderRoom:
        """No call out: a signaling room is created by the first peer to
        connect, so there is nothing to provision ahead of time."""
        return ProviderRoom(
            external_id=f"session-{request.session_id}", provider=self.name
        )

    def get_join_url(
        self, room: ProviderRoom, participant: Participant, *, expires_at: dt.datetime
    ) -> JoinGrant:
        token = mint(
            RoomToken(
                room_id=room.external_id,
                user_id=participant.user_id,
                is_teacher=participant.is_teacher,
                expires_at=int(expires_at.timestamp()),
            ),
            settings.SIGNALING_SECRET,
        )
        # The token is a query parameter because a browser cannot set headers
        # on a WebSocket handshake. Short-lived and single-room for exactly
        # that reason -- and signaling must not log query strings.
        base = settings.SIGNALING_URL.rstrip("/")
        return JoinGrant(
            join_url=f"{base}/ws/rooms/{room.external_id}?t={token}",
            expires_at=expires_at,
        )

    def end_room(self, room: ProviderRoom) -> None:
        """Nothing to release: the room is process-local state in the
        signaling service and disappears when its peers do."""
```

- [ ] **Step 5: Run them and watch them pass**

```bash
docker compose -f docker-compose.local.yml exec -T django pytest kaleem/scheduling -q
docker compose -f docker-compose.local.yml exec -T django lint-imports
```
Expected: the whole scheduling suite passes (C3a's authorization tests untouched), and 11 contracts kept / 0 broken.

- [ ] **Step 6: Commit**

```bash
git add kaleem/scheduling/providers/signaling_provider.py kaleem/scheduling/tests/test_signaling_provider.py config/settings/base.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(scheduling): mint real signaling join URLs"
```

---

### Task 8: Run it locally

**Files:**
- Modify: `docker-compose.local.yml` (**meta repo root**, not `backend/`)
- Modify: `backend/.env.example` if one exists; otherwise skip and note it in the report

**Interfaces:**
- Consumes: `signaling.app:app` (Tasks 3–5).
- Produces: a `signaling` service on `ws.kaleem.localhost`, and a documented `DJANGO_SIGNALING_SECRET` for local use.

**Context:** ⚠ **`docker-compose.local.yml` lives at the meta repo root**, so this task commits to the **meta** repo, not `backend`. Branch it `feat/phase-c3b-signaling` there too. **Never commit a `.env` file** — pre-commit blocks it and rule #11 forbids it.

Copy the shape of the existing `django` service: same build context and target, same bind mount, Traefik labels, `depends_on`. It needs **no** database and **no** Redis, so give it neither — a service that declares dependencies it does not use will wait on them at boot for no reason.

- [ ] **Step 1: Add the service**

In `docker-compose.local.yml`, after the `django` service:

```yaml
  # Signaling — its own service, same image, different command (ADR-0035).
  # No postgres, no redis: it has no database and no ORM by design.
  signaling:
    build:
      context: ./backend
      target: dev
      args: *uidgid
    command: uvicorn signaling.app:app --host 0.0.0.0 --port 9000 --reload
    volumes:
      - ./backend:/app
    ports:
      - "9000:9000"
    environment:
      # Local-only value. Production reads the real one from .env.production,
      # and it MUST match the API container's or every join fails auth with a
      # correct-looking token.
      - DJANGO_SIGNALING_SECRET=local-dev-signaling-secret
    labels:
      - traefik.enable=true
      - traefik.http.routers.signaling.rule=Host(`ws.kaleem.localhost`)
      - traefik.http.routers.signaling.entrypoints=web
      - traefik.http.services.signaling.loadbalancer.server.port=9000
```

- [ ] **Step 2: Bring it up and prove it answers**

```bash
docker compose -f docker-compose.local.yml up -d signaling
curl -s -o /dev/null -w '%{http_code}\n' http://ws.kaleem.localhost/health/live/
```
Expected: `200`.

- [ ] **Step 3: Prove the health check actually catches a bad secret**

Temporarily change `DJANGO_SIGNALING_SECRET` in the compose file to an empty string, `docker compose -f docker-compose.local.yml up -d signaling`, and curl again. Expected: **503**. Restore the value, bring it back up, confirm 200.

Record both in your report. This is the one check standing between a mismatched secret and a child unable to join a lesson; a health check nobody has watched go red is not known to work.

- [ ] **Step 4: Commit (meta repo)**

```bash
cd /home/abdulkhalek/Projects/kaleem
git add docker-compose.local.yml
git commit -m "feat(infra): run the signaling service locally"
```

---

### Task 9: CI

**Files:**
- Modify: `.github/workflows/ci.yml` (**meta repo**)

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: `backend-test` measuring `signaling` too, and `signaling`'s own tests running.

**Context:** `backend-test` runs `pytest --cov=kaleem --cov-report=term-missing -v`. Two things follow from Task 6:

1. The command must become `pytest --cov=kaleem --cov=signaling` or the new service's coverage is not measured in the gate that enforces the floor — the floor would pass with `signaling/` untested.
2. `pytest` already collects `signaling/tests/` because `python_files` matches `test_*.py` anywhere under the rootdir. Confirm it by reading the run's output for the signaling tests, rather than assuming.

The e2e job needs **no** change: C3b adds no user-facing behaviour and no Playwright flow (spec, Test plan). Do not add a signaling container to the e2e job — nothing there talks to it yet. C3d will.

- [ ] **Step 1: Update the coverage command**

In `.github/workflows/ci.yml`, in the `backend-test` job:

```yaml
      - name: Run tests with coverage
        # --cov=kaleem --cov=signaling: signaling is a separate service in the
        # same repo (ADR-0035) and must be inside the coverage gate, not beside
        # it. Never a bare `--cov`: it falls back to the `include` filter and
        # omits files no test imports, reading ~0.55 high -- which set a false
        # floor once already (see pyproject.toml).
        run: pytest --cov=kaleem --cov=signaling --cov-report=term-missing -v
```

- [ ] **Step 2: Verify the same command locally**

```bash
docker compose -f docker-compose.local.yml exec -T django pytest --cov=kaleem --cov=signaling --cov-report=term-missing -q
```
Expected: passes against the floor Task 6 set, and the output lists `signaling/` files.

- [ ] **Step 3: Commit (meta repo)**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: measure signaling inside the coverage gate"
```

---

### Task 10: Production deployment

**Files:**
- Modify: `infra/docker-compose.production.yml`
- Modify: `infra/scripts/ship.sh`
- Create: `docs/runbook/signaling.md` (**meta repo**)

**Interfaces:**
- Consumes: everything.
- Produces: `signaling-blue` / `signaling-green`, deployed and drained by `ship.sh`.

**Context:** `infra` is its own submodule — branch it `feat/phase-c3b-signaling` and commit there; the runbook is meta.

Read `infra/docker-compose.production.yml`'s `django-blue` and copy its shape: `profiles: [blue]`, the `${DEPLOY_SHA}` image, `env_file`, a healthcheck, Traefik labels. Then read `ship.sh` — the new pair must be added in **four** places, and missing any one leaves a half-deployed system:

1. step 5 starts the new colour (it uses `--profile "$NEW"`, so a profiled service is picked up automatically — verify, do not assume),
2. step 6's health check (add a signaling check alongside Django's),
3. the rollback block, which names services explicitly,
4. step 8's stop/rm of the old colour, which also names them explicitly.

The signaling service needs **no** postgres and **no** redis dependency, and **must not** run migrations.

- [ ] **Step 1: Add the production services**

In `infra/docker-compose.production.yml`, after `django-green`:

```yaml
  signaling-blue:
    profiles: [blue]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: uvicorn signaling.app:app --host 0.0.0.0 --port 9000
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
      - "traefik.http.routers.signaling-blue.rule=Host(`${WS_DOMAIN}`)"
      - "traefik.http.routers.signaling-blue.entrypoints=websecure"
      - "traefik.http.routers.signaling-blue.tls.certresolver=letsencrypt"
      - "traefik.http.services.signaling-blue.loadbalancer.server.port=9000"

  signaling-green:
    profiles: [green]
    image: ghcr.io/kaleem-lms/backend:${DEPLOY_SHA:-latest}
    command: uvicorn signaling.app:app --host 0.0.0.0 --port 9000
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
      - "traefik.http.routers.signaling-green.rule=Host(`${WS_DOMAIN}`)"
      - "traefik.http.routers.signaling-green.entrypoints=websecure"
      - "traefik.http.routers.signaling-green.tls.certresolver=letsencrypt"
      - "traefik.http.services.signaling-green.loadbalancer.server.port=9000"
```

- [ ] **Step 2: Teach `ship.sh` the new colour**

Add a signaling health check after the Django one:

```bash
# ─── 6b. Signaling health check ───────────────────────────────
# Mints and verifies a token, so a DJANGO_SIGNALING_SECRET that does not match
# the API's is red HERE rather than silent until a student cannot join.
echo "Checking signaling-${NEW}..."
SIGNALING_OK=false
for i in $(seq 1 $HEALTH_RETRIES); do
    if docker exec "kaleem-signaling-${NEW}-1" curl -sf http://localhost:9000/health/live/ > /dev/null 2>&1; then
        SIGNALING_OK=true
        break
    fi
    sleep $HEALTH_DELAY
done

if [ "$SIGNALING_OK" = false ]; then
    echo "ERROR: signaling health check failed. Rolling back."
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" stop \
        "django-${NEW}" "celery-worker-${NEW}" "celery-beat-${NEW}" "signaling-${NEW}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" rm -f \
        "django-${NEW}" "celery-worker-${NEW}" "celery-beat-${NEW}" "signaling-${NEW}"
    exit 1
fi
```

and add `"signaling-${NEW}"` to the existing Django-failure rollback lists, and `"signaling-${CURRENT}"` to step 8's `stop` and `rm` lists.

- [ ] **Step 3: Check the compose file parses**

```bash
cd /home/abdulkhalek/Projects/kaleem/infra
docker compose -f docker-compose.production.yml --profile blue config > /dev/null && echo "compose OK"
bash -n scripts/ship.sh && echo "ship.sh syntax OK"
```
Expected: both OK. (`config` may warn about unset `${WS_DOMAIN}` — that is expected without `.env.production`.)

- [ ] **Step 4: Write the runbook**

Create `docs/runbook/signaling.md` covering: what the service is and what it is not (no media passes through it); the two environment variables (`DJANGO_SIGNALING_SECRET`, `DJANGO_SIGNALING_URL`) and that **the secret must be identical in the API and signaling containers**; how to rotate it (both containers together, and every outstanding grant dies — so rotate between lessons); what each close code means; that it is **single-replica per colour** and why (two peers must land on the same process); and that `.env.production` is hand-managed on the VPS.

- [ ] **Step 5: Commit**

```bash
cd /home/abdulkhalek/Projects/kaleem/infra
git add docker-compose.production.yml scripts/ship.sh
git commit -m "feat(infra): deploy the signaling service blue/green"

cd /home/abdulkhalek/Projects/kaleem
git add docs/runbook/signaling.md
git commit -m "docs: runbook for the signaling service"
```

---

### Task 11: Ship it (D9)

**Files:**
- Modify: `STATE.md`, `ISSUES.md`, `CLAUDE.md`, `docs/superpowers/journal/2026-W36.md`
- Modify: `docs/superpowers/specs/2026-09-06-phase-c3b-signaling-design.md` (`status: shipped`)

**Context:** D9. Merge order is **backend → infra → meta**, and **the meta merge is a staging deploy** (ADR-0028).

⚠ **`.env.production` on the VPS is hand-managed.** `DJANGO_SIGNALING_SECRET`, `DJANGO_SIGNALING_URL` and `WS_DOMAIN` must exist there **before** the meta merge, or the deploy's signaling health check fails and rolls back. A DNS record for `WS_DOMAIN` must also exist for Traefik to get a certificate. Flag both to the human rather than assuming they are done.

- [ ] **Step 1: Run every gate from a clean state**

```bash
docker compose -f docker-compose.local.yml exec -T django pytest --cov=kaleem --cov=signaling -q
docker compose -f docker-compose.local.yml exec -T django lint-imports
docker compose -f docker-compose.local.yml exec -T django ruff check .
docker compose -f docker-compose.local.yml exec -T django mypy kaleem config signaling
cd dashboard && pnpm vitest run --coverage && pnpm exec playwright test --workers=1
```
Expected: all green; **e2e stays at 33** — C3b adds no flow, and claiming otherwise would be false.

- [ ] **Step 2: Prove the service works end to end by hand**

With the local stack up, connect a real WebSocket to `ws://ws.kaleem.localhost/ws/rooms/session-1?t=<token>` using a token minted with the local secret. Confirm: a valid token connects; a second connects and both see `peer-joined`; a message from one arrives at the other; a third is refused; closing one sends `peer-left` to the other. A short Python script using `websockets` is fine — it is throwaway, so do not commit it.

- [ ] **Step 3: Push and open the PRs**

```bash
git -C backend push -u origin feat/phase-c3b-signaling
git -C infra push -u origin feat/phase-c3b-signaling
```
Open a PR from each into `main`. State plainly what does **not** work yet: no browser code, no TURN, so **no call connects**.

- [ ] **Step 4: Meta docs and PR**

Bump all changed submodule pointers, close the spec, update `STATE.md`, add the new `lint-imports` count and the raised floor to **`CLAUDE.md`'s D3 tables** (and note the e2e table is unchanged, deliberately), append a journal entry, and log anything found to `ISSUES.md`. Open the meta PR.

- [ ] **Step 5: Merge in order once green**

backend → infra → meta. **The meta merge deploys to staging.** Afterwards confirm `deploy-staging` succeeded and that `https://<WS_DOMAIN>/health/live/` returns 200 — proving the deployed secret is usable, which is the whole reason that endpoint mints a token.

---

## Self-Review

**Spec coverage.** Token → Tasks 1 and 7. The protocol → Tasks 3–4. Two-peer cap → Task 2. Cleanup → Tasks 2 and 4. Health check → Task 5. Boundary contract, verified by breaking it → Task 6. Coverage of the new package → Task 6 and 9. Deployment → Tasks 8 and 10. Runbook → Task 10. D9 → Task 11. Decisions 1–7 all land in a task; decision 6 (nothing persisted) is satisfied by construction, since no task introduces a database.

**Deliberately not built, and why:** `end_room` still has no caller — the C3a gap logged in `ISSUES.md` stands, and a signaling room needs no teardown because it is process-local. No rate limit on relayed messages (OQ-C3b-2): one client, two peers, a short-lived token, and C3d will show the real volume. No reconnection semantics (OQ-C3b-1): a fresh connection with a valid token already works, and whether it should *feel* seamless is a client question.

**Type consistency.** `RoomToken(room_id, user_id, is_teacher, expires_at)`, `mint(token, secret)`, `verify(raw, secret, *, now)` and `TokenError` are identical in Tasks 1, 3, 5 and 7. `RoomRegistry.join/leave/peers/room_count`, `RoomFull` and `MAX_PEERS` match between Tasks 2, 3 and 4. `CLOSE_UNAUTHORIZED` / `CLOSE_ROOM_FULL` / `CLOSE_BAD_MESSAGE` are defined in Task 3 and reused in Tasks 3–4. `SignalingProvider` satisfies the same `VideoProvider` Protocol `FakeVideoProvider` does, so the C3a seam is untouched.

**Known hazards named for the executor:** Task 3 adds dependencies and **requires an image rebuild** before its tests can pass. Task 6 changes `root_packages` — a contract on `signaling` silently does nothing without it — and adds `signaling/**` to coverage, without which the whole service is invisible to the gate that guards it. Task 8 commits to the **meta** repo and Task 10 to **infra**, not `backend`. Task 11 depends on VPS environment variables and a DNS record that no task can create.
