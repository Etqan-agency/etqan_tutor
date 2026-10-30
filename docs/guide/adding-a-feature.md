---
title: "Adding a feature"
---

The end-to-end recipe for a new feature, from spec to merged. It assumes you have read
[Architecture](architecture.md). The finance app (`backend/etqan/finance/`, expenses and
donations) is a small, complete example to copy from.

## 0. Spec and plan

1. Write `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`: the problem, scope,
   **non-goals**, data model, API, screens, permissions, and the feature switch.
2. Write `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`: test-first tasks small enough to
   review one at a time.
3. Branch `feat/<topic>` in every repo you will touch.

## 1. Backend app

Only for a new area. Most features extend an existing app.

```sh
just new-module <name>   # creates backend/etqan/<name>/{api,tests} with empty files
```

Then by hand:

- [ ] `apps.py`: an `AppConfig` with `name = "etqan.<name>"`.
- [ ] Add `"etqan.<name>"` to `TENANT_APPS` in `backend/config/settings/base.py` (to
      `SHARED_APPS` only if the data belongs to Etqan, not to an academy).
- [ ] `api/urls.py`, mounted in `backend/config/api_router.py` as
      `path("<prefix>/", include("etqan.<name>.api.urls"))`.
- [ ] Contracts in `backend/pyproject.toml` `[tool.importlinter]`: "`<name>` reaches other
      apps only through their services" and "other apps reach `<name>` only through its
      services". Also add the app to the `forbidden_modules` of "platform imports no business
      modules". Copy an existing pair (for example billing's).
- [ ] `just migrate` once you have models. That runs `migrate_schemas`, which covers every
      academy.

## 2. Model, services, API

- **Models** hold data only. Money is `amount_minor` (integer) plus `currency` (ISO code).
  Instants are `DateTimeField` in UTC.
- **Services** (`services.py`, or a `services/` package once it grows) hold every rule. Other
  apps and your views call these, never the models. To read another app's data, call *its*
  services.
- **Views** are thin: validate input with a serializer, call one service, return a payload.
  Each view declares who may call it:

  ```python
  class ThingListView(generics.GenericAPIView):
      permission_classes = [HasCode, FeatureOn]       # this order: 403 before 404
      feature = "things"                              # the feature switch
      permission_codes = {"GET": "thing.view_any", "POST": "thing.create"}
  ```

  Use the role classes (`IsTeacher`, `IsStudent`, `IsParent`, `ReadsOwn`…) for routes that
  aren't office work.
- **Outside services.** Get credentials only from `integrations.services.resolve(...)`. Send
  email only with `queue_email` / `send_email_now`. Meter use of Etqan's defaults with
  `etqan_billing.services.record_usage(...)`. Encrypt stored secrets with
  `etqan.platform.secrets`. See [Integrations](../features/integrations.md).
- **Links** in emails and notices come from `etqan.platform.frontend.app_url(path)`.

## 3. Register the switch and the codes

- [ ] **Feature switch.** Add a `_built("things", "Things", "<Arabic label>", "<group>",
      default=...)` entry to `REGISTRY` in `backend/etqan/platform/features.py`. Use
      `requires=(...)` if it depends on another switch. New features are usually off by default.
      Add the code to the dashboard's `FeatureCode` type in
      `dashboard/src/features/identity/schemas.ts`.
- [ ] **Permission codes.** Add a `Resource("thing", "Things", "<Arabic>", in_use)` (or an
      `Entry` for a single page) to `backend/etqan/access/registry.py`. `in_use` must list
      exactly the verbs your routes and screens check: `etqan.access.tests.test_routes` fails
      otherwise. If the academy's preset roles (`access/presets.py`) should hold the codes,
      add them there.

## 4. Background jobs

A periodic task runs in no academy until you make it. Wrap the body:

```python
@shared_task(name="things.daily")
def daily():
    return for_each_academy(services.do_daily_work, name="things.daily")
```

Then add a `CELERY_BEAT_SCHEDULE` entry in `backend/config/settings/base.py`. Use
`atomic=False` when the job calls an outside service and manages its own transactions.

## 5. Notifications

Don't import `notifications` from your app; the boundaries forbid it. Notifications finds
work by reading your app's services. Add a notice kind and a finder in
`backend/etqan/notifications/` (`kinds.py`, `finders.py`, `recipients.py`) that calls your
services. See [Notifications](../features/notifications.md).

## 6. Dashboard

- [ ] `dashboard/src/features/<name>/`: `api.ts` (calls through `@/lib/api`), `queries.ts`
      (TanStack Query hooks and keys), `schemas.ts` (zod), components, and `*.test.tsx` next to
      each one. Don't import other features. Shared pieces go to `src/ui/` or `src/lib/`.
- [ ] Routes in `dashboard/src/routes/_authed/…` (file-based). An office screen sets
      `staticData: { permission: "thing.view_any", feature: "things" }`, and `PermissionGate`
      then shows "no access" or "feature off" instead of the page.
- [ ] Navigation: an entry in `dashboard/src/features/shell/nav.ts` with `code` and `feature`.
- [ ] Strings: a new `dashboard/src/locales/{en,ar,es}/<area>.json` (one file per area, loaded
      automatically). `locales.test.ts` checks that the catalogues agree. Arabic is
      right-to-left, so check the layout in Arabic.
- [ ] Money through `src/lib/money.ts`. Never use floats for amounts.

## 7. Marketing site

Only if visitors see the feature: `marketing/src/…`, reading the academy's public API on the
same host. See [Website](../features/website.md).

## 8. Seed data

Add demo rows so others can see the feature: `backend/etqan/tenants/seeds/` and
`seed_dev`. Keep seeding idempotent, because `just seed` re-runs on existing academies.

## 9. Tests and checks

See [Testing](testing.md). Before you open a PR:

```sh
just test    # backend + dashboard types + marketing + boundaries
just lint    # ruff, biome, boundaries, gitleaks
just e2e     # if you touched a user journey (needs `just dev-backend`)
```

## 10. Document it

- [ ] Add or update the feature's page in `docs/features/` (copy the structure of an existing
      page) and its line in [`docs/features/README.md`](../features/README.md).
- [ ] If you changed a rule in `CLAUDE.md` (a new cross-cutting convention), update it.

## 11. Merge

Submodule PRs first, then the meta PR that bumps the pointers. See
[Onboarding → Git workflow](onboarding.md#git-workflow). A green `master` deploys to staging.
Migrations must be **expand first, contract later**: the old code must run against the new
schema, because deploys are blue/green and migrations are never reversed.
