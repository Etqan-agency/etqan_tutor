# A2 Agent 2 (verifier) cycle 1 log
- 2026-10-28 22:30 start: 48 FIXED-UNVERIFIED bugs.
- 22:35 dashboard: 33 A2 test files in the dashboard container: 450/451 pass; MyBalance failed once under load (spinner timeout), passes alone (8/8). people.students.$personId 5/5.
- 22:38 backend: pytest etqan_billing + tenants test_admin_round2_qa, consultations test_name_initial, site test_public_api: 24 passed.
- 22:39 marketing: round2-a2 + closed + components: 52/52 (needs `vitest --configLoader runner`; default loader hits EACCES on node_modules/.vite-temp).
- 22:40 tsc --noEmit: 1 error, FamilySessions.test.tsx:202 onTestFinished; that line is from committed 430185f (round 1), not A2's diff.
- 22:40-23:20 browser checks (screens/round-2/A2/): admin AR (101,119,256,261,503,607,625,681,684,274,275,258,610,615,676,675,424), student AR (469,667,263,655,470,602,605), teacher AR (411,679,375), visitor AR (751,752,064,762,780), console EN (814,815). Rest by regression test (qa data has no article, no open consultation slot, no about section, site not closed).
- Diff review: no weakened validation (825 uses the shared clean_currency; 820 parses and refuses with a clear error; registration_open is additive).
- Side notes (not A2 regressions, not filed): homework answer dialog title starting in Latin ("M14-sweep memorise …") is left-aligned in AR; report print body starting in Latin shows the full stop at the wrong end.
- 23:20 register: 48 entries VERIFIED (round 2).
