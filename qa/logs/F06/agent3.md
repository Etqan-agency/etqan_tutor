# F06 Agent 3 (Debugger & Fix Engineer), fix cycle 1, attempt 1

## 2026-10-19 Start
- Read README (lean, resume), environment.md, register QA-039..042, Agent 2 log. Stack up.
- Read `scheduling/services/generation.py`, `subscriptions.py` (create/renew), `board.py`, `api/views.py`, payloads; docs `features/subscriptions.md`, plan-4 spec (P4-6, P4-9), B2a/B2b/B2f specs.

## Fixes (backend, scheduling only; no migration; additive API keys)
- QA-042: `generation.subscription_conflicts`, `views.detail(conflicts=)`; create + renew 201 add `conflicts`.
- QA-040: `rules.person_inactive`; `generate` skips into `skipped_inactive` (also in generate payload); Today board drops missing rows for inactive people (substitutions prefetched, constant queries).
- QA-039: first prototype (skip a renewal date held by a kept old session) broke `test_renewal.py::test_old_untouched_sessions_from_the_new_start_are_removed` and `test_today.py::test_a_session_always_shows_even_after_its_renewal_took_over`; B2b spec §10 documents the duplicate as design. Reverted -> NOT_A_BUG; overlap now reported by the QA-042 fix. QA spec TC-015 corrected; design change written as a proposal.
- QA-041: PROPOSAL (cross-app seam, lint-imports academy contract, session ids change). Mitigation: settings-form warning (dashboard `AcademySettingsForm.tsx` + 3 locales + vitest).

## Verification (REAL, local stack; all outputs in evidence/F06/fix-cycle-1/)
- New `etqan/scheduling/tests/test_generation_guards.py`: 9 failed on HEAD code, 9 passed with the fix.
- `pytest etqan/scheduling etqan/catalogue`: 1460 passed.
- ruff check + format: clean. lint-imports: 54 kept, 0 broken.
- Dashboard: new vitest fails before / 11 pass after; biome clean; tsc no errors.
- Docs: `docs/features/subscriptions.md` (conflicts key, inactive skip), `docs/features/academy-settings.md` (timezone note).
- Nothing committed. Did not touch etqan/site, dashboard website/nav/routeTree, marketing, or any academy data.
