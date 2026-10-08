# Plan 39 — B6d Certificates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Certificate templates, issued certificates (four kinds, auto-filled completed-session count, private photo, revoke), a printable A4-landscape page, the course "awards certificates" toggle, and public anonymous verification by code — in `etqan.learning`, behind `certificates` and `verified_certificates` (requires `certificates`), both off by default.

**Architecture:** Three tables in `etqan.learning` (`CertificateTemplate`, `CourseCertificate`, `Certificate`), `services/certificates.py`, `api/certificate_views.py` (+ an anonymous verify view with a local throttle). Dashboard `src/features/certificates/`, a `_print` route, and a public `/verify/$code` route.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest; React + TanStack Router/Query + Vitest; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-05-b6d-certificates-design.md` (T-1…T-12). Phase spec `…-b6-learning-design.md`. Ledger D33.

**Requires:** B6a (merged); uses B6b's `etqan/learning/files.py` helpers — branch `feat/b6d-certificates` off trunk after B6b (and, by queue order, B6c) merge.

## Global Constraints

- Work from `/home/abdulkhalek/Projects/etqan_tutor-wt/b6`; `backend/`, `dashboard/` on `feat/b6d-certificates`. Never run writing `git submodule` commands; never touch `/home/abdulkhalek/Projects/etqan_tutor`.
- Run via `D=/home/abdulkhalek/.claude/jobs/0bc5cdff/tmp/dc` (pytest, ruff, lint-imports, makemigrations, dash vitest/tsc/lint); suites `just test`, `just lint`, `just e2e`, `just seed`.
- Coverage: backend ≥ 80 %; dashboard 80/80/70/70.
- Logic in `etqan/learning/services/`; allowed imports as before (platform, identity/catalogue/scheduling/academy services). Scheduling values as strings.
- Lines only under `── phase B6 ──` markers; `verified_certificates` flipped in place with `requires=("certificates",)`. No edit to `config/settings/base.py` (local throttle class).
- Files private via `files.attach` / `remove_after_commit`; template ≤ 5 MiB, photo ≤ 2 MiB; images only (PNG/JPEG/WEBP).
- Routes under `/api/v1/learning/`; students by user id; `_int_param` for numeric params.
- Locales `certificates.json` (en + real ar), no wrapper; date-only via `formatDay`.
- Commit trailer `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`; explicit paths. Gitleaks scan before pushing (gate script).

## Review Focus

1. **Verification leaking data or being guessable** — only T-8 fields; student name only when valid; unknown code and switch off → 404; per-IP throttle with `authentication_classes = []`. Task 4.
2. **A family reading another family's certificate, photo or background** — 404; revoked hidden from family. Tasks 2, 4.
3. **Completion certificate for a course whose toggle is off** — 400 `course`. Task 2.
4. **Auto-fill counting the wrong sessions** — only completed + present + subscription + not trial, that student, that course. Task 2.
5. **Template image readable by people who shouldn't** — the template route is office-only; readers only through `certificates/<id>/background/` for a custom certificate they can read. Task 4.

---

### Task 1: Models, files path, switches, resources, migration

`learning/files.py`: `certificate_path = tenant_upload_path("certificates")` with `__module__` set; `IMAGE_TYPES = frozenset({".png", ".jpg", ".jpeg", ".webp"})`; `TEMPLATE_MAX = 5 * 1024 * 1024`; `PHOTO_MAX = 2 * 1024 * 1024`. Models per spec §3 (`Certificate.kind` TextChoices; CHECKs: kind in the four, `(kind='custom') = (template IS NOT NULL)`, `completed_sessions <= 9999`; `code` unique, default via a callable `new_code()` = `secrets.token_urlsafe(16)` defined in `files.py` or a small `codes.py`, `__module__` set if referenced by migrations). `post_delete` receivers for `CertificateTemplate.image` and `Certificate.photo` (file removed after commit) in `signals.py`. Features: `Feature("certificates", "Certificates", "الشهادات", "teaching", built=True)` under the B6 marker; flip `_later("verified_certificates", …)` to `Feature("verified_certificates", "Verified certificates", "نظام الشهادات الموثقة", "teaching", built=True, requires=("certificates",))`. Resources under the B6 marker: `certificate` (`view_any`, `view`, `create`, `update`, `delete`), `certificate_template` (`view_any`, `create`, `update`, `delete`). Update `platform/tests/test_features.py` BUILT. Migration `0004_certificates` (or the next number after B6c's).

Tests: switches built/off and `verified_certificates` held by `certificates`; CHECKs; code unique and 22 chars; delete removes files after commit.

- [ ] tests → RED → implement → migrate → GREEN (access `in_use` fails until Task 4 — accepted) → commit `feat(learning): certificate models and switches (B6d)`.

### Task 2: Certificate services

`services/certificates.py` per spec §4 with T-2…T-7 rules (issue and edit rules exactly as T-5; `session_count` per T-3 via `scheduling.services.sessions_queryset().filter(student__user_id=s, course_id=c, status="completed", student_attendance="present", subscription__isnull=False).exclude(kind="trial").count()`; `issue_certificate` auto-fills when `completed_sessions is None`; templates CRUD with 409 `learning.template_in_use` on delete when used; `set_course_toggle` creates/updates the row; `certificates_queryset` scoping per T-5; `revoke_certificate(cert, *, reason, by)` (reason required, 400 `reason`; already revoked → 409 `learning.certificate_revoked`); `delete_certificate`; `verify(code) -> VerifyResult | None` returning the T-8 fields (`status`, kind, course names, issued_on, academy_name from `connection.tenant.name` — read via `etqan.platform` or the academy services, whichever the codebase offers without importing tenants; check `academy.services.get_settings()` for a name field first); `certificates_of` per D33).

Tests: every issue/edit rule with its field; toggle gate; auto-fill counts (present yes; absent, excused, scheduled, other course, other student, no subscription, kind trial no); scoping (family own non-revoked, other family 404, teacher none); revoke rules; template in use 409; file replace/remove after commit; `verify` valid/revoked/unknown; `certificates_of` month bounds and shape.

- [ ] tests → RED → implement → GREEN → commit `feat(learning): certificate services (B6d)`.

### Task 3: Demo seed

`seed_b6_certificates` (idempotent, independent): a template "Classic" with a generated 1200×850 PNG (Pillow, plain colour + border), the Qur'an course toggle on, and a completion certificate for Yusuf (auto-filled) if he exists and none exists. Tests: idempotent, skips.

- [ ] tests → RED → implement → GREEN → `just seed` → commit `feat(learning): demo certificate (B6d)`.

### Task 4: API and route tables

`api/certificate_views.py` with the routes and permissions of spec §5 (teachers 403 by role; family 404 outside scope); multipart for template and certificate create/patch (`remove_photo` flag); files streamed with the shared `_stream` helper (`api/params.py`); `background/` streams the template image only for kind `custom`. Verify view: `authentication_classes = []`, `permission_classes = [AllowAny, FeatureOn]`, `feature = "verified_certificates"`, `throttle_classes = [CertificateVerifyThrottle]` where `class CertificateVerifyThrottle(AnonRateThrottle): rate = "30/minute"`; add to `SELF_SERVICE` ("public certificate check; unguessable code, throttled") at the end of the dict under a `# Phase B6, slice B6d` comment. Route tables: every coded row in `ROUTES` / `FEATURES` (`certificates`); `FEATURE_WORDS` `"/learning/certificate": "certificates"`. Item shapes per spec §5 (`verify_url` via `etqan.platform.frontend.app_url(f"/verify/{code}")` only while `verified_certificates` is on; `revoke_reason` office only).

