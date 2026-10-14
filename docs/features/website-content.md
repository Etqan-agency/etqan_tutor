# Website content: FAQs, advertisements, redirects, articles, videos

These are the optional content types an academy can publish on its public website, beyond the home
page and pages covered in [website.md](website.md). Each one is a feature Etqan switches on per
academy, and each is off by default. Academy admins, and staff with the matching codes, manage them
in the dashboard's Website area. Public visitors see them on the Astro site. A closed site
(`maintenance` / `system_only`) shows none of them.

## Concepts

All models are in `etqan.site.models`, in the **academy** schema.

| Model | Feature | Purpose |
|---|---|---|
| `Faq` | `faqs` | Bilingual question, rich-text answer (sanitised, at most 10,000 characters), `is_active`, `order`. At most 100 per academy |
| `Advertisement` | `advertisements` | `kind` (`general` / `discount`), title and body `_ar` / `_en`, `banner` image (required), `expires_on` (last day, inclusive). At most 20 can run at once |
| `Redirect` | `url_redirects` | `from_path` (unique, canonical), `to` (a site path or an http(s) URL), `permanent` (301 or 302), `is_active`. At most 500 |
| `ArticleCategory` | `articles` | Name and description `_ar` / `_en`, unique `slug`, `icon`, `order`. At most 100. A category that still holds articles cannot be deleted (409) |
| `Article` | `articles` | `category` (PROTECT), unique `slug`, title, summary and body `_ar` / `_en` (body sanitised, at most 50,000 characters), `cover`, `publish_on` (date), `is_published`, SEO title (≤60), SEO description (≤160), keywords, `views`, `reactions` |
| `Video` | `video_library` | Title and description `_ar` / `_en`, `source` `upload` (MP4 `file`, at most 20 MB) or `youtube` (11-char `external_id`), `cover`, unique `slug`, SEO fields, `is_published`, `order`, `views`, `reactions`. At most 200. A DB check constraint ties the media field to `source` |

The slug `sitemap` is reserved for articles and videos, because `.../sitemap/` is routed before
`<slug>`.

## How it works

### FAQs

- Active FAQs (`services.active_faqs`) go into the site payload in `order` and are rendered on
  `/[lang]/faq`.
- The page builder's `faqs` block can embed them (see website.md).

### Advertisements

- An ad is active while `expires_on >= academy_today()`. `academy_today()` is the date in
  `AcademySettings.timezone`.
- Active ads (`services.active_ads`) appear in the site payload, newest first, as home-page offer
  cards (`marketing/src/components/Offers.astro`).
- The banner is required on create. An update without a new file keeps the banner. A replaced or
  deleted banner's file is removed from storage.

### URL redirects

1. On save, `from_path` is canonicalised (`site/redirects.py:canonical_path`): percent-encoded with
   uppercase escapes, one trailing slash dropped.
   - Paths whose first segment is reserved are refused: `app`, `api`, `accounts`, `health`, `media`,
     `internal`, `_astro`, `closed-site`, `robots.txt`, `sitemap.xml`, `favicon.ico`.
   - The exact paths `/`, `/ar` and `/en` are also refused.
2. `to` is cleaned by `clean_target`. A URL on one of the academy's own hosts must be written as a
   path instead.
3. `services.check_redirect_chain` refuses a self-loop, a target that is itself redirected, and a
   path that another redirect points to.
4. The site payload carries the active redirects. `marketing/src/middleware.ts:findRedirect`
   matches the exact request path (escapes uppercased, trailing slash ignored). It answers 301
   (cached 1 h) or 302 (`no-store`) before rendering. Redirected paths are left out of
   `sitemap.xml`.

### Articles

1. Status is derived on the academy's calendar (`services.article_status`):
   - `draft`: `is_published` is false.
   - `scheduled`: published, but `publish_on` is in the future.
   - `published`: published and `publish_on <= today`.
2. The public list is `public_articles(today)`. `public_categories` returns only categories that
   hold a public article.
3. The public endpoints exist only while `articles` is on and the site is open (`_articles_open`).
   Otherwise they return 404.
4. The list is paginated with `PublicPagination` (12 per page, `?category=<slug>`).
5. Beacons (`articles/<slug>/view/` and `react/`) accept JSON-only POSTs. The body is ignored.
   - A view counts once per IP per article every 30 minutes (`services.count_view`).
   - A reaction counts once per IP per day (`services.react`).
   - IPv6 addresses are grouped by /64. The counters use the cache, and a cache outage skips
     counting.
   - Admin saves write only the edited columns, so they never overwrite the counters.
