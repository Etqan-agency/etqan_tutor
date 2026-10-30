---
title: "Apps (installable app and web push)"
---

Phase B11 gives every role (office, teacher, student, parent) an academy "app". This app is the existing
dashboard installed as a Progressive Web App (PWA). It carries the academy's name, colours and an icon built
from its logo, and it installs on Android and iOS home screens and as a desktop app. Slice B11b adds web push:
each new in-app notification is also pushed to the recipient's subscribed browsers and devices. Each slice is a
per-academy feature switch, off by default. The planned native mobile app (B11c–B11g) is **on hold**: the
owner's ruling E4 (2026-10-10) means no native repo, store accounts or FCM exist. The backend app behind this
feature is `etqan.devices`.

## Concepts

`etqan.devices` is in the **academy schema** (TENANT_APPS, under `── phase B11 ──`).

| Model | Purpose |
|---|---|
| `PushSubscription` | One browser's push subscription. Fields: `user`, unique `endpoint` (treated as a secret: never returned by an API or logged), `p256dh`, `auth`, `key_id` (the first 16 characters of the VAPID public key it was made with), `label` (derived from the User-Agent), `created_at`, `last_success_at`. At most 10 per user; the oldest or least recently successful are dropped first. |
| `PushedNote` | Dedupe record of a notification already pushed. Unique `notification_id`; pruned after 2 hours. |

The B11a manifest and icons have no model. They are built from `site.services.branding_snapshot()` and the
academy's default language.

Switches (`etqan.platform.features`):

- `installable_app` (B11a);
- `push_notifications` (B11b), which requires `installable_app`.

## How it works

### Installable app (B11a): `etqan/devices/services.py`

- `manifest()` returns an `application/manifest+json` document with these fields:
  - `id`, `start_url` and `scope` all set to `/app/`, and `display: standalone`;
  - the name in the academy's default language, falling back to the other language;
  - `lang` and `dir`;
  - `theme_color`, which is the primary colour or `#0E7C66`;
  - three icons (192, 512, maskable-512), versioned with `?v=<branding timestamp>-<language>`.

  It returns 404 when `installable_app` is off.
- `icon(kind)` returns the `192`, `512`, `maskable-512` or `apple-touch-180` PNG. `devices/icons.py` renders it
  from the logo, falling back to the name's first letter on the primary colour. The rendered PNG is cached for
  24 hours. The cache key includes the schema, the branding timestamp and the language.
- The dashboard is a static bundle, so it adds the manifest itself. `InstallableApp`, mounted in
  `routes/_authed.tsx`, runs when `me.features` includes `installable_app`. It:
  - fetches the manifest;
  - adds `<link rel="manifest">`, the apple-touch icon and the `theme-color` meta tag;
  - registers `/app/sw.js` with scope `/app/`.

  When the switch is off, it removes these again.
- The service worker `dashboard/public/sw.js` caches only `/app/offline.html` and serves it when navigation
  under `/app/` fails. It never intercepts API calls or assets. It also handles `push` and
  `notificationclick` (B11b).
- The "Install the app" card is on the account page. It shows a platform-specific install hint: the browser's
  install prompt, iOS "Add to Home Screen", or macOS Safari "Add to Dock".

### Web push (B11b): `push.py`, `sender.py`, `subscriptions.py`, `push_keys.py`

- **Subscribe.** The account page's `PushCard` reads the VAPID public key, subscribes the browser, and POSTs the
  subscription. `subscriptions.subscribe` upserts the row by endpoint. When an endpoint moves to another user,
  `created_at` is reset so the new user never receives older notices.
- **Deliver.** The per-academy run `push.run()` works as follows:
  1. It does nothing when the switch is off, when keys are not set up, or when another run holds the cache
     lock.
  2. It pages through the last 60 minutes of notifications using
     `notifications.services.created_since(since=, after_id=, limit=200)`, defined in
     `notifications/services/push.py`.
  3. It skips any notification that is already in `PushedNote`.
  4. It sends only to subscriptions created before the notification.
  5. It records a `PushedNote` before sending, so each notification is pushed at most once.
  6. It stops at a 40 s deadline.
- **Send.** `sender.send` encrypts the payload with RFC 8291 aes128gcm and signs it with VAPID (RFC 8292). The
  payload is the notification's title and body, already in the recipient's language, with URL
  `/app/notifications`. Payloads are at most 1 KB and use TTL 1 h. Rules:
  - The endpoint must be HTTPS on a browser vendor's push service (`push_hosts.SUFFIXES`: FCM, Mozilla,
    Windows, Apple), which prevents server-side request forgery (SSRF).
  - HTTP 400/401/403/404/410/413 deletes the subscription.
  - Success sets `last_success_at`.