Tests: per-role matrix; files per role; background only for custom; verify anonymous (no session cookie) valid / revoked (no student_name) / unknown 404 / switch off 404 / `certificates` off → 404; throttle (31st call → 429, using a cleared cache); `?student=²` ignored. Full access suite green; whole backend once.

- [ ] tests → RED → implement → GREEN → commit `feat(learning): certificates API and public verification (B6d)`.

### Task 5: Dashboard data layer and translations

`src/features/certificates/{schemas,api,queries,fixtures,errors,index}.ts` (+ tests), `src/locales/{en,ar}/certificates.json`, FeatureCode group `// Phase B6, slice B6d.` (`"certificates"`, `"verified_certificates"`). Blob downloads for photo/background/template image (`URL.createObjectURL`, revoked on unmount). `verifyApi.check(code)` uses a plain request without auth assumptions (works signed out).

- [ ] tests → RED → implement → GREEN → commit `feat(certificates): data layer and translations (B6d)`.

### Task 6: Office screens

`CertificatesList.tsx` + `IssueCertificateDialog.tsx` (student via `usePeople("students")`, course via catalogue, completed sessions pre-filled from `session-count` and editable, kind radio, template select for custom (active only), photo (2 MiB client check), message, date) + `CertificateDialog.tsx` (edit per T-5, revoke with reason, delete, open print); `TemplatesAdmin.tsx` (templates with blob thumbnails, add/edit/delete; course toggle list via `certificate-courses/`). Routes `people.certificates.tsx` (`{permission: "certificate.view_any", feature: "certificates"}`), `people.certificate-templates.tsx` (`{permission: "certificate_template.view_any", feature: "certificates"}`); nav under B6 marker; test lists extended.

- [ ] tests → RED → implement → GREEN → commit `feat(certificates): office screens (B6d)`.

### Task 7: Family page, print page, public verify page

`MyCertificates.tsx` (student/parent, child picker) at `learning.certificates.tsx`; print route under `_print` (`certificates.$certificateId.print.tsx`, check the `_print` layout's guards and how invoices' print route is permissioned) rendering `CertificatePrint.tsx` (A4 landscape `@page`, template background blob for custom or CSS frame, kind title, academy name + logo, student, course, sessions, message, `formatDay(issued_on)`, verify URL text when present; Print button); public route `verify.$code.tsx` (outside `_authed`, like `pay.return.tsx`) rendering `VerifyCertificate.tsx` with valid / revoked / not-found states in the reader's language (locale toggle as on other public pages). Tests for each; extend routes/permissions tests (public route listed as public, as pay routes are).

- [ ] tests → RED → implement → GREEN → full dashboard coverage run → commit `feat(certificates): family, print and verify pages (B6d)`.

### Task 8: e2e — `dashboard/e2e/b6-certificates.spec.ts`

Follow `e2e/b6-homework.spec.ts`. Journey: switches `certificates`, `verified_certificates` on; admin uploads a template (small PNG), enables Quran Memorisation, issues a completion certificate for a stamped student with a live subscription (count pre-filled shows a number); the student opens My certificates and the print page (student name and verify link visible); a fresh anonymous context opens the verify link → "Valid"; admin revokes it → anonymous verify shows "Revoked".

- [ ] write → passes twice → whole `just e2e` → commit `test(e2e): B6d certificates journey`.

### Task 9: Slice verification

- [ ] Fresh-stack gates (gate script incl. gitleaks) green; T-1…T-12 and §6 traced; phase notes updated.
