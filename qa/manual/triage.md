# Triage (Agent 2)

| Finding | Area | Result (bug id / dup / not a bug) | Sev | Type | Easy P3 | Status | Screenshot |
|---|---|---|---|---|---|---|---|
| M02-F-001 | M02 | ETQAN-QA-048 (same root cause as ETQAN-QA-011) | P3 | translation | yes | VERIFIED | `qa/manual/screens/M02/triage/t008-account-newpw-123-en.png` |
| M02-F-002 | M02 | ETQAN-QA-049 | P3 | translation | yes | VERIFIED | `qa/manual/screens/M02/triage/t002-invalid-credentials-ar.png` |
| M02-F-003 | M02 | ETQAN-QA-050 | P3 | functional | no | OPEN | `qa/manual/screens/M02/triage/t009-profile-save-flips-lang.png` |
| M02-F-004 | M02 | ETQAN-QA-051 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M02/triage/t013-verify-email-double-prefix.png` |
| M02-F-005 | M02 | ETQAN-QA-052 | P3 | functional | no | OPEN | `qa/manual/screens/M02/triage/t010c-double-submit-sync.png` |
| M02-F-006 | M02 | ETQAN-QA-053 | P3 | functional | no | OPEN | `qa/manual/screens/M02/triage/t014b-verify-second-invalid.png` |
| M02-F-007 | M02 | ETQAN-QA-054 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M02/triage/t015-remove-email-no-toast.png` |
| M02-F-008 | M02 | ETQAN-QA-055 | P3 | functional | no | OPEN | `qa/manual/screens/M02/triage/t019c-used-reset-link-error.png` |
| M02-F-009 | M02 | ETQAN-QA-056 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M02/triage/t020-forgot-code-step-cards.png` |
| M02-F-010 | M02 | ETQAN-QA-057 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M02/triage/t022c-quick-login-used-link.png` |
| M02-F-011 | M02 | ETQAN-QA-058 | P3 | functional | no | OPEN | `qa/manual/screens/M02/triage/t006-deeplink-after-login.png` |
| M02-F-012 | M02 | ETQAN-QA-059 | P3 | functional | no | OPEN | `qa/manual/screens/M02/triage/t016-session-lost-save.png` |
| M02-F-013 | M02 | ETQAN-QA-060 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M02/triage/t016-session-lost-save.png` |
| M02-F-014 | M02 | ETQAN-QA-061 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M02/triage/t004-forgot-sms-ar.png` |
| M02-F-015 | M02 | ETQAN-QA-062 | P3 | RTL | yes | CLOSED (not a bug on retest, gate) | `qa/manual/screens/M02/triage/t005-mobile-method-cards-ar.png` |
| M02-F-016 | M02 | not a bug: "+99" is how "99+" renders in an RTL context and is the usual Arabic UI form (e.g. "+100"); count is right | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M02/triage/t006-deeplink-after-login.png` |
| M02-F-017 | M02 | ETQAN-QA-063 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M02/triage/t023-lockout-no-wait-time.png` |
| M02-F-018 | M02 | not a bug: by design in `ui/locale-toggle.tsx` - with 2 languages (qaother, login) a toggle shows the target; with 3+ (qa has Spanish on) a menu shows the current language | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M02/triage/t007-student-account-en.png` |
| M02-F-019 | M02 | not a bug: the anonymous `GET identity/me/` session probe answering 403 is the documented contract (sign-in.md: requireAuth redirects when `me/` fails); console-only, no user impact. Manifest ERR_ABORTED is a cancelled prefetch | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M02/triage/t001-login-empty-ar.png` |
| M02-F-020 | M02 | ETQAN-QA-064 | P4 | copy | no | OPEN | `qa/manual/screens/M02/triage/t001-login-empty-ar.png` |
| M02-F-021 | M02 | ETQAN-QA-065 (Arabic order of the parts). Missing date/time = not a bug: B9b S-8 defines "device · IP · zone"; time needs an API field -> PROPOSAL | P3 | RTL | yes | OPEN | `qa/manual/screens/M02/triage/t032-last-signin-ar.png` |
| M02-F-022 | M02 | ETQAN-QA-066 | P3 | copy | yes | OPEN | `qa/manual/screens/M02/triage/t030-qaother-new-to-etqan-ar.png` |
| M06-F-001 | M06 | ETQAN-QA-202 | P3 | functional | no | OPEN | `qa/manual/screens/M06/triage/t001-new-sub-form-ar.png` |
| M06-F-002 | M06 | ETQAN-QA-208 | P3 | translation | yes | VERIFIED | `qa/manual/screens/M06/triage/t003-sub94-detail-ar.png` |
| M06-F-003 | M06 | ETQAN-QA-210 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M06/triage/t001-new-sub-form-ar.png` |
| M06-F-004 | M06 | ETQAN-QA-209 (related to ETQAN-QA-060, different components) | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M06/triage/t003-sub94-detail-ar.png` |
| M06-F-005 | M06 | not a bug: a past start is allowed by design (Plan 4 spec §4.2: "A start in the past is allowed; the dates between that start and today get no sessions automatically, and the admin backfills them with Generate for range"); the hourly job expires it once today > grace_ends_on (§5 Expiry); the invoice is issued at creation + invoice_due_days (billing.md) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M06/M06-F-005-backdated-sub-active-no-sessions.png` |
| M06-F-006 | M06 | ETQAN-QA-215 | P4 | copy | no | OPEN | `qa/manual/screens/M06/triage/t001-new-sub-form-ar.png` |
| M06-F-007 | M06 | ETQAN-QA-205 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M06/triage/t007-slot-stop-no-confirm.png` |
| M06-F-008 | M06 | ETQAN-QA-200 (invoice due date part is by design: billing.md invoice_due_days from issue) | P3 | functional | no | OPEN | `qa/manual/screens/M06/triage/t004-list-ibrahim-renewal-two-active.png` |
| M06-F-009 | M06 | ETQAN-QA-201 (calendar duplicate part → ETQAN-QA-200) | P3 | functional | no | OPEN | `qa/manual/screens/M06/triage/t003-sub94-detail-ar.png` |
| M06-F-010 | M06 | not a bug: cancel is documented as status + deletion of untouched regular sessions only (subscriptions.md §6); invoices are a separate billing decision (void/refund rules in billing.md), nothing couples them. The slot buttons left (أوقف/حذف, no edit) match the services: an ended subscription allows deactivation, and delete_slot allows a slot with no sessions | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M06/triage/t009-cancelled-sub95.png` |
| M06-F-011 | M06 | ETQAN-QA-211 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M06/triage/t011-bundle-pause-english-error.png` |
| M06-F-012 | M06 | ETQAN-QA-203 (related to ETQAN-QA-033) | P3 | functional | yes | VERIFIED | `qa/manual/screens/M06/triage/t010-family-picker.png` |
| M06-F-013 | M06 | ETQAN-QA-206 | P3 | translation | yes | VERIFIED | `qa/manual/screens/M06/triage/t011-bundle-pause-english-error.png` |
| M06-F-014 | M06 | ETQAN-QA-207 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M06/triage/t012-trials-datetime-rtl.png` |
| M06-F-015 | M06 | ETQAN-QA-212 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M06/M06-F-015-schedule-trial-not-prefilled.png` (+ code) |
| M06-F-016 | M06 | ETQAN-QA-213 | P3 | a11y | yes | VERIFIED | `qa/manual/screens/M06/triage/t014-attendance-unlabeled.png` |
| M06-F-017 | M06 | ETQAN-QA-214 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M06/triage/t015-en-list-archive-label.png` |
| M06-F-018 | M06 | not a bug: B2e spec E-11 "Warnings, never blocks: every slot row carries outside_availability (computed on read, in the slot payload) … so subscription create … show it": the warning is designed to appear on the saved slot rows, which it does ("Outside … availability" on sub 104). A pre-save hint in the form is an enhancement (proposal), like ETQAN-QA-043 for conflicts | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M06/triage/t019-sub104-outside-availability.png` |
| M06-F-019 | M06 | not a bug: Plan 4 spec §4.1 Generation: "Today's session is created even when its start time has already passed." (sub 104 session 448 at 27/10 09:00 created 22:09). A form hint is an owner proposal | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M06/triage/t018-teacher-today-past-lesson.png` |
| M06-F-020 | M06 | dup of M06-F-013 → ETQAN-QA-206 (same class: untranslated server ValidationError text; availability.py:91) | P3 | translation | yes | VERIFIED (dup) | `qa/manual/screens/M06/triage/t017-availability-english-error.png` |
| M06-F-021 | M06 | dup of M06-F-008 → ETQAN-QA-200 (student view of the same not-started renewal) | P3 | functional | no | OPEN (dup) | `qa/manual/screens/M06/triage/t006-student-two-active-cards.png` |
| M06-F-022 | M06 | ETQAN-QA-204 | P3 | mobile | yes | VERIFIED | `qa/manual/screens/M06/triage/t016-mobile-list-overflow.png` |
| M06-F-023 | M06 | dup of M06-F-007 → ETQAN-QA-205 (no confirmation); deleting a pause that started today is documented (subscriptions.md §3) | P3 | UI-layout | yes | VERIFIED (dup) | `qa/manual/screens/M06/triage/t008c-end-early-no-confirm.png` |
| M06-G-001 | M06 | ETQAN-QA-216 (found by Agent 2 at the gate: expanded calendar names, same class as ETQAN-QA-209, outside its scope) | P3 | RTL | yes | OPEN | `qa/manual/screens/M06/triage/t020-calendar-name-bidi-wrap.png` |
| M06-F-024 | M06 | ETQAN-QA-217 (same pattern as ETQAN-QA-205, which fixed Stop/End early only; delete of a pause and of a stopped slot still unconfirmed) | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M06/triage/t023e-pause-deleted-no-confirm.png` |
| M06-F-025 | M06 | ETQAN-QA-218 (same class as ETQAN-QA-209/216; components SchedulesList + SessionsList not covered by them) | P3 | RTL | yes | OPEN | `qa/manual/screens/M06/triage/t021-weekly-schedules-names.png`, `t022-sessions-list-names.png` |
| M03-F-001 | M03 | ETQAN-QA-100 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M03/triage/t001-admin-home-ar.png` |
| M03-F-002 | M03 | ETQAN-QA-101 | P4 | UI-layout | no | OPEN | `qa/manual/screens/M03/triage/t009-admin-home-tiles-en.png` |
| M03-F-003 | M03 | ETQAN-QA-102 (bidi/format only; Arabic text in EN UI is by design: notifications.md renders in recipient's preferred_language, qa-admin = ar) | P3 | RTL | yes | REOPENED | `qa/manual/screens/M03/triage/t006-notifications-page-en.png` |
| M03-F-004 | M03 | ETQAN-QA-103 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M03/triage/t002-bell-panel-ar.png` |
| M03-F-005 | M03 | not a bug: Spanish is the opt-in `spanish` switch; es catalogue is a documented subset with per-key English fallback (academy-settings.md Languages; B9d L-1/L-2) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M03/M03-F-005-spanish-half-english.png` |
| M03-F-006 | M03 | ETQAN-QA-104 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M03/triage/t003-account-menu-ar.png` |
| M03-F-007 | M03 | dup of ETQAN-QA-104 (time stamp scrambled by the LTR panel); body part in ETQAN-QA-102 | - | RTL | - | DUP | `qa/manual/screens/M03/triage/t002-bell-panel-ar.png` |
| M03-F-008 | M03 | ETQAN-QA-105 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M03/triage/t004-404-ar.png` |
| M03-F-009 | M03 | ETQAN-QA-106 | P3 | functional | no | OPEN | `qa/manual/screens/M03/triage/t005-missing-student-ar.png` |
| M03-F-010 | M03 | ETQAN-QA-107 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M03/triage/t010-staff-nocode-home-ar.png` |
| M03-F-011 | M03 | ETQAN-QA-108 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M03/triage/t010-staff-nocode-home-ar.png` |
| M03-F-012 | M03 | ETQAN-QA-109 | P3 | permission | yes | VERIFIED | `qa/manual/screens/M03/triage/t011-codes-family-link-ar.png` |
| M03-F-013 | M03 | not a bug: documented intent, PermissionGate.tsx (Plan 12a §6.1) "the layouts' requireOffice has already sent teachers, students and parents home"; access is blocked, server refuses data | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M03/triage/t012-teacher-forbidden-silent-home-ar.png` |
| M03-F-014 | M03 | ETQAN-QA-110 (unlabelled selects; "I'm in" on past sessions is by design, ruling P10 server decides) | P3 | a11y | yes | VERIFIED | `qa/manual/screens/M03/triage/t013-maryam-home-en.png` |
| M03-F-015 | M03 | ETQAN-QA-111 (related to ETQAN-QA-060 follow-up) | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M03/triage/t014-maryam-home-ar.png` |
| M03-F-016 | M03 | ETQAN-QA-112 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M03/triage/t015-student-home-ar.png` |
| M03-F-017 | M03 | ETQAN-QA-113 | P3 | translation | yes | VERIFIED | `qa/manual/screens/M03/triage/t015-student-home-ar.png` |
| M03-F-018 | M03 | ETQAN-QA-114 | P3 | functional | no | OPEN | `qa/manual/screens/M03/triage/t020-502-shows-login-ar.png` |
| M03-F-019 | M03 | ETQAN-QA-115 | P3 | copy | yes | REOPENED | `qa/manual/screens/M03/triage/t018-parent-home-en.png` |
| M03-F-020 | M03 | ETQAN-QA-116 | P3 | functional | yes | VERIFIED | `qa/manual/screens/M03/triage/t019-qaother-home-ar.png` |
| M03-F-021 | M03 | ETQAN-QA-117 | P2 | mobile | no | VERIFIED | `qa/manual/screens/M03/triage/t016-mobile-drawer-admin-ar.png` |
| M03-F-022 | M03 | ETQAN-QA-118 | P3 | mobile | no | OPEN | `qa/manual/screens/M03/triage/t017-mobile-teacher-table-en.png` |
| M03-F-023 | M03 | ETQAN-QA-119 | P4 | UI-layout | no | OPEN | `qa/manual/screens/M03/triage/t008-student-detail-title-en.png` |
| M03-F-024 | M03 | ETQAN-QA-120 (regression of the QA-111/112 bidiName FSI isolation, EN UI) | P3 | RTL | yes | OPEN | `qa/manual/screens/M03/triage/t021-maryam-home-en-name-order.png` |
| M03-F-025 | M03 | dup of ETQAN-QA-115 (in the original F-019 list; fix incomplete) → QA-115 REOPENED | P3 | copy | yes | REOPENED | `qa/manual/screens/M03/triage/t022-parent-rate-wording-ar.png` |
| M03-F-026 | M03 | ETQAN-QA-121 | P4 | mobile | no | OPEN | `qa/manual/screens/M03/triage/t023-mobile-parent-invoices-badge-en.png` |
| M04-F-001 | M04 | ETQAN-QA-150 | P3 | UI-layout | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t001-students-list-ar.png` |
| M04-F-002 | M04 | ETQAN-QA-151 | P2 | functional | no | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t002-search-no-hamza-empty.png` |
| M04-F-003 | M04 | ETQAN-QA-152 | P3 | copy | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t002-search-no-hamza-empty.png` |
| M04-F-004 | M04 | ETQAN-QA-153 (related ETQAN-QA-060/111/209, other components) | P3 | RTL | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t001-students-list-ar.png` |
| M04-F-005 | M04 | dup of ETQAN-QA-060 (VERIFIED fix): XP `-5` now reads "-5" in the AR form (input unicode-bidi plaintext) | - | - | - | CLOSED (dup) | `qa/manual/screens/M04/triage/t005-new-student-xp.png` |
| M04-F-006 | M04 | ETQAN-QA-154 | P3 | translation | no | OPEN | `qa/manual/screens/M04/triage/t005-new-student-xp.png` |
| M04-F-007 | M04 | dup of ETQAN-QA-119 (M03: generic detail title "الطالب", no breadcrumb); the missing overview/links to subscriptions is a feature request, not filed | - | - | - | CLOSED (dup) | `qa/manual/screens/M04/triage/t007-student-detail-full.png` |
| M04-F-008 | M04 | ETQAN-QA-155 | P3 | copy | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t007-student-detail-full.png` |
| M04-F-009 | M04 | ETQAN-QA-156 | P3 | copy | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t007-student-detail-full.png` |
| M04-F-010 | M04 | ETQAN-QA-157 | P3 | translation | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t010-dup-email-english.png` |
| M04-F-011 | M04 | ETQAN-QA-158 | P3 | UI-layout | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t011-dup-email-viewport.png` |
| M04-F-012 | M04 | ETQAN-QA-159 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M04/triage/t012-249-deactivated-no-confirm.png` |
| M04-F-013 | M04 | ETQAN-QA-160 | P3 | UI-layout | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t012-249-deactivated-no-confirm.png` |
| M04-F-014 | M04 | ETQAN-QA-161 | P3 | translation | no | OPEN | `qa/manual/screens/M04/triage/t014-csv-from-ar.png` |
| M04-F-015 | M04 | dup of ETQAN-QA-206 (M06 filed the same "End the window after it starts." message); reproduced, 400 PUT schedule/availability/251/ | - | - | - | CLOSED (dup) | `qa/manual/screens/M04/triage/t015-availability-english-error.png` |
| M04-F-016 | M04 | not a bug: not reproducible. The teacher page's "العقود" button links to `/people/contracts?teacher=251` and the page opens filtered to that teacher (route unchanged since 2026-10-09); the unfiltered page is the sidebar "العقود" link | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M04/triage/t016-teacher-contracts-link.png` |
| M04-F-017 | M04 | ETQAN-QA-162 | P4 | UI-layout | no | OPEN | `qa/manual/screens/M04/triage/t017-availability-week.png` |
| M04-F-018 | M04 | ETQAN-QA-163 | P3 | RTL | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t016-teacher-contracts-link.png` |
| M04-F-019 | M04 | dup of ETQAN-QA-157 (same root cause as F-010: untranslated server text; filed together) | P3 | translation | yes | CLOSED (dup) | `qa/manual/screens/M04/triage/t019-contract-filetype-english.png` |
| M04-F-020 | M04 | ETQAN-QA-164 | P3 | functional | no | OPEN | `qa/manual/screens/M04/triage/t020-family-edit-payer-blank.png` |
| M04-F-021 | M04 | ETQAN-QA-165 | P3 | UI-layout | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t020-family-edit-payer-blank.png` |
| M04-F-022 | M04 | ETQAN-QA-166 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M04/triage/t023-bulk-bar-preselected.png` |
| M04-F-023 | M04 | ETQAN-QA-167 | P3 | functional | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t023-bulk-bar-preselected.png` |
| M04-F-024 | M04 | ETQAN-QA-168 (likely side effect of the ETQAN-QA-060 input fix) | P3 | RTL | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t023-bulk-bar-preselected.png` |
| M04-F-025 | M04 | ETQAN-QA-169 | P3 | translation | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t025-admins-invite-supervisor.png` |
| M04-F-026 | M04 | ETQAN-QA-170 | P3 | RTL | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/triage/t026-groups-latin-comma.png` |
| M04-F-027 | M04 | ETQAN-QA-171 | P3 | functional | no | OPEN | `qa/manual/screens/M04/triage/t027-registration-review.png` |
| M04-F-028 | M04 | ETQAN-QA-172 | P3 | copy | yes | VERIFIED (gate 2026-10-27) | `qa/manual/screens/M04/M04-F-028-verify-says-can-sign-in-while-pending.png` |
| M04-F-029 | M04 | dup of ETQAN-QA-109 (M03: family link shown to staff who can't open families); reproduced with qa-staff-codes on student 248 → families/16 no-permission | - | - | - | CLOSED (dup) | `qa/manual/screens/M04/triage/t029b-staffcodes-family-forbidden.png` |
| M04-F-030 | M04 | ETQAN-QA-173 | P3 | mobile | no | OPEN | `qa/manual/screens/M04/triage/t030b-mobile-table.png` |
| M04-F-031 | M04 | ETQAN-QA-174 | P3 | functional | no | OPEN | `qa/manual/screens/M04/triage/t031-unsaved-form-lost.png` |
| M04-F-032 | M04 | ETQAN-QA-175 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M04/triage/t032-email-hint-under-tz.png` |
| M04-F-033 | M04 | ETQAN-QA-176 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M04/triage/t033-retired-family-actions-wrap.png` |
| M04-F-034 | M04 | ETQAN-QA-177 | P4 | UI-layout | yes (trivial) | OPEN | `qa/manual/screens/M04/triage/t034-readonly-student-double-gap.png` |
| M04-F-035 | M04 | ETQAN-QA-178 | P4 | UI-layout | yes (trivial) | OPEN | `qa/manual/screens/M04/triage/t035-parents-invite-pending-wraps.png` |
| M14-F-001 | M14 | ETQAN-QA-400 | P3 | functional | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t003-im-in-future.png` |
| M14-F-002 | M14 | ETQAN-QA-401 | P3 | UI-layout | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t006-report-dialog.png` |
| M14-F-003 | M14 | ETQAN-QA-402 | P3 | copy | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t001-home-ar.png` |
| M14-F-004 | M14 | ETQAN-QA-403 | P3 | translation | no | OPEN | `qa/manual/screens/M14/triage/t009-print.png` |
| M14-F-005 | M14 | ETQAN-QA-404 | P3 | functional | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t014-withdraw-arabic-digit.png` |
| M14-F-006 | M14 | ETQAN-QA-405 | P3 | copy | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t014-withdraw-arabic-digit.png` |
| M14-F-007 | M14 | ETQAN-QA-406 | P3 | copy | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t015-cancel-vs-cancel.png` |
| M14-F-008 | M14 | ETQAN-QA-407 | P3 | translation | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t019-overlap-english.png` |
| M14-F-009 | M14 | ETQAN-QA-408 | P3 | UI-layout | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t018-overlap-offscreen.png` |
| M14-F-010 | M14 | ETQAN-QA-409 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M14/triage/t036-maryam-home.png` |
| M14-F-011 | M14 | not a bug: sessions 435/409/445 were created after they had ended (created 22:01/21:22/22:06 Cairo for 15:00/18:00/20:00); `provision_meetings` fills only sessions not yet ended, from now−4 h to now+24 h (meetings.md). Tomorrow's sessions have Jitsi links. Test-data artefact | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M14/triage/t002-week.png` |
| M14-F-012 | M14 | ETQAN-QA-410 | P4 | copy | yes | OPEN | `qa/manual/screens/M14/triage/t013-balance.png` |
| M14-F-013 | M14 | ETQAN-QA-411 | P4 | UI-layout | yes | OPEN | `qa/manual/screens/M14/triage/t007-reports.png` |
| M14-F-014 | M14 | ETQAN-QA-412 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M14/triage/t005-history.png` |
| M14-F-015 | M14 | ETQAN-QA-413 | P3 | UI-layout | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t022-hw-instructions-english.png` |
| M14-F-016 | M14 | ETQAN-QA-414 | P4 | UI-layout | yes | OPEN | `qa/manual/screens/M14/triage/t028-hw-delete-confirm.png` |
| M14-F-017 | M14 | ETQAN-QA-415 | P3 | functional | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t027-hw-answered-not-flagged.png` |
| M14-F-018 | M14 | ETQAN-QA-416 | P3 | copy | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t030-levels-empty-picker.png` |
| M14-F-019 | M14 | ETQAN-QA-417 | P3 | copy | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t031-honour.png` |
| M14-F-020 | M14 | ETQAN-QA-418 | P3 | functional | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t029-hw-delete-answered-409.png` |
| M14-F-021 | M14 | ETQAN-QA-419 | P3 | translation | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t022-hw-instructions-english.png` |
| M14-F-022 | M14 | ETQAN-QA-420 | P3 | UI-layout | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t009-print.png` |
| M14-F-023 | M14 | ETQAN-QA-421 | P4 | UI-layout | yes | OPEN | `qa/manual/screens/M14/triage/t012-confirm-receipt-red.png` |
| M14-F-024 | M14 | ETQAN-QA-422 | P3 | UI-layout | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t011-payslips-list-en.png` |
| M14-F-025 | M14 | not a bug: B2b spec B-8 / §7 — a teacher's postponement is checked only for the teacher's own clashes (409 `teacher_busy`) and shows nothing else; availability warnings are for office scheduling (scheduling-tools.md). The availability page line refers to the office's scheduling | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M14/M14-F-025-postpone-outside-availability-no-warning.png` |
| M14-F-026 | M14 | ETQAN-QA-423 | P4 | copy | yes | OPEN | `qa/manual/screens/M14/triage/t004-disposal-row.png` |
| M14-F-027 | M14 | dup of M14-F-004 → ETQAN-QA-403 (same root: `describe_session` stores the line text in the generation language) | P3 | translation | no | OPEN (dup) | `qa/manual/screens/M14/triage/t010-payslip-en.png` |
| M14-F-028 | M14 | ETQAN-QA-424 | P4 | UI-layout | yes | OPEN | `qa/manual/screens/M14/triage/t008-payslip-ar.png` |
| M14-F-029 | M14 | ETQAN-QA-425 | P3 | mobile | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t035-m-availability.png` |
| M14-F-030 | M14 | ETQAN-QA-426 | P3 | mobile | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t032-m-homework.png` |
| M14-F-031 | M14 | ETQAN-QA-427 | P3 | mobile | yes | VERIFIED (gate 1) | `qa/manual/screens/M14/triage/t034-m-payslip.png` |
| M14-F-032 | M14 | ETQAN-QA-428 | P3 | mobile | no | OPEN | `qa/manual/screens/M14/triage/t033-m-levels.png` |
| M14-F-033 | M14 | ETQAN-QA-429 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M14/triage/t040-week-hints.png` |
| M14-F-034 | M14 | ETQAN-QA-430 | P3 | mobile | no | OPEN | `qa/manual/screens/M14/triage/t042-m-homework-open-offscreen.png` |
| M14-F-035 | M14 | dup of ETQAN-QA-272 (M07, open P4: ended session with no link says "لا يوجد رابط بعد" in the teacher's حصصي history) | P4 | copy | yes | OPEN (via 272) | `qa/manual/screens/M14/triage/t041-history-no-link-yet.png` |

| M09-F-001 | M09 | ETQAN-QA-350 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M09/triage/T-F001-number-wraps.png` |
| M09-F-002 | M09 | ETQAN-QA-351 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M09/triage/T-F002-notes-unlabelled.png` |
| M09-F-003 | M09 | dup of ETQAN-QA-420 (print page has no way back; same `/app/payslips/<id>/print` for office and teacher) | P3 | UI-layout | yes | OPEN (via 420) | `qa/manual/screens/M09/triage/T-F003-print-same-tab.png` |
| M09-F-004 | M09 | ETQAN-QA-352 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M09/triage/T-F004-rates-top.png` |
| M09-F-005 | M09 | ETQAN-QA-353 | P3 | RTL | yes | OPEN | `qa/manual/screens/M09/triage/T-F007-month-field.png` |
| M09-F-006 | M09 | dup of ETQAN-QA-404 (Arabic-Indic digits in money input). Fix must cover every payroll money field (rate, fixed salary, bulk, student rate, adjustment), not only WithdrawalDialog | P3 | functional | yes | OPEN (via 404) | `qa/manual/screens/M09/triage/T-F006-arabic-digits.png` |
| M09-F-007 | M09 | ETQAN-QA-354 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M09/triage/T-F007-month-field.png` |
| M09-F-008 | M09 | ETQAN-QA-355 | P3 | functional | no | OPEN | `qa/manual/screens/M09/triage/T-F014-negative-net.png` |
| M09-F-009 | M09 | ETQAN-QA-356 | P3 | copy | yes | OPEN | `qa/manual/screens/M09/triage/T-F013-oct-generate.png` |
| M09-F-010 | M09 | ETQAN-QA-357 | P3 | functional | no | OPEN | `qa/manual/screens/M09/triage/T-F009-F010-generate-sep.png` |
| M09-F-011 | M09 | ETQAN-QA-358 | P3 | translation | yes | OPEN | `qa/manual/screens/M09/triage/T-F011c-withdrawal-pay-english.png` |
| M09-F-012 | M09 | ETQAN-QA-359 | P3 | functional | no | OPEN | `qa/manual/screens/M09/triage/T-F012-adjustments.png` |
| M09-F-013 | M09 | not a bug: payroll.md Building step 6 puts every pending adjustment with `effective_on` ≤ month end into each draft; the adjustment dialog says it is used by the next issued payslip; issuing consumes it once (drafts are previews) | — | — | — | CLOSED | `qa/manual/screens/M09/triage/T-F013-oct-generate.png` |
| M09-F-014 | M09 | ETQAN-QA-360 | P3 | RTL | yes | OPEN | `qa/manual/screens/M09/triage/T-F015-projection-total.png` |
| M09-F-015 | M09 | ETQAN-QA-361 | P3 | data | no | OPEN | `qa/manual/screens/M09/triage/T-F015-projection-total.png` |
| M09-F-016 | M09 | ETQAN-QA-362 | P4 | UI-layout | no | OPEN | `qa/manual/screens/M09/triage/T-F016-F020-F021-withdrawals.png` |
| M09-F-017 | M09 | dup of ETQAN-QA-410 (My balance has no explanation; payroll.md: balance is derived, no ledger — a credit statement would be a proposal) | P4 | copy | — | OPEN (via 410) | `qa/manual/screens/M09/triage/T-F017-balance-no-history.png` |
| M09-F-018 | M09 | dup of ETQAN-QA-405 (teacher withdrawal dialog in third person) | P3 | copy | yes | OPEN (via 405) | `qa/manual/screens/M09/triage/T-F018-teacher-dialog-third-person.png` |
| M09-F-019 | M09 | dup of ETQAN-QA-406 ("إلغاء" vs "إلغاء هذا الطلب") | P3 | copy | yes | OPEN (via 406) | `qa/manual/screens/M09/triage/T-F019-cancel-vs-cancel.png` |
| M09-F-020 | M09 | ETQAN-QA-363 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M09/triage/T-F020b-reject-green.png` |
| M09-F-021 | M09 | ETQAN-QA-364 | P3 | functional | yes | OPEN | `qa/manual/screens/M09/triage/T-F017-balance-no-history.png` |
| M09-F-022 | M09 | ETQAN-QA-365 | P3 | functional | no | OPEN | `qa/manual/screens/M09/triage/T-F022-not-found-spinner.png` |
| M09-F-023 | M09 | ETQAN-QA-366 | P3 | translation | yes | OPEN | `qa/manual/screens/M09/triage/T-F023-en-paid-so-far.png` |
| M09-F-024 | M09 | ETQAN-QA-367 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M09/triage/T-F024-amount-empty-parens.png` |
| M09-F-025 | M09 | ETQAN-QA-368 | P3 | copy | yes | OPEN | `qa/manual/screens/M09/triage/T-F025-expense-title.png` |
| M09-F-026 | M09 | dup of ETQAN-QA-427 (phone payslip line runs together; same `PayslipBody` for office) | P3 | mobile | yes | OPEN (via 427) | `qa/manual/screens/M09/triage/T-F026-mobile-session-lines.png` |
| M09-F-027 | M09 | ETQAN-QA-369 | P3 | mobile | no | OPEN | `qa/manual/screens/M09/triage/T-F027b-mobile-withdrawals.png` |
| M09-F-028 | M09 | ETQAN-QA-370 | P3 | copy | yes | OPEN | `qa/manual/screens/M09/triage/T-F028-bulk-dialog-copy.png` |
| M09-F-029 | M09 | ETQAN-QA-371 | P3 | functional | no | OPEN | `qa/manual/screens/M09/s069.png` |
| M09-F-030 | M09 | ETQAN-QA-372 | P3 | functional | no | OPEN | `qa/manual/screens/M09/triage/T-F030-filter-empty.png` |
| M09-F-031 | M09 | dup of ETQAN-QA-161 (CSV exported in English). "(minor units)" columns are the project-wide labelled CSV convention (billing, finance, scheduling…); the filter part did not reproduce: the link carries `status`/`teacher` | P3 | translation | no | OPEN (via 161) | `qa/manual/screens/M09/triage/T-F030-filter-empty.png` |
| M09-F-032 | M09 | ETQAN-QA-373 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M09/triage/T-F032-edit-adjustment.png` |
| M09-F-033 | M09 | not a bug: glyph positions on PAY-000007 (AR) give currency x49–64, minus 76, digits 82–108 — the same layout as positives (18.00: currency 64, digits 76) and the verified ETQAN-QA-360 output; the LRI-isolated "-6.00" keeps its minus directly left of the digits, as any left-to-right number does. Same `Money` component as the PAY-000042 adjustment line Agent 1 compared it with | — | — | — | CLOSED | `qa/manual/screens/M09/triage/T-F033-F034-ar-el.png`, `qa/manual/screens/M09/triage/T-F033-amount-zoom.png` |
| M09-F-034 | M09 | dup of ETQAN-QA-403 (payslip line text frozen at generation: ISO date + academy language; `build.py` MISSING_REPORT is the same stored-string design). AR date shown "02-09-2026" after the Arabic label; EN line stays Arabic and scrambled — both go with 403's structured-fields proposal | P3 | translation | no | OPEN (via 403) | `qa/manual/screens/M09/triage/T-F033-F034-ar-el.png`, `qa/manual/screens/M09/triage/T-F034-en-line.png` |
| M09-F-035 | M09 | ETQAN-QA-374 (also the approve dialog) | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M09/triage/T-F035-pay-dialog.png`, `qa/manual/screens/M09/triage/T-F035b-cancel-dialog.png` |
| M09-F-036 | M09 | ETQAN-QA-375 | P4 | UI-layout | no | OPEN | `qa/manual/screens/M09/triage/T-F036-card.png` |
| M07-F-001 | M07 | ETQAN-QA-250 (empty state only; links are provisioned by design up to 24 h ahead, today's ones were generated after they ended) | P3 | copy | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t001-link-blank-362.png` |
| M07-F-002 | M07 | ETQAN-QA-251 | P3 | UI | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t002-mark-no-toast.png` |
| M07-F-003 | M07 | ETQAN-QA-252 | P3 | functional | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t003-undo-one-click-activity.png` |
| M07-F-004 | M07 | ETQAN-QA-253 (family of QA-104/207, different component) | P3 | RTL | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t003-undo-one-click-activity.png` |
| M07-F-005 | M07 | ETQAN-QA-254 (related QA-212) | P3 | UI-layout | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t005-postpone-dialog-no-cancel.png` |
| M07-F-006 | M07 | not a bug: B2b B-1/B-2 allow the teacher's in/out on scheduled/completed sessions any time after the start; times are a record only (pay and consumption use `minutes`) and the office can correct them. Proposal: refuse or warn on stamps long after the end | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M07/triage/t011-session-409-en-full.png` |
| M07-F-007 | M07 | ETQAN-QA-255 | P3 | functional | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t007c-im-in-future-refused.png` |
| M07-F-008 | M07 | ETQAN-QA-256 | P4 | copy | yes | OPEN | `qa/manual/screens/M07/triage/t008-today-generated-chip.png` |
| M07-F-009 | M07 | ETQAN-QA-257 (class of QA-157/206, new message) | P3 | translation | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t009-postpone-english-error.png` |
| M07-F-010 | M07 | ETQAN-QA-258 | P4 | UI-layout | yes | OPEN | `qa/manual/screens/M07/triage/t011-session-409-en-full.png` |
| M07-F-011 | M07 | ETQAN-QA-259 | P3 | functional | no | OPEN | `qa/manual/screens/M07/triage/t011-session-409-en-full.png` |
| M07-F-012 | M07 | ETQAN-QA-260 (related QA-200) | P3 | UI | no | OPEN | `qa/manual/screens/M07/triage/t012-add-session-dialog.png` |
| M07-F-013 | M07 | ETQAN-QA-261 | P4 | copy | yes | OPEN | `qa/manual/screens/M07/triage/t012-add-session-dialog.png` |
| M07-F-014 | M07 | ETQAN-QA-262 | P3 | UI | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t014-archive-one-click.png` |
| M07-F-015 | M07 | ETQAN-QA-263 | P4 | copy | yes | OPEN | `qa/manual/screens/M07/triage/t009-postpone-english-error.png` |
| M07-F-016 | M07 | not a bug: the page has a Pager ("صفحة 1 من 4", السابق/التالي) under the 25 rows (`MissingReports.tsx`, PAGE_SIZE 25, unchanged since 7 Oct); all 76 are reachable. Teacher "كل الحصص المكتملة لها تقارير" is right per the 24 h rule (sessions.md) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M07/triage/t016-missing-reports-25.png` |
| M07-F-017 | M07 | not a bug: B2a spec line 145 "the office alone sees … disposal_reason"; there is no teacher session page by design (sessions.md: teacher uses `teaching.sessions.tsx`). Proposal: show notes to the teacher | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M07/M07-F-017-teacher-no-notes.png` |
| M07-F-018 | M07 | ETQAN-QA-264 | P3 | UI | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t018-level-empty-dropdown.png` |
| M07-F-019 | M07 | ETQAN-QA-265 | P3 | functional | no | OPEN | `qa/manual/screens/M07/triage/t019-upgrade-double-submit-500.png` |
| M07-F-020 | M07 | not a bug: "Choose FileNo file chosen" is headless Chromium's native file input (already ruled not filed in the register, line ~3054); a file on a text homework is allowed (homework-content.md: text kind needs instructions, file optional) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M07/triage/t020-file-input-english.png` |
| M07-F-021 | M07 | ETQAN-QA-266 (no session shown) + ETQAN-QA-267 (subtitle grammar, empty cell) | P3 / P4 | functional / copy | no / yes | OPEN | `qa/manual/screens/M07/triage/t020-file-input-english.png` |
| M07-F-022 | M07 | ETQAN-QA-268 (pattern of QA-118/173, different page) | P3 | mobile | no | OPEN | `qa/manual/screens/M07/triage/t022-mobile-today.png` |
| M07-F-023 | M07 | ETQAN-QA-269 (unlabelled note). "465# الحصة" part not a bug: correct RTL order | P3 | UI-layout | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t023-session-ref-mirrored.png` |
| M07-F-024 | M07 | ETQAN-QA-270 | P3 | UI | yes | VERIFIED (gate) | `qa/manual/screens/M07/triage/t024-simple-view.png` |
| M07-F-025 | M07 | ETQAN-QA-271 (family of QA-161) | P3 | translation | no | OPEN | `qa/manual/screens/M07/triage/t025-sessions-csv-ar.txt` |
| M07-gate | M07 | ETQAN-QA-272 (found by Agent 2 at the gate: wording of two cycle-1 strings) | P4 | copy | yes | OPEN | `qa/manual/screens/M07/fix/g252a-undo-dialog.png` |
| M07-F-026 | M07 | ETQAN-QA-273 (family of QA-202/QA-371, different dialog) | P3 | functional | no | OPEN | `qa/manual/screens/M07/triage/t026-extra-student-list.png` |
| M07-F-027 | M07 | ETQAN-QA-274 | P4 | UI | yes | OPEN | `qa/manual/screens/M07/triage/t027-extra-minutes-no-star.png` |
| M07-F-028 | M07 | ETQAN-QA-275 (gap left by the QA-250 fix; fix with QA-272) | P4 | UI | yes | OPEN | `qa/manual/screens/M07/triage/t028-cancelled-link-blank.png` |
| M07-F-029 | M07 | ETQAN-QA-276 | P3 | UI | yes | OPEN | `qa/manual/screens/M07/triage/t029-simple-disabled-no-hint.png` |
| M08-F-001 | M08 | ETQAN-QA-300 | P3 | copy | yes | OPEN | VERIFIED |
| M08-F-002 | M08 | ETQAN-QA-301 (also covers the red buttons of M08-F-007; class of QA-421) | P3 | UI | yes | OPEN | VERIFIED |
| M08-F-003 | M08 | ETQAN-QA-302 (no-way-back part: pattern of QA-420) | P3 | UI | yes | OPEN | VERIFIED |
| M08-F-004 | M08 | ETQAN-QA-303 | P3 | translation | yes | OPEN | VERIFIED |
| M08-F-005 | M08 | ETQAN-QA-304 | P3 | functional | no | OPEN | `qa/manual/screens/M08/triage/F-005-repro.png` |
| M08-F-006 | M08 | ETQAN-QA-305 (reference) + ETQAN-QA-306 (empty state "yet", class of QA-152) | P3 / P3 | functional / copy | no / yes | OPEN | 305 OPEN (not in fix scope) / 306 VERIFIED |
| M08-F-007 | M08 | ETQAN-QA-307 (layout, USD symbol); red buttons in QA-301 | P3 | UI-layout | yes | OPEN | VERIFIED |
| M08-F-008 | M08 | ETQAN-QA-308 | P3 | translation | yes | OPEN | VERIFIED |
| M08-F-009 | M08 | ETQAN-QA-309 | P3 | functional | no | OPEN | `qa/manual/screens/M08/triage/F-009-repro-decline.png` |
| M08-F-010 | M08 | ETQAN-QA-310 (class of QA-212/401/254) | P3 | UI | yes | OPEN | VERIFIED |
| M08-F-011 | M08 | ETQAN-QA-311 | P3 | RTL | yes | OPEN | VERIFIED |
| M08-F-012 | M08 | dup of ETQAN-QA-311 (same signed-amount bidi problem, filed together) | P3 | RTL | yes | OPEN (via 311) | VERIFIED (via 311) |
| M08-F-013 | M08 | ETQAN-QA-312 (related QA-100) | P3 | RTL | yes | OPEN | VERIFIED |
| M08-F-014 | M08 | ETQAN-QA-313 | P3 | translation | yes | OPEN | VERIFIED |
| M08-F-015 | M08 | not a bug: online-payments.md "money that still arrives on a closed link becomes attention"; DB shows checkout d20b6538 `attention=link_closed`, `applied=false`, resolved 2026-10-19 00:52 by admin (Tier 1 test), so no record and nothing open is correct. Empty-state copy part filed in ETQAN-QA-306. Proposal: show a "resolved" mark on such rows | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M08/triage/F-014-repro.png` |
| M08-F-016 | M08 | ETQAN-QA-314 (subscription-link part: pattern of QA-109) | P2 | permission | no | OPEN | VERIFIED (dashboard) + API PROPOSAL-accepted |
| M08-F-017 | M08 | ETQAN-QA-315 (family of QA-173, different page) | P3 | mobile | no | OPEN | `qa/manual/screens/M08/triage/F-017-repro-list.png` |
| M08-F-018 | M08 | ETQAN-QA-316 | P3 | UI | yes | OPEN | VERIFIED |
| M08-F-019 | M08 | ETQAN-QA-317 | P4 | UI-layout | yes | OPEN | `qa/manual/screens/M08/triage/F-019-repro.png` |
| M08-F-020 | M08 | ETQAN-QA-318 (class of QA-206/157/358/257, new screen) | P3 | translation | yes | OPEN | `qa/manual/screens/M08/triage/F-020-repro.png` |
| M08-F-021 | M08 | ETQAN-QA-319 | P3 | UI/copy | yes | OPEN | `qa/manual/screens/M08/triage/F-021-repro.png` |
| M08-F-022 | M08 | ETQAN-QA-320 | P4 | copy | yes | OPEN | `qa/manual/screens/M08/triage/F-022-repro.png` |
| M08-F-023 | M08 | ETQAN-QA-321 | P3 | RTL | yes | OPEN | `qa/manual/screens/M08/triage/F-023-repro.png` |
| M12-F-001 | M12 | ETQAN-QA-500 (same family as ETQAN-QA-048, which fixed only identity schemas) | P3 | translation | yes | OPEN | `qa/manual/screens/M12/triage/t001-colour-error.png` |
| M12-F-002 | M12 | ETQAN-QA-501 | P3 | translation | yes | OPEN | `qa/manual/screens/M12/triage/t001-colour-error.png` |
| M12-F-003 | M12 | ETQAN-QA-502 | P4 | UI-layout | no | OPEN | `qa/manual/screens/M12/triage/t001-colour-error.png` |
| M12-F-004 | M12 | ETQAN-QA-503 | P4 | copy | no | OPEN | `qa/manual/screens/M12/triage/t004-features-built.png` |
| M12-F-005 | M12 | ETQAN-QA-504 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M12/triage/t005-role-editor.png` |
| M12-F-006 | M12 | ETQAN-QA-505 (permission behaviour by design: view = one record, view_any = list; missing explanation is the bug) | P3 | copy | yes | OPEN | `qa/manual/screens/M12/triage/t006-teacher-view-no-access.png` |
| M12-F-007 | M12 | ETQAN-QA-506 | P3 | translation | yes | OPEN | `qa/manual/screens/M12/triage/t007-escalation-after-save.png` |
| M12-F-008 | M12 | ETQAN-QA-507 (same pattern as ETQAN-QA-160/165/205/217, other screen) | P3 | functional | yes | OPEN | `qa/manual/screens/M12/triage/t008-retire-no-confirm.png` |
| M12-F-009 | M12 | ETQAN-QA-508 | P3 | copy | yes | OPEN | `qa/manual/screens/M12/triage/t009-roles-list.png` |
| M12-F-010 | M12 | ETQAN-QA-509 | P3 | functional | no | OPEN | `qa/manual/screens/M12/triage/t010-google-half-saved.png` |
| M12-F-011 | M12 | not a bug: sign-in.md defines `/settings/sign-in` as the Google card only; 2FA, quick login, phone login and code reset are Etqan-managed switches with no academy policy in the spec (feature request) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M12/triage/t011-signin-page.png` |
| M12-F-012 | M12 | not a bug: sign-in.md defines the security log as `SecurityEvent` rows (quick login, sign-in links, 2FA off), matching the page subtitle; role/settings auditing and filters are feature requests | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M12/triage/t012-security-log.png` |
| M12-F-013 | M12 | ETQAN-QA-510 (English "Timed out."). Manual-only run list = not a bug: academy-settings.md, run_job is on demand only; the hourly lifecycle runs under scheduling.run_daily | P3 | translation | yes | OPEN | `qa/manual/screens/M12/triage/t013-system-status-timed-out.png` |
| M12-F-014 | M12 | ETQAN-QA-511 | P3 | RTL | yes | OPEN | `qa/manual/screens/M12/triage/t014-reg-code-layout.png` |
| M12-F-015 | M12 | ETQAN-QA-512 | P3 | functional | yes | OPEN | `qa/manual/screens/M12/triage/t015-tags-emoji-text.png` |
| M12-F-016 | M12 | ETQAN-QA-513 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M12/triage/t016-templates-no-gutter.png` |
| M12-F-017 | M12 | ETQAN-QA-514 | P3 | translation | yes | OPEN | `qa/manual/screens/M12/triage/t016-templates-no-gutter.png` |
| M12-F-018 | M12 | ETQAN-QA-515 (ISO time in the preview = ETQAN-QA-102 family, not re-filed) | P3 | translation | yes | OPEN | `qa/manual/screens/M12/triage/t018-template-error.png` |
| M12-F-019 | M12 | ETQAN-QA-516 | P3 | copy | no | OPEN | `qa/manual/screens/M12/triage/t019-integrations.png` |
| M12-F-020 | M12 | ETQAN-QA-517 | P3 | copy | no | OPEN | `qa/manual/screens/M12/triage/t020-etqan-billing.png` |
| M12-F-021 | M12 | not a bug: academy-settings.md says `default_language` stays ar/en (Spanish is a per-user UI language). Timezone list = ETQAN-QA-154 | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M12/triage/t021-default-language.png` |
| M12-F-022 | M12 | ETQAN-QA-518 (side effect of the verified ETQAN-QA-060 Input plaintext-bidi fix; typed values are fine, placeholder only) | P3 | RTL | yes | OPEN | `qa/manual/screens/M12/triage/fg022-whatsapp-field.png` |
| M10-F-001 | M10 | ETQAN-QA-600 (pattern of ETQAN-QA-254/401, new dialog) | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M10/triage/t001-new-chat-dialog.png` |
| M10-F-002 | M10 | ETQAN-QA-601 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M10/triage/t002-chat-thread.png` |
| M10-F-003 | M10 | ETQAN-QA-602 (delete itself by design, B5e; styling only) | P4 | UI-layout | no | OPEN | `qa/manual/screens/M10/triage/t002-chat-thread.png` |
| M10-F-004 | M10 | ETQAN-QA-603 | P3 | RTL | yes | OPEN | `qa/manual/screens/M10/triage/t002-chat-thread.png` |
| M10-F-005 | M10 | ETQAN-QA-604 (class of ETQAN-QA-060/153, chat surfaces not covered) | P3 | RTL | yes | OPEN | `qa/manual/screens/M10/triage/t002-chat-thread.png` |
| M10-F-006 | M10 | ETQAN-QA-605 (read counts by design; wording only) | P4 | copy | no | OPEN | `qa/manual/screens/M10/triage/t002-chat-thread.png` |
| M10-F-007 | M10 | dup of ETQAN-QA-604 (same root cause: message text has no own direction; EN side) | P3 | RTL | yes | OPEN | `qa/manual/screens/M10/triage/t007-en-chat.png` |
| M10-F-008 | M10 | ETQAN-QA-606 (code `supervisor` = staff by design, label wrong) | P3 | copy | yes | OPEN | `qa/manual/screens/M10/triage/t008-staff-supervisor.png` |
| M10-F-009 | M10 | ETQAN-QA-607 (pattern of ETQAN-QA-502, other screen) | P4 | UI-layout | no | OPEN | `qa/manual/screens/M10/triage/t009-010-group-dialog.png` |
| M10-F-010 | M10 | ETQAN-QA-608 (class of ETQAN-QA-157/206) | P3 | translation | yes | OPEN | `qa/manual/screens/M10/triage/t009-010-group-dialog.png` |
| M10-F-011 | M10 | not a bug: B5e/B5f define group header = name only; member list is office-only (`conversation_group.view`), groups office-managed; feature request | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M10/triage/t011-group-thread-student.png` |
| M10-F-012 | M10 | dup of ETQAN-QA-102 (its locale-date part was left proposal-level; ISO date + "(Africa/Cairo)" still in stored text — added as note there) | P3 | RTL | - | OPEN (QA-102) | `qa/manual/screens/M10/triage/t012-parent-notifications.png` |
| M10-F-013 | M10 | not a bug: notifications.md / `links.py:_session` send families to `/learning/sessions` by design — families have no session detail page; proposal: open at the past section | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M10/triage/t013-absence-link.png` |
| M10-F-014 | M10 | ETQAN-QA-609 | P3 | RTL | yes | OPEN | `qa/manual/screens/M10/triage/t014-absence-email.png` |
| M10-F-015 | M10 | dup of ETQAN-QA-513 (gutter now present in working tree, M12 fix) | - | - | - | see QA-513 | `qa/manual/screens/M10/triage/t015-templates-page.png` |
| M10-F-016 | M10 | dup of ETQAN-QA-514 (heading now "الحصص" in working tree) | - | - | - | see QA-514 | `qa/manual/screens/M10/triage/t015-templates-page.png` |
| M10-F-017 | M10 | ETQAN-QA-610 | P4 | UI-layout | no | OPEN | `qa/manual/screens/M10/triage/t017-template-dialog.png` |
| M10-F-018 | M10 | dup of ETQAN-QA-515 (error now Arabic in working tree) | - | - | - | see QA-515 | `qa/manual/screens/M10/triage/t018-placeholder-error.png` |
| M10-F-019 | M10 | not a bug: B5b C-7 keeps `email_error` hidden; the example row is `chat.unread`, in-app only by design (email `skipped`) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M10/triage/t019-log.png` |
| M10-F-020 | M10 | ETQAN-QA-611 (pattern of ETQAN-QA-152/306, new screen) | P3 | copy | yes | OPEN | `qa/manual/screens/M10/triage/t020-log-empty-filter.png` |
| M10-F-021 | M10 | ETQAN-QA-612 | P3 | copy | yes | OPEN | `qa/manual/screens/M10/triage/t021-024-broadcast-list.png` |
| M10-F-022 | M10 | ETQAN-QA-613 | P3 | RTL | yes | OPEN | `qa/manual/screens/M10/triage/t022-composer.png` |
| M10-F-023 | M10 | ETQAN-QA-614 (group name part only; recipient-count preview is a B5b non-goal) | P3 | copy | yes | OPEN | `qa/manual/screens/M10/triage/t023-confirm.png` |
| M10-F-024 | M10 | ETQAN-QA-615 | P4 | UI-layout | no | OPEN | `qa/manual/screens/M10/triage/t021-024-broadcast-list.png` |
| M10-F-025 | M10 | ETQAN-QA-616 (pattern of ETQAN-QA-253) | P3 | RTL | yes | OPEN | `qa/manual/screens/M10/triage/t025-026-detail.png` |
| M10-F-026 | M10 | ETQAN-QA-617 | P3 | RTL | yes | OPEN | `qa/manual/screens/M10/triage/t026-027-broadcast-email.png` |
| M10-F-027 | M10 | not a bug: email-whatsapp.md / B5b C-5 fix the title "رسالة جديدة"; subject field and broadcast templates are non-goals (feature request) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M10/triage/t026-027-broadcast-email.png` |
| M10-F-028 | M10 | not a bug: Plan 12a §6.1 (`PermissionGate.tsx`): `requireOffice` sends teachers/students/parents home by design; the no-permission page is for office staff | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M10/triage/t028-teacher-direct-url.png` |
| M10-F-029 | M10 | ETQAN-QA-618 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M10/triage/t029-settings-link.png` |
| M10-F-030 | M10 | ETQAN-QA-619 (column by design, B5c; missing hint) | P3 | copy | no | OPEN | `qa/manual/screens/M10/triage/t030-whatsapp-boxes.png` |
| M10-F-031 | M10 | ETQAN-QA-620 (residual of ETQAN-QA-104 on the phone) | P3 | mobile | yes | OPEN | `qa/manual/screens/M10/triage/t031-mobile-bell.png` |
| M10-F-032 | M10 | not a bug: chat.md moderation list shows "attachment counts" by design; office opening files is a feature request | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M10/triage/t032-moderation.png` |
| M10-F-033 | M10 | ETQAN-QA-621 (hiding the button by design, B5e; message missing) | P3 | copy | yes | OPEN | `qa/manual/screens/M10/triage/t033-student-cannot-start.png` |
| M10-F-034 | M10 | ETQAN-QA-622 (family of ETQAN-QA-054/251) | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M10/triage/t034-switch-silent.png` |
| M10-F-035 | M10 | ETQAN-QA-624 (residual of ETQAN-QA-617: bell/page body takes the title's direction) | P3 | RTL | yes | OPEN | `qa/manual/screens/M10/triage/fg035-bell-mobile.png` |
| M10-F-036 | M10 | ETQAN-QA-625 (residual of ETQAN-QA-608: participants sentence not mapped) | P3 | translation | yes | OPEN | `qa/manual/screens/M10/triage/fg036-group-no-participants.png` |
| M10-F-037 | M10 | ETQAN-QA-626 (empty thread has no empty-state line) | P4 | copy | no | OPEN | `qa/manual/screens/M10/triage/fg037-empty-group-thread.png` |
| M15-F-001 | M15 | ETQAN-QA-454 (family twin of ETQAN-QA-412; attendance IS shown once marked) | P3 | UI-layout | no | OPEN | `qa/manual/screens/M15/triage/t001-sessions-ar.png` |
| M15-F-002 | M15 | ETQAN-QA-455 (renew button not a bug: renewal is office-only, subscriptions.md §5; duplicate cards = ETQAN-QA-200) | P3 | copy | yes | VERIFIED | `qa/manual/screens/M15/triage/t002-subscriptions.png` |
| M15-F-003 | M15 | ETQAN-QA-450 | P2 | functional | no | VERIFIED | `qa/manual/screens/M15/triage/t005-inv144-print.png` |
| M15-F-004 | M15 | ETQAN-QA-469 (phone overflow = ETQAN-QA-315) | P4 | copy | no | OPEN | `qa/manual/screens/M15/triage/t004-inv144.png` |
| M15-F-005 | M15 | ETQAN-QA-453 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M15/triage/t003-invoices-list.png` |
| M15-F-006 | M15 | dup of ETQAN-QA-320 (same `vouchers.json` "done" string; not re-run, needs a fresh code and the invoice already holds its one discount) | - | - | - | CLOSED (dup) | `qa/manual/screens/M15/M15-F-006-toast-double-period.png` |
| M15-F-007 | M15 | not a bug: vouchers.md/billing.md record a discount as a `code` payment on the invoice (paid 720 + code 100 = 820, 680 left is correct, as M08 verified on QA-320); "SYS-XXXXX-XXXXX" is the documented display form of a typed code | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M15/triage/t006-inv143-ar.png` |
| M15-F-008 | M15 | ETQAN-QA-456 ("Cash" English). Blank adjustment details = not a bug: `wallet/api/payloads.py:entry_row` hides the office's reason from families on purpose | P3 | translation | no | OPEN | `qa/manual/screens/M15/triage/t008-wallet-ar.png` |
| M15-F-009 | M15 | ETQAN-QA-470 (pattern of ETQAN-QA-502 / M10-F-009) | P4 | UI-layout | no | OPEN | `qa/manual/screens/M15/triage/t011-homework-dialog.png` |
| M15-F-010 | M15 | ETQAN-QA-458 (student twin of ETQAN-QA-415; no due date by design, homework-content.md) | P3 | functional | yes | VERIFIED | `qa/manual/screens/M15/triage/t010-homework-list.png` |
| M15-F-011 | M15 | ETQAN-QA-459 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M15/triage/t014-review-double-toast.png` |
| M15-F-012 | M15 | ETQAN-QA-460 | P3 | functional | yes | VERIFIED | `qa/manual/screens/M15/triage/t013-review-long.png` |
| M15-F-013 | M15 | ETQAN-QA-461 (pattern of ETQAN-QA-052) | P3 | functional | yes | VERIFIED | `qa/manual/screens/M15/triage/t014-review-double-toast.png` |
| M15-F-014 | M15 | ETQAN-QA-462 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M15/triage/t015-store-nav.png` |
| M15-F-015 | M15 | ETQAN-QA-463 | P3 | functional | no | OPEN | `qa/manual/screens/M15/triage/t016-player.png` |
| M15-F-016 | M15 | not a bug: B7g spec §6 ruling (G-3 wording): a recorded-course certificate is reached from the course player and print page, the certificates list excludes subject certificates (D58). Print page with no back → ETQAN-QA-466 | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M15/triage/t016-player.png` |
| M15-F-017 | M15 | ETQAN-QA-452 | P3 | functional | no | OPEN | `qa/manual/screens/M15/triage/t003-invoices-list.png` |
| M15-F-018 | M15 | ETQAN-QA-464 (IANA list = ETQAN-QA-154 pattern) | P3 | translation | yes | VERIFIED | `qa/manual/screens/M15/triage/t023-consult-whatsapp.png` |
| M15-F-019 | M15 | ETQAN-QA-451 (slot-blocking follow-up was observed before the holds ended; see bug) | P2 | functional | no | VERIFIED (UI) + PROPOSAL-accepted (auto-cancel) | `qa/manual/screens/M15/triage/t020-consult-list.png` |
| M15-F-020 | M15 | dup of M10-F-003 (red "حذف") + M10-F-006 ("قرأها 0"), parallel M10 triage owns them | - | - | - | CLOSED (dup) | `qa/manual/screens/M15/triage/t024-chat.png` |
| M15-F-021 | M15 | not a bug: "upcoming" = not yet ended (`scheduling/services/rules.py:661`, a session in progress stays upcoming); session 478 (03:45 Cairo, 30 min) was marked at 04:12 and seen at ~04:14 Cairo, before its 04:15 end. Disposal badge = ETQAN-QA-423 | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M15/triage/t001-sessions-ar.png` |
| M15-F-022 | M15 | dup of ETQAN-QA-321 (Arabic description in EN = frozen text, ETQAN-QA-403 family) | - | - | - | CLOSED (dup) | `qa/manual/screens/M15/triage/t007-inv143-en.png` |
| M15-F-023 | M15 | dup of M15-F-005 → ETQAN-QA-453 (Home part added to it); parent "قيّم حصصك" = ETQAN-QA-115 (reopened) | - | - | - | CLOSED (dup) | `qa/manual/screens/M15/triage/t027-student-home-overdue.png` |
| M15-F-024 | M15 | ETQAN-QA-465 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M15/triage/t028-parent-progress.png` |
| M15-F-025 | M15 | ETQAN-QA-466 (no PDF download = by design, certificates.md) | P3 | UI-layout | yes | OPEN (fix rejected: dir=auto regression) | `qa/manual/screens/M15/triage/t019-cert-print.png` |
| M15-F-026 | M15 | dup of M10-F-028: the shared `identity/require-admin.ts:requireRole` silently redirects to "/" for every wrong-role area (learning, people, …); no data shown | - | - | - | CLOSED (dup) | `qa/manual/screens/M15/triage/t025-teacher-redirect.png` |
| M15-F-027 | M15 | ETQAN-QA-467 (badge = ETQAN-QA-121) | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M15/triage/t030-invoices-mobile.png` |
| M15-F-028 | M15 | ETQAN-QA-457 | P3 | mobile | no | OPEN | `qa/manual/screens/M15/triage/t009-wallet-mobile.png` |
| M15-F-029 | M15 | ETQAN-QA-468 (pattern of ETQAN-QA-115) | P3 | copy | yes | VERIFIED | `qa/manual/screens/M15/triage/t029-parent-courses.png` |
| M15-F-030 | M15 | ETQAN-QA-471 (Latin-comma date on the same page folded in; status line = note under ETQAN-QA-451; auto-cancel delay = 451 proposal) | P3 | copy | yes | OPEN | `qa/manual/screens/M15/triage/final/M15-F-030-repro-held-until-past.png` |
| M15-F-031 | M15 | ETQAN-QA-472 | P3 | mobile | yes | OPEN | `qa/manual/screens/M15/triage/final/M15-F-031-repro-phone-receipt.png` |
| M05-F-001 | M05 | ETQAN-QA-550 | P3 | functional | no | OPEN | `qa/manual/screens/M05/triage/t001-courses-order.png` |
| M05-F-002 | M05 | ETQAN-QA-551 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M05/triage/t002-filter-no.png` |
| M05-F-003 | M05 | ETQAN-QA-552 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M05/triage/t003-no-match.png` |
| M05-F-004 | M05 | ETQAN-QA-553 | P3 | functional | yes | VERIFIED | `qa/manual/screens/M05/triage/t004-delete-stays.png` |
| M05-F-005 | M05 | ETQAN-QA-554 | P3 | functional | no | OPEN | `qa/manual/screens/M05/triage/t005-deleted-course-spins.png` |
| M05-F-006 | M05 | ETQAN-QA-555 | P3 | data | no | OPEN | `qa/manual/screens/M05/triage/t006-courses-csv.png` |
| M05-F-007 | M05 | ETQAN-QA-556 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M05/triage/t007-package-form.png` |
| M05-F-008 | M05 | ETQAN-QA-557 | P3 | functional | no | OPEN | `qa/manual/screens/M05/triage/t008-price-3dec.png` |
| M05-F-009 | M05 | not a bug: B3d spec D-8 asks the form to prefill the resolved price and label its currency, which it does (EG 2000 EGP, SA 300 SAR, US 12.750 KWD; invoices correct); the country card already says country prices apply. A 'why' hint is a suggestion, not a defect | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M05/triage/t010-035-package21-main.png` |
| M05-F-010 | M05 | ETQAN-QA-558 | P3 | functional | no | OPEN | `qa/manual/screens/M05/triage/t010-035-package21-main.png` |
| M05-F-011 | M05 | ETQAN-QA-559 | P4 | copy | no | OPEN | `qa/manual/screens/M05/triage/t010-035-package21-main.png` |
| M05-F-012 | M05 | ETQAN-QA-560 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M05/triage/t012-level-dialog.png` |
| M05-F-013 | M05 | ETQAN-QA-561 | P3 | translation | yes | VERIFIED | `qa/manual/screens/M05/triage/t013-topic-english-error.png` |
| M05-F-014 | M05 | not a bug: `aria-current=page` and the gold bar are on "سور القرآن" (also "الدورات المسجلة"); the grey background on "مستويات الطلاب" is the hover state under the parked test cursor after the sidebar scrolls back to top (direct load shows no highlight) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M05/triage/t014-sidebar-after-click.png` |
| M05-F-015 | M05 | ETQAN-QA-562 | P3 | functional | yes | VERIFIED | `qa/manual/screens/M05/M05-F-015-topic-surah-list-empty.png` |
| M05-F-016 | M05 | ETQAN-QA-563 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M05/triage/t016-surah-dialog.png` |
| M05-F-017 | M05 | dup of M05-F-016 → ETQAN-QA-563 (same Latin-name/mirrored-number root) | - | - | - | CLOSED (dup) | `qa/manual/screens/M05/triage/t017-surah-latin-verse-error.png` |
| M05-F-018 | M05 | ETQAN-QA-564 | P4 | copy | no | OPEN | `qa/manual/screens/M05/triage/t018-level-order-after-filter.png` |
| M05-F-019 | M05 | dup of M05-F-013 → ETQAN-QA-561 (raw English server message; file-picker part = ETQAN-QA-470/607 pattern) | - | - | - | CLOSED (dup) | `qa/manual/screens/M05/triage/t019-exe-english-error.png` |
| M05-F-020 | M05 | ETQAN-QA-565 | P3 | functional | no | OPEN | `qa/manual/screens/M05/triage/t020-materials-list.png` |
| M05-F-021 | M05 | ETQAN-QA-566 | P4 | functional | no | OPEN | `qa/manual/screens/M05/triage/t021-reload-loses-course.png` |
| M05-F-022 | M05 | ETQAN-QA-567 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M05/triage/t022-https-hint.png` |
| M05-F-023 | M05 | ETQAN-QA-568 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M05/triage/t023-link-delete-mentions-file.png` |
| M05-F-024 | M05 | dup of M05-F-002 → ETQAN-QA-551 (unlabelled filters); its sidebar part is not a bug (see F-014) | - | - | - | CLOSED (dup) | `qa/manual/screens/M05/triage/t024-recorded-filters.png` |
| M05-F-025 | M05 | dup of M05-F-013 → ETQAN-QA-561 (slug message); the الخصم remark is not a bug (see F-032) | - | - | - | CLOSED (dup) | `qa/manual/screens/M05/triage/t025-slug-english.png` |
| M05-F-026 | M05 | not a bug: the image uses `object-fit: cover` (100x100 → 192x108 box, store card too), so it is cropped, not stretched (Agent 1's solid red square hid this); 400×225 in the label is a recommended size; docs only cap thumbnails at 2 MB | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M05/triage/t026-thumb.png` |
| M05-F-027 | M05 | ETQAN-QA-569 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M05/triage/t027-video-added.png` |
| M05-F-028 | M05 | ETQAN-QA-570 | P3 | translation | yes | VERIFIED | `qa/manual/screens/M05/triage/t028-consult-raw-constraint.png` |
| M05-F-029 | M05 | ETQAN-QA-571 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M05/triage/t029-consult-list.png` |
| M05-F-030 | M05 | ETQAN-QA-572 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M05/triage/t030-consult-teachers-tab.png` |
| M05-F-031 | M05 | not a bug: homework-content.md scopes teacher materials to active items of courses they teach or are listed on, with no course-status rule; the teacher of a deactivated course keeping read access to its materials leaks nothing | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M05/triage/t031-teacher-materials.png` |
| M05-F-032 | M05 | not a bug: recorded-courses.md defines net price = price_minor − discount_minor; "الخصم" means the discount amount, and both the admin list and the student card show the result (20.00 ج.م. with 100.00 struck through) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M05/triage/t033-student-store.png` |
| M05-F-033 | M05 | dup of ETQAN-QA-462 (M15, same two-items-active sidebar) | - | - | - | CLOSED (dup) | `qa/manual/screens/M05/triage/t033-student-store.png` |
| M05-F-034 | M05 | ETQAN-QA-573 | P3 | mobile | yes | VERIFIED | `qa/manual/screens/M05/triage/t034-mobile-levels.png` |
| M05-F-035 | M05 | ETQAN-QA-574 | P4 | copy | no | OPEN | `qa/manual/screens/M05/triage/t010-035-package21-main.png` |
| M05-F-036 | M05 | ETQAN-QA-575 | P3 | UX | yes | OPEN | `qa/manual/screens/M05/triage/t036-form-no-warning.png` |
| M01-F-001 | M01 | ETQAN-QA-806 | P3 | copy | yes | VERIFIED (final gate cycle 2) | `qa/manual/screens/M01/triage/t001-subdomain-not-marked.png` |
| M01-F-002 | M01 | ETQAN-QA-805 | P3 | copy | yes | OPEN | `qa/manual/screens/M01/triage/t002-invite-opens-reset-page.png` |
| M01-F-003 | M01 | ETQAN-QA-807 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M01/triage/t003-feature-labels-wrap.png` |
| M01-F-004 | M01 | ETQAN-QA-808 (related ETQAN-QA-007) | P3 | functional | no | OPEN | `qa/manual/screens/M01/triage/t004-history-no-direction.png` |
| M01-F-005 | M01 | ETQAN-QA-804 | P3 | translation | yes | OPEN | `qa/manual/screens/M01/triage/t005-suspended-login-english-ar.png` |
| M01-F-006 | M01 | ETQAN-QA-801 (ordering part → ETQAN-QA-814) | P2 | functional | no | OPEN | `qa/manual/screens/M01/triage/t006a-suspend-no-confirm.png` |
| M01-F-007 | M01 | ETQAN-QA-803 (same class as ETQAN-QA-016, other entry point) | P3 | functional | no | OPEN | `qa/manual/screens/M01/triage/t007-after.png` |
| M01-F-008 | M01 | ETQAN-QA-809 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M01/triage/t008-domains-long-host.png` |
| M01-F-009 | M01 | ETQAN-QA-810 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M01/triage/t009-domain-readonly-save-buttons.png` |
| M01-F-010 | M01 | ETQAN-QA-811 (ordering part → ETQAN-QA-814) | P3 | copy | yes | OPEN | `qa/manual/screens/M01/triage/t010-domain-exists-no-owner.png` |
| M01-F-011 | M01 | ETQAN-QA-812 + ETQAN-QA-813 (raw names) | P3 | copy | yes | OPEN | `qa/manual/screens/M01/triage/t011a-price-form-no-currency.png` |
| M01-F-012 | M01 | ETQAN-QA-814 | P3 | functional | no | OPEN | `qa/manual/screens/M01/triage/t012-pricing-filter-etqan.png` |
| M01-F-013 | M01 | ETQAN-QA-815 | P4 | copy | yes (trivial) | OPEN | `qa/manual/screens/M01/triage/t013-017-invoice-list.png` |
| M01-F-014 | M01 | ETQAN-QA-816 | P3 | copy | yes | OPEN | `qa/manual/screens/M01/triage/t014a-invoice-inline-raw.png` |
| M01-F-015 | M01 | ETQAN-QA-817 (message part → ETQAN-QA-816) | P3 | functional | no | OPEN | `qa/manual/screens/M01/triage/t015-lines-list-landing-raw-amounts.png` |
| M01-F-016 | M01 | not a bug: usage totals per academy/month are not in etqan-billing.md (UsageEvent is a read-only log; monthly totals live on each invoice and the academy's Settings → Etqan billing); an enhancement | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M01/triage/t016-usage-events.png` |
| M01-F-017 | M01 | ETQAN-QA-818 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M01/triage/t013-017-invoice-list.png` |
| M01-F-018 | M01 | ETQAN-QA-819 | P3 | copy | no | OPEN | `qa/manual/screens/M01/triage/t018-invoice-email-lowercase-text-only.png` |
| M01-F-019 | M01 | ETQAN-QA-820 | P3 | functional | no | OPEN | `qa/manual/screens/M01/triage/t019-mark-paid-bad-date.png` |
| M01-F-020 | M01 | ETQAN-QA-802 | P2 | functional | no | OPEN | `qa/manual/screens/M01/triage/t020-void-no-reason-no-confirm.png` |
| M01-F-021 | M01 | ETQAN-QA-821 + ETQAN-QA-813 (raw title) | P3 | copy | yes | OPEN | `qa/manual/screens/M01/triage/t021-platform-account-raw-title.png` |
| M01-F-022 | M01 | ETQAN-QA-822 | P4 | copy | no | OPEN | `qa/manual/screens/M01/triage/t022-periodic-tasks.png` |
| M01-F-023 | M01 | ETQAN-QA-823 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M01/triage/t023-staff-role-student.png` |
| M01-F-024 | M01 | ETQAN-QA-800 | P1 | data | no | OPEN | `qa/manual/screens/M01/triage/t024a-add-user-plain-password.png` |
| M01-F-025 | M01 | ETQAN-QA-824 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M01/triage/t025-bare-403.png` |
| M01-F-026 | M01 | ETQAN-QA-825 (related ETQAN-QA-022) + ETQAN-QA-813 (raw title) | P3 | data | no | OPEN | `qa/manual/screens/M01/triage/t026-connect-fee-zz.png` |
| M01-F-027 | M01 | ETQAN-QA-826 | P4 | UI-layout | no | OPEN | `qa/manual/screens/M01/triage/t027-console-home.png` |
| M01-F-028 | M01 | not a bug: Academies search is name + subdomain by design; the Domains list searches by host and shows the academy (tenant) in one step, which answers the support case; extra columns are an enhancement | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M01/triage/t028-domain-search-finds-academy.png` |
| M01-F-029 | M01 | ETQAN-QA-827 (related ETQAN-QA-804 header PROPOSAL, ETQAN-QA-114) | P3 | UI-layout | yes | VERIFIED (final gate cycle 2) | `qa/manual/screens/M01/triage/t029-suspended-login-phone.png` |
| M01-F-030 | M01 | ETQAN-QA-828 | P4 | copy | yes (trivial) | VERIFIED (final gate cycle 2) | `qa/manual/screens/M01/triage/t030-void-message-stray-dot.png` |
| M01-F-031 | M01 | ETQAN-QA-829 (PDF link part: enhancement, not filed) | P3 | copy | yes | VERIFIED (final gate cycle 2) | `qa/manual/screens/M01/triage/t031-manual-line-qty0.png` |
| M01-F-032 | M01 | ETQAN-QA-830 | P4 | UI-layout | yes | VERIFIED (final gate cycle 2) | `qa/manual/screens/M01/triage/t032-copy-features-name-order.png` |
| M16-F-001 | M16 | ETQAN-QA-750 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M16/triage/t001-qaother-footer.png` |
| M16-F-002 | M16 | ETQAN-QA-751 | P3 | functional | no | OPEN | `qa/manual/screens/M16/triage/t001-home-ar-full.png` |
| M16-F-003 | M16 | ETQAN-QA-752 | P3 | functional | no | OPEN | `qa/manual/screens/M16/triage/t003-buy-login.png` |
| M16-F-004 | M16 | ETQAN-QA-753 | P3 | copy | yes | OPEN | `qa/manual/screens/M16/triage/t004-trial-cta.png` |
| M16-F-005 | M16 | ETQAN-QA-754 | P3 | copy | yes | OPEN | `qa/manual/screens/M16/triage/t005-recorded-durations.png` |
| M16-F-006 | M16 | ETQAN-QA-755 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M16/triage/t006-phone-placeholder.png` |
| M16-F-007 | M16 | dup of ETQAN-QA-154 (same `dashboard/src/lib/timezones.ts` raw IANA list, also used by RegisterForm and consultation BookingWizard; the fix there covers registration + visitor booking) | - | - | - | DUPLICATE | `qa/manual/screens/M16/triage/t008-past-dates-step3.png` |
| M16-F-008 | M16 | ETQAN-QA-756 | P3 | functional | yes | OPEN | `qa/manual/screens/M16/triage/t008-past-dates-step3.png` |
| M16-F-009 | M16 | ETQAN-QA-757 | P3 | translation | yes | OPEN | `qa/manual/screens/M16/triage/t009-invalid-code.png` |
| M16-F-010 | M16 | ETQAN-QA-758 | P2 | mobile | no | OPEN | `qa/manual/screens/M16/triage/t010-mobile-register.png` |
| M16-F-011 | M16 | ETQAN-QA-759 | P3 | functional | no | OPEN | `qa/manual/screens/M16/triage/t009-invalid-code.png` |
| M16-F-012 | M16 | ETQAN-QA-760 | P3 | copy | yes | OPEN | `qa/manual/screens/M16/triage/t012-register-success.png` |
| M16-F-013 | M16 | ETQAN-QA-761 | P3 | copy | yes | OPEN | `qa/manual/screens/M16/triage/t013-future-dob.png` |
| M16-F-014 | M16 | ETQAN-QA-762 | P4 | UI-layout | yes | OPEN | `qa/manual/screens/M16/triage/t014-consult-avatar.png` |
| M16-F-015 | M16 | ETQAN-QA-763 | P3 | UI-layout | no | OPEN | `qa/manual/screens/M16/triage/t015-consult-booking-bare.png` |
| M16-F-016 | M16 | ETQAN-QA-764 | P3 | functional | yes | OPEN | `qa/manual/screens/M16/triage/t016-checkout-no-appointment.png` |
| M16-F-017 | M16 | not a bug: the manage-link email is a deliberate fixed bilingual template (`consultations/services/notices.py` docstring, B7d K-9; it carries no booker text). Suggestion only: put `row.language` first | - | - | - | CLOSED (not a bug) | Mailpit 3fZHhGMLEgVqwFvOnEuhOD |
| M16-F-018 | M16 | ETQAN-QA-765 | P3 | copy | yes | OPEN | `qa/manual/screens/M16/triage/t018-manage-paid-mobile.png` |
| M16-F-019 | M16 | ETQAN-QA-766 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M16/triage/t019-inquiries.png` |
| M16-F-020 | M16 | ETQAN-QA-767 | P3 | functional | no | OPEN | `qa/manual/screens/M16/triage/t020-paid-link.png` |
| M16-F-021 | M16 | not a bug: verification is by link to an unguessable 22-char code (`certificates.md`: `verify_url = /verify/<code>`, printed as link text); a type-a-code box is a feature request. Valid/invalid pages work | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M16/triage/t021-verify-invalid.png` |
| M16-F-022 | M16 | ETQAN-QA-768 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M16/triage/t022-404-ar.png` |
| M16-F-023 | M16 | ETQAN-QA-769 | P4 | copy | yes | OPEN | `qa/manual/screens/M16/triage/t023-about-dup.png` |
| M16-F-024 | M16 | ETQAN-QA-770 | P2 | functional | no | OPEN | `qa/manual/screens/M16/triage/t001-home-ar-full.png` |
| M16-F-025 | M16 | ETQAN-QA-771 | P3 | RTL | yes | OPEN | `qa/manual/screens/M16/triage/t025-en-arabic-title.png` |
| M16-F-026 | M16 | ETQAN-QA-772 | P3 | functional | yes | OPEN | `qa/manual/screens/M16/triage/t026-phone-accepts-text.png` |
| M16-F-027 | M16 | ETQAN-QA-773 | P3 | RTL | yes | OPEN | `qa/manual/screens/M16/triage/t027-mobile-header-ar.png` |
| M16-F-028 | M16 | ETQAN-QA-774 | P3 | mobile | yes | OPEN | `qa/manual/screens/M16/triage/t028-mobile-article-cover.png` |
| M16-F-029 | M16 | ETQAN-QA-775 | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M16/triage/t029-bogus-link.png` |
| M16-G-001 | M16 | ETQAN-QA-776 (found by Agent 2 when the qa site went into maintenance mid-run) | P4 | copy | yes | OPEN | `qa/manual/screens/M16/triage/g001-closed-site-name-twice.png` |
| M16-G-002 | M16 | ETQAN-QA-777 (found by Agent 2 at the gate) | P4 | RTL | yes | OPEN | `qa/manual/screens/M16/fix/g774-article-cover-m.png` |
| M16-F-030 | M16 | ETQAN-QA-778 (sweep; residual of the 753 fix) | P3 | functional | yes | OPEN | `qa/manual/screens/M16/triage/t030-trial-heading-resets-ar-m.png` |
| M16-F-031 | M16 | ETQAN-QA-779 (sweep; follows the 772 fix) | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M16/triage/t031-phone-error-green-ar-m.png` |
| M16-F-032 | M16 | ETQAN-QA-780 (sweep) | P4 | UX | yes | OPEN | `qa/manual/screens/M16/triage/t032-slot-dates-no-weekday.png` |
| M11-F-001 | M11 | dup of ETQAN-QA-470 (bare native file picker; same pattern in the office/teacher set-homework and edit dialogs, and the certificate photo picker; one shared picker fixes all) | P4 | UI-layout | no | DUP | `qa/manual/screens/M11/triage/t005-teacher-new-hw-dialog.png` |
| M11-F-002 | M11 | dup of ETQAN-QA-651 (file name direction: same missing `dir="auto"` in the homework dialog; a lone Arabic file name in AR reads correctly) | P3 | RTL | yes | DUP | `qa/manual/screens/M11/triage/t002-hw-file-dialog-bottom.png` |
| M11-F-003 | M11 | ETQAN-QA-652 | P4 | UI-layout | yes (P4) | OPEN | `qa/manual/screens/M11/triage/t003-hw-dialog-footer.png` |
| M11-F-004 | M11 | ETQAN-QA-650 | P3 | functional | yes | VERIFIED | `qa/manual/screens/M11/triage/t003-hw-dialog-footer.png` |
| M11-F-005 | M11 | ETQAN-QA-653 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M11/triage/t005-teacher-new-hw-dialog.png` |
| M11-F-006 | M11 | not a bug: title max length is enforced (`Homework.title` max_length=200; the row has 199 chars) and the full title wraps legibly; other columns keep their content (two-word cells wrap in every row, long title or not) | - | - | - | CLOSED (not a bug) | `qa/manual/screens/M11/triage/t004-teacher-hw-list-long-title.png` |
| M11-F-007 | M11 | ETQAN-QA-651 (+F-002) | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M11/triage/t002-hw-file-dialog-bottom.png` |
| M11-F-008 | M11 | ETQAN-QA-654 | P3 | mobile | yes | VERIFIED | `qa/manual/screens/M11/triage/t008-mobile-toast-over-buttons.png` |
| M11-F-009 | M11 | dup of ETQAN-QA-115 (REOPENED: parent addressed as the student; add homework dialog "إجابتك" to its scope, plus "قيّم حصصك" still seen) | P3 | copy | yes | DUP | `qa/manual/screens/M11/triage/t009-parent-hw-your-answer.png` |
| M11-F-010 | M11 | dup of ETQAN-QA-567 (VERIFIED): on retest the hint reads "أدخل رابطًا يبدأ بـ https://." intact (string has U+2066/2069); missing * on the conditionally required link field not filed (minor, the hint says what is needed) | - | RTL | - | DUP (fixed) | `qa/manual/screens/M11/triage/t010-https-hint.png` |
| M11-F-011 | M11 | ETQAN-QA-655 | P4 | UI-layout | yes (P4) | OPEN | `qa/manual/screens/M11/triage/t011-student-materials.png` |
| M11-F-012 | M11 | ETQAN-QA-656 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M11/triage/t012-level-dialog-blocks.png` |
| M11-F-013 | M11 | ETQAN-QA-657 | P3 | functional | no | OPEN | `qa/manual/screens/M11/triage/t013-topic-no-surah.png` |
| M11-F-014 | M11 | ETQAN-QA-658 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M11/triage/t014-upgrade-form-no-target.png` |
| M11-F-015 | M11 | ETQAN-QA-659 (sidebar count only; one-click approve = not a bug, reversible via student levels) | P3 | functional | no | OPEN | `qa/manual/screens/M11/triage/t015-upgrades-no-count.png` |
| M11-F-016 | M11 | ETQAN-QA-660 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M11/triage/t013a-teacher-progress.png` |
| M11-F-017 | M11 | ETQAN-QA-661 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M11/triage/t017-018-surah-names-empty.png` |
| M11-F-018 | M11 | ETQAN-QA-662 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M11/triage/t017-018-surah-names-empty.png` |
| M11-F-019 | M11 | ETQAN-QA-663 | P3 | functional | no | OPEN | `qa/manual/screens/M11/triage/t019-021-honour-dialog.png` |
| M11-F-020 | M11 | dup of ETQAN-QA-354 (native `<input type=month>` shows English month names; same in honour filter/dialog and the report form) | P3 | UI-layout | no | DUP | `qa/manual/screens/M11/triage/t019-021-honour-dialog.png` |
| M11-F-021 | M11 | ETQAN-QA-664 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M11/triage/t005-teacher-new-hw-dialog.png` |
| M11-F-022 | M11 | ETQAN-QA-665 | P3 | translation | yes | VERIFIED | `qa/manual/screens/M11/triage/t022-cert-english-error.png` |
| M11-F-023 | M11 | ETQAN-QA-666 | P3 | copy | yes | VERIFIED | `qa/manual/screens/M11/triage/t023-revoke-confirm.png` |
| M11-F-024 | M11 | ETQAN-QA-667 | P4 | UI-layout | yes (P4) | OPEN | `qa/manual/screens/M11/triage/t024-student-cert-card-mobile.png` |
| M11-F-025 | M11 | ETQAN-QA-668 | P2 | mobile | no | VERIFIED | `qa/manual/screens/M11/triage/t025-mobile-cert-print-clipped.png` |
| M11-F-026 | M11 | ETQAN-QA-669 | P3 | mobile | yes | VERIFIED | `qa/manual/screens/M11/triage/t026-mobile-admin-certs-wide.png` |
| M11-F-027 | M11 | ETQAN-QA-670 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M11/triage/t027-028-library-types-exe.png` |
| M11-F-028 | M11 | ETQAN-QA-671 | P3 | translation | yes | VERIFIED | `qa/manual/screens/M11/triage/t027-028-library-types-exe.png` |
| M11-F-029 | M11 | ETQAN-QA-672 | P3 | RTL | yes | VERIFIED | `qa/manual/screens/M11/triage/t029-library-meta-line.png` |
| M11-F-030 | M11 | ETQAN-QA-673 | P3 | functional | yes | VERIFIED | `qa/manual/screens/M11/triage/t030b-copy-link-success-stub.png` |
| M11-F-031 | M11 | ETQAN-QA-674 | P3 | translation | yes | VERIFIED | `qa/manual/screens/M11/triage/t031-library-delete-grammar.png` |
| M11-F-032 | M11 | ETQAN-QA-675 | P4 | functional | no | OPEN | `qa/manual/screens/M11/triage/t032-ai-draft-not-set-up.png` |
| M11-F-033 | M11 | ETQAN-QA-676 | P4 | UI-layout | yes (P4) | OPEN | `qa/manual/screens/M11/triage/t033-report-print-twice.png` |
| M11-F-034 | M11 | ETQAN-QA-677 (narrowed: print pages spin on 403/404; the redirect of office URLs to Home is documented in roles-permissions.md → not a bug; /ar/ landing not reproduced) | P3 | functional | yes | VERIFIED | `qa/manual/screens/M11/triage/t034d-parent-cert3-print.png` |
| M11-F-035 | M11 | ETQAN-QA-678 | P3 | UI-layout | yes | VERIFIED | `qa/manual/screens/M11/triage/t013a-teacher-progress.png` |
| M11-F-036 | M11 | ETQAN-QA-679 | P4 | UI-layout | yes (P4) | OPEN | `qa/manual/screens/M11/triage/t036-avg-4-5-five-stars.png` |
| M11-F-037 | M11 | ETQAN-QA-680 | P4 | UI-layout | yes (P4) | OPEN | `qa/manual/screens/M11/triage/t037a-parent-hw-cards.png` |
| M11-F-038 | M11 | ETQAN-QA-681 (sweep; residual of the 653 fix in the certificate dialog) | P3 | UI-layout | yes | OPEN | `qa/manual/screens/M11/triage/t038-cert-issue-blank-selects.png` |
| M11-F-039 | M11 | ETQAN-QA-682 (sweep; same shape as 652, certificate dialog) | P4 | UI-layout | yes (P4) | OPEN | `qa/manual/screens/M11/triage/t039-cert-detail-footer.png` |
| M11-F-040 | M11 | ETQAN-QA-683 (sweep; 209-class names on certificate print, public verify and office list) | P3 | RTL | yes | OPEN | `qa/manual/screens/M11/triage/t040a-verify-name-brackets.png` |
| M11-F-041 | M11 | ETQAN-QA-684 (sweep; side effect of the 651/672 `dir="auto"` fix) | P3 | RTL | yes | OPEN | `qa/manual/screens/M11/triage/t041-library-latin-title-far-side.png` |
| M13-F-001 | M13 | dup of ETQAN-QA-750 (empty footer contact column; at triage the column is already hidden in the working tree) | - | - | - | DUPLICATE | `qa/manual/screens/M13/triage/t001-002-public-footer-primary.png` |
| M13-F-002 | M13 | ETQAN-QA-700 | P2 | functional | no | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t001-002-public-footer-primary.png` |
| M13-F-003 | M13 | ETQAN-QA-701 | P3 | UI-layout | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t000-login-branding.png` |
| M13-F-004 | M13 | ETQAN-QA-702 (residue of ETQAN-QA-048/500 on other website forms) | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t004-005-branding-errors.png` |
| M13-F-005 | M13 | ETQAN-QA-703 | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t005-whatsapp-error.png` |
| M13-F-006 | M13 | ETQAN-QA-703 (same bug as F-005: server sentence shown raw) | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t006-slide-button-error.png` |
| M13-F-007 | M13 | dup of ETQAN-QA-770 (home switches courses/packages/teachers do nothing) | - | - | - | DUPLICATE | `qa/manual/screens/M13/M13-F-007-section-toggles-public.png` |
| M13-F-008 | M13 | dup of ETQAN-QA-769 (about eyebrow repeats heading) | - | - | - | DUPLICATE | `qa/manual/screens/M13/triage/t031-empty-about-public.png` |
| M13-F-009 | M13 | ETQAN-QA-703 (same bug as F-005) | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t009-block-errors.png` |
| M13-F-010 | M13 | ETQAN-QA-704 | P3 | RTL | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t010-pages-list.png` |
| M13-F-011 | M13 | ETQAN-QA-705 (label); rule text in ETQAN-QA-702 | P3 | copy | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t011-category-slug-label.png` |
| M13-F-012 | M13 | ETQAN-QA-706 | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t012-category-list.png` |
| M13-F-013 | M13 | ETQAN-QA-708 | P3 | UI-layout | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t013-article-save-blank.png` |
| M13-F-014 | M13 | ETQAN-QA-709 (wording part in ETQAN-QA-705) | P3 | functional | no | PART VERIFIED (705); 709 OPEN | `qa/manual/screens/M13/triage/t014-slug-hint.png` |
| M13-F-015 | M13 | ETQAN-QA-703 (same bug as F-005) | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t015-redirect-errors.png` |
| M13-F-016 | M13 | ETQAN-QA-702 ("Required") + ETQAN-QA-705 (no *) | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t016-faq-required.png` |
| M13-F-017 | M13 | ETQAN-QA-706 (same bug as F-012) | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t017-faq-list.png` |
| M13-F-018 | M13 | ETQAN-QA-707 (past date); list title in ETQAN-QA-706 | P3 | functional | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t018-ad-past-date.png` |
| M13-F-019 | M13 | ETQAN-QA-703 (same bug as F-005) | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t019-video-file-error.png` |
| M13-F-020 | M13 | ETQAN-QA-705 (same bug as F-011) | P3 | copy | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t019-video-file-error.png` |
| M13-F-021 | M13 | ETQAN-QA-702 (same bug as F-004) | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t021-022-testimonial-errors.png` |
| M13-F-022 | M13 | ETQAN-QA-710 (naming); list quote in ETQAN-QA-706 | P3 | copy | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t022-testimonial-list.png` |
| M13-F-023 | M13 | date / WhatsApp / mirroring: dup of ETQAN-QA-766 (already rendering in the working tree); email/phone links: ETQAN-QA-711 | P4 | UI-layout | yes | OPEN | `qa/manual/screens/M13/triage/t023-inquiries.png` |
| M13-F-024 | M13 | ETQAN-QA-712 | P3 | functional | no | OPEN | `qa/manual/screens/M13/triage/t024-handled-view.png` |
| M13-F-025 | M13 | ETQAN-QA-713 | P3 | copy | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t025-tracking-hint.png` |
| M13-F-026 | M13 | ETQAN-QA-714 (contact, wording, no confirm; confirmed in code, site not closed again); name twice = dup of ETQAN-QA-776 | P3 | copy | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/M13-F-026-system-only-page.png` |
| M13-F-027 | M13 | ETQAN-QA-715 | P2 | mobile | no | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t027-inquiries-phone.png` |
| M13-F-028 | M13 | ETQAN-QA-716 | P3 | mobile | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t028-slide-title-phone.png` |
| M13-F-029 | M13 | ETQAN-QA-717 | P3 | mobile | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t029-phone-article-row.png` |
| M13-F-030 | M13 | dup of ETQAN-QA-773 (phone header name cut; at triage it is cut at the end, the outcome 773 accepts) | - | - | - | DUPLICATE | `qa/manual/screens/M13/triage/t030-public-header-phone.png` |
| M13-F-031 | M13 | ETQAN-QA-718 | P3 | functional | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/t031-empty-about-public.png` |
| M13-G-001 | M13 | ETQAN-QA-702 (found by Agent 2: article publish date raw zod "Too small…" and body "Required") | P3 | translation | yes | VERIFIED (gate 2026-10-28) | `qa/manual/screens/M13/triage/g001-article-date-raw-zod.png` |