6. Marketing pages:
   - `/[lang]/articles/`
   - `/[lang]/articles/c/[category]`
   - `/[lang]/articles/[slug]`, with JSON-LD and a "Helpful" button (`components/Helpful.astro`)
7. Articles feed `sitemap.xml` (at most 5,000).
8. The dashboard editor offers "Write with AI" drafts for article fields when `ai_assistant` is on
   (B10, `features/ai/AiDraftButton`).

### Video library

- The public list (`public_videos`) holds published videos, by `order` then newest.
- The public endpoints exist only while `video_library` is on and the site is open
  (`services.videos_open`).
- Pages: `/[lang]/videos/` and `/[lang]/videos/[slug]`. Players re-validate the source on output.
- View and react beacons work as for articles.
- The sitemap lists at most 200 videos.
- Videos are also used as the landing `intro_video`, in video testimonials (needs
  `testimonial_media`) and in page-builder `video` blocks. The admin can pick only published videos
  there. An unpublished or deleted video drops out of the public payload.
- YouTube input may be an id or a link. Only the id is stored (`site/youtube.py:parse_id`).

### Seeding

`site/services.py` has `seed_faqs`, `seed_ad`, `seed_redirect`, `seed_article_category`,
`seed_article`, `seed_video`, `seed_video_testimonial` and `seed_block_page`, for dev and e2e data
(`tenants/seeds/b8.py`). They go through the same validators as the admin API.

## API

