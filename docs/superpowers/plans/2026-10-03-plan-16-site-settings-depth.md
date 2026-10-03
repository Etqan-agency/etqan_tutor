# Plan 16 — Site settings depth (B8a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Requires:** — (no other phase's slice; builds on Plan 2 and Plan 13, both merged)

**Goal:** Site status modes (live / maintenance / beta / system only), validated analytics-and-ads IDs, three
more social networks, footer text and SEO keywords — in the backend, the Astro public site and the
dashboard's Website area.

**Architecture:** A new singleton `SiteSettings` in `etqan.site` holds status, tracking IDs, footer text and
keywords; two new registry features (`site_status`, `site_tracking`) gate the status and the IDs. The
public payload gains a `settings` key; while the effective status is closed the API withholds content. The
Astro middleware rewrites every path of a closed site to an internal `/closed-site` page; `Layout` renders
banner, keywords and tracking snippets from fixed templates. The dashboard gets a Website → Settings tab.

**Tech Stack:** Django 5 + DRF + django-tenants (pytest), Astro 6 SSR (vitest + AstroContainer), React +
TanStack Router/Query + zod + react-hook-form (vitest + Testing Library), Playwright.

**Spec:** `docs/superpowers/specs/2026-10-03-b8a-site-settings-design.md` (phase spec
`docs/superpowers/specs/2026-10-03-marketing-extras-design.md`). Read both before any task.

## Global Constraints

