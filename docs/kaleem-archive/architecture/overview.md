# kaleem Architecture Overview

## Module map

```mermaid
graph TD
    platform[platform<br/>cross-cutting utilities]

    identity[identity<br/>users, profiles, auth]
    billing[billing<br/>plans, subscriptions, stripe]
    scheduling[scheduling<br/>availability, bookings, sessions]
    assessment[assessment<br/>reports, ratings, progress]
    curriculum[curriculum<br/>courses, lessons]
    content[content<br/>resources, files]
    messaging[messaging<br/>chat, messages]
    notifications[notifications<br/>email, in-app, reminders]
    engagement[engagement<br/>points, badges, streaks]
    analytics[analytics<br/>dashboards, aggregation]

    scheduling --> identity
    scheduling --> billing
    scheduling --> notifications
    billing --> identity
    assessment --> identity
    assessment --> scheduling
    curriculum --> identity
    curriculum --> content
    content --> identity
    messaging --> identity
    messaging --> notifications
    notifications --> identity
    engagement --> identity
    analytics --> identity
    analytics --> scheduling
    analytics --> assessment
    analytics --> billing
    analytics --> engagement
```

## Boundary rules

1. No business module imports another module's models
2. All inter-module calls go through `<module>/services.py`
3. `analytics` is read-only — it never writes to other modules
4. `platform` is imported by all, imports from none
5. No circular dependencies at the module level
6. Enforced by `import-linter` in CI

## Current state

**Phase 0** — only `platform` module exists. All other modules are planned for later phases.
