# B9d — Languages (Spanish, quick translate) — Design

**Date:** 2026-10-04
**Status:** Approved after an independent spec review (orchestration spec PO-3); review findings
1–18 applied 2026-10-05.
**Phase spec:** `2026-10-03-platform-extras-design.md` (B9-6; ledger D11).
**Slice:** B9d — AUTH-014 a third interface language (Spanish) and SYS-007 quick translate.
**Requires:** none. Built last, so it translates the most strings; identity emails that exist when it
is built get Spanish, and any later one falls back to English (L-4).

## 1. Goal

An academy can offer its dashboard in Spanish as well as Arabic and English, people can choose it as
their language and get their account emails in it, and an academy's admins can reword any dashboard
text per language without a release — each behind a switch, off by default.

## 2. Decisions

### 2.1 Spanish

| # | Decision | Source |
|---|---|---|
| L-1 | **Dashboard catalogue:** `dashboard/src/locales/es/<area>.json` for every area present when the slice is built (all files in `locales/en/` at that commit). Each `es` file is a **subset** of the same `en` file's keys (compared after stripping plural suffixes, as `locales.test.ts`'s `leaves()` does; `es` plurals use `_one/_many/_other`), every value non-empty, and with the same interpolation placeholders as English (`{{name}}`, `{{n, format}}` and `$t(...)` extracted). Missing keys fall back to English per key (`fallbackLng: "en"`). The `ar`/`en` equality test is unchanged (D11); a separate `es` test is added. `es` ships eagerly like `ar`/`en` (the catalogue is small). Left-to-right (`RTL_LOCALES` stays `["ar"]`). | TH §1.1, P1 §2.3; ledger D11; `[assumed]` subset rule and eager loading |
| L-2 | The Spanish text is produced in this slice (machine-assisted) and checked by those tests; a native-speaker review is an owner follow-up, not a gate. Bilingual **data** fields (tag names, role names, feature labels: `label_ar`/`label_en`, `name_ar`/`name_en`) show their English value to Spanish readers. | `[assumed]` |
| L-3 | **`es` everywhere a language is chosen or read** (additive; B9 owns `identity.auth` and the identity app's own API/UI): `User.Language` gains `es` (migration: choices only, no data change); `platform/validators.py` `clean_language` / `LANGUAGES` accept `es` and its message names three languages; `identity/emails.py` `LANGUAGES`; `identity/api/serializers.py` `MeUpdateSerializer` language field; `identity/api/people_serializers.py` `LANGUAGES`; dashboard `features/identity/schemas.ts` language enum, `ProfileEditForm.tsx` (no `ar`/`en` fallback that turns `es` into `en`), `people/UserFieldsSection.tsx`, `lib/i18n.ts` `SUPPORTED`/`Locale` and resources. `Academy.default_language` / `AcademySettingsForm` stay `ar`/`en`. Account creation (`create_person` / registration) accepts `es` only while the switch is on. | review 3; B9-5 |
| L-4 | **Emails:** identity's emails get `.es.txt` templates and Spanish subjects for every identity email that exists at build time (invite, reset, security notices, quick-login link, and B9c's if merged first). `identity.emails.render_email` falls back to the English template and subject when an `es` template is missing (so a later email never fails). Other apps keep their own rule: notifications' `language_for(preferred, default)` gives an `es` reader **the academy's default language**, as today (unchanged); billing texts follow the academy default (unchanged). | review 1; D11 |
| L-5 | Switch **`spanish`** (new, `platform`, off). One server helper `identity.services.effective_language(user) -> "ar"|"en"|"es"` returns `en` for a stored `es` while the switch is off, and identity's emails and the `me` payload's new `effective_language` field use it; `me.preferred_language` still returns the stored value (kept, not rewritten — like a stored named theme, B9a A-3). `PATCH me` that sets `es` is refused (400 on `preferred_language`) while off; a stored `es` sent back unchanged is accepted and kept (the profile and people forms always resend the language). Registration (B9c) accepts `es` as the page language only while on, and its emails follow the same `.es` template / English fallback rule. Dashboard: `SUPPORTED` is filtered by `hasFeature(me, "spanish")`; a stored `es` locale (`localStorage["etqan-locale"]` or `me.effective_language`) is clamped to `en` with `i18n.changeLanguage` when off; pages before sign-in offer only `ar`/`en` (switches unknown there, as B9a A-3). | review 2; B9a A-3; FT-4 |
| L-6 | **Language control:** with Spanish on, the topbar toggle becomes a small menu (العربية / English / Español, each labelled in its own language, accessible name from `locale.choose`), staying usable at 320 px (icon-only button opening the menu); with Spanish off it stays today's two-way toggle. My account's language select lists the three. | review 4 |