- Branch `feat/b8a-marketing` in meta, `backend/`, `dashboard/`, `marketing/`. Never run `git submodule`
  write commands. Never run `manage.py`/`migrate`/e2e except through `just` (`just test`, `just lint`,
  `just e2e`, `just makemigrations` / `docker compose -f docker-compose.local.yml run --rm django …`
  from the meta worktree — `.env.stream` points them at this stream's stack).
- Shared lists: add only under `── phase B8 ──` markers (`features.py`, `seed_dev.py`). Unmarked shared
  lists touched here (`test_routes.py` `ROUTES`/`FEATURES`, dashboard `FeatureCode`): append only.
- New features `_built(..., default=False)`, group `content`.
- Status values exactly: `live`, `maintenance`, `beta`, `system_only`.
- ID patterns exactly: `ga4_id` `^G-[A-Z0-9]{4,12}$`; `meta_pixel_id` `^[0-9]{6,20}$`;
  `adsense_client` `^ca-pub-[0-9]{10,20}$`; `google_site_verification` `^[A-Za-z0-9_-]{10,100}$`.
- Lengths: `footer_text_*` ≤ 300, `keywords_*` ≤ 255.
- Closed = `maintenance` or `system_only`. Closed inquiries answer 403 `{"code": "site.closed"}`.
- Maintenance: 503 + `Retry-After: 3600`; system only: 403; both `X-Robots-Tag: noindex` and
  `<meta name="robots" content="noindex">`.
- Shared decision D2: no academy-supplied script or raw HTML is rendered; tracking IDs are interpolated
  into fixed templates only, re-validated in Astro.
- Coverage: backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70; marketing per its
  `vitest.config.ts` thresholds.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. A closed site queried straight through the API (`/api/v1/site/`, `/api/v1/site/pages/<slug>/`,
   `POST /api/v1/site/inquiries/`) with **no `SiteSettings` row yet** — must behave as `live` (Task 2 test).
2. A stored `maintenance` status while `site_status` is switched **off** — the site must be fully open
   (Tasks 1 and 2 tests).
3. A tampered payload (ID with `"`, `<`, or a `javascript:` value) reaching Astro — no snippet is rendered
   (Task 5 test).
4. `/closed-site` requested directly on an **open** site — must be the academy's ordinary 404, revealing
   nothing (Task 6 test).
5. A staff account with every `site.*` code PATCHing `status`/IDs through `settings/` — nothing changes
   (Task 3 test).

---

### Task 1: `SiteSettings`, new socials, services, registry

**Files:**
- Modify: `backend/etqan/site/models.py`, `backend/etqan/site/services.py`,
  `backend/etqan/platform/features.py` (under `# ── phase B8 ──`)
- Create: `backend/etqan/site/migrations/0002_sitesettings_branding_socials.py` (generated)
- Test: `backend/etqan/site/tests/test_settings_model.py`, `backend/etqan/platform/tests/` (existing
  registry tests must still pass)

**Interfaces:**
- Produces: `SiteSettings` model with `Status` TextChoices (`LIVE="live"`, `MAINTENANCE="maintenance"`,
  `BETA="beta"`, `SYSTEM_ONLY="system_only"`), classmethod `SiteSettings.current() -> SiteSettings`;
  `TRACKING_FIELDS = ("ga4_id", "meta_pixel_id", "adsense_client", "google_site_verification")` and
  `TRACKING_PATTERNS: dict[str, re.Pattern]` in `etqan/site/models.py`; `Branding.linkedin/snapchat/soundcloud`;
  `services.effective_status() -> str`, `services.is_closed(status: str) -> bool`;
  `services.CLOSED = frozenset({"maintenance", "system_only"})`; registry codes `site_status`,
  `site_tracking`.

- [ ] **Step 1: Write the failing tests** — `backend/etqan/site/tests/test_settings_model.py`:

```python
import pytest

from etqan.platform import features
from etqan.site import services
from etqan.site.models import Branding
from etqan.site.models import SiteSettings
from etqan.site.services import ensure_site_defaults


def test_current_creates_a_live_row_once():
    assert not SiteSettings.objects.exists()
    first = SiteSettings.current()
    assert first.status == SiteSettings.Status.LIVE
    assert first.footer_text_ar == "" and first.ga4_id == ""
    assert SiteSettings.current().pk == first.pk
    assert SiteSettings.objects.count() == 1


def test_ensure_site_defaults_creates_settings():
    ensure_site_defaults("Main")
    assert SiteSettings.objects.count() == 1


def test_branding_has_the_new_socials():
    ensure_site_defaults("Main")
    b = Branding.load()
    assert (b.linkedin, b.snapchat, b.soundcloud) == ("", "", "")


@pytest.mark.parametrize(
    ("switch", "stored", "expected"),
    [
        (False, "maintenance", "live"),
        (True, "maintenance", "maintenance"),
        (True, "beta", "beta"),
        (True, "live", "live"),
    ],
)
def test_effective_status(set_features, switch, stored, expected):
    set_features(site_status=switch)
    s = SiteSettings.current()
    s.status = stored
    s.save()
    assert services.effective_status() == expected


def test_effective_status_with_no_row_is_live(set_features):
    set_features(site_status=True)
    assert services.effective_status() == "live"


@pytest.mark.parametrize(
    ("status", "closed"),
    [("live", False), ("beta", False), ("maintenance", True), ("system_only", True)],
)
def test_is_closed(status, closed):
    assert services.is_closed(status) is closed


def test_registry_has_b8a_features_off_by_default():
    for code in ("site_status", "site_tracking"):
        f = features.get(code)
        assert f.built is True
        assert f.default is False
        assert f.group == "content"
```

- [ ] **Step 2: Run them, expect failures** — from the meta worktree:
  `docker compose -f docker-compose.local.yml run --rm django pytest etqan/site/tests/test_settings_model.py -q`
  Expected: ImportError on `SiteSettings`.

- [ ] **Step 3: Implement.** In `models.py` add after `LandingContent`:

```python
TRACKING_PATTERNS = {
    "ga4_id": re.compile(r"^G-[A-Z0-9]{4,12}$"),
    "meta_pixel_id": re.compile(r"^[0-9]{6,20}$"),
    "adsense_client": re.compile(r"^ca-pub-[0-9]{10,20}$"),
    "google_site_verification": re.compile(r"^[A-Za-z0-9_-]{10,100}$"),
}
TRACKING_FIELDS = tuple(TRACKING_PATTERNS)


class SiteSettings(models.Model):
    """B8a: the public site's status, analytics/ads IDs, footer text and SEO
    keywords. One row per academy, created on first use."""

    class Status(models.TextChoices):
        LIVE = "live", "Live"
        MAINTENANCE = "maintenance", "Under maintenance"
        BETA = "beta", "Beta"
        SYSTEM_ONLY = "system_only", "System only"

    status = models.CharField(max_length=16, choices=Status.choices, default=Status.LIVE)
    ga4_id = models.CharField(max_length=16, blank=True, default="")
    meta_pixel_id = models.CharField(max_length=20, blank=True, default="")
    adsense_client = models.CharField(max_length=28, blank=True, default="")
    google_site_verification = models.CharField(max_length=100, blank=True, default="")
    footer_text_ar = models.CharField(max_length=300, blank=True, default="")
    footer_text_en = models.CharField(max_length=300, blank=True, default="")
    keywords_ar = models.CharField(max_length=255, blank=True, default="")
    keywords_en = models.CharField(max_length=255, blank=True, default="")
    updated_at = models.DateTimeField(auto_now=True)

    @classmethod
    def current(cls) -> "SiteSettings":
        obj = cls.objects.first()
        return obj if obj is not None else cls.objects.create()

    def __str__(self):
        return f"SiteSettings<{self.status}>"
```

  Add `import re` at the top. On `Branding`, after `telegram`: `linkedin`, `snapchat`, `soundcloud` as
  `models.URLField(blank=True, default="")`. In `services.py`:

```python
from etqan.platform import features
from etqan.site.models import SiteSettings

CLOSED = frozenset({SiteSettings.Status.MAINTENANCE, SiteSettings.Status.SYSTEM_ONLY})


def effective_status() -> str:
    """B8a A-6: the stored status while `site_status` is on, else live."""
    if not features.enabled("site_status"):
        return SiteSettings.Status.LIVE
    return SiteSettings.current().status


def is_closed(status: str) -> bool:
    """Maintenance and system-only sites show no content (B8a A-5, M-9)."""
    return status in CLOSED
```

  and in `ensure_site_defaults` add `SiteSettings.current()`. Check that `etqan.site` may import
  `etqan.platform` (it already does in `admin_views.py`). In `features.py` under `# ── phase B8 ──`:

```python
    _built(
        "site_status", "Site status modes", "أوضاع حالة الموقع", "content", default=False
    ),
    _built(
        "site_tracking", "Analytics and ads", "التحليلات والإعلانات", "content", default=False
    ),
```

  Generate the migration: `docker compose -f docker-compose.local.yml run --rm django python manage.py
  makemigrations site --name sitesettings_branding_socials` (from the meta worktree, `.env.stream` loaded
  by `just`; if `just` has a `makemigrations` recipe use it).

- [ ] **Step 4: Run** the new tests plus `etqan/platform` and `etqan/site` suites: all pass. Run the
  registry tests (`etqan/platform/tests`) — fix any count-based assertion only if it counts `REGISTRY` and
  B8's two lines are the reason.
- [ ] **Step 5: Commit** (backend): `feat(site): SiteSettings, three socials, site_status and site_tracking features`.

---

### Task 2: Public API — `settings` key, closed sites, new socials

**Files:**
- Modify: `backend/etqan/site/api/serializers.py`, `backend/etqan/site/api/views.py`
- Test: `backend/etqan/site/tests/test_public_settings.py`

**Interfaces:**
- Consumes: Task 1 (`SiteSettings.current`, `effective_status`, `is_closed`, `TRACKING_FIELDS`).
- Produces: payload key `settings` = `{"status", "footer_text": {ar,en}, "keywords": {ar,en},
  "tracking": {<4 ids>}}`; `branding.social` with 9 keys (adds `linkedin`, `snapchat`, `soundcloud`);
  `settings_payload(s, status: str) -> dict` in `serializers.py`.

- [ ] **Step 1: Failing tests** — `test_public_settings.py`:

```python
import pytest
from rest_framework.test import APIClient

from etqan.site.models import SitePage
from etqan.site.models import SiteSettings
from etqan.site.models import Testimonial
from etqan.site.services import ensure_site_defaults

SITE = "/api/v1/site/"


@pytest.fixture
def content():
    ensure_site_defaults("Main")
    Testimonial.objects.create(author_name="A", quote_ar="ق", quote_en="q")
    SitePage.objects.create(
        slug="policies", title_ar="س", title_en="P", body_ar="<p>ع</p>",
        body_en="<p>e</p>", is_published=True,
    )


def _store(**fields):
    s = SiteSettings.current()
    for k, v in fields.items():
        setattr(s, k, v)
    s.save()


def test_payload_has_settings_and_socials(content, set_features):
    set_features(site_tracking=True)
    _store(footer_text_en="Since 2010", keywords_ar="قرآن", ga4_id="G-ABC123")
    data = APIClient().get(SITE).json()
    assert data["settings"] == {
        "status": "live",
        "footer_text": {"ar": "", "en": "Since 2010"},
        "keywords": {"ar": "قرآن", "en": ""},
        "tracking": {
            "ga4_id": "G-ABC123", "meta_pixel_id": "", "adsense_client": "",
            "google_site_verification": "",
        },
    }
    assert set(data["branding"]["social"]) >= {"linkedin", "snapchat", "soundcloud"}
    assert set(APIClient().get(SITE + "branding/").json()["social"]) >= {"linkedin"}


def test_tracking_empty_when_feature_off(content, set_features):
    set_features(site_tracking=False)
    _store(ga4_id="G-ABC123")
    tracking = APIClient().get(SITE).json()["settings"]["tracking"]
    assert set(tracking.values()) == {""}


def test_stored_closed_status_ignored_when_feature_off(content, set_features):
    set_features(site_status=False)
    _store(status="maintenance")
    data = APIClient().get(SITE).json()
    assert data["settings"]["status"] == "live"
    assert data["pages"] and data["testimonials"]
    assert APIClient().get(SITE + "pages/policies/").status_code == 200


@pytest.mark.parametrize("status", ["maintenance", "system_only"])
def test_closed_site_withholds_content(content, set_features, status):
    set_features(site_status=True)
    _store(status=status)
    data = APIClient().get(SITE).json()
    assert data["settings"]["status"] == status
    assert data["branding"]["name"]["en"]  # still branded
    assert data["pages"] == [] and data["testimonials"] == []
    landing = data["landing"]
    assert landing["hero_title"] == {"ar": "", "en": ""}
    assert landing["about_html"] == {"ar": "", "en": ""}
    assert landing["hero_image_url"] == ""
    assert not any(landing["sections"].values())
    assert APIClient().get(SITE + "pages/policies/").status_code == 404
    r = APIClient().post(
        SITE + "inquiries/",
        {"name": "V", "email": "v@x.test", "locale": "en"},
        format="json",
    )
    assert r.status_code == 403
    assert r.json()["code"] == "site.closed"


def test_beta_is_open(content, set_features):
    set_features(site_status=True)
    _store(status="beta")
    data = APIClient().get(SITE).json()
    assert data["settings"]["status"] == "beta" and data["pages"]


def test_no_settings_row_page_and_inquiry_are_open(set_features):
    """Review Focus 1: views that never call ensure_site_defaults."""
    set_features(site_status=True)
    SitePage.objects.create(
        slug="p1", title_ar="س", title_en="P", body_ar="x", body_en="x",
        is_published=True,
    )
    assert APIClient().get(SITE + "pages/p1/").status_code == 200
    r = APIClient().post(
        SITE + "inquiries/",
        {"name": "V", "email": "v2@x.test", "locale": "en"},
        format="json",
    )
    assert r.status_code == 201


def test_closing_one_academy_leaves_the_other_open(content, set_features, tenants):
    set_features(site_status=True)
    _store(status="system_only")
    set_features(academy=tenants.other, site_status=True)
    other = APIClient().get(SITE, HTTP_HOST="pytest-other.etqan.localhost").json()
    assert other["settings"]["status"] == "live"
```

  (Check `test_inquiries.py` for the exact inquiry body the existing tests post, and for how throttling is
  reset between tests; copy that.)

- [ ] **Step 2: Run, expect failures** (`KeyError: 'settings'`).
- [ ] **Step 3: Implement.** In `serializers.py`: extend the social tuple to
  `("facebook", "instagram", "youtube", "x", "tiktok", "telegram", "linkedin", "snapchat", "soundcloud")`;
  add

```python
EMPTY = {"ar": "", "en": ""}


def settings_payload(s, status: str, *, tracking_on: bool) -> dict:
    return {
        "status": status,
        "footer_text": pair(s, "footer_text"),
        "keywords": pair(s, "keywords"),
        "tracking": {f: (getattr(s, f) if tracking_on else "") for f in TRACKING_FIELDS},
    }


def closed_landing_payload() -> dict:
    """B8a A-5: a closed site's landing carries no content."""
    return {
        "hero_title": EMPTY, "hero_subtitle": EMPTY, "hero_image_url": "",
        "cta_label": EMPTY, "about_html": EMPTY,
        "sections": dict.fromkeys(
            ("courses", "packages", "teachers", "testimonials", "contact"), False
        ),
    }
```

  In `views.py` `SiteView.get`: compute `status = effective_status()`, `closed = is_closed(status)`; use
  `closed_landing_payload()` when closed; `testimonials`/`pages` `[]` when closed; add
  `"settings": settings_payload(SiteSettings.current(), status, tracking_on=features.enabled("site_tracking"))`.
  `PageView.get`: `if is_closed(effective_status()): raise Http404`. `InquiryCreateView.post`: before
  validation, `if is_closed(effective_status()): return Response({"code": "site.closed", "detail":
  "This site is closed."}, status=403)`.
- [ ] **Step 4: Run** `etqan/site` tests: all pass (existing `test_public_api.py` asserts on social keys —
  update it only if it compares the whole `social` dict, adding the three keys).
- [ ] **Step 5: Commit** `feat(site): public settings payload and closed-site API`.

---

### Task 3: Admin API — settings, status, tracking routes; branding socials; route table

**Files:**
- Modify: `backend/etqan/site/api/admin_serializers.py`, `backend/etqan/site/api/admin_views.py`,
  `backend/etqan/site/api/urls.py`, `backend/etqan/access/tests/test_routes.py`
- Test: `backend/etqan/site/tests/test_admin_settings.py`

**Interfaces:**
- Consumes: Task 1.
- Produces: `GET/PATCH /api/v1/site/admin/settings/` (`footer_text_ar/en`, `keywords_ar/en`),
  `GET/PATCH /api/v1/site/admin/status/` (`status`), `GET/PATCH /api/v1/site/admin/tracking/` (four IDs);
  branding admin gains the three socials.

- [ ] **Step 1: Failing tests** — `test_admin_settings.py` (reuse `client_for` style from
  `test_admin_api.py`; use the `staff_for` fixture from the root conftest for staff with codes):

```python
import pytest
from rest_framework.test import APIClient

from etqan.identity.models import User
from etqan.site.models import SiteSettings
from etqan.site.services import ensure_site_defaults

B = "/api/v1/site/admin/"


@pytest.fixture
def admin():
    ensure_site_defaults("Main")
    user = User.objects.create_user(email="adm@x.test", password="pw-12345678", role="admin")
    c = APIClient()
    c.force_login(user)
    return c


def test_settings_round_trip(admin):
    r = admin.patch(B + "settings/", {"footer_text_en": "Hi", "keywords_ar": "قرآن"}, format="json")
    assert r.status_code == 200
    assert admin.get(B + "settings/").json() == {
        "footer_text_ar": "", "footer_text_en": "Hi", "keywords_ar": "قرآن", "keywords_en": "",
    }


def test_settings_length_limits(admin):
    r = admin.patch(B + "settings/", {"footer_text_en": "x" * 301, "keywords_en": "k" * 256}, format="json")
    assert r.status_code == 400
    assert set(r.json()) >= {"footer_text_en", "keywords_en"}


def test_status_route(admin, set_features):
    set_features(site_status=True)
    assert admin.patch(B + "status/", {"status": "beta"}, format="json").json() == {"status": "beta"}
    assert admin.patch(B + "status/", {"status": "closed"}, format="json").status_code == 400


def test_status_route_404_when_off(admin, set_features):
    set_features(site_status=False)
    assert admin.get(B + "status/").status_code == 404


@pytest.mark.parametrize(
    ("field", "good", "bad"),
    [
        ("ga4_id", "G-ABC123XYZ", "UA-12345-1"),
        ("meta_pixel_id", "123456789012345", "12ab"),
        ("adsense_client", "ca-pub-1234567890123456", "pub-123"),
        ("google_site_verification", "abcDEF_123-xyz", 'x"><script>'),
    ],
)
def test_tracking_validation(admin, set_features, field, good, bad):
    set_features(site_tracking=True)
    assert admin.patch(B + "tracking/", {field: good}, format="json").status_code == 200
    assert admin.patch(B + "tracking/", {field: bad}, format="json").status_code == 400
    assert admin.patch(B + "tracking/", {field: ""}, format="json").status_code == 200


def test_tracking_404_when_off(admin, set_features):
    set_features(site_tracking=False)
    assert admin.get(B + "tracking/").status_code == 404


def test_mass_assignment_is_ignored(set_features, staff_for):
    """Review Focus 5."""
    ensure_site_defaults("Main")
    set_features(site_status=True, site_tracking=True)
    staff = staff_for("site.view", "site.update")
    staff.patch(B + "settings/", {"status": "system_only", "ga4_id": "G-EVIL1", "footer_text_en": "ok"}, format="json")
    staff.patch(B + "status/", {"footer_text_en": "nope", "ga4_id": "G-EVIL2"}, format="json")
    s = SiteSettings.current()
    assert (s.status, s.ga4_id, s.footer_text_en) == ("live", "", "ok")


def test_branding_accepts_new_socials(admin):
    r = admin.patch(B + "branding/", {"linkedin": "https://linkedin.com/company/x"}, format="json")
    assert r.status_code == 200
    assert r.json()["linkedin"] == "https://linkedin.com/company/x"
```

  (Check the `staff_for` fixture's signature in `backend/conftest.py` before using it; adapt the call.)

- [ ] **Step 2: Run, expect 404s/failures.**
- [ ] **Step 3: Implement.** Serializers:

```python
class SiteSettingsAdminSerializer(serializers.ModelSerializer):
    class Meta:
        model = SiteSettings
        fields = ["footer_text_ar", "footer_text_en", "keywords_ar", "keywords_en"]


class SiteStatusAdminSerializer(serializers.ModelSerializer):
    class Meta:
        model = SiteSettings
        fields = ["status"]


class SiteTrackingAdminSerializer(serializers.ModelSerializer):
    class Meta:
        model = SiteSettings
        fields = list(TRACKING_FIELDS)

    def validate(self, attrs):
        errors = {
            f: ["Use the format shown under the field."]
            for f, v in attrs.items()
            if v and not TRACKING_PATTERNS[f].fullmatch(v)
        }
        if errors:
            raise serializers.ValidationError(errors)
        return attrs
```

  Add `linkedin`, `snapchat`, `soundcloud` to `BrandingAdminSerializer.Meta.fields`. Views (in
  `admin_views.py`, reusing `SingletonAdminView` but with `get_object` returning `SiteSettings.current()`):

```python
class SiteSettingsSingletonView(SingletonAdminView):
    model = SiteSettings
    parser_classes = [JSONParser]

    def get_object(self):
        return SiteSettings.current()


class SiteSettingsAdminView(SiteSettingsSingletonView):
    serializer_class = SiteSettingsAdminSerializer


class SiteStatusAdminView(SiteSettingsSingletonView):
    permission_classes = [HasCode, FeatureOn]
    feature = "site_status"
    serializer_class = SiteStatusAdminSerializer


class SiteTrackingAdminView(SiteSettingsSingletonView):
    permission_classes = [HasCode, FeatureOn]
    feature = "site_tracking"
    serializer_class = SiteTrackingAdminSerializer
```

  URLs: `admin/settings/`, `admin/status/`, `admin/tracking/` (names `admin-settings`, `admin-status`,
  `admin-tracking`). Route table — append after the existing site lines in `ROUTES`:

```python
    ("GET", "/api/v1/site/admin/settings/", "site.view"),
    ("PATCH", "/api/v1/site/admin/settings/", "site.update"),
    ("GET", "/api/v1/site/admin/status/", "site.view"),
    ("PATCH", "/api/v1/site/admin/status/", "site.update"),
    ("GET", "/api/v1/site/admin/tracking/", "site.view"),
    ("PATCH", "/api/v1/site/admin/tracking/", "site.update"),
```

  and append to `FEATURES`:

```python
    **dict.fromkeys(
        (("GET", "/api/v1/site/admin/status/"), ("PATCH", "/api/v1/site/admin/status/")),
        "site_status",
    ),
    **dict.fromkeys(
        (("GET", "/api/v1/site/admin/tracking/"), ("PATCH", "/api/v1/site/admin/tracking/")),
        "site_tracking",
    ),
```

  and to `FEATURE_WORDS`: `"/site/admin/status/": "site_status"`, `"/site/admin/tracking/": "site_tracking"`.
- [ ] **Step 4: Run** `etqan/site` and `etqan/access` tests: all pass (the route table tests exercise 403/404
  ordering and the "every other route is there with every feature off" check).
- [ ] **Step 5: Commit** `feat(site): admin settings, status and tracking routes`.

---

### Task 4: `set_site_status` command and demo seed

**Files:**
- Create: `backend/etqan/site/management/__init__.py`, `backend/etqan/site/management/commands/__init__.py`,
  `backend/etqan/site/management/commands/set_site_status.py`, `backend/etqan/tenants/seeds/b8.py`
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (one line under `# ── phase B8 ──`, one
  import)
- Test: `backend/etqan/site/tests/test_set_site_status.py`, `backend/etqan/tenants/tests/` (seed test if one
  exists for other steps — follow it)

**Interfaces:**
- Produces: `manage.py tenant_command set_site_status <status> --schema=<schema>`; `seed_b8(subdomain: str)`
  in `etqan/tenants/seeds/b8.py`.

- [ ] **Step 1: Failing tests:**

```python
import pytest
from django.core.management import CommandError
from django.core.management import call_command

from etqan.site.models import SiteSettings


def test_sets_the_status(capsys):
    call_command("set_site_status", "maintenance")
    assert SiteSettings.current().status == "maintenance"
    assert "maintenance" in capsys.readouterr().out


def test_rejects_unknown_status():
    with pytest.raises(CommandError):
        call_command("set_site_status", "closed")
```

  (The test runs inside the academy schema the root conftest sets, which is what `tenant_command` does in
  production.)

- [ ] **Step 2: Run, expect "Unknown command".**
- [ ] **Step 3: Implement:**

```python
from django.core.management.base import BaseCommand
from django.core.management.base import CommandError

from etqan.site.models import SiteSettings


class Command(BaseCommand):
    help = (
        "Set this academy's public-site status. Run per academy: "
        "manage.py tenant_command set_site_status <status> --schema=<schema>. "
        "The site_status feature must be on for it to take effect."
    )

    def add_arguments(self, parser):
        parser.add_argument("status")

    def handle(self, *args, status, **opts):
        if status not in SiteSettings.Status.values:
            raise CommandError(f"Use one of: {', '.join(SiteSettings.Status.values)}.")
        s = SiteSettings.current()
        s.status = status
        s.save(update_fields=["status", "updated_at"])
        self.stdout.write(self.style.SUCCESS(f"Site status: {status}"))
```

  Seed (`etqan/tenants/seeds/b8.py`): `seed_b8(subdomain)` — for `demo` only, set `SiteSettings.current()`
  `footer_text_ar="أكاديمية ديمو — نعلّم منذ 2015"`, `footer_text_en="Demo Academy — teaching since 2015"`,
  `keywords_ar="دروس خصوصية، قرآن"`, `keywords_en="private tutoring, quran"`; idempotent (plain assignment).
  In `seed_dev.py` under `# ── phase B8 ──`: `seed_b8(subdomain)` (check how neighbouring steps get the
  subdomain in that function and match it).
- [ ] **Step 4: Run** the new tests and the tenants seed tests.
- [ ] **Step 5: Commit** `feat(site): set_site_status command and demo seed`.

---

### Task 5: Marketing — payload types, banner, keywords, tracking, footer, socials

**Files:**
- Modify: `marketing/src/lib/site.ts` (types), `marketing/src/layouts/Layout.astro`,
  `marketing/src/components/Footer.astro`, `marketing/src/lib/i18n.ts` (strings), `marketing/test/fixtures.ts`
- Create: `marketing/src/lib/tracking.ts`, `marketing/src/components/Tracking.astro`
- Test: `marketing/test/settings.test.ts`, `marketing/test/tracking.test.ts`

**Interfaces:**
- Consumes: Task 2 payload.
- Produces: `SitePayload.settings: { status: SiteStatus; footer_text: Pair; keywords: Pair; tracking: Tracking }`,
  `export type SiteStatus = "live" | "maintenance" | "beta" | "system_only"`,
  `export const isClosed = (s: SiteStatus) => s === "maintenance" || s === "system_only"` (in `site.ts`);
  `safeTracking(t: Tracking): Tracking` in `tracking.ts` (returns `""` for any value failing its pattern);
  i18n keys `betaBanner`, `maintenanceTitle`, `maintenanceBody`, `restrictedTitle`, `restrictedBody`,
  `signIn` in both languages.

- [ ] **Step 1: Failing tests.** Update `fixtures.ts`: `social` gains `linkedin: "", snapchat: "", soundcloud: ""`;
  add `settings: { status: "live", footer_text: { ar: "نص التذييل", en: "Footer words" }, keywords: { ar: "قرآن", en: "quran, tutoring" }, tracking: { ga4_id: "", meta_pixel_id: "", adsense_client: "", google_site_verification: "" } }`.
  `tracking.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { safeTracking } from "../src/lib/tracking";

describe("safeTracking", () => {
	it("keeps valid ids", () => {
		const t = { ga4_id: "G-ABC123", meta_pixel_id: "1234567", adsense_client: "ca-pub-1234567890", google_site_verification: "abcdefghij_-" };
		expect(safeTracking(t)).toEqual(t);
	});
	it("blanks anything that fails its pattern (Review Focus 3)", () => {
		expect(
			safeTracking({ ga4_id: 'G-1"><script>', meta_pixel_id: "javascript:1", adsense_client: "ca-pub-x", google_site_verification: "<b>" }),
		).toEqual({ ga4_id: "", meta_pixel_id: "", adsense_client: "", google_site_verification: "" });
	});
});
```

  `settings.test.ts` (AstroContainer, as in `pages.test.ts`):

```ts
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, expect, it } from "vitest";
import Landing from "../src/pages/[lang]/index.astro";
import { demoSite } from "./fixtures";

const withSettings = (patch: Partial<typeof demoSite.settings>, social = {}) => ({
	host: "demo.etqan.localhost",
	siteResult: {
		kind: "ok" as const,
		site: {
			...demoSite,
			branding: { ...demoSite.branding, social: { ...demoSite.branding.social, ...social } },
			settings: { ...demoSite.settings, ...patch },
		},
	},
});

async function render(lang: "ar" | "en", locals = withSettings({})) {
	const c = await AstroContainer.create();
	return c.renderToString(Landing, { params: { lang }, locals });
}

describe("site settings on the landing page", () => {
	it("shows the footer text and keywords in the page language", async () => {
		const en = await render("en");
		expect(en).toContain("Footer words");
		expect(en).toContain('<meta name="keywords" content="quran, tutoring"');
		const ar = await render("ar");
		expect(ar).toContain("نص التذييل");
	});
	it("omits keywords when empty", async () => {
		const html = await render("en", withSettings({ keywords: { ar: "", en: "" } }));
		expect(html).not.toContain('name="keywords"');
	});
	it("shows the beta banner only in beta", async () => {
		expect(await render("en", withSettings({ status: "beta" }))).toContain("data-site-banner");
		expect(await render("en")).not.toContain("data-site-banner");
	});
	it("renders tracking snippets for valid ids only", async () => {
		const html = await render(
			"en",
			withSettings({ tracking: { ga4_id: "G-ABC123", meta_pixel_id: "1234567", adsense_client: "ca-pub-1234567890", google_site_verification: "abcdefghij" } }),
		);
		expect(html).toContain("https://www.googletagmanager.com/gtag/js?id=G-ABC123");
		expect(html).toContain("fbq('init', '1234567')");
		expect(html).toContain("client=ca-pub-1234567890");
		expect(html).toContain('<meta name="google-site-verification" content="abcdefghij"');
		const none = await render("en");
		expect(none).not.toContain("googletagmanager");
		expect(none).not.toContain("fbq(");
		expect(none).not.toContain("adsbygoogle");
	});
	it("links the new social networks", async () => {
		const html = await render("en", withSettings({}, { linkedin: "https://linkedin.com/company/demo" }));
		expect(html).toContain("https://linkedin.com/company/demo");
	});
});
```

- [ ] **Step 2: Run** `docker compose -f docker-compose.local.yml run --rm marketing pnpm vitest run` (or the
  repo's documented test command in `marketing/CLAUDE.md`): failures.
- [ ] **Step 3: Implement.** `tracking.ts`:

```ts
import type { Tracking } from "./site";

const PATTERNS: Record<keyof Tracking, RegExp> = {
	ga4_id: /^G-[A-Z0-9]{4,12}$/,
	meta_pixel_id: /^[0-9]{6,20}$/,
	adsense_client: /^ca-pub-[0-9]{10,20}$/,
	google_site_verification: /^[A-Za-z0-9_-]{10,100}$/,
};

/** Shared decision D2: IDs are the only academy values in these snippets,
 * so re-check each against its pattern here as well as on the API. */
export function safeTracking(t: Tracking): Tracking {
	const out = { ...t };
	for (const key of Object.keys(PATTERNS) as (keyof Tracking)[]) {
		if (!PATTERNS[key].test(t[key] ?? "")) out[key] = "";
	}
	return out;
}
```

  `Tracking.astro` (props `tracking: Tracking`): after `safeTracking`, render
  `<meta name="google-site-verification" content={id}>`; for GA4
  `<script async src={`https://www.googletagmanager.com/gtag/js?id=${ga}`}></script>` plus an inline
  script built as a string with `JSON.stringify(ga)` and `set:html`
  (`window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}gtag('js',new Date());gtag('config',<id>);`);
  for Meta Pixel the standard base code with `fbq('init', '<id>')` and `fbq('track','PageView')` (the id
  is digits only after `safeTracking`, so writing it inside quotes is safe; keep the exact
  `fbq('init', '…')` spacing the test asserts); for AdSense
  `<script async src={`https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${client}`} crossorigin="anonymous"></script>`.
  In `Layout.astro`: `<meta name="keywords">` when `pick(site.settings.keywords, lang)` is non-empty;
  `<Tracking tracking={site.settings.tracking} />` as the last child of `<head>`; as the first child of
  `<body>` when `status === "beta"`: `<p data-site-banner class="bg-accent px-4 py-1 text-center text-sm">{t.betaBanner}</p>`
  (no `role`). `Footer.astro`: `{pick(site.settings.footer_text, lang) && <p>{…}</p>}` above powered-by.
  Strings — en: `betaBanner: "Beta — this site is still being tested"`, `maintenanceTitle: "Under maintenance"`,
  `maintenanceBody: "We'll be back shortly."`, `restrictedTitle: "Restricted area"`,
  `restrictedBody: "This academy's website is not public."`, `signIn: "Sign in"`; ar: `"نسخة تجريبية — هذا الموقع قيد الاختبار"`,
  `"الموقع تحت الصيانة"`, `"سنعود قريباً."`, `"منطقة محظورة"`, `"موقع هذه الأكاديمية غير متاح للعامة."`, `"تسجيل الدخول"`.
- [ ] **Step 4: Run** the marketing suite and `pnpm astro check` / biome as `marketing/CLAUDE.md` says: green.
- [ ] **Step 5: Commit** (marketing) `feat: site settings — beta banner, keywords, tracking, footer text, socials`.

---

### Task 6: Marketing — closed sites

**Files:**
- Modify: `marketing/src/middleware.ts`, `marketing/src/pages/robots.txt.ts`, `marketing/src/pages/sitemap.xml.ts`
- Create: `marketing/src/components/ClosedPage.astro`, `marketing/src/pages/closed-site.astro`
- Test: `marketing/test/closed.test.ts`

**Interfaces:**
- Consumes: Task 5 (`isClosed`, `SiteStatus`, strings).
- Produces: route `/closed-site`; middleware behaviour below.

- [ ] **Step 1: Failing tests** — `closed.test.ts`:

```ts
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { afterEach, describe, expect, it, vi } from "vitest";
import * as site from "../src/lib/site";
import { onRequest } from "../src/middleware";
import ClosedSite from "../src/pages/closed-site.astro";
import { GET as robots } from "../src/pages/robots.txt";
import { GET as sitemap } from "../src/pages/sitemap.xml";
import { demoSite } from "./fixtures";

afterEach(() => vi.restoreAllMocks());

const siteWith = (status: site.SiteStatus) => ({
	...demoSite,
	settings: { ...demoSite.settings, status },
});
const localsFor = (status: site.SiteStatus) => ({
	host: "demo.etqan.localhost",
	siteResult: { kind: "ok" as const, site: siteWith(status) },
});

async function viaMiddleware(status: site.SiteStatus, path: string) {
	vi.spyOn(site, "resolveSite").mockResolvedValue({ kind: "ok", site: siteWith(status) });
	const rewrite = vi.fn(async () => new Response("closed", { status: status === "maintenance" ? 503 : 403 }));
	const next = vi.fn(async () => new Response("page"));
	const res = (await onRequest(
		{
			request: new Request(`http://demo.etqan.localhost${path}`, { headers: { host: "demo.etqan.localhost" } }),
			url: new URL(`http://demo.etqan.localhost${path}`),
			locals: {} as App.Locals,
			rewrite,
		} as never,
		next,
	)) as Response;
	return { res, rewrite, next };
}

