# Plan 19 — FAQs, advertisements, URL redirects (B8b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B8a (merged)

**Goal:** Bilingual FAQs on a public FAQ page, expiring promotional advertisements on the home page, and URL
redirects applied by the public site — three registry features, off by default.

**Architecture:** Three new models in `etqan.site` with CRUD admin viewsets gated by `[HasCode, FeatureOn]`.
The public site payload gains `faqs`, `advertisements`, `redirects` (empty while a feature is off or the site
is closed). Astro renders `/<lang>/faq` and an Offers strip, and its middleware answers redirects after the
B8a closed-site check. The dashboard gets three Website tabs.

**Tech Stack:** Django 5 + DRF + django-tenants (pytest), Astro 6 SSR (vitest + AstroContainer), React +
TanStack Router/Query + zod + react-hook-form (vitest), Playwright.

**Spec:** `docs/superpowers/specs/2026-10-03-b8b-faqs-ads-redirects-design.md` (binding; decisions B-1…B-17,
B-8a, B-8b). Phase spec `docs/superpowers/specs/2026-10-03-marketing-extras-design.md`.

## Global Constraints

- Branch `feat/b8b-faqs-ads-redirects` in meta, `backend/`, `dashboard/`, `marketing/`. Never `git submodule`
  writes, never `git stash`. Run manage/pytest/e2e only through the stream stack (`.env.stream`; see the SDD
  `context.md`).
- Features: `faqs` ("FAQs" / "الأسئلة الشائعة"), `advertisements` ("Advertisements" / "الإعلانات الترويجية")
  as `_built(..., default=False)`, group `content`, under `# ── phase B8 ──`; `url_redirects` flipped in place
  from `_later(...)` to `_built(..., default=False)` keeping label and group `platform`.
- Access resources under `# ── phase B8 ──` in `etqan/access/registry.py`: `faq` ("FAQs" / "الأسئلة الشائعة"),
  `advertisement` ("Advertisements" / "الإعلانات الترويجية"), `redirect` ("URL redirects" / "تحويل الروابط"),
  `in_use = ("view", "view_any", "create", "update", "delete")`.
- Limits: question ≤ 300; answer ≤ 10 000 (after sanitising); ≤ 100 FAQs; ad title ≤ 120, body ≤ 500, banner
  ≤ 2 MB PNG/JPEG/WebP; ≤ 20 unexpired ads; from_path ≤ 200; to ≤ 500; ≤ 500 redirects.
- Redirect statuses: `permanent` false (default) → 302 + `Cache-Control: no-store`; true → 301 +
  `Cache-Control: max-age=3600`.
- Reserved redirect paths (whole segment): `/`, `/ar`, `/en`, `/app`, `/api`, `/accounts`, `/health`,
  `/media`, `/internal`, `/_astro`, `/closed-site`, `/robots.txt`, `/sitemap.xml`, `/favicon.ico`.
- Closed site (B8a `is_closed(effective_status())`) → `faqs`, `advertisements`, `redirects` all `[]`.
- Shared decision D2: no academy-supplied script/HTML; JSON-LD escapes `<` as `<`; FAQ answers only via
  the Plan 2 `nh3` allow-list.
- Coverage: backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70; marketing per config.
- Commit messages end with `Co-Authored-By: <your model line> <noreply@anthropic.com>` after a blank line.

## Review Focus

1. An admin pastes an Arabic old URL (`/مقالات/قديم`) as `from_path` — it must match the browser's encoded
   request path (Tasks 1 and 6).
2. `to = "//evil.com"` or `"/\\evil.com"` or containing CR/LF — refused by the API, ignored by Astro (Tasks 1, 3, 6).
3. Turning an inactive redirect back on that would form a chain — refused (Task 3).
4. An ad expiring "today" in Africa/Cairo at 23:30 UTC the day before — still shown / already hidden correctly
   (Task 1).
5. A FAQ question containing `</script><script>` — the FAQ JSON-LD stays one inert script (Task 5).

---

### Task 1: Models, services, registry, resources

**Files:** `backend/etqan/site/models.py`, `backend/etqan/site/uploads.py` (`ad_path`),
`backend/etqan/site/services.py`, new `backend/etqan/site/redirects.py`, migration (generated, app label
`academy_site`), `backend/etqan/platform/features.py`, `backend/etqan/access/registry.py`; tests
`backend/etqan/site/tests/test_b8b_models.py`, `test_redirect_paths.py`.

