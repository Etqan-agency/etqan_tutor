# Plan 59 — B7g Recorded-course Certificates and Activation Codes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A student who watches every published lesson of a certificate playlist gets a printable, verifiable certificate, and the office can sell or give activation codes that enrol a student in a playlist. This slice also builds two pieces delegated to B7: R8 (learning's `SubjectCertificate`, ledger D58) and R9 (vouchers' redeemer registry, ledger D56).

**Architecture:**
- **R9, vouchers:** a generic registry, `register_redeemer(kind, …)`. Batches gain `target_id` and codes gain `target_ref_id`. The registered kind `playlist` is redeemed by a hook that `etqan.recorded` registers in `ready()`, so vouchers never imports recorded.
- **R8, learning:** a separate `SubjectCertificate` table with `issue_subject_certificate`, `revoke_by_source` and `certificate_by_source`. `verify()` falls back to it, and a read route plus a print page are added. `Certificate` is untouched.
- **B7:** `etqan.recorded` issues the certificate inside its watched writers (under the enrolment lock), exposes the office tick and the student link, and registers the playlist redeemer.

**Tech Stack:** Django 5 + DRF + django-tenants + pytest; React + TanStack Router/Query + Vitest + RTL + zod; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-08-b7g-recorded-certificates-codes-design.md` (G-1…G-7, §3, §4 with the R8/R9 terms D58/D56, §4a original request shapes). Phase decisions: `docs/superpowers/specs/2026-10-08-b7-add-on-sales-design.md` §2 (B7-12) and slice B7a §5–§12.

**Requires:** B7a (`etqan.recorded`, plan 49). B6d and B3f are merged on trunk. R8 and R9 are built **inside** this slice. **Before Task 1 the slice branches must merge trunk** (`origin/master` in meta, `origin/main` in backend and dashboard) to get the B6d `learning` certificates and the B3f `vouchers` code (Task 0).

**Written in spec-only mode** (2026-10-08): nothing below has been run. Build only once the phase holds a slot, B7a has merged and the stack is up (`just dev-backend`).

## Global Constraints

- Work from `/home/abdulkhalek/Projects/etqan_tutor-wt/b7`. `backend/` and `dashboard/` are separate git worktrees on the slice branch `feat/b7g-certificates-codes`. Never run `git submodule update` or any `git submodule` command that writes.
- Commands (after `set -a; . ./.env.stream; set +a` in the meta worktree), written below as:
  - `B <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django <cmd>`
  - `F <cmd>` = `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard <cmd>`
  - Whole suites: `just migrate`, `just test`, `just lint`, `just e2e`.
- **Claims (ledger D56/D58):**
  - Every edit to `etqan.vouchers` goes under `python3 scripts/orchestration/ledger.py claim B7 etqan.vouchers --reason "R9 redeemer registry"`, released right after the R9 commits with `ledger.py release B7 etqan.vouchers`.
  - Every edit to `etqan.learning` goes under `ledger.py claim B7 etqan.learning --reason "R8 SubjectCertificate"`, released after the R8 commits.
  - Dashboard files in `src/features/vouchers/` and `src/features/certificates/` are edited under a claim on that folder in their own task.
- **R9 is additive only.** Activation, renewal and discount codes keep working unchanged, and existing tests must pass untouched. A new test proves each still redeems.
- **R8 rules:**
  - `Certificate` is untouched.
  - B6's office certificate routes never list or edit `SubjectCertificate`.
  - `certificates_of` (D33) does **not** list them.
  - `verify()` answers the same T-8 fields, with `student_name` only while the certificate is valid.
  - The learning migration comes after `0004_certificates`.
- B7 data: `Enrolment` gains no column. Certificate state is learning's (G-4) and code state is vouchers' (G-5). People are addressed by **user id** in API and services.
- `etqan.recorded` reaches `learning` and `vouchers` only through `<app>.services`, and the import contracts are updated. Vouchers never imports recorded (new contract).
- Codes are never revenue (D43). A code enrolment has `method="code"`, `amount_minor=0`, `payment_id=None`, and the transaction number is the display code `SYS-XXXXX-XXXXX`.
- Lock order on redemption: Voucher → Playlist → Enrolment. On completion: Enrolment (the B7a writers' lock) → learning insert.
- Locales: `recorded.json`, `certificates.json` and `vouchers.json` in en and ar, with the same keys in both. No es file for new keys (D22).
- Commit messages end with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Stage explicit paths; never `git commit -a`.
- Backend coverage ≥ 80 %. Dashboard lines and statements ≥ 80, branches and functions ≥ 70.

## Review Focus

1. **Two lessons marked watched at once by two requests.** Exactly one certificate must be issued, not zero and not two. The enrolment row lock serializes the writers, and the `(source, source_id)` partial unique index is the last guard. Pinned in Task 6 (`test_parallel_completion_issues_once`, captured SQL and the unique-index path).
2. **A parent or another student redeeming a playlist code for someone outside their family.** The answer must be 404 and the code must stay unused. Pinned in Task 2 (`test_playlist_family_scope`).
3. **A playlist code redeemed while `recorded_courses` is off, or for an unpublished playlist.** The first gives B3f's `errors.unavailable()` (`vouchers.unavailable`, whose status G-6 gives as 404) and the second 409 `recorded.not_for_sale`, and the code stays unused in both cases. Pinned in Tasks 2 and 8.
4. **A revoked subject certificate looked up on the public verify page.** The answer must be `status: revoked` with no `student_name`. Pinned in Task 5 (`test_verify_falls_back_to_subject_certificates`).
5. **The office unticking "certificate obtained" and ticking it again.** The first certificate must be revoked with the fixed reason, and a fresh certificate with a new code issued. Pinned in Task 7.

---

## File Structure

```text
backend/etqan/vouchers/            (R9, under claim)
  models.py                        + Kind.PLAYLIST, VoucherBatch.target_id, Voucher.target_ref_id, constraint branch
  migrations/0002_redeemer_targets.py
  services/registry.py   (new)     Redeemer, register_redeemer, redeemer, office_code_of
  services/batches.py              generate(target_id=…), batches_exist
  services/redeem.py               _use_registered, Redemption.target_ref_id, _mark_used
  services/reads.py                Preview.target, target_of
  services/__init__.py             exports
  api/serializers.py, api/views.py, api/payloads.py
  tests/test_registry.py (new)
backend/etqan/learning/            (R8, under claim)
  models.py                        + SubjectCertificate
  migrations/0005_subject_certificates.py
  services/subject_certificates.py (new)
  services/certificates.py         verify() fallback
  services/__init__.py             exports
  api/certificate_views.py         + SubjectCertificateView
  api/serializers.py               + subject_certificate_data
  api/urls.py                      + subject-certificates/<int:pk>/
  tests/test_subject_certificates.py (new)
backend/etqan/recorded/
  services/certificates.py (new)   SOURCE, issue_if_complete, set_certificate, certificate_of
  services/codes.py (new)          playlist redeemer: describe/check/redeem, register
  services/watching.py, services/enrolments.py, services/playlists.py, services/__init__.py
  apps.py                          ready() registers the redeemer
  api/serializers.py, api/views.py, api/my_views.py
  tests/test_certificates.py, tests/test_codes.py (new)
backend/pyproject.toml             contracts
backend/etqan/access/tests/test_routes.py   + the subject-certificate route rows (B7 block)
dashboard/src/features/certificates/   SubjectCertificatePrint, CertificateSheet extraction, api/queries/schemas
dashboard/src/routes/_print/subject-certificates.$certificateId.print.tsx
dashboard/src/features/recorded/       EnrolmentDialog cert section, CoursePlayer link, schemas/api
dashboard/src/features/vouchers/       playlist kind in schemas, GenerateCodesDialog, RedeemCodePage, CodesPage
dashboard/src/locales/{en,ar}/{recorded,certificates,vouchers}.json
dashboard/e2e/b7-recorded-certificates.spec.ts
```

---

### Task 0: Bring trunk into the slice branches

**Files:** none edited by hand, except to resolve merge conflicts.

- [ ] **Step 1: Create the slice branches on top of B7a's merged trunk.** B7a must be merged before this slice builds (`ledger.py show`).

```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/b7
git fetch origin && git switch -c feat/b7g-certificates-codes origin/master
git -C backend fetch origin && git -C backend switch -c feat/b7g-certificates-codes origin/main
git -C dashboard fetch origin && git -C dashboard switch -c feat/b7g-certificates-codes origin/main
python3 scripts/orchestration/ledger.py phase B7 --branch feat/b7g-certificates-codes --slice B7g
```

If B7c is still unmerged and this slice must stack on it, merge its branch instead, e.g. `git -C backend merge --no-edit origin/feat/b7c-consultations-office`. Resolve conflicts by spec §6.2 of the orchestration design: shared lists keep both lines in order under their markers; regenerate `routeTree.gen.ts` with `F pnpm vite build`; never hand-merge a migration.

- [ ] **Step 2: Check the trunk code is present.**

```bash
ls backend/etqan/learning/migrations/0004_certificates.py backend/etqan/vouchers/services/redeem.py backend/etqan/recorded/services/watching.py
set -a; . ./.env.stream; set +a
just migrate
B pytest etqan/vouchers etqan/learning etqan/recorded -q
```

Expected: the three files exist; the suites pass.

---

### Task 1: R9 — the redeemer registry, targets and the `playlist` kind (vouchers)

**Files:**
- Modify: `backend/etqan/vouchers/models.py`
- Create: `backend/etqan/vouchers/migrations/0002_redeemer_targets.py` (generated)
- Create: `backend/etqan/vouchers/services/registry.py`
- Modify: `backend/etqan/vouchers/services/__init__.py`
- Test: `backend/etqan/vouchers/tests/test_registry.py`

**Interfaces:**
- Produces:
  - `VoucherBatch.Kind.PLAYLIST == "playlist"`; `VoucherBatch.target_id: int | None`; `Voucher.target_ref_id: int | None`.
  - `register_redeemer(kind: str, *, describe, check, redeem, office_code: str, feature: str) -> None`.
  - `redeemer(kind) -> Redeemer | None`.
  - `REGISTERED_KINDS = frozenset({"playlist"})`.
  - `Redeemer(describe: Callable[[int], tuple[str, str]], check: Callable[[int], None], redeem: Callable[..., tuple[int, int]], office_code: str, feature: str)`.
  - `redeem(*, target_id: int, student_user_id: int, code_display: str, by) -> (student_profile_id, ref_id)`.

- [ ] **Step 1: Claim vouchers.**

```bash
python3 scripts/orchestration/ledger.py claim B7 etqan.vouchers --reason "R9 redeemer registry (D56), slice B7g"
```

- [ ] **Step 2: Write the failing tests.** `backend/etqan/vouchers/tests/test_registry.py`:

```python
import pytest
from django.core.exceptions import ImproperlyConfigured
from django.db import IntegrityError
from django.db import transaction

