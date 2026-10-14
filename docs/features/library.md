# File library

The file library is an academy-wide list of files that the office uploads to get a **public URL**, for
example to paste into an article, a page or a message. Staff upload a file and copy its link. Files
cannot be edited: to change one, delete it and upload again. It is office-only (admins, and staff holding
`library_file.*` codes) and sits behind the `file_uploads` switch. It is a separate thing from the
**private** learning files (homework, content, certificates): library files are deliberately public. See
[Private files](private-files.md) for the contrast.

## Concepts

| Model | Key fields | Notes |
|---|---|---|
| `library.LibraryFile` | `name` (≤ 120), `file`, `size`, `content_type`, `uploaded_by` (SET_NULL), `created_at` | Ordered newest first. Stored on the **default** (public) storage at `tenants/<schema>/library/<uuid><ext>`. The original name is kept only in `name`. |

## How it works

`etqan/library/services.py`:
- `upload(name, file, by)`:
  - It checks the file with `platform.uploads.check_upload`, matching the extension and the content.
  - Accepted kinds (`KINDS`): images (PNG/JPEG/WEBP/GIF), PDF, Office (DOCX/XLSX/PPTX), text (TXT/CSV),
    audio (MP3/M4A) and video (MP4).
  - Maximum size: `uploads.LIBRARY_MAX` = 20 MiB.
  - PNG, JPEG and WEBP images are re-encoded, which strips their metadata.
  - The content type is set on the stored object so S3 serves it correctly.
  - A blank name falls back to the original file name, cut to 120 characters.
- `delete_files(ids)` deletes the rows and then removes each stored file after commit, with one robust
  callback per path. It returns how many it deleted. Ids that are not found are ignored.
- The API returns `url` as an absolute media URL (`request.build_absolute_uri(file.url)`):
  - Locally it is served under `/media/`, which Caddy routes to Django.
  - In production it is the public S3 object.
- Turning `file_uploads` off hides the library and its API. Links already pasted keep working, because
  the files are not deleted.

## API

All routes use `[HasCode, FeatureOn]` with the `file_uploads` switch.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/library/?q=` | `library_file.view_any` | Paginated list, searched by name |
| POST | `/api/v1/library/` (multipart `{name, file}`) | `library_file.create` | Upload; returns the row with `url` |
| DELETE | `/api/v1/library/<id>/` | `library_file.delete` | Delete one |
| POST | `/api/v1/library/bulk-delete/` | `library_file.delete_any` | `{ids}` (1–100); returns `{deleted}` |

## Dashboard

- Route: `dashboard/src/routes/_authed/library.tsx` (`/app/library`). It is gated by `requireOffice`,
  the `library_file.view_any` code and the `file_uploads` feature.
- Nav: an office item in the **Settings** group, under the B9 marker (`features/shell/nav.ts`).
- Feature folder: `dashboard/src/features/library/`.
  - `LibraryList`: search, columns, copy URL, single and bulk delete.
  - `UploadDialog`.
- Locale area: `library.json`.

## Background jobs

None.

## Configuration

- Switch: `file_uploads` (group `content`, built, off by default).
- Access resource: `library_file` (`view_any`, `create`, `delete`, `delete_any`), under the B9 marker.
- Storage: `STORAGES["default"]`.
  - Locally this is the file system under `MEDIA_ROOT`.
  - In production it is S3 (`DJANGO_S3_BUCKET`, a public-read bucket, `querystring_auth=False`,
    `file_overwrite=False`). See `backend/config/settings/production.py`.
- Demo data: `etqan/tenants/seeds/b9.py` seeds two library files.

## Code map

- `backend/etqan/library/models.py`: `LibraryFile`, `library_path`.
- `backend/etqan/library/services.py`: `upload`, `delete_files`.
- `backend/etqan/library/api/views.py`, `serializers.py`, `urls.py`.
- `backend/etqan/platform/uploads.py`: shared type and size checks (`LIBRARY_MAX`, `check_upload`,
  `tenant_upload_path`).
- `dashboard/src/features/library/`.

## Design history

- [B9 platform extras spec](../superpowers/specs/2026-10-03-platform-extras-design.md), rows A-4 (the
  library), A-6 (storage and cleanup after commit) and A-8 (switch and access).
- [Plan 18: B9a platform](../superpowers/plans/2026-10-03-plan-18-platform.md).