describe("closed sites", () => {
	for (const path of ["/", "/en/", "/ar/p/policies", "/en/a/b"]) {
		it(`maintenance rewrites ${path} to the closed page`, async () => {
			const { res, rewrite, next } = await viaMiddleware("maintenance", path);
			expect(rewrite).toHaveBeenCalledWith("/closed-site");
			expect(next).not.toHaveBeenCalled();
			expect(res.status).toBe(503);
			expect(res.headers.get("Retry-After")).toBe("3600");
			expect(res.headers.get("X-Robots-Tag")).toBe("noindex");
		});
		it(`system only rewrites ${path}`, async () => {
			const { res, rewrite } = await viaMiddleware("system_only", path);
			expect(rewrite).toHaveBeenCalledWith("/closed-site");
			expect(res.status).toBe(403);
			expect(res.headers.get("Retry-After")).toBeNull();
			expect(res.headers.get("X-Robots-Tag")).toBe("noindex");
		});
	}
	for (const path of ["/robots.txt", "/sitemap.xml"]) {
		it(`leaves ${path} to its own route`, async () => {
			const { rewrite, next } = await viaMiddleware("maintenance", path);
			expect(rewrite).not.toHaveBeenCalled();
			expect(next).toHaveBeenCalled();
		});
	}
	it("open and beta sites are not rewritten", async () => {
		for (const status of ["live", "beta"] as const) {
			const { rewrite, next } = await viaMiddleware(status, "/en/");
			expect(rewrite).not.toHaveBeenCalled();
			expect(next).toHaveBeenCalled();
		}
	});

	it("the maintenance page is branded, 503 and noindex", async () => {
		const c = await AstroContainer.create();
		const res = await c.renderToResponse(ClosedSite, { locals: localsFor("maintenance") });
		expect(res.status).toBe(503);
		const html = await res.text();
		expect(html).toContain("Under maintenance");
		expect(html).toContain("الموقع تحت الصيانة");
		expect(html).toContain("Demo Academy");
		expect(html).toContain('name="robots" content="noindex"');
		expect(html).not.toContain("googletagmanager");
	});
	it("the restricted page is 403 with a sign-in link", async () => {
		const c = await AstroContainer.create();
		const res = await c.renderToResponse(ClosedSite, { locals: localsFor("system_only") });
		expect(res.status).toBe(403);
		const html = await res.text();
		expect(html).toContain("Restricted area");
		expect(html).toContain('href="/app/"');
	});
	it("/closed-site on an open site is the ordinary 404 (Review Focus 4)", async () => {
		const c = await AstroContainer.create();
		const res = await c.renderToResponse(ClosedSite, { locals: localsFor("live") });
		expect(res.status).toBe(404);
		expect(await res.text()).not.toContain("Restricted area");
	});

	it("robots and sitemap follow the status", async () => {
		const call = (fn: typeof robots, status: site.SiteStatus) => fn({ locals: localsFor(status) } as never) as Promise<Response>;
		expect(await (await call(robots, "system_only")).text()).toBe("User-agent: *\nDisallow: /\n");
		expect((await call(robots, "maintenance")).status).toBe(200);
		expect((await call(sitemap, "system_only")).status).toBe(404);
		expect((await call(sitemap, "maintenance")).status).toBe(503);
		expect((await call(sitemap, "beta")).status).toBe(200);
	});
});
```

- [ ] **Step 2: Run, expect failures.**
- [ ] **Step 3: Implement.** Middleware, after `context.locals.siteResult = siteResult;`:

```ts
	const path = new URL(context.request.url).pathname;
	const status = siteResult.kind === "ok" ? siteResult.site.settings.status : "live";
	let response: Response;
	if (isClosed(status) && path !== "/robots.txt" && path !== "/sitemap.xml") {
		// B8a A-20: every path of a closed site answers with the closed page.
		response = await context.rewrite("/closed-site");
		response.headers.set("X-Robots-Tag", "noindex");
		if (status === "maintenance") response.headers.set("Retry-After", "3600");
	} else {
		response = await next();
		// existing 404 → 503 rewrite for suspended/unavailable stays here
	}
