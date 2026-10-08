# Slice B6d — Certificates — Design

**Date:** 2026-10-05
**Status:** Self-approved after an independent spec review (orchestration spec PO-3); review findings applied 2026-10-05.
**Phase spec:** `2026-10-05-b6-learning-design.md` (B6-1…B6-11 bind; §3 row B6d is the contract).
**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` (P1 CERT-001/002/003, FLOW-011, BR-31, BR-39) and
`docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` (TH §2.8). Unobserved behaviour is `[assumed]` (ledger D1).
**Requires:** B6a (the `etqan.learning` app). No other phase's slice.

## 1. Goal

The office issues certificates to students — completion, appreciation, pride, or on one of the academy's own templates —
with the number of completed sessions filled in for them; students and parents can open and print them; and, when
verified certificates are switched on, anyone holding a certificate's link can check it is genuine.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| T-1 | **Certificate templates**: title\*, short description, template image\* (PNG/JPEG/WEBP, ≤ **5 MiB** = 5 × 1024 × 1024 bytes, re-encoded by `etqan.platform.uploads`), active flag. The office manages them. A template is the background of a "custom" certificate. Replacing a template's image changes how every custom certificate on it prints from then on [assumed: accepted, templates are designs]. | P1 CERT-001 (title\*, short description, template image ≤ 5 MB); BR-39 |
| T-2 | **A certificate**: student\*, course\*, kind\* `completion` / `appreciation` / `pride` / `custom` (custom requires an active template; the other kinds have none and use the built-in design), completed-session count\*, optional student photo (PNG/JPEG/WEBP ≤ **2 MiB**), optional message from the administration (≤ 1000), issue date (default today, academy-local), who issued it. | P1 CERT-002 (type\*, photo ≤ 2 MB, student\*, course\*, completed session count, message); TH §2.8 · [assumed] issue date, built-in design for the three named kinds |
| T-3 | **Completed sessions auto-fill**: the count of the student's sessions in that course with status `completed`, student attendance `present`, a subscription (`subscription_id` not null) and `kind != "trial"` — the same eligibility as B6c R-2 — read through `scheduling.services.sessions_queryset()` with string comparisons. The office form pre-fills it from `GET certificates/session-count/?student=&course=` and may change it (0–9999); the stored number is what the certificate shows. | P1 BR-31 ("auto-filled from the chosen student + course"); FLOW-011 · [assumed] editable after auto-fill, "completed" = attended |
| T-4 | **The course "certificate" toggle** (CERT-003, "students can get a certificate after completing"): a learning-owned row `CourseCertificate(course one-to-one, enabled)` (no catalogue field, B6-1/B6-10), edited on the certificates settings screen. A **completion** certificate may be issued only for a course whose toggle is on (else 400 `course`); the other kinds for any course. Default: off (no row = off). | P1 CERT-003; TH CATALOG-001 "Certificate" toggle; phase spec §3 B6d · [assumed] what the toggle gates |
| T-5 | **Who**: the office (codes) issues, edits, revokes and deletes certificates and manages templates and toggles. Students and parents read their own (children's) non-revoked certificates and open the printable page. **Teachers get 403** on every certificate route (role check) [assumed]; a student or parent asking for a certificate outside their scope gets 404. **Issue rules** (400 with field): the student must be an active student (`student`); the course must exist (`course`); a completion certificate needs the course toggle on (`course`); kind must be one of the four (`kind`); custom needs an active template (`template`), the others none (`template`); 0 ≤ completed sessions ≤ 9999 (`completed_sessions`); `issued_on` not in the future (`issued_on`). No subscription is required (appreciation and pride may honour any student) [assumed]. **Edit rules**: `student`, `course` and `kind` never change (400 on that field); a custom certificate may switch to another active template; `completed_sessions` (not re-auto-filled), `message`, `issued_on`, photo (replace, or `remove_photo`) are editable; a revoked certificate is read-only (409 `learning.certificate_revoked`) except for deletion; there is no un-revoke. | B6-4 · [assumed] |
| T-6 | **Printable certificate**: a dashboard print page (the existing `_print` layout, as invoices/payslips) laying out on an A4-landscape page: the template image (custom) or the built-in frame (other kinds, CSS only), the kind's title, the academy name and logo, the student's name, the course name, the completed-session count, the message, the issue date, and — when verified certificates are on — the verification link as text. The photo and template image reach the page as blobs from authenticated endpoints (never public URLs; ledger D2); the academy logo is the existing public branding image. The page uses its own `@page { size: A4 landscape }` (the existing `PrintSheet` is portrait). The built-in frame for the three named kinds is dashboard CSS [assumed]. The reader prints or saves as PDF from the browser; no server-side PDF. | P1 FLOW-011 ("rendered from the selected certificate template image") · [assumed] browser print, A4 landscape, no QR code |
| T-7 | **Revoking**: the office may revoke a certificate (`revoked_at`, reason ≤ 500); a revoked certificate stays listed (marked) for the office and disappears from the student's list; its verification answers "revoked". Deleting is also allowed (office) and removes its photo after commit. | [assumed] |
| T-8 | **Verified certificates** (`verified_certificates`, the existing `_later` line flipped in place to built, **requires `certificates`**): every certificate has an unguessable `code` (`secrets.token_urlsafe(16)`, unique). While the switch is on, an **anonymous** `GET /api/v1/learning/certificates/verify/<code>/` answers `{status: "valid" | "revoked", kind, course_name_en, course_name_ar, issued_on, academy_name}` plus `student_name` only when valid (no photo, no template image, no ids); `academy_name` is the academy's stored name. The view has `authentication_classes = []` (as the gateways public link view), `AllowAny` + `FeatureOn`, and a learning-local `CertificateVerifyThrottle(AnonRateThrottle)` with `rate = "30/minute"` (no edit to the shared settings file), so it throttles per IP; an unknown code or the switch off → 404. The public page is the dashboard route `/app/verify/$code` (outside the app shell, like `/app/pay/return`), linked from the printable certificate via `etqan.platform.frontend.app_url("/verify/<code>")`. | P1 CERT-003 flag "نظام الشهادات الموثق"; phase spec §3 (anonymous, throttled, unguessable) · [assumed] fields shown |
| T-9 | Switches: `certificates` (new, under the B6 marker, "Certificates" / "الشهادات", group `teaching`, built, off) and `verified_certificates` (flipped, `requires=("certificates",)`). | B6-2 |
| T-10 | Access resources (new, under the B6 marker), `in_use` exactly the codes §5 declares: `certificate` ("Certificates" / "الشهادات": `view_any`, `view`, `create`, `update`, `delete`) and `certificate_template` ("Certificate templates" / "قوالب الشهادات": `view_any`, `create`, `update`, `delete`). The toggle edit uses `certificate_template.update`. | P1 permission keys `certificate`, `certificate::template` |
| T-11 | **B7**: recorded-course certificates (RC "accredited certificate") are B7's; any change to `Certificate` / `issue_certificate` they need is a request to B6 (orchestration §6.2.1, §6.2.5) — no reuse is promised here. **B5**: `certificate_events` is not built (COMM-004 lists no certificate notice). **B10**: `certificates_of(student_user_id, *, month) -> list[CertificateMonth(certificate_id, course_id, course_name_en, course_name_ar, kind, issued_on, revoked)]` (issued in the calendar month). Recorded in the ledger. | phase spec §3; B6-9 |
| T-12 | No column on any existing table; four new tables in `etqan.learning` (B6-10). No notifications (B6-6). | B6-6, B6-10 |

## 3. Data

```text
etqan.learning.CertificateTemplate
  title         CharField(120)  required
  description   TextField(blank, max 1000)
  image         FileField(private, upload_to=files.certificate_path, max_length=255)  required   (path callable defined in learning/files.py with __module__ set, as B6b's)
  image_name    CharField(255)
  is_active     BooleanField(default True)
  created_at, updated_at
  ordering (title, id)

etqan.learning.CourseCertificate
  course        OneToOne catalogue.Course  CASCADE  related_name="+"
  enabled       BooleanField(default False)

etqan.learning.Certificate
  student       FK identity.StudentProfile  PROTECT  related_name="+"
  course        FK catalogue.Course  PROTECT  related_name="+"
  kind          CharField(12)  completion | appreciation | pride | custom   (CHECK)
  template      FK CertificateTemplate  null  PROTECT  related_name="certificates"
  completed_sessions  PositiveIntegerField  (CHECK <= 9999)
  photo         FileField(private, same path)  blank
  photo_name    CharField(255, blank)
  message       TextField(blank, max 1000)
  issued_on     DateField
  code          CharField(32)  unique
  revoked_at    DateTimeField  null
  revoke_reason TextField(blank, max 500)
  issued_by     FK AUTH_USER  null  SET_NULL  related_name="+"
  created_at, updated_at
  CHECK: (kind = 'custom') = (template IS NOT NULL)
  ordering (-issued_on, -id)
```

A template with certificates cannot be deleted (409 `learning.template_in_use`; deactivate instead). Replaced or removed
images/photos and those of deleted rows are deleted after commit (B6b's `files` helpers).

## 4. Services (`services/certificates.py`)

`templates_queryset`, `create_template`, `update_template`, `delete_template`; `course_toggles()`, `set_course_toggle(course_id,
enabled)`; `session_count(student_user_id, course_id) -> int`; `certificates_queryset(user, *, student=None, course=None,
kind=None)` (office all, revoked included and marked; student own non-revoked; parent children's non-revoked; teachers and others none);
`get_certificate(user, id)`; `issue_certificate(*, student_user_id, course_id, kind, completed_sessions=None, template_id=None,
photo=None, message="", issued_on=None, by)` (None count → auto-fill); `update_certificate(cert, **changes)`;
`revoke_certificate(cert, *, reason, by)`; `delete_certificate(cert)`; `verify(code) -> VerifyResult | None`;
`certificates_of(...)`.

## 5. API (`/api/v1/learning/`, `FeatureOn` last)

| Method & path | Permission (staff code) | Feature |
|---|---|---|
| `GET/POST certificate-templates/`, `PATCH/DELETE certificate-templates/<id>/`, `GET certificate-templates/<id>/image/` | `HasCode` — `certificate_template.view_any` / `create` / `update` / `delete` (the image GET is office-only; readers get a certificate's background through `certificates/<id>/background/`) | `certificates` |
| `GET certificate-courses/`, `PUT certificate-courses/<course_id>/` | `HasCode` — `certificate_template.view_any` / `update` | `certificates` |
| `GET certificates/session-count/?student=&course=` | `HasCode` — `certificate.create` | `certificates` |
| `GET certificates/?student=&course=&kind=&page=` | `HasCode \| (ReadOnly & (IsStudent \| IsParent))` — `certificate.view_any` | `certificates` |
| `POST certificates/` (multipart) | `HasCode` — `certificate.create` | `certificates` |
| `GET certificates/<id>/` | as the list — `certificate.view` | `certificates` |
| `PATCH certificates/<id>/` (multipart), `POST certificates/<id>/revoke/` | `HasCode` — `certificate.update` | `certificates` |
| `DELETE certificates/<id>/` | `HasCode` — `certificate.delete` | `certificates` |
| `GET certificates/<id>/photo/`, `GET certificates/<id>/background/` (the template image of a custom certificate; 404 otherwise) | as `GET certificates/<id>/` — `certificate.view` | `certificates` |
| `GET certificates/verify/<code>/` | anonymous, `SELF_SERVICE` ("public certificate check; unguessable code, throttled"), `AllowAny` + `FeatureOn` for `verified_certificates` | `verified_certificates` |

Students by user id. Certificate item: `{id, student:{id, full_name}, course:{id, name_en, name_ar}, kind, template_id,
completed_sessions, has_photo, message, issued_on, code (office and readers), verify_url (when verified_certificates is on),
revoked_at, revoke_reason (office only), issued_by}`. `FEATURE_WORDS` gains `"/learning/certificate": "certificates"` (covers
`certificates/`, `certificate-templates/`, `certificate-courses/`) — the verify route declares `verified_certificates`
and is SELF_SERVICE, so it is outside the words check; learning's own tests cover it (anonymous valid / revoked / unknown,
switch off 404, `certificates` off holds it off, throttle).

## 6. Screens (dashboard `src/features/certificates/`; locale area `certificates.json`)

| Who | Where | What |
|---|---|---|
| Office | People → Certificates `/people/certificates` (`certificate.view_any`, `certificates`) | List: student · course · kind · sessions · issued · status (revoked); filters; Issue (student, course → completed sessions pre-filled, kind, template for custom, photo, message, date); open → edit / revoke / delete / print. |
| Office | People → Certificate templates `/people/certificate-templates` (`certificate_template.view_any`) | Templates (image thumbnail via blob, title, active) add / edit / delete; "Courses that award certificates" toggle list. |
| Student / parent | Learning → My certificates `/learning/certificates` | Own (children's) certificates; open → print page. |
| Anyone with access | Print page `/certificates/$id/print` (`_print` layout) | The certificate laid out for A4 landscape; Print button. |
| Anonymous | `/app/verify/$code` (outside the shell, no sign-in) | "Valid certificate" / "Revoked" / "Not found" with the T-8 fields. |

## 7. Seeds and tests

- `seed_b6` gains: one template (a generated PNG), the Qur'an course's toggle on, and a completion certificate for Yusuf
  (auto-filled count). Idempotent.
- Backend: T-1…T-12 rules (template image types/size, custom ⇔ template, toggle gate for completion, auto-fill count
  incl. absent/excused/other course excluded, scoping per role incl. revoked hidden from family, revoke/delete, template in
  use 409, file cleanup, code uniqueness, verify anonymous: valid / revoked / unknown 404 / switch off 404 / `certificates`
  off holds `verified_certificates` / throttle), route tables, seed.
- Dashboard: each screen per role; print page layout pieces present (names, kind title, verification link only when on);
  verify page states; locale parity.
- e2e `e2e/b6-certificates.spec.ts`: switches on; admin uploads a template, enables the course, issues a completion
  certificate (count pre-filled); the student opens My certificates and the print page; the verify link opened anonymously
  shows "Valid"; after revoking it shows "Revoked".
