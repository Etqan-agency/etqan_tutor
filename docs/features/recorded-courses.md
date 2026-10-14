# Recorded courses

An academy sells pre-recorded video courses. TutorHamster calls them "playlists" and so does the code. The office
(admins and staff with the right codes) builds a course from videos and enrols students by hand: paid manually or free.
Students and parents buy a course in the in-app store (free courses, or a Stripe/PayPal checkout) or redeem an
activation code. A student watches lessons and ticks them off, comments under a lesson, and leaves one review per
course. If the course offers a certificate, the student gets one on completion. Visitors browse the catalogue on the
marketing site. Everything sits behind the per-academy feature `recorded_courses`, which is off by default.

## Concepts

| Model (`etqan.recorded.models`) | What it is |
|---|---|
| `Playlist` | The course. Unique `slug` and `code`, `content_language` (ar/en/ur/tr/fr/es), `price_minor`, `discount_minor` (DB check: discount ≤ price), `currency`, `terms`, a public `thumbnail` and `intro_video`, and flags: `is_published`, `certificate` (accredited certificate), `app_only` (never sold in the store). |
| `PlaylistVideo` | A lesson in a playlist, ordered by `position`. Its `kind` is `link` (https URL; YouTube/Vimeo detected into `embed_provider`/`embed_id`), `live` (URL) or `file` (private .mp4). `status`: draft/published/hidden. `downloadable` is allowed only on `file` (DB check). |
| `Enrolment` | A student's access to a playlist. Its `method` is manual/free/stripe/paypal/code, and its `status` is active or revoked. At most one active enrolment per (playlist, student) (partial unique index). Holds `amount_minor`, `currency`, `transaction_number`, an optional FK to `billing.Payment`, and `accepted_terms_at`. |
| `WatchedVideo` | (enrolment, video) pairs; they drive progress. |
| `Purchase` | A checkout's reference: a price snapshot (`amount_minor` > 0, `currency`) and the student it is for. Status pending, paid or cancelled. Once paid, it points at its enrolment. |
| `Comment` | A lesson discussion, one level deep (a reply to a reply is attached to the top comment). Has `by_office` and `hidden`. |
| `Review` | One per (playlist, student). `rating` is 1–5. It stays pending until the office approves or rejects it. |

The app stores no certificate or code rows of its own. A certificate is a learning subject certificate tagged
`source="recorded.enrolment"`, and a code is a `vouchers` voucher of kind `playlist`.

## How it works

**Office catalogue.** `services/playlists.py` (`create_playlist`, `update_playlist`, `delete_playlist`) and
`services/videos.py` (`create_video`, `update_video`, `move_video`, `delete_video`). A playlist cannot be deleted
once it has enrolments, purchases or voucher batches (409 `recorded.playlist_in_use`): unpublish it instead. Deleting
a playlist or video removes its files after commit (`signals.py`).

**What is on sale.** A playlist is on sale when `is_published` is set and `app_only` is not
(`services/store.py:is_for_sale`). The net price is `price_minor - discount_minor` (`net_price`). Only students and
parents can buy. A parent buys for their own child, passing `student_id`. Staff get 403
(`store.py:buyer_student_id`).

**Free path.** `services/purchases.py:enrol_free` takes a course whose net price is 0. The buyer must accept the terms.
It writes an enrolment with method `free` and no billing record.

**Paid path.**
1. `purchases.py:start_purchase`. The buyer must accept the terms. Under a lock on the playlist, it reuses a pending
   `Purchase` with the same price or cancels it and creates a new one. Then it calls
   `gateways.services.start_checkout("recorded_course", purchase.pk, provider)` outside any transaction (the buy view
   is non-atomic).
2. Gateways calls back through the registered purpose, `services/purpose.py`. `prepare` re-checks: the switch is on,
   the purchase is pending and the caller is the buyer (else 404); the course is still for sale, the student is not
   already enrolled, and the price has not changed (else 409).
3. `purpose.py:complete` locks the playlist, then the purchase. In one inner block it calls
   `billing.services.record_link_payment`, then `enrolments.enrol_from_sale`, then marks the purchase paid. Duplicate
   transactions, an already-paid purchase, a currency mismatch or an existing enrolment record nothing and return a
   reason. The office refunds by hand. A course unpublished after payment still enrols.

**Office enrolment.** `services/enrolments.py:enrol_by_office` takes method `manual` or `free`. A manual enrolment
writes `billing.services.create_record` in the same transaction. The view also requires `payment.create` (or the
admin role) for manual. `revoke` and `restore` are idempotent; restore refuses if another active enrolment exists.
`delete_enrolment` is allowed only for manual/free enrolments with no watch history. It revokes the certificate. The
billing payment stays.