```

  (keep the existing `nosniff` / `Referrer-Policy` headers on every response; if `context.rewrite`
  returns a response with immutable headers, copy into `new Response(body, {status, headers})` as the
  existing 503 branch does.) `ClosedPage.astro` (props `site`, `status: "maintenance" | "system_only"`):
  a standalone document like `StatusPage.astro` — `<meta name="robots" content="noindex">`, the brand CSS
  vars and logo/name from `site.branding`, Arabic and English title/body, and for `system_only` an
  `<a href="/app/">` with `signIn`; sets `Astro.response.status` (503 / 403). It never renders `Tracking`.
  `pages/closed-site.astro`: if `siteResult.kind === "ok"` and `isClosed(status)` → `<ClosedPage>`; else
  render exactly what `404.astro` renders (import and reuse its components; `Astro.response.status = 404`).
  `robots.txt.ts`: when ok and status `system_only` → `"User-agent: *\nDisallow: /\n"`. `sitemap.xml.ts`:
  `system_only` → 404 `"Not found"`, `maintenance` → 503 `"Unavailable"`.
- [ ] **Step 4: Run** the full marketing suite + coverage + lint: green. Also smoke the real stack:
  `curl -s -o /dev/null -w '%{http_code}' http://demo.etqan.localhost:8380/en/` → 200 (demo is live).
