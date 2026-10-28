# Manual campaign progress (Agent 2 owns status)

| Area | Status | Findings | Confirmed bugs | Fixed + verified | Open | Gate |
|---|---|---|---|---|---|---|
| M02 Sign-in & account | PASSED (final) | 22 (19 confirmed, 0 dup, 3 not a bug; +1 not a bug on retest: QA-062) | 18 real: ETQAN-QA-048..066 minus 062 (17 P3, 1 P4) | 9 (048, 049, 051, 054, 056, 057, 060, 061, 063) + QA-011 | 9 (P3: 050, 052, 053, 055, 058, 059, 065, 066; P4: 064) | FINAL GATE PASSED 2026-10-27 (Agent 2) |
| M03 Dashboards & navigation | PASSED (final) | 26 (22 confirmed, 2 dup, 2 not a bug) | 22: ETQAN-QA-100..121 (1 P2, 18 P3 incl. 15 easy, 3 P4); revenue figure verified correct | 13 (100, 103, 104, 105, 107, 108, 109, 110, 111, 112, 113, 116, 117) | 9 (P3: 102 + 115 reopened/easy, 120 new/easy, 106, 114, 118; P4: 101, 119, 121) | FINAL GATE PASSED 2026-10-27 (Agent 2) |
| M04 People | PASSED (final) | 35 (29 confirmed, 5 dup, 1 not a bug) | 29: ETQAN-QA-150..178 (1 P2, 25 P3 incl. 17 easy, 3 P4) | 16 (150, 151, 152, 153, 155, 156, 157, 158, 160, 163, 165, 167, 168, 169, 170, 172) | 13 (P3: 154, 159, 161, 164, 166, 171, 173, 174, 175 new/easy, 176 new/easy; P4: 162, 177 new, 178 new) | FINAL GATE PASSED 2026-10-27 (Agent 2) |
| M06 Subscriptions & schedules | PASSED | 25 (18 confirmed, 3 dup, 4 not a bug) + 1 at the gate (M06-G-001) | 19: ETQAN-QA-200..218 (18 P3 incl. 15 easy, 1 P4; no P0–P2) | 12 (203–214) | 7 (P3: 200, 201, 202 non-easy; 216, 217, 218 easy, next cycle; P4: 215) | FINAL GATE PASSED 2026-10-27 (Agent 2) |
| M07 Sessions & attendance | PASSED | 29 (25 confirmed → 26 bugs, 0 dup, 4 not a bug) + 1 at the gate | 27: ETQAN-QA-250..276 (0 P0–P2; 19 P3 incl. 12 easy, 8 P4) | 11 (250, 251, 252, 253, 254, 255, 257, 262, 264, 269, 270) | 16 (P3 easy: 276; P3 non-easy: 259, 260, 265, 266, 268, 271, 273; P4: 256, 258, 261, 263, 267, 272, 274, 275) | FINAL GATE PASSED 2026-10-28T00:45:01Z (Agent 2); 276 (easy P3) + 274/275 (easy P4) left for the next fix cycle |
| M08 Billing & finance | PASSED (final) | 23 (21 confirmed → 22 bugs, 1 dup, 1 not a bug) | 22: ETQAN-QA-300..321 (1 P2: 314 fixed; 19 P3 incl. 15 easy; 2 P4 easy). Money math verified correct by Agent 1 and at both gates | 13 (300, 301, 302, 303, 306, 307, 308, 310, 311, 312, 313, 314, 316); proposals accepted: 314 API lookup, 307 USD symbol, 313 server label | 9 (P3 easy, new: 318, 319, 321; P3 non-easy: 304, 305, 309, 315; P4: 317, 320 new) | FINAL GATE PASSED 2026-10-28T00:48:17Z (Agent 2); 318/319/321 (easy P3) + 320 (easy P4) left for the next fix cycle |
| M09 Payroll | PASSED | 36 (26 confirmed, 8 dup, 2 not a bug) | 26: ETQAN-QA-350..375 (no P0–P2; 24 P3 incl. 14 easy, 2 P4) | 12 (350, 353, 356, 358, 360, 363, 364, 366, 367, 368, 370, 373) | 14 (P3 easy: 351 reopened, 374 new; P3 non-easy: 352, 354, 355, 357, 359, 361, 365, 369, 371, 372; P4: 362, 375) | FINAL GATE PASSED 2026-10-28T00:42:39Z (Agent 2) after Agent 1's confirmation sweep |
| M14 Teacher portal | PASSED | 35 (31 confirmed, 2 dup, 2 not a bug) | 31: ETQAN-QA-400..430 (no P0–P2; 25 P3 incl. 20 easy, 6 P4) | 19 (400, 401, 402, 404, 405, 406, 407, 408, 413, 415, 416, 417, 418, 419, 420, 422, 425, 426, 427) | 12 (P3 easy: 429; P3 non-easy: 403, 409, 412, 428, 430; P4: 410, 411, 414, 421, 423, 424) + F-035 via M07's ETQAN-QA-272 | FINAL GATE PASSED 2026-10-28T00:40:13Z (Agent 2); 429 (easy P3) left for the next fix cycle |
| M15 Student & parent portal | PASSED | 31 (23 confirmed, 5 dup, 3 not a bug) | 23: ETQAN-QA-450..472 (2 P2: 450, 451; 19 P3 incl. 13 easy; 2 P4) | 12 (450, 451 UI part, 455, 458, 459, 460, 461, 462, 464, 465, 467, 468); proposals accepted: 451 auto-cancel rule (owner), 464 API error code | 11 (P3 easy: 466 reopened, 471 new, 472 new; P3 non-easy: 452, 453, 454, 456, 457, 463; P4: 469, 470) | FINAL GATE PASSED 2026-10-28T12:31:55Z (Agent 2); sweep 3 added 471, 472 (easy P3) for the next fix cycle with 466 |
| M12 Settings | PASSED | 22 (19 confirmed, 0 dup, 3 not a bug) | 19: ETQAN-QA-500..518 (no P0–P2; 17 P3 incl. 13 easy, 2 P4) | 12 (500, 501, 505, 506, 507, 508, 510, 511, 512, 513, 514, 515); proposals accepted: 506 disable unheld codes + 403 code, 508 active-first order, 510 JobRun error_code, 515 placeholder names as data, 512 legacy-tag cleanup | 7 (P3 easy: 518, new in sweep; P3 non-easy: 504, 509, 516, 517; P4: 502, 503) | FINAL GATE PASSED 2026-10-28T02:12:09Z (Agent 2); gate-1 PASSED 2026-10-28T01:50:25Z; Google live, gateways/integrations live BLOCKED (no credentials) |
| M05 Catalogue | PASSED (final) | 36 (26 confirmed, 5 dup, 5 not a bug) | 26: ETQAN-QA-550..575 (no P0–P2; 22 P3 incl. 16 easy, 4 P4); price resolution, invoices and money minor units verified correct | 15 (551, 552, 553, 556, 560, 561, 562, 563, 567, 568, 569, 570, 571, 572, 573); proposals accepted: 562 auto-sync chapters (owner), 561 API codes | 11 (P3 easy: 575 new in sweep; P3 non-easy: 550, 554, 555, 557, 558, 565; P4: 559, 564, 566, 574) | FINAL GATE PASSED 2026-10-28T12:29:33Z (Agent 2); gate-1 PASSED 2026-10-28T02:19:52Z; 575 (easy P3) left for the next fix cycle |
| M10 Communication | PASSED | 34 (23 confirmed, 5 dup, 6 not a bug) + 1 at the gate + 3 from the confirmation sweep | 27: ETQAN-QA-600..626 (no P0–P2; 21 P3 incl. 19 easy, 6 P4) | 15 (600, 603, 606, 608, 609, 611, 612, 613, 614, 616, 617, 618, 620, 621, 622); 604 NOT-A-BUG accepted | 11 (P3 easy: 623, 624, 625; P3 non-easy: 601, 619; P4: 602, 605, 607, 610, 615, 626) | FINAL GATE PASSED 2026-10-28T12:27:34Z (Agent 2); easy P3s 623/624/625 for the next fix cycle; web push/WhatsApp live BLOCKED (no VAPID/credentials) |
| M11 Learning (homework, content, curriculum, certificates) | PASSED (final gate) | 41 (35 confirmed → 35 bugs, 5 dup, 1 not a bug) | 35: ETQAN-QA-650..684 (1 P2: 668; 26 P3 incl. 23 easy; 8 P4) | 21 (650, 651, 653, 654, 656, 658, 660, 661, 662, 664, 665, 666, 668 (P2), 669, 670, 671, 672, 673, 674, 677, 678) | 14 (P3 easy: 681, 683, 684; P3 non-easy: 657, 659, 663; P4: 652, 655, 667, 675, 676, 679, 680, 682) | Final gate 2026-10-28 (Agent 2): PASSED; see ### M11 final gate. Real AI provider BLOCKED (no account) |
| M13 Website admin | PASSED | 31 (27 confirmed incl. F-023 in part, 4 dup of known bugs: F-001→750, F-007→770, F-008→769, F-030→773; F-023 date/WhatsApp part→766; 0 not a bug) + 1 at triage (M13-G-001) | 19: ETQAN-QA-700..718 (2 P2: 700, 715; 16 P3 incl. 14 easy; 1 P4) | 16 (700, 701, 702, 703, 704, 705, 706, 707, 708, 710, 713, 714, 715, 716, 717, 718) | 3 (P3 non-easy: 709, 712; P4 easy: 711) | FINAL GATE PASSED 2026-10-28T15:57:35Z (Agent 2; sweep 0 new); GATE PASSED 2026-10-28T15:41:39Z (Agent 2); all M13G test content deleted, branding/status/about back at start values; closed page checked on qaother (site_status switched on for ~1 min, restored); real logo/favicon upload not covered |
| M16 Public pages | PASSED | 29 (26 confirmed, 1 dup, 2 not a bug) + 1 at triage (M16-G-001) + 1 at the gate (QA-777) + 3 at the sweep (F-030..032) | 31: ETQAN-QA-750..780 (2 P2: 758 fixed, 770 proposal accepted; 24 P3 incl. 19 easy; 5 P4) | 18 (750, 753, 754, 755, 756, 757, 758, 760, 761, 764, 765, 766, 768, 771, 772, 773, 774, 775); proposal accepted: 770 public catalogue/teachers (owner) + registration error codes | 12 (P3 non-easy: 751, 752, 759, 763, 767; P3 easy: 778, 779 new; P4 easy: 762, 769, 776, 777, 780 new) | FINAL GATE PASSED 2026-10-28T15:23:19Z (Agent 2); real payments/WhatsApp/Zoom BLOCKED (no credentials); closed-site toggle not exercised on purpose (shared qa) |
| M01 Etqan staff console | PASSED (final gate cycle 2, 2026-10-28) | 32 (30 confirmed → 31 bugs, 0 dup, 2 not a bug) | 31: ETQAN-QA-800..830 (1 P1: 800; 2 P2: 801, 802; 23 P3 incl. 15 easy; 5 P4) | 20 (800, 801, 802, 804 + header proposal accepted, 805, 806, 807, 809, 810, 811, 812, 813, 816, 821, 823, 824, 827, 828, 829, 830) + known QA-012 VERIFIED | 11 (P3: 803, 808, 814, 817, 818, 819, 820, 825; P4: 815 easy, 822, 826), none blocking | FINAL GATE PASSED 2026-10-28T16:05:12Z (Agent 2): fix cycle 2 verified in the browser (012 as ops-view@, 806, 827 at 375 px AR+EN, 828, 829, 830); 800 re-confirmed; no open P0/P1/P2; superuser and view-only main jobs work. Live integrations BLOCKED (no real keys) |


### M02 gate
Agent 2, 2026-10-27. **Decision: PASSED.**

**Fixes verified (fix cycle 1).** Each was re-walked in the browser. BEFORE/AFTER composites are in `qa/manual/screens/M02/fix/<BUG>-after.png`, and the raw AFTER shot is in `*-after-raw.png`.
- VERIFIED: ETQAN-QA-048, 049, 051, 054, 056, 057, 060, 061 and 063.
- VERIFIED: ETQAN-QA-011 (the set-password page), covered by the QA-048 fix.
- ETQAN-QA-062 is closed as not a bug on retest. The BEFORE and AFTER renders are identical and correct ("+20 100 123 4567"), so the triage misread it. Agent 3's LRI/PDI change is kept as harmless hardening.

**Code review** (`git -C dashboard|backend diff`, branch `qa/manual-2026-10`, uncommitted):
- The fixes are at the root cause. No test was weakened or skipped, and nothing was committed.
- QA-049 maps the exact server text on the client. That is accepted as an interim fix, with the API `code` as a proposal.
- The shared `ui/input.tsx` change was checked outside M02. An empty Arabic placeholder (the staff students search) still sits on the right, and Arabic values stay right-aligned.

**Tests re-run by Agent 2:**
- Vitest: 38 files and 296 tests pass (identity, quicklogin, forgot-password, ui/input, radio-card-group, locales/bidi, lib).
- tsc: 0 errors. biome: clean, 214 files.
- pytest `etqan/identity` + `etqan/site/tests/test_emails.py`: 879 passed.

