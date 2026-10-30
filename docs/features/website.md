---
title: "Public website and branding"
---

Every academy has its own bilingual (Arabic and English) public website at the root of each of its
hosts. It shows a home page, extra pages, testimonials and a contact or trial form. Its name, logo
and colours also brand the dashboard and the emails the academy sends. Academy admins, and staff
with `site.*` / `inquiry.*` codes, edit it in the dashboard's Website area. Public visitors read it,
and the Astro app in `marketing/` renders it. The optional content types (FAQs, ads, redirects,
articles, videos) are on [website-content.md](website-content.md).

## Concepts

All models are in `etqan.site.models`, in the **academy** schema.

| Model | Purpose |
|---|---|
| `Branding` (singleton) | Names and taglines (`_ar` / `_en`), `logo`, `favicon`, `share_image`, `primary_color`, `primary_text` (derived), `accent_color`, contact email, phone, WhatsApp and address, nine social links (facebook, instagram, youtube, x, tiktok, telegram, linkedin, snapchat, soundcloud), `show_powered_by` |
| `LandingContent` (singleton) | Hero title, subtitle and image, CTA label, about text (sanitised HTML), section flags `show_courses/packages/teachers/testimonials/contact`, `intro_video` (FK `Video`) |
| `SiteSettings` (pk 1, `current()`) | `status` (`live` / `maintenance` / `beta` / `system_only`), tracking IDs (`ga4_id`, `meta_pixel_id`, `adsense_client`, `google_site_verification`), `footer_text_*`, `keywords_*` |
| `SitePage` | Extra page at `/<lang>/p/<slug>`. `layout` is `rich` (`body_ar` / `body_en` HTML) or `blocks` (`blocks` JSON, the page builder). SEO description, `show_in_menu`, `is_published`, `order`. Some slugs are reserved (`app`, `api`, `p`, `ar`, `en`, …) |
| `PageImage` | An image uploaded for one page's blocks. At most 40 per page |
| `Testimonial` | Author, quote (`_ar` / `_en`), `stars` 1–5, `kind` (`text` / `audio` / `video`), `audio` file or `video` FK, `is_published`, `order` |
| `Inquiry` | A contact or trial request from the public form: `kind`, name, email and/or phone, `has_whatsapp`, message, `locale`, `status` (`new` / `handled`), `handled_by`, `source_host` |

Uploads go to `tenants/<schema>/site/<kind>/<uuid>.<ext>` (`site/uploads.py`), on S3 in production.
Images are re-encoded by `site/images.py:clean_image`: PNG, JPEG or WebP. The logo can be at most
1 MB, the favicon 256 KB (PNG or ICO), other images 2 MB.

## How it works

### Rendering the public site

1. Caddy sends every non-`/api`, non-`/app` path on an academy host to the marketing SSR
   (`marketing/`, Astro, Node adapter).
2. `marketing/src/middleware.ts` calls `resolveSite(host)` (`src/lib/site.ts`). The call is
   `GET /api/v1/site/` with the visitor's `Host`, sent to `SITE_API_ORIGIN` (in production, Caddy's
   internal `:8098` listener, which adds `X-Etqan-Internal` so public throttles skip it).
   - Results are cached in memory per host: 60 s for a found site, 30 s for not found or suspended.
     Errors are never cached.
   - A 404 becomes `notfound`. A 403 `tenant.suspended` becomes `suspended`, served as 503 on every
     path. Any other failure becomes `unavailable`, also 503.
3. The middleware then applies the site status and redirects (see below). Pages read
   `Astro.locals.siteResult`. `/` redirects to `/ar/` or `/en/` from `Accept-Language`.
4. Public pages: `/[lang]/` (home), `/[lang]/p/[slug]`, `/[lang]/faq`, `/[lang]/articles/...`,
   `/[lang]/videos/...`, `/[lang]/recorded-courses/...` and `/[lang]/consultations/...` (the last two
   belong to the B7 add-on sales features), plus `/robots.txt` and `/sitemap.xml`.
