# Plan 30 — Page builder (B8e) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** B8a, B8b, B8c, B8d (merged)

**Goal:** Site pages can be composed from typed blocks (heading, text, image, video, button, testimonials, FAQs,
divider) in a structured editor, stored as validated JSON and rendered from fixed Astro templates — behind
`page_builder`, off by default.

**Architecture:** `SitePage.layout` + `SitePage.blocks` (JSON) and a page-owned `PageImage`. One backend module
`etqan/site/blocks.py` validates and normalises the block array (client-assigned ids, DRF nested errors) and resolves
references in bulk for the public payload. Astro gets a `PageBlocks` component; the dashboard page editor gains a
layout switch and a block list editor with up/down/duplicate/delete.

**Tech Stack:** Django 5 + DRF + django-tenants (pytest), Astro 6 SSR (vitest), React + TanStack (vitest), Playwright.

**Spec:** `docs/superpowers/specs/2026-10-05-b8e-page-builder-design.md` (binding: E-1…E-15).

## Global Constraints

- Branch `feat/b8e-page-builder` in meta, `backend/`, `dashboard/`, `marketing/`. No `git submodule` writes, no
  `git stash`, no `git commit -a` in meta, no force-push. Manage/pytest/e2e only through the stream stack.
- Feature under `# ── phase B8 ──`: `page_builder` ("Page builder" / "منشئ الصفحات"), `_built(..., default=False)`,
  group `content`. No new access resource (pages and images use `site.*`).
- Block types exactly: `heading`, `text`, `image`, `video`, `button`, `testimonials`, `faqs`, `divider`. Flat list.
- Limits: ≤ 40 blocks; `len(json.dumps(blocks))` ≤ 200 000 checked before sanitising; heading ≤ 160; rich text
  ≤ 8 000 per language after sanitising; alt/caption ≤ 200; button label ≤ 60; testimonials limit 1–12 (default 6);
  faqs limit 1–20 (default 10); ≤ 40 images per page; image PNG/JPEG/WebP ≤ 2 MB via `etqan.site.images.clean_image`.
- Block id `^[0-9a-f]{32}$`, client-assigned, unique per page, never rewritten.
- Errors: `{"blocks": {"<id>": {"<field>": ["msg"]}}}` per block; `{"blocks": ["msg"]}` for the array.
- Button internal targets exactly `home`, `faq`, `articles`, `videos`, `contact`, `page:<slug>`; external via
  `etqan.site.redirects.clean_target`.
- Feature off: `layout=blocks` pages hidden (page 404, not in `pages`, not in sitemap); admin refuses switching to
  blocks or writing `blocks`; page-image routes 404.
- D2: no academy HTML outside the Plan 2 `nh3` allow-list; fixed templates; `escapeLd`; `safeTarget`, `playable()`,
  `UPLOAD_RE` on render.
- Coverage: backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.

## Review Focus

1. A save with a new block whose id the client did not send, or a duplicate id — refused with an array-level error (Task 1).
2. `page_builder` switched off with a published blocks page — public 404, gone from menu and sitemap, stored blocks kept (Tasks 2, 3).
3. A button with `javascript:` / `//evil.com` / own-host URL / `page:` of a draft — refused on save, nothing rendered if it slips through (Tasks 1, 4).
4. 40 text blocks of 8 000 characters each — refused by the size cap before `nh3` runs (Task 1).
5. Deleting an image a block uses (via the dashboard) — the save that drops the block deletes the file; the page payload never points at a missing file (Tasks 2, 3).

---

### Task 1: Model fields, `PageImage`, block validation module, feature

**Files:** `backend/etqan/site/models.py` (`SitePage.layout`, `SitePage.blocks`, `body_ar/en` → `blank=True`;
`PageImage(page FK CASCADE, image upload_to=uploads.page_image_path, created_at)`), `uploads.py`
(`page_image_path = upload_to("pages")`), new `backend/etqan/site/blocks.py`, migration (`academy_site`,
`--name page_builder`), `features.py`, `platform/tests/test_features.py` (BUILT in registry order); tests
`test_blocks.py`, `test_page_builder_models.py`.

**Produces:** `blocks.validate_blocks(raw, *, page, today) -> list[dict]` raising `rest_framework.serializers.ValidationError`
with the spec's shapes; `blocks.BLOCK_TYPES`; `blocks.INTERNAL_TARGETS = ("home", "faq", "articles", "videos", "contact")`;
`blocks.referenced_image_ids(blocks) -> set[int]`, `blocks.referenced_video_ids(blocks) -> set[int]`.