**Proposals.** All 4 are PROPOSAL-accepted, P3 only (see `qa/coverage-gaps.md`):
- QA-049: an API error code.
- QA-061: an app-wide Radix `Direction.Provider`.
- QA-048 family: a sweep of the zod schemas in other features.
- QA-060: the Textarea and table-name follow-up.

**Main jobs per role (AR and EN).** These were covered in Agent 1's walk and triage. The gate re-ran this smoke test:
- The admin (EN) reaches its home and a student record, and can send a sign-in link.
- The teacher (AR), parent (EN) and staff-codes (AR) land on their own homes.
- The student signs in (AR and EN), uses the quick link, and on the account page edits the profile, adds and removes an email, and gets a translated error for a short password.
- The lockout message appears for the throwaway account.
- A qa account signing in on qaother is refused.

**Gate criteria:**
- No P0, P1 or P2 exists in M02.
- Every easy P3 assigned is fixed and verified.

**Still open, all non-easy P3 plus one P4, outside the "P0–P2 + easy P3" fix scope and not blocking:**
- ETQAN-QA-050: saving the profile switches the UI language.
- ETQAN-QA-052: a double submit sends two password changes.
- ETQAN-QA-053: a verify link opened a second time says "invalid".
- ETQAN-QA-055: a used reset link still shows the form.
- ETQAN-QA-058: the deep link is lost after sign-in.
- ETQAN-QA-059: an ended session shows the raw auth error.
- ETQAN-QA-064 (P4): the sign-in copy is written for students only.

**State left:**
- student.ind5 is restored: Aisha Rahman, no phone, no extra email, password unchanged.
- One quick-login link for student 246 was used.
- student.ind6 is still throttled (it is a throwaway).

### M02 final gate
Agent 2, 2026-10-27. **Decision: PASSED (final).**

- **Sweep findings triaged** (Agent 1 confirmation sweep after fix cycle 1), each reproduced with Agent 2's own screenshot:
  - M02-F-021 -> **ETQAN-QA-065** (P3, RTL, easy): in Arabic the "Last sign-in" parts read zone-first ("آخر دخول: Africa/Cairo · حاسوب · 192.168.65.1") because the value sits in one `<span dir="ltr">`. Shots `screens/M02/triage/t032-last-signin-ar.png`, `t033-last-signin-en.png`. The missing date/time is **not a bug** (B9b S-8 defines "device · IP · zone"; the payload has no `last_login`) and is logged as a PROPOSAL in `qa/coverage-gaps.md`.
  - M02-F-022 -> **ETQAN-QA-066** (P3, copy, easy): Arabic login on a white-label academy says "جديد على إتقان؟"; EN/ES say "New here?". Shots `screens/M02/triage/t030-qaother-new-to-etqan-ar.png`, `t031-qaother-new-here-en.png`.
- **Sweep re-confirmed** all 9 verified fixes (048, 049, 051, 054, 056, 057, 060, 061, 063) and the main jobs for every role in AR and EN: sign-in and landing for admin, staff, teacher, student, parent and qaother admin; wrong/empty login; forgot by link and code; 2FA setup, TOTP and recovery-code sign-in, disable; quick link; logout + Back; session lost; lockout; account page (profile, password, emails, dark mode); a qa account refused on qaother. Mobile AR for login/reset/account.
- **Criteria:** no P0, P1 or P2 in M02 (none found in either pass). The two new bugs are P3, so they do not block. They are easy P3s and therefore in fix scope: **queue ETQAN-QA-065 and 066 for the next fix cycle** (retest by Agent 2 then).
- **Still open (non-blocking):** P3 050, 052, 053, 055, 058, 059 (non-easy, outside fix scope), 065, 066 (easy, next cycle); P4 064.
- **State left:** no data changed by the final gate (read-only repro). student.ind5 password `QA-People-2026!`, 2FA off; student.ind6 throttled ~1 h from 19:46Z (throwaway).

### M03 gate
Agent 2, 2026-10-27. **Decision: PASSED.**

- **Fix cycle 1 (Agent 3) retested in the browser**, each with BEFORE/AFTER side by side in `screens/M03/fix/<BUG-ID>-before-after.png` (AFTER alone in `<BUG-ID>-after.png`, working shots `g01..g25`).
  - **VERIFIED (14):** 100, 103, 104, 105, 107, 108, 109, 110, 111, 112, 113, 115, 116, 117 (the only P2: the phone drawer scrolls to the end by real mouse wheel and "Account" can be tapped, admin AR and parent EN).
  - **Reopened (1): ETQAN-QA-102** (P3, easy). A new Arabic notification (created through the real `scan._row` renderer, id 564) now keeps its order: the amount stays in brackets and the date reads "2026-10-26.". But the template's lone "لـ" still renders glued to the isolated Latin name ("SCN Student B1J"), which is the first symptom in the bug. Queue it for the next cycle, with the same remedy as QA-100 (reword the Arabic templates).
  - **Proposal accepted:** QA-102 follow-up, formatting amounts and dates in the recipient's language (N8-4, `qa/coverage-gaps.md`).
