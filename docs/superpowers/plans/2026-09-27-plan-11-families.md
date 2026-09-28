# Plan 11 — Family Accounts and Payer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An academy groups siblings into a family and names who pays for it: one of the family's students or an active parent of one. Every new invoice for a student in the family, manual or automatic, then defaults to that payer. The payer is never silently repointed: when it stops qualifying, the family is flagged until an admin chooses again.

**Architecture:** Everything about families lives in `etqan.identity` (F-1).
- A new `Family` model (`name`, `notes`, `is_active`, `payer` → User) and one nullable `StudentProfile.family` column, so a student is in at most one family. The account type (`individual` | `family`) is derived from that column, never stored (D1).
- `services.py` owns every rule: `create_family`, `update_family`, `bulk_family`, the payer rule (`_payer_candidates`, `_payer_for`), the race-safe link (`_claim`), `payer_needs_choosing` (computed by two `EXISTS` annotations, never stored) and `family_payer(student_user_id)`, the one lookup billing uses.
- Billing's `payer_options` puts the family payer first, then the active guardians, then the student, deduplicated. `payer_choices`/`resolve_payer` keep their meaning (the default is the first; valid means listed), so manual and automatic invoices follow without other changes, and existing invoices never change.
- The API adds `GET/POST people/families/`, `GET/PATCH people/families/<id>/` and `GET people/families/payers/?students=`; the student payloads, filters, CSV and bulk action gain the family; `me/` shows the family's name.
- On the dashboard: People → Families (a list with Add and Edit dialogs, Retire and Restore, and a family page), the account type column, a family chip, two filters and three bulk actions on the students list, the family on the student form and profile card, and "Family payer" on the invoice form.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-09-27-families-design.md` (Phase B1, plan 2 of 4). It builds on:
- Plan 3, `2026-09-24-people-catalogue-design.md`: people, guardianship, the students bulk action, CSV, admin-only people routes;
- Plan 6, `2026-09-25-billing-design.md`: the one payer rule in `billing/services/payers.py` (P6-4), used by the invoice form's choices, manual invoices and the automatic invoices for subscriptions;
- Plan 10, `2026-09-27-profile-depth-design.md`: the student list's filters, the bulk bar, `profile_payload(*, staff)` and `me/`.

Where this plan fills a gap in the spec, the Decisions below say so.

**Verified:** a script applied the code in Tasks 1–11 in this plan's order, exactly as written here, to fresh copies of `backend@d32af77` and `dashboard@2ed4aab` (the current `main` of each). That covers every `Create`, `replace … with`, `Append to` and `Merge into` block, and the `makemigrations` command.
- Before each task's code went in, its new tests were run and failed. The few that passed are guards named in their task's Step 2 (junk filters ignored, no family on teachers, flat query counts, the older bulk actions' answers, admin-only routes).
- After each task, its format, lint, import-contract, type, test and coverage commands passed, and `ruff format --check` and `biome check` found the plan's code already formatted (the generated migration aside). The plan-applied dashboard is byte-identical to the one it was written from.
- Backend: 1358 → 1425 tests, coverage 97.95% → 98.0%.
- Dashboard: 668 → 691 tests, lines 94.27% → 94.36%, branches 87.77% → 88.06%, functions 81.65% → 82.08%.

The e2e suite then passed through Caddy, run the way the CI `e2e` job runs it: Django (`config.settings.local`, the file email backend, eager Celery) and the Vite preview on a freshly migrated and seeded database, plus the marketing server on `:4321` and a `caddy:2.11.4-alpine` edge (Django on `:18000` and the edge on `:8080` with the overrides Task 11 names, since `:80` and `:8000` were taken). That was 20 of 20, `families.spec.ts` included, twice on the same database, with no retry.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), meta repo (trunk `master`).
- The branch `feat/families` already exists in the meta repo, `backend/` and `dashboard/`, so do not create it. Check with `git -C backend branch --show-current` and `git -C dashboard branch --show-current` before Task 1 and Task 7.
- Nothing is merged without the user's approval. After merge, bump the submodule pointers in meta.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

**Backend commands**
- Run from `backend/` with the virtualenv `backend/.venv`. Export this environment once per shell:
  `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`
- Tests: `.venv/bin/pytest …`. Add `--create-db` once after Task 1, which adds a migration.
- Format: `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`
- Verify: `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE` and `E501` (88 columns).

**Dashboard commands**
- Run from `dashboard/` through `npx pnpm@10`.
- Format: `npx pnpm@10 exec biome check --write src e2e`
- New route files are picked up by the TanStack Router plugin. Regenerate `src/routeTree.gen.ts` with `npx pnpm@10 exec vite build` before `tsc` (Task 8).
- Verify: `npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: no hex colour literals and no Tailwind palette utilities anywhere, comments included. Semantic tokens only.

**Coverage and dev data**
- Coverage gates: backend ≥ 80% (`pytest --cov=etqan`); dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026` (admins only). Academies: `demo` (`admin@demo.test`) and `other` (`admin@other.test`).

**Tenancy and module boundaries**
- No new app (F-1). `Family` lives in `etqan.identity`, in `SHARED_APPS` and `TENANT_APPS`; migrate with `migrate_schemas`. Migration `0015_families` adds a table and one nullable column, no NOT NULL column on an existing table, so the old colour keeps working during a blue/green switch (`STATE.md`'s standing warning).
- Business logic lives in `etqan/identity/services.py`. Views parse, call one service, re-read and arrange a payload.
- Billing reaches identity only through `identity.services` (`family_payer`, plus Plan 6's `guardians_by_link` and `get_user`); billing tests use identity's services, never its models. `lint-imports` stays at 16 contracts kept.
- Keyword-only arguments with no default for flags and selectors: `_student_ids(*, required)`, `_family_students(ids, *, family)`, `update_family(family, *, fields)`.

**API and data rules**
- All routes under `/api/v1/`: `people/families/`, `people/families/<id>/`, `people/families/payers/`; the people and billing routes as before.
- Spec values, verbatim: a family's `name` is required, up to 120 characters; `notes` is text and admin-only; `is_active` defaults to `true`; `account_type` is `individual` or `family`; a family row is `id, name, is_active, payer {id, full_name, role}, payer_needs_choosing, students [{id, full_name}], notes, created_at`; the bulk answer for the family actions is `{updated, skipped: [{id, full_name, reason}]}`.
- Student and payer ids are user ids everywhere, as in every people route.
- Every write answers with a fresh read. There is no `PUT` or `DELETE` on a family.
- Every families route is `403` for non-admins and anonymous callers; an unknown or other-academy family is `404`.
- Family notes never appear in `me/`; a student's and each child's `me/` profile carries `family {id, name}` only.
- Errors name their field: `name`, `student_ids`, `payer_id` on the families routes; `name`, `payer_id`, `family_id`, `ids` on the bulk action.
- Any id from a query string goes through `people_filters.as_int` (`int()` inside `try`; negatives are junk): a filter id never 500s.
- The families list, the student list (and its CSV) with families, a parent's `me/` and `payer_choices` have query-count tests that stay flat as families grow.

**Dashboard strings and helpers**
- Every string is in `src/locales/en/common.json` and `src/locales/ar/common.json`; zod messages are i18n keys rendered through `useFieldError`; server field errors land through `applyServerErrors`, toasts use `errorText`.
- Where one accessible name is a prefix of another or also an `<option>` ("Family" and "Family to add to"; a family's name is a filter option and a chip), tests match exactly, by role, or inside the row or dialog.
- Screens work RTL and at phone width. Reuse `Pager`, `Fact`, `clean`, `applyServerErrors`/`errorText`, `useFieldError`; no copies.

**Tests**
- Each new assertion fails without the code under test; guards that pass beforehand are named in their Step 2.
- Cross-academy tests hold data in both academies, with the other academy's pk forced above this one's (`until_pk_exceeds`).

### Decisions this plan makes where the spec is silent or conflicts with the code

- **D1 — `account_type` is derived, not stored.** §3.2 lists it as a field the linking services "set together" with `family`; F-3 says it is derived. A second column could only ever disagree with the first, so there is none: `services.account_type(profile)` is `family` exactly when `family_id` is set, the payload uses it, and `?account_type=` filters on `family__isnull`. This needs no check constraint and no `db_default`, and `family` keeps the spec's `SET_NULL`.
- **D2 — One family per student.** The database forbids two by construction: one `family_id` column. The services refuse a student of another family with `400 {"student_ids": ["<name> is already in another family."]}` before writing, and link through `_claim`, a conditional `UPDATE … WHERE family_id IS NULL OR family_id = <this>`: of two admins racing for one student, the second gets `400 {"student_ids": ["A student joined another family meanwhile. Try again."]}` and nothing is written (the service is atomic).
- **D3 — The family-payer lookup.** Identity exposes `family_payer(student_user_id) -> User | None`: one query over `_families()`, None unless the family is active and its payer valid. Billing's `payer_options(student_user_id) -> [(person, relation)]` lists it first (`family`), then `guardians_by_link` (`guardian`), then the student (`student`), and keeps a person's first relation only, so a parent who is both family payer and guardian appears once, as the family payer. `payer_choices` is the people of `payer_options`, and `resolve_payer` is unchanged in shape; its refusal now reads "Choose the student, one of their guardians or their family's payer."
- **D4 — Validity (F-2, §3.3).** A payer is valid when active and either one of the family's students or a parent linked by guardianship to one of them. So: a deactivated payer student or payer parent, a payer student who left, a payer parent unlinked from every family student, and any payer of a family emptied by a bulk removal, all flag the family. Reads compute it with two `EXISTS` annotations (`payer_is_student`, `payer_is_parent`) plus `payer.is_active`; writes check the same rule through `_payer_candidates(profile_ids)`. A retired or flagged family supplies no payer.
- **D5 — The bulk payloads.** `create_family` takes `{name, payer_id}` and links the selected students who are in no family; `add_to_family` takes `{family_id}` (any family of this academy; the dashboard offers active ones) and counts students already in it as updated; `remove_from_family` takes nothing and may leave a family empty (it is then flagged). Students of another family are skipped and reported as `{id, full_name, reason: "in_another_family"}`, a code the dashboard translates. `create_family`'s payer must suit the students actually linked; a selection entirely in other families is `400 {"ids": ["Every selected student is already in a family."]}`. Only the family actions add `skipped`; the Plan 3 and Plan 10 actions still answer `{updated}`.
- **D6 — The payer choices for an unsaved set of students.** The Add and Edit dialogs and the bulk Create family dialog need a family's payer choices before it exists, which §5 has no route for. `GET people/families/payers/?students=1,2` answers `[{id, full_name, role}]`: the active students, then their active parents, each by name (junk ids and other academies' ignored, at most 100).
- **D7 — Where the admin UI lives.** `/people/families` (list, search, a Status filter, Add and Edit dialogs, Retire and Restore) with a nav item "Families" after Parents in People, and `/people/families/$familyId`, a family page that the students' family chips and the student form link to (it uses §5's `GET families/<id>/`).
- **D8 — The dialogs always send a payer.** The dialog's payer select lists the chosen students' choices, asked only while the dialog is open and again when the students change; a payer who no longer suits them (a flagged family's, or one whose student was removed) is cleared, so saving asks for a new one. §4.1's "an update may leave the payer invalid" stays an API and bulk path.
- **D9 — The invoice form's label.** The server marks the family payer `relation: "family"` and the form labels it "{{name}} (Family payer)"; no comparison in the dashboard. The other relations and every existing payer test are unchanged.
- **D10 — The students list's family pickers.** The Family filter and the bulk bar's "Family to add to" list up to 100 families by name (the API's page maximum), the filter marking retired ones and the bulk bar offering active ones only.
- **D11 — Seeds.** `FAMILIES["demo"]`: "Omar family" with Yusuf Omar and Aisha Omar, their father Omar Hassan paying (already their first guardian, so the seeded invoices keep their payer). `seed_families` runs after `seed_profiles`; it does nothing when a family of that name exists, and prints a `skip:` line for a missing person or a refused family. `other` gets none.

## Review Focus

- **Two admins racing for one student.** Both pass the "not in another family" check before either commits; the second must get a 400 and write nothing, never move the student. Test: Task 1 `test_a_student_claimed_meanwhile_is_a_400_and_nothing_is_written`.
- **Editing a flagged family.** The form still holds the old payer's id; saving it unchanged would pass it back as if chosen. The dialog must clear it and ask for a new payer, and removing a student must re-ask the choices. Tests: Task 8 `FamilyDialog` "asks a flagged family for a new payer and re-asks when a student leaves"; Task 1 `test_a_new_payer_must_suit_the_resulting_students`.
- **The payer of a bulk-created family chosen from a skipped student's parents.** A parent of only the student who was skipped must be refused, and nothing linked. Test: Task 4 `test_the_payer_must_suit_the_students_actually_linked`.
- **Junk and huge ids.** `family=x`, `family=-1`, `family=²`, a 5000-digit `family`, `tag` or `course`, and `?students=1, x ,,` must be ignored, never a 500. Tests: Task 2 `test_a_huge_id_in_any_id_filter_is_ignored_not_a_500`, `test_the_payer_choices_for_the_dialog`; Task 3 `test_junk_filters_are_ignored_never_a_500`.
- **A parent who is both guardian and family payer, and a list of many families.** They must appear once in the payer choices, as the family payer; and neither the families list nor the payer rule may cost a query per family member, nor the list's closed Edit dialogs a request per row. Tests: Task 5 `test_a_guardian_who_is_the_family_payer_is_listed_once`, `test_the_payer_choices_are_flat_as_the_family_and_guardians_grow`; Task 2 `test_the_families_list_is_flat_as_families_and_students_grow`; Task 8 `FamiliesList` "lists each family's students, payer and status".

---

## File Structure

```
backend/
  etqan/identity/
    models.py                  Family; StudentProfile.family (one column: one family per student)
    migrations/0015_families.py  generated
    services.py                account_type, families_queryset (EXISTS annotations), get_family,
                               payer_needs_choosing, family_payer, family_payer_choices,
                               create_family, update_family, bulk_family, _claim, _payer_for;
                               people_queryset selects a student's family
    api/payloads.py            payer_summary, family_row, skipped_rows; account_type and family
                               on a student's profile
    api/people_filters.py      as_int (junk-safe), filter_families, ?account_type=, ?family=
    api/people_serializers.py  FamilyCreate/FamilyUpdate serializers; bulk name, payer_id, family_id
    api/people_views.py        FamilyListCreateView, FamilyDetailView, FamilyPayersView;
                               bulk family actions; CSV columns
    api/people_urls.py         families/, families/payers/, families/<id>/
    api/views.py               me/: children's family selected
    tests/test_families.py test_families_api.py test_family_people.py test_family_bulk.py  NEW
    tests/test_people_depth_lists.py   the CSV's two new columns
  etqan/billing/
    services/payers.py         payer_options (family, guardian, student), payer_choices, resolve_payer
    services/__init__.py       exports payer_options
    api/payloads.py api/views.py   payers_payload(options) with relation "family"
    tests/test_family_payer.py NEW
  etqan/tenants/management/commands/seed_dev.py   FAMILIES, seed_families (+ tests/test_seed_dev.py)
dashboard/
  src/features/people/
    schemas.ts api.ts queries.ts   Family types, familyFormSchema, bulkFamilySchema, families API
                                   and hooks, BulkResult
    FamilyDialog.tsx               NEW: Add/Edit dialog, PayerOptions
    FamiliesList.tsx               NEW: the list, FamilyActiveToggle, FamilyPayerCell
    FamilyPage.tsx                 NEW: one family
    BulkFamilyDialog.tsx           NEW: the bulk bar's Create family
    StudentsList.tsx StudentForm.tsx   account type, family chip, filters, bulk actions; read-only family
    index.ts
  src/features/billing/schemas.ts  relation "family"
  src/features/identity/components/MyProfileCard.tsx   the family on a student's and each child's card
  src/features/shell/nav.ts        People → Families
  src/routes/_authed/people.families.index.tsx, people.families.$familyId.tsx   NEW
  src/test/people-fixtures.ts      familyRow
  src/locales/{en,ar}/common.json
  e2e/families.spec.ts             NEW
meta: STATE.md, submodule pointers
```

---

### Task 1: Data and rules: the `Family` model, one family per student, the payer rule and the flag

**Files:**
- Create: `backend/etqan/identity/migrations/0015_families.py` (generated in Step 4)
- Modify: `backend/etqan/identity/models.py`, `backend/etqan/identity/services.py`
- Test: `backend/etqan/identity/tests/test_families.py` (new)

**Interfaces:**
- Consumes: Plan 3's `create_person`, `link_guardian`, `unlink_guardian`, `deactivate`, `activate`, `get_student_profile`.
- Produces:
  - `etqan.identity.models.Family` (`name` ≤ 120, `notes`, `is_active`, `payer` → User PROTECT with `related_name="families_paid_for"`, `created_at`, `updated_at`; `Meta.ordering = ("name", "id")`);
  - `StudentProfile.family` (→ Family, nullable, `SET_NULL`, `related_name="students"`);
  - in `etqan.identity.services`:
    - `FAMILY_FIELDS`, `FAMILY_NAME_MAX = 120`, `ACCOUNT_TYPES = ("individual", "family")`;
    - `account_type(profile: StudentProfile) -> str`;
    - `families_queryset() -> QuerySet[Family]` (annotated `payer_is_student`, `payer_is_parent`; payer selected; students prefetched by name);
    - `get_family(family_id: int) -> Family` (NotFoundError → 404);
    - `payer_needs_choosing(family: Family) -> bool` (for a row from `families_queryset`);
    - `family_payer(student_user_id: int) -> User | None` (one query);
    - `family_payer_choices(student_user_ids) -> list[User]`;
    - `create_family(*, name: str, student_ids, payer_id: int, notes: str = "") -> Family`;
    - `update_family(family: Family, *, fields: dict) -> Family`;
    - the private helpers `_families()`, `_payer_candidates(profile_ids)`, `_clean_family_name(value)`, `_family_students(student_ids, *, family)`, `_payer_for(payer_id, profiles)`, `_claim(family, profiles)` that Task 4 reuses.
  - Errors are `ValidationError(field=…)`: `name`, `student_ids`, `payer_id`, or the unknown field's name.

- [ ] **Step 1: Write the failing tests**

The rules of §4.1 and F-2 to F-4: a family links its students and names a payer; ids that are not this academy's students, or students of another family, are a 400 on `student_ids`, with nothing written; a payer outside F-2 is a 400 on `payer_id`; a race for one student loses with the same 400; an update replaces the whole set, and a new payer must suit it; the flag follows the payer student leaving or being deactivated, and the payer parent being deactivated or unlinked; a flagged or retired family supplies no payer; the family payer is one query; the payer choices for a set of students list the students, then their active parents.

Create `backend/etqan/identity/tests/test_families.py`:

```python
"""Plan 11 families: the rules (spec §3, §4.1, F-2 to F-4)."""

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.identity import services
from etqan.identity.models import Family
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db


def student(name):
    return services.create_person("student", full_name=name)


def parent(name, *children):
    user = services.create_person("parent", full_name=name)
    for child in children:
        services.link_guardian(user, child)
    return user


def family_of(user):
    return services.get_student_profile(user.pk).family


def types(*users):
    return [services.account_type(services.get_student_profile(u.pk)) for u in users]


def flagged(family):
    return services.payer_needs_choosing(services.get_family(family.pk))


def refused(field, call, *args, **kwargs):
    with pytest.raises(ValidationError) as exc:
        call(*args, **kwargs)
    assert exc.value.field == field, exc.value.message
    return exc.value.message


class TestCreate:
    def test_a_family_links_its_students_and_names_a_payer(self):
        yusuf, aisha, zaid = student("Yusuf"), student("Aisha"), student("Zaid")
        omar = parent("Omar", yusuf)
        family = services.create_family(
            name="  Omar family ",
            student_ids=[yusuf.pk, aisha.pk, yusuf.pk],
            payer_id=omar.pk,
            notes="Pays in cash",
        )
        read = services.get_family(family.pk)
        assert (read.name, read.notes, read.is_active, read.payer) == (
            "Omar family",
            "Pays in cash",
            True,
            omar,
        )
        assert [p.user.full_name for p in read.students.all()] == ["Aisha", "Yusuf"]
        assert types(yusuf, aisha, zaid) == ["family", "family", "individual"]
        assert not services.payer_needs_choosing(read)

    def test_any_student_of_the_family_may_pay(self):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        family = services.create_family(
            name="F", student_ids=[yusuf.pk, aisha.pk], payer_id=aisha.pk
        )
        assert not flagged(family)
        assert services.family_payer(yusuf.pk) == aisha

    def test_the_students_must_be_this_academys_and_in_no_other_family(self):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        omar = parent("Omar", yusuf)
        teacher = services.create_person(
            "teacher", full_name="Bilal", profile={"gender": "male"}
        )
        first = services.create_family(
            name="First", student_ids=[yusuf.pk], payer_id=yusuf.pk
        )
        create = services.create_family
        assert refused("student_ids", create, name="F", student_ids=[], payer_id=1)
        for ids in ([aisha.pk, teacher.pk], [aisha.pk, omar.pk], [999_999], ["x"]):
            message = refused(
                "student_ids", create, name="F", student_ids=ids, payer_id=aisha.pk
            )
            assert message == "Choose students from the list."
        message = refused(
            "student_ids",
            create,
            name="Second",
            student_ids=[aisha.pk, yusuf.pk],
            payer_id=aisha.pk,
        )
        assert message == "Yusuf is already in another family."
        assert list(Family.objects.values_list("name", flat=True)) == ["First"]
        assert (family_of(yusuf), family_of(aisha)) == (first, None)

    def test_the_payer_must_be_a_student_or_an_active_parent_of_one(self):
        yusuf, aisha, other = student("Yusuf"), student("Aisha"), student("Other")
        omar = parent("Omar", aisha)
        stranger = parent("Stranger", other)
        gone = parent("Gone", yusuf)
        services.deactivate(gone, by=None)
        teacher = services.create_person(
            "teacher", full_name="Bilal", profile={"gender": "male"}
        )
        ids = [yusuf.pk, aisha.pk]
        for payer in (stranger, gone, teacher, other, None):
            message = refused(
                "payer_id",
                services.create_family,
                name="F",
                student_ids=ids,
                payer_id=payer.pk if payer else None,
            )
            assert message == "Choose one of the family's students or their parents."
        services.deactivate(aisha, by=None)
        refused(
            "payer_id",
            services.create_family,
            name="F",
            student_ids=ids,
            payer_id=aisha.pk,
        )
        assert not Family.objects.exists()
        assert types(yusuf, aisha) == ["individual", "individual"]
        # A parent of any one of the students will do.
        family = services.create_family(name="F", student_ids=ids, payer_id=omar.pk)
        assert services.get_family(family.pk).payer == omar

    @pytest.mark.parametrize("name", ["", "   ", None, "x" * 121])
    def test_a_name_is_required_and_short(self, name):
        yusuf = student("Yusuf")
        refused(
            "name",
            services.create_family,
            name=name,
            student_ids=[yusuf.pk],
            payer_id=yusuf.pk,
        )
        assert not Family.objects.exists()

    def test_a_student_claimed_meanwhile_is_a_400_and_nothing_is_written(
        self, monkeypatch
    ):
        """Two admins race for one student: the second passes the pre-check
        before the first commits, and the claiming UPDATE refuses it."""
        yusuf, aisha = student("Yusuf"), student("Aisha")
        first = services.create_family(
            name="First", student_ids=[yusuf.pk], payer_id=yusuf.pk
        )
        profiles = [services.get_student_profile(u.pk) for u in (aisha, yusuf)]
        for profile in profiles:
            profile.family_id = None  # what the second admin read earlier
        monkeypatch.setattr(
            services, "_family_students", lambda ids, *, family: profiles
        )
        message = refused(
            "student_ids",
            services.create_family,
            name="Second",
            student_ids=[aisha.pk, yusuf.pk],
            payer_id=aisha.pk,
        )
        assert message == "A student joined another family meanwhile. Try again."
        assert list(Family.objects.all()) == [first]
        assert (family_of(yusuf), family_of(aisha)) == (first, None)


