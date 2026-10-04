# B8e — Page builder for site pages — Design

**Date:** 2026-10-05
**Status:** Approved by the phase orchestrator after an independent spec review (orchestration PO-3);
review findings 1–17 resolved in this version.
**Phase / slice:** B8 marketing extras, slice B8e (phase spec `2026-10-03-marketing-extras-design.md`).
**Requires:** B8a–B8d (closed sites, `escapeLd`, sitemap redirect filter, FAQs, testimonials, the video library,
`playable()`, `clean_target`/`safeTarget`) — all merged by the time this slice builds. Images use the site app's own
`etqan.site.images.clean_image` (B9a's uploads are optional per D12).
**Parity divergence (recorded):** TutorHamster edits site pages in GrapesJS, a free-form drag-and-drop HTML/CSS
builder. Etqan ships a **structured block editor** instead (E-1, ledger D2). The phase spec's "pages designed in a
visual builder" is amended to "pages composed from blocks".

**Evidence:** P1 audit §4.12 CNT-006 (site pages: page name\*, page key\*, page title, meta title, meta description,
keywords; editing uses the GrapesJS drag-and-drop builder — CONFIRMED fields / PROBABLE builder binding), §2.1
(Filament plugin `dotswan/filament-grapesjs-v3`), §7.2 (SitePage + GrapesJS body), §10 INT-017 (GrapesJS, client
side), §20.6 (pages built in GrapesJS unobserved on the public site); TH audit §5.10 ("GrapesJS page builder =
NON-GOAL" in Plan 2, lifted by the phase spec). Visitor-facing behaviour is `[assumed]` (PO-2).

## 1. Goal

An academy admin composes a site page from ready-made blocks — headings, text, images, videos, buttons,
testimonials, FAQs and dividers — reorders them, and publishes; the public site renders the page in the academy's
style. Behind `page_builder`, off by default; existing rich-text pages keep working.

## 2. Decisions

| # | Question | Answer | Source |
|---|---|---|---|
| E-1 | GrapesJS or structured blocks? | **Structured blocks.** GrapesJS stores arbitrary HTML and CSS; serving it from the academy origin is what D2 forbids, and no sanitiser keeps its styling and stays safe. A page is an ordered, flat list of typed blocks stored as validated JSON and rendered by Astro from fixed templates; texts are plain or pass Plan 2's `nh3` allow-list. | D2; P1 CNT-006, INT-017; [assumed] |
| E-2 | Blocks | `heading` (level 2 or 3, text ar/en ≤ 160; the page title stays the only `<h1>`), `text` (rich text ar/en), `image` (a page image + alt ar/en ≤ 200 + optional caption ar/en ≤ 200), `video` (a published library video), `button` (label ar/en ≤ 60, target E-3, style `primary`/`secondary`), `testimonials` (limit 1–12, default 6), `faqs` (limit 1–20, default 10), `divider`. No columns, no nesting. | review #10; [assumed] |
| E-3 | Button targets | Either an **internal** target from a fixed set — `home`, `faq`, `articles`, `videos`, `contact` (home page `#contact`), or `page:<slug>` of a published site page — rendered by the template as `/${lang}/…` so it is right in both languages; or an **external** http(s) URL stored as `clean_target`'s output (B8b B-8b: own hosts refused, ASCII, no control characters). The template re-checks external targets with `safeTarget()` and renders nothing on null; external links get `rel="noopener noreferrer nofollow"` and no `target` from data. | B8b B-8b; review #8 |
| E-4 | Limits | ≤ 40 blocks; the serialized `blocks` JSON (`len(json.dumps(...))`, before sanitising) ≤ 200 000 characters, checked first so `nh3` never runs on huge input; rich text ≤ 8 000 characters per language after sanitising. | review #4; [assumed] |
| E-5 | Block ids and errors | The **client** gives every block a uuid4 hex `id` (new blocks and duplicates too). The server checks the format (`^[0-9a-f]{32}$`) and uniqueness within the page, refuses anything else, and never rewrites ids. Validation errors use DRF's nested shape: `{"blocks": {"<id>": {"<field>": ["msg"]}}}` for a block, `{"blocks": ["msg"]}` for the whole array (count, size, duplicate ids); raised as a DRF `serializers.ValidationError`. Unknown types or fields → error (no silent drop). | review #1 |
| E-6 | Storage | `SitePage` gains `layout` (`rich` default · `blocks`) and `blocks` (JSON, default `[]`). `body_ar/en` become `blank=True` and are required only when `layout=rich`; `blocks` must be non-empty when `layout=blocks`. Switching layouts keeps the other field's stored content. | spec 2026-09-23 §3.4; review #2 |
| E-7 | Page images | `PageImage(page FK → SitePage CASCADE, image, created_at)`, image re-encoded by `etqan.site.images.clean_image` (PNG/JPEG/WebP ≤ 2 MB). Uploaded with `POST /api/v1/site/admin/pages/<id>/images/` (multipart) — a page must exist first. On every page save, the page's images that no block references are deleted with their files; deleting a page deletes its images and files. ≤ 40 images per page. No shared library. | B8b B-4; review #7 |
| E-8 | Feature off | `page_builder` ("Page builder" / "منشئ الصفحات") under `── phase B8 ──`, `_built(..., default=False)`, group `content`. Off → a `layout=blocks` page is treated as unpublished: the page endpoint 404s, it is left out of the site payload's `pages` (menu) and the sitemap; stored blocks are kept (FT-4). Admin API while off: changing `layout` to `blocks`, or any write to `blocks`, is refused; `layout` sent unchanged is accepted, so editing a hidden blocks page's title/SEO still works; page-image routes 404. The dashboard lists such pages with a "Needs Page builder" badge. | M-5, M-10; FT-4; review #2, #3 |
| E-9 | Block content rules | `testimonials` shows the academy's published testimonials whatever the home page's `show_testimonials` toggle, through B8d's `testimonial_payload` (media neutral values per `testimonial_media`/`video_library`); `faqs` shows nothing while `faqs` is off; `video` shows nothing unless `video_library` is on and the video is published, rendered only through `playable()`; `image` renders only when its URL matches B8d's `UPLOAD_RE` (http(s) or `/media/`). Saving refuses a `video` block whose video is unpublished or while `video_library` is off, and a `page:<slug>` target that is not a published page. | B8b, B8d; review #9 |
| E-10 | Permissions | Pages and their images use `site.*`. The `video` block is offered only while `video_library` is on and the user holds `video.view_any` (B8d D-11); the admin serializer echoes `{id, title_ar, title_en}` for chosen videos so other editors still see the choice. B8d's delete-video confirmation (`used_by`) also lists pages whose blocks reference the video (a JSON scan; capped page count makes it cheap). | B8d D-11, D-14; review #6 |
| E-11 | Dashboard | The page editor gains a layout switch (Rich text / Blocks) while the feature is on. The block editor is a vertical list: an "Add block" menu, each block a card with its form, Move up / Move down buttons, Duplicate and Delete; per-block errors shown on the block. No drag-and-drop library, no preview pane — an "Open public page" link for published pages. | review #10 |
| E-12 | Public payload | `GET /api/v1/site/pages/<slug>/` gains `layout` and `blocks`, resolved in bulk (one query per reference kind): image blocks carry `url`/`alt`/`caption`, video blocks the B8d video summary, testimonials/faqs blocks their items, button blocks a resolved `href` for internal targets per language (`{ar, en}`) or the external URL. A blocks page sends `body_html: {ar: "", en: ""}`. | spec 2026-09-23 (page endpoint); review #5, #12 |
| E-13 | Deploy skew | Deploy the backend first. Marketing's page guard accepts a missing `layout`/`blocks` as rich, and type-guards each block, dropping malformed or unknown ones without failing the page. An older marketing reading a blocks page renders the empty `body_html` (acceptable for the deploy window). | B8a–B8d pattern; review #5 |
| E-14 | SEO | Unchanged (title, SEO description, Plan 2 `WebPage`); FAQ blocks add no `FAQPage` JSON-LD. | [assumed] |
| E-15 | Seeds | Demo: one published blocks page `about-us` (heading, text, image with a generated PNG created only when missing, button to the internal `faq` target, testimonials block), in the menu. Idempotent through a dedicated seed helper (`seed_site` takes plain pages). | review #11 |

## 3. Data

`SitePage.layout`, `SitePage.blocks` (JSON), `body_ar/en` → `blank=True`; `PageImage`. One additive migration.

## 4. Behaviour

- Admin API: `pages/` accepts `layout`, `blocks` (E-5 validation, E-8 rules); `pages/<id>/images/` (POST multipart,
  GET list, DELETE); response echoes chosen videos.
- Public API: per E-12; closed site as today.
- Marketing: `[lang]/p/[slug].astro` renders `PageBlocks` for `layout: "blocks"` (fixed templates; `Testimonials` and
  the FAQ list take an `items` prop).
- Dashboard: per E-11.

## 5. Testing

Backend: block validation per type (required fields, limits, sanitising, unknown types/fields, id format and
uniqueness, size cap before sanitising), error shape, button targets (internal set, `page:` must be published,
external through `clean_target`), video/page references, layout switch keeps content, body optional only for
blocks, feature-off hiding (page 404, menu, sitemap) and admin write refusal, page images (upload, cleanup of
unreferenced images on save with files, cascade on page delete, cap), bulk resolution query count, B8d `used_by`
includes pages, isolation, seeds idempotent. Marketing: each block template in both languages, internal hrefs per
language, external targets refused/accepted, broken references render nothing, hostile text escaped, skew defaults
and malformed blocks dropped. Dashboard: add/move/duplicate/delete, per-block errors, layout switch, video block
gating, needs-builder badge. e2e `b8-page-builder.spec.ts` (demo, which has `page_builder` on via seeding): the admin
creates page `b8e-<stamp>` with `show_in_menu=false`, adds a heading, a text and a button, publishes it, and the
public page shows them in order; `afterAll` deletes by id plus a `b8e-` sweep. Check no existing spec counts menu
links (the seeded `about-us` adds one).

## 6. Non-goals

GrapesJS or any free-form HTML/CSS; drag-and-drop; columns or nesting; per-block fonts, colours or spacing; a
preview pane; a shared image library; templates; scheduled publishing; per-page custom code; CNT-006's page key,
meta title and keywords fields (parity gap, recorded); draft preview on the public site.
