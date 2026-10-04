# Plan 24 — Articles and article categories (B8c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B8a, B8b (merged)

**Goal:** Bilingual articles in categories on the public site (list, category and article pages with SEO and
Open Graph), browser-counted views and a "Helpful" reaction, managed from the dashboard — behind `articles`, off
by default.

**Architecture:** `ArticleCategory` and `Article` in `etqan.site`; public read endpoints (paginated, no side
effects) plus two JSON-only POST beacons (view, react) deduplicated per client IP in the cache; counters updated
with `F()` only. Astro renders three page types, extends `Layout` with article metadata and adds sitemap entries
from a dedicated endpoint. Dashboard gets an Articles tab with a categories sub-page.

**Tech Stack:** Django 5 + DRF + django-tenants (pytest), Astro 6 SSR (vitest), React + TanStack (vitest), Playwright.

**Spec:** `docs/superpowers/specs/2026-10-03-b8c-articles-design.md` (binding: C-1…C-21, §4.1 shapes).

## Global Constraints

- Branch `feat/b8c-articles` in meta, `backend/`, `dashboard/`, `marketing/`. No `git submodule` writes, no
  `git stash`, no `git commit -a` in meta. Run manage/pytest/e2e only through the stream stack.
- Feature `articles` flipped in place: `_later(...)` → `_built(..., default=False)` (label/group unchanged).
- Access resources under `# ── phase B8 ──`: `article` ("Articles" / "المقالات"), `article_category`
  ("Article categories" / "فئات المقالات"); in use: view, view_any, create, update, delete.
- Limits: category name ≤ 80, icon ≤ 16, description ≤ 300, ≤ 100 categories; slug `^[a-z0-9-]{1,60}$`;
  title ≤ 160, summary ≤ 300, body ≤ 50 000 after sanitising, SEO title ≤ 60, SEO description ≤ 160,
  keywords ≤ 255; cover PNG/JPEG/WebP ≤ 2 MB.
- Public list page size 12 (no `page_size` param); admin article list page size 25; sitemap ≤ 5 000 articles.
- Dedupe: view 1 per IP key per article per 1 800 s; reaction 1 per IP key per article per 86 400 s; cache keys
  `article_view:{id}:{ip_key}`, `article_react:{id}:{ip_key}`; IPv6 keyed by /64.
- Beacons: `authentication_classes = []`, `parser_classes = [JSONParser]`, never publicly cacheable; feature off
  or article not public → 404; closed site → 403 `{"code": "site.closed"}`.
- Counters only via `filter(pk=…).update(x=F("x") + 1)`; admin saves use `update_fields` excluding counters.
- Status: draft / scheduled / published from `is_published` and `publish_on` vs `academy_today()` (B8b).
- D2: generated JSON-LD only, through `escapeLd`.
- Coverage: backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.

## Review Focus

1. A curl loop on the view or react beacon from one IP — counted once per window (Task 3).
2. An admin saving an article while visitors react — the reaction count survives and `updated_at` is unchanged by
   reactions (Task 2 / Task 3).
3. A form POST from another site to `/react/` — refused (415) (Task 3).
4. `?page=abc`, `?page=0`, `?page=99999` on the public list — the academy 404, never a 500 (Tasks 3, 5).
5. An article title containing `</script>` — JSON-LD and OG tags stay inert (Task 5).

---

### Task 1: Models, registry, resources, services core

**Files:** `backend/etqan/site/models.py`, `uploads.py` (`article_path`), `services.py`, migration (generated,
`academy_site`, `--name articles`), `backend/etqan/platform/features.py`, `backend/etqan/access/registry.py`,
tests `backend/etqan/site/tests/test_articles_models.py`, `backend/etqan/access/tests/test_registry.py`.

**Produces:** `ArticleCategory`, `Article` (fields per C-1/C-3; `category` `PROTECT`); `services.article_status(article, today) -> "draft"|"scheduled"|"published"`,
`services.public_articles(today)` (queryset), `services.public_categories(today)`, `services.ip_key(ip: str) -> str`,
`MAX_CATEGORIES = 100`, `ARTICLE_BODY_MAX = 50_000`.

- [x] Tests: status around midnight in Africa/Cairo (patch `services.now`); `public_articles` excludes draft,
  scheduled, other academies; `public_categories` only those with a public article, ordered `order, id`;
  `ip_key("203.0.113.9") == "203.0.113.9"`, `ip_key("2001:db8:1:2:3:4:5:6") == ip_key("2001:db8:1:2:ffff::1")`
  (same /64), different /64 differs, garbage → `"unknown"`; registry/resources per Global Constraints;
  `PROTECT` raises `ProtectedError` on deleting a used category.