**Produces:** models `Faq`, `Advertisement` (`Kind.GENERAL="general"`, `Kind.DISCOUNT="discount"`), `Redirect`;
`redirects.canonical_path(raw: str) -> str`, `redirects.clean_target(raw: str, own_hosts: set[str]) -> str`,
`redirects.target_path(to: str) -> str | None`, `redirects.RESERVED`; `services.academy_today() -> date`,
`services.now()`, `services.active_faqs()`, `services.active_ads(today)`, `services.active_redirects()`,
limits `MAX_FAQS=100`, `MAX_ACTIVE_ADS=20`, `MAX_REDIRECTS=500`. Raise `etqan.platform.exceptions.ValidationError(message, field=...)`.

- [ ] **Step 1: failing tests.** `test_redirect_paths.py`:

```python
import pytest

from etqan.platform.exceptions import ValidationError
from etqan.site import redirects


@pytest.mark.parametrize(
    ("raw", "canonical"),
    [
        ("/old", "/old"),
        ("/old/", "/old"),
        ("/مقالات/قديم", "/%D9%85%D9%82%D8%A7%D9%84%D8%A7%D8%AA/%D9%82%D8%AF%D9%8A%D9%85"),
        ("/a%c3%a9", "/a%C3%A9"),
        ("/blog/2020-01_x~y", "/blog/2020-01_x~y"),
        ("/a b", "/a%20b"),  # as the browser sends it
    ],
)
def test_canonical_path(raw, canonical):
    assert redirects.canonical_path(raw) == canonical


@pytest.mark.parametrize(
    "raw",
    ["old", "/a?b=1", "/a#x", "//a", "/a//b", "/a\\b", "/a/../b", "/./a", "/a%2Fb", "/a%5cb",
     "/a%00", "/", "/ar", "/en/", "/app", "/app/x", "/api/v1", "/_astro/x.css",
     "/closed-site", "/robots.txt", "/favicon.ico", "/" + "a" * 200],
)
def test_canonical_path_refuses(raw):
    with pytest.raises(ValidationError):
        redirects.canonical_path(raw)


def test_reserved_is_by_segment():
    assert redirects.canonical_path("/apple") == "/apple"


@pytest.mark.parametrize(
    ("raw", "stored"),
    [
        ("/en/faq", "/en/faq"),
        ("/en/p/x?ref=old#top", "/en/p/x?ref=old#top"),
        ("https://new.example.com/x", "https://new.example.com/x"),
        ("/ar/صفحة", "/ar/%D8%B5%D9%81%D8%AD%D8%A9"),
    ],
)
def test_clean_target(raw, stored):
    assert redirects.clean_target(raw, {"demo.etqan.localhost"}) == stored


@pytest.mark.parametrize(
    "raw",
    ["//evil.com", "/\\evil.com", "/a\r\nSet-Cookie: x=1", "javascript:alert(1)", "ftp://x.com",
     "relative", "https://demo.etqan.localhost/x", "/a b", "/" + "a" * 500],
)
def test_clean_target_refuses(raw):
    with pytest.raises(ValidationError):
        redirects.clean_target(raw, {"demo.etqan.localhost"})


@pytest.mark.parametrize(
    ("to", "path"),
    [("/b/", "/b"), ("/b?x=1#y", "/b"), ("https://other.example/b", None)],
)
def test_target_path(to, path):
    assert redirects.target_path(to) == path
```

`test_b8b_models.py`: `academy_today()` with `services.now` patched to `2026-10-31T23:30:00Z` and the academy
timezone `Africa/Cairo` (patch `etqan.academy.services.get_settings` to return an object with
`timezone="Africa/Cairo"`, or set the settings row as `billing` tests do) returns `2026-11-01`; an unknown zone
falls back to UTC; `active_ads(date(2026,11,1))` includes an ad with `expires_on=2026-11-01`, excludes
`2026-10-31`; ordering newest first; `active_faqs()` only active, by `order, id`; `active_redirects()` only
active; registry: `faqs`, `advertisements`, `url_redirects` built and off by default with the groups above;
access registry has the three resources with the five verbs in use.

