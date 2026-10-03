# B8c — Articles and article categories — Design

**Date:** 2026-10-03
**Status:** Approved by the phase orchestrator after an independent spec review (orchestration PO-3);
review findings 1–16 resolved in this version.
**Phase / slice:** B8 marketing extras, slice B8c (phase spec `2026-10-03-marketing-extras-design.md`).
**Requires:** B8a and B8b (closed sites, `academy_today()`, JSON-LD escaping, redirects and the sitemap filter).

**Evidence:** P1 audit §4.12 CNT-001 (articles: 5 tabs — basic / content / attachments / SEO / schema; cover
image, title\*, category\*, slug\*, short description\* (AI), publish date\*, published toggle, view count,
reaction count, content (AI), attachments, SEO title/description (AI), keywords (AI), schema codes repeater;
filter: status), CNT-002 (categories: icon, name\*, slug\*, description (AI)), §7.2 (Article / ArticleCategory,
published / draft), §16.2 ("Publishing an Article requires ArticleCategory … surfaces on the public site (site
settings must be live)"), §18.1 (categories reached from the Articles header), BR-38 (SEO title ≤ 60, SEO
description ≤ 160 for videos — reused here); TH audit §2.9 (CNT-001), §5.10 (CNT-001/002 gap rows).
TutorHamster's public site is disabled, so every visitor-facing behaviour is `[assumed]` (PO-2). AI generation is
B10's (phase M-3).

## 1. Goal

The academy publishes bilingual articles in categories on its public site — list, category and article pages
with SEO metadata — and visitors can mark an article helpful; all behind the `articles` feature, off by default.

## 2. Decisions

