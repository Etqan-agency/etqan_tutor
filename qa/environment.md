# QA environment

## Stack
- Local docker stack `docker-compose.local.yml` (project `etqan_tutor`), in the main checkout
  `~/Documents/Etqan tutor/etqan_tutor`. It is the only stack; don't start another.
- URLs:
  - `http://<sub>.etqan.localhost/app/` is the dashboard, `/api/v1/` the API, and `/` the
    academy's marketing site.
  - `http://etqan.localhost/admin/` is the Etqan staff console.
  - `http://mail.etqan.localhost/` is the Mailpit UI; its API is `http://localhost:8025/api/v1/`.
  - Health checks: `http://etqan.localhost/health/live/` and `/health/ready/`. A bare `/health/` is
    a 404 by design.
- DB: postgres 18 at `localhost:5433`, db `etqan`, user and password `etqan`.
  - Schemas: `public`, `academy_demo`, `academy_other`, plus the QA academies once created.
  - pytest uses its own `test_etqan` database (`--reuse-db`).
- Run docker compose through the helper, which applies the ETQAN-QA-001 workaround:
  `/Users/khaledsakr/.etqan-qa-tools/dc.sh`
  (`dc.sh exec -T django python manage.py …`, `dc.sh exec -T django pytest etqan/<app> -q`).
  It builds with `HOST_GID=1000`, because `just rebuild` fails on macOS (ETQAN-QA-001).
- Run manage.py inside an academy with `dc.sh exec -T django python manage.py tenant_command <cmd> --schema=academy_qa …`.
- `GATEWAYS_SIMULATE=True` and `ETQAN_AI_FAKE=True` (local defaults). Email goes over SMTP to
  mailpit, so nothing leaves the machine. WhatsApp, Zoom, Stripe, PayPal, Twilio, Google OAuth and
  VAPID have no credentials, so anything live there is BLOCKED.

## Code under test (2026-10-17)
| Repo | Commit | Note |
|---|---|---|
| meta `etqan_tutor` | 85a5160 (master) | |
| backend | adff9c9 | updated from 5bf7573 (688 commits) |
| dashboard | 5ed775d | updated from 4a0332d |
| infra | b16332f | |
| marketing | 1c87b0a | |
| tokens | 83bd39d (v0.3.0) | |

## Backup (taken before any change)
- `~/Documents/Etqan tutor/backups/etqan-pre-qa-2026-10-17.dump` (`pg_dump -Fc`, all schemas) and
  `etqan-globals-pre-qa-2026-10-17.sql`.
- Verified 2026-10-17: restored into the scratch DB `etqan_restore_check`. All 152 tables and 1,539
  rows had identical row counts. The scratch DB was then dropped.
- Also saved: `git-state-pre-qa.txt` (pre-update submodule commits) and `backend.env.pre-qa`.
- Restore: `pg_restore -h localhost -p 5433 -U etqan -d etqan --clean --if-exists etqan-pre-qa-2026-10-17.dump`.
  Restoring the old schema also needs the old code: `git -C etqan_tutor/backend checkout 5bf7573`
  etc.

## Setup log
1. Submodules checked out at their pointers (`git submodule update --checkout`, sources were the
   sibling clones).
2. `just rebuild` failed (ETQAN-QA-001), so the images were built with `HOST_GID=1000`.
3. Stopped django and celery, then `migrate_schemas`: 207 migrations over 3 schemas, exit 0.
4. `seed_dev`: exit 0 (demo and other already existed, data topped up).
5. `up -d`. The dashboard failed with EACCES because the old `dashboard_node_modules` volume was
   owned by the previous image's user. Recreated the volume (dependency cache only, no data).
   Dashboard 200.

## Accounts
- Seeded (password `e2e-EtqanTest-2026`):
  - demo: `admin@demo.test`, sara, omar, maryam, huda, bilal, yusuf, zaid
  - other: `admin@other.test`, kareem, layla, salma
- QA academies (created 2026-10-17 by F01 Agent 2; full table in `feature-inventory.md` § QA academies):
  - `qa` "Etqan QA Academy", `academy_qa`, Africa/Cairo/EGP, created through the admin Add form:
    admin `qa-admin@qa.etqan.test` / `QA-Admin-2026!`; people `qa-staff-nocode@`, `qa-staff-codes@`,
    `qa-supervisor@`, `qa-teacher@`, `qa-student@`, `qa-parent@` (`@qa.etqan.test`) / `QA-People-2026!`.
  - `qaother` "Etqan QA Other", `academy_qaother`, UTC/USD, created by `create_academy`:
    admin `qaother-admin@qa.etqan.test` / `QA-Other-2026!`.
  - Etqan staff (public): `ops@qa.etqan.test` / `QA-Etqan-Staff-2026!` (superuser),
    `ops-view@qa.etqan.test` / `QA-Etqan-View-2026!` (view only), `ops-noperm@qa.etqan.test` /
    `QA-Etqan-NoPerm-2026!` (no permissions).
  - Throwaways `qa-tmp-1`, `qa-tmp-tz` (broken timezone on purpose), `qa-tmp-race-a`, `qa-tmp-race-b`:
    suspended after F01; see feature-inventory.
  - Added by the F01 gap review (Agent 2, 2026-10-18):
    - Etqan staff (public, `is_staff`, not superuser): `ops-change@qa.etqan.test` / `QA-Etqan-Change-2026!`
      (view+change academy, view domain); `ops-add@` / `QA-Etqan-Add-2026!` (view+add academy);
      `ops-domain@` / `QA-Etqan-Domain-2026!` (view academy, view+change domain); `ops-view-all@` /
      `QA-Etqan-ViewAll-2026!` (every `view_*` of etqan_billing, integrations, identity,
      django_celery_beat, account, tenants).
    - `qa-tmp-r1ok` admin `qa-tmp-r1ok-admin@qa.etqan.test` / `QA-R1ok-2026!` (set via Forgot password, TC-168); suspended.
    - `qa-tmp-cmd` (id 17, created by TC-156 with admin `not-an-email`, ETQAN-QA-016): suspended.
    - `qa-tmp-abort` (TC-169), if created: suspended.
- Host Playwright: `pnpm install` cannot fetch the private `@etqan/tokens` git dependency, so F01 Agent 2
  installed `@playwright/test@1.62.1` + `@axe-core/playwright@4.13.0` in `qa/tools/pw/` (moved from the scratchpad, which the 2026-10-19 reboot wiped) and
  symlinked them into `dashboard/node_modules` (gitignored). Specs that call `manage()` need
  `E2E_MANAGE=/Users/khaledsakr/.etqan-qa-tools/manage-wrap.sh` because the checkout path has a space (ETQAN-QA-009).

## Helper scripts (durable, since 2026-10-19)
- The helper scripts live in `qa/tools/` (uncommitted). `~/.etqan-qa-tools` is a symlink to that
  directory with no space in the path.
  - `dc.sh`: docker compose with `HOST_GID=1000`.
  - `manage-wrap.sh`: the `E2E_MANAGE` target.
  - `pw/`: the host Playwright packages, symlinked into `dashboard/node_modules`.
- After a reboot, start Docker Desktop (`open -a Docker`), then run `~/.etqan-qa-tools/dc.sh up -d`.
- Run e2e from the meta repo with
  `E2E_MANAGE=/Users/khaledsakr/.etqan-qa-tools/manage-wrap.sh just e2e e2e/qa/<file>`.