**Access.** `services/scope.py:can_watch` lets in a student with an active enrolment in a published playlist, for a
published video. A parent can see a child's lessons (`parent_sees`) but gets 403 on the file and the watched toggle.
`services/serving.py:serve_video` handles lesson files in one of two ways. With a dedicated private bucket, it returns
a 302 to a signed URL (600 s). Otherwise (local storage, or `PRIVATE_STORAGE_SHARED_WITH_PUBLIC`), it streams the file
with single-range support. Responses are `Cache-Control: private, no-store`.

**Progress and certificates.** Progress counts published videos only (`services/progress.py`).
`services/watching.py:set_watched` locks the enrolment and, on the transition to complete, calls
`certificates.py:issue_if_complete`. That issues a certificate only when the playlist has `certificate` set, the
`certificates` feature is on, and the student is active. Office tick/untick goes through
`certificates.py:set_certificate` (PATCH `certificate_obtained` on an enrolment).

**Activation codes.** `services/codes.py:register` (called in `RecordedConfig.ready`) registers the `playlist` voucher
kind with `vouchers`. On redemption, `redeem` enrols with method `code`, amount 0, and the code shown as the
transaction number. A code is never revenue.

**Comments and reviews.** `services/comments.py`: a student with watch access posts and replies; the office replies,
hides or deletes. A hidden top-level comment hides its whole thread from other students. `services/reviews.py`:
`save_my_review` creates or edits a review, and every edit goes back to pending. `ratings_for` / `rating_of` average
approved reviews only. The store and the public detail show the latest approved reviews.

## API

All paths are under `/api/v1/recorded/`. "Office" means `HasCode` with the listed code; every route also needs
`recorded_courses` on.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `public/playlists/` | anyone (throttle `recorded_public`) | On-sale catalogue (≤100, newest first, with outline and rating) |
| GET | `public/playlists/<slug>/` | anyone | One course with its latest reviews |
| GET | `store/`, `store/<id>/` | student, parent (`?student=`) | Storefront with net price, enrolled flag, rating |
| GET | `store/<id>/providers/` | student, parent | Payment providers available (404 if `online_payments` is off) |
| POST | `store/<id>/enrol/` | student, parent; not impersonating | Free enrolment `{accept_terms, student_id?}` |
| POST | `store/<id>/buy/` | student, parent; not impersonating (throttle `gateway_start`) | Start a checkout `{provider, accept_terms, student_id?}`; 404 if `online_payments` is off |
| GET | `my/`, `my/<id>/` | student, parent | My enrolled courses / one course with videos and watched set |
| PUT/DELETE | `my/videos/<id>/watched/` | student (a parent gets 403) | Mark / unmark watched |
| GET/POST | `my/videos/<id>/comments/` | student (throttle `recorded_comment`) | Read threads / post |
| DELETE | `my/comments/<id>/` | student | Delete own comment |
| POST | `my/comments/<id>/replies/` | student | Reply in own thread |
| GET/PUT/DELETE | `my/<id>/review/` | student (throttle `recorded_review`) | My review |
| GET/POST | `playlists/` | office `playlist.view_any` / `playlist.create` | List (filters) / create (multipart) |
| GET/PATCH/DELETE | `playlists/<id>/` | office `playlist.view/update/delete` | One playlist |
| GET/POST | `playlists/<id>/videos/` | office `playlist_video.view_any/create` | Videos |
| PATCH/DELETE | `videos/<id>/` | office `playlist_video.update/delete` | One video |
| POST | `videos/<id>/move/` | office `playlist_video.reorder` | Move up/down |
| GET | `videos/<id>/file/` | office `playlist_video.view_any`, or an enrolled student | Stream or redirect to the lesson file |
| GET/POST | `playlists/<id>/enrolments/` | office `rc_enrolment.view_any/create` | List / enrol by hand |
| GET/PATCH/DELETE | `enrolments/<id>/` | office `rc_enrolment.view/update/delete` | Edit notes, watched ids, `certificate_obtained` |
| POST | `enrolments/<id>/revoke/`, `…/restore/` | office `rc_enrolment.update` | Revoke / restore |
| GET | `videos/<id>/comments/` | office `rc_comment.view_any` | Threads incl. hidden |
| POST | `comments/<id>/replies/` | office `rc_comment.create` | Office reply |
| PATCH/DELETE | `comments/<id>/` | office `rc_comment.update/delete` | Hide/unhide, delete |
| GET | `playlists/<id>/reviews/` | office `rc_review.view_any` | Reviews by status |
| PATCH | `reviews/<id>/` | office `rc_review.update` | Approve / reject with reason |