| # | Question | Answer | Source |
|---|---|---|---|
| C-1 | Category fields | `name_ar/en` (≤ 80, required), `slug` (`^[a-z0-9-]{1,60}$`, unique), `icon` (optional plain text ≤ 16 characters, meant for an emoji — [assumed]), `description_ar/en` (plain ≤ 300), `order` (`PositiveIntegerField`, 0). At most 100 categories. Lengths and cap [assumed]. | P1 CNT-002; M-4 |
| C-2 | Deleting a category in use | Refused with `ConflictError` (409): "This category has N articles; move or delete them first." (`on_delete=PROTECT`). | P1 §16.2; [assumed] |
| C-3 | Article fields | `category` (required FK), `slug` (as C-1, unique among articles), `title_ar/en` (≤ 160, required), `summary_ar/en` (TH "short description", plain ≤ 300, required), `body_ar/en` (rich text, Plan 2 allow-list unchanged, ≤ 50 000 after sanitising, required — [assumed], TH's content is not starred), `cover` (optional image, PNG/JPEG/WebP ≤ 2 MB, re-encoded by `etqan.site.images`, `uploads.article_path`), `publish_on` (date, required), `is_published` (bool, default false), `seo_title_ar/en` (≤ 60), `seo_description_ar/en` (≤ 160), `keywords_ar/en` (≤ 255), counters `views`, `reactions` (read-only), `created_at`, `updated_at`. Lengths [assumed] except BR-38's. | P1 CNT-001; BR-38; M-4, M-6 |
| C-4 | Status and publication | Derived status: **draft** (`is_published` false), **scheduled** (true, `publish_on` > academy today), **published** (true, `publish_on` ≤ today, B8b `academy_today()`); TH's status filter mapped onto these three [assumed]. Public = published, feature `articles` on, site not closed (M-9). Drafts cannot be previewed on the public site (non-goal). | P1 §7.2; [assumed] |
| C-5 | TH "schema codes repeater" | Not built: academy-supplied JSON-LD is script content on the shared origin (D2). The article page emits a generated `Article` JSON-LD (C-15). | D2 |
| C-6 | Attachments | Not built in B8c: file types unobserved; same-origin downloads should use B9a's shared upload rules (D12), not merged yet. Later slice. | P1 CNT-001; D12 |
| C-7 | Images inside the body | No; the allow-list stays (M-6). The cover is the article's image. | M-6 |
| C-8 | View count | Counted by the **browser**, not the server render: the article page sends `POST /api/v1/site/articles/<slug>/view/` with `fetch` after load. The API counts at most one view per client IP per article per 30 min (`cache.add(f"article_view:{article.id}:{ip_key}", 1, 1800)`, atomic). Clients without JS (most bots) never count. The detail GET has no side effect. | review #1; [assumed] |
| C-9 | Reactions | One "Helpful 👍" reaction. `POST /api/v1/site/articles/<slug>/react/`: at most one counted per client IP per article per 24 h (`cache.add(f"article_react:{article.id}:{ip_key}", 1, 86400)`); a repeat answers 200 `{"counted": false, "reactions": n}`. The page keeps a pressed state in `localStorage`. No separate rate throttle (the dedupe is the one mechanism). | TH reaction count; phase §3.1; review #6, #16 |
| C-10 | Client IP | `ip_key` = the client IP DRF derives with `NUM_PROXIES = 1` (Caddy is the first hop and overwrites `X-Forwarded-For`; a CDN in front would need that setting revisited). IPv6 is keyed by its /64. Visitors behind one NAT share a key — accepted. | settings `NUM_PROXIES`; review #6 |
| C-11 | View/react endpoint rules | `authentication_classes = []`, CSRF-exempt like the inquiry form, **JSON only** (`parser_classes = [JSONParser]`, so a cross-site HTML form cannot post and `fetch` with JSON forces a preflight). Feature off or article not public → 404; closed site → 403 `{"code": "site.closed"}` (as inquiries, B8a A-5). Body ignored. Response never publicly cacheable. | B8a A-5; review #7 |
| C-12 | Public URLs | `/<lang>/articles` (newest first: `publish_on` desc, then id desc; 12 per page; `?page=n` accepted only as `^[1-9][0-9]{0,3}$`, anything else or a page past the end → the academy 404), `/<lang>/articles/c/<category-slug>`, `/<lang>/articles/<slug>`. Pages ≥ 2 carry `<meta name="robots" content="noindex,follow">` and canonicalise to themselves. Header link "Articles" / "المقالات" while `has_articles`. The closed-site rewrite (B8a) already covers these paths. Article and category slugs never collide (`/c/` segment). Changing a slug breaks the old URL; the dashboard hints "Add a redirect from the old address" (B8b allows `/en/articles/<old>`). | [assumed]; review #4, #14, #15 |
| C-13 | Public API | Shapes in §4.1. List and category endpoints use a dedicated pagination class (`page_size = 12`, no `page_size` parameter) with an envelope `{count, page, pages, results}` (no absolute `next` URLs). `?category=<slug>` that is unknown or has no public article → 404. Site payload gains only `has_articles: bool`. Everything 404s (or `false`) when the feature is off or the site is closed. Detail GETs keep the public 60 s cache; they carry no side effect. | review #2–#4 |
| C-14 | Sitemap | `GET /api/v1/site/articles/sitemap/` → `{"articles": [{slug, updated_at}], "categories": [slug]}`, newest first, at most 5 000 articles; 404 when off/closed. Marketing adds the index, each category page and each article (both languages, `<lastmod>` from `updated_at`) to the existing `paths` list, so B8b's redirect filter applies. | review #2 |
| C-15 | SEO and Open Graph | `Layout` gains optional props `ogType` (`"article"`), `image` (cover, falling back to the share image), `keywords` (article's, falling back to the site's) and `article` (`published_time`, `modified_time`, `section`). Title/description = SEO fields, falling back to title/summary. JSON-LD `Article`: `headline` (title, cut at 110), `description`, `image` (absolute cover URL, omitted when none), `datePublished` = `publish_on`, `dateModified` = `updated_at`, `publisher` = academy (`EducationalOrganization` with logo when present), `mainEntityOfPage` = canonical URL; rendered through the existing `escapeLd`. | D2; review #8 |
| C-16 | Counters vs edits | Counters change only with `Article.objects.filter(pk=…).update(views=F("views") + 1)` (same for reactions), which leaves `updated_at` alone. Admin saves write only editable fields (`save(update_fields=[…, "updated_at"])`), never the counters. | review #5 |
| C-17 | Cover lifecycle | Replacing the cover or deleting the article deletes the old file; `cover_clear=true` (multipart) removes it. Same pattern as B8b's banner. | B8b B-4; review #9 |
| C-18 | Feature and permissions | Registry: `articles` flipped in place to `_built(..., default=False)`. Access resources under `── phase B8 ──`: `article` ("Articles" / "المقالات") and `article_category` ("Article categories" / "فئات المقالات"), verbs view, view_any, create, update, delete. | M-5; spec 2026-09-28 |
| C-19 | Dashboard | Website tab "Articles" (`article.view_any`, feature `articles`): paginated list (25 per page, the admin endpoint paginates — articles have no cap) with status (all / draft / scheduled / published) and category filters; editor with Arabic/English side by side, cover upload/clear, SEO section, read-only counters, and the slug-change hint. A "Categories" link opens `/website/articles/categories` (`article_category.view_any`), a sibling route (`website.articles_.categories.tsx`). Categories list unpaginated (cap 100). A 409 on category delete shows its message. | P1 CNT-001, §18.1 |
| C-20 | Deploy skew | Marketing: `site.has_articles ??= false`; article endpoints answering 404 from an older backend render the academy 404. | B8a/B8b pattern; review #10 |
| C-21 | Seeds | Demo: two categories; two published articles (`publish_on` = seed date − 7 and − 1) and one scheduled (`publish_on` = seed date + 30, moved forward on every re-seed). Idempotent by slug; covers generated only when missing. | review #11 |

## 3. Data (`etqan.site`, one additive migration)

`ArticleCategory` and `Article` per C-1 and C-3; `Article.category` `PROTECT`; categories ordered `order, id`;
articles `-publish_on, -id`.

## 4. Behaviour

### 4.1 Public API shapes

```jsonc
// GET /api/v1/site/articles/?category=<slug>&page=<n>
{"count": 14, "page": 1, "pages": 2,
 "category": {"slug": "tajweed", "name": {"ar": "…", "en": "…"}, "description": {…}, "icon": "📖"},  // only with ?category
 "results": [{"slug": "…", "title": {…}, "summary": {…}, "cover_url": "…", "publish_on": "2026-10-01",
              "category": {"slug": "…", "name": {…}}}]}
// GET /api/v1/site/articles/<slug>/  — summary fields plus:
{"body_html": {…}, "seo_title": {…}, "seo_description": {…}, "keywords": {…},
 "updated_at": "2026-10-02T10:00:00Z", "reactions": 12}          // views are not public
// GET /api/v1/site/article-categories/  — categories with ≥ 1 public article
[{"slug": "…", "name": {…}, "description": {…}, "icon": "…"}]
// POST …/view/ → 204;  POST …/react/ → {"counted": true, "reactions": 13}
```

### 4.2 Services

`public_articles(today)`, `public_categories(today)`, `article_status(article, today)`, `count_view(article, ip)`,
`react(article, ip) -> (counted, reactions)`, `ip_key(ip)`.

### 4.3 Admin API

CRUD `/api/v1/site/admin/articles/` (paginated 25; multipart for cover; `?status=draft|scheduled|published`,
`?category=<id>`; read-only `status`, `views`, `reactions`), CRUD `/api/v1/site/admin/article-categories/`
(unpaginated; cap 100); `[HasCode, FeatureOn]`; route-table rows (ROUTES, FEATURES, FEATURE_WORDS).

### 4.4 Marketing

Pages per C-12, metadata per C-15, view beacon and reaction button (`fetch` with JSON; the button is hidden
without JS), header link, sitemap per C-14. Reaction counts come from the uncached detail fetch, so a reload
shows the new count.

## 5. Testing

Backend: validation and caps; PROTECT → 409; status around midnight in a non-UTC timezone; public endpoints per
feature/closed/draft/scheduled; pagination envelope and bounds; view and reaction dedupe (same IP, other IP, IPv6
/64, other article), JSON-only (form POST → 415), closed → 403; counters survive a concurrent admin save and do
not touch `updated_at`; cover replace/clear/delete; admin filters and pagination; route table; isolation; seeds
idempotent with the scheduled date moved. Marketing: the three pages in both languages, pagination and bad
`?page`, noindex on page ≥ 2, OG/JSON-LD (a title containing `</script>`), beacon and button, header link,
sitemap with redirect filtering, `has_articles` default. Dashboard: list, filters, pager, editor, cover clear,
categories, 409 message, gating. e2e `b8-articles.spec.ts` (demo): the admin creates category `b8c-<stamp>` and an
article `b8c-<stamp>` with `publish_on` = yesterday (avoids runner/academy timezone skew); the public page shows
it; one reaction counts and a reload shows the new count; `afterAll` deletes the article then the category by id
(PROTECT order), plus a sweep of `b8c-` slugs.

## 6. Non-goals

AI generation (B10); attachments (C-6); custom schema code (C-5); comments; images in the body; authors; RSS;
draft previews on the public site; per-visitor view dedupe beyond IP.