class TestUpdate:
    def test_rename_note_retire_and_restore_keep_the_links(self):
        yusuf = student("Yusuf")
        family = services.create_family(
            name="Old", student_ids=[yusuf.pk], payer_id=yusuf.pk
        )
        services.update_family(
            family, fields={"name": " New ", "notes": "Note", "is_active": False}
        )
        read = services.get_family(family.pk)
        assert (read.name, read.notes, read.is_active) == ("New", "Note", False)
        assert family_of(yusuf) == family
        assert services.family_payer(yusuf.pk) is None  # retired: no payer
        services.update_family(family, fields={"is_active": True})
        assert services.family_payer(yusuf.pk) == yusuf
        refused("name", services.update_family, family, fields={"name": " "})
        refused("id", services.update_family, family, fields={"id": 3})

    def test_student_ids_replace_the_whole_set(self):
        yusuf, aisha, zaid = student("Yusuf"), student("Aisha"), student("Zaid")
        family = services.create_family(
            name="F", student_ids=[yusuf.pk, aisha.pk], payer_id=yusuf.pk
        )
        services.update_family(
            family, fields={"student_ids": [yusuf.pk, zaid.pk], "payer_id": zaid.pk}
        )
        assert types(yusuf, aisha, zaid) == ["family", "individual", "family"]
        assert services.get_family(family.pk).payer == zaid
        empty = {"student_ids": []}
        refused("student_ids", services.update_family, family, fields=empty)

    def test_a_student_of_another_family_is_refused_and_nothing_changes(self):
        yusuf, aisha, zaid = student("Yusuf"), student("Aisha"), student("Zaid")
        mine = services.create_family(
            name="Mine", student_ids=[yusuf.pk], payer_id=yusuf.pk
        )
        theirs = services.create_family(
            name="Theirs", student_ids=[zaid.pk], payer_id=zaid.pk
        )
        message = refused(
            "student_ids",
            services.update_family,
            mine,
            fields={"name": "Renamed", "student_ids": [aisha.pk, zaid.pk]},
        )
        assert message == "Zaid is already in another family."
        assert services.get_family(mine.pk).name == "Mine"
        assert (family_of(yusuf), family_of(aisha), family_of(zaid)) == (
            mine,
            None,
            theirs,
        )

    def test_a_new_payer_must_suit_the_resulting_students(self):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        omar = parent("Omar", aisha)
        family = services.create_family(
            name="F", student_ids=[yusuf.pk, aisha.pk], payer_id=omar.pk
        )
        refused(
            "payer_id",
            services.update_family,
            family,
            fields={"student_ids": [yusuf.pk], "payer_id": omar.pk},
        )
        assert types(yusuf, aisha) == ["family", "family"]
        services.update_family(family, fields={"payer_id": aisha.pk})
        assert services.get_family(family.pk).payer == aisha


class TestPayerNeedsChoosing:
    """F-4: never repointed, flagged instead; a flagged family supplies no
    payer."""

    def test_removing_the_payer_student_flags_the_family(self):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        family = services.create_family(
            name="F", student_ids=[yusuf.pk, aisha.pk], payer_id=aisha.pk
        )
        services.update_family(family, fields={"student_ids": [yusuf.pk]})
        assert services.get_family(family.pk).payer == aisha  # not repointed
        assert flagged(family)
        assert services.family_payer(yusuf.pk) is None

    def test_deactivating_the_payer_parent_flags_until_restored(self):
        yusuf = student("Yusuf")
        omar = parent("Omar", yusuf)
        family = services.create_family(
            name="F", student_ids=[yusuf.pk], payer_id=omar.pk
        )
        services.deactivate(omar, by=None)
        assert flagged(family)
        assert services.family_payer(yusuf.pk) is None
        services.activate(omar)
        assert not flagged(family)
        assert services.family_payer(yusuf.pk) == omar

    def test_unlinking_the_payer_parent_flags_the_family(self):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        omar = parent("Omar", yusuf, aisha)
        family = services.create_family(
            name="F", student_ids=[yusuf.pk, aisha.pk], payer_id=omar.pk
        )
        services.unlink_guardian(omar, yusuf)
        assert not flagged(family)  # still Aisha's parent
        services.unlink_guardian(omar, aisha)
        assert flagged(family)

    def test_a_deactivated_payer_student_flags_the_family(self):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        family = services.create_family(
            name="F", student_ids=[yusuf.pk, aisha.pk], payer_id=aisha.pk
        )
        services.deactivate(aisha, by=None)
        assert flagged(family)
        assert services.family_payer(yusuf.pk) is None

    def test_choosing_a_new_payer_clears_the_flag(self):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        family = services.create_family(
            name="F", student_ids=[yusuf.pk, aisha.pk], payer_id=aisha.pk
        )
        services.update_family(family, fields={"student_ids": [yusuf.pk]})
        services.update_family(family, fields={"payer_id": yusuf.pk})
        assert not flagged(family)

    def test_a_student_in_no_family_has_no_family_payer(self):
        yusuf = student("Yusuf")
        assert services.family_payer(yusuf.pk) is None

    def test_the_family_payer_is_one_query_however_big_the_family(self):
        kid = student("Kid")
        family = services.create_family(name="F", student_ids=[kid.pk], payer_id=kid.pk)
        with CaptureQueriesContext(connection) as one:
            assert services.family_payer(kid.pk) == kid
        more = [student(f"More {n}") for n in range(4)]
        parent("Omar", *more)
        services.update_family(
            family, fields={"student_ids": [kid.pk, *[m.pk for m in more]]}
        )
        with CaptureQueriesContext(connection) as five:
            assert services.family_payer(more[-1].pk) == kid
        selects = [q for q in five.captured_queries if q["sql"].startswith("SELECT")]
        assert len(five) == len(one)
        assert len(selects) == 1


def test_the_payer_choices_for_a_set_of_students():
    yusuf, aisha, zaid = student("Yusuf"), student("Aisha"), student("Zaid")
    omar = parent("Omar", yusuf, aisha)
    huda = parent("Huda", aisha)
    gone = parent("Gone", yusuf)
    services.deactivate(gone, by=None)
    parent("Other", zaid)
    teacher = services.create_person(
        "teacher", full_name="Bilal", profile={"gender": "male"}
    )
    choices = services.family_payer_choices([yusuf.pk, aisha.pk, teacher.pk, omar.pk])
    # Students first, then their active parents, each by name; once each.
    assert choices == [aisha, yusuf, huda, omar]
    assert services.family_payer_choices([]) == []
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/identity/tests/test_families.py -q`

Expected: FAIL — a collection error, `cannot import name 'Family' from 'etqan.identity.models'`.

- [ ] **Step 3: Implement the model and the rules**

In `backend/etqan/identity/models.py`, replace:

```python
XP_MAX = 1_000_000
```

with:

```python
class Family(models.Model):
    """Siblings grouped under one payer (Plan 11). Never deleted: a retired
    family (``is_active=False``) keeps its students but supplies no payer.
    Whether ``payer`` still qualifies is computed when read (F-4), never
    stored: see ``services.families_queryset``."""

    name = models.CharField(max_length=120)
    notes = models.TextField(blank=True, default="")
    is_active = models.BooleanField(default=True)
    payer = models.ForeignKey(
        User, on_delete=models.PROTECT, related_name="families_paid_for"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("name", "id")

    def __str__(self):
        return f"Family<{self.name}>"


XP_MAX = 1_000_000
```

In `backend/etqan/identity/models.py`, replace:

```python
    tags = models.ManyToManyField(Tag, blank=True, related_name="students")

    def __str__(self):
        return f"StudentProfile<{self.user}>"
```

with:

```python
    tags = models.ManyToManyField(Tag, blank=True, related_name="students")
    # One column, so a student is in at most one family (F-3). The account
    # type is derived from it (``services.account_type``), never stored.
    family = models.ForeignKey(
        Family,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="students",
    )

    def __str__(self):
        return f"StudentProfile<{self.user}>"
```

In `backend/etqan/identity/services.py`, replace:

```python
from django.db.models import Count
from django.db.models import Max
from django.db.models import Q
from django.db.models import QuerySet
```

with:

```python
from django.db.models import Count
from django.db.models import Exists
from django.db.models import Max
from django.db.models import OuterRef
from django.db.models import Prefetch
from django.db.models import Q
from django.db.models import QuerySet
```

In `backend/etqan/identity/services.py`, replace:

```python
from etqan.identity.emails import render_email
from etqan.identity.models import Guardianship
```

with:

```python
from etqan.identity.emails import render_email
from etqan.identity.models import Family
from etqan.identity.models import Guardianship
```

Append to `backend/etqan/identity/services.py`:

```python
# ── Families (Plan 11) ────────────────────────────────────────────────────────

FAMILY_FIELDS = frozenset({"name", "notes", "is_active", "payer_id", "student_ids"})
FAMILY_NAME_MAX = 120
ACCOUNT_TYPES = ("individual", "family")


def account_type(profile: StudentProfile) -> str:
    """``family`` exactly when the student is in a family (F-3): derived from
    the one ``family`` column, so it can never disagree with it."""
    return "family" if profile.family_id else "individual"


def _families() -> QuerySet[Family]:
    """Families with their payer, annotated with what ``payer_needs_choosing``
    reads: is the payer one of the family's students, or a parent linked to
    one of them? Two ``EXISTS`` subqueries, so a page of families costs no
    query per row."""
    member = StudentProfile.objects.filter(
        family=OuterRef("pk"), user_id=OuterRef("payer_id")
    )
    parent = Guardianship.objects.filter(
        student__family=OuterRef("pk"), parent__user_id=OuterRef("payer_id")
    )
    return Family.objects.select_related("payer").annotate(
        payer_is_student=Exists(member), payer_is_parent=Exists(parent)
    )


def families_queryset() -> QuerySet[Family]:
    """Families by name, each with its students by name (one extra query for
    the whole page)."""
    students = StudentProfile.objects.select_related("user").order_by(
        "user__full_name", "user_id"
    )
    return (
        _families()
        .prefetch_related(Prefetch("students", queryset=students))
        .order_by("name", "id")
    )


def get_family(family_id: int) -> Family:
    try:
        return families_queryset().get(pk=family_id)
    except Family.DoesNotExist:
        raise NotFoundError("Family", family_id) from None


def payer_needs_choosing(family: Family) -> bool:
    """§3.3: the payer is valid when active and either one of the family's
    students or a parent linked to one of them. Computed on every read, never
    stored; ``family`` comes from ``families_queryset``."""
    qualifies = family.payer_is_student or family.payer_is_parent
    return not (family.payer.is_active and qualifies)


def family_payer(student_user_id: int) -> User | None:
    """The payer the student's family supplies (billing's first choice,
    §4.2): None unless the family is active and its payer valid. One query."""
    family = (
        _families().filter(is_active=True, students__user_id=student_user_id).first()
    )
    if family is None or payer_needs_choosing(family):
        return None
    return family.payer


def _payer_candidates(profile_ids) -> QuerySet[User]:
    """Everyone who may pay for a family of these students (F-2): an active
    one of them, or an active parent linked to one of them."""
    return (
        User.objects.filter(is_active=True)
        .filter(
            Q(student_profile__pk__in=profile_ids)
            | Q(parent_profile__child_links__student_id__in=profile_ids)
        )
        .distinct()
    )


def family_payer_choices(student_user_ids) -> list[User]:
    """The payer choices for a family of these students (user ids), the
    students first, then their parents, each by name. Ids that are not
    students of this academy are ignored."""
    profile_ids = StudentProfile.objects.filter(
        user_id__in=list(student_user_ids), user__role=User.Role.STUDENT
    ).values("pk")
    people = _payer_candidates(profile_ids).order_by("full_name", "id")
    return sorted(people, key=lambda person: person.role != User.Role.STUDENT)


def _clean_family_name(value: str | None) -> str:
    name = (value or "").strip()
    if not name:
        raise ValidationError("Enter a name.", field="name")
    if len(name) > FAMILY_NAME_MAX:
        raise ValidationError(
            f"Keep the name to {FAMILY_NAME_MAX} characters.", field="name"
        )
    return name


def _family_students(student_ids, *, family: Family | None) -> list[StudentProfile]:
    """The profiles ``student_ids`` (user ids) name: at least one, each a
    student of this academy, and none in a family other than ``family``
    (§4.1). Nothing is written here."""
    try:
        wanted = list(dict.fromkeys(int(pk) for pk in student_ids))
    except (TypeError, ValueError):
        raise ValidationError(
            "Choose students from the list.", field="student_ids"
        ) from None
    if not wanted:
        raise ValidationError("Choose at least one student.", field="student_ids")
    found = {
        profile.user_id: profile
        for profile in StudentProfile.objects.select_related("user").filter(
            user_id__in=wanted, user__role=User.Role.STUDENT
        )
    }
    if len(found) != len(wanted):
        raise ValidationError("Choose students from the list.", field="student_ids")
    own = family.pk if family is not None else None
    for pk in wanted:
        if found[pk].family_id not in (None, own):
            raise ValidationError(
                f"{found[pk].user.full_name} is already in another family.",
                field="student_ids",
            )
    return [found[pk] for pk in wanted]


def _payer_for(payer_id, profiles: list[StudentProfile]) -> User:
    """``payer_id``'s user when valid for these students (F-2); otherwise a
    400 on ``payer_id``."""
    payer = (
        _payer_candidates([profile.pk for profile in profiles])
        .filter(pk=payer_id or 0)
        .first()
    )
    if payer is None:
        raise ValidationError(
            "Choose one of the family's students or their parents.",
            field="payer_id",
        )
    return payer


def _claim(family: Family, profiles: list[StudentProfile]) -> None:
    """Link ``profiles`` to ``family``, but only those still in no family or
    in this one. The conditional UPDATE re-checks each row once it holds the
    row's lock, so of two admins racing for one student only one wins; the
    other gets the same 400 as the pre-check (§9)."""
    ids = [profile.pk for profile in profiles]
    claimed = (
        StudentProfile.objects.filter(pk__in=ids)
        .filter(Q(family__isnull=True) | Q(family=family))
        .update(family=family)
    )
    if claimed != len(ids):
        raise ValidationError(
            "A student joined another family meanwhile. Try again.",
            field="student_ids",
        )


@transaction.atomic
def create_family(*, name: str, student_ids, payer_id: int, notes: str = "") -> Family:
    """§4.1: everything is checked before anything is written."""
    clean_name = _clean_family_name(name)
    profiles = _family_students(student_ids, family=None)
    family = Family.objects.create(
        name=clean_name, notes=notes or "", payer=_payer_for(payer_id, profiles)
    )
    _claim(family, profiles)
    return family


@transaction.atomic
def update_family(family: Family, *, fields: dict) -> Family:
    """§4.1: name, notes, active (retire and restore), the payer, and the
    whole student set (removed students go back to individual). The payer
    must suit the resulting students when it is part of the update; when it
    is not, an update may leave it invalid, and the family is then flagged
    (F-4). Nothing is ever deleted."""
    unknown = sorted(set(fields) - FAMILY_FIELDS)
    if unknown:
        raise ValidationError("Unknown field.", field=unknown[0])
    family = Family.objects.select_for_update().get(pk=family.pk)
    if "name" in fields:
        family.name = _clean_family_name(fields["name"])
    if "notes" in fields:
        family.notes = fields["notes"] or ""
    if "is_active" in fields:
        family.is_active = bool(fields["is_active"])
    profiles = None
    if "student_ids" in fields:
        profiles = _family_students(fields["student_ids"], family=family)
    if "payer_id" in fields:
        members = profiles if profiles is not None else list(family.students.all())
        family.payer = _payer_for(fields["payer_id"], members)
    family.save()
    if profiles is not None:
        kept = [profile.pk for profile in profiles]
        StudentProfile.objects.filter(family=family).exclude(pk__in=kept).update(
            family=None
        )
        _claim(family, profiles)
    return family
```

- [ ] **Step 4: Generate the migration**

Run (from `backend/`):

```bash
.venv/bin/python manage.py makemigrations identity --name families --settings=config.settings.test
```

Expected: `etqan/identity/migrations/0015_families.py`, creating `Family` and adding the nullable `family` column to `StudentProfile`. It adds no NOT NULL column to an existing table, so the old colour keeps working during a blue/green switch. A warning about `etqan/static` is harmless.

- [ ] **Step 5: Format, then run the tests on a fresh test database**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/identity/tests/test_families.py -q --create-db
```

Expected: 21 passed.

- [ ] **Step 6: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1379 tests (21 new), coverage 98.0%.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/identity
git -C backend commit -m "feat(identity): families with one payer, one family per student

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The families admin API (`/api/v1/people/families/`) and junk-safe id filters

**Files:**
- Modify: `backend/etqan/identity/api/payloads.py`, `backend/etqan/identity/api/people_filters.py`, `backend/etqan/identity/api/people_serializers.py`, `backend/etqan/identity/api/people_views.py`, `backend/etqan/identity/api/people_urls.py`
- Test: `backend/etqan/identity/tests/test_families_api.py` (new)

**Interfaces:**
- Consumes: Task 1's `families_queryset`, `get_family`, `payer_needs_choosing`, `family_payer_choices`, `create_family`, `update_family`.
- Produces:
  - `GET/POST people/families/` (paged; `?search=`, `?active=true|false`), `GET/PATCH people/families/<id>/`, `GET people/families/payers/?students=1,2` (a plain array);
  - a family row: `{id, name, is_active, payer: {id, full_name, role}, payer_needs_choosing, students: [{id, full_name}], notes, created_at}`; student ids are user ids, like every people route;
  - `payloads.payer_summary(user) -> {id, full_name, role}`, `payloads.family_row(family) -> dict`;
  - `people_filters.as_int(value) -> int | None` (public now, replacing `_as_int`: `int()` inside `try`, negatives are junk) and `people_filters.filter_families(queryset, params)`;
  - `FamilyCreateSerializer`, `FamilyUpdateSerializer`.

- [ ] **Step 1: Write the failing tests**

Admins create, list, search, filter, read and patch families, always answered with a fresh read; errors name their field and change nothing; there is no PUT or DELETE and an unknown id is a 404; the payer choices endpoint ignores junk; every route is admin-only; another academy's families, students and parents are never reachable (with `until_pk_exceeds`); the list's query count is flat; and a 5000-digit id in the existing `tag` and `course` filters is ignored instead of a 500.

Create `backend/etqan/identity/tests/test_families_api.py`:

```python
"""Plan 11 §5: /api/v1/people/families/ — admins only, fresh reads, no PUT
or DELETE, never another academy's."""

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.identity import services
from etqan.identity.models import Family
from etqan.identity.models import User
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
F = "/api/v1/people/families/"
ROW_KEYS = {
    "id",
    "name",
    "is_active",
    "payer",
    "payer_needs_choosing",
    "students",
    "notes",
    "created_at",
}


@pytest.fixture
def admin(api_for):
    return api_for("admin")


def student(name):
    return services.create_person("student", full_name=name)


def parent(name, *children):
    user = services.create_person("parent", full_name=name)
    for child in children:
        services.link_guardian(user, child)
    return user


def family(name, *students, payer=None):
    return services.create_family(
        name=name,
        student_ids=[s.pk for s in students],
        payer_id=(payer or students[0]).pk,
    )


class TestAdmin:
    def test_create_answers_a_fresh_read(self, admin):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        omar = parent("Omar", yusuf)
        body = {
            "name": "Omar family",
            "student_ids": [yusuf.pk, aisha.pk],
            "payer_id": omar.pk,
            "notes": "Pays monthly",
        }
        resp = admin.post(F, body, format="json")
        assert resp.status_code == 201, resp.json()
        row = resp.json()
        assert set(row) == ROW_KEYS
        assert row["payer"] == {"id": omar.pk, "full_name": "Omar", "role": "parent"}
        assert row["students"] == [
            {"id": aisha.pk, "full_name": "Aisha"},
            {"id": yusuf.pk, "full_name": "Yusuf"},
        ]
        assert (row["name"], row["notes"], row["is_active"]) == (
            "Omar family",
            "Pays monthly",
            True,
        )
        assert row["payer_needs_choosing"] is False
        assert admin.get(f"{F}{row['id']}/").json() == row

    def test_the_list_pages_searches_and_filters_by_active(self, admin):
        a, b, c = student("A"), student("B"), student("C")
        family("Omar family", a)
        retired = family("Huda family", b)
        services.update_family(retired, fields={"is_active": False})
        family("Zaid house", c)

        def names(query=""):
            body = admin.get(f"{F}{query}").json()
            return body["count"], [row["name"] for row in body["results"]]

        assert names() == (3, ["Huda family", "Omar family", "Zaid house"])
        assert names("?search=FAMILY") == (2, ["Huda family", "Omar family"])
        assert names("?active=true") == (2, ["Omar family", "Zaid house"])
        assert names("?active=false&search=huda") == (1, ["Huda family"])
        assert names("?active=maybe&search=") == names()
        body = admin.get(f"{F}?page_size=1&page=2").json()
        assert [row["name"] for row in body["results"]] == ["Omar family"]

    def test_patch_answers_a_fresh_read_and_can_retire(self, admin):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        mine = family("Mine", yusuf, aisha, payer=aisha)
        resp = admin.patch(
            f"{F}{mine.pk}/",
            {"name": "Renamed", "student_ids": [yusuf.pk], "is_active": False},
            format="json",
        )
        assert resp.status_code == 200, resp.json()
        row = resp.json()
        assert (row["name"], row["is_active"], row["payer_needs_choosing"]) == (
            "Renamed",
            False,
            True,  # Aisha left, and was the payer (F-4)
        )
        assert row["students"] == [{"id": yusuf.pk, "full_name": "Yusuf"}]
        resp = admin.patch(f"{F}{mine.pk}/", {"payer_id": yusuf.pk}, format="json")
        assert resp.json()["payer_needs_choosing"] is False

    def test_errors_name_their_field_and_change_nothing(self, admin):
        yusuf, aisha, zaid = student("Yusuf"), student("Aisha"), student("Zaid")
        stranger = parent("Stranger", zaid)
        theirs = family("Theirs", zaid)
        cases = [
            ({"student_ids": [yusuf.pk, zaid.pk], "payer_id": yusuf.pk}, "student_ids"),
            ({"student_ids": [yusuf.pk], "payer_id": stranger.pk}, "payer_id"),
            ({"student_ids": [], "payer_id": yusuf.pk}, "student_ids"),
            ({"student_ids": [yusuf.pk]}, "payer_id"),
            ({"name": " ", "student_ids": [yusuf.pk], "payer_id": yusuf.pk}, "name"),
        ]
        for body, field in cases:
            resp = admin.post(F, {"name": "New", **body}, format="json")
            assert resp.status_code == 400, body
            assert list(resp.json()) == [field], resp.json()
        taken = {"name": "New", "student_ids": [yusuf.pk, zaid.pk], "payer_id": 1}
        assert admin.post(F, taken, format="json").json() == {
            "student_ids": ["Zaid is already in another family."]
        }
        widen = {"student_ids": [zaid.pk, aisha.pk], "payer_id": yusuf.pk}
        resp = admin.patch(f"{F}{theirs.pk}/", widen, format="json")
        assert list(resp.json()) == ["payer_id"]
        assert list(Family.objects.values_list("name", flat=True)) == ["Theirs"]
        assert services.get_student_profile(aisha.pk).family is None

    def test_no_put_no_delete_and_an_unknown_family_is_a_404(self, admin):
        yusuf = student("Yusuf")
        mine = family("Mine", yusuf)
        assert admin.put(f"{F}{mine.pk}/", {}, format="json").status_code == 405
        assert admin.delete(f"{F}{mine.pk}/").status_code == 405
        assert admin.get(f"{F}999999/").status_code == 404
        assert admin.patch(f"{F}999999/", {}, format="json").status_code == 404
        assert Family.objects.filter(pk=mine.pk).exists()

    def test_the_payer_choices_for_the_dialog(self, admin):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        omar = parent("Omar", yusuf)
        url = f"{F}payers/?students={aisha.pk},{yusuf.pk}"
        assert admin.get(url).json() == [
            {"id": aisha.pk, "full_name": "Aisha", "role": "student"},
            {"id": yusuf.pk, "full_name": "Yusuf", "role": "student"},
            {"id": omar.pk, "full_name": "Omar", "role": "parent"},
        ]
        junk = ["", "x", "-1", "%C2%B2", "1" * 5000, f"{yusuf.pk}, x ,,"]
        for students in junk:
            resp = admin.get(f"{F}payers/?students={students}")
            assert resp.status_code == 200, students
        assert [p["id"] for p in resp.json()] == [yusuf.pk, omar.pk]
        assert admin.get(f"{F}payers/").json() == []


@pytest.mark.parametrize("role", ["teacher", "parent", "student"])
def test_every_family_route_is_admin_only(api_for, role):
    client = api_for(role)
    yusuf = student("Yusuf")
    mine = family("Mine", yusuf)
    body = {"name": "X", "student_ids": [yusuf.pk], "payer_id": yusuf.pk}
    assert client.get(F).status_code == 403
    assert client.post(F, body, format="json").status_code == 403
    assert client.get(f"{F}{mine.pk}/").status_code == 403
    resp = client.patch(f"{F}{mine.pk}/", {"name": "Y"}, format="json")
    assert resp.status_code == 403
    assert client.get(f"{F}payers/?students={yusuf.pk}").status_code == 403
    assert APIClient().get(F).status_code == 403
    assert services.get_family(mine.pk).name == "Mine"


def test_another_academys_families_and_people_are_never_reachable(admin, tenants):
    yusuf = student("Yusuf")
    mine = family("Mine", yusuf)
    ceiling = max(
        Family.objects.aggregate(top=Max("pk"))["top"],
        User.objects.aggregate(top=Max("pk"))["top"],
    )
    with tenant_context(tenants.other):
        layla = until_pk_exceeds(User, ceiling, lambda: student("Layla"))
        salma = until_pk_exceeds(User, ceiling, lambda: parent("Salma", layla))
        theirs = until_pk_exceeds(Family, ceiling, lambda: family("Theirs", layla))
    assert min(layla.pk, salma.pk, theirs.pk) > ceiling
    assert admin.get(f"{F}{theirs.pk}/").status_code == 404
    resp = admin.patch(f"{F}{theirs.pk}/", {"name": "Mine now"}, format="json")
    assert resp.status_code == 404
    assert [row["name"] for row in admin.get(F).json()["results"]] == ["Mine"]
    body = {"name": "X", "student_ids": [yusuf.pk, layla.pk], "payer_id": yusuf.pk}
    assert list(admin.post(F, body, format="json").json()) == ["student_ids"]
    resp = admin.patch(f"{F}{mine.pk}/", {"payer_id": salma.pk}, format="json")
    assert list(resp.json()) == ["payer_id"]
    payers = admin.get(f"{F}payers/?students={yusuf.pk},{layla.pk}").json()
    assert [p["id"] for p in payers] == [yusuf.pk]
    with tenant_context(tenants.other):
        assert services.get_family(theirs.pk).name == "Theirs"


def test_the_families_list_is_flat_as_families_and_students_grow(admin):
    def count():
        with CaptureQueriesContext(connection) as queries:
            assert admin.get(F).status_code == 200
        return len(queries)

    a = student("A")
    family("F0", a, payer=parent("P0", a))
    one = count()
    for n in range(1, 4):
        kids = [student(f"K{n}{m}") for m in range(3)]
        family(f"F{n}", *kids, payer=parent(f"P{n}", *kids))
    assert count() == one


def test_a_huge_id_in_any_id_filter_is_ignored_not_a_500(admin):
    """``isdecimal()`` alone let a 5000-digit id reach ``int()``."""
    student("Aisha")
    huge = "1" * 5000
    for query in (f"tag={huge}", f"tag={huge}&tag=x"):
        resp = admin.get(f"/api/v1/people/students/?{query}")
        assert resp.status_code == 200
        assert resp.json()["count"] == 1
    resp = admin.get(f"/api/v1/people/teachers/?course={huge}")
    assert resp.status_code == 200
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.venv/bin/pytest etqan/identity/tests/test_families_api.py -q`

Expected: FAIL — 12 failed. The families routes do not exist yet (Django's HTML 404: `Content-Type header is "text/html; charset=utf-8", not "application/json"`, or a 404 where 403 was expected), and `test_a_huge_id_in_any_id_filter_is_ignored_not_a_500` raises `ValueError: Exceeds the limit (4300 digits) for integer string conversion`.

- [ ] **Step 3: Implement**

In `backend/etqan/identity/api/people_filters.py`, replace:

```python
def _as_int(value: str) -> int | None:
    """Like the old ``value.isdigit()`` guard (no ``-``, junk ignored), but
    ``isdecimal()`` instead of ``isdigit()``: ``isdigit()`` is True for
    non-decimal digits such as "²", which ``int()`` then rejects with a
    ValueError that bubbled up as a 500."""
    if not value.isdecimal():
        return None
    return int(value)
```

with:

```python
def as_int(value: str) -> int | None:
    """An id from a query parameter, or None for junk: never a 500. ``int()``
    itself decides, inside ``try``: ``isdigit()`` passes "²" and
    ``isdecimal()`` passes a 5000-digit string, and ``int()`` raises
    ValueError on both. A negative number is junk too."""
    try:
        number = int(value)
    except (TypeError, ValueError):
        return None
    return number if number >= 0 else None
```

In `backend/etqan/identity/api/people_filters.py`, replace:

```python
    ids = [n for value in params.getlist("tag") if (n := _as_int(value)) is not None]
```

with:

```python
    ids = [n for value in params.getlist("tag") if (n := as_int(value)) is not None]
```

In `backend/etqan/identity/api/people_filters.py`, replace:

```python
        if (course := _as_int(params.get("course", ""))) is not None:
```

with:

```python
        if (course := as_int(params.get("course", ""))) is not None:
```

In `backend/etqan/identity/api/people_filters.py`, replace:

```python
def filter_people(queryset, role: str, params):
```

with:

```python
def filter_families(queryset, params):
    """``?search=`` on the name, ``?active=true|false``; anything else is
    ignored."""
    if search := params.get("search", "").strip():
        queryset = queryset.filter(name__icontains=search)
    if (active := params.get("active")) in _BOOL:
        queryset = queryset.filter(is_active=_BOOL[active])
    return queryset


def filter_people(queryset, role: str, params):
```

In `backend/etqan/identity/api/payloads.py`, replace:

```python
def _iso(value):
    return value.isoformat() if value else None
```

with:

```python
def _iso(value):
    return value.isoformat() if value else None


def payer_summary(user: User) -> dict:
    """Who pays for a family, or may: a student or a parent (F-2)."""
    return {"id": user.id, "full_name": user.full_name, "role": user.role}
```

Append to `backend/etqan/identity/api/payloads.py`:

```python
def family_row(family) -> dict:
    """A families-admin row (spec §5); ``family`` comes from
    ``services.families_queryset``. Admin-only, notes included."""
    return {
        "id": family.id,
        "name": family.name,
        "is_active": family.is_active,
        "payer": payer_summary(family.payer),
        "payer_needs_choosing": services.payer_needs_choosing(family),
        "students": [
            {"id": profile.user_id, "full_name": profile.user.full_name}
            for profile in family.students.all()
        ],
        "notes": family.notes,
        "created_at": family.created_at,
    }
```

Append to `backend/etqan/identity/api/people_serializers.py`:

```python
def _student_ids(*, required: bool):
    """A family's whole student set (user ids), replacing what it had."""
    return serializers.ListField(
        child=serializers.IntegerField(min_value=1),
        allow_empty=False,
        max_length=100,
        required=required,
    )


class FamilyCreateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120)
    student_ids = _student_ids(required=True)
    payer_id = serializers.IntegerField(min_value=1)
    notes = serializers.CharField(required=False, allow_blank=True)


class FamilyUpdateSerializer(serializers.Serializer):
    """PATCH only (spec §5): there is no PUT and no DELETE."""

    name = serializers.CharField(max_length=120, required=False)
    student_ids = _student_ids(required=False)
    payer_id = serializers.IntegerField(min_value=1, required=False)
    notes = serializers.CharField(required=False, allow_blank=True)
    is_active = serializers.BooleanField(required=False)
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
from etqan.identity.api.payloads import csv_rows
```

with:

```python
from etqan.identity.api.payloads import csv_rows
from etqan.identity.api.payloads import family_row
from etqan.identity.api.payloads import payer_summary
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
from etqan.identity.api.people_filters import filter_people
```

with:

```python
from etqan.identity.api.people_filters import as_int
from etqan.identity.api.people_filters import filter_families
from etqan.identity.api.people_filters import filter_people
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
from etqan.identity.api.people_serializers import GuardianLinkSerializer
```

with:

```python
from etqan.identity.api.people_serializers import FamilyCreateSerializer
from etqan.identity.api.people_serializers import FamilyUpdateSerializer
from etqan.identity.api.people_serializers import GuardianLinkSerializer
```

Append to `backend/etqan/identity/api/people_views.py`:

```python
class FamilyListCreateView(generics.GenericAPIView):
    """The academy's families (Plan 11 §5): admins only, paged."""

    permission_classes = [IsAdmin]

    def get(self, request):
        queryset = filter_families(services.families_queryset(), request.query_params)
        page = self.paginate_queryset(queryset)
        return self.get_paginated_response([family_row(f) for f in page])

    def post(self, request):
        serializer = FamilyCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        family = services.create_family(**serializer.validated_data)
        return Response(
            family_row(services.get_family(family.pk)), status=status.HTTP_201_CREATED
        )


class FamilyDetailView(APIView):
    """GET and PATCH: there is no PUT and no DELETE (§5)."""

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        return Response(family_row(services.get_family(pk)))

    def patch(self, request, pk):
        family = services.get_family(pk)
        serializer = FamilyUpdateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        services.update_family(family, fields=dict(serializer.validated_data))
        return Response(family_row(services.get_family(pk)))


class FamilyPayersView(APIView):
    """``?students=1,2``: who may pay for a family of these students (the
    Add and Edit dialogs' payer select, recomputed as the students change).
    Junk and other academies' ids are ignored."""

    permission_classes = [IsAdmin]

    def get(self, request):
        raw = request.query_params.get("students", "")
        ids = [n for part in raw.split(",") if (n := as_int(part)) is not None]
        people = services.family_payer_choices(ids[:100])
        return Response([payer_summary(person) for person in people])
```

In `backend/etqan/identity/api/people_urls.py`, replace:

```python
    re_path(r"^tags/(?P<pk>\d+)/$", views.TagDetailView.as_view(), name="tag"),
```

with:

```python
    re_path(r"^tags/(?P<pk>\d+)/$", views.TagDetailView.as_view(), name="tag"),
    re_path(r"^families/$", views.FamilyListCreateView.as_view(), name="families"),
    re_path(
        r"^families/payers/$", views.FamilyPayersView.as_view(), name="family-payers"
    ),
    re_path(
        r"^families/(?P<pk>\d+)/$", views.FamilyDetailView.as_view(), name="family"
    ),
```

- [ ] **Step 4: Run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/identity/tests/test_families_api.py etqan/identity/tests/test_people_depth_lists.py -q
```

Expected: all pass (`test_people_depth_lists.py`'s `tag=-1` and `tag=%C2%B2` cases still list every student).

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1391 tests (12 new), coverage 98.0%.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/identity
git -C backend commit -m "feat(identity): families admin API and junk-safe id filters

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: A student's account type and family: rows, `me/`, the two filters and the CSV

**Files:**
- Modify: `backend/etqan/identity/services.py` (`people_queryset`), `backend/etqan/identity/api/payloads.py`, `backend/etqan/identity/api/people_filters.py`, `backend/etqan/identity/api/people_views.py` (CSV columns), `backend/etqan/identity/api/views.py` (`me/`)
- Test: `backend/etqan/identity/tests/test_family_people.py` (new); `backend/etqan/identity/tests/test_people_depth_lists.py` (its CSV header and last-column assertions shift by the two new columns)

**Interfaces:**
- Consumes: Task 1's `account_type`, `ACCOUNT_TYPES`, `create_family`, `update_family`; Task 2's `as_int`.
- Produces:
  - a student's `profile` (admin rows and details, `me/` and each of a parent's `children[].profile`) gains `account_type` (`individual` | `family`) and `family` (`{id, name}` or `null`); teachers and parents gain nothing;
  - the student list takes `?account_type=individual|family` and `?family=<id>`, junk ignored;
  - the student CSV ends `… XP, Tags, Account type, Family` (the family's name, blank when none).

- [ ] **Step 1: Write the failing tests**

Rows and details carry the account type and family, and follow membership; teachers and parents carry neither; both filters are exact across pages and junk-safe; the CSV gains its two columns (a family name starting with `=` is defused like any cell); a student sees their own family and a parent each child's through `me/`, and family notes never appear there; the student list, its CSV and a parent's `me/` keep a flat query count as students in families grow.

Create `backend/etqan/identity/tests/test_family_people.py`:

```python
"""Plan 11 §4.3 and §4.4 on people: the account type and family on rows and in
`me/`, the two list filters, the CSV columns, and flat query counts."""

import csv
import io

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from etqan.identity import services

pytestmark = pytest.mark.django_db
B = "/api/v1/people/"
ME = "/api/v1/identity/me/"


@pytest.fixture
def admin(api_for):
    return api_for("admin")


def student(name, email=None):
    return services.create_person("student", full_name=name, email=email, invite=False)


def parent(name, *children):
    user = services.create_person("parent", full_name=name)
    for child in children:
        services.link_guardian(user, child)
    return user


def family(name, *students, notes=""):
    return services.create_family(
        name=name,
        student_ids=[s.pk for s in students],
        payer_id=students[0].pk,
        notes=notes,
    )


def names(client, query):
    body = client.get(f"{B}students/?{query}").json()
    return body["count"], [row["user"]["full_name"] for row in body["results"]]


def signed_in(user):
    client = APIClient()
    client.force_login(user)
    return client


def test_rows_and_details_carry_the_account_type_and_the_family(admin):
    yusuf, zaid = student("Yusuf"), student("Zaid")
    mine = family("Omar family", yusuf)
    rows = {
        row["user"]["full_name"]: row["profile"]
        for row in admin.get(f"{B}students/").json()["results"]
    }
    assert (rows["Yusuf"]["account_type"], rows["Yusuf"]["family"]) == (
        "family",
        {"id": mine.pk, "name": "Omar family"},
    )
    assert (rows["Zaid"]["account_type"], rows["Zaid"]["family"]) == (
        "individual",
        None,
    )
    detail = admin.get(f"{B}students/{yusuf.pk}/").json()["profile"]
    assert detail["family"] == {"id": mine.pk, "name": "Omar family"}
    services.update_family(mine, fields={"student_ids": [zaid.pk]})
    detail = admin.get(f"{B}students/{yusuf.pk}/").json()["profile"]
    assert (detail["account_type"], detail["family"]) == ("individual", None)


def test_a_teacher_or_parent_row_has_no_family():
    teacher = services.create_person(
        "teacher", full_name="Bilal", profile={"gender": "male"}
    )
    for user in (teacher, parent("Omar")):
        profile = signed_in(user).get(ME).json()["profile"]
        assert "family" not in profile
        assert "account_type" not in profile


class TestFilters:
    def test_account_type_and_family(self, admin):
        a, b, c = student("A"), student("B"), student("C")
        student("D")
        first = family("First", a, b)
        second = family("Second", c)
        assert names(admin, "account_type=family") == (3, ["A", "B", "C"])
        assert names(admin, "account_type=individual") == (1, ["D"])
        assert names(admin, f"family={first.pk}") == (2, ["A", "B"])
        assert names(admin, f"family={second.pk}&account_type=family") == (1, ["C"])
        assert names(admin, "family=999999") == (0, [])

    def test_junk_filters_are_ignored_never_a_500(self, admin):
        student("A")
        for query in (
            "account_type=",
            "account_type=household",
            "family=",
            "family=x",
            "family=-1",
            "family=%C2%B2",
            f"family={'1' * 5000}",
        ):
            assert names(admin, query) == (1, ["A"]), query

    def test_the_family_filter_is_exact_across_pages(self, admin):
        kids = [student(f"Kid {n}") for n in range(5)]
        mine = family("Mine", *kids)
        for n in range(3):
            student(f"Other {n}")
        pages = [
            admin.get(f"{B}students/?family={mine.pk}&page_size=2&page={p}").json()
            for p in (1, 2, 3)
        ]
        assert [page["count"] for page in pages] == [5, 5, 5]
        seen = [row["user"]["full_name"] for page in pages for row in page["results"]]
        assert seen == [f"Kid {n}" for n in range(5)]


def test_the_csv_gains_account_type_and_family(admin):
    yusuf = student("Yusuf")
    student("Zaid")
    family("=Omar family", yusuf)
    resp = admin.get(f"{B}students/?format=csv")
    header, *rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
    assert header[-2:] == ["Account type", "Family"]
    by_name = {row[1]: row[-2:] for row in rows}
    assert by_name == {
        "Yusuf": ["family", "'=Omar family"],  # defused like any cell
        "Zaid": ["individual", ""],
    }


class TestMe:
    def test_a_student_sees_their_family_name_and_a_parent_each_childs(self):
        yusuf = student("Yusuf", email="yusuf@x.test")
        aisha, zaid = student("Aisha"), student("Zaid")
        omar = parent("Omar", yusuf, zaid)
        mine = family("Omar family", yusuf, aisha, notes="Staff-only note")
        own = signed_in(yusuf).get(ME).json()["profile"]
        assert (own["account_type"], own["family"]) == (
            "family",
            {"id": mine.pk, "name": "Omar family"},
        )
        children = signed_in(omar).get(ME).json()["children"]
        assert [(c["full_name"], c["profile"]["family"]) for c in children] == [
            ("Yusuf", {"id": mine.pk, "name": "Omar family"}),
            ("Zaid", None),
        ]
        for client in (signed_in(yusuf), signed_in(omar)):
            assert "Staff-only note" not in client.get(ME).content.decode()

    def test_a_parents_me_is_flat_as_children_in_families_grow(self):
        omar = parent("Omar")
        first = student("A")
        services.link_guardian(omar, first)
        family("F0", first)
        client = signed_in(omar)
        with CaptureQueriesContext(connection) as one:
            assert client.get(ME).status_code == 200
        for n in range(1, 4):
            kid = student(f"K{n}")
            services.link_guardian(omar, kid)
            family(f"F{n}", kid)
        with CaptureQueriesContext(connection) as four:
            children = client.get(ME).json()["children"]
        assert len(four) == len(one)
        assert [c["profile"]["family"]["name"] for c in children] == [
            "F0",
            "F1",
            "F2",
            "F3",
        ]


def test_the_student_list_is_flat_as_students_in_families_grow(admin):
    def count(url):
        with CaptureQueriesContext(connection) as queries:
            assert admin.get(url).status_code == 200
        return len(queries)

    family("F0", student("A"))
    one = count(f"{B}students/")
    csv_one = count(f"{B}students/?format=csv")
    for n in range(1, 4):
        last = family(f"F{n}", student(f"K{n}"), student(f"L{n}"))
    assert count(f"{B}students/") == one
    assert count(f"{B}students/?format=csv") == csv_one
    assert count(f"{B}students/?account_type=family&family={last.pk}") == one
```

In `backend/etqan/identity/tests/test_people_depth_lists.py`, replace:

```python
            "XP",
            "Tags",
        ]
        assert row[-4:] == ["child", "arab", "120", "🎓 جديد; ⭐ نجم الشهر"]
        academy_services.update_settings(default_language="en")
        _, row = read_csv(admin.get(f"{B}students/?format=csv"))
        assert row[-1] == "🎓 New; ⭐ Star of the month"
```

with:

```python
            "XP",
            "Tags",
            "Account type",
            "Family",
        ]
        assert row[-6:] == [
            "child",
            "arab",
            "120",
            "🎓 جديد; ⭐ نجم الشهر",
            "individual",
            "",
        ]
        academy_services.update_settings(default_language="en")
        _, row = read_csv(admin.get(f"{B}students/?format=csv"))
        assert row[-3] == "🎓 New; ⭐ Star of the month"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.venv/bin/pytest etqan/identity/tests/test_family_people.py etqan/identity/tests/test_people_depth_lists.py -q`

Expected: FAIL — 7 failed: `KeyError: 'account_type'` on the rows and `me/`, the filters list every student, and both CSV tests miss `Account type` and `Family`. Three pass already and guard what the code must keep: no family on teachers and parents, junk filters ignored, and the flat student list (it turns red if Step 3's `select_related` is left out).

- [ ] **Step 3: Implement**

In `backend/etqan/identity/services.py`, replace:

```python
    if role in Tag.Kind.values:
        # One query for every row's tags, in list order (Tag.Meta.ordering).
        qs = qs.prefetch_related(f"{relation}__tags")
