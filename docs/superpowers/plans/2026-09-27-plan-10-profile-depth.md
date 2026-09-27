# Plan 10 — Student and Teacher Profile Depth — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Academies describe and motivate their people the way TutorHamster does: editable emoji tags on students and teachers (21 and 22 presets per academy), XP points and a nationality on students, and an age group derived from the date of birth. All of them show in the list rows and can be filtered, exported and bulk-applied, and students, parents and teachers see their own through `me/`.

**Architecture:** Everything lives in `etqan.identity` (PD-1).
- A new `Tag` model (`kind`, `emoji`, `name_ar`, `name_en`, `position`, `is_active`) is unique per kind in either language whatever the case, through two `Lower()` constraints.
- `StudentProfile` gains `xp`, `nationality` and `tags`; `TeacherProfile` gains `tags`.
- `presets.py` holds the 43 presets and one `seed(model)` function. The data migration `0014_preset_tags` calls it in every academy schema (never in `public`), and `create_academy` calls it through `services.ensure_preset_tags()`.
- The age group is never stored. `ages.py` turns the academy's today (`identity.clock.today()`) into two cut-off dates. The payload classifies a row with them, and the `?age_group=` filter is a plain date comparison on the same cut-offs, so counts and paging stay exact.
- Services own every rule: assignment through `profile.tag_ids`, the bulk `add_tag`/`remove_tag`, and tag create, rename, move, retire and restore (no delete).
- The API adds `GET/POST /api/v1/people/tags/` and `PATCH /api/v1/people/tags/<id>/`. It adds the new fields to the person payloads (nationality only in admin payloads), the filters, and the CSV columns. `me/` gains a student's own tags, XP and age group, each child's for a parent, and a teacher's own tags.
- On the dashboard (`features/people`):
  - a Settings → Tags page;
  - a `TagPicker` on the student and teacher forms, plus XP and Nationality on the student form;
  - chips, filters and bulk tag actions on the lists;
  - tags, XP and age group on the account page's profile card (`MyProfileCard`).
- A shared `TagChips` component in `src/components` renders tags everywhere.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18; React 19 + TanStack Router/Query + Vite (base `/app/`), react-hook-form + zod 4, i18next; Playwright through the Caddy edge.

**Spec:** `docs/superpowers/specs/2026-09-27-profile-depth-design.md` (Phase B1, plan 1 of 4). It builds on:
- Plan 3, `2026-09-24-people-catalogue-design.md`: people, the profiles, the statuses, the students bulk action, CSV, the staff-only `notes`, admin-only people endpoints, nested `{"user": …, "profile": …}` errors (plan D7);
- `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`: PEOPLE-001 (tags, XP, nationality, age group), PEOPLE-005 (teacher tags), note 15 (21 and 22 emoji presets).

Where this plan fills a gap in the spec, the Decisions below say so.

**Verified:** a script applied the code in Tasks 1–11 in this plan's order, exactly as written here, to fresh copies of `backend@0516048` and `dashboard@6dad0c1` (the current `main` of each). That covers every `Create`, `replace … with`, `Append to` and `Merge into` block, and the `makemigrations` command.
- Before each task's code went in, its new tests were run and failed. The ones that passed are the Plan 3 tests the task leaves alone, plus the teachers-list test whose fixture Task 9 only extends.
- After each task, its format, lint, import-contract, type, test and coverage commands passed, and `ruff format --check` and `biome check` found the plan's code already formatted (the generated migration aside).
- Backend: 1268 → 1353 tests, coverage 97.9% → 98.0%.
- Dashboard: 644 → 665 tests, lines 94.1% → 94.3%, branches 87.2% → 87.7%, functions 81.0% → 81.6%.

The e2e suite then passed through Caddy, run the way the CI `e2e` job runs it: Django (`config.settings.local`, the file email backend, eager Celery) and the Vite preview on a freshly migrated and seeded database, plus the marketing server on `:4321` and a `caddy:2.11.4-alpine` edge. That was 19 of 19, `profile-depth.spec.ts` included, twice on the same database, with no retry. Migrations are generated with `makemigrations`, so only their timestamps will differ.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), meta repo (trunk `master`).
- The branch `feat/profile-depth` already exists in the meta repo, `backend/` and `dashboard/`, so do not create it. Check with `git -C backend branch --show-current` and `git -C dashboard branch --show-current` before Task 1 and Task 6.
- Nothing is merged without the user's approval. After merge, bump the submodule pointers in meta.
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

**Backend commands**
- Run from `backend/` with the virtualenv `backend/.venv`. Export this environment once per shell:
  `export DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan CELERY_BROKER_URL=redis://localhost:56379/0 DJANGO_SECRET_KEY=test-secret DJANGO_READ_DOT_ENV_FILE=False DJANGO_TENANT_BASE_DOMAIN=etqan.localhost`
- Tests: `.venv/bin/pytest …`. Add `--create-db` once after Task 1, which adds migrations (the reused test database must pick them up).
- Format: `.venv/bin/ruff check --fix . && .venv/bin/ruff format .`
- Verify: `.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan`
- Ruff selects `PL`, `FBT`, `DTZ`, `BLE` and `E501` (88 columns): datetimes carry `tzinfo`, booleans are passed by keyword.

**Dashboard commands**
- Run from `dashboard/` through `npx pnpm@10`.
- Format: `npx pnpm@10 exec biome check --write src e2e`
- New route files are picked up by the TanStack Router plugin. Regenerate `src/routeTree.gen.ts` with `npx pnpm@10 exec vite build` before `tsc` (Task 7).
- Verify: `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`
- `pnpm lint` is `biome ci . && node scripts/check-colors.mjs`: no hex colour literals and no Tailwind palette utilities anywhere in `src/`, `e2e/` or `scripts/`, comments included. Semantic tokens only.
- `tsc` has `noUnusedLocals`/`noUnusedParameters`.

**Coverage and dev data**
- Coverage gates: backend ≥ 80% (`pytest --cov=etqan`); dashboard lines 80 / statements 80 / branches 70 / functions 70.
- Seeded dev password `e2e-EtqanTest-2026` (admins only; seeded students, parents and teachers have no password).
- Academies: `demo` (`admin@demo.test`, timezone UTC, default language Arabic) and `other` (`admin@other.test`).

**Tenancy and module boundaries**
- No new app (PD-1). `Tag` lives in `etqan.identity`, which is in both `SHARED_APPS` (staff accounts in `public`) and `TENANT_APPS`. The preset migration therefore runs in `public` too, and skips it.
- Migrate with `migrate_schemas`. Every academy schema is created by `Academy.save()` with `auto_create_schema`, which runs every migration, `0014_preset_tags` included.
- Business logic lives in `etqan/identity/services.py` (and the pure helpers `ages.py`, `presets.py`). Views parse, call one service, re-read and arrange a payload.
- `lint-imports` must stay at 16 contracts kept. Nothing here crosses an app boundary except `tenants` (`create_academy`, `seed_dev`), which calls `identity.services`.
- Keyword-only flags with no default: `profile_payload(user, *, staff, …)`. Other new keyword arguments: `ages.age_group(dob, *, today)`, `ages.born_lookups(group, *, today)`, `update_tag(tag, *, fields)`, `_tags_to_assign(kind, ids, *, kept)`.

**API and data rules**
- All routes are under `/api/v1/`: the tags at `/api/v1/people/tags/`, the people routes as before.
- Spec values, verbatim:
  - `kind` `student · teacher`; `emoji` up to 8 characters (code points); `name_ar`, `name_en` up to 60;
  - XP from 0 to 1,000,000, default 0;
  - nationality `arab · foreign` or blank;
  - age group `child` under 13, `teen` 13–17, `adult` 18 and over, blank without a date of birth; the filter also takes `minor` (child or teen);
  - 21 student and 22 teacher presets, each with an emoji.