Codes are generated and redeemed through the vouchers API (kind `playlist`), not here.

## Dashboard

| Route | Who | Component (`dashboard/src/features/recorded/`) |
|---|---|---|
| `routes/_authed/catalogue.recorded.index.tsx` → `/catalogue/recorded` | office (`playlist.view_any`) | `PlaylistsAdmin` |
| `routes/_authed/catalogue.recorded.$playlistId.tsx` | office | `PlaylistPage`: tabs `VideosTab`, `EnrolmentsTab`, `CommentsTab`, `ReviewsTab` |
| `routes/_authed/learning.recorded.index.tsx` → `/learning/recorded` | student, parent | `MyCourses` |
| `routes/_authed/learning.recorded.$playlistId.tsx` | student, parent (`?student=`) | `CoursePlayer` (`VideoPane`, `Discussion`) |
| `routes/_authed/learning.recorded.store.index.tsx` | student, parent | `Store` |
| `routes/_authed/learning.recorded.store.$playlistId.tsx` | student, parent | `StoreDetailPage` / `BuyPanel` |

Code generation and redemption UI is in `dashboard/src/features/vouchers/` (`GenerateCodesDialog`, `RedeemCodePage`).
Certificates are shown by `dashboard/src/features/certificates/`.

**Marketing site.** `marketing/src/pages/[lang]/recorded-courses/index.astro` and `[slug].astro`, fed by
`marketing/src/lib/recorded.ts`. "Buy" links to `/app/learning/recorded/store/<id>`.

## Background jobs

None.

## Configuration

- Features (`etqan/platform/features.py`): `recorded_courses` (off by default). Buying also needs `online_payments`.
  Certificates need `certificates`. Codes need the vouchers feature (the B7 spec names `system_codes`).
- `RECORDED_VIDEO_MAX_MB` (default 100): the maximum lesson file size (`recorded/files.py:video_max`). Intro videos
  are capped at 100 MB and thumbnails at 2 MB.
- `PRIVATE_STORAGE_SHARED_WITH_PUBLIC` (`config/settings/base.py`) decides signed URL vs streamed file.
- Throttles in `DEFAULT_THROTTLE_RATES`: `recorded_public` 60/min, `recorded_comment` 60/h, `recorded_review` 10/h.
- Payments go through `etqan.gateways` (Stripe/PayPal) under the purpose `recorded_course`.

## Code map

- `backend/etqan/recorded/models.py`: all models.
- `backend/etqan/recorded/services/__init__.py`: the public API other apps may import.
- `backend/etqan/recorded/services/{store,purchases,purpose}.py`: selling.
- `backend/etqan/recorded/services/{enrolments,scope,watching,progress,serving}.py`: access and watching.
- `backend/etqan/recorded/services/{certificates,codes}.py`: learning certificates and the voucher kind.
- `backend/etqan/recorded/services/{comments,reviews}.py`: feedback.
- `backend/etqan/recorded/api/urls.py` (mounted at `recorded/` in `backend/config/api_router.py`).
- `backend/etqan/recorded/embeds.py`, `files.py`, `signals.py`.
- `backend/etqan/tenants/seeds/b7.py`: demo data.
- `dashboard/src/features/recorded/`, `marketing/src/lib/recorded.ts`.

## Design history

- [B7 add-on sales](../superpowers/specs/2026-10-08-b7-add-on-sales-design.md): the phase spec. Its §5–§12 are slice B7a (catalogue, enrolment, watching). Plan: [plan 49](../superpowers/plans/2026-10-08-plan-49-recorded-courses.md).
- [B7b selling recorded courses](../superpowers/specs/2026-10-08-b7b-selling-recorded-courses-design.md): store, purchase, public catalogue. Plan: [plan 51](../superpowers/plans/2026-10-08-plan-51-selling-recorded-courses.md).
- [B7e comments and reviews](../superpowers/specs/2026-10-08-b7e-recorded-comments-reviews-design.md). Plan: [plan 52](../superpowers/plans/2026-10-08-plan-52-recorded-comments-reviews.md).
- [B7g certificates and codes](../superpowers/specs/2026-10-08-b7g-recorded-certificates-codes-design.md). Plan: [plan 59](../superpowers/plans/2026-10-08-plan-59-recorded-certificates-codes.md). Its fallback "B7g builds its own certificate" did not happen: learning's certificates are used.
