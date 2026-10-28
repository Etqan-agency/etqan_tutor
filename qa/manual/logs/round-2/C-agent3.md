# Group C, Agent 3 (fixer), cycle 1

- 2026-10-28 20:30 Read README, group-C.md, register entries for the 24 bugs.
- 2026-10-28 20:45 Shared student picker `features/people/StudentPicker.tsx` (server search + hint + kept selection); wired into SubscriptionForm, AddSessionDialog, StudentRateDialog, HonourDialog (QA-202/273/371/663). Options keyed by id so an uncontrolled `register` select keeps its value.
- 2026-10-28 21:05 Shared `phoneCards` recipe (`ui/styles.ts`) + `data-label` cells on 9 tables (QA-118/173/268/315/369/428/430/457); `components/PhoneFilters.tsx` for list filters on phones (QA-173/315).
- 2026-10-28 21:20 Receipt rows (QA-472), invoice payment line wrap (QA-315), StatusChip nowrap (QA-178), system codes nowrap (QA-317), local-method instructions direction (QA-321), DialogFooter `start` slot for homework/certificate dialogs (QA-652/682), homework card chip + wording (QA-680), inquiry mailto/tel (QA-711).
- 2026-10-28 21:40 QA-171: backend additive `registrant_details` + dashboard panel (details, gendered kind, link to student).
- 2026-10-28 21:50 QA-779 marketing contact form; QA-818 / QA-822 Etqan console admin.
- 2026-10-28 22:00 NOTE: the shared scratchpad's helper scripts and two locale files (common.json, registration.json) were overwritten by parallel agents; my keys were re-applied (idempotent script). If keys `common.phoneFilters`, `people.picker`, `registration.admin.detail.{phone,dateOfBirth,gender,country,openStudent}`, `registration.admin.kind.adult_female` go missing again, re-add them.
- 2026-10-28 22:10 Checks: dashboard vitest on all touched suites green (unrelated flakes under load pass alone: FamilyDialog, MyBalance; SupervisorFields "Sara · Present" and payroll heading tests fail from other groups' bidi changes); tsc clean for my files (remaining errors are other groups': FamilySessions, unsaved-changes test, billing api `Outstanding`); backend pytest registration + admin tests green, ruff format/check clean on my files (I001 in etqan_billing/admin.py imports is not mine), lint-imports 54 kept; marketing components test green (run as root in the container: EACCES on .vite-temp otherwise).
- 2026-10-28 22:15 Register: 24 entries FIXED-UNVERIFIED (round 2); group-C.md ticked; 7 decision lines added.

# Cycle 2

- 2026-10-28 22:40 QA-779: `items-start` on the email/phone row + `empty:hidden` on the phone error span (email field no longer stretched). Marketing components test green.
- 2026-10-28 22:45 QA-818: invoice list's four date columns merged into one `Dates` column (`key_date`, ISO dates by status). Billing admin pytest 24 passed, ruff clean; lint-imports 53 kept, 1 broken (platform test_console_order, another group's).
- 2026-10-28 22:50 Register: both FIXED-UNVERIFIED (round 2, cycle 2); group-C.md ticked.
