---
number: "0009"
title: CSRF token flow with React SPA
status: accepted
date: 2026-04-12
---

## Context
Need CSRF protection to work with a same-origin React SPA making API calls via Axios.

## Decision
- CSRF_COOKIE_HTTPONLY=False (so JavaScript can read the csrftoken cookie)
- SESSION_COOKIE_HTTPONLY=True (session cookie is not readable by JS)
- Axios configured with withXSRFToken=true, xsrfCookieName="csrftoken", xsrfHeaderName="X-CSRFToken"
- CORS_ALLOW_CREDENTIALS=True for localhost origins in local settings

## Alternatives considered
- **CSRF_COOKIE_HTTPONLY=True with a /csrf/ endpoint**: more complex, same security.

## Consequences
- Standard Django CSRF flow works transparently with Axios.
- No custom middleware or CSRF-exempt hacks needed.
