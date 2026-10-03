# Phase B9 — Platform extras — Design

**Date:** 2026-10-03
**Status:** Approved after an independent spec review (orchestration spec PO-3); review findings applied 2026-10-03.
**Phase:** B9 of `2026-09-24-parity-roadmap-design.md`: two-factor auth, Google sign-in, phone + OTP
login and reset, student self-registration with the enhanced funnel and waiting list, quick login and
quick-login links, named themes and dark mode, file library, system-status jobs, employment contracts,
Spanish (AUTH-*, LEAD-004, SYS-004…007, PEOPLE-006). Depends on B0 only.
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` (P1) and `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`
(TH). R7 is dropped (ledger D1): what the audits do not show is marked `[assumed]`.

This document is the phase spec (§1–§3: the split into slices and the decisions that hold across
them) and the first slice's spec (§4–§9: **B9a — platform**). Later slices get their own spec files,
designed against this one.

## 1. Goal

Close TutorHamster's platform and account gaps listed in TH §5.1 for every academy on etqan_tutor,
each behind its own feature switch, off by default (PO-5), so merged work stays invisible until Etqan
switches it on.

## 2. Phase decisions

| # | Decision | Source |
|---|---|---|
| B9-1 | B9 is four slices, each independently mergeable and each behind its own switches (§3). None needs another phase's slice. | roadmap §2 (B9 depends on B0 only) |
| B9-2 | Every B9 feature is registered in `etqan.platform.features`, **off by default**. The existing `_later` lines `file_uploads`, `contracts` and `registration_waitlist` are flipped in place to built-but-off; every other switch is new, under the `── phase B9 ──` marker. | spec 2026-10-02 PO-5; spec 2026-09-30 FT-2 |
| B9-3 | TutorHamster's page permissions `page.two_factor`, `page.system_status` and `page.quick_translate` become `in_use` in the slice that builds each page, flipped in place in `PAGES` (which has no phase marker) with its "never in use" comment updated. `page.themes` stays not in use (A-3). | `etqan/access/registry.py` PAGES; TH §2.10 RBAC |
| B9-4 | One sign-in for every role stays (TH has four panels; we have one dashboard). New sign-in methods apply to every role unless the audit shows them on one panel only: Google sign-in, self-registration and OTP reset are **student-side**, as in TH. | TH §2.11, §5.1 AUTH-001; P1 AUTH-006…010 |
| B9-5 | Business data a B9 slice adds lives in **new tenant apps** (`etqan.library`, `etqan.employment`, `etqan.systemstatus` in B9a). B9 owns `identity` authentication (ledger ownership `identity.auth`); a people-field change in `identity` (e.g. a `pending` student status for the waiting list) is made under a `claim`. | spec 2026-10-02 §4.3, §6.2 |
| B9-6 | Spanish arrives in B9d for the dashboard and the emails. Until then and after it, other phases add `en` and `ar` strings only; a missing `es` string falls back to English per key, and the `ar`/`en` key-equality test is unchanged. The public site (B8's `site`/`marketing`) stays `ar`/`en` in B9. | TH §1.1 (ar/en/es), §5.1 AUTH-014; `[assumed]` fallback rule; recorded as a shared decision |
| B9-7 | Real SMS delivery needs an external account: B9c builds OTP behind an `SmsBackend` interface with a console backend and a test outbox, and escalates (§8.1) for a provider account. | spec 2026-10-02 §8.1; roadmap §3 ("SMS / OTP with B9") |
| B9-8 | AI drafting of contract wording (P1 PEOPLE-006, INT-010) is B10's, not B9's. | roadmap §2 B10; TH §5.2 PEOPLE-006 note |
| B9-9 | "Phone + OTP login" in the roadmap row is read as TH has it: sign-in by **phone or email with a password** (AUTH-006, B9b) and an **OTP password reset** (AUTH-010, B9c). Passwordless OTP sign-in is not built: TH shows none. | P1 AUTH-006, AUTH-010, FLOW-012 |
| B9-10 | The student login's hidden fields (timezone, device type, IP, language: P1 AUTH-006) are B9b's: on each sign-in the user's timezone is filled if empty, and the last sign-in IP and device type are recorded. | P1 AUTH-006; TH §2.1 PEOPLE-001 "Technical" tab |
| B9-11 | Google sign-in uses a per-academy OAuth client that **Etqan staff** enter in the platform admin (integration keys are platform-level config, TH §5.1 INT). Creating Google clients is an external-account step: B9c escalates (§8.1) for the owner's Google Cloud project and builds and tests against a mocked provider. | TH §5.1 INT, AUTH-007; P1 INT-008; spec 2026-10-02 §8.1 |

## 3. Slices

| Slice | Topic | Contents | Audit IDs | Requires | Size |
|---|---|---|---|---|---|
| **B9a** | platform | Named themes (Default · Dracula · Nord · Sunset) on top of the existing light/dark mode; file library; employment contracts; system-status page with the "reconcile now" job | SYS-004, SYS-005, SYS-006, PEOPLE-006 | — | M |
| **B9b** | sign-in | Two-factor authentication (TOTP + recovery codes, `allauth.mfa`, already installed); sign-in by phone **or** email with a password; quick login (impersonation) for admins with a "return to my account" banner; quick-login links sent by email (single use, expiring) | AUTH-003, AUTH-006, AUTH-011, AUTH-012 | — | M |
| **B9c** | registration | Student self-registration (standard 3 steps and the enhanced funnel: minor ⇒ family, adult ⇒ individual, scheduling preferences, intro-call slot); waiting list (admin approval or a registration code, `registration_waitlist`); Google sign-in for students (per-academy OAuth client); OTP password reset by email, phone or student ID behind the SMS interface (B9-7) | AUTH-007…010, LEAD-004, BR-20/21, FLOW-001, FLOW-012 | — | L |
| **B9d** | languages | Spanish for the dashboard and emails (`User.Language` gains `es`); quick translate: an academy's per-language overrides of dashboard strings | AUTH-014, SYS-007 | — | M |

Order: B9a, B9b, B9c, B9d. B9d goes last so that it translates the most strings other phases have
added by then.

## 4. B9a — decisions

| # | Decision | Source |
|---|---|---|
| A-1 | **Named themes are a per-browser preference** in `localStorage` (new key `etqan-palette`, next to today's `etqan-theme` light/dark key), not an academy setting. TH's themes page is an admin page (`/admin/themes`, `page.themes`) whose scope was not observed; a per-user choice is the simpler option and lets every role pick, and the academy's identity is already its brand colours. | TH §2.10 SYS-005, P1 SYS-005; `[assumed]` per-browser scope |
| A-2 | Four themes: **Default** (light and dark, today's tokens), **Dracula** (dark only, as in TH), **Nord** and **Sunset** (light and dark). A theme replaces the neutral palette (background, surfaces, borders, muted text); the **academy's brand primary and accent colours stay in every theme**, so the academy's identity survives a theme change. While Dracula is chosen the page renders dark and the light option is disabled, but the stored light/dark value is left untouched, so choosing another theme restores it. No "system" mode is added (today's toggle is light/dark only). | TH §2.10 SYS-005 ("Dracula (no light mode)"); `[assumed]` brand colours kept |
| A-3 | Themes are under the switch `themes` (new, group `platform`, off). Off: only Default, exactly today's behaviour; a stored named theme is ignored, not deleted. The appearance picker is in **My account** for every role; `page.themes` gates nothing (it stays not in use: every role may choose its own look). Pages shown before sign-in (login, reset, verify) always use Default, since the academy's switches are not known there. | B9-2; FT-4 ("turning off hides, never deletes"); `[assumed]` every role |
| A-4 | **File library**: an academy-wide list of uploaded files with a public URL, for pasting into content. Fields: name\*, file\*. List: name, type, size, uploaded by, date; search by name; single and bulk delete (at most 100 ids per call, 400 above); copy URL. No edit (delete and re-upload). Turning `file_uploads` off hides the library; links already pasted keep working (FT-4: off hides, never deletes). | TH §2.10 SYS-006 (list + bulk delete; name\*, file\*); P1 SYS-006 ("CDN"); `[assumed]` columns |
| A-5 | Accepted files are exactly the table in §5.1, at most **20 MiB**. Everything else is refused, notably SVG and HTML (scriptable when served from the academy's origin) and the legacy binary Office formats. The type is checked by extension **and** content (§5.1); the stored and served content type is the table's, never the browser's or boto's guess. PNG, JPEG and WEBP are re-encoded with Pillow to strip metadata (EXIF/GPS), as Plan 2's site images are; GIF is kept as uploaded. | `[assumed]` list and size; security; spec 2026-09-23 §3.8 re-encode |
| A-6 | Library files are stored under `tenants/<schema>/library/<uuid><ext>` on the default storage (local `/media/`, production S3 public-read, `file_overwrite=False`), like branding images. The original name is kept in the record, not in the path. Whenever a stored file stops being referenced (library delete or bulk delete; contract delete, file replacement or `remove_file`) it is deleted from storage after the transaction commits (`transaction.on_commit`). | `etqan/site/uploads.py` pattern; production settings |
| A-7 | Generic upload checks (allowed extensions, size, content signature, metadata stripping) live in **`etqan.platform.uploads`**, available for reuse by later phases; B9 does not change how B8 or the `site` app handle their own media. | B9-5; recorded in the ledger as shared decision |
| A-8 | `file_uploads` flips to built, off. Access resource `library_file` ("Files" / "الملفات"), verbs in use: `view_any`, `create`, `delete`, `delete_any` (bulk). | B9-2, B9-3; TH bulk delete |
| A-9 | **Employment contracts**: a contract belongs to one teacher and has teacher\*, reference (the TH "identifier", optional, ≤ 60 chars), details (plain text, optional) and file (optional). At least one of details or file is required, checked on the **result** of the change (so a PATCH with `remove_file=true` and empty details is refused with a `non_field_errors` 400). A teacher has any number of contracts. Users are never hard-deleted (deactivation only), so `teacher` is `PROTECT`. | P1 PEOPLE-006 (teacher\*, details, file); P1 PEOPLE-005 contracts repeater (identifier, details, file); `[assumed]` "details or file" |
| A-10 | Contract files: PDF, DOCX or image (PNG, JPEG, WEBP), at most **10 MiB**, through `etqan.platform.uploads`; stored under `tenants/<schema>/employment/<uuid><ext>` with the original name kept in `file_name`. Contract files are **never public**: they are streamed by an authenticated endpoint, never given a URL. They use a separate `STORAGES["private"]` alias: in development and tests a `FileSystemStorage` at `PRIVATE_MEDIA_ROOT` (`backend/etqan/private_media/`, outside `MEDIA_ROOT`, git-ignored, on the bind-mounted source so it survives restarts); in production an S3 storage on **`DJANGO_S3_PRIVATE_BUCKET`**, a bucket with no public policy (the default bucket's public-read policy would override object ACLs). The production variable is optional so that deploys do not break: when it is unset the alias falls back to the default bucket under the unlisted `private/` prefix with uuid keys never sent to a client, and a Django system check warns (`etqan.W901`). Adding the variable to staging and production configuration is an owner/conductor action, noted in the phase notes. | security: a contract is personal data; spec 2026-10-02 PO-6, §3.1; `[assumed]` |
| A-11 | Who sees contracts: admins and staff holding `contract.*` codes see and manage all; a **teacher sees their own contracts read-only** (My account → Contracts). Permissions: `[HasCode | (ReadOnly & IsTeacher), FeatureOn]`. Students and parents get 403; a teacher reading another teacher's contract gets 404; a teacher's `?teacher=` filter is ignored. Staff creating a contract need `teacher.view_any` as well, to fill the teacher picker (the dashboard hides the create button otherwise). | v1 spec §6.1 (scoping returns 404); `[assumed]` teacher read-only |
| A-12 | `contracts` flips to built, off. Access resource `contract` ("Employment contracts" / "عقود العمل"), verbs in use: `view`, `view_any`, `create`, `update`, `delete`. | B9-2, B9-3 |
| A-13 | **System status** page for admins (`page.system_status`, now in use): app version (`ETQAN_VERSION` env, "dev" when unset), academy subdomain, academy timezone and local time, server UTC time, the number of features on, and a static list of the background jobs ("Reconcile subscriptions": hourly at minute 5; "Notifications": every minute). | TH §2.10 SYS-004 (version, licence, env panel); P1 SYS-004 |
| A-14 | Its one action is **"Reconcile subscriptions now"**: it queues the hourly lifecycle for this academy only (`scheduling.services.run_lifecycle`: pauses, expiry, generation — each step safe to repeat one after another). Each run is recorded (`JobRun`, §5). At most one run is open (queued or running) per academy, enforced by a partial unique constraint (409 otherwise); an open run older than 1 hour is marked `failed` ("timed out") before that check, so a lost task never blocks later runs. A manual run that overlaps the hourly beat run may fail on a database deadlock: that is accepted, recorded as `failed` with the error, and the admin retries (the beat run retries its own academy the next hour). The page lists the last 20 runs. | TH §2.10 SYS-004; `scheduling/services/lifecycle.py`; `[assumed]` overlap handling (B2 owns `scheduling`) | TH §2.10 SYS-004 ("manually reconcile subscriptions"); `scheduling/services/lifecycle.py` |
| A-15 | Not built from SYS-004: **clear cache** (nothing an academy can see is cached per academy), **notify teachers of the monthly evaluation** (behaviour unknown), the licence panel and the vendor support widget (vendor-only). | TH §2.10 SYS-004, §4 U8; `[assumed]` |
| A-16 | System status is under the switch `system_status` (new, group `platform`, off). | B9-2 |

## 5. B9a — data

New tenant apps, added to `TENANT_APPS` under the B9 marker, each with an import-linter contract
(they import only `etqan.platform`, and `etqan.employment` also `etqan.identity` services;
`etqan.systemstatus` also `etqan.scheduling` services):

```text
etqan.library.LibraryFile
  name          CharField(120)              required
  file          FileField(upload_to=library path)   required
  size          PositiveBigIntegerField     bytes, set on upload
  content_type  CharField(100)              from the §5.1 table
  uploaded_by   FK identity.User, SET_NULL, null
  created_at    DateTimeField(auto_now_add)
  ordering: -created_at, -id

