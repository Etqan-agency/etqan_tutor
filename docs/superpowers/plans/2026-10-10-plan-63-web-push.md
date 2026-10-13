# Plan 63 — B11b web push — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** B11b (phase B11, last slice). **Requires:** B11a (whole plan; `etqan.devices`, `sw.js`, `features/apps`);
R12 (delegated to B11 by D70; built in Task 4 Step 0 on a trunk with B5c merged). Tasks 1–3 and 5 do not need R12.

**Goal:** Each new in-app notification reaches the recipient's devices as a system notification when they turned
push on for that device; tapping it opens `/app/notifications`.

**Architecture:** `etqan.devices` gains two tables (browser subscriptions; already-pushed notification ids), an
authenticated subscribe/unsubscribe API restricted to known push-service hosts, VAPID keys read through
`etqan.platform.secrets` (a dev pair derived from `SECRET_KEY` in local/test), and a per-academy Celery task that
reads the last 60 minutes of notifications through `notifications.services.created_since` (R12), dedupes, encrypts
each payload with `http-ece` and POSTs it with `httpx`. The dashboard's service worker shows the pushes; an account
card turns push on/off per device; sign-out unsubscribes the browser.

**Tech Stack:** Django 5, DRF, Celery, httpx, PyJWT (ES256), cryptography, http-ece; React 19, vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-10-10-b11b-web-push-design.md` (P-1…P-13, §3–§5); phase spec
`docs/superpowers/specs/2026-10-09-b11-apps-design.md`. Read both.

## Global Constraints

- Switch `push_notifications`: "Push notifications" / "الإشعارات الفورية", group `communication`, `built=True`,
  `default=False`, `requires=("installable_app",)`, under `# ── phase B11 ──` in the registry (after `installable_app`).
- Shared lists: only under `── phase B11 ──` markers. Single-file shared lists without markers (`requirements/base.txt`,
  `CELERY_BEAT_SCHEDULE`, settings files): one appended block with a `# B11b` comment.
- Push hosts allowed (exact host or dot-suffix): `fcm.googleapis.com`, `push.services.mozilla.com`,
  `notify.windows.com`, `push.apple.com`. `https` only, no userinfo, no explicit port, endpoint ≤ 1000 chars.
  `p256dh` decodes (base64url, padding optional) to 65 bytes, `auth` to 16.
- Window 60 minutes; page size 200; per-run send deadline 40 s; task `soft_time_limit` 50, `time_limit` 55; beat every
  minute, `expires` 55; lock key `devices:push:lock` timeout 60; PushedNote pruned after 2 hours; payload ≤ 1024 bytes
  UTF-8; TTL 3600; HTTP timeout 10 s; `follow_redirects=False`; max 10 subscriptions per user.
- Outcomes: 201/202 success; 400/401/403/404/410/413 delete the row; anything else keep. Never log an endpoint.
- Settings: `WEB_PUSH_VAPID_PUBLIC_KEY`, `WEB_PUSH_VAPID_PRIVATE_KEY_ENC` (Fernet token via `platform.secrets`),
  `WEB_PUSH_VAPID_SUBJECT`, `WEB_PUSH_VAPID_FROM_SECRET_KEY` (True only in local/test).
- Every test and check runs in this stream's containers via `just` (loads `.env.stream`), one command per
  invocation (`just` splits quoted `sh -c` strings): backend
  `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django pytest <paths> -q`;
  dashboard `just _compose run --rm dashboard pnpm vitest run <paths>`; `just check-boundaries`. Never call
  `docker compose` directly, never `manage.py`/migrations outside `just`, never the full suite before the
  conductor's full window. Migrations are generated with
  `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django python manage.py makemigrations devices`.
- Adding `http-ece` needs the django image rebuilt (`just _compose build django`) — the orchestrator does it.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. TDD throughout.

## Review Focus

1. **A notification committed late (its id lower than rows already pushed)** — must still be pushed once (window +
   PushedNote, not an id cursor). Pinned in Task 4.
2. **An endpoint on an internal host, an IP, a port or `http`** — refused at POST and again before sending. Pinned in
   Tasks 2 and 4.
3. **The run dies mid-way** — rows recorded before the failure are not re-sent; the rest go next run. Pinned in Task 4.
4. **A device subscribed after a notification was created** — never receives it. Pinned in Task 4.
5. **Sign-out while impersonating** — must not unsubscribe the admin's browser or call DELETE. Pinned in Task 5.

---

### Task 1: Switch, VAPID keys and the VAPID header

**Files:**
- Create: `backend/etqan/devices/push_keys.py`, `backend/etqan/devices/management/__init__.py`,
  `backend/etqan/devices/management/commands/__init__.py`,
  `backend/etqan/devices/management/commands/make_vapid_keys.py`, `backend/etqan/devices/tests/test_push_keys.py`
- Modify: `backend/etqan/platform/features.py` (B11 marker), `backend/etqan/platform/tests/test_features.py` (B11 marker
  in the pinned BUILT dict, as B11a did), `backend/config/settings/base.py`, `local.py`, `test.py`,
  `production.py` (appended `# B11b` blocks), `backend/requirements/base.txt` (`# B11b: web push payload encryption
  (RFC 8291).` then `http-ece>=1.2`)

**Interfaces:**
- Produces `etqan.devices.push_keys`: `NOT_SET_UP` (exception class), `public_key() -> str` (base64url, no padding,
  65-byte uncompressed point), `private_key() -> ec.EllipticCurvePrivateKey`, `subject() -> str`,
  `configured() -> bool`, `vapid_authorization(endpoint: str, *, now: datetime | None = None) -> str`
  (the `Authorization` header value `vapid t=<jwt>, k=<public key>`), `b64url_decode(value: str) -> bytes`,
  `b64url_encode(raw: bytes) -> str`.
- Produces switch code `push_notifications`.

- [ ] **Step 1: Write the failing tests** (`test_push_keys.py`)

```python
import base64

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from django.core.management import call_command

from etqan.devices import push_keys
from etqan.platform import features
from etqan.platform import secrets


def test_switch_registered():
    feature = features.get("push_notifications")
    assert (feature.group, feature.built, feature.default) == ("communication", True, False)
    assert feature.requires == ("installable_app",)


def test_dev_pair_from_secret_key_is_stable(settings):
    settings.WEB_PUSH_VAPID_PUBLIC_KEY = ""
    settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC = ""
    settings.WEB_PUSH_VAPID_FROM_SECRET_KEY = True
    first = push_keys.public_key()
    assert first == push_keys.public_key()
    assert len(push_keys.b64url_decode(first)) == 65
    assert push_keys.configured()


def test_not_configured_without_keys(settings):
    settings.WEB_PUSH_VAPID_PUBLIC_KEY = ""
    settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC = ""
    settings.WEB_PUSH_VAPID_FROM_SECRET_KEY = False
    assert not push_keys.configured()
    with pytest.raises(push_keys.NOT_SET_UP):
        push_keys.public_key()


def test_env_keys_through_platform_secrets(settings):
    key = ec.generate_private_key(ec.SECP256R1())
    raw = key.private_numbers().private_value.to_bytes(32, "big")
    settings.WEB_PUSH_VAPID_FROM_SECRET_KEY = False
    settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC = secrets.encrypt(push_keys.b64url_encode(raw))
    settings.WEB_PUSH_VAPID_PUBLIC_KEY = push_keys.b64url_encode(
        key.public_key().public_bytes(push_keys.X962, push_keys.UNCOMPRESSED)
    )
    settings.WEB_PUSH_VAPID_SUBJECT = "mailto:ops@etqan.app"
    assert push_keys.configured()
    assert push_keys.private_key().private_numbers().private_value == key.private_numbers().private_value


def test_undecryptable_private_key_is_not_set_up(settings):
    settings.WEB_PUSH_VAPID_FROM_SECRET_KEY = False
    settings.WEB_PUSH_VAPID_PUBLIC_KEY = "x"
    settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC = "not-a-token"
    settings.WEB_PUSH_VAPID_SUBJECT = "mailto:ops@etqan.app"
    assert not push_keys.configured()


def test_missing_subject_is_not_set_up(settings):
    settings.WEB_PUSH_VAPID_FROM_SECRET_KEY = True
    settings.WEB_PUSH_VAPID_SUBJECT = ""
    assert not push_keys.configured()


def test_vapid_authorization_verifies(settings):
    settings.WEB_PUSH_VAPID_FROM_SECRET_KEY = True
    settings.WEB_PUSH_VAPID_PUBLIC_KEY = ""
    settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC = ""
    settings.WEB_PUSH_VAPID_SUBJECT = "mailto:ops@etqan.app"
    header = push_keys.vapid_authorization("https://fcm.googleapis.com/fcm/send/abc")
    assert header.startswith("vapid t=")
    token = header.split("t=", 1)[1].split(",", 1)[0]
    k = header.split("k=", 1)[1]
    assert k == push_keys.public_key()
    claims = jwt.decode(
        token,
        push_keys.private_key().public_key(),
        algorithms=["ES256"],
        audience="https://fcm.googleapis.com",
    )
    assert claims["sub"] == "mailto:ops@etqan.app"
    assert claims["exp"] - claims.get("iat", claims["exp"] - 43200) <= 43200


def test_make_vapid_keys_prints_usable_pair(capsys, settings):
    call_command("make_vapid_keys")
    out = capsys.readouterr().out
    lines = dict(line.split("=", 1) for line in out.strip().splitlines() if "=" in line)
    assert len(push_keys.b64url_decode(lines["WEB_PUSH_VAPID_PUBLIC_KEY"])) == 65
    raw = secrets.decrypt(lines["WEB_PUSH_VAPID_PRIVATE_KEY_ENC"])
    assert len(base64.urlsafe_b64decode(raw + "==")) == 32
```

