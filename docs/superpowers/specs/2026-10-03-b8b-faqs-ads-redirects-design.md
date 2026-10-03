# B8b — FAQs, advertisements, URL redirects — Design

**Date:** 2026-10-03
**Status:** Approved by the phase orchestrator after an independent spec review (orchestration PO-3);
review findings 1–17 resolved in this version.
**Phase / slice:** B8 marketing extras, slice B8b (phase spec `2026-10-03-marketing-extras-design.md`).
**Requires:** B8a (merged): `SiteSettings`, `effective_status()` / `is_closed()`, the closed-site middleware.

**Evidence:** P1 audit §4.12 rows CNT-004 (FAQs), CNT-007 (advertisements), CNT-008 (redirects), §5.2 (the
Supervisor role holds the 12 `advertisement` verbs), §7.2 (Faq, Advertisement, Redirect entities), §8.5
(FAQ active ↔ inactive), §16.3 (flag "نظام اعاده توجيه الروابط" → redirects, INFERRED in the audit), §18.1 (advertisements and
redirects reached from Site settings), §19 (redirect fields UNKNOWN); TH audit §2.9 (CNT-004 tabs and filter),
§5.10 (gap rows). TutorHamster's public site is disabled on the demo, so every visitor-facing behaviour
here is `[assumed]` (orchestration PO-2).

## 1. Goal

The academy admin can publish bilingual FAQs on a public FAQ page, run time-limited promotional
advertisements on the home page, and keep old links working with URL redirects — each a feature Etqan
switches on per academy.

## 2. Decisions