- Errors:
  - a duplicate or blank tag name is `400 {"name_en"|"name_ar": [...]}`; a bad `kind` is `400 {"kind": [...]}`;
  - a wrong-kind, unknown or other-academy tag, or a retired tag the person does not already have, is `400 {"profile": {"tag_ids": [...]}}` on a person write (Plan 3's nesting, D7), and `400 {"tag_id": [...]}` on the bulk action;
  - every tags and people route is `403` for non-admins and anonymous callers; an unknown tag is `404`.
- Nationality appears in no payload a non-admin reads (`me/`, a parent's `children`); `notes` stays staff-only as before.
- Every write answers with a fresh read. There is no `PUT`, `DELETE` or detail `GET` on a tag.
- The student and teacher lists, their CSV, the tags list and a parent's `me/` have query-count tests that stay flat as tagged rows grow.

**Dashboard strings and helpers**
- Every dashboard string is in `src/locales/en/common.json` and `src/locales/ar/common.json`, with no English literal in components. Each task lists the keys it adds; merge them into the existing objects.
- zod messages are i18n keys rendered through `useFieldError`. Server field errors land through `applyServerErrors`; toasts use `errorText`.
- Where one accessible name is a prefix or substring of another (`Tag` inside `Tag to add or remove`; a tag's name is also a filter `<option>`), tests match exactly, by role, or inside the row.
- Screens work RTL and at phone width.
- Reuse the shared helpers: `Pager` (through `PeopleList`), `clean`/`csvUrl`, `applyServerErrors`/`errorText`, `useFieldError`, `Fact`. No copies inside a feature.
- Pages handle a load error with a translated message.

**Tests**
- Each assertion fails without the code under test.
- Duplicate matches are scoped (`within(row)`, the bulk bar region, the dialog).
- Cross-academy tests hold data in BOTH academies, with the other academy's pk forced above this one's (`until_pk_exceeds`), and assert this academy's own data.
- Timezone tests put the academy in a zone whose date differs from UTC's at the pinned instant (Pacific/Auckland: 13:00 UTC on 1 June is 2 June there).
- Identity's clock is pinned by monkeypatching `etqan.identity.clock.now`.
- Every test academy starts with the 43 presets (the migration ran when its schema was created); tests look them up by name.

### Decisions this plan makes where the spec is silent or conflicts with the code

- **D1 — The presets.** `etqan/identity/presets.py` holds them as `(emoji, name_ar, name_en)`, in list order. The audit's examples are kept verbatim; the rest are completed in the same spirit.
  - **Students (21):** 🎓 جديد New · 🌟 متميز Outstanding · ⭐ نجم الشهر Star of the month · 💯 حافظ متقن Proficient memoriser · 📖 قارئ ماهر Skilled reader · 🎤 متحدث طليق Fluent speaker · 📅 عضو منذ سنة Member for 1 year · 🏆 بطل المسابقة Competition champion · 🚀 سريع التقدم Fast learner · ⏰ ملتزم بالمواعيد Always on time · 📝 منجز الواجبات Homework done · 🧠 سريع الحفظ Quick memoriser · 🗣️ نطق سليم Clear pronunciation · 🎶 صوت جميل Beautiful recitation · 💪 مثابر Persistent · 🤝 متعاون Cooperative · 😊 مهذب Well-mannered · ❓ كثير الأسئلة Curious · 🔥 متحمس Enthusiastic · 🌱 يحتاج إلى دعم Needs support · 📈 في تحسن مستمر Steadily improving.
  - **Teachers (22):** 👑 متميز في التدريس Excellent at teaching · 🎯 خبير Expert · 🤝 صبور Patient · ✨ ملهم Inspiring · ⏰ ملتزم بالمواعيد Punctual · 📚 واسع المعرفة Knowledgeable · 🎓 حاصل على إجازة Holds an ijazah · 🗣️ ثنائي اللغة Bilingual · 👶 ممتاز مع الأطفال Great with children · 🧑‍🎓 ممتاز مع الكبار Great with adults · 🎤 صوت جميل Beautiful recitation · 📖 متخصص في التجويد Tajweed specialist · 💯 متخصص في التحفيظ Memorisation specialist · 🔤 متخصص في اللغة العربية Arabic specialist · 💬 تواصل ممتاز Great communicator · 😊 ودود Friendly · 📝 تقارير مفصلة Detailed reports · 🧩 مبدع في الأساليب Creative methods · 🌟 الأعلى تقييمًا Top rated · 🆕 معلم جديد New teacher · 📅 معلم منذ سنة Teaching for 1 year · 🏅 معلم الشهر Teacher of the month.
  - Seeding is `presets.seed(model)`. A preset is skipped when its kind already has the same English name or the same Arabic name, compared case-insensitively. New presets go after the kind's last position. The same function serves the migration (with the historical model) and `ensure_preset_tags()`.
- **D2 — Case-insensitive uniqueness.** Two database constraints, `UniqueConstraint(F("kind"), Lower("name_en"))` and `UniqueConstraint(F("kind"), Lower("name_ar"))`, are the last line of defence. The service checks first (`__iexact` on the trimmed name, excluding the tag itself) and answers `400` on that field, so the constraint never surfaces as a 500. `full_clean` then runs with `validate_constraints=False`, because Django's own constraint message would be a non-field error.
- **D3 — The age-group SQL.** `ages.cutoffs(today)` returns `(teen_cut, adult_cut)`, the dates 13 and 18 years before the academy's today.
  - `years_before` maps 29 February in a year without one to the 28th.
  - child: born after `teen_cut`; teen: born after `adult_cut` and on or before `teen_cut`; adult: born on or before `adult_cut`; minor: born after `adult_cut`.
  - Someone born exactly on a cut-off has had that birthday today. A 29 February birthday comes round on 1 March in a common year (on 28 February 2029 the cut-off is 28 February 2016, so a 29 February 2016 child is still 12).
  - The filter is `student_profile__date_of_birth__gt/__lte` on those dates, a plain `WHERE` that NULL never matches. The payload runs `ages.age_group(dob, today=…)` on the same cut-offs, so a row's `age_group` always agrees with the filter that finds it.
  - Today is `identity.clock.today()`, the academy's `AcademySettings.timezone`, read once per list.
- **D4 — `tag_ids` rules.** `tag_ids` sits inside `profile` (like a teacher's `course_ids`) and replaces the whole set; duplicates collapse.
  - Every id must be a tag of the person's kind in this academy, else `Choose tags from the list.`
  - A retired tag is refused (`A retired tag can't be added.`) unless the person already has it, so a form that sends back a retired tag keeps it.
  - Parents and admins take no `tag_ids` (`Unknown field.` / `Admins have no profile.`).
  - Everything is validated before anything is written, including the email change.
- **D5 — The bulk action.** `POST /api/v1/people/students/bulk/` takes `{"ids": [...], "action": "add_tag" | "remove_tag", "tag_id": <id>}` and answers `{"updated": <students targeted>}`, as the other actions do.
  - The tag must be a student tag of this academy (`400 {"tag_id": ["Choose a tag from the list."]}`), and a missing `tag_id` is `400 {"tag_id": ["Choose a tag."]}`.
  - `add_tag` refuses a retired tag. `remove_tag` allows one: removing is how an academy clears a retired tag off.
  - Non-students and other academies' ids are ignored, as before. Adding is `bulk_create(ignore_conflicts=True)` on the link table and removing is one `DELETE`, so both are idempotent.
- **D6 — The CSV.**
  - Students: the Plan 3 columns (ID … Date of birth), then `Age group`, `Nationality`, `XP`, `Tags`.
  - Teachers: the Plan 3 columns (… Course IDs), then `Tags`.
  - A Tags cell is `emoji name; emoji name` in the academy's default language (a tag without an emoji is just its name), in list order. Age group and nationality are their codes (`child`, `arab`), like Status.
- **D7 — `me/`.** `profile_payload(user, *, staff, …)` replaces Plan 3's `include_notes=` flag. `staff=False` drops `STAFF_ONLY = ("notes", "nationality")`.
  - A student's `me/` profile gains `tags`, `xp` and `age_group`, and each of a parent's `children[].profile` gains the same.
  - A teacher's gains `tags`.
  - Admin rows and details carry everything, `nationality` included.
  - A tag in a payload is `{id, emoji, name_ar, name_en}`; a row of the tags admin adds `kind, position, is_active, people`.
- **D8 — The tags admin.**
  - `GET people/tags/?kind=` is a plain array, not paginated: at most a few dozen rows, and every form needs all of them. Without `kind` it answers both kinds, students first; an unknown kind is `400`.
  - `people` counts active people (`user.is_active`). A retired tag still counts the people who have it.
  - `position` on PATCH is the tag's 1-based place in its kind's list. The service renumbers the whole kind to 1..n under `select_for_update`, so ties and gaps (two tags created at once, old data) heal on the next move. A place past the end means last; 0 is a 400.
  - New tags go last (`max(position) + 1`).
- **D9 — The dashboard.**
  - The multi-select reuses the checkbox fieldset pattern the teacher form already uses for courses: `TagPicker`, with the legend "Tags". It shows the kind's active tags plus any retired tag the person already has, labelled "(Retired)" and named in full on its checkbox.
  - Chips are one shared `src/components/TagChips.tsx` (`TagChips`, `tagName`, `tagLabel`), used by the people feature and by `MyProfileCard` in identity.
  - The emoji is `aria-hidden`: a chip reads as its name.
  - Settings → Tags is its own page, `/settings/tags`, with a nav item after Academy in the Settings group (admins only). It has two tabs, and up and down buttons that send the row's new 1-based place.
  - The emoji limit is checked in code points (`[...value].length <= 8`), as the server counts it; zod's `max` would count UTF-16 units and refuse a legal 4-flag emoji.
- **D10 — Seeds.** `seed_profiles(PROFILES.get(subdomain))` runs after `seed_people` in `seed_academy`.
  - Every academy gets `ensure_preset_tags()`. `other` gets nothing else.
  - In `demo`:
    - Yusuf gets ⭐ Star of the month and 📖 Skilled reader, 320 XP, `arab`, and is 9 (a child);
    - Aisha gets 🎓 New, 40 XP, `foreign`, and is 15 (a teen);
    - Zaid gets 💯 Proficient memoriser and 150 XP, and is 19 (an adult);
    - Bilal gets 👑 Excellent at teaching and 🤝 Patient;
    - Maryam gets 👶 Great with children.
  - Dates of birth are 10 March, that many years before the academy's today. A seeded person who already has a tag is left alone, so a second run (or an admin's own tagging) changes nothing, and a missing seeded person is skipped with a `skip:` line.
- **D11 — The e2e journey.** Seeded students have no password, so the spec creates its own student with an email address (the invite goes out on save). It creates a stamped tag in Settings → Tags, bulk-adds it from the list, filters by it alone (exactly one row), then signs the student in through the invite (`acceptInvite`) and finds the tag on `/account`.

## Review Focus

- **Position ties and gaps.** Two admins adding tags at once can give two tags the same place, and old data can have gaps. A move must still land where asked and leave the kind numbered 1..n. Test: Task 2 `test_a_move_heals_ties_and_gaps`.
- **Names that differ only by spaces or case.** `" نجم الشهر "`, `"star OF the MONTH"` and a rename to `" جديد "` must be a 400 on that field, never a 500 from the database constraint. Tests: Task 2 `test_a_bad_or_duplicate_name_is_a_400_on_that_field` (spaced rows), `test_rename_and_re_emoji_but_never_a_clash` (spaced Arabic rename).
- **Removing in bulk a tag nobody selected has.** The selection may include students without the tag and ids that are not students: the action succeeds, counts the students, and changes nothing else. Test: Task 3 `test_removing_a_tag_nobody_has_changes_nothing`.
- **A stale or foreign filter.** A teacher tag id in the students list's `?tag=` (an old bookmark), an unknown id, or junk (`tag=-1`, `tag=x`, an empty `age_group`) must answer with an empty or unfiltered list, never a 500. Test: Task 4 `test_a_tag_of_the_other_kind_or_junk_filters_never_break_the_list`.
- **A tag without an emoji.** The emoji is optional, so chips, option labels and the CSV cell must read cleanly with no stray space. Tests: Task 4 `test_teachers_gain_tags_and_a_tag_without_an_emoji_reads_cleanly`; Task 6 `TagChips` "labels a tag with its emoji and name" (`Plain`).

---

## File Structure

```
backend/
  etqan/identity/
    models.py                  Tag (+ Lower() constraints); StudentProfile.xp, .nationality, .tags; TeacherProfile.tags
    presets.py                 NEW: PRESETS (21 + 22) and seed(model)
    ages.py                    NEW: years_before, cutoffs, age_group, born_lookups (PD-5, D3)
    clock.py                   NEW: now(), today() on the academy's calendar
    migrations/0013_profile_depth.py   generated (fields, Tag, constraints)
    migrations/0014_preset_tags.py     NEW data migration: presets in every academy, not public
    services.py                ensure_preset_tags, tags_queryset, get_tag, create_tag, update_tag (move);
                               tag_ids on create/update_person; bulk add_tag/remove_tag; tag prefetch
    api/payloads.py            tag_chip, tag_row, tag_labels, csv_rows; tags/xp/nationality/age_group;
                               profile_payload(*, staff) with STAFF_ONLY
    api/people_serializers.py  tag_ids, xp, nationality; bulk tag_id; TagCreate/TagUpdate serializers
    api/people_views.py        TagListCreateView, TagDetailView; bulk tag_id; CSV columns
    api/people_filters.py      ?tag= (repeatable), ?nationality=, ?age_group=
    api/people_urls.py         tags/, tags/<id>/
    api/views.py               me/: staff=False, the academy's today, children's tags prefetched
    tests/test_tags.py test_tags_api.py test_ages.py test_profile_depth.py
    tests/test_profile_access.py test_people_depth_lists.py     NEW
  etqan/tenants/services.py    create_academy → ensure_preset_tags (+ tests/test_services.py)
  etqan/tenants/management/commands/seed_dev.py   PROFILES, seed_profiles (+ tests/test_seed_dev.py)
dashboard/
  src/components/TagChips.tsx          NEW: TagChip, TagChips, tagName, tagLabel (+ test)
  src/features/people/
    schemas.ts api.ts queries.ts        Tag types, tag API, useTags/useCreateTag/useUpdateTag, form fields
    TagsSettings.tsx                    NEW: Settings → Tags (tabs, add/edit dialog, move, retire/restore)
    TagPicker.tsx                       NEW: the forms' tag checkboxes
    TagOptions.tsx                      NEW: tags as <option>s for filters and the bulk bar
    StudentForm.tsx TeacherForm.tsx     tags; XP, nationality, age group (student)
    StudentsList.tsx TeachersList.tsx   chips, filters, bulk add/remove tag
    index.ts
  src/features/identity/components/MyProfileCard.tsx   own tags, XP, age group; children's
  src/features/shell/nav.ts            Settings → Tags
  src/routes/_authed/settings.tags.tsx NEW
  src/test/people-fixtures.ts          NEW: tagRow, STUDENT_TAGS, TEACHER_TAGS
  src/locales/{en,ar}/common.json
  e2e/profile-depth.spec.ts            NEW
meta: STATE.md, submodule pointers
```

---

### Task 1: Data: the `Tag` model, XP and nationality, the presets and how every academy gets them

**Files:**
- Create: `backend/etqan/identity/presets.py`, `backend/etqan/identity/migrations/0013_profile_depth.py` (generated in Step 4), `backend/etqan/identity/migrations/0014_preset_tags.py`
- Modify: `backend/etqan/identity/models.py`, `backend/etqan/identity/services.py`, `backend/etqan/tenants/services.py`
- Test: `backend/etqan/identity/tests/test_tags.py` (new), `backend/etqan/tenants/tests/test_services.py`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `etqan.identity.models.Tag` (`Tag.Kind.STUDENT/TEACHER`; fields `kind, emoji, name_ar, name_en, position, is_active, created_at, updated_at`; `Meta.ordering = ("position", "id")`; constraints `identity_tag_kind_name_en_ci_unique`, `identity_tag_kind_name_ar_ci_unique`);
  - `StudentProfile.xp` (0..`XP_MAX` = 1,000,000), `StudentProfile.Nationality.ARAB/FOREIGN`, `StudentProfile.nationality`, `StudentProfile.tags` (reverse `Tag.students`), `TeacherProfile.tags` (reverse `Tag.teachers`);
  - `etqan.identity.presets.PRESETS: dict[str, tuple[tuple[str, str, str], ...]]` (`(emoji, name_ar, name_en)`) and `presets.seed(tag_model) -> int`;
  - `etqan.identity.services.ensure_preset_tags() -> int` (how many were added);
  - `create_academy` seeds the presets in the new academy.

- [ ] **Step 1: Write the failing tests**

Every academy (both test academies) starts with the 21 and 22 presets in order and none retired; `public` gets none. The migration's function runs twice without duplicating and keeps an academy's own spelling of a preset. `ensure_preset_tags` adds only what is missing. Names are unique per kind in either language whatever the case. `create_academy` calls the seeding in the new academy's schema.

Create `backend/etqan/identity/tests/test_tags.py`:

```python
"""Plan 10 tags: the model, the presets and how every academy gets them."""

import importlib
from types import SimpleNamespace

import pytest
from django.apps import apps
from django.db import IntegrityError
from django.db import connection
from django.db import transaction
from django_tenants.utils import schema_context
from django_tenants.utils import tenant_context

from etqan.identity import presets
from etqan.identity import services
from etqan.identity.models import Tag

pytestmark = pytest.mark.django_db
preset_migration = importlib.import_module("etqan.identity.migrations.0014_preset_tags")


def listed(kind):
    return list(
        Tag.objects.filter(kind=kind)
        .order_by("position", "id")
        .values_list("emoji", "name_ar", "name_en")
    )


def test_21_student_and_22_teacher_presets_each_with_an_emoji():
    assert (len(presets.PRESETS["student"]), len(presets.PRESETS["teacher"])) == (
        21,
        22,
    )
    for rows in presets.PRESETS.values():
        assert all(0 < len(emoji) <= 8 for emoji, _, _ in rows)
        assert all(0 < len(ar) <= 60 and 0 < len(en) <= 60 for _, ar, en in rows)
        assert len({en.lower() for _, _, en in rows}) == len(rows)
        assert len({ar for _, ar, _ in rows}) == len(rows)
    assert ("⭐", "نجم الشهر", "Star of the month") in presets.PRESETS["student"]
    assert ("👑", "متميز في التدريس", "Excellent at teaching") in presets.PRESETS[
        "teacher"
    ]


def test_every_academy_starts_with_the_presets_in_order(tenants):
    for academy in (tenants.main, tenants.other):
        with tenant_context(academy):
            assert listed("student") == list(presets.PRESETS["student"])
            assert listed("teacher") == list(presets.PRESETS["teacher"])
            positions = Tag.objects.filter(kind="teacher").values_list(
                "position", flat=True
            )
            assert sorted(positions) == list(range(1, 23))
            assert not Tag.objects.filter(is_active=False).exists()


def test_the_public_schema_gets_no_tags():
    Tag.objects.all().delete()
    preset_migration.forwards(
        apps, SimpleNamespace(connection=SimpleNamespace(schema_name="public"))
    )
    assert not Tag.objects.exists()
    with schema_context("public"):
        assert not Tag.objects.exists()


def test_the_presets_migration_runs_once_and_keeps_an_academys_own_names():
    star = Tag.objects.get(kind="student", name_en="Star of the month")
    star.name_en = "STAR OF THE MONTH"  # the academy's own spelling stays
    star.save()
    Tag.objects.filter(kind="teacher", name_en="Patient").delete()
    editor = SimpleNamespace(connection=connection)
    preset_migration.forwards(apps, editor)
    preset_migration.forwards(apps, editor)
    assert Tag.objects.filter(kind="student").count() == 21
    assert Tag.objects.get(kind="student", name_ar="نجم الشهر").name_en == (
        "STAR OF THE MONTH"
    )
    patient = Tag.objects.get(kind="teacher", name_en="Patient")
    assert (patient.emoji, patient.position) == ("🤝", 23)  # after the last
    assert Tag.objects.filter(kind="teacher").count() == 22


def test_ensure_preset_tags_adds_only_what_is_missing():
    assert services.ensure_preset_tags() == 0
    Tag.objects.filter(name_en__in=["New", "Expert"]).delete()
    assert services.ensure_preset_tags() == 2
    assert services.ensure_preset_tags() == 0


def test_names_are_unique_per_kind_in_either_language_whatever_the_case():
    # The same names on the other kind are fine.
    Tag.objects.create(kind="teacher", name_ar="نجم الشهر", name_en="Star of the month")
    with pytest.raises(IntegrityError), transaction.atomic():
        Tag.objects.create(kind="student", name_ar="جديدة", name_en="STAR of the month")
    with pytest.raises(IntegrityError), transaction.atomic():
        Tag.objects.create(kind="student", name_ar="نجم الشهر", name_en="Other")
    assert str(Tag(kind="student", name_en="New")) == "Tag<student, New>"
```

In `backend/etqan/tenants/tests/test_services.py`, replace:

```python
from etqan.identity.models import User
```

with:

```python
from etqan.identity.models import Tag
from etqan.identity.models import User
```

Append to `backend/etqan/tenants/tests/test_services.py`:

```python
@pytest.mark.django_db
def test_create_academy_seeds_the_preset_tags(in_public, monkeypatch):
    seed = services.identity_services.ensure_preset_tags
    calls = []

    def spy():
        calls.append(connection.schema_name)
        return seed()

    monkeypatch.setattr(services.identity_services, "ensure_preset_tags", spy)
    academy = services.create_academy(
        name="Tagged", subdomain="tagged", admin_email="t@tagged.test"
    )
    assert calls == ["academy_tagged"]
    with tenant_context(academy):
        assert Tag.objects.filter(kind="student", is_active=True).count() == 21
        assert Tag.objects.filter(kind="teacher", is_active=True).count() == 22
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/identity/tests/test_tags.py etqan/tenants/tests/test_services.py -q`

Expected: FAIL — two collection errors: `cannot import name 'presets' from 'etqan.identity'` (test_tags.py) and `cannot import name 'Tag' from 'etqan.identity.models'` (test_services.py).

- [ ] **Step 3: Implement the model, the presets and the seeding**

In `backend/etqan/identity/models.py`, replace:

```python
from django.core.validators import RegexValidator
```

with:

```python
from django.core.validators import MaxValueValidator
from django.core.validators import RegexValidator
```

In `backend/etqan/identity/models.py`, replace:

```python
class StudentProfile(models.Model):
    class Status(models.TextChoices):
```

with:

```python
class Tag(models.Model):
    """An emoji tag an academy puts on its students or teachers (Plan 10).

    Never deleted: a retired tag (``is_active=False``) stays on the people who
    have it but can't be newly assigned."""

    class Kind(models.TextChoices):
        STUDENT = "student", "Student"
        TEACHER = "teacher", "Teacher"

    kind = models.CharField(max_length=8, choices=Kind.choices)
    # Up to 8 characters: a flag (2) or a ZWJ sequence such as 🧑‍🎓 (3) fits.
    emoji = models.CharField(max_length=8, blank=True, default="")
    name_ar = models.CharField(max_length=60)
    name_en = models.CharField(max_length=60)
    position = models.IntegerField(default=0)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("position", "id")
        constraints = [
            models.UniqueConstraint(
                models.F("kind"),
                Lower("name_en"),
                name="identity_tag_kind_name_en_ci_unique",
            ),
            models.UniqueConstraint(
                models.F("kind"),
                Lower("name_ar"),
                name="identity_tag_kind_name_ar_ci_unique",
            ),
        ]

    def __str__(self):
        return f"Tag<{self.kind}, {self.name_en}>"


XP_MAX = 1_000_000


class StudentProfile(models.Model):
    class Status(models.TextChoices):
```

In `backend/etqan/identity/models.py`, replace:

```python
        INACTIVE = "inactive", "Inactive"

    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="student_profile"
    )
```

with:

```python
        INACTIVE = "inactive", "Inactive"

    class Nationality(models.TextChoices):
        ARAB = "arab", "Arab"
        FOREIGN = "foreign", "Foreign"

    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="student_profile"
    )
```

In `backend/etqan/identity/models.py`, replace:

```python
    notes = models.TextField(blank=True, default="")

    def __str__(self):
        return f"StudentProfile<{self.user}>"
```

with:

```python
    notes = models.TextField(blank=True, default="")
    xp = models.PositiveIntegerField(default=0, validators=[MaxValueValidator(XP_MAX)])
    nationality = models.CharField(
        max_length=8, choices=Nationality.choices, blank=True, default=""
    )
    tags = models.ManyToManyField(Tag, blank=True, related_name="students")

    def __str__(self):
        return f"StudentProfile<{self.user}>"
```

In `backend/etqan/identity/models.py`, replace:

```python
    payout_details = models.TextField(blank=True, default="")

    def __str__(self):
        return f"TeacherProfile<{self.user}>"
```

with:

```python
    payout_details = models.TextField(blank=True, default="")
    tags = models.ManyToManyField(Tag, blank=True, related_name="teachers")

    def __str__(self):
        return f"TeacherProfile<{self.user}>"
```

Create `backend/etqan/identity/presets.py`:

```python
"""TutorHamster's preset tags (audit note 15): 21 for students and 22 for
teachers, each ``(emoji, name_ar, name_en)``. Every academy starts with them.

Plain data plus one seeding function that works on the real ``Tag`` model and
on the migration's historical one alike, so the data migration and
``create_academy`` share it (and never import each other)."""

STUDENT = "student"
TEACHER = "teacher"

PRESETS: dict[str, tuple[tuple[str, str, str], ...]] = {
    STUDENT: (
        ("🎓", "جديد", "New"),
        ("🌟", "متميز", "Outstanding"),
        ("⭐", "نجم الشهر", "Star of the month"),
        ("💯", "حافظ متقن", "Proficient memoriser"),
        ("📖", "قارئ ماهر", "Skilled reader"),
        ("🎤", "متحدث طليق", "Fluent speaker"),
        ("📅", "عضو منذ سنة", "Member for 1 year"),
        ("🏆", "بطل المسابقة", "Competition champion"),
        ("🚀", "سريع التقدم", "Fast learner"),
        ("⏰", "ملتزم بالمواعيد", "Always on time"),
        ("📝", "منجز الواجبات", "Homework done"),
        ("🧠", "سريع الحفظ", "Quick memoriser"),
        ("🗣️", "نطق سليم", "Clear pronunciation"),
        ("🎶", "صوت جميل", "Beautiful recitation"),
        ("💪", "مثابر", "Persistent"),
        ("🤝", "متعاون", "Cooperative"),
        ("😊", "مهذب", "Well-mannered"),
        ("❓", "كثير الأسئلة", "Curious"),
        ("🔥", "متحمس", "Enthusiastic"),
        ("🌱", "يحتاج إلى دعم", "Needs support"),
        ("📈", "في تحسن مستمر", "Steadily improving"),
    ),
    TEACHER: (
        ("👑", "متميز في التدريس", "Excellent at teaching"),
        ("🎯", "خبير", "Expert"),
        ("🤝", "صبور", "Patient"),
        ("✨", "ملهم", "Inspiring"),
        ("⏰", "ملتزم بالمواعيد", "Punctual"),
        ("📚", "واسع المعرفة", "Knowledgeable"),
        ("🎓", "حاصل على إجازة", "Holds an ijazah"),
        ("🗣️", "ثنائي اللغة", "Bilingual"),
        ("👶", "ممتاز مع الأطفال", "Great with children"),
        ("🧑‍🎓", "ممتاز مع الكبار", "Great with adults"),
        ("🎤", "صوت جميل", "Beautiful recitation"),
        ("📖", "متخصص في التجويد", "Tajweed specialist"),
        ("💯", "متخصص في التحفيظ", "Memorisation specialist"),
        ("🔤", "متخصص في اللغة العربية", "Arabic specialist"),
        ("💬", "تواصل ممتاز", "Great communicator"),
        ("😊", "ودود", "Friendly"),
        ("📝", "تقارير مفصلة", "Detailed reports"),
        ("🧩", "مبدع في الأساليب", "Creative methods"),
        ("🌟", "الأعلى تقييمًا", "Top rated"),
        ("🆕", "معلم جديد", "New teacher"),
        ("📅", "معلم منذ سنة", "Teaching for 1 year"),
        ("🏅", "معلم الشهر", "Teacher of the month"),
    ),
}


def seed(tag_model) -> int:
    """Add every preset the current schema lacks; return how many were added.

    Idempotent: a preset is skipped when its kind already has a tag with the
    same English or Arabic name, compared case-insensitively (an academy that
    renamed or re-created one keeps its own). New presets go after the kind's
    last position."""
    added = 0
    for kind, presets in PRESETS.items():
        existing = list(
            tag_model.objects.filter(kind=kind).values_list(
                "name_en", "name_ar", "position"
            )
        )
        taken_en = {en.lower() for en, _, _ in existing}
        taken_ar = {ar.lower() for _, ar, _ in existing}
        position = max((p for _, _, p in existing), default=0)
        rows = []
        for emoji, name_ar, name_en in presets:
            if name_en.lower() in taken_en or name_ar.lower() in taken_ar:
                continue
            position += 1
            rows.append(
                tag_model(
                    kind=kind,
                    emoji=emoji,
                    name_ar=name_ar,
                    name_en=name_en,
                    position=position,
                )
            )
        tag_model.objects.bulk_create(rows)
        added += len(rows)
    return added
```

In `backend/etqan/identity/services.py`, replace:

```python
from etqan.academy import services as academy_services
from etqan.identity.emails import render_email
from etqan.identity.models import Guardianship
from etqan.identity.models import ParentProfile
from etqan.identity.models import StudentProfile
from etqan.identity.models import TeacherProfile
```

with:

```python
from etqan.academy import services as academy_services
from etqan.identity import presets
from etqan.identity.emails import render_email
from etqan.identity.models import Guardianship
from etqan.identity.models import ParentProfile
from etqan.identity.models import StudentProfile
from etqan.identity.models import Tag
from etqan.identity.models import TeacherProfile
```

Append to `backend/etqan/identity/services.py`:

```python
# ── Tags (Plan 10) ────────────────────────────────────────────────────────────


def ensure_preset_tags() -> int:
    """Seed TutorHamster's presets into the current academy; idempotent."""
    return presets.seed(Tag)
```

In `backend/etqan/tenants/services.py`, replace:

```python
        identity_services.create_academy_admin(
            email=admin_email, full_name=admin_full_name, password=admin_password
        )
    return academy
```

with:

```python
        identity_services.create_academy_admin(
            email=admin_email, full_name=admin_full_name, password=admin_password
        )
        # The presets migration already ran in the new schema; this makes the
        # spec's guarantee explicit, and is a no-op when nothing is missing.
        identity_services.ensure_preset_tags()
    return academy
```

- [ ] **Step 4: Generate the schema migration and write the data migration**

Run (from `backend/`):

```bash
.venv/bin/python manage.py makemigrations identity --name profile_depth --settings=config.settings.test
```

Expected: `etqan/identity/migrations/0013_profile_depth.py` adding `nationality`, `xp`, creating `Tag` (with its two `Lower()` constraints) and adding `tags` to both profiles. A warning that the database can't be reached for the history check is harmless.

Create `backend/etqan/identity/migrations/0014_preset_tags.py`:

```python
"""Plan 10: every academy starts with TutorHamster's preset tags.

identity migrates into the public schema too (Etqan staff accounts), which
has no people and so gets no tags. Idempotent: a preset whose name the
academy already uses is skipped."""

from django.db import migrations
from django_tenants.utils import get_public_schema_name

from etqan.identity import presets


def forwards(apps, schema_editor):
    if schema_editor.connection.schema_name == get_public_schema_name():
        return
    presets.seed(apps.get_model("identity", "Tag"))


class Migration(migrations.Migration):
    dependencies = [("identity", "0013_profile_depth")]
    operations = [migrations.RunPython(forwards, migrations.RunPython.noop)]
```

- [ ] **Step 5: Format, then run the tests on a fresh test database**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/identity/tests/test_tags.py etqan/tenants/tests/test_services.py -q --create-db
```

Expected: 30 passed. `--create-db` matters: the test academies are created once per database, and only a fresh one runs `0014` in them.

- [ ] **Step 6: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1275 tests, coverage 97.9%.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/identity etqan/tenants/services.py etqan/tenants/tests/test_services.py
git -C backend commit -m "feat(identity): tags with TutorHamster's presets, XP and nationality

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The tags admin: list, add, rename, move, retire and restore (`/api/v1/people/tags/`)

**Files:**
- Modify: `backend/etqan/identity/services.py`, `backend/etqan/identity/api/payloads.py`, `backend/etqan/identity/api/people_serializers.py`, `backend/etqan/identity/api/people_views.py`, `backend/etqan/identity/api/people_urls.py`
- Test: `backend/etqan/identity/tests/test_tags_api.py` (new)

**Interfaces:**
- Consumes: Task 1's `Tag`, `StudentProfile.tags`, `ensure_preset_tags`.
- Produces:
  - `services.TAG_FIELDS`; `services.tags_queryset(kind: str | None = None) -> QuerySet[Tag]` (list order; each row annotated `people`, the active people with it); `services.get_tag(tag_id) -> Tag` (annotated; `NotFoundError`); `services.create_tag(*, kind, name_ar, name_en, emoji="") -> Tag` (last in its kind); `services.update_tag(tag, *, fields: dict) -> Tag` (`emoji, name_ar, name_en, position, is_active`; `position` is the 1-based place, and the kind is renumbered 1..n);
  - `payloads.tag_chip(tag) -> {id, emoji, name_ar, name_en}` and `payloads.tag_row(tag) -> {id, emoji, name_ar, name_en, kind, position, is_active, people}`;
  - `GET /api/v1/people/tags/?kind=student|teacher` (array, not paginated), `POST /api/v1/people/tags/` (201, fresh read), `PATCH /api/v1/people/tags/<id>/` (fresh read); no GET/PUT/DELETE on one tag. Admins only.

- [ ] **Step 1: Write the failing tests**

Non-admins get 403 everywhere. The list is in order with the active people on each, and a bad `kind` is a 400. A new tag goes last and answers with a fresh read. A duplicate name in either language, whatever the case or surrounding spaces, a blank or too-long name, or a too-long emoji, is a 400 on that field, and the same name on the other kind is fine. Renaming never clashes, and the kind never changes. Retiring keeps every assignment. A move renumbers the kind and heals ties and gaps. There is no GET, PUT or DELETE on one tag. Another academy's tags are never visible or editable. The services refuse what the API refuses. The list's query count is flat whatever the people. People are tagged through the model here: assigning through the people API is Task 3.

Create `backend/etqan/identity/tests/test_tags_api.py`:

```python
"""Plan 10 §4.1 and §5: the tags admin at /api/v1/people/tags/."""

import pytest
from django.db import connection
from django.db.models import Max
from django.test.utils import CaptureQueriesContext
from django_tenants.utils import tenant_context
from rest_framework.test import APIClient

from etqan.identity import services
from etqan.identity.models import Tag
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
TAGS = "/api/v1/people/tags/"
ROW_KEYS = {"id", "kind", "emoji", "name_ar", "name_en", "position", "is_active"}


@pytest.fixture
def admin(api_for):
    return api_for("admin")


def tag(name_en, kind="student"):
    return Tag.objects.get(kind=kind, name_en=name_en)


def student(name, *tags):
    user = services.create_person("student", full_name=name, profile={})
    services.get_student_profile(user.pk).tags.add(*tags)
    return user


@pytest.mark.parametrize("role", ["teacher", "parent", "student"])
def test_non_admins_are_refused(api_for, role):
    client = api_for(role)
    star = tag("Star of the month")
    assert client.get(TAGS).status_code == 403
    body = {"kind": "student", "name_ar": "س", "name_en": "S"}
    assert client.post(TAGS, body, format="json").status_code == 403
    patch = {"is_active": False}
    assert client.patch(f"{TAGS}{star.pk}/", patch, format="json").status_code == 403
    assert APIClient().get(TAGS).status_code == 403
    assert tag("Star of the month").is_active


def test_the_list_is_in_order_with_the_active_people_on_each(admin):
    star = tag("Star of the month")
    student("Yusuf", star)
    gone = student("Zaid", star, tag("New"))
    services.deactivate(gone, by=None)
    rows = admin.get(f"{TAGS}?kind=student").json()
    assert [row["name_en"] for row in rows[:3]] == [
        "New",
        "Outstanding",
        "Star of the month",
    ]
    assert len(rows) == 21
    assert set(rows[2]) == ROW_KEYS | {"people"}
    assert (rows[2]["emoji"], rows[2]["position"], rows[2]["people"]) == ("⭐", 3, 1)
    assert rows[0]["people"] == 0  # only the deactivated Zaid has "New"
    teachers = admin.get(f"{TAGS}?kind=teacher").json()
    assert {row["kind"] for row in teachers} == {"teacher"}
    everything = admin.get(TAGS).json()
    assert [row["kind"] for row in everything] == ["student"] * 21 + ["teacher"] * 22
    resp = admin.get(f"{TAGS}?kind=parent")
    assert (resp.status_code, resp.json()) == (
        400,
        {"kind": ["Choose student or teacher."]},
    )


def test_a_new_tag_goes_last_and_answers_with_a_fresh_read(admin):
    resp = admin.post(
        TAGS,
        {
            "kind": "student",
            "emoji": " 🌙 ",
            "name_ar": " هلال ",
            "name_en": "Crescent",
        },
        format="json",
    )
    assert resp.status_code == 201, resp.json()
    body = resp.json()
    assert body == {
        "id": body["id"],
        "kind": "student",
        "emoji": "🌙",
        "name_ar": "هلال",
        "name_en": "Crescent",
        "position": 22,
        "is_active": True,
        "people": 0,
    }


@pytest.mark.parametrize(
    ("body", "field"),
    [
        ({"name_ar": "مختلف", "name_en": "star OF the MONTH"}, "name_en"),
        ({"name_ar": "مختلف", "name_en": "  Star of the month  "}, "name_en"),
        ({"name_ar": "نجم الشهر", "name_en": "Different"}, "name_ar"),
        ({"name_ar": " نجم الشهر ", "name_en": "Different"}, "name_ar"),
        ({"name_ar": "مختلف", "name_en": "   "}, "name_en"),
        ({"name_ar": "مختلف", "name_en": "x" * 61}, "name_en"),
        ({"name_ar": "مختلف", "name_en": "Nine", "emoji": "🌙" * 9}, "emoji"),
    ],
)
def test_a_bad_or_duplicate_name_is_a_400_on_that_field(admin, body, field):
    resp = admin.post(TAGS, {"kind": "student", **body}, format="json")
    assert resp.status_code == 400
    assert list(resp.json()) == [field]
    assert Tag.objects.filter(kind="student").count() == 21


def test_the_same_name_is_fine_for_the_other_kind(admin):
    body = {"kind": "teacher", "name_ar": "نجم الشهر", "name_en": "Star of the month"}
    assert admin.post(TAGS, body, format="json").status_code == 201
    unknown = {"kind": "parent", "name_ar": "س", "name_en": "S"}
    assert list(admin.post(TAGS, unknown, format="json").json()) == ["kind"]


def test_rename_and_re_emoji_but_never_a_clash(admin):
    star = tag("Star of the month")
    url = f"{TAGS}{star.pk}/"
    resp = admin.patch(
        url, {"name_en": "Star of the week", "emoji": "🌠"}, format="json"
    )
    assert resp.status_code == 200, resp.json()
    assert (resp.json()["name_en"], resp.json()["emoji"]) == ("Star of the week", "🌠")
    assert resp.json()["name_ar"] == "نجم الشهر"
    clash = admin.patch(url, {"name_en": "new"}, format="json")
    assert (clash.status_code, list(clash.json())) == (400, ["name_en"])
    clash = admin.patch(url, {"name_ar": " جديد "}, format="json")
    assert (clash.status_code, list(clash.json())) == (400, ["name_ar"])
    # Its own name, in another case, is not a clash.
    same = admin.patch(url, {"name_en": "STAR OF THE WEEK"}, format="json")
    assert same.status_code == 200
    # The kind never changes.
    moved = admin.patch(url, {"kind": "teacher"}, format="json")
    assert (moved.status_code, moved.json()["kind"]) == (200, "student")


def test_retiring_keeps_every_assignment_and_restoring_reopens_it(admin):
    star = tag("Star of the month")
    yusuf = student("Yusuf", star)
    url = f"{TAGS}{star.pk}/"
    resp = admin.patch(url, {"is_active": False}, format="json")
    assert (resp.json()["is_active"], resp.json()["people"]) == (False, 1)
    assert list(services.get_student_profile(yusuf.pk).tags.all()) == [star]
    assert admin.patch(url, {"is_active": True}, format="json").json()["is_active"]


def test_moving_a_tag_renumbers_its_kind(admin):
    star = tag("Star of the month")
    resp = admin.patch(f"{TAGS}{star.pk}/", {"position": 1}, format="json")
    assert resp.json()["position"] == 1
    names = [row["name_en"] for row in admin.get(f"{TAGS}?kind=student").json()]
    assert names[:4] == [
        "Star of the month",
        "New",
        "Outstanding",
        "Proficient memoriser",
    ]
    last = admin.patch(f"{TAGS}{star.pk}/", {"position": 99}, format="json").json()
    assert last["position"] == 21
    positions = Tag.objects.filter(kind="student").values_list("position", flat=True)
    assert sorted(positions) == list(range(1, 22))
    zero = admin.patch(f"{TAGS}{star.pk}/", {"position": 0}, format="json")
    assert (zero.status_code, list(zero.json())) == (400, ["position"])
    teachers = Tag.objects.filter(kind="teacher").values_list("position", flat=True)
    assert sorted(teachers) == list(range(1, 23))


def test_there_is_no_get_put_or_delete_on_one_tag(admin):
    url = f"{TAGS}{tag('New').pk}/"
    assert admin.get(url).status_code == 405
    assert admin.put(url, {"name_en": "X"}, format="json").status_code == 405
    assert admin.delete(url).status_code == 405
    assert admin.patch(f"{TAGS}999999/", {}, format="json").status_code == 404
    assert Tag.objects.filter(kind="student").count() == 21


def test_another_academys_tags_are_never_visible_or_editable(admin, tenants):
    ceiling = Tag.objects.aggregate(top=Max("pk"))["top"]
    with tenant_context(tenants.other):
        theirs = until_pk_exceeds(
            Tag,
            ceiling,
            lambda: services.create_tag(
                kind="student", name_ar="غريب", name_en="Foreign"
            ),
        )
    assert theirs.pk > ceiling
    names = [row["name_en"] for row in admin.get(TAGS).json()]
    assert "Foreign" not in names
    assert "New" in names  # this academy's own
    resp = admin.patch(f"{TAGS}{theirs.pk}/", {"is_active": False}, format="json")
    assert resp.status_code == 404
    with tenant_context(tenants.other):
        theirs.refresh_from_db()
        assert theirs.is_active


def test_the_services_hold_the_same_rules_without_the_api():
    with pytest.raises(ValidationError) as caught:
        services.create_tag(kind="parent", name_ar="س", name_en="S")
    assert caught.value.field == "kind"
    with pytest.raises(ValidationError) as caught:
        services.create_tag(kind="student", name_ar="س", name_en="  ")
    assert (caught.value.field, caught.value.message) == ("name_en", "Enter a name.")
    with pytest.raises(ValidationError) as caught:
        services.create_tag(kind="student", name_ar="س", name_en="S", emoji="🌙" * 9)
    assert caught.value.field == "emoji"
    star = services.get_tag(tag("Star of the month").pk)
    for fields, field in (({"kind": "teacher"}, "kind"), ({"position": 0}, "position")):
        with pytest.raises(ValidationError) as caught:
            services.update_tag(star, fields=fields)
        assert caught.value.field == field
    with pytest.raises(NotFoundError):
        services.get_tag(999999)
    assert tag("Star of the month").position == 3


def test_a_move_heals_ties_and_gaps(admin):
    # Two tags added at once can share a place; an old list can have gaps.
    Tag.objects.filter(kind="student", name_en="Outstanding").update(position=1)
    Tag.objects.filter(kind="student", name_en="Curious").update(position=40)
    curious = tag("Curious")
    resp = admin.patch(f"{TAGS}{curious.pk}/", {"position": 2}, format="json")
    assert resp.json()["position"] == 2
    names = [row["name_en"] for row in admin.get(f"{TAGS}?kind=student").json()]
    assert names[:3] == ["New", "Curious", "Outstanding"]
    positions = Tag.objects.filter(kind="student").values_list("position", flat=True)
    assert sorted(positions) == list(range(1, 22))


def test_the_tag_list_is_one_query_whatever_the_people(admin):
    star = tag("Star of the month")
    student("A", star)
    with CaptureQueriesContext(connection) as one:
        assert admin.get(TAGS).status_code == 200
    for name in ("B", "C"):
        student(name, star, tag("New"))
    with CaptureQueriesContext(connection) as three:
        assert admin.get(TAGS).json()[2]["people"] == 3
    assert len(three) == len(one)
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/identity/tests/test_tags_api.py -q`

Expected: FAIL — `AttributeError: module 'etqan.identity.services' has no attribute 'create_tag'` in the cross-academy test and the services test; 404s on `/api/v1/people/tags/` elsewhere.

- [ ] **Step 3: Implement the services**

In `backend/etqan/identity/services.py`, replace:

```python
from django.db import transaction
from django.db.models import QuerySet
```

with:

```python
from django.db import transaction
from django.db.models import Count
from django.db.models import Max
from django.db.models import Q
from django.db.models import QuerySet
```

Append to `backend/etqan/identity/services.py`:

```python
TAG_FIELDS = frozenset({"emoji", "name_ar", "name_en", "position", "is_active"})


def _active_people(relation: str) -> Count:
    active = Q(**{f"{relation}__user__is_active": True})
    return Count(relation, filter=active, distinct=True)


def tags_queryset(kind: str | None = None) -> QuerySet[Tag]:
    """Tags in list order (position, then id), each annotated with ``people``:
    how many active people have it (a tag has one kind, so one term is 0)."""
    queryset = Tag.objects.annotate(
        people=_active_people("students") + _active_people("teachers")
    )
    if kind is not None:
        queryset = queryset.filter(kind=kind)
    return queryset.order_by("kind", "position", "id")


def get_tag(tag_id: int) -> Tag:
    try:
        return tags_queryset().get(pk=tag_id)
    except Tag.DoesNotExist:
        raise NotFoundError("Tag", tag_id) from None


def _check_tag(tag: Tag) -> None:
    """Trimmed names, unique within the kind in either language whatever the
    case (400 on that name, D2), and the model's own limits."""
    tag.emoji = (tag.emoji or "").strip()
    for field in ("name_en", "name_ar"):
        value = (getattr(tag, field) or "").strip()
        setattr(tag, field, value)
        if not value:
            raise ValidationError("Enter a name.", field=field)
        clash = Tag.objects.filter(kind=tag.kind, **{f"{field}__iexact": value})
        if clash.exclude(pk=tag.pk).exists():
            raise ValidationError("A tag with this name already exists.", field=field)
    try:
        tag.full_clean(validate_unique=False, validate_constraints=False)
    except DjangoValidationError as exc:
        raise from_django(exc) from None


@transaction.atomic
def create_tag(*, kind: str, name_ar: str, name_en: str, emoji: str = "") -> Tag:
    """A new tag, last in its kind's list."""
    if kind not in Tag.Kind.values:
        raise ValidationError("Choose student or teacher.", field="kind")
    last = Tag.objects.filter(kind=kind).aggregate(last=Max("position"))["last"]
    tag = Tag(
        kind=kind,
        name_ar=name_ar,
        name_en=name_en,
        emoji=emoji,
        position=(last or 0) + 1,
    )
    _check_tag(tag)
    tag.save()
    return tag


def _move(tag: Tag, position: int) -> None:
    """Put ``tag`` at the 1-based ``position`` of its kind's list (past the
    end means last) and renumber the kind 1..n, so ties never linger (D8)."""
    siblings = list(
        Tag.objects.select_for_update()
        .filter(kind=tag.kind)
        .exclude(pk=tag.pk)
        .order_by("position", "id")
    )
    siblings.insert(min(position, len(siblings) + 1) - 1, tag)
    for number, sibling in enumerate(siblings, start=1):
        sibling.position = number
    Tag.objects.bulk_update(siblings, ["position"])


@transaction.atomic
def update_tag(tag: Tag, *, fields: dict) -> Tag:
    """Rename, re-emoji, retire or restore a tag, or move it (``position``).
    The kind never changes, and nothing is ever deleted (PD-2)."""
    unknown = sorted(set(fields) - TAG_FIELDS)
    if unknown:
        raise ValidationError("Unknown field.", field=unknown[0])
    position = fields.get("position")
    if position is not None and position < 1:
        raise ValidationError("Choose a position of 1 or more.", field="position")
    for key in ("emoji", "name_ar", "name_en", "is_active"):
        if key in fields:
            setattr(tag, key, fields[key])
    _check_tag(tag)
    tag.save()
    if position is not None:
        _move(tag, position)
    return tag
```

- [ ] **Step 4: Implement the payload, serializers, views and routes**

In `backend/etqan/identity/api/payloads.py`, replace:

```python
from etqan.identity import services
from etqan.identity.models import User
```

with:

```python
from etqan.identity import services
from etqan.identity.models import Tag
from etqan.identity.models import User
```

In `backend/etqan/identity/api/payloads.py`, replace:

```python
def _student_profile(p, _course_ids) -> dict:
```

with:

```python
def tag_chip(tag: Tag) -> dict:
    """A tag as a person's row shows it."""
    return {
        "id": tag.id,
        "emoji": tag.emoji,
        "name_ar": tag.name_ar,
        "name_en": tag.name_en,
    }


def tag_row(tag: Tag) -> dict:
    """A row of the tags admin; ``tag`` comes from ``services.tags_queryset``."""
    return {
        **tag_chip(tag),
        "kind": tag.kind,
        "position": tag.position,
        "is_active": tag.is_active,
        "people": tag.people,
    }


def _student_profile(p, _course_ids) -> dict:
```

In `backend/etqan/identity/api/people_serializers.py`, replace:

```python
from etqan.identity.models import StudentProfile
from etqan.identity.models import TeacherProfile
```

with:

```python
from etqan.identity.models import StudentProfile
from etqan.identity.models import Tag
from etqan.identity.models import TeacherProfile
```

Append to `backend/etqan/identity/api/people_serializers.py`:

```python
class TagCreateSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=Tag.Kind.choices)
    emoji = serializers.CharField(max_length=8, required=False, allow_blank=True)
    name_ar = serializers.CharField(max_length=60)
    name_en = serializers.CharField(max_length=60)


class TagUpdateSerializer(serializers.Serializer):
    """PATCH only: a tag's kind never changes, so ``kind`` is not accepted."""

    emoji = serializers.CharField(max_length=8, required=False, allow_blank=True)
    name_ar = serializers.CharField(max_length=60, required=False)
    name_en = serializers.CharField(max_length=60, required=False)
    position = serializers.IntegerField(min_value=1, required=False)
    is_active = serializers.BooleanField(required=False)
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
from etqan.identity.api.payloads import person_summary
from etqan.identity.api.people_filters import filter_people
from etqan.identity.api.people_serializers import GuardianLinkSerializer
from etqan.identity.api.people_serializers import PersonWriteSerializer
from etqan.identity.api.people_serializers import StudentBulkSerializer
from etqan.identity.api.people_serializers import as_drf
```

with:

```python
from etqan.identity.api.payloads import person_summary
from etqan.identity.api.payloads import tag_row
from etqan.identity.api.people_filters import filter_people
from etqan.identity.api.people_serializers import GuardianLinkSerializer
from etqan.identity.api.people_serializers import PersonWriteSerializer
from etqan.identity.api.people_serializers import StudentBulkSerializer
from etqan.identity.api.people_serializers import TagCreateSerializer
from etqan.identity.api.people_serializers import TagUpdateSerializer
from etqan.identity.api.people_serializers import as_drf
from etqan.identity.models import Tag
```

Append to `backend/etqan/identity/api/people_views.py`:

```python
class TagListCreateView(APIView):
    """The academy's tags (Plan 10 §5): admins only, never paginated (D8)."""

    permission_classes = [IsAdmin]

    def get(self, request):
        kind = request.query_params.get("kind") or None
        if kind is not None and kind not in Tag.Kind.values:
            raise EtqanValidationError("Choose student or teacher.", field="kind")
        return Response([tag_row(tag) for tag in services.tags_queryset(kind)])

    def post(self, request):
        serializer = TagCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        tag = services.create_tag(**serializer.validated_data)
        return Response(
            tag_row(services.get_tag(tag.pk)), status=status.HTTP_201_CREATED
        )


class TagDetailView(APIView):
    """PATCH only: there is no GET, PUT or DELETE on one tag (§5)."""

    permission_classes = [IsAdmin]

    def patch(self, request, pk):
        tag = services.get_tag(pk)
        serializer = TagUpdateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        services.update_tag(tag, fields=dict(serializer.validated_data))
        return Response(tag_row(services.get_tag(tag.pk)))
```

In `backend/etqan/identity/api/people_urls.py`, replace:

```python
    re_path(r"^students/bulk/$", views.StudentBulkView.as_view(), name="bulk"),
```

with:

```python
    re_path(r"^students/bulk/$", views.StudentBulkView.as_view(), name="bulk"),
    re_path(r"^tags/$", views.TagListCreateView.as_view(), name="tags"),
    re_path(r"^tags/(?P<pk>\d+)/$", views.TagDetailView.as_view(), name="tag"),
```

- [ ] **Step 5: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/identity/tests/test_tags_api.py -q
```

Expected: 21 passed.

- [ ] **Step 6: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1296 tests, coverage 98.0%.

- [ ] **Step 7: Commit**

```bash
git -C backend add etqan/identity
git -C backend commit -m "feat(identity): the tags admin: add, rename, move, retire and restore

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Tags, XP, nationality and the age group on people, one by one, in bulk, and in `me/`

**Files:**
- Create: `backend/etqan/identity/ages.py`, `backend/etqan/identity/clock.py`
- Modify: `backend/etqan/identity/services.py`, `backend/etqan/identity/api/payloads.py`, `backend/etqan/identity/api/people_serializers.py`, `backend/etqan/identity/api/people_views.py`, `backend/etqan/identity/api/views.py`
- Test: `backend/etqan/identity/tests/test_ages.py`, `backend/etqan/identity/tests/test_profile_depth.py`, `backend/etqan/identity/tests/test_profile_access.py` (all new)

**Interfaces:**
- Consumes: Task 1's models; Task 2's `tag_chip`, `update_tag`, `create_tag`.
- Produces:
  - `etqan.identity.clock.now() -> datetime`, `clock.today() -> date` (the academy's calendar);
  - `etqan.identity.ages`: `CHILD, TEEN, ADULT, MINOR`, `AGE_GROUPS`, `FILTERS`, `years_before(day, years) -> date`, `cutoffs(today) -> (teen_cut, adult_cut)`, `age_group(dob, *, today) -> str | None`, `born_lookups(group, *, today) -> dict[str, date] | None`;
  - `profile.tag_ids`, `profile.xp`, `profile.nationality` on `create_person`/`update_person` (students; teachers take `tag_ids`), errors on `tag_ids`/`xp`/`nationality`;
  - `services.BULK_ACTIONS` gains `add_tag`, `remove_tag`; `services.TAG_ACTIONS`; `bulk_update_students(ids, action, *, status=None, tag_id=None, by=None)`;
  - `payloads.STAFF_ONLY = ("notes", "nationality")`; `profile_payload(user, *, staff: bool, course_ids=None, today=None)`; student profiles gain `xp, nationality, age_group, tags`, teacher profiles `tags`;
  - `me/`: a student's `profile` and a parent's `children[].profile` gain `tags, xp, age_group` (no `nationality`, no `notes`); a teacher's gains `tags`. Each child's tags are prefetched, so a parent's `me/` stays flat.

- [ ] **Step 1: Write the failing tests**

The age group turns over on the birthday, 29 February included, and each filter is a date range on the same cut-offs. On people:
- tags, XP and nationality save, and tags list in tag order;
- `tag_ids` replaces the whole set;
- teachers take teacher tags;
- a wrong-kind, unknown, other-academy or retired tag is refused, and a parent has no tags;
- a retired tag survives every edit of its person until removed;
- XP and nationality keep their limits.

In bulk, add and remove touch only the selected students; removing a tag nobody has changes nothing; the assignment rules hold. Through the API, rows carry the new fields, errors nest under `profile.tag_ids`, and the age groups in rows turn over on the birthday. Access: admins see nationality and no one else does; `me/` shows a student and a parent's children their tags, XP and age group, and a teacher their tags; every tag route and the bulk tag actions are admin-only; a parent's `me/` stays flat as tagged children grow.

Create `backend/etqan/identity/tests/test_ages.py`:

```python
"""Plan 10 PD-5: child under 13, teen 13-17, adult 18 and over."""

from datetime import date

import pytest

from etqan.identity import ages


@pytest.mark.parametrize(
    ("born", "group"),
    [
        (date(2013, 6, 2), "child"),  # 13 tomorrow
        (date(2013, 6, 1), "teen"),  # 13 today
        (date(2008, 6, 2), "teen"),  # 18 tomorrow
        (date(2008, 6, 1), "adult"),  # 18 today
        (date(2026, 1, 1), "child"),
        (date(1960, 1, 1), "adult"),
        (None, None),
    ],
)
def test_the_group_turns_over_on_the_birthday(born, group):
    assert ages.age_group(born, today=date(2026, 6, 1)) == group


def test_a_29_february_birthday_comes_round_on_1_march_in_a_common_year():
    leap = date(2016, 2, 29)
    assert ages.age_group(leap, today=date(2029, 2, 28)) == "child"
    assert ages.age_group(leap, today=date(2029, 3, 1)) == "teen"
    # In a leap year it is the day itself.
    assert ages.age_group(date(2015, 2, 28), today=date(2028, 2, 28)) == "teen"
    assert ages.age_group(date(2015, 3, 1), today=date(2028, 2, 29)) == "child"
    assert ages.years_before(date(2028, 2, 29), 13) == date(2015, 2, 28)


@pytest.mark.parametrize(
    ("group", "lookups"),
    [
        ("child", {"gt": date(2013, 6, 1)}),
        ("teen", {"gt": date(2008, 6, 1), "lte": date(2013, 6, 1)}),
        ("adult", {"lte": date(2008, 6, 1)}),
        ("minor", {"gt": date(2008, 6, 1)}),
        ("elder", None),
    ],
)
def test_each_filter_is_a_date_range_on_the_same_cutoffs(group, lookups):
    assert ages.born_lookups(group, today=date(2026, 6, 1)) == lookups
```

Create `backend/etqan/identity/tests/test_profile_depth.py`:

```python
"""Plan 10 §4.2: tags, XP and nationality on people, one by one and in bulk."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db.models import Max
from django_tenants.utils import tenant_context

from etqan.identity import clock
from etqan.identity import services
from etqan.identity.models import Tag
from etqan.platform.exceptions import ValidationError
from etqan.scheduling.tests.conftest import until_pk_exceeds

pytestmark = pytest.mark.django_db
B = "/api/v1/people/"
CHIP_KEYS = {"id", "emoji", "name_ar", "name_en"}


@pytest.fixture
def admin(api_for):
    return api_for("admin")


@pytest.fixture
def pinned(monkeypatch):
    """Monday 1 June 2026, 08:00 UTC on identity's clock (the academy is UTC)."""
    monkeypatch.setattr(clock, "now", lambda: datetime(2026, 6, 1, 8, tzinfo=UTC))


def tag(name_en, kind="student"):
    return Tag.objects.get(kind=kind, name_en=name_en)


def ids(*tags):
    return [t.pk for t in tags]


def student(name="Yusuf", **profile):
    return services.create_person("student", full_name=name, profile=profile)


def tags_of(user):
    profile = services.get_student_profile(user.pk) or services.get_teacher_profile(
        user.pk
    )
    return [t.name_en for t in profile.tags.all()]


def retire(t):
    services.update_tag(t, fields={"is_active": False})


class TestAssigning:
    def test_tags_xp_and_nationality_are_saved_and_listed_in_tag_order(self):
        star, new = tag("Star of the month"), tag("New")
        user = student(tag_ids=ids(star, new, star), xp=120, nationality="arab")
        profile = services.get_student_profile(user.pk)
        assert (profile.xp, profile.nationality) == (120, "arab")
        assert tags_of(user) == ["New", "Star of the month"]  # by position

    def test_tag_ids_replace_the_whole_set(self):
        user = student(tag_ids=ids(tag("New"), tag("Outstanding")))
        services.update_person(user, profile={"tag_ids": ids(tag("Curious"))})
        assert tags_of(user) == ["Curious"]
        services.update_person(user, profile={"tag_ids": []})
        assert tags_of(user) == []

    def test_a_teacher_has_teacher_tags(self):
        patient = tag("Patient", "teacher")
        teacher = services.create_person(
            "teacher",
            full_name="Bilal",
            profile={"gender": "male", "tag_ids": [patient.pk]},
        )
        assert tags_of(teacher) == ["Patient"]

    @pytest.mark.parametrize(
        ("role", "profile"),
        [
            ("student", {"tag_ids": "teacher"}),
            ("teacher", {"gender": "male", "tag_ids": "student"}),
            ("student", {"tag_ids": [999999]}),
        ],
    )
    def test_a_wrong_kind_or_unknown_tag_is_refused(self, role, profile):
        if isinstance(profile["tag_ids"], str):
            profile["tag_ids"] = [Tag.objects.filter(kind=profile["tag_ids"])[0].pk]
        with pytest.raises(ValidationError) as caught:
            services.create_person(role, full_name="X", profile=profile)
        assert (caught.value.field, caught.value.message) == (
            "tag_ids",
            "Choose tags from the list.",
        )
        assert not services.people_queryset(role).filter(full_name="X").exists()

    def test_a_parent_or_admin_has_no_tags(self):
        with pytest.raises(ValidationError) as caught:
            services.create_person(
                "parent", full_name="Omar", profile={"tag_ids": ids(tag("New"))}
            )
        assert caught.value.field == "tag_ids"

    def test_a_retired_tag_cannot_be_added(self):
        star = tag("Star of the month")
        retire(star)
        with pytest.raises(ValidationError) as caught:
            student(tag_ids=ids(star))
        assert (caught.value.field, caught.value.message) == (
            "tag_ids",
            "A retired tag can't be added.",
        )

    def test_a_retired_tag_survives_every_edit_of_its_person(self):
        star, new = tag("Star of the month"), tag("New")
        user = student(tag_ids=ids(star))
        retire(star)
        services.update_person(user, fields={"full_name": "Yusuf Omar"})
        services.update_person(user, profile={"xp": 5})
        assert tags_of(user) == ["Star of the month"]
        services.update_person(user, profile={"tag_ids": ids(star, new)})
        assert tags_of(user) == ["New", "Star of the month"]
        services.update_person(user, profile={"tag_ids": ids(new)})
        assert tags_of(user) == ["New"]
        with pytest.raises(ValidationError):  # gone once removed
            services.update_person(user, profile={"tag_ids": ids(star, new)})
        assert tags_of(user) == ["New"]

    @pytest.mark.parametrize(
        ("profile", "field"),
        [
            ({"xp": -1}, "xp"),
            ({"xp": 1_000_001}, "xp"),
            ({"nationality": "martian"}, "nationality"),
        ],
    )
    def test_xp_and_nationality_limits(self, profile, field):
        with pytest.raises(ValidationError) as caught:
            student(**profile)
        assert caught.value.field == field

    def test_xp_up_to_a_million_and_a_blank_nationality(self):
        user = student(xp=1_000_000, nationality="foreign")
        services.update_person(user, profile={"nationality": None})
        profile = services.get_student_profile(user.pk)
        assert (profile.xp, profile.nationality) == (1_000_000, "")


class TestBulk:
    def test_add_and_remove_a_tag_on_the_selected_students_only(self):
        star = tag("Star of the month")
        a, b, c = student("A"), student("B", tag_ids=ids(star)), student("C")
        teacher = services.create_person(
            "teacher", full_name="T", profile={"gender": "male"}
        )
        count = services.bulk_update_students(
            [a.pk, b.pk, teacher.pk], "add_tag", tag_id=star.pk
        )
        assert count == 2
        assert [tags_of(u) for u in (a, b, c)] == [
            ["Star of the month"],
            ["Star of the month"],
            [],
        ]
        assert tags_of(teacher) == []
        retire(star)  # removing a retired tag is how an academy clears it
        assert services.bulk_update_students([a.pk], "remove_tag", tag_id=star.pk) == 1
        assert [tags_of(u) for u in (a, b)] == [[], ["Star of the month"]]

    def test_removing_a_tag_nobody_has_changes_nothing(self):
        star, new = tag("Star of the month"), tag("New")
        a, b = student("A", tag_ids=ids(new)), student("B")
        parent = services.create_person("parent", full_name="P", profile={})
        count = services.bulk_update_students(
            [a.pk, b.pk, parent.pk], "remove_tag", tag_id=star.pk
        )
        assert count == 2
        assert [tags_of(a), tags_of(b)] == [["New"], []]

    @pytest.mark.parametrize(
        ("action", "which", "message"),
        [
            ("add_tag", "retired", "A retired tag can't be added."),
            ("add_tag", "teacher", "Choose a tag from the list."),
            ("remove_tag", "teacher", "Choose a tag from the list."),
            ("add_tag", "none", "Choose a tag from the list."),
        ],
    )
    def test_the_assignment_rules_hold_in_bulk(self, action, which, message):
        user = student()
        star = tag("Star of the month")
        tag_id = {
            "retired": star.pk,
            "teacher": tag("Patient", "teacher").pk,
            "none": None,
        }[which]
        retire(star)
        with pytest.raises(ValidationError) as caught:
            services.bulk_update_students([user.pk], action, tag_id=tag_id)
        assert (caught.value.field, caught.value.message) == ("tag_id", message)
        assert tags_of(user) == []


class TestApi:
    def test_create_and_read_a_student_with_tags_xp_and_nationality(
        self, admin, pinned
    ):
        star = tag("Star of the month")
        resp = admin.post(
            f"{B}students/",
            {
                "user": {"full_name": "Aisha"},
                "profile": {
                    "tag_ids": [star.pk],
                    "xp": 120,
                    "nationality": "arab",
                    "date_of_birth": "2015-03-10",
                },
            },
            format="json",
        )
        assert resp.status_code == 201, resp.json()
        profile = resp.json()["profile"]
        assert profile["tags"] == [
            {
                "id": star.pk,
                "emoji": "⭐",
                "name_ar": "نجم الشهر",
                "name_en": star.name_en,
            }
        ]
        assert set(profile["tags"][0]) == CHIP_KEYS
        assert (profile["xp"], profile["nationality"], profile["age_group"]) == (
            120,
            "arab",
            "child",
        )
        detail = admin.get(f"{B}students/{resp.json()['id']}/").json()
        assert detail["profile"] == profile

    def test_a_student_without_a_birthday_has_no_age_group(self, admin):
        user = student()
        body = admin.get(f"{B}students/{user.pk}/").json()["profile"]
        assert (body["age_group"], body["tags"], body["xp"], body["nationality"]) == (
            None,
            [],
            0,
            "",
        )

    def test_teacher_rows_carry_their_tags(self, admin):
        expert = tag("Expert", "teacher")
        resp = admin.post(
            f"{B}teachers/",
            {
                "user": {"full_name": "Bilal"},
                "profile": {"gender": "male", "tag_ids": [expert.pk]},
            },
            format="json",
        )
        assert resp.status_code == 201, resp.json()
        assert [t["name_en"] for t in resp.json()["profile"]["tags"]] == ["Expert"]
        assert "xp" not in resp.json()["profile"]

    def test_a_bad_tag_is_a_400_on_profile_tag_ids_and_changes_nothing(self, admin):
        user = student(tag_ids=ids(tag("New")))
        url = f"{B}students/{user.pk}/"
        body = {
            "user": {"full_name": "Renamed"},
            "profile": {"xp": 50, "tag_ids": [tag("Patient", "teacher").pk]},
        }
        resp = admin.patch(url, body, format="json")
        assert resp.status_code == 400
        assert resp.json() == {"profile": {"tag_ids": ["Choose tags from the list."]}}
        after = admin.get(url).json()
        assert (after["user"]["full_name"], after["profile"]["xp"]) == ("Yusuf", 0)
        assert [t["name_en"] for t in after["profile"]["tags"]] == ["New"]
        resp = admin.patch(url, {"profile": {"xp": 1_000_001}}, format="json")
        assert list(resp.json()["profile"]) == ["xp"]

    def test_bulk_add_and_remove_through_the_api(self, admin):
        star = tag("Star of the month")
        a, b = student("A"), student("B")
        body = {"ids": [a.pk, b.pk], "action": "add_tag", "tag_id": star.pk}
        resp = admin.post(f"{B}students/bulk/", body, format="json")
        assert resp.json() == {"updated": 2}
        assert tags_of(b) == ["Star of the month"]
        body = {"ids": [b.pk], "action": "remove_tag", "tag_id": star.pk}
        assert admin.post(f"{B}students/bulk/", body, format="json").json() == {
            "updated": 1
        }
        assert tags_of(b) == []
        missing = {"ids": [a.pk], "action": "add_tag"}
        resp = admin.post(f"{B}students/bulk/", missing, format="json")
        assert (resp.status_code, resp.json()) == (400, {"tag_id": ["Choose a tag."]})
        retire(star)
        retired = {"ids": [b.pk], "action": "add_tag", "tag_id": star.pk}
        resp = admin.post(f"{B}students/bulk/", retired, format="json")
        assert (resp.status_code, resp.json()) == (
            400,
            {"tag_id": ["A retired tag can't be added."]},
        )
        assert tags_of(b) == []

    def test_another_academys_tag_is_never_assignable(self, admin, tenants):
        user = student()
        ceiling = Tag.objects.aggregate(top=Max("pk"))["top"]
        with tenant_context(tenants.other):
            theirs = until_pk_exceeds(
                Tag,
                ceiling,
                lambda: services.create_tag(
                    kind="student", name_ar="غريب", name_en="Foreign"
                ),
            )
        assert theirs.pk > ceiling
        url = f"{B}students/{user.pk}/"
        resp = admin.patch(url, {"profile": {"tag_ids": [theirs.pk]}}, format="json")
        assert resp.status_code == 400
        body = {"ids": [user.pk], "action": "add_tag", "tag_id": theirs.pk}
        assert admin.post(f"{B}students/bulk/", body, format="json").status_code == 400
        assert tags_of(user) == []
        mine = tag("New")  # while this academy's own tag works
        resp = admin.patch(url, {"profile": {"tag_ids": [mine.pk]}}, format="json")
        assert resp.status_code == 200


def test_age_groups_in_rows_turn_over_on_the_birthday(admin, pinned):
    born = {
        "Twelve": date(2013, 6, 2),
        "Thirteen": date(2013, 6, 1),
        "Seventeen": date(2008, 6, 2),
        "Eighteen": date(2008, 6, 1),
    }
    for name, day in born.items():
        student(name, date_of_birth=day)
    rows = admin.get(f"{B}students/").json()["results"]
    groups = {row["user"]["full_name"]: row["profile"]["age_group"] for row in rows}
    assert groups == {
        "Eighteen": "adult",
        "Seventeen": "teen",
        "Thirteen": "teen",
        "Twelve": "child",
    }
```

Create `backend/etqan/identity/tests/test_profile_access.py`:

```python
"""Plan 10 §4.3: who sees what. Nationality is admin-only everywhere; a
student sees their own tags, XP and age group through me/, a parent each
child's, a teacher their own tags; the tag routes are admin-only."""

from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from etqan.identity import clock
from etqan.identity import services
from etqan.identity.models import Tag

pytestmark = pytest.mark.django_db
B = "/api/v1/people/"
ME = "/api/v1/identity/me/"


@pytest.fixture
def admin(api_for):
    return api_for("admin")


@pytest.fixture
def pinned(monkeypatch):
    """Monday 1 June 2026, 08:00 UTC on identity's clock (the academy is UTC)."""
    monkeypatch.setattr(clock, "now", lambda: datetime(2026, 6, 1, 8, tzinfo=UTC))


def tag(name_en, kind="student"):
    return Tag.objects.get(kind=kind, name_en=name_en)


def student(name, *tags, email=None, **profile):
    return services.create_person(
        "student",
        full_name=name,
        email=email,
        invite=False,
        profile={"tag_ids": [t.pk for t in tags], **profile},
    )


def signed_in(user):
    client = APIClient()
    client.force_login(user)
    return client


class TestWhoSeesWhat:
    def test_admins_see_nationality_and_no_one_else_does(self, admin, pinned):
        star = tag("Star of the month")
        kid = student(
            "Yusuf",
            star,
            email="yusuf@x.test",
            xp=40,
            nationality="foreign",
            date_of_birth=date(2012, 1, 1),
        )
        other = student("Aisha", tag("New"), xp=7)
        parent = services.create_person("parent", full_name="Omar", profile={})
        services.link_guardian(parent, kid)
        admin_row = admin.get(f"{B}students/{kid.pk}/").json()["profile"]
        assert admin_row["nationality"] == "foreign"

        own = signed_in(kid).get(ME).json()["profile"]
        assert "nationality" not in own
        assert (own["xp"], own["age_group"]) == (40, "teen")
        assert [t["name_en"] for t in own["tags"]] == ["Star of the month"]

        children = signed_in(parent).get(ME).json()["children"]
        assert [c["full_name"] for c in children] == ["Yusuf"]  # not Aisha
        child = children[0]["profile"]
        assert "nationality" not in child
        assert (child["xp"], child["age_group"]) == (40, "teen")
        assert [t["id"] for t in child["tags"]] == [star.pk]
        assert other.pk not in [c["id"] for c in children]
        for client in (signed_in(kid), signed_in(parent)):
            assert "foreign" not in client.get(ME).content.decode()

    def test_a_teacher_sees_their_own_tags(self):
        kareem = services.create_person(
            "teacher",
            full_name="Kareem",
            profile={
                "gender": "male",
                "tag_ids": [tag("Patient", "teacher").pk, tag("Expert", "teacher").pk],
            },
        )
        profile = signed_in(kareem).get(ME).json()["profile"]
        assert [t["name_en"] for t in profile["tags"]] == ["Expert", "Patient"]

    @pytest.mark.parametrize("role", ["teacher", "parent", "student"])
    def test_every_tag_route_and_the_bulk_tag_actions_are_admin_only(
        self, api_for, role
    ):
        client = api_for(role)
        kid = student("Yusuf")
        star = tag("Star of the month")
        body = {"ids": [kid.pk], "action": "add_tag", "tag_id": star.pk}
        assert client.post(f"{B}students/bulk/", body, format="json").status_code == 403
        assert client.get(f"{B}students/?tag={star.pk}").status_code == 403
        assert client.get(f"{B}tags/?kind=student").status_code == 403
        assert services.get_student_profile(kid.pk).tags.count() == 0


def test_a_parents_me_is_flat_as_tagged_children_grow():
    parent = services.create_person("parent", full_name="Omar", profile={})
    star = tag("Star of the month")
    services.link_guardian(parent, student("A", star))
    client = signed_in(parent)
    with CaptureQueriesContext(connection) as one:
        assert client.get(ME).status_code == 200
    for name in ("B", "C", "D"):
        services.link_guardian(parent, student(name, star, tag("New")))
    with CaptureQueriesContext(connection) as four:
        children = client.get(ME).json()["children"]
    assert len(four) == len(one)
    assert [len(child["profile"]["tags"]) for child in children] == [1, 2, 2, 2]
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/identity/tests/test_ages.py etqan/identity/tests/test_profile_depth.py etqan/identity/tests/test_profile_access.py -q`

Expected: FAIL — collection errors: `cannot import name 'ages' from 'etqan.identity'` and `cannot import name 'clock' from 'etqan.identity'`.

- [ ] **Step 3: Implement the clock and the age groups**

Create `backend/etqan/identity/clock.py`:

```python
"""The only clock identity reads, so tests pin it by monkeypatching `now`."""

from datetime import date
from datetime import datetime
from zoneinfo import ZoneInfo

from django.utils import timezone

from etqan.academy import services as academy_services


def now() -> datetime:
    """The current instant, timezone-aware UTC."""
    return timezone.now()


def today() -> date:
    """Today on the academy's calendar (`AcademySettings.timezone`): a
    student's age group turns over by it (Plan 10, PD-5)."""
    return now().astimezone(ZoneInfo(academy_services.get_settings().timezone)).date()
```

Create `backend/etqan/identity/ages.py`:

```python
"""Age groups (Plan 10, PD-5): derived from the date of birth, never stored.

``child`` is under 13, ``teen`` 13 to 17 and ``adult`` 18 and over, on the
academy's calendar. The payload and the list filter both compare the date of
birth with the same two cut-off dates, so a row's ``age_group`` always agrees
with the filter that finds it, and the filter stays a plain date comparison in
SQL (exact counts and paging)."""

from datetime import date

CHILD = "child"
TEEN = "teen"
ADULT = "adult"
MINOR = "minor"
AGE_GROUPS = (CHILD, TEEN, ADULT)
FILTERS = (*AGE_GROUPS, MINOR)
TEEN_FROM = 13
ADULT_FROM = 18


def years_before(day: date, years: int) -> date:
    """The same calendar day ``years`` earlier. 29 February, when that year
    has none, becomes the 28th: born on 28 February 2015, you are 13 on
    29 February 2028."""
    try:
        return day.replace(year=day.year - years)
    except ValueError:
        return day.replace(year=day.year - years, day=28)


def cutoffs(today: date) -> tuple[date, date]:
    """(born after this is a child, born after this is not yet an adult).

    Someone born exactly on a cut-off has had that birthday today. A 29
    February birthday comes round on 1 March in a common year."""
    return years_before(today, TEEN_FROM), years_before(today, ADULT_FROM)


def age_group(date_of_birth: date | None, *, today: date) -> str | None:
    if date_of_birth is None:
        return None
    teen_cut, adult_cut = cutoffs(today)
    if date_of_birth > teen_cut:
        return CHILD
    if date_of_birth > adult_cut:
        return TEEN
    return ADULT


def born_lookups(group: str, *, today: date) -> dict[str, date] | None:
    """Date-of-birth lookups (``{"gt": ..., "lte": ...}``) that select an age
    group, or ``minor`` (child or teen). ``None`` for an unknown group. A
    missing date of birth never matches: SQL compares NULL as unknown."""
    teen_cut, adult_cut = cutoffs(today)
    return {
        CHILD: {"gt": teen_cut},
        TEEN: {"gt": adult_cut, "lte": teen_cut},
        ADULT: {"lte": adult_cut},
        MINOR: {"gt": adult_cut},
    }.get(group)
```

- [ ] **Step 4: Implement assignment and the bulk actions in the services**

In `backend/etqan/identity/services.py`, replace:

```python
    "student": frozenset({"date_of_birth", "gender", "country", "status", "notes"}),
    "teacher": frozenset(
        {
            "gender",
```

with:

```python
    "student": frozenset(
        {
            "date_of_birth",
            "gender",
            "country",
            "status",
            "notes",
            "xp",
            "nationality",
            "tag_ids",
        }
    ),
    "teacher": frozenset(
        {
            "tag_ids",
            "gender",
```

In `backend/etqan/identity/services.py`, replace:

```python
BULK_ACTIONS = ("activate", "deactivate", "set_status")
```

with:

```python
BULK_ACTIONS = ("activate", "deactivate", "set_status", "add_tag", "remove_tag")
TAG_ACTIONS = ("add_tag", "remove_tag")
```

In `backend/etqan/identity/services.py`, replace:

```python
def _apply_profile(role: str, profile_obj, data: dict) -> None:
    """Validate ``data`` onto an unsaved-or-saved profile; the caller saves it."""
    unknown = sorted(set(data) - PROFILE_FIELDS[role])
    if unknown:
        raise ValidationError("Unknown field.", field=unknown[0])
```

with:

```python
def _tags_to_assign(kind: str, tag_ids, *, kept: set[int]) -> list[Tag]:
    """The tags ``tag_ids`` names, all of ``kind`` and in this academy. A
    retired tag is refused unless it is in ``kept`` (the person already has
    it), so editing a person never forces a retired tag off (D4)."""
    wanted = list(dict.fromkeys(tag_ids))
    found = {tag.pk: tag for tag in Tag.objects.filter(pk__in=wanted, kind=kind)}
    if len(found) != len(wanted):
        raise ValidationError("Choose tags from the list.", field="tag_ids")
    if any(not found[pk].is_active and pk not in kept for pk in wanted):
        raise ValidationError("A retired tag can't be added.", field="tag_ids")
    return [found[pk] for pk in wanted]


def _apply_profile(role: str, profile_obj, data: dict) -> list[Tag] | None:
    """Validate ``data`` onto an unsaved-or-saved profile; the caller saves it,
    then sets the returned tags (``None``: the tags were not given)."""
    unknown = sorted(set(data) - PROFILE_FIELDS[role])
    if unknown:
        raise ValidationError("Unknown field.", field=unknown[0])
    tags = None
    if (tag_ids := data.pop("tag_ids", None)) is not None:
        kept = set()
        if profile_obj.pk:
            kept = set(profile_obj.tags.values_list("pk", flat=True))
        tags = _tags_to_assign(role, tag_ids, kept=kept)
```

In `backend/etqan/identity/services.py`, replace:

```python
    try:
        profile_obj.full_clean(exclude=["user"])
    except DjangoValidationError as exc:
        raise from_django(exc) from None


@transaction.atomic
def create_person(
```

with:

```python
    try:
        profile_obj.full_clean(exclude=["user"])
    except DjangoValidationError as exc:
        raise from_django(exc) from None
    return tags


@transaction.atomic
def create_person(
```

In `backend/etqan/identity/services.py`, replace:

```python
        _apply_profile(role, profile_obj, dict(profile or {}))
        profile_obj.save()
```

with:

```python
        tags = _apply_profile(role, profile_obj, dict(profile or {}))
        profile_obj.save()
        if tags is not None:
            profile_obj.tags.set(tags)
```

In `backend/etqan/identity/services.py`, replace:

```python
    profile_obj = None
    if profile:
        model = _PROFILE_MODELS.get(user.role)
        if model is None:
            raise ValidationError("Admins have no profile.", field=sorted(profile)[0])
        profile_obj = model.objects.filter(user=user).first() or model(user=user)
        _apply_profile(user.role, profile_obj, dict(profile))
```

with:

```python
    profile_obj = tags = None
    if profile:
        model = _PROFILE_MODELS.get(user.role)
        if model is None:
            raise ValidationError("Admins have no profile.", field=sorted(profile)[0])
        profile_obj = model.objects.filter(user=user).first() or model(user=user)
        tags = _apply_profile(user.role, profile_obj, dict(profile))
```

In `backend/etqan/identity/services.py`, replace:

```python
    if profile_obj is not None:
        profile_obj.save()
    return user
```

with:

```python
    if profile_obj is not None:
        profile_obj.save()
    if tags is not None:
        profile_obj.tags.set(tags)
    return user
```

In `backend/etqan/identity/services.py`, replace:

```python
@transaction.atomic
def bulk_update_students(
    user_ids: list[int],
    action: str,
    *,
    status: str | None = None,
    by: User | None = None,
) -> int:
    if action not in BULK_ACTIONS:
        raise ValidationError("Unknown action.", field="action")
    if action == "set_status" and status not in StudentProfile.Status.values:
        raise ValidationError("Choose a status.", field="status")
    students = list(User.objects.filter(pk__in=user_ids, role=User.Role.STUDENT))
```

with:

```python
def _bulk_tag(action: str, tag_id: int | None) -> Tag:
    """The student tag a bulk ``add_tag``/``remove_tag`` names. Adding follows
    the assignment rules (no retired tag); removing a retired tag is allowed,
    as that is how an academy clears one off (D5)."""
    tag = Tag.objects.filter(pk=tag_id or 0, kind=Tag.Kind.STUDENT).first()
    if tag is None:
        raise ValidationError("Choose a tag from the list.", field="tag_id")
    if action == "add_tag" and not tag.is_active:
        raise ValidationError("A retired tag can't be added.", field="tag_id")
    return tag


def _tag_students(action: str, tag: Tag, students: list[User]) -> None:
    link = StudentProfile.tags.through
    profile_ids = StudentProfile.objects.filter(user__in=students).values_list(
        "pk", flat=True
    )
    if action == "add_tag":
        link.objects.bulk_create(
            [link(studentprofile_id=pk, tag_id=tag.pk) for pk in profile_ids],
            ignore_conflicts=True,
        )
    else:
        link.objects.filter(studentprofile_id__in=profile_ids, tag=tag).delete()


@transaction.atomic
def bulk_update_students(
    user_ids: list[int],
    action: str,
    *,
    status: str | None = None,
    tag_id: int | None = None,
    by: User | None = None,
) -> int:
    if action not in BULK_ACTIONS:
        raise ValidationError("Unknown action.", field="action")
    if action == "set_status" and status not in StudentProfile.Status.values:
        raise ValidationError("Choose a status.", field="status")
    tag = _bulk_tag(action, tag_id) if action in TAG_ACTIONS else None
    students = list(User.objects.filter(pk__in=user_ids, role=User.Role.STUDENT))
    if tag is not None:
        _tag_students(action, tag, students)
```

- [ ] **Step 5: Implement the payloads, the serializers and the views**

In `backend/etqan/identity/api/payloads.py`, replace:

```python
from etqan.catalogue import services as catalogue_services
from etqan.identity import services
from etqan.identity.models import Tag
from etqan.identity.models import User
```

with:

```python
from datetime import date

from etqan.catalogue import services as catalogue_services
from etqan.identity import ages
from etqan.identity import clock
from etqan.identity import services
from etqan.identity.models import Tag
from etqan.identity.models import User

# Staff-internal: admins read them, the person themself and their family never
# do (notes since Plan 3; nationality is admin-only everywhere, Plan 10 §4.3).
STAFF_ONLY = ("notes", "nationality")
```

In `backend/etqan/identity/api/payloads.py`, replace:

```python
def _student_profile(p, _course_ids) -> dict:
    return {
        "date_of_birth": _iso(p.date_of_birth),
        "gender": p.gender,
        "country": p.country,
        "status": p.status,
        "notes": p.notes,
    }


def _teacher_profile(p, course_ids) -> dict:
```

with:

```python
def _student_profile(p, _course_ids, today: date | None) -> dict:
    return {
        "date_of_birth": _iso(p.date_of_birth),
        "gender": p.gender,
        "country": p.country,
        "status": p.status,
        "notes": p.notes,
        "xp": p.xp,
        "nationality": p.nationality,
        "age_group": ages.age_group(p.date_of_birth, today=today or clock.today()),
        "tags": [tag_chip(tag) for tag in p.tags.all()],
    }


def _teacher_profile(p, course_ids, _today) -> dict:
```

In `backend/etqan/identity/api/payloads.py`, replace:

```python
        "course_ids": course_ids or [],
    }


def _parent_profile(p, _course_ids) -> dict:
```

with:

```python
        "course_ids": course_ids or [],
        "tags": [tag_chip(tag) for tag in p.tags.all()],
    }


def _parent_profile(p, _course_ids, _today) -> dict:
```

In `backend/etqan/identity/api/payloads.py`, replace:

```python
def profile_payload(
    user: User, *, course_ids: list[int] | None = None, include_notes: bool = True
) -> dict:
    """``include_notes=False`` for anything the person themself reads: notes
    are staff-internal remarks written by admins."""
    relation, build = _PROFILES.get(user.role, (None, None))
    p = getattr(user, relation, None) if relation else None
    payload = build(p, course_ids) if p is not None else {}
    if not include_notes:
        payload.pop("notes", None)
    return payload


def person_rows(users: list[User], *, viewer: User) -> list[dict]:
    teacher_ids = [u.id for u in users if u.role == "teacher"]
    courses = (
        catalogue_services.course_ids_for_teachers(teacher_ids) if teacher_ids else {}
    )
    rows = []
    for user in users:
        row = {
            "id": user.id,
            "role": user.role,
            "user": user_payload(user),
            "profile": profile_payload(user, course_ids=courses.get(user.id)),
        }
```

with:

```python
def profile_payload(
    user: User,
    *,
    staff: bool,
    course_ids: list[int] | None = None,
    today: date | None = None,
) -> dict:
    """``staff=False`` for anything the person or their family reads: it drops
    ``STAFF_ONLY``. ``today`` (the academy's) dates the age group; a list
    passes it once instead of reading it per row."""
    relation, build = _PROFILES.get(user.role, (None, None))
    p = getattr(user, relation, None) if relation else None
    payload = build(p, course_ids, today) if p is not None else {}
    if not staff:
        for key in STAFF_ONLY:
            payload.pop(key, None)
    return payload


def person_rows(users: list[User], *, viewer: User) -> list[dict]:
    teacher_ids = [u.id for u in users if u.role == "teacher"]
    courses = (
        catalogue_services.course_ids_for_teachers(teacher_ids) if teacher_ids else {}
    )
    today = clock.today() if any(u.role == "student" for u in users) else None
    rows = []
    for user in users:
        row = {
            "id": user.id,
            "role": user.role,
            "user": user_payload(user),
            "profile": profile_payload(
                user, staff=True, course_ids=courses.get(user.id), today=today
            ),
        }
```

In `backend/etqan/identity/api/views.py`, replace:

```python
from etqan.catalogue import services as catalogue_services
from etqan.identity import services
```

with:

```python
from etqan.catalogue import services as catalogue_services
from etqan.identity import clock
from etqan.identity import services
```

In `backend/etqan/identity/api/views.py`, replace:

```python
        course_ids = catalogue_services.course_ids_for_teachers([user.id]).get(user.id)
    payload = {
```

with:

```python
        course_ids = catalogue_services.course_ids_for_teachers([user.id]).get(user.id)
    # Plan 10: a student's age group, and each child's, on the academy's day.
    today = clock.today() if user.role in ("student", "parent") else None
    payload = {
```

In `backend/etqan/identity/api/views.py`, replace:

```python
        "profile": profile_payload(user, course_ids=course_ids, include_notes=False),
```

with:

```python
        "profile": profile_payload(
            user, staff=False, course_ids=course_ids, today=today
        ),
```

In `backend/etqan/identity/api/views.py`, replace:

```python
                "profile": profile_payload(child.user, include_notes=False),
            }
            for child in services.get_children(user.id).select_related("user")
        ]
```

with:

```python
                "profile": profile_payload(child.user, staff=False, today=today),
            }
            for child in services.get_children(user.id)
            .select_related("user")
            .prefetch_related("tags")
        ]
```

In `backend/etqan/identity/api/people_serializers.py`, replace:

```python
from etqan.identity.models import TeacherProfile
from etqan.identity.services import USER_FIELDS
```

with:

```python
from etqan.identity.models import TeacherProfile
from etqan.identity.services import BULK_ACTIONS
from etqan.identity.services import TAG_ACTIONS
from etqan.identity.services import USER_FIELDS
```

In `backend/etqan/identity/api/people_serializers.py`, replace:

```python
class StudentProfileInput(serializers.ModelSerializer):
    class Meta:
        model = StudentProfile
        fields = ["date_of_birth", "gender", "country", "status", "notes"]
```

with:

```python
def _tag_ids():
    """The whole set of a person's tags (Plan 10 D4): replaces what they had."""
    return serializers.ListField(
        child=serializers.IntegerField(min_value=1), required=False
    )


class StudentProfileInput(serializers.ModelSerializer):
    tag_ids = _tag_ids()

    class Meta:
        model = StudentProfile
        fields = [
            "date_of_birth",
            "gender",
            "country",
            "status",
            "notes",
            "xp",
            "nationality",
            "tag_ids",
        ]
```

In `backend/etqan/identity/api/people_serializers.py`, replace:

```python
    course_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1), required=False
    )

    class Meta:
        model = TeacherProfile
```

with:

```python
    course_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1), required=False
    )
    tag_ids = _tag_ids()

    class Meta:
        model = TeacherProfile
