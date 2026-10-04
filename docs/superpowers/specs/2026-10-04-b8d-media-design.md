# B8d — Media: video library, audio/video testimonials, intro video — Design

**Date:** 2026-10-04
**Status:** Approved by the phase orchestrator after an independent spec review (orchestration PO-3);
review findings 1–20 resolved in this version.
**Phase / slice:** B8 marketing extras, slice B8d (phase spec `2026-10-03-marketing-extras-design.md`).
**Requires:** B8a–B8c (closed sites, `academy_today()`, `escapeLd`, sitemap redirect filter, the B8c beacons) and
B9a (`etqan.platform.uploads`, ledger D12) — all merged.
**Amends:** phase spec M-8 ("large video goes to object storage directly"): B8d does not upload large video at all;
uploads are capped at 20 MB through Django and larger videos are YouTube links (D-1).

**Evidence:** P1 audit §4.12 CNT-003 (video library: 3 tabs — video info / SEO / publishing; title\*, description,
video file\* MP4/MOV max 5 GB, cover image\* JPG/PNG/WEBP 16:9, SEO title ≤ 60, SEO description ≤ 160, keywords,
publish toggle, view count, reaction count), CNT-005 (testimonials: student name\*, star count\* 1–5, review type\*
text / audio / video), CNT-009 (site settings: intro video), §7.2 (Video: published / unpublished; StudentReview),
BR-38; TH audit §2.9, §5.10 ("TH audio/video types not addressed"; "Intro video … NOT ADDRESSED"). The public site is
disabled on the demo, so every visitor-facing behaviour is `[assumed]` (PO-2).

## 1. Goal

The academy publishes a video library on its public site, collects audio and video testimonials beside text ones,
and can show an intro video on its home page — behind `video_library` and `testimonial_media`, off by default.

## 2. Decisions