5. `GET /api/v1/site/` (`site/api/views.py:SiteView`) returns everything for one render: academy
   subdomain and canonical host (the primary domain), branding, landing, published testimonials,
   visible pages for the menu, settings, and the FAQ, ad, redirect and has-articles / has-videos
   flags. Each optional part is empty when its feature is off or the site is closed. Responses
   carry `Cache-Control: public, max-age=60`.

### Site status (feature `site_status`)

- `site/services.py:effective_status()` returns the stored status while `site_status` is on, and
  `live` otherwise. `is_closed()` is true for `maintenance` and `system_only`.
- When the site is closed:
  - The API serves an empty landing (`closed_landing_payload`) with no pages, testimonials or
    optional content. Page, article and video endpoints return 404. Inquiries and beacons return
    403 `site.closed`.
  - The marketing middleware rewrites every path to `/closed-site` with `X-Robots-Tag: noindex`.
    Maintenance also adds `Retry-After: 3600`.
  - A `system_only` site serves `Disallow: /` in robots.txt and an empty sitemap.
- `beta` shows a banner (`marketing/src/layouts/Layout.astro`).
- The dashboard under `/app` keeps working in every status.
- For ops: `manage.py tenant_command set_site_status <status> --schema=<schema>`.

### Tracking (feature `site_tracking`)

The four IDs are validated by pattern (`SiteTrackingAdminSerializer`). They reach the public payload
only while the feature is on. `marketing/src/components/Tracking.astro` then injects GA4, the Meta
Pixel, AdSense and the Search Console meta tag.

### Branding

- Saving branding derives `primary_text` (white or near-black, whichever reaches WCAG 4.5:1) from
  `primary_color` (`site/colors.py:text_color_for`). An unreadable colour is refused.
- `GET /api/v1/site/branding/` (anonymous, `no-cache`) is the dashboard's boot call.
  `dashboard/src/features/branding/BrandProvider.tsx` → `apply.ts` sets `--primary`,
  `--primary-foreground`, `--accent` and derived variables, and sets the favicon. `usePageTitle`
  and `BrandWordmark` use the academy name.
- Emails: `site/emails.py:brand_email()` wraps identity and other notices with the academy's name,
  logo and contact details. It uses the academy's contact email as reply-to. In the public schema
  it only adds the `[Etqan]` subject prefix.
- Installable app: `site/services.py:branding_snapshot()` feeds the B11 web manifest and icons.
- `ensure_site_defaults(name)` creates `Branding`, `LandingContent` and `SiteSettings` when they are
  missing. It runs when an academy is created and lazily in the public views.

### Pages and the page builder (feature `page_builder`)

- A rich page needs non-blank `body_ar` and `body_en`, sanitised by `site/sanitize.py:clean_html`
  (nh3 allow-list).
- A blocks page needs at least one block. Switching a page to `blocks`, or writing `blocks`, needs
  `page_builder` on.
  - `site/blocks.py:validate_blocks` checks the eight block types: `heading`, `text`, `image`,
    `video`, `button`, `testimonials`, `faqs`, `divider`. Each block has a 32-hex `id`. A page can
    have at most 40 blocks and 200 KB of JSON.
  - Button targets are an internal target (`home`, `faq`, `articles`, `videos`, `contact`), another
    page, or an http(s) URL that is not the academy's own host.
- Page images are uploaded through `admin/pages/<id>/images/`. Saving a page prunes images no
  block references (`services.prune_page_images`). Deleting a page deletes its files after commit
  (`services.delete_page`).
- Public: `blocks.page_visible()` hides unpublished pages, and hides blocks pages while
  `page_builder` is off. The admin serializer then reports `needs_page_builder`.
  `resolve_blocks()` turns stored references into public data: image URLs, videos, testimonials,
  FAQs, language hrefs. A reference to something gone or unpublished drops out.