- [ ] **Step 5: Commit** `feat: closed sites — maintenance and system-only pages`.

---

### Task 7: Dashboard — Website → Settings tab, branding socials

**Files:**
- Modify: `dashboard/src/features/website/{api.ts,queries.ts,schemas.ts,BrandingForm.tsx,index.ts}`,
  `dashboard/src/features/shell/nav.ts` (`WEBSITE_TABS`), `dashboard/src/features/identity/schemas.ts`
  (`FeatureCode`), `dashboard/src/locales/{en,ar}/website.json`, `dashboard/src/routeTree.gen.ts`
  (regenerated)
- Create: `dashboard/src/features/website/SiteSettingsForm.tsx`, `dashboard/src/routes/_authed/website.settings.tsx`
- Test: `dashboard/src/features/website/SiteSettingsForm.test.tsx`, existing `BrandingForm.test.tsx`

**Interfaces:**
- Consumes: Task 3 routes.
- Produces: `websiteApi.getSettings/patchSettings/getStatus/patchStatus/getTracking/patchTracking`;
  hooks `useSiteSettings`, `useUpdateSiteSettings`, `useSiteStatus(enabled: boolean)`, `useUpdateSiteStatus`,
  `useSiteTracking(enabled: boolean)`, `useUpdateSiteTracking`; zod `siteSettingsSchema`, `trackingSchema`;
  `type SiteStatus = "live" | "maintenance" | "beta" | "system_only"`.