```

In `backend/etqan/identity/api/people_serializers.py`, replace:

```python
            "payout_details",
            "course_ids",
        ]
```

with:

```python
            "payout_details",
            "course_ids",
            "tag_ids",
        ]
```

In `backend/etqan/identity/api/people_serializers.py`, replace:

```python
    action = serializers.ChoiceField(choices=["activate", "deactivate", "set_status"])
    status = serializers.ChoiceField(
        choices=StudentProfile.Status.choices, required=False
    )

    def validate(self, attrs):
        if attrs["action"] == "set_status" and not attrs.get("status"):
            raise serializers.ValidationError({"status": ["Choose a status."]})
        return attrs
```

with:

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

In `backend/etqan/identity/api/people_views.py`, replace:

```python
        updated = services.bulk_update_students(
            ids, data["action"], status=data.get("status"), by=request.user
        )
```

with:

```python
        updated = services.bulk_update_students(
            ids,
            data["action"],
            status=data.get("status"),
            tag_id=data.get("tag_id"),
            by=request.user,
        )
```

- [ ] **Step 6: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/identity/tests/test_ages.py etqan/identity/tests/test_profile_depth.py etqan/identity/tests/test_profile_access.py -q
```

Expected: 45 passed.

- [ ] **Step 7: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1341 tests, coverage 98.0%. Plan 3's `test_parent_me_query_count_does_not_grow_with_children` keeps passing only because each child's tags are prefetched (`prefetch_related("tags")` above): without it, every child costs one more query.