| # | Question | Answer | Source |
|---|---|---|---|
| D-1 | How do videos get onto the platform? | Two sources: an **uploaded MP4** (≤ 20 MB — B9a's `LIBRARY_MAX` — checked by `check_upload` with `{".mp4"}`) or a **YouTube video**, stored as its validated id. TH's 5 GB / MOV uploads are out: production runs 3 gunicorn sync workers with a 120 s timeout and Caddy streams request bodies, so an upload holds a worker for its whole transfer; 20 MB stays under the timeout on a ~2 Mbit/s uplink. Larger videos go through YouTube. Vimeo and other providers are not built (no audit row needs them). | P1 CNT-003, BR-38; infra compose; review #2, #19; [assumed] |
| D-2 | YouTube ids | Stored: the id only (`^[A-Za-z0-9_-]{11}$`); the URL is never stored or echoed. Accepted input: a bare id, or an `http(s)` URL parsed with `urlsplit` whose host is exactly one of `youtube.com`, `www.youtube.com`, `m.youtube.com`, `youtu.be`, with paths `/watch?v=<id>`, `/<id>` (youtu.be), `/shorts/<id>`, `/embed/<id>`, `/live/<id>`; other query parameters ignored. Anything else → field error "Paste a YouTube link or video id." | review #11; [assumed] |
| D-3 | Rendering (D2) | Fixed templates only. YouTube: `<iframe src="https://www.youtube-nocookie.com/embed/<id>" loading="lazy" allow="fullscreen; picture-in-picture" referrerpolicy="strict-origin-when-cross-origin" title="<video title>">` — the id re-validated in Astro; the iframe runs on YouTube's origin, not the academy's. Uploaded MP4: `<video controls preload="metadata" poster="<cover>">` with `src`/`poster` accepted only as `^https?://` URLs (or the site's own `/media/` path made absolute). Unknown `source` → nothing rendered. | ledger D2; B8a A-8; review #12 |
| D-4 | Video fields | `title_ar/en` (≤ 160, required), `description_ar/en` (plain ≤ 2 000), `source` (`upload` · `youtube`), `file` (when `upload`), `external_id` (when `youtube`), `cover` (required; PNG/JPEG/WebP ≤ 2 MB, re-encoded by `etqan.site.images` like B8c's cover — not B9a's `IMAGE` set, which admits GIF unre-encoded), `slug` (`^[a-z0-9-]{1,60}$`, unique, `sitemap` reserved), `seo_title_ar/en` (≤ 60), `seo_description_ar/en` (≤ 160), `keywords_ar/en` (≤ 255), `is_published` (default false), `order` (`PositiveIntegerField`, 0), counters `views`, `reactions` (read-only), `created_at`, `updated_at`. At most 200 videos. DB check constraint: `(source='upload' AND file<>'' AND external_id='') OR (source='youtube' AND file='' AND external_id<>'')`. | P1 CNT-003, BR-38; M-4; review #6, #7 |
| D-5 | Source switch and file lifecycle | Switching away from `upload` deletes the stored file; switching to `upload` needs a file in the same request; switching away from `youtube` clears `external_id`. Replacing the file or cover, or deleting the video, deletes the old files (B8b B-4 pattern). | review #7 |
| D-6 | Public pages | `/<lang>/videos` (published; `order`, then newest; 12 per page; B8c C-12 `?page` rules and noindex on page ≥ 2 or when empty) and `/<lang>/videos/<slug>` (player, description, Helpful button). `Layout` props: `ogType="website"`, `image` = cover. Header link "Videos" / "الفيديوهات" while `has_videos` (true only when the feature is on, the site open, and ≥ 1 published video). `VideoObject` JSON-LD: `name`, `description` (falls back to the title), `thumbnailUrl` (cover), `uploadDate` (`created_at`), `contentUrl` (uploads) or `embedUrl` (YouTube nocookie URL), through `escapeLd`. | B8c pattern; review #14; [assumed] |
| D-7 | Views and reactions | B8c's beacons for videos: `POST /api/v1/site/videos/<slug>/view/` and `/react/`, same rules (explicit JSON content type, per-IP dedupe, `F()` counters, cache outage skips). The B8c services are generalised to `count_view(obj, ip)` and `react(obj, ip)` with the cache key `f"{obj._meta.model_name}_view:{obj.pk}:{ip_key}"` (articles keep today's `article_view:` keys) and the total read from `type(obj).objects` — additive for articles. | P1 CNT-003; B8c C-8–C-11; review #3 |
| D-8 | Testimonial media | Testimonial gains `kind` (`text` default · `audio` · `video`), `audio` (MP3/M4A ≤ 10 MB via `check_upload` with B9a `AUDIO`), and `video` (FK to a library `Video`, `SET_NULL`). The text quote stays required for every kind (shown beside the player) [assumed]. Save rules: `kind=audio` needs `audio`; `kind=video` needs a **published** `video` and `video_library` on; switching kind clears the other media field and deletes an old audio file. A testimonial whose video was later unpublished or deleted renders as text. A video used by a testimonial or as the intro video is published, so it also appears on `/videos` — accepted [assumed]. | P1 CNT-005; TH §5.10; review #1 |
| D-9 | Intro video | `LandingContent` gains `intro_video` (FK to a published `Video`, `SET_NULL`, optional) [assumed: a library video rather than a separate upload]. Shown between the hero and "about" while `video_library` is on and the video is published. | P1 CNT-009; [assumed] |
| D-10 | Features | `video_library` ("Video library" / "مكتبة الفيديوهات") and `testimonial_media` ("Audio and video testimonials" / "آراء صوتية ومرئية") under `── phase B8 ──`, `_built(..., default=False)`, group `content`, no `requires` (audio testimonials work without the library; video testimonials need both, D-8). Off → admin routes 404, stored data kept (FT-4). Neutral payload values: `testimonial_media` off → every testimonial `kind:"text"`, `audio_url:""`, `video:null`; `video_library` off or site closed → `has_videos:false`, `landing.intro_video:null`, testimonial `video:null`. Keys always present. | M-5, M-10; FT-4; review #8 |
| D-11 | Permissions | Resource under `── phase B8 ──`: `video` ("Videos" / "الفيديوهات"), verbs view, view_any, create, update, delete, held by grant like any code. Testimonial and landing media stay under `site.*`; their admin serializers echo the selected video as `{id, title_en, title_ar}` so an editor without `video.view_any` still sees it. | spec 2026-09-28; B8b B-14; review #1, #18 |
| D-12 | Closed site | As M-9: no videos in the payload, video pages and beacons as B8c (404 / 403 `site.closed`), `closed_landing_payload()` gains `intro_video: null`, testimonials hidden as today. | M-9; review #8 |
| D-13 | Storage and serving | Files via `etqan.site.uploads` (`upload_to("videos")`, `upload_to("audio")`, module-level names, as the site app does today), default public storage. `check_upload` pins the stored extension to `.mp4` / `.mp3` / `.m4a`; the served Content-Type comes from that extension (django-storages guesses it on S3 — the upload sets `ContentType` explicitly from `content_type_for` to be sure; dev `static.serve` uses the same mapping and SecurityMiddleware sends `nosniff`). The content check only reads leading bytes, so the safety rests on the extension-derived type plus `nosniff`, not on sniffing. Dev `/media/` does not serve byte ranges, so uploaded MP4s cannot seek locally (Safari may refuse them) — a known dev limitation; S3 serves ranges in production. | D12; review #5, #15 |
| D-14 | Dashboard | Website tab "Videos" (`video.view_any`, feature `video_library`): list (status filter, order), editor with source switch (upload / YouTube link), cover, SEO section, read-only counters; deleting a video lists what uses it (testimonials, intro video) in the confirmation. Testimonials manager: kind selector (Text always; Audio while `testimonial_media`; Video while both features are on and the user holds `video.view_any`), audio upload (the form switches to multipart via `toFormData` when a file or `audio_clear` is sent), video picker (published videos). Home page form: intro-video picker under the same conditions as the Video kind. | P1 CNT-003; review #1, #16, #17 |
| D-15 | Seeds | Demo: two YouTube videos (fixed test ids as constants), covers generated with Pillow only when missing, idempotent by slug; one video testimonial (author "B8d demo") pointing at the first. No audio testimonial (no binary in the repo) and **no intro video on demo** (it would put an external iframe on the home page every e2e loads) [assumed]. | review #9 |

## 3. Data (`etqan.site`, one additive migration)

`Video` per D-4 (+ check constraint); `Testimonial` + `kind`, `audio`, `video` (FK `SET_NULL`); `LandingContent` +
`intro_video` (FK `SET_NULL`). Ordering: videos `order, -created_at`.

## 4. Behaviour

### 4.1 Public API (shapes)

```jsonc
// video summary
{"slug": "…", "title": {…}, "description": {…}, "cover_url": "…", "source": "upload|youtube",
 "file_url": "…" /* uploads, else "" */, "external_id": "…" /* youtube, else "" */}
// GET /api/v1/site/videos/?page=n → {count, page, pages, results: [summary]}
// GET /api/v1/site/videos/<slug>/ → summary + seo_title, seo_description, keywords, reactions, created_at, updated_at
// GET /api/v1/site/videos/sitemap/ → {"videos": [{slug, updated_at}]}  (≤ 200)
// site payload: "has_videos": bool, "landing": {…, "intro_video": null | summary},
//   testimonials[i]: {…, "kind": "text|audio|video", "audio_url": "", "video": null | summary}
```

### 4.2 Admin API

CRUD `/api/v1/site/admin/videos/` (multipart; `?status=draft|published` on list only; cap 200; D-5 lifecycle;
`[HasCode, FeatureOn]`, `feature="video_library"`); testimonial admin accepts `kind`, `audio`, `audio_clear`,
`video` (id) with D-8 rules; landing admin accepts `intro_video` (id). Route-table rows appended.

### 4.3 Marketing

Pages per D-6, players per D-3, testimonials with `<audio controls preload="none">` or the player, intro video on
home, header link, sitemap entries through B8b's redirect filter, skew defaults (`has_videos ??= false`,
`intro_video ??= null`, testimonial `kind ??= "text"`). `Helpful` generalised: `data-kind` mapped through the closed
set `{articles, videos}` inside the fixed script (anything else → return), `localStorage` key
`etqan:helpful:<kind>:<slug>`.