(Adjust `features.get` to the registry's real lookup — `features.BY_CODE[...]` if there is no `get`.)

- [ ] **Step 2: Run to verify they fail** — `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django pytest etqan/devices/tests/test_push_keys.py -q` → FAIL (ImportError).

- [ ] **Step 3: Implement**

Settings, `base.py` (append at the end of the file):

```python
# B11b (spec 2026-10-10-b11b P-6): web push. The private key is a Fernet token
# made with etqan.platform.secrets.encrypt; local/test derive a dev pair from
# SECRET_KEY when none is given.
WEB_PUSH_VAPID_PUBLIC_KEY = env("WEB_PUSH_VAPID_PUBLIC_KEY", default="")
WEB_PUSH_VAPID_PRIVATE_KEY_ENC = env("WEB_PUSH_VAPID_PRIVATE_KEY_ENC", default="")
WEB_PUSH_VAPID_SUBJECT = env("WEB_PUSH_VAPID_SUBJECT", default="")
WEB_PUSH_VAPID_FROM_SECRET_KEY = False
```

`local.py` and `test.py` (append): `# B11b: a dev VAPID pair from SECRET_KEY when the env gives none.` then
`WEB_PUSH_VAPID_FROM_SECRET_KEY = True` and
`WEB_PUSH_VAPID_SUBJECT = WEB_PUSH_VAPID_SUBJECT or "mailto:dev@etqan.localhost"` (import the base value as those files
already do for other names; if they use `from .base import *`, the name is in scope).
`production.py` (append): no default subject — `WEB_PUSH_VAPID_SUBJECT = env("WEB_PUSH_VAPID_SUBJECT", default="")`
with a comment that push stays "not set up" until it is set.

`backend/etqan/devices/push_keys.py`:

```python
"""Web push VAPID keys (B11b P-6, RFC 8292). The private key is a secret: it is
read only through etqan.platform.secrets. Local and test settings derive a
stable development pair from SECRET_KEY so every dev stack can push."""

import base64
import hashlib
from datetime import UTC
from datetime import datetime
from datetime import timedelta
from urllib.parse import urlsplit

import jwt
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding
from cryptography.hazmat.primitives.serialization import PublicFormat
from django.conf import settings

from etqan.platform import secrets
from etqan.platform.exceptions import EtqanError

X962 = Encoding.X962
UNCOMPRESSED = PublicFormat.UncompressedPoint
JWT_LIFETIME = timedelta(hours=12)
# The order of the P-256 group: a derived scalar must fall in [1, n - 1].
P256_ORDER = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551


class NOT_SET_UP(Exception):  # noqa: N801, N818 -- reads as a state in callers
    """No usable key pair or subject: push is "not set up"."""


def b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def b64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _dev_key() -> ec.EllipticCurvePrivateKey:
    digest = hashlib.sha256(f"{settings.SECRET_KEY}:web-push-vapid".encode()).digest()
    scalar = int.from_bytes(digest, "big") % (P256_ORDER - 1) + 1
    return ec.derive_private_key(scalar, ec.SECP256R1())


def private_key() -> ec.EllipticCurvePrivateKey:
    token = settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC
    if not token:
        if settings.WEB_PUSH_VAPID_FROM_SECRET_KEY:
            return _dev_key()
        raise NOT_SET_UP
    try:
        raw = b64url_decode(secrets.decrypt(token))
        return ec.derive_private_key(int.from_bytes(raw, "big"), ec.SECP256R1())
    except (EtqanError, ValueError) as error:
        raise NOT_SET_UP from error


def public_key() -> str:
    configured_key = settings.WEB_PUSH_VAPID_PUBLIC_KEY
    if configured_key and settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC:
        return configured_key
    return b64url_encode(private_key().public_key().public_bytes(X962, UNCOMPRESSED))


def subject() -> str:
    value = settings.WEB_PUSH_VAPID_SUBJECT
    if not value.startswith(("mailto:", "https://")):
        raise NOT_SET_UP
    return value


def configured() -> bool:
    try:
        private_key()
        public_key()
        subject()
    except NOT_SET_UP:
        return False
    return True


def vapid_authorization(endpoint: str, *, now: datetime | None = None) -> str:
    parts = urlsplit(endpoint)
    issued = now or datetime.now(UTC)
    token = jwt.encode(
        {
            "aud": f"{parts.scheme}://{parts.netloc}",
            "exp": int((issued + JWT_LIFETIME).timestamp()),
            "sub": subject(),
        },
        private_key(),
        algorithm="ES256",
    )
    return f"vapid t={token}, k={public_key()}"
```

Check `secrets.decrypt`'s failure type (`backend/etqan/platform/secrets.py`: it raises `UnavailableError`, an
`EtqanError`, on a bad token or missing key) and catch exactly what it raises.

`make_vapid_keys.py`:

```python
from cryptography.hazmat.primitives.asymmetric import ec
from django.core.management.base import BaseCommand

from etqan.devices import push_keys
from etqan.platform import secrets


class Command(BaseCommand):
    help = "Print a new web push VAPID key pair for the environment (B11b P-6)."

    def handle(self, *args, **options):
        key = ec.generate_private_key(ec.SECP256R1())
        raw = key.private_numbers().private_value.to_bytes(32, "big")
        public = key.public_key().public_bytes(push_keys.X962, push_keys.UNCOMPRESSED)
        self.stdout.write(f"WEB_PUSH_VAPID_PUBLIC_KEY={push_keys.b64url_encode(public)}")
        self.stdout.write(
            f"WEB_PUSH_VAPID_PRIVATE_KEY_ENC={secrets.encrypt(push_keys.b64url_encode(raw))}"
        )
```

Registry line under `# ── phase B11 ──` after `installable_app`:

```python
    # B11b
    Feature(
        "push_notifications",
        "Push notifications",
        "الإشعارات الفورية",
        "communication",
        built=True,
        default=False,
        requires=("installable_app",),
    ),
```

`requirements/base.txt` (append): `# B11b: web push payload encryption (RFC 8291).` / `http-ece>=1.2`. The orchestrator
rebuilds the django image before Task 4 needs it (Task 1 does not import `http_ece`).

- [ ] **Step 4: Run to verify they pass** — same command plus `etqan/platform/tests/test_features.py`; then
  `just check-boundaries`. Expected PASS.