- [ ] **Step 2: run, expect failures.**
- [ ] **Step 3: implement.** `redirects.py`:

```python
"""B8b B-8a/B-8b: the one canonical form of a redirect's paths, and what a
safe target is. The public site compares the browser's request path, which
is percent-encoded with uppercase hex, against `from_path` byte for byte."""

import re
from urllib.parse import quote
from urllib.parse import urlsplit

from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.validators import URLValidator

from etqan.platform.exceptions import ValidationError

RESERVED = frozenset(
    {"", "ar", "en", "app", "api", "accounts", "health", "media", "internal",
     "_astro", "closed-site", "robots.txt", "sitemap.xml", "favicon.ico"}
)
# RFC 3986 pchar plus "/", after percent-encoding: unreserved, sub-delims, ":", "@", "%XX".
_PATH = re.compile(r"^/(?:[A-Za-z0-9\-._~!$&'()*+,;=:@/]|%[0-9A-F]{2})*$")
_FORBIDDEN_ESCAPES = re.compile(r"%(2F|5C|00)")
_CONTROL = re.compile(r"[\x00-\x20\x7f\\]")
_SITE_PATH = re.compile(r"^/(?![/\\])")
_URL = URLValidator(schemes=["http", "https"])
FROM_MAX = 200
TO_MAX = 500


def _encode(raw: str) -> str:
    # Encode non-ASCII as UTF-8 and uppercase existing escapes; keep every
    # ASCII path character as typed.
    # "?" and "#" stay as typed: canonical_path refuses them first, and a
    # target keeps its own query and fragment.
    encoded = quote(raw, safe="/-._~!$&'()*+,;=:@%?#")
    return re.sub(r"%[0-9a-f]{2}", lambda m: m.group(0).upper(), encoded)


def canonical_path(raw: str) -> str:
    path = (raw or "").strip()
    if not path.startswith("/") or "?" in path or "#" in path or "\\" in path:
        raise ValidationError("Enter a path that starts with / (no ? or #).", field="from_path")
    path = _encode(path)
    if len(path) > 1 and path.endswith("/"):
        path = path[:-1]
    segments = path.split("/")[1:]
    if (
        "//" in path
        or any(s in (".", "..") for s in segments)
        or _FORBIDDEN_ESCAPES.search(path)
        or not _PATH.fullmatch(path)
    ):
        raise ValidationError("This path is not allowed.", field="from_path")
    if segments[0] in RESERVED:
        raise ValidationError("This path belongs to the site and cannot be redirected.", field="from_path")
    if len(path) > FROM_MAX:
        raise ValidationError(f"Use at most {FROM_MAX} characters.", field="from_path")
    return path


def clean_target(raw: str, own_hosts: set[str]) -> str:
    to = (raw or "").strip()
    if not to or _CONTROL.search(to):
        raise ValidationError("Enter a path or an http(s) address without spaces.", field="to")
    to = _encode(to) if to.startswith("/") else to
    if to.startswith("/"):
        if not _SITE_PATH.match(to):
            raise ValidationError("Enter a path or an http(s) address.", field="to")
    else:
        try:
            _URL(to)
        except DjangoValidationError:
            raise ValidationError("Enter a path or an http(s) address.", field="to") from None
        if not to.isascii():
            raise ValidationError("Enter the address in its encoded form.", field="to")
        host = (urlsplit(to).hostname or "").lower()
        if host in own_hosts:
            raise ValidationError("Use a path for this site.", field="to")
    if len(to) > TO_MAX:
        raise ValidationError(f"Use at most {TO_MAX} characters.", field="to")
    return to


def target_path(to: str) -> str | None:
    """The site path a target points at, canonical for loop checks; None for
    an external URL."""
    if not to.startswith("/"):
        return None
    path = urlsplit(to).path
    return path[:-1] if len(path) > 1 and path.endswith("/") else path
```

  (Adjust messages/limits only if a test disagrees; keep behaviour.) Models per spec §3
  (`Faq` ordering `["order", "id"]`; `Advertisement` ordering `["-created_at", "-id"]`, `banner =
  ImageField(upload_to=uploads.ad_path)`; `Redirect.from_path` `unique=True`, ordering `["from_path"]`).
  Services: `now()` = `timezone.now()`; `academy_today()` per `billing/clock.py` with
  `ZoneInfoNotFoundError` → UTC; `active_*` per spec. Registry/resources per Global Constraints. Generate the
  migration (`makemigrations academy_site --name faqs_ads_redirects`).