- **No metering.** Web push uses no outside account (B11-7), so it is not an integrations service and is not
  metered.
- **Import boundary.** `etqan.devices` is the only app allowed to import `etqan.notifications.services`
  (read-only, B11-6 amends D39). Nothing imports `etqan.devices`.

## API

All routes are on academy hosts.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/devices/manifest.webmanifest` | anonymous | The academy's web app manifest (404 when `installable_app` is off) |
| GET | `/api/v1/devices/icons/<kind>.png` | anonymous | App icon: `192`, `512`, `maskable-512`, `apple-touch-180` |
| GET | `/api/v1/devices/push/key/` | signed in, `push_notifications` on | `{public_key}` (404 when push is not set up) |
| GET | `/api/v1/devices/push/subscriptions/` | signed in | The caller's devices (no endpoints) |
| POST | `/api/v1/devices/push/subscriptions/` | signed in, switch on, not impersonating | Subscribe `{endpoint, keys: {p256dh, auth}}` (201 new, 200 existing) |
| DELETE | `/api/v1/devices/push/subscriptions/` | signed in, not impersonating | Unsubscribe `{endpoint}` (204) |

Listing and deleting subscriptions still work when the switch is off, so people can clean up their devices.

## Dashboard

- `dashboard/src/features/apps/`:
  - `InstallableApp.tsx` and `installable.ts`: manifest injection and service-worker registration;
  - `InstallAppCard.tsx`, `install.ts` and `platform.ts`: the install prompt and per-platform hints;
  - `PushCard.tsx` and `push.ts`: turning push on and off, key sync, and `signOutCleanup`, which unsubscribes
    on sign-out.
- `routes/_authed.tsx` mounts `InstallableApp`. `routes/_authed/account.tsx` shows `InstallAppCard` and
  `PushCard`.
- `dashboard/public/sw.js` and `dashboard/public/offline.html`.
- Strings: `dashboard/src/locales/{en,ar}/apps.json`.

## Background jobs

- `devices.push` runs every minute from beat, with `expires=55`. It fans out one `devices.push_academy(schema)`
  task per active academy (`status="active"`).
- `devices.push_academy` runs `push.run()` in `academy_context`, with `soft_time_limit=50`.

## Configuration

- `WEB_PUSH_VAPID_PUBLIC_KEY`: the public key, as plain env config.
- `WEB_PUSH_VAPID_PRIVATE_KEY_ENC`: the private key, Fernet-encrypted with `etqan.platform.secrets` and read
  only through `secrets.decrypt`.
- `WEB_PUSH_VAPID_SUBJECT`: a `mailto:` or `https:` URL. If the private key is set without a valid subject,
  system check `devices.W001` warns.
- `manage.py make_vapid_keys` prints a new key pair, with the private key already encrypted.
- Local and test settings derive a dev pair from `SECRET_KEY` (`WEB_PUSH_VAPID_FROM_SECRET_KEY`). Production has
  no default subject, so push stays "not set up" until all three are set.
- Branding (name, colours, logo) comes from the academy's site settings. There is no app-specific
  configuration.

## Code map

- `backend/etqan/devices/`: `services.py` and `icons.py` (B11a); `push.py`, `sender.py`, `subscriptions.py`,
  `push_keys.py`, `push_hosts.py` and `user_agents.py` (B11b)
- Also in `backend/etqan/devices/`: `tasks.py`, `checks.py`, `models.py`, `api/`,
  `management/commands/make_vapid_keys.py`
- `backend/etqan/notifications/services/push.py` (`created_since`)
- `dashboard/src/features/apps/`, `dashboard/public/sw.js`, `dashboard/public/offline.html`

## Design history

- [B11 apps design](../superpowers/specs/2026-10-09-b11-apps-design.md): the phase (B11-1 to B11-11) and the
  B11a spec. Slices B11c–B11g (native app sign-in, Expo app, FCM via `integrations.resolve('push')`) are
  **deferred** by E4 and not built. There is no `push` integrations service.
- [B11b web push design](../superpowers/specs/2026-10-10-b11b-web-push-design.md): the last built slice of B11.
- [Plan 62: installable app](../superpowers/plans/2026-10-09-plan-62-installable-app.md).
- [Plan 63: web push](../superpowers/plans/2026-10-10-plan-63-web-push.md).
