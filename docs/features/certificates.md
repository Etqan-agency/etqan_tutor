# Certificates

The office issues certificates to students for a course. There are four kinds: completion, appreciation,
pride, and custom (which is drawn on an uploaded template image). Students and parents read their own
(their children's) certificates, which are not revoked, and print them from the dashboard. Teachers get
403 on every certificate route. When verified certificates are on, each certificate carries an
unguessable code, and anyone can check it on a public page. Other apps (recorded courses today) issue
**subject certificates** through learning's services, and those share the same verification and print
flow.

## Concepts

| Model | Key fields | Notes |
|---|---|---|
| `CertificateTemplate` | `title` (≤ 120), `description`, `image` (private), `image_name`, `is_active` | The background of a custom certificate. A template that any certificate uses cannot be deleted. |
| `CourseCertificate` | `course` (one-to-one), `enabled` | The course's "awards a certificate" toggle. No row means off. It is kept in learning, not as a catalogue field. |
| `Certificate` | `student`, `course`, `kind`, `template` (custom only, DB check), `completed_sessions` (0–9999), `photo` (private, optional), `message` (≤ 1000), `issued_on`, `code` (unique), `revoked_at`, `revoke_reason`, `issued_by` | `code` = `secrets.token_urlsafe(16)` (`files.new_code`). |
| `SubjectCertificate` | `student`, `subject_en`/`subject_ar`, `count`, `count_label` (`lessons`), `source`/`source_id`, `code`, `issued_on`, `revoked_at` | For subjects that are not catalogue courses. At most one open (non-revoked) row per (source, source_id). The office certificate list never shows these. |

## How it works

`etqan/learning/services/certificates.py`:
- **Templates**: `create_template` / `update_template` / `delete_template`.
  - Image: PNG, JPEG or WEBP, at most 5 MiB (`files.TEMPLATE_MAX`). Images are re-encoded by
    `platform.uploads`.
  - Deleting a template that certificates use is refused with 409 `learning.template_in_use`. Deactivate
    it instead.
- **Toggles**: `course_toggles`, `set_course_toggle`.
- **Session count**: `session_count(student, course)` counts completed sessions with the student present
  and a subscription, excluding trials. The rule matches review eligibility. The issue form pre-fills
  this number, and the office can change it.
- **Issue**: `issue_certificate`.
  - The student must be active, and the course must exist.
  - `completion` needs the course toggle on (400 `course`).
  - `custom` needs an active template, and the other kinds must not have one.
  - The photo is optional: PNG, JPEG or WEBP, at most 2 MiB.
  - `issued_on` defaults to the academy's today and cannot be in the future.
  - No subscription is required.
- **Edit**: `update_certificate`.
  - `student`, `course` and `kind` never change (400).
  - A custom certificate can switch to another active template.
  - The session count, message, date and photo (replace or `remove_photo`) can be edited.
  - A revoked certificate is read-only (409 `learning.certificate_revoked`).
- **Revoke**: `revoke_certificate` needs a reason of at most 500 characters. A revoked certificate cannot
  be un-revoked. It stays in the office list, marked as revoked, and disappears from the student's list.
- **Delete**: `delete_certificate` (office). The photo is removed after commit.
- **Scoping**: `certificates_queryset(user, …)` gives the office everything, a student their own
  non-revoked certificates, and a parent their children's non-revoked certificates. Anyone else gets
  nothing.
- **Verify**: `verify(code)` looks for a `Certificate` first, then falls back to a `SubjectCertificate`
  (`_verify_subject`). It returns status `valid` or `revoked`, the kind, the course or subject names,
  `issued_on`, and the academy name (`connection.tenant.name`). The student's name is included only while
  the certificate is valid.
- **B10 hook**: `certificates_of(student_user_id, *, month)` lists certificates issued in that month.

`etqan/learning/services/subject_certificates.py` (exported for other apps):
- `issue_subject_certificate(student_user_id, subject_en, subject_ar, count, source, source_id, by)` is
  idempotent. It returns the open certificate if there is one, and survives a race on the partial unique
  constraint.
- `revoke_by_source`, `certificate_by_source`, `certificates_by_source_ids` return a `CertificateRef`.
- `get_subject_certificate(user, pk)` uses the same role scoping as certificates.
- The recorded-courses app uses this with `source="recorded.enrolment"`
  (`etqan/recorded/services/certificates.py`). See [Recorded courses](recorded-courses.md).

When `verified_certificates` is on, the certificate payload carries
`verify_url = app_url("/verify/<code>")`, which points at the dashboard's public page. When the switch is
off, `verify_url` is null.

## API

All routes are under `/api/v1/learning/`. Every route uses the `certificates` switch except verify, which
uses `verified_certificates`.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET / POST | `/api/v1/learning/certificate-templates/` | `certificate_template.view_any` / `.create` | List / add (multipart) |
| PATCH / DELETE | `/api/v1/learning/certificate-templates/<id>/` | `certificate_template.update` / `.delete` | Edit / delete |
| GET | `/api/v1/learning/certificate-templates/<id>/image/` | `certificate_template.view_any` | Stream the template image (office) |
| GET | `/api/v1/learning/certificate-courses/` | `certificate_template.view_any` | Course toggles |
| PUT | `/api/v1/learning/certificate-courses/<course_id>/` | `certificate_template.update` | `{enabled}` |
| GET | `/api/v1/learning/certificates/session-count/?student=&course=` | `certificate.create` | Pre-fill count |
| GET / POST | `/api/v1/learning/certificates/?student=&course=&kind=` | `certificate.view_any` (or student/parent read) / `certificate.create` | Paginated list / issue (multipart) |
| GET / PATCH / DELETE | `/api/v1/learning/certificates/<id>/` | `certificate.view` (or student/parent) / `.update` / `.delete` | Read / edit / delete |
| POST | `/api/v1/learning/certificates/<id>/revoke/` | `certificate.update` | `{reason}` |
| GET | `/api/v1/learning/certificates/<id>/photo/` | `certificate.view`; student/parent in scope | Stream the photo |
| GET | `/api/v1/learning/certificates/<id>/background/` | same | The template image of a custom certificate |
| GET | `/api/v1/learning/subject-certificates/<id>/` | same | One subject certificate for its print page |
| GET | `/api/v1/learning/certificates/verify/<code>/` | Anonymous (`authentication_classes = []`, `AllowAny`) | Public check, throttled to 30/minute per IP (`CertificateVerifyThrottle`) |

## Dashboard

| Route file (`dashboard/src/routes/`) | Who | Component |
|---|---|---|
| `_authed/people.certificates.tsx` | Office | `CertificatesList`, `IssueCertificateDialog`, `CertificateDialog` |
| `_authed/people.certificate-templates.tsx` | Office | `TemplatesAdmin` (templates and course toggles) |
| `_authed/learning.certificates.tsx` | Student / parent | `MyCertificates` |
| `_print/certificates.$certificateId.print.tsx` | Readers | `CertificatePrint`: A4 landscape, template image or built-in CSS frame, verification link as text |
| `_print/subject-certificates.$certificateId.print.tsx` | Readers | `SubjectCertificatePrint` |
| `verify.$code.tsx` (`/app/verify/<code>`, no sign-in) | Anyone | `VerifyCertificate` |

Images reach the print page as blobs from the authenticated endpoints, never as public URLs. Printing and
saving as PDF are done in the browser; there is no server-side PDF. The feature folder is
`dashboard/src/features/certificates/`.

## Background jobs

None. Certificates send no notifications.

## Configuration

- Switches:
  - `certificates`: built, off by default.
  - `verified_certificates`: built, off by default, and `requires=("certificates",)`.
- Access resources:
  - `certificate`: `view_any`, `view`, `create`, `update`, `delete`.
  - `certificate_template`: `view_any`, `create`, `update`, `delete`. Toggle edits use
    `certificate_template.update`.
- Demo data: `etqan/tenants/seeds/b6.py:seed_b6_certificates`.

## Code map

- `backend/etqan/learning/models.py`: `CertificateTemplate`, `CourseCertificate`, `Certificate`,
  `SubjectCertificate`.
- `backend/etqan/learning/services/certificates.py`, `subject_certificates.py`.
- `backend/etqan/learning/api/certificate_views.py`, `serializers.py` (`certificate_data`,
  `subject_certificate_data`).
- `backend/etqan/learning/files.py`: `IMAGE_TYPES`, `TEMPLATE_MAX`, `PHOTO_MAX`, `new_code`.
- `backend/etqan/learning/signals.py`: deletes template images and photos when rows are deleted.
- `dashboard/src/features/certificates/`.

## Design history

- [B6d spec: certificates](../superpowers/specs/2026-10-05-b6d-certificates-design.md), decisions T-1…T-12.
- [Plan 39](../superpowers/plans/2026-10-05-plan-39-certificates.md).
- [B7g spec](../superpowers/specs/2026-10-08-b7g-recorded-certificates-codes-design.md) R8 (ledger D58)
  added `SubjectCertificate` and the verification fallback. It also amends B6d's T-11, which had said "no
  reuse is promised".
- [Plan 59](../superpowers/plans/2026-10-08-plan-59-recorded-certificates-codes.md).