etqan.employment.Contract
  teacher       FK identity.User, PROTECT, limit to role=teacher (checked in the service)
  reference     CharField(60), blank
  details       TextField, blank
  file          FileField(storage=storages["private"], upload_to=employment path), blank
  file_name     CharField(255), blank      original name, used as the download name
  created_by    FK identity.User, SET_NULL, null
  created_at, updated_at
  constraint: details <> '' OR file <> ''
  ordering: -created_at, -id

etqan.systemstatus.JobRun
  job           CharField(40)   choices: reconcile_subscriptions
  status        CharField(10)   queued · running · ok · failed
  result        JSONField       counts from run_lifecycle ({} until done)
  error         TextField, blank   short reason when failed
  requested_by  FK identity.User, SET_NULL, null
  requested_at, started_at (null), finished_at (null)
  constraint: unique (job) where status in (queued, running)
  ordering: -requested_at, -id
```

### 5.1 Accepted uploads

| Extension | Content type | Content check | Kind |
|---|---|---|---|
| `.png` | `image/png` | Pillow opens it as PNG; re-encoded | IMAGE |
| `.jpg`, `.jpeg` | `image/jpeg` | Pillow opens it as JPEG; re-encoded | IMAGE |
| `.webp` | `image/webp` | Pillow opens it as WEBP; re-encoded | IMAGE |
| `.gif` | `image/gif` | starts `GIF87a` or `GIF89a` | IMAGE |
| `.pdf` | `application/pdf` | starts `%PDF-` | PDF |
| `.docx` | `application/vnd.openxmlformats-officedocument.wordprocessingml.document` | starts `PK\x03\x04` | OFFICE |
| `.xlsx` | `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` | starts `PK\x03\x04` | OFFICE |
| `.pptx` | `application/vnd.openxmlformats-officedocument.presentationml.presentation` | starts `PK\x03\x04` | OFFICE |
| `.txt` | `text/plain; charset=utf-8` | valid UTF-8, no NUL byte, first non-space character is not `<` | TEXT |
| `.csv` | `text/csv; charset=utf-8` | as `.txt` | TEXT |
| `.mp3` | `audio/mpeg` | starts `ID3`, or a frame sync (`0xFF` then a byte `& 0xE0 == 0xE0`) | AUDIO |
| `.m4a` | `audio/mp4` | `ftyp` at offset 4 | AUDIO |
| `.mp4` | `video/mp4` | `ftyp` at offset 4 | VIDEO |

The library accepts every kind; contracts accept IMAGE (PNG, JPEG, WEBP only), PDF and `.docx`.
Stored objects get the table's content type (S3 `ContentType` set explicitly).

`etqan.platform.uploads`: `check_upload(file, *, kinds, max_bytes) -> CheckedUpload` (the content
type, and the file to store: the re-encoded image or the original; raises `ValidationError`), the
kinds (`IMAGE`, `PDF`, `OFFICE`, `TEXT`, `AUDIO`, `VIDEO`) built from the §5.1 table, and
`tenant_upload_path(folder)` building `tenants/<schema>/<folder>/<uuid><ext>`.

## 6. B9a — API (all under `/api/v1/`)

While a route's switch is off it answers 404 to every caller who passes its permission check
(`FeatureOn` runs after `HasCode`, spec 2026-09-30 §5.2); callers who fail the check keep their 403.

| Route | Methods | Who | Notes |
|---|---|---|---|
| `library/` | GET (search `q`, paginated), POST multipart `{name, file}` | `library_file.view_any` / `.create` | response includes `url` (absolute media URL) |
| `library/<id>/` | DELETE | `library_file.delete` | |
| `library/bulk-delete/` | POST `{ids}` (1–100) | `library_file.delete_any` | deletes those found, returns `{deleted}` |
| `contracts/` | GET (filter `teacher`, search `q` on reference and teacher name), POST multipart | `contract.view_any` / `.create`; a teacher GETs only their own | |
| `contracts/<id>/` | GET, PATCH multipart (`file` may be cleared with `remove_file=true`), DELETE | `contract.view` / `.update` / `.delete`; teacher GET own | |
| `contracts/<id>/file/` | GET | same as `contracts/<id>/` GET | streams the file with its stored content type, `Content-Disposition: attachment; filename=<file_name>`, `X-Content-Type-Options: nosniff`, `Cache-Control: private, no-store`; 404 when the contract has no file |
| `system-status/` | GET | `page.system_status` | §4 A-13 plus `runs` (last 20) |
| `system-status/runs/` | POST `{job: "reconcile_subscriptions"}` | `page.system_status` | 202 with the run; 409 if one is open |

Errors use the existing envelope. Upload validation errors are field errors on `file`.

The run (`systemstatus.run_job(schema_name, run_id)`, `soft_time_limit=3000`, `time_limit=3300`, as
`scheduling.run_daily`):

1. The POST creates the `queued` row and queues the task with `transaction.on_commit` (requests are
   atomic, `ATOMIC_REQUESTS=True`), so the worker always sees the row.
2. The task enters `academy_context(schema_name)`; an academy that is not `active` ends the run as
   `failed` ("academy suspended").
3. It commits `running` (with `started_at`) in its own transaction.
4. It takes `pg_try_advisory_xact_lock` on a key derived from the job name and runs `run_lifecycle()`
   inside `transaction.atomic()` (needed by the `select_for_update` in generation).
5. In a separate transaction after that one commits or rolls back, it records `ok` with the counts,
   or `failed` with a short error. Any exception, including a deadlock `OperationalError` and the
   soft time limit, ends as `failed`.

## 7. B9a — dashboard

- **My account → Appearance** (switch `themes`): theme cards (Default, Dracula, Nord, Sunset) next
  to the existing light/dark toggle; Dracula disables light (A-2). Themes are CSS variable sets
  selected by `data-theme` on `<html>`, defined in the dashboard (the shared `@etqan/tokens` package
  is not changed). Brand variables win because `applyBranding` sets them as inline styles on `:root`;
  the one rule it writes into a stylesheet, `:root:not(.dark){--primary-text}`, must not be beaten, so
  theme selectors set no `--primary-text` in light mode and each named theme sets its own dark-mode
  `--primary-text`. Theme colours meet WCAG AA: a unit test runs the tokens package's contrast check
  (`@etqan/tokens/contrast.mjs`, its pairs manifest) over each theme in each of its modes. The academy's
  brand primary on the named themes' surfaces is not checked (it is the academy's choice).
- **Content → Files** (`/app/library`, switch `file_uploads`, permission `library_file.view_any`):
  table with search, pagination, row delete with confirm, select + bulk delete, "copy link"; upload
  dialog (name defaults to the file name; client-side size check before sending).
- **People → Contracts** (`/app/people/contracts`, switch `contracts`, permission
  `contract.view_any`): table (teacher, reference, has file, created), teacher filter, create/edit
  dialog (teacher picker, reference, details, file), delete with confirm, download. The teacher page
  gets a "Contracts" link filtered to that teacher.
- **My account → Contracts** for a teacher (switch `contracts`): read-only list with download.
- **Settings → System status** (`/app/settings/system-status`, switch `system_status`, permission
  `page.system_status`): the facts of A-13, the "Reconcile subscriptions now" button (disabled while a
  run is open), and the runs table, refreshing every 5 s while a run is open.
- New nav entries go under the `── phase B9 ──` marker of `NAV_ITEMS`; strings in new files
  `dashboard/src/locales/{en,ar}/{library,contracts,systemStatus,appearance}.json`.

## 8. B9a — registries and seeds

- Features: `file_uploads` and `contracts` → `Feature(..., built=True, default=False)` in place;
  `themes` and `system_status` under `── phase B9 ──`.
- Access: `library_file` and `contract` under `── phase B9 ──`; `page.system_status` `in_use=True`
  in place (B9-3).
- `TENANT_APPS`, `config/api_router.py`, the import-linter forbidden list and contracts, `NAV_ITEMS`:
  B9 markers only.
- Seeds: `etqan/tenants/seeds/b9.py`, called from `seed_academy`
  (`etqan/tenants/management/commands/seed_dev.py`) under its B9 marker: two library files (real
  bytes written to the default storage) and one contract with a small PDF for the demo teacher (on
  the private storage). No switch is turned on by the seed.

## 9. B9a — testing

- Backend (pytest, coverage ≥ 80 %): upload checks (each §5.1 row accepted; SVG, HTML, a renamed
  executable, a `.txt` starting with `<`, an oversize file refused; image metadata stripped); every
  route × role (admin, staff with and without the code, teacher, student, parent, anonymous) with the
  statuses of §6 and A-11 including 404 when the switch is off; a teacher sees only their own
  contracts and gets 404 on another's; contract download headers, auth required, and the file is on
  the private storage; the system check warning; cross-academy isolation; bulk delete and its limit;
  stored files removed after commit (`django_capture_on_commit_callbacks`) on delete, replace and
  `remove_file`; JobRun: queued → running → ok, failed on an exception and on an `OperationalError`,
  suspended academy, 409 while open (constraint), stale open run marked failed, the task runs
  `run_lifecycle` in the right schema inside an atomic block; registry tests (markers, `in_use`
  equals routes).
- Dashboard (vitest, lines/statements ≥ 80, branches/functions ≥ 70): theme selection and fallback
  when the switch is off, Dracula forcing dark, theme contrast; files upload/delete/bulk; contracts
  form validation (details or file); system-status polling.
- e2e `dashboard/e2e/b9-platform.spec.ts` through Caddy, switches turned on with
  `manage.py set_features`: an admin uploads a file and opens its link; creates a contract with a file
  for a teacher; the teacher signs in and downloads it; another teacher cannot; the admin runs
  "Reconcile subscriptions now" and sees it finish; a user picks Nord and the choice survives a reload.

## 10. Non-goals (B9a)

Server-stored theme preference; per-academy default theme; editing a library file; folders or tags in
the library; image resizing or CDN invalidation; contract templates, signatures, dates or AI wording
(B10); clear cache; the monthly-evaluation notification; a log of the automatic hourly runs.
