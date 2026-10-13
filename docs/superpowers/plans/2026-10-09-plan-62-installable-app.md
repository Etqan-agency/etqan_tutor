# Plan 62 — B11a installable app — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** B11a (phase B11, Apps). **Requires:** — (no other phase's slice; builds on merged B8a `site.Branding`,
B9 `me.features`, Plan 13 switches).

**Goal:** When an academy turns `installable_app` on, every signed-in user can install the dashboard as a desktop or
home-screen app with the academy's name, colours and an icon made from its logo, and gets an offline page instead
of a browser error.

**Architecture:** A new tenant app `etqan.devices` serves a per-academy web manifest and PNG icons anonymously
(plain Django responses inside DRF views). The dashboard reads `me.features` strictly and, when the switch is on,
adds the manifest/icon/theme tags to `<head>` and registers `/app/sw.js` (scope `/app/`), a worker that caches only
`/app/offline.html` and answers failed navigations with it; when off it removes tags, unregisters and drops caches.
An "Install the app" card on the account page explains installing per platform.

**Tech Stack:** Django 5 + DRF, Pillow, django-tenants cache; React 19 + TanStack Router, react-i18next, vitest +
Testing Library, Playwright.

**Spec:** `docs/superpowers/specs/2026-10-09-b11-apps-design.md` (§4 phase decisions, §5–§10 B11a). Read both.

## Global Constraints

- Every new line in a shared list goes under `── phase B11 ──` (TENANT_APPS, `config/api_router.py`, feature
  registry, `pyproject.toml` platform forbidden list and contracts section). Outside markers, only the four
  one-line dashboard edits named in spec §8 (main.tsx, `_authed.tsx`, `_authed/account.tsx`, `FeatureCode` union).
- Switch: `installable_app`, "Installable app (desktop and mobile)" / "تطبيق قابل للتثبيت (سطح المكتب والجوال)",
  group `platform`, `built=True`, `default=False`, no `requires`.
- No model, no migration in B11a (A-9).
- Manifest: `GET /api/v1/devices/manifest.webmanifest`, `application/manifest+json`, `Cache-Control: public,
  max-age=300` on 200 only. Icons: `GET /api/v1/devices/icons/<kind>.png`, kind ∈ `192`, `512`, `maskable-512`,
  `apple-touch-180`, `image/png`, `Cache-Control: public, max-age=86400` on 200 only. Both anonymous; `404` while off.
- Logo share of the side: 70 %; `maskable-512`: 56 %. Letter: 50 % of the side, `primary_text`, DejaVuSans bundled in
  `etqan/devices/fonts/`. Fallback colour `#0E7C66`.
- Worker cache names start `devices-`; only navigations under `/app/` are handled; `skipWaiting()` + `clients.claim()`.
- Strings only in new `dashboard/src/locales/{en,ar}/apps.json` (keys equal in both).
- Backend coverage ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70. TDD.
- Never run `manage.py`, `migrate` or e2e outside `just` (the stream's `.env.stream` is what points them at this
  stack). There is no host venv or `node_modules`: every test runs in this stream's containers through `just`, which
  loads `.env.stream`. Targeted runs (from the worktree root):
  - backend: `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django pytest <paths> -q`
  - dashboard: `just _compose run --rm dashboard pnpm vitest run <paths>` (also `pnpm tsc --noEmit`, `pnpm lint`)
  - import boundaries: `just check-boundaries`
  Never call `docker compose` directly: without `.env.stream` it would reach the owner's stack.
- Memory rule (conductor, 2026-10-09): the stack and images are built/started only in a memory window the conductor
  grants; the orchestrator asks before the first test run and stops the stack (`just stop`) when the window ends.
  Implementers do not start or stop stacks themselves; they run the targeted commands above when told the stack is up.

## Review Focus

1. **Anonymous fetch with the switch off or a missing `Branding` row** — expect `404` (off) and never a 500 (no row:
   defaults created). Pinned in Task 1.
2. **A logo that is huge, corrupt, or deleted from storage** — expect the letter icon, a logged warning, no 500.
   Pinned in Task 2.
3. **An Arabic-default academy** — manifest `lang: "ar"`, `dir: "rtl"`, Arabic name, and the letter icon draws a real
   glyph (non-background pixels at the centre), not tofu/blank. Pinned in Tasks 1–2.
4. **`me` still loading, or `me.features` missing** — the dashboard must neither add tags/register nor unregister.
   Pinned in Task 3.
5. **iPad Safari (reports `MacIntel` with touch)** — gets the iOS "Add to Home Screen" steps, not macOS "Add to
   Dock". Pinned in Task 4.

---

### Task 1: `etqan.devices` app, switch, branding snapshot and manifest

**Files:**
- Create: `backend/etqan/devices/__init__.py`, `backend/etqan/devices/apps.py`, `backend/etqan/devices/services.py`,
  `backend/etqan/devices/api/__init__.py`, `backend/etqan/devices/api/urls.py`, `backend/etqan/devices/api/views.py`,
  `backend/etqan/devices/tests/__init__.py`, `backend/etqan/devices/tests/test_manifest.py`,
  `backend/etqan/site/tests/test_branding_snapshot.py`
- Modify: `backend/etqan/site/services.py` (append `BrandingSnapshot`, `branding_snapshot`) — under a ledger claim on
  `site` (orchestrator takes `ledger.py claim site --phase B11 --reason "B11a branding_snapshot"` before, `release`
  after the commit)
- Modify: `backend/etqan/platform/features.py` (under `# ── phase B11 ──`), `backend/config/settings/base.py`
  (TENANT_APPS under `# ── phase B11 ──`), `backend/config/api_router.py` (under `# ── phase B11 ──`),
  `backend/pyproject.toml` (platform forbidden list under `# ── phase B11 ──` at ~line 103; contracts under
  `# ── phase B11 ──` at ~line 758)

**Interfaces:**
- Produces: `site.services.BrandingSnapshot(name_ar: str, name_en: str, primary_color: str, primary_text: str,
  logo_name: str, updated_at: datetime)` (frozen dataclass); `site.services.branding_snapshot() -> BrandingSnapshot`.
- Produces: `devices.services.SWITCH = "installable_app"`, `DEFAULT_PRIMARY = "#0E7C66"`,
  `ICON_KINDS: dict[str, tuple[int, float, str]]` (`kind -> (size, logo_share, purpose)`),
  `require_on() -> None` (raises `NotFoundError("App")`), `app_name(snapshot, language: str) -> str`,
  `version(snapshot) -> int` (epoch seconds), `manifest() -> dict`.
- Produces: URL names `devices:manifest`, `devices:icon` (the icon route itself lands in Task 2).

- [ ] **Step 1: Write the failing tests**

`backend/etqan/site/tests/test_branding_snapshot.py`:

```python
import pytest
from django.db import connection

from etqan.site.models import Branding
from etqan.site.services import BrandingSnapshot
from etqan.site.services import branding_snapshot


@pytest.mark.django_db
def test_snapshot_creates_defaults_when_missing():
    Branding.objects.all().delete()
    snap = branding_snapshot()
    assert isinstance(snap, BrandingSnapshot)
    assert snap.name_en == connection.tenant.name
    assert snap.logo_name == ""
    assert snap.primary_color == "#0E7C66"


@pytest.mark.django_db
def test_snapshot_reads_branding(django_assert_max_num_queries):
    branding_snapshot()  # creates defaults if needed
    Branding.objects.update(name_en="Noor", name_ar="نور", primary_color="#123456")
    with django_assert_max_num_queries(4):
        snap = branding_snapshot()
    assert (snap.name_en, snap.name_ar, snap.primary_color) == ("Noor", "نور", "#123456")
    assert snap.updated_at is not None
```

`backend/etqan/devices/tests/test_manifest.py`:

