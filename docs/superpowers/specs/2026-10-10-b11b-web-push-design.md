# B11b — Web push — Design

**Date:** 2026-10-10
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings (3 critical,
8 important, 8 minor) applied 2026-10-10.
**Phase spec:** `2026-10-09-b11-apps-design.md` (B11-6, B11-7, B11-8, B11-9; ledger D68). This slice is the last
of B11 (E4: native apps held).
**Requires:** B11a (the installable app, the service worker, `etqan.devices`); request R11 (R-B11b-1) done by B5.
**Evidence:** TutorHamster's notices go out by email, WhatsApp and the in-app stream (TH COMM-003/004); "app"
appears among the advertised channels (TH V05) but push was never observed — so everything here is `[assumed]`
(ledger D1) unless cited.

## 1. Goal

A user who turns on "Notifications on this device" gets each new in-app notification as a system notification on
that computer or phone, even when the app is closed; tapping it opens the notifications page. The academy turns
the feature on with `push_notifications`; each person chooses per device.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| P-1 | **Switch `push_notifications`**, "Push notifications" / "الإشعارات الفورية", group `communication`, built, default off, `requires=("installable_app",)` (the worker that receives pushes is B11a's). | B11-9; PO-5 |
| P-2 | **One row per browser subscription:** `devices.PushSubscription(user → AUTH_USER_MODEL CASCADE, endpoint URLField(max_length=1000) unique, p256dh CharField(100), auth CharField(30), key_id CharField(16) — the first 16 chars of the VAPID public key it was made with, label CharField(80), created_at, last_success_at null)`. `label` is "<browser> on <OS>" from a small local User-Agent classifier in `etqan.devices` (identity's `device_of` is not exported and gives only mobile/tablet/desktop). An endpoint is one browser profile, so a second user signing in on that browser takes the row over; endpoints are never returned by any API, so a takeover needs the secret endpoint and can only deny the victim pushes. At most 10 rows per user: an 11th replaces the user's least recently delivered one. | [assumed]; review I/minor |
| P-3 | **What is pushed:** each `Notification` row, as `{title, body, url: "/app/notifications", tag: "n<id>"}`, Web Push TTL 3600 s, urgency `normal`, to every subscription of its recipient that was **created before the row's `created_at`** (so a new device or a fresh switch-on never receives old notices). Title and body are the row's own text, already in the recipient's language and filtered by the recipient's mutes (B5a). Payload UTF-8 capped at 1 KB (body truncated with "…"). | B11-6; D68 |
| P-4 | **A time window, not an id cursor.** Notification ids can commit out of order (scans run per academy in one transaction, broadcasts and API requests are atomic), so a high-water mark would skip late-committed rows. Instead each run reads the rows created in the last 60 minutes, oldest id first, page by page (`created_since(since, after_id, limit=200)`, R11), and skips any already recorded in `devices.PushedNote(notification_id unique, created_at)`. A row is recorded (`ignore_conflicts`, autocommitted) **before** its sends, so it is pushed at most once; a run that stops early leaves the unrecorded rest for the next run. PushedNote rows older than 2 hours are deleted at the end of each run. Rows older than 60 minutes are never pushed (a backlog after downtime is dropped). | review C1, I2; D39/D68 (pull-based) |
| P-5 | **One task per academy.** Beat `devices.push` runs every minute (`expires` 55 s) and only enqueues `devices.push_academy(schema_name)` for each active academy; each of those runs inside `tenant_context` **without** a wrapping transaction, returns at once when the switch is off or keys are not set up, takes a per-academy lock `cache.add("devices:push:lock", 1, 60)` (schema-prefixed; released in `finally`), and stops sending after a 40 s deadline (`soft_time_limit` 50 s, `time_limit` 55 s). One slow academy never delays another. | review C2, C3; `platform/tenancy.py`; CLAUDE.md (jobs loop academies) |
| P-6 | **Sending with the existing `httpx`**, `follow_redirects=False`, 10 s timeout, payload encrypted with `http-ece` (aes128gcm) and the request signed with a VAPID JWT from `py-vapid` (two small new dependencies in `requirements/base.txt`, one line each with a `# B11b` comment; `pywebpush` is not used — it would add `requests`). Keys: public `settings.WEB_PUSH_VAPID_PUBLIC_KEY`; private `etqan.platform.secrets.decrypt(settings.WEB_PUSH_VAPID_PRIVATE_KEY_ENC)`; subject `settings.WEB_PUSH_VAPID_SUBJECT` (a real `mailto:`/`https:` subject; required in production settings whenever the keys are set). Missing or undecryptable keys or subject = "not set up". In local and test settings, when the env gives no keys, a fixed development pair is derived from `SECRET_KEY` (like `SECRETS_KEY_FROM_SECRET_KEY`), so dev, CI and e2e stacks have working keys without editing CI. A management command `make_vapid_keys` prints a new public key and the encrypted private key. Not metered. | B11-7 (conductor 2026-10-09: private key via `platform.secrets`); review I3, I7 |
| P-7 | **Only push services are ever called.** An endpoint is accepted only if it is `https://` on a known push-service host: `fcm.googleapis.com`, `*.push.services.mozilla.com`, `*.notify.windows.com`, `*.push.apple.com` (exact host or dot-suffix match), with no userinfo or port; `p256dh` must decode (base64url) to 65 bytes and `auth` to 16. The same host check runs again before every send. This keeps a signed-in user from making the server POST to internal addresses. | review I1 (SSRF) |
| P-8 | **Delivery outcomes:** 201/202 → `last_success_at = now`; 400, 401, 403, 404, 410 or 413 → the row is deleted (gone, or made with another key); 429, 5xx or a timeout → left for the next notice (no counter). Logs carry the status code and the row id only, never the endpoint (a bearer capability); Sentry breadcrumbs of these requests are accepted (Etqan's own restricted service). | review I5, I6 |
| P-9 | **API** under `devices/push/`, signed-in users only: `GET key/` → `{public_key}` (404 while the switch is off or not set up); `GET subscriptions/` → the caller's own rows `[{id, label, created_at, last_success_at}]` (never endpoints); `POST subscriptions/` `{endpoint, keys: {p256dh, auth}}` → upsert by endpoint for the caller (201 new, 200 existing), 404 while off; `DELETE subscriptions/` `{endpoint}` → deletes the caller's row with that endpoint, 204 also when absent, and works whether or not the switch is on. POST and DELETE add `NotImpersonating` (D19). Validation errors are 400 `validation_error` naming the field. | D19; CLAUDE.md (`/api/v1/`); review I8a |
| P-10 | **Service worker** (B11a's `sw.js`, version bumped): `push` → `showNotification(title, {body, tag, icon: "/api/v1/devices/icons/192.png", data: {url}})`; `notificationclick` → close, focus an open `/app/` window and navigate it to `url`, else `clients.openWindow(url)`. An unreadable payload shows nothing. | [assumed] |
| P-11 | **Account card "Notifications on this device"** (in `features/apps`; shown when `me.features` strictly includes both switches and the user is not impersonated): unsupported (no `PushManager`) → says so, and on iOS adds "install the app first" (iOS delivers web push only to home-screen apps); permission denied → how to allow it in browser settings; off → "Turn on" (permission, `pushManager.subscribe({userVisibleOnly: true, applicationServerKey})`, POST); on → "Turn off" (unsubscribe, DELETE). When the browser's subscription was made with another key than `key/` returns, the card re-subscribes silently. The card says notices show on the lock screen. It lists the user's other devices by label and last delivery (read-only). | [assumed]; review I5, minor (privacy) |
| P-12 | **Sign-out stops pushes to that browser:** the shell's sign-out handler (`features/shell/AppShell.tsx`, one additive call, under a one-commit claim) first unsubscribes this browser and DELETEs its row, best effort (never blocks or fails sign-out), and skips it while impersonating. A session that simply expires keeps its row until the push service drops it (accepted). | [assumed] (privacy); review I8 |
| P-13 | **Data and migrations:** `devices` gets its first migration (two new tables, PushSubscription and PushedNote; nothing existing changed). `seed_academy` adds nothing. | orchestration §6.2 |

## 3. Requests and claims

- **R11 → B5, amended** (filed 2026-10-09, amended 2026-10-10 before B5 acted): replace (a)/(b) with one service:
  `notifications.services.created_since(*, since: datetime, after_id: int = 0, limit: int = 200) ->
  list[PushNote(id, recipient_id, title, body, created_at)]` — rows with `created_at >= since` and `id > after_id`,
  ordered by id, at most `limit`, one query. Import contract: only `"etqan.devices.** -> etqan.notifications.services"`
  in the devices contract's `ignore_imports` (B11's own contract); the "no app imports notifications" contract does
  not list devices and is unchanged. B11b's push job is built only after B5 marks R11 done; the rest of the slice
  (models, API, worker, card) does not wait.
- **Shell sign-out (P-12):** one additive dashboard line in `features/shell/AppShell.tsx` under a one-commit
  ledger claim (conductor's area).

## 4. Errors and edge cases

- `push_notifications` turned off: academies are skipped, `key/` and POST answer 404, the card disappears; rows stay
  and are used again when it is turned back on. `installable_app` turned off unregisters the service worker (B11a
  A-4), which ends every browser subscription: those rows get 404/410 on their next push and are deleted (P-8).
- VAPID key rotation: pushes to old subscriptions are refused (400/401/403) and the rows deleted; each browser
  re-subscribes with the new key the next time its user opens the account page (P-11). Until then it gets nothing.
- A user deleted: rows cascade. A user who loses access (e.g. parents switched off): no notification rows are created
  for them, so nothing is pushed.
- Tenancy: rows live in each academy's schema; each task runs in `tenant_context` for its academy; the lock key is
  schema-prefixed.

## 5. Testing

- Backend: endpoint/key validation incl. host allow-list (internal host, IP, port, userinfo, http → 400); upsert and
  takeover; the 10-per-user cap; API permissions (anonymous 403; impersonated POST/DELETE refused; DELETE while
  off works); `key/` 404 while off or not set up; dev key derivation in test settings; `push_academy` with the HTTP
  send mocked (respx or a fake transport): sends each new row once to subscriptions created before it; skips rows
  already in PushedNote; a row older than 60 min is not sent; a subscription created after the row is not sent to;
  outcomes per status code; deadline stops and the next run continues; lock held (seed the LocMem key) → no-op;
  no wrapping transaction (a mid-run failure keeps earlier PushedNote rows); prune > 2 h; payload encryption
  round-trips with `http-ece` decrypt; query count bounded per page.
- Dashboard: card states (unsupported, iOS not installed, denied, off → subscribe → POST, on → unsubscribe →
  DELETE, key mismatch → re-subscribe) with mocked `PushManager`/`Notification`; sign-out cleanup best effort and
  skipped when impersonated.
- e2e `e2e/b11-web-push.spec.ts`: with both switches on (demo has every built switch on), `GET devices/push/key/`
  answers with the dev key and the account card renders; real delivery is not exercised (headless browsers have
  no push service).

## 6. Non-goals

Native push (FCM/APNs, held with E4); per-type push preferences (B5a mutes already apply); quiet hours; pushing
chat messages that create no notification row; badges on the app icon.