```python
import ipaddress


def ip_key(ip: str) -> str:
    """C-10: the dedupe key for a client address; IPv6 by its /64."""
    try:
        addr = ipaddress.ip_address((ip or "").strip())
    except ValueError:
        return "unknown"
    if addr.version == 6:
        return str(ipaddress.ip_network(f"{addr}/64", strict=False).network_address) + "/64"
    return str(addr)
```

- [x] Implement, generate the migration, run site/platform/access, lint, boundaries; commit
  `feat(site): article and article-category models; articles feature and resources`.

### Task 2: Admin API

**Files:** `admin_serializers.py`, `admin_views.py`, `api/urls.py`, `backend/etqan/access/tests/test_routes.py`;
test `backend/etqan/site/tests/test_admin_articles.py`.

- [x] Categories CRUD `/api/v1/site/admin/article-categories/` (unpaginated, cap 100, slug unique, delete in use
  → `ConflictError` "This category has N articles; move or delete them first." → 409). Articles CRUD
  `/api/v1/site/admin/articles/` (`pagination_class = StandardPagination` with `page_size = 25`; filters
  `?status=draft|scheduled|published`, `?category=<id>`; read-only `status`, `views`, `reactions`,
  `created_at`, `updated_at`; body sanitised with `clean_html`, empty after sanitising refused, ≤ 50 000; cover
  via `images.clean_image`; `cover_clear=true` removes it; replacing/clearing/deleting deletes the old file;
  saves via `save(update_fields=[editable…, "updated_at"])`). `[HasCode, FeatureOn]`, `feature="articles"`,
  `viewset_codes("article")` / `("article_category")`. Route table: append ROUTES, FEATURES, FEATURE_WORDS
  (`"/site/admin/articles/"` and `"/site/admin/article-categories/"` → `articles`).
- [x] Tests: CRUD and validation for both; 409 on in-use delete; filters; pagination envelope; cover lifecycle
  (`default_storage.exists`); **counter safety** — load an article, increment `reactions` with `F()` in between,
  PATCH the title → reactions keep the increment; staff without codes 403, feature off 404.
- [x] Commit `feat(site): admin articles and categories`.

### Task 3: Public API and beacons

**Files:** `backend/etqan/site/api/views.py`, `serializers.py`, `api/urls.py`, `services.py`
(`count_view`, `react`), `backend/etqan/platform/pagination.py` (new `PublicPagination`: `page_size = 12`,
`page_size_query_param = None`, response `{count, page, pages, results}`); test
`backend/etqan/site/tests/test_public_articles.py`.

**Produces:** `GET /api/v1/site/articles/?category=&page=`, `GET /api/v1/site/articles/<slug>/`,
`GET /api/v1/site/article-categories/`, `GET /api/v1/site/articles/sitemap/`,
`POST /api/v1/site/articles/<slug>/view/` (204), `POST /api/v1/site/articles/<slug>/react/`
(`{counted, reactions}`); site payload `has_articles`. Shapes exactly as spec §4.1.

```python
from django.core.cache import cache
from django.db.models import F

VIEW_WINDOW = 1_800
REACT_WINDOW = 86_400


def count_view(article, ip: str) -> None:
    if cache.add(f"article_view:{article.id}:{ip_key(ip)}", 1, VIEW_WINDOW):
        Article.objects.filter(pk=article.pk).update(views=F("views") + 1)


def react(article, ip: str) -> tuple[bool, int]:
    counted = cache.add(f"article_react:{article.id}:{ip_key(ip)}", 1, REACT_WINDOW)
    if counted:
        Article.objects.filter(pk=article.pk).update(reactions=F("reactions") + 1)
    return counted, Article.objects.values_list("reactions", flat=True).get(pk=article.pk)
```

  Beacon views: `authentication_classes = []`, `permission_classes = [AllowAny]`, `parser_classes = [JSONParser]`,
  client IP from DRF's `SimpleRateThrottle().get_ident(request)` pattern (respects `NUM_PROXIES`) — put a small
  `client_ip(request)` helper in `etqan/site/throttling.py`; closed → 403 `site.closed`; feature off / not public
  → 404. Public GETs extend `PublicView`; unknown/empty `?category` → 404; page out of range → 404.