from etqan.vouchers.models import Voucher
from etqan.vouchers.models import VoucherBatch
from etqan.vouchers.services import registry

pytestmark = pytest.mark.django_db


def _noop(*args, **kwargs):
    return None


def test_register_and_find(monkeypatch):
    monkeypatch.setattr(registry, "_REDEEMERS", {})
    registry.register_redeemer(
        "playlist",
        describe=lambda t: ("Course", "دورة"),
        check=_noop,
        redeem=lambda **kw: (1, 2),
        office_code="rc_enrolment.create",
        feature="recorded_courses",
    )
    found = registry.redeemer("playlist")
    assert found.office_code == "rc_enrolment.create"
    assert found.feature == "recorded_courses"
    assert registry.redeemer("activation") is None


def test_registering_twice_with_other_hooks_is_refused(monkeypatch):
    monkeypatch.setattr(registry, "_REDEEMERS", {})
    kw = {"check": _noop, "redeem": _noop, "office_code": "x", "feature": "f"}
    registry.register_redeemer("playlist", describe=_noop, **kw)
    registry.register_redeemer("playlist", describe=_noop, **kw)  # same: no-op
    with pytest.raises(ImproperlyConfigured):
        registry.register_redeemer("playlist", describe=lambda t: ("a", "b"), **kw)


@pytest.mark.parametrize("kind", ["activation", "renewal", "discount", "nope"])
def test_only_registrable_kinds(monkeypatch, kind):
    monkeypatch.setattr(registry, "_REDEEMERS", {})
    with pytest.raises(ImproperlyConfigured):
        registry.register_redeemer(
            kind, describe=_noop, check=_noop, redeem=_noop, office_code="x", feature="f"
        )


def _batch(**fields):
    base = {
        "kind": "playlist",
        "valid_days": 30,
        "expires_on": "2026-07-01",
        "quantity": 1,
        "target_id": 7,
    }
    return VoucherBatch.objects.create(**(base | fields))


def test_playlist_batch_needs_a_target_and_no_course():
    assert _batch().target_id == 7
    with pytest.raises(IntegrityError), transaction.atomic():
        _batch(target_id=None)


def test_core_kinds_take_no_target(world):
    with pytest.raises(IntegrityError), transaction.atomic():
        VoucherBatch.objects.create(
            kind="discount",
            valid_days=30,
            expires_on="2026-07-01",
            quantity=1,
            discount_kind="percent",
            discount_value=10,
            target_id=3,
        )


def test_voucher_keeps_its_target_ref():
    batch = _batch()
    code = Voucher.objects.create(batch=batch, kind="playlist", code="ABCDEFGHJK")
    assert code.target_ref_id is None
```

- [ ] **Step 3: Run them to verify they fail.** Run: `B pytest etqan/vouchers/tests/test_registry.py -q`. Expected: FAIL with `ImportError` on `registry`.

- [ ] **Step 4: Edit the models.** In `backend/etqan/vouchers/models.py`:
  - Add to `VoucherBatch.Kind`: `PLAYLIST = "playlist", "Recorded course"`.
  - Add after `teacher`:

```python
    # B7g R9 (D56): what a registered kind names, by plain id (F-1).
    target_id = models.BigIntegerField(null=True, blank=True)
```

  - Replace the `vouchers_batch_targets_follow_kind` constraint with:

```python
            models.CheckConstraint(
                condition=Q(
                    kind="activation",
                    course__isnull=False,
                    package__isnull=False,
                    teacher__isnull=False,
                    target_id__isnull=True,
                )
                | Q(
                    kind="renewal",
                    course__isnull=False,
                    package__isnull=False,
                    teacher__isnull=True,
                    target_id__isnull=True,
                )
                | Q(kind="discount", teacher__isnull=True, target_id__isnull=True)
                | Q(
                    kind="playlist",
                    target_id__isnull=False,
                    course__isnull=True,
                    package__isnull=True,
                    teacher__isnull=True,
                ),
                name="vouchers_batch_targets_follow_kind",
            ),
```

  - Add to `Voucher` after `payment_id`:

```python
    # B7g R9: what a registered kind's redemption created (e.g. an enrolment).
    target_ref_id = models.BigIntegerField(null=True, blank=True)
```

- [ ] **Step 5: Generate the migration.** Run `B python manage.py makemigrations vouchers --name redeemer_targets`. Read the file:
  - It must only `AddField` (two nullable columns), `AlterField` the `kind` choices on both models, and `RemoveConstraint`/`AddConstraint` the targets constraint.
  - Every existing row satisfies the new constraint, since the old kinds now also require `target_id IS NULL` and the column is new and null.
  - Nothing is dropped or rewritten.

- [ ] **Step 6: Write the registry.** `backend/etqan/vouchers/services/registry.py`:

```python
"""B7g R9 (ledger D56): kinds other apps redeem. The owning app registers
its hooks in its AppConfig.ready(); vouchers never imports it. A kind must
be a declared choice (the database checks its target) and not a core one."""

from collections.abc import Callable
from dataclasses import dataclass

from django.core.exceptions import ImproperlyConfigured

from etqan.vouchers.models import VoucherBatch

REGISTERED_KINDS = frozenset({VoucherBatch.Kind.PLAYLIST})


@dataclass(frozen=True)
class Redeemer:
    # (name_en, name_ar) of the target, for lists and the family's check.
    describe: Callable[[int], tuple[str, str]]
    # Raises ValidationError(field="target") when the target cannot be sold.
    check: Callable[[int], None]
    # redeem(*, target_id, student_user_id, code_display, by)
    #   -> (student_profile_id, ref_id); raises to refuse (the code stays unused).
    redeem: Callable[..., tuple[int, int]]
    # What the office also needs beside voucher.update (F-20's KIND_CODES).
    office_code: str
    # The owning app's switch: off -> generation 400, redemption 409 unavailable.
    feature: str


_REDEEMERS: dict[str, Redeemer] = {}


def register_redeemer(
    kind: str, *, describe, check, redeem, office_code: str, feature: str
) -> None:
    if kind not in REGISTERED_KINDS:
        raise ImproperlyConfigured(f"{kind!r} is not a registrable voucher kind.")
    hooks = Redeemer(describe, check, redeem, office_code, feature)
    if _REDEEMERS.get(kind, hooks) != hooks:
        raise ImproperlyConfigured(f"The voucher kind {kind!r} is registered already.")
    _REDEEMERS[kind] = hooks


def redeemer(kind: str) -> Redeemer | None:
    return _REDEEMERS.get(kind)
```

  Export `REGISTERED_KINDS`, `Redeemer`, `register_redeemer` and `redeemer` from `services/__init__.py`, adding them to the imports and `__all__`.

- [ ] **Step 7: Run the tests to verify they pass.** Run: `B pytest etqan/vouchers -q`. Expected: PASS, including every pre-existing vouchers test unchanged.

- [ ] **Step 8: Commit.**

```bash
B ruff format etqan/vouchers && B ruff check etqan/vouchers
git -C backend add etqan/vouchers/models.py etqan/vouchers/migrations/0002_redeemer_targets.py etqan/vouchers/services/registry.py etqan/vouchers/services/__init__.py etqan/vouchers/tests/test_registry.py
git -C backend commit -m "feat(vouchers): B7g R9 redeemer registry and playlist kind" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: R9 — generate, redeem and preview for registered kinds (vouchers services)

**Files:**
- Modify: `backend/etqan/vouchers/services/batches.py`, `services/redeem.py`, `services/reads.py`, `services/__init__.py`
- Test: `backend/etqan/vouchers/tests/test_registry.py` (extend)

**Interfaces:**
- Consumes: Task 1's registry.
- Produces:
  - `generate(..., target_id: int | None = None)`.
  - `batches_exist(*, kind: str, target_id: int) -> bool`.
  - `Redemption` gains `target_ref_id: int | None = None` as its last field (additive).
  - `Preview` gains `target: dict | None = None` (last field).
  - `target_of(batch) -> dict | None` returns `{"id", "name_en", "name_ar"}`.
  - `redeem()` handles a registered kind.

- [ ] **Step 1: Write the failing tests** (append to `test_registry.py`):

```python
from datetime import date

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.vouchers import services


@pytest.fixture
def fake(monkeypatch, codes_on, set_features):
    """A playlist redeemer standing in for recorded's (Task 8 registers it)."""
    set_features(recorded_courses=True)
    calls = []

    def check(target_id):
        if target_id == 404:
            raise ValidationError("Choose a recorded course.", field="target")

    def redeem(*, target_id, student_user_id, code_display, by):
        from etqan.identity import services as identity_services  # noqa: PLC0415

        calls.append((target_id, student_user_id, code_display))
        profile = identity_services.get_student_profile(student_user_id)
        return profile.pk, 99

    monkeypatch.setitem(
        registry._REDEEMERS,
        "playlist",
        registry.Redeemer(
            describe=lambda t: (f"Course {t}", f"دورة {t}"),
            check=check,
            redeem=redeem,
            office_code="rc_enrolment.create",
            feature="recorded_courses",
        ),
    )
    return calls


def _generate(admin, **extra):
    fields = {"kind": "playlist", "quantity": 2, "valid_days": 30, "by": admin}
    return services.generate(**(fields | extra))


def test_generate_a_playlist_batch(fake, admin):
    batch = _generate(admin, target_id=7)
    assert batch.target_id == 7 and batch.codes.count() == 2
    assert services.batches_exist(kind="playlist", target_id=7)
    assert not services.batches_exist(kind="playlist", target_id=8)


@pytest.mark.parametrize(
    ("extra", "field"),
    [({}, "target"), ({"target_id": 404}, "target"), ({"target_id": 7, "course_id": 1}, "course")],
)
def test_generate_refusals(fake, admin, extra, field):
    with pytest.raises(ValidationError) as exc:
        _generate(admin, **extra)
    assert exc.value.field == field


def test_generate_refused_while_the_owner_is_off(fake, admin, set_features):
    set_features(recorded_courses=False)
    with pytest.raises(ValidationError) as exc:
        _generate(admin, target_id=7)
    assert exc.value.field == "kind"


def test_a_target_on_a_core_kind_is_refused(codes_on, admin, world):
    with pytest.raises(ValidationError) as exc:
        services.generate(
            kind="discount", quantity=1, valid_days=30, by=admin,
            discount_kind="percent", discount_value=10, target_id=3,
        )
    assert exc.value.field == "target"


def test_redeem_a_playlist_code(fake, admin, world):
    code = _generate(admin, target_id=7).codes.first()
    result = services.redeem(code=code.code, user=world.student, student_user_id=world.student.id)
    assert result.kind == "playlist" and result.target_ref_id == 99
    assert (result.amount_minor, result.currency) == (0, "")
    code.refresh_from_db()
    assert code.status == "used" and code.target_ref_id == 99
    assert code.student.user_id == world.student.id and code.payment_id is None
    assert fake == [(7, world.student.id, services.display(code.code))]


def test_playlist_family_scope(fake, admin, world, parent):
    from etqan.identity import services as identity_services  # noqa: PLC0415

    stranger = identity_services.create_person("student", full_name="Zaid")
    code = _generate(admin, target_id=7).codes.first()
    with pytest.raises(NotFoundError):
        services.redeem(code=code.code, user=stranger, student_user_id=world.student.id)
    services.redeem(code=code.code, user=parent, student_user_id=world.student.id)
    code.refresh_from_db()
    assert code.status == "used"


def test_a_refusing_hook_leaves_the_code_unused(fake, admin, world, monkeypatch):
    def refuse(**kw):
        raise ConflictError("Not for sale.", code="recorded.not_for_sale")

    hooks = registry._REDEEMERS["playlist"]  # frozen: replace the whole entry
    monkeypatch.setitem(
        registry._REDEEMERS, "playlist",
        registry.Redeemer(hooks.describe, hooks.check, refuse, hooks.office_code, hooks.feature),
    )
    code = _generate(admin, target_id=7).codes.first()
    with pytest.raises(ConflictError):
        services.redeem(code=code.code, user=world.student, student_user_id=world.student.id)
    code.refresh_from_db()
    assert code.status == "unused"


def test_redeem_while_owner_off_is_unavailable(fake, admin, world, set_features):
    code = _generate(admin, target_id=7).codes.first()
    set_features(recorded_courses=False)
    with pytest.raises(ConflictError) as exc:
        services.redeem(code=code.code, user=world.student, student_user_id=world.student.id)
    assert exc.value.code == "vouchers.unavailable"


def test_preview_lists_the_family_and_the_target(fake, admin, world):
    code = _generate(admin, target_id=7).codes.first()
    shown = services.preview(code.code, user=world.student)
    assert shown.kind == "playlist"
    assert shown.target == {"id": 7, "name_en": "Course 7", "name_ar": "دورة 7"}
    assert [s["id"] for s in shown.students] == [world.student.id]


@pytest.mark.parametrize("kind", ["activation", "renewal", "discount"])
def test_core_kinds_still_redeem(kind, codes_on, admin, world, invoice):
    """D56: the registry changes nothing for the three B3f kinds."""
    from etqan.vouchers.tests.test_redeem import make_code  # noqa: PLC0415

    code = make_code(kind, admin, world)
    targets = {
        "activation": {"student_user_id": world.student.id},
        "renewal": {"subscription_id": world.subscription.id},
        "discount": {"invoice_id": invoice().id},
    }[kind]
    result = services.redeem(code=code.code, user=admin, office=True, **targets)
    assert result.kind == kind and result.target_ref_id is None
```

