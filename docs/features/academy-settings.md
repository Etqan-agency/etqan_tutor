# Academy settings, appearance, languages and system status

These are the per-academy knobs the academy itself controls: the settings row (timezone, currency,
default language, scheduling and billing defaults), the browser's named theme, the dashboard
language (Arabic, English, optional Spanish), the academy's own rewording of dashboard text (quick
translate), and the System status page. Academy admins, and staff holding the right codes, edit them
in the dashboard's Settings area. Every signed-in user reads the settings, because forms need the
currency and timezone. Feature switches are Etqan's, not the academy's: see
[feature-toggles.md](feature-toggles.md). The name, logo and colours belong to the public site:
see [website.md](website.md#branding).

## Concepts

| Model | Schema | Purpose |
|---|---|---|
| `academy.AcademySettings` | academy | One row per academy (a singleton by convention, `.first()`). Fields: `timezone`, `default_currency` (ISO 4217), `default_language` (`ar` / `en`, default `ar`), `generation_horizon_days` (1–60, default 14), `renewal_grace_days` (0–60, default 7), `absent_consumes_session`, `excused_consumes_session`, `auto_invoice_on_subscription`, `invoice_due_days` (0–90), `postpone_limit_minutes` (0–10080). `supervision_enabled` is a dead column: the `supervision` feature replaced it. |
| `translations.TranslationOverride` | academy | The academy's own text for one dashboard i18n key in one language (`ar` / `en` / `es`). Unique per (`language`, `key`). `value` is at most 500 characters. |
| `systemstatus.JobRun` | academy | One manual run of a background job: `job` (only `reconcile_subscriptions`), `status` (`queued` / `running` / `ok` / `failed`), `result`, `error`, `requested_by`, timestamps. A partial unique constraint allows one open (queued or running) run per job. |

`Academy.timezone` and `Academy.currency` (public schema) only seed `AcademySettings` when the
academy is created. After that, code reads `AcademySettings`, for example in
`site.services.academy_today()`.

## How it works

### Settings

- `etqan/academy/services.py:get_settings()` returns the row. If it is missing, it is created from
  the `Academy` row ("self-healed").
- `update_settings(**fields)` validates through `platform.validators` (`clean_timezone`,
  `clean_currency`, `clean_language`) and the bounds above.
- `postpone_limit_minutes` is hidden from the payload and refused on write unless the
  `postponement` feature is on. `supervision_enabled` in the payload is read-only and reflects
  `features.enabled("supervision")`.
- Other apps read these values through `academy.services` only. Scheduling reads the horizon and
  grace days. Billing reads the invoice settings. Attendance counting reads the
  `*_consumes_session` flags.

### Appearance (named themes)

- A theme is a per-browser choice, not an academy setting. It is stored in `localStorage`
  (`etqan-palette`), next to the light/dark key `etqan-theme`.
- The four palettes are `default`, `dracula` (dark only), `nord` and `sunset`. A theme replaces the
  neutral tokens only. The academy's brand primary and accent colours stay.
- Gated by the `themes` feature. With the feature off, or before sign-in, the page uses Default. A
  stored choice is ignored, not deleted. The picker (`AppearanceCard`) is on My account
  (`/app/account`) for every role.
- No backend involvement beyond the feature switch.

### Languages

- The dashboard has three catalogues: `dashboard/src/locales/{ar,en,es}/<area>.json`, one file per
  area. Each `es` file is a subset of its `en` file. Missing keys fall back to English.
- Spanish is gated by the `spanish` feature. `identity/services.py:effective_language(user)`
  returns `en` for a stored `es` while the feature is off, and the stored value is kept.
  `GET identity/me/` returns both `preferred_language` and `effective_language`. On the dashboard,
  `features/identity/languages.ts:useLanguages` offers `es` only while the feature is on.
- The academy's `default_language` stays `ar` / `en`. It is the language new accounts get.
- Arabic is RTL (`lib/i18n.ts:RTL_LOCALES`, `lib/direction.tsx`).

### Quick translate

- `etqan/translations/services.py`:
  - `set_override` creates or updates. It validates the language, the key (dotted, at most 200
    characters, no `__proto__` / `constructor` / `prototype` segment) and the value. A value must be
    plain text: no `<`, `>`, `$t(` or `{{-`, and only `{{word}}` placeholders. An academy can have at
    most 2000 rows.
  - `clear_override` deletes one row.
  - `overrides()` returns every row grouped by language as flat dotted keys, or `{}` while the
    `quick_translate` feature is off. Rows are kept while it is off.
- The dashboard mounts `<TranslationOverrides />` in `main.tsx`. It fetches
  `GET /api/v1/translations/` (anonymous, so the sign-in pages get the overrides too), unflattens
  the keys, and merges them into the i18next bundles (`features/translations/merge.ts`). It merges
  again after a save or a clear.
- The Settings → Quick translate page lists every key of the bundled English catalogue, with the
  chosen language's bundled text and the override beside it. It has search and paging, and an edit
  dialog that checks the same rules on the client (`features/translations/keys.ts`).

### System status

- `etqan/systemstatus/services.py:overview()` returns the app version (`ETQAN_VERSION`, or `dev`),
  the subdomain, the academy timezone and local time, the server UTC time, the number of features
  on, and a static list of jobs (`reconcile_subscriptions` hourly, `notifications` every minute).
- `request_run(job, by=)`:
  1. Marks open runs older than 1 hour as `failed` ("Timed out.").
  2. Creates a `queued` `JobRun`. A second open run hits the constraint and gets 409
     `systemstatus.run_open`.
  3. Queues `systemstatus.run_job` on commit.
- Task `systemstatus.run_job(schema_name, run_id)` (`systemstatus/tasks.py`):
  1. Enters the academy through `academy_context`. A suspended academy fails the run.
  2. Moves the run from `queued` to `running`.
  3. Runs `scheduling.services.run_lifecycle()` in one transaction, under a per-schema Postgres
     advisory lock.
  4. Records `ok` with the result, or `failed` with the error.
- Gated by the `system_status` feature and the code `page.system_status`.

## API

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/academy/settings/` | Any signed-in user (`academy_settings.view` gates the screen) | Read settings |
| PATCH | `/api/v1/academy/settings/` | Admin, or staff with `academy_settings.update` | Update settings (partial) |
| GET | `/api/v1/academy/features/` | Admins | Read-only feature list ([feature-toggles.md](feature-toggles.md)) |
| GET | `/api/v1/translations/` | Anyone (anonymous, throttle scope `translations` 120/min, `Cache-Control: max-age=60`) | All overrides by language. `{}` while `quick_translate` is off |
| PUT | `/api/v1/translations/<lang>/<key>/` | `page.quick_translate`, feature `quick_translate` | Set one override (`{value}`). 201 if new, 200 if updated |
| DELETE | `/api/v1/translations/<lang>/<key>/` | `page.quick_translate`, feature `quick_translate` | Clear one override (204) |
| GET | `/api/v1/system-status/` | `page.system_status`, feature `system_status` | Overview plus the last 20 runs |
| POST | `/api/v1/system-status/runs/` | `page.system_status`, feature `system_status` | Queue a run (`{job: "reconcile_subscriptions"}`). 202, or 409 when a run is open |

## Dashboard

| Route | Screen |
|---|---|
| `/app/settings` | Redirects to `/settings/academy` |
| `/app/settings/academy` (`routes/_authed/settings.academy.tsx`) | `features/academy/AcademySettingsForm.tsx` and the notification settings form |
| `/app/settings/features` | Read-only features list (`features/academy/FeaturesPage.tsx`) |
| `/app/settings/quick-translate` | `features/translations/QuickTranslatePage.tsx` (feature `quick_translate`). Spanish appears in its language picker only while `spanish` is on |
| `/app/settings/system-status` | `features/systemstatus/SystemStatusPage.tsx` (feature `system_status`) |
| `/app/account` | `AppearanceCard` while `themes` is on |

App shell (`dashboard/src/features/shell/`): `AppShell`, `AppSidebar`, `AppTopbar` and `UserMenu`.
`nav.ts` holds `NAV_ITEMS`, each with `permission`, `feature`, `requiresRole` and `group`, plus the
Website tabs. `PermissionGate` turns `staticData.permission` / `staticData.feature` on routes into
`NoAccess` / `FeatureOff` screens. The office-only layouts call `requireOffice`.

Global providers in `dashboard/src/main.tsx`: `ThemeProvider` (light/dark), `DirectionProvider`,
`PaletteProvider` (named themes), `BrandProvider` (academy colours, see website.md) and
`TranslationOverrides`.

## Background jobs

- `systemstatus.run_job`: only on demand, for one academy. It is not on the beat schedule. The
  hourly `scheduling.run_daily` beat task is what normally runs the lifecycle for every academy.

## Configuration

- Features: `themes`, `spanish`, `quick_translate`, `system_status` (all `platform`, off by
  default). `postponement` controls `postpone_limit_minutes`.
- Permission codes: `academy_settings.view` / `.update`, `page.quick_translate`,
  `page.system_status`.
- Env: `ETQAN_VERSION` (shown on System status).
- `REST_FRAMEWORK` throttle rate `translations: 120/minute`.

## Code map

- `backend/etqan/academy/` (`models.py`, `services.py`, `api/`)
- `backend/etqan/translations/` (`models.py`, `services.py`, `api/`)
- `backend/etqan/systemstatus/` (`models.py`, `services.py`, `tasks.py`, `api/`)
- `backend/etqan/platform/validators.py`: `clean_timezone`, `clean_currency`, `clean_language`
- `backend/etqan/identity/services.py`: `effective_language`
- `dashboard/src/features/academy/`, `features/appearance/`, `features/translations/`,
  `features/systemstatus/`, `features/shell/`
- `dashboard/src/lib/i18n.ts`, `lib/theme.tsx`, `lib/direction.tsx`, `dashboard/src/locales/`
- `dashboard/src/routes/_authed/settings.*.tsx`, `routes/_authed/account.tsx`

## Design history

- [v1 design](../superpowers/specs/2026-09-23-etqan-tutor-v1-design.md) §4.1: the original
  `AcademySettings`. Its branding fields moved to `site.Branding` in the academy-sites spec.
- Scheduling, billing and sessions specs
  ([subscriptions-scheduling](../superpowers/specs/2026-09-24-subscriptions-scheduling-design.md),
  [sessions-attendance](../superpowers/specs/2026-09-25-sessions-attendance-design.md),
  [billing](../superpowers/specs/2026-09-25-billing-design.md)): added the horizon, grace,
  consumption and invoice fields. [B2b](../superpowers/specs/2026-10-03-b2b-times-postponement-design.md)
  added `postpone_limit_minutes`.
- [Feature toggles](../superpowers/specs/2026-09-30-feature-toggles-design.md): replaced
  `supervision_enabled` with the `supervision` switch.
- [Platform extras (B9a)](../superpowers/specs/2026-10-03-platform-extras-design.md) A-1…A-3
  (named themes, per browser) and A-13…A-15 (System status, manual reconcile). Implemented in
  [Plan 18](../superpowers/plans/2026-10-03-plan-18-platform.md).
- [B9d languages](../superpowers/specs/2026-10-04-b9d-languages-design.md) L-1…L-12: Spanish and
  quick translate. Implemented in [Plan 29](../superpowers/plans/2026-10-05-plan-29-languages.md).