- [ ] **Step 1: Failing tests** — `SiteSettingsForm.test.tsx`, following `HomePageForm.test.tsx`'s setup
  (mock `./api`, `QueryClientProvider`, `CanProvider` with `staffMe`/admin fixtures from
  `@/test/access-fixtures`; find there how a test supplies features to `hasFeature` and use the same
  provider). Cases:
  1. Renders "Footer and SEO" with Arabic + English footer text and keywords; saving calls
     `patchSettings` with exactly `{footer_text_ar, footer_text_en, keywords_ar, keywords_en}`.
  2. With `site_status` off: no "Site status" card and `getStatus` not called. On: four radios
     (Live, Under maintenance, Beta, System only) and the "within a minute" hint; choosing Beta and saving
     calls `patchStatus({status: "beta"})`.
  3. With `site_tracking` off: no "Analytics and ads" card. On: entering `UA-1` in GA4 shows the format
     error and does not call `patchTracking`; `G-ABC123` saves.
  4. Without `site.update`: inputs disabled, no save buttons.
  `BrandingForm.test.tsx`: add a case that LinkedIn, Snapchat and SoundCloud inputs render and are sent.
- [ ] **Step 2: Run** `docker compose -f docker-compose.local.yml run --rm dashboard pnpm vitest run src/features/website`: failures.
- [ ] **Step 3: Implement.**
  - `schemas.ts`: add `linkedin`, `snapchat`, `soundcloud: optionalUrl` to `brandingSchema`;

