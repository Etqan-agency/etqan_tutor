# etqan — Copilot Instructions

This is a modular-monolith LMS. Key rules:

1. No module may import another module's models. Use `<module>/services.py` public API.
2. CSRF middleware is ENABLED. Never disable it.
3. Every feature needs a spec in docs/superpowers/specs/ BEFORE any code.
4. TDD: write failing test first, then code.
5. Business logic goes in services.py, never on models.
6. Git-flow in every repo: `feat/<name>` → `dev` → PR → `master`. Never commit directly to dev/trunk. No feature work in the meta repo (docs + submodule pointer bumps only). See ADR-0014.
7. Full roadmap: docs/superpowers/specs/2026-04-11-rebuild-roadmap-design.md
8. Current state: see STATE.md
