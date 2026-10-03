# Plan 18 — B9a Platform (themes, file library, contracts, system status) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** none (B9 depends on B0 only; no other phase's slice).

**Goal:** Ship slice B9a: named themes, an academy file library, teacher employment contracts with private files, and a system-status page with a "reconcile subscriptions now" job — each behind its own feature switch, off by default.

**Architecture:** Three new tenant apps (`etqan.library`, `etqan.employment`, `etqan.systemstatus`) each with models → `services.py` → DRF views guarded by `[HasCode …, FeatureOn]`; a shared upload checker in `etqan.platform.uploads`; a `STORAGES["private"]` alias for contract files. Dashboard: one feature folder per area (`features/library`, `features/employment`, `features/systemstatus`, `features/appearance`), routes under `_authed/`, nav items under the B9 marker.

**Tech Stack:** Django 5 + DRF + django-tenants + Celery + Pillow (backend); React + TanStack Router/Query + zod + i18next + vitest + Playwright (dashboard).

**Spec:** `docs/superpowers/specs/2026-10-03-platform-extras-design.md` §4–§10 (decisions A-1…A-16). Read it before each task.

## Global Constraints

- Every new feature is off by default: `file_uploads`, `contracts` flipped in place to `Feature(..., built=True)` with `default=False`; `themes` and `system_status` new, under `# ── phase B9 ──`.
- Add lines to shared lists only under `── phase B9 ──` markers: `TENANT_APPS`, `config/api_router.py`, `features.py`, access `RESOURCES`, `seed_academy`, both `pyproject.toml` marker sections, dashboard `NAV_ITEMS`. `PAGES` in `access/registry.py` has no marker: flip `page.system_status` in place.
- Lists without markers that this plan must append to (`etqan/access/tests/test_routes.py` `ROUTES`, `FEATURES`, `FEATURE_WORDS`; dashboard `FeatureCode` union): append one clearly commented `# B9a` block at the end of each.
- All API routes under `/api/v1/`. Business logic in `<app>/services.py`. New apps import only `etqan.platform`, plus `etqan.identity.services` (employment) and `etqan.scheduling.services` (systemstatus). FKs to users use `settings.AUTH_USER_MODEL`.
- Stored instants are UTC. Migrate with `just migrate` (never plain `migrate`). Run backend tests with `just test-backend` or `just test-backend-host` from the worktree (the `.env.stream` points at this stream's DB).
- Library uploads ≤ 20 MiB (`20 * 1024 * 1024`); contract files ≤ 10 MiB. Accepted types exactly spec §5.1. SVG/HTML/legacy Office refused.
- New translation files only: `dashboard/src/locales/{en,ar}/{library,contracts,systemStatus,appearance}.json`, keys equal in en and ar.
- Coverage: backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- e2e spec file: `dashboard/e2e/b9-platform.spec.ts`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Backend and dashboard are separate git repos (submodules on `feat/b9a-platform`): commit inside each.

## Review Focus

1. **A teacher reaching another teacher's contract file** by guessing ids → 404, never the bytes (Task 4 test `test_teacher_cannot_download_another_teachers_file`).
2. **A file renamed to an allowed extension** (`evil.html` → `evil.pdf`, `<svg …>` as `.txt`) → 400 on `file` (Task 1 tests `test_html_renamed_pdf_refused`, `test_txt_starting_with_markup_refused`).
3. **Double-click on "Reconcile now"** (two POSTs racing) → one 202 and one 409, never two open runs (Task 5 `test_second_open_run_is_409_by_constraint`).
4. **A run whose worker died** stays `running` → after 1 h the next POST marks it failed and starts a new one (Task 5 `test_stale_open_run_is_failed_then_new_run_allowed`).
5. **Switching `themes` off while Dracula is stored** → Default light/dark as the user had it, stored `etqan-theme` untouched (Task 7 test `ignores a stored named theme while the switch is off`).

---

### Task 1: Shared upload checks and the private storage

**Files:**
- Create: `backend/etqan/platform/uploads.py`
- Create: `backend/etqan/platform/checks.py`
- Modify: `backend/etqan/platform/apps.py` (import checks in `ready()`)
- Modify: `backend/config/settings/base.py` (STORAGES `private`, `PRIVATE_MEDIA_ROOT`)
- Modify: `backend/config/settings/production.py` (private S3 storage)
- Modify: `backend/.gitignore` (`etqan/private_media/`)
- Test: `backend/etqan/platform/tests/test_uploads.py`, `backend/etqan/platform/tests/test_private_storage_check.py`

**Interfaces:**
- Produces:
  - `etqan.platform.uploads.IMAGE, PDF, OFFICE, TEXT, AUDIO, VIDEO` — `frozenset[str]` of extensions (`".png"`, …).
  - `etqan.platform.uploads.CheckedUpload` — frozen dataclass `(file: django.core.files.File, content_type: str, original_name: str)`.
  - `etqan.platform.uploads.check_upload(upload, *, extensions: frozenset[str], max_bytes: int, field: str = "file") -> CheckedUpload` — raises `etqan.platform.exceptions.ValidationError(message, field=field)`.
  - `etqan.platform.uploads.tenant_upload_path(folder: str) -> Callable[[Model, str], str]` → `tenants/<schema>/<folder>/<uuid32hex><ext>`; the function gets a stable `__name__`/`__qualname__` `f"{folder}_path"` (migrations serialise it).
  - `etqan.platform.uploads.LIBRARY_MAX = 20 * 1024 * 1024`, `CONTRACT_MAX = 10 * 1024 * 1024`.
  - `django.core.files.storage.storages["private"]`.

- [ ] **Step 1: Write the failing tests** — `test_uploads.py`:

```python
import io

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from PIL import Image

from etqan.platform import uploads
from etqan.platform.exceptions import ValidationError

ALL = uploads.IMAGE | uploads.PDF | uploads.OFFICE | uploads.TEXT | uploads.AUDIO | uploads.VIDEO


def _png(exif=False):
    buf = io.BytesIO()
    image = Image.new("RGB", (4, 4), "red")
    kwargs = {}
    if exif:
        e = Image.Exif()
        e[0x010F] = "SecretCamera"
        kwargs["exif"] = e.tobytes()
    image.save(buf, "PNG", **kwargs)
    return buf.getvalue()


def _up(name, data):
    return SimpleUploadedFile(name, data)


@pytest.mark.parametrize(
    ("name", "data", "content_type"),
    [
        ("a.pdf", b"%PDF-1.7\n...", "application/pdf"),
        ("a.gif", b"GIF89a" + b"\0" * 10, "image/gif"),
        ("a.docx", b"PK\x03\x04rest", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
        ("a.xlsx", b"PK\x03\x04rest", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
        ("a.pptx", b"PK\x03\x04rest", "application/vnd.openxmlformats-officedocument.presentationml.presentation"),
        ("a.txt", "سلام hello\n".encode(), "text/plain; charset=utf-8"),
        ("a.csv", b"a,b\n1,2\n", "text/csv; charset=utf-8"),
        ("a.mp3", b"ID3\x04" + b"\0" * 10, "audio/mpeg"),
        ("b.mp3", b"\xff\xfb\x90\x00" + b"\0" * 10, "audio/mpeg"),
        ("a.m4a", b"\0\0\0\x20ftypM4A " + b"\0" * 10, "audio/mp4"),
        ("a.mp4", b"\0\0\0\x20ftypisom" + b"\0" * 10, "video/mp4"),
        ("A.PDF", b"%PDF-1.4", "application/pdf"),
    ],
)
def test_each_accepted_type(name, data, content_type):
    checked = uploads.check_upload(_up(name, data), extensions=ALL, max_bytes=1 << 20)
    assert checked.content_type == content_type
    assert checked.original_name == name


def test_png_is_reencoded_without_metadata():
    checked = uploads.check_upload(_up("p.png", _png(exif=True)), extensions=ALL, max_bytes=1 << 20)
    assert checked.content_type == "image/png"
    data = checked.file.read()
    assert b"SecretCamera" not in data
    assert Image.open(io.BytesIO(data)).format == "PNG"


@pytest.mark.parametrize(
    ("name", "data"),
    [
        ("x.svg", b"<svg xmlns='http://www.w3.org/2000/svg'/>"),
        ("x.html", b"<html></html>"),
        ("x.doc", b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"),
        ("x.exe", b"MZ\x90\x00"),
        ("noext", b"%PDF-1.4"),
    ],
)
def test_unlisted_extensions_refused(name, data):
    with pytest.raises(ValidationError) as exc:
        uploads.check_upload(_up(name, data), extensions=ALL, max_bytes=1 << 20)
    assert exc.value.field == "file"


def test_html_renamed_pdf_refused():
    with pytest.raises(ValidationError):
        uploads.check_upload(_up("evil.pdf", b"<html><script>"), extensions=ALL, max_bytes=1 << 20)


def test_exe_renamed_png_refused():
    with pytest.raises(ValidationError):
        uploads.check_upload(_up("evil.png", b"MZ\x90\x00" * 10), extensions=ALL, max_bytes=1 << 20)


@pytest.mark.parametrize("data", [b"  <svg onload=x>", b"a\x00b", b"\xff\xfe\xfa"])
def test_txt_starting_with_markup_or_binary_refused(data):
    with pytest.raises(ValidationError):
        uploads.check_upload(_up("x.txt", data), extensions=ALL, max_bytes=1 << 20)


def test_txt_starting_with_markup_refused():
    with pytest.raises(ValidationError):
        uploads.check_upload(_up("x.csv", b"<script>"), extensions=ALL, max_bytes=1 << 20)


def test_extension_outside_the_allowed_set_refused():
    with pytest.raises(ValidationError):
        uploads.check_upload(_up("a.mp4", b"\0\0\0\x20ftypisom"), extensions=uploads.PDF, max_bytes=1 << 20)


def test_oversize_refused():
    with pytest.raises(ValidationError) as exc:
        uploads.check_upload(_up("a.pdf", b"%PDF-" + b"0" * 100), extensions=ALL, max_bytes=50)
    assert "MB" in exc.value.message or "KB" in exc.value.message


def test_tenant_upload_path(tenants):
    path = uploads.tenant_upload_path("library")(None, "My File.PDF")
    assert path.startswith("tenants/pytest_main/library/")
    assert path.endswith(".pdf")
    assert len(path.rsplit("/", 1)[1]) == 32 + 4
    assert uploads.tenant_upload_path("library").__name__ == "library_path"
```

`test_private_storage_check.py`:

```python
from django.core.files.storage import storages
from django.test import override_settings

from etqan.platform.checks import private_storage_check


def test_private_storage_is_not_under_media_root(settings):
    location = str(storages["private"].location)
    assert not location.startswith(str(settings.MEDIA_ROOT))


@override_settings(PRIVATE_STORAGE_SHARED_WITH_PUBLIC=True)
def test_warns_when_private_files_share_the_public_bucket():
    assert [w.id for w in private_storage_check(None)] == ["etqan.W901"]


def test_silent_by_default():
    assert private_storage_check(None) == []
```

- [ ] **Step 2: Run to verify failure**

Run: `just test-backend-host etqan/platform/tests/test_uploads.py etqan/platform/tests/test_private_storage_check.py`
Expected: FAIL — `ModuleNotFoundError: etqan.platform.uploads`.

- [ ] **Step 3: Implement `uploads.py`**

```python
"""Spec 2026-10-03 B9a §5.1: the uploads an academy may store, checked by
extension and by content. Shared (ledger D12): any app may use it."""

import io
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import PurePosixPath

from django.core.files.base import ContentFile
from django.core.files.base import File
from django.db import connection
from PIL import Image
from PIL import UnidentifiedImageError

from etqan.platform.exceptions import ValidationError

LIBRARY_MAX = 20 * 1024 * 1024
CONTRACT_MAX = 10 * 1024 * 1024
MAX_PIXELS = 16_000_000
_ZIP = b"PK\x03\x04"
_OOXML = "application/vnd.openxmlformats-officedocument."


def _starts(*prefixes: bytes):
    return lambda head: head.startswith(prefixes)


def _ftyp(head: bytes) -> bool:
    return head[4:8] == b"ftyp"


def _mp3(head: bytes) -> bool:
    return head.startswith(b"ID3") or (
        len(head) > 1 and head[0] == 0xFF and head[1] & 0xE0 == 0xE0
    )


def _text(data: bytes) -> bool:
    if b"\x00" in data:
        return False
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return not text.lstrip().startswith("<")


# extension → (content type, kind, check on the leading bytes | None: Pillow, "text": whole file)
_TYPES: dict[str, tuple[str, str, object]] = {
    ".png": ("image/png", "image", "PNG"),
    ".jpg": ("image/jpeg", "image", "JPEG"),
    ".jpeg": ("image/jpeg", "image", "JPEG"),
    ".webp": ("image/webp", "image", "WEBP"),
    ".gif": ("image/gif", "image", _starts(b"GIF87a", b"GIF89a")),
    ".pdf": ("application/pdf", "pdf", _starts(b"%PDF-")),
    ".docx": (_OOXML + "wordprocessingml.document", "office", _starts(_ZIP)),
    ".xlsx": (_OOXML + "spreadsheetml.sheet", "office", _starts(_ZIP)),
    ".pptx": (_OOXML + "presentationml.presentation", "office", _starts(_ZIP)),
    ".txt": ("text/plain; charset=utf-8", "text", "text"),
    ".csv": ("text/csv; charset=utf-8", "text", "text"),
    ".mp3": ("audio/mpeg", "audio", _mp3),
    ".m4a": ("audio/mp4", "audio", _ftyp),
    ".mp4": ("video/mp4", "video", _ftyp),
}


def _kind(kind: str) -> frozenset[str]:
    return frozenset(ext for ext, (_, k, _) in _TYPES.items() if k == kind)


IMAGE = _kind("image")
PDF = _kind("pdf")
OFFICE = _kind("office")
TEXT = _kind("text")
AUDIO = _kind("audio")
VIDEO = _kind("video")


@dataclass(frozen=True)
class CheckedUpload:
    file: File
    content_type: str
    original_name: str


def _size_label(max_bytes: int) -> str:
    if max_bytes >= 1024 * 1024:
        return f"{max_bytes // (1024 * 1024)} MB"
    return f"{max(max_bytes // 1024, 1)} KB"


def _reencode(upload, fmt: str, field: str) -> ContentFile:
    """As etqan.site.images: decode, verify, rebuild from pixels only, so no
    metadata (EXIF/GPS/ICC/text) survives."""
    refused = ValidationError("This file is not a valid image.", field=field)
    try:
        image = Image.open(upload)
        image.verify()
        upload.seek(0)
        image = Image.open(upload)
        if image.format != fmt or image.width * image.height > MAX_PIXELS:
            raise refused
        image.load()
        clean = Image.frombytes(image.mode, image.size, image.tobytes())
        if image.mode == "P":
            clean.putpalette(image.getpalette())
        if fmt == "JPEG" and clean.mode not in ("RGB", "L"):
            clean = clean.convert("RGB")
        options = {}
        if fmt == "PNG" and "transparency" in image.info:
            options["transparency"] = image.info["transparency"]
        buf = io.BytesIO()
        clean.save(buf, fmt, **options)
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError, Image.DecompressionBombError) as exc:
        raise refused from exc
    return ContentFile(buf.getvalue())


def check_upload(upload, *, extensions: frozenset[str], max_bytes: int, field: str = "file") -> CheckedUpload:
    name = PurePosixPath(upload.name or "").name
    ext = PurePosixPath(name).suffix.lower()
    if ext not in extensions or ext not in _TYPES:
        raise ValidationError("This type of file is not allowed.", field=field)
    if upload.size > max_bytes:
        raise ValidationError(f"The file must be at most {_size_label(max_bytes)}.", field=field)
    content_type, _, check = _TYPES[ext]
    upload.seek(0)
    if isinstance(check, str) and check != "text":
        return CheckedUpload(_reencode(upload, check, field), content_type, name)
    data = upload.read() if check == "text" else upload.read(16)
    upload.seek(0)
    ok = _text(data) if check == "text" else check(data)
    if not ok:
        raise ValidationError("The file's content does not match its type.", field=field)
    return CheckedUpload(upload, content_type, name)


def tenant_upload_path(folder: str) -> Callable[[object, str], str]:
    def _path(instance, filename: str) -> str:
        ext = PurePosixPath(filename).suffix.lower() or ".bin"
        return f"tenants/{connection.schema_name}/{folder}/{uuid.uuid4().hex}{ext}"

    _path.__name__ = _path.__qualname__ = f"{folder}_path"
    return _path
```

Note: `tenant_upload_path` returns a new closure each call; models must bind it to a **module-level name** (`library_path = tenant_upload_path("library")`) so migrations can serialise it by import path. Re-encoded images get their storage name from `upload_to` (the original name's extension), so pass `ContentFile(..., name=original_name)` when saving (Task 3 does).

- [ ] **Step 4: Implement settings and the check**

`base.py`, next to `STORAGES`:

```python
# B9a (spec A-10): files no visitor may fetch by URL (contract files). Kept
# outside MEDIA_ROOT, so neither Django's /media/ nor Caddy serves them;
# streamed by an authenticated view instead.
PRIVATE_MEDIA_ROOT = env("DJANGO_PRIVATE_MEDIA_ROOT", default=str(APPS_DIR / "private_media"))
STORAGES["private"] = {
    "BACKEND": "django.core.files.storage.FileSystemStorage",
    "OPTIONS": {"location": PRIVATE_MEDIA_ROOT, "base_url": None},
}
PRIVATE_STORAGE_SHARED_WITH_PUBLIC = False
```

(Use the module's existing name for the `etqan/` directory — check what `MEDIA_ROOT` is built from and reuse it.) `test.py` already inherits; if `test.py` overrides `MEDIA_ROOT` to a temp dir, set `PRIVATE_MEDIA_ROOT`/`STORAGES["private"]` to a sibling temp dir there too.

`production.py`, after the default storage:

```python
# B9a (spec A-10): contract files. The default bucket is public-read, which
# would override any object ACL, so private files want their own bucket.
# Optional so a deploy without it still works: files then go to the default
# bucket under an unlisted prefix, never given out as a URL, and the
# etqan.W901 check warns.
_private_bucket = env("DJANGO_S3_PRIVATE_BUCKET", default="")
PRIVATE_STORAGE_SHARED_WITH_PUBLIC = not _private_bucket
STORAGES["private"] = {  # noqa: F405
    "BACKEND": "storages.backends.s3.S3Storage",
    "OPTIONS": {
        **STORAGES["default"]["OPTIONS"],  # noqa: F405
        "bucket_name": _private_bucket or env("DJANGO_S3_BUCKET"),
        "location": "" if _private_bucket else "private",
        "custom_domain": None,
        "querystring_auth": True,
    },
}
```

`checks.py`:

```python
from django.conf import settings
from django.core.checks import Warning as CheckWarning
from django.core.checks import register


@register()
def private_storage_check(app_configs, **kwargs):
    if getattr(settings, "PRIVATE_STORAGE_SHARED_WITH_PUBLIC", False):
        return [
            CheckWarning(
                "Contract files share the public bucket (DJANGO_S3_PRIVATE_BUCKET is unset).",
                hint="Set DJANGO_S3_PRIVATE_BUCKET to a bucket with no public policy.",
                id="etqan.W901",
            )
        ]
    return []
```

Import it in `PlatformConfig.ready()` (`from etqan.platform import checks  # noqa: F401`). Add `etqan/private_media/` to `backend/.gitignore`.

- [ ] **Step 5: Run tests** — `just test-backend-host etqan/platform/tests/` → PASS. Run `just lint` (ruff, mypy, lint-imports) → clean.

- [ ] **Step 6: Commit** (in `backend/`)

```bash
git add etqan/platform/uploads.py etqan/platform/checks.py etqan/platform/apps.py etqan/platform/tests/test_uploads.py etqan/platform/tests/test_private_storage_check.py config/settings .gitignore
git commit -m "feat(platform): shared upload checks and a private storage (B9a)"
```

---

### Task 2: Feature switches

**Files:**
- Modify: `backend/etqan/platform/features.py`
- Modify: `backend/etqan/platform/tests/test_features.py` (and any test that counts built/registry entries — run the suite to find them)
- Modify: `dashboard/src/features/identity/schemas.ts` (`FeatureCode`)

**Interfaces:**
- Produces feature codes `file_uploads`, `contracts`, `themes`, `system_status`, all `built=True`, `default=False`.

- [ ] **Step 1: Failing test** — append to `backend/etqan/platform/tests/test_features.py`:

```python
import pytest

from etqan.platform import features


@pytest.mark.parametrize("code", ["file_uploads", "contracts", "themes", "system_status"])
def test_b9a_features_are_built_and_off_by_default(code):
    feature = features.get(code)
    assert feature.built is True
    assert feature.default is False
    assert features.is_on(code, {}) is False
    assert features.is_on(code, {code: True}) is True


def test_b9a_new_switches_are_platform_group():
    assert features.get("themes").group == "platform"
    assert features.get("system_status").group == "platform"
```

- [ ] **Step 2: Run** `just test-backend-host etqan/platform/tests/test_features.py` → FAIL (`themes` unknown).

- [ ] **Step 3: Implement.** Replace the two `_later` lines in place:

```python
    Feature("file_uploads", "File uploads", "نظام رفع الملفات", "content", built=True),
```
```python
    Feature("contracts", "Contracts", "نظام العقود", "people", built=True),
```

Under `# ── phase B9 ──`:

```python
    # ── phase B9 ──
    Feature("themes", "Named themes", "القوالب", "platform", built=True),
    Feature("system_status", "System status", "حالة النظام", "platform", built=True),
```

In `dashboard/src/features/identity/schemas.ts`, extend `FeatureCode` at its end:

```ts
	| "export"
	// B9a
	| "file_uploads"
	| "contracts"
	| "themes"
	| "system_status";
```

- [ ] **Step 4: Run the whole backend suite** (`just test-backend-host`) — fix any test that pinned the built list or count (e.g. a test asserting `BUILT` equals the eight Plan 13 codes: extend it with the four B9a codes and a `# B9a` comment). `seed_dev` turns every built feature on for `demo` (`FEATURES = {"demo": features.BUILT}`); that is intended (demo shows everything) — check `seed` tests still pass. Run `just test-frontend` (type check).

- [ ] **Step 5: Commit** in `backend/` (`feat(platform): B9a feature switches, off by default`) and in `dashboard/` (`feat(identity): B9a feature codes`).

---

### Task 3: File library (`etqan.library`)

**Files:**
- Create: `backend/etqan/library/{__init__.py,apps.py,models.py,services.py,migrations/__init__.py}`, `backend/etqan/library/api/{__init__.py,serializers.py,views.py,urls.py}`, `backend/etqan/library/tests/{__init__.py,test_services.py,test_api.py}`
- Modify: `backend/config/settings/base.py` (`TENANT_APPS` B9 marker: `"etqan.library",`)
- Modify: `backend/config/api_router.py` (B9 marker: `path("library/", include("etqan.library.api.urls")),`)
- Modify: `backend/etqan/access/registry.py` (B9 marker)
- Modify: `backend/etqan/access/tests/test_routes.py` (append `# B9a` blocks)
- Modify: `backend/pyproject.toml` (both B9 markers)

**Interfaces:**
- Consumes: `etqan.platform.uploads.check_upload, LIBRARY_MAX, IMAGE…VIDEO, tenant_upload_path`.
- Produces:
  - `etqan.library.models.LibraryFile` (spec §5).
  - `etqan.library.services.upload(*, name: str, file, by) -> LibraryFile`; `delete_files(ids: list[int]) -> int`; `MAX_BULK = 100`.
  - Routes `GET/POST /api/v1/library/`, `DELETE /api/v1/library/<id>/`, `POST /api/v1/library/bulk-delete/`. Response item: `{id, name, url, size, content_type, uploaded_by: {id, full_name} | null, created_at}`.

- [ ] **Step 1: Failing tests.** `test_services.py`:

```python
import pytest
from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile

from etqan.library import services
from etqan.library.models import LibraryFile
from etqan.platform.exceptions import ValidationError


def _pdf(name="a.pdf"):
    return SimpleUploadedFile(name, b"%PDF-1.4 test")


def test_upload_stores_file_and_metadata(api_for):
    admin = api_for("admin").user
    item = services.upload(name="Syllabus", file=_pdf("Syl.PDF"), by=admin)
    assert item.size == len(b"%PDF-1.4 test")
    assert item.content_type == "application/pdf"
    assert item.file.name.startswith("tenants/pytest_main/library/")
    assert item.file.name.endswith(".pdf")
    assert default_storage.exists(item.file.name)


def test_upload_refuses_svg(api_for):
    with pytest.raises(ValidationError):
        services.upload(name="x", file=SimpleUploadedFile("x.svg", b"<svg/>"), by=api_for().user)


def test_delete_removes_stored_files_after_commit(api_for, django_capture_on_commit_callbacks):
    item = services.upload(name="a", file=_pdf(), by=api_for().user)
    path = item.file.name
    with django_capture_on_commit_callbacks(execute=True):
        assert services.delete_files([item.pk, 999999]) == 1
    assert not LibraryFile.objects.exists()
    assert not default_storage.exists(path)
```

`test_api.py`:

```python
import pytest
from django.core.files.uploadedfile import SimpleUploadedFile

from etqan.library import services


@pytest.fixture(autouse=True)
def _on(set_features):
    set_features(file_uploads=True)


def _post(client, name="Doc", filename="d.pdf", data=b"%PDF-1.4"):
    return client.post("/api/v1/library/", {"name": name, "file": SimpleUploadedFile(filename, data)}, format="multipart")


def test_admin_uploads_lists_and_deletes(api_for):
    admin = api_for("admin")
    resp = _post(admin)
    assert resp.status_code == 201, resp.content
    body = resp.json()
    assert body["name"] == "Doc"
    assert body["url"].startswith("http") and "/media/tenants/pytest_main/library/" in body["url"]
    assert body["uploaded_by"]["id"] == admin.user.id
    listing = admin.get("/api/v1/library/", {"q": "do"}).json()
    assert [r["id"] for r in listing["results"]] == [body["id"]]
    assert admin.delete(f"/api/v1/library/{body['id']}/").status_code == 204


def test_bad_file_is_a_field_error(api_for):
    resp = _post(api_for("admin"), filename="x.html", data=b"<html>")
    assert resp.status_code == 400
    assert "file" in resp.json()


def test_bulk_delete_and_its_limit(api_for):
    admin = api_for("admin")
    ids = [_post(admin).json()["id"] for _ in range(2)]
    resp = admin.post("/api/v1/library/bulk-delete/", {"ids": ids}, format="json")
    assert resp.json() == {"deleted": 2}
    too_many = admin.post("/api/v1/library/bulk-delete/", {"ids": list(range(1, 102))}, format="json")
    assert too_many.status_code == 400
    assert admin.post("/api/v1/library/bulk-delete/", {"ids": []}, format="json").status_code == 400


@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_other_roles_are_refused(api_for, role):
    assert api_for(role).get("/api/v1/library/").status_code == 403


def test_off_is_404(api_for, set_features):
    set_features(file_uploads=False)
    assert api_for("admin").get("/api/v1/library/").status_code == 404


def test_other_academy_cannot_see_files(api_for, tenants):
    from django.db import connection
    from rest_framework.test import APIClient

    _post(api_for("admin"))
    # The other academy has its own schema: its admin lists nothing.
    connection.set_tenant(tenants.other)
    from etqan.identity.models import User
    other_admin = User.objects.create_user(email="o@x.test", password="pw-12345678", role="admin")
    client = APIClient(HTTP_HOST="pytest-other.etqan.localhost")
    client.force_login(other_admin)
    # Feature switches are per academy:
    type(tenants.other).objects.filter(pk=tenants.other.pk).update(features={"file_uploads": True})
    assert client.get("/api/v1/library/").json()["count"] == 0
```

(If an existing cross-academy test pattern exists — grep `tenants.other` in `etqan/site/tests` — copy it instead of the hand-rolled one above.)

- [ ] **Step 2: Run** `just test-backend-host etqan/library` → FAIL (no app).

- [ ] **Step 3: Implement.** `apps.py`: `class LibraryConfig(AppConfig): name = "etqan.library"; default_auto_field = "django.db.models.BigAutoField"` (match the `default_auto_field` other apps use). `models.py`:

```python
from django.conf import settings
from django.db import models

from etqan.platform.uploads import tenant_upload_path

library_path = tenant_upload_path("library")


class LibraryFile(models.Model):
    """Spec B9a A-4: a file in the academy's library, served at a public URL."""

    name = models.CharField(max_length=120)
    file = models.FileField(upload_to=library_path, max_length=255)
    size = models.PositiveBigIntegerField()
    content_type = models.CharField(max_length=100)
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at", "-id")

    def __str__(self):
        return f"LibraryFile<{self.name}>"
```

`services.py`:

```python
from django.core.files.base import ContentFile
from django.db import transaction

from etqan.library.models import LibraryFile
from etqan.platform import uploads

MAX_BULK = 100
KINDS = uploads.IMAGE | uploads.PDF | uploads.OFFICE | uploads.TEXT | uploads.AUDIO | uploads.VIDEO


def upload(*, name: str, file, by) -> LibraryFile:
    checked = uploads.check_upload(file, extensions=KINDS, max_bytes=uploads.LIBRARY_MAX)
    stored = checked.file
    if isinstance(stored, ContentFile):
        stored.name = checked.original_name
    item = LibraryFile(name=name.strip() or checked.original_name, content_type=checked.content_type, uploaded_by=by)
    item.file.save(checked.original_name, stored, save=False)
    item.size = item.file.size
    item.save()
    return item


def _remove_after_commit(paths: list[str], storage) -> None:
    def _remove():
        for path in paths:
            storage.delete(path)

    transaction.on_commit(_remove)


def delete_files(ids: list[int]) -> int:
    items = list(LibraryFile.objects.filter(pk__in=ids))
    if not items:
        return 0
    storage = items[0].file.storage
    paths = [item.file.name for item in items]
    LibraryFile.objects.filter(pk__in=[item.pk for item in items]).delete()
    _remove_after_commit(paths, storage)
    return len(items)
```

S3 content type: set `ContentType` explicitly. django-storages' `S3Storage` reads `get_object_parameters(name)`; give `LibraryFile.file` no special storage but, in `upload`, set `stored.content_type = checked.content_type` (S3Storage uses `content.content_type` when present — verify in `storages/backends/s3.py` `_save`: it calls `_get_write_parameters(name, content)` which uses `getattr(content, "content_type", None)` before guessing). Add a unit test with a fake storage object only if that check passes; otherwise note the finding in the task report.

`api/serializers.py`:

```python
from rest_framework import serializers

from etqan.library.models import LibraryFile


class LibraryFileSerializer(serializers.ModelSerializer):
    url = serializers.SerializerMethodField()
    uploaded_by = serializers.SerializerMethodField()

    class Meta:
        model = LibraryFile
        fields = ("id", "name", "url", "size", "content_type", "uploaded_by", "created_at")

    def get_url(self, obj) -> str:
        return self.context["request"].build_absolute_uri(obj.file.url)

    def get_uploaded_by(self, obj) -> dict | None:
        user = obj.uploaded_by
        return None if user is None else {"id": user.id, "full_name": user.full_name}


class UploadSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120, allow_blank=True, required=False, default="")
    file = serializers.FileField()


class BulkDeleteSerializer(serializers.Serializer):
    ids = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=100)
```

(`build_absolute_uri` on an already-absolute S3 URL returns it unchanged.)

`api/views.py`:

```python
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import status
from rest_framework.parsers import JSONParser
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.library import services
from etqan.library.api.serializers import BulkDeleteSerializer
from etqan.library.api.serializers import LibraryFileSerializer
from etqan.library.api.serializers import UploadSerializer
from etqan.library.models import LibraryFile
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode

FEATURE = "file_uploads"


class LibraryListView(generics.ListAPIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"GET": "library_file.view_any", "POST": "library_file.create"}
    feature = FEATURE
    serializer_class = LibraryFileSerializer
    parser_classes = [MultiPartParser, JSONParser]

    def get_queryset(self):
        qs = LibraryFile.objects.select_related("uploaded_by")
        if q := self.request.query_params.get("q", "").strip():
            qs = qs.filter(name__icontains=q)
        return qs

    def post(self, request):
        data = UploadSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        item = services.upload(name=data.validated_data["name"], file=data.validated_data["file"], by=request.user)
        return Response(LibraryFileSerializer(item, context={"request": request}).data, status=status.HTTP_201_CREATED)


class LibraryDetailView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"DELETE": "library_file.delete"}
    feature = FEATURE

    def delete(self, request, pk):
        get_object_or_404(LibraryFile, pk=pk)
        services.delete_files([pk])
        return Response(status=status.HTTP_204_NO_CONTENT)


class LibraryBulkDeleteView(APIView):
    permission_classes = [HasCode, FeatureOn]
    permission_codes = {"POST": "library_file.delete_any"}
    feature = FEATURE

    def post(self, request):
        data = BulkDeleteSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        return Response({"deleted": services.delete_files(data.validated_data["ids"])})
```

`api/urls.py`: `""` → `LibraryListView`, `"bulk-delete/"` → bulk, `"<int:pk>/"` → detail (bulk-delete before `<int:pk>`).

Registry, under `# ── phase B9 ──` in `RESOURCES`:

```python
    # ── phase B9 ──
    Resource("library_file", "Files", "الملفات", ("view_any", "create", "delete", "delete_any")),
```

`test_routes.py`: append to `ROUTES` (before the closing `]`):

```python
    # B9a: the file library.
    ("GET", "/api/v1/library/", "library_file.view_any"),
    ("POST", "/api/v1/library/", "library_file.create"),
    ("DELETE", f"/api/v1/library/{N}/", "library_file.delete"),
    ("POST", "/api/v1/library/bulk-delete/", "library_file.delete_any"),
```

to `FEATURES` (a new `**dict.fromkeys((...), "file_uploads")` entry marked `# B9a`), and `"/library/": "file_uploads"` to `FEATURE_WORDS`.

pyproject first B9 marker (platform forbidden list): `"etqan.library",`. Second B9 marker (end of contracts):

```toml
# ── phase B9 ──
[[tool.importlinter.contracts]]
name = "library imports only the platform"
type = "forbidden"
source_modules = ["etqan.library"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access"]
ignore_imports = ["etqan.library.tests.* -> etqan.identity.models"]
```

(Keep the marker line itself where it is and put the block right after it; read how the second marker section looks first and match its comment style.)

Make the migration: `just _stack-manage makemigrations library` (or `just shell` equivalent; the stack must be up: `just dev-backend`). Check the generated migration references `etqan.library.models.library_path`.

- [ ] **Step 4: Run** `just migrate`, then `just test-backend-host etqan/library etqan/access etqan/platform` → PASS; `just lint` → clean.

- [ ] **Step 5: Commit** (`feat(library): academy file library (B9a)`).

---

### Task 4: Employment contracts (`etqan.employment`)

**Files:**
- Create: `backend/etqan/employment/{__init__.py,apps.py,models.py,services.py,migrations/__init__.py}`, `api/{__init__.py,serializers.py,views.py,urls.py}`, `tests/{__init__.py,test_services.py,test_api.py}`
- Modify: `TENANT_APPS`, `api_router.py` (`path("contracts/", include("etqan.employment.api.urls")),`), `registry.py`, `test_routes.py`, `pyproject.toml` (B9 markers)

**Interfaces:**
- Consumes: `uploads.check_upload, CONTRACT_MAX, IMAGE, PDF, tenant_upload_path`; `etqan.identity.services.get_teacher_profile(user_id) -> TeacherProfile | None`.
- Produces:
  - `etqan.employment.models.Contract` (spec §5; `teacher` FK `settings.AUTH_USER_MODEL`, `PROTECT`, `related_name="contracts"`).
  - `services.create_contract(*, teacher_id: int, reference: str, details: str, file, by) -> Contract`; `services.update_contract(contract, *, reference=None, details=None, file=None, remove_file=False) -> Contract`; `services.delete_contract(contract) -> None`; `services.contracts_for(user) -> QuerySet` (office: all; teacher: own; others: none).
  - Item JSON: `{id, teacher: {id, full_name}, reference, details, has_file, file_name, created_at, updated_at}`.

- [ ] **Step 1: Failing tests.** `test_api.py` (the services are covered through the API plus a few direct tests in `test_services.py` for the "details or file" rule and the after-commit file removal on delete/replace/remove):

```python
import pytest
from django.core.files.storage import storages
from django.core.files.uploadedfile import SimpleUploadedFile

PDF = b"%PDF-1.4 contract"


@pytest.fixture(autouse=True)
def _on(set_features):
    set_features(contracts=True)


@pytest.fixture
def teacher(api_for):
    from etqan.identity import services as identity_services

    client = api_for("teacher")
    identity_services.ensure_teacher_profile(client.user)  # see note below
    return client


def _create(admin, teacher_id, **extra):
    data = {"teacher": teacher_id, "reference": "C-1", "details": "", **extra}
    return admin.post("/api/v1/contracts/", data, format="multipart")


def test_admin_creates_with_file_and_teacher_downloads(api_for, teacher):
    admin = api_for("admin")
    resp = _create(admin, teacher.user.id, file=SimpleUploadedFile("Contract.pdf", PDF))
    assert resp.status_code == 201, resp.content
    body = resp.json()
    assert body["has_file"] is True and body["file_name"] == "Contract.pdf"
    assert "url" not in body
    from etqan.employment.models import Contract
    stored = Contract.objects.get(pk=body["id"]).file
    assert stored.storage is storages["private"]
    download = teacher.get(f"/api/v1/contracts/{body['id']}/file/")
    assert download.status_code == 200
    assert b"".join(download.streaming_content) == PDF
    assert download["Content-Type"] == "application/pdf"
    assert download["Content-Disposition"].startswith("attachment;")
    assert "Contract.pdf" in download["Content-Disposition"]
    assert download["X-Content-Type-Options"] == "nosniff"
    assert "no-store" in download["Cache-Control"]


def test_details_or_file_required(api_for, teacher):
    resp = _create(api_for("admin"), teacher.user.id)
    assert resp.status_code == 400
    assert "non_field_errors" in resp.json()


def test_remove_file_with_empty_details_refused(api_for, teacher):
    admin = api_for("admin")
    cid = _create(admin, teacher.user.id, file=SimpleUploadedFile("c.pdf", PDF)).json()["id"]
    resp = admin.patch(f"/api/v1/contracts/{cid}/", {"remove_file": "true"}, format="multipart")
    assert resp.status_code == 400
    ok = admin.patch(f"/api/v1/contracts/{cid}/", {"remove_file": "true", "details": "Signed on paper"}, format="multipart")
    assert ok.status_code == 200 and ok.json()["has_file"] is False
    assert admin.get(f"/api/v1/contracts/{cid}/file/").status_code == 404


def test_teacher_must_be_a_teacher(api_for):
    student = api_for("student")
    resp = _create(api_for("admin"), student.user.id, details="x")
    assert resp.status_code == 400 and "teacher" in resp.json()


def test_teacher_sees_only_own_and_cannot_write(api_for, teacher):
    admin = api_for("admin")
    other = api_for("teacher")
    mine = _create(admin, teacher.user.id, details="mine").json()["id"]
    theirs = _create(admin, other.user.id, details="theirs").json()["id"]
    listing = teacher.get("/api/v1/contracts/", {"teacher": other.user.id}).json()
    assert [c["id"] for c in listing["results"]] == [mine]
    assert teacher.get(f"/api/v1/contracts/{theirs}/").status_code == 404
    assert teacher.post("/api/v1/contracts/", {"teacher": teacher.user.id, "details": "x"}).status_code == 403
    assert teacher.patch(f"/api/v1/contracts/{mine}/", {"details": "y"}).status_code == 403


def test_teacher_cannot_download_another_teachers_file(api_for, teacher):
    admin = api_for("admin")
    other = api_for("teacher")
    theirs = _create(admin, other.user.id, file=SimpleUploadedFile("c.pdf", PDF)).json()["id"]
    assert teacher.get(f"/api/v1/contracts/{theirs}/file/").status_code == 404


@pytest.mark.parametrize("role", ["student", "parent"])
def test_students_and_parents_are_refused(api_for, role):
    assert api_for(role).get("/api/v1/contracts/").status_code == 403


def test_anonymous_download_refused(api_for, teacher, client):
    cid = _create(api_for("admin"), teacher.user.id, file=SimpleUploadedFile("c.pdf", PDF)).json()["id"]
    assert client.get(f"/api/v1/contracts/{cid}/file/").status_code in (401, 403)


def test_off_is_404_for_admin_and_teacher(api_for, teacher, set_features):
    set_features(contracts=False)
    assert api_for("admin").get("/api/v1/contracts/").status_code == 404
    assert teacher.get("/api/v1/contracts/").status_code == 404


def test_delete_and_replace_remove_stored_file_after_commit(api_for, teacher, django_capture_on_commit_callbacks):
    admin = api_for("admin")
    cid = _create(admin, teacher.user.id, file=SimpleUploadedFile("a.pdf", PDF)).json()["id"]
    from etqan.employment.models import Contract
    first = Contract.objects.get(pk=cid).file.name
    with django_capture_on_commit_callbacks(execute=True):
        admin.patch(f"/api/v1/contracts/{cid}/", {"file": SimpleUploadedFile("b.pdf", PDF)}, format="multipart")
    assert not storages["private"].exists(first)
    second = Contract.objects.get(pk=cid).file.name
    with django_capture_on_commit_callbacks(execute=True):
        assert admin.delete(f"/api/v1/contracts/{cid}/").status_code == 204
    assert not storages["private"].exists(second)


def test_mp4_refused_for_contracts(api_for, teacher):
    resp = _create(api_for("admin"), teacher.user.id, file=SimpleUploadedFile("a.mp4", b"\0\0\0\x20ftypisom"))
    assert resp.status_code == 400 and "file" in resp.json()
```

Note on the `teacher` fixture: `api_for("teacher")` creates a bare `User` with role teacher. Check whether `get_teacher_profile` returns None for it; if so, create the profile the way identity tests do (grep `TeacherProfile.objects.create` in `etqan/identity/tests`) and drop the made-up `ensure_teacher_profile` call. The service's teacher check is: `get_teacher_profile(teacher_id) is not None` (a teacher-role user with a profile).

- [ ] **Step 2: Run** `just test-backend-host etqan/employment` → FAIL.

- [ ] **Step 3: Implement.** `models.py`:

```python
from django.conf import settings
from django.core.files.storage import storages
from django.db import models
from django.db.models import Q

from etqan.platform.uploads import tenant_upload_path

employment_path = tenant_upload_path("employment")


def private_storage():
    return storages["private"]


class Contract(models.Model):
    """Spec B9a A-9: a teacher's employment contract. Its file is private (A-10)."""

    teacher = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="contracts")
    reference = models.CharField(max_length=60, blank=True, default="")
    details = models.TextField(blank=True, default="")
    file = models.FileField(storage=private_storage, upload_to=employment_path, blank=True, max_length=255)
    file_name = models.CharField(max_length=255, blank=True, default="")
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at", "-id")
        constraints = [
            models.CheckConstraint(
                check=~(Q(details="") & Q(file="")), name="employment_contract_details_or_file"
            )
        ]

    def __str__(self):
        return f"Contract<{self.teacher_id}, {self.reference}>"
```

(Django is 5.0: `CheckConstraint` takes `check=`.)

`services.py`:

```python
from django.core.files.base import ContentFile
from django.db import transaction

from etqan.employment.models import Contract
from etqan.identity import services as identity_services
from etqan.platform import uploads
from etqan.platform.exceptions import ValidationError
from etqan.platform.permissions import is_office
from etqan.platform.permissions import role_of

KINDS = frozenset({".png", ".jpg", ".jpeg", ".webp"}) | uploads.PDF | frozenset({".docx"})
DETAILS_OR_FILE = "Enter the details or attach the contract file."


def contracts_for(user):
    qs = Contract.objects.select_related("teacher")
    if is_office(user):
        return qs
    if role_of(user) == "teacher":
        return qs.filter(teacher_id=user.id)
    return qs.none()


def _attach(contract: Contract, file) -> str | None:
    """Store ``file`` on the contract; returns the old stored name to delete."""
    checked = uploads.check_upload(file, extensions=KINDS, max_bytes=uploads.CONTRACT_MAX)
    old = contract.file.name or None
    stored = checked.file
    if isinstance(stored, ContentFile):
        stored.name = checked.original_name
    stored.content_type = checked.content_type
    contract.file.save(checked.original_name, stored, save=False)
    contract.file_name = checked.original_name
    return old


def _remove_after_commit(name: str | None) -> None:
    if name:
        storage = Contract._meta.get_field("file").storage  # noqa: SLF001
        transaction.on_commit(lambda: storage.delete(name))


def _check(contract: Contract) -> None:
    if not contract.details.strip() and not contract.file:
        raise ValidationError(DETAILS_OR_FILE, field="non_field_errors")


def create_contract(*, teacher_id: int, reference: str = "", details: str = "", file=None, by) -> Contract:
    if identity_services.get_teacher_profile(teacher_id) is None:
        raise ValidationError("Choose a teacher.", field="teacher")
    contract = Contract(teacher_id=teacher_id, reference=reference.strip(), details=details.strip(), created_by=by)
    if file is not None:
        _attach(contract, file)
    _check(contract)
    contract.save()
    return contract


def update_contract(contract: Contract, *, reference=None, details=None, file=None, remove_file=False) -> Contract:
    if reference is not None:
        contract.reference = reference.strip()
    if details is not None:
        contract.details = details.strip()
    stale = None
    if file is not None:
        stale = _attach(contract, file)
    elif remove_file and contract.file:
        stale = contract.file.name
        contract.file = None
        contract.file_name = ""
    _check(contract)
    contract.save()
    _remove_after_commit(stale)
    return contract


def delete_contract(contract: Contract) -> None:
    name = contract.file.name or None
    contract.delete()
    _remove_after_commit(name)
```

Note: a file attached by `_attach` and then refused by `_check` cannot happen (a file makes `_check` pass). But a request that fails *after* `create_contract` (e.g. a later exception rolling back the transaction) leaves an orphan stored file — accepted (no listing exposes it); mention in the docstring.

If `ValidationError(field="non_field_errors")` renders as `{"non_field_errors": [...]}` through `etqan.platform.drf.exception_handler` (it uses `field` as the key) — it does.

`api/serializers.py`:

```python
from rest_framework import serializers

from etqan.employment.models import Contract


class ContractSerializer(serializers.ModelSerializer):
    teacher = serializers.SerializerMethodField()
    has_file = serializers.SerializerMethodField()

    class Meta:
        model = Contract
        fields = ("id", "teacher", "reference", "details", "has_file", "file_name", "created_at", "updated_at")

    def get_teacher(self, obj) -> dict:
        return {"id": obj.teacher_id, "full_name": obj.teacher.full_name}

    def get_has_file(self, obj) -> bool:
        return bool(obj.file)


class ContractWriteSerializer(serializers.Serializer):
    teacher = serializers.IntegerField(required=False)
    reference = serializers.CharField(max_length=60, required=False, allow_blank=True)
    details = serializers.CharField(required=False, allow_blank=True)
    file = serializers.FileField(required=False)
    remove_file = serializers.BooleanField(required=False, default=False)
```

`api/views.py` (permission `[HasCode | (ReadOnly & IsTeacher), FeatureOn]`):

```python
from django.http import FileResponse
from django.http import Http404
from rest_framework import generics
from rest_framework import status
from rest_framework.parsers import JSONParser
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.employment import services
from etqan.employment.api.serializers import ContractSerializer
from etqan.employment.api.serializers import ContractWriteSerializer
from etqan.platform.permissions import FeatureOn
from etqan.platform.permissions import HasCode
from etqan.platform.permissions import IsTeacher
from etqan.platform.permissions import ReadOnly
from etqan.platform.permissions import is_office

PERMISSIONS = [HasCode | (ReadOnly & IsTeacher), FeatureOn]
FEATURE = "contracts"


def _get(request, pk):
    contract = services.contracts_for(request.user).filter(pk=pk).first()
    if contract is None:
        raise Http404
    return contract


class ContractListView(generics.ListAPIView):
    permission_classes = PERMISSIONS
    permission_codes = {"GET": "contract.view_any", "POST": "contract.create"}
    feature = FEATURE
    serializer_class = ContractSerializer
    parser_classes = [MultiPartParser, JSONParser]

    def get_queryset(self):
        qs = services.contracts_for(self.request.user)
        params = self.request.query_params
        if is_office(self.request.user) and (teacher := params.get("teacher", "")).isdigit():
            qs = qs.filter(teacher_id=int(teacher))
        if q := params.get("q", "").strip():
            from django.db.models import Q
            qs = qs.filter(Q(reference__icontains=q) | Q(teacher__full_name__icontains=q))
        return qs

    def post(self, request):
        data = ContractWriteSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        v = data.validated_data
        if "teacher" not in v:
            return Response({"teacher": ["This field is required."]}, status=status.HTTP_400_BAD_REQUEST)
        contract = services.create_contract(
            teacher_id=v["teacher"], reference=v.get("reference", ""), details=v.get("details", ""),
            file=v.get("file"), by=request.user,
        )
        return Response(ContractSerializer(contract).data, status=status.HTTP_201_CREATED)


class ContractDetailView(APIView):
    permission_classes = PERMISSIONS
    permission_codes = {"GET": "contract.view", "PATCH": "contract.update", "DELETE": "contract.delete"}
    feature = FEATURE
    parser_classes = [MultiPartParser, JSONParser]

    def get(self, request, pk):
        return Response(ContractSerializer(_get(request, pk)).data)

    def patch(self, request, pk):
        contract = _get(request, pk)
        data = ContractWriteSerializer(data=request.data, partial=True)
        data.is_valid(raise_exception=True)
        v = data.validated_data
        contract = services.update_contract(
            contract, reference=v.get("reference"), details=v.get("details"),
            file=v.get("file"), remove_file=v.get("remove_file", False),
        )
        return Response(ContractSerializer(contract).data)

    def delete(self, request, pk):
        services.delete_contract(_get(request, pk))
        return Response(status=status.HTTP_204_NO_CONTENT)


class ContractFileView(APIView):
    permission_classes = PERMISSIONS
    permission_codes = {"GET": "contract.view"}
    feature = FEATURE

    def get(self, request, pk):
        contract = _get(request, pk)
        if not contract.file:
            raise Http404
        from etqan.platform.uploads import content_type_for
        response = FileResponse(
            contract.file.open("rb"), as_attachment=True, filename=contract.file_name or "contract",
            content_type=content_type_for(contract.file.name),
        )
        response["X-Content-Type-Options"] = "nosniff"
        response["Cache-Control"] = "private, no-store"
        return response
```

Add to `uploads.py` (with a test in `test_uploads.py`): `def content_type_for(name: str) -> str: return _TYPES.get(PurePosixPath(name).suffix.lower(), ("application/octet-stream",))[0]`. Move the local imports to module top (ruff). `urls.py`: `""`, `"<int:pk>/"`, `"<int:pk>/file/"`.

Registry B9 marker:

```python
    Resource("contract", "Employment contracts", "عقود العمل", ("view", "view_any", "create", "update", "delete")),
```

`test_routes.py` appends (`# B9a: employment contracts`): GET/POST `/api/v1/contracts/` (`contract.view_any` / `contract.create`), GET/PATCH/DELETE `/api/v1/contracts/{N}/` (`contract.view`/`update`/`delete`), GET `/api/v1/contracts/{N}/file/` (`contract.view`); the same six in `FEATURES` → `"contracts"`; `FEATURE_WORDS["/contracts/"] = "contracts"`.

pyproject: `"etqan.employment",` in the platform forbidden list (marker 1); contract (marker 2):

```toml
[[tool.importlinter.contracts]]
name = "employment reaches identity only through its services"
type = "forbidden"
source_modules = ["etqan.employment"]
forbidden_modules = ["etqan.identity.models", "etqan.identity.api", "etqan.tenants", "etqan.site", "etqan.academy", "etqan.catalogue", "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access"]
allow_indirect_imports = true
ignore_imports = ["etqan.employment.tests.* -> etqan.identity.models"]
```

Migration via `makemigrations employment` (stack up); check it serialises `etqan.employment.models.private_storage` and `employment_path`.

- [ ] **Step 4: Run** `just migrate`; `just test-backend-host etqan/employment etqan/access etqan/platform` → PASS; `just lint`.

- [ ] **Step 5: Commit** (`feat(employment): teacher employment contracts with private files (B9a)`).

---

### Task 5: System status and the reconcile job (`etqan.systemstatus`)

**Files:**
- Create: `backend/etqan/systemstatus/{__init__.py,apps.py,models.py,services.py,tasks.py,migrations/__init__.py}`, `api/{__init__.py,views.py,serializers.py,urls.py}`, `tests/{__init__.py,test_services.py,test_tasks.py,test_api.py}`
- Modify: `TENANT_APPS`, `api_router.py` (`path("system-status/", include("etqan.systemstatus.api.urls")),`), `registry.py` (`page.system_status` → `in_use=True` in place; update the `PAGES` comment to "TutorHamster's pages: listed for parity; B9 builds some (spec 2026-10-03 B9-3)"), `test_routes.py`, `pyproject.toml`

**Interfaces:**
- Consumes: `etqan.scheduling.services.run_lifecycle() -> dict[str, int]`; `etqan.academy.services.get_settings().timezone`; `etqan.platform.tenancy.academy_context(schema_name)`; `etqan.platform.features.enabled_codes()`.
- Produces:
  - `JobRun` (spec §5) with `Job.RECONCILE = "reconcile_subscriptions"`, `Status` choices, `OPEN = ("queued", "running")`.
  - `services.request_run(job: str, *, by) -> JobRun` (raises `ConflictError(code="systemstatus.run_open")`); `services.overview() -> dict`; `services.recent_runs(limit=20)`; `STALE_AFTER = timedelta(hours=1)`.
  - Celery task `systemstatus.run_job(schema_name: str, run_id: int)`.
  - `GET /api/v1/system-status/` → `{version, subdomain, timezone, academy_now, server_now, features_on, jobs: [{code, schedule}], runs: [...]}`; `POST /api/v1/system-status/runs/` → 202 run JSON `{id, job, status, result, error, requested_by: {id, full_name}|null, requested_at, started_at, finished_at}`.

- [ ] **Step 1: Failing tests.** `test_tasks.py`:

```python
from unittest import mock

import pytest
from django.db import OperationalError

from etqan.systemstatus import services
from etqan.systemstatus import tasks
from etqan.systemstatus.models import JobRun


@pytest.fixture
def run(api_for, django_capture_on_commit_callbacks):
    with mock.patch.object(tasks.run_job, "delay"):
        with django_capture_on_commit_callbacks(execute=True):
            return services.request_run(JobRun.Job.RECONCILE, by=api_for("admin").user)


def test_ok_records_counts_inside_an_atomic_block(run, tenants):
    seen = {}

    def fake():
        from django.db import connection
        seen["schema"] = connection.schema_name
        seen["atomic"] = connection.in_atomic_block
        return {"paused": 1, "resumed": 0, "expired": 2, "created": 3}

    with mock.patch.object(tasks, "run_lifecycle", side_effect=fake):
        tasks.run_job(tenants.main.schema_name, run.pk)
    run.refresh_from_db()
    assert (run.status, run.result) == ("ok", {"paused": 1, "resumed": 0, "expired": 2, "created": 3})
    assert run.started_at and run.finished_at
    assert seen == {"schema": tenants.main.schema_name, "atomic": True}


@pytest.mark.parametrize("error", [RuntimeError("boom"), OperationalError("deadlock detected")])
def test_failure_is_recorded(run, tenants, error):
    with mock.patch.object(tasks, "run_lifecycle", side_effect=error):
        tasks.run_job(tenants.main.schema_name, run.pk)
    run.refresh_from_db()
    assert run.status == "failed"
    assert run.error


def test_suspended_academy_fails_the_run(run, tenants):
    type(tenants.main).objects.filter(pk=tenants.main.pk).update(status="suspended")
    try:
        with mock.patch.object(tasks, "run_lifecycle") as lifecycle:
            tasks.run_job(tenants.main.schema_name, run.pk)
        lifecycle.assert_not_called()
    finally:
        type(tenants.main).objects.filter(pk=tenants.main.pk).update(status="active")
    run.refresh_from_db()
    assert run.status == "failed" and "suspended" in run.error
```

`Academy.Status` is `active` / `suspended` (`etqan/tenants/models.py`). The task cannot import `etqan.tenants`; it reads `academy.status` off the object `academy_context` yields.

`test_services.py`:

```python
from datetime import timedelta
from unittest import mock

import pytest
from django.db import IntegrityError
from django.utils import timezone

from etqan.platform.exceptions import ConflictError
from etqan.systemstatus import services
from etqan.systemstatus import tasks
from etqan.systemstatus.models import JobRun

R = JobRun.Job.RECONCILE


def test_request_queues_on_commit(api_for, django_capture_on_commit_callbacks, tenants):
    with mock.patch.object(tasks.run_job, "delay") as delay:
        with django_capture_on_commit_callbacks(execute=False) as callbacks:
            run = services.request_run(R, by=api_for().user)
        delay.assert_not_called()
        for callback in callbacks:
            callback()
    delay.assert_called_once_with(tenants.main.schema_name, run.pk)
    assert run.status == "queued"


def test_second_open_run_is_409(api_for):
    with mock.patch.object(tasks.run_job, "delay"):
        services.request_run(R, by=api_for().user)
        with pytest.raises(ConflictError) as exc:
            services.request_run(R, by=api_for().user)
    assert exc.value.code == "systemstatus.run_open"


def test_second_open_run_is_409_by_constraint(api_for):
    JobRun.objects.create(job=R, status="running")
    with pytest.raises(IntegrityError):
        JobRun.objects.create(job=R, status="queued")


def test_stale_open_run_is_failed_then_new_run_allowed(api_for):
    old = JobRun.objects.create(job=R, status="running")
    JobRun.objects.filter(pk=old.pk).update(requested_at=timezone.now() - timedelta(hours=2))
    with mock.patch.object(tasks.run_job, "delay"):
        new = services.request_run(R, by=api_for().user)
    old.refresh_from_db()
    assert (old.status, old.error) == ("failed", "Timed out.")
    assert new.status == "queued"


def test_overview(api_for, set_features, settings):
    settings.ETQAN_VERSION = "1.2.3"
    set_features(system_status=True)
    data = services.overview()
    assert data["version"] == "1.2.3"
    assert data["features_on"] >= 1
    assert [j["code"] for j in data["jobs"]] == ["reconcile_subscriptions", "notifications"]
```

`request_run` must turn a race's `IntegrityError` into the same `ConflictError`: wrap the insert in `transaction.atomic()` (a savepoint) and catch `IntegrityError`.

`test_api.py`: admin GET 200 with the keys above; staff with `page.system_status` passes, without it 403; teacher 403; switch off → 404 for admin; POST → 202 then a second POST → 409 with `{"detail": ..., "code": "systemstatus.run_open"}`; GET lists the run in `runs`.

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement.** `models.py`:

```python
from django.conf import settings
from django.db import models
from django.db.models import Q


class JobRun(models.Model):
    """Spec B9a A-14: one manual run of a background job in this academy."""

    class Job(models.TextChoices):
        RECONCILE = "reconcile_subscriptions", "Reconcile subscriptions"

    class Status(models.TextChoices):
        QUEUED = "queued", "Queued"
        RUNNING = "running", "Running"
        OK = "ok", "Done"
        FAILED = "failed", "Failed"

    OPEN = (Status.QUEUED, Status.RUNNING)

    job = models.CharField(max_length=40, choices=Job.choices)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.QUEUED)
    result = models.JSONField(default=dict, blank=True)
    error = models.TextField(blank=True, default="")
    requested_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    requested_at = models.DateTimeField(auto_now_add=True)
    started_at = models.DateTimeField(null=True, blank=True)
    finished_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-requested_at", "-id")
        constraints = [
            models.UniqueConstraint(
                fields=["job"], condition=Q(status__in=["queued", "running"]), name="systemstatus_one_open_run_per_job"
            )
        ]
```

`services.py`:

```python
from datetime import timedelta

from django.conf import settings
from django.db import IntegrityError
from django.db import connection
from django.db import transaction
from django.utils import timezone

from etqan.platform import features
from etqan.platform.exceptions import ConflictError
from etqan.systemstatus.models import JobRun

STALE_AFTER = timedelta(hours=1)
JOBS = (
    {"code": "reconcile_subscriptions", "schedule": "hourly"},
    {"code": "notifications", "schedule": "every_minute"},
)


def _fail_stale(job: str) -> None:
    JobRun.objects.filter(job=job, status__in=JobRun.OPEN, requested_at__lt=timezone.now() - STALE_AFTER).update(
        status=JobRun.Status.FAILED, error="Timed out.", finished_at=timezone.now()
    )


def request_run(job: str, *, by) -> JobRun:
    from etqan.systemstatus import tasks  # the task module imports this one

    _fail_stale(job)
    try:
        with transaction.atomic():
            run = JobRun.objects.create(job=job, requested_by=by)
    except IntegrityError:
        raise ConflictError("A run of this job is already in progress.", code="systemstatus.run_open") from None
    schema = connection.schema_name
    transaction.on_commit(lambda: tasks.run_job.delay(schema, run.pk))
    return run


def recent_runs(limit: int = 20):
    return JobRun.objects.select_related("requested_by")[:limit]


def overview() -> dict:
    tz_name = academy_services.get_settings().timezone
    now = timezone.now()
    return {
        "version": getattr(settings, "ETQAN_VERSION", "") or "dev",
        "subdomain": getattr(connection.tenant, "subdomain", ""),
        "timezone": tz_name,
        "academy_now": now.astimezone(ZoneInfo(tz_name)).isoformat(),
        "server_now": now.isoformat(),
        "features_on": len(features.enabled_codes()),
        "jobs": list(JOBS),
    }
```

with `from zoneinfo import ZoneInfo` and `from etqan.academy import services as academy_services` at the top (`get_settings()` returns the academy's `AcademySettings`, whose `timezone` is an IANA name). Add `ETQAN_VERSION = env("ETQAN_VERSION", default="")` to `config/settings/base.py`.

`tasks.py`:

```python
import logging

from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded
from django.db import transaction
from django.utils import timezone

from etqan.platform.tenancy import academy_context
from etqan.scheduling.services import run_lifecycle
from etqan.systemstatus.models import JobRun

logger = logging.getLogger(__name__)
RUN_JOB = "systemstatus.run_job"
LOCK_KEY = 0x5E7A_0001  # pg advisory lock: one manual reconcile at a time per academy schema


def _finish(run_id: int, **fields) -> None:
    JobRun.objects.filter(pk=run_id).update(finished_at=timezone.now(), **fields)


@shared_task(name=RUN_JOB, soft_time_limit=3000, time_limit=3300)
def run_job(schema_name: str, run_id: int) -> str:
    with academy_context(schema_name) as academy:
        if getattr(academy, "status", "active") != "active":
            _finish(run_id, status=JobRun.Status.FAILED, error="Academy suspended.")
            return "failed"
        JobRun.objects.filter(pk=run_id).update(status=JobRun.Status.RUNNING, started_at=timezone.now())
        try:
            with transaction.atomic():
                from django.db import connection
                with connection.cursor() as cursor:
                    cursor.execute("SELECT pg_try_advisory_xact_lock(%s)", [LOCK_KEY])
                    (locked,) = cursor.fetchone()
                if not locked:
                    raise RuntimeError("Another reconcile is running.")
                result = run_lifecycle()
        except (Exception, SoftTimeLimitExceeded) as exc:  # noqa: BLE001 — recorded, not lost
            logger.exception("%s failed for %s", RUN_JOB, schema_name)
            _finish(run_id, status=JobRun.Status.FAILED, error=str(exc)[:500] or exc.__class__.__name__)
            return "failed"
        _finish(run_id, status=JobRun.Status.OK, result=result)
        return "ok"
```

Note the advisory lock key is per database, not per schema: two academies' manual runs serialise against each other, which is harmless (each is short and the second fails fast with "Another reconcile is running." — **change this**: derive the key from the schema, `LOCK_KEY ^ zlib.crc32(schema_name.encode())`, so academies don't block each other; test `test_ok_records_counts_inside_an_atomic_block` still passes). Move the `connection` import to the top. Tests run Celery eagerly (`CELERY_TASK_ALWAYS_EAGER = True` in `config/settings/test.py`); the tests above call `run_job(...)` directly and patch `.delay`, so an API test that POSTs must patch `tasks.run_job.delay` too (or capture on-commit callbacks without executing them).

Views: `SystemStatusView(APIView)` GET (`permission_codes = {"GET": "page.system_status"}`, `feature = "system_status"`, `[HasCode, FeatureOn]`) returns `{**services.overview(), "runs": JobRunSerializer(services.recent_runs(), many=True).data}`; `SystemStatusRunsView` POST (`{"POST": "page.system_status"}`) validates `job` is a `JobRun.Job` value, calls `request_run`, returns 202.

`test_routes.py` appends: GET `/api/v1/system-status/` and POST `/api/v1/system-status/runs/` with `page.system_status`; both in `FEATURES` → `"system_status"`; `FEATURE_WORDS["/system-status/"] = "system_status"`. Because a POST in the route test's parametrised calls has `{}` as body, it returns 400 (not 403) for allowed callers — fine. **But** the route tests call the POST for real with the admin: with an empty body it must 400 before queueing. Make the serializer require `job`.

pyproject: `"etqan.systemstatus",` in platform's forbidden list; contract:

```toml
[[tool.importlinter.contracts]]
name = "systemstatus reaches scheduling only through its services"
type = "forbidden"
source_modules = ["etqan.systemstatus"]
forbidden_modules = ["etqan.identity", "etqan.tenants", "etqan.site", "etqan.catalogue", "etqan.scheduling.models", "etqan.scheduling.api", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access", "etqan.academy.models", "etqan.academy.api"]
# systemstatus -> scheduling.services / academy.services -> their models is the allowed path.
allow_indirect_imports = true
ignore_imports = ["etqan.systemstatus.tests.* -> etqan.identity.models"]
```

Also add `"etqan.systemstatus"` to the existing "other apps reach scheduling only through its services" contract? No — that contract is a shared single list owned by nobody; leave it (the B9 contract above already forbids `scheduling.models/api`). Migration via `makemigrations systemstatus`.

- [ ] **Step 4: Run** `just migrate`; `just test-backend-host etqan/systemstatus etqan/access etqan/platform` → PASS; `just lint`.

- [ ] **Step 5: Commit** (`feat(systemstatus): system status page and the reconcile-now job (B9a)`).

---

### Task 6: Seeds

**Files:**
- Create: `backend/etqan/tenants/seeds/b9.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (one call under `# ── phase B9 ──`)
- Test: `backend/etqan/tenants/tests/test_seed_b9.py` (check where seed tests live: `grep -rl seed_academy etqan/tenants/tests`)

**Interfaces:**
- Consumes: `etqan.library.services.upload`, `etqan.employment.services.create_contract`, `etqan.identity.services.get_person`/teacher lookup by email.
- Produces: `etqan.tenants.seeds.b9.seed_b9(subdomain: str) -> None` — idempotent; for `demo` only: two library files (`Welcome.pdf`, `Timetable.csv`) and one contract (reference `EMP-001`, a small PDF, details "Part-time, 10 hours a week") for `bilal@demo.test`; other academies nothing. Switches are not touched.

- [ ] **Step 1: Failing test** — call `seed_b9("demo")` twice in the main test academy after creating a teacher with `email="bilal@demo.test"` the way the seed's own helpers do; assert 2 library files, 1 contract, files exist in their storages; `seed_b9("other")` adds nothing.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** with `SimpleUploadedFile` bytes (`b"%PDF-1.4\n% Etqan demo\n"`, `b"day,time\nMon,10:00\n"`); idempotency by `LibraryFile.objects.filter(name=...)` / `Contract.objects.filter(reference="EMP-001")` — use the apps' services and models via their public modules (the tenants app already imports business services in seed_dev). Under the B9 marker in `seed_academy`: `b9_seeds.seed_b9(subdomain)` with `from etqan.tenants.seeds import b9 as b9_seeds` at the top.
- [ ] **Step 4: Run** `just test-backend-host etqan/tenants` and `just seed` (stack up) → PASS / no error twice.
- [ ] **Step 5: Commit** (`feat(seeds): B9a demo files and contract`).

---

### Task 7: Named themes (dashboard)

**Files:**
- Create: `dashboard/src/features/appearance/{palettes.ts,palette.tsx,AppearanceCard.tsx,index.ts}`, tests `palettes.test.ts`, `palette.test.tsx`, `AppearanceCard.test.tsx`
- Modify: `dashboard/src/lib/theme.tsx` (respect a forced dark mode without overwriting the stored value)
- Modify: the app root that mounts `ThemeProvider` (grep `ThemeProvider` in `src/main.tsx`/`__root.tsx`) to mount `PaletteProvider` inside it
- Modify: `dashboard/src/routes/_authed/account.tsx` (render `<AppearanceCard />` when `hasFeature(me, "themes")`)
- Create: `dashboard/src/locales/{en,ar}/appearance.json`

**Interfaces:**
- Produces:
  - `type PaletteName = "default" | "dracula" | "nord" | "sunset"`; `PALETTES: Record<Exclude<PaletteName,"default">, { light?: Tokens; dark: Tokens }>` where `Tokens` is a `Record<ColorToken, string>` of `#RRGGBB` for every colour token in `@etqan/tokens/tokens.css` (`background, foreground, card, card-foreground, popover, popover-foreground, primary, primary-foreground, primary-text, secondary, secondary-foreground, muted, muted-foreground, accent, accent-foreground, destructive, destructive-foreground, border, input, ring, success, success-foreground, warning, warning-foreground, info, info-foreground`, plus `overlay` in its `"#RRGGBB NN%"` shape).
  - `paletteCss(name): string` → CSS text: light tokens under `:root[data-theme="<name>"]:not(.dark)` **without** `--primary`, `--primary-foreground`, `--accent`, `--accent-foreground`, `--primary-text` (brand-owned); dark tokens under `:root[data-theme="<name>"].dark` without the first four but **with** `--primary-text`.
  - `PaletteProvider`, `usePalette(): { palette: PaletteName; setPalette(p): void; available: boolean }` — storage key `etqan-palette`; `available = hasFeature(me, "themes")` when signed in, `false` otherwise (pre-sign-in pages: Default, A-3).
  - `ThemeProvider` gains `forcedDark?: boolean` in context: `useTheme()` returns `{ theme, setTheme, forced }`; when forced, `<html>` gets `.dark` but `localStorage["etqan-theme"]` keeps the user's own value.

- [ ] **Step 1: Failing tests.**

`palettes.test.ts` (contrast; read `node_modules/@etqan/tokens/contrast.mjs` `resolveTheme` to see the object shape `evaluate` wants — if it takes the DTCG token tree, build it from the flat map with a small adapter in the test):

```ts
import { evaluate } from "@etqan/tokens/contrast.mjs";
import { describe, expect, it } from "vitest";
import { PALETTES, paletteCss } from "./palettes";

describe("named palettes", () => {
	for (const [name, modes] of Object.entries(PALETTES)) {
		for (const [mode, tokens] of Object.entries(modes)) {
			it(`${name} ${mode} passes WCAG AA`, () => {
				const report = evaluate(tokens as Record<string, unknown>, mode);
				expect(report.failures.map((f) => `${f.foreground} on ${f.surface}: ${f.ratio.toFixed(2)}`)).toEqual([]);
			});
		}
	}
	it("dracula has no light mode", () => {
		expect(PALETTES.dracula.light).toBeUndefined();
	});
	it("never sets brand variables in light mode", () => {
		const css = paletteCss("nord");
		const light = css.split(".dark")[0];
		expect(light).not.toMatch(/--primary(-foreground|-text)?:/);
		expect(light).not.toMatch(/--accent(-foreground)?:/);
		expect(css).toMatch(/\.dark\{[^}]*--primary-text:/);
	});
});
```

`palette.test.tsx`: renders `PaletteProvider` with a mocked `useMe` (`features: ["themes"]`) → `setPalette("nord")` sets `document.documentElement.dataset.theme === "nord"`, writes `etqan-palette`, injects one `<style id="etqan-palette">`; with `features: []` and `localStorage["etqan-palette"]="dracula"` → **ignores a stored named theme while the switch is off**: `dataset.theme` absent, `.dark` follows `etqan-theme`, `etqan-palette` still `"dracula"`; with Dracula on and `etqan-theme="light"` → `<html>` has `.dark`, `localStorage["etqan-theme"]` still `"light"`; switching back to Default removes `.dark`.

`AppearanceCard.test.tsx`: four radio cards; choosing Dracula disables the light/dark toggle's light option and shows the "Dracula is dark only" hint; labels come from `appearance.*`.

- [ ] **Step 2: Run** `pnpm vitest run src/features/appearance` (inside the dashboard container if that is how `just test-frontend` runs it — check the justfile) → FAIL.

- [ ] **Step 3: Implement.** Palettes (all pass AA; tune values until the contrast test is green — start from the public palettes):
  - **Dracula (dark):** background `#282A36`, card/popover `#303241`, foreground `#F8F8F2`, muted/secondary `#383A4A`, muted-foreground `#C3C6D4`, border `#44475A`, input `#8A8FA8`, ring `#BD93F9`, primary-text `#BD93F9`, destructive `#FF5555` (foreground `#282A36`), success `#50FA7B` (fg `#282A36`), warning `#F1FA8C` (fg `#282A36`), info `#8BE9FD` (fg `#282A36`).
  - **Nord:** light background `#ECEFF4`, card `#FFFFFF`, foreground `#2E3440`, muted `#E5E9F0`, muted-foreground `#4C566A`, border `#D8DEE9`, input `#7B88A1`; dark background `#2E3440`, card `#3B4252`, foreground `#ECEFF4`, muted `#434C5E`, muted-foreground `#D8DEE9`, border `#4C566A`, input `#8F9BB3`, primary-text `#88C0D0`.
  - **Sunset:** light background `#FFF5EE`, card `#FFFFFF`, foreground `#2B1B17`, muted `#FBE7DC`, muted-foreground `#6B4A3F`, border `#F0D5C6`, input `#A07E70`; dark background `#241615`, card `#2F1E1C`, foreground `#FBEDE6`, muted `#3A2624`, muted-foreground `#E2C2B5`, border `#4A302D`, input `#A5837A`, primary-text `#FFB38A`.
  - Brand tokens (`primary`, `primary-foreground`, `accent`, `accent-foreground`) in the palette objects are copied from Default (`tokens.css`) so the contrast check has values; `paletteCss` omits them.

  `PaletteProvider` writes `document.documentElement.dataset.theme` (removed for Default/unavailable) and one `<style id="etqan-palette">` holding `paletteCss` for the active palette only; tells `ThemeProvider` to force dark while Dracula is active (lift a `forcedDark` prop/state: simplest is a small context setter exported from `theme.tsx`, `useForceDark(on: boolean)`). `AppearanceCard` uses `RadioCardGroup` (from `@/ui`) for the four palettes plus the existing `ThemeToggle`.

  `appearance.json` (en): `{"title":"Appearance","palette":"Theme","default":"Default","dracula":"Dracula","nord":"Nord","sunset":"Sunset","darkOnly":"Dracula is dark only.","mode":"Mode"}`; ar: `{"title":"المظهر","palette":"القالب","default":"الافتراضي","dracula":"دراكولا","nord":"نورد","sunset":"الغروب","darkOnly":"قالب دراكولا داكن فقط.","mode":"الوضع"}`.

- [ ] **Step 4: Run** `just test-frontend` and the dashboard's vitest with coverage (see `dashboard/package.json` scripts) → PASS; `just lint`.
- [ ] **Step 5: Commit** in `dashboard/` (`feat(appearance): named themes behind the themes switch (B9a)`).

---

### Task 8: File library screen (dashboard)

**Files:**
- Create: `dashboard/src/features/library/{api.ts,queries.ts,schemas.ts,LibraryList.tsx,UploadDialog.tsx,index.ts}` + tests `LibraryList.test.tsx`, `UploadDialog.test.tsx`, `schemas.test.ts`
- Create: `dashboard/src/routes/_authed/library.tsx`
- Modify: `dashboard/src/features/shell/nav.ts` (under `// ── phase B9 ──`)
- Create: `dashboard/src/locales/{en,ar}/library.json`

**Interfaces:**
- Consumes: `GET/POST /api/v1/library/`, `DELETE /api/v1/library/<id>/`, `POST /api/v1/library/bulk-delete/` (Task 3 shapes).
- Produces: `libraryApi.{list(q, page), upload(name, file), remove(id), bulkRemove(ids)}`; zod `libraryFileSchema`; `LIBRARY_MAX_BYTES = 20 * 1024 * 1024`.

- [ ] **Step 1: Failing tests** (mock `@/lib/api` like `src/features/website/*.test.tsx` do): list renders name, human size (`1.2 MB`), uploader, date; search input debounced → `list("syl", 1)`; selecting two rows enables "Delete selected" → confirm dialog → `bulkRemove([1,2])` and toast; "Copy link" calls `navigator.clipboard.writeText(url)`; UploadDialog prefills the name from the chosen file, refuses a 21 MB file client-side with the `library.tooLarge` message and never calls `upload`; a 400 `{file: ["..."]}` shows under the file field; buttons hidden when `can("library_file.create")`/`delete`/`delete_any` is false.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** following `features/website` (api.ts with `toFormData`-style multipart, queries with `useInfiniteQuery` or paged `useQuery` as `InquiriesList` does, `Card`/`EmptyState`/`AlertDialog`/`Dialog`/`Field`/`Input`/`Checkbox`/`Button` from `@/ui`). Route:

```tsx
export const Route = createFileRoute("/_authed/library")({
	staticData: { permission: "library_file.view_any", feature: "file_uploads" },
	beforeLoad: ({ context }) => requireOffice(context),
	component: function LibraryRoute() {
		const { t } = useTranslation();
		usePageTitle(t("library.title"));
		return (
			<PageContainer>
				<PageHeader title={t("library.title")} description={t("library.subtitle")} />
				<LibraryList />
			</PageContainer>
		);
	},
});
```

Nav, under `// ── phase B9 ──` (pick a lucide icon such as `FolderOpen`; import it at the top of `nav.ts`):

```ts
	// ── phase B9 ──
	office("/library", "library.nav", FolderOpen, "settings", "library_file.view_any", "file_uploads"),
```

`library.json` en: `title "Files"`, `subtitle "Upload files and copy their links into your content."`, `nav "Files"`, `upload`, `name`, `file`, `size`, `uploadedBy`, `date`, `copyLink`, `copied`, `delete`, `deleteSelected`, `confirmDelete` ("Delete {{count}} file(s)? Links to them stop working."), `empty`, `search`, `tooLarge` ("Files can be at most 20 MB."), `accepted` ("Images, PDF, Word, Excel, PowerPoint, text, CSV, MP3, M4A, MP4"); ar equivalents with the same keys. Run `pnpm generate-routes` / the router plugin as the repo does (regenerate `routeTree.gen.ts`, never hand-edit).
- [ ] **Step 4: Run** tests + `just test-frontend` + `just lint` → PASS.
- [ ] **Step 5: Commit** (`feat(library): file library screen (B9a)`).

---

### Task 9: Contracts screens (dashboard)

**Files:**
- Create: `dashboard/src/features/employment/{api.ts,queries.ts,schemas.ts,ContractsList.tsx,ContractDialog.tsx,MyContractsCard.tsx,index.ts}` + tests
- Create: `dashboard/src/routes/_authed/people.contracts.tsx`
- Modify: `dashboard/src/routes/_authed/people.teachers.$personId.tsx` (a "Contracts" link to `/people/contracts?teacher=<id>` when `hasFeature(me,"contracts") && can("contract.view_any")`)
- Modify: `dashboard/src/routes/_authed/account.tsx` (`<MyContractsCard />` for `me.role === "teacher"` with the feature on)
- Modify: `nav.ts` (B9 marker)
- Create: `dashboard/src/locales/{en,ar}/contracts.json`

**Interfaces:**
- Consumes: Task 4 routes and item shape; the teachers list `GET /api/v1/people/teachers/` (existing people feature query — reuse its hook for the picker).
- Produces: `employmentApi.{list({teacher,q,page}), get(id), create(form), update(id, form), remove(id), download(id)}`; `download` fetches `contracts/<id>/file/` with `responseType: "blob"` and saves with the `file_name` (an object URL + temporary `<a download>`), never navigates to a URL.

- [ ] **Step 1: Failing tests:** list with teacher filter from the `?teacher=` search param; create dialog requires a teacher and "details or file" (`contracts.detailsOrFile` message, client-side, mirrored from the server rule) and posts multipart; edit dialog with "Remove file" checkbox; a 400 `non_field_errors` is shown; delete confirm; download calls `employmentApi.download` and creates an object URL; create button hidden unless `can("contract.create") && can("teacher.view_any")`; `MyContractsCard` lists the teacher's contracts read-only with download and no edit controls.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Route `/_authed/people/contracts` with `staticData: { permission: "contract.view_any", feature: "contracts" }`, `validateSearch` for `teacher?: number`. Nav under the B9 marker: `office("/people/contracts", "contracts.nav", FileSignature, "people", "contract.view_any", "contracts"),`. `contracts.json` en keys: `nav "Contracts"`, `title "Employment contracts"`, `subtitle`, `teacher`, `reference`, `details`, `file`, `removeFile`, `hasFile`, `noFile`, `download`, `add`, `edit`, `delete`, `confirmDelete`, `detailsOrFile` ("Enter the details or attach the contract file."), `mine` ("My contracts"), `empty`, `accepted` ("PDF, Word (.docx) or an image, up to 10 MB"), `tooLarge`; ar with the same keys.
- [ ] **Step 4: Run** tests, `just test-frontend`, `just lint` → PASS.
- [ ] **Step 5: Commit** (`feat(employment): contracts screens and My contracts (B9a)`).

---

### Task 10: System status screen (dashboard)

**Files:**
- Create: `dashboard/src/features/systemstatus/{api.ts,queries.ts,schemas.ts,SystemStatusPage.tsx,index.ts}` + tests
- Create: `dashboard/src/routes/_authed/settings.system-status.tsx`
- Modify: `nav.ts` (B9 marker)
- Create: `dashboard/src/locales/{en,ar}/systemStatus.json`

**Interfaces:**
- Consumes: Task 5 `GET /api/v1/system-status/`, `POST /api/v1/system-status/runs/`.
- Produces: `useSystemStatus()` — `refetchInterval: (q) => q.state.data?.runs.some(r => r.status === "queued" || r.status === "running") ? 5000 : false`; `useRequestRun()`.

- [ ] **Step 1: Failing tests:** facts rendered (version, subdomain, timezone, academy time formatted in the academy timezone, server UTC, features on, jobs with translated schedule); button posts `{job:"reconcile_subscriptions"}` and is disabled while a run is open; a 409 shows `systemStatus.runOpen`; the runs table shows status chips (`queued`/`running`/`ok`/`failed`) with counts for `ok` (`created`, `expired`, `paused`, `resumed`) and the error for `failed`; polling: with an open run the query refetches after 5 s (fake timers), and stops once `ok`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Route `/_authed/settings/system-status`, `staticData: { permission: "page.system_status", feature: "system_status" }`, `beforeLoad: requireOffice`. Nav: `office("/settings/system-status", "systemStatus.nav", Activity, "settings", "page.system_status", "system_status"),` under the B9 marker. If `settings.index.tsx` lists settings cards from a static array, add a card only if that array is built from `NAV_ITEMS` (otherwise leave it — the nav entry is enough). `systemStatus.json` keys: `nav`, `title`, `subtitle`, `version`, `subdomain`, `timezone`, `academyTime`, `serverTime`, `featuresOn`, `jobs`, `schedule.hourly`, `schedule.every_minute`, `job.reconcile_subscriptions`, `job.notifications`, `runNow` ("Reconcile subscriptions now"), `runHelp` ("Applies pauses, expires due subscriptions and generates upcoming sessions, as the hourly job does."), `runOpen`, `runs`, `status.queued|running|ok|failed`, `counts` ("{{created}} sessions created, {{expired}} expired, {{paused}} paused, {{resumed}} resumed"), `requestedBy`, `empty`.
- [ ] **Step 4: Run** tests, `just test-frontend`, `just lint` → PASS.
- [ ] **Step 5: Commit** (`feat(systemstatus): system status screen (B9a)`).

---

### Task 11: End-to-end journey

**Files:**
- Create: `dashboard/e2e/b9-platform.spec.ts`
- Possibly create: `dashboard/e2e/fixtures/b9/contract.pdf` (tiny `%PDF-1.4` file) and `syllabus.pdf`

**Interfaces:**
- Consumes: `login`, `DEMO_URL`, `DEMO_ADMIN`, `DEV_PASSWORD` from `e2e/fixtures.ts`; `manage()` from `e2e/manage.ts`; seeded teachers `bilal@demo.test`, `maryam@demo.test` (check they can sign in with `DEV_PASSWORD` the way other specs sign teachers in — grep `bilal@demo.test` in `e2e/`).

- [ ] **Step 1: Write the spec** (it fails until the stack runs this branch):

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, login } from "./fixtures";
import { manage } from "./manage";

const SWITCHES = ["file_uploads", "contracts", "themes", "system_status"];

test.describe("B9a platform", () => {
	test.beforeAll(() => {
		manage("set_features", "demo", ...SWITCHES.flatMap((s) => ["--on", s]));
	});

	test("admin uploads a file and opens its link", async ({ page, request }) => {
		await login(page, DEMO_URL, DEMO_ADMIN);
		await page.goto(`${DEMO_URL}/app/library`);
		await page.getByRole("button", { name: /upload/i }).click();
		await page.getByLabel(/file/i).setInputFiles({ name: "syllabus.pdf", mimeType: "application/pdf", buffer: Buffer.from("%PDF-1.4\n% e2e\n") });
		await page.getByRole("button", { name: /^upload$/i }).click();
		const row = page.getByRole("row", { name: /syllabus/i });
		await expect(row).toBeVisible();
		await page.context().grantPermissions(["clipboard-read", "clipboard-write"]);
		await row.getByRole("button", { name: /copy link/i }).click();
		const url = await page.evaluate(() => navigator.clipboard.readText());
		const res = await request.get(url);
		expect(res.status()).toBe(200);
		expect((await res.body()).toString()).toContain("%PDF-1.4");
	});

	test("contract file reaches its teacher only", async ({ browser }) => {
		const admin = await browser.newPage();
		await login(admin, DEMO_URL, DEMO_ADMIN);
		await admin.goto(`${DEMO_URL}/app/people/contracts`);
		await admin.getByRole("button", { name: /add/i }).click();
		await admin.getByLabel(/teacher/i).selectOption({ label: "Ustadha Maryam" });
		await admin.getByLabel(/reference/i).fill("E2E-1");
		await admin.getByLabel(/^file/i).setInputFiles({ name: "e2e-contract.pdf", mimeType: "application/pdf", buffer: Buffer.from("%PDF-1.4\n% contract\n") });
		await admin.getByRole("button", { name: /save/i }).click();
		await expect(admin.getByRole("row", { name: /E2E-1/ })).toBeVisible();

		const maryam = await browser.newPage();
		await login(maryam, DEMO_URL, "maryam@demo.test");
		await maryam.goto(`${DEMO_URL}/app/account`);
		const download = maryam.waitForEvent("download");
		await maryam.getByRole("row", { name: /E2E-1/ }).getByRole("button", { name: /download/i }).click();
		expect((await download).suggestedFilename()).toBe("e2e-contract.pdf");

		const bilal = await browser.newPage();
		await login(bilal, DEMO_URL, "bilal@demo.test");
		await bilal.goto(`${DEMO_URL}/app/account`);
		await expect(bilal.getByText("E2E-1")).toHaveCount(0);
	});

	test("admin runs reconcile now and sees it finish", async ({ page }) => {
		await login(page, DEMO_URL, DEMO_ADMIN);
		await page.goto(`${DEMO_URL}/app/settings/system-status`);
		await page.getByRole("button", { name: /reconcile subscriptions now/i }).click();
		await expect(page.getByText(/sessions created/i).first()).toBeVisible({ timeout: 60_000 });
	});

	test("a chosen theme survives a reload", async ({ page }) => {
		await login(page, DEMO_URL, DEMO_ADMIN);
		await page.goto(`${DEMO_URL}/app/account`);
		await page.getByRole("radio", { name: /nord/i }).check();
		await page.reload();
		await expect(page.locator("html")).toHaveAttribute("data-theme", "nord");
	});
});
```

Adjust labels/roles to the real components built in Tasks 7–10 (read them); keep the assertions. If teachers have no known password in the seed, sign them in the way existing specs do (e.g. via `acceptInvite` or a `manage` command) — never add a test-only HTTP route.

- [ ] **Step 2: Run** with the stack up on this branch: `just dev-backend` (wait until healthy), `just migrate`, `just seed`, then `just e2e e2e/b9-platform.spec.ts` → PASS. Then the whole suite: `just e2e` → PASS (the B9 switches stay on for `demo` afterwards; check no existing spec depends on them being off — `features.spec.ts` toggles `families` only).
- [ ] **Step 3: Commit** (`test(e2e): B9a platform journey`).

---

## Final checks (before queuing)

- [ ] `just test` (backend coverage ≥ 80, dashboard coverage gates), `just lint`, `just e2e` all green.
- [ ] Whole-slice review by a fresh reviewer against the spec; fix critical/important; log minors in `../_ledger/orchestration/phases/B9.md`.
- [ ] `python3 scripts/orchestration/ledger.py queue B9a`.