```ts
export const siteSettingsSchema = z.object({
	footer_text_ar: z.string().max(300),
	footer_text_en: z.string().max(300),
	keywords_ar: z.string().max(255),
	keywords_en: z.string().max(255),
});
export type SiteSettings = z.infer<typeof siteSettingsSchema>;
export const SITE_STATUSES = ["live", "maintenance", "beta", "system_only"] as const;
export type SiteStatus = (typeof SITE_STATUSES)[number];
const idOrEmpty = (re: RegExp) => z.string().refine((v) => v === "" || re.test(v), { message: "format" });
export const trackingSchema = z.object({
	ga4_id: idOrEmpty(/^G-[A-Z0-9]{4,12}$/),
	meta_pixel_id: idOrEmpty(/^[0-9]{6,20}$/),
	adsense_client: idOrEmpty(/^ca-pub-[0-9]{10,20}$/),
	google_site_verification: idOrEmpty(/^[A-Za-z0-9_-]{10,100}$/),
});
export type Tracking = z.infer<typeof trackingSchema>;
```

  - `api.ts`: `getSettings` → `GET site/admin/settings/`, `patchSettings(d)` → PATCH; same for `status/`
    and `tracking/`. `queries.ts`: query keys `["website","settings"]`, `["website","status"]`,
    `["website","tracking"]`; the status/tracking queries take `enabled` so they never fire while the
    feature is off.
  - `SiteSettingsForm.tsx`: three `Card`s (use the `@/ui` components `BrandingForm` uses), each its own
    react-hook-form + zodResolver form and save button; Footer/SEO with `BilingualField`; Status as a radio
    group of `SITE_STATUSES` with `website.settings.status.<value>.label` / `.hint`; Tracking with four
    monospace inputs and format hints. Cards 2 and 3 render only when `hasFeature("site_status")` /
    `hasFeature("site_tracking")`; editing needs `can("site.update")`.
  - `BrandingForm.tsx`: `SOCIAL_FIELDS` gains `"linkedin", "snapchat", "soundcloud"`; `toDefaults` maps them.
  - `nav.ts` `WEBSITE_TABS`: append `{ to: "/website/settings", labelKey: "website.nav.settings", code: "site.view" }`.
  - `identity/schemas.ts` `FeatureCode`: append `| "site_status" | "site_tracking"`.
  - Route `website.settings.tsx`, as `website.home.tsx` with `staticData: { permission: "site.view" }`,
    title `website.nav.settings`, rendering `SiteSettingsForm`. Regenerate `routeTree.gen.ts` with the
    repo's generator (see `dashboard/CLAUDE.md`), never by hand.
  - `website.json` (en / ar, key-for-key): `nav.settings` "Settings" / "الإعدادات";
    `branding.social.linkedin|snapchat|soundcloud`; `settings.footerSeo.title` "Footer and SEO" / "التذييل
    وتحسين الظهور", `settings.footerText` "Footer text" / "نص التذييل", `settings.keywords` "Keywords
    (comma-separated)" / "الكلمات المفتاحية (مفصولة بفواصل)"; `settings.status.title` "Site status" / "حالة
    الموقع", `settings.status.delay` "Changes reach the public site within a minute." / "تظهر التغييرات على
    الموقع العام خلال دقيقة."; per status `label`/`hint`: live "Live" — "Everyone can see the site." / "يعمل"
    — "الموقع متاح للجميع."; maintenance "Under maintenance" — "Visitors see a maintenance page; the
    dashboard keeps working." / "تحت الصيانة" — "يرى الزوار صفحة صيانة، وتعمل لوحة التحكم كالمعتاد.";
    beta "Beta" — "The site works and shows a beta banner." / "تجريبي" — "يعمل الموقع مع شريط يوضح أنه
    تجريبي."; system_only "System only" — "The public site is closed; only sign-in works." / "النظام فقط" —
    "الموقع العام مغلق، ويعمل تسجيل الدخول فقط."; `settings.tracking.title` "Analytics and ads" / "التحليلات
    والإعلانات", field labels "Google Analytics 4 ID" / "معرّف Google Analytics 4", "Meta Pixel ID" /
    "معرّف Meta Pixel", "AdSense publisher ID" / "معرّف ناشر AdSense", "Google Search Console verification" /
    "رمز التحقق من Google Search Console"; hints "Format: G-XXXXXXX", "Digits only", "Format:
    ca-pub-0000000000", "The content value of the verification meta tag"; `settings.tracking.formatError`
    "Use the format shown under the field." / "استخدم الصيغة الموضحة أسفل الحقل.".