Check `etqan/vouchers/tests/test_redeem.py` for its code-making helper and the `world.subscription` fixture name. If none fits, build the codes with `services.generate(...)` exactly as `test_redeem.py` does, and keep the test's four assertions.

- [ ] **Step 2: Run them to verify they fail.** Run: `B pytest etqan/vouchers/tests/test_registry.py -q`. Expected: FAIL (`generate()` has no `target_id`; `Redemption` has no `target_ref_id`).

- [ ] **Step 3: Implement.**

`services/batches.py`:
  - Import `from etqan.platform import features` and `from etqan.vouchers.services.registry import redeemer`.
  - Add the `target_id: int | None = None` keyword to `generate`. Change the first kind check to accept registered kinds, then branch:

```python
    if kind not in Kind.values:
        raise ValidationError(
            "Choose activation, renewal, discount or a recorded course.", field="kind"
        )
    hooks = redeemer(kind)
    if kind not in (Kind.ACTIVATION, Kind.RENEWAL, Kind.DISCOUNT):
        if hooks is None or not features.enabled(hooks.feature):
            raise ValidationError("This kind of code is not available.", field="kind")
        if course_id is not None:
            raise ValidationError("This kind names no course.", field="course")
        if package_id is not None:
            raise ValidationError("This kind names no package.", field="package")
        if teacher_user_id is not None:
            raise ValidationError("This kind names no teacher.", field="teacher")
        _whole(target_id, 1, MAX_ID, "target", "Choose what the code is for.")
        hooks.check(target_id)
    elif target_id is not None:
        raise ValidationError("This kind takes no target.", field="target")
```

    Keep the quantity, valid-days and note checks before this block, unchanged. Pass `target_id=target_id` to `VoucherBatch.objects.create`. For registered kinds the existing course, package, teacher and discount checks are skipped: course, package and teacher are refused above, and `_discount` already returns blanks for non-discount kinds.
  - Add:

```python
def batches_exist(*, kind: str, target_id: int) -> bool:
    """B7g G-7: whether any batch names this target (a playlist in use)."""
    return VoucherBatch.objects.filter(kind=kind, target_id=target_id).exists()
```

`services/redeem.py`:
  - `Redemption` gains `target_ref_id: int | None = None` as its last field.
  - `_Outcome` gains `target_ref_id: int | None = None` as its last field.
  - Import `from etqan.platform import features` and `from etqan.vouchers.services.registry import redeemer`.
  - Add:

```python
def _use_registered(voucher: Voucher, user, student_user_id, *, office: bool) -> _Outcome:
    """D56: a registered kind; the owner's hook does the work inside this
    transaction (Voucher locked first, then the owner's rows: F-15)."""
    hooks = redeemer(voucher.kind)
    if hooks is None or not features.enabled(hooks.feature):
        raise errors.unavailable()
    student_user_id = _target(student_user_id, "student", "Choose a student.")
    if not office and not in_family(user, student_user_id):
        raise NotFoundError("Student", student_user_id)
    profile_id, ref_id = hooks.redeem(
        target_id=voucher.batch.target_id,
        student_user_id=student_user_id,
        code_display=display(voucher.code),
        by=user,
    )
    redemption = Redemption(
        kind=voucher.kind,
        subscription_id=None,
        invoice_id=None,
        amount_minor=0,
        currency="",
        target_ref_id=ref_id,
    )
    return _Outcome(redemption, profile_id, None, ref_id)
```

  - In `redeem()`, dispatch to `_use_registered` first when the kind is not one of the three core kinds:

```python
    if voucher.kind not in (Kind.ACTIVATION, Kind.RENEWAL, Kind.DISCOUNT):
        outcome = _use_registered(voucher, user, student_user_id, office=office)
    elif voucher.kind == Kind.ACTIVATION:
```

  - In `_mark_used`, also set `voucher.target_ref_id = outcome.target_ref_id` and add `"target_ref_id"` to `update_fields`.

`services/reads.py`:
  - `Preview` gains `target: dict | None = None` as its last field.
  - Add:

```python
def target_of(batch) -> dict | None:
    """D56: a registered kind's target, named by its owner."""
    if batch.target_id is None:
        return None
    hooks = redeemer(batch.kind)
    if hooks is None:
        return {"id": batch.target_id, "name_en": "", "name_ar": ""}
    name_en, name_ar = hooks.describe(batch.target_id)
    return {"id": batch.target_id, "name_en": name_en, "name_ar": name_ar}
```

    In `preview()`, list the family's students for `ACTIVATION` **and** registered kinds: `if kind == VoucherBatch.Kind.ACTIVATION or kind in REGISTERED_KINDS`. Pass `target=target_of(batch)`. Import `redeemer` and `REGISTERED_KINDS` from `registry`.
  - Export `batches_exist` and `target_of`.

- [ ] **Step 4: Run the tests to verify they pass.** Run: `B pytest etqan/vouchers -q`. Expected: PASS, with every pre-existing test unchanged.

- [ ] **Step 5: Commit.**

```bash
B ruff format etqan/vouchers && B ruff check etqan/vouchers
git -C backend add etqan/vouchers/services etqan/vouchers/tests/test_registry.py
git -C backend commit -m "feat(vouchers): B7g R9 generate, redeem and preview registered kinds" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: R9 — API, payloads and contracts (vouchers), then release the claim

**Files:**
- Modify: `backend/etqan/vouchers/api/serializers.py`, `api/views.py`, `api/payloads.py`
- Modify: `backend/pyproject.toml`
- Test: `backend/etqan/vouchers/tests/test_registry.py` (extend with API cases)

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `POST vouchers/batches/` accepts `target` (an int).
  - Batch, code and preview payloads gain `target: {id, name_en, name_ar} | null`; the redemption payload gains `target_ref_id`.
  - Office redemption of a registered kind needs `voucher.update` plus the redeemer's `office_code`.

- [ ] **Step 1: Write the failing tests** (append):

```python
from rest_framework.test import APIClient

B = "/api/v1/vouchers/"


def _client(user):
    c = APIClient()
    c.force_login(user)
    return c


def test_api_generates_and_lists_a_playlist_batch(fake, admin):
    resp = _client(admin).post(
        f"{B}batches/", {"kind": "playlist", "quantity": 1, "valid_days": 30, "target": 7}, format="json"
    )
    assert resp.status_code == 201, resp.data
    assert resp.data["target"] == {"id": 7, "name_en": "Course 7", "name_ar": "دورة 7"}
    codes = _client(admin).get(f"{B}codes/").data["results"]
    assert codes[0]["target"]["id"] == 7


def test_office_redeem_needs_the_registered_code(fake, admin, world, staff_for):
    code = _generate(admin, target_id=7).codes.first()
    staff = staff_for("voucher.update")
    resp = staff.post(f"{B}codes/{code.pk}/redeem/", {"student": world.student.id}, format="json")
    assert resp.status_code == 403
    staff = staff_for("voucher.update", "rc_enrolment.create")
    resp = staff.post(f"{B}codes/{code.pk}/redeem/", {"student": world.student.id}, format="json")
    assert resp.status_code == 201 and resp.data["target_ref_id"] == 99


def test_family_check_and_redeem(fake, admin, world):
    code = _generate(admin, target_id=7).codes.first()
    student = _client(world.student)
    shown = student.post(f"{B}check/", {"code": code.code}, format="json")
    assert shown.status_code == 200 and shown.data["kind"] == "playlist"
    assert shown.data["target"]["id"] == 7
    done = student.post(f"{B}redeem/", {"code": code.code, "student": world.student.id}, format="json")
    assert done.status_code == 201 and done.data["kind"] == "playlist"
```

Use the `staff_for` fixture's real signature from `etqan/conftest.py` (code arguments). If it returns a client, call `.post` on it directly as above.

- [ ] **Step 2: Run them to verify they fail.** Run: `B pytest etqan/vouchers/tests/test_registry.py -q`. Expected: FAIL (`target` not accepted; no `target` in payloads).

- [ ] **Step 3: Implement.**
  - `serializers.BatchInput`: add `target = _id(required=False, allow_null=True)`. `kind` already reads `VoucherBatch.Kind.choices`, which now include `playlist`. Change `CodeQueryInput.kind` the same way (no change needed if it already reads the choices).
  - `views.py`:
    - Add `"target": "target_id"` to `BATCH_FIELDS`.
    - Replace `KIND_CODES[kind]` in `_office_may` with `_office_codes(kind)`:

```python
def _office_codes(kind: str) -> tuple[str, ...]:
    """F-20's KIND_CODES, extended by registration (D56)."""
    if kind in KIND_CODES:
        return KIND_CODES[kind]
    hooks = services.redeemer(kind)
    return (hooks.office_code,) if hooks else ()