- [ ] **Step 8: Commit**

```bash
git -C backend add etqan/identity
git -C backend commit -m "feat(identity): tags, XP, nationality and age group on people and me/

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The lists: tag, nationality and age filters, the CSV columns, and flat query counts

**Files:**
- Modify: `backend/etqan/identity/api/people_filters.py`, `backend/etqan/identity/api/payloads.py`, `backend/etqan/identity/api/people_views.py`, `backend/etqan/identity/services.py`
- Test: `backend/etqan/identity/tests/test_people_depth_lists.py` (new)

**Interfaces:**
- Consumes: Task 3's `ages.FILTERS`, `ages.born_lookups`, `clock.today`, `profile_payload`, `person_rows`; Task 2's `tag_chip`.
- Produces:
  - list filters on `GET /api/v1/people/students/` and `teachers/`: `?tag=<id>` (repeatable, any of); students also `?nationality=arab|foreign` and `?age_group=child|teen|adult|minor`. Unknown values are ignored, and a tag id of the other kind or another academy matches no one;
  - `payloads.tag_labels(tags: list[dict], *, language: str) -> str` and `payloads.csv_rows(users, *, viewer) -> list[dict]` (`person_rows` plus a top-level `tags` text);
  - the CSV columns of D6;
  - `people_queryset("student"|"teacher")` prefetches the tags.

- [ ] **Step 1: Write the failing tests**

- **Tag filter:** it matches any of the repeated tags, once each, and teachers filter by theirs. A tag of the other kind, an unknown id or junk never breaks the list.
- **Nationality filter:** it filters.
- **Age filters:** age groups and `minor` leave out unknown birthdays. The age filter is exact across pages, and the academy's calendar (Auckland) decides the birthday.
- **CSV:** the columns are D6's, and the Tags cell follows the academy's language, a tag without an emoji included.
- **Query counts:** the student and teacher lists and the students' CSV stay flat as tagged rows grow.

Create `backend/etqan/identity/tests/test_people_depth_lists.py`:

```python
"""Plan 10 §4.2 on the lists: the tag, nationality and age filters, the CSV
columns, and query counts that stay flat with tags attached."""

import csv
import io
from datetime import UTC
from datetime import date
from datetime import datetime

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.academy import services as academy_services
from etqan.identity import clock
from etqan.identity import services
from etqan.identity.models import Tag

pytestmark = pytest.mark.django_db
B = "/api/v1/people/"


@pytest.fixture
def admin(api_for):
    return api_for("admin")


@pytest.fixture
def pin(monkeypatch):
    """``pin(instant)`` sets identity's clock (the academy's today follows)."""
    return lambda when: monkeypatch.setattr(clock, "now", lambda: when)


def tag(name_en, kind="student"):
    return Tag.objects.get(kind=kind, name_en=name_en)


def student(name, *tags, email=None, **profile):
    return services.create_person(
        "student",
        full_name=name,
        email=email,
        invite=False,
        profile={"tag_ids": [t.pk for t in tags], **profile},
    )


def teacher(name, *tags):
    return services.create_person(
        "teacher",
        full_name=name,
        profile={"gender": "male", "tag_ids": [t.pk for t in tags]},
    )


def names(client, query, kind="students"):
    body = client.get(f"{B}{kind}/?{query}").json()
    return [row["user"]["full_name"] for row in body["results"]]


def read_csv(resp):
    return list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))


class TestFilters:
    def test_tag_matches_any_of_the_repeated_tags_once_each(self, admin):
        star, new, reader = tag("Star of the month"), tag("New"), tag("Skilled reader")
        student("Aisha", star, new)
        student("Bilal", new)
        student("Huda", reader)
        student("Zaid")
        assert names(admin, f"tag={star.pk}") == ["Aisha"]
        query = f"tag={star.pk}&tag={new.pk}"
        assert names(admin, query) == ["Aisha", "Bilal"]  # Aisha once
        assert admin.get(f"{B}students/?{query}").json()["count"] == 2
        assert names(admin, "tag=abc") == ["Aisha", "Bilal", "Huda", "Zaid"]

    def test_a_tag_of_the_other_kind_or_junk_filters_never_break_the_list(self, admin):
        student("Aisha", tag("New"))
        patient = tag("Patient", "teacher")
        assert names(admin, f"tag={patient.pk}") == []
        assert names(admin, "tag=999999") == []
        for query in ("tag=-1", "age_group=", "nationality=", "tag=&tag=x"):
            assert names(admin, query) == ["Aisha"], query

    def test_teachers_filter_by_their_tags(self, admin):
        teacher("Kareem", tag("Patient", "teacher"))
        teacher("Maryam")
        patient = tag("Patient", "teacher")
        assert names(admin, f"tag={patient.pk}", "teachers") == ["Kareem"]

    def test_nationality(self, admin):
        student("Aisha", nationality="arab")
        student("Bilal", nationality="foreign")
        student("Zaid")
        assert names(admin, "nationality=arab") == ["Aisha"]
        assert names(admin, "nationality=foreign") == ["Bilal"]
        assert names(admin, "nationality=martian") == ["Aisha", "Bilal", "Zaid"]

    def test_age_groups_and_minor_leave_out_unknown_birthdays(self, admin, pin):
        pin(datetime(2026, 6, 1, 8, tzinfo=UTC))
        student("Child", date_of_birth=date(2013, 6, 2))
        student("Teen", date_of_birth=date(2013, 6, 1))
        student("Old teen", date_of_birth=date(2008, 6, 2))
        student("Adult", date_of_birth=date(2008, 6, 1))
        student("Unknown")
        assert names(admin, "age_group=child") == ["Child"]
        assert names(admin, "age_group=teen") == ["Old teen", "Teen"]
        assert names(admin, "age_group=adult") == ["Adult"]
        assert names(admin, "age_group=minor") == ["Child", "Old teen", "Teen"]
        assert len(names(admin, "age_group=elder")) == 5

    def test_the_age_filter_is_exact_across_pages(self, admin, pin):
        pin(datetime(2026, 6, 1, 8, tzinfo=UTC))
        for n in range(5):
            student(f"Minor {n}", date_of_birth=date(2012, 1, 1 + n))
        for n in range(3):
            student(f"Adult {n}", date_of_birth=date(1990, 1, 1 + n))
        pages = [
            admin.get(f"{B}students/?age_group=minor&page_size=2&page={p}").json()
            for p in (1, 2, 3)
        ]
        assert [page["count"] for page in pages] == [5, 5, 5]
        seen = [row["user"]["full_name"] for page in pages for row in page["results"]]
        assert seen == [f"Minor {n}" for n in range(5)]

    def test_the_academys_calendar_decides_the_birthday(self, admin, pin):
        """13:00 UTC on 1 June is already 2 June in Auckland (UTC+12)."""
        academy_services.update_settings(timezone="Pacific/Auckland")
        pin(datetime(2026, 6, 1, 13, tzinfo=UTC))
        student("Birthday", date_of_birth=date(2013, 6, 2))
        assert names(admin, "age_group=teen") == ["Birthday"]
        assert names(admin, "age_group=child") == []
        row = admin.get(f"{B}students/").json()["results"][0]
        assert row["profile"]["age_group"] == "teen"
        academy_services.update_settings(timezone="UTC")
        assert names(admin, "age_group=child") == ["Birthday"]