- [ ] **Step 4: Run** the website tests, `pnpm tsc --noEmit`, the locale key-equality test, biome, and the
  full dashboard suite with coverage: green.
- [ ] **Step 5: Commit** (dashboard) `feat(website): Settings tab — footer/SEO, site status, analytics IDs; three socials`.

---

### Task 8: e2e journey

**Files:**
- Create: `dashboard/e2e/b8-site-settings.spec.ts`

**Interfaces:**
- Consumes: everything above; `manage()` from `e2e/manage.ts`; `login`, `DEMO_URL`, `DEMO_ADMIN` from
  `e2e/fixtures.ts`; `E2E_BASE_URL`-style host building as `fixtures.ts` does for `OTHER_URL`.

- [ ] **Step 1: Write the spec.**

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, login } from "./fixtures";
import { manage } from "./manage";

// Spec 2026-10-03-b8a §5. Polls ride out the marketing site's 60 s payload cache.
const POLL = { timeout: 90_000, intervals: [2_000, 5_000] };
const B8_URL = DEMO_URL.replace("//demo.", "//b8site.");
const SEEDED_FOOTER_EN = "Demo Academy — teaching since 2015";

test.describe.configure({ mode: "serial" });

test("an admin edits footer text and analytics, and the public site shows them", async ({ page }) => {
	test.setTimeout(240_000);
	const footer = `B8 footer ${Date.now()}`;
	await login(page, DEMO_URL, DEMO_ADMIN);
	await page.goto(`${DEMO_URL}/app/website/settings`);
	await expect(page.getByRole("heading", { name: "Site status" })).toBeVisible();
	await page.getByLabel("Footer text (English)").fill(footer);
	await page.getByRole("button", { name: "Save" }).first().click();
	await page.getByLabel("Google Analytics 4 ID").fill("G-B8E2E01");
	await page.getByRole("button", { name: "Save" }).last().click();
	await expect
		.poll(async () => (await page.request.get(`${DEMO_URL}/en/`)).text(), POLL)
		.toContain(footer);
	expect(await (await page.request.get(`${DEMO_URL}/en/`)).text()).toContain("gtag/js?id=G-B8E2E01");
	// Leave demo as seeded for the other suites.
	await page.getByLabel("Footer text (English)").fill(SEEDED_FOOTER_EN);
	await page.getByRole("button", { name: "Save" }).first().click();
	await page.getByLabel("Google Analytics 4 ID").fill("");
	await page.getByRole("button", { name: "Save" }).last().click();
	await expect(page.getByText("Saved").last()).toBeVisible();
});

test("a closed site answers every path with its closed page", async ({ page }) => {
	test.setTimeout(360_000);
	try {
		manage("create_academy", "--name", "B8 Site", "--subdomain", "b8site", "--admin-email", "b8site-admin@e2e.test");
	} catch (e) {
		if (!String(e).match(/exist|taken|already/i)) throw e;
	}
	manage("set_features", "b8site", "--on", "site_status");
	const status = (s: string) => manage("tenant_command", "set_site_status", s, "--schema=academy_b8site");
	status("maintenance"); // before any visit: the first request is uncached
	const first = await page.request.get(`${B8_URL}/en/`);
	expect(first.status()).toBe(503);
	expect(first.headers()["retry-after"]).toBe("3600");
	expect(await first.text()).toContain("Under maintenance");
	expect((await page.request.get(`${B8_URL}/app/login`)).status()).toBe(200);

	status("system_only");
	await expect.poll(async () => (await page.request.get(`${B8_URL}/en/a/b`)).status(), POLL).toBe(403);
	await page.goto(`${B8_URL}/en/`);
	await expect(page.getByText("Restricted area")).toBeVisible();
	await expect(page.getByRole("link", { name: "Sign in" })).toHaveAttribute("href", "/app/");

	status("beta");
	await expect
		.poll(async () => (await page.request.get(`${B8_URL}/en/`)).text(), POLL)
		.toContain("data-site-banner");
	status("live");
});
```

  Before running, confirm: the schema name `create_academy` gives (`academy_<subdomain>`, as
  `notifications.spec.ts` shows with `academy_demo`); the exact error text `create_academy` raises for an
  existing subdomain (adjust the regex); the field labels `BilingualField` produces (adjust `getByLabel`);
  and that `DEMO_URL`'s host form makes the `replace` correct.
- [ ] **Step 2: Run** `just e2e b8-site-settings` (stack up via `just dev-backend`, after `just migrate` /
  seed if the recipes require). Fix until green. Then run the full `just e2e` to prove no other suite
  regressed.
- [ ] **Step 3: Commit** (dashboard) `test(e2e): B8a site settings and closed sites`.

---

### Task 9: Slice wrap-up

- [ ] `just test`, `just lint`, `just e2e` — all green; note results in the phase notes.
- [ ] Final whole-slice review by a fresh reviewer (spec + this plan + diff of all four repos).
- [ ] Commit the plan's checkboxes (meta) and `queue B8a`.