```

with:

```python
    if role in Tag.Kind.values:
        # One query for every row's tags, in list order (Tag.Meta.ordering).
        qs = qs.prefetch_related(f"{relation}__tags")
    if role == "student":
        qs = qs.select_related("student_profile__family")  # Plan 11
```

In `backend/etqan/identity/api/payloads.py`, replace:

```python
        "tags": [tag_chip(tag) for tag in p.tags.all()],
    }


def _teacher_profile
```

with:

```python
        "tags": [tag_chip(tag) for tag in p.tags.all()],
        "account_type": services.account_type(p),
        "family": {"id": p.family.id, "name": p.family.name} if p.family else None,
    }


def _teacher_profile
```

In `backend/etqan/identity/api/views.py`, replace:

```python
            for child in services.get_children(user.id)
            .select_related("user")
            .prefetch_related("tags")
```

with:

```python
            for child in services.get_children(user.id)
            .select_related("user", "family")
            .prefetch_related("tags")
```

In `backend/etqan/identity/api/people_filters.py`, replace:

```python
from etqan.identity.models import TeacherProfile
```

with:

```python
from etqan.identity.models import TeacherProfile
from etqan.identity.services import ACCOUNT_TYPES
```

In `backend/etqan/identity/api/people_filters.py`, replace:

```python
    if (nationality := params.get("nationality")) in StudentProfile.Nationality.values:
```

with:

```python
    if (kind := params.get("account_type")) in ACCOUNT_TYPES:
        # Derived, like the payload's (F-3): "family" is a family set.
        queryset = queryset.filter(student_profile__family__isnull=kind == "individual")
    if (family := as_int(params.get("family", ""))) is not None:
        queryset = queryset.filter(student_profile__family_id=family)
    if (nationality := params.get("nationality")) in StudentProfile.Nationality.values:
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
        ("profile.xp", "XP"),
        ("tags", "Tags"),
    ),
```

with:

```python
        ("profile.xp", "XP"),
        ("tags", "Tags"),
        ("profile.account_type", "Account type"),
        ("profile.family.name", "Family"),
    ),
```

- [ ] **Step 4: Run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/identity/tests/test_family_people.py etqan/identity/tests/test_people_depth_lists.py -q
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1400 tests (9 new), coverage 98.0%.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/identity
git -C backend commit -m "feat(identity): account type and family on students, filters and CSV

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The students bulk action: create a family, add to one, remove from one

**Files:**
- Modify: `backend/etqan/identity/services.py`, `backend/etqan/identity/api/payloads.py`, `backend/etqan/identity/api/people_serializers.py`, `backend/etqan/identity/api/people_views.py` (`StudentBulkView`)
- Test: `backend/etqan/identity/tests/test_family_bulk.py` (new)

**Interfaces:**
- Consumes: Task 1's `_clean_family_name`, `_payer_for`, `_claim`, `create_family`, `payer_needs_choosing`, `get_family`.
- Produces:
  - `services.FAMILY_ACTIONS = ("create_family", "add_to_family", "remove_from_family")`, `services.IN_ANOTHER_FAMILY = "in_another_family"`;
  - `services.bulk_family(user_ids, action, *, name=None, payer_id=None, family_id=None) -> tuple[int, list[User]]` (updated, skipped);
  - `POST people/students/bulk/` takes `{"ids", "action": "create_family", "name", "payer_id"}`, `{"ids", "action": "add_to_family", "family_id"}` or `{"ids", "action": "remove_from_family"}`, and answers `{"updated": n, "skipped": [{"id", "full_name", "reason": "in_another_family"}]}`. The Plan 3 and Plan 10 actions still answer `{"updated": n}`;
  - `payloads.skipped_rows(users) -> list[dict]`.

- [ ] **Step 1: Write the failing tests**

`create_family` links the selected students and reports who was already in another family, never moving them; the payer must suit the students actually linked; a selection already all in families is a 400 on `ids`; a name and a payer are required. `add_to_family` counts students already in that family, skips other families' students, and refuses another academy's family (with `until_pk_exceeds`). `remove_from_family` sends students back to individual and may flag a family whose payer left. Non-students and other academies' ids are ignored, the older actions answer as before, and the family actions are admin-only.

Create `backend/etqan/identity/tests/test_family_bulk.py`:

```python
"""Plan 11 §4.3: the students bulk action's create_family, add_to_family and
remove_from_family. A student in another family is reported and skipped,
never moved."""

import pytest
from django.db.models import Max
from django_tenants.utils import tenant_context

from etqan.identity import services
from etqan.identity.models import Family
from etqan.identity.models import User
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
BULK = "/api/v1/people/students/bulk/"


@pytest.fixture
def admin(api_for):
    return api_for("admin")


def student(name):
    return services.create_person("student", full_name=name)


def parent(name, *children):
    user = services.create_person("parent", full_name=name)
    for child in children:
        services.link_guardian(user, child)
    return user


def family(name, *students):
    return services.create_family(
        name=name, student_ids=[s.pk for s in students], payer_id=students[0].pk
    )


def family_of(user):
    return services.get_student_profile(user.pk).family


def bulk(client, users, action, **body):
    return client.post(
        BULK, {"ids": [u.pk for u in users], "action": action, **body}, format="json"
    )


class TestCreateFamily:
    def test_creates_from_the_selection_and_reports_who_was_skipped(self, admin):
        yusuf, aisha, zaid = student("Yusuf"), student("Aisha"), student("Zaid")
        omar = parent("Omar", aisha)
        theirs = family("Theirs", zaid)
        resp = bulk(
            admin,
            [yusuf, aisha, zaid],
            "create_family",
            name="Omar family",
            payer_id=omar.pk,
        )
        assert resp.status_code == 200, resp.json()
        assert resp.json() == {
            "updated": 2,
            "skipped": [
                {"id": zaid.pk, "full_name": "Zaid", "reason": "in_another_family"}
            ],
        }
        mine = family_of(yusuf)
        assert (mine.name, mine.payer, family_of(aisha)) == ("Omar family", omar, mine)
        assert family_of(zaid) == theirs  # never moved
        assert services.account_type(services.get_student_profile(aisha.pk)) == (
            "family"
        )

    def test_the_payer_must_suit_the_students_actually_linked(self, admin):
        yusuf, zaid = student("Yusuf"), student("Zaid")
        huda = parent("Huda", zaid)  # only the skipped student's parent
        family("Theirs", zaid)
        resp = bulk(admin, [yusuf, zaid], "create_family", name="F", payer_id=huda.pk)
        assert (resp.status_code, list(resp.json())) == (400, ["payer_id"])
        assert family_of(yusuf) is None
        assert Family.objects.count() == 1

    def test_everyone_already_in_a_family_is_a_400(self, admin):
        zaid = student("Zaid")
        family("Theirs", zaid)
        resp = bulk(admin, [zaid], "create_family", name="F", payer_id=zaid.pk)
        assert resp.status_code == 400
        message = "Every selected student is already in a family."
        assert resp.json() == {"ids": [message]}
        assert Family.objects.count() == 1

    @pytest.mark.parametrize(
        ("body", "field"),
        [
            ({"payer_id": 1}, "name"),
            ({"name": "F"}, "payer_id"),
            ({"name": "   ", "payer_id": 1}, "name"),
            ({"name": "x" * 121, "payer_id": 1}, "name"),
        ],
    )
    def test_a_name_and_a_payer_are_required(self, admin, body, field):
        yusuf = student("Yusuf")
        if "payer_id" in body:
            body = {**body, "payer_id": yusuf.pk}
        resp = bulk(admin, [yusuf], "create_family", **body)
        assert (resp.status_code, list(resp.json())) == (400, [field])
        assert not Family.objects.exists()