class TestCsv:
    def test_students_gain_age_group_nationality_xp_and_tags(self, admin, pin):
        pin(datetime(2026, 6, 1, 8, tzinfo=UTC))
        student(
            "Aisha",
            tag("Star of the month"),
            tag("New"),
            xp=120,
            nationality="arab",
            date_of_birth=date(2015, 3, 10),
        )
        resp = admin.get(f"{B}students/?format=csv")
        header, row = read_csv(resp)
        assert header == [
            "ID",
            "Name",
            "Email",
            "Phone",
            "Language",
            "Account",
            "Active",
            "Status",
            "Gender",
            "Country",
            "Date of birth",
            "Age group",
            "Nationality",
            "XP",
            "Tags",
        ]
        assert row[-4:] == ["child", "arab", "120", "🎓 جديد; ⭐ نجم الشهر"]
        academy_services.update_settings(default_language="en")
        _, row = read_csv(admin.get(f"{B}students/?format=csv"))
        assert row[-1] == "🎓 New; ⭐ Star of the month"

    def test_teachers_gain_tags_and_a_tag_without_an_emoji_reads_cleanly(self, admin):
        plain = services.create_tag(kind="teacher", name_ar="بسيط", name_en="Plain")
        teacher("Kareem", tag("Patient", "teacher"), plain)
        academy_services.update_settings(default_language="en")
        header, row = read_csv(admin.get(f"{B}teachers/?format=csv"))
        assert header[-2:] == ["Course IDs", "Tags"]
        assert row[-1] == "🤝 Patient; Plain"


class TestQueryCounts:
    def _count(self, client, url):
        with CaptureQueriesContext(connection) as queries:
            assert client.get(url).status_code == 200
        return len(queries)

    def test_the_student_list_is_flat_as_tagged_rows_grow(self, admin, pin):
        pin(datetime(2026, 6, 1, 8, tzinfo=UTC))
        star, new = tag("Star of the month"), tag("New")
        student("A", star, new, date_of_birth=date(2012, 1, 1))
        one = self._count(admin, f"{B}students/")
        for name in ("B", "C", "D"):
            student(name, star, new, nationality="arab")
        assert self._count(admin, f"{B}students/") == one
        filtered = f"{B}students/?tag={star.pk}&age_group=minor&nationality=arab"
        csv_one = self._count(admin, f"{B}students/?format=csv")
        student("E", star)
        assert self._count(admin, f"{B}students/?format=csv") == csv_one
        assert self._count(admin, filtered) <= one + 1  # the academy's today

    def test_the_teacher_list_is_flat_as_tagged_rows_grow(self, admin):
        patient = tag("Patient", "teacher")
        teacher("A", patient)
        one = self._count(admin, f"{B}teachers/")
        for name in ("B", "C", "D"):
            teacher(name, patient, tag("Expert", "teacher"))
        assert self._count(admin, f"{B}teachers/") == one
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `backend/`): `.venv/bin/pytest etqan/identity/tests/test_people_depth_lists.py -q`

Expected: FAIL — the filter tests list every student (the filters are ignored), the CSV header ends at `Date of birth`, and the query counts grow with each tagged row.

- [ ] **Step 3: Implement the filters**

Rewrite `backend/etqan/identity/api/people_filters.py` whole (the student filters move into `_student_filters`, and `_tag_filter` serves both kinds).

Create `backend/etqan/identity/api/people_filters.py`:

```python
from django.db.models import Q

from etqan.catalogue import services as catalogue_services
from etqan.identity import ages
from etqan.identity import clock
from etqan.identity.models import StudentProfile
from etqan.identity.models import TeacherProfile

_BOOL = {"true": True, "false": False}
_TAGGED = {"student": StudentProfile, "teacher": TeacherProfile}


def _tag_filter(queryset, role: str, params):
    """``?tag=<id>``, repeatable: people with ANY of the tags. A subquery,
    not a join, so no row appears twice and counts stay exact."""
    ids = [int(value) for value in params.getlist("tag") if value.isdigit()]
    model = _TAGGED.get(role)
    if not ids or model is None:
        return queryset
    tagged = model.objects.filter(tags__in=ids).values("user_id")
    return queryset.filter(pk__in=tagged)


def _student_filters(queryset, params):
    for key in ("status", "country", "gender"):
        if value := params.get(key):
            queryset = queryset.filter(**{f"student_profile__{key}": value.strip()})
    if (nationality := params.get("nationality")) in StudentProfile.Nationality.values:
        queryset = queryset.filter(student_profile__nationality=nationality)
    if (group := params.get("age_group")) in ages.FILTERS:
        # Plain date comparisons against the academy's today (PD-5).
        lookups = ages.born_lookups(group, today=clock.today())
        queryset = queryset.filter(
            **{
                f"student_profile__date_of_birth__{op}": day
                for op, day in lookups.items()
            }
        )
    return queryset


def filter_people(queryset, role: str, params):
    if q := params.get("q", "").strip():
        queryset = queryset.filter(
            Q(full_name__icontains=q) | Q(email__icontains=q) | Q(phone__icontains=q)
        )
    if (active := params.get("is_active")) in _BOOL:
        queryset = queryset.filter(is_active=_BOOL[active])
    queryset = _tag_filter(queryset, role, params)
    if role == "student":
        queryset = _student_filters(queryset, params)
    elif role == "teacher":
        if gender := params.get("gender"):
            queryset = queryset.filter(teacher_profile__gender=gender)
        if (course := params.get("course", "")).isdigit():
            ids = catalogue_services.teacher_user_ids_for_course(int(course))
            queryset = queryset.filter(pk__in=ids)
    elif role == "parent" and (whatsapp := params.get("has_whatsapp")) in _BOOL:
        queryset = queryset.filter(parent_profile__has_whatsapp=_BOOL[whatsapp])
    return queryset
```

- [ ] **Step 4: Implement the CSV columns**

In `backend/etqan/identity/api/payloads.py`, replace:

```python
from datetime import date

from etqan.catalogue import services as catalogue_services
```

with:

```python
from datetime import date

from etqan.academy import services as academy_services
from etqan.catalogue import services as catalogue_services
```

In `backend/etqan/identity/api/payloads.py`, replace:

```python
def _student_profile(p, _course_ids, today: date | None) -> dict:
```

with:

```python
def tag_labels(tags: list[dict], *, language: str) -> str:
    """One CSV cell: each tag's emoji and name in ``language``, joined (D6)."""
    name = "name_ar" if language == "ar" else "name_en"
    return "; ".join(f"{tag['emoji']} {tag[name]}".strip() for tag in tags)


def _student_profile(p, _course_ids, today: date | None) -> dict:
```

Append to `backend/etqan/identity/api/payloads.py`:

```python
def csv_rows(users: list[User], *, viewer: User) -> list[dict]:
    """``person_rows`` plus ``tags``: the tags as text in the academy's
    default language, for the CSV's Tags column."""
    language = academy_services.get_settings().default_language
    rows = person_rows(users, viewer=viewer)
    for row in rows:
        row["tags"] = tag_labels(row["profile"].get("tags", []), language=language)
    return rows
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
from etqan.identity.api.payloads import person_rows
```

with:

```python
from etqan.identity.api.payloads import csv_rows
from etqan.identity.api.payloads import person_rows
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
        ("profile.country", "Country"),
        ("profile.date_of_birth", "Date of birth"),
    ),
```

with:

```python
        ("profile.country", "Country"),
        ("profile.date_of_birth", "Date of birth"),
        ("profile.age_group", "Age group"),
        ("profile.nationality", "Nationality"),
        ("profile.xp", "XP"),
        ("tags", "Tags"),
    ),
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
        ("profile.course_ids", "Course IDs"),
    ),
```

with:

```python
        ("profile.course_ids", "Course IDs"),
        ("tags", "Tags"),
    ),
```

In `backend/etqan/identity/api/people_views.py`, replace:

```python
            return self.csv_response(person_rows(list(queryset), viewer=request.user))
```

with:

```python
            return self.csv_response(csv_rows(list(queryset), viewer=request.user))
```

- [ ] **Step 5: Prefetch the list's tags**

In `backend/etqan/identity/services.py`, replace:

```python
    if relation:
        qs = qs.select_related(relation)
    if role == "parent":
```

with:

```python
    if relation:
        qs = qs.select_related(relation)
    if role in Tag.Kind.values:
        # One query for every row's tags, in list order (Tag.Meta.ordering).
        qs = qs.prefetch_related(f"{relation}__tags")
    if role == "parent":
```

- [ ] **Step 6: Format, then run the tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/identity/tests/test_people_depth_lists.py -q
```

Expected: 11 passed.

- [ ] **Step 7: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1352 tests, coverage 98.0%. Plan 3's `test_csv_respects_filters_and_opens_in_excel` and `test_csv_has_a_header_for_every_kind` still pass: they check only the first columns.

- [ ] **Step 8: Commit**

```bash
git -C backend add etqan/identity
git -C backend commit -m "feat(identity): filter and export people by tag, nationality and age group

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Dev seeds: the presets everywhere, and tagged demo people with XP, nationalities and every age group

**Files:**
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py`
- Test: `backend/etqan/tenants/tests/test_seed_dev.py`

**Interfaces:**
- Consumes: Task 1's `ensure_preset_tags`; Task 2's `tags_queryset`; Task 3's `update_person(profile={"tag_ids", "xp", "nationality", "date_of_birth"})` and `person_rows`'s new fields.
- Produces: `seed_dev.PROFILES` and `seed_dev.seed_profiles(spec: dict | None) -> None`, run by `seed_academy` after `seed_people` (so `seed_staging` gets them too), as D10 describes.

- [ ] **Step 1: Write the failing test**

Two runs of `seed_dev` give the demo people their tags, XP, nationalities and ages (child, teen and adult all appear), leave the other academy with only the presets, change nothing the second time, and skip a missing seeded person with a `skip:` line.

Append to `backend/etqan/tenants/tests/test_seed_dev.py`:

```python
@pytest.mark.django_db
@override_settings(DEBUG=True)
def test_seed_dev_tags_the_demo_people_once_and_the_other_academy_not_at_all(
    capsys, monkeypatch
):
    from etqan.identity.api.payloads import person_rows  # noqa: PLC0415
    from etqan.identity.models import Tag  # noqa: PLC0415

    def state():
        rows = person_rows(
            [*User.objects.filter(role__in=["student", "teacher"]).order_by("id")],
            viewer=None,
        )
        return {
            row["user"]["full_name"]: (
                [tag["name_en"] for tag in row["profile"]["tags"]],
                row["profile"].get("xp"),
                row["profile"].get("nationality"),
                row["profile"].get("age_group"),
            )
            for row in rows
        }

    call_command("seed_dev")
    connection.set_schema_to_public()
    demo = Academy.objects.get(subdomain="demo")
    other = Academy.objects.get(subdomain="other")
    with tenant_context(demo):
        first = state()
        assert first["Yusuf Omar"] == (
            ["Star of the month", "Skilled reader"],
            320,
            "arab",
            "child",
        )
        assert first["Aisha Omar"] == (["New"], 40, "foreign", "teen")
        assert first["Zaid Huda"] == (["Proficient memoriser"], 150, "", "adult")
        assert first["Ustadh Bilal"][0] == ["Excellent at teaching", "Patient"]
        assert first["Ustadha Maryam"][0] == ["Great with children"]
        assert Tag.objects.count() == 43
    with tenant_context(other):
        assert Tag.objects.count() == 43
        assert all(
            tags == [] and xp in (0, None) for tags, xp, _, _ in state().values()
        )
    missing = {"tags": ("New",), "xp": 1, "born": 10}
    monkeypatch.setitem(seed_dev.PROFILES["demo"]["students"], "Nobody", missing)
    capsys.readouterr()
    call_command("seed_dev")
    connection.set_schema_to_public()
    with tenant_context(demo):
        assert state() == first
        assert Tag.objects.count() == 43
    out = capsys.readouterr().out
    assert "skip: Nobody profile — seeded record not found" in out
    assert "Yusuf Omar profile" not in out
```

- [ ] **Step 2: Run it to verify it fails**

Run (from `backend/`): `.venv/bin/pytest etqan/tenants/tests/test_seed_dev.py -q -k tags`

Expected: FAIL — `assert ([], 0, '', None) == (['Star of the month', 'Skilled reader'], 320, 'arab', 'child')` for Yusuf.

- [ ] **Step 3: Implement**

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
def _person(role: str, full_name: str):
    return identity_services.people_queryset(role).filter(full_name=full_name).first()
```

with:

```python
def _person(role: str, full_name: str):
    return identity_services.people_queryset(role).filter(full_name=full_name).first()


# Plan 10 (spec §7): one or two tags on every demo student and teacher, XP on
# the students, and a nationality and a date of birth on some, so the child,
# teen and adult groups all appear. ``born`` is an age in years on the
# academy's today (10 March of that year). The other academy gets only the
# presets.
PROFILES = {
    "demo": {
        "students": {
            "Yusuf Omar": {
                "tags": ("Star of the month", "Skilled reader"),
                "xp": 320,
                "nationality": "arab",
                "born": 9,
            },
            "Aisha Omar": {
                "tags": ("New",),
                "xp": 40,
                "nationality": "foreign",
                "born": 15,
            },
            "Zaid Huda": {"tags": ("Proficient memoriser",), "xp": 150, "born": 19},
        },
        "teachers": {
            "Ustadh Bilal": ("Excellent at teaching", "Patient"),
            "Ustadha Maryam": ("Great with children",),
        },
    },
}


def _tag_ids(kind: str, names) -> list[int]:
    by_name = {tag.name_en: tag.pk for tag in identity_services.tags_queryset(kind)}
    return [by_name[name] for name in names if name in by_name]


def seed_profiles(spec: dict | None) -> None:
    """Every academy gets the preset tags. In demo, a seeded person who has
    no tag yet gets theirs, so a second run (or an admin's own tagging) is
    left as it is. A seeded person who is missing is skipped."""
    identity_services.ensure_preset_tags()
    if spec is None:
        return
    today = scheduling_services.today()
    for name, values in spec["students"].items():
        person = _person("student", name)
        if person is None:
            print(f"skip: {name} profile — seeded record not found")  # noqa: T201
            continue
        if person.student_profile.tags.exists():
            continue
        profile = {"tag_ids": _tag_ids("student", values["tags"]), "xp": values["xp"]}
        profile["date_of_birth"] = date(today.year - values["born"], 3, 10)
        if "nationality" in values:
            profile["nationality"] = values["nationality"]
        identity_services.update_person(person, profile=profile)
    for name, tag_names in spec["teachers"].items():
        person = _person("teacher", name)
        if person is None:
            print(f"skip: {name} profile — seeded record not found")  # noqa: T201
            continue
        if person.teacher_profile.tags.exists():
            continue
        identity_services.update_person(
            person, profile={"tag_ids": _tag_ids("teacher", tag_names)}
        )
```

In `backend/etqan/tenants/management/commands/seed_dev.py`, replace:

```python
        seed_people(PEOPLE[subdomain])
        seed_subscriptions(SUBSCRIPTIONS[subdomain])
```

with:

```python
        seed_people(PEOPLE[subdomain])
        seed_profiles(PROFILES.get(subdomain))
        seed_subscriptions(SUBSCRIPTIONS[subdomain])
```

- [ ] **Step 4: Format, then run the seed tests**

```bash
.venv/bin/ruff check --fix . && .venv/bin/ruff format .
.venv/bin/pytest etqan/tenants/tests/test_seed_dev.py etqan/tenants/tests/test_seed_staging.py -q
```

Expected: 19 passed.

- [ ] **Step 5: Full suite and linters**

```bash
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports && .venv/bin/pytest -q --cov=etqan
```

Expected: every check passes; 16 contracts kept; 1353 tests, coverage 98.0%.

- [ ] **Step 6: Commit**

```bash
git -C backend add etqan/tenants
git -C backend commit -m "feat(tenants): seed tags, XP, nationalities and ages on the demo people

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Dashboard: the tags data layer and the shared `TagChips`

**Files:**
- Create: `dashboard/src/components/TagChips.tsx`
- Modify: `dashboard/src/features/people/schemas.ts`, `dashboard/src/features/people/api.ts`, `dashboard/src/features/people/queries.ts`
- Test: `dashboard/src/components/TagChips.test.tsx` (new), `dashboard/src/features/people/tags-api.test.ts` (new), `dashboard/src/features/people/StudentsList.test.tsx` and `dashboard/src/features/people/StudentForm.test.tsx` (their `StudentProfile` fixtures gain the new fields, or `tsc` fails)

**Interfaces:**
- Consumes: Tasks 2–4's API: `GET/POST people/tags/`, `PATCH people/tags/<id>/`, bulk `{ids, action: "add_tag"|"remove_tag", tag_id}`, the new profile fields.
- Produces:
  - `@/components/TagChips`: `interface TagChip {id, emoji, name_ar, name_en}`, `tagName(tag, language)`, `tagLabel(tag, language)` ("⭐ Star of the month", or just the name without an emoji), `<TagChips tags />` (a list of chips, or "—");
  - `schemas.ts`: `BulkAction` gains `"add_tag" | "remove_tag"`; `NATIONALITIES`, `Nationality`, `AGE_GROUPS`, `AgeGroup`, `AGE_FILTERS` (with `minor`), `XP_MAX`; `TagKind`, `TagInput {emoji, name_ar, name_en}`, `Tag` (a chip plus `kind, position, is_active, people`); `StudentProfile` gains `xp, nationality, age_group, tags`, `TeacherProfile` gains `tags`;
  - `api.ts`: `BulkBody`, `TagChange` (`Partial<TagInput>` plus `position?`, `is_active?`), `peopleApi.tags(kind)`, `peopleApi.createTag({...TagInput, kind})`, `peopleApi.updateTag(id, TagChange)`, `peopleApi.bulkStudents(BulkBody)`;
  - `queries.ts`: `tagsKey(kind)` (under `["people"]`), `useTags(kind)`, `useCreateTag(kind)`, `useUpdateTag()` (invalidates `["people"]`, as a rename shows on every row); `useSavePerson` and `useBulkStudents` also refresh `["people", "tags"]` (the counts change).

- [ ] **Step 1: Write the failing tests**

Chips show the emoji (hidden from screen readers) and the name in the reader's language, and a dash when there are none. A tag without an emoji reads as its bare name. The API calls send the kind, the new tag and the change to the right URLs.

Create `dashboard/src/components/TagChips.test.tsx`:

```tsx
import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import i18n from "@/lib/i18n";
import { TagChips, tagLabel } from "./TagChips";

const star = {
	id: 3,
	emoji: "⭐",
	name_ar: "نجم الشهر",
	name_en: "Star of the month",
};
const plain = { id: 8, emoji: "", name_ar: "بدون", name_en: "Plain" };

describe("TagChips", () => {
	it("shows each tag's emoji and its name in the reader's language", async () => {
		const { unmount } = render(<TagChips tags={[star, plain]} />);
		const items = screen.getAllByRole("listitem");
		expect(items.map((item) => item.textContent)).toEqual([
			"⭐Star of the month",
			"Plain",
		]);
		// The emoji is decoration: the name alone is what a reader hears.
		expect(within(items[0]).getByText("⭐")).toHaveAttribute(
			"aria-hidden",
			"true",
		);
		unmount();
		// Switch languages with nothing mounted, so no update lands outside act.
		await i18n.changeLanguage("ar");
		const arabic = render(<TagChips tags={[star]} />);
		expect(screen.getByRole("listitem")).toHaveTextContent("نجم الشهر");
		arabic.unmount();
		await i18n.changeLanguage("en");
	});

	it("shows a dash for no tags", () => {
		render(<TagChips tags={[]} />);
		expect(screen.getByText("—")).toBeInTheDocument();
		expect(screen.queryByRole("list")).toBeNull();
	});

	it("labels a tag with its emoji and name", () => {
		expect(tagLabel(star, "en")).toBe("⭐ Star of the month");
		expect(tagLabel(star, "ar")).toBe("⭐ نجم الشهر");
		expect(tagLabel(plain, "en")).toBe("Plain");
	});
});
```

Create `dashboard/src/features/people/tags-api.test.ts`:

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

describe("peopleApi tags", () => {
	beforeEach(() => vi.clearAllMocks());

	it("lists a kind's tags, creates one and patches one", async () => {
		await peopleApi.tags("teacher");
		expect(api.get).toHaveBeenCalledWith("people/tags/", {
			params: { kind: "teacher" },
		});
		const body = { emoji: "🌙", name_ar: "هلال", name_en: "Crescent" };
		await peopleApi.createTag({ ...body, kind: "student" });
		expect(api.post).toHaveBeenCalledWith("people/tags/", {
			...body,
			kind: "student",
		});
		await peopleApi.updateTag(7, { position: 2 });
		expect(api.patch).toHaveBeenCalledWith("people/tags/7/", { position: 2 });
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/components/TagChips.test.tsx src/features/people/tags-api.test.ts`

Expected: FAIL — `Failed to resolve import "./TagChips"`, and `peopleApi.tags is not a function`.

- [ ] **Step 3: Implement**

Create `dashboard/src/components/TagChips.tsx`:

```tsx
import { useTranslation } from "react-i18next";

/** A tag as a person's row carries it (Plan 10 §5). */
export interface TagChip {
	id: number;
	emoji: string;
	name_ar: string;
	name_en: string;
}

/** A tag's name in the reader's language. */
export function tagName(tag: TagChip, language: string): string {
	return language === "ar" ? tag.name_ar : tag.name_en;
}

/** A tag's emoji and name, as one label ("⭐ Star of the month"). */
export function tagLabel(tag: TagChip, language: string): string {
	return `${tag.emoji} ${tagName(tag, language)}`.trim();
}

/** A person's tags as chips, or a dash when they have none. Shared by the
 * people screens and the student, parent and teacher's own pages. */
export function TagChips({ tags }: { tags: readonly TagChip[] }) {
	const { i18n } = useTranslation();
	if (tags.length === 0) return <span>—</span>;
	return (
		<ul className="flex flex-wrap gap-1">
			{tags.map((tag) => (
				<li
					key={tag.id}
					className="inline-flex items-center gap-1 rounded-full bg-secondary px-2 py-0.5 text-xs font-medium text-secondary-foreground"
				>
					{tag.emoji ? <span aria-hidden="true">{tag.emoji}</span> : null}
					{tagName(tag, i18n.language)}
				</li>
			))}
		</ul>
	);
}
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
import { z } from "zod";
import type { AcademySettings } from "@/features/academy/api";
```

with:

```ts
import { z } from "zod";
import type { TagChip } from "@/components/TagChips";
import type { AcademySettings } from "@/features/academy/api";
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
export type BulkAction = "activate" | "deactivate" | "set_status";
```

with:

```ts
export type BulkAction =
	| "activate"
	| "deactivate"
	| "set_status"
	| "add_tag"
	| "remove_tag";
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
export type PayoutMethod = (typeof PAYOUT_METHODS)[number];
```

with:

```ts
export type PayoutMethod = (typeof PAYOUT_METHODS)[number];
export const NATIONALITIES = ["arab", "foreign"] as const;
export type Nationality = (typeof NATIONALITIES)[number];
/** Derived from the date of birth on the academy's calendar (Plan 10 PD-5). */
export const AGE_GROUPS = ["child", "teen", "adult"] as const;
export type AgeGroup = (typeof AGE_GROUPS)[number];
/** The list filter also offers `minor`: a child or a teen. */
export const AGE_FILTERS = [...AGE_GROUPS, "minor"] as const;
export const XP_MAX = 1_000_000;

export type { TagChip } from "@/components/TagChips";
export type TagKind = "student" | "teacher";
/** A new tag's fields, and what a rename changes. */
export interface TagInput {
	emoji: string;
	name_ar: string;
	name_en: string;
}
/** A row of the tags admin (`GET people/tags/`). */
export interface Tag extends TagChip {
	kind: TagKind;
	position: number;
	is_active: boolean;
	/** How many active people have it. */
	people: number;
}
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
	status: StudentStatus;
	notes: string;
}
```

with:

```ts
	status: StudentStatus;
	notes: string;
	xp: number;
	nationality: "" | Nationality;
	age_group: AgeGroup | null;
	tags: TagChip[];
}
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
	payout_details: string;
	course_ids: number[];
}
```

with:

```ts
	payout_details: string;
	course_ids: number[];
	tags: TagChip[];
}
```

In `dashboard/src/features/people/api.ts`, replace:

```ts
	PersonSummary,
	StudentStatus,
} from "./schemas";
```

with:

```ts
	PersonSummary,
	StudentStatus,
	Tag,
	TagInput,
	TagKind,
} from "./schemas";
```

In `dashboard/src/features/people/api.ts`, replace:

```ts
	profile?: Record<string, unknown>;
}
```

with:

```ts
	profile?: Record<string, unknown>;
}
export interface BulkBody {
	ids: number[];
	action: BulkAction;
	status?: StudentStatus;
	tag_id?: number;
}
/** A PATCH to one tag: a new name or emoji, a new 1-based place in its
 * kind's list, or retire (`false`) and restore (`true`). */
export type TagChange = Partial<TagInput> & {
	position?: number;
	is_active?: boolean;
};
```

In `dashboard/src/features/people/api.ts`, replace:

```ts
	bulkStudents: async (body: {
		ids: number[];
		action: BulkAction;
		status?: StudentStatus;
	}) =>
		(await api.post<{ updated: number }>("people/students/bulk/", body)).data,
};
```

with:

```ts
	bulkStudents: async (body: BulkBody) =>
		(await api.post<{ updated: number }>("people/students/bulk/", body)).data,
	tags: async (kind: TagKind) =>
		(await api.get<Tag[]>("people/tags/", { params: { kind } })).data,
	createTag: async (body: TagInput & { kind: TagKind }) =>
		(await api.post<Tag>("people/tags/", body)).data,
	updateTag: async (id: number, body: TagChange) =>
		(await api.patch<Tag>(`people/tags/${id}/`, body)).data,
};
```

In `dashboard/src/features/people/queries.ts`, replace:

```ts
import { type ListParams, type PersonBody, peopleApi } from "./api";
import type { BulkAction, Kind, PersonAction, StudentStatus } from "./schemas";

export const peopleKey = (kind: Kind) => ["people", kind] as const;
```

with:

```ts
import {
	type BulkBody,
	type ListParams,
	type PersonBody,
	peopleApi,
	type TagChange,
} from "./api";
import type { Kind, PersonAction, TagInput, TagKind } from "./schemas";

export const peopleKey = (kind: Kind) => ["people", kind] as const;
/** Under `["people"]`: a person's save changes the tags' counts too. */
export const tagsKey = (kind: TagKind) => ["people", "tags", kind] as const;
```

In `dashboard/src/features/people/queries.ts`, replace:

```ts
				: peopleApi.update<P>(kind, id, body),
		onSuccess: () => qc.invalidateQueries({ queryKey: peopleKey(kind) }),
	});
}
```

with:

```ts
				: peopleApi.update<P>(kind, id, body),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: peopleKey(kind) });
			qc.invalidateQueries({ queryKey: ["people", "tags"] });
		},
	});
}
```

In `dashboard/src/features/people/queries.ts`, replace:

```ts
		mutationFn: (body: {
			ids: number[];
			action: BulkAction;
			status?: StudentStatus;
		}) => peopleApi.bulkStudents(body),
		onSuccess: () => qc.invalidateQueries({ queryKey: peopleKey("students") }),
	});
}
```

with:

```ts
		mutationFn: (body: BulkBody) => peopleApi.bulkStudents(body),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: peopleKey("students") });
			qc.invalidateQueries({ queryKey: ["people", "tags"] });
		},
	});
}

/** A kind's tags in list order, retired ones included (Plan 10 §5). */
export function useTags(kind: TagKind) {
	return useQuery({
		queryKey: tagsKey(kind),
		queryFn: () => peopleApi.tags(kind),
		staleTime: 60_000,
	});
}

export function useCreateTag(kind: TagKind) {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (body: TagInput) => peopleApi.createTag({ ...body, kind }),
		onSuccess: () => qc.invalidateQueries({ queryKey: tagsKey(kind) }),
	});
}

/** A rename or retirement shows on every person's chips: refresh `["people"]`. */
export function useUpdateTag() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: ({ id, body }: { id: number; body: TagChange }) =>
			peopleApi.updateTag(id, body),
		onSuccess: () => qc.invalidateQueries({ queryKey: ["people"] }),
	});
}
```