- [ ] **Step 5: Commit** — backend: `feat(devices): push_notifications switch and VAPID keys (B11b)`.

---

### Task 2: Subscriptions — models, validation and API

**Files:**
- Create: `backend/etqan/devices/models.py`, `backend/etqan/devices/migrations/0001_initial.py` (generated),
  `backend/etqan/devices/migrations/__init__.py`, `backend/etqan/devices/push_hosts.py`,
  `backend/etqan/devices/user_agents.py`, `backend/etqan/devices/subscriptions.py`,
  `backend/etqan/devices/api/push_views.py`, `backend/etqan/devices/api/push_serializers.py`,
  `backend/etqan/devices/tests/test_push_hosts.py`, `backend/etqan/devices/tests/test_user_agents.py`,
  `backend/etqan/devices/tests/test_push_api.py`
- Modify: `backend/etqan/devices/api/urls.py`, `backend/etqan/devices/services.py` (re-export the subscription
  services other code needs: none outside the app — keep them in `subscriptions.py`)

**Interfaces:**
- Consumes: Task 1 `push_keys.configured()`, `push_keys.public_key()`, `push_keys.b64url_decode`; B11a
  `services.require_on()` pattern.
- Produces models `PushSubscription(user, endpoint, p256dh, auth, key_id, label, created_at, last_success_at)`
  (`Meta.ordering = ["-created_at", "-id"]`) and `PushedNote(notification_id BigIntegerField unique, created_at
  DateTimeField default now)`; `push_hosts.allowed(endpoint: str) -> bool`; `user_agents.label(user_agent: str) -> str`;
  `subscriptions.subscribe(user, *, endpoint, p256dh, auth, user_agent) -> tuple[PushSubscription, bool]` (created?),
  `subscriptions.unsubscribe(user, *, endpoint) -> None`, `subscriptions.of(user) -> QuerySet`, `MAX_PER_USER = 10`,
  `PUSH_SWITCH = "push_notifications"`.
- Routes (under `/api/v1/devices/`): `push/key/` (`devices:push-key`), `push/subscriptions/` (`devices:push-subscriptions`).

- [ ] **Step 1: Write the failing tests**

`test_push_hosts.py`:

```python
import pytest

from etqan.devices.push_hosts import allowed


@pytest.mark.parametrize(
    "endpoint",
    [
        "https://fcm.googleapis.com/fcm/send/abc",
        "https://updates.push.services.mozilla.com/wpush/v2/abc",
        "https://wns2-par02p.notify.windows.com/w/?token=abc",
        "https://web.push.apple.com/QGx",
    ],
)
def test_known_push_services(endpoint):
    assert allowed(endpoint)


@pytest.mark.parametrize(
    "endpoint",
    [
        "http://fcm.googleapis.com/fcm/send/abc",
        "https://fcm.googleapis.com:8443/fcm/send/abc",
        "https://user:pw@fcm.googleapis.com/x",
        "https://evilfcm.googleapis.com.attacker.net/x",
        "https://notpush.apple.com/x",
        "https://169.254.169.254/latest/meta-data",
        "https://127.0.0.1/x",
        "https://localhost/x",
        "https://django:8000/x",
        "fcm.googleapis.com/x",
        "https://fcm.googleapis.com/" + "a" * 1000,
    ],
)
def test_everything_else_refused(endpoint):
    assert not allowed(endpoint)
```

`test_user_agents.py`:

```python
import pytest

from etqan.devices.user_agents import label

CHROME_ANDROID = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36"
SAFARI_IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
EDGE_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36 Edg/129.0"
FIREFOX_LINUX = "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0"
SAFARI_MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"


@pytest.mark.parametrize(
    ("ua", "expected"),
    [
        (CHROME_ANDROID, "Chrome on Android"),
        (SAFARI_IPHONE, "Safari on iOS"),
        (EDGE_WINDOWS, "Edge on Windows"),
        (FIREFOX_LINUX, "Firefox on Linux"),
        (SAFARI_MAC, "Safari on macOS"),
        ("", "Browser"),
        ("curl/8.0", "Browser"),
    ],
)
def test_label(ua, expected):
    assert label(ua) == expected


def test_label_is_capped():
    assert len(label("x" * 500)) <= 80
```

`test_push_api.py` (use the root conftest's `api_for` fixture for signed-in clients — read `backend/conftest.py`
`api_for(role=...)`; for impersonation read how `etqan/platform/tests/test_impersonation_helpers.py` or identity tests
set an impersonated session and reuse that helper):

```python
import base64

import pytest
from rest_framework.test import APIClient

from etqan.devices.models import PushSubscription
from etqan.devices.subscriptions import MAX_PER_USER

KEY = "/api/v1/devices/push/key/"
SUBS = "/api/v1/devices/push/subscriptions/"
P256DH = base64.urlsafe_b64encode(b"\x04" + b"\x01" * 64).rstrip(b"=").decode()
AUTH = base64.urlsafe_b64encode(b"\x02" * 16).rstrip(b"=").decode()


def body(endpoint="https://fcm.googleapis.com/fcm/send/abc", p256dh=P256DH, auth=AUTH):
    return {"endpoint": endpoint, "keys": {"p256dh": p256dh, "auth": auth}}


@pytest.fixture
def on(set_features):
    set_features(installable_app=True, push_notifications=True)


@pytest.mark.django_db
def test_key_needs_sign_in_and_switch(api_for, set_features):
    assert APIClient().get(KEY).status_code in (401, 403)
    set_features(installable_app=True, push_notifications=False)
    assert api_for("student").get(KEY).status_code == 404


@pytest.mark.django_db
def test_key_returns_public_key(api_for, on):
    resp = api_for("student").get(KEY)
    assert resp.status_code == 200
    assert len(base64.urlsafe_b64decode(resp.json()["public_key"] + "==")) == 65


@pytest.mark.django_db
def test_key_404_when_not_set_up(api_for, on, settings):
    settings.WEB_PUSH_VAPID_FROM_SECRET_KEY = False
    settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC = ""
    assert api_for("student").get(KEY).status_code == 404


@pytest.mark.django_db
def test_subscribe_upsert_and_list_without_endpoints(api_for, on):
    client = api_for("teacher")
    first = client.post(SUBS, body(), format="json", HTTP_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0")
    assert first.status_code == 201
    again = client.post(SUBS, body(), format="json")
    assert again.status_code == 200
    rows = client.get(SUBS).json()
    assert len(rows) == 1
    assert set(rows[0]) == {"id", "label", "created_at", "last_success_at"}
    assert rows[0]["label"] == "Firefox on Linux"


@pytest.mark.django_db
def test_second_user_takes_the_endpoint_over(api_for, on):
    api_for("teacher").post(SUBS, body(), format="json")
    api_for("student").post(SUBS, body(), format="json")
    assert PushSubscription.objects.count() == 1
    assert PushSubscription.objects.get().user.role == "student"


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("payload", "field"),
    [
        (body(endpoint="https://127.0.0.1/x"), "endpoint"),
        (body(endpoint="http://fcm.googleapis.com/x"), "endpoint"),
        (body(p256dh="AAAA"), "p256dh"),
        (body(auth="AAAA"), "auth"),
        (body(p256dh="***"), "p256dh"),
    ],
)
def test_validation(api_for, on, payload, field):
    resp = api_for("student").post(SUBS, payload, format="json")
    assert resp.status_code == 400
    assert field in str(resp.json())


@pytest.mark.django_db
def test_post_404_when_off(api_for, set_features):
    set_features(installable_app=True, push_notifications=False)
    assert api_for("student").post(SUBS, body(), format="json").status_code == 404


@pytest.mark.django_db
def test_delete_own_and_works_when_off(api_for, on, set_features):
    client = api_for("student")
    client.post(SUBS, body(), format="json")
    set_features(installable_app=True, push_notifications=False)
    assert client.delete(SUBS, {"endpoint": body()["endpoint"]}, format="json").status_code == 204
    assert PushSubscription.objects.count() == 0
    assert client.delete(SUBS, {"endpoint": body()["endpoint"]}, format="json").status_code == 204


@pytest.mark.django_db
def test_delete_cannot_remove_someone_elses(api_for, on):
    api_for("teacher").post(SUBS, body(), format="json")
    api_for("student").delete(SUBS, {"endpoint": body()["endpoint"]}, format="json")
    assert PushSubscription.objects.count() == 1


@pytest.mark.django_db
def test_cap_replaces_least_recently_delivered(api_for, on):
    client = api_for("student")
    for i in range(MAX_PER_USER + 1):
        client.post(SUBS, body(endpoint=f"https://fcm.googleapis.com/fcm/send/{i}"), format="json")
    endpoints = set(PushSubscription.objects.values_list("endpoint", flat=True))
    assert len(endpoints) == MAX_PER_USER
    assert "https://fcm.googleapis.com/fcm/send/10" in endpoints
    assert "https://fcm.googleapis.com/fcm/send/0" not in endpoints


@pytest.mark.django_db
def test_impersonated_post_and_delete_refused(on, impersonated_client):
    # impersonated_client: write this fixture in the test module from the
    # existing impersonation test helpers (an admin signed in as a student).
    assert impersonated_client.post(SUBS, body(), format="json").status_code == 403
    assert impersonated_client.delete(SUBS, {"endpoint": body()["endpoint"]}, format="json").status_code == 403
```