- [x] Tests: shapes; feature off/closed/draft/scheduled; pagination (12, envelope, page past end 404,
  `page_size` ignored); category 404; sitemap shape/cap/order; views and reactions counted once per window per IP
  key, again from another IP, IPv6 same /64 once; form-encoded POST → 415; closed → 403; `updated_at` unchanged
  by counting; `has_articles` true/false.
- [x] Commit `feat(site): public articles API, view and reaction beacons`.

### Task 4: Seeds

**Files:** `services.py` (seed helpers `seed_article_category`, `seed_article`, validated via `full_clean`,
allow-listed fields, dev-only docstrings), `backend/etqan/tenants/seeds/b8.py`; tests.

- [x] Demo: categories `tajweed` ("التجويد" / "Tajweed", 📖) and `study-tips` ("نصائح الدراسة" / "Study tips",
  💡); articles `learning-tajweed-at-home` (− 7 days), `five-study-habits` (− 1 day), `ramadan-schedule`
  (+ 30 days, moved forward on each seed); short bilingual summaries and `<p>` bodies; covers generated (Pillow
  1200×675 in the primary colour) only when missing. Idempotent by slug; `other` untouched.
- [x] Commit `feat(site): demo articles`.

### Task 5: Marketing

**Files:** `marketing/src/lib/site.ts` (`has_articles ??= false`), new `src/lib/articles.ts` (typed fetchers
`getArticles(host, {category, page})`, `getArticle(host, slug)`, `getArticleCategories(host)`,
`getArticleSitemap(host)` returning `{kind: "ok"|"notfound"|"unavailable"}` like `getPage`),
`src/layouts/Layout.astro` (props `ogType`, `image`, `keywords`, `article`), pages
`src/pages/[lang]/articles/index.astro`, `src/pages/[lang]/articles/c/[category].astro`,
`src/pages/[lang]/articles/[slug].astro`, components `ArticleCard.astro`, `Pager.astro`, `Helpful.astro`
(button + inline script posting JSON to `/api/v1/site/articles/<slug>/react/`, `localStorage` pressed state;
view beacon posted on load), `Header.astro` (link), `sitemap.xml.ts`, `i18n.ts`; tests `marketing/test/articles.test.ts`.

- [x] Tests: list/category/detail in both languages; `?page` validation (`abc`, `0`, `99999` → 404 in layout);
  `noindex,follow` on page ≥ 2; OG `article` tags, cover/share fallback, keywords fallback; JSON-LD Article
  fields with a `</script>` title escaped; the inline script posts JSON (`Content-Type: application/json`) and is
  absent when JS-off markup is checked (button hidden by default, shown by the script); header link only with
  `has_articles`; sitemap adds index, categories, articles with `<lastmod>`, and B8b's redirect filter drops a
  redirected article URL; missing `has_articles` → false; backend 404 → academy 404.
- [x] Commit `feat: articles on the public site`.

### Task 6: Dashboard

**Files:** `dashboard/src/features/website/{api.ts,queries.ts,schemas.ts,index.ts}`, `ArticlesManager.tsx`,
`ArticleEditor.tsx`, `ArticleCategoriesManager.tsx` (+ tests), routes `website.articles.tsx`,
`website.articles_.categories.tsx` (sibling route), `features/shell/nav.ts` (`WEBSITE_TABS` + Articles with
`feature: "articles"`), `features/identity/schemas.ts` (`FeatureCode` += `"articles"`), `routes/permissions.test.ts`
(FEATURE_SCREENS + FEATURE_WORDS), locales `website.json`, `routeTree.gen.ts` (generated).

- [x] Tests: list with pager (25), status and category filters, status badge; editor create/edit with both
  languages (rich text body via `RichTextEditor`), SEO section with counters read-only, cover upload and clear
  (multipart only when a file is sent), slug-change hint shown when the slug of a saved article is edited;
  categories CRUD and the 409 message on delete; gating by code and feature (tab, route `staticData`, index).
- [x] Commit `feat(website): articles and categories`.

### Task 7: e2e

**Files:** `dashboard/e2e/b8-articles.spec.ts`.

- [x] Demo admin creates category `b8c-<stamp>` and article `b8c-<stamp>` (`publish_on` = yesterday, published);
  poll (≤ 90 s) `/en/articles/b8c-<stamp>` shows the title; press Helpful once → `{counted: true}`; reload shows
  the count; `afterAll` (fresh context, API by id, article before category, plus a sweep of `b8c-` slugs).
  Run `just e2e b8-articles` then the full `just e2e`. Commit `test(e2e): B8c articles`.

### Task 8: Slice wrap-up

- [x] Gates one at a time; final whole-slice review; fix wave; `queue B8c`.