class TestAddAndRemove:
    def test_add_links_the_selection_and_skips_other_families(self, admin):
        yusuf, aisha, zaid = student("Yusuf"), student("Aisha"), student("Zaid")
        huda = student("Huda")
        mine = family("Mine", yusuf)
        theirs = family("Theirs", zaid)
        resp = bulk(admin, [yusuf, aisha, zaid], "add_to_family", family_id=mine.pk)
        assert resp.json() == {
            "updated": 2,  # Yusuf was already in it: counted, unchanged
            "skipped": [
                {"id": zaid.pk, "full_name": "Zaid", "reason": "in_another_family"}
            ],
        }
        assert (family_of(aisha), family_of(zaid), family_of(huda)) == (
            mine,
            theirs,
            None,
        )

    def test_add_needs_a_family_of_this_academy(self, admin, tenants):
        yusuf = student("Yusuf")
        ceiling = Family.objects.aggregate(top=Max("pk"))["top"] or 0
        with tenant_context(tenants.other):
            theirs = until_pk_exceeds(
                Family, ceiling, lambda: family("Theirs", student("Layla"))
            )
        family("Mine", student("Aisha"))
        for body in ({}, {"family_id": theirs.pk}, {"family_id": 999_999}):
            resp = bulk(admin, [yusuf], "add_to_family", **body)
            assert (resp.status_code, list(resp.json())) == (400, ["family_id"])
        assert family_of(yusuf) is None

    def test_remove_sends_students_back_to_individual_and_flags_a_lost_payer(
        self, admin
    ):
        yusuf, aisha = student("Yusuf"), student("Aisha")
        mine = family("Mine", aisha, yusuf)  # Aisha pays
        resp = bulk(admin, [aisha], "remove_from_family")
        assert resp.json() == {"updated": 1, "skipped": []}
        assert (family_of(aisha), family_of(yusuf)) == (None, mine)
        assert services.payer_needs_choosing(services.get_family(mine.pk))
        resp = bulk(admin, [aisha, yusuf], "remove_from_family")
        assert resp.json() == {"updated": 2, "skipped": []}
        assert services.get_family(mine.pk).students.count() == 0

    def test_non_students_and_other_academies_people_are_ignored(self, admin, tenants):
        yusuf = student("Yusuf")
        omar = parent("Omar", yusuf)
        ceiling = User.objects.aggregate(top=Max("pk"))["top"]
        with tenant_context(tenants.other):
            layla = until_pk_exceeds(User, ceiling, lambda: student("Layla"))
        assert layla.pk > ceiling
        resp = admin.post(
            BULK,
            {
                "ids": [yusuf.pk, omar.pk, layla.pk],
                "action": "create_family",
                "name": "F",
                "payer_id": omar.pk,
            },
            format="json",
        )
        assert resp.json() == {"updated": 1, "skipped": []}
        with tenant_context(tenants.other):
            assert family_of(layla) is None


def test_the_other_bulk_actions_answer_as_before(admin):
    yusuf = student("Yusuf")
    resp = bulk(admin, [yusuf], "set_status", status="paused")
    assert resp.json() == {"updated": 1}


@pytest.mark.parametrize("role", ["teacher", "parent", "student"])
def test_the_family_actions_are_admin_only(api_for, role):
    yusuf = student("Yusuf")
    resp = bulk(api_for(role), [yusuf], "create_family", name="F", payer_id=yusuf.pk)
    assert resp.status_code == 403
    assert not Family.objects.exists()
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.venv/bin/pytest etqan/identity/tests/test_family_bulk.py -q`

Expected: FAIL — the family actions are a 400 `{"action": ['"create_family" is not a valid choice.']}` (and the same for the other two). The older-actions and admin-only tests pass already.

- [ ] **Step 3: Implement**

Append to `backend/etqan/identity/services.py`:

```python
FAMILY_ACTIONS = ("create_family", "add_to_family", "remove_from_family")
IN_ANOTHER_FAMILY = "in_another_family"


@transaction.atomic
def bulk_family(
    user_ids: list[int],
    action: str,
    *,
    name: str | None = None,
    payer_id: int | None = None,
    family_id: int | None = None,
) -> tuple[int, list[User]]:
    """The students bulk action's family actions (§4.3), on the students among
    ``user_ids``: ``create_family`` from them, ``add_to_family`` or
    ``remove_from_family``. A student already in another family is skipped
    and returned, never moved. Returns ``(updated, skipped)``."""
    if action not in FAMILY_ACTIONS:
        raise ValidationError("Unknown action.", field="action")
    profiles = list(
        StudentProfile.objects.select_related("user")
        .filter(user_id__in=user_ids, user__role=User.Role.STUDENT)
        .order_by("user__full_name", "user_id")
    )
    if action == "remove_from_family":
        StudentProfile.objects.filter(pk__in=[p.pk for p in profiles]).update(
            family=None
        )
        return len(profiles), []
    family = None
    if action == "add_to_family":
        family = Family.objects.filter(pk=family_id or 0).first()
        if family is None:
            raise ValidationError("Choose a family from the list.", field="family_id")
    own = family.pk if family is not None else None
    kept = [p for p in profiles if p.family_id in (None, own)]
    skipped = [p.user for p in profiles if p.family_id not in (None, own)]
    if action == "create_family":
        clean_name = _clean_family_name(name)
        if not kept:
            raise ValidationError(
                "Every selected student is already in a family.", field="ids"
            )
        family = Family.objects.create(
            name=clean_name, payer=_payer_for(payer_id, kept)
        )
    _claim(family, kept)
    return len(kept), skipped
```

Append to `backend/etqan/identity/api/payloads.py`:

```python
def skipped_rows(users) -> list[dict]:
    """The students a bulk family action left alone (§4.3): each was already
    in another family, and is reported, never moved."""
    reason = services.IN_ANOTHER_FAMILY
    return [
        {"id": user.id, "full_name": user.full_name, "reason": reason} for user in users
    ]
```

In `backend/etqan/identity/api/people_serializers.py`, replace:

```python
from etqan.identity.services import BULK_ACTIONS
```

with:

```python
from etqan.identity.services import BULK_ACTIONS
from etqan.identity.services import FAMILY_ACTIONS
```

In `backend/etqan/identity/api/people_serializers.py`, replace:

```python
    action = serializers.ChoiceField(choices=BULK_ACTIONS)
    status = serializers.ChoiceField(
        choices=StudentProfile.Status.choices, required=False
    )
    tag_id = serializers.IntegerField(min_value=1, required=False)

    def validate(self, attrs):
        if attrs["action"] == "set_status" and not attrs.get("status"):
            raise serializers.ValidationError({"status": ["Choose a status."]})
        if attrs["action"] in TAG_ACTIONS and not attrs.get("tag_id"):
            raise serializers.ValidationError({"tag_id": ["Choose a tag."]})
        return attrs
```

with:

```python
    action = serializers.ChoiceField(choices=(*BULK_ACTIONS, *FAMILY_ACTIONS))
    status = serializers.ChoiceField(
        choices=StudentProfile.Status.choices, required=False
    )
    tag_id = serializers.IntegerField(min_value=1, required=False)
    # Plan 11: create_family takes a name and a payer, add_to_family a family.
    name = serializers.CharField(max_length=120, required=False)
    payer_id = serializers.IntegerField(min_value=1, required=False)
    family_id = serializers.IntegerField(min_value=1, required=False)

    def validate(self, attrs):
        action = attrs["action"]
        if action == "set_status" and not attrs.get("status"):
            raise serializers.ValidationError({"status": ["Choose a status."]})
        if action in TAG_ACTIONS and not attrs.get("tag_id"):
            raise serializers.ValidationError({"tag_id": ["Choose a tag."]})
        if action == "create_family" and not attrs.get("name"):
            raise serializers.ValidationError({"name": ["Enter a name."]})
        if action == "create_family" and not attrs.get("payer_id"):
            raise serializers.ValidationError({"payer_id": ["Choose a payer."]})
        if action == "add_to_family" and not attrs.get("family_id"):
            raise serializers.ValidationError({"family_id": ["Choose a family."]})
        return attrs
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
from etqan.identity.api.payloads import person_summary
```

with:

```python
from etqan.identity.api.payloads import person_summary
from etqan.identity.api.payloads import skipped_rows
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
            .values_list("pk", flat=True)
        )
        updated = services.bulk_update_students(
```

with:

```python
            .values_list("pk", flat=True)
        )
        if data["action"] in services.FAMILY_ACTIONS:
            updated, skipped = services.bulk_family(
                ids,
                data["action"],
                name=data.get("name"),
                payer_id=data.get("payer_id"),
                family_id=data.get("family_id"),
            )
            return Response({"updated": updated, "skipped": skipped_rows(skipped)})
        updated = services.bulk_update_students(
```

- [ ] **Step 4: Run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/identity/tests/test_family_bulk.py etqan/identity/tests/test_people_actions_api.py etqan/identity/tests/test_profile_depth.py -q
```

Expected: all pass.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1415 tests (15 new), coverage 98.0%.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/identity
git -C backend commit -m "feat(identity): create, add to and remove from a family in bulk

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Billing: the family payer first in the one payer rule

**Files:**
- Modify: `backend/etqan/billing/services/payers.py` (rewritten whole below), `backend/etqan/billing/services/__init__.py`, `backend/etqan/billing/api/payloads.py`, `backend/etqan/billing/api/views.py` (`PayersView`)
- Test: `backend/etqan/billing/tests/test_family_payer.py` (new). The existing payer tests (`test_rules.py`'s three payer tests, `test_api.py::test_summary_and_payers`, `test_subscriptions.py::test_an_automatic_invoice_skips_an_inactive_guardian`) are left as they are: without a family their answers do not change, and they must stay green.

**Interfaces:**
- Consumes: Task 1's `identity_services.family_payer(student_user_id) -> User | None`, `create_family`, `update_family`; Plan 6's `guardians_by_link`, `get_user`.
- Produces:
  - `billing.services.payer_options(student_user_id) -> list[tuple[User, str]]`: `(person, relation)` with relation `family` | `guardian` | `student`, the default first, deduplicated (first relation wins);
  - `payer_choices(student_user_id) -> list[User]` (the people of `payer_options`, same order), `resolve_payer` unchanged in shape;
  - `GET billing/payers/?student=` answers `{"default", "choices": [{id, full_name, relation}]}` with `relation: "family"` for the family payer; `payloads.payers_payload(options)`.

- [ ] **Step 1: Write the failing tests**

The family payer comes first, then the guardians, then the student, once each; a new manual invoice defaults to the family payer, while an explicit valid payer still wins; a subscription's automatic invoice uses it; existing invoices keep their payer; a retired or flagged family supplies none; the payers route labels it `family`; and `payer_choices` keeps a flat query count as the family and its guardians grow.

Create `backend/etqan/billing/tests/test_family_payer.py`:

```python
"""Plan 11 §4.2: the family payer comes first in the one payer rule, for
manual invoices, automatic ones and the invoice form's choices. Existing
invoices never change (F-5)."""

from datetime import date

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from etqan.billing import services
from etqan.billing.tests.conftest import make_parent
from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import make_student

JUNE_8 = date(2026, 6, 8)


def invoice_for(student, admin, **overrides):
    fields = {
        "student_id": student.id,
        "amount_minor": 1000,
        "due_on": JUNE_8,
        "description": "Tajweed — June",
        "by": admin,
        **overrides,
    }
    return services.create_invoice(**fields)


def family(*students, payer):
    return identity_services.create_family(
        name="Family", student_ids=[s.pk for s in students], payer_id=payer.pk
    )


def options(student):
    return [(p.full_name, r) for p, r in services.payer_options(student.pk)]


def test_the_family_payer_comes_first_then_guardians_then_the_student(world):
    yusuf = world.student
    aisha = make_student("Aisha")
    zainab = make_parent("Zainab", yusuf)
    family(yusuf, aisha, payer=aisha)
    assert options(yusuf) == [
        ("Aisha", "family"),
        ("Zainab", "guardian"),
        ("Yusuf", "student"),
    ]
    assert services.payer_choices(yusuf.pk) == [aisha, zainab, yusuf]
    assert options(aisha) == [("Aisha", "family")]  # the payer herself, once


def test_a_guardian_who_is_the_family_payer_is_listed_once(world):
    yusuf = world.student
    aisha = make_student("Aisha")
    omar = make_parent("Omar", aisha)
    huda = make_parent("Huda", yusuf)
    identity_services.link_guardian(omar, yusuf)  # linked after Huda
    family(yusuf, aisha, payer=omar)
    assert options(yusuf) == [
        ("Omar", "family"),
        ("Huda", "guardian"),
        ("Yusuf", "student"),
    ]
    assert services.payer_choices(yusuf.pk) == [omar, huda, yusuf]


def test_a_new_manual_invoice_defaults_to_the_family_payer(world, admin):
    yusuf = world.student
    aisha = make_student("Aisha")
    father = make_parent("Omar", yusuf)
    family(yusuf, aisha, payer=aisha)
    assert invoice_for(yusuf, admin).payer == aisha
    # An explicitly chosen valid payer still wins.
    assert invoice_for(yusuf, admin, payer_id=father.pk).payer == father
    assert invoice_for(yusuf, admin, payer_id=yusuf.pk).payer == yusuf
    stranger = make_parent("Stranger", make_student("Other"))
    with pytest.raises(ValidationError) as exc:
        invoice_for(yusuf, admin, payer_id=stranger.pk)
    assert exc.value.field == "payer"


def test_a_subscriptions_automatic_invoice_uses_the_family_payer(
    subscribe, world, admin
):
    aisha = make_student("Aisha")
    make_parent("Omar", world.student)
    family(world.student, aisha, payer=aisha)
    invoice = services.invoice_subscription(subscribe().pk, by=admin)
    assert invoice.payer == aisha


def test_existing_invoices_never_change(world, admin):
    yusuf = world.student
    father = make_parent("Omar", yusuf)
    before = invoice_for(yusuf, admin)
    aisha = make_student("Aisha")
    family(yusuf, aisha, payer=aisha)
    after = invoice_for(yusuf, admin)
    rows = {row.pk: row.payer for row in services.invoices_queryset()}
    assert rows == {before.pk: father, after.pk: aisha}


def test_a_retired_or_flagged_family_supplies_no_payer(world, admin):
    yusuf = world.student
    aisha = make_student("Aisha")
    father = make_parent("Omar", yusuf)
    mine = family(yusuf, aisha, payer=aisha)
    identity_services.update_family(mine, fields={"is_active": False})
    assert invoice_for(yusuf, admin).payer == father
    identity_services.update_family(mine, fields={"is_active": True})
    assert invoice_for(yusuf, admin).payer == aisha
    identity_services.deactivate(aisha, by=admin)  # the payer: flagged (F-4)
    assert invoice_for(yusuf, admin).payer == father
    assert "family" not in [r for _, r in services.payer_options(yusuf.pk)]


def test_the_payers_route_labels_the_family_payer(api_for, world):
    yusuf = world.student
    aisha = make_student("Aisha")
    omar = make_parent("Omar", yusuf)
    family(yusuf, aisha, payer=aisha)
    resp = api_for("admin").get(f"/api/v1/billing/payers/?student={yusuf.pk}")
    assert resp.json() == {
        "default": aisha.pk,
        "choices": [
            {"id": aisha.pk, "full_name": "Aisha", "relation": "family"},
            {"id": omar.pk, "full_name": "Omar", "relation": "guardian"},
            {"id": yusuf.pk, "full_name": "Yusuf", "relation": "student"},
        ],
    }
    anonymous = APIClient().get(f"/api/v1/billing/payers/?student={yusuf.pk}")
    assert anonymous.status_code == 403


def test_the_payer_choices_are_flat_as_the_family_and_guardians_grow(world):
    yusuf = world.student
    aisha = make_student("Aisha")
    mine = family(yusuf, aisha, payer=make_parent("Omar", yusuf))
    with CaptureQueriesContext(connection) as small:
        services.payer_choices(yusuf.pk)
    kids = [make_student(f"Kid {n}") for n in range(4)]
    for n in range(3):
        make_parent(f"Parent {n}", yusuf, *kids)
    identity_services.update_family(
        mine, fields={"student_ids": [yusuf.pk, aisha.pk, *[k.pk for k in kids]]}
    )
    with CaptureQueriesContext(connection) as big:
        assert len(services.payer_choices(yusuf.pk)) == 5
    assert len(big) == len(small)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.venv/bin/pytest etqan/billing/tests/test_family_payer.py -q`

Expected: FAIL — `AttributeError: module 'etqan.billing.services' has no attribute 'payer_options'`, and the invoices default to the guardian, not the family payer. `test_existing_invoices_never_change` fails too (its second invoice still goes to the father). 7 failed; the query-count test passes already and keeps the new lookup from adding a query per family member.

- [ ] **Step 3: Implement**

Create `backend/etqan/billing/services/payers.py` (it replaces the existing file whole):

```python
"""Who pays an invoice (P6-4, extended by Plan 11 §4.2).

Inactive guardians are skipped entirely (controller ruling): they never
appear in `payer_choices` and never become the default payer. If a student
has only inactive guardians, the student is the default payer. A family
supplies its payer only while it is active and its payer valid (F-4);
identity decides that, billing only asks.
"""

from etqan.identity import services as identity_services
from etqan.platform.exceptions import ValidationError

FAMILY = "family"
GUARDIAN = "guardian"
STUDENT = "student"


def payer_options(student_user_id: int) -> list[tuple]:
    """``(person, relation)`` for each person who may pay a student's
    invoices, the default first: the family payer, then the active guardians
    (the earliest-linked first), then the student. Someone who qualifies
    twice appears once, under their first relation. Three queries whatever
    the family's size."""
    family_payer = identity_services.family_payer(student_user_id)
    candidates = [
        *([(family_payer, FAMILY)] if family_payer else []),
        *[
            (guardian, GUARDIAN)
            for guardian in identity_services.guardians_by_link(student_user_id)
        ],
        (identity_services.get_user(student_user_id), STUDENT),
    ]
    seen: set[int] = set()
    options = []
    for person, relation in candidates:
        if person.pk not in seen:
            seen.add(person.pk)
            options.append((person, relation))
    return options


def payer_choices(student_user_id: int) -> list:
    """The one payer rule: the default payer is ``payer_choices(...)[0]`` and
    a payer is valid exactly when listed here."""
    return [person for person, _ in payer_options(student_user_id)]


def resolve_payer(student_user_id: int, payer_id: int | None):
    """``payer_id``'s user when it is one of `payer_choices`, the default
    when it is None; otherwise a 400 on ``payer``."""
    choices = payer_choices(student_user_id)
    if payer_id is None:
        return choices[0]
    for person in choices:
        if person.pk == payer_id:
            return person
    raise ValidationError(
        "Choose the student, one of their guardians or their family's payer.",
        field="payer",
    )
```

In `backend/etqan/billing/services/__init__.py`, replace:

```python
from etqan.billing.services.payers import payer_choices
```

with:

```python
from etqan.billing.services.payers import payer_choices
from etqan.billing.services.payers import payer_options
```

In `backend/etqan/billing/services/__init__.py`, replace:

```python
    "payer_choices",
```

with:

```python
    "payer_choices",
    "payer_options",
```

In `backend/etqan/billing/api/payloads.py`, replace:

```python
def payers_payload(student_user_id: int, people) -> dict:
    """The payer choices for one student, the default first (P6-4)."""
    return {
        "default": people[0].pk,
        "choices": [
            {
                **_person(person),
                "relation": "student" if person.pk == student_user_id else "guardian",
            }
            for person in people
        ],
    }
```

with:

```python
def payers_payload(options) -> dict:
    """The payer choices for one student, the default first (P6-4), each
    with its relation: ``family`` (Plan 11: the invoice form labels it
    "Family payer"), ``guardian`` or ``student``."""
    return {
        "default": options[0][0].pk,
        "choices": [
            {**_person(person), "relation": relation} for person, relation in options
        ],
    }
```

In `backend/etqan/billing/api/views.py`, replace:

```python
        people = services.payer_choices(student.user_id)
        return Response(payloads.payers_payload(student.user_id, people))
```

with:

```python
        options = services.payer_options(student.user_id)
        return Response(payloads.payers_payload(options))
```

- [ ] **Step 4: Run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/billing -q
```

Expected: all pass, the existing payer tests included.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept (billing still reaches identity only through `identity.services`); 1423 tests (8 new), coverage 98.0%.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/billing
git -C backend commit -m "feat(billing): the family payer comes first in the payer rule

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Dev seeds: the Omar family in `demo`, nothing in `other`

**Files:**
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py`
- Test: `backend/etqan/tenants/tests/test_seed_dev.py` (two tests appended; the existing billing seed test still expects Omar Hassan on the Omar children's invoices, which he remains as their family's payer)

**Interfaces:**
- Consumes: Task 1's `families_queryset`, `create_family`, `payer_needs_choosing`; the seeds' `_person(role, full_name)`.
- Produces: `seed_dev.FAMILIES` and `seed_dev.seed_families(spec: dict | None) -> None`, run in `seed_academy` right after `seed_profiles` (before subscriptions and invoices, so the seeded invoices go to the family payer).

- [ ] **Step 1: Write the failing tests**

After `seed_dev`, `demo` has one family, "Omar family", with Aisha Omar and Yusuf Omar and their father Omar Hassan as its valid payer; Zaid Huda stays individual; `other` has no family. A second run changes nothing, a missing seeded person is skipped with a `skip:` line, and a family the rules refuse (an admin already moved a child elsewhere) is skipped with the rule's message.

Append to `backend/etqan/tenants/tests/test_seed_dev.py`:

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_makes_the_omar_family_once_and_none_in_the_other_academy(
    capsys, monkeypatch
):
    from etqan.identity import services as identity  # noqa: PLC0415

    def state():
        return [
            (
                family.name,
                family.payer.full_name,
                [p.user.full_name for p in family.students.all()],
                identity.payer_needs_choosing(family),
            )
            for family in identity.families_queryset()
        ]

    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        first = state()
        assert first == [
            ("Omar family", "Omar Hassan", ["Aisha Omar", "Yusuf Omar"], False)
        ]
        zaid = User.objects.get(full_name="Zaid Huda")
        assert identity.get_student_profile(zaid.pk).family is None
    with tenant_context(other):
        assert state() == []
    missing = {"name": "Nobody family", "students": ("Nobody",), "payer": "X"}
    monkeypatch.setitem(seed_dev.FAMILIES, "other", missing)
    capsys.readouterr()
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first
    with tenant_context(other):
        assert state() == []
    assert "skip: Nobody family — seeded record not found" in capsys.readouterr().out


@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_families_skips_what_the_rules_refuse(capsys):
    from etqan.identity import services as identity  # noqa: PLC0415

    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    with tenant_context(demo):
        family = identity.families_queryset().get()
        identity.update_family(family, fields={"name": "Renamed"})
        capsys.readouterr()
        seed_dev.seed_families(seed_dev.FAMILIES["demo"])
        out = capsys.readouterr().out
        assert "skip: Omar family — Yusuf Omar is already in another family." in out
        assert [f.name for f in identity.families_queryset()] == ["Renamed"]
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.venv/bin/pytest etqan/tenants/tests/test_seed_dev.py -q -k "family or families"`

Expected: FAIL — `assert [] == [('Omar family', …)]` and `DoesNotExist` from `families_queryset().get()`.

- [ ] **Step 3: Implement**

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
def seed_subscriptions(specs: list[dict]) -> None:
```

with:

```python
# Plan 11 (spec §7): demo's two Omar children are one family, their father
# paying; Zaid stays individual. The other academy gets no family.
FAMILIES = {
    "demo": {
        "name": "Omar family",
        "students": ("Yusuf Omar", "Aisha Omar"),
        "payer": "Omar Hassan",
    },
}


def seed_families(spec: dict | None) -> None:
    """Demo's family, once: nothing happens when a family of that name
    exists. A missing seeded person is skipped, and so is a family the rules
    refuse (an admin already put a child in another family)."""
    if spec is None:
        return
    if identity_services.families_queryset().filter(name=spec["name"]).exists():
        return
    students = [_person("student", name) for name in spec["students"]]
    payer = _person("parent", spec["payer"])
    if payer is None or None in students:
        print(f"skip: {spec['name']} — seeded record not found")  # noqa: T201
        return
    try:
        identity_services.create_family(
            name=spec["name"],
            student_ids=[student.pk for student in students],
            payer_id=payer.pk,
        )
    except ValidationError as exc:
        print(f"skip: {spec['name']} — {exc}")  # noqa: T201


def seed_subscriptions(specs: list[dict]) -> None:
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
        seed_profiles(PROFILES.get(subdomain))
```

with:

```python
        seed_profiles(PROFILES.get(subdomain))
        seed_families(FAMILIES.get(subdomain))
```

- [ ] **Step 4: Run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/tenants/tests/test_seed_dev.py -q
```

Expected: all pass, the billing seed test included (Omar Hassan still pays the Omar children's invoices, now as their family's payer).

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1425 tests (2 new), coverage 98.0%.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/tenants
git -C backend commit -m "feat(tenants): seed the Omar family in the demo academy

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Dashboard: the families data layer

**Files:**
- Modify: `dashboard/src/features/people/schemas.ts`, `dashboard/src/features/people/api.ts`, `dashboard/src/features/people/queries.ts`, `dashboard/src/test/people-fixtures.ts`
- Test: `dashboard/src/features/people/families-api.test.ts` (new), `dashboard/src/features/people/families-queries.test.tsx` (new); `StudentsList.test.tsx` and `StudentForm.test.tsx` (their student fixtures gain `account_type` and `family`, without which `tsc` fails)

**Interfaces:**
- Consumes: Tasks 2 to 4's routes and payloads.
- Produces (all exported from `@/features/people`):
  - types `AccountType` (`ACCOUNT_TYPES = ["individual", "family"]`), `FamilyRef {id, name}`, `FamilyPayer {id, full_name, role}`, `Family` (the row), `FamilyInput {name, student_ids, payer_id, notes}`, `FamilyChange` (partial, plus `is_active`), `SkippedStudent {id, full_name, reason}`, `BulkResult {updated, skipped?}`; `StudentProfile` gains `account_type` and `family`; `BulkAction` gains the three family actions and `BulkBody` gains `name`, `payer_id`, `family_id`;
  - zod `familyFormSchema` (`name`, `student_ids`, `payer_id` as the select's string, `notes`; messages `people.families.errors.*`) and `bulkFamilySchema` (its `name` and `payer_id`), with `FamilyFormValues` and `BulkFamilyValues`;
  - `peopleApi.families(params)`, `.family(id)`, `.createFamily(body)`, `.updateFamily(id, body)`, `.familyPayers(studentIds)` (`?students=1,2`); `bulkStudents` resolves to `BulkResult`;
  - `familiesKey = ["people", "families"]`, `useFamilies(params, {enabled})`, `useFamily(id)`, `useFamilyPayers(studentIds)` (disabled while empty; the key sorts the ids), `useCreateFamily()`, `useUpdateFamily()` (both refresh `["people"]`); `useBulkStudents` also refreshes `familiesKey`;
  - `src/test/people-fixtures.ts`: `familyRow(fields)` (Yusuf 11 and Aisha 12, Omar 31 paying).

- [ ] **Step 1: Write the failing tests**

The API functions hit the routes with the right parameters (empty filters dropped); the payer choices are not asked while no student is chosen, and the same set in another order is one request; saving a family refreshes every people list, and a bulk action refreshes the families.

In `dashboard/src/test/people-fixtures.ts`, replace:

```ts
import type { Tag } from "@/features/people/schemas";

/** A tags-admin row: a student tag unless ``fields`` says otherwise. */
```

with:

```ts
import type { Family, Tag } from "@/features/people/schemas";

/** A tags-admin row: a student tag unless ``fields`` says otherwise. */
```

In `dashboard/src/test/people-fixtures.ts`, replace:

```ts
		position: 1,
	}),
];
```

with:

```ts
		position: 1,
	}),
];

