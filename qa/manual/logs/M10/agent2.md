# M10 Agent 2 log (triage)

- 2026-10-28T01:30:01Z start: read README, environment, register (QA-001..517), M10 findings (34). Known overlaps to check: QA-513/514/515 (templates), QA-102/104/060/153/306/254/502.
- 2026-10-28T01:39:17Z repro done F-001..F-034 (own shots in screens/M10/triage/t0NN-*). Student3 can_start toggled off for F-033 and restored on (verified after reload). No broadcast sent (confirm dialog left open, browser closed); EN template 400 refused, unchanged.
- 2026-10-28T01:41:36Z triage done: 23 confirmed → ETQAN-QA-600..622 (18 P3 incl. 16 easy, 5 P4), 5 dup (F-007→604, F-012→QA-102 note added, F-015→513, F-016→514, F-018→515), 6 not a bug (F-011, 013, 019, 027, 028, 032). Register, triage.md, progress.md updated. Register 'Next ID' left as is (parallel-run rule: ranges).
- 2026-10-28T02:04:37Z gate start: stack found stopped (Exited ~2 min, no Docker-down otherwise); restarted with dc.sh up -d --no-build per README, health/ready 200. Scoped vitest (chat+notifications+locales) 21 files / 218 pass -> evidence/M10/gate-1/vitest.txt.
- 2026-10-28T02:18:37Z gate done: 14 VERIFIED (600,603,606,608,609,611,612,613,614,616,617,620,621,622), 618 REOPENED, 604 NOT-A-BUG accepted, new ETQAN-QA-623 (P3 easy, email footer URL mirrored). pytest 1346+171 pass, tsc 0. Area M10 PASSED. Register + progress updated.
- 2026-10-28T12:24:22Z final gate start: triage M10-F-035..037 (sweep), then final status.
- 2026-10-28T12:27:00Z reproduced F-035 (bell 375 AR), F-036 (group 0 participants, 400, nothing created), F-037 (student c=4 blank) with own shots fg035/fg036/fg037; filed ETQAN-QA-624 (P3 easy), 625 (P3 easy), 626 (P4); triage rows added. QA-618 re-tested AR+EN via in-app link: top 0 both -> VERIFIED.
- 2026-10-28T12:27:34Z FINAL GATE: PASSED (no P0-P2). Verified 15 (618 added). Open 11 (easy P3 623/624/625 next cycle). progress.md row + '### M10 final gate', findings/M10.md summary written.