- [ ] **Step 4:** site + platform + access suites, `just lint-backend`, `just check-boundaries` green.
- [ ] **Step 5: commit** `feat(site): FAQ, advertisement and redirect models; B8b features and resources`.

### Task 2: Public payload

**Files:** `backend/etqan/site/api/serializers.py`, `backend/etqan/site/api/views.py`; test
`backend/etqan/site/tests/test_public_b8b.py`.

**Consumes:** Task 1. **Produces:** payload keys `faqs` (`[{question: Pair, answer_html: Pair}]`),
`advertisements` (`[{kind, title: Pair, body: Pair, banner_url, expires_on: "YYYY-MM-DD"}]`), `redirects`
(`[{from, to, permanent}]`).

- [ ] Tests: each key present with data when its feature is on; `[]` when off (stored rows untouched); all
  three `[]` on a closed site (`site_status` on + `maintenance`); expired ad absent; inactive FAQ/redirect
  absent; `banner_url` absolute; tenant isolation (rows in main absent from `other`).
- [ ] Implement in `SiteView.get` (reuse the `closed` flag B8a computes) with small payload builders in
  `serializers.py`. Run site + access suites; commit `feat(site): FAQs, advertisements and redirects in the site payload`.

### Task 3: Admin API

**Files:** `admin_serializers.py`, `admin_views.py`, `api/urls.py`, `backend/etqan/access/tests/test_routes.py`;
test `backend/etqan/site/tests/test_admin_b8b.py`.

**Produces:** `/api/v1/site/admin/faqs/` (`?active=1`), `/advertisements/` (multipart), `/redirects/`;
viewsets `permission_classes = [HasCode, FeatureOn]`, `permission_codes = viewset_codes("faq"|"advertisement"|"redirect")`,
`feature = "faqs"|"advertisements"|"url_redirects"`, `pagination_class = None`.

