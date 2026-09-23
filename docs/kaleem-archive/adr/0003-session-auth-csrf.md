---
number: "0003"
title: Session cookies with real CSRF protection
status: accepted
date: 2026-04-12
---

## Context
The old MVP had CSRF middleware commented out and used a custom CsrfExemptSessionAuthentication — a real security vulnerability.

## Decision
Session cookies with real CSRF protection. Django's CsrfViewMiddleware is enabled. Frontend sends CSRF token via X-CSRFToken header using Axios withXSRFToken. SESSION_COOKIE_HTTPONLY=True, CSRF_COOKIE_HTTPONLY=False (so JS can read it).

## Alternatives considered
- **JWT**: more complex, refresh token dance, premature for web-only. Escape hatch E3 exists for mobile.
- **CSRF-exempt sessions**: rejected — the old code's security hole.

## Consequences
- Simpler, more secure than JWT for same-origin SPA.
- No refresh token complexity.
- JWT available as escape hatch E3 when native mobile work begins.