```

    - Use `missing = [code for code in _office_codes(kind) if not _holds(request.user, code)]`. Keep the discount `_need("invoices")` line unchanged.
  - `payloads.py`:
    - `_terms(batch)` gains `"target": services.target_of(batch)`.
    - Add `("target.name_en", "Recorded course")` to `CSV_COLUMNS` after `("teacher.full_name", "Teacher")`.
    - `redemption()` and `preview()` already use `asdict` and pick up the new fields.

- [ ] **Step 4: Contracts** (`backend/pyproject.toml`):
  - In "other apps reach vouchers only through its services", add `"etqan.recorded"` to `source_modules`. Extend its `ignore_imports` to:

```toml
ignore_imports = [
    "etqan.tenants.** -> etqan.vouchers.services",
    # B7g R9 (D56): recorded registers its playlist redeemer through services.
    "etqan.recorded.** -> etqan.vouchers.services",
]
```

    Update the comment above it: `# F-1 as amended by D56: only the tenants seeds and etqan.recorded reach vouchers, through its services.`
  - Under the `── phase B7 ──` marker, after the recorded and consultations contracts, add:

```toml
[[tool.importlinter.contracts]]
name = "vouchers never imports recorded"
type = "forbidden"
# B7g R9 (D56): the playlist kind is reached through the registry only.
source_modules = ["etqan.vouchers"]
forbidden_modules = ["etqan.recorded"]
```

  - In the "recorded reaches other apps only through their services" contract, add `"etqan.vouchers"` to `forbidden_modules` (`etqan.learning` is already there). Add these to `ignore_imports`: `"etqan.recorded.** -> etqan.vouchers.services"` and `"etqan.recorded.** -> etqan.learning.services"`. **Add the learning line only in Task 6**, when the import first exists; an unmatched ignore fails `lint-imports`.

- [ ] **Step 5: Run.** `B pytest etqan/vouchers etqan/access -q && B lint-imports`. Expected: PASS. The vouchers ignore for recorded is unmatched until Task 8. If `lint-imports` fails on it now, move that one ignore line to Task 8 and say so in the report.

- [ ] **Step 6: Commit and release the claim.**

```bash
B ruff format etqan/vouchers && B ruff check etqan/vouchers
git -C backend add etqan/vouchers/api etqan/vouchers/tests/test_registry.py pyproject.toml
git -C backend commit -m "feat(vouchers): B7g R9 API, payloads and contracts for registered kinds" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 etqan.vouchers
```

---

### Task 4: R8 — `SubjectCertificate` and its services (learning)

**Files:**
- Modify: `backend/etqan/learning/models.py`
- Create: `backend/etqan/learning/migrations/0005_subject_certificates.py` (generated)
- Create: `backend/etqan/learning/services/subject_certificates.py`
- Modify: `backend/etqan/learning/services/__init__.py`
- Test: `backend/etqan/learning/tests/test_subject_certificates.py`

**Interfaces:**
- Produces:
  - `CertificateRef(id: int, code: str, issued_on: date, revoked: bool)`.
  - `issue_subject_certificate(*, student_user_id, subject_en, subject_ar, count, source, source_id, by=None) -> CertificateRef`. It is idempotent: the open certificate for `(source, source_id)` is returned when one exists.
  - `revoke_by_source(source, source_id, *, reason, by) -> None` (a no-op with nothing open).
  - `certificate_by_source(source, source_id) -> CertificateRef | None` (the newest row, revoked or not).
  - `get_subject_certificate(user, pk) -> SubjectCertificate`, scoped as `certificates_queryset`.

- [ ] **Step 1: Claim learning.**

```bash
python3 scripts/orchestration/ledger.py claim B7 etqan.learning --reason "R8 SubjectCertificate (D58), slice B7g"
```

- [ ] **Step 2: Write the failing tests.** `backend/etqan/learning/tests/test_subject_certificates.py`:

```python
import pytest
from django.db import IntegrityError
from django.db import transaction

from etqan.learning import services
from etqan.learning.models import SubjectCertificate
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
SRC = "recorded.enrolment"


def issue(world, **extra):
    fields = {
        "student_user_id": world.student.id,
        "subject_en": "Tajweed basics",
        "subject_ar": "أساسيات التجويد",
        "count": 5,
        "source": SRC,
        "source_id": 11,
    }
    return services.issue_subject_certificate(**(fields | extra))


def test_issue_and_read_back(world, clock):
    ref = issue(world)
    row = SubjectCertificate.objects.get(pk=ref.id)
    assert (row.subject_en, row.count, row.count_label) == ("Tajweed basics", 5, "lessons")
    assert row.issued_on == ref.issued_on and len(ref.code) >= 20 and not ref.revoked
    assert row.issued_by is None
    assert services.certificate_by_source(SRC, 11) == ref


def test_issue_is_idempotent_while_open(world):
    assert issue(world) == issue(world)
    assert SubjectCertificate.objects.count() == 1


def test_one_open_per_source_in_the_database(world):
    issue(world)
    with pytest.raises(IntegrityError), transaction.atomic():
        SubjectCertificate.objects.create(
            student=SubjectCertificate.objects.get().student,
            subject_en="x", subject_ar="x", count=1, source=SRC, source_id=11,
            issued_on="2026-06-01",
        )


def test_revoke_then_issue_again_gives_a_new_code(world):
    first = issue(world)
    services.revoke_by_source(SRC, 11, reason="Revoked from the recorded course enrolment", by=None)
    assert services.certificate_by_source(SRC, 11).revoked
    second = issue(world)
    assert second.code != first.code and not second.revoked
    assert services.certificate_by_source(SRC, 11) == second


def test_revoke_with_nothing_open_is_a_noop(world):
    services.revoke_by_source(SRC, 99, reason="x", by=None)
    assert services.certificate_by_source(SRC, 99) is None


@pytest.mark.parametrize(
    ("extra", "field"),
    [({"subject_en": " "}, "subject_en"), ({"count": -1}, "count"), ({"count": 10000}, "count"),
     ({"count": True}, "count"), ({"source": ""}, "source")],
)
def test_issue_refusals(world, extra, field):
    with pytest.raises(ValidationError) as exc:
        issue(world, **extra)
    assert exc.value.field == field


def test_scoped_reads(world, api_for, parent_of_student, other_student):
    ref = issue(world)
    assert services.get_subject_certificate(api_for("admin").user, ref.id).pk == ref.id
    assert services.get_subject_certificate(world.student, ref.id).pk == ref.id
    assert services.get_subject_certificate(parent_of_student, ref.id).pk == ref.id
    with pytest.raises(NotFoundError):
        services.get_subject_certificate(other_student, ref.id)


def test_certificates_of_does_not_list_them(world, clock):
    ref = issue(world)
    assert services.certificates_of(world.student.id, month=ref.issued_on) == []
```

  Use the learning conftest's real fixture names for a parent of `world.student` and an unrelated student. The B6d tests have them: check `etqan/learning/tests/conftest.py`. If none exists, create the two people inline with `identity_services.create_person` and `link_guardian`, as `etqan/recorded/tests/conftest.py` does.

- [ ] **Step 3: Run them to verify they fail.** Run: `B pytest etqan/learning/tests/test_subject_certificates.py -q`. Expected: FAIL with `ImportError` on `SubjectCertificate`.

- [ ] **Step 4: Model.** Append to `backend/etqan/learning/models.py`:

```python
class SubjectCertificate(models.Model):
    """B7g R8 (ledger D58): a completion certificate for something that is
    not a catalogue course (a recorded course, ...), issued by its owner
    through learning's services. Read by verify() and the print page; B6's
    certificate list never shows it; certificates_of never lists it."""

    class CountLabel(models.TextChoices):
        LESSONS = "lessons", "Lessons"

    student = models.ForeignKey(
        "identity.StudentProfile", on_delete=models.PROTECT, related_name="+"
    )
    subject_en = models.CharField(max_length=200)
    subject_ar = models.CharField(max_length=200)
    count = models.PositiveIntegerField()
    count_label = models.CharField(
        max_length=10, choices=CountLabel.choices, default=CountLabel.LESSONS
    )
    source = models.CharField(max_length=40)
    source_id = models.BigIntegerField()
    code = models.CharField(max_length=32, unique=True, default=new_code)
    issued_on = models.DateField()
    revoked_at = models.DateTimeField(null=True, blank=True)
    revoke_reason = models.TextField(blank=True, default="", max_length=500)
    issued_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-issued_on", "-id")
        constraints = [
            models.UniqueConstraint(
                fields=["source", "source_id"],
                condition=Q(revoked_at__isnull=True),
                name="learning_subject_certificate_one_open",
            ),
            models.CheckConstraint(
                condition=Q(count__lte=9999),
                name="learning_subject_certificate_count_max",
            ),
        ]

    def __str__(self):
        return f"subject certificate {self.pk}"
```

  Run `B python manage.py makemigrations learning --name subject_certificates`. It must be `0005_subject_certificates` depending on `0004_certificates`, and create only the new table.

- [ ] **Step 5: Services.** `backend/etqan/learning/services/subject_certificates.py`:

```python
"""B7g R8 (ledger D58): certificates whose subject is owned elsewhere."""

from dataclasses import dataclass
from datetime import date

from django.db import IntegrityError
from django.db import transaction
from django.utils import timezone

from etqan.identity import services as identity_services
from etqan.learning.models import SubjectCertificate
from etqan.learning.services.progress import _student
from etqan.learning.services.progress import academy_today
from etqan.platform.exceptions import NotFoundError
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import is_office
from etqan.platform.permissions import role_of

MAX_COUNT = 9999
MAX_SUBJECT = 200


@dataclass(frozen=True)
class CertificateRef:
    id: int
    code: str
    issued_on: date
    revoked: bool


def _ref(row: SubjectCertificate) -> CertificateRef:
    return CertificateRef(row.pk, row.code, row.issued_on, row.revoked_at is not None)


def _subject(value, field: str) -> str:
    text = (value or "").strip() if isinstance(value, str) else ""
    if not text:
        raise ValidationError("A subject is required.", field=field)
    if len(text) > MAX_SUBJECT:
        raise ValidationError("The subject is too long.", field=field)
    return text


def _count(value) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= MAX_COUNT:
        raise ValidationError(f"Enter a number from 0 to {MAX_COUNT}.", field="count")
    return value


def _open(source: str, source_id: int):
    return SubjectCertificate.objects.filter(
        source=source, source_id=source_id, revoked_at__isnull=True
    )


@transaction.atomic
def issue_subject_certificate(  # noqa: PLR0913 -- keyword-only; one certificate's columns
    *, student_user_id, subject_en, subject_ar, count, source, source_id, by=None
) -> CertificateRef:
    if not isinstance(source, str) or not source:
        raise ValidationError("A source is required.", field="source")
    student = _student(student_user_id)
    fields = {
        "student": student,
        "subject_en": _subject(subject_en, "subject_en"),
        "subject_ar": _subject(subject_ar, "subject_ar"),
        "count": _count(count),
        "source": source,
        "source_id": source_id,
        "issued_on": academy_today(),
        "issued_by": by,
    }
    existing = _open(source, source_id).first()
    if existing is not None:
        return _ref(existing)
    try:
        with transaction.atomic():
            row = SubjectCertificate.objects.create(**fields)
    except IntegrityError:
        # Lost a race to another issue for the same source: return theirs.
        return _ref(_open(source, source_id).get())
    return _ref(row)


@transaction.atomic
def revoke_by_source(source: str, source_id: int, *, reason: str, by) -> None:
    row = _open(source, source_id).select_for_update().first()
    if row is None:
        return
    row.revoked_at = timezone.now()
    row.revoke_reason = (reason or "").strip()[:500]
    row.save(update_fields=["revoked_at", "revoke_reason"])


def certificate_by_source(source: str, source_id: int) -> CertificateRef | None:
    row = (
        SubjectCertificate.objects.filter(source=source, source_id=source_id)
        .order_by("-created_at", "-id")
        .first()
    )
    return None if row is None else _ref(row)


def subject_certificates_queryset(user):
    qs = SubjectCertificate.objects.select_related("student__user")
    role = role_of(user)
    if is_office(user):
        return qs
    if role == "student":
        return qs.filter(student__user_id=user.pk, revoked_at__isnull=True)
    if role == "parent":
        return qs.filter(
            student__in=identity_services.get_children(user.pk), revoked_at__isnull=True
        )
    return qs.none()


def get_subject_certificate(user, pk) -> SubjectCertificate:
    row = subject_certificates_queryset(user).filter(pk=pk).first()
    if row is None:
        raise NotFoundError("Certificate", pk)
    return row
```

  Export `CertificateRef`, `issue_subject_certificate`, `revoke_by_source`, `certificate_by_source`, `get_subject_certificate` and `subject_certificates_queryset` from `services/__init__.py`, adding them to the imports and `__all__`.

- [ ] **Step 6: Run.** `B pytest etqan/learning -q`. Expected: PASS, with every B6 test unchanged.

- [ ] **Step 7: Commit.**

```bash
B ruff format etqan/learning && B ruff check etqan/learning
git -C backend add etqan/learning/models.py etqan/learning/migrations/0005_subject_certificates.py etqan/learning/services/subject_certificates.py etqan/learning/services/__init__.py etqan/learning/tests/test_subject_certificates.py
git -C backend commit -m "feat(learning): B7g R8 subject certificates" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: R8 — `verify()` fallback and the read route (learning), then release the claim

**Files:**
- Modify: `backend/etqan/learning/services/certificates.py` (`verify`)
- Modify: `backend/etqan/learning/api/serializers.py`, `api/certificate_views.py`, `api/urls.py`
- Modify: `backend/etqan/access/tests/test_routes.py` (B7 block)
- Test: `backend/etqan/learning/tests/test_subject_certificates.py` (extend)

**Interfaces:**
- Produces:
  - `GET /api/v1/learning/subject-certificates/<int:pk>/` (feature `certificates`, office `certificate.view`, or the student and their parents). It answers `{id, student{id, full_name}, subject{name_en, name_ar}, kind: "completion", count, count_label, issued_on, code, verify_url, revoked_at}`.
  - `verify(code)` returns `VerifyResult` for either table.

- [ ] **Step 1: Write the failing tests** (append):

```python
from rest_framework.test import APIClient


def test_verify_falls_back_to_subject_certificates(world):
    ref = issue(world)
    result = services.verify(ref.code)
    assert result.status == "valid" and result.kind == "completion"
    assert (result.course_name_en, result.course_name_ar) == ("Tajweed basics", "أساسيات التجويد")
    assert result.student_name == world.student.full_name
    services.revoke_by_source(SRC, 11, reason="x", by=None)
    revoked = services.verify(ref.code)
    assert revoked.status == "revoked" and revoked.student_name is None


def test_verify_route_answers_subject_certificates(world, set_features):
    set_features(certificates=True, verified_certificates=True)
    ref = issue(world)
    resp = APIClient().get(f"/api/v1/learning/certificates/verify/{ref.code}/")
    assert resp.status_code == 200 and resp.data["course_name_en"] == "Tajweed basics"
    assert set(resp.data) == {
        "status", "kind", "course_name_en", "course_name_ar", "issued_on",
        "academy_name", "student_name",
    }


def test_subject_certificate_route(world, set_features, api_for, other_student):
    set_features(certificates=True)
    ref = issue(world)
    url = f"/api/v1/learning/subject-certificates/{ref.id}/"
    data = api_for("admin").get(url).data
    assert data["subject"] == {"name_en": "Tajweed basics", "name_ar": "أساسيات التجويد"}
    assert (data["count"], data["count_label"], data["kind"]) == (5, "lessons", "completion")
    student = APIClient()
    student.force_login(world.student)
    assert student.get(url).status_code == 200
    stranger = APIClient()
    stranger.force_login(other_student)
    assert stranger.get(url).status_code == 404
    set_features(certificates=False)
    assert api_for("admin").get(url).status_code == 404


def test_b6_lists_never_show_subject_certificates(world, set_features, api_for):
    set_features(certificates=True)
    issue(world)
    assert api_for("admin").get("/api/v1/learning/certificates/").data["count"] == 0
```

- [ ] **Step 2: Run them to verify they fail.** Run: `B pytest etqan/learning/tests/test_subject_certificates.py -q`. Expected: FAIL (verify returns None; the route is a 404).

- [ ] **Step 3: Implement.**
  - `certificates.verify`: after `if cert is None:`, fall back:

```python
    if cert is None:
        subject = (
            SubjectCertificate.objects.select_related("student__user")
            .filter(code=code or "")
            .first()
        )
        if subject is None:
            return None
        valid = subject.revoked_at is None
        return VerifyResult(
            status="valid" if valid else "revoked",
            kind=Certificate.Kind.COMPLETION,
            course_name_en=subject.subject_en,
            course_name_ar=subject.subject_ar,
            issued_on=subject.issued_on,
            academy_name=_academy_name(),
            student_name=subject.student.user.full_name if valid else None,
        )
```

    Add `from etqan.learning.models import SubjectCertificate` to the imports.
  - `serializers.py`:

```python
def subject_certificate_data(row, *, verify_url: str | None) -> dict:
    """B7g R8: the print page's data, shaped like a certificate's."""
    return {
        "id": row.pk,
        "student": person_ref(row.student.user),
        "subject": {"name_en": row.subject_en, "name_ar": row.subject_ar},
        "kind": "completion",
        "count": row.count,
        "count_label": row.count_label,
        "issued_on": row.issued_on,
        "code": row.code,
        "verify_url": verify_url,
        "revoked_at": row.revoked_at,
    }
```

  - `certificate_views.py`:

```python
class SubjectCertificateView(APIView):
    """B7g R8: one subject certificate for its print page; scoped as
    certificates (office by code, the student, their parents)."""

    feature = FEATURE
    permission_classes = READERS
    permission_codes = {"GET": "certificate.view"}

    def get(self, request, pk):
        try:
            row = services.get_subject_certificate(request.user, pk)
        except NotFoundError:
            raise Http404 from None
        verify_url = (
            app_url(f"/verify/{row.code}")
            if features.enabled("verified_certificates")
            else None
        )
        return Response(s.subject_certificate_data(row, verify_url=verify_url))
```

  - `urls.py`: add `path("subject-certificates/<int:pk>/", cert.SubjectCertificateView.as_view()),` after the certificates routes.
  - `access/tests/test_routes.py`: in each route table (ROUTES, FEATURES, and SELF_SERVICE where student and parent readers are listed), add under the B7 block: `("GET", "/api/v1/learning/subject-certificates/{N}/", "certificate.view")`, the feature pair `certificates`, and the SELF_SERVICE entry `"etqan.learning.api.certificate_views.SubjectCertificateView": "a student's or parent's own subject certificate; scoped in the service"`. Copy the exact tuple shapes from the B7a block.

- [ ] **Step 4: Run.** `B pytest etqan/learning etqan/access -q && B lint-imports`. Expected: PASS.

- [ ] **Step 5: Commit, release, ask for review.**

```bash
B ruff format etqan/learning && B ruff check etqan/learning
git -C backend add etqan/learning etqan/access/tests/test_routes.py
git -C backend commit -m "feat(learning): B7g R8 verify fallback and subject certificate route" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 etqan.learning
```

  The controller then sends the conductor, who owns learning since B6 merged, the commit range of Tasks 4–5 for review (D58: "ping me to review the learning diff").

---

### Task 6: B7 — the completion trigger in the watched writers (recorded)

**Files:**
- Create: `backend/etqan/recorded/services/certificates.py`
- Modify: `backend/etqan/recorded/services/watching.py` (`set_watched`), `services/enrolments.py` (`update_enrolment`), `services/__init__.py`
- Modify: `backend/pyproject.toml` (recorded contract: `learning.services` ignore)
- Test: `backend/etqan/recorded/tests/test_certificates.py`

**Interfaces:**
- Consumes: Task 4's `issue_subject_certificate` and `certificate_by_source`; B7a's `is_complete` and `progress`.
- Produces:
  - `SOURCE = "recorded.enrolment"`.
  - `issue_if_complete(row: Enrolment) -> None`, called with the enrolment row already locked.
  - `certificate_of(enrolment) -> CertificateRef | None`.

- [ ] **Step 1: Write the failing tests.** `backend/etqan/recorded/tests/test_certificates.py`:

```python
import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from etqan.learning import services as learning_services
from etqan.recorded import services
from etqan.recorded.tests.conftest import png

pytestmark = pytest.mark.django_db


@pytest.fixture
def course(people, set_features, api_for):
    set_features(recorded_courses=True, certificates=True)
    admin = api_for("admin").user
    pl = services.create_playlist(
        thumbnail=png(), title="Tajweed basics", slug="tajweed-basics",
        description="d", code="TJ1", content_language="ar", price_minor=0,
        terms="t", is_published=True, certificate=True, by=admin,
    )
    a = services.create_video(pl, code="A", title="a", slug="a", kind="link",
                              url="https://youtu.be/aaaaaaaaaaa", duration_seconds=60, status="published")
    b = services.create_video(pl, code="B", title="b", slug="b", kind="link",
                              url="https://youtu.be/bbbbbbbbbbb", duration_seconds=60, status="published")
    e = services.enrol_by_office(playlist=pl, student_user_id=people.student.pk,
                                 method="free", amount_minor=0, by=admin)
    return pl, a, b, e