```python
import pytest
from rest_framework.test import APIClient

from etqan.academy import services as academy_services
from etqan.site.models import Branding
from etqan.site.services import branding_snapshot

URL = "/api/v1/devices/manifest.webmanifest"
OTHER = "pytest-other.etqan.localhost"


@pytest.fixture
def on(set_features):
    set_features(installable_app=True)
    branding_snapshot()
    Branding.objects.update(name_en="Noor Academy", name_ar="أكاديمية نور", primary_color="#123456")


@pytest.mark.django_db
def test_off_is_404_without_cache_header(set_features):
    set_features(installable_app=False)
    resp = APIClient().get(URL)
    assert resp.status_code == 404
    assert "public" not in resp.get("Cache-Control", "")


@pytest.mark.django_db
def test_manifest_english(on):
    academy_services.update_settings(default_language="en")
    resp = APIClient().get(URL)
    assert resp.status_code == 200
    assert resp["Content-Type"] == "application/manifest+json"
    assert resp["Cache-Control"] == "public, max-age=300"
    data = resp.json()
    assert data["id"] == data["start_url"] == data["scope"] == "/app/"
    assert data["display"] == "standalone"
    assert data["name"] == data["short_name"] == "Noor Academy"
    assert (data["lang"], data["dir"]) == ("en", "ltr")
    assert data["theme_color"] == "#123456"
    assert data["background_color"] == "#FFFFFF"
    srcs = [(i["src"].split("?")[0], i["sizes"], i["purpose"]) for i in data["icons"]]
    assert srcs == [
        ("/api/v1/devices/icons/192.png", "192x192", "any"),
        ("/api/v1/devices/icons/512.png", "512x512", "any"),
        ("/api/v1/devices/icons/maskable-512.png", "512x512", "maskable"),
    ]
    assert all(i["type"] == "image/png" and "?v=" in i["src"] for i in data["icons"])


@pytest.mark.django_db
def test_manifest_arabic_rtl(on):
    academy_services.update_settings(default_language="ar")
    data = APIClient().get(URL).json()
    assert (data["name"], data["lang"], data["dir"]) == ("أكاديمية نور", "ar", "rtl")


@pytest.mark.django_db
def test_blank_name_falls_back_to_other_language(on):
    academy_services.update_settings(default_language="ar")
    Branding.objects.update(name_ar="")
    assert APIClient().get(URL).json()["name"] == "Noor Academy"


@pytest.mark.django_db
def test_invalid_colour_falls_back(on):
    Branding.objects.update(primary_color="red")
    assert APIClient().get(URL).json()["theme_color"] == "#0E7C66"


@pytest.mark.django_db
def test_missing_branding_row_is_not_500(set_features):
    set_features(installable_app=True)
    Branding.objects.all().delete()
    assert APIClient().get(URL).status_code == 200


@pytest.mark.django_db
def test_per_academy(on, set_features, tenants):
    set_features(academy="other", installable_app=False)
    assert APIClient().get(URL, HTTP_HOST=OTHER).status_code == 404
    assert APIClient().get(URL).status_code == 200
```

Check `update_settings`'s real keyword signature in `backend/etqan/academy/services.py:49` and the
`set_features(academy=...)` argument form in `backend/conftest.py` (`switch(*, academy=None, **values)`; `academy`
is a fixture attribute name such as `"other"` or the Academy — read it) before running; adjust the calls, not the
assertions.

- [ ] **Step 2: Run tests to verify they fail**

Run: `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django pytest etqan/site/tests/test_branding_snapshot.py etqan/devices -q`
Expected: FAIL (ImportError: `branding_snapshot`, then 404 for the route).

- [ ] **Step 3: Implement**

Append to `backend/etqan/site/services.py` (keep its import style: one `from x import y` per line; add
`from dataclasses import dataclass` at the top):

```python
@dataclass(frozen=True)
class BrandingSnapshot:
    """What an installed app needs from the academy's branding (B11a §7.2)."""

    name_ar: str
    name_en: str
    primary_color: str
    primary_text: str
    logo_name: str
    updated_at: datetime


def branding_snapshot() -> BrandingSnapshot:
    """The academy's branding, creating the defaults first (an anonymous
    manifest fetch must never 500 on a new academy, as BrandingView)."""
    ensure_site_defaults(connection.tenant.name)
    branding = Branding.load()
    return BrandingSnapshot(
        name_ar=branding.name_ar,
        name_en=branding.name_en,
        primary_color=branding.primary_color,
        primary_text=branding.primary_text,
        logo_name=branding.logo.name or "",
        updated_at=branding.updated_at,
    )
```

`backend/etqan/devices/apps.py`:

```python
from django.apps import AppConfig


class DevicesConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.devices"
    label = "devices"
```

`backend/etqan/devices/services.py`:

```python
"""Phase B11 apps (spec 2026-10-09-b11-apps). B11a: the installable web app's
manifest and icons, per academy, read anonymously."""

import re

from etqan.academy import services as academy_services
from etqan.platform import features
from etqan.platform.exceptions import NotFoundError
from etqan.site import services as site_services

SWITCH = "installable_app"
DEFAULT_PRIMARY = "#0E7C66"
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
# kind -> (side in px, share of the side the logo may fill, manifest purpose).
ICON_KINDS = {
    "192": (192, 0.70, "any"),
    "512": (512, 0.70, "any"),
    "maskable-512": (512, 0.56, "maskable"),
    "apple-touch-180": (180, 0.70, "any"),
}
MANIFEST_ICONS = ("192", "512", "maskable-512")
ICON_URL = "/api/v1/devices/icons/{kind}.png?v={version}"


def require_on() -> None:
    if not features.enabled(SWITCH):
        raise NotFoundError("App")


def colour(value: str, default: str = DEFAULT_PRIMARY) -> str:
    return value if HEX.match(value or "") else default


def app_name(snapshot, language: str) -> str:
    first, second = (
        (snapshot.name_ar, snapshot.name_en)
        if language == "ar"
        else (snapshot.name_en, snapshot.name_ar)
    )
    return (first or "").strip() or (second or "").strip()


def version(snapshot) -> int:
    return int(snapshot.updated_at.timestamp())


def manifest() -> dict:
    require_on()
    snapshot = site_services.branding_snapshot()
    language = academy_services.get_settings().default_language
    name = app_name(snapshot, language)
    v = version(snapshot)
    return {
        "id": "/app/",
        "start_url": "/app/",
        "scope": "/app/",
        "display": "standalone",
        "name": name,
        "short_name": name,
        "lang": language,
        "dir": "rtl" if language == "ar" else "ltr",
        "theme_color": colour(snapshot.primary_color),
        "background_color": "#FFFFFF",
        "icons": [
            {
                "src": ICON_URL.format(kind=kind, version=v),
                "sizes": f"{ICON_KINDS[kind][0]}x{ICON_KINDS[kind][0]}",
                "type": "image/png",
                "purpose": ICON_KINDS[kind][2],
            }
            for kind in MANIFEST_ICONS
        ],
    }
```

`backend/etqan/devices/api/views.py`:

```python
from django.http import JsonResponse
from rest_framework.permissions import AllowAny
from rest_framework.views import APIView

from etqan.devices import services


class PublicAppView(APIView):
    """Anonymous: browsers fetch manifests and icons without cookies (A-1)."""

    authentication_classes = ()
    permission_classes = (AllowAny,)


class ManifestView(PublicAppView):
    def get(self, request, *args, **kwargs):
        response = JsonResponse(
            services.manifest(),
            content_type="application/manifest+json",
            json_dumps_params={"ensure_ascii": False},
        )
        response["Cache-Control"] = "public, max-age=300"
        return response
```

`backend/etqan/devices/api/urls.py`:

```python
from django.urls import path

from etqan.devices.api import views

app_name = "devices"
urlpatterns = [
    path("manifest.webmanifest", views.ManifestView.as_view(), name="manifest"),
]
```

`backend/config/api_router.py`, under `# ── phase B11 ──`:

```python
    # manifest.webmanifest, icons/<kind>.png (B11a spec §7).
    path("devices/", include("etqan.devices.api.urls")),
```

`backend/config/settings/base.py` TENANT_APPS, under `# ── phase B11 ──`: `"etqan.devices",`

`backend/etqan/platform/features.py`, under `# ── phase B11 ──`:

```python
    # B11a
    Feature(
        "installable_app",
        "Installable app (desktop and mobile)",
        "تطبيق قابل للتثبيت (سطح المكتب والجوال)",
        "platform",
        built=True,
        default=False,
    ),
```

`backend/pyproject.toml`: in the platform contract's forbidden list under `# ── phase B11 ──` add `"etqan.devices",`.
Under the contracts section's `# ── phase B11 ──` add:

