# B8 — Marketing extras — Phase design

**Date:** 2026-10-03
**Status:** Approved by the phase orchestrator after an independent spec review (orchestration PO-3).
**Amends:** `2026-09-23-academy-sites-design.md` §1.2 non-goals — removes "drag-and-drop page builder" and
"blog/articles" (now B8e and B8c), per the roadmap's B8 row (TH audit §7 Option B, roadmap R1/R3).
**Phase:** B8 of `2026-09-24-parity-roadmap-design.md` (CNT-001…010). Depends on Plan 2 only.

**Builds on:**
- `2026-09-23-academy-sites-design.md` (Plan 2) — the `etqan.site` app, the public payload, the Astro
  site in `marketing/`, the dashboard's Website area.
- `2026-09-30-feature-toggles-design.md` (Plan 13) — every B8 feature is a registry switch, off by default.
- `2026-09-28-roles-permissions-design.md` (Plan 12a) — the `site` and `inquiry` resources.
- `2026-10-02-parallel-orchestration-design.md` — the rules this phase is built under.

**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` §4.12 (CNT-001…009), §7.2, §16.2–16.3, BR-38;
`docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §1.3 #14, §2.9, §5.10. TutorHamster's public site is
disabled on the demo (audit P1 §20.6), so everything visitor-facing is designed, not observed, and is
marked `[assumed]` (orchestration PO-2).

## 1. Goal

An academy's public site reaches TutorHamster's content surface: it can be put in maintenance, beta or
"system only" mode, carry the academy's own tracking/ads code, link every social network TutorHamster
lists, and publish FAQs, advertisements, redirects, articles, a video library, audio/video testimonials
and pages composed from blocks in a structured editor (B8e E-1: not a free-form visual builder, per D2). Every new behaviour or screen is a feature Etqan switches on per
academy (M-10).

## 2. Phase decisions

| # | Decision | Source |
|---|---|---|
| M-1 | B8 extends the existing `etqan.site` app (owned by B8, ledger §4.3) rather than creating new apps: every entity is site content, read by the same public payload and edited in the same Website area. | spec 2026-10-02 §4.3; spec 2026-09-23 S1 |
| M-2 | Five slices, each mergeable alone and each leaving the product deployable (§3). | roadmap R5 |
| M-3 | No slice requires another phase's slice. AI generation of articles/SEO (CNT-001 "AI") is B10's; B8 leaves the fields AI would fill as plain inputs. | roadmap §2 (B10 depends on B6, not B8) |
| M-4 | Every new public text keeps Plan 2's rule: `_ar` and `_en`, both required when the field is required. | spec 2026-09-23 S3 |
| M-5 | New features use the registry's existing lines where TutorHamster has a flag (`articles`, `url_redirects`), flipped in place to built and **off by default**; the rest are new lines under `── phase B8 ──`, off by default. Built-in demo seeding turns every built feature on for `demo` (Plan 13 §7), so e2e sees them. | spec 2026-09-30 §3, §7; PO-5 |
| M-6 | Rich text everywhere uses Plan 2's `nh3` allow-list; new rich-text fields add nothing to it except where a slice says so. | spec 2026-09-23 §3.7 |
| M-7 | Visitor-facing behaviour TutorHamster never showed (its public site is disabled) follows Plan 2's Astro conventions: `/ar/…` and `/en/…`, canonical host, sitemap, `noindex` on non-content pages. | audit P1 §20.6; spec 2026-09-23 §2.4, §5.3 |
| M-8 | Uploaded media follows Plan 2 §3.8 (academy-prefixed storage path, Pillow re-encode for images). Amended by B8d D-1: video uploads are capped at 20 MB through Django (gunicorn 3 workers / 120 s, Caddy streams bodies); larger videos are YouTube links. No direct-to-storage upload path. | spec 2026-09-23 §3.8; B8d D-1 |
| M-9 | **Closed sites stay closed.** While the effective site status (B8a) is `maintenance` or `system_only`, every public B8 endpoint, page and sitemap entry (FAQs, ads, redirects, articles, videos, …) answers as B8a A-5 does: no content in payloads, 404 on detail endpoints, nothing in the sitemap. Each slice tests it. | P1 audit §16.2 ("site settings must be live"); B8a A-5 |
| M-10 | **What needs a switch.** A new behaviour, entity or screen is a registry feature, off by default. New optional fields on an already-built area (including a new tab of the Website area that holds only such fields) that are empty by default, so no academy sees a change until it fills them, need none. | PO-5 |

## 3. Slices

| Slice | Topic | Audit IDs | Features (registry) | Requires |
|---|---|---|---|---|
| **B8a** | Site settings depth: site status modes, analytics/ads/verification IDs (TH's custom header and ads code), extra social networks, footer text, SEO keywords | CNT-009, CNT-010 | `site_status`, `site_tracking` (new) | — |
| **B8b** | FAQs, advertisements, URL redirects | CNT-004, CNT-007, CNT-008 | `faqs`, `advertisements` (new); `url_redirects` (flip) | — |
| **B8c** | Articles and article categories, on the public site and sitemap | CNT-001, CNT-002 | `articles` (flip) | — |
| **B8d** | Media: video library, audio/video testimonials, intro video | CNT-003, CNT-005, CNT-009 (intro video) | `video_library`, `testimonial_media` (new) | — |
| **B8e** | Page builder for site pages | CNT-006 | `page_builder` (new) | — |

Order: B8a → B8b → B8c → B8d → B8e (smallest and most self-contained first; the page builder, the only
L-sized piece, last). Each slice gets its own spec (`2026-10-03-b8a-…` onwards) with its own decisions
table, written when the slice starts.

### 3.1 What each slice leaves for later

- The **packages-page blurb** (CNT-009 Content tab) has nowhere to appear until the public packages
  section is rendered; it is not built in B8 and is listed for whichever plan renders that section. [assumed]
- **View and reaction counts** on articles (CNT-001) and videos (CNT-003): B8c and B8d design them;
  visitor reactions without accounts need abuse limits, decided there.
- **Discount advertisements** (CNT-007 type "discount"): B8b keeps the type as a label and banner style;
  linking an advert to B3's discount codes is not in B8 (B3 owns the codes).
- **Spanish** is B9's; B8 strings are ar/en.

## 4. Cross-phase effects

- None of B8's models leave `etqan.site`. No other phase's app changes.
- `RESOURCES` gains B8 resources under its marker as slices need them (B8b onward); B8a reuses `site`.
- The public payload (`GET /api/v1/site/`) only gains keys; nothing is renamed or removed, so the
  marketing site and the dashboard's branding boot keep working between slices.

## 5. Testing (every slice)

Backend tests per entity and per feature switch (off → admin routes 404 and the public payload carries the
key with a neutral value — empty list, empty string, `live`; on → present); the closed-site rule (M-9);
tenant isolation (two academies); marketing render tests from payload fixtures; dashboard unit tests;
one e2e journey per slice in `dashboard/e2e/b8-*.spec.ts` through Caddy.