### Testimonials (media: feature `testimonial_media`)

Text testimonials are always available. Audio (at most 10 MB) and video kinds need
`testimonial_media` on, and video also needs `video_library`. When a media kind cannot be shown,
the public payload serves the testimonial as text (`site/payloads.py:testimonial_payload`).

### Inquiries

1. `POST /api/v1/site/inquiries/` is anonymous and needs no CSRF.
   - Needs an email or a phone.
   - Has a honeypot field `website`: a filled honeypot gets a fake 201.
   - Throttled per schema by IP (10/hour) and by email (5/hour).
   - Stores `source_host`.
2. The office lists inquiries with `?status=` and `?kind=` filters, and marks them handled
   (`handled_by` is set to the caller).
3. On the inquiries screen, a trial inquiry can become a trial request (`TrialFromInquiry` from
   `features/scheduling`; one per inquiry, enforced in `scheduling/services/trials.py`).

## API

Public endpoints are anonymous, read the academy from `Host`, and are cached for 60 s unless noted.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/site/` | Public | The whole site payload for one render |
| GET | `/api/v1/site/branding/` | Public (`no-cache`) | Branding only (dashboard boot) |
| GET | `/api/v1/site/pages/<slug>/` | Public | One visible page (rich HTML or resolved blocks). 404 when closed |
| POST | `/api/v1/site/inquiries/` | Public, throttled | Contact or trial form. 403 `site.closed` when closed |
| GET, PATCH | `/api/v1/site/admin/branding/` | `site.view` / `site.update` | Branding (JSON or multipart; a file can be cleared) |
| GET, PATCH | `/api/v1/site/admin/landing/` | `site.view` / `site.update` | Home page content |
| GET, PATCH | `/api/v1/site/admin/settings/` | `site.view` / `site.update` | Footer text and SEO keywords |
| GET, PATCH | `/api/v1/site/admin/status/` | `site.view` / `site.update`, feature `site_status` | Site status |
| GET, PATCH | `/api/v1/site/admin/tracking/` | `site.view` / `site.update`, feature `site_tracking` | Tracking IDs |
| GET, POST | `/api/v1/site/admin/pages/` | `site.view_any` / `site.create` | List or create pages (unpaginated) |
| GET, PUT, PATCH, DELETE | `/api/v1/site/admin/pages/<id>/` | `site.view` / `site.update` / `site.delete` | One page |
| GET, POST | `/api/v1/site/admin/pages/<page_id>/images/` | `site.view_any` / `site.create`, feature `page_builder` | List or upload page images (multipart) |
| DELETE | `/api/v1/site/admin/pages/<page_id>/images/<id>/` | `site.delete`, feature `page_builder` | Delete one image |
| GET, POST | `/api/v1/site/admin/testimonials/` | `site.view_any` / `site.create` | Testimonials |
| GET, PUT, PATCH, DELETE | `/api/v1/site/admin/testimonials/<id>/` | `site.*` | One testimonial |
| GET | `/api/v1/site/admin/inquiries/` | `inquiry.view_any` | Inquiries (paginated, `?status=`, `?kind=`) |
| POST | `/api/v1/site/admin/inquiries/<id>/handle/` | `inquiry.update` | Mark handled |

Admins pass every `HasCode` check. Staff need the code.

## Dashboard

`/app/website` (`routes/_authed/website.tsx`) is office-only (`requireOffice`). It has a tab bar
built from `WEBSITE_TABS` in `features/shell/nav.ts`, filtered by permission code and feature, and
a "Preview site" link to `/<lang>/`. `/app/website` opens the first allowed tab
(`website.index.tsx`).

| Route | Component (`features/website/`) |
|---|---|
| `/app/website/branding` | `BrandingForm.tsx` |
| `/app/website/home` | `HomePageForm.tsx` |
| `/app/website/pages`, `/app/website/pages/$pageId` | `PagesList.tsx`, `PageEditor.tsx` (`BlockListEditor.tsx`, `BlockForms.tsx`, `RichTextEditor.tsx`) |
| `/app/website/testimonials` | `TestimonialsManager.tsx` |
| `/app/website/inquiries` | `InquiriesList.tsx` (+ `TrialFromInquiry`) |
| `/app/website/settings` | `SiteSettingsForm.tsx` (footer and keywords; status and tracking sections appear when their features are on) |

`features/branding/` holds the boot-time branding (`BrandProvider`, `applyBranding`,
`usePageTitle`, `BrandWordmark`, `PrintSheet`). `features/website/api.ts` holds every admin call.

## Background jobs

None.

## Configuration

- Features: `site_status`, `site_tracking`, `page_builder`, `testimonial_media`, `video_library`
  (all `content`, off by default). The content features are on website-content.md.
- Permission codes: `site.view`, `site.view_any`, `site.create`, `site.update`, `site.delete`,
  `inquiry.view_any`, `inquiry.update`.
- Throttles: `inquiry_ip` 10/hour, `inquiry_email` 5/hour.
- Marketing env: `SITE_API_ORIGIN` (default `http://127.0.0.1:8000`), `SITE_SCHEME` (canonical
  URLs, default `https`), `ETQAN_HMR_CLIENT_PORT` (dev).