The existing `StudentProfile` fixtures must carry the new fields.

In `dashboard/src/features/people/StudentForm.test.tsx`, replace:

```tsx
		status: "active",
		notes: "",
	},
};
```

with:

```tsx
		status: "active",
		notes: "",
		xp: 0,
		nationality: "",
		age_group: null,
		tags: [],
	},
};
```

In `dashboard/src/features/people/StudentsList.test.tsx`, replace:

```tsx
		status: "trial",
		notes: "",
	},
});
```

with:

```tsx
		status: "trial",
		notes: "",
		xp: 0,
		nationality: "",
		age_group: null,
		tags: [],
	},
});
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vitest run src/components/TagChips.test.tsx src/features/people
```

Expected: 46 passed.

- [ ] **Step 5: Verify**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 648 tests; lines 94.0%, branches 87.2%, functions 80.8%.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src/components src/features/people
git -C dashboard commit -m "feat(people): the tags data layer and shared tag chips

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Dashboard: Settings → Tags (two tabs; add, edit, move, retire and restore)

**Files:**
- Create: `dashboard/src/features/people/TagsSettings.tsx`, `dashboard/src/routes/_authed/settings.tags.tsx`, `dashboard/src/test/people-fixtures.ts`
- Modify: `dashboard/src/features/people/schemas.ts`, `dashboard/src/features/people/index.ts`, `dashboard/src/features/shell/nav.ts`, `dashboard/src/routeTree.gen.ts` (regenerated), `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/people/TagsSettings.test.tsx` (new), `dashboard/src/features/shell/nav.test.ts` (the admin nav list gains `/settings/tags`)

**Interfaces:**
- Consumes: Task 6's `useTags`, `useCreateTag`, `useUpdateTag`, `Tag`, `TagKind`, `TagChange`, `tagName`; `applyServerErrors`, `errorText`, `useFieldError`, `Field`, `Dialog`, `StatusChip`, `EmptyState`.
- Produces:
  - `tagFormSchema` / `TagFormValues` in `schemas.ts`: `emoji` at most 8 code points, `name_ar`/`name_en` trimmed, 1–60, with i18n-key messages;
  - `<TagsSettings />`, exported from `@/features/people`: a tablist (Student tags / Teacher tags), then one row per tag named by its name (`listitem`), showing its people and "Retired". Each row has Move up / Move down (sending `{position: <new 1-based place>}`), Edit (a dialog), and Retire or Restore. Add tag opens a dialog of the open tab's kind;
  - the route `/settings/tags` (admins only) and the nav item `nav.tags` after Academy in the Settings group;
  - `src/test/people-fixtures.ts`: `tagRow(fields)`, `STUDENT_TAGS` (New 1, Star of the month 3, retired Old badge 9), `TEACHER_TAGS` (Patient 30).

- [ ] **Step 1: Write the failing tests**

The page lists each kind's tags with their people, marking retired ones. The first row can't move up and the last can't move down. A move sends the row's new place. Retire and restore send `is_active`. Adding checks the emoji in characters and the names before sending, then sends the open tab's kind. A duplicate name from the server lands on its field. A load error is translated, and the page reads in Arabic. The admin nav lists `/settings/tags` after `/settings/academy`.

Create `dashboard/src/test/people-fixtures.ts`:

```ts
import type { Tag } from "@/features/people/schemas";

/** A tags-admin row: a student tag unless ``fields`` says otherwise. */
export function tagRow(fields: Partial<Tag> & Pick<Tag, "id">): Tag {
	return {
		kind: "student",
		emoji: "⭐",
		name_ar: `وسم ${fields.id}`,
		name_en: `Tag ${fields.id}`,
		position: fields.id,
		is_active: true,
		people: 0,
		...fields,
	};
}

/** Three student tags: New, Star of the month and a retired Old badge. */
export const STUDENT_TAGS: Tag[] = [
	tagRow({ id: 1, emoji: "🎓", name_ar: "جديد", name_en: "New", people: 2 }),
	tagRow({
		id: 3,
		emoji: "⭐",
		name_ar: "نجم الشهر",
		name_en: "Star of the month",
		position: 2,
		people: 1,
	}),
	tagRow({
		id: 9,
		emoji: "🏷️",
		name_ar: "شارة قديمة",
		name_en: "Old badge",
		position: 3,
		is_active: false,
	}),
];

export const TEACHER_TAGS: Tag[] = [
	tagRow({
		id: 30,
		kind: "teacher",
		emoji: "🤝",
		name_ar: "صبور",
		name_en: "Patient",
		position: 1,
	}),
];
```

Create `dashboard/src/features/people/TagsSettings.test.tsx`:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError, AxiosHeaders } from "axios";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import i18n from "@/lib/i18n";
import { STUDENT_TAGS, TEACHER_TAGS } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { TagsSettings } from "./TagsSettings";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: {
			...actual.peopleApi,
			tags: vi.fn(),
			createTag: vi.fn(),
			updateTag: vi.fn(),
		},
	};
});

function badRequest(data: Record<string, string[]>) {
	return new AxiosError("Bad Request", "400", undefined, undefined, {
		status: 400,
		statusText: "Bad Request",
		data,
		headers: {},
		config: { headers: new AxiosHeaders() },
	});
}

// A row's accessible name is the tag's name; "New" is also a prefix of
// nothing else here, but match whole names anyway.
const row = (name: string) => screen.getByRole("listitem", { name });

describe("TagsSettings", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.tags).mockImplementation(async (kind) =>
			kind === "student" ? STUDENT_TAGS : TEACHER_TAGS,
		);
		vi.mocked(peopleApi.updateTag).mockImplementation(async (id, body) => ({
			...(STUDENT_TAGS.find((t) => t.id === id) ?? STUDENT_TAGS[0]),
			...body,
		}));
	});
	afterEach(async () => {
		await i18n.changeLanguage("en");
	});

	it("lists each kind's tags with their people, marking retired ones", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TagsSettings />);
		const star = await screen.findByRole("listitem", {
			name: "Star of the month",
		});
		expect(within(star).getByText("People: 1")).toBeInTheDocument();
		expect(within(star).queryByText("Retired")).toBeNull();
		const old = row("Old badge");
		expect(within(old).getByText("Retired")).toBeInTheDocument();
		expect(
			within(old).getByRole("button", { name: "Restore Old badge" }),
		).toBeInTheDocument();
		// The first can't move up, the last can't move down.
		expect(screen.getByRole("button", { name: "Move New up" })).toBeDisabled();
		expect(
			screen.getByRole("button", { name: "Move Old badge down" }),
		).toBeDisabled();
		await user.click(screen.getByRole("tab", { name: "Teacher tags" }));
		expect(
			await screen.findByRole("listitem", { name: "Patient" }),
		).toBeInTheDocument();
		expect(peopleApi.tags).toHaveBeenLastCalledWith("teacher");
	});

	it("moves a tag by its place in the list", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TagsSettings />);
		await screen.findByRole("listitem", { name: "Star of the month" });
		await user.click(
			screen.getByRole("button", { name: "Move Star of the month up" }),
		);
		await waitFor(() =>
			expect(peopleApi.updateTag).toHaveBeenCalledWith(3, { position: 1 }),
		);
		await user.click(screen.getByRole("button", { name: "Move New down" }));
		await waitFor(() =>
			expect(peopleApi.updateTag).toHaveBeenLastCalledWith(1, { position: 2 }),
		);
	});

	it("retires and restores", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TagsSettings />);
		await user.click(
			await screen.findByRole("button", { name: "Retire Star of the month" }),
		);
		await waitFor(() =>
			expect(peopleApi.updateTag).toHaveBeenCalledWith(3, {
				is_active: false,
			}),
		);
		expect(
			await screen.findByText(
				"Tag retired. It stays on the people who have it.",
			),
		).toBeInTheDocument();
		await user.click(screen.getByRole("button", { name: "Restore Old badge" }));
		await waitFor(() =>
			expect(peopleApi.updateTag).toHaveBeenLastCalledWith(9, {
				is_active: true,
			}),
		);
	});

	it("adds a tag of the open tab's kind and checks it first", async () => {
		vi.mocked(peopleApi.createTag).mockResolvedValue(TEACHER_TAGS[0]);
		const user = userEvent.setup();
		renderWithRouter(<TagsSettings />);
		await screen.findByRole("listitem", { name: "New" });
		await user.click(screen.getByRole("tab", { name: "Teacher tags" }));
		await user.click(screen.getByRole("button", { name: "Add tag" }));
		const dialog = await screen.findByRole("dialog");
		await user.type(
			within(dialog).getByLabelText("Emoji"),
			"🌙🌙🌙🌙🌙🌙🌙🌙🌙",
		);
		await user.click(within(dialog).getByRole("button", { name: "Save tag" }));
		expect(
			await within(dialog).findByText("Use at most 8 characters."),
		).toBeInTheDocument();
		expect(within(dialog).getAllByText("Enter a name.")).toHaveLength(2);
		expect(peopleApi.createTag).not.toHaveBeenCalled();
		// A flag is two characters to the server but four UTF-16 units.
		await user.clear(within(dialog).getByLabelText("Emoji"));
		await user.type(within(dialog).getByLabelText("Emoji"), "🇪🇬🇪🇬🇪🇬🇪🇬");
		await user.type(within(dialog).getByLabelText(/^Arabic name/), "هلال");
		await user.type(within(dialog).getByLabelText(/^English name/), "Crescent");
		await user.click(within(dialog).getByRole("button", { name: "Save tag" }));
		await waitFor(() =>
			expect(peopleApi.createTag).toHaveBeenCalledWith({
				emoji: "🇪🇬🇪🇬🇪🇬🇪🇬",
				name_ar: "هلال",
				name_en: "Crescent",
				kind: "teacher",
			}),
		);
		expect(await screen.findByText("Tag saved.")).toBeInTheDocument();
	});

	it("puts a duplicate name from the server on its field", async () => {
		vi.mocked(peopleApi.updateTag).mockRejectedValueOnce(
			badRequest({ name_en: ["A tag with this name already exists."] }),
		);
		const user = userEvent.setup();
		renderWithRouter(<TagsSettings />);
		await user.click(
			await screen.findByRole("button", { name: "Edit Star of the month" }),
		);
		const dialog = await screen.findByRole("dialog");
		const english = within(dialog).getByLabelText(/^English name/);
		expect(english).toHaveValue("Star of the month");
		await user.clear(english);
		await user.type(english, "new");
		await user.click(within(dialog).getByRole("button", { name: "Save tag" }));
		expect(
			await within(dialog).findByText("A tag with this name already exists."),
		).toBeInTheDocument();
		expect(peopleApi.updateTag).toHaveBeenCalledWith(3, {
			emoji: "⭐",
			name_ar: "نجم الشهر",
			name_en: "new",
		});
	});

	it("says when the tags couldn't load, and reads in Arabic", async () => {
		vi.mocked(peopleApi.tags).mockRejectedValueOnce(new Error("offline"));
		const { unmount } = renderWithRouter(<TagsSettings />);
		expect(
			await screen.findByText("Couldn't load the tags."),
		).toBeInTheDocument();
		unmount();
		await i18n.changeLanguage("ar");
		renderWithRouter(<TagsSettings />);
		expect(
			await screen.findByRole("listitem", { name: "نجم الشهر" }),
		).toBeInTheDocument();
		expect(
			screen.getByRole("tab", { name: "وسوم المعلمين" }),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, replace:

```ts
			"/settings/academy",
			"/account",
		]);
```

with:

```ts
			"/settings/academy",
			"/settings/tags",
			"/account",
		]);
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/people/TagsSettings.test.tsx src/features/shell/nav.test.ts`

Expected: FAIL — `Failed to resolve import "./TagsSettings"`, and the nav list lacks `/settings/tags`.

- [ ] **Step 3: Implement the page**

Append to `dashboard/src/features/people/schemas.ts`:

```ts
/** An emoji is counted in characters (code points), as the server counts it,
 * so a flag or a ZWJ sequence fits in 8 (D9). */
const EMOJI_MAX = 8;
const tagName = z
	.string()
	.trim()
	.min(1, "people.tags.errors.nameRequired")
	.max(60, "people.tags.errors.nameTooLong");
export const tagFormSchema = z.object({
	emoji: z
		.string()
		.trim()
		.refine(
			(value): boolean => [...value].length <= EMOJI_MAX,
			"people.tags.errors.emojiTooLong",
		),
	name_ar: tagName,
	name_en: tagName,
});
export type TagFormValues = z.infer<typeof tagFormSchema>;
```

Create `dashboard/src/features/people/TagsSettings.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowDown, ArrowUp, Tags } from "lucide-react";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { tagName } from "@/components/TagChips";
import { useFieldError } from "@/lib/field-error";
import { applyServerErrors, errorText } from "@/lib/form-errors";
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
	EmptyState,
	Field,
	Input,
	Spinner,
	StatusChip,
	toast,
} from "@/ui";
import type { TagChange } from "./api";
import { useCreateTag, useTags, useUpdateTag } from "./queries";
import {
	type Tag,
	type TagFormValues,
	type TagKind,
	tagFormSchema,
} from "./schemas";

const KINDS: readonly TagKind[] = ["student", "teacher"];

/** Settings → Tags (Plan 10 §6): a tab per kind; add, rename, reorder,
 * retire and restore. Nothing is ever deleted. */
export function TagsSettings() {
	const { t } = useTranslation();
	const [kind, setKind] = useState<TagKind>("student");
	return (
		<div className="flex flex-col gap-4">
			<div
				role="tablist"
				aria-label={t("people.tags.title")}
				className="flex flex-wrap gap-2 border-b border-border pb-2"
			>
				{KINDS.map((k) => (
					<button
						key={k}
						type="button"
						role="tab"
						aria-selected={kind === k}
						onClick={() => setKind(k)}
						className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
					>
						{t(`people.tags.tab.${k}`)}
					</button>
				))}
			</div>
			<TagList key={kind} kind={kind} />
		</div>
	);
}

function TagList({ kind }: { kind: TagKind }) {
	const { t, i18n } = useTranslation();
	const { data: tags, isPending, isError } = useTags(kind);
	const update = useUpdateTag();

	function change(tag: Tag, body: TagChange, done?: string) {
		update.mutate(
			{ id: tag.id, body },
			{
				onSuccess: () => {
					if (done) toast({ description: t(done), variant: "success" });
				},
				onError: (error) =>
					toast({ description: errorText(error, t), variant: "destructive" }),
			},
		);
	}

	return (
		<div className="flex flex-col gap-4">
			<div className="flex justify-end">
				<TagDialog kind={kind} />
			</div>
			{isError ? (
				<Alert variant="destructive">
					<AlertDescription>{t("people.tags.loadError")}</AlertDescription>
				</Alert>
			) : isPending ? (
				<div className="flex justify-center py-6">
					<Spinner />
				</div>
			) : tags.length === 0 ? (
				<EmptyState icon={Tags} title={t("people.tags.empty")} />
			) : (
				<ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
					{tags.map((tag, index) => {
						const name = tagName(tag, i18n.language);
						return (
							<li
								key={tag.id}
								aria-label={name}
								className="flex flex-wrap items-center gap-3 p-3"
							>
								<span aria-hidden="true" className="text-lg">
									{tag.emoji}
								</span>
								<span className="font-medium">{name}</span>
								{tag.is_active ? null : (
									<StatusChip>{t("people.tags.retired")}</StatusChip>
								)}
								<span className="text-sm text-muted-foreground">
									{t("people.tags.people", { count: tag.people })}
								</span>
								<div className="ms-auto flex flex-wrap items-center gap-1">
									{/* Places are 1-based and the server renumbers the
									    kind, so a move is this row's index, up or down. */}
									<Button
										size="icon"
										variant="ghost"
										aria-label={t("people.tags.moveUp", { name })}
										disabled={index === 0 || update.isPending}
										onClick={() => change(tag, { position: index })}
									>
										<ArrowUp className="size-4" />
									</Button>
									<Button
										size="icon"
										variant="ghost"
										aria-label={t("people.tags.moveDown", { name })}
										disabled={index === tags.length - 1 || update.isPending}
										onClick={() => change(tag, { position: index + 2 })}
									>
										<ArrowDown className="size-4" />
									</Button>
									<TagDialog kind={kind} tag={tag} />
									<Button
										size="sm"
										variant="outline"
										aria-label={t(
											tag.is_active
												? "people.tags.retireName"
												: "people.tags.restoreName",
											{ name },
										)}
										onClick={() =>
											change(
												tag,
												{ is_active: !tag.is_active },
												tag.is_active
													? "people.tags.retiredDone"
													: "people.tags.restoredDone",
											)
										}
									>
										{t(
											tag.is_active
												? "people.tags.retire"
												: "people.tags.restore",
										)}
									</Button>
								</div>
							</li>
						);
					})}
				</ul>
			)}
		</div>
	);
}

/** Add a tag of ``kind`` (no ``tag``), or edit ``tag``'s emoji and names. */
function TagDialog({ kind, tag }: { kind: TagKind; tag?: Tag }) {
	const { t, i18n } = useTranslation();
	const [open, setOpen] = useState(false);
	const create = useCreateTag(kind);
	const update = useUpdateTag();
	const fieldError = useFieldError();
	const {
		register,
		handleSubmit,
		reset,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<TagFormValues>({
		resolver: zodResolver(tagFormSchema),
		values: {
			emoji: tag?.emoji ?? "",
			name_ar: tag?.name_ar ?? "",
			name_en: tag?.name_en ?? "",
		},
	});
	const prefix = tag ? `tag-${tag.id}` : `new-${kind}-tag`;

	async function onSubmit(values: TagFormValues) {
		try {
			if (tag) await update.mutateAsync({ id: tag.id, body: values });
			else await create.mutateAsync(values);
			toast({ description: t("people.tags.saved"), variant: "success" });
			reset();
			setOpen(false);
		} catch (error) {
			applyServerErrors(error, setError);
		}
	}

	return (
		<Dialog open={open} onOpenChange={setOpen}>
			<DialogTrigger asChild>
				{tag ? (
					<Button
						size="sm"
						variant="outline"
						aria-label={t("people.tags.editName", {
							name: tagName(tag, i18n.language),
						})}
					>
						{t("people.tags.edit")}
					</Button>
				) : (
					<Button size="sm">{t("people.tags.add")}</Button>
				)}
			</DialogTrigger>
			<DialogContent>
				<DialogTitle>
					{t(tag ? "people.tags.editTitle" : "people.tags.add")}
				</DialogTitle>
				<DialogDescription>
					{t(tag ? "people.tags.editBody" : "people.tags.addBody")}
				</DialogDescription>
				<form
					onSubmit={handleSubmit(onSubmit)}
					className="mt-4 flex flex-col gap-4"
					noValidate
				>
					<Field
						id={`${prefix}-emoji`}
						label={t("people.tags.emoji")}
						error={fieldError(errors.emoji?.message)}
					>
						<Input {...register("emoji")} />
					</Field>
					<Field
						id={`${prefix}-name_ar`}
						label={t("people.tags.nameAr")}
						error={fieldError(errors.name_ar?.message)}
						required
					>
						<Input dir="rtl" {...register("name_ar")} />
					</Field>
					<Field
						id={`${prefix}-name_en`}
						label={t("people.tags.nameEn")}
						error={fieldError(errors.name_en?.message)}
						required
					>
						<Input dir="ltr" {...register("name_en")} />
					</Field>
					<DialogFooter className="mt-0">
						<DialogClose asChild>
							<Button type="button" variant="outline">
								{t("people.cancel")}
							</Button>
						</DialogClose>
						<Button type="submit" disabled={isSubmitting}>
							{t("people.tags.save")}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
```

In `dashboard/src/features/people/index.ts`, replace:

```ts
export { TeacherForm } from "./TeacherForm";
```

with:

```ts
export { TagsSettings } from "./TagsSettings";
export { TeacherForm } from "./TeacherForm";
```

Create `dashboard/src/routes/_authed/settings.tags.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { requireAdmin } from "@/features/identity/require-admin";
import { TagsSettings } from "@/features/people";
import { PageContainer, PageHeader } from "@/ui";

export const Route = createFileRoute("/_authed/settings/tags")({
	beforeLoad: ({ context }) => requireAdmin(context),
	component: function TagsSettingsRoute() {
		const { t } = useTranslation();
		usePageTitle(t("people.tags.title"));
		return (
			<PageContainer>
				<PageHeader
					title={t("people.tags.title")}
					description={t("people.tags.subtitle")}
				/>
				<TagsSettings />
			</PageContainer>
		);
	},
});
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	ShieldCheck,
	User,
```

with:

```ts
	ShieldCheck,
	Tags,
	User,
```

In `dashboard/src/features/shell/nav.ts`, replace:

```ts
	admin("/settings/academy", "nav.academy", Settings, "settings"),
```

with:

```ts
	admin("/settings/academy", "nav.academy", Settings, "settings"),
	// Plan 10: the academy's student and teacher tags.
	admin("/settings/tags", "nav.tags", Tags, "settings"),
```

Merge into `dashboard/src/locales/en/common.json`:

```json
{
	"nav": {
		"tags": "Tags"
	},
	"people": {
		"tags": {
			"title": "Tags",
			"subtitle": "Emoji tags that describe and encourage your students and teachers.",
			"tab": {
				"student": "Student tags",
				"teacher": "Teacher tags"
			},
			"add": "Add tag",
			"addBody": "The new tag goes at the end of the list.",
			"edit": "Edit",
			"editName": "Edit {{name}}",
			"editTitle": "Edit tag",
			"editBody": "The new name shows wherever the tag is used.",
			"emoji": "Emoji",
			"nameAr": "Arabic name",
			"nameEn": "English name",
			"save": "Save tag",
			"saved": "Tag saved.",
			"retire": "Retire",
			"retireName": "Retire {{name}}",
			"restore": "Restore",
			"restoreName": "Restore {{name}}",
			"retired": "Retired",
			"retiredDone": "Tag retired. It stays on the people who have it.",
			"restoredDone": "Tag restored.",
			"moveUp": "Move {{name}} up",
			"moveDown": "Move {{name}} down",
			"people": "People: {{count}}",
			"empty": "No tags yet.",
			"loadError": "Couldn't load the tags.",
			"errors": {
				"nameRequired": "Enter a name.",
				"nameTooLong": "Use at most 60 characters.",
				"emojiTooLong": "Use at most 8 characters."
			}
		}
	}
}
```

Merge into `dashboard/src/locales/ar/common.json`:

```json
{
	"nav": {
		"tags": "الوسوم"
	},
	"people": {
		"tags": {
			"title": "الوسوم",
			"subtitle": "وسوم بالرموز التعبيرية تصف طلابك ومعلميك وتشجّعهم.",
			"tab": {
				"student": "وسوم الطلاب",
				"teacher": "وسوم المعلمين"
			},
			"add": "إضافة وسم",
			"addBody": "يُضاف الوسم الجديد في آخر القائمة.",
			"edit": "تعديل",
			"editName": "تعديل {{name}}",
			"editTitle": "تعديل الوسم",
			"editBody": "يظهر الاسم الجديد أينما استُخدم الوسم.",
			"emoji": "الرمز التعبيري",
			"nameAr": "الاسم بالعربية",
			"nameEn": "الاسم بالإنجليزية",
			"save": "حفظ الوسم",
			"saved": "تم حفظ الوسم.",
			"retire": "إيقاف",
			"retireName": "إيقاف {{name}}",
			"restore": "استعادة",
			"restoreName": "استعادة {{name}}",
			"retired": "موقوف",
			"retiredDone": "تم إيقاف الوسم. يبقى على من يحملونه.",
			"restoredDone": "تمت استعادة الوسم.",
			"moveUp": "نقل {{name}} للأعلى",
			"moveDown": "نقل {{name}} للأسفل",
			"people": "الأشخاص: {{count}}",
			"empty": "لا توجد وسوم بعد.",
			"loadError": "تعذّر تحميل الوسوم.",
			"errors": {
				"nameRequired": "أدخل اسمًا.",
				"nameTooLong": "استخدم 60 حرفًا على الأكثر.",
				"emojiTooLong": "استخدم 8 أحرف على الأكثر."
			}
		}
	}
}
```

- [ ] **Step 4: Regenerate the route tree, format, then run the tests**

```bash
npx pnpm@10 exec vite build
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vitest run src/features/people/TagsSettings.test.tsx src/features/shell
```

Expected: `src/routeTree.gen.ts` now has `/_authed/settings/tags`; 34 passed.

- [ ] **Step 5: Verify**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 654 tests; lines 94.2%, branches 87.5%, functions 81.3%.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src/features/people src/features/shell src/routes src/routeTree.gen.ts src/test/people-fixtures.ts src/locales
git -C dashboard commit -m "feat(people): Settings → Tags: add, edit, move, retire and restore

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Dashboard: tags on the student and teacher forms; XP, nationality and age group on the student's

**Files:**
- Create: `dashboard/src/features/people/TagPicker.tsx`
- Modify: `dashboard/src/features/people/schemas.ts`, `dashboard/src/features/people/StudentForm.tsx`, `dashboard/src/features/people/TeacherForm.tsx`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/people/StudentForm.test.tsx`, `dashboard/src/features/people/TeacherForm.test.tsx`

**Interfaces:**
- Consumes: Task 6's `useTags`, `NATIONALITIES`, `XP_MAX`, `tagName`; Task 7's `STUDENT_TAGS`, `TEACHER_TAGS` fixtures and the `people.tags.retired`/`loadError` strings; `Fact`, `Checkbox`, `FormError`.
- Produces:
  - `<TagPicker kind value onChange error? />`: a fieldset (legend "Tags") of checkboxes: the kind's active tags, plus any retired tag in `value`, named `"<name> (Retired)"`; error id `profile.tag_ids-error`;
  - `studentFormSchema.profile` gains `xp` (integer 0–1,000,000, message `people.errors.xpInvalid`), `nationality` (`"" | arab | foreign`) and `tag_ids`; `teacherFormSchema.profile` gains `tag_ids`;
  - the student form sends `profile.{xp, nationality, tag_ids}` and shows the age group (a `Fact`) for a saved student who has one; the teacher form sends `profile.tag_ids`.

- [ ] **Step 1: Write the failing tests**

On an existing student, the form shows a retired tag the student has, checked and marked, and hides other retired tags. It shows the age group and saves tags, XP and nationality. XP is checked before saving (too big, or empty). A server error on `tag_ids` lands under the tags. A new teacher is tagged with teacher tags.

In `dashboard/src/features/people/StudentForm.test.tsx`, replace:

```tsx
import { screen, waitFor } from "@testing-library/react";
```

with:

```tsx
import { screen, waitFor, within } from "@testing-library/react";
```

In `dashboard/src/features/people/StudentForm.test.tsx`, replace:

```tsx
import { renderWithRouter } from "@/test/render";
```

with:

```tsx
import { STUDENT_TAGS } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
```

In `dashboard/src/features/people/StudentForm.test.tsx`, replace:

```tsx
			guardians: vi.fn(),
			list: vi.fn(),
		},
```

with:

```tsx
			guardians: vi.fn(),
			list: vi.fn(),
			tags: vi.fn(),
		},
```

In `dashboard/src/features/people/StudentForm.test.tsx`, replace:

```tsx
		vi.mocked(peopleApi.guardians).mockResolvedValue([]);
	});