- [ ] **Step 2: Run to verify they fail** — the backend pytest command on the three new files → FAIL.

- [ ] **Step 3: Implement**

`push_hosts.py`:

```python
"""Which URLs the push sender may call (B11b P-7): only the browser vendors'
push services, so a signed-in user cannot make the server POST elsewhere."""

from urllib.parse import urlsplit

SUFFIXES = (
    "fcm.googleapis.com",
    "push.services.mozilla.com",
    "notify.windows.com",
    "push.apple.com",
)
MAX_LENGTH = 1000


def allowed(endpoint: str) -> bool:
    if not isinstance(endpoint, str) or len(endpoint) > MAX_LENGTH:
        return False
    try:
        parts = urlsplit(endpoint)
        port = parts.port
    except ValueError:
        return False
    if parts.scheme != "https" or port is not None or parts.username or parts.password:
        return False
    host = (parts.hostname or "").lower()
    return any(host == suffix or host.endswith(f".{suffix}") for suffix in SUFFIXES)
```

`user_agents.py`:

```python
"""A short "<browser> on <OS>" label for a push subscription (B11b P-2)."""

import re

BROWSERS = (
    ("Edge", re.compile(r"Edg(e|A|iOS)?/")),
    ("Opera", re.compile(r"OPR/")),
    ("Firefox", re.compile(r"Firefox/|FxiOS/")),
    ("Chrome", re.compile(r"Chrome/|CriOS/")),
    ("Safari", re.compile(r"Version/[\d.]+.*Safari/")),
)
SYSTEMS = (
    ("iOS", re.compile(r"iPhone|iPad|iPod")),
    ("Android", re.compile(r"Android")),
    ("Windows", re.compile(r"Windows")),
    ("macOS", re.compile(r"Macintosh|Mac OS X")),
    ("ChromeOS", re.compile(r"CrOS")),
    ("Linux", re.compile(r"Linux|X11")),
)
MAX = 80


def _first(table, value: str) -> str:
    return next((name for name, pattern in table if pattern.search(value)), "")


def label(user_agent: str) -> str:
    browser = _first(BROWSERS, user_agent or "")
    system = _first(SYSTEMS, user_agent or "")
    if browser and system:
        text = f"{browser} on {system}"
    else:
        text = browser or system or "Browser"
    return text[:MAX]
```

`models.py`:

```python
from django.conf import settings
from django.db import models
from django.utils import timezone


class PushSubscription(models.Model):
    """One browser's push subscription (B11b P-2). The endpoint is a secret
    capability: no API returns it and nothing logs it."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+"
    )
    endpoint = models.URLField(max_length=1000, unique=True)
    p256dh = models.CharField(max_length=100)
    auth = models.CharField(max_length=30)
    # The first 16 characters of the VAPID public key it was made with.
    key_id = models.CharField(max_length=16)
    label = models.CharField(max_length=80)
    created_at = models.DateTimeField(default=timezone.now)
    last_success_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at", "-id"]


class PushedNote(models.Model):
    """A notification already pushed (B11b P-4): the dedupe record that
    replaces an id cursor. Pruned after two hours."""

    notification_id = models.BigIntegerField(unique=True)
    created_at = models.DateTimeField(default=timezone.now)
```

`subscriptions.py`:

```python
"""Subscribe and unsubscribe browsers (B11b P-2, P-9)."""

from django.db import transaction
from django.db.models import F

from etqan.devices import push_keys
from etqan.devices import user_agents
from etqan.devices.models import PushSubscription

PUSH_SWITCH = "push_notifications"
MAX_PER_USER = 10


@transaction.atomic
def subscribe(user, *, endpoint, p256dh, auth, user_agent) -> tuple[PushSubscription, bool]:
    row, created = PushSubscription.objects.select_for_update().update_or_create(
        endpoint=endpoint,
        defaults={
            "user": user,
            "p256dh": p256dh,
            "auth": auth,
            "key_id": push_keys.public_key()[:16],
            "label": user_agents.label(user_agent),
        },
    )
    extra = (
        PushSubscription.objects.filter(user=user)
        .exclude(pk=row.pk)
        .order_by(F("last_success_at").asc(nulls_first=True), "created_at")
    )
    surplus = extra.count() - (MAX_PER_USER - 1)
    if surplus > 0:
        PushSubscription.objects.filter(pk__in=list(extra.values_list("pk", flat=True)[:surplus])).delete()
    return row, created


def unsubscribe(user, *, endpoint) -> None:
    PushSubscription.objects.filter(user=user, endpoint=endpoint).delete()


def of(user):
    return PushSubscription.objects.filter(user=user)
```

`api/push_serializers.py`:

```python
import binascii

from rest_framework import serializers

from etqan.devices import push_hosts
from etqan.devices.push_keys import b64url_decode


def _decoded_length(value: str, size: int, field: str) -> str:
    try:
        raw = b64url_decode(value)
    except (binascii.Error, ValueError) as error:
        raise serializers.ValidationError({field: "Not base64url."}) from error
    if len(raw) != size:
        raise serializers.ValidationError({field: f"Must decode to {size} bytes."})
    return value


class KeysSerializer(serializers.Serializer):
    p256dh = serializers.CharField(max_length=100)
    auth = serializers.CharField(max_length=30)

    def validate_p256dh(self, value):
        return _decoded_length(value, 65, "p256dh")

    def validate_auth(self, value):
        return _decoded_length(value, 16, "auth")


class SubscribeSerializer(serializers.Serializer):
    endpoint = serializers.CharField(max_length=1000)
    keys = KeysSerializer()

    def validate_endpoint(self, value):
        if not push_hosts.allowed(value):
            raise serializers.ValidationError("Not a supported push service.")
        return value


class UnsubscribeSerializer(serializers.Serializer):
    endpoint = serializers.CharField(max_length=1000)


class SubscriptionRowSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    label = serializers.CharField()
    created_at = serializers.DateTimeField()
    last_success_at = serializers.DateTimeField(allow_null=True)
```

The repo maps DRF validation errors to its own `validation_error` body — check `etqan/platform` exception handler
output for nested `keys.p256dh` and make the test's `field in str(resp.json())` hold; if nested keys come back as
`keys.p256dh`, that satisfies it.

`api/push_views.py`:

```python
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.devices import push_keys
from etqan.devices import subscriptions
from etqan.devices.api.push_serializers import SubscribeSerializer
from etqan.devices.api.push_serializers import SubscriptionRowSerializer
from etqan.devices.api.push_serializers import UnsubscribeSerializer
from etqan.platform import features
from etqan.platform.exceptions import NotFoundError
from etqan.platform.permissions import NotImpersonating


def _require_push() -> None:
    if not features.enabled(subscriptions.PUSH_SWITCH):
        raise NotFoundError("Push notifications")


class PushKeyView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request, *args, **kwargs):
        _require_push()
        if not push_keys.configured():
            raise NotFoundError("Push notifications")
        return Response({"public_key": push_keys.public_key()})


class PushSubscriptionsView(APIView):
    def get_permissions(self):
        if self.request.method in ("POST", "DELETE"):
            return [IsAuthenticated(), NotImpersonating()]
        return [IsAuthenticated()]

    def get(self, request, *args, **kwargs):
        rows = subscriptions.of(request.user)
        return Response(SubscriptionRowSerializer(rows, many=True).data)

    def post(self, request, *args, **kwargs):
        _require_push()
        if not push_keys.configured():
            raise NotFoundError("Push notifications")
        data = SubscribeSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        _row, created = subscriptions.subscribe(
            request.user,
            endpoint=data.validated_data["endpoint"],
            p256dh=data.validated_data["keys"]["p256dh"],
            auth=data.validated_data["keys"]["auth"],
            user_agent=request.headers.get("User-Agent", ""),
        )
        return Response(status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    def delete(self, request, *args, **kwargs):
        data = UnsubscribeSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        subscriptions.unsubscribe(request.user, endpoint=data.validated_data["endpoint"])
        return Response(status=status.HTTP_204_NO_CONTENT)
```

Routes in `api/urls.py`:

```python
    path("push/key/", push_views.PushKeyView.as_view(), name="push-key"),
    path("push/subscriptions/", push_views.PushSubscriptionsView.as_view(), name="push-subscriptions"),
```

Generate the migration with the `makemigrations devices` command from Global Constraints; commit it.

- [ ] **Step 4: Run to verify they pass** — the three test files, `etqan/devices`, and `just check-boundaries`.

- [ ] **Step 5: Commit** — backend: `feat(devices): push subscriptions API restricted to push services (B11b)`.

---

### Task 3: Payload encryption and one send

**Files:**
- Create: `backend/etqan/devices/sender.py`, `backend/etqan/devices/tests/test_sender.py`

**Interfaces:**
- Consumes: Task 1 `push_keys.vapid_authorization`, `b64url_decode`; Task 2 `push_hosts.allowed`, `PushSubscription`.
- Produces: `sender.payload(*, notification_id: int, title: str, body: str) -> bytes` (JSON, ≤ 1024 bytes),
  `sender.encrypt(row: PushSubscription, data: bytes) -> bytes`,
  `sender.send(client: httpx.Client, row: PushSubscription, data: bytes) -> str` returning `"sent" | "gone" | "retry"`,
  applying P-8 to the row (sets `last_success_at` / deletes it), `TTL = 3600`, `TIMEOUT = 10`.

- [ ] **Step 1: Write the failing tests** (`test_sender.py`; the orchestrator rebuilds the django image with
  `http-ece` before this task)

```python
import base64
import json
import logging

import http_ece
import httpx
import pytest
from cryptography.hazmat.primitives.asymmetric import ec

from etqan.devices import push_keys
from etqan.devices import sender
from etqan.devices.models import PushSubscription

ENDPOINT = "https://fcm.googleapis.com/fcm/send/secret-token"


@pytest.fixture
def client_keys():
    key = ec.generate_private_key(ec.SECP256R1())
    auth = b"\x07" * 16
    return key, auth


@pytest.fixture
def row(client_keys, django_user_model):
    key, auth = client_keys
    public = key.public_key().public_bytes(push_keys.X962, push_keys.UNCOMPRESSED)
    user = django_user_model.objects.create(email="push@x.test", role="student")
    return PushSubscription.objects.create(
        user=user,
        endpoint=ENDPOINT,
        p256dh=push_keys.b64url_encode(public),
        auth=push_keys.b64url_encode(auth),
        key_id="k",
        label="Chrome on Android",
    )


def test_payload_shape_and_cap():
    data = json.loads(sender.payload(notification_id=7, title="T", body="B"))
    assert data == {"title": "T", "body": "B", "url": "/app/notifications", "tag": "n7"}
    long = sender.payload(notification_id=7, title="ع" * 200, body="ب" * 2000)
    assert len(long) <= 1024
    assert json.loads(long)["body"].endswith("…")


@pytest.mark.django_db
def test_encrypt_round_trips(row, client_keys):
    key, auth = client_keys
    body = sender.encrypt(row, b'{"title":"x"}')
    assert http_ece.decrypt(body, private_key=key, auth_secret=auth, version="aes128gcm") == b'{"title":"x"}'


def _client(status, seen):
    def handler(request):
        seen.append(request)
        return httpx.Response(status)

    return httpx.Client(transport=httpx.MockTransport(handler), follow_redirects=False)


@pytest.mark.django_db
def test_sent_sets_last_success_and_headers(row):
    seen = []
    assert sender.send(_client(201, seen), row, b"{}") == "sent"
    row.refresh_from_db()
    assert row.last_success_at is not None
    request = seen[0]
    assert request.headers["TTL"] == "3600"
    assert request.headers["Content-Encoding"] == "aes128gcm"
    assert request.headers["Authorization"].startswith("vapid t=")


@pytest.mark.django_db
@pytest.mark.parametrize("status", [400, 401, 403, 404, 410, 413])
def test_permanent_failures_delete(row, status):
    assert sender.send(_client(status, []), row, b"{}") == "gone"
    assert not PushSubscription.objects.filter(pk=row.pk).exists()


@pytest.mark.django_db
@pytest.mark.parametrize("status", [429, 500, 503])
def test_transient_failures_keep(row, status):
    assert sender.send(_client(status, []), row, b"{}") == "retry"
    assert PushSubscription.objects.filter(pk=row.pk).exists()


@pytest.mark.django_db
def test_timeout_keeps_and_never_logs_endpoint(row, caplog):
    def handler(request):
        raise httpx.ReadTimeout("slow", request=request)

    client = httpx.Client(transport=httpx.MockTransport(handler))
    with caplog.at_level(logging.INFO):
        assert sender.send(client, row, b"{}") == "retry"
    assert "secret-token" not in caplog.text


@pytest.mark.django_db
def test_disallowed_host_is_deleted_without_a_request(row):
    PushSubscription.objects.filter(pk=row.pk).update(endpoint="https://127.0.0.1/x")
    row.refresh_from_db()
    seen = []
    assert sender.send(_client(201, seen), row, b"{}") == "gone"
    assert seen == []
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement** `sender.py`:

```python
"""One web push (B11b P-3, P-6, P-8): encrypt the payload for the browser
(RFC 8291 aes128gcm), sign with VAPID (RFC 8292) and POST it to the push
service. Never logs the endpoint: it is a bearer capability."""

import json
import logging
import os

import http_ece
import httpx
from cryptography.hazmat.primitives.asymmetric import ec
from django.utils import timezone

from etqan.devices import push_hosts
from etqan.devices import push_keys

logger = logging.getLogger(__name__)
TTL = 3600
TIMEOUT = 10
MAX_PAYLOAD = 1024
GONE = frozenset({400, 401, 403, 404, 410, 413})
URL = "/app/notifications"


def payload(*, notification_id: int, title: str, body: str) -> bytes:
    def dump(text: str) -> bytes:
        return json.dumps(
            {"title": title, "body": text, "url": URL, "tag": f"n{notification_id}"},
            ensure_ascii=False,
        ).encode()

    data = dump(body)
    if len(data) <= MAX_PAYLOAD:
        return data
    text = body
    while text and len(data) > MAX_PAYLOAD:
        text = text[: max(0, len(text) - max(1, (len(data) - MAX_PAYLOAD)))]
        data = dump(text + "…")
    return data


def encrypt(row, data: bytes) -> bytes:
    return http_ece.encrypt(
        data,
        salt=os.urandom(16),
        private_key=ec.generate_private_key(ec.SECP256R1()),
        dh=push_keys.b64url_decode(row.p256dh),
        auth_secret=push_keys.b64url_decode(row.auth),
        version="aes128gcm",
    )