```toml
[[tool.importlinter.contracts]]
name = "devices reaches other apps only through their services"
type = "forbidden"
# B11-8: other apps' services only. The packages are forbidden whole and the
# services imports let through in ignore_imports.
source_modules = ["etqan.devices"]
forbidden_modules = [
    "etqan.identity", "etqan.academy", "etqan.catalogue", "etqan.scheduling",
    "etqan.learning", "etqan.integrations", "etqan.tenants", "etqan.site",
    "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access",
    "etqan.finance", "etqan.gateways", "etqan.wallet", "etqan.employment",
    "etqan.library", "etqan.registration", "etqan.systemstatus",
    "etqan.translations", "etqan.etqan_billing", "etqan.ai", "etqan.chat",
    "etqan.recorded", "etqan.consultations", "etqan.vouchers",
]
allow_indirect_imports = true
ignore_imports = [
    # B11a: branding and the default language (spec §7.2, A-2).
    "etqan.devices.** -> etqan.site.services",
    "etqan.devices.** -> etqan.academy.services",
    # The tests build fixtures from other apps' models and helpers.
    "etqan.devices.tests.** -> etqan.**",
]

[[tool.importlinter.contracts]]
name = "no app imports devices"
type = "forbidden"
# B11-8: devices reads the other apps; none of them calls it.
source_modules = [
    "etqan.identity", "etqan.catalogue", "etqan.academy", "etqan.site", "etqan.tenants",
    "etqan.scheduling", "etqan.billing", "etqan.payroll", "etqan.notifications", "etqan.access",
    "etqan.finance", "etqan.gateways", "etqan.wallet", "etqan.learning", "etqan.employment",
    "etqan.library", "etqan.registration", "etqan.systemstatus", "etqan.translations",
    "etqan.integrations", "etqan.ai", "etqan.chat", "etqan.recorded", "etqan.consultations",
    "etqan.vouchers", "etqan.etqan_billing",
]
forbidden_modules = ["etqan.devices"]
allow_indirect_imports = true
```

If `lint-imports` reports an `ignore_imports` line that matches nothing (it fails on those), drop that line; if a
listed source/forbidden module does not exist, remove it from the list.

- [ ] **Step 4: Run tests to verify they pass**

Run: `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django pytest etqan/site/tests/test_branding_snapshot.py etqan/devices etqan/platform/tests/test_features.py etqan/platform/tests/test_phase_sections.py -q && just check-boundaries`
Expected: PASS. If `test_features.py` pins a registry count/snapshot, update it for the new line only.

- [ ] **Step 5: Commit**

Backend repo: commit the `site/services.py` + its test as their own commit first (`feat(site): branding_snapshot read
service for B11a`), then the rest (`feat(devices): installable_app switch and per-academy web manifest (B11a)`).
Each message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

---

### Task 2: App icons from the academy logo

**Files:**
- Create: `backend/etqan/devices/icons.py`, `backend/etqan/devices/fonts/DejaVuSans.ttf` and
  `backend/etqan/devices/fonts/LICENSE` (copy both from `backend/etqan/etqan_billing/fonts/`),
  `backend/etqan/devices/tests/test_icons.py`
- Modify: `backend/etqan/devices/services.py` (add `icon`), `backend/etqan/devices/api/views.py` (add `IconView`),
  `backend/etqan/devices/api/urls.py` (add route)

**Interfaces:**
- Consumes: Task 1's `require_on`, `ICON_KINDS`, `colour`, `app_name`, `version`, `DEFAULT_PRIMARY`,
  `site.services.branding_snapshot`.
- Produces: `devices.icons.render(*, size: int, share: float, background: str, foreground: str, letter: str,
  logo_name: str) -> bytes`; `devices.services.icon(kind: str) -> bytes`; route `icons/<str:kind>.png` named
  `devices:icon`.

- [ ] **Step 1: Write the failing tests**

`backend/etqan/devices/tests/test_icons.py`:

```python
import io

import pytest
from django.core.cache import cache
from django.core.files.base import ContentFile
from PIL import Image
from rest_framework.test import APIClient

from etqan.academy import services as academy_services
from etqan.devices import icons
from etqan.site.models import Branding
from etqan.site.services import branding_snapshot


def png(colour=(255, 0, 0, 255), size=(40, 20)):
    out = io.BytesIO()
    Image.new("RGBA", size, colour).save(out, "PNG")
    return out.getvalue()


def opened(data: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(data))
    image.load()
    return image


@pytest.fixture
def on(set_features):
    cache.clear()
    set_features(installable_app=True)
    branding_snapshot()
    Branding.objects.update(name_en="Noor", name_ar="نور", primary_color="#123456", primary_text="#FFFFFF")


@pytest.mark.django_db
@pytest.mark.parametrize(("kind", "side"), [("192", 192), ("512", 512), ("maskable-512", 512), ("apple-touch-180", 180)])
def test_each_kind_is_a_png_of_its_size(on, kind, side):
    resp = APIClient().get(f"/api/v1/devices/icons/{kind}.png")
    assert resp.status_code == 200
    assert resp["Content-Type"] == "image/png"
    assert resp["Cache-Control"] == "public, max-age=86400"
    image = opened(resp.content)
    assert image.format == "PNG"
    assert image.size == (side, side)
    assert image.convert("RGB").getpixel((0, 0)) == (0x12, 0x34, 0x56)


@pytest.mark.django_db
def test_unknown_kind_and_off_are_404(on, set_features):
    assert APIClient().get("/api/v1/devices/icons/64.png").status_code == 404
    set_features(installable_app=False)
    assert APIClient().get("/api/v1/devices/icons/192.png").status_code == 404


@pytest.mark.django_db
def test_logo_is_centred_inside_its_share(on):
    branding = Branding.objects.get()
    branding.logo.save("logo.png", ContentFile(png()), save=True)
    image = opened(APIClient().get("/api/v1/devices/icons/512.png").content).convert("RGB")
    assert image.getpixel((256, 256)) == (255, 0, 0)  # the logo
    # 40x20 scaled into 70% of 512 = 358 wide, 179 high, centred.
    assert image.getpixel((256, 256 - 100)) == (0x12, 0x34, 0x56)
    assert image.getpixel((256 - 170, 256)) == (255, 0, 0)
    assert image.getpixel((256 - 190, 256)) == (0x12, 0x34, 0x56)


@pytest.mark.django_db
def test_maskable_logo_is_smaller(on):
    branding = Branding.objects.get()
    branding.logo.save("logo.png", ContentFile(png()), save=True)
    image = opened(APIClient().get("/api/v1/devices/icons/maskable-512.png").content).convert("RGB")
    # 56% of 512 = 286 wide: x = 256 - 160 is outside the logo.
    assert image.getpixel((256 - 160, 256)) == (0x12, 0x34, 0x56)


def _has_glyph(image: Image.Image, background) -> bool:
    centre = image.convert("RGB").crop((64, 64, 128, 128))
    return any(pixel != background for pixel in centre.getdata())


@pytest.mark.django_db
def test_letter_without_logo_arabic(on):
    academy_services.update_settings(default_language="ar")
    image = opened(APIClient().get("/api/v1/devices/icons/192.png").content)
    assert _has_glyph(image, (0x12, 0x34, 0x56))


def test_render_arabic_letter_is_a_real_glyph():
    """Tofu would be an outlined box; compare with a letter that does not exist
    in the font's Arabic coverage being drawn: the Arabic glyph must differ from
    the notdef glyph."""
    arabic = opened(icons.render(size=192, share=0.7, background="#000000", foreground="#FFFFFF", letter="ن", logo_name=""))
    notdef = opened(icons.render(size=192, share=0.7, background="#000000", foreground="#FFFFFF", letter="￿", logo_name=""))
    assert _has_glyph(arabic, (0, 0, 0))
    assert arabic.tobytes() != notdef.tobytes()


@pytest.mark.django_db
def test_unreadable_logo_falls_back_to_letter(on, caplog):
    branding = Branding.objects.get()
    branding.logo.save("logo.png", ContentFile(b"not an image"), save=True)
    resp = APIClient().get("/api/v1/devices/icons/192.png")
    assert resp.status_code == 200
    assert _has_glyph(opened(resp.content), (0x12, 0x34, 0x56))
    assert "logo" in caplog.text.lower()


@pytest.mark.django_db
def test_missing_logo_file_falls_back(on):
    Branding.objects.update(logo="site/logo/gone.png")
    assert APIClient().get("/api/v1/devices/icons/192.png").status_code == 200


def test_huge_logo_is_refused(monkeypatch):
    monkeypatch.setattr(icons, "MAX_PIXELS", 100)
    assert icons.load_logo_from(io.BytesIO(png(size=(20, 20)))) is None


@pytest.mark.django_db
def test_cached_until_branding_changes(on, django_assert_max_num_queries):
    first = APIClient().get("/api/v1/devices/icons/192.png").content
    # QuerySet.update() skips auto_now: updated_at (the cache key) is unchanged,
    # so the second request is the cached bytes despite the new colour.
    Branding.objects.update(primary_color="#ABCDEF")
    with django_assert_max_num_queries(6):
        again = APIClient().get("/api/v1/devices/icons/192.png").content
    assert again == first
    branding = Branding.objects.get()
    branding.primary_color = "#654321"
    branding.save()
    changed = opened(APIClient().get("/api/v1/devices/icons/192.png").content).convert("RGB")
    assert changed.getpixel((0, 0)) == (0x65, 0x43, 0x21)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django pytest etqan/devices/tests/test_icons.py -q`
