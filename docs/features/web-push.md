# Web push

Browser push notifications for the installable dashboard app. Every in-app `Notification` (see
[notifications.md](notifications.md)) created after a browser subscribed is pushed to that browser once, as its
stored title and body. Any signed-in user can turn it on for a device from their account page. Push lives in the
`etqan.devices` app, which also serves the B11a installable-app manifest and icons; it reads notices through
`notifications.services.created_since` and writes nothing back to notifications.

## Concepts

Models in `etqan/devices/models.py`:

| Model | Key fields | Notes |
|---|---|---|
| `PushSubscription` | `user`, `endpoint` (unique, ≤ 1000), `p256dh`, `auth`, `key_id` (first 16 chars of the VAPID public key), `label` ("browser on OS"), `created_at`, `last_success_at` | One row per browser. The endpoint is a bearer capability: no API returns it and nothing logs it. Max 10 per user; the stalest are dropped. |
| `PushedNote` | `notification_id` (unique), `created_at` | Dedupe record of a notice already pushed; pruned after 2 h. |

Other pieces: `push_keys.py` (VAPID keys and JWT), `push_hosts.py` (allowed push-service hosts),
`sender.py` (encrypt + POST one push), `push.py` (the per-academy run), `subscriptions.py` (subscribe/unsubscribe),
`user_agents.py` (label).

## How it works

**Subscribe** (`subscriptions.py:subscribe`): upsert by endpoint for the caller. If the endpoint belonged to another
user it is taken over and `created_at` is reset, so the new user never gets older notices. A re-subscribe without
a User-Agent keeps the old label. Over 10 subscriptions, the ones with the oldest `last_success_at` go.
`unsubscribe` deletes only the caller's row.

**Push run** (`push.py:run`, one academy):

1. Return early when `push_notifications` is off, VAPID is not configured, or another run holds the per-academy
   cache lock (`devices:push:lock`, 60 s, schema-prefixed).
2. Page through notices created in the last 60 minutes, oldest id first, 200 at a time
   (`notifications.services.created_since(since, after_id, limit)`). A **time window, not an id cursor**, because
   ids can commit out of order.
3. Skip notices with a `PushedNote`. For each other notice, take the recipient's subscriptions **created before
   the notice** (a new device never receives old notices). No such device: skip without recording.
4. Record `PushedNote` first (at-most-once), then send to each device until a 40 s deadline.
5. Prune `PushedNote` rows older than 2 h.

**One send** (`sender.py:send`):
- Payload `{title, body, url: "/app/notifications", tag: "n<id>"}`, ≤ 1024 bytes (body, then title, cut with "…").
- Encrypted with `http_ece` (aes128gcm, RFC 8291), signed with a VAPID ES256 JWT (RFC 8292, `aud` = endpoint
  origin, 12 h expiry), `TTL: 3600`, `Urgency: normal`, httpx with 10 s timeout and no redirects.
- Endpoint host must be `https` on `fcm.googleapis.com`, `*.push.services.mozilla.com`, `*.notify.windows.com` or
  `*.push.apple.com`, no port or userinfo — checked at subscribe and again with httpx's parser before each send.
- 200/201/202 → `last_success_at`; 400/401/403/404/410/413 or unusable keys/host → row deleted; 429/5xx/timeout →
  left alone (no retry counter; the notice is not pushed again).

**Service worker** (`dashboard/public/sw.js`, from B11a): `push` shows the notification with the academy icon;
`notificationclick` focuses an open `/app/` window and navigates it to the URL, else opens one. Only same-origin
`/app/` URLs are followed. Every push opens the notifications page, not the notice's own link.

**Client** (`dashboard/src/features/apps/push.ts`): `pushSupport()` (unsupported / iOS not installed / supported),
`turnOn` (permission → `GET push/key/` → `pushManager.subscribe` → `POST subscriptions/`), `turnOff`, and
`signOutCleanup`, which the shell's sign-out (`features/shell/AppShell.tsx`) calls best-effort to unsubscribe this
browser and delete its row (skipped while impersonating).

