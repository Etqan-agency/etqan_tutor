# Slice B7g — Recorded-course certificates and activation codes — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (PO-3); findings applied 2026-10-08. Spec-only
mode (ledger D45). The plan waits for B6d, B3f and the two requests in §4 to merge.
**Phase:** B7, slice g (`2026-10-08-b7-add-on-sales-design.md` §3, B7-12).
**Requires:** B7a; B6d (learning certificates) and B3f (`etqan.vouchers`), plus requests R-B7g-1 (B6)
and R-B7g-2 (B3).
**Evidence:** P1 RC-001 ("accredited certificate" toggle) and RC-003 (payment method "activation code",
"certificate obtained" toggle). Ledger D33: recorded-course certificates are B7's, and changes to
learning's certificates are requests to B6. Ledger D44: B7 asks B3 for a voucher kind. Ledger D43: a code
is never revenue.

## 1. Goal

A student who has watched every published video of a playlist that grants a certificate gets one. It is
printable and verifiable like B6d's certificates. The office can also give codes that enrol a student in a
playlist when redeemed, which is TutorHamster's "activation code" way of paying.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| G-1 | **Completion** means every published video of the playlist is watched, and the playlist has at least one (B7a `is_complete`). The check runs inside each of the three watched-set writers (the student's toggle, the player's auto-mark, and the office's multi-select through `update_enrolment`). They all lock the enrolment row first (B7a §8.2), so concurrent marks cannot miss completion. When the set reaches completion on a playlist with `certificate=true`, while `certificates` is on and the enrolment is active, B7 issues the certificate in the same transaction (`by=None`). Unwatching videos afterwards, whether by the student or the office, does not revoke it. Revoking the enrolment does nothing to the certificate. Turning a playlist's `certificate` flag on later does not back-fill; the office uses G-2. | P1 RC-001, RC-003 · [assumed] trigger |
| G-2 | **"Certificate obtained" by hand** (RC-003). The office ticks it on the enrolment page. B7 first checks `certificates` itself (B6's issue service has no feature check): off gives 409 `recorded.certificates_off`. Then it issues, if none exists for the enrolment. Unticking revokes it, with the reason "Revoked from the recorded course enrolment". The tick is not stored on the enrolment: it is read from learning (G-4), so it cannot go stale. B7a has no such column. | P1 RC-003 · [assumed] |
| G-3 | **The certificate** is a learning-owned row of the new kind requested in R-B7g-1. Its subject is the playlist's title. Its count is the playlist's lesson count, printed as "lessons completed". Printing, the verification page (`verified_certificates`) and the student's certificates list are B6's. | ledger D33 |
| G-4 | **B7 keeps no copy of certificate state.** The enrolment page and the student's player read `learning.services.certificate_by_source("recorded.enrolment", enrolment_id)`, which returns the id, code, issued date and revoked flag, or None. | review I4 |
| G-5 | **Activation codes** (RC-003 "activation code") are B3f vouchers of the new kind `playlist` requested in R-B7g-2. The office generates them in B3f's batch screen, choosing a playlist. They are redeemed on B3f's family and office redeem routes. Redemption enrols the student through `enrol_from_sale(method="code", amount_minor=0, currency=<playlist currency>, transaction_number=<the code's display form, SYS-XXXXX-XXXXX>, payment_id=None)`. No billing row is made, and a code is never revenue (D43, B3f F-7). | P1 RC-003; ledger D43, D44 |
| G-6 | **Redemption refusals** come from B7's hook. `recorded_courses` off gives 404 (`vouchers.unavailable`). A playlist that is not published gives 409 `recorded.not_for_sale`. A student already enrolled gives 409 `recorded.already_enrolled`. The code stays unused in each case, because B3f's redemption is one transaction (F-14). | B3f F-14 |
| G-7 | **Deleting a playlist** (B7a A-12) is also refused while any `playlist` batch names it (`vouchers.services.batches_exist(kind="playlist", target_id=…)`): 409 `recorded.playlist_in_use`. | review I8 |

## 3. Data

B7g adds no column to `etqan.recorded`: certificate state is learning's (G-4) and code state is vouchers' (G-5).

## 4. Requests, now delegated to B7

Both requests were delegated back to B7 to build in this slice:

- **R8** (ledger D58, by B6). Build only after B6d merges (it has). Work under a ledger claim on
  `etqan.learning`, in learning's own migration after `0004_certificates`. `verify()` falls back to
  `SubjectCertificate` when no `Certificate` has the code; it answers the same T-8 fields and gives the
  student name only while the certificate is valid. The printable page is extended additively.
  `Certificate` is untouched. B6's office certificate routes never list or edit these rows.
  `certificates_of` (D33) does **not** list them: B7 reports its own. Release the claim when merged, then
  ask the learning owner (the conductor) to review the learning diff.
- **R9** (ledger D56, by the conductor). Work under a ledger claim on `etqan.vouchers`, additive only. The
  existing voucher kinds must keep working unchanged, and tests must prove it. Release the claim right
  after.

The original request text follows for reference.

## 4a. Original requests

- **R-B7g-1 → B6 (learning). A separate certificate table, leaving `Certificate` untouched.** A nullable
  `Certificate.course` would break `course_ref` in the serializers, `verify()`, the lists and forms, and
  `CertificateMonth.course_id: int` (D33, read by B10). So the request is a new learning table instead:
  `SubjectCertificate(student, subject_en, subject_ar, count, count_label 'lessons', source, source_id,
  code, issued_on, revoked_at, revoke_reason, issued_by null)`, unique on (`source`, `source_id`) while
  not revoked. It comes with these services: `issue_subject_certificate(*, student_user_id, subject_en,
  subject_ar, count, source, source_id, by=None) -> CertificateRef(id, code)`;
  `revoke_by_source(source, source_id, *, reason, by)`; and `certificate_by_source(source, source_id) ->
  CertificateRef | None`. B6's `verify()` and printable page also read this table, under the same code
  space and the same `verified_certificates` switch. The office cannot edit or delete these rows through
  B6's routes; they are revoked only through `revoke_by_source`. Whether `certificates_of` (B10) lists them
  is B6's choice, and would be recorded as a D33 amendment. If B6 declines, B7g builds its own
  `RecordedCertificate`, print page and verification route, and records a shared decision.
- **R-B7g-2 → B3 (vouchers). A generic redeemer registry and a `playlist` kind.** This is a migration on
  B3's tables (`kind` choices and checks, and a generic `target_id` BigInteger column on the batch, plus
  `target_ref_id` on the voucher for the created enrolment), not just "additive" services.
  - Vouchers gains `register_redeemer(kind, *, describe(target_id) -> (name_en, name_ar),
    check(target_id), redeem(*, target_id, student_user_id, code_display, by) -> (student_profile_id,
    ref_id), office_code="rc_enrolment.create", feature="recorded_courses")`. `RecordedConfig.ready()`
    registers it, so vouchers never imports recorded.
  - Redemption applies B3f's family scope (`in_family`, F-16) before the hook, and `preview()` lists the
    family's students for this kind as it does for activation.
  - `KIND_CODES` gains the registered office code.
  - Generation and redemption refuse while the registered feature is off.
  - F-15's lock order gains Voucher → Playlist → Enrolment.
  - F-1's "no app imports vouchers" is amended to allow `etqan.recorded` to reach `vouchers.services`,
    and a contract "vouchers never imports recorded" is added.
  - `batches_exist(kind, target_id)` is exported for G-7.