| # | Question | Answer | Source |
|---|---|---|---|
| B-1 | FAQ fields | `question_ar/en` (plain text ≤ 300), `answer_ar/en` (rich text, Plan 2 allow-list, ≤ 10 000 characters after sanitising), `is_active` (default true), `order` (`PositiveIntegerField`, 0 allowed, default 0). Both languages required (TH requires question(ar), answer(ar) and Answer(en); M-4 makes Question(en) required too). At most 100 FAQs per academy (bounds the payload). Lengths and the cap [assumed]. | P1 §4.12 CNT-004; phase M-4, M-6 |
| B-2 | FAQ list in the dashboard | Ordered by `order`, then id; filter "active only" (all / active). Order is edited as a number in the form; no drag-and-drop. | P1 §4.12 ("Filter: active only", "sort order") |
| B-3 | Where do FAQs appear publicly? | A page `/<lang>/faq` listing active FAQs in order, each as a native `<details>`/`<summary>` (accessible, no JS), with `FAQPage` JSON-LD: `Layout` gains an optional `jsonLd` prop rendered as a second `<script type="application/ld+json">` with the same `<` → `\u003c` escaping as the existing block; answers go into it as plain text (tags stripped). A "FAQ" link joins the header menu when at least one active FAQ exists. Sitemap lists `/ar/faq` and `/en/faq` then. With the feature off or no active FAQ, `/<lang>/faq` is the academy's 404. | [assumed] |
| B-4 | Advertisement fields | `banner` (image, PNG/JPEG/WebP ≤ 2 MB, re-encoded by `etqan.site.images` like the hero image; required on create, optional on PATCH, no clear; deleting an ad or replacing its banner deletes the old file), `kind` (`general` · `discount`, TH "عام / خصم"), `title_ar/en` (≤ 120, required), `body_ar/en` (plain text ≤ 500, required), `expires_on` (date, required). At most 20 unexpired ads at once (a 21st is refused). Limits [assumed]. | P1 §4.12 CNT-007; M-4 |
| B-5 | When is an advertisement active? | While `expires_on` ≥ today (inclusive) in the academy's timezone — `etqan.academy.services.get_settings().timezone`, the setting admins edit and billing/payroll read (pattern of `billing/clock.py`: a patchable `now()`; an unknown zone falls back to UTC). No separate on/off switch (TH shows none); deleting or back-dating ends it. The admin list returns a server-computed `is_active`. | P1 §7.2 ("active until expiry"); inclusive day and timezone [assumed] |
| B-6 | Where do advertisements appear? | A "Offers" strip on the home page, above testimonials: each active ad as a card with banner, title, body; `discount` cards carry a "Discount" / "خصم" badge in the primary colour pair (`primary_color` / `primary_text`, already contrast-checked). Newest first. No click-through link (TH shows none). | [assumed] |
| B-7 | Discount ads and B3's discount codes | Not linked: `kind` is a label and a style only (phase spec §3.1). | phase spec §3.1 |
| B-8 | Redirect fields | TH's are unobserved. `from_path` (≤ 200, unique after canonicalising, B-8a), `to` (≤ 500, B-8b), `permanent` (bool, default **false** → 302; true → 301), `is_active` (default true). | P1 §19 (fields UNKNOWN); [assumed] |
| B-8a | Canonical `from_path` | The backend stores one canonical form, the way a browser sends it: non-ASCII characters percent-encoded as UTF-8 with uppercase hex (an Arabic old URL typed by the admin matches), existing `%xx` escapes uppercased, then: must start with `/`; only RFC 3986 path characters; no query or fragment; no `//`, no backslash, no `.`/`..` segments; no `%2F`, `%5C` or `%00`; one trailing slash removed. | review #2; [assumed] |
| B-8b | Safe `to` | ASCII only (non-ASCII percent-encoded on save), no whitespace or control characters, no backslash. Either a **site path** matching `^/(?![/\\])` (so `//evil.com` and `/\\evil.com` are refused), optionally with `?query` and `#fragment`; or an **absolute** `http(s)://` URL passing Django's `URLValidator(schemes=["http","https"])`. An absolute URL on one of the academy's own domains (`connection.tenant.domains`) is refused with "Use a path for this site." Redirecting to any external http(s) URL is allowed by design (old links moving to a new domain): the only open-redirect surface is admin-authored, like the rest of the site's content. | review #3; [assumed] |
| B-9 | Which paths may not be redirected? | Matched by whole segment on the canonical path (`/app` and `/app/...` refused, `/apple` allowed): `/`, `/ar`, `/en` (the home pages), `/app`, `/api`, `/accounts`, `/health`, `/media`, `/internal`, `/_astro`, `/closed-site`, `/robots.txt`, `/sitemap.xml`, `/favicon.ico`. Rejected with a field error. | CLAUDE.md routing table; B8a A-20; review #8 |
| B-10 | Loops and chains | Compare on the **path part** of a site-path `to`, canonicalised like `from_path` (query, fragment and trailing slash dropped). That path may not equal `from_path`, may not be the `from_path` of another active redirect, and `from_path` may not be the target path of another active redirect (no chains, so no loops; same-host absolute URLs are already refused, B-8b). Checked on every create and update, including switching `is_active` on and editing an inactive row. | [assumed]; review #4 |
| B-11 | Matching | Astro takes `new URL(request.url).pathname` (already percent-encoded with uppercase hex), removes one trailing slash (not from `/`), does **not** decode, and compares exactly (case-sensitive) with `from`. The request's query string is not carried over; `to`'s own query/fragment are kept. | [assumed]; review #2 |
| B-12 | How does the public site apply redirects? | The site payload carries `redirects: [{from, to, permanent}]` (active only). The Astro middleware, after resolving the site and **after** the closed-site check (a closed site shows its closed page on every path), looks the path up and answers 301/302 with `Location: <to>` before rendering, `Cache-Control: max-age=3600` on a 301 (so a deleted or fixed permanent redirect stops sticking in browsers within the hour) and `no-store` on a 302. Redirects take precedence over real pages, and a redirected path is left out of the sitemap. At most 500 redirects per academy (backend validation) to bound the payload. The dashboard says that a permanent redirect is cached by browsers for an hour. | B8a A-20; [assumed]; review #5, #9 |
| B-13 | Feature switches | `faqs` (new: "FAQs" / "الأسئلة الشائعة") and `advertisements` (new: "Advertisements" / "الإعلانات الترويجية" — "promotional" added so it is not confused with B8a's `site_tracking` "التحليلات والإعلانات") under `── phase B8 ──`, and the existing `url_redirects` line flipped in place to built, all `default=False`. Group: `content` for the two new ones; `url_redirects` keeps `platform`. Off → admin routes 404 (after the permission check), the payload carries `[]`, the public FAQ page 404s, no strip, no redirect. | phase M-5, M-10; PO-5 |
| B-14 | Permissions | Three new access resources under `── phase B8 ──`: `faq` ("FAQs" / "الأسئلة الشائعة"), `advertisement` ("Advertisements" / "الإعلانات الترويجية"), `redirect` ("URL redirects" / "تحويل الروابط"), each with verbs in use `view_any, view, create, update, delete`. TH's Supervisor role holds `advertisement` — staff roles here get it by grant like any code. | P1 §5.2; spec 2026-09-28 |
| B-15 | Closed sites | While closed (B8a), the payload's `faqs`, `advertisements` and `redirects` are `[]`; Astro shows the closed page before any redirect lookup. | phase M-9 |
| B-16 | Dashboard placement | Three new tabs in the Website area — FAQs, Advertisements, Redirects — each shown when its feature is on and the user holds its `view_any` code; the routes declare `staticData: { permission, feature }` so a direct link shows "not enabled"; `website.index.tsx` (first visible tab) filters on features too. The Website nav item may show for someone holding only a B8b code while that feature is off; it then lands on the not-enabled page — accepted. Lists with add/edit dialogs and delete-with-confirm, matching the Testimonials manager; no pagination (caps bound the lists). | spec 2026-09-23 §4.3; P1 §18.1; review #10 |
| B-17 | Article/video-style view counts, AI | Not in B8b (none on these entities). | P1 §4.12 |

## 3. Data (`etqan.site`, tenant schema; one additive migration)

| Model | Fields | Ordering / constraints |
|---|---|---|
| `Faq` | `question_ar`, `question_en` (char 300), `answer_ar`, `answer_en` (text, sanitised, ≤ 10 000), `is_active` (bool, true), `order` (`PositiveIntegerField`, 0), `updated_at` | `order, id` |
| `Advertisement` | `kind` (`general`·`discount`), `title_ar`, `title_en` (char 120), `body_ar`, `body_en` (text ≤ 500), `banner` (image, `uploads.ad_path` → `tenants/<schema>/site/ads/<uuid>.<ext>`), `expires_on` (date), `created_at` | `-created_at, -id` |
| `Redirect` | `from_path` (char 200, unique), `to` (char 500), `permanent` (bool, false), `is_active` (bool, true), `created_at` | `from_path` |

Services (`etqan.site.services`): `active_faqs()`, `active_ads(today)`, `active_redirects()`; `academy_today()`
(today in `academy.services.get_settings().timezone`, B-5); `canonical_path(raw) -> str` (B-8a, raising a
field error on anything refused); `seed_faqs(...)`, `seed_ad(...)`, `seed_redirect(...)` for `etqan/tenants/seeds/b8.py`.

## 4. Behaviour

### 4.1 Public API (`GET /api/v1/site/`, additive keys)

```jsonc
"faqs": [{"question": {"ar": "…", "en": "…"}, "answer_html": {"ar": "…", "en": "…"}}],
"advertisements": [{"kind": "discount", "title": {…}, "body": {…}, "banner_url": "…", "expires_on": "2026-11-01"}],
"redirects": [{"from": "/old-page", "to": "/en/faq", "permanent": true}]
```

Each is `[]` while its feature is off or the site is closed.

### 4.2 Admin API

| Route | Codes | Feature |
|---|---|---|
| CRUD `/api/v1/site/admin/faqs/` (`?active=1` filter) | `faq.view_any / view / create / update / delete` | `faqs` |
| CRUD `/api/v1/site/admin/advertisements/` (multipart for `banner`) | `advertisement.*` | `advertisements` |
| CRUD `/api/v1/site/admin/redirects/` | `redirect.*` | `url_redirects` |

`[HasCode, FeatureOn]`; viewsets with `viewset_codes(...)`. Route-table rows appended to `ROUTES`, `FEATURES`
and `FEATURE_WORDS` (`/site/admin/faqs/` → `faqs`, `/site/admin/advertisements/` → `advertisements`,
`/site/admin/redirects/` → `url_redirects`). Validation per B-1, B-4, B-8–B-10 and the 500 cap (B-12).

### 4.3 Marketing site

- `SitePayload` gains the three keys; `resolveSite` defaults each to `[]` when missing (deploy skew, as B8a).
- `src/pages/[lang]/faq.astro`: B-3. Header menu link "FAQ" / "الأسئلة الشائعة" when `faqs.length > 0`.
- Home page: `Offers` component (B-6) when `advertisements.length > 0`, above testimonials.
- Middleware: after the closed-site branch, `findRedirect(site.redirects, path)` → `Response(null, {status: 301|302, headers: {Location, Cache-Control}})`.
  `to` is re-validated with B-8b's rules (ASCII, no whitespace/control/backslash, `^/(?![/\\])` or `^https?://`); an
  unsafe value is ignored, never thrown on.
- Sitemap adds `/faq` per language when FAQs exist, and drops any URL whose path is a redirect's `from`.

### 4.4 Dashboard

Website tabs FAQs (`/website/faqs`, `faq.view_any`, feature `faqs`), Advertisements (`/website/ads`,
`advertisement.view_any`, `advertisements`), Redirects (`/website/redirects`, `redirect.view_any`,
`url_redirects`). `WEBSITE_TABS` entries gain an optional `feature`; the tab list filters on `hasFeature` too.
`FeatureCode` gains `faqs`, `advertisements`, `url_redirects`. FAQ answers use the existing `RichTextEditor`;
bilingual fields side by side (`BilingualField`). Strings in `locales/{en,ar}/website.json`.

### 4.5 Seeds

`seed_b8` (demo), through the new `etqan.site.services` seed helpers: three FAQs, one discount advertisement
expiring 30 days after the seed date (re-seeding moves the date forward), one redirect `/old-faq` → `/en/faq`.
Idempotent (keyed by `question_en`, `title_en`, `from_path`). The demo ad's banner is a small generated PNG
(Pillow), created only when the ad has none (no orphaned files on re-seed).

## 5. Testing

- **Backend:** model validation (required pairs, lengths, `kind`, reserved and malformed `from_path`, `to`
  formats, self/chain loops, trailing-slash normalisation, uniqueness after normalisation, 500 cap); FAQ answers
  sanitised; ad active/expired around midnight in a non-UTC academy timezone (patching the clock); canonical
  paths (Arabic, encoded, `%2f`, `..`, `//`, backslash), `to` safety (`//evil.com`, `/\\evil.com`, CR/LF,
  same-host absolute URL), loops via trailing slash and via activating an inactive row, the 100/20/500 caps; payload keys per feature on/off
  and closed site; admin CRUD + `?active=1`; 403 for staff without codes, 404 after the check with the feature
  off (route table); tenant isolation; seed idempotent.
- **Marketing:** FAQ page both languages (`<details>`, JSON-LD, 404 when empty), menu link only with FAQs,
  Offers strip and discount badge, middleware 301/302 with and without trailing slash, no redirect on closed
  sites, unsafe `to` ignored, encoded Arabic path matched, 301/302 cache headers, FAQ JSON-LD escaping (a
  question containing `</script>`), missing keys default to `[]`, sitemap entry and redirected paths left out.
- **Dashboard:** each manager list/add/edit/delete, validation messages, tabs hidden per feature and code.
- **e2e** `dashboard/e2e/b8-faqs-ads-redirects.spec.ts` (demo, serial): the admin adds a uniquely named FAQ,
  an advertisement expiring at least 2 days ahead, and a redirect from a unique path (`/b8b-<random>`, 302);
  the public `/en/faq` shows the FAQ, the home page shows the ad, and the redirect answers 302 with its
  `Location` (`maxRedirects: 0`; polls ≤ 90 s for the payload cache); the test deletes all three at the end,
  also on failure (a deleted redirect lingers ≤ 60 s in the cache — harmless, the path is unique).

## 6. Non-goals

Drag-and-drop ordering; ad click-through links, scheduling a start date, or placement choices; redirect
patterns/wildcards, query-string matching, hit counters; linking discount ads to B3 codes; FAQ categories.