/** A families-admin row: Yusuf and Aisha, their father Omar paying, unless
 * ``fields`` says otherwise. */
export function familyRow(
	fields: Partial<Family> & Pick<Family, "id">,
): Family {
	return {
		name: `Family ${fields.id}`,
		is_active: true,
		payer: { id: 31, full_name: "Omar", role: "parent" },
		payer_needs_choosing: false,
		students: [
			{ id: 12, full_name: "Aisha" },
			{ id: 11, full_name: "Yusuf" },
		],
		notes: "",
		created_at: "2026-06-01T08:00:00Z",
		...fields,
	};
}
```

Create `dashboard/src/features/people/families-api.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "@/lib/api";
import { peopleApi } from "./api";

vi.mock("@/lib/api", async (orig) => {
	const actual = await orig<typeof import("@/lib/api")>();
	const ok = () => Promise.resolve({ data: { id: 1 } });
	return {
		...actual,
		api: { get: vi.fn(ok), post: vi.fn(ok), patch: vi.fn(ok) },
	};
});

describe("peopleApi families", () => {
	beforeEach(() => vi.clearAllMocks());

	it("lists, reads, creates and patches families", async () => {
		await peopleApi.families({ search: "omar", active: "", page: 2 });
		expect(api.get).toHaveBeenCalledWith("people/families/", {
			params: { search: "omar", page: "2" },
		});
		await peopleApi.family(4);
		expect(api.get).toHaveBeenCalledWith("people/families/4/");
		const body = { name: "F", student_ids: [11], payer_id: 31, notes: "" };
		await peopleApi.createFamily(body);
		expect(api.post).toHaveBeenCalledWith("people/families/", body);
		await peopleApi.updateFamily(4, { is_active: false });
		expect(api.patch).toHaveBeenCalledWith("people/families/4/", {
			is_active: false,
		});
	});

	it("asks for the payer choices of a set of students", async () => {
		await peopleApi.familyPayers([12, 11]);
		expect(api.get).toHaveBeenCalledWith("people/families/payers/", {
			params: { students: "12,11" },
		});
	});
});
```

Create `dashboard/src/features/people/families-queries.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { familyRow } from "@/test/people-fixtures";
import { peopleApi } from "./api";
import {
	useBulkStudents,
	useCreateFamily,
	useFamilyPayers,
	useUpdateFamily,
} from "./queries";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: {
			...actual.peopleApi,
			familyPayers: vi.fn(),
			createFamily: vi.fn(),
			updateFamily: vi.fn(),
			bulkStudents: vi.fn(),
		},
	};
});

function spiedWrapper() {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	const spy = vi.spyOn(client, "invalidateQueries");
	const wrap = ({ children }: { children: ReactNode }) => (
		<QueryClientProvider client={client}>{children}</QueryClientProvider>
	);
	return { wrap, spy };
}