Public endpoints are anonymous, read the academy from `Host`, and are cached for 60 s (beacons are
`no-store`).

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/site/articles/` | Public | Published articles, 12 per page, `?category=<slug>`, `?page=` |
| GET | `/api/v1/site/articles/<slug>/` | Public | One article |
| GET | `/api/v1/site/articles/sitemap/` | Public | Article slugs, `updated_at` and category slugs |
| POST | `/api/v1/site/articles/<slug>/view/` | Public, JSON only | Count a view (204) |
| POST | `/api/v1/site/articles/<slug>/react/` | Public, JSON only | Count a reaction: `{counted, reactions}` |
| GET | `/api/v1/site/article-categories/` | Public | Categories that hold public articles |
| GET | `/api/v1/site/videos/` | Public | Published videos, paginated |
| GET | `/api/v1/site/videos/<slug>/` | Public | One video |
| GET | `/api/v1/site/videos/sitemap/` | Public | Video slugs and `updated_at` |
| POST | `/api/v1/site/videos/<slug>/view/`, `.../react/` | Public, JSON only | Video beacons |
| GET, POST | `/api/v1/site/admin/faqs/` | `faq.view_any` / `faq.create`, feature `faqs` | List (`?active=1`) or create |
| GET, PUT, PATCH, DELETE | `/api/v1/site/admin/faqs/<id>/` | `faq.*` | One FAQ |
| GET, POST | `/api/v1/site/admin/advertisements/` | `advertisement.*`, feature `advertisements` | List or create (multipart). Each row has a computed `is_active` |
| GET, PUT, PATCH, DELETE | `/api/v1/site/admin/advertisements/<id>/` | `advertisement.*` | One ad |
| GET, POST | `/api/v1/site/admin/redirects/` | `redirect.*`, feature `url_redirects` | List or create |
| GET, PUT, PATCH, DELETE | `/api/v1/site/admin/redirects/<id>/` | `redirect.*` | One redirect |
| GET, POST | `/api/v1/site/admin/article-categories/` | `article_category.*` (the list also allows `article.view_any` / `article.create` / `article.update`), feature `articles` | Categories |
| GET, PUT, PATCH, DELETE | `/api/v1/site/admin/article-categories/<id>/` | `article_category.*` | One category (409 while it holds articles) |
| GET, POST | `/api/v1/site/admin/articles/` | `article.*`, feature `articles` | List (25 per page, `?status=draft\|scheduled\|published`, `?category=<id>`) or create (multipart) |
| GET, PUT, PATCH, DELETE | `/api/v1/site/admin/articles/<id>/` | `article.*` | One article |
| GET, POST | `/api/v1/site/admin/videos/` | `video.*`, feature `video_library` | List (unpaginated, `?status=draft\|published`) or create (multipart) |
| GET, PUT, PATCH, DELETE | `/api/v1/site/admin/videos/<id>/` | `video.*` | One video |

FAQs, ads, redirects and video lists are unpaginated. Deleting an ad, article or video also deletes
its files.

## Dashboard

These are tabs of `/app/website`, each shown only with its permission code and feature (`WEBSITE_TABS`
in `features/shell/nav.ts`, `staticData` on the route).

| Route | Component (`features/website/`) | Code / feature |
|---|---|---|
| `/app/website/faqs` | `FaqsManager.tsx` | `faq.view_any` / `faqs` |
| `/app/website/ads` | `AdsManager.tsx` | `advertisement.view_any` / `advertisements` |
| `/app/website/redirects` | `RedirectsManager.tsx` | `redirect.view_any` / `url_redirects` |
| `/app/website/articles` | `ArticlesManager.tsx`, `ArticleEditor.tsx` | `article.view_any` / `articles` |
| `/app/website/articles/categories` | `ArticleCategoriesManager.tsx` | `article_category.view_any` / `articles` |
| `/app/website/videos` | `VideosManager.tsx`, `VideoEditor.tsx` | `video.view_any` / `video_library` |

## Background jobs

None. Article scheduling has no job: status is computed from `publish_on` at read time.

## Configuration

- Features: `faqs`, `advertisements`, `articles` and `video_library` (group `content`), and
  `url_redirects` (group `platform`). `testimonial_media` and `page_builder` matter for
  embedding. All are off by default.
- Permission resources: `faq`, `advertisement`, `redirect`, `article`, `article_category`, `video`.
  Each has `view_any`, `view`, `create`, `update`, `delete`.
- Upload limit `platform/uploads.py:LIBRARY_MAX` (20 MB) for MP4. Images go through
  `site/images.py` (2 MB, PNG / JPEG / WebP).
- The beacon dedupe uses the Django cache (Redis).

## Code map

- `backend/etqan/site/models.py`: `Faq`, `Advertisement`, `Redirect`, `ArticleCategory`, `Article`,
  `Video`
- `backend/etqan/site/services.py`: `active_faqs`, `active_ads`, `active_redirects`,
  `check_redirect_chain`, `article_status`, `public_articles`, `public_categories`, `public_videos`,
  `videos_open`, `count_view`, `react`, `academy_today`, the seed helpers
- `backend/etqan/site/redirects.py`, `youtube.py`, `payloads.py`
- `backend/etqan/site/api/views.py` (public, beacons), `api/admin_views.py`,
  `api/admin_serializers.py`
- `dashboard/src/features/website/` (the managers and editors above, `api.ts`, `schemas.ts`,
  `queries.ts`)
- `marketing/src/lib/articles.ts`, `lib/videos.ts`, `lib/redirects.ts`, `lib/youtube.ts`,
  `src/pages/[lang]/faq.astro`, `src/pages/[lang]/articles/`, `src/pages/[lang]/videos/`,
  `src/pages/sitemap.xml.ts`, `src/components/` (`FaqList`, `Offers`, `ArticleCard`, `VideoCard`,
  `VideoPlayer`, `IntroVideo`, `Helpful`, `Pager`)

## Design history

- [Marketing extras (B8 phase)](../superpowers/specs/2026-10-03-marketing-extras-design.md): lifted
  the academy-sites non-goals for articles and the page builder, and split the work into B8a–B8e.
- [B8b FAQs, ads, redirects](../superpowers/specs/2026-10-03-b8b-faqs-ads-redirects-design.md).
  Implemented in [Plan 19](../superpowers/plans/2026-10-03-plan-19-faqs-ads-redirects.md).
- [B8c articles](../superpowers/specs/2026-10-03-b8c-articles-design.md): derived status, beacons,
  sitemap. Implemented in [Plan 24](../superpowers/plans/2026-10-03-plan-24-articles.md).
- [B8d media](../superpowers/specs/2026-10-04-b8d-media-design.md): the video library. It
  supersedes the phase spec's M-8: uploads are capped at 20 MB through Django, and larger videos are
  YouTube links. Implemented in [Plan 27](../superpowers/plans/2026-10-04-plan-27-media.md).
- [B8e page builder](../superpowers/specs/2026-10-05-b8e-page-builder-design.md): the `faqs`,
  `video` and `testimonials` blocks reuse these models.
- [B10 AI](../superpowers/specs/2026-10-08-b10-ai-design.md): the "Write with AI" drafts for
  articles.