```

with:

```tsx
		vi.mocked(peopleApi.guardians).mockResolvedValue([]);
		vi.mocked(peopleApi.tags).mockResolvedValue(STUDENT_TAGS);
	});
```

In `dashboard/src/features/people/StudentForm.test.tsx`, replace:

```tsx
			await screen.findByText("Couldn't load this student."),
		).toBeInTheDocument();
	});
});
```

with:

```tsx
			await screen.findByText("Couldn't load this student."),
		).toBeInTheDocument();
	});

	it("saves tags, XP and nationality, keeping a retired tag the student has", async () => {
		const tagged: Person<StudentProfile> = {
			...saved,
			profile: {
				...saved.profile,
				xp: 40,
				nationality: "arab",
				age_group: "teen",
				tags: [
					{ id: 9, emoji: "🏷️", name_ar: "شارة قديمة", name_en: "Old badge" },
				],
			},
		};
		vi.mocked(peopleApi.get).mockResolvedValue(tagged);
		vi.mocked(peopleApi.update).mockResolvedValue(tagged);
		const user = userEvent.setup();
		renderWithRouter(<StudentForm personId="5" />);
		const tags = await screen.findByRole("group", { name: "Tags" });
		expect(
			await within(tags).findByRole("checkbox", {
				name: "Old badge (Retired)",
			}),
		).toBeChecked();
		expect(
			within(tags).getByRole("checkbox", { name: "Star of the month" }),
		).not.toBeChecked();
		expect(within(tags).getAllByRole("checkbox")).toHaveLength(3);
		expect(screen.getByText("Teen")).toBeInTheDocument();
		await user.click(
			within(tags).getByRole("checkbox", { name: "Star of the month" }),
		);
		const xp = screen.getByLabelText("XP points");
		expect(xp).toHaveValue(40);
		await user.clear(xp);
		await user.type(xp, "120");
		await user.selectOptions(screen.getByLabelText("Nationality"), "foreign");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(peopleApi.update).toHaveBeenCalledWith(
				"students",
				5,
				expect.objectContaining({
					profile: expect.objectContaining({
						tag_ids: [9, 3],
						xp: 120,
						nationality: "foreign",
					}),
				}),
			),
		);
	});

	it("hides retired tags the student doesn't have and checks XP", async () => {
		vi.mocked(peopleApi.get).mockResolvedValue(saved);
		const user = userEvent.setup();
		renderWithRouter(<StudentForm personId="5" />);
		const tags = await screen.findByRole("group", { name: "Tags" });
		await within(tags).findByRole("checkbox", { name: "New" });
		expect(within(tags).queryByText("Old badge")).toBeNull();
		// No birthday, no age group.
		expect(screen.queryByText("Age group")).toBeNull();
		const xp = screen.getByLabelText("XP points");
		await user.clear(xp);
		await user.type(xp, "1000001");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(
			await screen.findByText("Enter a whole number from 0 to 1,000,000."),
		).toBeInTheDocument();
		await user.clear(xp);
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(
			await screen.findByText("Enter a whole number from 0 to 1,000,000."),
		).toBeInTheDocument();
		expect(peopleApi.update).not.toHaveBeenCalled();
	});

	it("puts the server's tag error under the tags", async () => {
		vi.mocked(peopleApi.get).mockResolvedValue(saved);
		vi.mocked(peopleApi.update).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { profile: { tag_ids: ["A retired tag can't be added."] } },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<StudentForm personId="5" />);
		await screen.findByDisplayValue("Aisha");
		await user.click(screen.getByRole("button", { name: "Save" }));
		const tags = screen.getByRole("group", { name: "Tags" });
		expect(
			await within(tags).findByText("A retired tag can't be added."),
		).toBeInTheDocument();
	});
});
```

In `dashboard/src/features/people/TeacherForm.test.tsx`, replace:

```tsx
import { renderWithRouter } from "@/test/render";
```

with:

```tsx
import { TEACHER_TAGS } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
```

In `dashboard/src/features/people/TeacherForm.test.tsx`, replace:

```tsx
			create: vi.fn(),
			update: vi.fn(),
		},
```

with:

```tsx
			create: vi.fn(),
			update: vi.fn(),
			tags: vi.fn(),
		},
```

In `dashboard/src/features/people/TeacherForm.test.tsx`, replace:

```tsx
			invoice_due_days: 7,
		});
		vi.mocked(catalogueApi.list).mockResolvedValue({
```

with:

```tsx
			invoice_due_days: 7,
		});
		vi.mocked(peopleApi.tags).mockResolvedValue(TEACHER_TAGS);
		vi.mocked(catalogueApi.list).mockResolvedValue({
```

In `dashboard/src/features/people/TeacherForm.test.tsx`, replace:

```tsx
			await screen.findByText("Couldn't load this teacher."),
		).toBeInTheDocument();
	});
});
```

with:

```tsx
			await screen.findByText("Couldn't load this teacher."),
		).toBeInTheDocument();
	});

	it("tags a teacher with teacher tags", async () => {
		vi.mocked(peopleApi.create).mockResolvedValue({ id: 30 } as never);
		const user = userEvent.setup();
		renderWithRouter(<TeacherForm personId="new" />, {
			extraPaths: ["/people/teachers/$personId"],
		});
		await user.type(await screen.findByLabelText(/full name/i), "Maryam");
		await user.selectOptions(screen.getByLabelText(/^Gender/), "female");
		await user.click(await screen.findByRole("checkbox", { name: "Patient" }));
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(peopleApi.create).toHaveBeenCalledWith(
				"teachers",
				expect.objectContaining({
					profile: expect.objectContaining({ tag_ids: [30] }),
				}),
			),
		);
		expect(peopleApi.tags).toHaveBeenCalledWith("teacher");
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/people/StudentForm.test.tsx src/features/people/TeacherForm.test.tsx`

Expected: FAIL — the four new tests: `Unable to find role="group" and name "Tags"` (and `"checkbox" … "Patient"`); the older tests still pass.

- [ ] **Step 3: Implement the picker and the form fields**

Create `dashboard/src/features/people/TagPicker.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { tagName } from "@/components/TagChips";
import { Checkbox, FormError } from "@/ui";
import { useTags } from "./queries";
import type { TagKind } from "./schemas";

/** A person's tags as checkboxes, the way the teacher form picks courses:
 * the kind's active tags, plus any retired tag the person already has,
 * marked as retired, so saving the form never drops it (Plan 10 §4.2). */
export function TagPicker({
	kind,
	value,
	onChange,
	error,
}: {
	kind: TagKind;
	value: number[];
	onChange: (ids: number[]) => void;
	error?: string;
}) {
	const { t, i18n } = useTranslation();
	const { data: tags, isError } = useTags(kind);
	const shown = (tags ?? []).filter(
		(tag) => tag.is_active || value.includes(tag.id),
	);
	return (
		<fieldset
			className="flex flex-col gap-2"
			aria-describedby={error ? "profile.tag_ids-error" : undefined}
		>
			<legend className="text-sm font-medium">{t("people.field.tags")}</legend>
			{isError ? (
				<p className="text-sm text-destructive">{t("people.tags.loadError")}</p>
			) : null}
			<div className="flex flex-wrap gap-x-4 gap-y-2">
				{shown.map((tag) => {
					const name = tagName(tag, i18n.language);
					const retired = `(${t("people.tags.retired")})`;
					return (
						<label
							key={tag.id}
							htmlFor={`tag-${tag.id}`}
							className="flex items-center gap-2 text-sm"
						>
							<Checkbox
								id={`tag-${tag.id}`}
								// Named in full here: the label's parts would run together.
								aria-label={tag.is_active ? name : `${name} ${retired}`}
								checked={value.includes(tag.id)}
								onCheckedChange={(on) =>
									onChange(
										on ? [...value, tag.id] : value.filter((x) => x !== tag.id),
									)
								}
							/>
							<span aria-hidden="true">{tag.emoji}</span>
							{name}
							{tag.is_active ? null : (
								<span className="text-muted-foreground">{retired}</span>
							)}
						</label>
					);
				})}
			</div>
			{error ? <FormError id="profile.tag_ids-error">{error}</FormError> : null}
		</fieldset>
	);
}
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
		status: z.enum(STUDENT_STATUSES),
		notes: z.string(),
	}),
});
```

with:

```ts
		status: z.enum(STUDENT_STATUSES),
		notes: z.string(),
		// `valueAsNumber` turns an empty box into NaN, which z.number() refuses.
		xp: z
			.number({ error: "people.errors.xpInvalid" })
			.int("people.errors.xpInvalid")
			.min(0, "people.errors.xpInvalid")
			.max(XP_MAX, "people.errors.xpInvalid"),
		nationality: z.enum(["", ...NATIONALITIES]),
		tag_ids: z.array(z.number()),
	}),
});
```

In `dashboard/src/features/people/schemas.ts`, replace:

```ts
			course_ids: z.array(z.number()),
		})
```

with:

```ts
			course_ids: z.array(z.number()),
			tag_ids: z.array(z.number()),
		})
```

In `dashboard/src/features/people/StudentForm.tsx`, replace:

```tsx
import { FormProvider, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
```

with:

```tsx
import { FormProvider, useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Fact } from "@/components/Fact";
```

In `dashboard/src/features/people/StudentForm.tsx`, replace:

```tsx
	emptyUser,
	type Person,
	STUDENT_STATUSES,
```

with:

```tsx
	emptyUser,
	NATIONALITIES,
	type Person,
	STUDENT_STATUSES,
```

In `dashboard/src/features/people/StudentForm.tsx`, replace:

```tsx
	userDefaults,
} from "./schemas";
import { UserFieldsSection } from "./UserFieldsSection";
```

with:

```tsx
	userDefaults,
	XP_MAX,
} from "./schemas";
import { TagPicker } from "./TagPicker";
import { UserFieldsSection } from "./UserFieldsSection";
```

In `dashboard/src/features/people/StudentForm.tsx`, replace:

```tsx
			status: p.status,
			notes: p.notes,
		},
```

with:

```tsx
			status: p.status,
			notes: p.notes,
			xp: p.xp,
			nationality: p.nationality,
			tag_ids: p.tags.map((tag) => tag.id),
		},
```

In `dashboard/src/features/people/StudentForm.tsx`, replace:

```tsx
							status: "active",
							notes: "",
						},
```

with:

```tsx
							status: "active",
							notes: "",
							xp: 0,
							nationality: "",
							tag_ids: [],
						},
```

In `dashboard/src/features/people/StudentForm.tsx`, replace:

```tsx
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = methods;
	const fieldError = useFieldError();
```

with:

```tsx
		handleSubmit,
		control,
		setError,
		formState: { errors, isSubmitting },
	} = methods;
	const tags = useController({
		control,
		name: "profile.tag_ids",
		defaultValue: [],
	});
	const fieldError = useFieldError();
```

In `dashboard/src/features/people/StudentForm.tsx`, replace:

```tsx
									</option>
								))}
							</Select>
						</Field>
					</div>
```

with:

```tsx
									</option>
								))}
							</Select>
						</Field>
						<Field
							id="profile.xp"
							label={t("people.field.xp")}
							error={fieldError(errors.profile?.xp?.message)}
						>
							<Input
								type="number"
								inputMode="numeric"
								min={0}
								max={XP_MAX}
								{...register("profile.xp", { valueAsNumber: true })}
							/>
						</Field>
						<Field
							id="profile.nationality"
							label={t("people.field.nationality")}
							error={fieldError(errors.profile?.nationality?.message)}
						>
							<Select {...register("profile.nationality")}>
								<option value="">—</option>
								{NATIONALITIES.map((n) => (
									<option key={n} value={n}>
										{t(`people.nationality.${n}`)}
									</option>
								))}
							</Select>
						</Field>
					</div>
					{person?.profile.age_group ? (
						<dl>
							<Fact label={t("people.field.age_group")}>
								{t(`people.ageGroup.${person.profile.age_group}`)}
							</Fact>
						</dl>
					) : null}
					<TagPicker
						kind="student"
						value={tags.field.value}
						onChange={tags.field.onChange}
						error={fieldError(errors.profile?.tag_ids?.message)}
					/>
```

In `dashboard/src/features/people/TeacherForm.tsx`, replace:

```tsx
	userDefaults,
} from "./schemas";
import { UserFieldsSection } from "./UserFieldsSection";
```

with:

```tsx
	userDefaults,
} from "./schemas";
import { TagPicker } from "./TagPicker";
import { UserFieldsSection } from "./UserFieldsSection";
```

In `dashboard/src/features/people/TeacherForm.tsx`, replace:

```tsx
			course_ids: p.course_ids,
		},
```

with:

```tsx
			course_ids: p.course_ids,
			tag_ids: p.tags.map((tag) => tag.id),
		},
```

In `dashboard/src/features/people/TeacherForm.tsx`, replace:

```tsx
							course_ids: [],
						},
```

with:

```tsx
							course_ids: [],
							tag_ids: [],
						},
```

In `dashboard/src/features/people/TeacherForm.tsx`, replace:

```tsx
		name: "profile.course_ids",
		defaultValue: [],
	});
```

with:

```tsx
		name: "profile.course_ids",
		defaultValue: [],
	});
	const tags = useController({
		control,
		name: "profile.tag_ids",
		defaultValue: [],
	});
```

In `dashboard/src/features/people/TeacherForm.tsx`, replace:

```tsx
					</fieldset>
					{errors.root?.server ? (
```

with:

```tsx
					</fieldset>
					<TagPicker
						kind="teacher"
						value={tags.field.value}
						onChange={tags.field.onChange}
						error={fieldError(pe?.tag_ids?.message)}
					/>
					{errors.root?.server ? (
```

Merge into `dashboard/src/locales/en/common.json`:

```json
{
	"people": {
		"field": {
			"tags": "Tags",
			"xp": "XP points",
			"nationality": "Nationality",
			"age_group": "Age group"
		},
		"nationality": {
			"arab": "Arab",
			"foreign": "Foreign"
		},
		"ageGroup": {
			"child": "Child",
			"teen": "Teen",
			"adult": "Adult"
		},
		"errors": {
			"xpInvalid": "Enter a whole number from 0 to 1,000,000."
		}
	}
}
```

Merge into `dashboard/src/locales/ar/common.json`:

```json
{
	"people": {
		"field": {
			"tags": "الوسوم",
			"xp": "نقاط الخبرة",
			"nationality": "الجنسية",
			"age_group": "الفئة العمرية"
		},
		"nationality": {
			"arab": "عربي",
			"foreign": "أجنبي"
		},
		"ageGroup": {
			"child": "طفل",
			"teen": "مراهق",
			"adult": "بالغ"
		},
		"errors": {
			"xpInvalid": "أدخل عددًا صحيحًا من 0 إلى 1,000,000."
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vitest run src/features/people
```

Expected: 53 passed.

- [ ] **Step 5: Verify**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 658 tests; lines 94.2%, branches 87.5%, functions 81.3%.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src/features/people src/locales
git -C dashboard commit -m "feat(people): tags on the student and teacher forms; XP, nationality and age group

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dashboard: tag chips, the tag, nationality and age filters, and bulk add and remove on the lists

**Files:**
- Create: `dashboard/src/features/people/TagOptions.tsx`
- Modify: `dashboard/src/features/people/StudentsList.tsx` (rewritten whole below), `dashboard/src/features/people/TeachersList.tsx`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`
- Test: `dashboard/src/features/people/StudentsList.test.tsx` and `dashboard/src/features/people/TeachersList.test.tsx` (both rewritten whole: the teacher fixture gains `tags`, without which the row crashes)

**Interfaces:**
- Consumes: Task 6's `useTags`, `useBulkStudents` (`BulkBody`), `TagChips`, `tagLabel`, `AGE_FILTERS`, `NATIONALITIES`; Task 7's fixtures and `people.tags.retired`; Task 8's `people.field.nationality`, `people.field.age_group`, `people.nationality.*`, `people.ageGroup.*`; `errorText`.
- Produces:
  - `<TagOptions tags />`: a kind's tags as `<option value={id}>`, labelled `tagLabel` and "(Retired)" when retired;
  - students list: a Tags column (chips); filters "Tag" (`tag`), "Nationality" (`nationality`) and "Age group" (`age_group`, with Minor), which reach the CSV link too; in the bulk bar, "Tag to add or remove" (the first active tag by default) with "Add tag" (disabled for a retired tag) and "Remove tag", sending `{ids, action, tag_id}`. A refused bulk action toasts the server's reason;
  - teachers list: a Tags column and a "Tag" filter.

- [ ] **Step 1: Write the failing tests**

Rows show their tags (scoped to the row, since tag names are also filter options). The tag, nationality and age filters reach the list and the CSV link; a retired tag is marked in the options. The bulk bar adds a tag to the selected rows, defaults to the first active tag, disables Add for a retired tag and still removes it. A refused bulk action shows the server's reason. Teachers show their tags and filter by one.

Create `dashboard/src/features/people/StudentsList.test.tsx` (it replaces the existing file whole):

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { STUDENT_TAGS } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { StudentsList } from "./StudentsList";
import type { Person, StudentProfile } from "./schemas";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: {
			...actual.peopleApi,
			list: vi.fn(),
			bulkStudents: vi.fn(),
			tags: vi.fn(),
		},
	};
});

const row = (
	id: number,
	name: string,
	email: string | null,
	tags: StudentProfile["tags"] = [],
): Person<StudentProfile> => ({
	id,
	role: "student",
	user: {
		full_name: name,
		email,
		phone: "",
		preferred_language: "ar",
		timezone: "UTC",
		is_active: true,
		account_state: email ? "invited" : "no_login",
		pending_email: "",
	},
	profile: {
		date_of_birth: null,
		gender: "",
		country: "EG",
		status: "trial",
		notes: "",
		xp: 0,
		nationality: "",
		age_group: null,
		tags,
	},
});

const page = (results: Person<StudentProfile>[]) => ({
	count: results.length,
	next: null,
	previous: null,
	results,
});

function lastParams() {
	return vi.mocked(peopleApi.list).mock.calls.at(-1)?.[1];
}

describe("StudentsList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.list).mockResolvedValue(
			page([
				row(1, "Yusuf", "y@x.test", [STUDENT_TAGS[1]]),
				row(2, "Aisha", null),
			]),
		);
		vi.mocked(peopleApi.tags).mockResolvedValue(STUDENT_TAGS);
	});

	it("lists students with their account state", async () => {
		renderWithRouter(<StudentsList />, {
			extraPaths: ["/people/students/$personId"],
		});
		expect(
			await screen.findByRole("link", { name: "Yusuf" }),
		).toBeInTheDocument();
		expect(screen.getByText("No login")).toBeInTheDocument();
	});

	it("filters by status tab and searches", async () => {
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		await screen.findByText("Aisha");
		await user.click(screen.getByRole("tab", { name: "Paused" }));
		await waitFor(() =>
			expect(lastParams()).toMatchObject({ status: "paused", page: 1 }),
		);
		await user.type(screen.getByRole("searchbox"), "yu");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({ q: "yu", status: "paused" }),
		);
		const csv = screen.getByRole("link", { name: "Export CSV" });
		expect(csv.getAttribute("href")).toContain("status=paused");
		expect(csv.getAttribute("href")).toContain("format=csv");
	});

	it("applies a bulk status change to the selected rows", async () => {
		vi.mocked(peopleApi.bulkStudents).mockResolvedValue({ updated: 2 });
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		await screen.findByText("Aisha");
		await user.click(screen.getByLabelText("Select Yusuf"));
		await user.click(screen.getByLabelText("Select Aisha"));
		const bar = screen.getByRole("region", { name: "2 selected" });
		await user.selectOptions(
			within(bar).getByLabelText("New status"),
			"paused",
		);
		await user.click(within(bar).getByRole("button", { name: "Set status" }));
		await waitFor(() =>
			expect(peopleApi.bulkStudents).toHaveBeenCalledWith({
				ids: [1, 2],
				action: "set_status",
				status: "paused",
			}),
		);
	});

	it("shows an empty state", async () => {
		vi.mocked(peopleApi.list).mockResolvedValue(page([]));
		renderWithRouter(<StudentsList />);
		expect(await screen.findByText("No students yet.")).toBeInTheDocument();
	});

	it("shows each row's tags and filters by tag, nationality and age", async () => {
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		// Tag names are also filter <option>s: look in Yusuf's row only.
		const yusuf = await screen.findByRole("row", { name: /Yusuf/ });
		expect(within(yusuf).getByRole("listitem")).toHaveTextContent(
			"Star of the month",
		);
		const filter = screen.getByLabelText("Tag");
		await within(filter).findByRole("option", { name: "⭐ Star of the month" });
		expect(
			within(filter).getByRole("option", { name: "🏷️ Old badge (Retired)" }),
		).toBeInTheDocument();
		await user.selectOptions(filter, "3");
		await user.selectOptions(screen.getByLabelText("Nationality"), "arab");
		await user.selectOptions(screen.getByLabelText("Age group"), "minor");
		await waitFor(() =>
			expect(lastParams()).toMatchObject({
				tag: "3",
				nationality: "arab",
				age_group: "minor",
				page: 1,
			}),
		);
		const csv = screen.getByRole("link", { name: "Export CSV" });
		expect(csv.getAttribute("href")).toContain("tag=3");
		expect(csv.getAttribute("href")).toContain("age_group=minor");
	});

	it("adds and removes a tag on the selected rows", async () => {
		vi.mocked(peopleApi.bulkStudents).mockResolvedValue({ updated: 2 });
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		await screen.findByText("Aisha");
		await user.click(screen.getByLabelText("Select Yusuf"));
		await user.click(screen.getByLabelText("Select Aisha"));
		const bar = screen.getByRole("region", { name: "2 selected" });
		const pick = within(bar).getByLabelText("Tag to add or remove");
		expect(pick).toHaveValue("1"); // the first active tag
		await user.selectOptions(pick, "3");
		await user.click(within(bar).getByRole("button", { name: "Add tag" }));
		await waitFor(() =>
			expect(peopleApi.bulkStudents).toHaveBeenCalledWith({
				ids: [1, 2],
				action: "add_tag",
				tag_id: 3,
			}),
		);
		await user.click(screen.getByLabelText("Select Aisha"));
		const again = screen.getByRole("region", { name: "1 selected" });
		// A retired tag can only be removed.
		await user.selectOptions(
			within(again).getByLabelText("Tag to add or remove"),
			"9",
		);
		expect(
			within(again).getByRole("button", { name: "Add tag" }),
		).toBeDisabled();
		await user.click(within(again).getByRole("button", { name: "Remove tag" }));
		await waitFor(() =>
			expect(peopleApi.bulkStudents).toHaveBeenLastCalledWith({
				ids: [2],
				action: "remove_tag",
				tag_id: 9,
			}),
		);
	});

	it("shows the server's reason when a bulk action is refused", async () => {
		vi.mocked(peopleApi.bulkStudents).mockRejectedValue(
			new AxiosError("Bad", "400", undefined, undefined, {
				status: 400,
				data: { tag_id: ["A retired tag can't be added."] },
			} as never),
		);
		const user = userEvent.setup();
		renderWithRouter(<StudentsList />);
		await screen.findByText("Aisha");
		await user.click(screen.getByLabelText("Select Aisha"));
		await user.click(screen.getByRole("button", { name: "Add tag" }));
		expect(
			await screen.findByText("A retired tag can't be added."),
		).toBeInTheDocument();
	});
});
```

Create `dashboard/src/features/people/TeachersList.test.tsx` (it replaces the existing file whole):

```tsx
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { catalogueApi } from "@/features/catalogue/api";
import { TEACHER_TAGS } from "@/test/people-fixtures";
import { renderWithRouter } from "@/test/render";
import { peopleApi } from "./api";
import { TeachersList } from "./TeachersList";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		peopleApi: { ...actual.peopleApi, list: vi.fn(), tags: vi.fn() },
	};
});
vi.mock("@/features/catalogue/api", async (orig) => {
	const actual = await orig<typeof import("@/features/catalogue/api")>();
	return { ...actual, catalogueApi: { ...actual.catalogueApi, list: vi.fn() } };
});

