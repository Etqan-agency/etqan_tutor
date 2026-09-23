---
number: "0004"
title: Keep django-allauth wrapped behind identity module
status: accepted
date: 2026-04-12
---

## Context
User expressed interest in custom auth for easy customization. allauth handles email verification, password reset, MFA, and social login — rewriting these is months of work.

## Decision
Keep allauth. Wrap it behind the identity module's public API. Nothing outside identity imports from allauth. If allauth is ever replaced, only the identity module changes.

## Alternatives considered
- **Custom auth from scratch**: rejected — auth edge cases are solved by allauth, DIY auth is a trap for solo devs.

## Consequences
- Auth concerns are solved by a battle-tested library.
- Customization happens via allauth's adapter system.
- Replaceable via escape hatch E6 if allauth becomes a blocker.
