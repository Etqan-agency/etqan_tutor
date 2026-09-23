---
number: "0006"
title: Sentry for error tracking, OpenTelemetry for instrumentation
status: accepted
date: 2026-04-12
---

## Context
Need error tracking and observability from Phase 0.

## Decision
Sentry (free tier or self-hosted) for error tracking in Django and React. OpenTelemetry SDK for vendor-neutral instrumentation. Prometheus + Grafana + Loki for metrics and logs. Uptime Kuma for external health checks.

## Alternatives considered
- **No monitoring**: rejected — can't debug what you can't see.
- **Full ELK stack**: overkill for solo, more ops burden.

## Consequences
- Errors visible immediately in Sentry dashboard.
- Structured JSON logs ingested by Loki.
- Grafana dashboards for metrics.
- Small ops burden for the monitoring stack itself.
