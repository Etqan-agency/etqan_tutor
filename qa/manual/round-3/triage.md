# Round 3 triage

One section per area, owned by that area's Agent 2.

## M03

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M03/triage/`.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M03-R3-001 | ETQAN-QA-950 | P3 | translation | yes | VERIFIED |
| M03-R3-002 | ETQAN-QA-951 (Agent 1 shot; totals since moved by other areas, layout same) | P3 | UI/layout | no | VERIFIED |
| M03-R3-003 | ETQAN-QA-952 | P3 | functional | yes | VERIFIED |
| M03-R3-004 | ETQAN-QA-953 | P3 | responsive | no | VERIFIED (gate cycle 2) |
| M03-R3-005 | ETQAN-QA-954 | P3 | responsive | no | VERIFIED |
| M03-R3-006 | ETQAN-QA-955 | P3 | responsive | no | VERIFIED |
| M03-R3-007 | ETQAN-QA-956 | P4 | spacing/icon | yes | VERIFIED |
| M03-R3-008 | ETQAN-QA-957 | P3 | copy | yes | VERIFIED |
| M03-R3-009 | ETQAN-QA-958 | P4 | spacing/icon | yes | VERIFIED |
| M03-R3-010 | ETQAN-QA-959 (alignment only; notice language per recipient is by design, notifications.md; duplicate INV-000149 pair was created by the QA-102 gate) | P4 | RTL | yes | VERIFIED |
| M03-R3-011 | ETQAN-QA-960 | P3 | translation | yes | VERIFIED |
| M03-R3-012 | ETQAN-QA-961 (menu alignment only; "EN" toggle vs current-language menu is the documented B9d L-5/L-6 design) | P4 | RTL | yes | VERIFIED |
| M03-R3-013 | ETQAN-QA-962 | P3 | translation | yes | VERIFIED |
| M03-R3-014 | ETQAN-QA-963 | P3 | UI/layout | no | VERIFIED (gate cycle 2) |
| M03-R3-015 | ETQAN-QA-964 | P3 | translation | yes | VERIFIED |
| M03-R3-016 | ETQAN-QA-965 | P4 | UI/layout | yes | VERIFIED |
| M03-R3-017 | ETQAN-QA-966 | P4 | UI/layout | no | VERIFIED |
| M03-R3-018 | ETQAN-QA-967 | P4 | responsive | yes | VERIFIED |
| M03-R3-019 | ETQAN-QA-968 | P4 | UI/layout | yes | VERIFIED |
| M03-R3-020 | ETQAN-QA-969 | P4 | theme | yes | VERIFIED |
| M03-R3-021 | ETQAN-QA-970 | P4 | copy | yes | VERIFIED |
| M03-R3-022 | ETQAN-QA-971 (regression of ETQAN-QA-106) | P3 | functional | yes | VERIFIED |
| M03-R3-023 | not a bug: roles-permissions.md § Dashboard route guards, "Teachers, students and parents are sent to `/`" (repro `t023-student-staff-url.png`) | - | - | - | CLOSED |
| M03-R3-024 | ETQAN-QA-972 | P3 | UI/layout | no | VERIFIED |
| M03-R3-025 | not a bug: global search / command palette is an explicit non-goal of the app-shell spec ("Breadcrumbs, a command palette, notifications bell, global search — not now"); feature request (repro `t025-no-search.png`) | - | - | - | CLOSED |
| M03-R3-026 | ETQAN-QA-973 | P3 | RTL | yes | VERIFIED |
| M03-R3-027 | not a bug: teacher double-bookings are allowed by design and only warned at creation (sessions.md "Conflicts are never blocked"); the five 22:00 rows are other areas' test data | - | - | - | CLOSED |
| M03-R3-028 (sweep) | ETQAN-QA-974 (student and parent Home; gap left by the QA-968 heading) | P4 | spacing/icon | yes | VERIFIED (gate cycle 3) |
| M03-R3-029 (sweep) | ETQAN-QA-975 (1440 residue of the crowding fixed by QA-955 at 768/1024; QA-955 itself holds) | P4 | UI/layout | no | VERIFIED (gate cycle 3) |
| M03-R3-030 (sweep) | ETQAN-QA-976 | P4 | UI/layout | yes | VERIFIED (gate cycle 3) |
| (gate) | ETQAN-QA-977 (regression of ETQAN-QA-955 at 768/1024, caused by the ETQAN-QA-1256 `sm:w-max` attendance box; found at gate cycle 3) | P3 | responsive | yes | VERIFIED (gate extra cycle 4) |

Filed: 24 (ETQAN-QA-950…973). Not bugs: 3. Duplicates: 0.

Gate cycle 1 (Agent 2, 2026-11-01): 22 VERIFIED, 2 FAILED (ETQAN-QA-953 wordmark truncated to "Etqan …"/"E." on phones + its regression test fails; ETQAN-QA-963 limited staff still get only sidebar-copy tiles). Area M03: FAILED, back to Agent 3. Before/after shots: `qa/manual/screens/r3/M03/fix/`.

Gate cycle 2 (Agent 2, 2026-11-01): ETQAN-QA-953 VERIFIED (full academy name in the phone top bar at 375/320, AR/EN, light/dark, no sideways scroll; theme switch in the account menu) and ETQAN-QA-963 VERIFIED (staff-codes Home: no sidebar-copy tiles from lg, pointer to the side menu; supervisor day card and no-screens alert unchanged). Regression tests 53/53 + 69/69. All 24 VERIFIED, no P0/P1. **Area M03: PASSED.** Shots: `qa/manual/screens/r3/M03/fix/g2-*.png`.

Sweep triage (Agent 2, 2026-11-01): reproduced M03-R3-028…030 (shots `qa/manual/screens/r3/M03/triage/t028-*`, `t029-*`, `t030-*`); filed ETQAN-QA-974…976 (3×P4). No duplicates, no not-a-bug. Area M03 reopened for these three: waiting for Agent 3 fixes.

Gate cycle 3 (Agent 2, 2026-11-01): ETQAN-QA-974, 975 and 976 VERIFIED in the browser (student/parent/teacher/supervisor; AR+EN; 375/768/1024/1440; light+dark). Shots: `qa/manual/screens/r3/M03/fix/g3-*.png`, before: `before-974…976-*`. vitest 5 files, 84 passed. ETQAN-QA-955 regressed: at 768/1024 the teacher Home table overflows its card (728/793 px in 660–668), and Actions/Report are cut off. Cause: the M14 ETQAN-QA-1256 `sm:w-max` attendance box. Filed as ETQAN-QA-977 (P3, OPEN). **Area M03: FAILED**, back to Agent 3 for 977; coordinate with M14 so that ETQAN-QA-1256 still holds on History.

Gate extra cycle 4 (Agent 2, 2026-11-01): ETQAN-QA-977 VERIFIED in the browser (teacher, AR+EN, 768/1024/1440; light, plus EN 1440 dark). Home table/box 768 668/668, 1024 660/660 (cards), 1440 1076/1076 (table); nothing cut off, page width = viewport. ETQAN-QA-975 still holds (EN 1440: When 97 / Student 144 / Course 128 px) and ETQAN-QA-955 holds again; M14's ETQAN-QA-1256 still holds on History (1440 1126/1126, 90–91 px rows). Shots `qa/manual/screens/r3/M03/fix/g4-*.png`; before `g3-977-*-overflow.png`. vitest TeacherSessions + qa-round3-m03 pass (`qa/manual/evidence/r3/M03/gate-4/vitest.txt`). All 28 M03 bugs (950–977) VERIFIED, no P0/P1 open. **Area M03: PASSED.**

## M04

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M04/triage/`.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M04-R3-001 | ETQAN-QA-1000 | P2 | responsive | no | VERIFIED |
| M04-R3-002 | ETQAN-QA-1001 | P3 | responsive | yes | VERIFIED |
| M04-R3-003 | ETQAN-QA-1002 | P3 | responsive | no | VERIFIED |
| M04-R3-004 | ETQAN-QA-1003 (sidebar-at-768 part is ETQAN-QA-954) | P3 | responsive | no | VERIFIED |
| M04-R3-005 | ETQAN-QA-1004 | P4 | spacing/icon | yes | VERIFIED |
| M04-R3-006 | ETQAN-QA-1005 | P3 | UI/layout | no | VERIFIED |
| M04-R3-007 | ETQAN-QA-1006 | P3 | responsive | yes | VERIFIED |
| M04-R3-008 | ETQAN-QA-1007 | P4 | spacing/icon | yes | VERIFIED |
| M04-R3-009 | ETQAN-QA-1008 | P3 | UI/layout | no | VERIFIED |
| M04-R3-010 | ETQAN-QA-1009 (staff/groups names not links and CSV scope dropped: by design) | P3 | UI/layout | no | VERIFIED |
| M04-R3-011 | ETQAN-QA-1010 (missing button on some rows is `can_delete` by design) | P4 | UI/layout | yes | VERIFIED |
| M04-R3-012 | ETQAN-QA-1011 | P4 | spacing/icon | yes | VERIFIED |
| M04-R3-013 | ETQAN-QA-1012 | P3 | theme | no | VERIFIED |
| M04-R3-014 | ETQAN-QA-1013 | P4 | spacing/icon | yes | VERIFIED |
| M04-R3-015 | ETQAN-QA-1014 | P3 | translation | no | VERIFIED |
| M04-R3-016 | ETQAN-QA-1015 | P3 | functional | yes | VERIFIED |
| M04-R3-017 | dup of ETQAN-QA-035 (still OPEN; student 269 saved with DOB 2030-01-01, repro `t017-future-dob.png`) | P3 | functional | - | DUP |
| M04-R3-018 | ETQAN-QA-1016 | P3 | translation | yes | VERIFIED |
| M04-R3-019 | ETQAN-QA-1017 | P3 | UI/layout | no | VERIFIED |
| M04-R3-020 | ETQAN-QA-1018 (order already fixed by QA-065; remaining: raw zone + no time) | P4 | translation | yes | VERIFIED |
| M04-R3-021 | ETQAN-QA-1019 (regression of ETQAN-QA-163) | P3 | RTL | yes | VERIFIED |
| M04-R3-022 | ETQAN-QA-1020 (regression of ETQAN-QA-170) | P3 | RTL | yes | VERIFIED |
| M04-R3-023 | ETQAN-QA-1021 (dialog not covered by the ETQAN-QA-153 fix) | P3 | RTL | yes | VERIFIED |
| M04-R3-024 | ETQAN-QA-1022 | P3 | translation | yes | VERIFIED |
| M04-R3-025 | ETQAN-QA-1023 | P4 | UI/layout | yes | VERIFIED |
| M04-R3-026 | ETQAN-QA-1024 | P4 | UI/layout | yes | VERIFIED |
| M04-R3-027 | ETQAN-QA-1025 | P3 | copy | yes | VERIFIED |
| M04-R3-028 | ETQAN-QA-1026 | P3 | functional | no | VERIFIED |
| M04-R3-029 | ETQAN-QA-1027 | P3 | data | yes | VERIFIED |
| M04-R3-030 | ETQAN-QA-1028 | P3 | translation | yes | VERIFIED |
| M04-R3-031 | ETQAN-QA-1029 | P4 | translation | yes | VERIFIED |
| M04-R3-032 | ETQAN-QA-1030 (count wording only; emoji part: not a bug, ETQAN-QA-512 refuses on save, legacy tag kept by accepted note) | P4 | translation | yes | VERIFIED |
| M04-R3-033 | ETQAN-QA-1031 | P4 | a11y | yes | VERIFIED |
| M04-R3-034 | ETQAN-QA-1032 | P4 | spacing/icon | yes | VERIFIED |
| M04-R3-035 | ETQAN-QA-1033 | P4 | theme | yes | VERIFIED |
| M04-R3-036 | ETQAN-QA-1034 | P4 | responsive | yes | VERIFIED |
| M04-R3-037 | ETQAN-QA-1035 | P3 | data | yes | VERIFIED |
| M04-R3-038 | ETQAN-QA-1036 | P4 | spacing/icon | yes | VERIFIED |
| M04-R3-039 | ETQAN-QA-1037 | P4 | UI/layout | yes | VERIFIED |
| M04-R3-040 (sweep) | ETQAN-QA-1038 (global `table { tabular-nums }` makes Inter's hyphen tabular; all tables) | P4 | spacing/icon | yes | VERIFIED (gate cycle 3) |
| M04-R3-041 (sweep) | ETQAN-QA-1039 (Contracts/Groups search without icon; "إضافة عقد" and "إضافة وسم" without "+"; follow-up of QA-1009) | P4 | spacing/icon | yes | VERIFIED (gate cycle 3) |

Filed: 38 (ETQAN-QA-1000…1037; 1×P2, 21×P3, 16×P4). Duplicates: 1 (017 → QA-035). Not bugs: 0 whole findings (parts of 004, 010, 011, 032 dropped as noted).

**Gate cycle 1 (Agent 2, 2026-11-01):** FAILED. 34 of 38 VERIFIED in the browser (before/after in `qa/manual/screens/r3/M04/fix/`), 1014 VERIFIED with the accepted decision D-M04-1. FAILED: ETQAN-QA-1005 (phone bulk bar still 299 px with ragged rows, family select 88 px "اختر عائ…"), ETQAN-QA-1012 (card gap 48 px above "الرصيد" vs 24 px elsewhere), ETQAN-QA-1019 (file line: ".pdf" still rendered to the right of the Arabic stem; the outer `<bdi>` of `FileNameText` resolves to LTR), ETQAN-QA-1037 (nowrap makes the 1440 students table 1174/1126 px, the Account column clipped). Regression tests: the 24 named vitest files pass (run in the dashboard container, small batches, `--maxWorkers=1`), backend 6/6 pass. No P0/P1 open.

**Gate cycle 2 (Agent 2, 2026-11-01):** PASSED. The 4 bugs that failed cycle 1 are VERIFIED in the browser (before/after in `qa/manual/screens/r3/M04/fix/`, `*-after-c2-*`): 1005 (phone bar 66 px with an Actions toggle, pickers 317 px, even rows; 1440 unchanged), 1012 (all student-248 cards 24 px apart, dark and light), 1019 ("عقد خالد" then ".pdf" in RTL), 1037 (students table 1126/1126 at 1440 AR and EN, Account column whole). Regression tests: 9 vitest files (2 runs, 43 + 49 tests), all pass (`--maxWorkers=1`). Area total: 38/38 VERIFIED (1014 with decision D-M04-1). Open: none in range; 017 is a dup of QA-035 (outside this range). No P0/P1 open.

**Sweep triage (Agent 2, 2026-11-01):** 2 new sweep findings reproduced (`triage/t040-*`, `t041-*`), both filed: 040 → ETQAN-QA-1038, 041 → ETQAN-QA-1039 (P4, spacing/icon, easy). Area REOPENED: 1038–1039 OPEN, back to Agent 3; 1000–1037 stay VERIFIED.

**Gate cycle 3 (Agent 2, 2026-11-01):** PASSED. ETQAN-QA-1038 VERIFIED (Staff e-mails "f02-staff-ql@…" with tight hyphens at 1440 EN, `font-variant-numeric: normal`; Invoices amounts keep `tabular-nums`). ETQAN-QA-1039 VERIFIED (Contracts and Study groups search with the magnifier, 36 px inset, at 1440 and 375 AR; "إضافة عقد" and "إضافة وسم" with "+"; Families/Staff/Students search unchanged through the new `SearchInput`; no sideways scroll; Contracts dark OK). Shots `qa/manual/screens/r3/M04/fix/1038-*`, `1039-*`. Regression tests: 8 vitest files / 63 tests pass (`--maxWorkers=1`). Area total: 40/40 VERIFIED (1014 with decision D-M04-1). No P0/P1 open; nothing open in range.

## M14

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M14/triage/`.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M14-R3-001 | ETQAN-QA-1250 (Homework + Levels; the My sessions table is the same as ETQAN-QA-955) | P3 | responsive | no | VERIFIED (gate cycle 1) |
| M14-R3-002 | ETQAN-QA-1251 | P3 | spacing/icon | yes | VERIFIED (gate cycle 1) |
| M14-R3-003 | ETQAN-QA-1252 (related ETQAN-QA-969, different surfaces) | P3 | theme | yes | VERIFIED (gate cycle 1) |
| M14-R3-004 | ETQAN-QA-1253 | P3 | functional | yes | VERIFIED (gate cycle 1) |
| M14-R3-005 | ETQAN-QA-1254 (related M04-R3-016) | P3 | UI/layout | yes | VERIFIED (gate cycle 1) |
| M14-R3-006 | ETQAN-QA-1255 (related M04-R3-015/024) | P3 | translation | no | VERIFIED (file fields) + PROPOSAL-accepted D-M14-1 (gate cycle 1) |
| M14-R3-007 | ETQAN-QA-1256 | P3 | UI/layout | no | VERIFIED (gate cycle 1) |
| M14-R3-008 | ETQAN-QA-1257 | P3 | functional | yes | VERIFIED (gate cycle 1) |
| M14-R3-009 | ETQAN-QA-1258 (same string as M07-R3-006) | P3 | translation | yes | VERIFIED (gate cycle 1) |
| M14-R3-010 | ETQAN-QA-1259 | P4 | translation | yes | VERIFIED (gate cycle 1) |
| M14-R3-011 | ETQAN-QA-1260 | P3 | translation | yes | VERIFIED (gate cycle 1) |
| M14-R3-012 | ETQAN-QA-1261 | P3 | translation | yes | VERIFIED (gate cycle 1) |
| M14-R3-013 | ETQAN-QA-1262 | P4 | UI/layout | yes | VERIFIED (gate cycle 1) |
| M14-R3-014 | ETQAN-QA-1263 | P4 | spacing/icon | yes | VERIFIED (gate cycle 1) |
| M14-R3-015 | ETQAN-QA-1264 | P3 | UI/layout | yes | VERIFIED (gate cycle 1) |
| M14-R3-016 | ETQAN-QA-1265 | P3 | functional | yes | VERIFIED (gate cycle 1) |
| M14-R3-017 | ETQAN-QA-1266 | P4 | functional | yes | VERIFIED (gate cycle 1) |
| M14-R3-018 | ETQAN-QA-1267 | P4 | UI/layout | yes | VERIFIED (gate cycle 1) |
| M14-R3-019 | ETQAN-QA-1268 | P4 | functional | yes | VERIFIED (gate cycle 1) |
| M14-R3-020 | ETQAN-QA-1269 | P3 | RTL | yes | VERIFIED (gate cycle 1) |
| M14-R3-021 | ETQAN-QA-1270 | P4 | translation | yes | VERIFIED (gate cycle 1) |
| M14-R3-022 | ETQAN-QA-1271 | P3 | RTL | yes | VERIFIED (gate cycle 1) |
| M14-R3-023 | ETQAN-QA-1272 | P4 | spacing/icon | yes | VERIFIED (gate cycle 1) |
| M14-R3-024 | ETQAN-QA-1273 (related M07-R3-005) | P4 | spacing/icon | yes | VERIFIED (gate cycle 1) |
| M14-R3-025 | ETQAN-QA-1274 | P3 | responsive | yes | VERIFIED (gate cycle 1) |
| M14-R3-026 | ETQAN-QA-1275 | P3 | responsive | no | VERIFIED (gate cycle 1) |
| M14-R3-027 | dup of ETQAN-QA-965 (same empty "التقرير" row on phone cards; in the current working tree the row already reads "بعد انتهاء الحصة", repro `t027-phone-session-report.png`) | - | - | - | DUP |
| M14-R3-028 | ETQAN-QA-1276 | P4 | responsive | yes | VERIFIED (gate cycle 1) |
| M14-R3-029 | not a bug: the week order follows the interface language by design (ETQAN-QA-162 fix, `scheduling/schemas.ts` `weekdaysInOrder`: Arabic from Saturday, other languages from Monday); repro `t003b-availability-bg.png` | - | - | - | CLOSED |
| M14-R3-030 | not a bug: teacher double-bookings are allowed by design and only warned at creation (sessions.md "Conflicts are never blocked"); the 22:00 rows are other areas' test data (same ruling as M03-R3-027); repro `t027-phone-session-report.png` / `t006b-postpone-date.png` | - | - | - | CLOSED |
| M14-R3-031 (sweep) | ETQAN-QA-1277 (regression of the ETQAN-QA-1256 fix; same root cause as ETQAN-QA-977, M03, which covers Home/Today; fix together). Repro `triage/t031a-history-1024-ar.png`, `t031b-history-1024-en.png`, `t031c-history-768-ar.png` (755/710, 881/710, 755/718) | P3 | responsive | yes | VERIFIED (gate cycle 3) |
| M14-R3-032 (sweep) | ETQAN-QA-1278 (grid `items-start`). Repro `triage/t032-availability-uneven.png` (147 vs 124 px per row) | P4 | spacing/icon | yes | VERIFIED (gate cycle 3) |

**Gate cycle 1 (Agent 2, 2026-11-01): M14 PASSED.** 27/27 VERIFIED in the browser (AR + EN; 375/768/1024/1440; light + dark), ETQAN-QA-1255 date/time part PROPOSAL-accepted (D-M14-1, follow-up). Regression tests: vitest 18 files 241 passed, pytest learning homework 22 passed (`qa/manual/evidence/r3/M14/gate-1/`). After shots `qa/manual/screens/r3/M14/fix/g*.png`. Non-blocking notes for a later pass: the empty "كل الطلاب" select still shows on a homework no-match; the availability end-before-start field has no aria-invalid/red border (message only); History's report cell says "بعد انتهاء الحصة" on unmarked past sessions (QA-965 wording, M03).

Filed: 27 (ETQAN-QA-1250…1276). Not bugs: 2 (029, 030). Duplicates: 1 (027 → ETQAN-QA-965).

**Sweep triage (Agent 2, 2026-11-01):** 031 → ETQAN-QA-1277 (P3), 032 → ETQAN-QA-1278 (P4), both OPEN, waiting for Agent 3. Totals: 29 filed (1250…1278).

**Gate cycle 3 (Agent 2, 2026-11-01): M14 PASSED.** ETQAN-QA-1277 and 1278 VERIFIED in the browser (AR + EN; 375/768/1024/1280/1440; light + dark). History fits its card at every width (cards below 1280, table 966/966 at 1280, 1126/1126 at 1440 with 90–91 px rows, so ETQAN-QA-1256 still holds); Home Today fits at 768/1024/1440 (also clears M03's ETQAN-QA-977, for M03's gate to record). Availability day cards equal per row at 1440 light/dark and 768. vitest 3 files, 57 passed (`qa/manual/evidence/r3/M14/gate-3/`). After shots `qa/manual/screens/r3/M14/fix/g3-*.png`. Area total: 29/29 VERIFIED (1255 date/time part PROPOSAL-accepted D-M14-1). No P0/P1 open.

## M02

Agent 2, 2026-11-01. Every finding reproduced in the browser; repro shots in `qa/manual/screens/r3/M02/triage/`.
Test state restored: teacher yousef 2FA OFF, student.ind6 phone +201009990947, extra email removed, admin returned from "sign in as".

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M02-R3-001 | ETQAN-QA-900 | P3 | translation | yes | VERIFIED |
| M02-R3-002 | ETQAN-QA-903 | P4 | translation | yes | VERIFIED |
| M02-R3-003 | ETQAN-QA-902 | P3 | UI/layout | yes | VERIFIED |
| M02-R3-004 | ETQAN-QA-901 | P3 | translation | yes | VERIFIED |
| M02-R3-005 | ETQAN-QA-904 | P4 | RTL | yes | VERIFIED |
| M02-R3-006 | ETQAN-QA-905 | P3 | copy | yes | VERIFIED |
| M02-R3-007 | dup of ETQAN-QA-906 (same auth secondary-action pattern as 022) | — | — | — | — |
| M02-R3-008 | dup of ETQAN-QA-958 (M03, same LogOut icon) | — | — | — | — |
| M02-R3-009 | ETQAN-QA-908 (also covers the 9×403 at "sign in as" from 033) | P3 | functional | no | VERIFIED |
| M02-R3-010 | ETQAN-QA-909 | P4 | UI/layout | yes | VERIFIED |
| M02-R3-011 | ETQAN-QA-910 | P4 | UI/layout | yes | VERIFIED |
| M02-R3-012 | ETQAN-QA-911 | P4 | translation | yes | VERIFIED |
| M02-R3-013 | ETQAN-QA-912 | P4 | translation | yes | VERIFIED |
| M02-R3-014 | ETQAN-QA-913 | P3 | translation | no | VERIFIED |
| M02-R3-015 | dup of ETQAN-QA-961 (M03, same language-menu alignment) | — | — | — | — |
| M02-R3-016 | not a bug: B9d L-5 "pages before sign-in offer only ar/en (switches unknown there)" (`docs/superpowers/specs/2026-10-04-b9d-languages-design.md`) | — | — | — | — |
| M02-R3-017 | ETQAN-QA-916 | P3 | functional | no | VERIFIED |
| M02-R3-018 | ETQAN-QA-917 (stale in both directions: add and clear) | P3 | functional | yes | VERIFIED |
| M02-R3-019 | ETQAN-QA-918 | P4 | translation | yes | VERIFIED |
| M02-R3-020 | ETQAN-QA-919 (gap left by QA-056) | P4 | copy | yes | VERIFIED |
| M02-R3-021 | split: grid + field pattern → ETQAN-QA-920; check mark touching the title → ETQAN-QA-921 | P4 / P3 | UI/layout / spacing/icon | yes | VERIFIED |
| M02-R3-022 | ETQAN-QA-906 | P3 | spacing/icon | no | VERIFIED |
| M02-R3-023 | ETQAN-QA-922 | P4 | UI/layout | yes | VERIFIED |
| M02-R3-024 | ETQAN-QA-923 | P4 | copy | yes | VERIFIED |
| M02-R3-025 | ETQAN-QA-924 | P4 | functional | yes | VERIFIED |
| M02-R3-026 | ETQAN-QA-925 | P4 | RTL | yes | VERIFIED |
| M02-R3-027 | ETQAN-QA-926 | P4 | UI/layout | yes | VERIFIED |
| M02-R3-028 | ETQAN-QA-927 | P4 | UI/layout | yes | VERIFIED |
| M02-R3-029 | ETQAN-QA-928 | P4 | UI/layout | yes | VERIFIED |
| M02-R3-030 | dup of ETQAN-QA-921 (same check-mark overlap, worse at 1024) | — | — | — | — |
| M02-R3-031 | dup of ETQAN-QA-1018 (M04: raw "Africa/Cairo" + no time). The missing time is by design (B9b S-8, proposal from QA-065) | — | — | — | — |
| M02-R3-032 | ETQAN-QA-930 (label, pill, button order); card frame/gaps = ETQAN-QA-1012 (M04) | P4 | translation | yes | VERIFIED |
| M02-R3-033 | ETQAN-QA-931 (403 burst → ETQAN-QA-908) | P3 | RTL | yes | VERIFIED |
| M02-R3-034 | ETQAN-QA-932 | P4 | functional | yes | VERIFIED |
| M02-R3-035 | ETQAN-QA-933 | P4 | UI/layout | yes | VERIFIED |
| M02-R3-036 | ETQAN-QA-934 (Account form; same server text as ETQAN-QA-1016) | P4 | translation | yes | VERIFIED |
| M02-R3-037 | ETQAN-QA-935 | P4 | responsive | yes | VERIFIED |
| M02-R3-038 | ETQAN-QA-936 | P4 | translation | yes | VERIFIED |
| M02-R3-039 (sweep) | ETQAN-QA-937 (shared top-bar badge, every AR screen) | P3 | RTL | yes | VERIFIED |
| M02-R3-040 (sweep) | ETQAN-QA-938 (code/name mix and opposite meaning; B9d L-6 fixes toggle vs menu, not the label) | P4 | copy | yes | VERIFIED |
| M02-R3-041 (sweep) | ETQAN-QA-939 | P4 | spacing/icon | yes | VERIFIED |

IDs 907, 914, 915, 929 are unused: those findings turned out to be duplicates of other areas' bugs or not a bug.

Gate cycle 1 (Agent 2, 2026-11-01): all 33 bugs (900–906, 908–913, 916–928, 930–936) retested in the browser and VERIFIED; after-shots in `qa/manual/screens/r3/M02/fix/`. Regression tests: dashboard 23 M02 suites 258 passed (the 1 failure is design-preview's other-area exports formGrid/phoneCardLead/tableFrame/tableHead/wideTableCards*, not M02); backend test_phone_login + test_email_language 30 passed. Area M02 PASSED.

Sweep triage (Agent 2, 2026-11-01): M02-R3-039..041 each reproduced (`screens/r3/M02/triage/t039-*`, `t040-*`, `t041-*`); 3 bugs filed (937–939, 1×P3, 2×P4), no dups or non-bugs. Waiting for Agent 3.

Gate cycle 3 (Agent 2, 2026-11-01): 937, 938, 939 retested in the browser (admin AR 1440 light + 375 dark, anonymous AR 1440 + EN 1440 dark, qa-teacher AR 375 + 1440 dark) and VERIFIED; after-shots `qa/manual/screens/r3/M02/fix/v937-*`, `v938-*`, `v939-*`. Regression tests: NotificationBell, toggles, MyContractsCard 3 files / 32 tests pass (`logs/M02/agent2-gate3-vitest.txt`). All 36 M02 bugs VERIFIED, no P0/P1. Area M02 PASSED.


## M09

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M09/triage/`.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M09-R3-001 | ETQAN-QA-1200 | P3 | UI/layout | yes | VERIFIED |
| M09-R3-002 | ETQAN-QA-1201 | P3 | translation | yes | VERIFIED |
| M09-R3-003 | ETQAN-QA-1202 | P3 | translation | yes | VERIFIED |
| M09-R3-004 | ETQAN-QA-1203 | P3 | copy | yes | VERIFIED (gate cycle 2) |
| M09-R3-005 | ETQAN-QA-1204 | P3 | translation | yes | VERIFIED |
| M09-R3-006 | not a bug: payroll.md § rules, "`paid_on` can't be in the future, nor before the first day of the month the payslip pays (ETQAN-QA-029)"; recording a payment made before the payslip was entered is allowed by design (repro `t006-paid-before-issued-ar.png`) | - | - | - | CLOSED |
| M09-R3-007 | ETQAN-QA-1205 | P3 | responsive | no | VERIFIED |
| M09-R3-008 | ETQAN-QA-1206 | P4 | translation | yes | VERIFIED |
| M09-R3-009 | dup of ETQAN-QA-030 (no upper bound on payroll money inputs, still OPEN); a 0.00 rate is valid (no rule against unpaid/volunteer teaching in payroll.md) | - | - | - | CLOSED |
| M09-R3-010 | ETQAN-QA-1207 (typo not reproduced; inconsistency only) | P4 | translation | yes | VERIFIED |
| M09-R3-011 | ETQAN-QA-1208 | P3 | translation | yes | VERIFIED (gate cycle 2) |
| M09-R3-012 | ETQAN-QA-1209 | P3 | UI/layout | yes | VERIFIED |
| M09-R3-013 | ETQAN-QA-1210 | P3 | functional | yes | VERIFIED |
| M09-R3-014 | ETQAN-QA-1211 | P3 | UI/layout | no | VERIFIED |
| M09-R3-015 | ETQAN-QA-1212 | P3 | UI/layout | yes | VERIFIED |
| M09-R3-016 | ETQAN-QA-1213 | P3 | responsive | no | VERIFIED |
| M09-R3-017 | ETQAN-QA-1214 (narrowed to payslips list; sidebar now collapses at 768) | P3 | responsive | no | VERIFIED |
| M09-R3-018 | ETQAN-QA-1215 | P3 | responsive | no | VERIFIED |
| M09-R3-019 | ETQAN-QA-1216 | P4 | theme | yes | VERIFIED |
| M09-R3-020 | ETQAN-QA-1217 | P3 | translation | yes | VERIFIED |
| M09-R3-021 | ETQAN-QA-1218 | P3 | copy | yes | VERIFIED |
| M09-R3-022 | ETQAN-QA-1219 | P4 | spacing/icon | yes | VERIFIED |
| M09-R3-023 | ETQAN-QA-1220 | P3 | translation | yes | VERIFIED |
| M09-R3-024 | ETQAN-QA-1221 (currency select only; payout method is by design) | P4 | RTL | yes | VERIFIED |
| M09-R3-025 | ETQAN-QA-1222 (same family as ETQAN-QA-353) | P3 | RTL | yes | VERIFIED |
| M09-R3-026 | ETQAN-QA-1223 | P3 | RTL | yes | VERIFIED |
| M09-R3-027 | ETQAN-QA-1224 | P4 | responsive | yes | VERIFIED |
| M09-R3-028 | ETQAN-QA-1225 | P4 | spacing/icon | yes | VERIFIED |
| M09-R3-029 | ETQAN-QA-1226 | P3 | functional | yes | VERIFIED |
| M09-R3-030 | ETQAN-QA-1227 (heading only; wording already fixed via QA-950) | P4 | UI/layout | yes | VERIFIED |
| M09-R3-031 | ETQAN-QA-1228 | P3 | UI/layout | no | VERIFIED |
| M09-R3-032 | ETQAN-QA-1229 | P4 | UI/layout | yes | VERIFIED |
| M09-R3-033 | ETQAN-QA-1230 | P3 | RTL | yes | VERIFIED |
| M09-R3-034 | ETQAN-QA-1231 | P4 | spacing/icon | yes | VERIFIED |
| M09-R3-035 (sweep) | ETQAN-QA-1232 (same root as 1231 on Adjustments/Withdrawals; 1231 itself holds) | P4 | spacing/icon | yes | VERIFIED |
| M09-R3-036 (sweep) | ETQAN-QA-1233 | P4 | copy | yes | VERIFIED |

Filed: 32 (ETQAN-QA-1200…1231). Not bugs: 1 (006). Duplicates: 1 (009 → QA-030).

Gate cycle 1 (Agent 2, 2026-11-01): 30 VERIFIED, 2 FAILED (1203, 1208), back to Agent 3. Before/after shots in `qa/manual/screens/r3/M09/fix/`. Payroll vitest: 21 files, 251 tests; 2 timeouts under load (SettingsPage, WithdrawalsPage) pass when rerun alone (30/30).

Gate cycle 2 (Agent 2, 2026-11-01): 1203 and 1208 retested in the browser (AR 1440/375 light, EN 375 dark) and VERIFIED; regression tests 9 files / 93 tests and the payroll suite 20 files / 252 tests green. All 32 bugs VERIFIED, no P0/P1. **M09 PASSED.**

Sweep triage (Agent 2, 2026-11-01): Agent 1's confirmation sweep added 035 and 036; both reproduced (`screens/r3/M09/triage/t035-*.png`, `t036-*.png`) and filed as ETQAN-QA-1232, 1233 (P4, OPEN). M09 reopened for these two; back to Agent 3.

Gate cycle 3 (Agent 2, 2026-11-01): 1232 and 1233 retested in the browser (AR 1440 light+dark, AR 375 light, EN 375 light+dark) and VERIFIED; the 3 named regression tests pass. MyBalance had 1 load timeout in the 3-file run (still loading); passes 10/10 twice when run alone. All 34 bugs (1200–1233) VERIFIED, no P0/P1. **M09 PASSED.**


## M07

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M07/triage/`.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M07-R3-001 | ETQAN-QA-1100 | P3 | spacing/icon | no | VERIFIED |
| M07-R3-002 | ETQAN-QA-1101 (also covers the residual 768 wrapping of M07-R3-030) | P3 | UI/layout | no | VERIFIED |
| M07-R3-003 | ETQAN-QA-1102 | P3 | functional | no | VERIFIED |
| M07-R3-004 | ETQAN-QA-1103 | P4 | UI/layout | yes | VERIFIED |
| M07-R3-005 | ETQAN-QA-1104 | P4 | spacing/icon | yes | VERIFIED |
| M07-R3-006 | ETQAN-QA-1105 | P3 | translation | yes | VERIFIED |
| M07-R3-007 | ETQAN-QA-1106 | P3 | translation | yes | VERIFIED |
| M07-R3-008 | dup of ETQAN-QA-045 (OPEN): after un-marking a reported session the card shows "كتبه QA Admin" + "يمكن كتابة التقرير بعد تسجيل حضور الطالب." — the UI face of the kept-report bug (repro `t008-report-after-unmark.png`) | - | - | - | CLOSED |
| M07-R3-009 | ETQAN-QA-1107 | P3 | copy | yes | VERIFIED |
| M07-R3-010 | ETQAN-QA-1108 | P3 | functional | no | VERIFIED |
| M07-R3-011 | ETQAN-QA-1109 | P4 | spacing/icon | yes | VERIFIED (gate 2) |
| M07-R3-012 | ETQAN-QA-1110 | P4 | UI/layout | yes | VERIFIED |
| M07-R3-013 | ETQAN-QA-1111 | P3 | UI/layout | yes | VERIFIED |
| M07-R3-014 | ETQAN-QA-1112 | P3 | UI/layout | no | VERIFIED |
| M07-R3-015 | ETQAN-QA-1113 | P3 | UI/layout | yes | VERIFIED |
| M07-R3-016 | ETQAN-QA-1114 | P3 | RTL | yes | VERIFIED |
| M07-R3-017 | ETQAN-QA-1115 | P3 | functional | no | VERIFIED |
| M07-R3-018 | ETQAN-QA-1116 | P3 | theme | no | VERIFIED |
| M07-R3-019 | ETQAN-QA-1117 | P3 | UI/layout | yes | VERIFIED |
| M07-R3-020 | ETQAN-QA-1118 | P3 | copy | yes | VERIFIED |
| M07-R3-021 | ETQAN-QA-1119 | P4 | UI/layout | yes | VERIFIED |
| M07-R3-022 | not reproduced: the working tree already shows "0 من 1" in `<bdi>`, the filter now says "بلا مستوى فقط" like the cells, phone cards show "—" under منذ, and "M07 المستوى 1" renders in correct RTL order (repro `t022-levels-bidi.png`, `t022b-levels-phone.png`) | - | - | - | CLOSED |
| M07-R3-023 | ETQAN-QA-1120 (picker only; title order already fixed) | P4 | functional | yes | VERIFIED |
| M07-R3-024 | ETQAN-QA-1121 | P3 | responsive | no | VERIFIED |
| M07-R3-025 | ETQAN-QA-1122 | P2 | responsive | no | VERIFIED |
| M07-R3-026 | ETQAN-QA-1123 | P3 | responsive | no | VERIFIED |
| M07-R3-027 | ETQAN-QA-1124 | P2 | responsive | no | VERIFIED |
| M07-R3-028 | ETQAN-QA-1125 | P3 | responsive | no | VERIFIED |
| M07-R3-029 | ETQAN-QA-1126 (action column/wrap; page-level 768 overflow gone) | P3 | responsive | no | VERIFIED |
| M07-R3-030 | not reproduced: at 768 the sidebar now collapses to the menu button; Today table 718/718 with the status column visible, Sessions table fits (repro `t030-today-768.png`, `t030b-sessions-768.png`); the remaining per-word wrapping is covered by ETQAN-QA-1101 | - | - | - | CLOSED |
| M07-R3-031 | ETQAN-QA-1127 (body copy; buttons already fixed) | P3 | translation | yes | VERIFIED |
| M07-R3-032 | ETQAN-QA-1128 (not-found state + 404 refetch; redirect+toast now work) | P4 | UI/layout | yes | VERIFIED |
| M07-R3-033 | ETQAN-QA-1129 | P3 | translation | yes | VERIFIED |
| M07-R3-034 | ETQAN-QA-1130 | P3 | functional | no | VERIFIED |
| M07-R3-035 | not a bug: B9d L-6 — the topbar control is a two-way "EN" toggle while the `spanish` switch is off (qaother) and a three-language menu when it is on (qa); same reasoning as M03-R3-012 | - | - | - | CLOSED |
| M07-R3-036 | ETQAN-QA-1131 | P3 | copy | yes | VERIFIED |

Filed: 32 (ETQAN-QA-1100…1131; 2×P2, 23×P3, 7×P4). Duplicates: 1 (008 → QA-045). Not reproduced: 2 (022, 030). Not bugs: 1 (035).

Gate cycle 1 (Agent 2, 2026-11-01): 31 of 32 VERIFIED in the browser (before/after in `qa/manual/screens/r3/M07/fix/`), regression tests 16 files / 191 tests pass. FAILED: ETQAN-QA-1109 (make-up dialog: date and time errors still on different rows because the time hint sits between input and error). Area FAILED, back to Agent 3.

Gate cycle 2 (Agent 2, 2026-11-01): ETQAN-QA-1109 VERIFIED (errors on one row under their inputs; AR 1440, AR 375, EN dark; `fix/1109-after-c2*.png`), regression vitest 5 files / 69 tests pass (`logs/M07/agent2-gate2-vitest.txt`). All 32 VERIFIED, no P0/P1 open. **Area PASSED.**

Sweep triage (Agent 2, 2026-11-01, after the Agent 1 confirmation sweep). Repro shots `triage/t037*.png`, `triage/t038-*.png`.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M07-R3-037 | ETQAN-QA-1132 (follow-up of QA-1102: Today and Simplified view still show "مجدولة" for the passed, unmarked 10:00 session that the list flags) | P3 | functional | no | VERIFIED (gate 3) |
| M07-R3-038 | ETQAN-QA-1133 (supervisor 375 card: date and time of الموعد spread apart) | P4 | responsive | yes | VERIFIED (gate 3) |

Sweep filed: 2 (ETQAN-QA-1132…1133; 1×P3, 1×P4). Area back to Agent 3.

Gate cycle 3 (Agent 2, 2026-11-01): ETQAN-QA-1132 VERIFIED (Today AR 1440 + EN 375 dark, Simplified view AR 1440 flag the passed unmarked session like the list; `fix/1132-*.png`), ETQAN-QA-1133 VERIFIED (supervisor AR 375, EN 375 dark, AR 1440; `fix/1133-*.png`). Regression vitest 4 files / 49 tests pass (`logs/M07/agent2-gate3-vitest.txt`). All 34 bugs (1100–1133) VERIFIED, no P0/P1 open. **Area PASSED.**

## M08

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M08/triage/`.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M08-R3-001 | ETQAN-QA-1150 | P3 | UI/layout | yes | VERIFIED |
| M08-R3-002 | ETQAN-QA-1151 | P3 | UI/layout | yes | VERIFIED |
| M08-R3-003 | ETQAN-QA-1152 | P3 | translation | yes | VERIFIED |
| M08-R3-004 | ETQAN-QA-1153 | P3 | translation | yes | VERIFIED |
| M08-R3-005 | ETQAN-QA-1154 | P3 | translation | yes | VERIFIED |
| M08-R3-006 | ETQAN-QA-1155 | P3 | UI/layout | no | VERIFIED |
| M08-R3-007 | ETQAN-QA-1156 | P4 | UI/layout | yes | VERIFIED (gate 2) |
| M08-R3-008 | ETQAN-QA-1157 | P4 | UI/layout | yes | VERIFIED |
| M08-R3-009 | ETQAN-QA-1158 | P4 | UI/layout | yes | VERIFIED |
| M08-R3-010 | ETQAN-QA-1159 | P3 | RTL | yes | VERIFIED |
| M08-R3-011 | placeholder: merged into 010 by Agent 1 (no separate finding) | - | - | - | - |
| M08-R3-012 | ETQAN-QA-1160 | P3 | functional | yes | VERIFIED |
| M08-R3-013 | ETQAN-QA-1161 | P3 | UI/layout | yes | VERIFIED |
| M08-R3-014 | ETQAN-QA-1162 | P3 | translation | no | VERIFIED |
| M08-R3-015 | ETQAN-QA-1163 | P3 | translation | yes | VERIFIED |
| M08-R3-016 | ETQAN-QA-1164 | P3 | translation | yes | VERIFIED |
| M08-R3-017 | not a bug: vouchers.md § How it works, "Void withdraws an unused code (expired ones too) for good"; cancelling an expired code is intended (repro `t017-expired-code-cancel.png`) | - | - | - | CLOSED |
| M08-R3-018 | placeholder: merged into 004 by Agent 1 | - | - | - | - |
| M08-R3-019 | placeholder: reserved placeholder, no finding | - | - | - | - |
| M08-R3-020 | ETQAN-QA-1165 | P4 | UI/layout | yes | VERIFIED |
| M08-R3-021 | not a bug: billing.md/vouchers.md, a discount code settles as one `code` payment on the invoice (status partly paid follows), `revenue_between` leaves out `code` payments, and "An invoice can carry only one discount" so Apply a code is hidden afterwards (repro `t015-invoice-184-ar.png`); the label "كود النظام" is filed under ETQAN-QA-1164 | - | - | - | CLOSED |
| M08-R3-022 | placeholder: merged into 008 by Agent 1 | - | - | - | - |
| M08-R3-023 | ETQAN-QA-1166 | P4 | spacing/icon | yes | VERIFIED |
| M08-R3-024 | ETQAN-QA-1167 | P4 | UI/layout | yes | VERIFIED |
| M08-R3-025 | ETQAN-QA-1168 | P3 | data | yes | VERIFIED |
| M08-R3-026 | not a bug: retry works. Agent 1's steps ran in separate browser contexts, which drop the sessionStorage the QA-309 fix uses; in one tab the decline page shows "حاول مرة أخرى" + hint (repro `t026-decline-same-tab.png`). Empty top band filed under ETQAN-QA-1170 | - | - | - | CLOSED |
| M08-R3-027 | ETQAN-QA-1169 | P4 | spacing/icon | yes | VERIFIED |
| M08-R3-028 | ETQAN-QA-1170 | P4 | UI/layout | yes | VERIFIED (gate 2) |
| M08-R3-029 | ETQAN-QA-1171 | P4 | spacing/icon | yes | VERIFIED |
| M08-R3-030 | ETQAN-QA-1172 | P3 | translation | yes | VERIFIED |
| M08-R3-031 | ETQAN-QA-1173 | P4 | copy | yes | VERIFIED |
| M08-R3-032 | ETQAN-QA-1174 | P3 | functional | yes | VERIFIED |
| M08-R3-033 | ETQAN-QA-1175 | P3 | responsive | no | VERIFIED |
| M08-R3-034 | ETQAN-QA-1176 | P3 | responsive | yes | VERIFIED (gate 2) |
| M08-R3-035 | ETQAN-QA-1177 | P3 | copy | yes | VERIFIED |
| M08-R3-036 | ETQAN-QA-1178 | P3 | translation | yes | VERIFIED |
| M08-R3-037 | ETQAN-QA-1179 | P3 | translation | yes | VERIFIED |
| M08-R3-038 | ETQAN-QA-1180 | P3 | translation | yes | VERIFIED |
| M08-R3-039 | ETQAN-QA-1181 | P3 | responsive | no | VERIFIED |
| M08-R3-040 | ETQAN-QA-1182 | P3 | responsive | yes | VERIFIED |
| M08-R3-041 | ETQAN-QA-1183 | P4 | translation | yes | VERIFIED |
| M08-R3-042 | ETQAN-QA-1184 | P4 | responsive | yes | VERIFIED |
| M08-R3-043 | ETQAN-QA-1185 | P3 | copy | yes | VERIFIED |
| M08-R3-044 | ETQAN-QA-1186 | P3 | RTL | yes | VERIFIED |
| M08-R3-045 | ETQAN-QA-1187 | P4 | RTL | yes | VERIFIED |
| M08-R3-046 | not a bug: billing.md § Revenue, `revenue_between` counts `completed` and `credited` payments; the money moved to the wallet was received this month and is left out later when spent from the wallet (`wallet` method) | - | - | - | CLOSED |

Filed: 38 (ETQAN-QA-1150…1187). Not bugs: 4 (017, 021, 026, 046). Duplicates: 0 (010 is the QA-307 family, still visible; 035 is the QA-300 message on the donation form; 044 relates to ETQAN-QA-953). Placeholders: 4 (011, 018, 019, 022).

Gate cycle 1 (Agent 2, 2026-11-01): 35 VERIFIED, 3 FAILED (1156: names in the codes usage cell still wrap and flip their brackets; 1170: the dead-link card has 25 px of padding above and 49 px below, from an empty CardContent; 1176: on a phone the local-method row is 224 px tall because `basis-56` sits in a column flex). Before/after shots are in `qa/manual/screens/r3/M08/fix/`.

Gate cycle 2 (Agent 2, 2026-11-01): 1156, 1170 and 1176 retested in the browser and VERIFIED (shots `*-after-c2*.png` in `qa/manual/screens/r3/M08/fix/`); vitest 5 files / 59 tests pass (`round-3/logs/M08/agent2-gate2-vitest.txt`). All 38 bugs (1150–1187) VERIFIED, no P0/P1, area PASSED.

Sweep triage (Agent 2, 2026-11-01): Agent 1's confirmation sweep found 6 new problems (047–052). All six reproduced in the browser (shots `qa/manual/screens/r3/M08/triage/t047-*` … `t052-*`). None is a duplicate: 047 is the shared-recipe form of ETQAN-QA-1224 (withdrawals only), 048 matches the ETQAN-QA-1100 fix pattern but on billing pages, and 050 is the exchange-rates page that ETQAN-QA-1175 left out.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M08-R3-047 | ETQAN-QA-1188 | P4 | UI/layout | yes | VERIFIED (gate 3) |
| M08-R3-048 | ETQAN-QA-1189 | P4 | spacing/icon | no | VERIFIED (gate 3) |
| M08-R3-049 | ETQAN-QA-1190 | P4 | responsive | yes | VERIFIED (gate 3) |
| M08-R3-050 | ETQAN-QA-1191 | P3 | responsive | yes | VERIFIED (gate 3) |
| M08-R3-051 | ETQAN-QA-1192 | P4 | RTL | yes | VERIFIED (gate 3) |
| M08-R3-052 | ETQAN-QA-1193 | P4 | spacing/icon | yes | VERIFIED (gate 3) |

Sweep filed: 6 (ETQAN-QA-1188…1193; 1×P3, 5×P4). Not bugs: 0. Duplicates: 0. The area is re-opened until these six are fixed and gated.

Gate cycle 3 (Agent 2, 2026-11-01): 1188–1193 retested in the browser (AR/EN, 375/768/1440, light and dark) and all VERIFIED; before/after shots `1188-*` … `1193-*` in `qa/manual/screens/r3/M08/fix/`. Vitest 39 files / 312 tests pass, incl. qa-m08-r3 24/24 (`round-3/logs/M08/agent2-gate3-vitest.txt`). All 44 M08 bugs (1150–1193) VERIFIED, no P0/P1 open: area PASSED.

## M06

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M06/triage/`. 45 findings → 39 bugs (ETQAN-QA-1050…1088: 21×P3, 18×P4), 4 dup/folded, 1 not reproduced (fixed), 1 not a bug.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M06-R3-001 | ETQAN-QA-1050 | P3 | responsive | no | VERIFIED |
| M06-R3-002 | ETQAN-QA-1051 | P3 | responsive | no | VERIFIED |
| M06-R3-003 | ETQAN-QA-1052 | P4 | spacing/icon | no | VERIFIED |
| M06-R3-004 | ETQAN-QA-1053 | P3 | UI/layout | yes | VERIFIED |
| M06-R3-005 | ETQAN-QA-1054 | P3 | UI/layout | yes | VERIFIED |
| M06-R3-006 | ETQAN-QA-1055 (missing success toast only; no early-start warning is correct because the default start is the day after the current end, and renewing an upcoming renewal / its auto-invoice are by design, subscriptions.md §5, billing.md) | P4 | functional | yes | VERIFIED |
| M06-R3-007 | ETQAN-QA-1056 (refusal itself is documented, subscriptions.md §7; the misleading offer is the bug) | P3 | functional | no | VERIFIED |
| M06-R3-008 | ETQAN-QA-1057 | P3 | copy | yes | VERIFIED |
| M06-R3-009 | ETQAN-QA-1058 | P3 | data | no | VERIFIED |
| M06-R3-010 | ETQAN-QA-1059 | P4 | UI/layout | yes | VERIFIED |
| M06-R3-011 | ETQAN-QA-1060 | P4 | copy | yes | VERIFIED |
| M06-R3-012 | dup of ETQAN-QA-1050 (sessions table on phone) | — | — | — | CLOSED |
| M06-R3-013 | ETQAN-QA-1061 (note-is-wrong part folded into ETQAN-QA-1058) | P4 | copy | yes | VERIFIED |
| M06-R3-014 | ETQAN-QA-1062 | P4 | copy | yes | VERIFIED |
| M06-R3-015 | ETQAN-QA-1063 (phone table part in ETQAN-QA-1050) | P3 | translation | yes | VERIFIED |
| M06-R3-016 | ETQAN-QA-1064 | P4 | spacing/icon | yes | VERIFIED |
| M06-R3-017 | ETQAN-QA-1065 | P4 | RTL | yes | VERIFIED |
| M06-R3-018 | ETQAN-QA-1066 | P3 | functional | no | VERIFIED |
| M06-R3-019 | ETQAN-QA-1067 | P3 | functional | no | VERIFIED |
| M06-R3-020 | ETQAN-QA-1068 | P3 | translation | yes | VERIFIED |
| M06-R3-021 | ETQAN-QA-1069 | P4 | RTL | yes | VERIFIED |
| M06-R3-022 | ETQAN-QA-1070 (regression of ETQAN-QA-216) | P3 | RTL | no | VERIFIED |
| M06-R3-023 | ETQAN-QA-1071 (calendar only; EN Monday-first vs AR Saturday-first in forms is by design, `schemas.ts weekdaysInOrder`) | P4 | functional | yes | VERIFIED |
| M06-R3-024 | ETQAN-QA-1072 | P3 | UI/layout | no | VERIFIED (gate 2) |
| M06-R3-025 | dup of ETQAN-QA-1066 (the "متوقفة" tab lists whole-schedule stops by design, scheduling-tools.md; the invisible stopped slot is filed there) | — | — | — | CLOSED |
| M06-R3-026 | dup of ETQAN-QA-1050 (schedules table on phone, 486/341 px) | — | — | — | CLOSED |
| M06-R3-027 | ETQAN-QA-1073 | P3 | translation | yes | VERIFIED |
| M06-R3-028 | ETQAN-QA-1074 | P4 | UI/layout | yes | VERIFIED |
| M06-R3-029 | ETQAN-QA-1075 | P3 | copy | yes | VERIFIED |
| M06-R3-030 | ETQAN-QA-1076 | P4 | UI/layout | yes | VERIFIED |
| M06-R3-031 | ETQAN-QA-1077 (names; regression of ETQAN-QA-209/218; table part in 1050, filter part in 1052) | P3 | RTL | yes | VERIFIED |
| M06-R3-032 | ETQAN-QA-1078 (members table part in 1050) | P4 | responsive | yes | VERIFIED |
| M06-R3-033 | ETQAN-QA-1079 | P4 | UI/layout | yes | VERIFIED |
| M06-R3-034 | ETQAN-QA-1080 | P3 | translation | yes | VERIFIED |
| M06-R3-035 | not reproduced: already fixed in the working tree (groups are phone cards at 375, delete button reads "حذف"; t035-groups.png, t035-groups-375.png) | — | — | — | CLOSED |
| M06-R3-036 | not a bug: renders in logical order "M04 Adam Brooks، M04 سارة …" with the Arabic comma; ETQAN-QA-170 fix holds (t035-groups.png) | — | — | — | CLOSED |
| M06-R3-037 | ETQAN-QA-1081 (20-row cut + three pickers; mirrored names and green buttons already fixed in the working tree) | P3 | functional | no | VERIFIED |
| M06-R3-038 | partly fixed in the working tree ("أضف فترة" labels, 2-column grid, success toast); remaining legend-box style folded into ETQAN-QA-1082 (t038-avail.png) | — | — | — | CLOSED |
| M06-R3-039 | ETQAN-QA-1083 | P4 | spacing/icon | no | VERIFIED |
| M06-R3-040 | ETQAN-QA-1084 | P3 | translation | yes | VERIFIED |
| M06-R3-041 | ETQAN-QA-1082 | P3 | UI/layout | no | VERIFIED |
| M06-R3-042 | ETQAN-QA-1085 | P4 | copy | yes | VERIFIED |
| M06-R3-043 | ETQAN-QA-1086 (feature-off page; no-permission H1 part is dup of ETQAN-QA-970; sidebar highlight on the archive sub-page is not a bug) | P4 | spacing/icon | yes | VERIFIED |
| M06-R3-044 | ETQAN-QA-1087 | P3 | functional | no | VERIFIED |
| M06-R3-045 | ETQAN-QA-1088 | P4 | theme | yes | VERIFIED |

Gate cycle 1 (Agent 2, 2026-11-01): 38 VERIFIED, 1 FAILED (ETQAN-QA-1072: the new teacher · period line garbles in RTL, "2026/11/18 – 2026/10/QA teacher · 19"). Proposals R3-M06-D1/D3/D5 accepted as proposals (1058/1081/1087 applied parts verified). Area M06: FAILED, back to Agent 3 for 1072.

Gate cycle 2 (Agent 2, 2026-11-01): ETQAN-QA-1072 VERIFIED (AR 1440 light/dark, AR 375 dark, EN 1440; the teacher · period line reads whole, Cancel present; shots `qa/manual/screens/r3/M06/fix/g2-*.png`). Regression: vitest 30/30, pytest candidates pass, tsc clean. All 39 VERIFIED (1058/1081/1087 with accepted proposals R3-M06-D1/D3/D5); no P0/P1 open. **Area M06: PASSED.**

Sweep triage (Agent 2, 2026-11-01, after gate cycle 2): 7 sweep findings (046–052) all reproduced in the browser (shots `qa/manual/screens/r3/M06/triage/t3-*`), 7 bugs filed ETQAN-QA-1089…1095 (2×P3, 5×P4), status OPEN. Area M06 REOPENED, back to Agent 3.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M06-R3-046 | ETQAN-QA-1089 (follow-up of 1070: separator not kept with a piece) | P4 | UI/layout | yes | VERIFIED |
| M06-R3-047 | ETQAN-QA-1090 | P3 | RTL | yes | VERIFIED |
| M06-R3-048 | ETQAN-QA-1091 (calendar missed the 1052 phone filter pattern) | P4 | responsive | yes | VERIFIED |
| M06-R3-049 | ETQAN-QA-1092 (follow-up of 1053) | P4 | UI/layout | yes | VERIFIED (gate extra cycle 4; failed gate 3: H1 dot led the wrapped line at 375) |
| M06-R3-050 | ETQAN-QA-1093 (follow-up of 1054/1064; teacher "تعطيل" included so one shared fix covers it) | P3 | UI/layout | yes | VERIFIED (gate extra cycle 4; failed gate 3: teacher "تعطيل" filled red) |
| M06-R3-051 | ETQAN-QA-1094 | P4 | translation | yes | VERIFIED |
| M06-R3-052 | ETQAN-QA-1095 (incl. period range wrapping with a leading "–") | P4 | UI/layout | yes | VERIFIED |

Gate cycle 3 (Agent 2, 2026-11-01): retested ETQAN-QA-1089…1095 in the browser (qa-admin AR/EN at 1440 and 375, light and dark; sessions r3-M06-g3-admin-ar/en; before/after shots `qa/manual/screens/r3/M06/fix/g3-*`). 5 VERIFIED (1089, 1090, 1091, 1094, 1095); 2 FAILED: **1092** — back links and owner title fixed, but the new bundle H1 "{{kind}} · {{owner}}" wraps at 375 with the "·" leading the second line (AR and EN), the 1089 defect class; **1093** — every M06 trigger fixed, but the teacher account "تعطيل" that triage put in scope is still filled red and was left out without an accepted proposal. Regression: vitest 5 files / 74 tests pass incl. every ETQAN-QA-1089…1095 test (logs/M06/gate3-vitest.log); tsc has one error in another area's file (`src/features/billing/qa-m08-r3.test.tsx:295`, M08), none in M06 (gate3-tsc.log). No data written (confirm dialogs opened and dismissed). No P0/P1 open. **Area M06: FAILED**, back to Agent 3 for 1092 and 1093.

Gate extra cycle 4 (Agent 2, 2026-11-01): ETQAN-QA-1092 VERIFIED (bundle H1 at 375 AR light / EN dark ends line 1 with "·", owner on line 2; AR 1440 one line; back links one pattern on bundle, archive, calendar, trial). ETQAN-QA-1093 VERIFIED (teacher 217 "تعطيل" outline red, its confirm filled red, dismissed without confirming; trial, groups and archive triggers still outline). Shots `qa/manual/screens/r3/M06/fix/g4-after-*.png`; before `g3-after-1092-bundle2-*-375*.png`, `g3-ref-1093-teacher217.png`. vitest qa-round3-m06, AccountActions, BundlePage, SubscriptionsList pass (`qa/manual/evidence/r3/M06/gate-4/vitest.txt`). No data written. All 46 M06 bugs (1050–1095) VERIFIED, no P0/P1 open. **Area M06: PASSED.**

## M01

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M01/triage/`; worker-log evidence `round-3/logs/M01/triage-worker.log`. 33 findings → 29 bugs (ETQAN-QA-1650…1678: 4×P2, 12×P3, 13×P4), 1 dup, 2 not a bug, 1 merged.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M01-R3-001 | ETQAN-QA-1650 | P4 | functional | yes | VERIFIED (gate 1) |
| M01-R3-002 | not a bug: the lost job was the stale worker (environment; the worker predated `tenants/tasks.py`); progress and a retry button are non-goals of spec 2026-10-29-fast-academy-creation. The missing way out for a stuck/failed academy is filed as ETQAN-QA-1654 | - | - | - | CLOSED |
| M01-R3-003 | ETQAN-QA-1651 | P2 | functional | no | VERIFIED (gate 1) |
| M01-R3-004 | ETQAN-QA-1652 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M01-R3-005 | ETQAN-QA-1653 | P2 | functional | no | VERIFIED (gate 1) |
| M01-R3-006 | ETQAN-QA-1654 | P3 | functional | no | VERIFIED (gate 1) |
| M01-R3-007 | ETQAN-QA-1655 | P3 | functional | no | VERIFIED (gate 1) |
| M01-R3-008 | ETQAN-QA-1656 | P2 | functional | no | VERIFIED (gate 1) |
| M01-R3-009 | ETQAN-QA-1657 | P3 | translation | yes | VERIFIED (gate 1) |
| M01-R3-010 | ETQAN-QA-1658 | P3 | translation | no | VERIFIED (gate 1) |
| M01-R3-011 | ETQAN-QA-1659 | P4 | RTL | no | VERIFIED (gate 1) |
| M01-R3-012 | ETQAN-QA-1660 | P2 | functional | yes | VERIFIED (gate 1) |
| M01-R3-013 | ETQAN-QA-1661 | P4 | copy | yes | VERIFIED (gate 1) |
| M01-R3-014 | ETQAN-QA-1662 | P4 | UI/layout | yes | VERIFIED (gate 2) |
| M01-R3-015 | dup of ETQAN-QA-007 (OPEN: Suspend/Reactivate leave no history entry); the doubled "Changed Status" row came from Agent 1's re-submitted 30 s save (ETQAN-QA-1651); per-switch detail of Copy features is an enhancement | - | - | - | CLOSED |
| M01-R3-016 | ETQAN-QA-1663 | P3 | functional | yes | VERIFIED (gate 1) |
| M01-R3-017 | ETQAN-QA-1664 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M01-R3-018 | ETQAN-QA-1665 | P3 | functional | no | VERIFIED (gate 1) |
| M01-R3-019 | ETQAN-QA-1666 | P3 | functional | no | VERIFIED (gate 1) |
| M01-R3-020 | ETQAN-QA-1667 | P4 | spacing/icon | yes | VERIFIED (gate 2) |
| M01-R3-021 | ETQAN-QA-1668 | P4 | copy | yes | VERIFIED (gate 1) |
| M01-R3-022 | ETQAN-QA-1669 (Source ref overflow only; per-academy totals not a bug, as round-1 M01-F-016) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M01-R3-023 | ETQAN-QA-1670 | P4 | copy | yes | VERIFIED (gate 1) |
| M01-R3-024 | ETQAN-QA-1671 | P4 | copy | no | VERIFIED (gate 1) |
| M01-R3-025 | ETQAN-QA-1672 | P3 | copy | yes | VERIFIED (gate 1) |
| M01-R3-026 | ETQAN-QA-1673 | P4 | UI/layout | no | VERIFIED (gate 1) |
| M01-R3-027 | ETQAN-QA-1674 | P3 | responsive | no | VERIFIED (gate 3) |
| M01-R3-028 | ETQAN-QA-1674 (merged with 027/028) | P3 | responsive | no | VERIFIED (gate 3) |
| M01-R3-029 | ETQAN-QA-1675 | P3 | responsive | no | VERIFIED (gate 2) |
| M01-R3-030 | ETQAN-QA-1676 | P4 | RTL | yes | VERIFIED (gate 1) |
| M01-R3-031 | not a bug: same as round-1 M01-F-028 (Academies search is name + subdomain by design; the Domains list searches hosts and shows the academy) | - | - | - | CLOSED |
| M01-R3-032 | ETQAN-QA-1677 | P3 | functional | no | VERIFIED (gate 1) |
| M01-R3-033 | ETQAN-QA-1678 | P3 | translation | yes | VERIFIED (gate 1) |

**Gate cycle 1 (Agent 2, 2026-11-01, resumed run): FAILED.** 25 of 29 VERIFIED; FAILED 1662 (Domains list at 1440 overflows: a 63-char label host can't break, Status/Primary/Custom/Verified cut), 1667 (chosen "Mark … paid (fill in the date and" cut in the 22rem select), 1674 (768/1024: list still squeezed to 159/≈415 px), 1675 (invoice phone cards labelled "2 Number:", "1 Period:"). All four P3/P4; no P0/P1 open; all P2s (1651, 1653, 1656, 1660) VERIFIED. 1657/1658/1659/1676/1678 VERIFIED under decision D-M01-1 (console English). Shots `qa/manual/screens/r3/M01/fix/g*` and `g2-*`; tests: pytest 10 files 156 passed, vitest login 13/13 (`round-3/logs/M01/gate2/`). State: ran the platform-account Test on AI/Online payments/Video meetings (no email); added nothing else at this resume (earlier gate part before the pause: domain gate.qa-r3-a.example.test added then disabled, invoice ETQ-2026-11-0001 for QA R3 A issued then voided, no email reached a real recipient).

**Gate cycle 2 (Agent 2, 2026-11-01): FAILED.** 28 of 29 VERIFIED; re-tested the 4 cycle-1 failures live (EN; Arabic console is English by D-M01-1). VERIFIED 1662 (Domains at 1440: table 791 = box 791, every column visible), 1667 ("Mark paid (fill in the date and method)" whole in the select at 1440), 1675 (375 invoice cards "Number:"/"Period:" without sort digits; academies/domains cards clean, no sideways scroll). FAILED 1674 (P3): the lists now fit at 768/1024, but `overflow-wrap:anywhere` on every cell and header splits words mid-word (Domains 768 "Disa/bled", "Pen/ding DNS", "Etqa/n Prem/ium", "IS PRI/MA/RY"; Academies "Suspende/d", "CURRE/NCY"; Invoices "PERIO/D", "STATU/S"; Users "I/D"; Domains 1024 still "Disabl/ed", "Pendin/g DNS"). No P0/P1 open. Shots `qa/manual/screens/r3/M01/fix/g3-*`; tests: pytest -p no:cacheprovider 4 files 37 passed (`round-3/logs/M01/gate3/pytest.log`); no dashboard change since cycle 1, so no vitest/tsc. State: none changed (reads only; mark-paid/void actions chosen but never run).

**Gate cycle 3 (Agent 2, 2026-11-01): PASSED.** 29 of 29 VERIFIED. Re-tested 1674 live (ops EN): at 768 and 1024 the five lists (Domains, Academies, Etqan invoices, Users, Platform accounts) fit (`.results` = table, no sideways scroll) and no word splits mid-word (per-character line-break check + screenshots); regression checks Domains 1440, invoice cards 375, Academies 768 dark all clean. No P0/P1 open; all P2s VERIFIED. Shots `qa/manual/screens/r3/M01/fix/g4-*`; tests: pytest -p no:cacheprovider 4 files 52 passed, ruff clean (`round-3/logs/M01/gate4/pytest.log`); no dashboard change, so no vitest/tsc. State: none changed (reads only).

**Sweep triage (Agent 2, 2026-11-01).** 7 sweep findings → 7 bugs (ETQAN-QA-1679…1685, all P4, OPEN); none dup or not-a-bug (no earlier bug covers them; 1681 follows up 1652, 1682 is a side effect of the 1662 list CSS, 1684 follows up 1664/1675, 1685 is the icon part of M01-R3-004 that 1652 didn't cover). Repro shots `qa/manual/screens/r3/M01/triage/t034…t040-*`. State: none changed (reads only; the copy-features action was chosen, never run).

| Finding | Bug | Severity | Type | Easy P3 | Status |
|---|---|---|---|---|---|
| M01-R3-034 | ETQAN-QA-1679 | P4 | RTL | yes | VERIFIED (sweep gate) |
| M01-R3-035 | ETQAN-QA-1680 | P4 | UI/layout | yes | VERIFIED (sweep gate) |
| M01-R3-036 | ETQAN-QA-1681 | P4 | UI/layout | yes | VERIFIED (sweep gate) |
| M01-R3-037 | ETQAN-QA-1682 | P4 | UI/layout | yes | VERIFIED (sweep gate) |
| M01-R3-038 | ETQAN-QA-1683 | P4 | responsive | yes | VERIFIED (sweep gate) |
| M01-R3-039 | ETQAN-QA-1684 | P4 | responsive | yes | VERIFIED (sweep gate) |
| M01-R3-040 | ETQAN-QA-1685 | P4 | spacing/icon | yes | VERIFIED (sweep gate) |

**Sweep gate (Agent 2, 2026-11-01): PASSED.** 7 of 7 sweep bugs VERIFIED live (sessions r3-M01-g5-en ops EN, r3-M01-g5-view ops-view): 1679 gloss isolated (U+2068/2069), brackets paired; 1680 ops-view switch labels one line (88 rows, max 28 px); 1681 invoice lines one row each, empty cells '-'; 1682 date cells one line at 1440 on Academies/Users/Domains/Platform accounts, 768/1024 Academies unchanged; 1683 375 breadcrumb keeps ETQ-2026-10-0003 whole; 1684 375 Action and Copy-from selects aligned (x=15, 345 px), Run aligned; 1685 plain No grey everywhere, Last test OK No still red. Light + dark checked. Area total 36/36 VERIFIED, no P0/P1. Shots `qa/manual/screens/r3/M01/fix/g5-*`; tests: pytest -p no:cacheprovider 3 files 44 passed (`round-3/logs/M01/gate5/pytest.log`); no dashboard change, so no vitest/tsc. State: none changed (reads only; copy-features action chosen, never run).

## M16

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M16/triage/`. 32 findings, all reproduced in the browser → 32 bugs (ETQAN-QA-1600…1631) + 1 found by Agent 2 during triage (ETQAN-QA-1632): 13×P3, 20×P4, no P0–P2. No duplicates; parts dropped: M16-R3-028 no-code entry page (not specced, certificates.md defines only `/verify/<code>`) and double request (not reproduced, one 404 per load). Tokens/manage links blurred or kept out of every shot.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M16-R3-001 | ETQAN-QA-1600 (`/register` redirecting signed-in users is by design, registration.md; the site header/hero is the bug) | P3 | functional | no | VERIFIED (gate 1) |
| M16-R3-002 | ETQAN-QA-1601 (signed-in booking `my/book/` exists, consultations.md) | P3 | functional | no | VERIFIED (gate 1) |
| M16-R3-003 | ETQAN-QA-1602 | P3 | translation | yes | VERIFIED (gate 1) |
| M16-R3-004 | ETQAN-QA-1603 (server `clean_contact` only checks non-empty ≤ 30) | P3 | data | yes | VERIFIED (gate 1) |
| M16-R3-005 | ETQAN-QA-1604 | P3 | functional | yes | VERIFIED (gate 1) |
| M16-R3-006 | ETQAN-QA-1605 | P4 | spacing/icon | yes | VERIFIED (gate 2; FAILED gate 1) |
| M16-R3-007 | ETQAN-QA-1606 (incomplete fix of ETQAN-QA-154: public booking not in its file list) | P3 | translation | yes | VERIFIED (gate 1) |
| M16-R3-008 | ETQAN-QA-1607 (pattern of ETQAN-QA-209/683) | P4 | RTL | yes | VERIFIED (gate 1) |
| M16-R3-009 | ETQAN-QA-1608 (return page's inline amounts added as a 4th layout) | P4 | UI/layout | no | VERIFIED (gate 2; FAILED gate 1) |
| M16-R3-010 | ETQAN-QA-1609 | P3 | copy | no | VERIFIED (gate 1) |
| M16-R3-011 | ETQAN-QA-1610 | P3 | translation | no | VERIFIED (gate 2; FAILED gate 1) |
| M16-R3-012 | ETQAN-QA-1611 (follow-up of ETQAN-QA-754, site-only fix) | P3 | UI/layout | yes | VERIFIED (gate 1) |
| M16-R3-013 | ETQAN-QA-1612 (512 and maskable icons byte-identical) | P3 | spacing/icon | no | VERIFIED (gate 1) |
| M16-R3-014 | ETQAN-QA-1613 | P4 | theme | no | VERIFIED (gate 1) |
| M16-R3-015 | ETQAN-QA-1614 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M16-R3-016 | ETQAN-QA-1615 | P4 | functional | yes | VERIFIED (gate 1) |
| M16-R3-017 | ETQAN-QA-1616 | P4 | copy | yes | VERIFIED (gate 1) |
| M16-R3-018 | ETQAN-QA-1617 | P4 | translation | yes | VERIFIED (gate 1) |
| M16-R3-019 | ETQAN-QA-1618 (follow-up of ETQAN-QA-759) | P4 | functional | yes | VERIFIED (gate 1) |
| M16-R3-020 | ETQAN-QA-1619 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M16-R3-021 | ETQAN-QA-1620 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M16-R3-022 | ETQAN-QA-1621 (scrollWidth 1537 @1440, 1018 @375) | P3 | responsive | yes | VERIFIED (gate 1) |
| M16-R3-023 | ETQAN-QA-1622 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M16-R3-024 | ETQAN-QA-1623 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M16-R3-025 | ETQAN-QA-1624 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M16-R3-026 | ETQAN-QA-1625 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M16-R3-027 | ETQAN-QA-1626 (pattern of ETQAN-QA-684) | P3 | RTL | yes | VERIFIED (gate 1) |
| M16-R3-028 | ETQAN-QA-1627 (title copy only; no-code entry page not a bug — not specced; double request not reproduced) | P4 | copy | yes | VERIFIED (gate 1) |
| M16-R3-029 | ETQAN-QA-1628 | P4 | translation | yes | VERIFIED (gate 1) |
| M16-R3-030 | ETQAN-QA-1629 (same doubling as ETQAN-QA-776) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M16-R3-031 | ETQAN-QA-1630 (follow-up of ETQAN-QA-773) | P4 | responsive | yes | VERIFIED (gate 1) |
| M16-R3-032 | ETQAN-QA-1631 | P3 | theme | yes | VERIFIED (gate 1) |
| M16-R3-T01 (Agent 2) | ETQAN-QA-1632 registration weekdays Monday-first in Arabic (`RegisterForm` fixed `DAYS`, not `weekdaysInOrder`) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M16-R3-033 (sweep) | ETQAN-QA-1633 (EN card footer wraps at 768) | P4 | responsive | yes | VERIFIED (gate 3) |
| M16-R3-034 (sweep) | ETQAN-QA-1634 (residual of ETQAN-QA-1607 on the marketing consultation page) | P4 | RTL | yes | VERIFIED (gate 3) |
| M16-R3-035 (sweep) | ETQAN-QA-1635 | P4 | spacing/icon | yes | VERIFIED (gate 3) |
| M16-R3-036 (sweep) | ETQAN-QA-1636 (wording split since ETQAN-QA-1615) | P4 | translation | yes | VERIFIED (gate 3) |

**Gate cycle 1 (Agent 2, 2026-11-01):** 30/33 VERIFIED; FAILED ETQAN-QA-1605 (check indicator 14 px above the teacher row), ETQAN-QA-1608 (checkout card teacher/time grid differs from `detailRows` used on return/paid-link pages), ETQAN-QA-1610 (regression: U+2069 isolate glued to the English manage URL in the booking email → link 404s; English block still right-aligned). Tests: marketing vitest 4 files/80 pass, dashboard vitest 9 files/129 pass, backend pytest 6 files/97 pass. Shots `qa/manual/screens/r3/M16/fix/*-g-*.png` (tokens blurred). Data: bookings CR-000016 (Sat 7 Nov 19:30) and CR-000017 (19:00), both paid with the SIMULATOR, for m16r3g-gate@qa.etqan.test; qa academy's cached PWA icon keys cleared.

**Sweep triage (Agent 2, 2026-11-01):** 4 sweep findings 033–036 all reproduced (shots `qa/manual/screens/r3/M16/triage/t033…t036`), no dups/non-bugs → ETQAN-QA-1633…1636 (4×P4) OPEN for Agent 3. No state changed.

**Gate cycle 3 (Agent 2, 2026-11-01): PASSED.** 1633, 1634, 1635, 1636 VERIFIED in the browser (EN/AR at 768/375/1440; after shots `qa/manual/screens/r3/M16/fix/g3-*`); vitest marketing round3-m16 20/20 + dashboard login.test.tsx 13/13 (`qa/manual/round-3/evidence/r3/M16/gate-3/`). All 37 bugs 1600–1636 VERIFIED, no P0/P1. No state changed.

## M12

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M12/triage/`.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M12-R3-001 | ETQAN-QA-1350 (residual of ETQAN-QA-508 order proposal) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M12-R3-002 | ETQAN-QA-1351 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M12-R3-003 | ETQAN-QA-1352 | P3 | responsive | no | VERIFIED (gate 1) |
| M12-R3-004 | ETQAN-QA-1353 | P3 | responsive | no | VERIFIED (gate 1) |
| M12-R3-005 | ETQAN-QA-1354 | P3 | responsive | yes | VERIFIED (gate 1) |
| M12-R3-006 | ETQAN-QA-1355 (residual of ETQAN-QA-1162: academy settings not covered) | P3 | RTL | yes | VERIFIED (gate 1) |
| M12-R3-007 | ETQAN-QA-1356 | P3 | translation | no | VERIFIED (gate 1) |
| M12-R3-008 | ETQAN-QA-1357 | P3 | functional | yes | VERIFIED (gate 1) |
| M12-R3-009 | ETQAN-QA-1358 | P4 | UI/layout | no | VERIFIED (gate 1) |
| M12-R3-010 | ETQAN-QA-1359 | P3 | translation | yes | VERIFIED (gate 1) |
| M12-R3-011 | ETQAN-QA-1360 | P3 | translation | yes | VERIFIED (gate 1) |
| M12-R3-012 | ETQAN-QA-1361 | P3 | functional | yes | VERIFIED (gate 1) |
| M12-R3-013 | ETQAN-QA-1362 | P4 | translation | yes | VERIFIED (gate 1) |
| M12-R3-014 | ETQAN-QA-1363 (follow-up of ETQAN-QA-1251: divided-header cards) | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M12-R3-015 | ETQAN-QA-1364 (the "الدفع المحلي" card now has a divided header; rest holds) | P4 | UI/layout | no | VERIFIED (gate 1) |
| M12-R3-016 | ETQAN-QA-1365 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M12-R3-017 | ETQAN-QA-1366 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M12-R3-018 | ETQAN-QA-1367 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M12-R3-019 | ETQAN-QA-1368 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M12-R3-020 | ETQAN-QA-1369 | P3 | functional | yes | VERIFIED (gate 1) |
| M12-R3-021 | ETQAN-QA-1370 | P4 | RTL | yes | VERIFIED (gate 1) |
| M12-R3-022 | ETQAN-QA-1371 | P4 | RTL | yes | VERIFIED (gate 2; gate 1 FAILED: description detached from the code by dir=auto + text-start) |
| M12-R3-023 | ETQAN-QA-1372 (EN now shows the time; 24-hour format remains in AR and EN) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M12-R3-024 | ETQAN-QA-1373 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M12-R3-025 | ETQAN-QA-1374 | P4 | translation | yes | VERIFIED (gate 1) |
| M12-R3-026 | ETQAN-QA-1375 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M12-R3-027 | ETQAN-QA-1376 (term القالب/السمة only; palette names are D-M02-3) | P4 | translation | yes | VERIFIED (gate 1) |
| M12-R3-028 | ETQAN-QA-1377 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M12-R3-029 | not a bug: by design, a named theme replaces only the neutral tokens and the academy's brand primary/accent stay (docs/features/academy-settings.md § Appearance; `palettes.ts` header). Repro `t029-dracula.png`: --primary #50A083, background Dracula | - | - | - | CLOSED |
| M12-R3-030 | not reproduced: with role 36 (role.* + student.view*) the refusal names the codes above the tabs ("صلاحيات لا تملكها: الفواتير: إضافة، … عرض الكل.") plus the toast; ETQAN-QA-506's fix holds. Ticking only-then-refusing is QA-506's accepted design. Repro `t030-escalation-refusal.png`; 403, no role created; temp grant undone | - | - | - | CLOSED |
| M12-R3-031 | ETQAN-QA-1378 | P4 | UI/layout | yes | VERIFIED (gate 1) |

Gate cycle 1 (Agent 2, 2026-11-01): 28 VERIFIED, 1371 FAILED. Before/after shots `qa/manual/screens/r3/M12/fix/`; pytest 101 pass, vitest 12 files 141 pass + 1 unrelated failure (`LastSignIn > joins device, IP and zone`, stale since M04's QA-1018 fix) in `qa/manual/evidence/r3/M12/gate-1/`. Data: created and deactivated code m12r3-gate-01; one reconcile run (double-click retest).

Gate cycle 2 (Agent 2, 2026-11-01): 1371 VERIFIED (description under the code at the page start edge, word order kept; 1440 AR/EN, 375 AR light/EN dark). All 29 bugs (1350–1378) VERIFIED, area PASSED. vitest CodesPage.test.tsx 14/14 (`qa/manual/evidence/r3/M12/gate-2/`). No data changed.

## M05

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M05/triage/`. Session `r3-M05-t-admin-ar`. Test copies made while reproducing 009 were deleted.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M05-R3-001 | ETQAN-QA-1400 | P3 | translation | yes | VERIFIED |
| M05-R3-002 | ETQAN-QA-1401 | P3 | UI/layout | yes | VERIFIED |
| M05-R3-003 | ETQAN-QA-1402 | P3 | translation | yes | VERIFIED |
| M05-R3-004 | ETQAN-QA-1403 | P3 | translation | no | VERIFIED |
| M05-R3-005 | ETQAN-QA-1404 | P3 | copy | yes | VERIFIED |
| M05-R3-006 | ETQAN-QA-1405 | P3 | spacing/icon | yes | VERIFIED |
| M05-R3-007 | ETQAN-QA-1406 | P4 | spacing/icon | yes | VERIFIED |
| M05-R3-008 | ETQAN-QA-1407 (same pattern as QA-1016) | P3 | copy | yes | VERIFIED |
| M05-R3-009 | ETQAN-QA-1408 | P3 | functional | yes | VERIFIED |
| M05-R3-010 | ETQAN-QA-1409 | P3 | copy | yes | VERIFIED |
| M05-R3-011 | ETQAN-QA-1410 (recorded-page Delete placement is in 1426) | P4 | UI/layout | yes | VERIFIED |
| M05-R3-012 | ETQAN-QA-1411 | P4 | theme | yes | VERIFIED |
| M05-R3-013 | ETQAN-QA-1412 | P3 | UI/layout | no | VERIFIED |
| M05-R3-014 | ETQAN-QA-1413 (layout part already fixed by QA-1022; wording only) | P4 | translation | yes | VERIFIED |
| M05-R3-015 | ETQAN-QA-1414 | P3 | UI/layout | yes | VERIFIED |
| M05-R3-016 | ETQAN-QA-1415 | P3 | functional | no | VERIFIED |
| M05-R3-017 | ETQAN-QA-1416 | P3 | translation | yes | VERIFIED |
| M05-R3-018 | ETQAN-QA-1417 (consultation dialog footer included) | P3 | UI/layout | no | VERIFIED |
| M05-R3-019 | ETQAN-QA-1418 | P3 | translation | yes | VERIFIED |
| M05-R3-020 | ETQAN-QA-1419 | P4 | spacing/icon | yes | VERIFIED |
| M05-R3-021 | ETQAN-QA-1420 | P3 | responsive | no | VERIFIED |
| M05-R3-022 | ETQAN-QA-1421 (same shared FilePicker as QA-1022/1255) | P3 | translation | yes | VERIFIED |
| M05-R3-023 | ETQAN-QA-1422 | P3 | UI/layout | yes | VERIFIED |
| M05-R3-024 | ETQAN-QA-1423 | P3 | functional | yes | VERIFIED |
| M05-R3-025 | ETQAN-QA-1424 (same as QA-551 on the other lists) | P4 | copy | yes | VERIFIED |
| M05-R3-026 | ETQAN-QA-1425 (Courses already fixed by QA-552) | P3 | copy | yes | VERIFIED |
| M05-R3-027 | ETQAN-QA-1426 | P3 | UI/layout | yes | VERIFIED |
| M05-R3-028 | ETQAN-QA-1427 | P3 | UI/layout | yes | VERIFIED |
| M05-R3-029 | ETQAN-QA-1428 | P3 | UI/layout | no | VERIFIED |
| M05-R3-030 | ETQAN-QA-1429 | P3 | translation | yes | VERIFIED |
| M05-R3-031 | ETQAN-QA-1430 (same pattern as QA-1077) | P4 | RTL | yes | VERIFIED |
| M05-R3-032 | ETQAN-QA-1431 | P4 | functional | yes | VERIFIED |
| M05-R3-033 | ETQAN-QA-1432 | P4 | UI/layout | yes | VERIFIED |
| M05-R3-034 | ETQAN-QA-1433 (levels-only parts are in 1414) | P3 | UI/layout | no | VERIFIED |
| M05-R3-035 | ETQAN-QA-1434 | P4 | copy | yes | VERIFIED |
| M05-R3-036 | dup of ETQAN-QA-1112 / decision D-M07-1 (native date-time placeholders "dd/mm/yyyy, --:-- --" stay by decision, D-M14-1 proposal); the calendar icon is now at the field end (QA-1083); "بتوقيت الأكاديمية" as one note under the date/time pair is the ETQAN-QA-1109 fix (by design); "دقائق التدريس" alone on the last row is the odd item of a 2-column grid, not a defect. Repro `t036-add-session-ar.png`, `t036-session-times-ar.png` | - | - | - | DUP |

### Gate cycle 1 (Agent 2, 2026-11-01, resume run)
- Result: **PASSED**: all 35 bugs (ETQAN-QA-1400…1434) VERIFIED, no P0/P1 open, no proposals needed.
- Retested in the browser as qa-admin, AR at 1440x900 (1420 at 375x812, 1430 at 768x1024; package 19 also in EN and dark). Before = `screens/r3/M05/triage/`, after = `screens/r3/M05/fix/g001…g036`.
- Tests (light load, one worker): vitest `src/qa-round3-m05.test.tsx` + `routes/_authed/catalogue.packages.$packageId.test.tsx` 55/55; pytest `catalogue/tests/test_services.py` + `learning/tests/test_quran.py` 27/27 (`logs/M05/a2-gate1-cycle1-*.log`).
- State: for 1408 one double-click made a single "غ (نسخة)" (id 29) and a second click made "غ (نسخة 2)" (id 30); both were deleted through the UI, and the list shows no copies. Nothing else was saved (delete dialog cancelled, price rows not saved).
- New small items for the sweep (not regressions of the gated bugs):
  - Levels: "إضافة مستوى" is centred on the filter block (label + select + hint), so it sits about 23 px below the course select (`g012`).
  - Level dialog: the sub-level/topic "إزالة" buttons are still filled red (`g013`/`g015`). This is the same pattern 1414 fixed on the rows.
  - Consultation edit dialog: "حذف" is a neutral outline button, while the other catalogue deletes use `destructiveOutline` (`g031`).
  - Content page: the course filter label sits beside the select, while on Levels it sits above (`g020`).
- Environment note: `qa/manual/sessions/` was emptied during the run (probably another area's cleanup), which signed out the stored sessions. The gate signed in again on each call.

### Sweep triage (Agent 2, 2026-11-01, resume run)
Agent 1's sweep found no regressions of 1400–1434 and 7 new items (037–043). All 7 reproduced by Agent 2 (session `r3-M05-t2-admin-{ar,en}`, all calls `--nosave`, nothing saved; shots `screens/r3/M05/triage/t037…t043`). 038–041 are the gate's 4 sweep notes.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M05-R3-037 | ETQAN-QA-1435 (residual of QA-1420, whose scope did not list Consultations) | P3 | responsive | yes | VERIFIED |
| M05-R3-038 | ETQAN-QA-1436 | P4 | spacing/icon | yes | VERIFIED |
| M05-R3-039 | ETQAN-QA-1437 (same pattern QA-1414 fixed on the rows) | P4 | UI/layout | yes | VERIFIED |
| M05-R3-040 | ETQAN-QA-1438 | P4 | UI/layout | yes | VERIFIED |
| M05-R3-041 | ETQAN-QA-1439 | P4 | spacing/icon | yes | VERIFIED |
| M05-R3-042 | ETQAN-QA-1440 (follow-up of the QA-1427 fix) | P4 | translation | yes | VERIFIED |
| M05-R3-043 | ETQAN-QA-1441 | P4 | copy | yes | VERIFIED |

### Gate cycle 2 after sweep (Agent 2, 2026-11-01)
- Retested 1435–1441 in the browser (qa-admin, sign-in per call with `--nosave`; AR+EN, 1440 and 375, level dialog light+dark, consultation confirm EN dark). Shots `screens/r3/M05/fix/g2-14xx-*`. All 7 VERIFIED.
- Vitest (touched files only, `--maxWorkers=1`): qa-round3-m05, ProductsAdmin, ProductDialog, LevelsList, LevelDialog, ChaptersTable, ContentAdmin, qa-round3-m11, qa-round3-m15: 9 files/178 pass (`logs/M05/a2-gate2-vitest.log`). No backend change, so no pytest.
- Result: M05 PASSED, 42/42 VERIFIED, no P0/P1. Nothing was saved (the consultation delete confirm was opened, not clicked).


## M15

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M15/triage/` (sessions `r3-M15-t-*`, all calls `--nosave`; no data created). 38 findings → 32 bugs (ETQAN-QA-1300…1331: 1×P2, 8×P3, 23×P4), 4 dups, 2 not a bug. Backend 502s / Vite reloads from other areas during triage were retried, not filed. Partial dups noted on the row; the remaining parts were filed.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M15-R3-001 | ETQAN-QA-1300 (regression of the ETQAN-QA-457 phone-cards fix) | P2 | responsive | yes | VERIFIED |
| M15-R3-002 | ETQAN-QA-1301 | P3 | functional | no | VERIFIED |
| M15-R3-003 | ETQAN-QA-1302 | P3 | functional | yes | VERIFIED |
| M15-R3-004 | dup of ETQAN-QA-1603 (OPEN): same `clean_contact` + shared `BookingWizard`; CR-000014 stored with whatsapp `abc` (DB checked). The fix must cover the signed-in route `/learning/consultations/book` | - | - | - | CLOSED |
| M15-R3-005 | dup of ETQAN-QA-1604 (OPEN): same `BookingWizard`, also mounted at `/learning/consultations/book`; reproduced (`t005-pay-disabled.png`) | - | - | - | CLOSED |
| M15-R3-006 | ETQAN-QA-1303 | P3 | functional | yes | VERIFIED |
| M15-R3-007 | ETQAN-QA-1304 | P4 | copy | no | VERIFIED |
| M15-R3-008 | not a bug: consultations.md "Bookers cannot cancel"; an unpaid self-booking holds 30 min and `cancel_unpaid` cancels it (every 15 min). Missing back link is in ETQAN-QA-1324 | - | - | - | CLOSED |
| M15-R3-009 | ETQAN-QA-1305 (pattern of ETQAN-QA-1222) | P4 | RTL | yes | VERIFIED |
| M15-R3-010 | ETQAN-QA-1306 (same wrong reason as ETQAN-QA-1177, wallet form not covered) | P3 | functional | yes | VERIFIED |
| M15-R3-011 | ETQAN-QA-1307 (invoice + top-up dialogs; the booking checkout card part is ETQAN-QA-1608) | P4 | UI/layout | yes | VERIFIED (gate 2) |
| M15-R3-012 | ETQAN-QA-1308 | P4 | UI/layout | yes | VERIFIED |
| M15-R3-013 | ETQAN-QA-1309 (return-page reference part related to ETQAN-QA-1609) | P4 | copy | no | VERIFIED |
| M15-R3-014 | dup of ETQAN-QA-1192 (FIXED in tree): not reproduced, "M08 إنستاباي" now spans 1038–1127, at the right edge (`t014-invoice-page.png`) | - | - | - | CLOSED |
| M15-R3-015 | ETQAN-QA-1310 | P4 | copy | yes | VERIFIED |
| M15-R3-016 | ETQAN-QA-1311 | P4 | UI/layout | yes | VERIFIED |
| M15-R3-017 | ETQAN-QA-1312 (join window not specified, only the link styling kept) | P3 | copy | yes | VERIFIED |
| M15-R3-018 | ETQAN-QA-1313 (English date/time placeholders not a bug, decision D-M07-1) | P4 | copy | yes | VERIFIED |
| M15-R3-019 | ETQAN-QA-1314 | P4 | UI/layout | yes | VERIFIED (gate 2) |
| M15-R3-020 | ETQAN-QA-1315 | P4 | UI/layout | yes | VERIFIED |
| M15-R3-021 | ETQAN-QA-1316 | P4 | copy | yes | VERIFIED |
| M15-R3-022 | ETQAN-QA-1317 | P4 | RTL | yes | VERIFIED |
| M15-R3-023 | ETQAN-QA-1318 | P4 | spacing/icon | yes | VERIFIED |
| M15-R3-024 | ETQAN-QA-1319 | P3 | translation | yes | VERIFIED |
| M15-R3-025 | ETQAN-QA-1320 | P4 | UI/layout | yes | VERIFIED |
| M15-R3-026 | ETQAN-QA-1321 | P3 | translation | yes | VERIFIED |
| M15-R3-027 | ETQAN-QA-1322 (ETQAN-QA-469 fixed the invoice page only) | P3 | copy | no | VERIFIED |
| M15-R3-028 | ETQAN-QA-1323 for "أبكر/لاحقًا", name/email asked of a signed-in user, no card; timezone list = dup of ETQAN-QA-1606, blue radio = dup of ETQAN-QA-1605 | P4 | translation | no | VERIFIED |
| M15-R3-029 | dup of ETQAN-QA-1607 (OPEN): same teacher card in the shared `BookingWizard`; reproduced at 375 (`t029-phone-teacher.png`) | - | - | - | CLOSED |
| M15-R3-030 | ETQAN-QA-1324 | P4 | UI/layout | no | VERIFIED |
| M15-R3-031 | ETQAN-QA-1325 | P4 | UI/layout | yes | VERIFIED |
| M15-R3-032 | ETQAN-QA-1326 | P4 | UI/layout | yes | VERIFIED |
| M15-R3-033 | ETQAN-QA-1327 for list durations, no back link, unexplained disabled buy; raw length + stretched price card on the store page = dup of ETQAN-QA-1611 | P4 | UI/layout | yes | VERIFIED |
| M15-R3-034 | not reproduced: fixed by ETQAN-QA-1251 / D-M14-4. Subscriptions card measured 24 px under the header divider and 25 px at the bottom; sessions cards symmetrical (`t034-card-padding.png`, `t016-sessions-past.png`) | - | - | - | CLOSED |
| M15-R3-035 | ETQAN-QA-1328 | P4 | translation | yes | VERIFIED |
| M15-R3-036 | ETQAN-QA-1329 (confirmed in `PayFromWallet.tsx`: returns null until the wallet query resolves) | P4 | UI/layout | yes | VERIFIED |
| M15-R3-037 | ETQAN-QA-1330 | P4 | responsive | yes | VERIFIED |
| M15-R3-038 | ETQAN-QA-1331 | P4 | UI/layout | yes | VERIFIED |
| M15-R3-039 (sweep) | ETQAN-QA-1332 (residual of ETQAN-QA-1312: Home `JoinLink` without `asButton`) | P4 | UI/layout | yes | VERIFIED (gate 3) |
| M15-R3-040 (sweep) | ETQAN-QA-1333 (residual of ETQAN-QA-1326 on the "دوراتي المسجلة" list; label only in aria-label) | P4 | UI/layout | yes | VERIFIED (gate 3) |
| M15-R3-041 (sweep) | ETQAN-QA-1334 (BookPicker cards: transparent, r 8, pad 16, no shadow; no back link) | P4 | UI/layout | yes | VERIFIED (gate 3) |
| M15-R3-042 (sweep) | ETQAN-QA-1335 (residual of ETQAN-QA-1319: `ChildFilter` aria-label only, sessions + subscriptions) | P4 | UI/layout | yes | VERIFIED (gate 3) |
| M15-R3-043 (sweep) | ETQAN-QA-1336 (student's own top-up title uses the third person, AR + EN) | P4 | copy | yes | VERIFIED (gate 3) |
| M15-R3-044 (sweep) | ETQAN-QA-1337 (follow-up of ETQAN-QA-1324: note + pay button outside the card) | P4 | UI/layout | yes | VERIFIED (gate 3) |
| M15-R3-045 (sweep) | ETQAN-QA-1338 (EN `lapsed` wording) | P4 | translation | yes | VERIFIED (gate 3) |
| M15-R3-046 (sweep) | ETQAN-QA-1339 (residual of ETQAN-QA-1330, EN 375 postponed row) | P4 | responsive | yes | VERIFIED (gate 3) |

**Gate cycle 1 (Agent 2, 2026-11-01, resume run):** 30/32 VERIFIED, ETQAN-QA-1307 and ETQAN-QA-1314 FAILED (both P4 layout regressions inside the fix: broken total rule in `amountRows`; "تحقّق" button drops below the input when the code error shows). No P0/P1 open. Shots `qa/manual/screens/r3/M15/fix/`, tests `qa/manual/evidence/r3/M15/gate-1/vitest-m15.txt` (3 files, 57 pass). State: one 1 EGP simulated top-up checkout (6d9e9e86) created to reach the EN simulator and set to expire; nothing paid.

**Gate cycle 2 (Agent 2, 2026-11-01):** ETQAN-QA-1307 and ETQAN-QA-1314 VERIFIED (total rule unbroken in the invoice pay and top-up summary dialogs, AR/EN, light/dark, 1440/375; "تحقّق" level with the input when the code error shows, 1440/375). 32/32 VERIFIED, no P0/P1 open: M15 PASSED. Shots `qa/manual/screens/r3/M15/fix/c2-*`, tests `qa/manual/evidence/r3/M15/gate-2/vitest-m15.txt` (2 files, 70 pass). State: nothing created (top-up stopped at the fee summary, no checkout).

**Sweep triage (Agent 2, 2026-11-01, resume run, light load):** 8 sweep findings M15-R3-039…046 all reproduced in one batched Chromium (sessions `r3-M15-t2-*`, viewport shots `qa/manual/screens/r3/M15/triage/t039…t046-*.png`) → 8 bugs ETQAN-QA-1332…1339 (all P4), OPEN for Agent 3. No dups, no not-a-bug. State: nothing created (top-up dialog opened and closed without an amount).

**Gate cycle 3 (Agent 2, 2026-11-01, light load):** 1332…1339 retested in one batched Chromium (fresh logins, student AR/EN and parent Najjar AR; 1440, 768 dark, 375; before = triage shots copied as `fix/g3-<id>-*-before.png`, after `fix/g3-<id>-*-after.png`); vitest `qa-round3-m15.test.tsx` --maxWorkers=1 56/56 pass (`evidence/r3/M15/gate-3`). All 8 VERIFIED → 40/40, M15 PASSED. No state created (top-up dialogs opened and cancelled without an amount).

## M11

Agent 2, 2026-11-01. Every finding re-walked in the browser (qa-admin AR/EN, qa-teacher AR, qaother-admin AR; 375 and 1440). Repro shots: `qa/manual/screens/r3/M11/triage/`.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M11-R3-001 | ETQAN-QA-1500 | P3 | responsive | yes | VERIFIED (gate 1) |
| M11-R3-002 | ETQAN-QA-1501 | P3 | responsive | yes | VERIFIED (gate 1) |
| M11-R3-003 | ETQAN-QA-1502 (merged with the picker parts of 014, 015, 016: one root, the shared `FilePicker` not used) | P3 | translation | yes | VERIFIED (gate 1) |
| M11-R3-004 | ETQAN-QA-1503 (solid red delete part → 1510) | P3 | responsive | yes | VERIFIED (gate 1) |
| M11-R3-005 | ETQAN-QA-1504 | P3 | RTL | yes | VERIFIED (gate 1) |
| M11-R3-006 | ETQAN-QA-1505 | P3 | UI/layout | yes | VERIFIED (gate 1) |
| M11-R3-007 | dup of ETQAN-QA-1255: the native `<input type="month">` is drawn in the browser's language; native date/time/month controls stay by D-M14-1 / D-M04-1 (proposal: shared localised DateField) | - | - | - | CLOSED |
| M11-R3-008 | ETQAN-QA-1506 (also the phone card title and the template edit field) | P3 | RTL | yes | VERIFIED (gate 2; gate 1 FAILED: Title inputs still LTR, shared Input plaintext) |
| M11-R3-009 | ETQAN-QA-1507 | P4 | functional | yes | VERIFIED (gate 1) |
| M11-R3-010 | ETQAN-QA-1508 | P3 | responsive | yes | VERIFIED (gate 1) |
| M11-R3-011 | ETQAN-QA-1509 (plain "إلغاء" and lantern parts → 1520) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M11-R3-012 | ETQAN-QA-1511 (wording, orphan count, "نسخ"); the "الاشتراكات — لا شيء هذا الشهر" part is not a bug: the 26 September sessions are extras with `subscription: null` and no subscription overlaps September (student-reports.md); "إلغاء" part → 1520 | P3 | translation | yes | VERIFIED (gate 1) |
| M11-R3-013 | ETQAN-QA-1510 | P3 | UI/layout | yes | VERIFIED (gate 1) |
| M11-R3-014 | picker → ETQAN-QA-1502; type list → ETQAN-QA-1512 (residual of ETQAN-QA-670) | P4 | RTL | yes | VERIFIED (gate 1) |
| M11-R3-015 | picker → ETQAN-QA-1502; radio label + subtitle → ETQAN-QA-1513 | P4 | a11y | yes | VERIFIED (gate 1) |
| M11-R3-016 | picker → ETQAN-QA-1502; thumbnail, label, subtitle → ETQAN-QA-1514 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M11-R3-017 | ETQAN-QA-1515 (EN side effect of ETQAN-QA-1264) | P3 | responsive | yes | VERIFIED (gate 1) |
| M11-R3-018 | ETQAN-QA-1516 (wording only); the language-button part is not a bug: two-language toggle names its target, three-language menu names the current language, by D-M02-9 (ETQAN-QA-938) | P3 | translation | yes | VERIFIED (gate 1) |
| M11-R3-019 | ETQAN-QA-1517 | P4 | responsive | yes | VERIFIED (gate 1) |
| M11-R3-020 | ETQAN-QA-1518 | P4 | copy | yes | VERIFIED (gate 1) |
| M11-R3-021 | ETQAN-QA-1519 | P3 | functional | yes | VERIFIED (gate 1) |
| M11-R3-022 | ETQAN-QA-1521 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M11-R3-023 | ETQAN-QA-1520 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M11-R3-024 | ETQAN-QA-1522 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M11-R3-025 | not a bug: the teacher/student/parent honour board lists the published entries grouped by month, no picker (reviews-honour.md: `HonourBoard` "published entries grouped by month"); only October 2026 has a published entry. The lantern sits in empty space, not behind content (repro `t025-teacher-honour.png`) | - | - | - | CLOSED |
| M11-R3-026 | ETQAN-QA-1523 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M11-R3-027 | ETQAN-QA-1524 (spacing only; the detail dialog is dimmed under the confirm now, ETQAN-QA-666 holds) | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M11-R3-028 (sweep) | ETQAN-QA-1525 (residual of 1500 / QA-683: `PersonName` split by the card's flex row) | P3 | responsive | yes | VERIFIED (gate 3) |
| M11-R3-029 (sweep) | ETQAN-QA-1526 (Homework filters not covered by 1503) | P3 | responsive | yes | VERIFIED (gate 3) |
| M11-R3-030 (sweep) | ETQAN-QA-1527 (Reports counterpart of 1501) | P3 | responsive | yes | VERIFIED (gate 3) |
| M11-R3-031 (sweep) | ETQAN-QA-1528 | P4 | spacing/icon | yes | VERIFIED (gate 3) |
| M11-R3-032 (sweep) | ETQAN-QA-1529 (follow-up of QA-663 / 1519) | P4 | translation | yes | VERIFIED (gate 3) |
| M11-R3-033 (sweep) | ETQAN-QA-1530 (multi-line counterpart of 1506) | P3 | RTL | yes | VERIFIED (gate 3) |
| M11-R3-034 (sweep) | ETQAN-QA-1531, reclassified: the dashboard pattern is "+ إضافة …" (QA-1009/1039), so the six M11 add buttons without "+" are the bug, not the icon on «إضافة مادة» | P4 | spacing/icon | yes | VERIFIED (gate 3) |
| M11-R3-035 (sweep) | ETQAN-QA-1532 | P4 | functional | yes | VERIFIED (gate 3) |
| M11-R3-036 (sweep) | ETQAN-QA-1533 (side effect of the 1515 fix) | P4 | responsive | yes | VERIFIED (gate 4: one span per instant; 375 AR/EN dark + 1440 EN) |

Filed: 25 (ETQAN-QA-1500…1524; 13×P3, 12×P4). Not bugs: 1 (025) plus the not-a-bug parts of 012 and 018. Duplicates: 1 (007 → QA-1255). Merged: the picker parts of 014/015/016 into 1502. No P0/P1/P2. All 25 are OPEN for Agent 3.


**Gate cycle 1 (Agent 2, 2026-11-01, resume wf_e2176705-2b9):** 24 of 25 VERIFIED in the browser (AR/EN, 375/768/1024/1440, light and dark; shots `qa/manual/screens/r3/M11/fix/g2-*`); scoped vitest 14 files / 188 pass (`round-3/logs/M11/gate-1/vitest.txt`). FAILED: ETQAN-QA-1506. The homework edit «العنوان» input and the template «اسم القالب» input get `dir="rtl"` from `textDir()` but still render «M14-C واجب تأكيد» from the left, because the shared `ui/input.tsx` always adds `[unicode-bidi:plaintext]` (first strong letter wins). Back to Agent 3. No P0/P1 open. No data changed (confirms opened and cancelled, dialogs closed unsaved).

**Gate cycle 2 (Agent 2, 2026-11-01):** ETQAN-QA-1506 VERIFIED: the shared `ui/input.tsx` now uses `[unicode-bidi:isolate]` when a `dir` is passed, so the homework «العنوان» and template «اسم القالب» inputs start «M14-C …» / «M11 …» at the right (1440 dark, 375; shots `fix/g3-1506-*`); inputs without `dir` keep `plaintext` (QA-060). Scoped vitest 4 files / 58 pass (`round-3/logs/M11/gate-2/vitest.txt`). Area PASSED: 25/25 VERIFIED, no P0/P1 open. No data changed (dialogs closed unsaved).

**Sweep triage (Agent 2, 2026-11-01, resume wf_e2176705-2b9):** all 9 sweep findings (028–036) reproduced in the browser (AR/EN, 375/1440; shots `qa/manual/screens/r3/M11/triage/t028…t036-*`). Filed 9 OPEN: ETQAN-QA-1525…1533 (4×P3, 5×P4). No dups, no not-a-bug; 034 reclassified (add the "+" to the others). No data changed (dialogs closed unsaved; the admin AR/EN sessions had expired and were signed in again). Back to Agent 3.

## M10

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M10/triage/` (sessions `r3-M10t-{admin-ar,admin-en,teacher-ar,student-ar,staff-ar,parent-ar}`, all repro calls `--nosave`). 34 findings: 30 reproduced → 30 bugs ETQAN-QA-1450…1479 (2×P2, 8×P3, 20×P4); 4 not a bug (020 not reproduced, 025/029 by design as in round 1, 027 by route-guard spec). No duplicates of open register bugs; 003/012 are regressions of QA-604/617. Parts narrowed: 018 (date placeholder, D-M07-1), 019 (send-failure reason), 021 (preview format moved to 1473), 028 (subject by design). No data changed during triage (no messages or broadcasts sent; one existing broadcast email read in Mailpit).

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M10-R3-001 | ETQAN-QA-1450 (scrollWidth 1613 @1440 (repro t001-long-word.png)) | P2 | responsive | yes | VERIFIED (gate 1) |
| M10-R3-002 | ETQAN-QA-1451 (follow-up of ETQAN-QA-601; thread opens at scrollTop 0) | P2 | functional | yes | VERIFIED (gate 1) |
| M10-R3-003 | ETQAN-QA-1452 (regression of ETQAN-QA-604) | P3 | RTL | yes | VERIFIED (gate 1) |
| M10-R3-004 | ETQAN-QA-1453 (same class as ETQAN-QA-466) | P4 | RTL | yes | VERIFIED (gate 1) |
| M10-R3-005 | ETQAN-QA-1454 (pattern of ETQAN-QA-959) | P4 | RTL | yes | VERIFIED (gate 1) |
| M10-R3-006 | ETQAN-QA-1455 | P4 | RTL | yes | VERIFIED (gate 1) |
| M10-R3-007 | ETQAN-QA-1456 | P4 | responsive | yes | VERIFIED (gate 1) |
| M10-R3-008 | ETQAN-QA-1457 | P3 | copy | yes | VERIFIED (gate 1) |
| M10-R3-009 | ETQAN-QA-1458 | P4 | translation | yes | VERIFIED (gate 1) |
| M10-R3-010 | ETQAN-QA-1459 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M10-R3-011 | ETQAN-QA-1460 (scrollWidth 603 @375) | P3 | responsive | yes | VERIFIED (gate 1) |
| M10-R3-012 | ETQAN-QA-1461 (regression of ETQAN-QA-617) | P3 | RTL | yes | VERIFIED (gate 1) |
| M10-R3-013 | ETQAN-QA-1462 (related to 1478 (same columns)) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M10-R3-014 | ETQAN-QA-1463 | P4 | translation | yes | VERIFIED (gate 1) |
| M10-R3-015 | ETQAN-QA-1464 (email-only channel is by design (email-whatsapp.md); the locked checkbox presentation is the bug) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M10-R3-016 | ETQAN-QA-1465 (same fix as ETQAN-QA-611) | P4 | copy | yes | VERIFIED (gate 1) |
| M10-R3-017 | ETQAN-QA-1466 | P3 | responsive | yes | VERIFIED (gate 1) |
| M10-R3-018 | ETQAN-QA-1467 (narrowed: "dd/mm/yyyy" placeholder not a bug (decision D-M07-1, native controls stay); inverted range + no clear-filters filed) | P4 | functional | yes | VERIFIED (gate 1) |
| M10-R3-019 | ETQAN-QA-1468 (narrowed: per-row "why not sent" reason dropped (no reason is stored; feature request)) | P4 | translation | yes | VERIFIED (gate 1) |
| M10-R3-020 | not a bug: not reproduced — the Arabic Title/Message fields are `dir="rtl"` in the EN UI and read correctly ("غياب: {student}", "غاب {student} عن حصة {course} في {time}."); Agent 1's shot shows the same correct text (repro t020-tpl-en-arabic.png) | - | - | - | CLOSED |
| M10-R3-021 | ETQAN-QA-1469 (narrowed to the chips; the English preview's ISO date/IANA zone moved to 1473) | P4 | copy | yes | VERIFIED (gate 1) |
| M10-R3-022 | ETQAN-QA-1470 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M10-R3-023 | ETQAN-QA-1471 | P3 | responsive | yes | VERIFIED (gate 1) |
| M10-R3-024 | ETQAN-QA-1472 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M10-R3-025 | not a bug: chat.md moderation list shows "attachment counts" by design; same as round 1 M10-F-032 (CLOSED not a bug) (repro t025-files-count.png) | - | - | - | CLOSED |
| M10-R3-026 | ETQAN-QA-1473 (also covers the generated-text format from 021 (`text.py:when`)) | P4 | translation | no | VERIFIED (gate 1) |
| M10-R3-027 | not a bug: roles-permissions.md § Route guards — `requireOffice` sends teachers/students/parents to `/`; same ruling as M03-R3-023 (repro t027-teacher-people-redirect.png, t027-teacher-settings-denied.png) | - | - | - | CLOSED |
| M10-R3-028 | ETQAN-QA-1474 (follow-up of ETQAN-QA-609/617; subject "رسالة جديدة" not a bug (documented broadcast title, email-whatsapp.md)) | P3 | RTL | yes | VERIFIED (gate 1) |
| M10-R3-029 | not a bug: B5e/B5f define the group header as name only and the member list as office-only; same as round 1 M10-F-011 (CLOSED not a bug) (repro t029-student-group-header.png) | - | - | - | CLOSED |
| M10-R3-030 | ETQAN-QA-1475 (broadcasts part is 1465) | P4 | UI/layout | no | VERIFIED (gate 1) |
| M10-R3-031 | ETQAN-QA-1476 (follow-up of ETQAN-QA-619) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M10-R3-032 | ETQAN-QA-1477 (scrollWidth 1041 @1024, 777 @768) | P3 | responsive | yes | VERIFIED (gate 1) |
| M10-R3-033 | ETQAN-QA-1478 | P4 | responsive | yes | VERIFIED (gate 1) |
| M10-R3-034 | ETQAN-QA-1479 ("message text not searched" is not specced; filed as copy (placeholder) + empty wording + clipped focus ring) | P4 | UI/layout | yes | VERIFIED (gate 1) |

**Gate cycle 1 (Agent 2, 2026-11-01, resume run):** all 30 bugs ETQAN-QA-1450…1479 VERIFIED in the browser (AR/EN, 375/768/1024/1440, light + EN dark; one batched Chromium). Shots `qa/manual/screens/r3/M10/fix/g<ID>-after-*` with before copies `g<ID>-before-*`. Tests `qa/manual/evidence/r3/M10/gate-1/`: vitest 15 files/198 pass (`--maxWorkers=1`), pytest notifications text/email/whatsapp_choice/templates/scan 112 pass. Data: one broadcast "R3-M10 gate: …" to QA Student Three (Mailpit only). M10 PASSED.

**Sweep triage (Agent 2, 2026-11-01, resume run):** all 7 sweep findings reproduced in one batched Chromium run (fresh admin sign-in, viewport shots `qa/manual/screens/r3/M10/triage/t035…t041-*`). 6 filed, 1 not a bug. Nothing sent, saved or deleted.

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M10-R3-035 | ETQAN-QA-1480 (follow-up of 1478: log table 789 in 710/718 px box, "مقروء" at x=−54) | P4 | responsive | yes | VERIFIED (gate 2) |
| M10-R3-036 | ETQAN-QA-1481 | P4 | UI/layout | yes | VERIFIED (gate 2) |
| M10-R3-037 | ETQAN-QA-1482 (follow-up of 1452/1461; `LATIN_RUN` keeps `)`) | P4 | RTL | yes | VERIFIED (gate 2) |
| M10-R3-038 | ETQAN-QA-1483 (follow-up of 1454; block-mode `BidiText`) | P4 | RTL | yes | VERIFIED (gate 2) |
| M10-R3-039 | ETQAN-QA-1484 (`Confirm` trigger is `size="sm"`) | P4 | spacing/icon | yes | VERIFIED (gate 2) |
| M10-R3-040 | ETQAN-QA-1485 (same rule as 1459) | P4 | spacing/icon | yes | VERIFIED (gate 2) |
| M10-R3-041 | not a bug: stored data. The INV-000149/INV-000145 notices were written on 2026-10-27, before the round-2 fix of ETQAN-QA-102 (backend 6638b688, 2026-10-29); the current template renders "كانت الفاتورة INV-000149 للطالب SCN Student B1 (50.00 ج.م.) مستحقة في 26/10/2026." and "was due on Oct 26, 2026" (pinned by `notifications/tests/test_text.py`). Same ruling as the gate-1 note on old notices (repro t041-notifs-invoice-ar.png, t041-notifs-invoice-en.png) | - | - | - | CLOSED |

## M13

Agent 2, 2026-11-01. Repro shots: `qa/manual/screens/r3/M13/triage/`. All 37 findings reproduced; no duplicates, no not-a-bug. Narrowed: 003 (3-digit hex not required), 020 (placeholder colour is the app-wide token). Nothing saved by triage (all repro saves were refused 400s or client refusals, one no-change category save).

| Finding | Result | Severity | Type | Easy | Status |
|---|---|---|---|---|---|
| M13-R3-001 | ETQAN-QA-1550 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M13-R3-002 | ETQAN-QA-1551 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M13-R3-003 | ETQAN-QA-1552 (narrowed) | P3 | translation | yes | VERIFIED (gate 1) |
| M13-R3-004 | ETQAN-QA-1553 | P4 | translation | yes | VERIFIED (gate 1) |
| M13-R3-005 | ETQAN-QA-1554 (follow-up of ETQAN-QA-1255) | P3 | translation | no | VERIFIED (gate 1) |
| M13-R3-006 | ETQAN-QA-1555 (same family as ETQAN-QA-1016) | P3 | functional | yes | VERIFIED (gate 1) |
| M13-R3-007 | ETQAN-QA-1556 | P4 | translation | yes | VERIFIED (gate 1) |
| M13-R3-008 | ETQAN-QA-1557 | P4 | translation | yes | VERIFIED (gate 1) |
| M13-R3-009 | ETQAN-QA-1558 | P3 | UI/layout | no | VERIFIED (gate 1) |
| M13-R3-010 | ETQAN-QA-1559 | P3 | functional | yes | VERIFIED (gate 1) |
| M13-R3-011 | ETQAN-QA-1560 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M13-R3-012 | ETQAN-QA-1561 | P3 | RTL | yes | VERIFIED (gate 1) |
| M13-R3-013 | ETQAN-QA-1562 (same family as ETQAN-QA-1015 / ETQAN-QA-1254) | P3 | functional | yes | VERIFIED (gate 1) |
| M13-R3-014 | ETQAN-QA-1563 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M13-R3-015 | ETQAN-QA-1564 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M13-R3-016 | ETQAN-QA-1565 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M13-R3-017 | ETQAN-QA-1566 | P4 | translation | no | VERIFIED (gate 1) |
| M13-R3-018 | ETQAN-QA-1567 (follow-up of ETQAN-QA-703) | P3 | translation | yes | VERIFIED (gate 1) |
| M13-R3-019 | ETQAN-QA-1568 | P3 | translation | yes | VERIFIED (gate 1) |
| M13-R3-020 | ETQAN-QA-1569 (narrowed) | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M13-R3-021 | ETQAN-QA-1570 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M13-R3-022 | ETQAN-QA-1571 | P4 | UI/layout | yes | VERIFIED (gate 1) |
| M13-R3-023 | ETQAN-QA-1572 | P3 | UI/layout | no | VERIFIED (gate 1) |
| M13-R3-024 | ETQAN-QA-1573 (same family as ETQAN-QA-1025) | P3 | copy | yes | VERIFIED (gate 1) |
| M13-R3-025 | ETQAN-QA-1574 | P4 | theme | yes | VERIFIED (gate 1) |
| M13-R3-026 | ETQAN-QA-1575 | P4 | spacing/icon | yes | VERIFIED (gate 1) |
| M13-R3-027 | ETQAN-QA-1576 | P4 | translation | yes | VERIFIED (gate 1) |
| M13-R3-028 | ETQAN-QA-1577 (follow-up of ETQAN-QA-712) | P4 | data | no | VERIFIED (gate 1) |
| M13-R3-029 | ETQAN-QA-1578 | P4 | translation | yes | VERIFIED (gate 1) |
| M13-R3-030 | ETQAN-QA-1579 (same family as ETQAN-QA-969 / ETQAN-QA-1252) | P4 | theme | yes | VERIFIED (gate 1) |
| M13-R3-031 | ETQAN-QA-1580 | P4 | RTL | yes | VERIFIED (gate 1) |
| M13-R3-032 | ETQAN-QA-1581 | P4 | responsive | yes | VERIFIED (gate 1) |
| M13-R3-033 | ETQAN-QA-1582 | P3 | functional | no | VERIFIED (gate 1) |
| M13-R3-034 | ETQAN-QA-1583 | P4 | copy | yes | VERIFIED (gate 1) |
| M13-R3-035 | ETQAN-QA-1584 | P4 | translation | yes | VERIFIED (gate 1) |
| M13-R3-036 | ETQAN-QA-1585 | P3 | functional | yes | VERIFIED (gate 1) |
| M13-R3-037 | ETQAN-QA-1586 | P3 | functional | yes | VERIFIED (gate 1) |
| M13-R3-038 (sweep) | ETQAN-QA-1587 | P3 | responsive | yes | VERIFIED (gate 2) |
| M13-R3-039 (sweep) | ETQAN-QA-1588 (follow-up of ETQAN-QA-717) | P3 | responsive | yes | VERIFIED (gate 2) |
| M13-R3-040 (sweep) | ETQAN-QA-1589 (same family as ETQAN-QA-920) | P4 | UI/layout | yes | VERIFIED (gate 2) |
| M13-R3-041 (sweep) | ETQAN-QA-1590 | P4 | translation | yes | VERIFIED (gate 2) |

Gate cycle 1 (Agent 2, 2026-11-01, resumed run): all 37 (1550–1586) retested in the browser (AR/EN, 1440/768/375, light/dark) and VERIFIED; shots `qa/manual/screens/r3/M13/fix/g*.png`; tests `logs/M13/gate-2/` (vitest 9 files/128 pass in the dashboard container, --maxWorkers=1; pytest 2 pass). Accepted decisions: D-M13-1 (toast bottom-start; it can now sit over the end of a row's title or the order field, no controls), D-M13-4 (categories keep 2 per-button AI notes). Data: one accidental qaother save of a 60-char Arabic CTA (maxLength trimmed the 300 chars, so Save succeeded), restored to the default «احجز حصة تجريبية».

Sweep triage (Agent 2, 2026-11-01): all 4 sweep findings reproduced (shots `qa/manual/screens/r3/M13/triage/t038…t041`): 038 scrollWidth 802 @768 / 794 @375 EN; 039 active tab at −141…−54 px (AR) and 454…528 px (EN) on a 375 viewport; 040 3 + 1 at AR 768; 041 label confirmed AR + EN. No dups, no not-a-bug. Filed ETQAN-QA-1587…1590 (2×P3, 2×P4) OPEN for Agent 3. Read-only (no saves).

Gate cycle 2 after sweep (Agent 2, 2026-11-01): ETQAN-QA-1587…1590 VERIFIED in the browser (EN 768/375 testimonials, AR/EN 375 tab strip, AR/EN 768 + AR 375 dark + AR/EN 1440 settings; shots `qa/manual/screens/r3/M13/fix/g1587…g1590-*`); vitest 3 files/37 pass (`logs/M13/gate-3/`). Read-only. M13 PASSED: 41/41 VERIFIED.