describe("family queries", () => {
	beforeEach(() => vi.clearAllMocks());

	it("asks for payers only once a student is chosen, whatever the order", async () => {
		vi.mocked(peopleApi.familyPayers).mockResolvedValue([]);
		const { wrap } = spiedWrapper();
		const { rerender } = renderHook(
			({ ids }: { ids: number[] }) => useFamilyPayers(ids),
			{ wrapper: wrap, initialProps: { ids: [] as number[] } },
		);
		expect(peopleApi.familyPayers).not.toHaveBeenCalled();
		rerender({ ids: [12, 11] });
		await waitFor(() =>
			expect(peopleApi.familyPayers).toHaveBeenCalledWith([11, 12]),
		);
		rerender({ ids: [11, 12] }); // the same set: no second request
		expect(peopleApi.familyPayers).toHaveBeenCalledTimes(1);
	});

	it("refreshes every people list after a family is saved", async () => {
		vi.mocked(peopleApi.createFamily).mockResolvedValue(familyRow({ id: 4 }));
		vi.mocked(peopleApi.updateFamily).mockResolvedValue(familyRow({ id: 4 }));
		const { wrap, spy } = spiedWrapper();
		const create = renderHook(() => useCreateFamily(), { wrapper: wrap });
		await create.result.current.mutateAsync({
			name: "F",
			student_ids: [11],
			payer_id: 31,
			notes: "",
		});
		expect(spy).toHaveBeenLastCalledWith({ queryKey: ["people"] });
		spy.mockClear();
		const update = renderHook(() => useUpdateFamily(), { wrapper: wrap });
		await update.result.current.mutateAsync({ id: 4, body: { name: "G" } });
		expect(spy).toHaveBeenCalledWith({ queryKey: ["people"] });
	});

	it("refreshes the families after a bulk action", async () => {
		vi.mocked(peopleApi.bulkStudents).mockResolvedValue({
			updated: 1,
			skipped: [],
		});
		const { wrap, spy } = spiedWrapper();
		const { result } = renderHook(() => useBulkStudents(), { wrapper: wrap });
		await result.current.mutateAsync({
			ids: [11],
			action: "remove_from_family",
		});
		expect(spy).toHaveBeenCalledWith({ queryKey: ["people", "families"] });
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/people/families-api.test.ts src/features/people/families-queries.test.tsx`

Expected: FAIL — `peopleApi.families is not a function` and `useFamilyPayers is not a function` (5 failed).

- [ ] **Step 3: Implement**

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
	| "set_status"
	| "add_tag"
	| "remove_tag";

export const STUDENT_STATUSES = [
```

with:

```ts
	| "set_status"
	| "add_tag"
	| "remove_tag"
	| "create_family"
	| "add_to_family"
	| "remove_from_family";

export const STUDENT_STATUSES = [
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
}

export interface PersonUser {
	full_name: string;
```

with:

```ts
}

/** Plan 11: a student's account type, derived from being in a family (F-3). */
export const ACCOUNT_TYPES = ["individual", "family"] as const;
export type AccountType = (typeof ACCOUNT_TYPES)[number];
/** A student's family as their row carries it. */
export interface FamilyRef {
	id: number;
	name: string;
}
/** Who pays for a family, or may: one of its students or a parent (F-2). */
export interface FamilyPayer {
	id: number;
	full_name: string;
	role: "admin" | "teacher" | "student" | "parent";
}
/** A row of the families admin (`GET people/families/`). */
export interface Family {
	id: number;
	name: string;
	is_active: boolean;
	payer: FamilyPayer;
	/** The payer no longer qualifies; an admin must choose a new one (F-4). */
	payer_needs_choosing: boolean;
	/** User ids and names, by name. */
	students: { id: number; full_name: string }[];
	notes: string;
	created_at: string;
}
export interface FamilyInput {
	name: string;
	student_ids: number[];
	payer_id: number;
	notes: string;
}
/** A PATCH to one family: any of its fields, or retire (`false`) and
 * restore (`true`). */
export type FamilyChange = Partial<FamilyInput> & { is_active?: boolean };
/** A student a bulk family action left alone: already in another family. */
export interface SkippedStudent {
	id: number;
	full_name: string;
	reason: "in_another_family";
}
/** The bulk action's answer; the family actions add `skipped`. */
export interface BulkResult {
	updated: number;
	skipped?: SkippedStudent[];
}

export interface PersonUser {
	full_name: string;
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
	age_group: AgeGroup | null;
	tags: TagChip[];
}
export interface TeacherProfile {
```

with:

```ts
	age_group: AgeGroup | null;
	tags: TagChip[];
	account_type: AccountType;
	family: FamilyRef | null;
}
export interface TeacherProfile {
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
export type TagFormValues = z.infer<typeof tagFormSchema>;
```

with:

```ts
export type TagFormValues = z.infer<typeof tagFormSchema>;

/** The Add and Edit family dialogs (Plan 11 §6). The payer is the select's
 * value, a user id as a string, until the form is sent. */
export const familyFormSchema = z.object({
	name: z
		.string()
		.trim()
		.min(1, "people.families.errors.nameRequired")
		.max(120, "people.families.errors.nameTooLong"),
	student_ids: z
		.array(z.number())
		.min(1, "people.families.errors.studentsRequired"),
	payer_id: z.string().min(1, "people.families.errors.payerRequired"),
	notes: z.string(),
});
export type FamilyFormValues = z.infer<typeof familyFormSchema>;

/** The bulk bar's Create family dialog: the students are the selection. */
export const bulkFamilySchema = familyFormSchema.pick({
	name: true,
	payer_id: true,
});
export type BulkFamilyValues = z.infer<typeof bulkFamilySchema>;
```

In `dashboard/src/features/people/api.ts`, replace:

```ts
import type {
	BulkAction,
	Kind,
	Paginated,
```

with:

```ts
import type {
	BulkAction,
	BulkResult,
	Family,
	FamilyChange,
	FamilyInput,
	FamilyPayer,
	Kind,
	Paginated,
```

In `dashboard/src/features/people/api.ts`, replace:

```ts
	status?: StudentStatus;
	tag_id?: number;
}
/** A PATCH to one tag: a new name or emoji, a new 1-based place in its
```

with:

```ts
	status?: StudentStatus;
	tag_id?: number;
	/** `create_family`: the new family's name and payer. */
	name?: string;
	payer_id?: number;
	/** `add_to_family`. */
	family_id?: number;
}
/** A PATCH to one tag: a new name or emoji, a new 1-based place in its
```

In `dashboard/src/features/people/api.ts`, replace:

```ts
	},
	bulkStudents: async (body: BulkBody) =>
		(await api.post<{ updated: number }>("people/students/bulk/", body)).data,
	tags: async (kind: TagKind) =>
		(await api.get<Tag[]>("people/tags/", { params: { kind } })).data,
```

with:

```ts
	},
	bulkStudents: async (body: BulkBody) =>
		(await api.post<BulkResult>("people/students/bulk/", body)).data,
	tags: async (kind: TagKind) =>
		(await api.get<Tag[]>("people/tags/", { params: { kind } })).data,
```

In `dashboard/src/features/people/api.ts`, replace:

```ts
	updateTag: async (id: number, body: TagChange) =>
		(await api.patch<Tag>(`people/tags/${id}/`, body)).data,
};
```

with:

```ts
	updateTag: async (id: number, body: TagChange) =>
		(await api.patch<Tag>(`people/tags/${id}/`, body)).data,
	families: async (params: ListParams) =>
		(
			await api.get<Paginated<Family>>("people/families/", {
				params: clean(params),
			})
		).data,
	family: async (id: number) =>
		(await api.get<Family>(`people/families/${id}/`)).data,
	createFamily: async (body: FamilyInput) =>
		(await api.post<Family>("people/families/", body)).data,
	updateFamily: async (id: number, body: FamilyChange) =>
		(await api.patch<Family>(`people/families/${id}/`, body)).data,
	/** Who may pay for a family of these students (user ids): the students,
	 * then their active parents. */
	familyPayers: async (studentIds: readonly number[]) =>
		(
			await api.get<FamilyPayer[]>("people/families/payers/", {
				params: { students: studentIds.join(",") },
			})
		).data,
};
```

In `dashboard/src/features/people/queries.ts`, replace:

```ts
	type TagChange,
} from "./api";
import type { Kind, PersonAction, TagInput, TagKind } from "./schemas";

export const peopleKey = (kind: Kind) => ["people", kind] as const;
/** Under `["people"]`: a person's save changes the tags' counts too. */
export const tagsKey = (kind: TagKind) => ["people", "tags", kind] as const;
export const guardiansKey = (studentId: number) =>
	["people", "students", "guardians", studentId] as const;
```

with:

```ts
	type TagChange,
} from "./api";
import type {
	FamilyChange,
	FamilyInput,
	Kind,
	PersonAction,
	TagInput,
	TagKind,
} from "./schemas";

export const peopleKey = (kind: Kind) => ["people", kind] as const;
/** Under `["people"]`: a person's save changes the tags' counts too. */
export const tagsKey = (kind: TagKind) => ["people", "tags", kind] as const;
/** Under `["people"]`: a family's save changes its students' rows too. */
export const familiesKey = ["people", "families"] as const;
export const guardiansKey = (studentId: number) =>
	["people", "students", "guardians", studentId] as const;
```

In `dashboard/src/features/people/queries.ts`, replace:

```ts
			qc.invalidateQueries({ queryKey: peopleKey("students") });
			qc.invalidateQueries({ queryKey: ["people", "tags"] });
		},
	});
```

with:

```ts
			qc.invalidateQueries({ queryKey: peopleKey("students") });
			qc.invalidateQueries({ queryKey: ["people", "tags"] });
			qc.invalidateQueries({ queryKey: familiesKey });
		},
	});
```

In `dashboard/src/features/people/queries.ts`, replace:

```ts
		onSuccess: () => qc.invalidateQueries({ queryKey: ["people"] }),
	});
}
```

with:

```ts
		onSuccess: () => qc.invalidateQueries({ queryKey: ["people"] }),
	});
}

/** A page of families (Plan 11 §5). */
export function useFamilies(
	params: ListParams,
	options: { enabled?: boolean } = {},
) {
	return useQuery({
		queryKey: [...familiesKey, "list", params],
		queryFn: () => peopleApi.families(params),
		placeholderData: keepPreviousData,
		enabled: options.enabled ?? true,
	});
}

export function useFamily(id: number | undefined) {
	return useQuery({
		queryKey: [...familiesKey, "detail", id],
		queryFn: () => peopleApi.family(id as number),
		enabled: id !== undefined,
	});
}

/** Who may pay for a family of these students; nothing until one is chosen. */
export function useFamilyPayers(studentIds: readonly number[]) {
	const ids = [...studentIds].sort((a, b) => a - b);
	return useQuery({
		queryKey: [...familiesKey, "payers", ids],
		queryFn: () => peopleApi.familyPayers(ids),
		enabled: ids.length > 0,
	});
}

/** A family's students show it on their rows: refresh all of `["people"]`. */
export function useCreateFamily() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (body: FamilyInput) => peopleApi.createFamily(body),
		onSuccess: () => qc.invalidateQueries({ queryKey: ["people"] }),
	});
}

export function useUpdateFamily() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: ({ id, body }: { id: number; body: FamilyChange }) =>
			peopleApi.updateFamily(id, body),
		onSuccess: () => qc.invalidateQueries({ queryKey: ["people"] }),
	});
}
```

In `dashboard/src/features/people/StudentsList.test.tsx`, replace:

```tsx
		age_group: null,
		tags,
	},
});
```

with:

```tsx
		age_group: null,
		tags,
		account_type: "individual",
		family: null,
	},
});
```

In `dashboard/src/features/people/StudentForm.test.tsx`, replace:

```tsx
		age_group: null,
		tags: [],
	},
};
```

with:

```tsx
		age_group: null,
		tags: [],
		account_type: "individual",
		family: null,
	},
};
```

- [ ] **Step 4: Verify**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 673 tests (5 new); lines 94.2%, branches 87.8%, functions 81.7%.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(people): families data layer

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Dashboard: People → Families (list, Add and Edit dialogs, Retire and Restore, the family page)

**Files:**
- Create: `dashboard/src/features/people/FamilyDialog.tsx`, `dashboard/src/features/people/FamiliesList.tsx`, `dashboard/src/features/people/FamilyPage.tsx`, `dashboard/src/routes/_authed/people.families.index.tsx`, `dashboard/src/routes/_authed/people.families.$familyId.tsx`
- Modify: `dashboard/src/features/people/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`, `dashboard/src/routeTree.gen.ts` (regenerated by `vite build`)
- Test: `FamilyDialog.test.tsx`, `FamiliesList.test.tsx`, `FamilyPage.test.tsx` (new); `dashboard/src/features/shell/nav.test.ts` (the item order and the People group gain Families)

**Interfaces:**
- Consumes: Task 7's types, `peopleApi` functions and hooks, `familyRow`; `usePeople`; the shared `Pager`, `Fact`, `applyServerErrors`/`errorText`, `useFieldError`.
- Produces:
  - `<FamilyDialog family?>`: Add ("Add family") or Edit ("Edit", named "Edit {{name}}"); fields Name, a Students fieldset (chosen students with "Remove {{name}}", "Find a student" with "Add {{name}}" buttons for students in no other family or in this one), Payer (the choices of the chosen students, asked only while the dialog is open and again when the students change; a payer who no longer suits is cleared), Notes; "Save family"; a flagged family shows "Choose a new payer";
  - `PayerOptions` (`<option>`s labelled "Omar (parent)", "Aisha (student)"), reused by Task 9;
  - `<FamiliesList />` (search, a Status filter, Add, rows with the name linking to the family page, student chips, the payer with a "Choose a new payer" chip when flagged, Active or Retired, Edit, "Retire {{name}}"/"Restore {{name}}"), `FamilyActiveToggle`, `FamilyPayerCell`;
  - `<FamilyPage familyId />` at `/people/families/$familyId`: the family, links to its students, Edit and Retire or Restore;
  - nav: "Families" (`/people/families`) after Parents in People, admins only;
  - locale keys `nav.families` and `people.families.*`.

- [ ] **Step 1: Write the failing tests**

The dialog adds a family from students in no other family (another family's student is never offered, and search waits for two letters), asks for the payer choices of exactly the chosen students, and sends the new family; it asks for a name, a student and a payer; a flagged family's old payer no longer counts, so saving asks for a new one, and removing a student asks for new choices; a server error lands under its field. The list shows each family's students, payer, flag and status (scoped to the row), searches and filters, retires and restores, and asks no payer choices for its closed Edit dialogs. The page links the students and says a missing or non-numeric family doesn't exist without asking the API for "abc". The nav lists Families in People.

Create `dashboard/src/features/people/FamiliesList.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { familyRow } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { FamiliesList } from "./FamiliesList";
import type { Family } from "./schemas";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: {
			...actual.peopleApi,
			families: vi.fn(),
			updateFamily: vi.fn(),
			familyPayers: vi.fn(),
		},
	};
});

const page = (results: Family[]) => ({
	count: results.length,
	next: null,
	previous: null,
	results,
});

function lastParams() {
	return vi.mocked(peopleApi.families).mock.calls.at(-1)?.[0];
}

describe("FamiliesList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.families).mockResolvedValue(
			page([
				familyRow({ id: 4, name: "Omar family" }),
				familyRow({
					id: 5,
					name: "Huda family",
					is_active: false,
					payer: { id: 13, full_name: "Zaid", role: "student" },
					payer_needs_choosing: true,
					students: [{ id: 14, full_name: "Maryam" }],
				}),
			]),
		);
		vi.mocked(peopleApi.updateFamily).mockResolvedValue(familyRow({ id: 4 }));
	});

	it("lists each family's students, payer and status", async () => {
		renderWithRouter(<FamiliesList />, {
			extraPaths: ["/people/families/$familyId"],
		});
		const omar = await screen.findByRole("row", { name: /Omar family/ });
		expect(
			within(omar).getByRole("link", { name: "Omar family" }),
		).toHaveAttribute("href", "/people/families/4");
		expect(
			within(omar)
				.getAllByRole("listitem")
				.map((li) => li.textContent),
		).toEqual(["Aisha", "Yusuf"]);
		expect(within(omar).getByText("Omar")).toBeInTheDocument();
		expect(within(omar).queryByText("Choose a new payer")).toBeNull();
		expect(within(omar).getByText("Active")).toBeInTheDocument();
		const huda = screen.getByRole("row", { name: /Huda family/ });
		expect(within(huda).getByText("Choose a new payer")).toBeInTheDocument();
		expect(within(huda).getByText("Retired")).toBeInTheDocument();
		// A closed Edit dialog asks nothing: no payer request per row.
		expect(peopleApi.familyPayers).not.toHaveBeenCalled();
	});

	it("searches and filters by status", async () => {
		const user = userEvent.setup();
		renderWithRouter(<FamiliesList />);
		await screen.findByText("Omar family");
		await user.type(screen.getByRole("searchbox"), "omar");
		await user.selectOptions(
			screen.getByRole("combobox", { name: "Status" }),
			"false",
		);
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				search: "omar",
				active: "false",
				page: 1,
			}),
		);
	});

	it("retires an active family and restores a retired one", async () => {
		const user = userEvent.setup();
		renderWithRouter(<FamiliesList />);
		await user.click(
			await screen.findByRole("button", { name: "Retire Omar family" }),
		);
		await waitFor(() =>
			expect(peopleApi.updateFamily).toHaveBeenCalledWith(4, {
				is_active: false,
			}),
		);
		expect(await screen.findByText("Family retired.")).toBeInTheDocument();
		await user.click(
			screen.getByRole("button", { name: "Restore Huda family" }),
		);
		await waitFor(() =>
			expect(peopleApi.updateFamily).toHaveBeenLastCalledWith(5, {
				is_active: true,
			}),
		);
	});

	it("shows an empty state and a load error", async () => {
		vi.mocked(peopleApi.families).mockResolvedValueOnce(page([]));
		const { unmount } = renderWithRouter(<FamiliesList />);
		expect(await screen.findByText("No families yet.")).toBeInTheDocument();
		unmount();
		vi.mocked(peopleApi.families).mockRejectedValueOnce(new Error("down"));
		renderWithRouter(<FamiliesList />);
		expect(
			await screen.findByText("Couldn't load the families."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/people/FamilyDialog.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { familyRow } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { FamilyDialog } from "./FamilyDialog";
import type { FamilyRef, Person, StudentProfile } from "./schemas";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: {
			...actual.peopleApi,
			list: vi.fn(),
			familyPayers: vi.fn(),
			createFamily: vi.fn(),
			updateFamily: vi.fn(),
		},
	};
});

const student = (
	id: number,
	name: string,
	family: FamilyRef | null = null,
): Person<StudentProfile> => ({
	id,
	role: "student",
	user: {
		full_name: name,
		email: null,
		phone: "",
		preferred_language: "en",
		timezone: "UTC",
		is_active: true,
		account_state: "no_login",
		pending_email: "",
	},
	profile: {
		date_of_birth: null,
		gender: "",
		country: "",
		status: "active",
		notes: "",
		xp: 0,
		nationality: "",
		age_group: null,
		tags: [],
		account_type: family ? "family" : "individual",
		family,
	},
});

describe("FamilyDialog", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue({
			count: 3,
			next: null,
			previous: null,
			results: [
				student(11, "Yusuf"),
				student(12, "Aisha"),
				student(13, "Zaid", { id: 9, name: "Huda family" }),
			],
		});
		vi.mocked(peopleApi.familyPayers).mockImplementation(async (ids) =>
			ids.length === 2
				? [
						{ id: 12, full_name: "Aisha", role: "student" },
						{ id: 11, full_name: "Yusuf", role: "student" },
						{ id: 31, full_name: "Omar", role: "parent" },
					]
				: [{ id: 11, full_name: "Yusuf", role: "student" }],
		);
		vi.mocked(peopleApi.createFamily).mockResolvedValue(familyRow({ id: 4 }));
		vi.mocked(peopleApi.updateFamily).mockResolvedValue(familyRow({ id: 4 }));
	});

	it("adds a family from students in no other family and their parent", async () => {
		const user = userEvent.setup();
		renderWithRouter(<FamilyDialog />);
		await user.click(await screen.findByRole("button", { name: "Add family" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Name/), "Omar family");
		await user.type(within(dialog).getByLabelText("Find a student"), "a");
		expect(peopleApi.list).not.toHaveBeenCalled(); // two letters first
		await user.type(within(dialog).getByLabelText("Find a student"), "i");
		await user.click(
			await within(dialog).findByRole("button", { name: "Add Yusuf" }),
		);
		await user.click(within(dialog).getByRole("button", { name: "Add Aisha" }));
		// Zaid is in another family: never offered.
		expect(
			within(dialog).queryByRole("button", { name: "Add Zaid" }),
		).toBeNull();
		const payer = within(dialog).getByLabelText(/^Payer/);
		await within(payer).findByRole("option", { name: "Omar (parent)" });
		expect(peopleApi.familyPayers).toHaveBeenLastCalledWith([11, 12]);
		await user.selectOptions(payer, "31");
		await user.click(
			within(dialog).getByRole("button", { name: "Save family" }),
		);
		await waitFor(() =>
			expect(peopleApi.createFamily).toHaveBeenCalledWith({
				name: "Omar family",
				student_ids: [11, 12],
				payer_id: 31,
				notes: "",
			}),
		);
		expect(await screen.findByText("Family saved.")).toBeInTheDocument();
	});

	it("asks for a name, a student and a payer", async () => {
		const user = userEvent.setup();
		renderWithRouter(<FamilyDialog />);
		await user.click(await screen.findByRole("button", { name: "Add family" }));
		const dialog = await screen.findByRole("dialog");
		await user.click(
			within(dialog).getByRole("button", { name: "Save family" }),
		);
		expect(
			await within(dialog).findByText("Enter a name."),
		).toBeInTheDocument();
		expect(
			within(dialog).getByText("Choose at least one student."),
		).toBeInTheDocument();
		expect(within(dialog).getByText("Choose who pays.")).toBeInTheDocument();
		expect(peopleApi.createFamily).not.toHaveBeenCalled();
	});

	it("asks a flagged family for a new payer and re-asks when a student leaves", async () => {
		const flagged = familyRow({
			id: 4,
			name: "Omar family",
			payer: { id: 40, full_name: "Gone", role: "parent" },
			payer_needs_choosing: true,
		});
		const user = userEvent.setup();
		renderWithRouter(<FamilyDialog family={flagged} />);
		await user.click(
			await screen.findByRole("button", { name: "Edit Omar family" }),
		);
		const dialog = await screen.findByRole("dialog");
		expect(within(dialog).getByText("Choose a new payer")).toBeInTheDocument();
		const payer = within(dialog).getByLabelText(/^Payer/);
		await within(payer).findByRole("option", { name: "Omar (parent)" });
		// The old payer no longer qualifies: the form wants a new one.
		await user.click(
			within(dialog).getByRole("button", { name: "Save family" }),
		);
		expect(
			await within(dialog).findByText("Choose who pays."),
		).toBeInTheDocument();
		expect(peopleApi.updateFamily).not.toHaveBeenCalled();
		await user.click(
			within(dialog).getByRole("button", { name: "Remove Aisha" }),
		);
		await waitFor(() =>
			expect(peopleApi.familyPayers).toHaveBeenLastCalledWith([11]),
		);
		await user.selectOptions(payer, "11");
		await user.click(
			within(dialog).getByRole("button", { name: "Save family" }),
		);
		await waitFor(() =>
			expect(peopleApi.updateFamily).toHaveBeenCalledWith(4, {
				name: "Omar family",
				student_ids: [11],
				payer_id: 11,
				notes: "",
			}),
		);
	});

	it("puts the server's reason under its field", async () => {
		vi.mocked(peopleApi.updateFamily).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { student_ids: ["Aisha is already in another family."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(
			<FamilyDialog family={familyRow({ id: 4, name: "Mine" })} />,
		);
		await user.click(await screen.findByRole("button", { name: "Edit Mine" }));
		const dialog = await screen.findByRole("dialog");
		await within(within(dialog).getByLabelText(/^Payer/)).findByRole("option", {
			name: "Omar (parent)",
		});
		await user.click(
			within(dialog).getByRole("button", { name: "Save family" }),
		);
		expect(
			await within(dialog).findByText("Aisha is already in another family."),
		).toBeInTheDocument();
		expect(screen.getByRole("dialog")).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/people/FamilyPage.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { familyRow } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { FamilyPage } from "./FamilyPage";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: { ...actual.peopleApi, family: vi.fn(), familyPayers: vi.fn() },
	};
});

describe("FamilyPage", () => {
	beforeEach(() => vi.clearAllMocks());

	it("shows the family with links to its students", async () => {
		vi.mocked(peopleApi.family).mockResolvedValue(
			familyRow({ id: 4, name: "Omar family", notes: "Pays monthly" }),
		);
		renderWithRouter(<FamilyPage familyId="4" />, {
			extraPaths: ["/people/students/$personId"],
		});
		expect(await screen.findByText("Omar family")).toBeInTheDocument();
		expect(peopleApi.family).toHaveBeenCalledWith(4);
		expect(screen.getByRole("link", { name: "Yusuf" })).toHaveAttribute(
			"href",
			"/people/students/11",
		);
		expect(screen.getByText("Omar")).toBeInTheDocument();
		expect(screen.getByText("Pays monthly")).toBeInTheDocument();
		expect(
			screen.getByRole("button", { name: "Retire Omar family" }),
		).toBeInTheDocument();
	});

	it("says a missing family doesn't exist", async () => {
		vi.mocked(peopleApi.family).mockRejectedValue(
			new AxiosError("Not found", "404", undefined, undefined, {
				status: 404,
				data: {},
			} as never),
		);
		const { unmount } = renderWithRouter(<FamilyPage familyId="99" />);
		expect(
			await screen.findByText("This family doesn't exist."),
		).toBeInTheDocument();
		unmount();
		renderWithRouter(<FamilyPage familyId="abc" />);
		expect(
			await screen.findByText("This family doesn't exist."),
		).toBeInTheDocument();
		expect(peopleApi.family).toHaveBeenCalledTimes(1);
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"/people/students",
			"/people/parents",
			"/people/teachers",
			"/people/admins",
```

with:

```ts
			"/people/students",
			"/people/parents",
			"/people/families",
			"/people/teachers",
			"/people/admins",
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"nav.adjustments",
		]);
		expect(groups[4]?.items).toHaveLength(4);
	});
});
```

with:

```ts
			"nav.adjustments",
		]);
		expect(groups[4]?.items.map((i) => i.labelKey)).toEqual([
			"nav.students",
			"nav.parents",
			"nav.families",
			"nav.teachers",
			"nav.admins",
		]);
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `npx pnpm@10 exec vitest run src/features/people/FamiliesList.test.tsx src/features/people/FamilyDialog.test.tsx src/features/people/FamilyPage.test.tsx src/features/shell/nav.test.ts`

Expected: FAIL — `Failed to resolve import "./FamiliesList"` (and `./FamilyDialog`, `./FamilyPage`), and the nav tests miss `/people/families`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/people/FamilyDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	FormError,
	Input,
	Select,
	Textarea,
	toast,
} from "@/ui";
import {
	useCreateFamily,
	useFamilyPayers,
	usePeople,
	useUpdateFamily,
} from "./queries";
import {
	type Family,
	type FamilyFormValues,
	type FamilyPayer,
	familyFormSchema,
	type StudentProfile,
} from "./schemas";

type Chosen = { id: number; full_name: string };

function blank(family?: Family): FamilyFormValues {
	return {
		name: family?.name ?? "",
		student_ids: (family?.students ?? []).map((s) => s.id),
		payer_id: family ? String(family.payer.id) : "",
		notes: family?.notes ?? "",
	};
}

/** A payer choice as its option reads: "Omar (parent)". */
export function PayerOptions({ payers }: { payers: readonly FamilyPayer[] }) {
	const { t } = useTranslation();
	return (
		<>
			{payers.map((payer) => (
				<option key={payer.id} value={String(payer.id)}>
					{t(`people.families.payerOption.${payer.role}`, {
						name: payer.full_name,
						defaultValue: payer.full_name,
					})}
				</option>
			))}
		</>
	);
}

/** Add a family (no `family`) or edit one (Plan 11 §6): its name, its
 * students (those in no other family, plus its own), its payer (one of the
 * chosen students or their active parents, asked again whenever the
 * students change) and notes. */
export function FamilyDialog({ family }: { family?: Family }) {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	const [chosen, setChosen] = useState<Chosen[]>(family?.students ?? []);
	const [query, setQuery] = useState("");
	const create = useCreateFamily();
	const update = useUpdateFamily();
	const fieldError = useFieldError();
	const {
		register,
		handleSubmit,
		reset,
		setError,
		setValue,
		getValues,
		watch,
		formState: { errors, isSubmitting },
	} = useForm<FamilyFormValues>({
		resolver: zodResolver(familyFormSchema),
		defaultValues: blank(family),
	});
	const studentIds = watch("student_ids");
	// Only while open: every row of the list has an Edit dialog.
	const { data: payers } = useFamilyPayers(open ? studentIds : []);
	const searching = query.trim().length >= 2;
	const { data: matches } = usePeople<StudentProfile>(
		"students",
		{ q: query.trim(), page_size: 5 },
		{ enabled: open && searching },
	);
	const prefix = family ? `family-${family.id}` : "new-family";

	// A payer who no longer suits the chosen students must be chosen again.
	useEffect(() => {
		if (!open || !payers) return;
		const current = getValues("payer_id");
		if (current && !payers.some((p) => String(p.id) === current)) {
			setValue("payer_id", "");
		}
	}, [open, payers, getValues, setValue]);

	function choose(next: Chosen[]) {
		setChosen(next);
		setValue(
			"student_ids",
			next.map((s) => s.id),
			{ shouldValidate: next.length > 0 },
		);
	}

	function openChange(next: boolean) {
		if (next) {
			reset(blank(family));
			setChosen(family?.students ?? []);
			setQuery("");
		}
		setOpen(next);
	}

	async function onSubmit(values: FamilyFormValues) {
		const body = {
			name: values.name.trim(),
			student_ids: values.student_ids,
			payer_id: Number(values.payer_id),
			notes: values.notes,
		};
		try {
			if (family) await update.mutateAsync({ id: family.id, body });
			else await create.mutateAsync(body);
			toast({ description: t("people.families.saved"), variant: "success" });
			setOpen(false);
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	const addable = (matches?.results ?? []).filter(
		(row) =>
			!studentIds.includes(row.id) &&
			(row.profile.family === null || row.profile.family.id === family?.id),
	);

	return (
		<Dialog open={open} onOpenChange={openChange}>
			<DialogTrigger asChild>
				{family ? (
					<Button
						size="sm"
						variant="outline"
						aria-label={t("people.families.editName", { name: family.name })}
					>
						{t("people.families.edit")}
					</Button>
				) : (
					<Button size="sm">{t("people.families.add")}</Button>
				)}
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>
					{t(family ? "people.families.editTitle" : "people.families.add")}
				</DialogTitle>
				<DialogDescription>
					{t(family ? "people.families.editBody" : "people.families.addBody")}
				</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id={`${prefix}-name`}
						label={t("people.families.name")}
						error={fieldError(errors.name?.message)}
						required
					>
						<Input {...register("name")} />
					</Field>
					<fieldset
						className="flex flex-col gap-2"
						aria-describedby={
							errors.student_ids ? `${prefix}-students-error` : undefined
						}
					>
						<legend className="text-sm font-medium">
							{t("people.families.students")}
						</legend>
						{chosen.length === 0 ? (
							<p className="text-sm text-muted-foreground">
								{t("people.families.noStudents")}
							</p>
						) : (
							<ul className="flex flex-col gap-2">
								{chosen.map((s) => (
									<li
										key={s.id}
										className="flex items-center justify-between gap-2 text-sm"
									>
										<span>{s.full_name}</span>
										<Button
											type="button"
											size="sm"
											variant="outline"
											aria-label={t("people.families.removeStudent", {
												name: s.full_name,
											})}
											onClick={() =>
												choose(chosen.filter((c) => c.id !== s.id))
											}
										>
											{t("people.families.remove")}
										</Button>
									</li>
								))}
							</ul>
						)}
						<Field
							id={`${prefix}-find`}
							label={t("people.families.findStudent")}
						>
							<Input
								type="search"
								value={query}
								onChange={(e) => setQuery(e.target.value)}
							/>
						</Field>
						{searching ? (
							<ul className="flex flex-col gap-2">
								{addable.map((row) => (
									<li
										key={row.id}
										className="flex items-center justify-between gap-2 text-sm"
									>
										<span>{row.user.full_name}</span>
										<Button
											type="button"
											size="sm"
											aria-label={t("people.families.addStudent", {
												name: row.user.full_name,
											})}
											onClick={() =>
												choose([
													...chosen,
													{ id: row.id, full_name: row.user.full_name },
												])
											}
										>
											{t("people.families.addOne")}
										</Button>
									</li>
								))}
							</ul>
						) : null}
						{errors.student_ids ? (
							<FormError id={`${prefix}-students-error`}>
								{fieldError(errors.student_ids.message)}
							</FormError>
						) : null}
					</fieldset>
					{family?.payer_needs_choosing ? (
						<Alert variant="destructive">
							<AlertDescription>
								{t("people.families.chooseNewPayer")}
							</AlertDescription>
						</Alert>
					) : null}
					<Field
						id={`${prefix}-payer`}
						label={t("people.families.payer")}
						error={fieldError(errors.payer_id?.message)}
						required
					>
						<Select disabled={!payers} {...register("payer_id")}>
							<option value="">—</option>
							<PayerOptions payers={payers ?? []} />
						</Select>
					</Field>
					<Field
						id={`${prefix}-notes`}
						label={t("people.families.notes")}
						error={fieldError(errors.notes?.message)}
					>
						<Textarea rows={3} {...register("notes")} />
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<Button type="submit" disabled={isSubmitting}>
							{t("people.families.save")}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

Create `dashboard/src/features/people/FamiliesList.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { Search, UsersRound } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Pager } from "@/components/Pager";
import { errorText } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	EmptyState,
	Input,
	Select,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import type { ListParams } from "./api";
import { FamilyDialog } from "./FamilyDialog";
import { useFamilies, useUpdateFamily } from "./queries";
import type { Family } from "./schemas";

const PAGE_SIZE = 25;

/** Retire an active family or restore a retired one; its links are kept. */
export function FamilyActiveToggle({ family }: { family: Family }) {
	const { t } = useTranslation();
	const update = useUpdateFamily();
	const retiring = family.is_active;
	return (
		<Button
			size="sm"
			variant="outline"
			disabled={update.isPending}
			aria-label={t(
				retiring ? "people.families.retireName" : "people.families.restoreName",
				{ name: family.name },
			)}
			onClick={() =>
				update.mutate(
					{ id: family.id, body: { is_active: !retiring } },
					{
						onSuccess: () =>
							toast({
								description: t(
									retiring
										? "people.families.retiredDone"
										: "people.families.restoredDone",
								),
								variant: "success",
							}),
						onError: (error) =>
							toast({
								description: errorText(error, t),
								variant: "destructive",
							}),
					},
				)
			}
		>
			{t(retiring ? "people.families.retire" : "people.families.restore")}
		</Button>
	);
}

/** The family's payer, with a warning when they no longer qualify (F-4). */
export function FamilyPayerCell({ family }: { family: Family }) {
	const { t } = useTranslation();
	return (
		<span className="flex flex-wrap items-center gap-2">
			<span>{family.payer.full_name}</span>
			{family.payer_needs_choosing ? (
				<StatusChip tone="warning">
					{t("people.families.chooseNewPayer")}
				</StatusChip>
			) : null}
		</span>
	);
}

/** People → Families (Plan 11 §6): search, an active filter, Add, and per
 * family its students, payer, status, Edit and Retire or Restore. */
export function FamiliesList() {
	const { t } = useTranslation();
	const [params, setParams] = useState<ListParams>({ page: 1 });
	const { data, isPending, isError } = useFamilies(params);
	const rows = data?.results ?? [];
	const page = Number(params.page ?? 1);
	const pages = Math.max(1, Math.ceil((data?.count ?? 0) / PAGE_SIZE));
	const set = (patch: ListParams) =>
		setParams({ ...params, page: 1, ...patch });

	return (
		<div className="flex flex-col gap-4">
			<div className="flex flex-wrap items-end gap-3">
				<div className="relative min-w-48 flex-1">
					<label htmlFor="families-search" className="sr-only">
						{t("people.families.search")}
					</label>
					<Search className="pointer-events-none absolute start-3 top-3.5 size-4 text-muted-foreground" />
					<Input
						id="families-search"
						type="search"
						className="ps-9"
						placeholder={t("people.families.search")}
						value={String(params.search ?? "")}
						onChange={(e) => set({ search: e.target.value })}
					/>
				</div>
				<Select
					aria-label={t("people.families.columns.status")}
					className="w-auto"
					value={String(params.active ?? "")}
					onChange={(e) => set({ active: e.target.value })}
				>
					<option value="">{t("people.families.anyStatus")}</option>
					<option value="true">{t("people.families.status.active")}</option>
					<option value="false">{t("people.families.status.retired")}</option>
				</Select>
				<FamilyDialog />
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("people.families.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : rows.length === 0 ? (
				<Card>
					<CardContent>
						<EmptyState icon={UsersRound} title={t("people.families.empty")} />
					</CardContent>
				</Card>
			) : (
				<div className="overflow-x-auto rounded-lg border border-border">
					<table className="w-full text-sm">
						<thead className="bg-secondary text-start text-muted-foreground">
							<tr>
								{(["name", "students", "payer", "status"] as const).map(
									(key) => (
										<th
											key={key}
											scope="col"
											className="p-3 text-start font-medium"
										>
											{t(`people.families.columns.${key}`)}
										</th>
									),
								)}
								<th scope="col" className="p-3">
									<span className="sr-only">
										{t("people.families.columns.actions")}
									</span>
								</th>
							</tr>
						</thead>
						<tbody>
							{rows.map((family) => (
								<tr key={family.id} className="border-t border-border">
									<td className="p-3">
										<Link
											to="/people/families/$familyId"
											params={{ familyId: String(family.id) }}
											className="font-medium text-primary-text underline-offset-4 hover:underline"
										>
											{family.name}
										</Link>
									</td>
									<td className="p-3">
										<ul className="flex flex-wrap gap-1">
											{family.students.map((s) => (
												<li
													key={s.id}
													className="rounded-full bg-secondary px-2 py-0.5 text-xs font-medium text-secondary-foreground"
												>
													{s.full_name}
												</li>
											))}
										</ul>
									</td>
									<td className="p-3">
										<FamilyPayerCell family={family} />
									</td>
									<td className="p-3">
										{t(
											family.is_active
												? "people.families.status.active"
												: "people.families.status.retired",
										)}
									</td>
									<td className="p-3">
										<div className="flex flex-wrap justify-end gap-1">
											<FamilyDialog family={family} />
											<FamilyActiveToggle family={family} />
										</div>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
			<Pager
				page={page}
				pages={pages}
				onChange={(next) => setParams({ ...params, page: next })}
			/>
		</div>
	);
}
```

Create `dashboard/src/features/people/FamilyPage.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { isAxiosError } from "axios";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
import {
	Alert,
	AlertDescription,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Spinner,
} from "@/ui";
import { FamilyActiveToggle, FamilyPayerCell } from "./FamiliesList";
import { FamilyDialog } from "./FamilyDialog";
import { useFamily } from "./queries";

/** One family (Plan 11 §6): the page a student's family chip links to. */
export function FamilyPage({ familyId }: { familyId: string }) {
	const { t } = useTranslation();
	const parsed = Number(familyId);
	const invalid = !Number.isInteger(parsed);
	const {
		data: family,
		isError,
		error,
	} = useFamily(invalid ? undefined : parsed);
	const status = isAxiosError(error) ? error.response?.status : undefined;
	if (invalid || status === 404 || isError) {
		return (
			<Alert variant="destructive">
				<AlertDescription>
					{invalid || status === 404
						? t("people.families.notFound")
						: t("people.families.loadError")}
				</AlertDescription>
			</Alert>
		);
	}
	if (!family) return <Spinner />;
	return (
		<Card>
			<CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 border-b border-border">
				<CardTitle>{family.name}</CardTitle>
				<div className="flex flex-wrap gap-1">
					<FamilyDialog family={family} />
					<FamilyActiveToggle family={family} />
				</div>
			</CardHeader>
			<CardContent>
				<dl className="grid gap-4 sm:grid-cols-2">
					<Fact label={t("people.families.columns.status")}>
						{t(
							family.is_active
								? "people.families.status.active"
								: "people.families.status.retired",
						)}
					</Fact>
					<Fact label={t("people.families.payer")}>
						<FamilyPayerCell family={family} />
					</Fact>
					<Fact label={t("people.families.students")}>
						<ul className="flex flex-col gap-1">
							{family.students.map((s) => (
								<li key={s.id}>
									<Link
										to="/people/students/$personId"
										params={{ personId: String(s.id) }}
										className="text-primary-text underline-offset-4 hover:underline"
									>
										{s.full_name}
									</Link>
								</li>
							))}
						</ul>
					</Fact>
					<Fact label={t("people.families.notes")}>{family.notes || "—"}</Fact>
				</dl>
			</CardContent>
		</Card>
	);
}
```

In `dashboard/src/features/people/index.ts`, replace:

```ts
export { AdminsList } from "./AdminsList";
export * from "./api";
export { GuardiansPanel } from "./GuardiansPanel";
export { ParentForm } from "./ParentForm";
```

with:

```ts
export { AdminsList } from "./AdminsList";
export * from "./api";
export { FamiliesList } from "./FamiliesList";
export { FamilyPage } from "./FamilyPage";
export { GuardiansPanel } from "./GuardiansPanel";
export { ParentForm } from "./ParentForm";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	User,
	Users,
	Wallet,
} from "lucide-react";
```

with:

```ts
	User,
	Users,
	UsersRound,
	Wallet,
} from "lucide-react";
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
	admin("/people/teachers", "nav.teachers", Presentation, "people"),
	admin("/people/admins", "nav.admins", ShieldCheck, "people"),
```

with:

```ts
	admin("/people/students", "nav.students", GraduationCap, "people"),
	admin("/people/parents", "nav.parents", Users, "people"),
	// Plan 11: siblings grouped under one payer.
	admin("/people/families", "nav.families", UsersRound, "people"),
	admin("/people/teachers", "nav.teachers", Presentation, "people"),
	admin("/people/admins", "nav.admins", ShieldCheck, "people"),
```

Create `dashboard/src/routes/_authed/people.families.index.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { FamiliesList } from "@/features/people";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/people/families/")({
	component: function FamiliesRoute() {
		const { t } = useTranslation();
		usePageTitle(t("people.families.title"));
		return (
			<>
				<PageHeader
					title={t("people.families.title")}
					description={t("people.families.subtitle")}
				/>
				<FamiliesList />
			</>
		);
	},
});
```

Create `dashboard/src/routes/_authed/people.families.$familyId.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { FamilyPage } from "@/features/people";
import { PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/people/families/$familyId")({
	component: function FamilyRoute() {
		const { t } = useTranslation();
		const { familyId } = Route.useParams();
		usePageTitle(t("people.families.one"));
		return (
			<>
				<PageHeader title={t("people.families.one")} />
				<FamilyPage familyId={familyId} />
			</>
		);
	},
});
```

Merge into `dashboard/src/locales/en/common.json`:

```json
{
	"nav": { "families": "Families" },
	"people": {
		"families": {
			"title": "Families",
			"subtitle": "Group siblings and name who pays for them.",
			"one": "Family",
			"add": "Add family",
			"addBody": "Choose the students and who pays for them.",
			"edit": "Edit",
			"editName": "Edit {{name}}",
			"editTitle": "Edit family",
			"editBody": "Change the name, the students, the payer or the notes.",
			"name": "Name",
			"students": "Students",
			"noStudents": "No students chosen yet.",
			"findStudent": "Find a student",
			"addOne": "Add",
			"addStudent": "Add {{name}}",
			"remove": "Remove",
			"removeStudent": "Remove {{name}}",
			"payer": "Payer",
			"payerOption": {
				"student": "{{name}} (student)",
				"parent": "{{name}} (parent)"
			},
			"chooseNewPayer": "Choose a new payer",
			"notes": "Notes",
			"save": "Save family",
			"saved": "Family saved.",
			"retire": "Retire",
			"retireName": "Retire {{name}}",
			"restore": "Restore",
			"restoreName": "Restore {{name}}",
			"retiredDone": "Family retired.",
			"restoredDone": "Family restored.",
			"status": { "active": "Active", "retired": "Retired" },
			"anyStatus": "Any status",
			"search": "Search families",
			"empty": "No families yet.",
			"loadError": "Couldn't load the families.",
			"notFound": "This family doesn't exist.",
			"columns": {
				"name": "Name",
				"students": "Students",
				"payer": "Payer",
				"status": "Status",
				"actions": "Actions"
			},
			"errors": {
				"nameRequired": "Enter a name.",
				"nameTooLong": "Keep the name to 120 characters.",
				"studentsRequired": "Choose at least one student.",
				"payerRequired": "Choose who pays."
			}
		}
	}
}
```

Merge into `dashboard/src/locales/ar/common.json`:

```json
{
	"nav": { "families": "العائلات" },
	"people": {
		"families": {
			"title": "العائلات",
			"subtitle": "اجمع الإخوة وحدّد من يدفع عنهم.",
			"one": "العائلة",
			"add": "إضافة عائلة",
			"addBody": "اختر الطلاب ومن يدفع عنهم.",
			"edit": "تعديل",
			"editName": "تعديل {{name}}",
			"editTitle": "تعديل العائلة",
			"editBody": "غيّر الاسم أو الطلاب أو الدافع أو الملاحظات.",
			"name": "الاسم",
			"students": "الطلاب",
			"noStudents": "لم يُختر أي طالب بعد.",
			"findStudent": "ابحث عن طالب",
			"addOne": "إضافة",
			"addStudent": "إضافة {{name}}",
			"remove": "إزالة",
			"removeStudent": "إزالة {{name}}",
			"payer": "الدافع",
			"payerOption": {
				"student": "{{name}} (طالب)",
				"parent": "{{name}} (وليّ أمر)"
			},
			"chooseNewPayer": "اختر دافعًا جديدًا",
			"notes": "ملاحظات",
			"save": "حفظ العائلة",
			"saved": "حُفظت العائلة.",
			"retire": "إيقاف",
			"retireName": "إيقاف {{name}}",
			"restore": "استعادة",
			"restoreName": "استعادة {{name}}",
			"retiredDone": "أُوقفت العائلة.",
			"restoredDone": "استُعيدت العائلة.",
			"status": { "active": "نشطة", "retired": "موقوفة" },
			"anyStatus": "أي حالة",
			"search": "ابحث في العائلات",
			"empty": "لا توجد عائلات بعد.",
			"loadError": "تعذّر تحميل العائلات.",
			"notFound": "هذه العائلة غير موجودة.",
			"columns": {
				"name": "الاسم",
				"students": "الطلاب",
				"payer": "الدافع",
				"status": "الحالة",
				"actions": "إجراءات"
			},
			"errors": {
				"nameRequired": "أدخل اسمًا.",
				"nameTooLong": "اجعل الاسم 120 حرفًا على الأكثر.",
				"studentsRequired": "اختر طالبًا واحدًا على الأقل.",
				"payerRequired": "اختر من يدفع."
			}
		}
	}
}
```

- [ ] **Step 4: Verify**

`vite build` regenerates `src/routeTree.gen.ts` with the two new routes before `tsc` runs.

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 683 tests (10 new); lines 94.3%, branches 88.1%, functions 82.0%.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(people): families admin page, dialogs and family page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dashboard: the students list and form: account type, family chip, filters, bulk family actions

**Files:**
- Create: `dashboard/src/features/people/BulkFamilyDialog.tsx`
- Modify: `dashboard/src/features/people/StudentsList.tsx`, `dashboard/src/features/people/StudentForm.tsx`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/people/StudentsList.test.tsx` (its mocks gain `families` and `familyPayers`, its rows a family; four tests appended), `dashboard/src/features/people/StudentForm.test.tsx` (two tests appended)

**Interfaces:**
- Consumes: Task 7's `useFamilies`, `useFamilyPayers`, `useBulkStudents` (`BulkResult`), `ACCOUNT_TYPES`, `bulkFamilySchema`; Task 8's `PayerOptions` and `people.families.*` keys.
- Produces:
  - students list: an "Account type" column ("Individual", or "Family" with the family's name as a chip linking to `/people/families/$familyId`); filters "Account type" (`account_type`) and "Family" (`family`, retired ones marked), which reach the CSV link; in the bulk bar "Create family" (a dialog: Name and a Payer from the selection and their parents), "Family to add to" (active families, the first by default) with "Add to family", and "Remove from family"; skipped students are reported in a status line, "Skipped, already in another family: …";
  - `<BulkFamilyDialog studentIds create />`;
  - the student form shows "Account type" and, when in one, the family as a link (read-only);
  - locale keys `people.field.account_type`, `people.field.family`, `people.columns.accountType`, `people.accountType.*`, `people.filters.anyAccountType`, `people.filters.anyFamily`, `people.bulk.{createFamily, createFamilyBody, familyToAdd, addToFamily, removeFromFamily, skipped}`.

- [ ] **Step 1: Write the failing tests**

Rows show "Individual" or the family chip (scoped to the row, since family names are also filter options); the two filters reach the list and the CSV link, with a retired family marked; Create family sends the selection, the name and a payer chosen among the selection's payer choices, and reports who was skipped; a 400 on `ids` keeps the dialog open with the reason; Add to family offers active families only and sends the first by default; Remove from family sends the selection. The form shows the account type and links the family.

In `dashboard/src/features/people/StudentsList.test.tsx`, replace:

```tsx
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { STUDENT_TAGS } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { StudentsList } from "./StudentsList";
import type { Person, StudentProfile } from "./schemas";

vi.mock("./api", async (orig) => {
```

with:

```tsx
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { familyRow, STUDENT_TAGS } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { StudentsList } from "./StudentsList";
import type { FamilyRef, Person, StudentProfile } from "./schemas";

vi.mock("./api", async (orig) => {
```

In `dashboard/src/features/people/StudentsList.test.tsx`, replace:

```tsx
			bulkStudents: vi.fn(),
			tags: vi.fn(),
		},
	};
```

with:

```tsx
			bulkStudents: vi.fn(),
			tags: vi.fn(),
			families: vi.fn(),
			familyPayers: vi.fn(),
		},
	};
```

In `dashboard/src/features/people/StudentsList.test.tsx`, replace:

```tsx
	email: string | null,
	tags: StudentProfile["tags"] = [],
): Person<StudentProfile> => ({
	id,
```

with:

```tsx
	email: string | null,
	tags: StudentProfile["tags"] = [],
	family: FamilyRef | null = null,
): Person<StudentProfile> => ({
	id,
```

In `dashboard/src/features/people/StudentsList.test.tsx`, replace:

```tsx
		age_group: null,
		tags,
		account_type: "individual",
		family: null,
	},
});
```

with:

```tsx
		age_group: null,
		tags,
		account_type: family ? "family" : "individual",
		family,
	},
});
```

In `dashboard/src/features/people/StudentsList.test.tsx`, replace:

```tsx
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([
				row(1, "Yusuf", "y@x.test", [STUDENT_TAGS[1]]),
				row(2, "Aisha", null),
			]),
		);
		vi.mocked(peopleApi.tags).mockResolvedValue(STUDENT_TAGS);
	});
```

with:

```tsx
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([
				row(1, "Yusuf", "y@x.test", [STUDENT_TAGS[1]], {
					id: 4,
					name: "Omar family",
				}),
				row(2, "Aisha", null),
			]),
		);
		vi.mocked(peopleApi.tags).mockResolvedValue(STUDENT_TAGS);
		vi.mocked(peopleApi.families).mockResolvedValue({
			count: 2,
			next: null,
			previous: null,
			results: [
				familyRow({ id: 5, name: "Huda family", is_active: false }),
				familyRow({ id: 4, name: "Omar family" }),
			],
		});
		vi.mocked(peopleApi.familyPayers).mockResolvedValue([
			{ id: 1, full_name: "Yusuf", role: "student" },
			{ id: 31, full_name: "Omar", role: "parent" },
		]);
	});
```

In `dashboard/src/features/people/StudentsList.test.tsx`, replace:

```tsx
		).toBeInTheDocument();
	});
});
```

with:

```tsx
		).toBeInTheDocument();
	});

	it("shows each row's account type with a family chip, and filters by both", async () => {
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />, {
			extraPaths: ["/people/families/$familyId"],
		});
		const yusuf = await screen.findByRole("row", { name: /Yusuf/ });
		expect(
			within(yusuf).getByRole("link", { name: "Omar family" }),
		).toHaveAttribute("href", "/people/families/4");
		const aisha = screen.getByRole("row", { name: /Aisha/ });
		expect(within(aisha).getByText("Individual")).toBeInTheDocument();
		const family = screen.getByRole("combobox", { name: "Family" });
		await within(family).findByRole("option", { name: "Omar family" });
		expect(
			within(family).getByRole("option", { name: "Huda family (Retired)" }),
		).toBeInTheDocument();
		await user.selectOptions(
			screen.getByRole("combobox", { name: "Account type" }),
			"family",
		);
		await user.selectOptions(family, "4");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				account_type: "family",
				family: "4",
				page: 1,
			}),
		);
		const csv = screen.getByRole("link", { name: "Export CSV" });
		expect(csv.getAttribute("href")).toContain("family=4");
		expect(csv.getAttribute("href")).toContain("account_type=family");
	});

	it("creates a family from the selection and reports who was skipped", async () => {
		vi.mocked(peopleApi.bulkStudents).mockResolvedValue({
			updated: 1,
			skipped: [{ id: 2, full_name: "Aisha", reason: "in_another_family" }],
		});
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		await screen.findByText("Aisha");
		await user.click(screen.getByLabelText("Select Yusuf"));
		await user.click(screen.getByLabelText("Select Aisha"));
		const bar = screen.getByRole("region", { name: "2 selected" });
		await user.click(
			within(bar).getByRole("button", { name: "Create family" }),
		);
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Name/), "Omar family");
		const payer = within(dialog).getByLabelText(/^Payer/);
		await within(payer).findByRole("option", { name: "Omar (parent)" });
		expect(peopleApi.familyPayers).toHaveBeenCalledWith([1, 2]);
		await user.selectOptions(payer, "31");
		await user.click(
			within(dialog).getByRole("button", { name: "Save family" }),
		);
		await waitFor(() =>
			expect(peopleApi.bulkStudents).toHaveBeenCalledWith({
				ids: [1, 2],
				action: "create_family",
				name: "Omar family",
				payer_id: 31,
			}),
		);
		expect(
			await screen.findByText("Skipped, already in another family: Aisha"),
		).toBeInTheDocument();
		expect(screen.getByText("1 updated.")).toBeInTheDocument();
	});

	it("keeps the dialog open with the reason when no one can be linked", async () => {
		vi.mocked(peopleApi.bulkStudents).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { ids: ["Every selected student is already in a family."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		await screen.findByText("Aisha");
		await user.click(screen.getByLabelText("Select Yusuf"));
		await user.click(screen.getByRole("button", { name: "Create family" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(within(dialog).getByLabelText(/^Name/), "F");
		const payer = within(dialog).getByLabelText(/^Payer/);
		await within(payer).findByRole("option", { name: "Yusuf (student)" });
		await user.selectOptions(payer, "1");
		await user.click(
			within(dialog).getByRole("button", { name: "Save family" }),
		);
		expect(
			await within(dialog).findByText(
				"Every selected student is already in a family.",
			),
		).toBeInTheDocument();
	});

	it("adds the selection to an active family and removes it from one", async () => {
		vi.mocked(peopleApi.bulkStudents).mockResolvedValue({
			updated: 1,
			skipped: [],
		});
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		await screen.findByText("Aisha");
		await user.click(screen.getByLabelText("Select Aisha"));
		const bar = screen.getByRole("region", { name: "1 selected" });
		const pick = within(bar).getByRole("combobox", {
			name: "Family to add to",
		});
		await waitFor(() => expect(pick).toHaveValue("4")); // retired ones not offered
		expect(within(pick).getAllByRole("option")).toHaveLength(1);
		await user.click(
			within(bar).getByRole("button", { name: "Add to family" }),
		);
		await waitFor(() =>
			expect(peopleApi.bulkStudents).toHaveBeenCalledWith({
				ids: [2],
				action: "add_to_family",
				family_id: 4,
			}),
		);
		expect(screen.queryByText(/Skipped/)).toBeNull();
		await user.click(screen.getByLabelText("Select Yusuf"));
		await user.click(
			screen.getByRole("button", { name: "Remove from family" }),
		);
		await waitFor(() =>
			expect(peopleApi.bulkStudents).toHaveBeenLastCalledWith({
				ids: [1],
				action: "remove_from_family",
			}),
		);
	});
});
```

In `dashboard/src/features/people/StudentForm.test.tsx`, replace:

```tsx
		).toBeInTheDocument();
	});
});
```

with:

```tsx
		).toBeInTheDocument();
	});

	it("shows the account type, and the family read-only with a link", async () => {
		vi.mocked(peopleApi.get).mockResolvedValue({
			...saved,
			profile: {
				...saved.profile,
				account_type: "family",
				family: { id: 4, name: "Omar family" },
			},
		});
		renderWithRouter(<StudentForm personId="5" />, {
			extraPaths: ["/people/families/$familyId"],
		});
		expect(
			await screen.findByRole("link", { name: "Omar family" }),
		).toHaveAttribute("href", "/people/families/4");
		expect(screen.getByText("Account type").nextSibling).toHaveTextContent(
			"Family",
		);
	});

	it("says an individual student is in no family", async () => {
		vi.mocked(peopleApi.get).mockResolvedValue(saved);
		renderWithRouter(<StudentForm personId="5" />);
		expect(await screen.findByText("Individual")).toBeInTheDocument();
		expect(screen.queryByText("Family")).toBeNull();
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `npx pnpm@10 exec vitest run src/features/people/StudentsList.test.tsx src/features/people/StudentForm.test.tsx`

Expected: FAIL — the six new tests (no family link in the rows, no "Create family" button, no "Family to add to" select, no "Individual"); the existing ones still pass.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/people/BulkFamilyDialog.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors } from "@/lib/form-errors";
import {
	Alert,
	AlertDescription,
	Button,
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogTitle,
	DialogTrigger,
	Field,
	Input,
	Select,
} from "@/ui";
import { PayerOptions } from "./FamilyDialog";
import { useFamilyPayers } from "./queries";
import { type BulkFamilyValues, bulkFamilySchema } from "./schemas";

/** The bulk bar's Create family (Plan 11 §4.3): a name, and a payer from the
 * selected students and their active parents. `create` runs the bulk action
 * and rejects with the server's error. */
export function BulkFamilyDialog({
	studentIds,
	create,
}: {
	studentIds: readonly number[];
	create: (values: { name: string; payer_id: number }) => Promise<unknown>;
}) {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	const fieldError = useFieldError();
	const { data: payers } = useFamilyPayers(open ? studentIds : []);
	const {
		register,
		handleSubmit,
		reset,
		setError,
		setValue,
		getValues,
		formState: { errors, isSubmitting },
	} = useForm<BulkFamilyValues>({
		resolver: zodResolver(bulkFamilySchema),
		defaultValues: { name: "", payer_id: "" },
	});

	useEffect(() => {
		if (!open || !payers) return;
		const current = getValues("payer_id");
		if (current && !payers.some((p) => String(p.id) === current)) {
			setValue("payer_id", "");
		}
	}, [open, payers, getValues, setValue]);

	async function onSubmit(values: BulkFamilyValues) {
		try {
			await create({
				name: values.name.trim(),
				payer_id: Number(values.payer_id),
			});
			setOpen(false);
		} catch (error) {
			const parsed = applyServerErrors(error, setError);
			if (parsed.fieldErrors.ids) {
				setError("root.server", { message: parsed.fieldErrors.ids });
			}
		}
	}

	return (
		<Dialog
			open={open}
			onOpenChange={(next) => {
				if (next) reset({ name: "", payer_id: "" });
				setOpen(next);
			}}
		>
			<DialogTrigger asChild>
				<Button size="sm" variant="outline">
					{t("people.bulk.createFamily")}
				</Button>
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>{t("people.bulk.createFamily")}</DialogTitle>
				<DialogDescription>
					{t("people.bulk.createFamilyBody")}
				</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id="bulk-family-name"
						label={t("people.families.name")}
						error={fieldError(errors.name?.message)}
						required
					>
						<Input {...register("name")} />
					</Field>
					<Field
						id="bulk-family-payer"
						label={t("people.families.payer")}
						error={fieldError(errors.payer_id?.message)}
						required
					>
						<Select disabled={!payers} {...register("payer_id")}>
							<option value="">—</option>
							<PayerOptions payers={payers ?? []} />
						</Select>
					</Field>
					{errors.root?.server ? (
						<Alert variant="destructive">
							<AlertDescription>
								{fieldError(errors.root.server.message)}
							</AlertDescription>
						</Alert>
					) : null}
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<Button type="submit" disabled={isSubmitting}>
							{t("people.families.save")}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

In `dashboard/src/features/people/StudentsList.tsx`, replace:

```tsx
import { countryOptions } from "@/lib/countries";
import { errorText } from "@/lib/form-errors";
import { Button, Select, toast } from "@/ui";
import { AccountStateChip } from "./AccountActions";
import type { BulkBody, ListParams } from "./api";
import { type Column, PeopleList } from "./PeopleList";
import { useBulkStudents, useTags } from "./queries";
import {
	AGE_FILTERS,
	type BulkAction,
	NATIONALITIES,
	STUDENT_STATUSES,
	type StudentProfile,
```

with:

```tsx
import { countryOptions } from "@/lib/countries";
import { errorText } from "@/lib/form-errors";
import { Alert, AlertDescription, Button, Select, toast } from "@/ui";
import { AccountStateChip } from "./AccountActions";
import type { BulkBody, ListParams } from "./api";
import { BulkFamilyDialog } from "./BulkFamilyDialog";
import { type Column, PeopleList } from "./PeopleList";
import { useBulkStudents, useFamilies, useTags } from "./queries";
import {
	ACCOUNT_TYPES,
	AGE_FILTERS,
	type BulkAction,
	type BulkResult,
	type Family,
	NATIONALITIES,
	type SkippedStudent,
	STUDENT_STATUSES,
	type StudentProfile,
```

In `dashboard/src/features/people/StudentsList.tsx`, replace:

```tsx
const TABS = ["all", ...STUDENT_STATUSES] as const;

export function StudentsList() {
	const { t, i18n } = useTranslation();
```

with:

```tsx
const TABS = ["all", ...STUDENT_STATUSES] as const;

/** A student's account type; a family's name is a chip linking to it. */
function AccountTypeCell({ profile }: { profile: StudentProfile }) {
	const { t } = useTranslation();
	if (!profile.family) return <>{t("people.accountType.individual")}</>;
	return (
		<span className="flex flex-wrap items-center gap-1">
			<span>{t("people.accountType.family")}</span>
			<Link
				to="/people/families/$familyId"
				params={{ familyId: String(profile.family.id) }}
				className="rounded-full bg-secondary px-2 py-0.5 text-xs font-medium text-secondary-foreground underline-offset-4 hover:underline"
			>
				{profile.family.name}
			</Link>
		</span>
	);
}

/** Families as `<option>`s, retired ones marked. */
function FamilyOptions({ families }: { families: readonly Family[] }) {
	const { t } = useTranslation();
	return (
		<>
			{families.map((family) => (
				<option key={family.id} value={String(family.id)}>
					{family.is_active
						? family.name
						: `${family.name} (${t("people.families.status.retired")})`}
				</option>
			))}
		</>
	);
}

export function StudentsList() {
	const { t, i18n } = useTranslation();
```

In `dashboard/src/features/people/StudentsList.tsx`, replace:

```tsx
	const [bulkStatus, setBulkStatus] = useState<StudentStatus>("active");
	const [bulkTag, setBulkTag] = useState<number>();
	const bulk = useBulkStudents();
	const { data: tags = [] } = useTags("student");
	// The bulk bar's tag: the one chosen, else the first active tag.
	const tagId = bulkTag ?? tags.find((tag) => tag.is_active)?.id;
```

with:

```tsx
	const [bulkStatus, setBulkStatus] = useState<StudentStatus>("active");
	const [bulkTag, setBulkTag] = useState<number>();
	const [bulkFamily, setBulkFamily] = useState<number>();
	const [skipped, setSkipped] = useState<SkippedStudent[]>([]);
	const bulk = useBulkStudents();
	const { data: tags = [] } = useTags("student");
	// Up to the API's 100 a page, by name: the filter and the bulk bar's
	// Add to family pick from these.
	const { data: familyPage } = useFamilies({ page_size: 100 });
	const families = familyPage?.results ?? [];
	const activeFamilies = families.filter((family) => family.is_active);
	const familyId = bulkFamily ?? activeFamilies[0]?.id;
	// The bulk bar's tag: the one chosen, else the first active tag.
	const tagId = bulkTag ?? tags.find((tag) => tag.is_active)?.id;
```

In `dashboard/src/features/people/StudentsList.tsx`, replace:

```tsx
		},
		{
			key: "account",
			header: t("people.columns.account"),
```

with:

```tsx
		},
		{
			key: "account_type",
			header: t("people.columns.accountType"),
			cell: (p) => <AccountTypeCell profile={p.profile} />,
		},
		{
			key: "account",
			header: t("people.columns.account"),
```

In `dashboard/src/features/people/StudentsList.tsx`, replace:

```tsx
	];

	function runBulk(action: BulkAction) {
		const body: BulkBody = { ids: selected, action };
		if (action === "set_status") body.status = bulkStatus;
		if (action === "add_tag" || action === "remove_tag") body.tag_id = tagId;
		bulk.mutate(body, {
			onSuccess: ({ updated }) => {
				setSelected([]);
				toast({
					description: t("people.bulk.done", { count: updated }),
					variant: "success",
				});
			},
			onError: (error) =>
				toast({ description: errorText(error, t), variant: "destructive" }),
		});
	}
```

with:

```tsx
	];

	function done({ updated, skipped: left = [] }: BulkResult) {
		setSelected([]);
		setSkipped(left);
		toast({
			description: t("people.bulk.done", { count: updated }),
			variant: "success",
		});
	}

	function runBulk(action: BulkAction) {
		const body: BulkBody = { ids: selected, action };
		if (action === "set_status") body.status = bulkStatus;
		if (action === "add_tag" || action === "remove_tag") body.tag_id = tagId;
		if (action === "add_to_family") body.family_id = familyId;
		bulk.mutate(body, {
			onSuccess: done,
			onError: (error) =>
				toast({ description: errorText(error, t), variant: "destructive" }),
		});
	}

	async function createFamily(values: { name: string; payer_id: number }) {
		done(
			await bulk.mutateAsync({
				ids: selected,
				action: "create_family",
				...values,
			}),
		);
	}
```

In `dashboard/src/features/people/StudentsList.tsx`, replace:

```tsx
						</>
					)}
				</section>
			) : null}
			<PeopleList<StudentProfile>
```

with:

```tsx
						</>
					)}
					<BulkFamilyDialog studentIds={selected} create={createFamily} />
					{familyId === undefined ? null : (
						<>
							<Select
								aria-label={t("people.bulk.familyToAdd")}
								className="w-auto"
								value={String(familyId)}
								onChange={(e) => setBulkFamily(Number(e.target.value))}
							>
								<FamilyOptions families={activeFamilies} />
							</Select>
							<Button
								size="sm"
								variant="outline"
								onClick={() => runBulk("add_to_family")}
							>
								{t("people.bulk.addToFamily")}
							</Button>
						</>
					)}
					<Button
						size="sm"
						variant="outline"
						onClick={() => runBulk("remove_from_family")}
					>
						{t("people.bulk.removeFromFamily")}
					</Button>
				</section>
			) : null}
			{skipped.length > 0 ? (
				<Alert>
					<AlertDescription role="status">
						{t("people.bulk.skipped", {
							names: skipped.map((s) => s.full_name).join(", "),
						})}
					</AlertDescription>
				</Alert>
			) : null}
			<PeopleList<StudentProfile>
