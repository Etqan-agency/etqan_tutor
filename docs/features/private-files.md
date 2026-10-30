---
title: "Private files"
---

Some uploaded files must never be reachable by URL. These are homework files and answers, teaching
content, certificate template images and student photos, employment contracts, chat attachments and
recorded-course videos. All of them go to a second storage alias, `STORAGES["private"]`. Each is handed
out only by an authenticated endpoint that applies the owning app's scoping. `backend/etqan/private_media/`
is that storage's **local directory**, not a Django app. This page describes the shared mechanism and how
learning uses it. The other apps' own pages cover their endpoints.

## Concepts

| Piece | Where | What |
|---|---|---|
| Storage alias `private` | `backend/config/settings/base.py` | Local: `FileSystemStorage` at `PRIVATE_MEDIA_ROOT` (env `DJANGO_PRIVATE_MEDIA_ROOT`, default `etqan/private_media`) with `base_url=None`, so it has no URL. It is outside `MEDIA_ROOT`, so neither Django's `/media/` nor Caddy serves it. |
| Production override | `backend/config/settings/production.py` | S3 with `querystring_auth=True` and no custom domain. The bucket is `DJANGO_S3_PRIVATE_BUCKET`, or, when that is unset, the public bucket under a `private/` prefix. |
| `PRIVATE_STORAGE_SHARED_WITH_PUBLIC` | settings | True when no private bucket is set. The system check `etqan.W901` (`etqan/platform/checks.py`) then warns. |
| Path | `etqan/platform/uploads.py:tenant_upload_path(folder)` | `tenants/<schema>/<folder>/<uuid><ext>`. The original name is never in the path; each model keeps it in a `*_name` column. |
| Upload check | `etqan/platform/uploads.py:check_upload` | Whitelist by extension, a size cap, and a content sniff. PNG/JPEG/WEBP are re-encoded from pixels, which strips EXIF, GPS and other metadata. HTML and SVG are never accepted. |

Local layout: `etqan/private_media/tenants/<schema>/{homework,content,certificates,chat,employment,…}/`.
The directory is git-ignored. Test runs leave folders for their test schemas in it.

## How it works (learning)

`etqan/learning/files.py` is learning's wrapper:
- `private_storage()` returns `storages["private"]`. It is used as a callable `storage=` on every
  learning `FileField`, so the alias is resolved at runtime, not at import.
- Upload paths:
  - `homework_path` and `content_path`.
  - `certificate_path` (folder `certificates`). Its `__module__` and `__name__` are pinned so that
    migrations import it by a stable path.
- Allowed types and size caps:

  | Use | Allowed types | Max size |
  |---|---|---|
  | Homework | `HOMEWORK_TYPES`: PDF, PNG/JPEG/WEBP, Office, TXT, MP3/M4A | 10 MiB (`uploads.CONTRACT_MAX`) |
  | Content | `CONTENT_TYPES`: the homework types plus MP4 | 20 MiB (`uploads.LIBRARY_MAX`) |
  | Certificate template | `IMAGE_TYPES` | 5 MiB (`TEMPLATE_MAX`) |
  | Certificate photo | `IMAGE_TYPES` | 2 MiB (`PHOTO_MAX`) |

- `attach(field_file, upload, extensions, max_bytes, field)` checks the upload and stores it on the field
  without saving the row. It returns the original name (bounded to 255 characters, keeping the extension)
  and the old stored name.
- `remove_after_commit(name)` deletes the old object with `transaction.on_commit(..., robust=True)`, so a
  rolled-back edit never loses the file it still points to. A rolled-back *upload* can leave an orphan
  object. That is accepted.
- `etqan/learning/signals.py` uses `post_delete` receivers on `EducationalContent`, `CertificateTemplate`
  and `Certificate` to remove their files. This also covers cascades, such as a course delete removing
  its content. Homework deletes remove both of their files in the service.
- `new_code()` makes the 22-character URL-safe certificate verification code.

Serving (`etqan/learning/api/params.py:_stream`):
- Every file route first loads the row through the scoped service (`get_homework`, `get_content`,
  `get_certificate`, …). A row the caller may not read is 404.
- The view returns a `FileResponse` as an attachment with the stored original name.
- The content type comes from the extension (`uploads.content_type_for`).
- Headers: `X-Content-Type-Options: nosniff` and `Cache-Control: private, no-store`.
- An empty field is 404.
- The dashboard fetches these as blobs (download links, certificate print images). It never builds a
  public URL.

Other apps use the same alias with their own copy of this pattern:
- `etqan/employment` (contracts; see [Employment](employment.md)).
- `etqan/chat` (see [Chat](chat.md)).
- `etqan/recorded`, whose `serve_video` redirects to a short-lived signed S3 URL when a dedicated private
  bucket exists, and otherwise streams byte ranges (see [Recorded courses](recorded-courses.md)).

## API

There are no routes of its own. The learning file routes are:

| Method | Path | Who |
|---|---|---|
| GET | `/api/v1/learning/homework/<id>/file/`, `/answer-file/` | Readers of the homework |
| GET | `/api/v1/learning/content/<id>/file/` | Readers of the content item |
| GET | `/api/v1/learning/certificate-templates/<id>/image/` | Office (`certificate_template.view_any`) |
| GET | `/api/v1/learning/certificates/<id>/photo/`, `/background/` | Readers of the certificate |

## Configuration

| Env var | Effect |
|---|---|
| `DJANGO_PRIVATE_MEDIA_ROOT` | The local directory for the private storage (dev, and any non-S3 deploy). |
| `DJANGO_S3_PRIVATE_BUCKET` | Production: a dedicated bucket with no public policy. If it is unset, files go to `DJANGO_S3_BUCKET/private/…` and `etqan.W901` warns. |
| `DJANGO_S3_BUCKET`, `DJANGO_S3_ENDPOINT_URL`, `DJANGO_S3_REGION` | Shared S3 options. The private alias copies them and drops the custom domain. |

## Code map

- `backend/config/settings/base.py` (`PRIVATE_MEDIA_ROOT`, `STORAGES["private"]`) and `production.py`.
- `backend/etqan/platform/uploads.py`, `backend/etqan/platform/checks.py`.
- `backend/etqan/learning/files.py`, `signals.py`, `api/params.py`.
- `backend/etqan/private_media/`: the local data directory, git-ignored.

## Design history

- [B9 platform extras spec](../superpowers/specs/2026-10-03-platform-extras-design.md), A-10: the private
  storage was introduced for contracts.
- [B6 phase spec](../superpowers/specs/2026-10-05-b6-learning-design.md), B6-7: all learning files are
  private. The slice specs B6b (H-7, H-8) and B6d (T-1, T-2, T-6) set the types and limits.