Expected: FAIL (`etqan.devices.icons` missing).

- [ ] **Step 3: Implement**

`backend/etqan/devices/icons.py`:

```python
"""App icons (B11a A-3): a tile of the academy's primary colour with its logo
fitted in, or the first letter of its name. The stored logo is never served:
it is opened, resized and saved as a new PNG."""

import io
import logging
from pathlib import Path

from django.core.files.storage import default_storage
from PIL import Image
from PIL import ImageDraw
from PIL import ImageFont
from PIL import UnidentifiedImageError

logger = logging.getLogger(__name__)
FONT = Path(__file__).parent / "fonts" / "DejaVuSans.ttf"
# Same bound as uploads (site.images.MAX_PIXELS): a logo larger than this was
# never accepted, so one in storage is not trusted.
MAX_PIXELS = 16_000_000


def load_logo_from(handle) -> Image.Image | None:
    try:
        image = Image.open(handle)
        if image.width * image.height > MAX_PIXELS:
            return None
        image.load()
    except (OSError, ValueError, UnidentifiedImageError, Image.DecompressionBombError):
        return None
    return image.convert("RGBA")


def load_logo(name: str) -> Image.Image | None:
    if not name:
        return None
    try:
        with default_storage.open(name) as handle:
            image = load_logo_from(handle)
    except OSError:
        image = None
    if image is None:
        logger.warning("App icon: the academy logo %s could not be read", name)
    return image


def _paste_logo(tile: Image.Image, logo: Image.Image, share: float) -> None:
    box = round(tile.width * share)
    scale = box / max(logo.width, logo.height)
    size = (max(1, round(logo.width * scale)), max(1, round(logo.height * scale)))
    fitted = logo.resize(size, Image.Resampling.LANCZOS)
    tile.paste(fitted, ((tile.width - size[0]) // 2, (tile.height - size[1]) // 2), fitted)


def _draw_letter(tile: Image.Image, letter: str, colour: str) -> None:
    font = ImageFont.truetype(str(FONT), round(tile.width * 0.5))
    centre = (tile.width / 2, tile.height / 2)
    ImageDraw.Draw(tile).text(centre, letter, font=font, fill=colour, anchor="mm")


def render(*, size: int, share: float, background: str, foreground: str, letter: str, logo_name: str) -> bytes:
    tile = Image.new("RGBA", (size, size), background)
    logo = load_logo(logo_name)
    if logo is not None:
        _paste_logo(tile, logo, share)
    elif letter:
        _draw_letter(tile, letter, foreground)
    out = io.BytesIO()
    tile.convert("RGB").save(out, "PNG", optimize=True)
    return out.getvalue()
```

Add to `backend/etqan/devices/services.py` (imports: `from django.core.cache import cache`,
`from etqan.devices import icons`):

```python
ICON_TTL = 86_400


def icon(kind: str) -> bytes:
    require_on()
    if kind not in ICON_KINDS:
        raise NotFoundError("App icon", kind)
    snapshot = site_services.branding_snapshot()
    # django-tenants' make_key prefixes the schema: one academy never reads
    # another's icon.
    key = f"devices:icon:{kind}:{version(snapshot)}"
    data = cache.get(key)
    if data is None:
        size, share, _purpose = ICON_KINDS[kind]
        name = app_name(snapshot, academy_services.get_settings().default_language)
        data = icons.render(
            size=size,
            share=share,
            background=colour(snapshot.primary_color),
            foreground=colour(snapshot.primary_text, "#FFFFFF"),
            letter=name[:1].upper(),
            logo_name=snapshot.logo_name,
        )
        cache.set(key, data, ICON_TTL)
    return data
```

`IconView` in `backend/etqan/devices/api/views.py` (import `HttpResponse`):

```python
class IconView(PublicAppView):
    def get(self, request, kind, *args, **kwargs):
        response = HttpResponse(services.icon(kind), content_type="image/png")
        response["Cache-Control"] = "public, max-age=86400"
        return response
```

Route in `backend/etqan/devices/api/urls.py`:
`path("icons/<str:kind>.png", views.IconView.as_view(), name="icon"),`

- [ ] **Step 4: Run tests to verify they pass**

Run: `just _compose run --rm -e DATABASE_URL=postgres://etqan:etqan@postgres:5432/etqan django sh -euc 'pytest etqan/devices -q --cov=etqan/devices --cov-report=term-missing && ruff check etqan/devices etqan/site && ruff format --check etqan/devices etqan/site'` then `just check-boundaries`
Expected: PASS; `etqan/devices` coverage ≥ 90 %.

- [ ] **Step 5: Commit**

`feat(devices): app icons from the academy logo or initial (B11a)` + the Co-Authored-By line.

---

### Task 3: Service worker, offline page and turning installability on/off

**Files:**
- Create: `dashboard/public/sw.js`, `dashboard/public/offline.html`,
  `dashboard/src/features/apps/installable.ts`, `dashboard/src/features/apps/installable.test.ts`,
  `dashboard/src/features/apps/InstallableApp.tsx`, `dashboard/src/features/apps/InstallableApp.test.tsx`,
  `dashboard/src/features/apps/index.ts`
- Modify: `dashboard/src/routes/_authed.tsx` (one line), `dashboard/src/features/identity/schemas.ts`
  (`FeatureCode` union, at the end: `// Phase B11, slice B11a.` then `| "installable_app"`)

**Interfaces:**
- Consumes: `useMe()` from `@/features/identity/queries` (`data?: Me` with `features?: readonly string[]`).
- Produces (`@/features/apps`): `SWITCH = "installable_app"`, `MANIFEST_URL = "/api/v1/devices/manifest.webmanifest"`,
  `SW_URL = "/app/sw.js"`, `SCOPE = "/app/"`, `CACHE_PREFIX = "devices-"`,
  `installState(me: Me | undefined): "unknown" | "on" | "off"`,
  `enableInstall(env?: InstallDeps): Promise<void>`, `disableInstall(env?: InstallDeps): Promise<void>`,
  `InstallDeps = { doc: Document; sw?: ServiceWorkerContainer; cacheStorage?: CacheStorage; fetcher: typeof fetch }`,
  `InstallableApp(): null` (component).

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/apps/installable.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Me } from "@/features/identity/schemas";
import { disableInstall, enableInstall, installState, MANIFEST_URL } from "./installable";

const me = (features?: string[]): Me =>
	({ id: 1, email: "a@b.c", full_name: "A", role: "student", profiles: [], features }) as Me;

const manifest = {
	theme_color: "#123456",
	icons: [{ src: "/api/v1/devices/icons/192.png?v=99" }],
};