## API

Under `/api/v1/devices/`. Signed-in users only; each acts on their own rows.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/devices/push/key/` | signed-in; feature `push_notifications` | `{public_key}`; 404 when not set up |
| GET | `/api/v1/devices/push/subscriptions/` | signed-in | Own rows `[{id, label, created_at, last_success_at}]`, never endpoints; works while the switch is off |
| POST | `/api/v1/devices/push/subscriptions/` | signed-in; feature `push_notifications`; not impersonating | `{endpoint, keys: {p256dh, auth}}`; 201 new / 200 existing; 404 when not set up |
| DELETE | `/api/v1/devices/push/subscriptions/` | signed-in; not impersonating | `{endpoint}`; 204; works while the switch is off |
| GET | `/api/v1/devices/manifest.webmanifest` | anonymous | B11a installable-app manifest (feature `installable_app`) |
| GET | `/api/v1/devices/icons/<kind>.png` | anonymous | B11a app icons |

## Dashboard

- `routes/_authed/account.tsx` renders `PushCard` (`dashboard/src/features/apps/PushCard.tsx`, "Notifications on
  this device") next to `InstallAppCard`; it covers unsupported browsers, iOS "install first", denied
  permission, on/off and the device list.
- Translations: `dashboard/src/locales/<lng>/apps.json`.

## Background jobs

| Task | Schedule | What |
|---|---|---|
| `devices.push` (`etqan/devices/tasks.py:push_all`) | Beat every minute, `expires` 55 s | Enqueues one `devices.push_academy` per tenant with `status="active"` (not via `for_each_academy`, so a slow academy never delays others) |
| `devices.push_academy(schema_name)` | Enqueued above, `expires` 55 s, soft/hard limit 50/55 s | `push.run()` inside `academy_context`, no wrapping transaction |

## Configuration

| Setting / env var | Meaning |
|---|---|
| `WEB_PUSH_VAPID_PRIVATE_KEY_ENC` | Private key, encrypted with `etqan.platform.secrets` |
| `WEB_PUSH_VAPID_PUBLIC_KEY` | Optional consistency check; a mismatch with the derived key = not set up |
| `WEB_PUSH_VAPID_SUBJECT` | `mailto:` or `https:` URL; required (system check `devices.W001` warns when missing) |
| `WEB_PUSH_VAPID_FROM_SECRET_KEY` | `True` in local and test settings: derive a stable dev key pair from `SECRET_KEY` |

- Generate a production pair: `python manage.py make_vapid_keys` (prints the public key and the encrypted private key).
- Feature `push_notifications` (built, default off, requires `installable_app`).
- Push sends whatever notices exist: muting a category or turning a type off works upstream in the scan.

## Code map

- `backend/etqan/devices/models.py`, `subscriptions.py`, `push.py`, `sender.py`, `push_keys.py`, `push_hosts.py`, `checks.py`, `tasks.py`.
- `backend/etqan/devices/api/push_views.py`, `push_serializers.py`, `urls.py`.
- `backend/etqan/devices/management/commands/make_vapid_keys.py`.
- `backend/etqan/notifications/services/push.py` — `PushNote`, `created_since` (the read used by devices).
- `dashboard/public/sw.js`; `dashboard/src/features/apps/push.ts`, `PushCard.tsx`.

## Design history

- [B11 apps phase](../superpowers/specs/2026-10-09-b11-apps-design.md) — B11-6…B11-9; native apps held.
- [B11b web push](../superpowers/specs/2026-10-10-b11b-web-push-design.md) — P-1…P-13; current.
- Plans: [plan 62 installable app](../superpowers/plans/2026-10-09-plan-62-installable-app.md), [plan 63 web push](../superpowers/plans/2026-10-10-plan-63-web-push.md).
