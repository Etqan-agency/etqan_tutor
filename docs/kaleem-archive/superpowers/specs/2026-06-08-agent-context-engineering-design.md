---
name: agent-context-engineering
phase: 0
modules: []
status: approved
created: 2026-06-08
closed: null
---

## Goal

Reduce context loss when AI agents work on kaleem. Three concrete gaps:
(1) agents re-explore the codebase every session, burning tokens on grep/read;
(2) knowledge learned in one session doesn't reliably carry to the next; and
(3) product/business decisions made in chat have no home (ADRs are architecture-only).

This is Phase 0 agent-friendly infrastructure — no product features. It adds
tooling (CodeGraph), a product-decision log, and a session-end handoff ritual to
complement the existing CLAUDE.md / STATE.md / memory / ADR scaffolding.

## Components

### 1. CodeGraph — code re-exploration

[CodeGraph](https://github.com/colbymchenry/codegraph) is a 100%-local, pre-indexed
code knowledge graph exposed to agents over MCP. Agents query symbols, call graphs,
and change impact instead of grepping/reading files.

- **Install:** CLI globally via `curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh` (self-contained runtime, no Node dependency for the binary).
- **Index scope:** built at the meta-repo root (`codegraph init -i`) so one graph spans
  `backend/`, `dashboard/`, and `marketing/` → cross-stack queries work. CodeGraph honors
  nested `.gitignore` files and skips `node_modules`/`.venv`/`dist`/`build`/`target` by
  default, so vendored code is auto-excluded. Legacy `kaleem/` reference code is indexed
  (CLAUDE.md tells agents to read it to understand features — querying it is a feature, not a bug).
- **Registration:** a project-scoped `.mcp.json` committed in the meta repo registers the
  `codegraph serve --mcp` stdio server. Chosen over `codegraph install` (which writes to the
  machine-specific global `~/.claude.json`) so the wiring is reproducible across machines —
  the only per-machine requirement is the globally installed `codegraph` binary on PATH.
- **Re-indexing:** the MCP server watches the tree via native OS file events with a 2s debounce
  and syncs incrementally. No cron or manual re-index needed. (`codegraph sync` / `codegraph index --force` available as manual escape hatches.)
- **Index storage:** `.codegraph/codegraph.db` (SQLite) — local artifact, gitignored.
- **Adoption:** CLAUDE.md documents the 8 MCP tools and *when to prefer them over grep* so
  agents actually reach for them.

### 2. Product / business decision log

ADRs (`docs/adr/`) stay architecture-only. Product and business decisions made in chat
(pricing, scope, policy, partnerships) get a lightweight home so they don't vanish.

- **Location:** `docs/decisions/YYYY-MM-DD-<slug>.md`, one short file per decision.
- **Shape:** context · decision · why · who decided. A `docs/decisions/README.md` explains
  the log and links a template.
- **Capture:** a `/new-decision` command (mirrors the existing `/new-adr`) creates a file
  from the template in ~30 seconds.
- **Sensitivity:** decision *content* is governance/financial-adjacent → written but **not
  auto-committed**; the user decides when to commit. The scaffold (README, template, command)
  is normal infra and is committed.

### 3. `/handoff` — session-end ritual

CLAUDE.md already defines a session-*start* read (STATE.md, ISSUES.md, active spec). Nothing
captures state at session *end*. `/handoff` closes the loop:

- Update `STATE.md` (current / in-progress / next).
- Write or update a `project`-type memory capturing non-obvious in-flight context.
- Append a line to the week's journal (`docs/superpowers/journal/YYYY-WW.md`).

So the next session resumes without re-deriving where things stand.

## Files touched

- **New:** `.mcp.json`; `docs/decisions/README.md` + `docs/templates/decision.md`;
  `.claude/commands/new-decision.md`; `.claude/commands/handoff.md`;
  this spec; `docs/adr/0012-agent-context-engineering.md`.
- **Edit:** `.gitignore` (add `.codegraph/`); `CLAUDE.md` (CodeGraph tool guidance, new
  commands, "Where things live" rows).

## Out of scope

- Per-submodule CodeGraph instances (rejected: 3× config, tool not designed for it).
- Migrating existing ADRs or governance docs into the new decision log.
- Any automated re-indexing cron (watch mode covers it).
- Enforcing `/handoff` via a hook — it's a command the agent/user invokes, not automated.

## Test plan

This is config + markdown tooling; verification is manual:
- `codegraph status` reports a healthy index with non-zero symbols across backend/dashboard.
- A fresh Claude session sees the `codegraph` MCP server and its tools load.
- `codegraph_search` returns a known backend symbol.
- `/new-decision` produces a correctly-named, template-filled file in `docs/decisions/`.
- `/handoff` updates STATE.md, writes a memory, and appends to the journal.
- `.codegraph/` is gitignored; `git status` stays clean of the index.

## Open questions

None. Design approved 2026-06-08.

## ADR note

Editing CLAUDE.md is, per CLAUDE.md itself, a decision requiring an ADR. ADR-0012 records
this agent-tooling setup.