function deps(overrides: Partial<Parameters<typeof enableInstall>[0]> = {}) {
	const registration = { scope: "http://demo.etqan.localhost/app/", unregister: vi.fn().mockResolvedValue(true) };
	const other = { scope: "http://demo.etqan.localhost/elsewhere/", unregister: vi.fn() };
	return {
		doc: document,
		fetcher: vi.fn().mockResolvedValue(new Response(JSON.stringify(manifest), { status: 200 })),
		sw: {
			register: vi.fn().mockResolvedValue(registration),
			getRegistrations: vi.fn().mockResolvedValue([registration, other]),
		} as unknown as ServiceWorkerContainer,
		cacheStorage: {
			keys: vi.fn().mockResolvedValue(["devices-1", "other"]),
			delete: vi.fn().mockResolvedValue(true),
		} as unknown as CacheStorage,
		registration,
		other,
		...overrides,
	};
}

afterEach(() => {
	for (const el of document.head.querySelectorAll("[data-etqan-app]")) el.remove();
});

describe("installState", () => {
	it("is unknown until me and its features are loaded", () => {
		expect(installState(undefined)).toBe("unknown");
		expect(installState(me(undefined))).toBe("unknown");
	});
	it("is on only when the switch is listed", () => {
		expect(installState(me(["installable_app"]))).toBe("on");
		expect(installState(me(["themes"]))).toBe("off");
	});
});

describe("enableInstall", () => {
	it("adds the head tags and registers the worker on /app/", async () => {
		const d = deps();
		await enableInstall(d);
		expect(d.fetcher).toHaveBeenCalledWith(MANIFEST_URL, { credentials: "omit" });
		expect(document.head.querySelector('link[rel="manifest"]')?.getAttribute("href")).toBe(MANIFEST_URL);
		expect(document.head.querySelector('link[rel="apple-touch-icon"]')?.getAttribute("href")).toBe(
			"/api/v1/devices/icons/apple-touch-180.png?v=99",
		);
		expect(document.head.querySelector('meta[name="theme-color"]')?.getAttribute("content")).toBe("#123456");
		expect(d.sw.register).toHaveBeenCalledWith("/app/sw.js", { scope: "/app/" });
	});
	it("is idempotent (StrictMode runs effects twice)", async () => {
		const d = deps();
		await enableInstall(d);
		await enableInstall(d);
		expect(document.head.querySelectorAll('link[rel="manifest"]')).toHaveLength(1);
	});
	it("does nothing when the manifest is refused", async () => {
		const d = deps({ fetcher: vi.fn().mockResolvedValue(new Response("", { status: 404 })) });
		await enableInstall(d);
		expect(document.head.querySelector('link[rel="manifest"]')).toBeNull();
		expect(d.sw.register).not.toHaveBeenCalled();
	});
	it("survives a browser without service workers", async () => {
		const d = deps({ sw: undefined });
		await expect(enableInstall(d)).resolves.toBeUndefined();
		expect(document.head.querySelector('link[rel="manifest"]')).not.toBeNull();
	});
	it("logs a failed registration and keeps the tags", async () => {
		const error = vi.spyOn(console, "error").mockImplementation(() => {});
		const d = deps();
		vi.mocked(d.sw.register).mockRejectedValue(new Error("private mode"));
		await enableInstall(d);
		expect(error).toHaveBeenCalled();
		expect(document.head.querySelector('link[rel="manifest"]')).not.toBeNull();
		error.mockRestore();
	});
});

