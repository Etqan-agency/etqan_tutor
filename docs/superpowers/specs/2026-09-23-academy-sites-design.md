# Academy sites & branding — Design

**Date:** 2026-09-23
**Status:** Approved in brainstorming, awaiting written-spec review
**Amends:** `2026-09-23-etqan-tutor-v1-design.md` (removes "CMS/marketing site" from §1.2 non-goals; supersedes the branding fields of §4.1 `AcademySettings`; changes the §3 routing layout)
**Delivery:** Plan 2 (this spec). The former Plan 2 "people & catalogue" becomes Plan 3 and adds the courses / packages / teachers sections defined here.

---

## 1. Goal

Every academy looks like its own business: its own public website (bilingual, SEO-friendly, on its subdomain or its own domain) and its own name, logo and colours on everything its users see — the public site, the dashboard, and the emails it sends. Etqan's brand appears only on the Etqan staff console and, optionally, a "Powered by Etqan" footer link.

### 1.1 Decisions

| # | Decision | Choice |
|---|---|---|
| S1 | Public site content | Fixed landing-page template filled from academy data **plus** extra rich-text pages the academy admin writes |
| S2 | Addresses | `<name>.<etqan-domain>` for every academy **and** custom domains in v1 (e.g. `noor-academy.com`) |
| S3 | Languages | Arabic **and** English, both mandatory for every academy; every public text field has `_ar` and `_en` |
| S4 | Rendering | Separate server-rendered **Astro** app in a new repo `etqan_tutor_marketing`, resolving the academy by `Host` through a Django API |
| S5 | Edge proxy | **Caddy** replaces Traefik (local and production) for on-demand TLS on custom domains |
| S6 | Editing | Academy admins edit branding and site content in a new **Website** area of the dashboard; Etqan staff manage only domains |

### 1.2 Non-goals

Drag-and-drop page builder; per-academy themes/layouts beyond colours, logo and section toggles; blog/articles; online payments on the public site; analytics dashboards; A/B tests; academy-chosen sender email addresses (sender *name* only); Etqan's own marketing site on the bare domain (later).

---

## 2. Architecture and routing

### 2.1 Repositories

| Repo | Change |
|---|---|
| `Etqan-agency/etqan_tutor_marketing` | **New, private.** Mirror of `kaleem-lms/marketing`, stripped to a tenant-aware Astro SSR app (`@astrojs/node`, standalone). Added to the meta repo as submodule `marketing/`. Consumes `@etqan/tokens`. |
| `etqan_tutor_backend` | New tenant app `etqan.site`; domain management in `etqan.tenants`; branded emails; internal TLS-allow endpoint. |
| `etqan_tutor_dashboard` | Served under `/app/`; runtime branding; new **Website** area. |
| `etqan_tutor_infra` | Caddy replaces Traefik; marketing service added. |
| `etqan_tutor` (meta) | Local compose switches to Caddy; marketing submodule; CI job for marketing. |

### 2.2 Path routing on every academy host (subdomain or custom domain)

| Path | Service |
|---|---|
| `/api/*`, `/accounts/*`, `/health/*` | Django |
| `/app/*` | Dashboard SPA (Vite `base: "/app/"`, router `basepath: "/app"`) |
| `/media/*` | Django-served media in dev; object storage URL in production |
| everything else | Astro public site |
| bare `<etqan-domain>` | Django (Etqan staff admin, `/health/`, internal endpoints) |

Existing dashboard links, email links and `frontend_url()` consumers change from `<host>/…` to `<host>/app/…` for app routes (login, reset-password, verify-email, account). `frontend_url()` keeps returning the host origin; callers append `/app/…`.

### 2.3 Academy resolution in Astro

1. Request arrives at Astro with the visitor's `Host`.
2. Astro calls `GET http://django:8000/api/v1/site/` with header `Host: <visitor host>` (internal network). django-tenants resolves the academy exactly as for any API call.
3. Responses:
   - `200` — site payload (§3.6) → render.
   - `404` — unknown host → Astro renders a generic "Site not found" page (no academy data, `noindex`).
   - `403 {"code":"tenant.suspended"}` → Astro renders "This site is temporarily unavailable" (`noindex`).
4. In-memory cache keyed by host, TTL 60 s; 404/403 cached 30 s. No cross-host reuse.

### 2.4 Languages

- URLs: `/ar/…` and `/en/…`. Page slugs are shared across languages (`/ar/p/policies`, `/en/p/policies`).
- `/` → 302 to `/ar/` or `/en/` from `Accept-Language` (Arabic when neither matches).
- Every page: `<html lang dir>`, `hreflang` alternates for both languages plus `x-default`, language switch in the header.

### 2.5 Inquiry form

`POST /api/v1/site/inquiries/` (public, JSON). Protections: per-IP throttle (`inquiry`: 10/hour), per-email throttle (5/hour), honeypot field (non-empty → 201 with no row created), max lengths. Creates an `Inquiry` in the academy's schema and an in-app/email notice to that academy's admins (email only if the notifications module exists; until then in-app list only). Astro submits it from the browser with `fetch` to the same host (same-origin; CSRF exempt for this one endpoint because it creates no session and is throttled).

