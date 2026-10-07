# Plan 29 — B9d Languages (Spanish, quick translate) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** none (B9d depends on no other slice; it is built after B9b/B9c merge so it translates their strings and emails).

**Goal:** Ship slice B9d: Spanish for the dashboard and identity emails behind the `spanish` switch, and per-academy quick-translate overrides of dashboard texts behind the `quick_translate` switch.

**Architecture:** Spanish = a third i18next language with per-area `locales/es/*.json` (subset of English, fallback per key), `es` accepted by identity's language fields through one `effective_language` helper, and Spanish identity email templates with an English fallback. Quick translate = new tenant app `etqan.translations` (model, services, anonymous read API + admin write API) merged into i18next at runtime, and a settings page.

**Tech Stack:** Django 6 + DRF + django-tenants; React + TanStack Router/Query + zod + i18next + vitest + Playwright.

**Spec:** `docs/superpowers/specs/2026-10-04-b9d-languages-design.md` (L-1…L-13). Ledger D11, D22.

## Global Constraints

- Switches under `# ── phase B9 ──` (after B9c's), `built=True`, off: `spanish` (platform), `quick_translate` (platform). FeatureCode `// B9d` block.
- `page.quick_translate` flipped to in use in `PAGES` (comment updated). New app `etqan.translations` under every B9 marker (TENANT_APPS, api_router `path("translations/", …)`, both pyproject sections: forbidden-list line + contract importing only `etqan.platform`).
- Exact values: override key regex `^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$`, key ≤ 200, value ≤ 500, 2000 rows per academy; refused in values: `<`, `>`, `$t(`, `{{-`, any `{{…}}` not matching `{{\s*\w+\s*}}`; GET `Cache-Control: max-age=60`; GET throttled with the site's public throttle class.
- `es` accepted only while `spanish` is on (validators, `me` PATCH, account creation); stored `es` kept when off; `effective_language(user)` → `en` for a stored `es` while off.
- Identity emails: `.es.txt` for every identity email template present at build time; missing `es` template → English template and subject (never an error).
- Notifications/billing language rules unchanged.
- New locale files: `dashboard/src/locales/es/<area>.json` for every `en` area at build time; `dashboard/src/locales/{en,ar,es}/translations.json` for the page's own strings (en/ar key-equal; es subset).
- Run gates one at a time (focused pytest via `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django pytest <paths>`; `just test-backend`; `just lint-backend`; `just check-boundaries`; dashboard vitest, `pnpm test:coverage`, `just test-frontend`, `just lint-frontend`; `just e2e`).
- Coverage: backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.

## Review Focus

1. **A Spanish-speaking user while the academy turns Spanish off** → English dashboard and emails, stored preference kept, Spanish back when turned on (Task 2, Task 4 tests).
2. **An override value with `{{- html}}`, `$t(other)` or `<b>`** → refused by the server (Task 5 `test_unsafe_values_refused`).
3. **An `es` file with a key English no longer has, or a missing `{{name}}`** → the catalogue test fails (Task 3).
4. **An identity email added later with no Spanish template** → sent in English, no error (Task 2 `test_missing_es_template_falls_back`).
5. **Clearing an override** → the bundled text comes back without a reload (Task 6).

---

### Task 1: Switches and registry

**Files:** `backend/etqan/platform/features.py`, `platform/tests/test_features.py`, dashboard `schemas.ts`.
- [ ] Tests: both switches built and off by default. The `page.quick_translate` flip happens in Task 5 with its routes (the route test requires in-use codes to match routes). Commit.

### Task 2: `es` in identity (language fields, effective language, emails)

**Files:** `identity/models.py` (`User.Language.ES`, migration choices only), `platform/validators.py` (`clean_language(value, *, allow_es=False)` additive keyword; callers in identity pass `allow_es=features.enabled("spanish")`), `identity/api/serializers.py`, `identity/api/people_serializers.py`, `identity/services.py` (`effective_language(user)`; `create_person` accepts `es` only while on), `identity/emails.py` (`LANGUAGES` with `es`; `render_email` falls back to `.en.txt` + English subject when the `es` template is missing; all identity email senders use `effective_language`), `identity/adapter.py` (allauth confirmation in the effective language), `me` payload `effective_language`, `.es.txt` templates for every `templates/email/identity/*.en.txt` and allauth's confirmation templates, tests.
- [ ] Tests: `es` accepted/refused by the switch on every field; stored `es` kept when off and `effective_language` = `en`; every identity email rendered in Spanish when on, English when off; `test_missing_es_template_falls_back` (temporarily remove one `es` template via `override_settings` TEMPLATES dirs or a fake kind); notifications for an `es` reader use the academy default (existing behaviour pinned). Commit.

### Task 3: Spanish catalogue

**Files:** `dashboard/src/locales/es/*.json` (one per `en` area at this commit), `dashboard/src/lib/i18n.ts` (`es` resources; `SUPPORTED` includes `es`), the locales test (`src/locales/locales.test.ts` or wherever the ar/en equality test lives — add an `es` suite), tests.
- [ ] Translate every `en` value to Spanish (natural, academy-tutoring register; keep placeholders and `$t()` exactly). Tests: every `es` file has an `en` twin; `es` leaf keys ⊆ `en` leaf keys after stripping plural suffixes; placeholder sets equal per key (`{{x}}`, `{{x, fmt}}`, `$t(...)`); no empty values; ar/en equality test unchanged. Commit.

### Task 4: Language control and switch behaviour in the dashboard

**Files:** `ui/locale-toggle.tsx` (two-way toggle when Spanish is off; a menu with العربية / English / Español when on, icon-only trigger usable at 320 px, accessible name `locale.choose`), `lib/i18n.ts` / a small `useLanguages()` hook (filter by `hasFeature(me, "spanish")`, clamp stored `es` to `en` with `changeLanguage` when off; pre-sign-in pages offer `ar`/`en` only), `features/identity/components/ProfileEditForm.tsx`, `features/people/UserFieldsSection.tsx`, `features/identity/schemas.ts` language enum, locale keys in `locale.json` (en/ar) + `es`, tests.
- [ ] Tests: menu vs toggle by switch; three choices with Spanish on; `dir="ltr"` for `es`; clamping on switch off; profile/people forms offer `es` only when on and keep a stored `es` visible. Commit.

### Task 5: `etqan.translations` backend

**Files:** create `backend/etqan/translations/{__init__,apps,models,services}.py`, migration, `api/{serializers,views,urls}.py`, tests; markers (TENANT_APPS, api_router, pyproject both), route table `# B9d` (GET SELF_SERVICE-style anonymous: add to the public views list as the site's public views are; PUT/DELETE code `page.quick_translate`, feature `quick_translate`), registry `page.quick_translate` in use.

**Interfaces:** `services.overrides() -> dict[str, dict[str, str]]` (`{}` while off); `services.set_override(language, key, value, *, by)`; `services.clear_override(language, key)`; validation per Global Constraints (field errors on `key`/`value`; 400 `translations.limit` past 2000 rows).
- [ ] Tests: anonymous GET shape and `{}` while off; `Cache-Control`; throttle; PUT create/update, DELETE; permissions (admin, staff with/without `page.quick_translate`, teacher 403); switch off → 404 for PUT/DELETE after the permission check; key regex; `test_unsafe_values_refused` (`<`, `>`, `$t(`, `{{-`, `{{ a.b }}`, `{{a, number}}` refused; `{{name}}` allowed); row cap; cross-academy isolation. Commit.

### Task 6: Dashboard — overrides merge and Quick translate page

**Files:** `dashboard/src/features/translations/*` (api, queries, `mergeOverrides(i18n, data)` unflattening dotted keys and `addResourceBundle(lng, "common", nested, true, true)`, re-adding the bundled catalogue before re-merging so cleared keys restore), app start-up hook (fetch after the branding/me bootstrap, and again after sign-in), `routes/_authed/settings.quick-translate.tsx` (language tabs ar/en/es — es tab only when Spanish is on; key list from the bundled English catalogue; search by key/text; edit dialog with the default text, `{{word}}` placeholder check, save, reset), nav item under `// ── phase B9 ──` (permission `page.quick_translate`, feature `quick_translate`), `// B9d` entries in nav.test.ts / permissions.test.ts, locale `translations.json` (en, ar, es), regenerate route tree; tests.
- [ ] Tests: merge (nested keys, override wins, cleared key restores bundled text without reload, fetch failure silent); page search, placeholder mismatch blocks save, save/reset call the API and re-merge. Commit.

### Task 7: End-to-end

**Files:** `dashboard/e2e/b9-languages.spec.ts`.
- [ ] Turn `spanish` and `quick_translate` on with `manage("set_features", "demo", "--on", …)`; a user picks Español and sees Spanish navigation (and back); an admin overrides a navigation label in English, a second signed-in user sees it after reload; the admin clears it. Re-runnable; run twice, then the full `just e2e` on a fresh stack (memory: `just stream-down`, `just dev-backend`, `just migrate`, `just seed`). Commit.

## Final checks

- [ ] `just test`, `just lint`, `just e2e` green; final whole-slice review; minors logged; `ledger.py queue B9d`.