describe("disableInstall", () => {
	it("removes tags, unregisters only /app/ and drops only devices- caches", async () => {
		const d = deps();
		await enableInstall(d);
		await disableInstall(d);
		expect(document.head.querySelector("[data-etqan-app]")).toBeNull();
		expect(d.registration.unregister).toHaveBeenCalled();
		expect(d.other.unregister).not.toHaveBeenCalled();
		expect(d.cacheStorage.delete).toHaveBeenCalledWith("devices-1");
		expect(d.cacheStorage.delete).not.toHaveBeenCalledWith("other");
	});
	it("survives missing service worker and cache APIs", async () => {
		await expect(disableInstall(deps({ sw: undefined, cacheStorage: undefined }))).resolves.toBeUndefined();
	});
});
```

`dashboard/src/features/apps/InstallableApp.test.tsx`:

```tsx
import { render, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
import { InstallableApp } from "./InstallableApp";
import * as installable from "./installable";

vi.mock("@/features/identity/queries", () => ({ useMe: vi.fn() }));

const meWith = (features?: string[]) =>
	({ data: features === undefined ? undefined : ({ id: 1, role: "teacher", features } as unknown as Me) }) as ReturnType<
		typeof useMe
	>;

beforeEach(() => {
	vi.spyOn(installable, "enableInstall").mockResolvedValue();
	vi.spyOn(installable, "disableInstall").mockResolvedValue();
});
afterEach(() => vi.restoreAllMocks());

it("does nothing while me loads", () => {
	vi.mocked(useMe).mockReturnValue(meWith(undefined));
	render(<InstallableApp />);
	expect(installable.enableInstall).not.toHaveBeenCalled();
	expect(installable.disableInstall).not.toHaveBeenCalled();
});

it("enables when the switch is on", async () => {
	vi.mocked(useMe).mockReturnValue(meWith(["installable_app"]));
	render(<InstallableApp />);
	await waitFor(() => expect(installable.enableInstall).toHaveBeenCalled());
	expect(installable.disableInstall).not.toHaveBeenCalled();
});

it("disables when the switch is off", async () => {
	vi.mocked(useMe).mockReturnValue(meWith([]));
	render(<InstallableApp />);
	await waitFor(() => expect(installable.disableInstall).toHaveBeenCalled());
});
```

(If spying on the module's exports does not intercept the component's calls under ESM, have `InstallableApp` call
them through the imported namespace — `import * as installable from "./installable"` — so the spies apply.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `just _compose run --rm dashboard pnpm vitest run src/features/apps`
Expected: FAIL (modules missing).

- [ ] **Step 3: Implement**

`dashboard/src/features/apps/installable.ts`:

```ts
import type { Me } from "@/features/identity/schemas";

/** Phase B11, slice B11a (spec 2026-10-09-b11-apps A-4): the dashboard is a
 * static bundle, so it adds the academy's manifest itself once `me` says the
 * switch is on, and takes it away again when it is off. */
export const SWITCH = "installable_app";
export const MANIFEST_URL = "/api/v1/devices/manifest.webmanifest";
export const SW_URL = "/app/sw.js";
export const SCOPE = "/app/";
export const CACHE_PREFIX = "devices-";
const APPLE_ICON = "/api/v1/devices/icons/apple-touch-180.png";
const MARK = "data-etqan-app";

export interface InstallDeps {
	doc: Document;
	fetcher: typeof fetch;
	sw?: ServiceWorkerContainer;
	cacheStorage?: CacheStorage;
}

function browserDeps(): InstallDeps {
	return {
		doc: document,
		fetcher: (...args) => fetch(...args),
		sw: "serviceWorker" in navigator ? navigator.serviceWorker : undefined,
		cacheStorage: typeof caches === "undefined" ? undefined : caches,
	};
}

/** Strict: `hasFeature` treats a missing `me` as allow-all, which would add
 * the manifest while `me` loads (spec review C2). */
export function installState(me: Me | undefined): "unknown" | "on" | "off" {
	if (!me?.features) return "unknown";
	return me.features.includes(SWITCH) ? "on" : "off";
}

function setTag(doc: Document, tag: "link" | "meta", key: string, attrs: Record<string, string>) {
	let el = doc.head.querySelector<HTMLElement>(`[${MARK}="${key}"]`);
	if (!el) {
		el = doc.createElement(tag);
		el.setAttribute(MARK, key);
		doc.head.appendChild(el);
	}
	for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
}

export async function enableInstall(deps: InstallDeps = browserDeps()): Promise<void> {
	const response = await deps.fetcher(MANIFEST_URL, { credentials: "omit" });
	if (!response.ok) return;
	const manifest = (await response.json()) as { theme_color?: string; icons?: { src: string }[] };
	const version = new URL(manifest.icons?.[0]?.src ?? "/", "http://x").searchParams.get("v") ?? "";
	setTag(deps.doc, "link", "manifest", { rel: "manifest", href: MANIFEST_URL });
	setTag(deps.doc, "link", "apple-touch-icon", {
		rel: "apple-touch-icon",
		href: version ? `${APPLE_ICON}?v=${version}` : APPLE_ICON,
	});
	if (manifest.theme_color) {
		setTag(deps.doc, "meta", "theme-color", { name: "theme-color", content: manifest.theme_color });
	}
	if (!deps.sw) return;
	try {
		await deps.sw.register(SW_URL, { scope: SCOPE });
	} catch (error) {
		console.error("The app's service worker could not be registered", error);
	}
}

export async function disableInstall(deps: InstallDeps = browserDeps()): Promise<void> {
	for (const el of deps.doc.head.querySelectorAll(`[${MARK}]`)) el.remove();
	if (deps.sw) {
		const registrations = await deps.sw.getRegistrations();
		await Promise.all(
			registrations
				.filter((r) => new URL(r.scope).pathname === SCOPE)
				.map((r) => r.unregister()),
		);
	}
	if (deps.cacheStorage) {
		const keys = await deps.cacheStorage.keys();
		await Promise.all(
			keys.filter((k) => k.startsWith(CACHE_PREFIX)).map((k) => deps.cacheStorage!.delete(k)),
		);
	}
}
```

`dashboard/src/features/apps/InstallableApp.tsx`:

```tsx
import { useEffect } from "react";
import { useMe } from "@/features/identity/queries";
import * as installable from "./installable";

/** Mounted once in the signed-in layout (spec A-4). Renders nothing. */
export function InstallableApp() {
	const { data: me } = useMe();
	const state = installable.installState(me);
	useEffect(() => {
		if (state === "on") void installable.enableInstall();
		else if (state === "off") void installable.disableInstall();
	}, [state]);
	return null;
}
```

`dashboard/src/features/apps/index.ts`:

```ts
export { InstallableApp } from "./InstallableApp";
export { installState } from "./installable";
```

`dashboard/src/routes/_authed.tsx`: import `{ InstallableApp } from "@/features/apps"` and render
`<InstallableApp />` as the first child inside `<AppShell>` (before `<PermissionGate>`).

`dashboard/src/features/identity/schemas.ts`: at the end of the `FeatureCode` union add
`// Phase B11, slice B11a.` and `| "installable_app"` (keep the trailing `;` on the last member).

`dashboard/public/sw.js`:

```js
// Phase B11, slice B11a (spec 2026-10-09-b11-apps A-5): caches only the
// offline page. API calls, assets and other origins are never intercepted.
const VERSION = "1";
const CACHE = `devices-${VERSION}`;
const OFFLINE = "/app/offline.html";

self.addEventListener("install", (event) => {
	event.waitUntil(
		caches
			.open(CACHE)
			.then((cache) => cache.add(new Request(OFFLINE, { cache: "reload" })))
			.then(() => self.skipWaiting()),
	);
});

self.addEventListener("activate", (event) => {
	event.waitUntil(
		caches
			.keys()
			.then((keys) =>
				Promise.all(
					keys
						.filter((key) => key.startsWith("devices-") && key !== CACHE)
						.map((key) => caches.delete(key)),
				),
			)
			.then(() => self.clients.claim()),
	);
});

self.addEventListener("fetch", (event) => {
	const request = event.request;
	if (request.mode !== "navigate") return;
	const url = new URL(request.url);
	if (url.origin !== self.location.origin || !url.pathname.startsWith("/app/")) return;
	event.respondWith(
		fetch(request).catch(() =>
			caches.match(OFFLINE, { cacheName: CACHE }).then((cached) => cached || Response.error()),
		),
	);
});
```

`dashboard/public/offline.html`:

```html
<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>غير متصل · Offline</title>
<style>
	:root { color-scheme: light dark; }
	body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: system-ui, sans-serif;
		background: #fff; color: #1f2937; padding: 16px; box-sizing: border-box; }
	@media (prefers-color-scheme: dark) { body { background: #111827; color: #f3f4f6; } }
	main { max-width: 28rem; text-align: center; display: grid; gap: 12px; }
	h1 { font-size: 1.25rem; margin: 0; }
	p { margin: 0; line-height: 1.6; }
	[lang="en"] { direction: ltr; }
	button { justify-self: center; font: inherit; padding: 8px 20px; border-radius: 8px; border: 1px solid currentColor;
		background: transparent; color: inherit; cursor: pointer; }
</style>
</head>
<body>
<main>
	<h1>أنت غير متصل بالإنترنت</h1>
	<p>تحقق من اتصالك ثم حاول مرة أخرى.</p>
	<h1 lang="en">You are offline</h1>
	<p lang="en">Check your connection, then try again.</p>
	<button type="button" onclick="location.reload()">حاول مرة أخرى · Try again</button>
</main>
</body>
</html>
```

- [ ] **Step 4: Run tests to verify they pass**

Run, one command at a time (`just` splits quoted `sh -c` strings): `just _compose run --rm dashboard pnpm vitest run src/features/apps`, `just _compose run --rm dashboard pnpm tsc --noEmit`, `just _compose run --rm dashboard pnpm lint`
Expected: PASS. (Regenerate nothing: `_authed.tsx` keeps its route path, so `routeTree.gen.ts` is unchanged.)

- [ ] **Step 5: Commit**

Dashboard repo: `feat(apps): service worker, offline page and per-academy manifest wiring (B11a)` + Co-Authored-By.

---

### Task 4: "Install the app" card on the account page

**Files:**
- Create: `dashboard/src/features/apps/install.ts`, `dashboard/src/features/apps/install.test.ts`,
  `dashboard/src/features/apps/platform.ts`, `dashboard/src/features/apps/platform.test.ts`,
  `dashboard/src/features/apps/InstallAppCard.tsx`, `dashboard/src/features/apps/InstallAppCard.test.tsx`,
  `dashboard/src/locales/en/apps.json`, `dashboard/src/locales/ar/apps.json`
- Modify: `dashboard/src/features/apps/index.ts` (export `InstallAppCard`), `dashboard/src/main.tsx` (one import
  line), `dashboard/src/routes/_authed/account.tsx` (one line)

**Interfaces:**
- Consumes: Task 3's `installState`.
- Produces: `install.ts`: `captureInstallPrompt(target?: Window): void` (called once at import),
  `useInstallPrompt(): { canPrompt: boolean; prompt: () => Promise<boolean> }`, `resetInstallPrompt(): void` (tests);
  `platform.ts`: `InstallEnv = { userAgent: string; platform: string; maxTouchPoints: number; standalone: boolean;
  displayStandalone: boolean }`, `readEnv(): InstallEnv`, `isIos(env): boolean`, `isMacSafariWithDock(env): boolean`,
  `installHint(env, canPrompt): "installed" | "prompt" | "ios" | "macSafari" | "browserMenu"`;
  `InstallAppCard(): JSX.Element`.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/features/apps/platform.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { type InstallEnv, installHint, isIos, isMacSafariWithDock } from "./platform";

const env = (over: Partial<InstallEnv>): InstallEnv => ({
	userAgent: "",
	platform: "",
	maxTouchPoints: 0,
	standalone: false,
	displayStandalone: false,
	...over,
});
const IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1";
const MAC_SAFARI_17 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15";
const MAC_SAFARI_16 = MAC_SAFARI_17.replace("Version/17.4", "Version/16.6");
const MAC_CHROME = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36";

describe("platform", () => {
	it("detects iPhone and iPad (MacIntel with touch)", () => {
		expect(isIos(env({ userAgent: IPHONE, platform: "iPhone" }))).toBe(true);
		expect(isIos(env({ userAgent: MAC_SAFARI_17, platform: "MacIntel", maxTouchPoints: 5 }))).toBe(true);
		expect(isIos(env({ userAgent: MAC_SAFARI_17, platform: "MacIntel", maxTouchPoints: 0 }))).toBe(false);
	});
	it("offers Add to Dock only on macOS Safari 17+", () => {
		expect(isMacSafariWithDock(env({ userAgent: MAC_SAFARI_17, platform: "MacIntel" }))).toBe(true);
		expect(isMacSafariWithDock(env({ userAgent: MAC_SAFARI_16, platform: "MacIntel" }))).toBe(false);
		expect(isMacSafariWithDock(env({ userAgent: MAC_CHROME, platform: "MacIntel" }))).toBe(false);
		expect(isMacSafariWithDock(env({ userAgent: MAC_SAFARI_17, platform: "MacIntel", maxTouchPoints: 5 }))).toBe(false);
	});
	it("picks the hint in order", () => {
		expect(installHint(env({ displayStandalone: true }), true)).toBe("installed");
		expect(installHint(env({ standalone: true, userAgent: IPHONE }), false)).toBe("installed");
		expect(installHint(env({ userAgent: MAC_CHROME, platform: "MacIntel" }), true)).toBe("prompt");
		expect(installHint(env({ userAgent: IPHONE, platform: "iPhone" }), false)).toBe("ios");
		expect(installHint(env({ userAgent: MAC_SAFARI_17, platform: "MacIntel" }), false)).toBe("macSafari");
		expect(installHint(env({ userAgent: MAC_SAFARI_16, platform: "MacIntel" }), false)).toBe("browserMenu");
	});
});
```

`dashboard/src/features/apps/install.test.ts`:

```ts
import { act, renderHook } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { captureInstallPrompt, resetInstallPrompt, useInstallPrompt } from "./install";

afterEach(() => resetInstallPrompt());

function promptEvent(outcome: "accepted" | "dismissed") {
	const event = new Event("beforeinstallprompt", { cancelable: true }) as Event & {
		prompt: () => Promise<void>;
		userChoice: Promise<{ outcome: string }>;
	};
	event.prompt = vi.fn().mockResolvedValue(undefined);
	event.userChoice = Promise.resolve({ outcome });
	return event;
}

it("captures the prompt, then prompts once", async () => {
	captureInstallPrompt(window);
	const { result } = renderHook(() => useInstallPrompt());
	expect(result.current.canPrompt).toBe(false);
	const event = promptEvent("accepted");
	act(() => {
		window.dispatchEvent(event);
	});
	expect(event.defaultPrevented).toBe(true);
	expect(result.current.canPrompt).toBe(true);
	let accepted = false;
	await act(async () => {
		accepted = await result.current.prompt();
	});
	expect(accepted).toBe(true);
	expect(event.prompt).toHaveBeenCalled();
	expect(result.current.canPrompt).toBe(false);
});

it("forgets the prompt once installed", () => {
	captureInstallPrompt(window);
	const { result } = renderHook(() => useInstallPrompt());
	act(() => {
		window.dispatchEvent(promptEvent("dismissed"));
	});
	act(() => {
		window.dispatchEvent(new Event("appinstalled"));
	});
	expect(result.current.canPrompt).toBe(false);
});

it("prompt without an event answers false", async () => {
	const { result } = renderHook(() => useInstallPrompt());
	await expect(result.current.prompt()).resolves.toBe(false);
});
```

`dashboard/src/features/apps/InstallAppCard.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, it, vi } from "vitest";
import "@/lib/i18n";
import i18n from "i18next";
import { InstallAppCard } from "./InstallAppCard";
import * as install from "./install";
import * as platform from "./platform";