---

## 3. Data (backend app `etqan.site`, tenant schema)

All public text fields exist as `<field>_ar` and `<field>_en`; **both are required** whenever the field is required.

### 3.1 `Branding` (singleton per academy)
`name_ar/en` (required), `tagline_ar/en`, `logo` (image, PNG/SVG/WebP ≤ 1 MB), `favicon` (PNG/ICO ≤ 256 KB), `share_image` (≤ 2 MB), `primary_color`, `accent_color` (hex `#RRGGBB`; validated: WCAG AA ≥ 4.5:1 against white **or** against `#111111`, the colour stores which text colour to use), `contact_email`, `contact_phone`, `whatsapp` (E.164), `address_ar/en`, social URLs (`facebook`, `instagram`, `youtube`, `x`, `tiktok`, `telegram`), `show_powered_by` (bool, default true), `updated_at`.
Created with defaults (`name_*` = academy name, Etqan default colours) by `create_academy`.

### 3.2 `LandingContent` (singleton per academy)
`hero_title_ar/en` (required), `hero_subtitle_ar/en`, `hero_image`, `cta_label_ar/en` (default "احجز حصة تجريبية" / "Book a free trial"), `about_ar/en` (rich text), section toggles `show_courses`, `show_packages`, `show_teachers`, `show_testimonials`, `show_contact` (defaults: courses/packages/teachers **false** until Plan 3 data exists; testimonials, contact true).

### 3.3 `Testimonial`
`author_name`, `quote_ar/en` (required), `stars` (1–5), `is_published`, `order`.

### 3.4 `SitePage`
`slug` (unique, `^[a-z0-9-]{1,60}$`, reserved: `app`, `api`, `accounts`, `health`, `media`, `ar`, `en`, `p`, `sitemap.xml`, `robots.txt`), `title_ar/en` (required), `body_ar/en` (rich text, required), `show_in_menu`, `order`, `is_published`, `seo_description_ar/en`.

### 3.5 `Inquiry`
`kind` (`contact · trial`), `name`, `email`, `phone`, `has_whatsapp`, `message` (≤ 2000), `locale` (`ar · en`), `preferred_course` (nullable FK — added in Plan 3), `status` (`new · handled`), `handled_by`, `created_at`, `source_host`.

### 3.6 Public site payload (`GET /api/v1/site/`, `AllowAny`)
```jsonc
{
  "academy": { "subdomain": "noor", "canonical_host": "noor-academy.com" },
  "branding": { "name": {"ar":"…","en":"…"}, "tagline": {...}, "logo_url": "…", "favicon_url": "…",
                "share_image_url": "…", "primary_color": "#0E7C66", "primary_text": "#FFFFFF",
                "accent_color": "…", "contact": {...}, "social": {...}, "show_powered_by": true },
  "landing": { "hero_title": {...}, "hero_subtitle": {...}, "hero_image_url": "…", "cta_label": {...},
               "about_html": {...}, "sections": {"courses": false, "packages": false, "teachers": false,
                                                 "testimonials": true, "contact": true} },
  "testimonials": [ {"author_name": "…", "quote": {...}, "stars": 5} ],
  "pages": [ {"slug": "policies", "title": {...}, "show_in_menu": true} ]
}
```
`GET /api/v1/site/pages/<slug>/` returns one published page (`title`, `body_html`, `seo_description` per language) or 404. `GET /api/v1/site/branding/` returns only the `branding` object (used by the dashboard before login). All three are `AllowAny`, read-only, and cacheable (`Cache-Control: public, max-age=60`).

### 3.7 Rich text
Stored as HTML, sanitised on save with an allow-list (`p, h2, h3, ul, ol, li, strong, em, a[href, rel, target], blockquote, br`); `a[href]` limited to `http(s):`, `mailto:`, `tel:`; `rel="noopener nofollow"` forced on external links. Library: `nh3`.

### 3.8 Files
Uploads go through Django storage with an academy-prefixed path `tenants/<schema_name>/site/<field>/<uuid>.<ext>`: `FileSystemStorage` under `MEDIA_ROOT` in dev (served at `/media/`), S3-compatible in production (`django-storages`, bucket from env). Images are re-encoded (Pillow) to strip metadata and enforce size limits.

### 3.9 Admin API (academy admin only; `role == admin`)
`GET/PATCH /api/v1/site/admin/branding/`, `GET/PATCH /api/v1/site/admin/landing/`, CRUD `/api/v1/site/admin/pages/`, CRUD `/api/v1/site/admin/testimonials/`, `GET /api/v1/site/admin/inquiries/` (filter by status/kind), `POST /api/v1/site/admin/inquiries/<id>/handle/`. File fields accept multipart uploads.

---

## 4. The academy's name on everything