describe("TeachersList", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(peopleApi.tags).mockResolvedValue(TEACHER_TAGS);
		vi.mocked(catalogueApi.list).mockResolvedValue({
			count: 1,
			next: null,
			previous: null,
			results: [
				{
					id: 4,
					name_ar: "تجويد",
					name_en: "Tajweed",
					description_ar: "",
					description_en: "",
					language: "ar",
					is_active: true,
					teacher_ids: [9],
				},
			],
		});
		vi.mocked(peopleApi.list).mockResolvedValue({
			count: 1,
			next: null,
			previous: null,
			results: [
				{
					id: 9,
					role: "teacher",
					user: {
						full_name: "Bilal",
						email: "b@x.test",
						phone: "",
						preferred_language: "ar",
						timezone: "UTC",
						is_active: true,
						account_state: "active",
						pending_email: "",
					},
					profile: {
						gender: "male",
						date_of_birth: null,
						bio: "",
						default_meeting_url: "",
						pay_currency: "EGP",
						payout_method: "",
						payout_details: "",
						course_ids: [4],
						tags: [
							{ id: 30, emoji: "🤝", name_ar: "صبور", name_en: "Patient" },
						],
					},
				},
			],
		});
	});

	it("shows course names and filters by course", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TeachersList />);
		// "Tajweed" also appears as a course-filter <option>, so scope the
		// assertion to the table itself (ruling 2).
		const table = await screen.findByRole("table");
		expect(
			await within(table).findByRole("cell", { name: "Tajweed" }),
		).toBeInTheDocument();
		await user.selectOptions(screen.getByLabelText("Course"), "4");
		await waitFor(() =>
			expect(vi.mocked(peopleApi.list).mock.calls.at(-1)?.[1]).toMatchObject({
				course: "4",
			}),
		);
	});

	it("shows each teacher's tags and filters by one", async () => {
		const user = userEvent.setup();
		renderWithRouter(<TeachersList />);
		const table = await screen.findByRole("table");
		// "Patient" is also a filter <option>: look in the table only.
		expect(within(table).getByRole("listitem")).toHaveTextContent("Patient");
		await user.selectOptions(await screen.findByLabelText("Tag"), "30");
		await waitFor(() =>
			expect(vi.mocked(peopleApi.list).mock.calls.at(-1)?.[1]).toMatchObject({
				tag: "30",
			}),
		);
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/people/StudentsList.test.tsx src/features/people/TeachersList.test.tsx`

Expected: FAIL — the new tests: `Unable to find a label with the text of: Tag`, `… Tag to add or remove`, and no `listitem` in the rows.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/people/TagOptions.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { tagLabel } from "@/components/TagChips";
import type { Tag } from "./schemas";

/** A kind's tags as `<option>`s, retired ones marked, for a filter or the
 * bulk bar. */
export function TagOptions({ tags }: { tags: readonly Tag[] }) {
	const { t, i18n } = useTranslation();
	return (
		<>
			{tags.map((tag) => (
				<option key={tag.id} value={String(tag.id)}>
					{tag.is_active
						? tagLabel(tag, i18n.language)
						: `${tagLabel(tag, i18n.language)} (${t("people.tags.retired")})`}
				</option>
			))}
		</>
	);
}
```

Create `dashboard/src/features/people/StudentsList.tsx` (it replaces the existing file whole):

```tsx
import { Link } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { TagChips } from "@/components/TagChips";
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
	type StudentStatus,
} from "./schemas";
import { TagOptions } from "./TagOptions";

const TABS = ["all", ...STUDENT_STATUSES] as const;

export function StudentsList() {
	const { t, i18n } = useTranslation();
	const [params, setParams] = useState<ListParams>({ page: 1 });
	const [selected, setSelected] = useState<number[]>([]);
	const [bulkStatus, setBulkStatus] = useState<StudentStatus>("active");
	const [bulkTag, setBulkTag] = useState<number>();
	const bulk = useBulkStudents();
	const { data: tags = [] } = useTags("student");
	// The bulk bar's tag: the one chosen, else the first active tag.
	const tagId = bulkTag ?? tags.find((tag) => tag.is_active)?.id;
	const tagRetired = tags.find((tag) => tag.id === tagId)?.is_active === false;
	const current = String(params.status ?? "all");
	const update = (patch: ListParams) => {
		setSelected([]);
		setParams({ ...params, page: 1, ...patch });
	};

	const columns: Column<StudentProfile>[] = [
		{
			key: "name",
			header: t("people.columns.name"),
			cell: (p) => p.user.full_name,
		},
		{
			key: "email",
			header: t("people.columns.email"),
			cell: (p) => p.user.email ?? "—",
		},
		{
			key: "phone",
			header: t("people.columns.phone"),
			cell: (p) => <span dir="ltr">{p.user.phone || "—"}</span>,
		},
		{
			key: "status",
			header: t("people.columns.status"),
			cell: (p) => t(`people.status.${p.profile.status}`),
		},
		{
			key: "tags",
			header: t("people.columns.tags"),
			cell: (p) => <TagChips tags={p.profile.tags} />,
		},
		{
			key: "account",
			header: t("people.columns.account"),
			cell: (p) => <AccountStateChip state={p.user.account_state} />,
		},
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

	return (
		<div className="flex flex-col gap-4">
			<div
				role="tablist"
				aria-label={t("people.columns.status")}
				className="flex flex-wrap gap-2 border-b border-border pb-2"
			>
				{TABS.map((tab) => (
					<button
						key={tab}
						type="button"
						role="tab"
						aria-selected={current === tab}
						onClick={() => update({ status: tab === "all" ? undefined : tab })}
						className="rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary aria-selected:bg-secondary aria-selected:text-foreground"
					>
						{tab === "all" ? t("people.tabs.all") : t(`people.status.${tab}`)}
					</button>
				))}
			</div>
			{selected.length > 0 ? (
				<section
					aria-label={t("people.bulk.selected", { count: selected.length })}
					className="flex flex-wrap items-end gap-2 rounded-lg border border-border bg-secondary p-3"
				>
					<span className="me-auto text-sm font-medium">
						{t("people.bulk.selected", { count: selected.length })}
					</span>
					<Button
						size="sm"
						variant="outline"
						onClick={() => runBulk("activate")}
					>
						{t("people.account.activate")}
					</Button>
					<Button
						size="sm"
						variant="outline"
						onClick={() => runBulk("deactivate")}
					>
						{t("people.account.deactivate")}
					</Button>
					{/* aria-label, not a wrapping <label>: a wrapping label's text
					    would include every option's text. */}
					<Select
						aria-label={t("people.bulk.newStatus")}
						className="w-auto"
						value={bulkStatus}
						onChange={(e) => setBulkStatus(e.target.value as StudentStatus)}
					>
						{STUDENT_STATUSES.map((s) => (
							<option key={s} value={s}>
								{t(`people.status.${s}`)}
							</option>
						))}
					</Select>
					<Button size="sm" onClick={() => runBulk("set_status")}>
						{t("people.bulk.setStatus")}
					</Button>
					{tagId === undefined ? null : (
						<>
							<Select
								aria-label={t("people.bulk.tag")}
								className="w-auto"
								value={String(tagId)}
								onChange={(e) => setBulkTag(Number(e.target.value))}
							>
								<TagOptions tags={tags} />
							</Select>
							<Button
								size="sm"
								variant="outline"
								disabled={tagRetired}
								onClick={() => runBulk("add_tag")}
							>
								{t("people.bulk.addTag")}
							</Button>
							<Button
								size="sm"
								variant="outline"
								onClick={() => runBulk("remove_tag")}
							>
								{t("people.bulk.removeTag")}
							</Button>
						</>
					)}
				</section>
			) : null}
			<PeopleList<StudentProfile>
				kind="students"
				columns={columns}
				params={params}
				onParamsChange={(next) => {
					setSelected([]);
					setParams(next);
				}}
				detailTo="/people/students/$personId"
				emptyLabel={t("people.students.empty")}
				selection={{ selected, onChange: setSelected }}
				filters={
					<>
						<Select
							aria-label={t("people.filters.active")}
							className="w-auto"
							value={String(params.is_active ?? "")}
							onChange={(e) => update({ is_active: e.target.value })}
						>
							<option value="">{t("people.filters.anyAccount")}</option>
							<option value="true">{t("people.account.active")}</option>
							<option value="false">{t("people.account.inactive")}</option>
						</Select>
						<Select
							aria-label={t("people.field.gender")}
							className="w-auto"
							value={String(params.gender ?? "")}
							onChange={(e) => update({ gender: e.target.value })}
						>
							<option value="">{t("people.filters.anyGender")}</option>
							<option value="male">{t("people.gender.male")}</option>
							<option value="female">{t("people.gender.female")}</option>
						</Select>
						<Select
							aria-label={t("people.field.country")}
							className="w-auto"
							value={String(params.country ?? "")}
							onChange={(e) => update({ country: e.target.value })}
						>
							<option value="">{t("people.filters.anyCountry")}</option>
							{countryOptions(i18n.language).map((c) => (
								<option key={c.code} value={c.code}>
									{c.name}
								</option>
							))}
						</Select>
						<Select
							aria-label={t("people.filters.tag")}
							className="w-auto"
							value={String(params.tag ?? "")}
							onChange={(e) => update({ tag: e.target.value })}
						>
							<option value="">{t("people.filters.anyTag")}</option>
							<TagOptions tags={tags} />
						</Select>
						<Select
							aria-label={t("people.field.nationality")}
							className="w-auto"
							value={String(params.nationality ?? "")}
							onChange={(e) => update({ nationality: e.target.value })}
						>
							<option value="">{t("people.filters.anyNationality")}</option>
							{NATIONALITIES.map((n) => (
								<option key={n} value={n}>
									{t(`people.nationality.${n}`)}
								</option>
							))}
						</Select>
						<Select
							aria-label={t("people.field.age_group")}
							className="w-auto"
							value={String(params.age_group ?? "")}
							onChange={(e) => update({ age_group: e.target.value })}
						>
							<option value="">{t("people.filters.anyAge")}</option>
							{AGE_FILTERS.map((group) => (
								<option key={group} value={group}>
									{t(`people.ageGroup.${group}`)}
								</option>
							))}
						</Select>
					</>
				}
				actions={
					<Button asChild size="sm">
						<Link to="/people/students/$personId" params={{ personId: "new" }}>
							<Plus className="size-4" />
							{t("people.students.new")}
						</Link>
					</Button>
				}
			/>
		</div>
	);
}
```

In `dashboard/src/features/people/TeachersList.tsx`, replace:

```tsx
import { useTranslation } from "react-i18next";
import { useCatalogue } from "@/features/catalogue/queries";
```

with:

```tsx
import { useTranslation } from "react-i18next";
import { TagChips } from "@/components/TagChips";
import { useCatalogue } from "@/features/catalogue/queries";
```

In `dashboard/src/features/people/TeachersList.tsx`, replace:

```tsx
import { type Column, PeopleList } from "./PeopleList";
import type { TeacherProfile } from "./schemas";
```

with:

```tsx
import { type Column, PeopleList } from "./PeopleList";
import { useTags } from "./queries";
import type { TeacherProfile } from "./schemas";
import { TagOptions } from "./TagOptions";
```

In `dashboard/src/features/people/TeachersList.tsx`, replace:

```tsx
	const { data: courses } = useCatalogue<Course>("courses", { page_size: 100 });
```

with:

```tsx
	const { data: courses } = useCatalogue<Course>("courses", { page_size: 100 });
	const { data: tags = [] } = useTags("teacher");
```

In `dashboard/src/features/people/TeachersList.tsx`, replace:

```tsx
					.join("، ") || "—",
		},
		{
			key: "account",
```

with:

```tsx
					.join("، ") || "—",
		},
		{
			key: "tags",
			header: t("people.columns.tags"),
			cell: (p) => <TagChips tags={p.profile.tags} />,
		},
		{
			key: "account",
```

In `dashboard/src/features/people/TeachersList.tsx`, replace:

```tsx
						<option value="false">{t("people.account.inactive")}</option>
					</Select>
				</>
```

with:

```tsx
						<option value="false">{t("people.account.inactive")}</option>
					</Select>
					<Select
						aria-label={t("people.filters.tag")}
						className="w-auto"
						value={String(params.tag ?? "")}
						onChange={(e) => update({ tag: e.target.value })}
					>
						<option value="">{t("people.filters.anyTag")}</option>
						<TagOptions tags={tags} />
					</Select>
				</>
```

Merge into `dashboard/src/locales/en/common.json`:

```json
{
	"people": {
		"columns": {
			"tags": "Tags"
		},
		"filters": {
			"tag": "Tag",
			"anyTag": "Any tag",
			"anyNationality": "Any nationality",
			"anyAge": "Any age"
		},
		"ageGroup": {
			"minor": "Minor (under 18)"
		},
		"bulk": {
			"tag": "Tag to add or remove",
			"addTag": "Add tag",
			"removeTag": "Remove tag"
		}
	}
}
```

Merge into `dashboard/src/locales/ar/common.json`:

```json
{
	"people": {
		"columns": {
			"tags": "الوسوم"
		},
		"filters": {
			"tag": "الوسم",
			"anyTag": "أي وسم",
			"anyNationality": "أي جنسية",
			"anyAge": "أي عمر"
		},
		"ageGroup": {
			"minor": "قاصر (أقل من 18)"
		},
		"bulk": {
			"tag": "الوسم المراد إضافته أو إزالته",
			"addTag": "إضافة الوسم",
			"removeTag": "إزالة الوسم"
		}
	}
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vitest run src/features/people
```

Expected: 57 passed.

- [ ] **Step 5: Verify**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 662 tests; lines 94.2%, branches 87.6%, functions 81.6%.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src/features/people src/locales
git -C dashboard commit -m "feat(people): tag chips, tag, nationality and age filters, and bulk tagging

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Dashboard: a student's, a parent's and a teacher's own view

**Files:**
- Modify: `dashboard/src/features/identity/components/MyProfileCard.tsx` (rewritten whole below)
- Test: `dashboard/src/features/identity/components/MyProfileCard.test.tsx`

**Interfaces:**
- Consumes: Task 3's `me/` payload (`profile.tags/xp/age_group`, `children[].profile.tags/xp/age_group`, a teacher's `profile.tags`); Task 6's `TagChips`, `TagChip`; Task 8's `people.field.{tags,xp,age_group}` and `people.ageGroup.*`.
- Produces: `<MyProfileCard me />` (on `/account`) now shows:
  - for a student, Age group, XP points and Tags;
  - for a teacher, Tags;
  - for a parent, each child as a `listitem` named by the child, with status, age group, XP and tags.
  Nationality is never in `me/`, so it never shows.

- [ ] **Step 1: Write the failing tests**

A student sees their own tags, XP and age group; a parent sees each child's, scoped to that child; a teacher sees their own tags.

In `dashboard/src/features/identity/components/MyProfileCard.test.tsx`, replace:

```tsx
import { render, screen } from "@testing-library/react";
```

with:

```tsx
import { render, screen, within } from "@testing-library/react";
```

In `dashboard/src/features/identity/components/MyProfileCard.test.tsx`, replace:

```tsx
const base: Me = {
```

with:

```tsx
const star = {
	id: 3,
	emoji: "⭐",
	name_ar: "نجم الشهر",
	name_en: "Star of the month",
};

const base: Me = {
```

In `dashboard/src/features/identity/components/MyProfileCard.test.tsx`, replace:

```tsx
		expect(container).toBeEmptyDOMElement();
	});
});
```

with:

```tsx
		expect(container).toBeEmptyDOMElement();
	});

	it("shows a student their own tags, XP and age group", () => {
		render(
			<MyProfileCard
				me={{
					...base,
					profile: {
						status: "active",
						xp: 320,
						age_group: "child",
						tags: [star],
					},
				}}
			/>,
		);
		expect(screen.getByText("320")).toBeInTheDocument();
		expect(screen.getByText("Child")).toBeInTheDocument();
		expect(screen.getByRole("listitem")).toHaveTextContent("Star of the month");
	});

	it("shows each child's tags, XP and age group to their parent", () => {
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
							profile: {
								status: "active",
								xp: 40,
								age_group: "teen",
								tags: [star],
							},
						},
						{
							id: 10,
							full_name: "Aisha",
							student_profile_id: 4,
							profile: { status: "trial", xp: 0, age_group: null, tags: [] },
						},
					],
				}}
			/>,
		);
		const yusuf = screen.getByRole("listitem", { name: "Yusuf" });
		expect(within(yusuf).getByText("40")).toBeInTheDocument();
		expect(within(yusuf).getByText("Teen")).toBeInTheDocument();
		expect(within(yusuf).getByText("Star of the month")).toBeInTheDocument();
		const aisha = screen.getByRole("listitem", { name: "Aisha" });
		expect(within(aisha).queryByText("Star of the month")).toBeNull();
		expect(within(aisha).getByText("0")).toBeInTheDocument();
	});

	it("shows a teacher their own tags", () => {
		render(
			<MyProfileCard
				me={{
					...base,
					role: "teacher",
					profiles: ["teacher"],
					profile: {
						gender: "male",
						tags: [
							{ id: 30, emoji: "🤝", name_ar: "صبور", name_en: "Patient" },
						],
					},
				}}
			/>,
		);
		expect(screen.getByText("Tags")).toBeInTheDocument();
		expect(screen.getByRole("listitem")).toHaveTextContent("Patient");
	});
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from `dashboard/`): `npx pnpm@10 exec vitest run src/features/identity/components/MyProfileCard.test.tsx`

Expected: FAIL — the three new tests: `Unable to find an element with the text: 320`, `Unable to find role="listitem" and name "Yusuf"`, `Unable to find an element with the text: Tags`.

- [ ] **Step 3: Implement**

Create `dashboard/src/features/identity/components/MyProfileCard.tsx` (it replaces the existing file whole):

```tsx
import { useTranslation } from "react-i18next";
import { type TagChip, TagChips } from "@/components/TagChips";
import { Card, CardContent, CardHeader, CardTitle } from "@/ui";
import type { Me } from "../schemas";

const FIELDS: Record<string, readonly string[]> = {
	student: ["status", "gender", "date_of_birth", "country", "age_group", "xp"],
	teacher: ["gender", "default_meeting_url", "pay_currency"],
	parent: ["has_whatsapp"],
};
// Plan 10: students and teachers carry tags; a parent sees each child's.
const TAGGED = new Set(["student", "teacher"]);

function useDisplay() {
	const { t, i18n } = useTranslation();
	const regions = new Intl.DisplayNames([i18n.language], { type: "region" });
	return (field: string, value: unknown): string => {
		if (value === "" || value === null || value === undefined) return "—";
		if (typeof value === "boolean")
			return t(value ? "people.yes" : "people.no");
		if (field === "status") return t(`people.status.${value}`);
		if (field === "gender") return t(`people.gender.${value}`);
		if (field === "age_group") return t(`people.ageGroup.${value}`);
		if (field === "country") return regions.of(String(value)) ?? String(value);
		return String(value);
	};
}

const tagsOf = (profile?: Record<string, unknown>) =>
	(profile?.tags as TagChip[] | undefined) ?? [];

/** The signed-in user's own role profile, read-only (non-admins see only
 * this): a student's tags, XP and age group, a teacher's tags, and each of a
 * parent's children's. */
export function MyProfileCard({ me }: { me: Me }) {
	const { t } = useTranslation();
	const display = useDisplay();
	const fields = FIELDS[me.role];
	if (!fields) return null;
	const profile = me.profile ?? {};
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("account.myProfile")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				<dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
					{fields.map((field) => (
						<div key={field} className="contents">
							<dt className="text-muted-foreground">
								{t(`people.field.${field}`)}
							</dt>
							<dd>{display(field, profile[field])}</dd>
						</div>
					))}
					{TAGGED.has(me.role) ? (
						<div className="contents">
							<dt className="text-muted-foreground">
								{t("people.field.tags")}
							</dt>
							<dd>
								<TagChips tags={tagsOf(profile)} />
							</dd>
						</div>
					) : null}
				</dl>
				{me.children && me.children.length > 0 ? (
					<div className="flex flex-col gap-2">
						<h3 className="text-sm font-semibold">{t("account.children")}</h3>
						<ul className="flex flex-col gap-3 text-sm">
							{me.children.map((child) => (
								<li
									key={child.id}
									aria-label={child.full_name}
									className="flex flex-col gap-1"
								>
									<div className="flex justify-between gap-4">
										<span>{child.full_name}</span>
										<span className="text-muted-foreground">
											{display("status", child.profile?.status)}
										</span>
									</div>
									<dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
										{["age_group", "xp"].map((field) => (
											<div key={field} className="contents">
												<dt className="text-muted-foreground">
													{t(`people.field.${field}`)}
												</dt>
												<dd>{display(field, child.profile?.[field])}</dd>
											</div>
										))}
										<dt className="text-muted-foreground">
											{t("people.field.tags")}
										</dt>
										<dd>
											<TagChips tags={tagsOf(child.profile)} />
										</dd>
									</dl>
								</li>
							))}
						</ul>
					</div>
				) : null}
			</CardContent>
		</Card>
	);
}
```

- [ ] **Step 4: Format, then run the tests**

```bash
npx pnpm@10 exec biome check --write src e2e
npx pnpm@10 exec vitest run src/features/identity src/routes/_authed/account.test.tsx
```

Expected: 64 passed.

- [ ] **Step 5: Verify**

```bash
npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build
```

Expected: every check passes; 665 tests; lines 94.3%, branches 87.7%, functions 81.6%.

- [ ] **Step 6: Commit**

```bash
git -C dashboard add src/features/identity
git -C dashboard commit -m "feat(identity): own tags, XP and age group on the profile card; a parent's children's

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: End-to-end through Caddy: an admin tags a student in bulk, filters by the tag, and the student sees it; STATE.md

**Files:**
- Create: `dashboard/e2e/profile-depth.spec.ts`
- Modify: `STATE.md` (meta), submodule pointers (meta, after merge)

**Interfaces:**
- Consumes: Tasks 1–10; `e2e/fixtures.ts`'s `login`, `expectLoggedIn`, `acceptInvite`, `DEMO_URL`, `DEMO_ADMIN`.
- Produces: `e2e/profile-depth.spec.ts` (spec §8's journey, D11).
- CI: no change. The `e2e` job already migrates, runs `seed_dev` (which now seeds the presets and the demo profiles), and serves Django, the Vite preview and the marketing site behind `caddy/Caddyfile.e2e`.

- [ ] **Step 1: Write the journey**

The admin creates a student with an email address (the invite goes out on save), then a stamped tag in Settings → Tags ("People: 0"). From the students list they select that student alone and add the tag from the bulk bar ("1 updated."). With the search cleared, the tag filter alone lists exactly that student. The student then accepts the invite, signs in, and finds the tag among their own on `/account`. Names are stamped, so a second run on the same database finds only its own.

Create `dashboard/e2e/profile-depth.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import {
	acceptInvite,
	DEMO_ADMIN,
	DEMO_URL,
	expectLoggedIn,
	login,
} from "./fixtures";

// Plan 10 spec §8: an admin creates a tag, tags a student in bulk and
// filters by it; the student sees the tag on their own page. Names are
// stamped, so a second run on the same database finds only its own.
test("an admin tags a student in bulk, filters by the tag, and the student sees it", async ({
	page,
	browser,
}) => {
	const stamp = Date.now();
	const tag = `E2E Tag ${stamp}`;
	const student = `E2E Tagged ${stamp}`;
	const studentEmail = `e2e-tagged-${stamp}@e2e.test`;

	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// A student with a login (the invite goes out on save)
	await page.goto(`${DEMO_URL}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(student);
	await page.getByLabel(/^email/i).fill(studentEmail);
	await page.getByLabel("Preferred language").selectOption("en");
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page).toHaveURL(/\/app\/people\/students\/\d+$/);

	// Settings → Tags: a new student tag, last in the list
	await page.goto(`${DEMO_URL}/app/settings/tags`);
	await expect(
		page.getByRole("listitem", { name: "Star of the month" }),
	).toBeVisible();
	await page.getByRole("button", { name: "Add tag" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel("Emoji").fill("🧪");
	await dialog.getByLabel(/^arabic name/i).fill(`وسم ${stamp}`);
	await dialog.getByLabel(/^english name/i).fill(tag);
	await dialog.getByRole("button", { name: "Save tag" }).click();
	await expect(page.getByRole("listitem", { name: tag })).toContainText(
		"People: 0",
	);

	// The bulk bar adds it to the selected student
	await page.goto(`${DEMO_URL}/app/people/students`);
	await page.getByRole("searchbox").fill(student);
	await page.getByLabel(`Select ${student}`, { exact: true }).click();
	const bar = page.getByRole("region", { name: "1 selected" });
	await bar
		.getByLabel("Tag to add or remove")
		.selectOption({ label: `🧪 ${tag}` });
	await bar.getByRole("button", { name: "Add tag" }).click();
	await expect(page.getByText("1 updated.", { exact: true })).toBeVisible();

	// Filtering by the tag alone finds exactly that student
	await page.getByRole("searchbox").fill("");
	await page.getByLabel("Tag", { exact: true }).selectOption({
		label: `🧪 ${tag}`,
	});
	const row = page.getByRole("row", { name: new RegExp(student) });
	await expect(row).toContainText(tag);
	await expect(page.getByRole("row")).toHaveCount(2); // the header and it

	// The student signs in through the invite and sees the tag on their page
	const kid = await acceptInvite(
		browser,
		studentEmail,
		"e2e-Tagged-2026",
		student,
	);
	await kid.goto(`${DEMO_URL}/app/account`);
	await expect(kid.getByText("My profile")).toBeVisible();
	await expect(kid.getByRole("listitem").filter({ hasText: tag })).toBeVisible();
	await kid.context().close();
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

Expected: 19 passed (the 18 existing tests and `profile-depth.spec.ts`), with no retry. Run it a second time on the same database: the same result. Then stop the edge (`docker rm -f edge`), the three servers, and drop the database if it was a scratch one.

- [ ] **Step 3: Format and lint**

```bash
npx pnpm@10 exec biome check --write src e2e && npx pnpm@10 lint
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git -C dashboard add e2e/profile-depth.spec.ts
git -C dashboard commit -m "test(e2e): an admin tags a student in bulk and the student sees the tag

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Update `STATE.md`**

In `STATE.md`, replace everything between the `## Where we are` heading and the `## Next` heading with:

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
The e2e suite covers the journey through the Caddy edge.

```

In `STATE.md`, replace everything between the `## Next` heading and the next `##` heading with:

```markdown
Open the PRs (backend, dashboard → `main`; meta → `master`), get meta CI green, merge backend then
dashboard, bump the meta pointers, merge meta; nothing merges without the user's approval. Then
Plan 11 (family accounts and payer). Tags, XP, nationality and the age group live only in
`etqan.identity`: the age group is `ages.age_group`/`ages.born_lookups` on `clock.today()`, never a
stored column; the presets are `presets.PRESETS` and `presets.seed`; assignment rules are
`_tags_to_assign` and `_bulk_tag`. Never restate them elsewhere.

```

- [ ] **Step 6: Commit the meta state**

```bash
git add STATE.md docs/superpowers/plans/2026-09-27-plan-10-profile-depth.md
git commit -m "chore: state for Plan 10 — profile depth

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

After the backend and dashboard PRs merge, bump the submodule pointers in meta (`git add backend dashboard && git commit`) with the same trailer.

---

## Self-review

Checked against the spec after writing; fixes were made inline.

**Spec coverage**

| Spec | Task |
|---|---|
| §3.1 `Tag` fields, the case-insensitive uniqueness, the presets defined once, the migration, `create_academy`, idempotent seeding | 1 (D1, D2) |
| §3.2 `tags` on both profiles (the services enforce the kind), `xp`, `nationality` | 1, 3 (D4) |
| §4.1 the tags admin: admins only, duplicate 400, retire keeps assignments, order and active-people counts | 2 (D8) |
| §4.2 `tag_ids` (retired tags kept), the `tag`/`nationality`/`age_group` filters in SQL, bulk `add_tag`/`remove_tag`, the CSV columns | 3, 4 (D3–D6) |
| §4.3 and §5 who sees what, `me/`, nationality admin-only, no PUT or DELETE, fresh reads | 2, 3 (D7) |
| §6 Settings → Tags (tabs, add dialog, edit, retire/restore, up/down) | 7 (D9) |
| §6 forms (multi-select with retired marked; XP, Nationality), detail (tags; XP, age group, nationality for admins, on the admin-only edit page) | 8 |
| §6 lists (chips, Tag/Nationality/Age group filters, bulk add/remove) | 9 |
| §6 student, parent and teacher views | 10 |
| §7 seeds (every academy the presets; demo tags, XP, nationality, all three age groups; idempotent; `other` presets only) | 5 (D10) |
| §8 tests: duplicates either language and case; wrong-kind and retired refused one by one and in bulk; a retired tag survives edits; no delete; birthday boundaries; a non-UTC calendar; `minor`; exact paging; nationality never outside admin payloads; `me/` per role; 403s; `until_pk_exceeds`; flat query counts; the migration and `create_academy`; dashboard units; one e2e journey | 1–11 |

**Spec gaps settled here:** where `tag_ids` travels (inside `profile`, D4); what `position` means on PATCH and how ties heal (D8); whether the tag list pages (no) and what it answers without `kind` (both kinds); whether `remove_tag` accepts a retired tag (yes, D5); which language and column order the CSV uses (D6); how the emoji limit is counted (code points, D9); how 29 February birthdays turn over (D3); that `public` gets no presets (Global Constraints, D1); what "active people" counts (`user.is_active`, D8); where the detail pages show the new fields (the admin edit pages, D9); and that the e2e journey needs its own student with a login, since seeded ones have no password (D11).

**Placeholder scan:** no "TBD", "TODO", "similar to Task N" or step without its code. Every name a later task uses is produced by an earlier task's Interfaces block.

**Type and name consistency:**
- `profile_payload(user, *, staff, course_ids=None, today=None)` is the one signature, and both callers pass `staff`.
- `bulk_update_students(…, tag_id=…)` matches `StudentBulkSerializer.tag_id` and the dashboard's `BulkBody.tag_id`.
- `Tag`/`TagChip`/`TagInput`/`TagChange` are consistent across `schemas.ts`, `api.ts`, `queries.ts` and the components.
- The error fields are `tag_ids` for a person and `tag_id` for bulk, as the API sends them.

**Review Focus:** each of the five lines names its tests, which are in the owning task's test file.