- [ ] Tests (admin client and `staff_for(...)` as in `test_admin_settings.py`):
  - FAQ: create needs all four texts; answer sanitised (`<script>` stripped); answer > 10 000 after sanitising
    → 400; 101st FAQ → 400; `?active=1` filters; ordering.
  - Ad: create needs banner (multipart PNG from Pillow), kind, both titles/bodies, expires_on; PATCH without
    banner keeps it; replacing the banner deletes the old file; DELETE deletes the file (assert storage
    `exists` false); list includes server `is_active`; 21st unexpired ad → 400 (expired ones don't count).
  - Redirect: stores canonical `from_path`; duplicate after canonicalising (`/old/` vs `/old`) → 400 on
    `from_path`; `to` refusals (Task 1 list) → 400 on `to`; same-host absolute (`http://testserver/x` — the
    request host — and the academy's primary domain) → 400; loops: `/a → /a`; chain `/a → /b` then `/b → /c`
    → 400; reverse chain `/b → /c` then `/a → /b/` → 400; inactive `/b → /c` allows `/a → /b`, but then
    PATCH `/b → /c` `is_active=true` → 400; 501st → 400.
  - Staff without codes → 403; feature off → 404 for an admin (covered by the route table too).
- [ ] Implement serializers (`FaqAdminSerializer` with `validate_answer_*` → `clean_html` + length;
  `AdvertisementAdminSerializer` reusing `FileClearMixin`-style replacement and `images.clean_image` with the
  hero limits, `is_active` read-only computed with `services.academy_today()`; `RedirectAdminSerializer`
  `validate_from_path` → `canonical_path`, `validate_to` → `clean_target(to, own_hosts)` where `own_hosts` =
  `{d.domain.lower() for d in connection.tenant.domains.all()} | {request.get_host().split(":")[0].lower()}`,
  `validate()` runs the B-10 loop checks against other **active** rows (exclude `self.instance`) only when
  the resulting row is active). Viewset `perform_destroy` for ads deletes the file. Caps in `validate()` /
  `create`. Route table: append rows for every method of the three viewsets to `ROUTES` (codes as
  `viewset_codes`), to `FEATURES`, and `FEATURE_WORDS` entries `"/site/admin/faqs/": "faqs"`,
  `"/site/admin/advertisements/": "advertisements"`, `"/site/admin/redirects/": "url_redirects"`.
- [ ] site + access suites, lint, boundaries; commit `feat(site): admin FAQs, advertisements and redirects`.

### Task 4: Seeds

**Files:** `backend/etqan/site/services.py` (seed helpers), `backend/etqan/tenants/seeds/b8.py`; tests in
`backend/etqan/site/tests/` and `backend/etqan/tenants/tests/test_seed_dev.py`.

- [ ] Seed helpers `seed_faqs(items)`, `seed_ad(*, title_en, **fields)`, `seed_redirect(*, from_path, to, permanent=False)`
  (validated through `canonical_path` / `clean_target`; allow-listed fields like B8a's `seed_site_settings`).
  `seed_b8` for demo adds: FAQs ("How do lessons work?" / "كيف تتم الدروس؟", "Can I change my teacher?" /
  "هل يمكنني تغيير المعلم؟", "How do I pay?" / "كيف أدفع؟" with short `<p>` answers), a `discount` ad "Family
  discount" / "خصم العائلات" expiring `academy_today() + 30 days`, banner generated (Pillow 1200×400 PNG in the
  primary colour) only when the ad has none, redirect `/old-faq` → `/en/faq` (302).
- [ ] Tests: idempotent twice, `other` untouched, no second banner file on re-seed. Commit
  `feat(site): demo FAQs, advertisement and redirect`.

### Task 5: Marketing — FAQ page, Offers strip, sitemap

**Files:** `marketing/src/lib/site.ts` (types + `resolveSite` defaults `[]`), `marketing/src/layouts/Layout.astro`
(`jsonLd?: object` prop), `marketing/src/pages/[lang]/faq.astro`, `marketing/src/components/Offers.astro`,
`marketing/src/components/Header.astro` (FAQ link), `marketing/src/pages/[lang]/index.astro`,
`marketing/src/pages/sitemap.xml.ts`, `marketing/src/lib/i18n.ts`, `marketing/test/fixtures.ts`; tests
`marketing/test/b8b.test.ts`.

- [ ] Tests: `/en/faq` and `/ar/faq` render each FAQ in a `<details><summary>`; FAQPage JSON-LD present and
  a question `"</script><script>alert(1)</script>"` yields no second `<script>` start inside the block (assert
  the raw HTML contains `</script>`); answers in JSON-LD have no tags; `/en/faq` is 404 (the academy's
  in-layout 404) with no FAQs; header shows "FAQ"/"الأسئلة الشائعة" only with FAQs; home shows Offers with
  the discount badge ("Discount"/"خصم") above testimonials, and nothing without ads; a payload missing the
  three keys renders; sitemap includes `/en/faq` with FAQs and drops a path that is a redirect `from`.
- [ ] Implement; strings: `faq` "FAQ"/"الأسئلة الشائعة", `faqTitle` "Frequently asked questions"/"الأسئلة
  الشائعة", `offers` "Offers"/"العروض", `discount` "Discount"/"خصم". JSON-LD: `JSON.stringify(obj).replace(/</g, "\\u003c")`.
  Run suite (`-e SITE_SCHEME=https`), `pnpm check`, `pnpm lint`; commit `feat: FAQ page, offers strip, sitemap entries`.

### Task 6: Marketing — redirects in the middleware

**Files:** `marketing/src/lib/redirects.ts`, `marketing/src/middleware.ts`; test `marketing/test/redirects.test.ts`.

**Produces:** `findRedirect(redirects, pathname) -> {to, permanent} | null`, `safeTarget(to) -> string | null`.

- [ ] Tests: `/old` and `/old/` match `from: "/old"`; encoded Arabic pathname matches the canonical stored
  form; case-sensitive; 302 + `Location` + `Cache-Control: no-store`; 301 + `max-age=3600`; `to` with query
  kept, request query dropped; unsafe `to` (`//evil.com`, `/\\evil.com`, `/a\nb`, `javascript:x`, non-ASCII)
  → no redirect, page served; closed site → closed page, no redirect; `/robots.txt` never redirected; live
  site without a match → `next()`.

```ts
const SITE_PATH = /^\/(?![\/\\])[\x21-\x7e]*$/;
const ABSOLUTE = /^https?:\/\/[\x21-\x7e]+$/i;

export function safeTarget(to: string): string | null {
	if (to.includes("\\")) return null;
	return SITE_PATH.test(to) || ABSOLUTE.test(to) ? to : null;
}

export function findRedirect(
	redirects: { from: string; to: string; permanent: boolean }[],
	pathname: string,
) {
	const path = pathname.length > 1 && pathname.endsWith("/") ? pathname.slice(0, -1) : pathname;
	const hit = redirects.find((r) => r.from === path);
	const to = hit ? safeTarget(hit.to) : null;
	return hit && to ? { to, permanent: hit.permanent } : null;
}
```

  Middleware: in the open-site branch, before `next()`, when the path is not `/robots.txt`/`/sitemap.xml`:
  `const hit = findRedirect(site.redirects, path)`; if hit → `new Response(null, {status: hit.permanent ? 301 : 302,
  headers: {Location: hit.to, "Cache-Control": hit.permanent ? "max-age=3600" : "no-store"}})`, keeping the
  nosniff/Referrer-Policy headers. Suite, check, lint; commit `feat: URL redirects`.

### Task 7: Dashboard — three Website tabs

**Files:** `dashboard/src/features/website/{api.ts,queries.ts,schemas.ts,index.ts}`, new
`FaqsManager.tsx`, `AdsManager.tsx`, `RedirectsManager.tsx` (+ tests), routes
`website.faqs.tsx`, `website.ads.tsx`, `website.redirects.tsx`, `routes/_authed/website.tsx` and
`website.index.tsx` (feature-aware), `features/shell/nav.ts` (`WEBSITE_TABS` gains optional `feature`),
`features/identity/schemas.ts` (`FeatureCode` += `faqs`, `advertisements`, `url_redirects`), locales
`website.json` en/ar, `routeTree.gen.ts` (generated).

- [ ] Tests per manager, following `TestimonialsManager.test.tsx`: list, add (dialog, both languages
  required), edit, delete with confirm, server 400 field errors shown on the field, read-only without
  update/create/delete codes. FAQ: answers via `RichTextEditor`, active filter, order field. Ads: banner file
  input (required on create, optional on edit), kind select, `expires_on` date input, "Expired"/"Active" badge
  from the server `is_active`. Redirects: from/to inputs, "Permanent (301)" checkbox with the hint "Browsers
  remember a permanent redirect for up to an hour.", active toggle. Tabs: hidden per feature and code; index
  redirects to the first tab allowed by both; routes declare `staticData: { permission, feature }`.
- [ ] Implement; strings in `website.json` (en/ar key-equal): tab names "FAQs"/"الأسئلة الشائعة",
  "Advertisements"/"الإعلانات الترويجية", "Redirects"/"تحويل الروابط", and the form labels. Full vitest with
  coverage, tsc, `pnpm exec biome ci .`; commit `feat(website): FAQs, advertisements and redirects tabs`.

### Task 8: e2e

**Files:** `dashboard/e2e/b8-faqs-ads-redirects.spec.ts`.

- [ ] Serial, demo admin via UI: create FAQ `B8b FAQ <stamp>` (both languages), ad `B8b Offer <stamp>`
  (`expires_on` today + 3 days, a generated PNG via `setInputFiles` with a buffer), redirect
  `/b8b-<stamp>` → `/en/faq` (302). Poll (≤ 90 s): `/en/faq` contains the FAQ; `/en/` contains the ad title;
  `page.request.get(B8b path, { maxRedirects: 0 })` → 302 with `location` `/en/faq`. `finally`: delete all
  three through the UI (or the admin API with the page's session), so demo is left as seeded.
- [ ] `just e2e b8-faqs-ads-redirects` green, then full `just e2e` (known families/features race excepted);
  biome; commit `test(e2e): B8b FAQs, advertisements and redirects`.

### Task 9: Slice wrap-up

- [ ] Gates one at a time (backend, dashboard, marketing, e2e); final whole-slice review; `queue B8b`.
