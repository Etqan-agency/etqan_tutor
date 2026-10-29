# Fast, background academy creation

**Problem.** Adding an academy in the staff admin (`/admin/tenants/academy/add/`) creates its
schema and runs every tenant migration (174 today) inside the web request. On production it
takes minutes and the browser waits, and as migrations grow it will pass the web worker's
timeout.

## Design

1. **A template schema.** `TENANT_BASE_SCHEMA = "academy_template"` and
   `TENANT_CREATION_FAKES_MIGRATIONS = True` in base settings (tests keep `pytest_template`).
   django-tenants then creates a new academy's schema by cloning the template and only *fakes*
   the migrations, so creation takes seconds.
   - `tenants.services.ensure_template()` keeps the template current: if it's missing, or has
     migrations left to apply, it is rebuilt by migrating a throwaway academy row. The row is
     then deleted and its schema kept, with the academy-settings row that migration writes
     removed. This is the logic in `conftest.py`, moved into the service; conftest calls it.
   - `bootstrap_platform` calls it. `ship.sh` already runs that after `migrate` on every deploy,
     so the template matches the new code before the new colour serves.
   - Provisioning also calls it first, so a template a deploy left behind can't be copied stale.
2. **Background provisioning.** `Academy.Status` gains `provisioning` and `failed`.
   - `services.request_academy(...)` (the admin's path): validates exactly as `create_academy`
     does, saves the academy with status `provisioning` and **no schema**, and saves its primary
     domain as `pending`, so its host 404s rather than reaching a missing schema. On commit it
     queues `tenants.tasks.provision_academy(academy_id, admin_email, admin_full_name)`.
   - The task creates the schema (a clone), then runs the steps `create_academy` runs today:
     settings, site defaults, first admin and their invite, preset tags, Supervisor preset. It
     then makes the domain active and the academy `active`. On error the build's transaction
     rolls back (schema included), the academy is marked `failed`, and the error re-raised for
     Celery's log.
   - The admin's Save returns at once with "Creating <name> in the background; refresh in a
     minute." The list shows the status.
   - No password goes through the queue: the admin path never set one; the invite does.
3. **`create_academy` stays synchronous** for the CLI (`create_academy`, `seed_dev`,
   `seed_staging`), sharing the same steps. It becomes fast through the template.

## Non-goals

- A retry button for a failed academy (re-add it after deleting the row).
- Progress beyond the status column.
- Changing the Etqan console or any API.

## Tests (TDD)

- `ensure_template` builds a missing template, leaves a current one alone, rebuilds a stale one.
- `request_academy`: provisioning row, pending domain, no schema until the task runs; validation
  errors are unchanged (duplicate subdomain, bad timezone).
- `provision_academy`: schema exists, admin and invite, domain active, status active. On an
  error in a step: status `failed`, and the error re-raised.
- The admin add form returns at once with the background message, and the academy ends up
  active (eager Celery in tests).
- `bootstrap_platform` ensures the template.