def test_watching_the_last_lesson_issues_once(course, people):
    pl, a, b, e = course
    services.set_watched(e, a, watched=True)
    assert services.certificate_of(e) is None
    services.set_watched(e, b, watched=True)
    ref = services.certificate_of(e)
    assert ref is not None and not ref.revoked
    services.set_watched(e, b, watched=True)  # idempotent
    services.set_watched(e, b, watched=False)  # unwatching keeps it (G-1)
    assert services.certificate_of(e) == ref
    assert learning_services.verify(ref.code).course_name_en == "Tajweed basics"


def test_office_watched_set_also_issues(course):
    pl, a, b, e = course
    services.update_enrolment(e, watched_video_ids=[a.pk, b.pk])
    assert services.certificate_of(e) is not None


@pytest.mark.parametrize("why", ["no_flag", "switch_off", "revoked"])
def test_no_certificate_when(course, set_features, api_for, why):
    pl, a, b, e = course
    admin = api_for("admin").user
    if why == "no_flag":
        services.update_playlist(pl, certificate=False)
    elif why == "switch_off":
        set_features(certificates=False)
    services.set_watched(e, a, watched=True)
    if why == "revoked":
        services.revoke(e, by=admin)
        services.update_enrolment(e, watched_video_ids=[a.pk, b.pk])
    else:
        services.set_watched(e, b, watched=True)
    assert services.certificate_of(e) is None


def test_parallel_completion_issues_once(course):
    """Review Focus 1: the writers lock the enrolment row before counting,
    so the issue runs after the lock (captured SQL), and the open-per-source
    unique index makes a second issue return the first."""
    pl, a, b, e = course
    services.set_watched(e, a, watched=True)
    with CaptureQueriesContext(connection) as ctx:
        services.set_watched(e, b, watched=True)
    sql = [q["sql"] for q in ctx.captured_queries]
    lock = next(i for i, s in enumerate(sql) if "FOR UPDATE" in s and "recorded_enrolment" in s)
    insert = next(i for i, s in enumerate(sql) if "INSERT INTO" in s and "subjectcertificate" in s)
    assert lock < insert
    from etqan.recorded.services.certificates import issue_if_complete  # noqa: PLC0415

    issue_if_complete(e)  # a second, racing issue: no second row
    from etqan.learning.models import SubjectCertificate  # noqa: PLC0415

    assert SubjectCertificate.objects.count() == 1
```

  The import of `etqan.learning.models` in a test is allowed by `etqan.recorded.tests.** -> etqan.**`. Use the real B7a service keyword names for `create_playlist`, `create_video` and `enrol_by_office`; read `etqan/recorded/services/__init__.py` first.

- [ ] **Step 2: Run them to verify they fail.** Run: `B pytest etqan/recorded/tests/test_certificates.py -q`. Expected: FAIL with `AttributeError: certificate_of`.

- [ ] **Step 3: Implement.** `backend/etqan/recorded/services/certificates.py`:

```python
"""Spec B7g G-1..G-4: recorded-course certificates are learning's subject
certificates (ledger D58); this module decides when, never stores a copy."""

from etqan.learning import services as learning_services
from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.recorded.models import Enrolment
from etqan.recorded.services.watching import is_complete
from etqan.recorded.services.watching import progress

SOURCE = "recorded.enrolment"
SWITCH = "certificates"
REVOKE_REASON = "Revoked from the recorded course enrolment"


def certificate_of(enrolment):
    return learning_services.certificate_by_source(SOURCE, enrolment.pk)


def _issue(row: Enrolment, *, by=None):
    playlist = row.playlist
    return learning_services.issue_subject_certificate(
        student_user_id=row.student.user_id,
        subject_en=playlist.title,
        subject_ar=playlist.title,  # A-3: one title, in its content language
        count=progress(row).total,
        source=SOURCE,
        source_id=row.pk,
        by=by,
    )


def issue_if_complete(row: Enrolment) -> None:
    """G-1. Call with ``row`` locked (the watched writers hold it)."""
    if (
        row.status != Enrolment.Status.ACTIVE
        or not row.playlist.certificate
        or not features.enabled(SWITCH)
        or not is_complete(row)
    ):
        return
    _issue(row)


def refuse_while_off() -> None:
    if not features.enabled(SWITCH):
        raise ConflictError(
            "Certificates are switched off.", code="recorded.certificates_off"
        )
```

  - `watching.set_watched`: after the get_or_create and delete branch, add `if watched: issue_if_complete(row)`. Import it lazily inside the function to avoid a circular import: `from etqan.recorded.services.certificates import issue_if_complete  # noqa: PLC0415`. Alternatively move `issue_if_complete` into a module both can import without a cycle; prefer the lazy import with a one-line comment.
  - `enrolments.update_enrolment`: after the watched-set rewrite (still under `row = _locked(...)`), call `issue_if_complete(row)` with the same lazy import.
  - Export `certificate_of`, `issue_if_complete` and `SOURCE` from `services/__init__.py`.
  - In the `pyproject.toml` recorded contract, add `"etqan.recorded.** -> etqan.learning.services"` to `ignore_imports`.

- [ ] **Step 4: Run.** `B pytest etqan/recorded -q && B lint-imports`. Expected: PASS, with every B7a test unchanged.

- [ ] **Step 5: Commit.**

```bash
B ruff format etqan/recorded && B ruff check etqan/recorded
git -C backend add etqan/recorded/services etqan/recorded/tests/test_certificates.py pyproject.toml
git -C backend commit -m "feat(recorded): B7g certificate on completion" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: B7 — the office tick, and certificate state in the payloads (recorded API)

**Files:**
- Modify: `backend/etqan/recorded/services/certificates.py` (`set_certificate`), `services/__init__.py`
- Modify: `backend/etqan/recorded/api/serializers.py` (`EnrolmentPatch`, `enrolment_data`), `api/views.py` (`EnrolmentDetailView.patch`, `_enrolment_json`), `api/my_views.py` (`MyCourseView`)
- Test: `backend/etqan/recorded/tests/test_certificates.py` (extend)

**Interfaces:**
- Produces:
  - `set_certificate(enrolment, *, obtained: bool, by) -> None`.
  - `PATCH recorded/enrolments/<id>/` accepts `certificate_obtained: bool`.
  - The enrolment payload gains `certificate: {id, code, issued_on, revoked} | null`.
  - `my/<playlist id>/` gains `certificate: {id} | null`, unrevoked only.

- [ ] **Step 1: Write the failing tests** (append):

```python
def test_office_tick_and_untick(course, api_for):
    """Review Focus 5."""
    pl, a, b, e = course
    admin = api_for("admin").user
    services.set_certificate(e, obtained=True, by=admin)  # not complete: still issued (G-2)
    first = services.certificate_of(e)
    services.set_certificate(e, obtained=False, by=admin)
    revoked = services.certificate_of(e)
    assert revoked.revoked and revoked.code == first.code
    from etqan.learning.models import SubjectCertificate  # noqa: PLC0415

    assert SubjectCertificate.objects.get(code=first.code).revoke_reason == (
        "Revoked from the recorded course enrolment"
    )
    services.set_certificate(e, obtained=True, by=admin)
    again = services.certificate_of(e)
    assert not again.revoked and again.code != first.code


def test_tick_refused_while_certificates_off(course, set_features, api_for):
    from etqan.platform.exceptions import ConflictError  # noqa: PLC0415

    pl, a, b, e = course
    set_features(certificates=False)
    with pytest.raises(ConflictError) as exc:
        services.set_certificate(e, obtained=True, by=api_for("admin").user)
    assert exc.value.code == "recorded.certificates_off"


def test_api_tick_and_payloads(course, api_for, people):
    from etqan.recorded.tests.conftest import as_user  # noqa: PLC0415

    pl, a, b, e = course
    admin = api_for("admin")
    url = f"/api/v1/recorded/enrolments/{e.pk}/"
    assert admin.get(url).data["certificate"] is None
    resp = admin.patch(url, {"certificate_obtained": True}, format="json")
    assert resp.status_code == 200 and resp.data["certificate"]["revoked"] is False
    my = as_user(people.student).get(f"/api/v1/recorded/my/{pl.pk}/").data
    assert my["certificate"] == {"id": resp.data["certificate"]["id"]}
    admin.patch(url, {"certificate_obtained": False}, format="json")
    assert as_user(people.student).get(f"/api/v1/recorded/my/{pl.pk}/").data["certificate"] is None
```

- [ ] **Step 2: Run them to verify they fail.** Run: `B pytest etqan/recorded/tests/test_certificates.py -q`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - In `certificates.py`:

```python
def set_certificate(enrolment, *, obtained: bool, by) -> None:
    """G-2: the office's tick; untick revokes with the fixed reason."""
    refuse_while_off()
    if obtained:
        current = certificate_of(enrolment)
        if current is None or current.revoked:
            row = Enrolment.objects.select_related("playlist", "student__user").get(
                pk=enrolment.pk
            )
            _issue(row, by=by)
    else:
        learning_services.revoke_by_source(
            SOURCE, enrolment.pk, reason=REVOKE_REASON, by=by
        )
```

    Wrap it in `@transaction.atomic` and take the enrolment lock first, `Enrolment.objects.select_for_update().get(pk=enrolment.pk)`, keeping the same order as the watched writers. Export it.
  - `serializers.EnrolmentPatch`: add `certificate_obtained = serializers.BooleanField(required=False)`.
  - `enrolment_data(e, total, certificate=None)`: add `"certificate": None if certificate is None else {"id": certificate.id, "code": certificate.code, "issued_on": certificate.issued_on, "revoked": certificate.revoked}`. In `views._enrolment_json`, pass `certificate=services.certificate_of(row)`. In the list view, pass `None` to keep it to one query per page. The office reads a row's certificate on its detail.
  - `EnrolmentDetailView.patch`: pop `certificate_obtained` from the validated data. When it is present, call `services.set_certificate(_enrolment(pk), obtained=value, by=request.user)` before `update_enrolment` with the rest.
  - `MyCourseView`: add `"certificate": ({"id": c.id} if (c := services.certificate_of(e)) and not c.revoked else None)`.

- [ ] **Step 4: Run.** `B pytest etqan/recorded etqan/access -q`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
B ruff format etqan/recorded && B ruff check etqan/recorded
git -C backend add etqan/recorded
git -C backend commit -m "feat(recorded): B7g certificate tick and payloads" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: B7 — the playlist redeemer and the delete guard (recorded)

**Files:**
- Create: `backend/etqan/recorded/services/codes.py`
- Modify: `backend/etqan/recorded/apps.py`, `services/playlists.py` (`delete_playlist`), `services/__init__.py`
- Modify: `backend/pyproject.toml` (recorded contract: `vouchers.services` ignore, if moved from Task 3)
- Test: `backend/etqan/recorded/tests/test_codes.py`

**Interfaces:**
- Consumes: Tasks 1–3 (`vouchers.services.register_redeemer`, `batches_exist`, `redeem`, `generate`) and B7a's `enrol_from_sale`.
- Produces: the registered `playlist` kind (`office_code="rc_enrolment.create"`, `feature="recorded_courses"`).

- [ ] **Step 1: Write the failing tests.** `backend/etqan/recorded/tests/test_codes.py`:

```python
import pytest

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.recorded import services
from etqan.recorded.models import Enrolment
from etqan.recorded.tests.conftest import png
from etqan.vouchers import services as vouchers