def send(client: httpx.Client, row, data: bytes) -> str:
    if not push_hosts.allowed(row.endpoint):
        row.delete()
        return "gone"
    try:
        response = client.post(
            row.endpoint,
            content=encrypt(row, data),
            headers={
                "TTL": str(TTL),
                "Urgency": "normal",
                "Content-Encoding": "aes128gcm",
                "Content-Type": "application/octet-stream",
                "Authorization": push_keys.vapid_authorization(row.endpoint),
            },
            timeout=TIMEOUT,
        )
    except httpx.HTTPError as error:
        logger.warning("Web push to subscription %s failed: %s", row.pk, type(error).__name__)
        return "retry"
    if response.status_code in (200, 201, 202):
        type(row).objects.filter(pk=row.pk).update(last_success_at=timezone.now())
        return "sent"
    if response.status_code in GONE:
        logger.info("Web push subscription %s gone (%s)", row.pk, response.status_code)
        row.delete()
        return "gone"
    logger.warning("Web push to subscription %s answered %s", row.pk, response.status_code)
    return "retry"
```

If `http_ece.encrypt`'s keyword names differ in the installed version, read its signature
(`python -c "import http_ece, inspect; print(inspect.signature(http_ece.encrypt))"` through the django container) and
adapt — the round-trip test is the contract. Replace the simplistic truncation loop with a clean bisect on the
body's characters if a reviewer asks; it must end with "…" and stay ≤ 1024 bytes.

- [ ] **Step 4: Run to verify they pass.** - [ ] **Step 5: Commit** — `feat(devices): encrypted web push send (B11b)`.

---

### Task 4: The push job (needs R12 merged)

**Files:**
- Create: `backend/etqan/devices/push.py`, `backend/etqan/devices/tasks.py`, `backend/etqan/devices/tests/test_push_job.py`
- Modify: `backend/config/settings/base.py` (`CELERY_BEAT_SCHEDULE` entry with a `# B11b` comment),
  `backend/pyproject.toml` (devices contract `ignore_imports` gains
  `"etqan.devices.** -> etqan.notifications.services",` with comment `# B11b: new notices to push (D68, D69, R12).`)

**Interfaces:**
- Consumes: R12 `notifications.services.created_since(*, since, after_id=0, limit=200) -> list[PushNote(id,
  recipient_id, title, body, created_at)]`; Task 2 models; Task 3 `sender.payload`, `sender.send`;
  `platform.tenancy.academy_context(schema_name)`; `platform.features.enabled`.
- Produces: `push.run(*, now=None, deadline_seconds=40, client=None) -> dict` (counts: sent, gone, retry, skipped);
  tasks `devices.push` (dispatcher) and `devices.push_academy(schema_name)`.