- **Tests re-run by the gate:**
  - Vitest: 31 files, 324 tests pass (Agent 3's regression tests plus the touched shell, notifications, people and scheduling suites).
  - `tsc -b`: exit 0.
  - pytest `etqan/notifications`: 401 pass.
  - Outputs: `evidence/M03/gate/`.
- **Diff review:** these are root-cause fixes:
  - bidi isolates in `lib/bidi.ts` and backend `text.isolate`;
  - an app-wide Radix `Direction.Provider`;
  - the flex/min-h-0 scroll containers;
  - one `useNavItems` shared by the sidebar and the Home tiles;
  - a `_authed/$` catch-all;
  - permission-gated family links.

  No tests were weakened. The changed test expectations match the new, correct output. The other areas' edits (M02 `useDir`, M06 `labelled`/PersonName) are kept.
- **Main jobs, AR + EN, re-smoked after the fixes:**
  - admin: AR/EN Home, bell, menu, 404, Today, student detail, notifications, phone drawer;
  - staff-nocode: AR;
  - staff-codes: AR;
  - supervisor: EN;
  - qa-teacher: AR, with a forbidden URL sent home;
  - maryam: AR/EN;
  - qa-student: AR Home and sessions;
  - parent.sharif: AR/EN, plus the phone drawer in EN;
  - qaother admin: AR.

  Agent 1's walk and triage already cover the rest.
- **Criteria:**
  - no P0 or P1 in M03;
  - the one P2 (117) is verified;
  - the open P3s don't block.
- **Still open (non-blocking):**
  - P3 102: reopened, easy, next cycle.
  - P3 106, 114, 118: not easy, outside the fix scope.
  - P4 101, 119.
- **State left:** two test notifications for qa-admin (ids 564 AR, 565 EN; dedupe keys `invoice.overdue:invoice:<id>:m03-gate-{ar,en}:<admin>`, email skipped). No other data changed.

### M03 final gate
Agent 2, 2026-10-27. **Decision: PASSED (final).**

- **Agent 1's confirmation sweep** (~27 calls, `screens/M03/confirm/c001..c026`) re-checked the cycle-1 fixes and the main jobs in AR and EN for every role (admin, staff no-code, staff with codes, supervisor, qa-teacher/maryam/ahmad, student, parent, qaother admin; phone drawer for admin AR and parent EN). Agent 1 reported three new findings. Agent 2 reproduced each one with its own screenshot:
  - **M03-F-024 → new ETQAN-QA-120** (P3, RTL, easy). In the English UI an "Arabic (English)" name shows its bracket part first: "Assalamu alaikum, (Maryam Al-Khatib) الأستاذة مريم الخطيب". This affects the greeting, the account button and the parent's "Next session" line, and the line scrambles on a phone. It is a **regression from fix cycle 1**: `bidiName()` wraps the name in FSI, which turns RTL because the name starts with an Arabic letter. Fix by isolating with the UI's direction. Screenshot: `screens/M03/triage/t021-maryam-home-en-name-order.png`.
  - **M03-F-025 → dup of ETQAN-QA-115, REOPENED** (P3, copy, easy). A parent's AR item and tile still read "قيّم حصصك". This label was in the original F-019 list, but `reviews.nav.rate` is missing from `PARENT_LABELS`, and the gate's first retest missed it. Screenshot: `screens/M03/triage/t022-parent-rate-wording-ar.png`.
  - **M03-F-026 → new ETQAN-QA-121** (P4, mobile, cosmetic). On a phone, the status badge on the family invoices list floats under the balance, because of `items-end` inside a wrapped flex block. Screenshot: `screens/M03/triage/t023-mobile-parent-invoices-badge-en.png`.
- **Criteria:**
  - There is no P0 or P1 in M03.
  - The only P2 (117) is still verified: Agent 1's sweep scrolled the phone drawer to the last item.
  - No new P2.
  - The new and reopened bugs are P3/P4. None of them stops a main job: names stay readable, and the wording and badge are cosmetic.
  - The main jobs work for every role in AR and EN.
- **Queue for the next fix cycle (easy P3):** 102 (reopened), 115 (reopened), 120 (new regression; add an EN test to `lib/bidi.test.ts` / `index.test.tsx`). 121 is optional (P4).
- **Still open (non-blocking):**
  - P3: 102, 115, 120 (easy, next cycle); 106, 114, 118 (not easy, outside the fix scope).
  - P4: 101, 119, 121.
- **Verified (13):** 100, 103, 104, 105, 107, 108, 109, 110, 111, 112, 113, 116, 117. 115 was verified, then reopened.
- **State left:** no data changed. Repro was read-only, using sessions M03-t-maryam-en, M03-sharif-ar and M03-c-sharif-en (`--nosave`).

### M04 gate
Agent 2, 2026-10-27. **Decision: PASSED.**

- **Fix cycle 1 (Agent 3) retested in the browser.** Each bug has BEFORE (Agent 1's original shot) and AFTER side by side in `screens/M04/fix/<BUG-ID>-after.png`; the working shots are `raw-*.png`.
  - **VERIFIED (16):** 150, 151 (the only P2), 152, 153, 155, 156, 157, 158, 160, 163, 165, 167, 168, 169, 170, 172.
    - 151: "ابراهيم" finds "إبراهيم حسن (Ibrahim Hassan)", and the families search "عائله" finds "عائلة".
    - 157: covers both the duplicate email and the contract file type.
    - 160: covers the detail page and bulk.
    - 172: checked end to end with a new self-registration (`m04-gate-reg@qa.etqan.test`). Verify, then sign-in says "تسجيلك بانتظار موافقة الأكاديمية.", and approval does send the welcome email that the new text promises.
  - **Proposals accepted** (written up in `qa/coverage-gaps.md` M04; none is P0–P2):
    - 157: error codes on the backend ValidationErrors, replacing the dashboard's sentence map;
    - 172: verify-email returns `can_sign_in`;
    - 151 follow-up: folded search in the other app searches;
    - 156 follow-up: the create toast says whether an invite was sent;
    - 155 note: `es/notifications.json` has no preferences section.
  - **Interim fixes accepted as they are:** the 157 text map (two fixed sentences, documented, tested) and the 172 rewording (true for both cases).
- **Tests re-run by the gate** (outputs in `evidence/M04/gate-1/`):
  - Vitest: 38 files, 216 tests pass (people, employment, access, components, NameList, form-errors, field-error, input, people-copy, verify-email).
  - `tsc --noEmit`: 0 errors.
  - pytest `platform/tests/test_search.py`, `identity/tests/test_people_api.py`, `identity/tests/test_families_api.py`: 56 pass.
- **Diff review:**
  - `platform/search.py` folds both sides in SQL (`TRANSLATE` + `REGEXP_REPLACE`): no migration and no API change. Email and phone stay plain `icontains`.
  - The regression tests assert the real behaviour. No test was weakened or skipped.
  - Shared files (`input.tsx`, the locale JSON) keep M02's and M06's edits.
  - Gaps that don't block: `applyServerErrors` focuses the first field in server order, not form order; the Confirm title isn't wrapped in `<bdi>` (it reads fine in the shots).
- **Main jobs, re-smoked after the fixes:**
  - admin, AR: students list, search, filters, bulk bar, select-all, add student, student detail, contracts, families, admins, study groups.
  - admin, EN: empty search, study groups, student detail with "Resend invite" sent, teachers.
  - admin, AR at 375: students list, search, and add student with a server error.
  - qa-staff-codes: sees only Students; Teachers is refused.
  - qa-staff-nocode: Students and Teachers are refused.
  - qa-supervisor: Students and Teachers lists.
  - qa-teacher: people URLs send it to its Home.
- **Criteria:**
  - no P0 or P1 in M04;
  - the one P2 (151) is verified;
  - every easy P3 is verified;
  - the open P3s and the P4 don't block.
- **Still open (non-blocking, not easy, outside the fix scope):**
  - P3: 154 (time-zone list), 159 (deactivated no-login looks active), 161 (CSV in English), 164 (family edit payer blank), 166 (retired family not marked), 171 (registration review missing fields), 173 (phone list layout), 174 (unsaved-form guard).
  - P4: 162 (week starts Monday).
- **Test data left by the gate:**
  - self-registration `M04 بوابة تسجيل منى` / `m04-gate-reg@qa.etqan.test`, email verified and pending approval;
  - family 16 is retired again, as it was before the gate.


### M04 final gate
Agent 2, 2026-10-27. **Decision: PASSED (final).**

- **Agent 1's confirmation sweep** re-walked the fixed screens; the 14 fixed items it checked still hold, and nothing VERIFIED regressed. It reported 4 new findings. I reproduced each one with my own screenshot in `screens/M04/triage/` and filed it:
  - M04-F-032 → **ETQAN-QA-175** (P3, easy): the email hint renders under the time-zone field (email at y 174, hint at y 394) and is also shown to read-only viewers. Pointer: `UserFieldsSection.tsx`. Shot `t032-email-hint-under-tz.png`.
  - M04-F-033 → **ETQAN-QA-176** (P3, easy): on retired families "تعديل"/"استعادة" wrap; those rows are 109 px vs 65 px. Pointer: `FamiliesList.tsx` action cell. Shot `t033-retired-family-actions-wrap.png`.
  - M04-F-034 → **ETQAN-QA-177** (P4, trivial): a supervisor's student page has a ~72 px gap, because an empty `div.mt-6` wraps a wallet card that returns null. Pointer: `routes/_authed/people.students.$personId.tsx`. Shot `t034-readonly-student-double-gap.png`.
  - M04-F-035 → **ETQAN-QA-178** (P4, trivial): the EN "Invite pending" pill wraps; those rows are 67 px vs 50 px. Shot `t035-parents-invite-pending-wraps.png`.
  - No duplicates: QA-109 covers only the family link, not the edit hints.
- **Criteria:**
  - no P0 or P1;
  - the only P2 (151) is still VERIFIED;
  - no new P2;
  - all four new findings are cosmetic P3/P4. They block no job and are queued as easy items for the next fix cycle.
- **Main jobs:** gate cycle 1 re-smoked every role after the fixes, and Agent 1's sweep re-walked them in AR and EN. In this pass I re-checked admin AR (new student, families), admin EN (parents) and supervisor AR (student detail). All loaded with no errors apart from the known 403 on `/identity/me/` before sign-in.
- **State left:** no data changed. Sessions used: M04-t2-admin-ar, M04-t2-admin-en, M04-t2-super-ar.

### M06 gate
Agent 2, 2026-10-27. **Decision: PASSED.**

**Fixes verified (fix cycle 1).** Each was re-walked in the browser. The BEFORE/AFTER composites are in `qa/manual/screens/M06/fix/ETQAN-QA-<id>-after.png`, with the raw AFTER shots beside them.
- VERIFIED: ETQAN-QA-203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213 and 214. All 12 easy P3s are fixed.
- Highlights:
  - 204: a 375px AR list measures `[375, 375, 0]`.
  - 205: stopping a slot and ending a pause early now ask first, then show a toast.
  - 206: both forms show an Arabic error and send no request.
  - 212: the dialog opens on 03/11 19:30, after the DST change, and Cancel resets it.

**Code review** (`git -C dashboard diff`, branch `qa/manual-2026-10`, uncommitted, no backend change):
- Each fix is at the root cause. For example, 203 was a wrong filter key (`active` vs `is_active`).
- No test was weakened or skipped.
- The shared `Confirm` only gains optional props, and its defaults are unchanged.
- `PersonName` uses `<bdi>`, with no invisible characters added.
- The Arabic plural keys cover all six forms.
- M03's later reuse of `AttendanceControls labelled` in the teacher table (its QA-110) is consistent.

**Tests re-run by Agent 2:**
- Vitest on `src/features/scheduling`, the shell sidebar/nav and `src/components`: 71 files, 523 tests pass.
- tsc: exit 0.
- Output: `qa/manual/evidence/M06/gate-1/vitest-tsc.txt`.

**Proposals.** All 4 are PROPOSAL-accepted, P3 only (`qa/coverage-gaps.md`, M06 section):
- 204 family: a sweep of the other table scrollers.
- 206 family: error codes, which also covers the still-English window-overlap message.
- 207 family: the other day+time joins.
- 211: the page header and browser title.

**New at the gate:** ETQAN-QA-216 (P3, RTL, easy). On the expanded weekly calendar, mixed names still wrap wrongly ("Adam Al-) آدم النجار" / "(Najjar"). The calendar was outside 209's listed scope. It is queued for the next fix cycle and does not block.

**Main jobs per role (AR and EN)**, smoke-tested at the gate:
- **Admin:**
  - List, search and tabs in AR and EN, plus the AR 375px list.
  - The create form in AR and EN.
  - A full create in EN (sub 106: Fatima, Quran, Tuesday 15:00), then cancel and archive from the list.
  - The detail page: slot stop and restart, pause add and end early.
  - The bundle page and bundle pause.
  - Trials: list, detail, new request (trial 4) and the schedule dialog.
  - The session page.
  - The expanded calendar on desktop AR and mobile AR.
- **Teacher (Ahmad):** My sessions in AR and EN, and availability in AR.
- **Student (Mona):** My subscriptions in AR and EN.
- **Parent (Najjar):** home in AR and subscriptions in EN.
- The parent can't open `/scheduling/bundles/<id>` (it redirects home). This is unchanged and not part of 211.
- **Staff:** no staff account has subscription codes. `qa-staff-codes@` (People > Students only) opening `/app/scheduling/subscriptions` gets the translated "ليس لديك صلاحية الوصول إلى هذه الصفحة." page, which is correct (`screens/M06/fix/smoke-staff-ar.png`). The admin covers this role, as the task allows.

**Gate criteria:**
- No P0, P1 or P2 exists in M06.
- Every easy P3 assigned in cycle 1 is fixed and verified.
- The main jobs work for every role in AR and EN.

**Still open (non-blocking):**
- ETQAN-QA-200, P3 non-easy: a not-started renewal shows as a second "Active".
- ETQAN-QA-201, P3 non-easy: early renewal gives no warning and shows a misleading "remaining".
- ETQAN-QA-202, P3 non-easy: the student dropdown stops at 100.
- ETQAN-QA-216, P3 easy: calendar names; next cycle.
- ETQAN-QA-215, P4: empty "Price ()".

**State left:**
- Sub 96's Monday slot was stopped and restarted.
- On sub 105, a pause from 27/10 to 29/10 was added and then ended early, which deletes it by design.
- Sub 106 (Fatima) was created, cancelled and archived.
- Trial 4 (Hamza, desired 03/11 19:30, note "M06-gate trial for QA-212") is left unscheduled.
- No data was changed on the 4 realistic subscriptions.
- The teacher's availability is unchanged, because the invalid window was never saved.

### M06 final gate
Agent 2, 2026-10-27 (after Agent 1's confirmation sweep). **Decision: PASSED.**

**Sweep findings triaged** (each reproduced with Agent 2's own screenshot):
- M06-F-024 → **ETQAN-QA-217** (P3, UI-layout, easy). Deleting a pause and deleting a stopped weekly slot still act on one click, with no dialog and no toast. The ETQAN-QA-205 fix covered only Stop and End early. Repro on sub 105: added a pause 10–12/11 ("M06-gate2 delete test"), then "حذف" → "لا توجد إيقافات.", 0 dialogs, no toast (`screens/M06/triage/t023d-pause-before-delete.png`, `t023e-pause-deleted-no-confirm.png`). The slot delete runs the same code path (`SlotsPanel.tsx:289`, as `PausesPanel.tsx:221`), and Agent 1's F-024c shows it.
- M06-F-025 → **ETQAN-QA-218** (P3, RTL, easy). On the weekly schedules list and the admin Sessions list, "Arabic (Latin)" names wrap with the brackets mirrored ("Hamza Al-) حمزة القاضي" / "(Qadi"). These components are not covered by 209, 111 or 216 (`screens/M06/triage/t021-weekly-schedules-names.png`, `t022-sessions-list-names.png`).
- Not filed: on the EN parent top bar, "(Huda Al-Najjar) هدى النجار" is the ETQAN-QA-120 class (M03), so it links there.

**Gate criteria:**
- No P0, P1 or P2 is open in M06, and both new findings are P3.
- All 12 cycle-1 fixes stay VERIFIED. Agent 1's sweep re-walked them in AR, EN and AR 375 with no regression.
- The main jobs work for every role in AR and EN: admin, teacher, student and parent, per the gate smoke test and the sweep. Staff without subscription codes get the correct no-access page.

**Still open, for the next fix cycle (non-blocking):**
- P3 non-easy: ETQAN-QA-200, 201 and 202.
- P3 easy: ETQAN-QA-216, 217 and 218.
- P4: ETQAN-QA-215.

**State left:** on sub 105, a pause from 10/11 to 12/11 was added and then deleted, so the sub is back to 7 of 7 freeze days. No other data was changed, and the realistic subs 90–93 are untouched.

### M14 gate
- 2026-10-27T21:06:30Z, Agent 2. Decision: **PASSED** (no open P0/P1/P2; all 19 easy P3s fixed and verified in the browser; the teacher's main jobs work in AR + EN desktop and AR phone).
- Verified with before/after screenshots (`screens/M14/fix/ETQAN-QA-<id>-after.png` and `-before-after.png`): 400, 401, 402, 404, 405, 406, 407, 408, 413, 415, 416, 417, 418, 419, 420, 422, 425, 426, 427. EN checks: 400 (Today tab hint), 405, 407, 419 (`*-after-en.png`).
- Main jobs re-walked: sessions today/week (Join links on today's and tomorrow's sessions; I'm in gated with a hint), postpone dialog, report dialog (desktop + phone), withdrawal request with Arabic digits + cancel, availability overlap (AR/EN), homework list/open/new, levels, honour, payslips list/page/print, phone pass (availability, homework, payslip, reports, sessions). The teacher's Today view shows today's sessions (no 403 seen in the browser). A student opening /app/teaching/payslips is sent to the student home.
- Tests: scoped vitest (36 files, 367 tests) in `evidence/M14/gate-1/vitest.txt`. All M14 tests pass, including the two Agent 3 escalated (TeacherSessions postpone deadline, WithdrawalsPage no balance). 10 failures belong to other areas' in-progress work, not to M14: InvoicePage ×4, AdjustmentsList, RatesPage, payroll schemas ×2 (amount messages changed by the QA-300 decimals work), money.test formatSignedMoney (QA-311), PayslipsList (QA-350/356). The owning areas must clear them at their gates. M14's `latinDigits` doesn't cause them: the failures are message-key changes (`decimals0` vs `amountInvalid`) and a formatSignedMoney bidi mark.
- Diff review: TimesPanel (gate mirrors times.py `_gate`, no test hack), Confirm (optional labels, defaults unchanged), PrintSheet (Back, print:hidden), HomeworkDialog (teacher delete only when unanswered; text kind needs instructions), money.ts latinDigits. No backend/API/migration change. Nothing committed.
- Still open (by policy, not blockers): P3 non-easy 403 (payslip lines ISO date + frozen course language), 409 (stamped times not shown), 412 (past unmarked sessions look like future ones), 428 (phone levels table cuts the button); P4 410, 411, 414, 421, 423, 424.
- Data left: withdrawal 1.50 EGP "M14-G إعادة اختبار" (cancelled). The availability overlap tests were not saved.


### M14 final gate
- 2026-10-28T00:40:13Z, Agent 2 (sole authority). Decision: **PASSED** — no open P0/P1, no P2 at all (open or unfixed). The 3 new sweep findings are all P3/P4, so they do not block; ETQAN-QA-429 is an easy P3 and goes to the next run's fix cycle.
- Sweep triage (own repro shots in `screens/M14/triage/`): M14-F-033 → **ETQAN-QA-429** P3 UI-layout, easy (both "opens at…" hints repeat under every week row, 3 sessions per screen; `t040-week-hints.png`). M14-F-034 → **ETQAN-QA-430** P3 mobile, not easy (homework table 578 px in a 341 px scroller hides status/date/"فتح"; page itself stays 375 px so QA-426 holds; card-view proposal like 118/428; `t042-m-homework-open-offscreen.png`). M14-F-035 → dup of M07's open P4 **ETQAN-QA-272** ("لا يوجد رابط بعد" on an ended session; `t041-history-no-link-yet.png`).
- Re-checked live: Ahmad AR week + history, qa-teacher AR phone homework, Ahmad EN balance (`t043-final-en-balance.png`). The 19 gate-1 fixes stay VERIFIED (Agent 1's sweep re-confirmed them; nothing regressed except the new density issue 429 introduced by the 400 hint).
- Still open (non-blocking): P3 easy 429; P3 non-easy 403, 409, 412, 428, 430; P4 410, 411, 414, 421, 423, 424; plus 272 (M07-owned).

### M07 gate
- **When / who:** 2026-10-27T21:08:20Z, Agent 2 (sole gate authority). Retest of Agent 3's fix cycle 1 (11 bugs).
- **Checks run by me:** `vitest run` on 16 scoped files (SessionPage, AttendanceControls, SessionActivity, RevertDialog, AddSessionDialog, SessionClasses, postponing, TeacherSessions, PostponeDialog, PostponeDialog.errors, SessionsList, SimpleSessions, curriculum/ProgressPanel, locales): 172/172 passed. `tsc --noEmit`: 0 errors. Evidence is in `qa/manual/evidence/M07/gate/`.
- **Diff review** (`git -C dashboard diff`, branch `qa/manual-2026-10`, uncommitted):
  - Every fix is at the root cause, in the components themselves.
  - No test was weakened beyond the 3 expectations that changed with the new behaviour.
  - No backend, migration or API change.
  - New strings are in ar/en/es; curriculum keys are ar/en only, because es has no curriculum.json.
  - The escalated key `curriculum.progress.noLevels`/`noLevelsOffice` is correct in ar and en, with different teacher and office texts.
- **Browser retest** (before/after in `qa/manual/screens/M07/fix/ETQAN-QA-<id>-after.png`; desktop AR+EN plus mobile AR 375):
  - **250 VERIFIED:** "لا يوجد رابط بعد" shows on the session page and in the teacher's table. The 24 h hint shows only on future scheduled sessions (412), not on ended ones (362).
  - **251 VERIFIED:** toasts appear for mark, clear, cancel and restore on the session page, and for marks in the simplified view.
  - **252 VERIFIED:** the confirm dialog appears with a teacher body and a student body. Nothing is sent before Confirm. The activity entry is titled "إلغاء تسجيل الحضور". The student undo reopened 362 (completed → scheduled).
  - **253 VERIFIED:** the AR activity line reads "QA Admin · 2026/10/27 23:58" in order.
  - **254 VERIFIED:** Cancel is present and closes the Add session, make-up and student postpone dialogs.
  - **255 VERIFIED:** no "أُغلق التأجيل" on finished lessons (Maryam "السجل", 27/10 15:00 scheduled). "I'm in" on future rows is disabled with a hint (QA-400).
  - **257 VERIFIED:** the student postpone refusal shows in Arabic (400 from the server).
  - **262 VERIFIED:** Archive and Restore ask first with the count. The summaries read "أُرشفت: 1. تُخطّي: 0." and "استُرجعت: 1. …".
  - **264 VERIFIED:** the teacher (AR) and the office (EN) each see an explanation instead of an empty picker.
  - **269 VERIFIED:** "ملاحظات", "سبب الإلغاء" and "سبب وضعها تحت تصرف الإدارة" are labelled (AR and EN).
  - **270 VERIFIED:** the buttons read "الطالب حاضر"/"الطالب غائب", with the name in the aria label. The date field is 153 px wide and a toast appears.
- **Cross-role:** the office's marks show on the teacher's "حصصي" and the student's "حصصي" (حاضر). The parent home shows Adam's Tajweed at "1 من 8", which matches the present mark on 409. The subscription count went back after the undo in triage.
- **New at the gate:** ETQAN-QA-272 (P4 copy): the undo dialog's keep button says "إبقاؤها", and an ended session says "لا يوجد رابط بعد".
- **Transient:** one blank page on the sessions list while another area reloaded. It passed on retry, so it wasn't filed.
- **Data left as found:**
  - 362: marked and undone several times; it is back to scheduled / not_set / not_set.
  - 466 (M07-makeup-1): cancelled with the reason "M07 gate retest", then restored to scheduled. Its cancel reason stays in the DB.
  - 465: archived, then restored.
  - 412: postpone refused (400), so no change.
  - No realistic subscription was cancelled.
- **Decision: PASSED.**
  - No open P0, P1 or P2.
  - Every easy P3 is verified.
  - Still open, all allowed by scope:
    - P3 non-easy: 259, 260, 265, 266, 268, 271.
    - P4: 256, 258, 261, 263, 267, 272.
  - The area's main jobs (Today, list and filters, detail, mark and undo, postpone, make-up, cancel and restore, archive, simplified view, levels) work for office, teacher, student and parent in AR and EN.


### M07 final gate
- **When / who:** 2026-10-28T00:45:01Z, Agent 2 (sole gate authority), after Agent 1's confirmation sweep #2 (4 new findings, F-026..F-029).
- **Sweep triage** (own repro shots in `screens/M07/triage/`, each re-done in the browser and checked against the code):
  - M07-F-026 → **ETQAN-QA-273** P3 functional, not easy: "إضافة حصة" kind "إضافية" lists only the first 100 active students, no search (eval 101 options, no 236/232; `t026-extra-student-list.png`). Same family as QA-202/QA-371, different dialog.
  - M07-F-027 → **ETQAN-QA-274** P4 UI, easy: "الدقائق" required for "إضافية" but unstarred (`t027-extra-minutes-no-star.png`).
  - M07-F-028 → **ETQAN-QA-275** P4 UI, easy: cancelled session 474 shows the "الرابط" label blank; a gap left by the QA-250 fix (`JoinLink` returns null for cancelled before `showEmpty`). QA-250 stays VERIFIED (`t028-cancelled-link-blank.png`).
  - M07-F-029 → **ETQAN-QA-276** P3 UI, easy: simplified view disables all 18 "Student present/absent" buttons before start with no hint (`t029-simple-disabled-no-hint.png`).
- **Spot check:** teacher Maryam EN "My sessions" today: Join links, "Attendance opens at the start time." and "Check-in opens 15 minutes before…" hints, Postpone (`t-final-maryam-en.png`). Agent 1's sweep #2 re-walked office AR/EN, supervisor AR, teacher AR, student AR/EN, parent AR, and sub 91 counts (0 used / 8 left after undo, 1 of 8 after re-mark) — consistent with my earlier gate.
- **Data:** no change by me (read-only repro; the add-session dialog was submitted empty, nothing sent). 474 is Agent 1's own cancelled+archived extra session.
- **Decision: PASSED.** No open P0, P1 or P2; no new P2 in the sweep. The main jobs (Today, list/filters, detail, mark/undo, postpone, make-up, extra, cancel/restore, archive, simplified view, missing reports, supervision, reviews, levels, homework) work for office, supervisor, teacher, student and parent in AR and EN. Open, allowed by scope: P3 easy 276 (new, next fix cycle); P3 non-easy 259, 260, 265, 266, 268, 271, 273; P4 256, 258, 261, 263, 267, 272, 274, 275. Note: 273 blocks the "extra" kind for students outside the first 100 — fix it with QA-202/QA-371 (shared searchable student picker).

### M09 gate
- **Decision: PASSED** (2026-10-27T21:12:05Z, Agent 2). No P0/P1/P2 were filed for M09. 12 of the 13 fixes are verified in the browser with before/after composites (`screens/M09/fix/ETQAN-QA-<id>-after.png`). The main jobs work for admin AR+EN and teacher AR, desktop and 375px: rates, fixed salary, adjustments, generate, payslip detail/print link, issue/mark paid, pay to balance, withdrawals (request, approve, reject dialog, pay dialog, cancel), projections, and the salary expense on the finance side.
- **Verified (12):** 350, 353, 356, 358 (all 3 sites), 360, 363, 364 (office + teacher), 366, 367, 368, 370, 373.
- **Reopened (1):** ETQAN-QA-351, easy P3. The back link and the label are fixed. The note value is `dd dir=auto` spanning 4 columns, so a Latin note sits at the far left, about 1,000px from its right-aligned label. It goes to the next fix cycle; it doesn't block the gate (P3).
- **Still open (11, all P3 non-easy / P4, by design):** 352, 354, 355, 357, 359, 361, 362 (P4), 365, 369, 371, 372.
- **Amounts checked:** the PAY-000003 net of 120.00 equals 2×60 min at 60/h, and the expense of 120.00 ج.م. matches it. Teacher PAY-000001 is 60+45+30 = 135.00 at 60/h. QA6 Teacher B's projection of −1,000 equals 3,000 fixed − 4,000 deduction. The withdrawal approve/cancel brought the teacher's available balance back to 159.00.
- **Diff review:** the fixes are at their root causes and nothing hacks around a test. The `Confirm` props are additive with defaults unchanged. `formatMoney` only rewrites an Arabic negative that carries the LRM-minus. Backend: titles only; the old expenses are untouched.
- **Tests (`evidence/M09/gate-1/`):**
  - tsc exit 0. Backend payroll pytest: 439 passed.
  - Scoped Vitest (payroll + lib/money + Confirm + server-messages): 182 passed, 5 failed. **None of the 5 is an M09 defect:**
    - 4 assert the old billing amount message after M08's QA-300 change (`billing.errors.decimals0` vs `amountInvalid`): AdjustmentsList, RatesPage, schemas.test ×2.
    - 1 is M08's QA-311 `formatSignedMoney` test (`money.test.ts:70`), which expects a plain space where Intl gives a NBSP.
  - **Escalated to M08's fixer:** update those expectations.
- **Proposals:** QA-368, the spec wording ("receipt" → "payslip" in the B4/B4c specs), is ACCEPTED as a PROPOSAL for the owner. QA-358, durable server error codes, is covered by the existing coverage-gaps proposal.
- **Data changed (M09 only):**
  - PAY-000003 (F10 Teacher Three, Sep 2026, test teacher) marked PAID 2026-10-28 with note 'M09-G gate pay', which posted the salary expense.
  - Sep and Oct 2026 drafts regenerated.
  - qa-teacher withdrawal 'M09-G1 gate' 1.00 was created, approved, then cancelled.
- **Incident:** during cleanup I cancelled M14's request 'M14-C تأكيد' (qa-teacher, EGP 1.50, Oct 28) by mistake; a new row had appeared at row 0. It can't be undone; M14 should re-create it if needed. Logged in `logs/M09/agent2.md`.

### M09 final gate
- **Decision: PASSED** (2026-10-28T00:42:39Z, Agent 2, final). No open P0, P1 or P2 in M09 — none was ever filed, and the confirmation sweep found none.
- **Confirmation-sweep findings triaged (own repro shots in `screens/M09/triage/`):**
  - M09-F-033 → **not a bug.** Measured glyph positions on PAY-000007 AR: the negative report deduction has the same layout as positives (currency left of the digits) with the minus directly before the digits — exactly the verified ETQAN-QA-360 output, same `Money` component as the adjustment line.
  - M09-F-034 → **dup of ETQAN-QA-403** (stored line text: ISO date + academy language; AR date shows "02-09-2026" after the Arabic label, EN line stays Arabic). Goes with 403's structured-fields proposal.
  - M09-F-035 → **ETQAN-QA-374** (P3, easy): teacher cancel, office approve and office pay dialogs name neither teacher nor amount.
  - M09-F-036 → **ETQAN-QA-375** (P4): teacher "رصيدي" card amount not aligned with date/note when the note is wider.
- **Open for the next fix cycle (none blocks the gate):** easy P3 351 (reopened at gate-1) and 374 (new); P3 non-easy 352, 354, 355, 357, 359, 361, 365, 369, 371, 372; P4 362, 375.
- **Main jobs re-checked, every role, AR + EN:** Agent 1's sweep (admin AR/EN: payslips, detail + print, rates, fixed salary, adjustments, rules, generate, projections, withdrawals approve → pay, expenses; teacher AR/EN + mobile AR: payslips, detail, balance, request + cancel) plus my own run today: admin AR + EN PAY-000007 detail (180.00 − 3 × 6.00 = 162.00 net ✓), teacher AR request 1.00 → available 157 → 156, office approve → pay dialog → cancel → available back to 157.00 ✓.
- **Data changed (M09 only):** qa-teacher withdrawal "M09-G2 فرز" 1.00 created, approved, then cancelled (my own row, matched by note). Nothing paid, no payslip touched.

### M08 gate
Agent 2, 2026-10-27T21:15:46Z. **Decision: PASSED.**

**Fixes verified (fix cycle 1).** Each was re-walked in the browser. BEFORE/AFTER composites are in `qa/manual/screens/M08/fix/<BUG>-after.png`; the raw AFTER shots are `*-after-raw.png` plus extra shots (`-en`, `-mobile`, `-attention`, `-sublink`, `-table`).
- VERIFIED: ETQAN-QA-300, 301, 302, 303, 306, 307, 308, 310, 311, 312, 313, 314 (dashboard) and 316. M08-F-012 (dup of 311) is covered.
- 311: the wallet statement was checked by measuring glyph positions. The signed amounts have the same layout as the unsigned balance. The home negative net-profit case can't be reproduced with live data (profit is positive now), so it rests on `money.test.ts` and Agent 3's probe.

**Proposals judged (all accepted, none is P0/P1):**
- ETQAN-QA-314 API part: a billing-owned student lookup gated by `invoice.create`. The P2 is resolved on the dashboard: the clerk now gets a clear explanation instead of a silent empty picker, and an admin can grant `student.view_any`. The lookup itself needs an API change, which is outside Agent 3's rules.
- ETQAN-QA-307 USD "$": a product decision, because changing it touches every amount in the app.
- ETQAN-QA-313 follow-up: store only the subject on the server and render the label when it is read (CSV included). The client-side mapping is accepted as an interim fix.

**Code review** (`git -C dashboard diff`, branch `qa/manual-2026-10`, uncommitted, backend untouched):
- The fixes are at the root cause or are reasonable interim fixes. No test was weakened or skipped, and nothing was committed.
- The four payroll expectations changed from "above zero" to the decimals message. That is correct, because payroll reuses billing `amount()`.
- Shared files (money.ts with QA-360/404, PrintSheet with QA-420, Confirm.tsx, locales) keep the other areas' changes.

**Tests re-run by Agent 2:**
- Vitest over billing, wallet, gateways, finance, payroll, vouchers, home(work) and lib/money: 772 of 775 passed. The 3 failures were 5 s timeouts under parallel load (SubscriptionInvoices, WithdrawalsPage, NewHomeworkDialog). Re-run alone, all 4 files pass (33/33).
- Evidence: `qa/manual/evidence/M08/gate/vitest.txt`, `vitest-rerun.txt`.

**Main jobs by role (AR + EN):**
- Admin: invoice detail, record payment validation, print, payment records, online payments, exchange rates.
- Billing clerk (role 34): invoice detail, plus the New invoice explanation.
- Anonymous payment link: AR and EN.
- Parent:
  - wallet, statement and top-up dialog;
  - invoice list on desktop and 375 px;
  - **pays INV-000165 on mobile AR**: checkout 1,049.75 + 5% fee 52.49 = 1,102.24 → simulator "ادفع" → return "تم الدفع" → invoice "مدفوعة", paid 1,200.00, 0.00 due, Stripe row with fee 52.49 (`screens/M08/fix/gate-mobile-parent-*.png`).
- Agent 1 already covered student code redeem, wallet spend, partial, full, over-payment, refund and void, and the money math was correct.

**Still open (allowed by scope: P0–P2 plus easy P3s):**
- P3 non-easy: ETQAN-QA-304 (second invoice for an invoiced subscription, no warning), 305 (payment reference not in records or search), 309 (payment-link return page dead end), 315 (phone invoices table overflow / filters).
- P4: 317 (system code wraps).

### M08 final gate
- **Decision: PASSED** (2026-10-28T00:48:17Z, Agent 2, final). No open P0, P1 or P2: the only P2 (ETQAN-QA-314) was fixed and verified at gate 1, and the confirmation sweep found no new P0–P2.
- **Confirmation-sweep findings triaged (own repro shots in `screens/M08/triage/F-02x-repro.png`):**
  - M08-F-020 → **ETQAN-QA-318** (P3 translation, easy): new link KWD 5.125 via Stripe → raw English "This payment method cannot take this amount." under the gateway field (400 on `POST /api/v1/gateways/links/`). Class of QA-206/157/358/257, new screen.
  - M08-F-021 → **ETQAN-QA-319** (P3 UI/copy, easy): office sees the family-worded "ادفع محليًا … ثم أخبر الأكاديمية لتسجّل دفعتك." card on INV-000178 (AR + EN).
  - M08-F-022 → **ETQAN-QA-320** (P4 copy, easy): student toast "طُبّق خصم بقيمة 100.00 ج.م.." (double stop). Amounts right: 20.00 + 100.00 paid, 80.00 left.
  - M08-F-023 → **ETQAN-QA-321** (P3 RTL, easy): EN "Pay locally" card shows the Arabic instructions LTR, phone number mid-sentence.
- **Open for the next fix cycle (none blocks the gate):** easy P3 318, 319, 321; P3 non-easy 304, 305, 309, 315; P4 317, 320.
- **Main jobs, every role, AR + EN:** Agent 1's sweep (admin AR/EN invoices list, SAR invoice partial/overpay-blocked/full/refund, print, payment records, links KWD 5.120 → anonymous → simulator paid, codes, rates, home money card; parent EN online pay + pay-from-balance + KWD fee rounding; parent AR mobile simulator pay; student AR code apply + reuse refused; clerk EN new-invoice explanation + record payment) plus my own run today: admin AR links form + invoice detail, admin EN invoice detail (200.00 / 120.00 / 80.00 ✓), student AR code apply (100.00 off ✓).
- **Data changed (M08 only):** INV-000178 discount SYS-NT8DT-4BX7D removed (code voided, reason "M08-G2 gate repro") and SYS-DSNF8-SCZYH (100.00 ج.م.) applied by Omar instead. No link created (5.125 refused).

### M12 gate
Agent 2, 2026-10-28T01:50:25Z. **Decision: PASSED.**

**Fixes verified (fix cycle 1, Agent 3).** Each one was re-walked in the browser (sessions `M12-g-admin-ar`, `M12-g-admin-en`, `M12-g-nocode-ar`). The BEFORE/AFTER composites are in `screens/M12/fix/<BUG>-after.png`, the raw AFTER shots in `*-after-raw.png`, and the working shots in `g0xx-*.png`.
- **VERIFIED (12):** 500, 501, 505, 506, 507, 508, 510, 511, 512, 513, 514, 515.
  - **500:** AR and EN branding errors are translated: the colour message, plus "هذا الحقل مطلوب." / "This field is required." for an empty name. Nothing was saved.
  - **501:** the social labels read لينكدإن / سناب شات / ساوند كلاود.
  - **505:** the عرض / عرض الكل hint shows above the matrix, on desktop and at 375 px.
  - **506:** as nocode holding role 35, ticking الفواتير › عرض الكل returns a 403, and no role is created. The refusal is shown in Arabic three ways:
    - above the tabs;
    - in a line naming the code ("صلاحيات لا تملكها: الفواتير: عرض الكل.");
    - in a toast by Save.
  - **507:** retiring asks first ("إيقاف M12 مشاهد الطلاب؟", members (1)). Cancel sends nothing, and confirm retires the role. Restore stays one click.
  - **508:** نشط / موقوف status with إيقاف / استعادة actions.
  - **510:** the failed run reads "استغرق التشغيل وقتًا طويلًا فأُوقف. شغّله مرة أخرى."
  - **511:** the code sits at the start of the card, above its description.
  - **512:** `abc` is refused in the form, with an Arabic message. The backend refuses `abc` and `ب` and accepts ⭐ 🇸🇦 1️⃣; this was checked in a shell inside a rolled-back transaction. Tag names now line up in one column.
  - **513:** the page has its gutter at 1440 and at 375.
  - **514:** the AR heading reads الحصص (the academy page has no الجلسات), and the EN timezone warning says "Sessions…". The timezone was not saved: qa is still Africa/Cairo/EGP.
  - **515:** one Arabic error under the field names {foo}. This was tested with preview only.
- **Code review** (`git -C dashboard|backend diff`, branch `qa/manual-2026-10`, uncommitted):
  - The fixes are at the root cause. No test was weakened or skipped, there are no migrations or API shape changes, and nothing was committed.
  - The only backend change is `_check_emoji`. It runs on create, and on update only when the emoji changes, so older tags can still be renamed.
  - The server English sentences are mapped in `lib/server-messages.ts`. That is an interim fix, with stable codes as proposals.
- **Tests re-run by the gate:**
  - Vitest: 27 files, 168 tests pass (all of Agent 3's regression files plus access, academy and lib).
  - Locale tests: 13 pass.
  - `tsc --noEmit`: exit 0.
  - pytest `test_tags_api.py` + `test_tags.py`: 40 pass.
- **Proposals accepted** (`qa/coverage-gaps.md`): 506 (disable or mark unheld codes, plus a stable 403 code); 508 (active roles first and a name search, for the owner to decide; the نشط filter covers it for now); 510 (JobRun error_code); 515 (placeholder names as data); the 512 note (cleaning up the old text emoji on `ب` and `abc`).
- **Still open, not blocking:** none of these is P0–P2, and none is an easy P3, so they are outside this cycle's fix scope.
  - P3 non-easy: 504 (role matrix size), 509 (Google half-saved), 516 (integrations copy), 517 (Etqan billing usage line).
  - P4: 502 (file pickers), 503 (features "once built" copy).
- **Roles:**
  - The admin works in AR and EN, on desktop and mobile.
  - A staff member gets exactly what an assigned role gives. Nocode with role 35 saw الطلاب and الأدوار only, and could not escalate.
  - With no roles, nocode gets the Arabic "ليس لديك صلاحية…" page on settings.
- **BLOCKED:** live Google sign-in, and live gateways and integrations (no credentials). Their state was shown only.
- **State restored:**
  - Role 35 is retired again, through the confirm.
  - qa-staff-nocode has 0 roles (checked in the DB).
  - Tag count is 51, unchanged.
  - The qa academy is still Africa/Cairo/EGP.
  - No branding or template was saved.

### M12 final gate
**Decision: PASSED** (2026-10-28T02:12:09Z, Agent 2, sole authority).
- **Confirmation sweep:** Agent 1, after fix cycle 1. All 12 fixes still hold (500, 501, 505, 506, 507, 508, 510–515), in AR, in EN and on a 375 phone. The sweep reported one new finding.
- **M12-F-022 → ETQAN-QA-518, P3, RTL, easy:**
  - Branding (AR): the empty WhatsApp field's example reads "966501234567+".
  - Agent 2 reproduced it on qaother (`screens/M12/triage/fg022-whatsapp-field.png`, `fg022-branding-form.png`).
  - A typed "+966501234567" displays correctly (`fg022b-whatsapp-typed.png`, nothing saved), so only the placeholder is wrong.
  - It is a side effect of the verified ETQAN-QA-060 plaintext-bidi fix on `Input`. It is not a duplicate.
  - It is P3, not P2, so it does not block. It is an easy P3 for the next fix cycle. `RegisterForm.tsx:278` probably has the same placeholder.
- **Still open, not blocking:**
  - Easy P3: 518.
  - P3 non-easy: 504, 509, 516, 517.
  - P4: 502, 503.
  - There is no open P0, P1 or P2, and no unfixed P2.
- **Smoke check at the final gate:**
  - Admin in EN: the roles list loads (`screens/M12/triage/fg-smoke-roles-en.png`).
  - Admin on qaother in AR: branding loads.
  - The sweep covered the rest: admin, staff with codes and staff without codes, in AR and EN, on desktop and phone.
- **BLOCKED:** live Google sign-in, and live gateways and integrations.
- **State checked in the DB:** qa is Africa/Cairo/EGP and qaother is UTC/USD. Agent 1 reports that role 35 is retired with 0 members and that nocode has no roles. No branding was saved by the gate.

### M15 gate
**Decision: PASSED** (2026-10-28T02:15:16Z, Agent 2, sole authority).
- **Fix cycle 1 (Agent 3), 13 bugs retested in the browser.** Before/after pictures are in `qa/manual/screens/M15/fix/<BUG>-after.png`.
  - **Verified (11):** 450, 455, 458, 459, 460, 461, 462, 464, 465, 467, 468.
  - **451 (P2):** the UI part is verified. Unpaid bookings read "بانتظار الدفع" with "ادفع الآن". CR-000002 was then paid end to end through the simulator (SIMULATED, 200.00 EGP) and the list switched it to "قيد المراجعة".
  - **451 proposal accepted:** the ~25 h before an abandoned booking is cancelled is the documented rule (consultations.md §5) and needs a gateway-flow change. The owner decides (coverage-gaps.md § M15 Agent 3 fix cycle 1).
  - **466 is reopened and the fix rejected.** The back button works and the Arabic message is no longer slanted. But the new `dir="auto"` makes a message that starts with a Latin character (the issued "M15- مبارك يا آدم…") print LTR, with the period in front of "مبارك". It is an easy P3 for the next cycle.
- **Diffs reviewed** with `git -C dashboard diff` and `git -C backend diff`. There are no test hacks.
  - The only backend change is a read-only `starts_at` on the reviews' `_session_ref`, with no migration.
  - The ReviewEditor guard is a ref, released in `finally`.
  - The progress `?student=` value is filtered to the parent's own children. A Sharif id (232) in the URL falls back to Adam and sends no request for 232.
  - Minor: `PrintBackButton` duplicates QA-420's inline back button in `PrintSheet`. This is cosmetic.
- **Tests** (`qa/manual/evidence/M15/gate-1/`):
  - Vitest scoped run: 33 files, 231 tests.
    - All passed except 2 BookingWizard tests in the parallel run, then ProductDialog/RequestDialog (3) in a rerun. All of these were 5 s timeouts at load average 27.
    - Each passes alone or serially: BookingWizard 8/8; ProductDialog + RequestDialog 28/28.
    - ProductDialog belongs to another area.
  - tsc exit 0.
  - pytest learning `-k review`: 69 passed.
  - The docker stack was stopped by someone else for about 3 minutes during the run and came back on its own.
- **Roles and languages checked:**
  - Student (qa-student@): AR desktop, EN desktop, AR 375.
  - Parent (parent.najjar@): AR desktop, EN desktop, AR 375 Home.
    - Switching between the two children works.
    - Another family's id is ignored.
    - The certificate print and back work.
  - Teacher on `/app/learning/*`: dup of M10-F-028 (silent redirect, no data shown), unchanged.
- **Still open, not blocking:**
  - P3 easy: 466 (reopened).
  - P3 non-easy: 452, 453, 454, 456, 457, 463.
  - P4: 469, 470.
  - There is no open P0, P1 or P2.
- **BLOCKED:** live Stripe/PayPal (the simulator only), WhatsApp and Zoom.
- **Data left by the gate:** review id 6 (session 278, "M15-gate: …"); consultation CR-000002 paid in the simulator (fee charged as configured).

### M15 final gate
**Decision: PASSED** (2026-10-28T12:31:55Z, Agent 2, sole authority). No open P0, P1 or P2.
- **Agent 1 confirmation sweep (run 3)** re-walked student AR/EN/375, parent Najjar AR, parent Sharif AR/EN/375 and teacher. All fixes from cycle 1 held (450 receipt fee, 451 chips, 465 child switch, 468 child-named empty state). Four online payments went through the SIMULATOR end to end (INV-000085, INV-000081 after a decline, INV-000178 as a parent, INV-000143 on a phone) and turned paid with a receipt; INV-000094 paid from the wallet; CR-000001 paid. Another family's INV-156 URL shows "لم نعثر على هذه الفاتورة".
- **New findings triaged (own screenshots in `qa/manual/screens/M15/triage/final/`):**
  - M15-F-030 → **ETQAN-QA-471** (P3 copy, easy). Reproduced with a fresh booking CR-000004: an abandoned checkout, the hold moved 2 h back in the DB to stand in for the wait, and the page still read "موعدك محجوز حتى 28/10/2026, 13:30." at 15:30 Cairo. Data is safe: `paying.rehold` re-holds or refuses with `slot_taken`, so it is not a P2. The Latin-comma date on that page is folded in.
  - M15-F-031 → **ETQAN-QA-472** (P3 mobile, easy). Reproduced at 375 on `/app/invoices/143/print`: the 100.00 and 680.00 amounts wrap onto their own lines under long labels.
- **Still open, not blocking:** P3 easy 466 (reopened), 471, 472; P3 non-easy 452, 453, 454, 456, 457, 463; P4 469, 470. These go to the next fix cycle.
- **Teacher on `/app/learning/*`:** silent redirect, no data (dup of M10-F-028), unchanged.
- **BLOCKED:** live Stripe/PayPal (simulator only), WhatsApp and Zoom.
- **Data left by the final gate:** CR-000004 (unpaid, its simulator checkout set to expired so `cancel_unpaid` cancels it).

### M10 gate
- **When / who:** 2026-10-28T02:18:37Z, Agent 2 (sole gate authority). Retest of Agent 3's fix cycle 1 (15 fixed, 1 not a bug).
- **Environment note:** the etqan stack was found stopped (all containers Exited ~2 min, not by this agent) at the start; restarted with `dc.sh up -d --no-build` per README, `/health/ready/` 200.
- **Verified in the browser (15 → 14 VERIFIED):** 600 (Cancel, AR+EN, closes), 603 ("193 بايت · …"), 606 (موظف/Staff), 608 (Arabic field error, no POST), 609 (RTL email + button, new gate broadcast in Mailpit), 611, 612, 613, 614 (confirm names "F10 group"), 616, 617 (email lines isolated), 620 (375 px: 16 px gap both sides), 621, 622 (both toasts). Before/after: `screens/M10/fix/ETQAN-QA-6NN-after.png`; raw shots `screens/M10/fix/gate/`.
- **Reopened:** ETQAN-QA-618 (P3 easy). The link goes to `#notifications`, but clicking it from the templates page lands at scrollY 259 with the section 1,184 px lower (AR and EN, 4 of 5 runs). Only a direct load works. The scroll fires before the academy form above has rendered.
- **New at the gate:** ETQAN-QA-623 (P3, RTL, easy), a side effect of the 609 fix. In the now-RTL Arabic email footer the home link shows as "/http://qa.etqan.localhost".
- **Not a bug, accepted:** 604 (and the dashboard half of 617). dir=auto is on every surface, and what is shown is UAX #9 first-strong output, the same as in the writer's composer.
- **Tests re-run by the gate** (`evidence/M10/gate-1/`): vitest chat + notifications + locales 21 files / 218 pass; pytest notifications + chat + site 1346 pass, plus identity/integrations `-k email` 171 pass; tsc 0 errors.
- **Diff review:** the changes are scoped. There are no test hacks and no migration or API change. `brand_email` gains optional kwargs (backward compatible), and the plain-text part keeps the link line. Other areas' hunks in shared files (bell 103, bits 102, TemplateDialog 515) were left alone. Nothing committed.
- **Main jobs smoke:** admin AR/EN chat and picker, groups dialog, broadcasts (sent "M10-gate" to F10 group, Mailpit only), notification log, templates/settings. Teacher mobile AR chat send works, the bell works at 375 px, and student3 sees the can't-start line. Parent `/app/chat` → "المحادثات غير متاحة لك." (parents never in chat). Agent 1's walk covered the EN sides.
- **Decision: PASSED.** There are no P0–P2. The open items are easy P3s 618/623 (next fix cycle, as for M07/M08), non-easy P3s 601/619, and P4s 602/605/607/610/615. Web push and WhatsApp live are BLOCKED (no VAPID or credentials).
- **State left:** broadcast "M10-gate: موعد الحصة 6:00 PM…" to F10 group (3 Mailpit emails). Chat message "M10-gate رسالة من المعلم ✅ test" in c=2. Student 33 can_start restored to on, and the teacher has no opt-outs (DB checked). No templates changed.

### M10 final gate
- **When / who:** 2026-10-28T12:27:34Z, Agent 2 (sole gate authority), after Agent 1's confirmation sweep (sweep found 3 new findings, F-035..F-037).
- **Triage of the sweep (own repro shots in `screens/M10/triage/`):**
  - M10-F-035 → **ETQAN-QA-624** (P3, RTL, easy): bell and notifications page lay a Latin-led mixed broadcast body in the Arabic title's direction ("PM. Please be on 6:00"); residual of 617 (email fixed, in-app notice not). `fg035-bell-mobile.png` (375 AR).
  - M10-F-036 → **ETQAN-QA-625** (P3, translation, easy): group with 0 participants → raw English "A group has 1 to 200 participants." (400, nothing created); residual of 608. `fg036-group-no-participants.png`.
  - M10-F-037 → **ETQAN-QA-626** (P4, copy): empty group thread is blank, no "لا رسائل بعد". `fg037-empty-group-thread.png`.
- **Re-verified:** ETQAN-QA-618 (was reopened) — in-app link from templates lands at the notifications section, AR and EN (top 0 both; Agent 1's sweep the same). No new code since cycle 1; now **VERIFIED** (`fg618-retest.png`, `fg618-retest-en.png`).
- **Main jobs (all roles, AR + EN):** Agent 1's sweep re-walked chat admin↔teacher (AR+EN), teacher↔student (student AR 375), PDF attach, unread badges, groups, moderation, bell/notifications page EN, preferences, templates, log, broadcast to F10 group (Mailpit 3 emails), real trigger (absent → parent bell + email). Gate re-checked: student bell 375 AR, admin groups dialog AR, templates → settings AR + EN, parent `/app/chat` → "المحادثات غير متاحة لك." (parents never in chat).
- **Decision: PASSED.** No open P0/P1 and no P2 (none ever filed in M10). The new items are P3/P4 only; easy P3s 623, 624, 625 go to the next fix cycle; 601, 619 (non-easy P3) and P4s 602, 605, 607, 610, 615, 626 stay open outside fix scope. Web push and WhatsApp live BLOCKED (no VAPID / credentials).
- **State left:** no new data except the 400 refused group attempt (nothing created). Sweep data as listed in `findings/M10.md`.

### M05 gate
- **Decision: PASSED** (2026-10-28T02:19:52Z, Agent 2). No P0/P1/P2 was filed for M05. All 15 easy P3s from fix cycle 1 are VERIFIED in the browser; before/after pairs are `screens/M05/fix/ETQAN-QA-<id>-before.png` / `-after*.png`.
- **Verified (15):** 551 (courses, packages, recorded, videos and consultations filters show a visible label; courses/packages offer نشط/غير نشط), 552 (AR courses + EN packages: "nothing matches" + clear button), 553 (deleted copy 14 → back on the list with a toast, no 404 refetch), 556 (desktop + 375 AR), 560 (AR + EN), 561 (verses range, no-chapter, .exe type, recorded slug, all in Arabic), 562 (hint + link; chapter list stubbed to [] in the browser because `qa` is synced and `qaother` has levels off), 563 (dialog title and picker "1 - الفاتحة" / EN "1. Al-Fatihah"), 567 (LTR isolate, renders intact), 568, 569, 570 (dialog jumps to التفاصيل with an Arabic sentence; backend raises the sentence before full_clean), 571 (AR + EN), 572, 573 (levels and Qur'an at 375 now scrollWidth 375, was 451/555).
- **Tests (`evidence/M05/gate-1/`):** `pnpm tsc --noEmit` exit 0 (the re-run Agent 3 owed after Biome). Vitest over catalogue, curriculum, content, recorded, consultations ProductDialog/ProductsAdmin, locales, lib: 63 files / 384 tests passed. Backend `pytest etqan/consultations`: 388 passed.
- **Diff review:** the fixes are at their root causes and none hacks around a test. FilterSelect is a new additive component. The delete mutation invalidates only the lists. The server-message map holds only fixed sentences, and the range sentence that carries a number is checked client-side. The backend `_check_description` mirrors the DB check and raises on the same field (`description_en`), with no migration and no API shape change. Minor: the service also rejects whitespace-only descriptions, which the DB check would accept. This is stricter and harmless.
- **Proposals:** 562 follow-up (sync chapters at academy creation) is ACCEPTED as a PROPOSAL for the owner, because it changes documented behaviour. 561 follow-up (API error codes) is ACCEPTED as a PROPOSAL. The 567 note about bare https:// in `ar/website.json` and `ar/scheduling.json` belongs to those areas.
- **Still open (10, non-easy P3 / P4, outside the fix scope):** 550, 554, 555, 557, 558, 565 (P3); 559, 564, 566, 574 (P4).
- **Main jobs re-checked:**
  - Admin AR + EN, desktop: courses, packages, levels, Qur'an chapters, content, recorded courses and videos, consultations.
  - Mobile AR (375): packages list and form, levels, Qur'an.
  - Teacher AR: materials list. The catalogue/levels URL redirects home by design.
  - Student AR: recorded-course store with EGP prices.
  - Money and minor units in the subscription form and invoice were verified at triage and are unchanged by these fixes.
- **Data changed (M05 only):**
  - Course copy 14 was created and deleted.
  - Link material "M05 gate link" was created and deleted.
  - Level, recorded-course and consultation saves were refused by validation, so nothing was created.
  - Packages in data.md were not touched.

### M05 final gate
- **Decision: PASSED** (2026-10-28T12:29:33Z, Agent 2), after Agent 1's confirmation sweep (`findings/M05.md` § Confirmation sweep, shots `screens/M05/sweep/s01–s44`).
- **New from the sweep (1):** M05-F-036 → **ETQAN-QA-575** (P3, UX, easy): the subscription form accepts one weekly slot for a 3-sessions-a-week package with no hint; sub 110 promises 24 sessions in 2 months with one Saturday slot (≈9 possible), INV-000181 bills all 24. Reproduced with my own shots `screens/M05/triage/t036-form-no-warning.png` (form filled, not submitted: no warning) and `t036-sub110.png`. Not a dup (no register entry on slots vs sessions per week). Not P2: the docs set no slot-count rule, nothing is mis-stored or mis-billed against the package, and the admin can add slots later; it is a missing warning.
- **Verified (unchanged, 15):** 551, 552, 553, 556, 560, 561, 562, 563, 567, 568, 569, 570, 571, 572, 573. The sweep re-walked all of them in AR/EN and found them still right; no new code since gate-1.
- **Main jobs (all roles, AR + EN):** admin AR + EN courses, packages, country prices (EG→1800.00 EGP, US→450.50 SAR in the subscription form; INV-000181 45050 minor SAR), levels, Qur'an, content, recorded videos, consultations; mobile AR packages/courses/levels/Qur'an; teacher materials/levels/consultations; student recorded store and booking prices; staff-codes no access (by design). All work.
- **Status rule:** no open P0/P1, no P2 ever filed in M05. 575 (easy P3) goes to the next fix cycle; 550, 554, 555, 557, 558, 565 (non-easy P3) and P4s 559, 564, 566, 574 stay open outside fix scope.
- **Data changed at this gate:** none (the form repro was not submitted). Sweep data left by Agent 1: package 22 "M05 باقة المسح" (+EG price), sub 110 + INV-000181 unpaid, draft video M05SW1, consultation "M05 استشارة المسح". Packages in data.md untouched.

### M01 final gate (cycle 2)
- **When / who:** 2026-10-28T16:05:12Z, Agent 2 (sole gate authority). Retest of Agent 3's fix cycle 2 (6 fixed: QA-012, 806 reopened, 827, 828, 829, 830; 0 proposals). Agent 3's report was not trusted: each original step was re-walked in the browser as the right role.
- **Tests re-run by the gate:** pytest `tenants/tests/test_admin_permissions.py`, `tenants/tests/test_admin_console_qa.py`, `etqan_billing/tests/test_admin_console_qa.py`, `etqan_billing/tests/test_admin.py`, `identity/tests/test_console_users.py`: 54 passed (`evidence/M01/gate-2/pytest-scoped.txt`). Vitest auth-layout + branding + shell: 99 passed (`gate-2/vitest.txt`). ruff check/format on both admin files and their tests: clean (`gate-2/ruff.txt`).
- **Diff review:** `tenants/admin.py`: `self.fields.get(...)` guards plus one `@admin.display(boolean=True)` per feature, set on `AcademyAdmin` (read-only pages only; editable pages still use the form fields); `format_html` escapes `<subdomain>`. `etqan_billing/admin.py`: "· " prefix dropped; `quantity_shown`/`free_quantity_shown` ("—" for manual/credit). Confirm template: `<bdi dir>` from `get_current_language_bidi`. Dashboard: `min-w-0 wrap-anywhere` on `BrandWordmark` (also used by the top bar, checked), header `gap-2`, toggles `shrink-0`. The regression tests assert behaviour: rendered HTML for 806 and 830, exact message for 828, table cells for 829, status 200 with no `_save` and a False icon for 012. No test hacks, no migration or API change, nothing committed.
- **Verified in the browser (6 + 1 re-confirmed); before/after in `screens/M01/fix/`:**
  - **ETQAN-QA-012** (as `ops-view@`): academy 19 → 200 "View academy", 0 submit buttons, every switch shown as an icon; the 7 "on" icons match the superuser's 7 checked switches. All 18 academy pages and Domains → 200. A forged POST → 403, academy unchanged. Shots: `ETQAN-QA-012-after.png`, `g2-012-*.png`; before `g-view-academy-readonly.png`.
  - **806:** the help text shows "…becomes <subdomain>.etqan.localhost…"; Subdomain is bold/required; an empty submit shows "This field is required." Shots: `ETQAN-QA-806-after-cycle2.png`, `g2-806-*.png`; before `g-806-add-form.png`.
  - **827:** suspended qa-tmp-m01a at 375 px: AR and EN both 375/375 (was 397). The host name wraps (mid-word, acceptable). Active qa login and the top bar did not regress. Shots: `ETQAN-QA-827-after-ar.png`, `-en.png`, `g2-827-*.png`; before `triage/t029`.
  - **828:** Void on the already-void ETQ-2026-10-0002 → "ETQ-2026-10-0002: already void; nothing changed."; the Issue error path has no dot either. Shots: `ETQAN-QA-828-after.png`, `g2-828-issue-on-void.png`; before `triage/t030`.
  - **829:** the invoice 13 manual line shows "— — — 12.50 USD"; the usage counts are kept. No line ≥ 1,000 exists, so the thousands separator is covered by the test only. Shots: `ETQAN-QA-829-after.png`, `g2-829-*.png`; before `triage/t031`.
  - **830:** the qa-tmp-m01c copy-features confirm reads "أكاديمية الفجر QA Tmp M01c — …" (`bdi dir=ltr`). It was left unconfirmed. Shots: `ETQAN-QA-830-after.png`, `g2-830-confirm-page.png`; before `triage/t032`.
  - **800 (P1) re-confirmed VERIFIED:** the Add user form has password1/password2; the change page shows a read-only argon2 hash and Reset password; DB ids 9 and 10 are argon2; the gate staff user signs in. Shots: `g2-800-recheck-*.png`.
- **Roles / languages:** superuser ops@: add form, academy actions with confirmation, billing invoice actions, invoice page, users all work. View-only ops-view@: academy list, every academy page read-only, Domains, forged write refused. Academy side AR+EN at 375 px and desktop. The console is English; Arabic names are whole.
- **Decision: PASSED.** No open P0/P1; both P2s (801, 802) verified; no unfixed P2; the main jobs work for superuser and view-only staff. Still open and not blocking (outside fix scope): P3 803, 808, 814, 817, 818, 819, 820, 825; P4 815 (easy, not taken this cycle), 822, 826. Live integrations BLOCKED (no real keys).
- **State left (throwaway only):** none changed. The Void and Issue re-runs on the already-void ETQ-2026-10-0002 changed nothing; the Copy features confirm on qa-tmp-m01c was left unconfirmed; the Add academy submit was invalid (nothing created); the forged view-only POST was refused. qa-admin@ only signed in to look at the top bar. No demo/other/khaled/qa/qaother setting touched.

### M01 final gate
- **When / who:** 2026-10-28T15:14:21Z, Agent 2 (sole gate authority), after Agent 1's confirmation sweep (no fix cycle ran after gate 1).
- **Sweep findings triaged (4, all reproduced with my own screenshot in `screens/M01/triage/`):**
  - M01-F-029 → **ETQAN-QA-827** (P3 UI-layout, easy): suspended academy login on a 375 px phone measures 397 px; host-name header title can't wrap (`t029-suspended-login-phone.png`, on the already-suspended qa-tmp-m01a). Related to 804's accepted header PROPOSAL and QA-114, but the layout is its own bug.
  - M01-F-030 → **ETQAN-QA-828** (P4 copy, easy): invoice action messages begin "· ETQ-…" (`t030-void-message-stray-dot.png`, Void on the already-void ETQ-2026-10-0002 → "· ETQ-2026-10-0002: already void; nothing changed."; same `_each()` path as "voided."). Seen in F01's QA-013 text but never filed.
  - M01-F-031 → **ETQAN-QA-829** (P3 copy, easy): manual line Quantity 0 / Free quantity 0 next to 12.50 USD (`t031-manual-line-qty0.png`). Left over by 816; PDF-link wish = enhancement, not filed.
  - M01-F-032 → **ETQAN-QA-830** (P4 bidi, easy): confirm page `<bdi>` auto-direction draws "QA Tmp M01c أكاديمية الفجر" (`t032-copy-features-name-order.png`; not confirmed, nothing copied).
- **Still failing (re-checked now):** ETQAN-QA-012: `ops-view@` on `/admin/tenants/academy/25/change/` → 500 KeyError 'etqan_defaults_suspended' (`triage/g2-qa012-view-academy-500.png`; `_AcademyChangeForm.__init__` line 150 unguarded). ETQAN-QA-806 (reopened): `AcademyCreationForm` help text still has the raw `<subdomain>` (tenants/admin.py:47), swallowed by the browser (Agent 1 sweep saw ".etqan.localhost").
- **Verified (unchanged from gate 1, 15):** 800, 801, 802, 804 (+ header PROPOSAL accepted), 805, 807, 809, 810, 811, 812, 813, 816, 821, 823, 824. Sweep re-walked them in the browser with no regression.
- **Roles / languages:** superuser ops@: all main jobs work (add academy + Arabic name, invite AR, actions with confirmation, domains, billing, integrations look-only, users). View-only ops-view@: lists read-only and 403 page OK, but **academy detail 500 (QA-012)**. No-permission ops-noperm@: console 403 page OK. Console is English; Arabic names whole everywhere except the confirm page (830). Academy side AR+EN OK (desktop); phone overflow 827.
- **Decision: FAILED.** No open P0/P1 and no unfixed P2 (801, 802 verified; no new P2 found now), but the view-only role's main job still fails (QA-012) and 806 stays reopened. Next run's fix cycle: QA-012 + 806, plus the easy 827, 828, 829, 830. Other open, not blocking: P3 803, 808, 814, 817, 818, 819, 820, 825; P4 815 (easy), 822, 826. Live integrations BLOCKED (no real keys).
- **State left (throwaway only):** none changed by this gate: the Void re-run on the already-void ETQ-2026-10-0002 changed nothing; the Copy features confirm page on qa-tmp-m01c was left unconfirmed (features unchanged); qa-tmp-m01a was only viewed (already suspended). No demo/other/khaled/qa/qaother changes.

### M01 gate
- **When / who:** 2026-10-28T14:58:48Z, Agent 2 (sole gate authority). Retest of Agent 3's fix cycle 1 (16 fixed, 1 proposal, 0 not a bug).
- **Tests re-run by the gate:** pytest identity/test_console_users, tenants/test_admin_console_qa + test_admin + test_admin_features + test_admin_permissions, etqan_billing/test_admin_console_qa + test_admin, integrations/test_admin, identity/test_email_branding: 94 passed. Vitest LoginForm.test.tsx + reset-password.test.tsx: 38 passed.
- **Diff review:** UserAdmin now on Django's auth UserAdmin (AdminUserCreationForm, read-only hash); confirmation step via a small shared `platform/admin_confirm.py` + template (posts the same action back with confirm=yes, like Django's delete confirmation); void requires a reason; form-level help texts (no migration); readable `__str__`; handler403 only for staff under /admin/. No test hacks, no migration/API change, nothing committed. One weak test: the QA-806 test checks the help_text string, not the rendered page (that is how its rendering bug slipped through).
- **Verified in the browser (15 VERIFIED), before/after in `screens/M01/fix/ETQAN-QA-8NN-after.png`, raw shots `screens/M01/fix/g-*.png`:** 800 (mismatch refused, argon2 hash, new staff signs in, read-only hash + Reset password), 801 (Suspend/Reactivate/Copy features ask first, DB unchanged until confirmed, "1 academy", cancel changes nothing), 802 (empty reason refused, confirm page with reason, throwaway draft voided with reason stored, already-void reported), 804 (Arabic/English suspended message up front and on submit), 805 (invite page AR/EN wording), 807, 809, 810, 811, 812, 813, 816, 821, 823, 824 (view-only and no-permission staff get the console's own page).
- **Proposal accepted:** QA-804 header host name on a suspended academy's login (P3; letting the branding read through the suspension middleware is an owner policy call; coverage-gaps.md).
- **Reopened:** ETQAN-QA-806 (P3 easy). Subdomain is now required/bold, but the help text renders "The academy's address becomes .etqan.localhost": the literal `<subdomain>` is output as HTML and swallowed by the browser. Escape it and test the rendered page.
- **Blocking known bug:** ETQAN-QA-012 (P3, filed in F01) re-confirmed: view-only `ops-view@` opening any academy's change page gets HTTP 500 KeyError 'etqan_defaults_suspended' (`screens/M01/fix/g-view-academy-readonly.png`). The view-only role's main job in this area (looking at an academy) fails, so the gate cannot pass for every role. Easy guard in `_AcademyChangeForm.__init__`.
- **Roles / languages:** superuser ops@ (all main jobs: add user, academy actions, domains, billing, integrations look-only), view-only ops-view@ (lists read-only, 403 page; academy detail 500 = QA-012), no-permission ops-noperm@ (console 403 page). Console is English; Arabic names display whole in feature labels, domain/invoice lists, confirm pages and the held-domain error. Academy side AR+EN checked for 804/805.
- **Decision: FAILED.** No P0/P1 open and both P2s (801, 802) verified, but QA-012 breaks the view-only role and 806 is reopened. Next fix cycle: 806 + QA-012 (both easy). Remaining open, not blocking: P3 803, 808, 814, 817, 818, 819, 820, 825; P4 815 (easy), 822, 826. Live integrations BLOCKED (no real keys).
- **State left (throwaway only):** qa-tmp-m01b suspended then reactivated (active, features unchanged); new draft invoice ETQ-2026-08-0001 for qa-tmp-m01b created and voided (reason "M01 gate: throwaway draft"); new staff user id 10 qa-tmp-m01-gate@qa.etqan.test (is_staff, no permissions, password Tmp-M01-Gate-2026!); user id 9's plain-text password replaced through the console (now hashed, Tmp-M01-Staff-2026!x). No demo/other/khaled/qa/qaother changes (qaother/qa-tmp-m01a only read as copy sources).


### M16 gate
Agent 2, 2026-10-28T14:59:13Z. **Decision: PASSED.**

**Fixes verified (fix cycle 1, Agent 3).** I re-walked each fix in the browser as an anonymous visitor and as the academy admin (sessions `M16-g-anon-ar`, `M16-g-anon-ar-m`, `M16-g-anon-en`, `M16-g-anon-en-m`, `M16-g-reg-ar`, `M16-g-reg-ar-m`, `M16-g-reg-en-m`, `M16-g-consult-ar`, `M16-g-consult-en`, `M16-g-admin-ar`). The BEFORE/AFTER composites are in `screens/M16/fix/ETQAN-QA-<id>-after.png` and the working shots in `screens/M16/fix/g*.png`.
- **VERIFIED (18):** 750, 753, 754, 755, 756, 757, 758, 760, 761, 764, 765, 766, 768, 771, 772, 773, 774, 775. The register has one line on each.
  - **758 (P2):** `/app/register` on a 375 px Arabic phone measures `[375,375,0]` on steps 1 and 2, for both the adult and the parent path. The whole form is visible.
  - **756 / 761 / 772 on the server:** I checked each one directly against the API. A past `start_on`, a past `intro_call_at`, a future date of birth, and an inquiry phone of "not a phone !!" all return 400.
  - **771:** the fix works for Arabic-first text. The QA course title starts with Latin ("M15- …"), so the bidi rules correctly keep it LTR. That page looks unchanged because of its data, not the code.
  - **774 and 775:** the qa academy had no article and no contact at gate time, because M13 runs in parallel.
    - For 774 I created a temporary article with a cover on qa and deleted it afterwards.
    - For 775 I gave qaother's branding a contact for a moment and then cleared it again.
  - **End to end:** an adult registration in AR went through and its confirmation email arrived in Mailpit. A visitor consultation (CR-000008) was booked and paid with the SIMULATOR. A trial request reached the office inquiries list.
- **Code review** (`git -C marketing|dashboard|backend diff`, branch `qa/manual-2026-10`, uncommitted):
  - The fixes are at the root cause. No test was weakened or skipped, and there are no migrations or API shape changes.
  - The server English sentences are mapped in `lib/server-messages.ts` for now; stable error codes are a proposal.
  - Two backend behaviour changes are intended and noted in coverage-gaps:
    - inquiry phones are now checked;
    - past start dates and intro calls are refused, with one day of slack on the start date.
  - A small gap that does not block: the consultation card *title* got no `dir=auto`; only its description did.
- **Tests re-run by the gate** (outputs in `evidence/M16/fix-1/gate-*.txt`):
  - marketing full Vitest: 347/347;
  - dashboard scoped Vitest: 30 files, 228 tests (registration, consultations, gateways, website, ui, lib, locales);
  - `tsc --noEmit`: clean;
  - pytest `etqan/registration` + `site/tests/test_inquiries.py`: 188 passed.
- **Proposals accepted:**
  - 770 (P2): the public catalogue, packages and teachers on the home page. It needs an API change and the owner's choice of which teacher fields are public. Interim option: hide or label the three switches.
  - Stable error codes for the registration rejections.
- **New at the gate:** ETQAN-QA-777 (P4, easy). An article category name ending in Latin letters or digits mixes with the date (bidi).
- **Still open, not blocking.** None of these is P0–P2:
  - P3 non-easy: 751, 752, 759, 763, 767.
  - P4 easy, for the next fix cycle: 762, 769, 776, 777.
- **BLOCKED (no credentials):** real Stripe/PayPal, WhatsApp delivery, Zoom.

### M16 final gate
Agent 2, 2026-10-28T15:23:19Z. **Decision: PASSED.**
- **Sweep findings triaged (Agent 1 confirmation sweep, 3 new), each reproduced with my own screenshot in `screens/M16/triage/`:**
  - M16-F-030 → **ETQAN-QA-778** (P3, functional, easy). After a trial send the form goes back to "تواصل معنا" / `kind=contact` while the trial success line stays; a second send is stored as a contact. Residual of the 753 fix (`ContactForm.astro` calls `setKind("contact")` after a send). Shot `t030-trial-heading-resets-ar-m.png` (AR 375).
  - M16-F-031 → **ETQAN-QA-779** (P3, UI-layout, easy). The phone error shows in the primary green `rgb(14,124,102)`, the same colour as the success line, and the field is not marked; "12" gets "digits only". Shot `t031-phone-error-green-ar-m.png` (AR 375).
  - M16-F-032 → **ETQAN-QA-780** (P4, UX, easy). Visitor booking day headings are "2026/10/29" with no weekday (`BookingSlots.tsx`). Shot `t032-slot-dates-no-weekday.png` (AR desktop).
  - No duplicates in the register. Known issues seen again, not re-filed: 762 (avatar "ا"), QA-154 (raw time-zone list).
- **Why PASSED:** no P0/P1 is open. Both P2s are closed: 758 is VERIFIED and the owner accepted the 770 proposal. The sweep found no new P2. The sweep also re-saw the fixes still working and the main visitor jobs going through end to end, in AR and EN, on desktop and phone: registration as an adult and as a parent (with email and verify), a trial request reaching the office inquiries, a visitor consultation paid with the SIMULATOR (with email and manage link), a payment link paid with the SIMULATOR, and certificate verify (valid and invalid). The admin sees what the visitor sent.
- **Open, not blocking (next fix cycle):** P3 easy 778, 779. P4 easy 762, 769, 776, 777, 780. P3 non-easy 751, 752, 759, 763, 767.
- **BLOCKED / not exercised:** real Stripe/PayPal, WhatsApp, Zoom (no credentials). I did not toggle the closed-site switch on the shared qa site; its page was seen when another area closed it (776).
- **Test data left:** trial inquiry "M16 بوابة نهائية" (+201001112255) on qa.

### M11 gate
**Decision: PASSED** (Agent 2, 2026-10-28). No P0/P1 is open, the only P2 (668) is VERIFIED, and the area's main jobs work for each role in AR and EN.

**Fixes verified (fix cycle 1, Agent 3): 21 of 21.**
- I re-walked each fix in the browser (sessions `M11-g-admin-ar/en`, `M11-g-teacher-ar/en`, `M11-g-student-ar`, `M11-g-parent-ar`, `M11-g-anon`).
- BEFORE/AFTER images are at `screens/M11/fix/ETQAN-QA-<id>-after.png` and the raw shots are in `screens/M11/fix/g/`.
- **VERIFIED:** 650, 651, 653, 654, 656, 658, 660, 661, 662, 664, 665, 666, 668, 669, 670, 671, 672, 673, 674, 677, 678.
  - **668 (P2):** at 375 px the whole certificate shows (article 343x517, no clipping). At 1440 px the A4 ratio is kept (1.414).
  - **669:** a phone measures `[375,375,0]`.
  - **677:** a teacher opening a certificate or report gets 403, shown as "ليست لديك صلاحية…". A parent opening another family's certificate gets 404, shown as "تعذّر العثور…". Each page has a Back button and no spinner.
  - **658:** I walked the whole flow. The admin rejected the pending request with a reason; the teacher's form then said "ترقية من M11 المستوى الأول إلى M11 المستوى الثاني"; the request was sent again, so the data is as it was.
  - **651:** in the EN dialog, Arabic-led title and answer text now compute to `direction: rtl`. Latin-first test data ("M11 …") correctly stays LTR.
  - **666:** the nested confirm now dims the dialog under it.
- **Code review** (`git -C dashboard diff`, branch `qa/manual-2026-10`, uncommitted):
  - The fixes are at the root cause. No test was weakened or skipped, and there are no backend, API or migration changes.
  - Shared changes are reasonable:
    - `main.tsx` uses `retryUnlessRefused`, so 4xx answers are not retried;
    - on phones the toast now sits at the top (`ui/toast.tsx`); I checked it is clear of the dialog's buttons;
    - the `ui/dialog.tsx` overlay is now z-50;
    - `lib/server-messages.ts` has one new mapping.
  - Nit: `library/schemas.ts` `formatBytes` keeps a stale doc comment above the new one.
- **Tests re-run by the gate** (`evidence/M11/gate-1/`):
  - Dashboard scoped Vitest over curriculum, certificates, homework, library, studentReports, honour, ui, lib and locales: 531 tests, 528 passed. The other 3 timed out at 5 s under parallel load (IssueCertificateDialog, LevelDialog, NewHomeworkDialog). Re-run alone, the 6 affected files passed: 72/72 (`vitest-rerun.txt`).
  - `tsc --noEmit`: one error, outside M11, in `src/features/website/AdsManager.tsx(114)` (`'other'` is unused). This is M13's work in progress and is flagged for M13.
- **Main jobs re-checked:**
  - homework: create dialog, answer and replace on a phone, review dialog for admin and teacher, AR and EN, teacher on a phone;
  - levels: dialog, progress panel, upgrade reject and request;
  - Qur'an names (AR and EN);
  - honour dialog;
  - certificates: issue (refusal), revoke confirm (cancelled), print on desktop and phone, the student's view, and public verification by code (anonymous, phone);
  - library: upload refusal (AR and EN), list, copy-fail fallback, delete confirm (cancelled).
- **Small note, not filed:** in the issue dialog, "هذه الدورة لا تمنح شهادات إتمام." shows twice: as the field error and as the type hint.
- **Still open, not blocking (none is P0–P2):**
  - P3 non-easy: 657, 659, 663. 663 belongs to the owner's pending shared student-picker proposal.
  - P4 (next fix cycle): 652, 655, 667, 675, 676, 679, 680.
- **BLOCKED (no credentials):** a real AI provider for monthly reports. ETQAN_AI_FAKE is on, so drafts are SIMULATED.



### M11 final gate
**Decision: PASSED** (Agent 2, 2026-10-28, after Agent 1's confirmation sweep). No P0/P1 is open, the only P2 (668) stays VERIFIED, and no new P2 was found. The main jobs work for every role in AR and EN (sweep: homework end to end teacher AR → student AR/EN/375 → teacher EN; certificates issue, print, verify; library; levels; honour; reports).

**Sweep findings triaged (4, all reproduced with my own screenshots in `screens/M11/triage/`):**
- M11-F-038 → **ETQAN-QA-681** (P3 easy, UI-layout): issue-certificate Student/Course selects blank; residual of the 653 fix. `t038-cert-issue-blank-selects.png`.
- M11-F-039 → **ETQAN-QA-682** (P4, UI-layout): certificate detail footer wraps, "حفظ" alone at y=718 vs y=666; same shape as 652. `t039-cert-detail-footer.png`.
- M11-F-040 → **ETQAN-QA-683** (P3 easy, RTL): "Arabic (English)" names flipped on the certificate print page (375), the public verify page (desktop) and the office list (375); 209-class, `PersonName` not used there. `t040a/b/c-*.png`.
- M11-F-041 → **ETQAN-QA-684** (P3 easy, RTL): a Latin-led title (default file name) jumps to the far left of the library card; side effect of the 651/672 `dir="auto"` on a block span. `t041-library-latin-title-far-side.png`. Test file deleted afterwards.
- None is a duplicate of an open bug; 682 and 652 can share one footer fix.

**Verified for the area (21):** 650, 651, 653, 654, 656, 658, 660, 661, 662, 664, 665, 666, 668, 669, 670, 671, 672, 673, 674, 677, 678 (sweep saw 17 of them still working; none regressed apart from the 651/672 side effect filed as 684).
**Open, not blocking (next fix cycle):** P3 easy 681, 683, 684; P3 non-easy 657, 659, 663 (663 waits for the owner's shared student-picker proposal); P4 652, 655, 667, 675, 676, 679, 680, 682.
**BLOCKED:** real AI provider for monthly reports (ETQAN_AI_FAKE, drafts SIMULATED).


### M13 gate
Agent 2, 2026-10-28T15:41:39Z. **Decision: PASSED.**
- **Retested in the browser (AR desktop, AR phone 375x812, EN desktop), all 16 FIXED-UNVERIFIED are VERIFIED:** 700, 701, 702, 703, 704, 705, 706, 707, 708, 710, 713, 714, 715, 716, 717, 718. Before | after pairs: `qa/manual/screens/M13/fix/ETQAN-QA-<id>-after.png`.
  - 700 (P2): primary colour #7A1F5C saved → computed `--primary` #7A1F5C on `/ar/` and `/en/` (was always #146B50); restored #0E7C66.
  - 715 (P2): phone inbox scrollWidth 375 (was 656) with the long unbroken name wrapped.
  - 714: confirm dialog appears before "تحت الصيانة" (cancelled on qa so the parallel areas were not disturbed); closed page checked on `qaother` (status system_only + site_status switch for ~1 min, then restored): "الموقع غير متاح حاليًا", mailto + wa.me links.
  - 718: emptied نبذة saved as '' in the DB; public `/ar/` has no empty "من نحن".
- **Roles:** academy admin edits everything (AR + EN). `qa-staff-nocode@` gets "ليس لديك صلاحية الوصول إلى هذه الصفحة" on `/app/website/branding`, and the API refuses it (POST faqs 403, GET branding 403).
- **Tests run by Agent 2:** dashboard Vitest `src/features/website` + website route + `src/lib`: 278 tests pass (3 timed out under parallel load and passed when re-run alone); `tsc --noEmit` clean. Backend `pytest etqan/site`: 755 pass. Marketing closed/layout/components/site: 70 pass (with `SITE_SCHEME=https`, as the canonical-URL assertions expect; the container sets http).
- **Diff review:** fixes are at the root cause (shared `ListRow.tsx`, i18n keys for zod messages, server-message map, `html:root` brand rule, backend `is_blank_html`). No test hacks, no migrations or API changes. Minor notes, not blocking: the ad `min` date uses the browser's timezone, not the academy's (the server stays the authority); the page-builder button still says "إضافة آراء العملاء" while the tab says "آراء الطلاب".
- **Still open (allowed by the gate rule):** 709 (P3 non-easy, slug-change redirect shortcut), 712 (P3 non-easy, handled inquiry undo/who/when, needs an API action), 711 (P4 easy, mailto/tel links).
- **Not covered:** real logo/favicon upload to the public site.

### M13 final gate
Agent 2, 2026-10-28T15:57:35Z. **Decision: PASSED (final).**
- Confirmation sweep (Agent 1, 15:42–15:56Z, ~42 calls) found **0 new findings**: branding colour/tagline, slides, page builder, articles/categories, FAQs, ads, redirects, testimonials, inquiries, settings confirm dialog, tracking errors, mobile AR inbox/slides, and `qa-staff-nocode@` refusal all held in AR and EN. Sweep cleanup done via API.
- Final check by Agent 2: public `/ar/` and `/en/` 200, computed `--primary` #0E7C66 (start value), no tagline, no slide, no M13 content left (`screens/M13/final/f001-public-ar.png`).
- **No open P0/P1, no unfixed P2** (both P2s, 700 and 715, VERIFIED).
- **Verified (16):** 700, 701, 702, 703, 704, 705, 706, 707, 708, 710, 713, 714, 715, 716, 717, 718 (702 also covers M13-G-001).
- **Open, not blocking (next fix cycle):** 709 (P3 non-easy), 712 (P3 non-easy, needs an API action), 711 (P4 easy).
- **Not covered:** real logo/favicon upload to the public site.