pytestmark = pytest.mark.django_db


@pytest.fixture
def playlist(people, set_features, api_for):
    set_features(recorded_courses=True, system_codes=True)
    return services.create_playlist(
        thumbnail=png(), title="Tajweed", slug="tajweed", description="d", code="TJ2",
        content_language="ar", price_minor=2000, currency="USD", terms="t",
        is_published=True, by=api_for("admin").user,
    )


def _code(playlist, api_for):
    batch = vouchers.generate(kind="playlist", quantity=1, valid_days=30,
                              target_id=playlist.pk, by=api_for("admin").user)
    return batch.codes.get()


def test_a_code_enrols_the_student(playlist, api_for, people):
    code = _code(playlist, api_for)
    result = vouchers.redeem(code=code.code, user=people.student, student_user_id=people.student.pk)
    e = Enrolment.objects.get(pk=result.target_ref_id)
    assert (e.method, e.amount_minor, e.payment_id) == ("code", 0, None)
    assert e.transaction_number == vouchers.display(code.code)
    assert e.currency == "USD" and e.student.user_id == people.student.pk


def test_unpublished_playlist_refuses_and_keeps_the_code(playlist, api_for, people):
    code = _code(playlist, api_for)
    services.update_playlist(playlist, is_published=False)
    with pytest.raises(ConflictError) as exc:
        vouchers.redeem(code=code.code, user=people.student, student_user_id=people.student.pk)
    assert exc.value.code == "recorded.not_for_sale"
    code.refresh_from_db()
    assert code.status == "unused"


def test_already_enrolled_refuses_and_keeps_the_code(playlist, api_for, people):
    services.enrol_by_office(playlist=playlist, student_user_id=people.student.pk,
                             method="free", amount_minor=0, by=api_for("admin").user)
    code = _code(playlist, api_for)
    with pytest.raises(ConflictError) as exc:
        vouchers.redeem(code=code.code, user=people.student, student_user_id=people.student.pk)
    assert exc.value.code == "recorded.already_enrolled"
    code.refresh_from_db()
    assert code.status == "unused"


def test_generate_checks_the_playlist(people, set_features, api_for):
    set_features(recorded_courses=True, system_codes=True)
    with pytest.raises(ValidationError) as exc:
        vouchers.generate(kind="playlist", quantity=1, valid_days=30, target_id=999999,
                          by=api_for("admin").user)
    assert exc.value.field == "target"


def test_playlist_with_codes_cannot_be_deleted(playlist, api_for):
    _code(playlist, api_for)
    with pytest.raises(ConflictError) as exc:
        services.delete_playlist(playlist)
    assert exc.value.code == "recorded.playlist_in_use"


def test_target_named_in_code_lists(playlist, api_for):
    _code(playlist, api_for)
    row = api_for("admin").get("/api/v1/vouchers/codes/").data["results"][0]
    assert row["target"] == {"id": playlist.pk, "name_en": "Tajweed", "name_ar": "Tajweed"}
```

- [ ] **Step 2: Run them to verify they fail.** Run: `B pytest etqan/recorded/tests/test_codes.py -q`. Expected: FAIL (the kind is not available because no redeemer is registered).

- [ ] **Step 3: Implement.** `backend/etqan/recorded/services/codes.py`:

```python
"""Spec B7g G-5..G-7: the `playlist` voucher kind (ledger D56). Registered
in RecordedConfig.ready(); vouchers calls these hooks inside its locked
redemption (Voucher -> Playlist -> Enrolment)."""

from etqan.platform.exceptions import ConflictError
from etqan.platform.exceptions import ValidationError
from etqan.recorded.models import Playlist
from etqan.recorded.services.enrolments import enrol_from_sale


def describe(target_id: int) -> tuple[str, str]:
    row = Playlist.objects.filter(pk=target_id).only("title").first()
    title = row.title if row else ""
    return title, title


def check(target_id: int) -> None:
    if not Playlist.objects.filter(pk=target_id).exists():
        raise ValidationError("Choose a recorded course.", field="target")


def redeem(*, target_id, student_user_id, code_display, by) -> tuple[int, int]:
    playlist = Playlist.objects.select_for_update().filter(pk=target_id).first()
    if playlist is None or not playlist.is_published:
        raise ConflictError(
            "This course is not available.", code="recorded.not_for_sale"
        )
    enrolment = enrol_from_sale(
        playlist=playlist,
        student_user_id=student_user_id,
        method="code",
        amount_minor=0,
        currency=playlist.currency,
        transaction_number=code_display,
        payment_id=None,
        by=by,
    )
    return enrolment.student_id, enrolment.pk


def register() -> None:
    from etqan.vouchers import services as vouchers  # noqa: PLC0415

    vouchers.register_redeemer(
        "playlist",
        describe=describe,
        check=check,
        redeem=redeem,
        office_code="rc_enrolment.create",
        feature="recorded_courses",
    )
```

  - `apps.py` `ready()`: add `from etqan.recorded.services import codes  # noqa: PLC0415` and `codes.register()`.
  - `playlists.delete_playlist`: after the enrolments check, add:

```python
    from etqan.vouchers import services as vouchers  # noqa: PLC0415

    if vouchers.batches_exist(kind="playlist", target_id=row.pk):
        raise ConflictError(
            "Codes were made for this course: unpublish it instead.",
            code="recorded.playlist_in_use",
        )
```

    Prefer a top-level import if no cycle appears, since vouchers imports nothing of recorded.
  - Confirm that the recorded contract's `etqan.recorded.** -> etqan.vouchers.services` ignore and the vouchers contract's matching ignore are now matched.

- [ ] **Step 4: Run.** `B pytest etqan/recorded etqan/vouchers -q && B lint-imports`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
B ruff format etqan/recorded && B ruff check etqan/recorded
git -C backend add etqan/recorded pyproject.toml
git -C backend commit -m "feat(recorded): B7g playlist activation codes" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Dashboard — the subject certificate print page (certificates feature, under claim)

**Files:**
- Modify: `dashboard/src/features/certificates/CertificatePrint.tsx` (extract `CertificateSheet`; keep `CertificatePrint` behaviour identical)
- Create: `dashboard/src/features/certificates/SubjectCertificatePrint.tsx` (+ test)
- Modify: `dashboard/src/features/certificates/api.ts`, `queries.ts`, `schemas.ts`, `index.ts`
- Create: `dashboard/src/routes/_print/subject-certificates.$certificateId.print.tsx`
- Modify: `dashboard/src/locales/{en,ar}/certificates.json` (`print.lessons`)

**Interfaces:**
- Produces:
  - `SubjectCertificate` type: `{ id, student: PersonRef, subject: { name_en, name_ar }, kind: "completion", count, count_label: "lessons", issued_on, code, verify_url, revoked_at }`.
  - `certificatesApi.getSubject(id)` and `useSubjectCertificate(id)`.
  - `SubjectCertificatePrint({ certificateId })`.
  - Route `/subject-certificates/$certificateId/print`.

- [ ] **Step 1: Claim.** `python3 scripts/orchestration/ledger.py claim B7 dashboard/src/features/certificates --reason "R8 print page (D58)"`

- [ ] **Step 2: Write the failing test.** `SubjectCertificatePrint.test.tsx`:

```tsx
import { screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { renderWithRouter } from "@/test/render";
import { certificatesApi } from "./api";
import { SubjectCertificatePrint } from "./SubjectCertificatePrint";

vi.mock("./api", async (orig) => ({ ...(await orig()), certificatesApi: { getSubject: vi.fn() } }));

const subject = {
	id: 4,
	student: { id: 9, full_name: "Yusuf Omar" },
	subject: { name_en: "Tajweed basics", name_ar: "أساسيات التجويد" },
	kind: "completion" as const,
	count: 5,
	count_label: "lessons" as const,
	issued_on: "2026-06-01",
	code: "abc",
	verify_url: "http://demo.etqan.localhost/app/verify/abc",
	revoked_at: null,
};

describe("SubjectCertificatePrint", () => {
	it("prints the subject, the student and the lesson count", async () => {
		vi.mocked(certificatesApi.getSubject).mockResolvedValue(subject);
		renderWithRouter(<SubjectCertificatePrint certificateId="4" />);
		expect(await screen.findByText("Yusuf Omar")).toBeInTheDocument();
		expect(screen.getByText("Tajweed basics")).toBeInTheDocument();
		expect(screen.getByText(/5 lessons/)).toBeInTheDocument();
		expect(screen.getByText(/verify\/abc/)).toBeInTheDocument();
	});

	it("says not found for a bad id without a request", async () => {
		renderWithRouter(<SubjectCertificatePrint certificateId="x" />);
		expect(await screen.findByRole("alert")).toBeInTheDocument();
		expect(certificatesApi.getSubject).not.toHaveBeenCalled();
	});
});
```

  Copy the mock style of `CertificatePrint.test.tsx`. If it mocks the api module differently, follow it.

- [ ] **Step 3: Run it to verify it fails.** `F pnpm vitest run src/features/certificates/SubjectCertificatePrint.test.tsx`. Expected: FAIL (module missing).

- [ ] **Step 4: Implement.**
  - Extract the `Sheet` body of `CertificatePrint.tsx` into an exported `CertificateSheet` that takes plain props: `{ titleKey, studentName, subjectLabel, countText, message, issuedOn, verifyUrl, revokedAt, backgroundUrl, photoUrl, photoAlt }`.
    - `CertificatePrint`'s `Sheet` keeps fetching its blobs and passes the same values it renders today, so every existing `CertificatePrint` test passes unchanged.
    - `countText` for a course is `t("certificates.print.sessions", {count})`, as today.
  - `SubjectCertificatePrint.tsx` mirrors `CertificatePrint`: id parse, `useSubjectCertificate`, not-found/error/spinner, `PrintPage wide` and the landscape style. It renders `CertificateSheet` with:
    - `titleKey="certificates.kindTitle.completion"`;
    - `subjectLabel={localName(cert.subject, i18n.language)}`;
    - `countText={t("certificates.print.lessons", {count: cert.count})}`;
    - no background, no photo, no message.
  - `api.ts`: `getSubject: async (id: number) => (await api.get<SubjectCertificate>(\`${L}subject-certificates/${id}/\`)).data`.
  - `queries.ts`: `useSubjectCertificate(id)`, shaped like `useCertificate`, with query key `[...certificatesKey, "subject", id]`.
  - `schemas.ts`: the `SubjectCertificate` interface above. `index.ts` exports `SubjectCertificatePrint`.
  - Route file, mirroring `certificates.$certificateId.print.tsx`:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { SubjectCertificatePrint } from "@/features/certificates";

