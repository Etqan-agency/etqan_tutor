# A1 agent 2 (verifier, cycle 1)
- 2026-10-28T20:00Z start: read README, group-A1, register regression-test lines.
- 2026-10-28T20:05Z backend (django container): 20 regression files, 520 passed. Diff review: identity (053/055/509/159), site+catalogue (770, name+bio only, no contact data), gateways (318 split refusal, no weakening), learning (265 IntegrityError->409). Nothing weakened.
- 2026-10-28T20:10Z dashboard (container): 38 touched test files, 511 passed. tsc: 1 error FamilySessions.test.tsx:202 onTestFinished — from committed 430185f (round 1), not this round's diff.
- 2026-10-28T20:12Z marketing: components+site tests 47 passed.
- 2026-10-28T20:15-20:45Z after shots in screens/round-2/A1/ (39 ids). Live checks: Arabic CSV students/sessions/courses, reset check API, not_authenticated code, verify-email used key, 770 switches on -> courses/packages/teachers render on /ar/ (switches restored to off), 372 filters in URL after reload, 365 one 404 no retries.
- Note 260: three options still read identically because those subscriptions have identical student/course/dates/teacher/status (data); option now carries dates+teacher+status as the register's Expected asks.
- 2026-10-28T20:50Z register: 48 VERIFIED (round 2). None failing.
