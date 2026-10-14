# Employment contracts

The `etqan.employment` app stores teachers' employment contracts. It does not handle hiring, job
applications or staff records; it holds only contracts. Each contract belongs to one teacher and has an
optional reference, optional plain-text details and an optional private file. It must have at least one
of details or file. Admins, and staff holding `contract.*` codes, manage every contract. A teacher can
only read and download their own contracts. Students and parents get 403. The whole feature sits behind
the `contracts` switch.

## Concepts

| Model | Fields | Notes |
|---|---|---|
| `Contract` (`etqan/employment/models.py`) | `teacher` (FK User, `PROTECT`), `reference` (≤ 60), `details` (text), `file`, `file_name`, `created_by`, timestamps | DB check `employment_contract_details_or_file`. A teacher can have any number of contracts. Ordered newest first. |

- The file is stored on the **private** storage alias (`storages["private"]`). The path is
  `tenants/<schema>/employment/<uuid><ext>` (`platform.uploads.tenant_upload_path`). The original name
  is kept in `file_name`, cut to 255 characters with the extension kept.
- A file is never given a URL. The only way to it is the authenticated `file/` endpoint.

## How it works

- `services.py:contracts_for(user)`: office users see every contract, a teacher sees only their own, and
  everyone else sees none. Anything out of scope returns 404.
- `services.py:create_contract`:
  - The teacher must have a teacher profile (400 on `teacher`).
  - Text is stripped.
  - An optional file is checked by `platform.uploads.check_upload`. Allowed types are PNG, JPEG, WEBP, PDF
    and DOCX, up to `uploads.CONTRACT_MAX` = 10 MiB.
- `services.py:update_contract`: a partial update. A new `file` replaces the old one, and
  `remove_file=true` clears it. The "details or file" rule is checked on the result of the change, so
  removing the file while details are empty is a 400 on `non_field_errors`.
- `services.py:delete_contract`: deletes the row.
- When a file is replaced or a contract deleted, the old stored file is removed only after the
  transaction commits (`transaction.on_commit`, robust). If a request rolls back after storing a file, an
  unreferenced orphan object is left behind. This is accepted.
- File download (`ContractFileView`) streams the file as an attachment with `Cache-Control: private,
  no-store` and `X-Content-Type-Options: nosniff`.

## API

Mounted at `/api/v1/contracts/` (`config/api_router.py` → `etqan/employment/api/urls.py`). Every view
uses `[HasCode | (ReadOnly & IsTeacher), FeatureOn]` with feature `contracts`.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/contracts/` | `contract.view_any`, or a teacher (own) | List. Supports `q` (reference or teacher name) and `teacher` (office only; a teacher's filter is ignored). |
| POST | `/api/v1/contracts/` | `contract.create` | Create (multipart or JSON: `teacher`, `reference`, `details`, `file`) |
| GET | `/api/v1/contracts/<id>/` | `contract.view`, or the owning teacher | One contract (`has_file`, `file_name`; never a URL) |
| PATCH | `/api/v1/contracts/<id>/` | `contract.update` | Partial update; `remove_file=true` clears the file |
| DELETE | `/api/v1/contracts/<id>/` | `contract.delete` | Delete (the file is removed after commit) |
| GET | `/api/v1/contracts/<id>/file/` | `contract.view`, or the owning teacher | Download the file |

## Dashboard

Feature folder: `dashboard/src/features/employment/`. Strings are in `locales/<lng>/contracts.json`.

| Where | Who | Component |
|---|---|---|
| `/people/contracts` (`routes/_authed/people.contracts.tsx`), optional `?teacher=` | `contract.view_any`; `contracts` | `ContractsList`, `ContractDialog` (create and edit with upload) |
| Teacher profile `/people/teachers/$personId` | office | A "Contracts" link to `/people/contracts?teacher=<id>` |
| `/account` (`routes/_authed/account.tsx`) | teacher | `MyContractsCard`: read-only list with download |

Staff also need `teacher.view_any` to fill the teacher picker. Without it, `ContractsList` hides the
create button.

## Background jobs

None.

## Configuration

- Feature switch `contracts` (group "people", built, off by default; `etqan/platform/features.py`).
- Access resource `contract`, with verbs `view`, `view_any`, `create`, `update` and `delete`
  (`etqan/access/registry.py`).
- Private storage:
  - In development and tests it is a `FileSystemStorage` at `DJANGO_PRIVATE_MEDIA_ROOT` (default
    `backend/etqan/private_media/`).
  - In production it is the S3 bucket `DJANGO_S3_PRIVATE_BUCKET`.
  - If `DJANGO_S3_PRIVATE_BUCKET` is unset, it falls back to the default bucket under an unlisted
    `private/` prefix, and the system check `etqan.W901` warns (`etqan/platform/checks.py`,
    `config/settings/production.py`).
- Demo data: `etqan/tenants/seeds/b9.py`.

## Code map

- `backend/etqan/employment/models.py`: `Contract`, `private_storage`, `employment_path`.
- `backend/etqan/employment/services.py`: scoping, create, update and delete, file handling.
- `backend/etqan/employment/api/`: views, serializers, URLs.
- `backend/etqan/platform/uploads.py`: upload checks and `CONTRACT_MAX`.
- `dashboard/src/features/employment/`: `ContractsList`, `ContractDialog`, `MyContractsCard`, `api.ts`,
  `queries.ts`, `schemas.ts`.

## Design history

- [Phase B9 — Platform extras](../superpowers/specs/2026-10-03-platform-extras-design.md), slice B9a,
  rows A-9…A-12: contracts, private files, visibility and the switch. API at §"contracts/". Dashboard
  pages are described there too.
- [Parity roadmap](../superpowers/specs/2026-09-24-parity-roadmap-design.md): B9 lists "employment
  contracts" (PEOPLE-006).
- Plan: [plan 18 — platform](../superpowers/plans/2026-10-03-plan-18-platform.md) (B9a).