### 2.2 Quick translate

| # | Decision | Source |
|---|---|---|
| L-7 | **Quick translate:** admins, and staff holding `page.quick_translate` (flipped to in use in `PAGES`, its comment updated, B9-3), override dashboard texts per language in Settings → Quick translate: the key list is the bundled **English** catalogue (every key, including ones with no `es` text yet), shown with the bundled value for the chosen language beside any override; search by key or text; set or clear an override. A page permission only — no `language_line` resource. Overrides apply to everyone in the academy, including the sign-in pages. | TH §2.10 RBAC pages ("quick translate"); P1 SYS-007 (`page_QuickTranslate`, `language::line`; TH answered 403, behaviour UNKNOWN); `[assumed]` all behaviour; review 9, 13, 14 |
| L-8 | **Data:** new tenant app `etqan.translations` (TENANT_APPS, api_router, import-linter contract and forbidden-list lines under the B9 markers): `TranslationOverride(language ar|en|es, key ≤ 200 matching ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$ (area.dotted.path, plural suffixes allowed), value ≤ 500, updated_by FK SET_NULL, updated_at)`, unique `(language, key)`, at most 2000 rows per academy `[assumed]`. Keys are not checked for existence on the server (harmless: an unknown key is never used). | review 6, 7; `[assumed]` limits |
| L-9 | **Values are plain text.** The server refuses `<`, `>`, `$t(`, `{{-` and any `{{…}}` other than `{{ word }}`; the dashboard also checks the `{{word}}` set equals the default's before saving (the server doesn't know defaults). Overrides are only ever rendered as React text; a future `<Trans>` or HTML use of `t()` would need re-review. Plural keys are separate keys and follow each language's plural rules. | review 6, 7 |
| L-10 | **API:** `GET /api/v1/translations/` — anonymous, tenant-resolved, throttled like the public site endpoints, `Cache-Control: max-age=60`, no server-side cache — returns `{ "<lang>": { "<area.key>": "<value>" } }` (flat dotted keys) or `{}` while `quick_translate` is off. `PUT /api/v1/translations/<lang>/<key>/ {value}` and `DELETE …` (code `page.quick_translate`, switch `quick_translate`). `es` overrides are served whatever the `spanish` switch (they are simply unused while Spanish is off). | review 8 |
| L-11 | **Dashboard merge:** at start-up and after sign-in the overrides are fetched and merged per language: flat keys are unflattened into nested objects, then `i18n.addResourceBundle(lng, "common", nested, true, true)`; after an admin saves or clears an override the bundle is re-merged (a cleared key restores the bundled text by re-adding the bundled catalogue). A failed fetch is silent (bundled texts). | review 6, 15 |
| L-12 | Switch **`quick_translate`** (new, `platform`, off). Off: overrides kept, served nowhere (GET returns `{}`), the page and its routes 404. Both new switches go under `── phase B9 ──`; no existing `_later` line covers them. | B9-2; FT-4; review 9 |
| L-13 | The marketing site stays `ar`/`en` (B8's). | D11 |

## 3. Testing

- Backend: `es` accepted where L-3 lists, refused while `spanish` is off; `effective_language`;
  identity emails in Spanish, missing `es` template → English; notifications for an `es` reader use
  the academy default (unchanged test); overrides CRUD (page code, switch, key/value validation incl.
  `$t(` / `{{-` / `<`, uniqueness, 2000-row cap), anonymous GET shape, `{}` while off, throttling and
  `Cache-Control`; route-table and registry tests; markers.
- Dashboard: `es` subset / placeholder / non-empty tests over every `es` file; language menu with
  Spanish on (three choices, LTR) and toggle with it off; clamping a stored `es` to `en` when off;
  overrides merged at start-up, after save and after clear (nested keys); the quick-translate page
  (search, placeholder check, reset).
- e2e `dashboard/e2e/b9-languages.spec.ts` (turns `spanish` and `quick_translate` on with
  `manage("set_features", …)`): a user switches to Spanish and sees Spanish navigation; an admin
  overrides a navigation label and another user sees it after reload; the admin clears it.

## 4. Non-goals

Spanish for the marketing site; an academy default language `es`; translating other apps' emails;
right-to-left beyond Arabic; overriding email or backend texts; bulk import/export of overrides; a
translation workflow (reviews, history); Spanish values for bilingual data fields.