## 5. Tests (outline; the plan is written once B6d, B3f and both requests are merged)

- **Completion.** It is issued exactly once, including under two parallel `set_watched` transactions on
  the last two videos. All three writers trigger it. A playlist with zero videos never completes.
  Unwatching keeps the certificate. Ticking and unticking by hand. `certificates` off issues nothing,
  and the hand tick answers 409. Revoking the enrolment keeps the certificate. Print and verify show the
  playlist title and "lessons completed".
- **Codes.** A code enrols a student, on the family route and the office route. The family scope is
  enforced. Each refusal leaves the code unused. No billing row is made, and revenue does not change. A
  playlist with batches cannot be deleted.
- **e2e:** the demo student watches the last video of a certificate playlist and opens the certificate. A
  generated code enrols another student.

## 6. Rulings from planning (plan 59)

- **G-3 wording.** Students reach a recorded-course certificate from the course player link and the print
  page. B6's certificate list does not show it, because `certificates_of` excludes subject certificates
  (D58).
- **`CertificateRef`** is `(id, code, issued_on, revoked)`, which G-4 needs.
- **Subject names.** A playlist has one title (B7a A-3), so `subject_en` and `subject_ar` are both set
  to it.
- **G-6 status.** A playlist code while `recorded_courses` is off reuses B3f's existing
  `vouchers.unavailable` error, at whatever status B3f gives it.
- **Concurrency.** The completion race is guarded by the enrolment row lock. It is tested with
  captured-SQL lock order plus an idempotent second issue, not a true two-transaction test:
  `transaction=True` leaks rows under django-tenants (as in B7a and B7c).
