# Phase B11 — Apps — Design

**Date:** 2026-10-09
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings (2 critical,
7 important, 8 minor) applied 2026-10-09.
**Phase:** B11 of `2026-09-24-parity-roadmap-design.md` §2: mobile and desktop apps (PANEL-008/009). Depends on
B2–B5 APIs (all four phase specs are recorded; B2, B3 merged; B4 and B5 finishing their last slices).
**Works under:** `2026-10-02-parallel-orchestration-design.md` (ledger, slices, merge queue, ownership).
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` (`P1 §x` / IDs) and `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`
(`TH §x`). TutorHamster's apps were never seen (TH §1.4, §4 U14: "runs locally on students' devices"; nothing
in the admin refers to them except the trial "request source = app" and the playlist "show in app only"
flag). Almost everything about what the apps do is therefore `[assumed]` (ledger D1).

This document is the phase spec (§1–§4: what B11 builds, how it is split, and the decisions that hold across
slices) and the first slice's spec (§5–§11: **B11a — installable app**). Later slices get their own specs,
designed against this one.

## 1. Goal

Teachers, students and parents (and the office) get an academy "app" on their phone and computer: an icon on
the home screen or desktop that opens their panel full-screen, with the academy's name and colours, and
(B11b) notifications that arrive even when the app is closed. Beyond that, a native mobile app (B11c–B11g)
is built only if the owner approves the new repository and the store and Firebase accounts it needs (§3,
escalation). Every feature is a per-academy switch, off by default (PO-5).

## 2. Scope spike: what exists today

Facts that set the shape of the phase (surveyed 2026-10-09 on trunk `f0915f7`):

| Area | Today |
|---|---|
| Panels | One dashboard (`/app/`) serves every role: office (admin, staff), teacher (`/teaching/*`: sessions with attendance and reports, payslips, balance and withdrawals, availability, homework, materials, reviews, consultations), student and parent (`/learning/*`: sessions, subscriptions, invoices with online pay, wallet, codes, progress, homework, certificates, recorded courses), plus chat (not parents), notifications and account. All of it already works at phone width. |
| Auth | Session cookie + CSRF only (`identity.authentication.SessionAuthentication`); no token auth. 2FA, Google sign-in and phone + password exist (B9b). The tenant is the Host header. |
| Notifications | In-app rows (`notifications.Notification`, one per recipient, rendered in the recipient's language) polled every 60 s; email. No push of any kind. B5 left push to B11 (B5 spec §3). |
| Chat | Polling (10–60 s); no websockets. |
| Meetings | `Session.meeting_url` (Zoom or Jitsi) opened as a plain link; the teacher's Zoom start link from `GET sessions/<id>/host-link/`. |
| PWA | None: no manifest, no service worker, no icons (`dashboard/index.html` favicon is `data:,`). `brand/favicons-app-icons/README.md` only lists planned files. |
| Desktop / native | Nothing (no Electron, Tauri, Capacitor, Expo, React Native). |
| App hints | `TrialRequest.source` has `app` (B2e); `Playlist.app_only` keeps a playlist off the web storefront (B7b). |

## 3. Slices

| Slice | Contents | Requires |
|---|---|---|
| **B11a — installable app** | Web app manifest per academy (name, colours, icons made from its logo), a service worker with an offline page, an "Install the app" card on the account page. Installs as a desktop app (Chrome/Edge on Windows, macOS, Linux; Safari on macOS) and on Android/iOS home screens. Switch `installable_app`. | — |
| **B11b — web push** | Push subscriptions per browser/device; a beat job that pushes each new in-app notification to its recipient's devices; per-device on/off on the account page. Switch `push_notifications` (requires `installable_app`). Needs request R-B11b-1 to B5 (§4). | B11a; R-B11b-1 done |
| **B11c — app sign-in API** | Only if escalation E-B11-1 is approved. Bearer tokens for native apps (one per signed-in device, hashed, revocable, listed beside sign-in history), app login incl. 2FA, academy lookup on the base domain, native push tokens (FCM) through `integrations.resolve('push')` (Etqan default only). | B11b; E-B11-1 approved |
| **B11d — mobile app shell** | New repo `etqan_tutor_mobile` (Expo / React Native, TypeScript): academy picker, sign-in, notifications with push, account, ar/en/es with RTL, academy branding. | B11c; repo created by the owner/conductor |
| **B11e — teacher in the app** | Today and upcoming sessions, join / start meeting (host link read fresh, never stored), attendance and session report, homework set, payslips and balance (read). | B11d |
| **B11f — students and parents in the app** | Sessions and join, homework (answer), progress and certificates (read), invoices with pay in the system browser, wallet balance, recorded courses the student is enrolled in (including `app_only` playlists), trial request with source `app`. | B11d |
| **B11g — chat in the app** | The B5e/B5f chat (polling, as the web). | B11d |

Desktop needs no further slice: the installed web app (B11a) is the desktop app (B11-2).

**E-B11-1 answered (ledger E4, owner, 2026-10-10): hold the native mobile app.** B11 ships B11a and B11b, then stops;
B11c–B11g are deferred until the owner reopens them (no new repo, no Apple/Google/Firebase accounts) and are not
recorded as ledger slices. B11-7's native-push half (FCM via `integrations.resolve('push')`) is deferred with them.

## 4. Phase decisions

| # | Decision | Source |
|---|---|---|
| B11-1 | **The installable web app comes first and is the baseline on every platform.** It reuses the whole dashboard (every role, every page, every later phase's pages) with no second codebase, needs no store account, and is the only way to ship "an app" before E-B11-1 is answered. | roadmap R2 (usable sooner); CLAUDE.md "keep it simple"; §2 (dashboard already serves all roles) · [assumed] |
| B11-2 | **Desktop = the installed web app.** No Electron/Tauri build: nothing desktop-only was observed (TH U14), and an installed PWA gives the same window, icon and launch. | TH §1.1, U14 · [assumed] |
| B11-3 | **A native mobile app is proposed, not assumed.** It needs a new GitHub repo (`etqan_tutor_mobile`, orchestration §6.3), Apple Developer and Google Play accounts, and a Firebase project for push — all §8.1 "external accounts". B11 escalates (E-B11-1) and builds B11c–B11g only on approval. Store submission and release are owner actions, never a slice's. | orchestration §6.3, §8.1; conductor message 2026-10-09 |
| B11-4 | **One Etqan app for all academies, not one per academy.** The native app opens with an academy picker (subdomain or custom domain, checked against the base domain's lookup) and then shows that academy's branding; white-label store listings are out. | [assumed] (a store listing per tenant is not CRUD-first) |
| B11-5 | **No selling of digital content inside the native app.** App stores require their own billing for digital goods; the app sells nothing: recorded courses show only enrolments (`app_only` playlists included, B7b), codes are not redeemed in the app, and invoices for live lessons open the existing web pay page in the system browser. The installed web app is the website and keeps every web feature. | B7 spec §3 ("the apps themselves are B11"), B7b §7 ("selling on the apps (B11)"); [assumed] store rules |
| B11-6 | **Push is a delivery of the in-app notification, nothing new to write.** A push carries the `Notification` row's title and body (already in the recipient's language) and opens `/app/notifications`. B11 reads new rows through a `notifications.services` read service (R-B11b-1) on its own beat job; notifications never imports B11. Mutes (B5a opt-outs) already stop the row being created, so they stop the push too. **This is a narrow exception to D39's "no app imports etqan.notifications"** (and the `pyproject.toml` contract that enforces it): `etqan.devices` alone may import `etqan.notifications.services`, read-only, for push delivery. Recorded as a shared decision amending D39 (affects B5); D39's reason — notices are finders over the owning app's read services, nobody pushes into notifications — is untouched. | ledger D39; B5 spec §3 (push → B11) |
| B11-7 | **Web push keys are platform settings, not an integration account.** VAPID needs no outside account (the browser vendors' push services are free and keyless); the public key is env config (`WEB_PUSH_VAPID_PUBLIC_KEY`); the private key is a secret, so it is stored Fernet-encrypted (`WEB_PUSH_VAPID_PRIVATE_KEY_ENC`, made with `etqan.platform.secrets.encrypt`) and read only through `etqan.platform.secrets.decrypt` (CLAUDE.md: secrets go through `etqan.platform.secrets`; conductor ruling 2026-10-09). Web push is not metered. Native push (FCM) is an outside account and goes through `integrations.resolve('push')`, Etqan default only (B11c). | CLAUDE.md (outside services via resolve; secrets); integrations IN-5 · [assumed] |
| B11-8 | **One new tenant app, `etqan.devices`**, owned by B11, under the `── phase B11 ──` marker in `TENANT_APPS`, with its own import contract (reads other apps only through their services; nothing imports it). All B11 backend code lives there except additive read services in other apps, made under a claim or by request. | orchestration §4.3; B6-1/AI-1 precedent |
| B11-9 | **Each slice has its own switch, built off by default**, under the `── phase B11 ──` marker of the feature registry: `installable_app` (B11a), `push_notifications` (B11b, requires `installable_app`), `mobile_app` (B11c, gates app sign-in for that academy). | PO-5; Plan 13 |
| B11-10 | **The apps add no business rule.** Every action in a native screen calls the same `/api/v1/` endpoint the web uses, with the same permissions, features and impersonation guards (D19); no endpoint is added for the apps apart from B11c's sign-in, lookup and device routes. | CLAUDE.md (all API under /api/v1/); D19 |
| B11-11 | **Strings:** new area files `dashboard/src/locales/{en,ar}/apps.json` only (es falls back, D11/D22). The native app keeps its own catalogues in its repo. | D11, D22; CLAUDE.md |

**Requests and claims across the phase:**

- **R-B11b-1 → B5 (notifications)**, filed 2026-10-09 (R11), amended 2026-10-10 by the B11b spec §3 (a time-window
  read `created_since(*, since, after_id=0, limit=200)` replaces the id cursor); B11b's push job builds on it only
  after B5 confirms.
- **B11a claim on `etqan.site`** (conductor's since B8 merged): additive read service
  `site.services.branding_snapshot() -> BrandingSnapshot(name_ar, name_en, primary_color, primary_text,
  logo_name, updated_at)`, one query, no model change (§7.2).
- **B11c claim on `etqan.identity`** (conductor's since B9 merged) for the bearer-token authentication class
  and its place in `REST_FRAMEWORK`; and on `etqan.integrations` for the `push` service. Detailed in B11c's
  spec.

**Escalation E-B11-1 (§8.1, external accounts):** "Approve a native mobile app (B11c–B11g)? It needs: a new
private repo `Etqan-agency/etqan_tutor_mobile`, an Apple Developer account, a Google Play developer account
and a Firebase project (FCM) owned by Etqan. Without it B11 ships the installable web app (desktop + mobile
home screen) and web push, then stops."

## 5. B11a — installable app: goal

When the academy turns `installable_app` on, any signed-in user can install the dashboard as an app on a
computer or phone. It opens full-screen at `/app/`, shows the academy's name and an icon made from the
academy's logo in its primary colour, and shows a friendly offline page instead of a browser error when the
network is down. Turning the switch off removes the manifest and unregisters the service worker at the next
signed-in page load. Copies already installed stay on the device (the browser owns them); they keep opening
`/app/` as a normal page, without the offline page.

## 6. B11a decisions

| # | Decision | Source |
|---|---|---|
| A-1 | **Manifest served by Django, per academy:** `GET /api/v1/devices/manifest.webmanifest`, anonymous (no authentication classes, `AllowAny`), returned as a plain Django `JsonResponse(content_type="application/manifest+json")` (DRF renderers cannot give that type); `Cache-Control: public, max-age=300` on 200 only; `404` while `installable_app` is off. The browser fetches manifests without cookies, so nothing may depend on a session; `platform.features.enabled` reads the tenant from the Host header, which works anonymously. | W3C manifest fetch is credential-less; `platform/features.py` · [assumed] |
| A-2 | **Manifest content:** `id` and `start_url` `/app/`, `scope` `/app/`, `display` `standalone`, `name` and `short_name` = the branding name in the academy's default language (`academy.services.get_settings().default_language`; `name_ar` for `ar`, else `name_en`; the other when the chosen one is blank — both are required fields, so one always exists), `lang` and `dir` (`rtl` for `ar`), `theme_color` = `primary_color`, `background_color` `#FFFFFF`, icons 192, 512 (`any`) and 512 (`maskable`), each URL carrying `?v=<branding updated_at epoch seconds>`. | [assumed]; site.Branding fields (B8a) |
| A-3 | **Icons made from the academy logo:** `GET /api/v1/devices/icons/<kind>.png`, kind ∈ `192`, `512`, `maskable-512`, `apple-touch-180`; anonymous; plain `HttpResponse(png, content_type="image/png")`; `404` while off or for another kind. A square of `primary_color` with the logo fitted, centred, into 70 % of the side (`maskable-512`: 56 %, inside the maskable safe zone) keeping its aspect ratio; with no logo or an unreadable one (logged, not raised), the first letter of the name (A-2's choice) in `primary_text` at 50 % of the side, drawn with a TTF bundled in `etqan/devices/fonts/` (DejaVuSans, which covers Arabic; licence file alongside). The logo is opened with Pillow under `Image.MAX_IMAGE_PIXELS` limits (logos are already PNG/JPEG/WEBP, re-encoded at upload by `site.images.clean_image`), converted to RGBA, resized and saved as a new PNG — the stored file is never served. PNG bytes are cached in Django's cache (key `devices:icon:<kind>:<updated_at epoch>`; django-tenants' `make_key` already prefixes the schema), `Cache-Control: public, max-age=86400` on 200 only. | `site/images.py`; `config/settings/base.py` cache `KEY_FUNCTION`; `brand/favicons-app-icons` rules (solid tile, survives masking) · [assumed] |
| A-4 | **The dashboard turns installability on and off itself, strictly.** The rule reads `useMe()` directly (not `useHasFeature`/`hasFeature`, which treat a missing `me` or a missing provider as allow-all): while `me` is loading nothing happens; when `me.features.includes("installable_app")` is true it adds `<link rel="manifest" href="/api/v1/devices/manifest.webmanifest">`, `<link rel="apple-touch-icon" href="/api/v1/devices/icons/apple-touch-180.png?v=…">` and `<meta name="theme-color">` to `<head>` and registers `/app/sw.js` with `{scope: "/app/"}`; when it is false it removes those tags, unregisters every registration whose scope ends in `/app/` and deletes the worker's caches (`devices-` prefix). The `?v` and theme colour come from the manifest, fetched once per page load when on. Mounted in the signed-in layout (`_authed.tsx`), so install is offered after sign-in. | `identity/api/views.py` (`me.features` for every role); `features/identity/permissions.tsx` (allow-all fallbacks); dashboard is a static bundle, so `index.html` cannot vary per academy |
| A-5 | **The service worker caches only the offline page.** `install` caches `/app/offline.html` and calls `self.skipWaiting()` (safe: there is no cached app state to keep consistent, and without it a new worker waits until every window of an installed desktop app closes); `activate` drops caches with another version and calls `clients.claim()`; `fetch` handles only navigation requests inside `/app/`: network first, the cached offline page on network failure. API calls, assets and other origins are never intercepted, so no stale data or stale bundle is ever served. Its cache name is `devices-<version>`, the version constant bumped when the file changes. nginx serves `/app/*` with `Cache-Control: no-cache`, and Vite (dev and `preview`, used by CI e2e) serves `public/` under `/app/`. | CLAUDE.md (CRUD-first, no offline data); `dashboard/nginx.conf`; `vite.config.ts` |
| A-6 | **Offline page:** static `dashboard/public/offline.html`, inline CSS only, Arabic and English text side by side, a "Try again" button that reloads. No academy data. | [assumed] |
| A-7 | **Install card on the account page** (all roles), shown only when A-4's strict rule is on and the user is not impersonated (`me.impersonator` unset, D19 spirit): when already running installed (`display-mode: standalone`, or `navigator.standalone` on iOS) it says so; when the browser offered an install prompt (`beforeinstallprompt`, Chromium on desktop and Android) an "Install" button; on iPhone/iPad Safari (iPad detected as `MacIntel` with `navigator.maxTouchPoints > 1`), the Share → "Add to Home Screen" steps; on macOS Safari 17+, File → "Add to Dock"; otherwise the browser-menu steps. The prompt event is captured by a listener installed at app start (`main.tsx` imports `features/apps/install`). | [assumed]; D19 |
| A-8 | **Switch:** `installable_app`, label "Installable app (desktop and mobile)" / "تطبيق قابل للتثبيت (سطح المكتب والجوال)", group `platform`, built, default off, no `requires`. | B11-9; PO-5 |
| A-9 | **No new model and no migration.** `etqan.devices` in B11a is views, services and tests only. | [assumed] |

## 7. B11a backend

### 7.1 `etqan.devices`
- New tenant app `etqan.devices` (AppConfig `label = "devices"`), one line in `TENANT_APPS` under
  `── phase B11 ──`, routed as `devices/` in `config/api_router.py` under the B11 marker.
- `devices.services.manifest() -> dict` and `devices.services.icon(kind) -> bytes`; both raise
  `NotFoundError` while the switch is off (`platform.features` check) or for an unknown kind.
- Views: `ManifestView`, `IconView` — `authentication_classes = ()`, `permission_classes = (AllowAny,)`,
  plain Django responses (A-1, A-3), `Cache-Control` set only on 200; no throttle beyond the caches (cheap,
  cached, public data the public site already shows).
- Import contract: `etqan.devices` may import only `etqan.platform`, `etqan.site.services`,
  `etqan.academy.services` (B11b adds `etqan.notifications.services`, B11-6); no app imports
  `etqan.devices`. Added to the platform contract's forbidden list and the contract section under the B11
  markers in `pyproject.toml`.
- `fonts/DejaVuSans.ttf` + `LICENSE` copied into the app (the existing copy belongs to `etqan_billing`).

### 7.2 Claim on `etqan.site`
`site.services.branding_snapshot()` calls `ensure_site_defaults(connection.tenant.name)` (as the public
`BrandingView` does, so an academy without a `Branding` row never 500s an anonymous request), then returns a
frozen dataclass from `Branding.load()`: `name_ar, name_en, primary_color, primary_text, logo_name` (the
storage name, `""` when unset) and `updated_at`. Additive, no model change; one commit under a ledger claim,
released after.

## 8. B11a dashboard

- `src/features/apps/`: `install.ts` (captures `beforeinstallprompt`, exposes a tiny store), `useInstallableApp.ts`
  (the A-4 effect), `InstallAppCard.tsx` (A-7), `platform.ts` (pure detection helpers: standalone, iOS incl.
  iPadOS, macOS Safari ≥ 17).
- Shared files edited outside markers (one additive line each, called out in the PR):
  `dashboard/src/main.tsx` (import `@/features/apps/install`), `routes/_authed.tsx` (`<InstallableApp />`
  inside the layout), `routes/_authed/account.tsx` (`<InstallAppCard />`, which applies A-4/A-7's strict rule
  itself), and the `FeatureCode` union in `features/identity/schemas.ts` (`"installable_app"` at the end with a
  `// Phase B11, slice B11a` comment; the union has no markers).
- `public/sw.js` and `public/offline.html` (served at `/app/sw.js` and `/app/offline.html`).
- Strings in `locales/{en,ar}/apps.json`.

## 9. Errors and edge cases

- Switch off: manifest and icons `404`; the dashboard removes its tags, unregisters the worker and deletes its
  caches (A-4). Installed copies stay installed (§5).
- `primary_color` invalid hex (should not happen; B8a validates): fall back to `#0E7C66`.
- Service worker registration fails (private mode, old browser): logged to the console, the card shows the
  browser-menu steps; nothing else changes.
- Tenancy: manifest and icons are per Host (django-tenants); cache keys are schema-prefixed by
  django-tenants' `make_key`.
- Known limit, documented in the card's help text for iOS only: in an iOS home-screen app, Google sign-in
  (`/accounts/*`, outside the `/app/` scope) opens in an in-app Safari view whose cookies are separate, so
  the user may need to sign in with a password inside the app. Nothing is built for it in B11a.

## 10. Testing

- Backend (pytest, ≥ 80 %): manifest fields per language/dir, name fallback, `404` when off, content type and
  cache headers only on 200, no `Branding` row → defaults created; icons for each kind (size, mode, colour at a
  corner pixel, logo vs letter, an Arabic first letter renders non-blank, unreadable logo → letter), cache
  hit; `branding_snapshot` query count; import contract.
- Dashboard (vitest): nothing while `me` loads; head tags added/removed with the switch; worker
  registered/unregistered and caches deleted (mocked `navigator.serviceWorker`, `caches`); card states per
  platform helper (incl. iPad as `MacIntel` + touch, impersonation hides it); strings ar/en equal.
- e2e `e2e/b11-installable-app.spec.ts`: demo has every built switch on (`seed_dev`), so `installable_app` is
  on by default and every e2e spec now runs with the worker registered (it touches navigations only, so the
  risk is low). The spec checks: the manifest link is in `<head>`, the manifest JSON has the academy name and
  `start_url` `/app/`, an icon is a PNG, `navigator.serviceWorker.ready` resolves with scope `/app/`, the
  account page shows the card; then switches it off → manifest `404`, and restores it in `finally`/`afterAll`
  (the `b4-balance.spec.ts` pattern).

## 11. Non-goals (phase)

Offline use of data or background sync; an app store listing per academy; Electron/Tauri; selling inside
the native app; built-in video (roadmap §3, still out); SMS; push from anything but in-app notifications.