- [ ] **Step 0: Build R12 (ledger D70: B5 delegated it to B11)** — only on a branch rebased on a trunk that has B5c
  merged (B5c edits `notifications/services/__init__.py`); if B5c is not merged yet, stop and report BLOCKED. The
  orchestrator takes `ledger.py claim B11 notifications` before and releases it right after this one commit. Scope,
  exactly: new module `backend/etqan/notifications/services/push.py`, exported from `etqan.notifications.services`
  (`created_since`, `PushNote`, keeping `__all__` sorted), additive, unscoped, read-only, ONE query —
  `Notification.objects.filter(created_at__gte=since, id__gt=after_id).order_by("id").values("id",
  "recipient_id", "title", "body", "created_at")[:limit]` mapped to a frozen dataclass
  `PushNote(id, recipient_id, title, body, created_at)`, title and body as stored. No model, migration, or change to
  existing services or contracts. Tests in `backend/etqan/notifications/tests/test_push_reads.py`: the `since` window
  (a row just before is excluded, one at `since` included), the `after_id` cursor, `limit`, id order,
  `django_assert_num_queries(1)`, and tenant isolation (a row in the other academy's schema is never returned).
  Commit: `feat(notifications): created_since read service for web push (R12, D70)`. The orchestrator asks B5 (or the
  conductor) to review that diff and marks R12 done citing D70.

- [ ] **Step 1: Write the failing tests** (`test_push_job.py`) — create notifications through the notifications app's
  own test helpers or its model (tests may import models across apps: the devices contract ignores
  `etqan.devices.tests.**`), patch `sender.send` to record calls:

```python
from datetime import timedelta

import pytest
from django.core.cache import cache
from django.utils import timezone

from etqan.devices import push
from etqan.devices.models import PushedNote
from etqan.devices.models import PushSubscription
from etqan.notifications.models import Notification

# Helpers in this module: make_user(role), subscribe(user, endpoint, created_at),
# notice(user, *, created_at, title="T", body="B") -> Notification (unique dedupe_key,
# a valid type/target_kind from the model's choices, language "en").


@pytest.fixture
def on(set_features, settings):
    cache.clear()
    set_features(installable_app=True, push_notifications=True)


@pytest.fixture
def sent(monkeypatch):
    calls = []
    monkeypatch.setattr(push.sender, "send", lambda client, row, data: calls.append((row.endpoint, data)) or "sent")
    return calls


@pytest.mark.django_db
def test_new_notice_goes_to_every_older_subscription_once(on, sent):
    now = timezone.now()
    user = make_user("student")
    subscribe(user, "https://fcm.googleapis.com/a", now - timedelta(minutes=10))
    subscribe(user, "https://fcm.googleapis.com/b", now - timedelta(minutes=10))
    notice(user, created_at=now - timedelta(minutes=1))
    push.run(now=now)
    push.run(now=now)
    assert sorted(endpoint for endpoint, _ in sent) == ["https://fcm.googleapis.com/a", "https://fcm.googleapis.com/b"]


@pytest.mark.django_db
def test_late_committed_lower_id_is_still_pushed(on, sent):
    now = timezone.now()
    user = make_user("student")
    subscribe(user, "https://fcm.googleapis.com/a", now - timedelta(minutes=30))
    newer = notice(user, created_at=now - timedelta(minutes=2))
    push.run(now=now)
    # A row with a lower id that only became visible now (simulated by a lower
    # created_at and inserting after the first run; ids keep increasing, so
    # assert by content instead of id order).
    late = notice(user, created_at=now - timedelta(minutes=5), title="late")
    push.run(now=now)
    titles = [data for _, data in sent]
    assert any(b'"late"' in data for data in titles)
    assert PushedNote.objects.filter(notification_id__in=[newer.id, late.id]).count() == 2


@pytest.mark.django_db
def test_older_than_window_never_pushed(on, sent):
    now = timezone.now()
    user = make_user("student")
    subscribe(user, "https://fcm.googleapis.com/a", now - timedelta(hours=3))
    notice(user, created_at=now - timedelta(minutes=61))
    push.run(now=now)
    assert sent == []


@pytest.mark.django_db
def test_subscription_newer_than_notice_skipped(on, sent):
    now = timezone.now()
    user = make_user("student")
    notice(user, created_at=now - timedelta(minutes=5))
    subscribe(user, "https://fcm.googleapis.com/a", now - timedelta(minutes=1))
    push.run(now=now)
    assert sent == []


@pytest.mark.django_db
def test_other_users_devices_untouched(on, sent):
    now = timezone.now()
    a, b = make_user("student"), make_user("teacher")
    subscribe(b, "https://fcm.googleapis.com/b", now - timedelta(minutes=10))
    notice(a, created_at=now - timedelta(minutes=1))
    push.run(now=now)
    assert sent == []


@pytest.mark.django_db
def test_switch_off_or_not_set_up_does_nothing(set_features, settings, sent):
    set_features(installable_app=True, push_notifications=False)
    assert push.run() == {"skipped": "off"}
    set_features(installable_app=True, push_notifications=True)
    settings.WEB_PUSH_VAPID_FROM_SECRET_KEY = False
    settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC = ""
    assert push.run() == {"skipped": "not_set_up"}


@pytest.mark.django_db
def test_lock_held_is_a_no_op(on, sent):
    cache.add(push.LOCK, 1, 60)
    assert push.run() == {"skipped": "locked"}


@pytest.mark.django_db
def test_failure_mid_run_keeps_what_was_recorded(on, monkeypatch):
    now = timezone.now()
    user = make_user("student")
    subscribe(user, "https://fcm.googleapis.com/a", now - timedelta(minutes=30))
    first = notice(user, created_at=now - timedelta(minutes=3))
    notice(user, created_at=now - timedelta(minutes=2))
    calls = []

    def flaky(client, row, data):
        calls.append(data)
        if len(calls) == 2:
            raise RuntimeError("boom")
        return "sent"

    monkeypatch.setattr(push.sender, "send", flaky)
    with pytest.raises(RuntimeError):
        push.run(now=now)
    assert PushedNote.objects.filter(notification_id=first.id).exists()
    assert cache.get(push.LOCK) is None  # released in finally


@pytest.mark.django_db
def test_deadline_stops_and_next_run_continues(on, sent, monkeypatch):
    now = timezone.now()
    user = make_user("student")
    subscribe(user, "https://fcm.googleapis.com/a", now - timedelta(minutes=30))
    for minute in (5, 4, 3):
        notice(user, created_at=now - timedelta(minutes=minute))
    push.run(now=now, deadline_seconds=0)
    assert sent == []
    push.run(now=now)
    assert len(sent) == 3


@pytest.mark.django_db
def test_prunes_old_pushed_notes(on, sent):
    PushedNote.objects.create(notification_id=999_999, created_at=timezone.now() - timedelta(hours=3))
    push.run()
    assert not PushedNote.objects.filter(notification_id=999_999).exists()


@pytest.mark.django_db
def test_dispatcher_enqueues_one_task_per_active_academy(monkeypatch, tenants):
    from etqan.devices import tasks

    queued = []
    monkeypatch.setattr(tasks.push_academy, "delay", lambda schema: queued.append(schema))
    tasks.push_all()
    assert {tenants.main.schema_name, tenants.other.schema_name} <= set(queued)
```

Write `make_user`, `subscribe` (PushSubscription with valid-looking keys from Task 3's fixture style), and `notice`
(a `Notification` with a unique `dedupe_key`, `type`/`target_kind` taken from the model's choices, `created_at` given)
at the top of the module.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

`push.py`:

```python
"""The per-academy push run (B11b P-3..P-5). Reads the last hour of
notifications through notifications.services (D68/D69), pushes each one once
(PushedNote, recorded before sending), never inside a wrapping transaction."""

import time
from datetime import timedelta

import httpx
from django.core.cache import cache
from django.utils import timezone

from etqan.devices import push_keys
from etqan.devices import sender
from etqan.devices.models import PushedNote
from etqan.devices.models import PushSubscription
from etqan.devices.subscriptions import PUSH_SWITCH
from etqan.notifications import services as notifications
from etqan.platform import features

WINDOW = timedelta(minutes=60)
KEEP = timedelta(hours=2)
PAGE = 200
LOCK = "devices:push:lock"
LOCK_SECONDS = 60


def run(*, now=None, deadline_seconds: float = 40, client: httpx.Client | None = None) -> dict:
    if not features.enabled(PUSH_SWITCH):
        return {"skipped": "off"}
    if not push_keys.configured():
        return {"skipped": "not_set_up"}
    if not cache.add(LOCK, 1, LOCK_SECONDS):
        return {"skipped": "locked"}
    try:
        return _run(now or timezone.now(), time.monotonic() + deadline_seconds, client)
    finally:
        cache.delete(LOCK)


def _run(now, deadline, client) -> dict:
    counts = {"sent": 0, "gone": 0, "retry": 0}
    own_client = client is None
    client = client or httpx.Client(follow_redirects=False)
    try:
        after_id = 0
        while time.monotonic() < deadline:
            notes = notifications.created_since(since=now - WINDOW, after_id=after_id, limit=PAGE)
            if not notes:
                break
            done = set(
                PushedNote.objects.filter(notification_id__in=[n.id for n in notes]).values_list(
                    "notification_id", flat=True
                )
            )
            for note in notes:
                after_id = note.id
                if note.id in done:
                    continue
                if time.monotonic() >= deadline:
                    return counts
                _push(client, note, counts)
    finally:
        if own_client:
            client.close()
    PushedNote.objects.filter(created_at__lt=now - KEEP).delete()
    return counts


def _push(client, note, counts) -> None:
    _row, created = PushedNote.objects.get_or_create(notification_id=note.id)
    if not created:
        return
    data = sender.payload(notification_id=note.id, title=note.title, body=note.body)
    rows = PushSubscription.objects.filter(user_id=note.recipient_id, created_at__lt=note.created_at)
    for row in rows:
        counts[sender.send(client, row, data)] += 1
```

(The deadline check before the first page means `deadline_seconds=0` sends nothing and records nothing, as the test
expects. Prune runs only on a full pass.)

`tasks.py`:

```python
from celery import shared_task
from django_tenants.utils import get_public_schema_name
from django_tenants.utils import get_tenant_model

from etqan.devices import push
from etqan.platform.tenancy import academy_context

PUSH = "devices.push"
PUSH_ACADEMY = "devices.push_academy"


@shared_task(name=PUSH_ACADEMY, soft_time_limit=50, time_limit=55)
def push_academy(schema_name: str) -> dict:
    """B11b P-5: one academy's run, no wrapping transaction; its lock keeps
    two runs of the same academy apart."""
    with academy_context(schema_name):
        return push.run()


@shared_task(name=PUSH)
def push_all() -> int:
    """Every minute: one task per active academy, so a slow academy never
    delays another (spec review C2)."""
    schemas = (
        get_tenant_model()
        .objects.exclude(schema_name=get_public_schema_name())
        .filter(status="active")
        .values_list("schema_name", flat=True)
    )
    for schema in schemas:
        push_academy.delay(schema)
    return len(schemas)
```

`CELERY_BEAT_SCHEDULE` entry (append inside the dict, after the last entry):

```python
    # B11b (spec 2026-10-10 P-5): every minute, one push task per academy.
    "devices.push": {
        "task": "devices.push",
        "schedule": crontab(),
        "options": {"expires": 55},
    },
```

- [ ] **Step 4: Run to verify they pass** — `etqan/devices`, then `just check-boundaries`.

- [ ] **Step 5: Commit** — `feat(devices): per-academy push job over the last hour of notices (B11b)`.

---

### Task 5: Service worker push, the device card, sign-out cleanup, e2e

**Files:**
- Modify: `dashboard/public/sw.js` (bump `VERSION` to `"2"`; add `push` and `notificationclick`),
  `dashboard/src/features/identity/schemas.ts` (`FeatureCode`: `| "push_notifications"` under the B11 comment),
  `dashboard/src/features/apps/index.ts`, `dashboard/src/routes/_authed/account.tsx` (one line),
  `dashboard/src/features/shell/AppShell.tsx` (one call in `onSignOut`, under a one-commit ledger claim on the shell
  taken by the orchestrator), `dashboard/src/locales/{en,ar}/apps.json` (new `push.*` keys)
- Create: `dashboard/src/features/apps/push.ts`, `push.test.ts`, `PushCard.tsx`, `PushCard.test.tsx`,
  `dashboard/e2e/b11-web-push.spec.ts`

**Interfaces:**
- Consumes: backend `GET/POST/DELETE /api/v1/devices/push/...`; Task-3-of-Plan-62 `installState`; `@/lib/api`
  (axios client with CSRF) for the calls.
- Produces: `push.ts`: `pushSupport(): "supported" | "unsupported" | "ios-not-installed"`,
  `currentSubscription(): Promise<PushSubscription | null>`, `turnOn(): Promise<"on" | "denied">`,
  `turnOff(): Promise<void>`, `syncKey(): Promise<void>` (re-subscribes when the browser's key differs from
  `key/`), `signOutCleanup(me: Me | undefined): Promise<void>` (best effort; no-op when impersonated or unsupported);
  `PushCard()`.

- [ ] **Step 1: Write the failing tests** — `push.test.ts` (mock `navigator.serviceWorker.ready` with a fake
  registration whose `pushManager` has `getSubscription`/`subscribe`, mock `Notification.requestPermission`, mock the
  api module): turnOn → requestPermission "granted" → subscribe called with `{userVisibleOnly: true,
  applicationServerKey: <Uint8Array of the key>}` → POST body `{endpoint, keys: {p256dh, auth}}` from
  `subscription.toJSON()`; permission "denied" → returns "denied", no POST; turnOff → unsubscribe then DELETE with the
  endpoint; syncKey with a different `options.applicationServerKey` → unsubscribe + subscribe + POST; same key → no
  calls; `signOutCleanup` with `me.impersonator` set → nothing called; when DELETE rejects → resolves anyway.
  `PushCard.test.tsx`: states unsupported, ios-not-installed ("install the app first" text), denied, off ("Turn on"),
  on ("Turn off"), the lock-screen note, other devices listed by label. Account test: card shown only when
  `me.features` has both switches and not impersonated. AppShell test (existing file): sign-out calls
  `signOutCleanup` before `logout.mutate` and still logs out when it rejects.

- [ ] **Step 2: Run to verify they fail** — `just _compose run --rm dashboard pnpm vitest run src/features/apps src/routes/_authed/account src/features/shell`.

- [ ] **Step 3: Implement**

`sw.js` additions:

```js
self.addEventListener("push", (event) => {
	let data;
	try {
		data = event.data ? event.data.json() : null;
	} catch {
		data = null;
	}
	if (!data || typeof data.title !== "string") return;
	event.waitUntil(
		self.registration.showNotification(data.title, {
			body: data.body || "",
			tag: data.tag,
			icon: "/api/v1/devices/icons/192.png",
			data: { url: data.url || "/app/notifications" },
		}),
	);
});

self.addEventListener("notificationclick", (event) => {
	event.notification.close();
	const url = new URL(event.notification.data?.url || "/app/notifications", self.location.origin);
	if (url.origin !== self.location.origin || !url.pathname.startsWith("/app/")) return;
	event.waitUntil(
		self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((windows) => {
			const open = windows.find((w) => new URL(w.url).pathname.startsWith("/app/"));
			if (open) return open.focus().then((w) => w.navigate(url.href));
			return self.clients.openWindow(url.href);
		}),
	);
});
```

`push.ts` (key helpers + flows; use the repo's axios `api` from `@/lib/api`):

```ts
import type { Me } from "@/features/identity/schemas";
import { api } from "@/lib/api";
import { isIos, readEnv } from "./platform";

export const PUSH_SWITCH = "push_notifications";

export function base64UrlToBytes(value: string): Uint8Array {
	const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (value.length % 4)) % 4);
	return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

function sameKey(a: ArrayBuffer | null | undefined, b: Uint8Array): boolean {
	if (!a) return false;
	const x = new Uint8Array(a);
	return x.length === b.length && x.every((v, i) => v === b[i]);
}

export function pushSupport(): "supported" | "unsupported" | "ios-not-installed" {
	const env = readEnv();
	const capable = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
	if (isIos(env) && !(env.standalone || env.displayStandalone)) return "ios-not-installed";
	return capable ? "supported" : "unsupported";
}

async function registration() {
	return navigator.serviceWorker.ready;
}

export async function currentSubscription() {
	return (await registration()).pushManager.getSubscription();
}

async function publicKey(): Promise<Uint8Array> {
	const { data } = await api.get<{ public_key: string }>("devices/push/key/");
	return base64UrlToBytes(data.public_key);
}

async function save(subscription: PushSubscription) {
	const json = subscription.toJSON();
	await api.post("devices/push/subscriptions/", { endpoint: json.endpoint, keys: json.keys });
}

export async function turnOn(): Promise<"on" | "denied"> {
	if ((await Notification.requestPermission()) !== "granted") return "denied";
	const key = await publicKey();
	const subscription = await (await registration()).pushManager.subscribe({
		userVisibleOnly: true,
		applicationServerKey: key,
	});
	await save(subscription);
	return "on";
}

export async function turnOff(): Promise<void> {
	const subscription = await currentSubscription();
	if (!subscription) return;
	const endpoint = subscription.endpoint;
	await subscription.unsubscribe();
	await api.delete("devices/push/subscriptions/", { data: { endpoint } });
}

export async function syncKey(): Promise<void> {
	const subscription = await currentSubscription();
	if (!subscription) return;
	const key = await publicKey();
	if (sameKey(subscription.options.applicationServerKey, key)) return;
	await subscription.unsubscribe();
	const fresh = await (await registration()).pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
	await save(fresh);
}

export async function signOutCleanup(me: Me | undefined): Promise<void> {
	if (!me || me.impersonator || pushSupport() !== "supported") return;
	try {
		await turnOff();
	} catch {
		// Best effort: sign-out never waits on push (spec P-12).
	}
}
```

`PushCard.tsx`: a `Card` titled `t("apps.push.title")`, using `useQuery` for `devices/push/subscriptions/` (other
devices) and local state from `currentSubscription()` + `Notification.permission`; runs `syncKey()` once on mount when
on; buttons call `turnOn`/`turnOff` and refetch; shows `t("apps.push.lockScreen")`. Strings (en; mirror in ar):

```json
"push": {
	"title": "Notifications on this device",
	"intro": "Get your academy's notices here even when the app is closed.",
	"unsupported": "This browser cannot receive notifications.",
	"iosInstall": "On iPhone or iPad, install the app first (see “Install the app”), then turn notifications on from the installed app.",
	"denied": "Notifications are blocked for this site. Allow them in your browser's site settings, then come back.",
	"on": "Notifications are on for this device.",
	"turnOn": "Turn on",
	"turnOff": "Turn off",
	"lockScreen": "Notices can show on your lock screen.",
	"otherDevices": "Your devices",
	"lastDelivered": "Last delivered {{when}}",
	"never": "Nothing delivered yet",
	"failed": "Could not change notifications on this device. Try again."
}
```

ar:

```json
"push": {
	"title": "الإشعارات على هذا الجهاز",
	"intro": "استلم إشعارات أكاديميتك هنا حتى عندما يكون التطبيق مغلقًا.",
	"unsupported": "هذا المتصفح لا يستقبل الإشعارات.",
	"iosInstall": "على iPhone أو iPad ثبّت التطبيق أولًا (انظر «ثبّت التطبيق»)، ثم فعّل الإشعارات من التطبيق المثبّت.",
	"denied": "الإشعارات محظورة لهذا الموقع. اسمح بها من إعدادات الموقع في متصفحك ثم عد إلى هنا.",
	"on": "الإشعارات مفعّلة على هذا الجهاز.",
	"turnOn": "تفعيل",
	"turnOff": "إيقاف",
	"lockScreen": "قد تظهر الإشعارات على شاشة القفل.",
	"otherDevices": "أجهزتك",
	"lastDelivered": "آخر تسليم {{when}}",
	"never": "لم يُسلَّم شيء بعد",
	"failed": "تعذّر تغيير الإشعارات على هذا الجهاز. حاول مرة أخرى."
}
```

Account page: `{own && installState(me) === "on" && me.features?.includes("push_notifications") ? <PushCard /> : null}`
after the install card. AppShell `onSignOut`: `void signOutCleanup(me).finally(() => logout.mutate(...))` keeping the
existing callbacks (sign-out proceeds when cleanup fails).

e2e `b11-web-push.spec.ts`: sign in as demo admin (both switches on by seed), `page.request.get(DEMO_URL +
"/api/v1/devices/push/key/")` → 200 with a 65-byte key; `/app/account` shows "Notifications on this device"; no
subscribe (headless Chromium has no push service).

- [ ] **Step 4: Run to verify they pass** — vitest on the touched folders, `pnpm tsc --noEmit`, `pnpm lint` (one
  per invocation).

- [ ] **Step 5: Commit** — dashboard: `feat(apps): push on this device, sign-out cleanup and e2e (B11b)`; the
  AppShell line as its own commit under the claim (`feat(shell): stop pushes to this browser on sign-out (B11b)`).

- [ ] **Step 6: Gates** (orchestrator, in the conductor's full window) — `just dev-backend`, `just test`,
  `just lint`, `just e2e`, then `just stop`.