export const Route = createFileRoute(
	"/_print/subject-certificates/$certificateId/print",
)({
	component: function SubjectCertificatePrintRoute() {
		const { t } = useTranslation();
		const { certificateId } = Route.useParams();
		usePageTitle(t("certificates.title"));
		return <SubjectCertificatePrint certificateId={certificateId} />;
	},
});
```

  - Locales: add `"lessons_one": "{{count}} lesson completed"` and `"lessons_other": "{{count}} lessons completed"` under `certificates.print` in en. Use the same plural form as the existing `sessions` key. Add the ar equivalents using the same plural keys as ar's `sessions`.
  - Regenerate the route tree: `F pnpm vite build`.

- [ ] **Step 5: Run.** `F pnpm vitest run src/features/certificates && F pnpm tsc --noEmit && F pnpm lint`. Expected: PASS.

- [ ] **Step 6: Commit and release.**

```bash
git -C dashboard add src/features/certificates src/routes/_print/subject-certificates.\$certificateId.print.tsx src/routeTree.gen.ts src/locales/en/certificates.json src/locales/ar/certificates.json
git -C dashboard commit -m "feat(certificates): B7g R8 subject certificate print page" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 dashboard/src/features/certificates
```

---

### Task 10: Dashboard — the enrolment tick and the student's certificate link (recorded)

**Files:**
- Modify: `dashboard/src/features/recorded/schemas.ts` (`Enrolment.certificate`, `MyPlaylist.certificate`), `api.ts` (`EnrolmentPatch.certificate_obtained`)
- Modify: `dashboard/src/features/recorded/EnrolmentDialog.tsx` (+ test), `CoursePlayer.tsx` (+ test)
- Modify: `dashboard/src/locales/{en,ar}/recorded.json`, `fixtures.ts`

**Interfaces:**
- Consumes: Task 7's payloads.

- [ ] **Step 1: Write the failing tests.**
  - `EnrolmentDialog.test.tsx`, for an existing enrolment of a playlist with `certificate: true`:
    - A "Certificate obtained" checkbox is shown; it is unchecked when `certificate` is null.
    - Ticking it and saving PATCHes `{ certificate_obtained: true }` together with the existing fields.
    - When `certificate` is `{id: 4, code: "abc", issued_on: "2026-06-01", revoked: false}`, the box is checked and a "Print certificate" link points to `/subject-certificates/4/print`.
    - It is hidden for a playlist with `certificate: false`.
    - A 409 `recorded.certificates_off` is shown as the form error.
  - `CoursePlayer.test.tsx`:
    - When `my` has `certificate: { id: 4 }`, a "Your certificate" link to `/subject-certificates/4/print` is shown.
    - None is shown when it is null.
    - The parent's read-only view shows it too, since parents may read the child's certificate.

  Write these with the same helpers and fixtures the files already use. Add `certificate: null` to the fixtures' enrolment and my-playlist objects.

- [ ] **Step 2: Run them to verify they fail.** `F pnpm vitest run src/features/recorded`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - Schemas: `Enrolment.certificate: { id: number; code: string; issued_on: string; revoked: boolean } | null` and `MyPlaylist.certificate: { id: number } | null`. `EnrolmentPatch.certificate_obtained?: boolean`.
  - `EnrolmentDialog`: the dialog already has the playlist (`playlist.certificate`). Add the checkbox in the edit section, state initialised from `enrolment.certificate && !enrolment.certificate.revoked`. Send `certificate_obtained` only when it changed. Map `recorded.certificates_off` through `recordedErrorText`, and add the error text to `recorded.json`. Render the print link with TanStack `Link` to `/subject-certificates/$certificateId/print`, opening in a new tab like other print links.
  - `CoursePlayer`: under the progress meter, `{course.certificate ? <a/Link to print>{t("recorded.my.certificate")}</…> : null}`.
  - Locales, en and ar: `recorded.enrolments.certificate` ("Certificate obtained"), `recorded.enrolments.printCertificate` ("Print certificate"), `recorded.my.certificate` ("Your certificate"), `recorded.errors.certificates_off` ("Certificates are switched off for this academy.").

- [ ] **Step 4: Run.** `F pnpm vitest run src/features/recorded src/features/locales && F pnpm tsc --noEmit && F pnpm lint`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git -C dashboard add src/features/recorded src/locales/en/recorded.json src/locales/ar/recorded.json
git -C dashboard commit -m "feat(recorded): B7g certificate tick and link" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Dashboard — the `playlist` code kind (vouchers feature, under claim)

**Files:**
- Modify: `dashboard/src/features/vouchers/schemas.ts`, `GenerateCodesDialog.tsx`, `RedeemCodePage.tsx`, `CodesPage.tsx`, `OfficeRedeemDialog.tsx` (+ tests)
- Modify: `dashboard/src/locales/{en,ar}/vouchers.json`

**Interfaces:**
- Consumes: Task 3's API. `usePlaylists` from `@/features/recorded` provides the target select.
- Produces:
  - `VOUCHER_KINDS` gains `"playlist"`.
  - `Terms.target: NamedRef | null`.
  - `GenerateBody.target?: number`.
  - `Redemption.target_ref_id: number | null`.

- [ ] **Step 1: Claim.** `python3 scripts/orchestration/ledger.py claim B7 dashboard/src/features/vouchers --reason "R9 playlist kind (D56)"`

- [ ] **Step 2: Write the failing tests.**
  - `GenerateCodesDialog.test.tsx`:
    - Choosing "Recorded course" hides course, package, teacher and discount, and shows a "Recorded course" select listing the playlists (mock `recordedApi.list`).
    - Submitting POSTs `{kind: "playlist", quantity, valid_days, target: <id>, note}`.
    - Submitting without a playlist shows the required error.
    - The option is absent while `recorded_courses` is off, using the `useHasFeature` pattern the dashboard already uses.
  - `RedeemCodePage.test.tsx`:
    - A check answering `kind: "playlist"`, `target: {id: 7, name_en: "Tajweed", name_ar: "تجويد"}` and one student shows the course name and the student choice.
    - Redeeming POSTs `{code, student}`.
    - Success says the student is enrolled and links to `/learning/recorded/$playlistId`, using `target.id`.
  - `CodesPage.test.tsx`: a playlist code row shows its target name in the course column.
  - `OfficeRedeemDialog.test.tsx`: a playlist code asks for a student, like activation.

- [ ] **Step 3: Run them to verify they fail.** `F pnpm vitest run src/features/vouchers`. Expected: FAIL.

- [ ] **Step 4: Implement.**
  - Schemas: add `"playlist"` to `VOUCHER_KINDS`; `target: NamedRef | null` in `Terms`; `target?: number` in `GenerateBody`; `target_ref_id: number | null` in `Redemption`.
  - `generateFormSchema` gains `target: z.string()`. In `superRefine`, for `v.kind === "playlist"` require `target` and skip the course and package requirement. Change the current `if (v.kind !== "discount")` to `if (v.kind === "activation" || v.kind === "renewal")`. `toGenerateBody` sends `target: Number(values.target)` only for playlist, and no course or package.
  - `GenerateCodesDialog`:
    - The kind `<option>`s come from `VOUCHER_KINDS`. Filter out `"playlist"` while `recorded_courses` is off.
    - For playlist, render a `Select` of `usePlaylists({})` results (title + code) instead of course, package and teacher.
  - `RedeemCodePage`: treat `preview.kind === "playlist"` like activation for the student choice. Show `localName(preview.target)`. On success, link to the course.
  - `OfficeRedeemDialog`: treat playlist like activation for the target input.
  - `CodesPage`: the course cell shows `row.course ?? row.target` names.
  - Locales, en and ar: `vouchers.kinds.playlist` ("Recorded course"), `vouchers.generate.target` ("Recorded course"), `vouchers.family.titles.playlist` ("Recorded course code"), `vouchers.family.enrolled` ("{{name}} is enrolled. Open the course."). Use the existing area structure.

- [ ] **Step 5: Run.** `F pnpm vitest run src/features/vouchers && F pnpm tsc --noEmit && F pnpm lint`. Expected: PASS, with existing vouchers tests unchanged.

- [ ] **Step 6: Commit and release.**

```bash
git -C dashboard add src/features/vouchers src/locales/en/vouchers.json src/locales/ar/vouchers.json
git -C dashboard commit -m "feat(vouchers): B7g R9 recorded course codes" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
python3 scripts/orchestration/ledger.py release B7 dashboard/src/features/vouchers
```

---

### Task 12: e2e journey

**Files:**
- Create: `dashboard/e2e/b7-recorded-certificates.spec.ts`

- [ ] **Step 1: Write the spec.** Follow `dashboard/e2e/b7-recorded.spec.ts`: its sign-in helpers, `manage("set_features")`, unique per-run names, and locale pinned with `context.addInitScript`. Two tests:

  1. **Certificate on completion.**
     - Switch on `recorded_courses`, `certificates` and `verified_certificates`.
     - The office creates a published playlist with "Accredited certificate" ticked and one published link video, then enrols a fresh student for free.
     - The student opens the course, marks the lesson watched, and sees the "Your certificate" link.
     - The link opens the print page, which shows the student's name and the course title.
     - An anonymous page at `/app/verify/<code>` shows "valid". Read the code from the print page's verify URL.
  2. **Activation code.**
     - Switch on `system_codes` and `recorded_courses`.
     - The office generates one "Recorded course" code for that playlist on `/app/billing/codes` and copies the code text from the codes table.
     - A second fresh student redeems it on `/app/learning/codes`, choosing themselves.
     - The student sees the course under "My recorded courses".

  Use visible labels and roles only; scope dialog labels to `page.getByRole("dialog")`. No `force` clicks. Wait for outcomes with `expect(...)`, not sleeps.

- [ ] **Step 2: Run it.** `set -a; . ./.env.stream; set +a; just e2e e2e/b7-recorded-certificates.spec.ts`. Expected: 2 passed. Run it twice to show it is idempotent.

- [ ] **Step 3: Commit.**

```bash
git -C dashboard add e2e/b7-recorded-certificates.spec.ts
git -C dashboard commit -m "test(recorded): B7g e2e certificates and codes" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Gates, final review and queue

- [ ] **Step 1:** `just migrate && just test && just lint`. Expected: PASS. Backend coverage must be ≥ 80 %, and import contracts all kept, including "vouchers never imports recorded".
- [ ] **Step 2:** `F pnpm test:coverage`. Expected: lines and statements ≥ 80, branches and functions ≥ 70.
- [ ] **Step 3:** `just e2e`, the whole suite. Expected: all pass.
- [ ] **Step 4:** A final whole-slice review by a fresh reviewer, covering backend, dashboard and the learning diff. The conductor reviews the learning diff (D58).
- [ ] **Step 5:** Confirm no claim is left open (`ledger.py show`, Claims table).
- [ ] **Step 6:** `python3 scripts/orchestration/ledger.py queue B7g`. When the slice is in flight, follow the orchestration loop: rebase, rerun the gates, open PRs, `slice B7g --prs`.
