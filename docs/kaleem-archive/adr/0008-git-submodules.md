---
number: "0008"
title: Meta repo with git submodules
status: accepted
date: 2026-04-12
---

## Context
Need to organize backend, dashboard, marketing, and infra as separable projects under one umbrella.

## Decision
Meta repo with 4 git submodules (backend, dashboard, marketing, infra). docs/ lives in the meta repo.

## Alternatives considered
- **Single monorepo with pnpm workspaces**: simpler git workflow, but mixes Python and Node tooling.
- **Fully separate repos**: no unified CI or docs location.

## Consequences
- Each sub-project has its own history and can be versioned independently.
- Submodule friction exists (detached HEAD, update commands).
- Escape hatch E1 (switch to pnpm monorepo) is pre-approved if friction > 1h/week.