## 5. Testing

Backend: YouTube id parsing (every accepted form, lookalike hosts, other schemes, extra params); upload checks
(content, size, stored extension); check constraint; source switch deletes/clears; cover/file lifecycle; caps;
publication, feature and closed rules incl. `landing.intro_video`; beacons for videos (incl. the empty-body 415);
a video and an article with the same id dedupe independently; testimonial kind rules (audio needs file, video
needs published library video and the feature, kind switch clears media, unpublish/delete degrades to text); intro
video rules; neutral payload values per feature; route table; isolation; seeds idempotent. Marketing: list and
detail in both languages, both player templates with hostile ids/URLs refused, JSON-LD escaping, testimonials of
each kind, intro video, header link, sitemap with redirect filtering, skew defaults, `Helpful` with `videos` and a
same-slug article keeping separate pressed state. Dashboard: video manager (source switch, cover, SEO, counters,
delete confirmation listing uses), testimonial kind/audio/video picker gating, intro-video picker gating. e2e
`b8-media.spec.ts` (demo): the admin adds a YouTube video `b8d-<stamp>` with a generated cover and publishes it;
the public video page has the nocookie iframe `src` (asserted without loading YouTube); a testimonial
`B8d e2e <stamp>` of kind video renders on the home page; the landing is never changed; `afterAll` deletes by id
plus sweeps (`b8d-` slugs, `B8d e2e` author names).

## 6. Non-goals

Uploads over 20 MB, MOV, transcoding, thumbnails from frames; Vimeo and other providers; captions; playlists
(recorded courses are B7); comments; unlisted videos; per-visitor dedupe beyond IP; byte ranges in dev.