```python
"""B8e: the page builder's blocks — validated and normalised on save (E-2…E-5).
Every text is plain or passes the Plan 2 allow-list; targets go through
clean_target; nothing here ever stores raw HTML outside clean_html."""

import json
import re

from rest_framework import serializers

ID_RE = re.compile(r"^[0-9a-f]{32}$")
BLOCK_TYPES = ("heading", "text", "image", "video", "button", "testimonials", "faqs", "divider")
INTERNAL_TARGETS = ("home", "faq", "articles", "videos", "contact")
MAX_BLOCKS = 40
MAX_JSON = 200_000
TEXT_MAX = 8_000
# field sets per type: every other key is an error (no silent drop)
FIELDS = {
    "heading": {"id", "type", "level", "text_ar", "text_en"},
    "text": {"id", "type", "html_ar", "html_en"},
    "image": {"id", "type", "image", "alt_ar", "alt_en", "caption_ar", "caption_en"},
    "video": {"id", "type", "video"},
    "button": {"id", "type", "label_ar", "label_en", "target", "style"},
    "testimonials": {"id", "type", "limit"},
    "faqs": {"id", "type", "limit"},
    "divider": {"id", "type"},
}


def validate_blocks(raw, *, page, today):
    if not isinstance(raw, list):
        raise serializers.ValidationError({"blocks": ["Send a list of blocks."]})
    if len(json.dumps(raw, ensure_ascii=False)) > MAX_JSON:
        raise serializers.ValidationError({"blocks": ["This page is too large."]})
    if len(raw) > MAX_BLOCKS:
        raise serializers.ValidationError({"blocks": [f"Use at most {MAX_BLOCKS} blocks."]})
    ids = [b.get("id") if isinstance(b, dict) else None for b in raw]
    if any(not isinstance(i, str) or not ID_RE.fullmatch(i) for i in ids):
        raise serializers.ValidationError({"blocks": ["Every block needs an id."]})
    if len(set(ids)) != len(ids):
        raise serializers.ValidationError({"blocks": ["Block ids must be unique."]})
    errors, cleaned = {}, []
    for block in raw:
        try:
            cleaned.append(_clean(block, page=page, today=today))
        except serializers.ValidationError as exc:
            errors[block["id"]] = exc.detail
    if errors:
        raise serializers.ValidationError({"blocks": errors})
    return cleaned
```

  `_clean(block, *, page, today)` validates one block by type and returns a normalised dict (only allowed keys):
  heading (level 2|3, both texts required ≤ 160, stripped); text (`clean_html` each language, both non-empty after
  sanitising, ≤ 8 000); image (`image` an id of a `PageImage` of this page; alt both ≤ 200; captions optional ≤ 200);
  video (`video` id of a **published** `Video` and `features.enabled("video_library")`); button (labels both ≤ 60;
  `target` either one of `INTERNAL_TARGETS`, `page:<slug>` of a published `SitePage` other than this one, or an
  external URL through `clean_target(raw, own_hosts)` with own hosts from `connection.tenant.domains`; `style`
  `primary`/`secondary`); testimonials/faqs (`limit` int in range, default); divider (no fields). Errors raised as
  `serializers.ValidationError({"field": ["msg"]})`.

- [ ] Tests (`test_blocks.py`): each type valid/invalid; unknown type; unknown field; missing/invalid/duplicate id;
  > 40 blocks; size cap triggers before sanitising (patch `clean_html` to assert it is not called); rich text with
  `<script>` sanitised and empty-after-sanitise refused; button targets (each internal, `page:` published/draft/self,
  `javascript:`, `//evil.com`, own-host URL, a good https URL stored as `clean_target` output); video published vs
  draft vs feature off; image of another page refused; error shape exact. Model tests: migration additive,
  `PageImage` cascade, BUILT order, feature registry.
- [ ] Commit `feat(site): page builder blocks, page images and the page_builder feature`.

### Task 2: Admin API

**Files:** `admin_serializers.py` (`PageAdminSerializer`), `admin_views.py`, `api/urls.py`,
`access/tests/test_routes.py`; tests `test_admin_page_builder.py`.

- [ ] `PageAdminSerializer`: `layout`, `blocks` (validated by `validate_blocks`), `body_ar/en` required only when
  `layout=rich`, `blocks` non-empty when `layout=blocks`; while `page_builder` is off: refuse switching to `blocks`
  and any `blocks` write, accept `layout` unchanged; after a successful save delete this page's `PageImage`s that no
  block references (with files); response echoes `video_details: {<id>: {id, title_ar, title_en}}` and
  `needs_page_builder: bool` (blocks page while the feature is off).
- [ ] `PageImageViewSet` at `/api/v1/site/admin/pages/<page_pk>/images/` (list, create multipart via `clean_image`,
  destroy with file deletion), `[HasCode, FeatureOn]`, `feature="page_builder"`, codes `site.view_any`/`site.create`/
  `site.delete`; cap 40 per page; 404 for another page's image. Page destroy deletes its images' files.
- [ ] B8d `used_by` on videos also lists `pages: [ids]` (pages whose blocks reference the video).
- [ ] Route table rows (ROUTES, FEATURES, FEATURE_WORDS `"/images/": "page_builder"` — check the substring does not
  collide with any existing route; if it does, use `"/site/admin/pages/"` with a narrower word).
