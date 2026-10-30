---
title: "Developer guide"
---

For developers joining etqan_tutor. Read the pages in this order:

| Page | Read it when |
|---|---|
| [Onboarding](onboarding.md) | Day one: access, running the stack, seeded accounts, how work is done |
| [Architecture](architecture.md) | Before touching code: repos, request path, tenancy, module boundaries, permissions, dashboard |
| [Adding a feature](adding-a-feature.md) | Before your first feature: the checklist from spec to merge |
| [Testing](testing.md) | Before your first PR: commands, fixtures, coverage floors, CI |
| [Deploy](runbooks/deploy.md) | Environments, the pipeline, blue/green, rollback, config and secrets |
| [Operations](runbooks/operations.md) | Health, logs, background jobs, academy admin, backups, incidents |

How each feature works is in the [feature reference](../features/README.md). The binding
rules are in [`CLAUDE.md`](../../CLAUDE.md).

**Keeping this current.** These pages and `docs/features/` describe the system as it is. A PR
that changes behaviour updates them. Specs and plans in `docs/superpowers/` are design
history and are not edited afterwards.