```

In `dashboard/src/features/people/StudentsList.tsx`, replace:

```tsx
							))}
						</Select>
					</>
				}
```

with:

```tsx
							))}
						</Select>
						<Select
							aria-label={t("people.field.account_type")}
							className="w-auto"
							value={String(params.account_type ?? "")}
							onChange={(e) => update({ account_type: e.target.value })}
						>
							<option value="">{t("people.filters.anyAccountType")}</option>
							{ACCOUNT_TYPES.map((kind) => (
								<option key={kind} value={kind}>
									{t(`people.accountType.${kind}`)}
								</option>
							))}
						</Select>
						<Select
							aria-label={t("people.field.family")}
							className="w-auto"
							value={String(params.family ?? "")}
							onChange={(e) => update({ family: e.target.value })}
						>
							<option value="">{t("people.filters.anyFamily")}</option>
							<FamilyOptions families={families} />
						</Select>
					</>
				}
```

In `dashboard/src/features/people/StudentForm.tsx`, replace:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useNavigate } from "@tanstack/react-router";
import { isAxiosError } from "axios";
import { FormProvider, useController, useForm } from "react-hook-form";
```

with:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { Link, useNavigate } from "@tanstack/react-router";
import { isAxiosError } from "axios";
import { FormProvider, useController, useForm } from "react-hook-form";
```

In `dashboard/src/features/people/StudentForm.tsx`, replace:

```tsx
						</Field>
					</div>
					{person?.profile.age_group ? (
						<dl>
```

with:

```tsx
						</Field>
					</div>
					{person ? (
						<dl className="grid gap-4 sm:grid-cols-2">
							<Fact label={t("people.field.account_type")}>
								{t(`people.accountType.${person.profile.account_type}`)}
							</Fact>
							{person.profile.family ? (
								<Fact label={t("people.field.family")}>
									<Link
										to="/people/families/$familyId"
										params={{ familyId: String(person.profile.family.id) }}
										className="text-primary-text underline-offset-4 hover:underline"
									>
										{person.profile.family.name}
									</Link>
								</Fact>
							) : null}
						</dl>
					) : null}
					{person?.profile.age_group ? (
						<dl>
```

Merge into `dashboard/src/locales/en/common.json`:

```json
{
	"people": {
		"field": { "account_type": "Account type", "family": "Family" },
		"columns": { "accountType": "Account type" },
		"accountType": { "individual": "Individual", "family": "Family" },
		"filters": {
			"anyAccountType": "Any account type",
			"anyFamily": "Any family"
		},
		"bulk": {
			"createFamily": "Create family",
			"createFamilyBody": "The selected students become one family. Anyone already in another family is skipped.",
			"familyToAdd": "Family to add to",
			"addToFamily": "Add to family",
			"removeFromFamily": "Remove from family",
			"skipped": "Skipped, already in another family: {{names}}"
		}
	}
}
```

Merge into `dashboard/src/locales/ar/common.json`:

```json
{
	"people": {
		"field": { "account_type": "نوع الحساب", "family": "العائلة" },
		"columns": { "accountType": "نوع الحساب" },
		"accountType": { "individual": "فردي", "family": "عائلي" },
		"filters": {
			"anyAccountType": "أي نوع حساب",
			"anyFamily": "أي عائلة"
		},
		"bulk": {
			"createFamily": "إنشاء عائلة",
			"createFamilyBody": "يصبح الطلاب المحددون عائلة واحدة، ويُتخطّى من هو في عائلة أخرى.",
			"familyToAdd": "العائلة المراد الإضافة إليها",
			"addToFamily": "إضافة إلى عائلة",
			"removeFromFamily": "إزالة من العائلة",
			"skipped": "تُخطّي، لأنهم في عائلة أخرى: {{names}}"
		}
	}
}
```

- [ ] **Step 4: Verify**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 689 tests (6 new); lines 94.4%, branches 88.1%, functions 82.1%.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(people): account type, family filters and bulk family actions on students

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dashboard: "Family payer" on the invoice form; the family on the profile card

**Files:**
- Modify: `dashboard/src/features/billing/schemas.ts`, `dashboard/src/features/identity/components/MyProfileCard.tsx`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/billing/InvoiceForm.test.tsx`, `dashboard/src/features/identity/components/MyProfileCard.test.tsx` (one test appended to each)

**Interfaces:**
- Consumes: Task 5's `relation: "family"` on `GET billing/payers/`; Task 3's `profile.family` in `me/`; Task 9's `people.field.family`.
- Produces: `Payers.choices[].relation` is `"family" | "guardian" | "student"`; the invoice form labels the family payer "{{name}} (Family payer)" (`billing.form.payerOption.family`), and it is preselected because the server lists it first as the default; `MyProfileCard` shows "Family" with the family's name on a student's own card and on each child's row of a parent's ("—" when none).

- [ ] **Step 1: Write the failing tests**

In `dashboard/src/features/billing/InvoiceForm.test.tsx`, replace:

```tsx
		}
	});
});
```

with:

```tsx
		}
	});

	it("lists the family payer first as the family payer, and defaults to them", async () => {
		vi.mocked(billingApi.payers).mockResolvedValue({
			default: 12,
			choices: [
				{ id: 12, full_name: "Aisha", relation: "family" },
				{ id: 31, full_name: "Omar", relation: "guardian" },
				{ id: 11, full_name: "Yusuf", relation: "student" },
			],
		});
		const user = userEvent.setup();
		renderWithRouter(<InvoiceForm />);
		await user.selectOptions(await screen.findByLabelText(/^Student/), "11");
		const payer = screen.getByLabelText(/^Billed to/);
		await waitFor(() => expect(payer).toHaveValue("12"));
		expect(
			screen
				.getAllByRole("option")
				.filter((o) => o.parentElement === payer)
				.map((o) => o.textContent),
		).toEqual([
			"—",
			"Aisha (Family payer)",
			"Omar (guardian)",
			"Yusuf (the student)",
		]);
	});
});
```

In `dashboard/src/features/identity/components/MyProfileCard.test.tsx`, replace:

```tsx
		expect(screen.getByRole("listitem")).toHaveTextContent("Patient");
	});
});
```

with:

```tsx
		expect(screen.getByRole("listitem")).toHaveTextContent("Patient");
	});

	it("shows a student their family and a parent each child's", () => {
		const family = { id: 4, name: "Omar family" };
		const { unmount } = render(
			<MyProfileCard me={{ ...base, profile: { status: "active", family } }} />,
		);
		expect(screen.getByText("Family").nextSibling).toHaveTextContent(
			"Omar family",
		);
		unmount();
		render(
			<MyProfileCard
				me={{
					...base,
					role: "parent",
					profiles: ["parent"],
					profile: { has_whatsapp: false },
					children: [
						{
							id: 9,
							full_name: "Yusuf",
							student_profile_id: 3,
							profile: { status: "active", family, tags: [] },
						},
						{
							id: 10,
							full_name: "Zaid",
							student_profile_id: 4,
							profile: { status: "trial", family: null, tags: [] },
						},
					],
				}}
			/>,
		);
		const yusuf = screen.getByRole("listitem", { name: "Yusuf" });
		expect(within(yusuf).getByText("Omar family")).toBeInTheDocument();
		const zaid = screen.getByRole("listitem", { name: "Zaid" });
		expect(within(zaid).getByText("Family").nextSibling).toHaveTextContent("—");
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `npx pnpm@10 exec vitest run src/features/billing/InvoiceForm.test.tsx src/features/identity/components/MyProfileCard.test.tsx`

Expected: FAIL — 2 failed: the option reads `Aisha (billing.form.payerOption.family)` instead of `Aisha (Family payer)`, and there is no "Family" row on the card.

- [ ] **Step 3: Implement**

In `dashboard/src/features/billing/schemas.ts`, replace:

```ts
export interface Payers {
	default: number;
	choices: (Person & { relation: "guardian" | "student" })[];
}
```

with:

```ts
export interface Payers {
	default: number;
	/** `family`: the student's family payer (Plan 11), listed first. */
	choices: (Person & { relation: "family" | "guardian" | "student" })[];
}
```

In `dashboard/src/features/identity/components/MyProfileCard.tsx`, replace:

```tsx
const FIELDS: Record<string, readonly string[]> = {
	student: ["status", "gender", "date_of_birth", "country", "age_group", "xp"],
	teacher: ["gender", "default_meeting_url", "pay_currency"],
	parent: ["has_whatsapp"],
```

with:

```tsx
const FIELDS: Record<string, readonly string[]> = {
	student: [
		"status",
		"gender",
		"date_of_birth",
		"country",
		"age_group",
		"xp",
		"family",
	],
	teacher: ["gender", "default_meeting_url", "pay_currency"],
	parent: ["has_whatsapp"],
```

In `dashboard/src/features/identity/components/MyProfileCard.tsx`, replace:

```tsx
		if (field === "age_group") return t(`people.ageGroup.${value}`);
		if (field === "country") return regions.of(String(value)) ?? String(value);
		return String(value);
	};
```

with:

```tsx
		if (field === "age_group") return t(`people.ageGroup.${value}`);
		if (field === "country") return regions.of(String(value)) ?? String(value);
		// Plan 11: a family is `{id, name}`; its name is what the person reads.
		if (field === "family") return (value as { name: string }).name;
		return String(value);
	};
```

In `dashboard/src/features/identity/components/MyProfileCard.tsx`, replace:

```tsx
			</div>
			<dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
				{["age_group", "xp"].map((field) => (
					<div key={field} className="contents">
						<dt className="text-muted-foreground">
```

with:

```tsx
			</div>
			<dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
				{["age_group", "xp", "family"].map((field) => (
					<div key={field} className="contents">
						<dt className="text-muted-foreground">
```

Merge into `dashboard/src/locales/en/common.json`:

```json
{ "billing": { "form": { "payerOption": { "family": "{{name}} (Family payer)" } } } }
```

Merge into `dashboard/src/locales/ar/common.json`:

```json
{ "billing": { "form": { "payerOption": { "family": "{{name}} (دافع العائلة)" } } } }
```

- [ ] **Step 4: Verify**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vite build && npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 691 tests (2 new); lines 94.4%, branches 88.1%, functions 82.1%.

- [ ] **Step 5: Commit**

```bash
git -C dashboard add src
git -C dashboard commit -m "feat(billing): label the family payer; show the family on the profile card

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: End-to-end through Caddy: a family with a parent paying, and a new invoice that bills them; STATE.md

**Files:**
- Create: `dashboard/e2e/families.spec.ts`
- Modify: `STATE.md` (meta), submodule pointers (meta, after merge)

**Interfaces:**
- Consumes: Tasks 1 to 10; `e2e/fixtures.ts`'s `login`, `expectLoggedIn`, `DEMO_URL`, `DEMO_ADMIN`.
- Produces: `e2e/families.spec.ts` (spec §8's journey).
- CI: no change. The `e2e` job already migrates, runs `seed_dev` (which now seeds the Omar family) and serves Django, the Vite preview and the marketing site behind `caddy/Caddyfile.e2e`.

- [ ] **Step 1: Write the journey**

The admin creates a parent and two students with stamped names, and links the parent to the younger student only (so, without a family, an invoice for the elder would default to the elder). In People → Families they add a family of the two students with the parent as payer, and find its row. The students list shows the elder's family chip. A new invoice for the elder preselects "‹parent› (Family payer)".

Create `dashboard/e2e/families.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";

// Plan 11 spec §8: an admin makes a family of two students with a parent as
// its payer, and a new invoice for one of them preselects that parent as the
// family payer. The parent is linked to the other student only, so without
// the family the invoice would default to the student. Names are stamped,
// so a second run on the same database finds only its own.
test("an admin makes a family with a parent paying, and a new invoice bills that parent", async ({
	page,
}) => {
	const stamp = Date.now();
	const parent = `E2E Payer ${stamp}`;
	const elder = `E2E Elder ${stamp}`;
	const younger = `E2E Younger ${stamp}`;
	const family = `E2E Family ${stamp}`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// A parent, and two students; the parent is linked to the younger only
	await page.goto(`${DEMO_URL}/app/people/parents/new`);
	await page.getByLabel(/^full name/i).fill(parent);
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/parents\/\d+$/);
	for (const name of [elder, younger]) {
		await page.goto(`${DEMO_URL}/app/people/students/new`);
		await page.getByLabel(/^full name/i).fill(name);
		await page.getByRole("button", { name: "Save", exact: true }).click();
		await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);
	}
	await page.getByLabel("Find a parent").fill(parent);
	await page
		.getByRole("button", { name: `Link ${parent}`, exact: true })
		.click();
	await expect(
		page.getByRole("button", { name: `Unlink ${parent}`, exact: true }),
	).toBeVisible();

	// People → Families: the two students, the parent paying
	await page.goto(`${DEMO_URL}/app/people/families`);
	await page.getByRole("button", { name: "Add family" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^name/i).fill(family);
	for (const name of [elder, younger]) {
		await dialog.getByLabel("Find a student").fill(name);
		await dialog
			.getByRole("button", { name: `Add ${name}`, exact: true })
			.click();
	}
	await dialog
		.getByLabel(/^payer/i)
		.selectOption({ label: `${parent} (parent)` });
	await dialog.getByRole("button", { name: "Save family" }).click();
	await expect(page.getByText("Family saved.", { exact: true })).toBeVisible();
	await page.getByRole("searchbox").fill(family);
	const row = page.getByRole("row", { name: new RegExp(family) });
	await expect(row).toContainText(elder);
	await expect(row).toContainText(younger);
	await expect(row).toContainText(parent);

	// The students list shows the family chip
	await page.goto(`${DEMO_URL}/app/people/students`);
	await page.getByRole("searchbox").fill(elder);
	await expect(
		page
			.getByRole("row", { name: new RegExp(elder) })
			.getByRole("link", { name: family, exact: true }),
	).toBeVisible();

	// A new invoice for the elder preselects the family payer
	await page.goto(`${DEMO_URL}/app/billing/invoices/new`);
	await page.getByLabel("Find a student").fill(elder);
	await page.getByLabel(/^Student/).selectOption({ label: elder });
	await expect(
		page.getByLabel(/^Billed to/).locator("option:checked"),
	).toHaveText(`${parent} (Family payer)`);
});
```

- [ ] **Step 2: Run the whole e2e suite through the edge, as the CI job does**

With Postgres and Redis up, from the meta root (the CI `e2e` job's steps; on a laptop use `backend/.venv/bin/python` and export `E2E_PYTHON` to it):

```bash
export DATABASE_URL=postgres://etqan:etqan@localhost:5432/etqan CELERY_BROKER_URL=redis://localhost:6379/0 \
  DJANGO_SETTINGS_MODULE=config.settings.local DJANGO_SECRET_KEY=ci-only \
  DJANGO_EMAIL_BACKEND=django.core.mail.backends.filebased.EmailBackend DJANGO_EMAIL_FILE_PATH=/tmp/etqan-mail \
  CELERY_TASK_ALWAYS_EAGER=true DJANGO_TENANT_URL_TEMPLATE='http://{domain}'
(cd backend && python manage.py migrate_schemas --shared && mkdir -p /tmp/etqan-mail && python manage.py seed_dev \
  && nohup python manage.py runserver 127.0.0.1:8000 > /tmp/django.log 2>&1 &)
(cd dashboard && npx pnpm@10 build && nohup npx pnpm@10 preview --port 4173 --host 127.0.0.1 > /tmp/preview.log 2>&1 &)
(cd marketing && npx pnpm@10 build && SITE_API_ORIGIN=http://127.0.0.1:8000 SITE_SCHEME=http HOST=127.0.0.1 PORT=4321 \
  nohup node dist/server/entry.mjs > /tmp/marketing.log 2>&1 &)
docker run -d --name edge --network host -v "$PWD/caddy/Caddyfile.e2e:/etc/caddy/Caddyfile:ro" caddy:2.11.4-alpine
cd dashboard && E2E_DEMO_URL=http://demo.etqan.localhost E2E_OTHER_URL=http://other.etqan.localhost \
  E2E_MAIL_DIR=/tmp/etqan-mail CI=1 npx pnpm@10 exec playwright test --retries=0
```

If ports 80 or 8000 are taken on the machine, run Django on another port (e.g. `18000`) and a scratch copy of `caddy/Caddyfile.e2e` on e.g. `:8080` pointing at it, and set `DJANGO_TENANT_URL_TEMPLATE='http://{domain}:8080'`, `E2E_BASE_URL=http://etqan.localhost:8080` and `E2E_APP_URL=http://demo.etqan.localhost:8080` (and leave `E2E_DEMO_URL`/`E2E_OTHER_URL` unset, so they follow `E2E_BASE_URL`). Never commit the port changes.

Expected: 20 passed (the 19 existing tests and `families.spec.ts`), with no retry. Run it a second time on the same database: the same result. Then stop the edge (`docker rm -f edge`), the three servers, and drop the database if it was a scratch one.

- [ ] **Step 3: Format and lint**

```bash
npx pnpm@10 exec biome check --write src e2e && npx pnpm@10 lint
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git -C dashboard add e2e/families.spec.ts
git -C dashboard commit -m "test(e2e): a family with a parent paying, and the invoice that bills them

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Update `STATE.md`**

In `STATE.md`, replace:

```markdown
Plan 10 (student and teacher profile depth, B1 plan 1 of 4) built and in review: branch
`feat/profile-depth` in backend, dashboard and meta (spec
`docs/superpowers/specs/2026-09-27-profile-depth-design.md`, plan
`docs/superpowers/plans/2026-09-27-plan-10-profile-depth.md`). In `etqan.identity`: editable emoji
`Tag`s per academy (21 student and 22 teacher presets from `presets.py`, seeded by migration
`0014_preset_tags` in every academy schema and by `create_academy`; unique per kind in either
language, case-insensitively; retire and restore, never delete), `StudentProfile.xp` and
`.nationality`, and an age group derived on the academy's calendar (`ages.py`, never stored).
People take `profile.tag_ids` (a retired tag already on a person stays), the students bulk action
takes `add_tag`/`remove_tag`, the lists filter by `tag`, `nationality` and `age_group` and export
them, and `me/` shows a student's own tags, XP and age group, a parent's children's, and a
teacher's own tags. Nationality is admin-only. The dashboard has Settings → Tags, a tag picker on
the forms, chips, filters and bulk tagging on the lists, and the profile card on `/account`.
The e2e suite covers the journey through the Caddy edge. Post-plan hardening: a concurrent
duplicate-name save maps to a 400, never a 500 (`_save_tag`); `tag_ids` are coerced to integers and
capped at 100 (`_tag_ids()`); a test pins the age group to the academy's calendar in a non-UTC zone
(Pacific/Auckland); the dashboard's tag filter is single-select, though `?tag=` is repeatable on the
API (`ANY` match).
```

with:

```markdown
Plan 11 (family accounts and payer, B1 plan 2 of 4) built and in review: branch `feat/families` in
backend, dashboard and meta (spec `docs/superpowers/specs/2026-09-27-families-design.md`, plan
`docs/superpowers/plans/2026-09-27-plan-11-families.md`). In `etqan.identity`: a `Family` (name,
notes, active, a payer) and `StudentProfile.family`, one column, so one family per student; the
account type is derived from it (`services.account_type`), never stored. A payer is one of the
family's students or an active parent of one (F-2); `payer_needs_choosing` is computed on every
read (`families_queryset`'s two EXISTS annotations), never stored, and a flagged or retired family
supplies no payer. Linking goes through `_claim`, a conditional UPDATE, so two admins racing for
one student get a 400, never a move. The API adds `people/families/` (list, create, read, patch; no
PUT or DELETE) and `families/payers/?students=`; students gain `account_type` and `family` in
rows, CSV and `me/`, the `account_type` and `family` filters, and the bulk `create_family`,
`add_to_family` and `remove_from_family` (skipped students reported, never moved). Billing's
`payer_options` puts `identity_services.family_payer` first, then guardians, then the student,
deduplicated; existing invoices never change. The id filters are junk-safe (`as_int`: `int()` in
`try`, so a 5000-digit id no longer 500s). The dashboard has People → Families (dialogs, retire and
restore, a family page), the account type and family chip, filters and bulk actions on students,
"Family payer" on the invoice form and the family on the profile card. The e2e suite covers the
journey through the Caddy edge.
```

In `STATE.md`, replace:

```markdown
Open the PRs (backend, dashboard → `main`; meta → `master`), get meta CI green, merge backend then
dashboard, bump the meta pointers, merge meta; nothing merges without the user's approval. Then
Plan 11 (family accounts and payer). Tags, XP, nationality and the age group live only in
`etqan.identity`: the age group is `ages.age_group`/`ages.born_lookups` on `clock.today()`, never a
stored column; the presets are `presets.PRESETS` and `presets.seed`; assignment rules are
`_tags_to_assign` and `_bulk_tag`. Never restate them elsewhere.
```

with:

```markdown
Open the PRs (backend, dashboard → `main`; meta → `master`), get meta CI green, merge backend then
dashboard, bump the meta pointers, merge meta; nothing merges without the user's approval. Then
Plan 12 (roles and permissions). The family rules live only in `etqan.identity.services`
(`_family_students`, `_payer_for`, `_claim`, `payer_needs_choosing`, `family_payer`); billing
asks `family_payer` and nothing else. Never restate them elsewhere.
```

- [ ] **Step 6: Commit the meta state**

```bash
git add STATE.md docs/superpowers/plans/2026-09-27-plan-11-families.md
git commit -m "chore: state for Plan 11 — families

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

After the backend and dashboard PRs merge, bump the submodule pointers in meta (`git add backend dashboard && git commit`) with the same trailer.

---

## Self-review

Checked against the spec after writing; fixes were made inline.

**Spec coverage**

| Spec | Task |
|---|---|
| §3.1 `Family` (name ≤ 120, notes, active, payer PROTECT, timestamps) | 1 |
| §3.2 `StudentProfile.family` (nullable, set null), one family per student, `account_type` matching membership | 1 (D1, D2), 3 |
| §3.3 `payer_needs_choosing`, computed, never stored | 1 (D4), 2 |
| §4.1 create, update (whole student set, payer valid for the result, invalid only when `payer_id` is absent), retire and restore, everything checked before writing | 1, 2 |
| §4.2 the payer rule: family payer, guardians, student, deduplicated; default is the first, valid means listed; "Family payer" on the form | 5 (D3, D9), 10 |
| §4.3 `account_type` and `family` on rows and details, the two filters, the three bulk actions with skipped students reported, the CSV columns | 3, 4 (D5), 9 |
| §4.4 families admin-only, notes admin-only, `me/` for a student and a parent's children | 2, 3, 10 |
| §5 the families routes, fresh reads, no PUT or DELETE | 2 (D6) |
| §6 People → Families (list, search, active filter, Add and Edit with student multi-select and recomputed payer select, Retire and Restore), students list (column, chip, filters, bulk), student form, invoice form, profile cards, en and ar | 7, 8 (D7, D8), 9 (D10), 10 |
| §7 seeds: the Omar family in `demo`, idempotent, nothing in `other` | 6 (D11) |
| §8 rules, billing, bulk, access and isolation (`until_pk_exceeds`), flat query counts, dashboard units, one e2e journey | 1–11 |
| §9 risks: computed validity and a visible flag; a DB-level one-family column plus a checked 400 and a race-safe claim; billing calls one identity service, `lint-imports` enforces it | 1, 5, 8 |

**Spec gaps settled here:** whether `account_type` is a column (no, D1); what "the database also forbids it" means with a single FK column, and how a race is refused (D2); the identity lookup billing uses and how duplicates collapse (D3); which people make a payer valid, including a deactivated payer student and an emptied family (D4); the bulk bodies, the skipped reason as a code, the 400 when everyone is skipped, adding to a retired family, and emptying a family (D5); how the dialogs get the payer choices of students not yet saved (D6, a new `families/payers/` route); where the admin UI and the chip's target live (D7); whether the dialog may resend a payer that no longer qualifies (D8); how the form knows which choice is the family payer (D9); how many families the students list's pickers offer (D10); and the seeded family (D11).

**Placeholder scan:** no "TBD", "TODO", "similar to Task N" or step without its code. Every name a later task uses is produced by an earlier task's Interfaces block.

**Type and name consistency:**
- `family_payer(student_user_id) -> User | None` (Task 1) is what `payer_options` calls (Task 5).
- `FAMILY_ACTIONS`, `bulk_family(…, name=, payer_id=, family_id=)` (Task 4) match `StudentBulkSerializer`'s fields and the dashboard's `BulkBody` (Task 7).
- The families routes' `student_ids`, `payer_id`, `name`, `notes`, `is_active` match `FamilyInput`/`FamilyChange` and the form's field names, so `applyServerErrors` lands errors on the right field.
- `relation: "family" | "guardian" | "student"` is the same on both sides; `people.field.family` (Task 9) is the key `MyProfileCard` reads (Task 10).

**Review Focus:** each of the five lines names its tests, which are in the owning task's test file.