- [ ] Tests for every rule above. Commit `feat(site): admin page builder and page images`.

### Task 3: Public API and payload

**Files:** `views.py` (`PageView`, `SiteView` pages list, sitemap source), `serializers.py`, `blocks.py`
(`resolve_blocks(request, blocks, *, lang_hrefs) -> list[dict]`); tests `test_public_page_builder.py`.

- [ ] `GET /api/v1/site/pages/<slug>/` gains `layout`, `blocks` (resolved in bulk: one query each for images,
  videos, testimonials, faqs, pages): image → `{id, type, url (absolute), alt, caption}`; video → `{id, type, video:
  B8d summary | null}` (null when unpublished/feature off); button → `{id, type, label, style, href: {ar, en}}`
  (internal targets resolved per language: `home` → `/<lang>/`, `faq` → `/<lang>/faq`, `articles` →
  `/<lang>/articles`, `videos` → `/<lang>/videos`, `contact` → `/<lang>/#contact`, `page:<slug>` → `/<lang>/p/<slug>`;
  external → the URL in both); testimonials → `{items}` through B8d's `testimonial_payload` (published, limit,
  neutral media values); faqs → `{items}` (active, limit; `[]` while `faqs` off); heading/text/divider as stored with
  `{ar, en}` pairs. A blocks page sends `body_html: {ar: "", en: ""}`.
- [ ] Feature off: a blocks page 404s and is excluded from the site payload's `pages`; the sitemap (which reads
  `pages`) therefore drops it.
- [ ] Tests: shapes; query count fixed regardless of block count; feature off hiding; references that no longer
  resolve; isolation. Commit `feat(site): page builder in the public page payload`.

### Task 4: Marketing

**Files:** `marketing/src/lib/site.ts` (`PagePayload` gains `layout`, `blocks`; guards: missing → rich; per-block
guard drops malformed/unknown blocks), `src/components/PageBlocks.astro` (+ one small component per block type),
`Testimonials.astro` and the FAQ list accept an `items` prop, `src/pages/[lang]/p/[slug].astro`; tests
`test/page-builder.test.ts`.

- [ ] Templates: heading `<h2>`/`<h3>` text (escaped); text via `set:html` of the backend-sanitised HTML only;
  image `<img>` only when `url` matches `UPLOAD_RE` (`absoluteUrl`), alt/caption escaped; video through
  `playable()`; button `<a>` only when the `href` for the page language passes `safeTarget()`, external links get
  `rel="noopener noreferrer nofollow"`, style class from a fixed map; testimonials/faqs reuse the existing
  components with `items`; divider `<hr>`. Unknown types render nothing.
- [ ] Tests: each template in both languages, hostile values (script in heading, `javascript:` href, bad image URL,
  bad YouTube id) render nothing harmful, malformed blocks dropped, missing `layout` → rich, empty body for blocks.
  Commit `feat: page builder blocks on the public site`.

### Task 5: Dashboard

**Files:** `features/website/{api,queries,schemas}.ts`, `PageEditor.tsx` (layout switch while `page_builder`),
new `BlockListEditor.tsx` + per-type block forms, `PagesList.tsx` ("Needs Page builder" badge), page-image upload,
`FeatureCode` += `"page_builder"`, locales `website.json`.

- [ ] Block ids generated client-side (`crypto.randomUUID().replaceAll("-", "")`), including duplicates. Add-block
  menu, Move up/Move down/Duplicate/Delete per card, per-block server errors from `{blocks: {id: {field: [...]}}}`
  shown on the card, array errors at the top. Image block: upload to `pages/<id>/images/` (only after the page exists
  — new pages save first), pick from the page's images. Video block offered only while `video_library` and
  `can("video.view_any")`; otherwise a read-only echo from `video_details`. Button: internal target select + external
  URL input. "Open public page" link for published pages.
- [ ] Tests for each behaviour, gating and the badge. Commit `feat(website): page builder editor`.

### Task 6: Seeds and e2e

**Files:** `backend/etqan/site/services.py` (`seed_block_page`, dev-only, validated through `validate_blocks`),
`backend/etqan/tenants/seeds/b8.py`; `dashboard/e2e/b8-page-builder.spec.ts`.

- [ ] Seed `about-us` (published, in menu): heading, text, image (generated PNG only when the page has none), button
  `faq`, testimonials block. Idempotent. Tests.
- [ ] e2e (demo): create page `b8e-<stamp>` with `show_in_menu` off, layout Blocks, add heading / text / button
  (internal `faq`), publish; poll `/en/p/b8e-<stamp>` and assert the three in order and the button href `/en/faq`;
  `afterAll` deletes by id plus a `b8e-` sweep; use `gotoApp` after login. Check no existing spec counts header menu
  links. `just e2e b8-page-builder`, then full `just e2e` on a fresh stack. Commit `test(e2e): B8e page builder`.

### Task 7: Slice wrap-up

- [ ] Gates one at a time on a fresh stack; final whole-slice review; fix wave; `queue B8e`.
