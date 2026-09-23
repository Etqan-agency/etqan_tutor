---
number: "0010"
title: allauth wrapping strategy in the identity module
status: accepted
date: 2026-04-12
---

## Context
allauth is kept (ADR-0004) but needs to be isolated so the rest of the app doesn't depend on it.

## Decision
The identity module's services.py exposes functions like register_student(), verify_email(), request_password_reset(). These wrap allauth internally. No other module imports from allauth.

## Alternatives considered
- **Direct allauth usage everywhere**: rejected — coupling every module to allauth makes replacement impossible.

## Consequences
- allauth is a detail of the identity module, not a system-wide dependency.
- If allauth is replaced, only identity/services.py changes.
- Each auth flow has a typed, testable service function.