beforeEach(async () => {
	await i18n.changeLanguage("en");
	vi.restoreAllMocks();
});

function withHint(hint: ReturnType<typeof platform.installHint>, canPrompt = false) {
	const prompt = vi.fn().mockResolvedValue(true);
	vi.spyOn(install, "useInstallPrompt").mockReturnValue({ canPrompt, prompt });
	vi.spyOn(platform, "installHint").mockReturnValue(hint);
	return prompt;
}

it("says when already installed", () => {
	withHint("installed");
	render(<InstallAppCard />);
	expect(screen.getByRole("heading", { name: "Install the app" })).toBeInTheDocument();
	expect(screen.getByText(/using the installed app/i)).toBeInTheDocument();
});

it("installs through the browser prompt", async () => {
	const prompt = withHint("prompt", true);
	render(<InstallAppCard />);
	await userEvent.click(screen.getByRole("button", { name: "Install" }));
	expect(prompt).toHaveBeenCalled();
});

it.each([
	["ios", /Add to Home Screen/],
	["macSafari", /Add to Dock/],
	["browserMenu", /browser's menu/],
] as const)("shows the %s steps", (hint, text) => {
	withHint(hint);
	render(<InstallAppCard />);
	expect(screen.getByText(text)).toBeInTheDocument();
	expect(screen.queryByRole("button", { name: "Install" })).toBeNull();
});

it("warns iOS users about Google sign-in", () => {
	withHint("ios");
	render(<InstallAppCard />);
	expect(screen.getByText(/Google sign-in/)).toBeInTheDocument();
});
```

Add to the account page's existing tests (find them with `ls dashboard/src/routes/_authed/account*.test.tsx`; if none
exists create `dashboard/src/routes/_authed/account.test.tsx` rendering `<Account me={…} />` the way
`AppearanceCard.test.tsx` builds a `Me`, mocking `@/features/apps` `InstallAppCard` to a stub with text
"install-card" and the other cards' data hooks as the existing tests do):

```tsx
it("shows the install card only when the switch is on and not impersonated", () => {
	const { rerender } = renderAccount({ features: ["installable_app"] });
	expect(screen.getByText("install-card")).toBeInTheDocument();
	rerender(withAccount({ features: [] }));
	expect(screen.queryByText("install-card")).toBeNull();
	rerender(withAccount({ features: ["installable_app"], impersonator: { id: 9, full_name: "Admin" } }));
	expect(screen.queryByText("install-card")).toBeNull();
});
```

(`renderAccount`/`withAccount` are local helpers you write in that file: build `Me` with the overrides and render or
return `<Account me={me} />` inside the providers the existing account tests use.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `just _compose run --rm dashboard pnpm vitest run src/features/apps src/routes/_authed/account`
Expected: FAIL (modules missing / card absent).

- [ ] **Step 3: Implement**

`dashboard/src/features/apps/platform.ts`:

```ts
/** Which install steps fit this browser (spec A-7). Pure, so tests pass an env. */
export interface InstallEnv {
	userAgent: string;
	platform: string;
	maxTouchPoints: number;
	/** iOS Safari's own flag for a home-screen app. */
	standalone: boolean;
	displayStandalone: boolean;
}

export type InstallHint = "installed" | "prompt" | "ios" | "macSafari" | "browserMenu";

export function readEnv(): InstallEnv {
	return {
		userAgent: navigator.userAgent,
		platform: navigator.platform,
		maxTouchPoints: navigator.maxTouchPoints ?? 0,
		standalone: (navigator as Navigator & { standalone?: boolean }).standalone === true,
		displayStandalone: window.matchMedia?.("(display-mode: standalone)").matches ?? false,
	};
}

export function isIos(env: InstallEnv): boolean {
	if (/iPhone|iPad|iPod/.test(env.userAgent)) return true;
	// iPadOS 13+ Safari reports a Mac; only the touch screen gives it away.
	return env.platform === "MacIntel" && env.maxTouchPoints > 1;
}

export function isMacSafariWithDock(env: InstallEnv): boolean {
	if (!env.platform.startsWith("Mac") || isIos(env)) return false;
	if (/Chrome|Chromium|Edg\/|Firefox|OPR\//.test(env.userAgent)) return false;
	const version = /Version\/(\d+)/.exec(env.userAgent);
	return /Safari\//.test(env.userAgent) && version !== null && Number(version[1]) >= 17;
}

export function installHint(env: InstallEnv, canPrompt: boolean): InstallHint {
	if (env.displayStandalone || env.standalone) return "installed";
	if (canPrompt) return "prompt";
	if (isIos(env)) return "ios";
	if (isMacSafariWithDock(env)) return "macSafari";
	return "browserMenu";
}
```

`dashboard/src/features/apps/install.ts`:

```ts
import { useSyncExternalStore } from "react";

/** Chromium's install prompt (spec A-7). It fires once, early, so the listener
 * is installed when main.tsx imports this module, before React renders. */
type PromptEvent = Event & {
	prompt: () => Promise<void>;
	userChoice: Promise<{ outcome: "accepted" | "dismissed" | string }>;
};

let deferred: PromptEvent | null = null;
const listeners = new Set<() => void>();
const captured = new WeakSet<Window>();

function emit() {
	for (const listener of listeners) listener();
}

export function captureInstallPrompt(target: Window = window): void {
	if (captured.has(target)) return;
	captured.add(target);
	target.addEventListener("beforeinstallprompt", (event) => {
		event.preventDefault();
		deferred = event as PromptEvent;
		emit();
	});
	target.addEventListener("appinstalled", () => {
		deferred = null;
		emit();
	});
}

export function resetInstallPrompt(): void {
	deferred = null;
	emit();
}

function subscribe(listener: () => void) {
	listeners.add(listener);
	return () => listeners.delete(listener);
}

export function useInstallPrompt() {
	const canPrompt = useSyncExternalStore(subscribe, () => deferred !== null);
	async function prompt(): Promise<boolean> {
		const event = deferred;
		if (!event) return false;
		deferred = null;
		emit();
		await event.prompt();
		const choice = await event.userChoice;
		return choice.outcome === "accepted";
	}
	return { canPrompt, prompt };
}

if (typeof window !== "undefined") captureInstallPrompt(window);
```

`dashboard/src/features/apps/InstallAppCard.tsx`:

```tsx
import { useTranslation } from "react-i18next";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@/ui";
import * as install from "./install";
import * as platform from "./platform";

/** My account → Install the app (spec 2026-10-09-b11-apps A-7). The account
 * page shows it only while installable_app is on and the user is themselves. */
export function InstallAppCard() {
	const { t } = useTranslation();
	const { canPrompt, prompt } = install.useInstallPrompt();
	const hint = platform.installHint(platform.readEnv(), canPrompt);
	return (
		<Card>
			<CardHeader className="border-b border-border">
				<CardTitle>{t("apps.title")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-3 text-sm">
				<p className="text-muted-foreground">{t("apps.intro")}</p>
				{hint === "installed" ? <p>{t("apps.installed")}</p> : null}
				{hint === "prompt" ? (
					<Button className="self-start" onClick={() => void prompt()}>
						{t("apps.install")}
					</Button>
				) : null}
				{hint === "ios" ? (
					<>
						<p>{t("apps.ios")}</p>
						<p className="text-muted-foreground">{t("apps.iosGoogle")}</p>
					</>
				) : null}
				{hint === "macSafari" ? <p>{t("apps.macSafari")}</p> : null}
				{hint === "browserMenu" ? <p>{t("apps.browserMenu")}</p> : null}
			</CardContent>
		</Card>
	);
}
```

(`CardTitle` must render a heading for the test's `getByRole("heading")`; check `@/ui`'s `CardTitle` — if it renders a
`div`, query by text instead.)

`dashboard/src/locales/en/apps.json`:

```json
{
	"title": "Install the app",
	"intro": "Use the academy like an app: its own window, and an icon on your home screen or desktop.",
	"installed": "You are using the installed app.",
	"install": "Install",
	"ios": "On iPhone or iPad: tap Share, then “Add to Home Screen”.",
	"iosGoogle": "In the installed app, sign in with your email and password: Google sign-in may not keep you signed in there.",
	"macSafari": "In Safari: choose File, then “Add to Dock”.",
	"browserMenu": "Open your browser's menu and choose “Install app” or “Add to Home screen”."
}
```

`dashboard/src/locales/ar/apps.json`:

```json
{
	"title": "ثبّت التطبيق",
	"intro": "استخدم الأكاديمية كتطبيق: نافذة خاصة بها وأيقونة على الشاشة الرئيسية أو سطح المكتب.",
	"installed": "أنت تستخدم التطبيق المثبّت.",
	"install": "تثبيت",
	"ios": "على iPhone أو iPad: اضغط زر المشاركة ثم «إضافة إلى الشاشة الرئيسية».",
	"iosGoogle": "داخل التطبيق المثبّت سجّل الدخول ببريدك الإلكتروني وكلمة المرور: قد لا يُبقيك تسجيل الدخول عبر Google متصلًا هناك.",
	"macSafari": "في Safari: اختر «ملف» ثم «إضافة إلى Dock».",
	"browserMenu": "افتح قائمة المتصفح واختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية»."
}
```

`dashboard/src/features/apps/index.ts` adds `export { InstallAppCard } from "./InstallAppCard";`.

`dashboard/src/main.tsx`: add `import "@/features/apps/install";` next to `import "@/lib/i18n";`.

`dashboard/src/routes/_authed/account.tsx`: import `InstallAppCard` and `installState` from `@/features/apps`; after
`<NotificationPreferencesCard />` add
`{own && installState(me) === "on" ? <InstallAppCard /> : null}`.

- [ ] **Step 4: Run tests to verify they pass**

Run, one command at a time: `just _compose run --rm dashboard pnpm vitest run src/features/apps src/routes/_authed/account src/locales src/lib`, `just _compose run --rm dashboard pnpm tsc --noEmit`, `just _compose run --rm dashboard pnpm lint`
Expected: PASS (including the ar/en key-equality test over `locales`).

- [ ] **Step 5: Commit**

`feat(apps): install-the-app card on the account page (B11a)` + Co-Authored-By.

---

### Task 5: e2e journey and the slice gates

**Files:**
- Create: `dashboard/e2e/b11-installable-app.spec.ts`

**Interfaces:**
- Consumes: e2e `fixtures.ts` (`login`, `DEMO_URL`, `DEMO_ADMIN`, `expectLoggedIn`), `manage.ts` (`manage(...)`);
  the endpoints and UI from Tasks 1–4.

- [ ] **Step 1: Write the e2e spec**

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, expectLoggedIn, login } from "./fixtures";
import { manage } from "./manage";

// Slice B11a spec §10. Demo has every built switch on (seed_dev), so
// installable_app is on already; the test turns it off at the end and
// restores it, whatever happens.
test.afterAll(() => {
	manage("set_features", "demo", "--on", "installable_app");
});

test("the dashboard installs as an app and has an offline page", async ({ page, context }) => {
	test.setTimeout(90_000);
	manage("set_features", "demo", "--on", "installable_app");
	await login(page, DEMO_URL, DEMO_ADMIN);
	await expectLoggedIn(page, /demo academy admin/i);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));

	// Manifest wired into <head>, served per academy.
	await expect(page.locator('link[rel="manifest"]')).toHaveAttribute(
		"href",
		"/api/v1/devices/manifest.webmanifest",
	);
	const manifestResponse = await page.request.get(`${DEMO_URL}/api/v1/devices/manifest.webmanifest`);
	expect(manifestResponse.status()).toBe(200);
	const manifest = await manifestResponse.json();
	expect(manifest.start_url).toBe("/app/");
	expect(manifest.name).toBeTruthy();
	const icon = await page.request.get(`${DEMO_URL}${manifest.icons[0].src}`);
	expect(icon.headers()["content-type"]).toBe("image/png");

	// The worker controls /app/.
	const scope = await page.evaluate(async () => (await navigator.serviceWorker.ready).scope);
	expect(scope).toBe(`${DEMO_URL}/app/`);

	// The account page explains installing.
	await page.goto(`${DEMO_URL}/app/account`);
	await expect(page.getByText("Install the app")).toBeVisible();

	// Offline: a navigation gets the offline page, not a browser error.
	await context.setOffline(true);
	await page.goto(`${DEMO_URL}/app/account`).catch(() => undefined);
	await expect(page.getByText("You are offline")).toBeVisible();
	await context.setOffline(false);

	// Switched off: the manifest is gone and the worker unregisters.
	manage("set_features", "demo", "--off", "installable_app");
	expect((await page.request.get(`${DEMO_URL}/api/v1/devices/manifest.webmanifest`)).status()).toBe(404);
	await page.goto(`${DEMO_URL}/app/account`);
	await expect(page.locator('link[rel="manifest"]')).toHaveCount(0);
	await expect
		.poll(() => page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).length))
		.toBe(0);
	await expect(page.getByText("Install the app")).toHaveCount(0);
});
```

(`me/` is cached for 60 s in the dashboard; `page.goto` reloads the document, so the fresh `me` reflects the switch.
If `login` leaves the page somewhere other than `/app/`, `page.goto(`${DEMO_URL}/app/`)` first.)

- [ ] **Step 2: Ask for the memory window**

The orchestrator confirms the conductor's memory window is still open (`just dev-backend` must be up for e2e).

- [ ] **Step 3: Run the gates**

Run: `just test` then `just lint` then `just e2e`
Expected: all green; backend coverage ≥ 80 %, dashboard thresholds met; e2e includes `b11-installable-app`.
Fix failures with TDD in the owning task's files; re-run.

- [ ] **Step 4: Commit**

Dashboard repo: `test(e2e): B11a installable app journey` + Co-Authored-By.

- [ ] **Step 5: Stop the stack**

`just stop` once the gates pass (the conductor's memory rule).