### 4.1 Dashboard
- Boot: `GET /api/v1/site/branding/` before rendering routes (also on login/reset pages).
- Applies: `document.title = "<page> · <academy name>"`, favicon `<link rel=icon>`, CSS variables `--primary`, `--primary-foreground`, `--accent` overriding `@etqan/tokens` defaults, logo + name replacing the Etqan wordmark in `AuthLayout` and `AppTopbar`.
- Fallback if the call fails: neutral tokens, name from `window.location.host`.

### 4.2 Emails
- From header: `"<academy name in recipient locale>" <DEFAULT_FROM_ADDRESS>` (address stays the platform's verified sender).
- Subject prefix: `[<academy name>] `.
- Shared bilingual layout (text + HTML) with academy logo, name, contact line, and link to the academy home page; direction follows the recipient's locale.
- Links use `frontend_url()` (primary domain) + `/app/…`.
- Etqan staff emails (from the public schema) keep Etqan branding.

### 4.3 Website area in the dashboard (admin role only)
Routes under `/app/website/`: **Branding**, **Home page**, **Pages** (list + editor), **Testimonials**, **Inquiries** (list, filter, mark handled). Each form shows Arabic and English fields side by side and validates both. A "Preview site" link opens the public site in a new tab.

---

## 5. Custom domains and the edge

### 5.1 Domain management (Etqan staff, Django admin)
`Domain` gains `status` (`pending · active · disabled`), `verified_at`, `is_custom` (false for `<sub>.<etqan-domain>`). The migration sets every existing row to `status=active, is_custom=false`; subdomains created by `create_academy` are born `active`. Academy change page gets a Domains inline:
- Add domain → `pending`; admin shows DNS instructions: CNAME → `sites.<etqan-domain>`, or for an apex domain an A record → `EDGE_PUBLIC_IP` (setting).
- Action **Check DNS** → resolves the domain; if it resolves to `sites.<etqan-domain>`'s addresses, set `active` + `verified_at`; otherwise show what it resolved to.
- Action **Make primary** (active only) → becomes `is_primary`; the subdomain stays as a working fallback.
- Action **Disable**.
- Only `active` domains are served: TenantMainMiddleware lookup is wrapped so `pending`/`disabled` custom domains 404.

### 5.2 Caddy
- `*.<etqan-domain>` + apex: one wildcard certificate via DNS-01 (Cloudflare API token, `caddy-dns/cloudflare` build).
- Custom domains: `on_demand_tls` with `ask http://django:8000/internal/tls-allowed` → Django (public URLconf, not reachable from outside: Caddy blocks `/internal/*` from the public listener) returns `200` only when `?domain=` matches an `active` Domain row, else `404`.
- Routes per §2.2; `X-Forwarded-Proto` set; HTTP → HTTPS redirect; `www.` custom domains redirect to the apex only if both are registered, otherwise served as-is.
- Local: Caddy on `:80` with `http://*.etqan.localhost` and `http://etqan.localhost`; custom domains testable via `/etc/hosts` with `auto_https off`.

### 5.3 SEO
- `sitemap.xml` per host: home and published pages in both languages, absolute URLs on the **canonical host** (primary domain).
- `robots.txt` per host: allow all, `Sitemap:` line; `Disallow: /app/`, `/api/`.
- `<link rel=canonical>` always on the canonical host; non-canonical hosts still serve content (no redirect loop risk) but canonicalise.
- Open Graph / Twitter tags from branding + page; JSON-LD `EducationalOrganization` with name, logo, contact, social links.

---

## 6. Testing

- **Backend:** site payload only contains the requesting academy's data (two academies with different names); inquiry created on host A absent from B; inquiry throttle and honeypot; TLS-allow returns 200 only for active domains (pending, disabled, unknown, subdomain-of-other → 404); pending/disabled custom domains 404 on all paths; rich-text sanitiser strips `<script>`, `on*=` attributes and `javascript:` links; colour contrast validation; required `_ar`/`_en` pairs; `create_academy` creates default Branding + LandingContent; branded email From/subject/layout.
- **Astro:** render tests from API fixtures — both languages with correct `lang`/`dir`, hidden sections, page 404, unknown-host page, suspended page, canonical/hreflang/sitemap output.
- **Dashboard:** runtime branding applied (title, favicon, CSS vars, wordmark) with fallback; Website forms validate both languages.
- **E2E:** academies `demo` and `other` seeded with different names/colours/testimonials: each home page, login screen and tab title shows its own name; a contact submission on `demo` appears in demo's Inquiries and not in other's; `/app/` login still works; unknown host shows "Site not found".

---

## 7. Changes to the v1 spec

- §1.2 non-goals: remove "CMS/marketing site"; add "page builder".
- §3: routing per this spec §2.2; custom domains per §5.
- §4.1 `AcademySettings`: drop display name, logo, primary colour (now `Branding`).
- §9 milestones: insert "Academy sites & branding" before "People & catalogue".
