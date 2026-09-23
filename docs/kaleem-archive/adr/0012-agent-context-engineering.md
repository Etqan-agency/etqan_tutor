---
number: "0012"
title: Agent context-engineering setup (CodeGraph + decision log + handoff)
status: accepted
date: 2026-06-08
---

## Context
AI agents lose context working on kaleem in three ways: they re-explore the
codebase every session (token-expensive grep/read), knowledge doesn't reliably
carry across sessions, and product/business decisions made in chat have no home
(ADRs are architecture-only). The existing CLAUDE.md / STATE.md / memory / ADR
scaffolding covers part of this but leaves these gaps. This ADR is required
because the setup edits CLAUDE.md, which CLAUDE.md itself declares a decision
requiring an ADR. Full design: docs/superpowers/specs/2026-06-08-agent-context-engineering-design.md.

## Decision
Add three pieces of Phase 0 agent tooling:
1. **CodeGraph** (colbymchenry/codegraph) — a 100%-local code knowledge graph
   exposed over MCP. Indexed at the meta-repo root so one graph spans the
   `backend`, `dashboard`, and `marketing` submodules. Registered via a
   committed project-scoped `.mcp.json`; the index (`.codegraph/`) is gitignored.
2. **Product/business decision log** at `docs/decisions/`, with a `/new-decision`
   command and template, separate from architecture ADRs.
3. **`/handoff` command** — a session-end ritual that updates STATE.md, writes a
   memory, and appends to the journal, complementing the session-start read.

## Alternatives considered
- **`codegraph install` global wiring** (writes `~/.claude.json`): rejected —
  machine-specific, not reproducible across machines or committable. Project
  `.mcp.json` is reproducible given a globally-installed `codegraph` binary on PATH.
- **One CodeGraph per submodule**: rejected — 3× config and servers, no
  cross-stack queries, and the tool isn't designed for it.
- **Extend ADRs to cover product decisions**: rejected — conflates architecture
  and business decisions; a separate lightweight log keeps each clean.
- **Enforce `/handoff` via a Stop hook**: deferred — kept as a manual command for
  now; can revisit if it's forgotten in practice.

## Consequences
- Agents can query symbols/callers/callees/impact instead of grepping, cutting
  exploration tokens. Value grows as the codebase grows (small in early Phase 0).
- A 3rd-party MCP server runs locally over all source. It is 100%-local with no
  network calls per the project; that is why it's acceptable.
- Each machine must have the `codegraph` CLI installed (`~/.local/bin` on PATH);
  the `.mcp.json` wiring itself is committed and shared.
- Product decisions now have a capture path; decision *content* is not
  auto-committed (governance/financial-adjacent).
- CLAUDE.md gains CodeGraph tool guidance and the two new commands.