- Storage: `DJANGO_S3_*` in production (`config/settings/production.py`).

## Code map

- `backend/etqan/site/models.py`, `services.py`, `blocks.py`, `payloads.py`, `colors.py`,
  `images.py`, `sanitize.py`, `uploads.py`, `emails.py`, `throttling.py`
- `backend/etqan/site/api/views.py` (public), `api/admin_views.py`, `api/admin_serializers.py`,
  `api/serializers.py`, `api/urls.py`
- `backend/etqan/site/management/commands/set_site_status.py`
- `dashboard/src/features/website/`, `dashboard/src/features/branding/`,
  `dashboard/src/routes/_authed/website*.tsx`
- `marketing/src/middleware.ts`, `src/lib/site.ts`, `src/lib/http.ts`, `src/lib/seo.ts`,
  `src/lib/i18n.ts`, `src/layouts/Layout.astro`, `src/components/` (`Hero`, `About`,
  `Testimonials`, `ContactForm`, `PageBody`, `PageBlocks`, `Tracking`, `ClosedPage`, `StatusPage`),
  `src/pages/`

## Design history

- [Academy sites and branding](../superpowers/specs/2026-09-23-academy-sites-design.md): the
  `site` app, the Astro site, path routing, custom domains, the Website area. Implemented in
  [Plan 2](../superpowers/plans/2026-09-23-plan-2-academy-sites.md). Its non-goals (page builder,
  articles) were lifted by marketing-extras.
- [Marketing extras (B8 phase)](../superpowers/specs/2026-10-03-marketing-extras-design.md): the
  phase split B8a–B8e. Its M-8 note on large video uploads was replaced by B8d.
- [B8a site settings](../superpowers/specs/2026-10-03-b8a-site-settings-design.md): status, tracking,
  footer, keywords, extra socials. Implemented in
  [Plan 16](../superpowers/plans/2026-10-03-plan-16-site-settings-depth.md).
- [B8d media](../superpowers/specs/2026-10-04-b8d-media-design.md): audio and video testimonials,
  intro video. Implemented in [Plan 27](../superpowers/plans/2026-10-04-plan-27-media.md).
- [B8e page builder](../superpowers/specs/2026-10-05-b8e-page-builder-design.md): a structured
  block editor instead of TutorHamster's GrapesJS. Implemented in
  [Plan 30](../superpowers/plans/2026-10-05-plan-30-page-builder.md).
- [B11 apps](../superpowers/specs/2026-10-09-b11-apps-design.md): reads branding for the manifest.
