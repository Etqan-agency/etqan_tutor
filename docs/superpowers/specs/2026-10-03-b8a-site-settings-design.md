# B8a — Site settings depth — Design

**Date:** 2026-10-03
**Status:** Approved by the phase orchestrator after an independent spec review (orchestration PO-3);
review findings 1–17 resolved in this version.
**Phase / slice:** B8 marketing extras, slice B8a (phase spec `2026-10-03-marketing-extras-design.md`).
**Requires:** no other phase's slice.

**Evidence:** TH audit §1.3 #14 (CNT-010 site status values), §2.9 (CNT-009 tabs Basic / Content / Social /
SEO), §5.10 (gap rows); P1 audit §4.12 CNT-009, §14 ("Public site disabled → `/system-only-error`,
'Restricted Area'"), §16.2 ("surfaces on the public site (SitePage/site settings must be live)"), §20.6
(public site unobserved, so visitor-facing behaviour is `[assumed]`, orchestration PO-2).

## 1. Goal

The academy's admin can take the public site down for maintenance, mark it beta, or close it to the
public ("system only") while the dashboard keeps working; can connect the public site to Google
Analytics, Meta Pixel, AdSense and Search Console; and can fill the rest of TutorHamster's site-settings
form: three more social networks, a footer text and SEO keywords.

## 2. Decisions

| # | Question | Answer | Source |
|---|---|---|---|
| A-1 | Which status values? | `live` · `maintenance` · `beta` · `system_only`, default `live`. | TH audit §1.3 #14, §2.9 |
| A-2 | What does `system_only` do to visitors? | Every public path shows a branded "Restricted area" page with a "Sign in" link to `/app/`; HTTP 403, `noindex`; `robots.txt` disallows everything; `sitemap.xml` answers 404. Dashboard, API and `/accounts/` untouched. | P1 audit §14 (TH redirects to `/system-only-error`, "Restricted Area"); page instead of redirect [assumed] |
| A-3 | What does `maintenance` do? | Every public path shows a branded "Under maintenance" page; HTTP 503, `Retry-After: 3600`, `noindex`; `robots.txt` unchanged; `sitemap.xml` 503. Dashboard unaffected. | [assumed] — 503 matches Plan 2's suspended-site rule (spec 2026-09-23 §2.3) |
| A-4 | What does `beta` do? | The normal site plus a slim banner on every content page: "Beta — this site is still being tested" (ar/en). Indexed as normal. | [assumed] |
| A-5 | While `maintenance` or `system_only` ("closed"), what does the public API expose? | `GET /api/v1/site/` answers 200 with `academy`, `branding` and `settings` (the closed pages show the academy's name and logo), but `landing` text fields (`hero_title`, `hero_subtitle`, `cta_label`, `about_html`) are empty pairs, `hero_image_url` is `""`, every `sections` flag is `false`, and `testimonials` and `pages` are `[]`; `GET /api/v1/site/pages/<slug>/` 404s; `POST /api/v1/site/inquiries/` answers 403 `{"code": "site.closed"}`. Every later B8 public endpoint follows the same rule (phase spec M-9). | P1 audit §16.2; [assumed] |
| A-6 | Is the status a feature switch? | Yes: new feature `site_status`, group `content`, off by default. Off → the effective status is `live` whatever is stored, the admin status route 404s, the dashboard hides the control. The stored value survives switching off (FT-4). | PO-5; spec 2026-09-30 FT-4 |
| A-7 | TH's "custom Header code" and "custom ads code": raw HTML? | **No — provider IDs rendered from fixed templates.** The public site shares its origin with `/app/` and `/api/`, and the CSRF cookie is script-readable (`CSRF_COOKIE_HTTPONLY = False`), so any pasted script — or a compromised third-party snippet — could act as every signed-in user who opens the public site, including admins using "Preview site". The common uses of those two boxes are covered by four validated IDs (A-8). Anything else stays out until a sandboxed design exists. | TH audit §2.9; security [assumed] |
| A-8 | Which IDs? | `ga4_id` (`^G-[A-Z0-9]{4,12}$`, loads gtag.js), `meta_pixel_id` (`^[0-9]{6,20}$`, loads the Meta Pixel base code), `adsense_client` (`^ca-pub-[0-9]{10,20}$`, loads the AdSense script), `google_site_verification` (`^[A-Za-z0-9_-]{10,100}$`, a `<meta>` tag). All optional. Google Tag Manager is excluded: a container runs arbitrary code. | [assumed] |
| A-9 | Is it a feature switch, who edits it? | New feature `site_tracking` ("Analytics and ads" / "التحليلات والإعلانات"), group `content`, off by default. Edited with `site.view` / `site.update`, like the rest of the site (validated IDs carry no script of the academy's own). Off → route 404s, payload carries empty strings, nothing rendered. | PO-5; spec 2026-09-28 |
| A-10 | Where are the snippets rendered? | In `Layout` only (home, site pages, the academy's 404): verification meta and the three loader scripts in `<head>`. Never on closed pages, status pages, the dashboard or the bare platform domain. | [assumed] |
| A-11 | TH's "site schema" field? | Not built: Plan 2 already emits JSON-LD. | TH audit §5.10 ("Site schema / SEO — BUILT") |
| A-12 | Which social networks? | TH lists 14. Etqan has Facebook, Instagram, YouTube, X, TikTok, Telegram, WhatsApp, phone and one contact e-mail. Add **LinkedIn, Snapchat, SoundCloud** (URLs). The three e-mail variants (Gmail / public-service / info) stay one contact e-mail. | TH audit §2.9 Social; e-mail consolidation [assumed] |
| A-13 | Per-network enable toggle? | No: an empty URL is the off state (same effect, one field). | [assumed] |
| A-14 | Footer text and keywords | `footer_text_ar/en` (plain text, ≤ 300) shown in the footer above "Powered by"; `keywords_ar/en` (plain text, ≤ 255, comma-separated) emitted as `<meta name="keywords">` in that language. Both optional. | TH audit §2.9 Content (footer blurb), SEO (keywords) |
| A-15 | Are footer text, keywords and the new socials feature-gated? | No. They are optional fields on a built screen, empty by default, so no academy sees any change until it fills them (phase spec M-10). | phase spec M-10; PO-5 |
| A-16 | Packages-page blurb and intro video | Not in B8a: the blurb waits for a rendered packages section (phase spec §3.1); the intro video is B8d. | phase spec §3 |
| A-17 | Where are the new settings stored? | A new singleton `SiteSettings` in `etqan.site` (status, tracking IDs, footer text, keywords). The three socials go on `Branding` beside the existing six, so `branding/` gains three keys in `social` and nothing else. | spec 2026-09-23 §3.1; M-1 |
| A-18 | No `SiteSettings` row yet? | `SiteSettings.current()` creates it on first use (`get_or_create`), so every caller — including the page and inquiry views, which never call `ensure_site_defaults` — sees a row; a new row is `live` with every other field empty. `ensure_site_defaults` also creates it. | review #9 |
| A-19 | How fast do changes reach the site? | Within the marketing site's 60 s payload cache; the dashboard says so next to the status control. | spec 2026-09-23 §2.3 |
| A-20 | How does Astro answer every path with 503/403? | `middleware.ts`: when the site resolves `ok` and its status is closed, and the path is neither `/robots.txt` nor `/sitemap.xml`, it returns `context.rewrite("/closed-site")` instead of `next()`. `src/pages/closed-site.astro` renders `ClosedPage` with the right status when the site is closed and the academy's 404 otherwise (so the route reveals nothing on an open site). The middleware then sets `X-Robots-Tag: noindex` and, for maintenance, `Retry-After: 3600`. `robots.txt.ts` and `sitemap.xml.ts` branch on the status themselves. | review #3; Astro 6 `context.rewrite` |

## 3. Data (`etqan.site`, tenant schema)

### 3.1 `SiteSettings` (singleton, `SiteSettings.current()`)

| Field | Type |
|---|---|
| `status` | choice `live · maintenance · beta · system_only`, default `live` |
| `ga4_id`, `meta_pixel_id`, `adsense_client`, `google_site_verification` | char (16 / 20 / 28 / 100), blank, regex-validated (A-8) |
| `footer_text_ar`, `footer_text_en` | char ≤ 300, blank |
| `keywords_ar`, `keywords_en` | char ≤ 255, blank |
| `updated_at` | auto |

### 3.2 `Branding` additions

`linkedin`, `snapchat`, `soundcloud`: `URLField`, blank. Additive migration; no data rewritten.

## 4. Behaviour

### 4.1 Services (`etqan.site.services`)

- `effective_status() -> str` — `SiteSettings.current().status` when `features.enabled("site_status")`,
  else `live`.
- `is_closed(status: str) -> bool` — `maintenance` or `system_only`. Later slices call
  `is_closed(effective_status())` for their own public endpoints.

### 4.2 Public API

`GET /api/v1/site/` gains a key (all other keys keep their shape):

```jsonc
"settings": {
  "status": "live",                       // effective (A-6)
  "footer_text": {"ar": "…", "en": "…"},
  "keywords": {"ar": "…", "en": "…"},
  "tracking": {                           // all "" unless site_tracking is on (A-9)
    "ga4_id": "", "meta_pixel_id": "", "adsense_client": "", "google_site_verification": ""
  }
}
```

`branding.social` gains `linkedin`, `snapchat`, `soundcloud` (also in `GET /api/v1/site/branding/`).
While closed, per A-5.

### 4.3 Admin API (dashboard Website area)

Three routes on the one `SiteSettings` row, each with its own serializer exposing only its own fields;
any other field in a PATCH body is ignored.

| Route | Permission | Feature | Fields |
|---|---|---|---|
| `GET/PATCH /api/v1/site/admin/settings/` | `site.view` / `site.update` | — | `footer_text_ar/en`, `keywords_ar/en` |
| `GET/PATCH /api/v1/site/admin/status/` | `site.view` / `site.update` | `site_status` | `status` |
| `GET/PATCH /api/v1/site/admin/tracking/` | `site.view` / `site.update` | `site_tracking` | the four IDs |
| `GET/PATCH /api/v1/site/admin/branding/` | unchanged | — | + `linkedin`, `snapchat`, `soundcloud` |

Off features answer 404 after the permission check (`[HasCode, FeatureOn]`, Plan 13 §5.2).

**Route table** (`etqan/access/tests/test_routes.py`, a shared file without phase markers — new lines
are appended to each table and conflicts resolved at rebase, orchestration §6.2.3): the three routes
join `ROUTES` with their codes; `status/` and `tracking/` join `FEATURES` with `site_status` /
`site_tracking`.

### 4.4 Management command

`set_site_status <live|maintenance|beta|system_only>` in `etqan/site/management/commands/`, run per
academy with django-tenants' `tenant_command set_site_status <status> --schema=<schema>`. Etqan staff
can use it to close a site from the shell; the e2e uses it (§5). It writes the stored status only (the
feature switch is separate, `set_features`).

### 4.5 Marketing site (Astro)

- `SitePayload` gains `settings` and the three socials.
- **Closed** (A-20): `ClosedPage` (branded: logo, name, Arabic and English text, `noindex`):
  - `maintenance` → "Under maintenance", 503, `Retry-After: 3600`; `sitemap.xml` 503.
  - `system_only` → "Restricted area" with a "Sign in" link to `/app/`, 403; `robots.txt` =
    `User-agent: *` / `Disallow: /`; `sitemap.xml` 404.
- `beta` → `Layout` shows the banner (`role="status"`) above the header.
- **Tracking** (A-10): `Layout` renders, only for non-empty IDs, the verification `<meta>` and the gtag.js,
  Meta Pixel and AdSense loaders from fixed templates; the ID is the only interpolated value, re-checked
  against A-8's pattern in Astro before use (defence in depth, as `Layout` already does for colours).
- **Footer** shows `footer_text` in the page language (escaped text); the new socials join the links.
- **Keywords:** `<meta name="keywords">` in the page language when non-empty.

### 4.6 Dashboard (`/app/website`)

- `WEBSITE_TABS` (in `features/shell/nav.ts`; the Website area is B8's) gains **Settings**
  (`/website/settings`, `site.view`) with up to three cards:
  1. **Footer and SEO** — footer text and keywords, Arabic and English side by side (`BilingualField`).
  2. **Site status** — while `hasFeature("site_status")`: four radio options with one line of explanation
     each, and "Changes reach the public site within a minute."
  3. **Analytics and ads** — while `hasFeature("site_tracking")`: the four ID inputs with their formats as
     hints.
  Read-only without `site.update`.
- **Branding** form gains LinkedIn, Snapchat, SoundCloud.
- `FeatureCode` (`features/identity/schemas.ts`, a shared union without markers) gains `site_status` and
  `site_tracking`; conflicts resolve at rebase.
- Strings in `locales/{en,ar}/website.json` (B8's existing area).

### 4.7 Registry, seeds

- `features.py` under `── phase B8 ──`: `site_status` ("Site status modes" / "أوضاع حالة الموقع") and
  `site_tracking` ("Analytics and ads" / "التحليلات والإعلانات"), both `_built(..., default=False)`,
  group `content`. `demo` gets them on through the existing `features.BUILT` seed.
- `seed_dev`: under `── phase B8 ──`, a step from `etqan/tenants/seeds/b8.py` that gives `demo` a footer
  text and keywords (idempotent).

## 5. Testing

- **Backend:** `SiteSettings.current()` creates a `live` row; payload carries `settings` and the new
  socials; effective status `live` with `site_status` off; closed statuses blank `landing`, empty
  testimonials/pages, 404 the page endpoint, 403 inquiries (also with no prior `SiteSettings` row);
  tracking empty in the payload with `site_tracking` off; ID validation (each pattern, accept and reject);
  length limits; **mass assignment** — PATCH `settings/` with `status` and tracking IDs, and `status/` with
  footer text, changes nothing outside each route's fields; `set_site_status` writes the status and rejects
  an unknown value; tenant isolation (closing `demo` never affects `other`); route-table entries and
  feature column.
- **Marketing:** render/middleware tests for each closed status on `/`, `/en/`, `/ar/p/<slug>` and an
  unmatched path `/en/a/b` (status code, `noindex`, `Retry-After`, sign-in link), `/closed-site` on an open
  site is the 404 page, robots/sitemap variants; beta banner; tracking snippets only for valid non-empty IDs
  and never on `ClosedPage`; footer text and keywords per language; new socials.
- **Dashboard:** Settings tab cards per feature and permission; forms submit both languages; ID format
  errors shown; branding form's new socials.
- **e2e** `dashboard/e2e/b8-site-settings.spec.ts`, `test.describe.configure({ mode: "serial" })`:
  1. *Settings (demo, UI):* the admin fills footer text, a GA4 ID and status `beta` in Website → Settings;
     the public home page shows the footer text, the gtag loader and the beta banner (assertions poll
     ≤ 90 s for the 60 s cache). `afterAll` resets demo through the UI-independent path
     (`tenant_command set_site_status live --schema=academy_demo`, and the footer/ID cleared through the
     admin API) so other suites see an unchanged demo.
  2. *Closed site (dedicated academy):* `beforeAll` runs `create_academy --subdomain b8site` (an
     "already exists" error is ignored, so reruns work), `set_features b8site --on site_status`, and
     `set_site_status maintenance` **before** any visit, so the first request sees it uncached → 503
     maintenance page; `/app/` on that host still answers; then `system_only` → poll for 403 "Restricted
     area" with a sign-in link. A dedicated academy keeps the parallel `academy-sites` suite's `demo` and
     `other` open.

## 6. Non-goals

Raw HTML/JS injection and Google Tag Manager (A-7, A-8); TutorHamster's "site schema" field (A-11);
per-network toggles (A-13); extra contact e-mails (A-12); packages blurb and intro video (A-16); scheduling
a status change.
