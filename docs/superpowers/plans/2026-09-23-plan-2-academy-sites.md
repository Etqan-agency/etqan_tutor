# Plan 2 — Academy Sites, Branding and Custom Domains — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every academy gets its own bilingual public website (subdomain or custom domain), and its own name, logo and colours on its site, dashboard and emails.

**Architecture:** A new tenant app `etqan.site` (backend) stores branding and site content per academy schema and serves it over public read-only endpoints. A new Astro SSR repo `etqan_tutor_marketing` renders each academy's site by forwarding the visitor's `Host` to that API. The dashboard moves to `/app/` and brands itself at runtime from the same API. Caddy replaces Traefik as the edge (path routing per host, wildcard certificate, on-demand certificates for custom domains gated by Django). Custom domains are `Domain` rows with a `pending → active → disabled` lifecycle; only `active` domains resolve.

**Tech Stack:** Django 6 / DRF / django-tenants 3.14, `nh3` (HTML sanitiser), Pillow, django-storages[s3]; React 19 + TanStack Router/Query + Vite (base `/app/`), TipTap (rich text); Astro 6 SSR (`@astrojs/node` standalone) + Tailwind v4 + `@etqan/tokens`, Vitest with the Astro container API; Caddy 2 (+ `caddy-dns/cloudflare` in production); Playwright.

**Spec:** `docs/superpowers/specs/2026-09-23-academy-sites-design.md` (amends `2026-09-23-etqan-tutor-v1-design.md`).

## Global Constraints

- Repos: all private, prefix `etqan_tutor`. New repo: `Etqan-agency/etqan_tutor_marketing`, submodule path `marketing/`. Feature branch in every touched repo: `feat/academy-sites`; trunks `master` (meta) / `main` (submodules). No merges without the user's approval.
- Every public text field exists as `<field>_ar` and `<field>_en`; both required whenever the field is required.
- Public endpoints: `GET /api/v1/site/`, `GET /api/v1/site/branding/`, `GET /api/v1/site/pages/<slug>/` (`AllowAny`, `Cache-Control: public, max-age=60`); `POST /api/v1/site/inquiries/` (`AllowAny`, no session auth, throttled).
- Admin endpoints under `/api/v1/site/admin/…`, only for `request.user.role == "admin"`.
- Path routing on every academy host: `/api/*`, `/accounts/*`, `/health/*`, `/media/*` → Django; `/app/*` → dashboard; everything else → Astro. Bare base domain → Django only. `/internal/*` is never reachable from outside Caddy.
- Dashboard: Vite `base: "/app/"`, router `basepath: "/app"`. Emailed app links are `<academy origin>/app/<route>`.
- Astro cache: 60 s per host for 200s, 30 s for 404/403. Astro resolves the academy only through `GET <SITE_API_ORIGIN>/api/v1/site/` with header `Host: <visitor host>`.
- Uploads: `tenants/<schema_name>/site/<kind>/<uuid>.<ext>`; logo ≤ 1 MB, favicon ≤ 256 KB, share/hero image ≤ 2 MB; images re-encoded with Pillow.
- Colours `#RRGGBB`; must reach contrast ≥ 4.5:1 against `#FFFFFF` or `#111111`; the passing one is stored as the text colour.
- Rich text allow-list: `p h2 h3 ul ol li strong em a blockquote br`; `a` attrs `href target`; URL schemes `http https mailto tel`; `rel="noopener nofollow"` forced.
- Inquiry throttles: `inquiry_ip` 10/hour, `inquiry_email` 5/hour; honeypot field `website`.
- Backend coverage ≥ 80%; dashboard floors lines 80 / branches 70 / functions 70 / statements 80; marketing floors lines 80 / branches 70 / functions 70 / statements 80.
- Dev seeded password `e2e-EtqanTest-2026`; academies `demo` ("Demo Academy" / "أكاديمية ديمو", `#0E7C66`) and `other` ("Other Academy" / "أكاديمية أخرى", `#7A2E8E`).
- Commit messages: Conventional Commits, ending with exactly `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Local test services: Postgres `postgres://etqan:etqan@localhost:55432/etqan`, Redis `redis://localhost:56379/0`; backend venv `backend/.venv`; pnpm via `npx pnpm@10`.

### Decisions this plan makes where the spec is silent or unsafe
- **P1 — No SVG uploads.** The spec allowed SVG logos; SVG can carry scripts and can't be re-encoded by Pillow. Logos accept PNG/JPEG/WebP; favicons PNG/ICO.
- **P2 — Email language.** Users have no locale field yet (Plan 3 adds it). Until then: From display name and subject prefix use `name_en`; the email layout shows both names. Plan 3 switches to the recipient's locale.
- **P3 — `ALLOWED_HOSTS = ["*"]` in local and production.** Custom domains are unknown at deploy time; django-tenants already 404s any host that is not an active `Domain`, and Caddy only forwards hosts it holds certificates for. Test settings keep an explicit list.
- **P4 — Inquiry endpoint has `authentication_classes = []`.** Visitors who are also logged into `/app/` on the same host would otherwise hit DRF's session CSRF check.
- **P5 — No `www.` → apex redirect yet.** The spec's optional redirect when both `www.` and the apex are registered is deferred; both hosts serve the site and canonical tags point at the primary domain, so search engines see one site. Added to the next plan's backlog.

## Review Focus

- **A visitor on academy B's host must never see academy A's branding, pages or inquiries** — including through the Astro cache (keyed by host) and absolute media URLs. Tests in Tasks 5, 11, 15.
- **A `pending` or `disabled` custom domain must 404 on every path and must not get a certificate.** Tests in Task 1.
- **Rich text from an academy admin must not execute script on the public site** (`<script>`, `onerror=`, `javascript:` links). Tests in Task 3.
- **A logged-in dashboard user submitting the public contact form must succeed** (no CSRF failure), and the honeypot/throttles must stop floods. Tests in Task 6.
- **Existing emailed links (reset, verify, set-password, security alerts) must land on `/app/…`** after the move, not the marketing site. Tests in Task 8.

---

## File Structure

```
backend/
  etqan/tenants/
    models.py            Domain.status / verified_at / is_custom
    middleware.py        + ActiveDomainTenantMiddleware
    services.py          + add_custom_domain, check_domain_dns, activate_domain, make_primary, disable_domain, is_tls_allowed
    admin.py             + DomainAdmin, DomainInline
    views.py             NEW: tls_allowed (internal)
  etqan/site/            NEW tenant app
    apps.py models.py sanitize.py colors.py uploads.py services.py emails.py permissions.py throttling.py
    api/{__init__,serializers,views,urls}.py
    tests/...
  etqan/platform/frontend.py   + app_url(path)
  config/settings/{base,local,test,production}.py, config/urls_public.py, config/api_router.py
dashboard/
  vite.config.ts, src/main.tsx, nginx.conf, Dockerfile
  src/features/branding/{api,queries,apply,BrandProvider}.ts(x)
  src/features/website/…  (api, schemas, forms, RichTextEditor)
  src/routes/_authed/website/{index,branding,home,pages,pages.$id,testimonials,inquiries}.tsx
  src/features/shell/{nav.ts,AppTopbar.tsx}, src/ui/auth-layout.tsx
  e2e/{fixtures.ts, tenant-login.spec.ts, academy-sites.spec.ts}
marketing/               NEW submodule Etqan-agency/etqan_tutor_marketing
  astro.config.mjs package.json Dockerfile vitest.config.ts
  src/middleware.ts src/env.d.ts
  src/lib/{site,http,i18n,seo}.ts
  src/layouts/Layout.astro
  src/components/{Header,Footer,Hero,About,Testimonials,ContactForm,PageBody,StatusPage}.astro
  src/pages/{index.astro,[lang]/index.astro,[lang]/p/[slug].astro,sitemap.xml.ts,robots.txt.ts}
  test/*.test.ts test/fixtures.ts
infra/
  caddy/{Dockerfile,Caddyfile}   docker-compose.production.yml  scripts/ship.sh  .env.production.example
meta: docker-compose.local.yml (Caddy), caddy/Caddyfile.local, .gitmodules, justfile, scripts/check-token-pin.mjs, .github/workflows/ci.yml, CLAUDE.md, STATE.md
```

---

### Task 1: Domain lifecycle, active-only resolution, TLS gate

**Files:**
- Modify: `backend/etqan/tenants/models.py`, `backend/etqan/tenants/middleware.py`, `backend/etqan/tenants/services.py`, `backend/config/settings/base.py` (MIDDLEWARE, new settings), `backend/config/urls_public.py`
- Create: `backend/etqan/tenants/views.py`, migration `backend/etqan/tenants/migrations/0002_domain_status.py` (generated, then edited), `backend/etqan/tenants/tests/test_domains.py`

**Interfaces:**
- Produces: `Domain.Status` (`PENDING="pending"`, `ACTIVE="active"`, `DISABLED="disabled"`), fields `Domain.status`, `Domain.verified_at`, `Domain.is_custom`; middleware `etqan.tenants.middleware.ActiveDomainTenantMiddleware`; services `add_custom_domain(academy, hostname) -> Domain`, `check_domain_dns(domain, resolve=socket.getaddrinfo) -> tuple[bool, list[str]]`, `activate_domain(domain)`, `make_primary(domain)`, `disable_domain(domain)`, `is_tls_allowed(hostname) -> bool`; view `GET /internal/tls-allowed?domain=` on the public URLconf; settings `EDGE_HOSTNAME` (default `sites.<TENANT_BASE_DOMAIN>`), `EDGE_PUBLIC_IP` (default `""`).

- [ ] **Step 1: Write the failing tests** — `backend/etqan/tenants/tests/test_domains.py`

```python
import pytest
from django.db import connection
from rest_framework.test import APIClient

from etqan.platform.exceptions import ValidationError
from etqan.tenants import services
from etqan.tenants.models import Domain

PUBLIC = "etqan.localhost"


@pytest.fixture
def in_public():
    connection.set_schema_to_public()


@pytest.mark.django_db
def test_subdomains_are_active_and_not_custom(tenants):
    d = Domain.objects.get(domain="pytest-other.etqan.localhost")
    assert d.status == Domain.Status.ACTIVE
    assert d.is_custom is False


@pytest.mark.django_db
def test_add_custom_domain_is_pending(in_public, tenants):
    d = services.add_custom_domain(tenants.other, "Noor-Academy.com ")
    assert d.domain == "noor-academy.com"
    assert d.status == Domain.Status.PENDING
    assert d.is_custom is True
    assert d.is_primary is False


@pytest.mark.django_db
@pytest.mark.parametrize("bad", ["", "no_dots", "x.etqan.localhost", "-a.com", "a..com", "http://a.com"])
def test_add_custom_domain_rejects_bad_hosts(in_public, tenants, bad):
    with pytest.raises(ValidationError):
        services.add_custom_domain(tenants.other, bad)


@pytest.mark.django_db
def test_pending_domain_404s(in_public, tenants):
    services.add_custom_domain(tenants.other, "pending.example")
    resp = APIClient().get("/api/v1/identity/csrf/", HTTP_HOST="pending.example")
    assert resp.status_code == 404


@pytest.mark.django_db
def test_active_domain_serves_its_academy(in_public, tenants):
    d = services.add_custom_domain(tenants.other, "live.example")
    services.activate_domain(d)
    resp = APIClient().get("/api/v1/identity/csrf/", HTTP_HOST="live.example")
    assert resp.status_code == 200


@pytest.mark.django_db
def test_disabled_domain_404s(in_public, tenants):
    d = services.add_custom_domain(tenants.other, "gone.example")
    services.activate_domain(d)
    services.disable_domain(d)
    assert APIClient().get("/api/v1/identity/csrf/", HTTP_HOST="gone.example").status_code == 404


@pytest.mark.django_db
def test_check_dns_compares_with_edge(in_public, tenants, settings):
    settings.EDGE_HOSTNAME = "sites.etqan.localhost"
    d = services.add_custom_domain(tenants.other, "dns.example")

    def fake(host, *_a, **_k):
        ips = {"sites.etqan.localhost": "203.0.113.7", "dns.example": "203.0.113.7"}
        return [(2, 1, 6, "", (ips[host], 0))]

    ok, seen = services.check_domain_dns(d, resolve=fake)
    assert ok is True
    assert seen == ["203.0.113.7"]


@pytest.mark.django_db
def test_check_dns_mismatch(in_public, tenants, settings):
    settings.EDGE_HOSTNAME = "sites.etqan.localhost"
    d = services.add_custom_domain(tenants.other, "wrong.example")

    def fake(host, *_a, **_k):
        ips = {"sites.etqan.localhost": "203.0.113.7", "wrong.example": "198.51.100.1"}
        return [(2, 1, 6, "", (ips[host], 0))]

    ok, seen = services.check_domain_dns(d, resolve=fake)
    assert ok is False
    assert seen == ["198.51.100.1"]


@pytest.mark.django_db
def test_make_primary_requires_active(in_public, tenants):
    d = services.add_custom_domain(tenants.other, "p.example")
    with pytest.raises(ValidationError):
        services.make_primary(d)
    services.activate_domain(d)
    services.make_primary(d)
    assert tenants.other.get_primary_domain().domain == "p.example"


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("host", "expected"),
    [("ok.example", 200), ("pending2.example", 404), ("unknown.example", 404), ("", 404)],
)
def test_tls_allowed(in_public, tenants, client, host, expected):
    ok = services.add_custom_domain(tenants.other, "ok.example")
    services.activate_domain(ok)
    services.add_custom_domain(tenants.other, "pending2.example")
    resp = client.get(f"/internal/tls-allowed?domain={host}", HTTP_HOST=PUBLIC)
    assert resp.status_code == expected


@pytest.mark.django_db
def test_tls_not_served_on_academy_hosts(client):
    assert client.get("/internal/tls-allowed?domain=x", HTTP_HOST="testserver").status_code == 404
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && DATABASE_URL=postgres://etqan:etqan@localhost:55432/etqan .venv/bin/pytest etqan/tenants/tests/test_domains.py -q`
Expected: FAIL — `AttributeError: type object 'Domain' has no attribute 'Status'`.

- [ ] **Step 3: Model**

Replace `class Domain(DomainMixin): pass` in `etqan/tenants/models.py` with:

```python
class Domain(DomainMixin):
    """A hostname that serves one academy. Only ACTIVE domains resolve."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending DNS"
        ACTIVE = "active", "Active"
        DISABLED = "disabled", "Disabled"

    status = models.CharField(max_length=16, choices=Status.choices, default=Status.ACTIVE)
    is_custom = models.BooleanField(default=False)
    verified_at = models.DateTimeField(null=True, blank=True)
```

Run `.venv/bin/python manage.py makemigrations tenants --name domain_status` (with `DJANGO_SETTINGS_MODULE=config.settings.test`). The default `ACTIVE` makes every existing row active and non-custom, as the spec requires.

- [ ] **Step 4: Middleware**

Append to `etqan/tenants/middleware.py`:

```python
from django_tenants.middleware.main import TenantMainMiddleware


class ActiveDomainTenantMiddleware(TenantMainMiddleware):
    """Resolve the academy only from ACTIVE domains; pending/disabled hosts 404."""

    def get_tenant(self, domain_model, hostname):
        domain = domain_model.objects.select_related("tenant").get(
            domain=hostname, status=domain_model.Status.ACTIVE
        )
        return domain.tenant
```

In `config/settings/base.py` replace `"django_tenants.middleware.main.TenantMainMiddleware"` with `"etqan.tenants.middleware.ActiveDomainTenantMiddleware"` (still first). Add after `TENANT_URL_TEMPLATE`:

```python
# The edge (Caddy) hostname custom domains must CNAME to, and its public IP for apex A records.
EDGE_HOSTNAME = env("DJANGO_EDGE_HOSTNAME", default=f"sites.{TENANT_BASE_DOMAIN}")
EDGE_PUBLIC_IP = env("DJANGO_EDGE_PUBLIC_IP", default="")
```

- [ ] **Step 5: Services** — append to `etqan/tenants/services.py`:

```python
import socket

from django.utils import timezone

HOSTNAME_RE = re.compile(r"^(?=.{4,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")


def add_custom_domain(academy: Academy, hostname: str) -> Domain:
    value = hostname.strip().lower().rstrip(".")
    if not HOSTNAME_RE.fullmatch(value):
        raise ValidationError("Enter a domain like academy-name.com.", field="domain")
    base = settings.TENANT_BASE_DOMAIN
    if value == base or value.endswith("." + base):
        raise ValidationError("Use the academy's own domain, not an Etqan subdomain.", field="domain")
    if Domain.objects.filter(domain=value).exists():
        raise ValidationError("This domain is already attached.", field="domain")
    return Domain.objects.create(
        domain=value, tenant=academy, is_primary=False,
        is_custom=True, status=Domain.Status.PENDING,
    )


def _addresses(host: str, resolve) -> list[str]:
    try:
        infos = resolve(host, None)
    except OSError:
        return []
    return sorted({info[4][0] for info in infos})


def check_domain_dns(domain: Domain, resolve=socket.getaddrinfo) -> tuple[bool, list[str]]:
    """Does the domain resolve to the edge? Returns (ok, addresses the domain resolved to)."""
    seen = _addresses(domain.domain, resolve)
    expected = set(_addresses(settings.EDGE_HOSTNAME, resolve))
    if settings.EDGE_PUBLIC_IP:
        expected.add(settings.EDGE_PUBLIC_IP)
    return (bool(seen) and bool(expected) and set(seen) <= expected, seen)


def activate_domain(domain: Domain) -> None:
    domain.status = Domain.Status.ACTIVE
    domain.verified_at = timezone.now()
    domain.save(update_fields=["status", "verified_at"])


def disable_domain(domain: Domain) -> None:
    if domain.is_primary and not domain.is_custom:
        raise ValidationError("The academy's own subdomain cannot be disabled.", field="domain")
    domain.status = Domain.Status.DISABLED
    domain.is_primary = False
    domain.save(update_fields=["status", "is_primary"])
    if not Domain.objects.filter(tenant=domain.tenant, is_primary=True).exists():
        Domain.objects.filter(tenant=domain.tenant, is_custom=False).update(is_primary=True)


@transaction.atomic
def make_primary(domain: Domain) -> None:
    if domain.status != Domain.Status.ACTIVE:
        raise ValidationError("Only an active domain can be primary.", field="domain")
    Domain.objects.filter(tenant=domain.tenant).exclude(pk=domain.pk).update(is_primary=False)
    domain.is_primary = True
    domain.save(update_fields=["is_primary"])


def is_tls_allowed(hostname: str) -> bool:
    value = (hostname or "").strip().lower()
    return bool(value) and Domain.objects.filter(domain=value, status=Domain.Status.ACTIVE).exists()
```

- [ ] **Step 6: Internal view** — `etqan/tenants/views.py`:

```python
from django.http import HttpResponse
from django.http import HttpResponseNotFound

from etqan.tenants.services import is_tls_allowed


def tls_allowed(request):
    """Caddy's on-demand TLS `ask` hook. Blocked from the internet at the edge."""
    if is_tls_allowed(request.GET.get("domain", "")):
        return HttpResponse("ok")
    return HttpResponseNotFound()
```

In `config/urls_public.py` add `from etqan.tenants.views import tls_allowed` and `path("internal/tls-allowed", tls_allowed, name="tls-allowed"),`. Add `"internal/"` to `ALLOWED_UNVERSIONED` in `tests/test_api_versioning_is_enforced.py` only if that test walks the public URLconf (it walks `ROOT_URLCONF`, the academy URLconf, so no change is expected — verify).

- [ ] **Step 7: Run tests, suite, linters**

Run: `.venv/bin/pytest etqan/tenants -q && .venv/bin/pytest -q && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(tenants): custom domain lifecycle, active-only resolution and TLS gate

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Domain admin for Etqan staff

**Files:**
- Modify: `backend/etqan/tenants/admin.py`
- Test: `backend/etqan/tenants/tests/test_domain_admin.py`

**Interfaces:**
- Consumes: Task 1 services.
- Produces: admin at `/admin/tenants/domain/` with add form (academy, domain), list (domain, academy, status, primary, custom, verified_at), actions `check_dns`, `make_primary_action`, `disable_action`; `AcademyAdmin` shows a read-only `DomainInline` plus the DNS instructions.

- [ ] **Step 1: Failing tests** — `backend/etqan/tenants/tests/test_domain_admin.py`

```python
import pytest
from django.db import connection

from etqan.identity.models import User
from etqan.tenants import services
from etqan.tenants.models import Domain

PUBLIC = "etqan.localhost"


@pytest.fixture
def staff_client(client):
    connection.set_schema_to_public()
    staff = User.objects.create_superuser(email="ops2@etqan.test", password="pw-12345678")
    client.force_login(staff)
    return client


@pytest.mark.django_db
def test_add_custom_domain_via_admin(staff_client, tenants):
    resp = staff_client.post(
        "/admin/tenants/domain/add/",
        {"tenant": tenants.other.pk, "domain": "noor.example"},
        HTTP_HOST=PUBLIC,
    )
    assert resp.status_code == 302, resp.content[:1500]
    connection.set_schema_to_public()
    d = Domain.objects.get(domain="noor.example")
    assert (d.status, d.is_custom, d.is_primary) == ("pending", True, False)


@pytest.mark.django_db
def test_admin_rejects_etqan_subdomain(staff_client, tenants):
    resp = staff_client.post(
        "/admin/tenants/domain/add/",
        {"tenant": tenants.other.pk, "domain": "x.etqan.localhost"},
        HTTP_HOST=PUBLIC,
    )
    assert resp.status_code == 200
    assert b"not an Etqan subdomain" in resp.content


@pytest.mark.django_db
def test_check_dns_action_activates(staff_client, tenants, monkeypatch):
    connection.set_schema_to_public()
    d = services.add_custom_domain(tenants.other, "act.example")
    monkeypatch.setattr(
        "etqan.tenants.admin.services.check_domain_dns", lambda domain: (True, ["203.0.113.7"])
    )
    resp = staff_client.post(
        "/admin/tenants/domain/",
        {"action": "check_dns", "_selected_action": [d.pk]},
        HTTP_HOST=PUBLIC,
    )
    assert resp.status_code == 302
    connection.set_schema_to_public()
    d.refresh_from_db()
    assert d.status == "active"


@pytest.mark.django_db
def test_make_primary_action(staff_client, tenants, restore_tenant_objects):
    connection.set_schema_to_public()
    d = services.add_custom_domain(tenants.other, "prim.example")
    services.activate_domain(d)
    staff_client.post(
        "/admin/tenants/domain/",
        {"action": "make_primary_action", "_selected_action": [d.pk]},
        HTTP_HOST=PUBLIC,
    )
    connection.set_schema_to_public()
    d.refresh_from_db()
    assert d.is_primary is True


@pytest.mark.django_db
def test_domain_admin_hides_public_domains(staff_client):
    resp = staff_client.get("/admin/tenants/domain/", HTTP_HOST=PUBLIC)
    assert resp.status_code == 200
    assert b">etqan.localhost<" not in resp.content
```

- [ ] **Step 2: Run to verify failure** — `.venv/bin/pytest etqan/tenants/tests/test_domain_admin.py -q` → FAIL (404 on `/admin/tenants/domain/`).

- [ ] **Step 3: Implement** — append to `etqan/tenants/admin.py` (keep existing code; add imports `from django_tenants.utils import get_public_schema_name` and `from etqan.tenants.models import Domain`):

```python
class DomainCreationForm(forms.ModelForm):
    class Meta:
        model = Domain
        fields = ["tenant", "domain"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["tenant"].queryset = Academy.objects.exclude(schema_name=get_public_schema_name())
        self.fields["domain"].help_text = (
            f"Ask the academy to add a CNAME record pointing to {settings.EDGE_HOSTNAME}"
            + (f", or an A record to {settings.EDGE_PUBLIC_IP} for a bare domain." if settings.EDGE_PUBLIC_IP else ".")
        )

    def clean(self):
        cleaned = super().clean()
        if self.errors:
            return cleaned
        value = cleaned["domain"].strip().lower().rstrip(".")
        base = settings.TENANT_BASE_DOMAIN
        if value == base or value.endswith("." + base):
            raise forms.ValidationError({"domain": "Use the academy's own domain, not an Etqan subdomain."})
        cleaned["domain"] = value
        return cleaned


@admin.register(Domain)
class DomainAdmin(admin.ModelAdmin):
    list_display = ["domain", "tenant", "status", "is_primary", "is_custom", "verified_at"]
    list_filter = ["status", "is_custom"]
    search_fields = ["domain", "tenant__name"]
    actions = ["check_dns", "make_primary_action", "disable_action"]

    def get_queryset(self, request):
        return super().get_queryset(request).exclude(tenant__schema_name=get_public_schema_name())

    def has_delete_permission(self, request, obj=None):
        return False

    def get_form(self, request, obj=None, change=False, **kwargs):
        if obj is None:
            kwargs["form"] = DomainCreationForm
        return super().get_form(request, obj, change=change, **kwargs)

    def get_fields(self, request, obj=None):
        return ["tenant", "domain"] if obj is None else ["tenant", "domain", "status", "is_primary", "is_custom", "verified_at"]

    def get_readonly_fields(self, request, obj=None):
        return [] if obj is None else ["tenant", "domain", "status", "is_primary", "is_custom", "verified_at"]

    def save_model(self, request, obj, form, change):
        if change:
            return
        created = services.add_custom_domain(form.cleaned_data["tenant"], form.cleaned_data["domain"])
        obj.pk = created.pk

    @admin.action(description="Check DNS and activate")
    def check_dns(self, request, queryset):
        for domain in queryset.filter(status=Domain.Status.PENDING):
            ok, seen = services.check_domain_dns(domain)
            if ok:
                services.activate_domain(domain)
                self.message_user(request, f"{domain.domain}: active.", messages.SUCCESS)
            else:
                shown = ", ".join(seen) or "nothing"
                self.message_user(
                    request,
                    f"{domain.domain}: resolves to {shown}, expected {settings.EDGE_HOSTNAME}.",
                    messages.WARNING,
                )

    @admin.action(description="Make primary")
    def make_primary_action(self, request, queryset):
        for domain in queryset:
            try:
                services.make_primary(domain)
            except EtqanValidationError as exc:
                self.message_user(request, f"{domain.domain}: {exc.message}", messages.ERROR)

    @admin.action(description="Disable")
    def disable_action(self, request, queryset):
        for domain in queryset:
            try:
                services.disable_domain(domain)
            except EtqanValidationError as exc:
                self.message_user(request, f"{domain.domain}: {exc.message}", messages.ERROR)


class DomainInline(admin.TabularInline):
    model = Domain
    fields = ["domain", "status", "is_primary", "is_custom", "verified_at"]
    readonly_fields = fields
    extra = 0
    can_delete = False
    show_change_link = True

    def has_add_permission(self, request, obj=None):
        return False
```

Add `inlines = [DomainInline]` to `AcademyAdmin` and `from django.conf import settings` at the top of the file. `DomainCreationForm.clean` duplicates one rule of `add_custom_domain` only to show a form error; `save_model` still calls the service, which is authoritative.

- [ ] **Step 4: Run** — `.venv/bin/pytest etqan/tenants -q && .venv/bin/pytest -q && .venv/bin/ruff check . && .venv/bin/ruff format --check .` → pass.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(tenants): domain admin with DNS check, primary and disable actions" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`

---

### Task 3: `etqan.site` app — models, sanitiser, colours, defaults

**Files:**
- Create: `backend/etqan/site/{__init__,apps,models,sanitize,colors,uploads,services}.py`, `backend/etqan/site/migrations/__init__.py`, migration `0001_initial.py` (generated), `backend/etqan/site/tests/{__init__,test_sanitize,test_colors,test_models}.py`
- Modify: `backend/requirements/base.txt` (+ `nh3>=0.2`, `Pillow>=11`), `backend/config/settings/base.py` (TENANT_APPS), `backend/pyproject.toml` (import-linter), `backend/etqan/tenants/services.py` (`create_academy` creates defaults)

**Interfaces:**
- Produces: models `Branding`, `LandingContent`, `Testimonial`, `SitePage`, `Inquiry` (fields per spec §3); `etqan.site.sanitize.clean_html(html: str) -> str`; `etqan.site.colors.text_color_for(hex_color: str) -> str` (returns `"#FFFFFF"` or `"#111111"`, raises `ValidationError(field=...)`); `etqan.site.uploads.upload_to(kind: str)` factory; `etqan.site.services.ensure_site_defaults(name: str) -> None` (idempotent); `Branding.load()` / `LandingContent.load()` classmethods returning the singleton.

- [ ] **Step 1: Dependencies and app registration**

Append to `requirements/base.txt`: `nh3>=0.2.18` and `Pillow>=11.0`; `.venv/bin/pip install -r requirements/local.txt`.
In `config/settings/base.py` append `"etqan.site"` to `TENANT_APPS` (not to SHARED_APPS).
In `pyproject.toml` add contracts:

```toml
[[tool.importlinter.contracts]]
name = "site imports neither identity nor tenants"
type = "forbidden"
source_modules = ["etqan.site"]
forbidden_modules = ["etqan.identity", "etqan.tenants"]
```

and add `"etqan.site"` to the platform contract's `forbidden_modules`. (Identity may import `etqan.site` — Task 8 uses it for branded emails; tenants may import site.)

- [ ] **Step 2: Failing tests**

`etqan/site/tests/test_sanitize.py`:

```python
from etqan.site.sanitize import clean_html


def test_strips_script_and_handlers():
    out = clean_html('<p onclick="x()">hi<script>alert(1)</script><img src=x onerror=alert(1)></p>')
    assert out == "<p>hi</p>"


def test_blocks_javascript_links_and_forces_rel():
    out = clean_html('<a href="javascript:alert(1)">x</a> <a href="https://a.test" target="_blank">y</a>')
    assert "javascript" not in out
    assert 'href="https://a.test"' in out
    assert 'rel="noopener nofollow"' in out


def test_keeps_allowed_structure():
    html = "<h2>T</h2><ul><li><strong>a</strong></li></ul><blockquote>q</blockquote>"
    assert clean_html(html) == html


def test_allows_mailto_and_tel():
    out = clean_html('<a href="mailto:a@b.c">m</a><a href="tel:+201">t</a>')
    assert "mailto:a@b.c" in out and "tel:+201" in out
```

`etqan/site/tests/test_colors.py`:

```python
import pytest

from etqan.platform.exceptions import ValidationError
from etqan.site.colors import text_color_for


def test_dark_colour_gets_white_text():
    assert text_color_for("#0E7C66") == "#FFFFFF"


def test_light_colour_gets_dark_text():
    assert text_color_for("#F5D76E") == "#111111"


@pytest.mark.parametrize("bad", ["0E7C66", "#0E7C6", "#GGGGGG", "red"])
def test_format(bad):
    with pytest.raises(ValidationError):
        text_color_for(bad)


def test_mid_grey_fails_both():
    with pytest.raises(ValidationError):
        text_color_for("#777777")
```

`etqan/site/tests/test_models.py`:

```python
import pytest
from django.db import connection
from django_tenants.utils import tenant_context

from etqan.site.models import Branding
from etqan.site.models import LandingContent
from etqan.site.services import ensure_site_defaults
from etqan.tenants import services as tenant_services


@pytest.mark.django_db
def test_defaults_are_idempotent():
    ensure_site_defaults("Pytest Main Academy")
    ensure_site_defaults("Something Else")
    assert Branding.objects.count() == 1
    assert Branding.load().name_en == "Pytest Main Academy"
    assert LandingContent.load().hero_title_ar


@pytest.mark.django_db
def test_create_academy_creates_site_defaults():
    connection.set_schema_to_public()
    academy = tenant_services.create_academy(name="Zeta Academy", subdomain="zeta", admin_email="z@z.test")
    with tenant_context(academy):
        b = Branding.load()
        assert (b.name_en, b.name_ar) == ("Zeta Academy", "Zeta Academy")
        assert b.primary_text == "#FFFFFF"
```

Run: `.venv/bin/pytest etqan/site -q` → FAIL (module not found).

- [ ] **Step 3: Implement helpers**

`etqan/site/__init__.py`: empty. `etqan/site/migrations/__init__.py`: empty. `etqan/site/tests/__init__.py`: empty.

`etqan/site/apps.py`:

```python
from django.apps import AppConfig


class SiteConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "etqan.site"
    label = "academy_site"
```

(The label avoids clashing with `django.contrib.sites`.)

`etqan/site/sanitize.py`:

```python
import nh3

ALLOWED_TAGS = {"p", "h2", "h3", "ul", "ol", "li", "strong", "em", "a", "blockquote", "br"}
ALLOWED_ATTRIBUTES = {"a": {"href", "target"}}
URL_SCHEMES = {"http", "https", "mailto", "tel"}


def clean_html(html: str) -> str:
    """Academy-authored rich text, reduced to a safe allow-list."""
    return nh3.clean(
        html or "",
        tags=ALLOWED_TAGS,
        attributes=ALLOWED_ATTRIBUTES,
        url_schemes=URL_SCHEMES,
        link_rel="noopener nofollow",
        strip_comments=True,
    )
```

`etqan/site/colors.py`:

```python
import re

from etqan.platform.exceptions import ValidationError

HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
WHITE = "#FFFFFF"
DARK = "#111111"
MIN_CONTRAST = 4.5


def _luminance(hex_color: str) -> float:
    def channel(c: int) -> float:
        s = c / 255
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4

    r, g, b = (int(hex_color[i : i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a: str, b: str) -> float:
    la, lb = sorted((_luminance(a), _luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def text_color_for(hex_color: str, field: str = "primary_color") -> str:
    if not HEX_RE.fullmatch(hex_color or ""):
        raise ValidationError("Use a colour like #0E7C66.", field=field)
    if contrast(hex_color, WHITE) >= MIN_CONTRAST:
        return WHITE
    if contrast(hex_color, DARK) >= MIN_CONTRAST:
        return DARK
    raise ValidationError("This colour is too close to both white and black text to be readable.", field=field)
```

`etqan/site/uploads.py`:

```python
import os
import uuid

from django.db import connection


def upload_to(kind: str):
    def _path(instance, filename: str) -> str:
        ext = os.path.splitext(filename)[1].lower() or ".bin"
        return f"tenants/{connection.schema_name}/site/{kind}/{uuid.uuid4().hex}{ext}"

    _path.__name__ = f"upload_to_{kind}"
    _path.__qualname__ = _path.__name__
    return _path
```

(Migrations serialize `upload_to` callables by import path, so define module-level aliases at the bottom of `uploads.py`: `logo_path = upload_to("logo")`, `favicon_path = upload_to("favicon")`, `share_path = upload_to("share")`, `hero_path = upload_to("hero")`, and set each alias's `__name__`/`__qualname__` to the alias name — models reference these aliases.)

- [ ] **Step 4: Models** — `etqan/site/models.py`:

```python
from django.conf import settings
from django.db import models

from etqan.site import uploads


class SingletonModel(models.Model):
    class Meta:
        abstract = True

    @classmethod
    def load(cls):
        obj = cls.objects.first()
        if obj is None:
            raise cls.DoesNotExist(f"{cls.__name__} has not been created for this academy.")
        return obj


class Branding(SingletonModel):
    name_ar = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120)
    tagline_ar = models.CharField(max_length=200, blank=True, default="")
    tagline_en = models.CharField(max_length=200, blank=True, default="")
    logo = models.ImageField(upload_to=uploads.logo_path, blank=True)
    favicon = models.FileField(upload_to=uploads.favicon_path, blank=True)
    share_image = models.ImageField(upload_to=uploads.share_path, blank=True)
    primary_color = models.CharField(max_length=7, default="#0E7C66")
    primary_text = models.CharField(max_length=7, default="#FFFFFF")
    accent_color = models.CharField(max_length=7, default="#C8962E")
    contact_email = models.EmailField(blank=True, default="")
    contact_phone = models.CharField(max_length=32, blank=True, default="")
    whatsapp = models.CharField(max_length=32, blank=True, default="")
    address_ar = models.CharField(max_length=300, blank=True, default="")
    address_en = models.CharField(max_length=300, blank=True, default="")
    facebook = models.URLField(blank=True, default="")
    instagram = models.URLField(blank=True, default="")
    youtube = models.URLField(blank=True, default="")
    x = models.URLField(blank=True, default="")
    tiktok = models.URLField(blank=True, default="")
    telegram = models.URLField(blank=True, default="")
    show_powered_by = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)


class LandingContent(SingletonModel):
    hero_title_ar = models.CharField(max_length=160)
    hero_title_en = models.CharField(max_length=160)
    hero_subtitle_ar = models.CharField(max_length=300, blank=True, default="")
    hero_subtitle_en = models.CharField(max_length=300, blank=True, default="")
    hero_image = models.ImageField(upload_to=uploads.hero_path, blank=True)
    cta_label_ar = models.CharField(max_length=60, default="احجز حصة تجريبية")
    cta_label_en = models.CharField(max_length=60, default="Book a free trial")
    about_ar = models.TextField(blank=True, default="")
    about_en = models.TextField(blank=True, default="")
    show_courses = models.BooleanField(default=False)
    show_packages = models.BooleanField(default=False)
    show_teachers = models.BooleanField(default=False)
    show_testimonials = models.BooleanField(default=True)
    show_contact = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)


class Testimonial(models.Model):
    author_name = models.CharField(max_length=120)
    quote_ar = models.TextField(max_length=600)
    quote_en = models.TextField(max_length=600)
    stars = models.PositiveSmallIntegerField(default=5)
    is_published = models.BooleanField(default=True)
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["order", "id"]
        constraints = [
            models.CheckConstraint(condition=models.Q(stars__gte=1, stars__lte=5), name="testimonial_stars_1_5"),
        ]


class SitePage(models.Model):
    RESERVED_SLUGS = frozenset(
        {"app", "api", "accounts", "health", "media", "ar", "en", "p", "sitemap.xml", "robots.txt", "internal"}
    )
    slug = models.SlugField(max_length=60, unique=True)
    title_ar = models.CharField(max_length=160)
    title_en = models.CharField(max_length=160)
    body_ar = models.TextField()
    body_en = models.TextField()
    seo_description_ar = models.CharField(max_length=160, blank=True, default="")
    seo_description_en = models.CharField(max_length=160, blank=True, default="")
    show_in_menu = models.BooleanField(default=True)
    is_published = models.BooleanField(default=False)
    order = models.PositiveIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["order", "id"]


class Inquiry(models.Model):
    class Kind(models.TextChoices):
        CONTACT = "contact", "Contact"
        TRIAL = "trial", "Trial request"

    class Status(models.TextChoices):
        NEW = "new", "New"
        HANDLED = "handled", "Handled"

    kind = models.CharField(max_length=16, choices=Kind.choices, default=Kind.CONTACT)
    name = models.CharField(max_length=120)
    email = models.EmailField(blank=True, default="")
    phone = models.CharField(max_length=32, blank=True, default="")
    has_whatsapp = models.BooleanField(default=False)
    message = models.TextField(max_length=2000, blank=True, default="")
    locale = models.CharField(max_length=2, default="ar")
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.NEW)
    handled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    source_host = models.CharField(max_length=253, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
```

(`CheckConstraint(condition=...)` is the Django ≥ 5.1 keyword.)

- [ ] **Step 5: Services + create_academy hook**

`etqan/site/services.py`:

```python
"""Public API for the site module."""

from etqan.site.models import Branding
from etqan.site.models import LandingContent

DEFAULT_HERO = {
    "hero_title_ar": "تعلّم مع أفضل المعلمين",
    "hero_title_en": "Learn with great teachers",
    "hero_subtitle_ar": "حصص مباشرة فردية بجدول يناسبك.",
    "hero_subtitle_en": "Live one-to-one lessons on a schedule that fits you.",
}


def ensure_site_defaults(name: str) -> None:
    """Create Branding and LandingContent for the current academy if missing."""
    if not Branding.objects.exists():
        Branding.objects.create(name_ar=name, name_en=name)
    if not LandingContent.objects.exists():
        LandingContent.objects.create(**DEFAULT_HERO)
```

In `etqan/tenants/services.py` `create_academy`, inside the existing `with tenant_context(academy):` block, add `site_services.ensure_site_defaults(name)` before the admin creation, and import `from etqan.site import services as site_services`.

- [ ] **Step 6: Migrate, run tests**

```bash
DJANGO_SETTINGS_MODULE=config.settings.test .venv/bin/python manage.py makemigrations academy_site
.venv/bin/pytest --create-db -q etqan/site etqan/tenants && .venv/bin/pytest -q
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/lint-imports
```
Expected: all pass (`--create-db` because a new tenant app changes every academy schema; the conftest recreates `pytest_main`/`pytest_other`, whose migrations now include `academy_site`). If the existing `pytest_main` schema from `--reuse-db` lacks the new tables, `--create-db` fixes it; later runs may use `--reuse-db` again.

- [ ] **Step 7: Commit** — `feat(site): academy site models, HTML sanitiser, colour contrast and defaults`.

---

### Task 4: Uploads — image validation, storage settings

**Files:**
- Create: `backend/etqan/site/images.py`, `backend/etqan/site/tests/test_images.py`
- Modify: `backend/requirements/base.txt` (+ `django-storages[s3]>=1.14`), `backend/config/settings/base.py`, `backend/config/settings/production.py`

**Interfaces:**
- Produces: `etqan.site.images.clean_image(upload, *, max_bytes: int, formats: set[str], field: str) -> ContentFile` (re-encoded, metadata stripped, keeps extension) and `clean_favicon(upload, field="favicon") -> ContentFile` (PNG or ICO ≤ 256 KB); constants `LOGO_MAX=1_048_576`, `FAVICON_MAX=262_144`, `IMAGE_MAX=2_097_152`, `IMAGE_FORMATS={"PNG","JPEG","WEBP"}`. Settings: `STORAGES` default FileSystemStorage; production uses S3 when `DJANGO_S3_BUCKET` is set.

- [ ] **Step 1: Failing tests** — `etqan/site/tests/test_images.py`

```python
import io

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from PIL import Image

from etqan.platform.exceptions import ValidationError
from etqan.site.images import IMAGE_FORMATS
from etqan.site.images import clean_favicon
from etqan.site.images import clean_image


def _img(fmt="PNG", size=(40, 40), exif=False):
    buf = io.BytesIO()
    im = Image.new("RGB", size, (10, 120, 100))
    kwargs = {}
    if exif and fmt == "JPEG":
        ex = Image.Exif()
        ex[0x010E] = "secret description"
        kwargs["exif"] = ex.tobytes()
    im.save(buf, fmt, **kwargs)
    return SimpleUploadedFile(f"x.{fmt.lower()}", buf.getvalue())


def test_png_is_reencoded():
    out = clean_image(_img("PNG"), max_bytes=1_000_000, formats=IMAGE_FORMATS, field="logo")
    assert out.name.endswith(".png")
    assert Image.open(io.BytesIO(out.read())).format == "PNG"


def test_exif_is_stripped():
    out = clean_image(_img("JPEG", exif=True), max_bytes=1_000_000, formats=IMAGE_FORMATS, field="logo")
    assert b"secret description" not in out.read()


def test_too_big():
    with pytest.raises(ValidationError) as exc:
        clean_image(_img("PNG", size=(2000, 2000)), max_bytes=1000, formats=IMAGE_FORMATS, field="logo")
    assert exc.value.field == "logo"


def test_svg_rejected():
    svg = SimpleUploadedFile("x.svg", b"<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>")
    with pytest.raises(ValidationError):
        clean_image(svg, max_bytes=1_000_000, formats=IMAGE_FORMATS, field="logo")


def test_favicon_png_ok_and_gif_rejected():
    assert clean_favicon(_img("PNG", size=(32, 32))).name.endswith(".png")
    with pytest.raises(ValidationError):
        clean_favicon(_img("GIF", size=(32, 32)))
```

- [ ] **Step 2: Run** → FAIL (module missing).

- [ ] **Step 3: Implement** — `etqan/site/images.py`:

```python
import io

from django.core.files.base import ContentFile
from PIL import Image
from PIL import UnidentifiedImageError

from etqan.platform.exceptions import ValidationError

LOGO_MAX = 1_048_576
FAVICON_MAX = 262_144
IMAGE_MAX = 2_097_152
IMAGE_FORMATS = {"PNG", "JPEG", "WEBP"}
FAVICON_FORMATS = {"PNG", "ICO"}
EXTENSIONS = {"PNG": ".png", "JPEG": ".jpg", "WEBP": ".webp", "ICO": ".ico"}
MAX_PIXELS = 25_000_000


def clean_image(upload, *, max_bytes: int, formats: set[str], field: str) -> ContentFile:
    if upload.size > max_bytes:
        raise ValidationError(f"The file must be at most {max_bytes // 1024} KB.", field=field)
    try:
        image = Image.open(upload)
        image.verify()
        upload.seek(0)
        image = Image.open(upload)
    except (UnidentifiedImageError, OSError, SyntaxError) as exc:
        raise ValidationError("Upload a PNG, JPEG or WebP image.", field=field) from exc
    fmt = image.format
    if fmt not in formats:
        raise ValidationError("This image format is not allowed.", field=field)
    if image.width * image.height > MAX_PIXELS:
        raise ValidationError("The image is too large.", field=field)
    clean = Image.new(image.mode, image.size)
    clean.putdata(list(image.getdata()))
    if fmt == "JPEG" and clean.mode not in ("RGB", "L"):
        clean = clean.convert("RGB")
    buf = io.BytesIO()
    clean.save(buf, fmt)
    return ContentFile(buf.getvalue(), name=f"upload{EXTENSIONS[fmt]}")


def clean_favicon(upload, field: str = "favicon") -> ContentFile:
    return clean_image(upload, max_bytes=FAVICON_MAX, formats=FAVICON_FORMATS, field=field)
```

(`putdata(getdata())` copies pixels only, so EXIF/ICC/text chunks are dropped. Palette-mode images keep their palette via `clean.putpalette(image.getpalette())` when `image.mode == "P"` — add that line after `putdata`.)

- [ ] **Step 4: Storage settings**

`requirements/base.txt`: add `django-storages[s3]>=1.14`. In `config/settings/base.py` below MEDIA settings:

```python
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}
```

(Check the current `STATICFILES_STORAGE`/WhiteNoise usage first: if the project relied on Django's default static storage, use `"django.contrib.staticfiles.storage.StaticFilesStorage"` for `staticfiles` instead, so tests without collected static keep passing.)

In `config/settings/production.py` append:

```python
S3_BUCKET = env("DJANGO_S3_BUCKET", default="")
if S3_BUCKET:
    STORAGES["default"] = {  # noqa: F405
        "BACKEND": "storages.backends.s3.S3Storage",
        "OPTIONS": {
            "bucket_name": S3_BUCKET,
            "endpoint_url": env("DJANGO_S3_ENDPOINT_URL", default=None),
            "region_name": env("DJANGO_S3_REGION", default=None),
            "custom_domain": env("DJANGO_S3_CUSTOM_DOMAIN", default=None),
            "default_acl": None,
            "querystring_auth": False,
            "file_overwrite": False,
        },
    }
```

- [ ] **Step 5: Run and commit** — `.venv/bin/pytest -q && ruff… && lint-imports`; commit `feat(site): validated, re-encoded image uploads and S3-ready storage`.

---

### Task 5: Public site API

**Files:**
- Create: `backend/etqan/site/api/{__init__,serializers,views,urls}.py`, `backend/etqan/site/tests/test_public_api.py`
- Modify: `backend/config/api_router.py` (mount `site/`)

**Interfaces:**
- Consumes: Task 3 models; `Academy`/`Domain` via `connection.tenant` (no import of tenants — use `connection.tenant.subdomain` and `connection.tenant.get_primary_domain()`).
- Produces: `GET /api/v1/site/` → payload exactly as spec §3.6; `GET /api/v1/site/branding/` → the `branding` object; `GET /api/v1/site/pages/<slug>/` → `{"slug","title":{ar,en},"body_html":{ar,en},"seo_description":{ar,en}}`. All `AllowAny`, `authentication_classes = []`, header `Cache-Control: public, max-age=60`. Media URLs absolute (`request.build_absolute_uri`), empty string when no file.

- [ ] **Step 1: Failing tests** — `etqan/site/tests/test_public_api.py`

```python
import pytest
from django.db import connection
from rest_framework.test import APIClient

from etqan.site.models import Branding
from etqan.site.models import SitePage
from etqan.site.models import Testimonial
from etqan.site.services import ensure_site_defaults

OTHER = "pytest-other.etqan.localhost"


@pytest.fixture
def two_sites(tenants):
    connection.set_tenant(tenants.main)
    ensure_site_defaults("Main")
    Branding.objects.update(name_en="Main Academy", name_ar="أكاديمية مين", primary_color="#0E7C66")
    Testimonial.objects.create(author_name="Sara", quote_ar="ممتاز", quote_en="Great", stars=5)
    SitePage.objects.create(slug="policies", title_ar="سياسات", title_en="Policies",
                            body_ar="<p>ع</p>", body_en="<p>e</p>", is_published=True)
    SitePage.objects.create(slug="draft", title_ar="م", title_en="Draft", body_ar="x", body_en="x")
    connection.set_tenant(tenants.other)
    ensure_site_defaults("Other")
    Branding.objects.update(name_en="Other Academy", name_ar="أكاديمية أخرى")
    connection.set_tenant(tenants.main)


@pytest.mark.django_db
def test_payload_is_per_academy(two_sites):
    main = APIClient().get("/api/v1/site/").json()
    other = APIClient().get("/api/v1/site/", HTTP_HOST=OTHER).json()
    assert main["branding"]["name"] == {"ar": "أكاديمية مين", "en": "Main Academy"}
    assert other["branding"]["name"]["en"] == "Other Academy"
    assert other["testimonials"] == []
    assert other["pages"] == []
    assert [p["slug"] for p in main["pages"]] == ["policies"]


@pytest.mark.django_db
def test_payload_shape(two_sites):
    resp = APIClient().get("/api/v1/site/")
    assert resp.status_code == 200
    assert resp["Cache-Control"] == "public, max-age=60"
    data = resp.json()
    assert data["academy"] == {"subdomain": "pytest-main", "canonical_host": "testserver"}
    assert data["branding"]["primary_text"] == "#FFFFFF"
    assert data["branding"]["logo_url"] == ""
    assert set(data["landing"]["sections"]) == {"courses", "packages", "teachers", "testimonials", "contact"}
    assert data["testimonials"] == [{"author_name": "Sara", "quote": {"ar": "ممتاز", "en": "Great"}, "stars": 5}]


@pytest.mark.django_db
def test_branding_endpoint(two_sites):
    data = APIClient().get("/api/v1/site/branding/", HTTP_HOST=OTHER).json()
    assert data["name"]["en"] == "Other Academy"


@pytest.mark.django_db
def test_page_published_only(two_sites):
    assert APIClient().get("/api/v1/site/pages/policies/").json()["body_html"] == {"ar": "<p>ع</p>", "en": "<p>e</p>"}
    assert APIClient().get("/api/v1/site/pages/draft/").status_code == 404
    assert APIClient().get("/api/v1/site/pages/policies/", HTTP_HOST=OTHER).status_code == 404


@pytest.mark.django_db
def test_unknown_host_and_public_host_404():
    assert APIClient().get("/api/v1/site/", HTTP_HOST="nope.etqan.localhost").status_code == 404
    assert APIClient().get("/api/v1/site/", HTTP_HOST="etqan.localhost").status_code == 404


@pytest.mark.django_db
def test_media_urls_use_request_host(two_sites, settings, tmp_path):
    settings.MEDIA_ROOT = str(tmp_path)
    from django.core.files.base import ContentFile

    b = Branding.load()
    b.logo.save("l.png", ContentFile(b"x"), save=True)
    data = APIClient().get("/api/v1/site/").json()
    assert data["branding"]["logo_url"].startswith("http://testserver/media/tenants/pytest_main/site/logo/")
```

- [ ] **Step 2: Run** → FAIL (404, route missing).

- [ ] **Step 3: Implement**

`etqan/site/api/serializers.py`:

```python
def pair(obj, field: str) -> dict:
    return {"ar": getattr(obj, f"{field}_ar"), "en": getattr(obj, f"{field}_en")}


def file_url(request, file) -> str:
    return request.build_absolute_uri(file.url) if file else ""


def branding_payload(request, b) -> dict:
    return {
        "name": pair(b, "name"),
        "tagline": pair(b, "tagline"),
        "logo_url": file_url(request, b.logo),
        "favicon_url": file_url(request, b.favicon),
        "share_image_url": file_url(request, b.share_image),
        "primary_color": b.primary_color,
        "primary_text": b.primary_text,
        "accent_color": b.accent_color,
        "contact": {
            "email": b.contact_email, "phone": b.contact_phone,
            "whatsapp": b.whatsapp, "address": pair(b, "address"),
        },
        "social": {k: getattr(b, k) for k in ("facebook", "instagram", "youtube", "x", "tiktok", "telegram")},
        "show_powered_by": b.show_powered_by,
    }


def landing_payload(request, lc) -> dict:
    return {
        "hero_title": pair(lc, "hero_title"),
        "hero_subtitle": pair(lc, "hero_subtitle"),
        "hero_image_url": file_url(request, lc.hero_image),
        "cta_label": pair(lc, "cta_label"),
        "about_html": pair(lc, "about"),
        "sections": {
            "courses": lc.show_courses, "packages": lc.show_packages, "teachers": lc.show_teachers,
            "testimonials": lc.show_testimonials, "contact": lc.show_contact,
        },
    }
```

`etqan/site/api/views.py`:

```python
from django.db import connection
from django.shortcuts import get_object_or_404
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.site.api.serializers import branding_payload
from etqan.site.api.serializers import landing_payload
from etqan.site.api.serializers import pair
from etqan.site.models import Branding
from etqan.site.models import LandingContent
from etqan.site.models import SitePage
from etqan.site.models import Testimonial

CACHE = "public, max-age=60"


class PublicView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]

    def finalize_response(self, request, response, *args, **kwargs):
        response = super().finalize_response(request, response, *args, **kwargs)
        if response.status_code == 200:
            response["Cache-Control"] = CACHE
        return response


def _canonical_host(request) -> str:
    domain = connection.tenant.get_primary_domain()
    return domain.domain if domain else request.get_host().split(":")[0]


class SiteView(PublicView):
    def get(self, request, *args, **kwargs):
        lc = LandingContent.load()
        return Response({
            "academy": {"subdomain": connection.tenant.subdomain, "canonical_host": _canonical_host(request)},
            "branding": branding_payload(request, Branding.load()),
            "landing": landing_payload(request, lc),
            "testimonials": [
                {"author_name": t.author_name, "quote": pair(t, "quote"), "stars": t.stars}
                for t in Testimonial.objects.filter(is_published=True)
            ] if lc.show_testimonials else [],
            "pages": [
                {"slug": p.slug, "title": pair(p, "title"), "show_in_menu": p.show_in_menu}
                for p in SitePage.objects.filter(is_published=True)
            ],
        })


class BrandingView(PublicView):
    def get(self, request, *args, **kwargs):
        return Response(branding_payload(request, Branding.load()))


class PageView(PublicView):
    def get(self, request, slug, *args, **kwargs):
        page = get_object_or_404(SitePage, slug=slug, is_published=True)
        return Response({
            "slug": page.slug, "title": pair(page, "title"),
            "body_html": pair(page, "body"), "seo_description": pair(page, "seo_description"),
        })
```

`test_payload_shape` expects `testimonials` even though the fixture never toggles; `show_testimonials` defaults to `True`, so the conditional is covered.

`etqan/site/api/urls.py`:

```python
from django.urls import path

from etqan.site.api import views

app_name = "site"
urlpatterns = [
    path("", views.SiteView.as_view(), name="site"),
    path("branding/", views.BrandingView.as_view(), name="branding"),
    path("pages/<slug:slug>/", views.PageView.as_view(), name="page"),
]
```

`etqan/site/api/__init__.py`: empty. In `config/api_router.py` add `path("site/", include("etqan.site.api.urls")),` next to identity. Branding/Landing missing (academy created before this plan) must not 500: in `SiteView`/`BrandingView` call `ensure_site_defaults(connection.tenant.name)` before `load()` (import from `etqan.site.services`), making old academies self-heal on first visit.

- [ ] **Step 4: Run and commit** — `.venv/bin/pytest etqan/site -q && .venv/bin/pytest -q && ruff… && lint-imports`; commit `feat(site): public site, branding and page endpoints`.

---

### Task 6: Inquiry endpoint

**Files:**
- Create: `backend/etqan/site/throttling.py`, `backend/etqan/site/tests/test_inquiries.py`
- Modify: `backend/etqan/site/api/{views,urls}.py`, `backend/config/settings/base.py` (throttle rates)

**Interfaces:**
- Produces: `POST /api/v1/site/inquiries/` body `{kind, name, email, phone, has_whatsapp, message, locale, website}` → `201 {"ok": true}`; `400` with field errors (`name` required; one of `email`/`phone` required; `kind` in contact|trial; `locale` in ar|en); honeypot `website` non-empty → `201` and nothing stored; throttles `inquiry_ip` 10/hour (by client IP) and `inquiry_email` 5/hour (by lower-cased email).

- [ ] **Step 1: Failing tests** — `etqan/site/tests/test_inquiries.py`

```python
import pytest
from django.core.cache import cache
from django.db import connection
from rest_framework.test import APIClient

from etqan.identity.models import User
from etqan.site.models import Inquiry

URL = "/api/v1/site/inquiries/"
OTHER = "pytest-other.etqan.localhost"


@pytest.fixture(autouse=True)
def _clear_throttles():
    cache.clear()
    yield
    cache.clear()


def payload(**kw):
    data = {"kind": "trial", "name": "Omar", "email": "omar@x.test", "phone": "", "has_whatsapp": False,
            "message": "Hi", "locale": "en", "website": ""}
    data.update(kw)
    return data


@pytest.mark.django_db
def test_creates_inquiry_in_this_academy_only(tenants):
    assert APIClient().post(URL, payload(), format="json").status_code == 201
    assert Inquiry.objects.get().source_host == "testserver"
    connection.set_tenant(tenants.other)
    assert Inquiry.objects.count() == 0


@pytest.mark.django_db
def test_logged_in_user_with_session_cookie_is_not_blocked_by_csrf():
    user = User.objects.create_user(email="s@x.test", password="pw-12345678")
    client = APIClient(enforce_csrf_checks=True)
    client.force_login(user)
    assert client.post(URL, payload(), format="json").status_code == 201


@pytest.mark.django_db
def test_honeypot_swallows(tenants):
    assert APIClient().post(URL, payload(website="spam.example"), format="json").status_code == 201
    assert Inquiry.objects.count() == 0


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("override", "field"),
    [({"name": ""}, "name"), ({"email": "", "phone": ""}, "email"), ({"kind": "x"}, "kind"),
     ({"locale": "fr"}, "locale"), ({"message": "a" * 2001}, "message")],
)
def test_validation(override, field):
    resp = APIClient().post(URL, payload(**override), format="json")
    assert resp.status_code == 400
    assert field in resp.json()


@pytest.mark.django_db
def test_email_throttle():
    codes = [APIClient().post(URL, payload(), format="json", REMOTE_ADDR=f"10.0.0.{i}").status_code for i in range(6)]
    assert codes[:5] == [201] * 5
    assert codes[5] == 429


@pytest.mark.django_db
def test_ip_throttle():
    codes = [APIClient().post(URL, payload(email=f"u{i}@x.test"), format="json").status_code for i in range(11)]
    assert codes[10] == 429


@pytest.mark.django_db
def test_throttle_is_per_academy():
    for i in range(10):
        APIClient().post(URL, payload(email=f"a{i}@x.test"), format="json")
    assert APIClient().post(URL, payload(email="z@x.test"), format="json", HTTP_HOST=OTHER).status_code == 201
```

(Per-academy throttling works because the cache key function prefixes keys with the schema name.)

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`etqan/site/throttling.py`:

```python
from rest_framework.throttling import SimpleRateThrottle


class InquiryIPThrottle(SimpleRateThrottle):
    scope = "inquiry_ip"

    def get_cache_key(self, request, view):
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class InquiryEmailThrottle(SimpleRateThrottle):
    scope = "inquiry_email"

    def get_cache_key(self, request, view):
        email = str(request.data.get("email", "")).strip().lower()
        if not email:
            return None
        return self.cache_format % {"scope": self.scope, "ident": email}
```

In `config/settings/base.py` `DEFAULT_THROTTLE_RATES` add `"inquiry_ip": "10/hour", "inquiry_email": "5/hour"`.

Append to `etqan/site/api/views.py`:

```python
from rest_framework import serializers
from rest_framework import status as http_status

from etqan.site.models import Inquiry
from etqan.site.throttling import InquiryEmailThrottle
from etqan.site.throttling import InquiryIPThrottle


class InquirySerializer(serializers.ModelSerializer):
    website = serializers.CharField(required=False, allow_blank=True, write_only=True)

    class Meta:
        model = Inquiry
        fields = ["kind", "name", "email", "phone", "has_whatsapp", "message", "locale", "website"]
        extra_kwargs = {"locale": {"required": True}}

    def validate_locale(self, value):
        if value not in ("ar", "en"):
            raise serializers.ValidationError("Use ar or en.")
        return value

    def validate(self, attrs):
        if not attrs.get("email") and not attrs.get("phone"):
            raise serializers.ValidationError({"email": "Give an email or a phone number."})
        return attrs


class InquiryCreateView(APIView):
    authentication_classes: list = []  # P4: visitors logged into /app/ must not hit session CSRF
    permission_classes = [AllowAny]
    throttle_classes = [InquiryIPThrottle, InquiryEmailThrottle]

    def post(self, request, *args, **kwargs):
        serializer = InquirySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        if serializer.validated_data.pop("website", ""):
            return Response({"ok": True}, status=http_status.HTTP_201_CREATED)
        Inquiry.objects.create(**serializer.validated_data, source_host=request.get_host().split(":")[0])
        return Response({"ok": True}, status=http_status.HTTP_201_CREATED)
```

Add to `urls.py`: `path("inquiries/", views.InquiryCreateView.as_view(), name="inquiries"),`.

- [ ] **Step 4: Run and commit** — full suite + linters; commit `feat(site): throttled public inquiry endpoint with honeypot`.

---

### Task 7: Academy admin site API

**Files:**
- Create: `backend/etqan/site/permissions.py`, `backend/etqan/site/api/admin_serializers.py`, `backend/etqan/site/api/admin_views.py`, `backend/etqan/site/tests/test_admin_api.py`
- Modify: `backend/etqan/site/api/urls.py`

**Interfaces:**
- Produces: `IsAcademyAdmin` permission; endpoints (all `IsAcademyAdmin`, session auth):
  - `GET/PATCH /api/v1/site/admin/branding/` (JSON or multipart; files `logo`, `favicon`, `share_image`; `"<file>_clear": true` removes a file)
  - `GET/PATCH /api/v1/site/admin/landing/` (multipart `hero_image`)
  - `/api/v1/site/admin/pages/` list/create, `/api/v1/site/admin/pages/<id>/` retrieve/update/delete
  - `/api/v1/site/admin/testimonials/` list/create, `/<id>/` retrieve/update/delete
  - `GET /api/v1/site/admin/inquiries/?status=new&kind=trial` (paginated), `POST /api/v1/site/admin/inquiries/<id>/handle/`
  - Branding PATCH recomputes `primary_text` via `text_color_for`; accent validated for format only.
  - Page/landing rich-text fields cleaned with `clean_html` on write; slug validated against `SitePage.RESERVED_SLUGS` and `^[a-z0-9-]{1,60}$`.

- [ ] **Step 1: Failing tests** — `etqan/site/tests/test_admin_api.py`

```python
import io

import pytest
from PIL import Image
from rest_framework.test import APIClient

from etqan.identity.models import User
from etqan.site.models import Branding
from etqan.site.models import Inquiry
from etqan.site.models import SitePage
from etqan.site.services import ensure_site_defaults

B = "/api/v1/site/admin/"


def client_for(role):
    user = User.objects.create_user(email=f"{role}@x.test", password="pw-12345678", role=role)
    c = APIClient()
    c.force_login(user)
    return c


@pytest.fixture
def admin():
    ensure_site_defaults("Main")
    return client_for("admin")


@pytest.mark.django_db
@pytest.mark.parametrize("role", ["teacher", "student", "parent"])
def test_non_admins_forbidden(role):
    ensure_site_defaults("Main")
    assert client_for(role).get(B + "branding/").status_code == 403


@pytest.mark.django_db
def test_anonymous_forbidden():
    assert APIClient().get(B + "branding/").status_code == 403


@pytest.mark.django_db
def test_patch_branding_recomputes_text_colour(admin):
    resp = admin.patch(B + "branding/", {"primary_color": "#F5D76E", "name_en": "Noor", "name_ar": "نور"}, format="json")
    assert resp.status_code == 200, resp.json()
    assert Branding.load().primary_text == "#111111"


@pytest.mark.django_db
def test_branding_rejects_unreadable_colour(admin):
    resp = admin.patch(B + "branding/", {"primary_color": "#777777"}, format="json")
    assert resp.status_code == 400
    assert "primary_color" in resp.json()


@pytest.mark.django_db
def test_both_names_required(admin):
    assert admin.patch(B + "branding/", {"name_ar": ""}, format="json").status_code == 400


@pytest.mark.django_db
def test_logo_upload_and_clear(admin, settings, tmp_path):
    settings.MEDIA_ROOT = str(tmp_path)
    buf = io.BytesIO()
    Image.new("RGB", (20, 20)).save(buf, "PNG")
    buf.name = "logo.png"
    buf.seek(0)
    assert admin.patch(B + "branding/", {"logo": buf}, format="multipart").status_code == 200
    assert Branding.load().logo.name.startswith("tenants/pytest_main/site/logo/")
    assert admin.patch(B + "branding/", {"logo_clear": True}, format="json").status_code == 200
    assert not Branding.load().logo


@pytest.mark.django_db
def test_page_crud_sanitises_and_validates_slug(admin):
    resp = admin.post(B + "pages/", {
        "slug": "about-us", "title_ar": "من نحن", "title_en": "About",
        "body_ar": "<p>ع<script>x</script></p>", "body_en": "<p>e</p>", "is_published": True,
    }, format="json")
    assert resp.status_code == 201, resp.json()
    assert SitePage.objects.get().body_ar == "<p>ع</p>"
    bad = admin.post(B + "pages/", {"slug": "app", "title_ar": "a", "title_en": "a", "body_ar": "a", "body_en": "a"}, format="json")
    assert bad.status_code == 400 and "slug" in bad.json()


@pytest.mark.django_db
def test_inquiries_list_and_handle(admin):
    i = Inquiry.objects.create(name="Omar", email="o@x.test", locale="en")
    data = admin.get(B + "inquiries/?status=new").json()
    assert [row["id"] for row in data["results"]] == [i.id]
    assert admin.post(B + f"inquiries/{i.id}/handle/").status_code == 200
    i.refresh_from_db()
    assert i.status == "handled" and i.handled_by.email == "admin@x.test"
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`etqan/site/permissions.py`:

```python
from rest_framework.permissions import BasePermission


class IsAcademyAdmin(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and getattr(user, "role", None) == "admin")
```

`etqan/site/api/admin_serializers.py`:

```python
import re

from rest_framework import serializers

from etqan.platform.exceptions import ValidationError as EtqanValidationError
from etqan.site.colors import HEX_RE
from etqan.site.colors import text_color_for
from etqan.site.images import IMAGE_FORMATS
from etqan.site.images import IMAGE_MAX
from etqan.site.images import LOGO_MAX
from etqan.site.images import clean_favicon
from etqan.site.images import clean_image
from etqan.site.models import Branding
from etqan.site.models import Inquiry
from etqan.site.models import LandingContent
from etqan.site.models import SitePage
from etqan.site.models import Testimonial
from etqan.site.sanitize import clean_html

SLUG_RE = re.compile(r"^[a-z0-9-]{1,60}$")


def _as_drf(exc: EtqanValidationError):
    return serializers.ValidationError({exc.field or "non_field_errors": [exc.message]})


class FileClearMixin:
    file_fields: tuple = ()

    def to_internal_value(self, data):
        clears = {f for f in self.file_fields if str(data.get(f"{f}_clear", "")).lower() in ("true", "1")}
        values = super().to_internal_value(data)
        for f in clears:
            values[f] = None
        return values

    def update(self, instance, validated_data):
        for f in self.file_fields:
            if f in validated_data and validated_data[f] is None:
                getattr(instance, f).delete(save=False)
                validated_data[f] = ""
        return super().update(instance, validated_data)


class BrandingAdminSerializer(FileClearMixin, serializers.ModelSerializer):
    file_fields = ("logo", "favicon", "share_image")

    class Meta:
        model = Branding
        exclude = ["id", "updated_at"]
        read_only_fields = ["primary_text"]

    def validate_logo(self, f):
        try:
            return clean_image(f, max_bytes=LOGO_MAX, formats=IMAGE_FORMATS, field="logo") if f else f
        except EtqanValidationError as exc:
            raise _as_drf(exc) from exc

    def validate_favicon(self, f):
        try:
            return clean_favicon(f) if f else f
        except EtqanValidationError as exc:
            raise _as_drf(exc) from exc

    def validate_share_image(self, f):
        try:
            return clean_image(f, max_bytes=IMAGE_MAX, formats=IMAGE_FORMATS, field="share_image") if f else f
        except EtqanValidationError as exc:
            raise _as_drf(exc) from exc

    def validate_accent_color(self, value):
        if not HEX_RE.fullmatch(value):
            raise serializers.ValidationError("Use a colour like #C8962E.")
        return value

    def validate(self, attrs):
        if "primary_color" in attrs:
            try:
                attrs["primary_text"] = text_color_for(attrs["primary_color"])
            except EtqanValidationError as exc:
                raise _as_drf(exc) from exc
        return attrs


class LandingAdminSerializer(FileClearMixin, serializers.ModelSerializer):
    file_fields = ("hero_image",)

    class Meta:
        model = LandingContent
        exclude = ["id", "updated_at"]

    def validate_hero_image(self, f):
        try:
            return clean_image(f, max_bytes=IMAGE_MAX, formats=IMAGE_FORMATS, field="hero_image") if f else f
        except EtqanValidationError as exc:
            raise _as_drf(exc) from exc

    def validate_about_ar(self, v):
        return clean_html(v)

    def validate_about_en(self, v):
        return clean_html(v)


class PageAdminSerializer(serializers.ModelSerializer):
    class Meta:
        model = SitePage
        exclude = ["updated_at"]

    def validate_slug(self, v):
        if not SLUG_RE.fullmatch(v) or v in SitePage.RESERVED_SLUGS:
            raise serializers.ValidationError("Use lowercase letters, digits and hyphens; this slug is reserved or invalid.")
        return v

    def validate_body_ar(self, v):
        return clean_html(v)

    def validate_body_en(self, v):
        return clean_html(v)


class TestimonialAdminSerializer(serializers.ModelSerializer):
    class Meta:
        model = Testimonial
        fields = "__all__"

    def validate_stars(self, v):
        if not 1 <= v <= 5:
            raise serializers.ValidationError("1 to 5.")
        return v


class InquiryAdminSerializer(serializers.ModelSerializer):
    handled_by_email = serializers.EmailField(source="handled_by.email", read_only=True, default="")

    class Meta:
        model = Inquiry
        fields = ["id", "kind", "name", "email", "phone", "has_whatsapp", "message", "locale",
                  "status", "handled_by_email", "source_host", "created_at"]
        read_only_fields = fields
```

(`name_ar`/`name_en` are non-blank model fields, so `""` fails DRF validation automatically; add `extra_kwargs = {"name_ar": {"allow_blank": False}, "name_en": {"allow_blank": False}}` if the default does not reject it.)

`etqan/site/api/admin_views.py`:

```python
from django.db import connection
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework import viewsets
from rest_framework.parsers import FormParser
from rest_framework.parsers import JSONParser
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.site.api.admin_serializers import BrandingAdminSerializer
from etqan.site.api.admin_serializers import InquiryAdminSerializer
from etqan.site.api.admin_serializers import LandingAdminSerializer
from etqan.site.api.admin_serializers import PageAdminSerializer
from etqan.site.api.admin_serializers import TestimonialAdminSerializer
from etqan.site.models import Branding
from etqan.site.models import Inquiry
from etqan.site.models import LandingContent
from etqan.site.models import SitePage
from etqan.site.models import Testimonial
from etqan.site.permissions import IsAcademyAdmin
from etqan.site.services import ensure_site_defaults

PARSERS = [JSONParser, MultiPartParser, FormParser]


class SingletonAdminView(generics.RetrieveUpdateAPIView):
    permission_classes = [IsAcademyAdmin]
    parser_classes = PARSERS
    model = None

    def get_object(self):
        ensure_site_defaults(connection.tenant.name)
        return self.model.load()


class BrandingAdminView(SingletonAdminView):
    serializer_class = BrandingAdminSerializer
    model = Branding
    http_method_names = ["get", "patch"]


class LandingAdminView(SingletonAdminView):
    serializer_class = LandingAdminSerializer
    model = LandingContent
    http_method_names = ["get", "patch"]


class PageAdminViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAcademyAdmin]
    serializer_class = PageAdminSerializer
    queryset = SitePage.objects.all()
    pagination_class = None


class TestimonialAdminViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAcademyAdmin]
    serializer_class = TestimonialAdminSerializer
    queryset = Testimonial.objects.all()
    pagination_class = None


class InquiryAdminList(generics.ListAPIView):
    permission_classes = [IsAcademyAdmin]
    serializer_class = InquiryAdminSerializer

    def get_queryset(self):
        qs = Inquiry.objects.select_related("handled_by")
        for key in ("status", "kind"):
            if value := self.request.query_params.get(key):
                qs = qs.filter(**{key: value})
        return qs


class InquiryHandleView(APIView):
    permission_classes = [IsAcademyAdmin]

    def post(self, request, pk, *args, **kwargs):
        inquiry = get_object_or_404(Inquiry, pk=pk)
        inquiry.status = Inquiry.Status.HANDLED
        inquiry.handled_by = request.user
        inquiry.save(update_fields=["status", "handled_by"])
        return Response(InquiryAdminSerializer(inquiry).data)
```

In `etqan/site/api/urls.py` add a `SimpleRouter` for pages/testimonials under `admin/` and paths `admin/branding/`, `admin/landing/`, `admin/inquiries/`, `admin/inquiries/<int:pk>/handle/`.

- [ ] **Step 4: Run and commit** — full suite + linters; commit `feat(site): academy admin API for branding, home page, pages, testimonials and inquiries`.

---

### Task 8: Branded emails and `/app/` links

**Files:**
- Create: `backend/etqan/site/emails.py`, `backend/etqan/site/tests/test_emails.py`, `backend/etqan/templates/email/layout.txt`, `backend/etqan/templates/email/layout.html`
- Modify: `backend/etqan/platform/frontend.py` (+ `app_url`), `backend/etqan/identity/services.py`, `backend/etqan/identity/adapter.py`, `backend/config/settings/base.py` (`ACCOUNT_EMAIL_SUBJECT_PREFIX` default `""`), identity tests that assert link paths/subjects

**Interfaces:**
- Consumes: `Branding.load()`.
- Produces:
  - `etqan.platform.frontend.app_url(path: str) -> str` = `frontend_url() + "/app" + path` (path starts with `/`).
  - `etqan.site.emails.brand_email(*, subject: str, body: str) -> dict` → `{"subject", "body", "html", "from_email"}`: in an academy schema, From = `"<name_en>" <address of DEFAULT_FROM_EMAIL>`, subject `"[<name_en>] <subject>"`, body wrapped in `layout.txt`, `html` from `layout.html` (logo, both names, contact line, home link `frontend_url() + "/"`); in the public schema, unchanged subject/body, `from_email=DEFAULT_FROM_EMAIL`, `html=None`.
  - Every identity email goes through `brand_email` and `send_email_message.delay(**…, alternatives=[[html, "text/html"]] if html else None)`.
  - All emailed dashboard links use `app_url("/reset-password?…")`, `app_url("/verify-email?key=…")`, `app_url("/account")`, `app_url("/forgot-password")`.

- [ ] **Step 1: Failing tests** — `etqan/site/tests/test_emails.py`

```python
import pytest
from django.core import mail
from django.db import connection
from django.test import override_settings

from etqan.identity import services as identity_services
from etqan.identity.models import User
from etqan.platform.frontend import app_url
from etqan.site.emails import brand_email
from etqan.site.models import Branding
from etqan.site.services import ensure_site_defaults


@pytest.fixture
def branded():
    ensure_site_defaults("x")
    Branding.objects.update(name_en="Noor Academy", name_ar="أكاديمية نور", contact_email="hi@noor.test")


@pytest.mark.django_db
@override_settings(DEFAULT_FROM_EMAIL="etqan <noreply@etqan.test>")
def test_brand_email_in_academy(branded):
    out = brand_email(subject="Reset your password", body="Click the link.")
    assert out["from_email"] == '"Noor Academy" <noreply@etqan.test>'
    assert out["subject"] == "[Noor Academy] Reset your password"
    assert "Click the link." in out["body"] and "أكاديمية نور" in out["body"]
    assert "hi@noor.test" in out["html"] and "http://testserver/" in out["html"]


@pytest.mark.django_db
def test_brand_email_escapes_names_in_html(branded):
    Branding.objects.update(name_en="<b>x</b>")
    assert "<b>x</b>" not in brand_email(subject="s", body="b")["html"]


@pytest.mark.django_db
def test_public_schema_is_unbranded():
    connection.set_schema_to_public()
    out = brand_email(subject="Hello", body="Body")
    assert out["subject"] == "Hello" and out["html"] is None


@pytest.mark.django_db
def test_app_url():
    assert app_url("/login") == "http://testserver/app/login"


@pytest.mark.django_db
def test_password_reset_email_is_branded_and_points_to_app(branded):
    from allauth.account.models import EmailAddress

    user = User.objects.create_user(email="r@x.test", password="pw-12345678")
    EmailAddress.objects.create(user=user, email=user.email, primary=True, verified=True)
    identity_services.request_password_reset("r@x.test")
    msg = mail.outbox[-1]
    assert msg.subject.startswith("[Noor Academy] ")
    assert "http://testserver/app/reset-password?uid=" in msg.body
    assert msg.alternatives and msg.alternatives[0][1] == "text/html"
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`etqan/platform/frontend.py` — append:

```python
def app_url(path: str) -> str:
    """Absolute URL of a dashboard route for the current academy (the dashboard lives under /app)."""
    return f"{frontend_url()}/app{path}"
```

`etqan/templates/email/layout.txt`:

```
{{ name_en }} · {{ name_ar }}

{{ body }}

--
{{ name_en }} · {{ name_ar }}
{% if contact_email %}{{ contact_email }}{% endif %}{% if contact_phone %} · {{ contact_phone }}{% endif %}
{{ home_url }}
```

`etqan/templates/email/layout.html`:

```html
<!doctype html>
<html><body style="margin:0;background:#f6f6f4;font-family:Arial,Helvetica,sans-serif;color:#111">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px">
<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden">
<tr><td style="background:{{ primary_color }};color:{{ primary_text }};padding:20px 24px">
{% if logo_url %}<img src="{{ logo_url }}" alt="" height="40" style="vertical-align:middle;margin-inline-end:12px">{% endif %}
<strong style="font-size:18px">{{ name_en }}</strong> <span dir="rtl" style="font-size:16px">· {{ name_ar }}</span>
</td></tr>
<tr><td style="padding:24px;font-size:15px;line-height:1.6;white-space:pre-line">{{ body|urlize }}</td></tr>
<tr><td style="padding:16px 24px;border-top:1px solid #eee;font-size:13px;color:#555">
{{ name_en }} · <span dir="rtl">{{ name_ar }}</span>{% if contact_email %} · {{ contact_email }}{% endif %}{% if contact_phone %} · {{ contact_phone }}{% endif %}<br>
<a href="{{ home_url }}" style="color:{{ primary_color }}">{{ home_url }}</a>
</td></tr></table></td></tr></table></body></html>
```

`etqan/site/emails.py`:

```python
from email.utils import formataddr
from email.utils import parseaddr

from django.conf import settings
from django.db import connection
from django.template.loader import render_to_string
from django_tenants.utils import get_public_schema_name

from etqan.platform.frontend import frontend_url
from etqan.site.models import Branding


def brand_email(*, subject: str, body: str) -> dict:
    if connection.schema_name == get_public_schema_name():
        return {"subject": subject, "body": body, "html": None, "from_email": settings.DEFAULT_FROM_EMAIL}
    branding = Branding.objects.first()
    if branding is None:
        return {"subject": subject, "body": body, "html": None, "from_email": settings.DEFAULT_FROM_EMAIL}
    home = frontend_url() + "/"
    context = {
        "name_en": branding.name_en, "name_ar": branding.name_ar, "body": body,
        "contact_email": branding.contact_email, "contact_phone": branding.contact_phone,
        "home_url": home, "primary_color": branding.primary_color, "primary_text": branding.primary_text,
        "logo_url": (frontend_url() + branding.logo.url) if branding.logo and branding.logo.url.startswith("/") else (branding.logo.url if branding.logo else ""),
    }
    _, address = parseaddr(settings.DEFAULT_FROM_EMAIL)
    return {
        "subject": f"[{branding.name_en}] {subject}",
        "body": render_to_string("email/layout.txt", context).strip() + "\n",
        "html": render_to_string("email/layout.html", context),
        "from_email": formataddr((branding.name_en, address)),
    }
```

`formataddr` quotes the display name, matching the test's `'"Noor Academy" <noreply@etqan.test>'`.

In `etqan/identity/services.py`: add a private helper and use it in `_send_child_set_password_link`, `request_password_reset` and `_send_email_security_alert`:

```python
def _send(to: str, subject: str, body: str) -> None:
    msg = brand_email(subject=subject, body=body)
    send_email_message.delay(
        subject=msg["subject"], body=msg["body"], from_email=msg["from_email"], to=[to],
        alternatives=[[msg["html"], "text/html"]] if msg["html"] else None,
    )
```

(import `from etqan.site.emails import brand_email` and `from etqan.platform.frontend import app_url`). Replace `f"{frontend_url()}/reset-password?…"` with `app_url(f"/reset-password?uid={uid}&token={token}")`, `/account` → `app_url("/account")`, `/forgot-password` → `app_url("/forgot-password")`. Change the subjects from "…etqan…" wording to neutral: `"Set your password"`, `"Reset your password"`, `"Security alert: a change was made to your account"` (the academy prefix is added by `brand_email`).

`etqan/identity/adapter.py`: in `send_mail`, after `render_mail`, route through `brand_email(subject=message.subject, body=message.body)` and send with its `from_email`/`subject`/`alternatives`; `get_email_confirmation_url` returns `app_url(f"/verify-email?key={emailconfirmation.key}")`. In `config/settings/base.py` set `ACCOUNT_EMAIL_SUBJECT_PREFIX = env("DJANGO_EMAIL_SUBJECT_PREFIX", default="")`.

Update identity tests that assert old subjects (`"Reset your etqan password"` etc.), old link paths (`/reset-password` without `/app`) or the `[Etqan] ` prefix: grep `etqan/identity/tests` for `reset-password`, `verify-email`, `/account`, `forgot-password`, `Etqan]`, `etqan password`, `etqan account`; update each expectation to the new branded subject/`/app/` path. Branded subjects in the main test academy are `"[Pytest Main Academy] …"` only if `ensure_site_defaults` ran; without Branding rows `brand_email` leaves the subject unchanged — keep tests deterministic by asserting with `in`/`endswith` on the neutral subject text.

- [ ] **Step 4: Run and commit** — full suite + linters; commit `feat: academy-branded emails and /app links`.

---

### Task 9: Dashboard under `/app/`

**Files:**
- Modify: `dashboard/vite.config.ts` (`base: "/app/"`), `dashboard/src/main.tsx` (`basepath: "/app"`), `dashboard/nginx.conf`, `dashboard/Dockerfile` (copy dist into `/usr/share/nginx/html/app`), `dashboard/playwright.config.ts`, `dashboard/e2e/fixtures.ts`, `dashboard/e2e/tenant-login.spec.ts`
- Test: `dashboard/src/main.basepath.test.ts`

**Interfaces:**
- Produces: dashboard served at `<host>/app/…`; e2e base `http://demo.etqan.localhost` (edge on port 80 — Task 14) with `login()` visiting `${baseUrl}/app/login`.

- [ ] **Step 1: Failing test** — `src/main.basepath.test.ts`

```ts
import { describe, expect, it } from "vitest";
import config from "../vite.config";

describe("dashboard is served under /app/", () => {
	it("sets Vite base", () => {
		expect((config as { base?: string }).base).toBe("/app/");
	});
});
```

Run `npx pnpm@10 vitest run src/main.basepath.test.ts` → FAIL.

- [ ] **Step 2: Implement**
  - `vite.config.ts`: add `base: "/app/",` to the config object.
  - `src/main.tsx`: `createRouter({ routeTree, context: { queryClient }, basepath: "/app" })`.
  - `nginx.conf`:

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    add_header X-Content-Type-Options "nosniff" always;

    location /app/assets/ {
        add_header X-Content-Type-Options "nosniff" always;
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files $uri =404;
    }

    location /app/ {
        add_header X-Content-Type-Options "nosniff" always;
        add_header Cache-Control "no-cache";
        try_files $uri $uri/ /app/index.html;
    }

    location = /app { return 301 /app/; }
}
```

  - `Dockerfile` production stage: `COPY --from=build /app/dist /usr/share/nginx/html/app`.
  - `e2e/fixtures.ts`: `DEMO_URL` default `http://demo.etqan.localhost`, `OTHER_URL` default `http://other.etqan.localhost`; `login()` goes to `${baseUrl}/app/login`. `playwright.config.ts` default `baseURL` `http://demo.etqan.localhost`. In `tenant-login.spec.ts` change `${DEMO_URL}/` to `${DEMO_URL}/app/` and the login URL assertions to `/\/app\/login/`.

- [ ] **Step 3: Verify** — `npx pnpm@10 tsc --noEmit && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`; `ls dist/index.html` and `grep -o '/app/assets/[^"]*' dist/index.html | head -1` prints an `/app/assets/…` path.

- [ ] **Step 4: Commit** — `feat: serve the dashboard under /app/`.

---

### Task 10: Runtime branding in the dashboard + admin-only nav

**Files:**
- Create: `dashboard/src/features/branding/{api.ts,queries.ts,apply.ts,BrandProvider.tsx,index.ts}`, `dashboard/src/features/branding/apply.test.ts`, `dashboard/src/features/branding/BrandProvider.test.tsx`
- Modify: `dashboard/src/main.tsx` (wrap in `BrandProvider`), `dashboard/src/features/shell/AppTopbar.tsx`, `dashboard/src/ui/auth-layout.tsx`, `dashboard/src/features/shell/nav.ts` (+ `requiresRole`), `dashboard/src/features/shell/nav.test.ts`, callers of `visibleNavItems` (pass `me.role`)

**Interfaces:**
- Produces: `type Branding = { name: {ar: string; en: string}; logo_url: string; favicon_url: string; primary_color: string; primary_text: string; accent_color: string; … }`; `useBranding()` (TanStack Query, key `["branding"]`, `staleTime: 60_000`, GET `site/branding/`); `applyBranding(b: Branding | undefined, doc = document)` sets CSS vars `--primary`, `--primary-foreground`, `--accent`, favicon link, and `data-academy-name` on `<html>`; `useBrandName()` returns the name in the current i18n language (fallback: host); `<BrandWordmark className>` renders logo `<img alt="">` + name; `NavItem.requiresRole?: Role` and `visibleNavItems(items, profiles, role)`; nav entry `{ to: "/website", labelKey: "nav.website", icon: Globe, requiresRole: "admin" }`; document title `"<page> · <academy name>"` via `usePageTitle(page: string)`.

- [ ] **Step 1: Failing tests**

`src/features/branding/apply.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { applyBranding } from "./apply";

const b = {
	name: { ar: "أكاديمية نور", en: "Noor Academy" },
	tagline: { ar: "", en: "" },
	logo_url: "",
	favicon_url: "http://x.test/f.png",
	share_image_url: "",
	primary_color: "#0E7C66",
	primary_text: "#FFFFFF",
	accent_color: "#C8962E",
	contact: { email: "", phone: "", whatsapp: "", address: { ar: "", en: "" } },
	social: {},
	show_powered_by: true,
};

describe("applyBranding", () => {
	it("sets colours, favicon and name", () => {
		applyBranding(b);
		const root = document.documentElement;
		expect(root.style.getPropertyValue("--primary")).toBe("#0E7C66");
		expect(root.style.getPropertyValue("--primary-foreground")).toBe("#FFFFFF");
		expect(root.style.getPropertyValue("--accent")).toBe("#C8962E");
		expect(document.querySelector<HTMLLinkElement>('link[rel="icon"]')?.href).toBe("http://x.test/f.png");
	});

	it("clears overrides when branding is missing", () => {
		applyBranding(b);
		applyBranding(undefined);
		expect(document.documentElement.style.getPropertyValue("--primary")).toBe("");
	});
});
```

`src/features/branding/BrandProvider.test.tsx` — renders `<BrandWordmark />` inside `QueryClientProvider` with `api.get` mocked (`vi.spyOn(api, "get").mockResolvedValue({ data: b })`) and i18n set to `ar`, expects text "أكاديمية نور"; with `api.get` rejected, expects the host name fallback (`window.location.hostname`).

Update `src/features/shell/nav.test.ts`: `NAV_ITEMS.map(i => i.to)` equals `["/", "/family", "/website", "/account"]`; `visibleNavItems(NAV_ITEMS, [], "admin")` contains `/website`; with role `"teacher"` it does not.

- [ ] **Step 2: Implement**

`api.ts`:

```ts
import { api } from "@/lib/api";

export type Pair = { ar: string; en: string };
export type Branding = {
	name: Pair;
	tagline: Pair;
	logo_url: string;
	favicon_url: string;
	share_image_url: string;
	primary_color: string;
	primary_text: string;
	accent_color: string;
	contact: { email: string; phone: string; whatsapp: string; address: Pair };
	social: Record<string, string>;
	show_powered_by: boolean;
};

export const brandingApi = {
	get: async (): Promise<Branding> => (await api.get<Branding>("site/branding/")).data,
};
```

`queries.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { brandingApi } from "./api";

export const brandingQueryKey = ["branding"] as const;

export function useBranding() {
	return useQuery({ queryKey: brandingQueryKey, queryFn: brandingApi.get, staleTime: 60_000, retry: false });
}

export function useBrandName(): string {
	const { i18n } = useTranslation();
	const { data } = useBranding();
	if (!data) return window.location.hostname;
	return i18n.language.startsWith("ar") ? data.name.ar : data.name.en;
}
```

`apply.ts`:

```ts
import type { Branding } from "./api";

const VARS = ["--primary", "--primary-foreground", "--accent"] as const;

export function applyBranding(b: Branding | undefined, doc: Document = document): void {
	const root = doc.documentElement;
	if (!b) {
		for (const v of VARS) root.style.removeProperty(v);
		return;
	}
	root.style.setProperty("--primary", b.primary_color);
	root.style.setProperty("--primary-foreground", b.primary_text);
	root.style.setProperty("--accent", b.accent_color);
	root.dataset.academyName = b.name.en;
	if (b.favicon_url) {
		let link = doc.querySelector<HTMLLinkElement>('link[rel="icon"]');
		if (!link) {
			link = doc.createElement("link");
			link.rel = "icon";
			doc.head.appendChild(link);
		}
		link.href = b.favicon_url;
	}
}
```

`BrandProvider.tsx`:

```tsx
import { type ReactNode, useEffect } from "react";
import { applyBranding } from "./apply";
import { useBranding, useBrandName } from "./queries";

export function BrandProvider({ children }: { children: ReactNode }) {
	const { data } = useBranding();
	useEffect(() => applyBranding(data), [data]);
	return <>{children}</>;
}

export function usePageTitle(page: string) {
	const name = useBrandName();
	useEffect(() => {
		document.title = page ? `${page} · ${name}` : name;
	}, [page, name]);
}

export function BrandWordmark({ className }: { className?: string }) {
	const { data } = useBranding();
	const name = useBrandName();
	return (
		<span className={className}>
			{data?.logo_url ? <img src={data.logo_url} alt="" className="inline-block h-8 w-auto me-2 align-middle" /> : null}
			<span className="align-middle">{name}</span>
		</span>
	);
}
```

`index.ts` re-exports. In `main.tsx`, put `<BrandProvider>` inside `QueryClientProvider` wrapping `RouterProvider`. Replace the `etqan<span…>.</span>` wordmarks in `AppTopbar.tsx` and `auth-layout.tsx` with `<BrandWordmark className="…same classes…" />`. Call `usePageTitle(t("…"))` in the login, home, account, family routes and the Website routes (Task 11).

`nav.ts`: add `import { Globe } from "lucide-react"`, `import type { Role } from "@/features/identity/schemas"`, `requiresRole?: Role` on `NavItem`, the `/website` item before `/account`, and:

```ts
export function visibleNavItems(items: NavItem[], profiles: readonly ProfileType[], role?: Role): NavItem[] {
	return items.filter((i) => {
		if (i.requiresRole) return i.requiresRole === role;
		if (i.requires) return profiles.includes(i.requires);
		if (i.requiresAny) return i.requiresAny.some((r) => profiles.includes(r));
		return true;
	});
}
```

Update every `visibleNavItems(…, me.profiles)` call (AppSidebar, home route) to pass `me.role`. Add `nav.website` to both locale files (`"Website"` / `"الموقع"`).

- [ ] **Step 3: Verify and commit** — `tsc`, `lint`, `test:coverage`, `build`; commit `feat: brand the dashboard from the academy's settings`.

---

### Task 11: Website area in the dashboard

**Files:**
- Create: `dashboard/src/features/website/{api.ts,schemas.ts,queries.ts,BilingualField.tsx,RichTextEditor.tsx,BrandingForm.tsx,HomePageForm.tsx,PagesList.tsx,PageEditor.tsx,TestimonialsManager.tsx,InquiriesList.tsx,index.ts}` + a `*.test.tsx` beside each form/list
- Create routes: `dashboard/src/routes/_authed/website.tsx` (layout with sub-nav + admin guard), `website/index.tsx` (redirect to branding), `website/branding.tsx`, `website/home.tsx`, `website/pages.index.tsx`, `website/pages.$pageId.tsx` (`new` for create), `website/testimonials.tsx`, `website/inquiries.tsx`
- Modify: `dashboard/package.json` (+ `@tiptap/react`, `@tiptap/starter-kit`, `@tiptap/extension-link`), locale files (`website.*` keys, ar + en)

**Interfaces:**
- Consumes: Task 7 endpoints; `useMe()` (`role`), `usePageTitle`.
- Produces: admin guard — `website.tsx` `beforeLoad` loads `me` and `throw redirect({ to: "/" })` unless `role === "admin"`; forms use react-hook-form + zod, each bilingual pair rendered by `BilingualField` (Arabic input `dir="rtl" lang="ar"`, English `dir="ltr" lang="en"`, both required where the API requires them); file inputs send multipart; `RichTextEditor` (TipTap StarterKit + Link, headings limited to h2/h3) emits HTML; after save, `queryClient.invalidateQueries({ queryKey: ["branding"] })` so the dashboard rebrands immediately; "Preview site" link opens `/${i18n.language}/` in a new tab.

- [ ] **Step 1: Failing tests** (Vitest + Testing Library, `api` mocked with `vi.spyOn`):
  - `BrandingForm.test.tsx`: renders values from GET; submitting with an empty Arabic name shows a required error and does not call PATCH; submitting valid values calls `api.patch("site/admin/branding/", …)` and invalidates `["branding"]`; a 400 `{"primary_color": ["…readable…"]}` shows that message under the colour field.
  - `PageEditor.test.tsx`: slug `app` shows the server's slug error; saving a new page POSTs `site/admin/pages/` with `title_ar`, `title_en`, `body_ar`, `body_en` HTML.
  - `InquiriesList.test.tsx`: lists rows from `site/admin/inquiries/?status=new`; clicking "Mark handled" POSTs `…/handle/` and removes the row.
  - `website.guard.test.tsx`: the `/website` route redirects a `teacher` to `/`.
  - `RichTextEditor.test.tsx`: typing and toggling bold produces `<p><strong>…</strong></p>` via `onChange`.

- [ ] **Step 2: Implement** the files listed. Key code:

`api.ts`:

```ts
import { api } from "@/lib/api";

const B = "site/admin/";
export const websiteApi = {
	getBranding: async () => (await api.get(`${B}branding/`)).data,
	patchBranding: async (data: FormData | Record<string, unknown>) => (await api.patch(`${B}branding/`, data)).data,
	getLanding: async () => (await api.get(`${B}landing/`)).data,
	patchLanding: async (data: FormData | Record<string, unknown>) => (await api.patch(`${B}landing/`, data)).data,
	listPages: async () => (await api.get(`${B}pages/`)).data,
	getPage: async (id: number) => (await api.get(`${B}pages/${id}/`)).data,
	createPage: async (d: Record<string, unknown>) => (await api.post(`${B}pages/`, d)).data,
	updatePage: async (id: number, d: Record<string, unknown>) => (await api.patch(`${B}pages/${id}/`, d)).data,
	deletePage: async (id: number) => api.delete(`${B}pages/${id}/`),
	listTestimonials: async () => (await api.get(`${B}testimonials/`)).data,
	createTestimonial: async (d: Record<string, unknown>) => (await api.post(`${B}testimonials/`, d)).data,
	updateTestimonial: async (id: number, d: Record<string, unknown>) => (await api.patch(`${B}testimonials/${id}/`, d)).data,
	deleteTestimonial: async (id: number) => api.delete(`${B}testimonials/${id}/`),
	listInquiries: async (status: "new" | "handled") => (await api.get(`${B}inquiries/`, { params: { status } })).data,
	handleInquiry: async (id: number) => (await api.post(`${B}inquiries/${id}/handle/`)).data,
};

export function toFormData(values: Record<string, unknown>): FormData | Record<string, unknown> {
	const hasFile = Object.values(values).some((v) => v instanceof File);
	if (!hasFile) return values;
	const fd = new FormData();
	for (const [k, v] of Object.entries(values)) {
		if (v === undefined || v === null) continue;
		fd.append(k, v instanceof File ? v : String(v));
	}
	return fd;
}
```

`BilingualField.tsx`:

```tsx
import type { FieldError, UseFormRegister } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Field, Input, Label } from "@/ui";

type Props = {
	name: string;
	label: string;
	register: UseFormRegister<Record<string, unknown>>;
	errors: Partial<Record<string, FieldError>>;
	multiline?: boolean;
};

export function BilingualField({ name, label, register, errors, multiline }: Props) {
	const { t } = useTranslation();
	return (
		<div className="grid gap-3 sm:grid-cols-2">
			{(["ar", "en"] as const).map((lang) => {
				const id = `${name}_${lang}`;
				const Tag = multiline ? "textarea" : Input;
				return (
					<Field key={lang}>
						<Label htmlFor={id}>{`${label} (${t(`website.lang.${lang}`)})`}</Label>
						<Tag id={id} dir={lang === "ar" ? "rtl" : "ltr"} lang={lang} {...register(id)} aria-invalid={!!errors[id]} />
						{errors[id] ? <p role="alert" className="text-sm text-destructive">{errors[id]?.message}</p> : null}
					</Field>
				);
			})}
		</div>
	);
}
```

(Use the project's existing `@/ui` exports; if `Field`/`Label`/`Input` differ in name or props, follow `src/ui/index.ts`.)

`schemas.ts` (zod): `brandingSchema` with `name_ar`/`name_en` `z.string().min(1)`, colours `z.string().regex(/^#[0-9A-Fa-f]{6}$/)`, optional contact/social strings (URLs validated with `z.url().or(z.literal(""))`), `show_powered_by: z.boolean()`; `landingSchema` with `hero_title_ar/en` `min(1)`, optional subtitles, `cta_label_ar/en` `min(1)`, `about_ar/en` strings, five `show_*` booleans; `pageSchema` with `slug` `/^[a-z0-9-]{1,60}$/`, both titles and bodies `min(1)`, `is_published`, `show_in_menu`, `order`, optional SEO descriptions (`max(160)`); `testimonialSchema` with `author_name` min 1, `quote_ar/en` min 1, `stars` 1–5.

`RichTextEditor.tsx`:

```tsx
import Link from "@tiptap/extension-link";
import { EditorContent, useEditor } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { useTranslation } from "react-i18next";
import { Button } from "@/ui";

export function RichTextEditor({ value, onChange, dir, label }: { value: string; onChange: (html: string) => void; dir: "rtl" | "ltr"; label: string }) {
	const { t } = useTranslation();
	const editor = useEditor({
		extensions: [StarterKit.configure({ heading: { levels: [2, 3] }, codeBlock: false, code: false, horizontalRule: false }), Link.configure({ openOnClick: false })],
		content: value,
		onUpdate: ({ editor: e }) => onChange(e.getHTML()),
		editorProps: { attributes: { dir, "aria-label": label, class: "prose min-h-40 rounded-md border border-border p-3 focus:outline-none" } },
	});
	if (!editor) return null;
	return (
		<div>
			<div className="mb-2 flex gap-2" role="toolbar" aria-label={label}>
				<Button type="button" variant="outline" size="sm" onClick={() => editor.chain().focus().toggleBold().run()}>{t("website.editor.bold")}</Button>
				<Button type="button" variant="outline" size="sm" onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}>{t("website.editor.heading")}</Button>
				<Button type="button" variant="outline" size="sm" onClick={() => editor.chain().focus().toggleBulletList().run()}>{t("website.editor.list")}</Button>
				<Button type="button" variant="outline" size="sm" onClick={() => { const url = window.prompt(t("website.editor.linkPrompt")); if (url) editor.chain().focus().setLink({ href: url }).run(); }}>{t("website.editor.link")}</Button>
			</div>
			<EditorContent editor={editor} />
		</div>
	);
}
```

The forms follow the pattern of existing identity forms (`src/features/identity/components/*Form.tsx`): `useForm({ resolver: zodResolver(schema), values: data })`, `useMutation` calling `websiteApi.*`, on 400 map `error.response.data` field arrays to `setError(field, { message })` (reuse `parseApiError` from `@/features/identity/api`), success toast via the existing `toast` from `@/ui`. File fields are `<input type="file" accept="image/png,image/jpeg,image/webp">` (favicon: `image/png,image/x-icon`) plus a "Remove" checkbox mapped to `<field>_clear`. Every route calls `usePageTitle(t("website.<section>.title"))`.

Add the `website.*` translation keys to `src/locales/en/common.json` and `src/locales/ar/common.json` (both complete; titles, field labels, buttons, empty states, `lang.ar = "العربية"/"Arabic"`, `lang.en = "الإنجليزية"/"English"`).

- [ ] **Step 3: Verify and commit** — `tsc`, `lint`, `test:coverage` (floors hold), `build`; commit `feat: website area for academy admins`.

---

### Task 12: Marketing repo — SSR skeleton with academy resolution

**Files:**
- Create repo `Etqan-agency/etqan_tutor_marketing` (mirror of `kaleem-lms/marketing`), meta submodule `marketing/`
- Rewrite: `marketing/package.json`, `astro.config.mjs`, `Dockerfile`, `CLAUDE.md`, `README.md`, `src/styles/global.css`
- Delete: `marketing/nginx.conf`, `marketing/src/pages/index.astro` (replaced), `marketing/public/favicon.*`
- Create: `marketing/src/lib/{http.ts,site.ts,i18n.ts,seo.ts}`, `marketing/src/middleware.ts`, `marketing/src/env.d.ts`, `marketing/src/layouts/Layout.astro`, `marketing/src/components/StatusPage.astro`, `marketing/vitest.config.ts`, `marketing/test/{fixtures.ts,site.test.ts,seo.test.ts,layout.test.ts}`, `marketing/biome.json`

**Interfaces:**
- Produces:
  - `src/lib/http.ts`: `getJson(path: string, host: string): Promise<{ status: number; body: unknown }>` — `node:http` request to `SITE_API_ORIGIN` (env, default `http://127.0.0.1:8000`) with header `Host: host`, `Accept: application/json`, 5 s timeout. (Node's `fetch` refuses to set `Host`, hence `node:http`.)
  - `src/lib/site.ts`: `type SitePayload` (spec §3.6), `type PagePayload`; `resolveSite(host) → {kind:"ok", site} | {kind:"notfound"} | {kind:"suspended"}` with the Global-Constraints cache (Map keyed by lower-cased host without port); `getPage(host, slug)`; `clearSiteCache()` for tests.
  - `src/lib/i18n.ts`: `LANGS = ["ar","en"] as const`, `type Lang`, `dir(lang)`, `pick(pair, lang)`, `ui(lang)` UI strings (nav, sign-in, contact form labels, sent/failed messages, not-found/unavailable texts, powered-by), `preferredLang(acceptLanguage: string|null): Lang` (ar unless the first matching tag is en).
  - `src/lib/seo.ts`: `canonical(site, path)`, `alternates(site, pathWithoutLang)` → `[{hreflang:"ar",href},{hreflang:"en",href},{hreflang:"x-default",href}]`, all on `https://` + `site.academy.canonical_host` (scheme from env `SITE_SCHEME`, default `https`, `http` in local/CI).
  - `src/middleware.ts`: sets `Astro.locals.host` and `Astro.locals.siteResult`; security headers `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`.
  - `Layout.astro` props `{ site, lang, title, description, path }`: `<html lang dir>`, favicon, OG/Twitter tags, canonical, hreflang, JSON-LD `EducationalOrganization`, inline `<style>` setting `--primary`, `--primary-foreground`, `--accent` from branding.
  - `StatusPage.astro` props `{ kind: "notfound" | "suspended" }`, `noindex`.

- [ ] **Step 1: Create the repo and submodule**

```bash
cd /home/abdulkhalek/Projects/etqan_tutor
gh repo create Etqan-agency/etqan_tutor_marketing --private
tmp=$(mktemp -d) && git clone --mirror https://github.com/kaleem-lms/marketing.git "$tmp/m.git"
git -C "$tmp/m.git" push --mirror git@github.com:Etqan-agency/etqan_tutor_marketing.git && rm -rf "$tmp"
git submodule add -b main https://github.com/Etqan-agency/etqan_tutor_marketing.git marketing
git -C marketing switch -c feat/academy-sites
```

- [ ] **Step 2: Project files**

`package.json`:

```json
{
	"name": "etqan_tutor_marketing",
	"type": "module",
	"version": "0.1.0",
	"engines": { "node": ">=22.12.0" },
	"packageManager": "pnpm@10.28.0",
	"scripts": {
		"dev": "astro dev",
		"build": "astro build",
		"start": "node ./dist/server/entry.mjs",
		"check": "astro check",
		"lint": "biome ci .",
		"test": "vitest run",
		"test:coverage": "vitest run --coverage"
	},
	"dependencies": {
		"@astrojs/node": "^9.4.0",
		"@etqan/tokens": "github:Etqan-agency/etqan_tutor_tokens#v0.3.0",
		"@fontsource-variable/fraunces": "^5.2.9",
		"@fontsource/ibm-plex-sans-arabic": "^5.2.6",
		"@fontsource/inter": "^5.2.8",
		"astro": "^6.1.5",
		"tailwindcss": "^4.2.2"
	},
	"devDependencies": {
		"@astrojs/check": "^0.9.10",
		"@biomejs/biome": "^2.4.0",
		"@tailwindcss/vite": "^4.3.1",
		"@vitest/coverage-v8": "^3.2.0",
		"typescript": "^6.0.3",
		"vitest": "^3.2.0"
	}
}
```

(Resolve exact versions with `npx pnpm@10 add` if a range doesn't exist; keep Astro 6 and a matching `@astrojs/node` major.)

`astro.config.mjs`:

```js
// @ts-check
import node from "@astrojs/node";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

export default defineConfig({
	output: "server",
	adapter: node({ mode: "standalone" }),
	server: { host: true, port: 4321 },
	security: { checkOrigin: false },
	vite: {
		plugins: [tailwindcss()],
		server: { allowedHosts: true, hmr: { clientPort: 80 } },
	},
});
```

(`allowedHosts: true` because academy hosts, including custom domains, are unknown at build time; the edge decides which hosts reach Astro. `checkOrigin: false` because the site has no Astro form actions; the contact form posts to Django.)

`src/styles/global.css`:

```css
@import "tailwindcss";
@import "@etqan/tokens/tokens.css";
@import "@etqan/tokens/theme.css";
@import "@fontsource-variable/fraunces";
@import "@fontsource/inter/400.css";
@import "@fontsource/inter/600.css";
@import "@fontsource/ibm-plex-sans-arabic/400.css";
@import "@fontsource/ibm-plex-sans-arabic/600.css";

:root:lang(ar) body { font-family: "IBM Plex Sans Arabic", system-ui, sans-serif; }
```

`vitest.config.ts`:

```ts
import { getViteConfig } from "astro/config";

export default getViteConfig({
	test: {
		environment: "node",
		include: ["test/**/*.test.ts"],
		coverage: {
			provider: "v8",
			include: ["src/lib/**", "src/components/**", "src/layouts/**"],
			thresholds: { lines: 80, branches: 70, functions: 70, statements: 80 },
		},
	},
});
```

`Dockerfile` — keep the Kaleem `build` and `dev` stages (with `@etqan/tokens` and the secret-mounted git auth, both `https://github.com/` and `git@github.com:` rewrites with `--add`), and replace the nginx `production` stage with:

```dockerfile
FROM node:22-alpine AS production
WORKDIR /app
ENV NODE_ENV=production HOST=0.0.0.0 PORT=4321
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
USER node
EXPOSE 4321
CMD ["node", "./dist/server/entry.mjs"]
```

Delete `nginx.conf`. Rewrite `CLAUDE.md`: "Server-rendered public site for each academy. Every request resolves the academy via `GET ${SITE_API_ORIGIN}/api/v1/site/` with the visitor's Host. No content lives in this repo; all text comes from the API in Arabic and English."

- [ ] **Step 3: Failing tests** — `test/fixtures.ts` exports a complete `SitePayload` (`demoSite`) and `test/site.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import * as http from "../src/lib/http";
import { clearSiteCache, resolveSite } from "../src/lib/site";
import { demoSite } from "./fixtures";

afterEach(() => {
	clearSiteCache();
	vi.restoreAllMocks();
});

describe("resolveSite", () => {
	it("returns the site for a known host and forwards the host", async () => {
		const spy = vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: demoSite });
		const r = await resolveSite("Demo.Etqan.Localhost:4321");
		expect(r).toEqual({ kind: "ok", site: demoSite });
		expect(spy).toHaveBeenCalledWith("/api/v1/site/", "demo.etqan.localhost");
	});

	it("maps 404 and 403 suspended", async () => {
		vi.spyOn(http, "getJson").mockResolvedValueOnce({ status: 404, body: {} }).mockResolvedValueOnce({ status: 403, body: { code: "tenant.suspended" } });
		expect((await resolveSite("a.test")).kind).toBe("notfound");
		expect((await resolveSite("b.test")).kind).toBe("suspended");
	});

	it("caches per host and never across hosts", async () => {
		const spy = vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: demoSite });
		await resolveSite("a.test");
		await resolveSite("a.test");
		await resolveSite("b.test");
		expect(spy).toHaveBeenCalledTimes(2);
	});

	it("expires after the TTL", async () => {
		vi.useFakeTimers();
		const spy = vi.spyOn(http, "getJson").mockResolvedValue({ status: 200, body: demoSite });
		await resolveSite("a.test");
		vi.advanceTimersByTime(61_000);
		await resolveSite("a.test");
		expect(spy).toHaveBeenCalledTimes(2);
		vi.useRealTimers();
	});

	it("treats network errors as notfound without caching", async () => {
		const spy = vi.spyOn(http, "getJson").mockRejectedValue(new Error("ECONNREFUSED"));
		expect((await resolveSite("a.test")).kind).toBe("notfound");
		await resolveSite("a.test");
		expect(spy).toHaveBeenCalledTimes(2);
	});
});
```

`test/seo.test.ts`: `canonical(demoSite, "/en/")` → `https://demo.example/en/` given `canonical_host: "demo.example"`; `alternates(demoSite, "/p/policies")` returns ar/en/x-default hrefs (`x-default` → Arabic); `preferredLang("en-US,en;q=0.9")` → `en`, `preferredLang("fr")` → `ar`, `preferredLang(null)` → `ar`.

`test/layout.test.ts` uses the container API:

```ts
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, expect, it } from "vitest";
import Layout from "../src/layouts/Layout.astro";
import StatusPage from "../src/components/StatusPage.astro";
import { demoSite } from "./fixtures";

describe("Layout", () => {
	it("renders Arabic RTL with hreflang, canonical and brand colour", async () => {
		const c = await AstroContainer.create();
		const html = await c.renderToString(Layout, { props: { site: demoSite, lang: "ar", title: "t", description: "d", path: "/" } });
		expect(html).toContain('lang="ar"');
		expect(html).toContain('dir="rtl"');
		expect(html).toContain('hreflang="en"');
		expect(html).toContain('rel="canonical" href="https://demo.example/ar/"');
		expect(html).toContain("--primary:#0E7C66");
		expect(html).toContain('"@type":"EducationalOrganization"');
	});
});

describe("StatusPage", () => {
	it("is noindex and names no academy", async () => {
		const c = await AstroContainer.create();
		const html = await c.renderToString(StatusPage, { props: { kind: "notfound" } });
		expect(html).toContain('name="robots" content="noindex"');
		expect(html).not.toContain("Demo Academy");
	});
});
```

Run `npx pnpm@10 install && npx pnpm@10 test` → FAIL (modules missing).

- [ ] **Step 4: Implement `src/lib/*`, middleware, Layout, StatusPage**

`src/lib/http.ts`:

```ts
import http from "node:http";

const ORIGIN = new URL(process.env.SITE_API_ORIGIN ?? "http://127.0.0.1:8000");

export function getJson(path: string, host: string): Promise<{ status: number; body: unknown }> {
	return new Promise((resolve, reject) => {
		const req = http.request(
			{ hostname: ORIGIN.hostname, port: ORIGIN.port || 80, path, method: "GET", headers: { host, accept: "application/json" }, timeout: 5000 },
			(res) => {
				let raw = "";
				res.setEncoding("utf8");
				res.on("data", (c) => { raw += c; });
				res.on("end", () => {
					let body: unknown = {};
					try { body = raw ? JSON.parse(raw) : {}; } catch { body = {}; }
					resolve({ status: res.statusCode ?? 502, body });
				});
			},
		);
		req.on("timeout", () => req.destroy(new Error("timeout")));
		req.on("error", reject);
		req.end();
	});
}
```

`src/lib/site.ts`:

```ts
import { getJson } from "./http";

export type Pair = { ar: string; en: string };
export type SitePayload = {
	academy: { subdomain: string; canonical_host: string };
	branding: {
		name: Pair; tagline: Pair; logo_url: string; favicon_url: string; share_image_url: string;
		primary_color: string; primary_text: string; accent_color: string;
		contact: { email: string; phone: string; whatsapp: string; address: Pair };
		social: Record<string, string>; show_powered_by: boolean;
	};
	landing: {
		hero_title: Pair; hero_subtitle: Pair; hero_image_url: string; cta_label: Pair; about_html: Pair;
		sections: { courses: boolean; packages: boolean; teachers: boolean; testimonials: boolean; contact: boolean };
	};
	testimonials: { author_name: string; quote: Pair; stars: number }[];
	pages: { slug: string; title: Pair; show_in_menu: boolean }[];
};
export type PagePayload = { slug: string; title: Pair; body_html: Pair; seo_description: Pair };
export type SiteResult = { kind: "ok"; site: SitePayload } | { kind: "notfound" } | { kind: "suspended" };

const OK_TTL = 60_000;
const MISS_TTL = 30_000;
const cache = new Map<string, { expires: number; value: SiteResult }>();

export function normalizeHost(host: string): string {
	return host.trim().toLowerCase().replace(/:\d+$/, "");
}

export function clearSiteCache(): void {
	cache.clear();
}

export async function resolveSite(rawHost: string): Promise<SiteResult> {
	const host = normalizeHost(rawHost);
	const hit = cache.get(host);
	if (hit && hit.expires > Date.now()) return hit.value;
	let value: SiteResult;
	try {
		const { status, body } = await getJson("/api/v1/site/", host);
		if (status === 200) value = { kind: "ok", site: body as SitePayload };
		else if (status === 403 && (body as { code?: string }).code === "tenant.suspended") value = { kind: "suspended" };
		else value = { kind: "notfound" };
	} catch {
		return { kind: "notfound" };
	}
	cache.set(host, { expires: Date.now() + (value.kind === "ok" ? OK_TTL : MISS_TTL), value });
	return value;
}

export async function getPage(rawHost: string, slug: string): Promise<PagePayload | null> {
	if (!/^[a-z0-9-]{1,60}$/.test(slug)) return null;
	const { status, body } = await getJson(`/api/v1/site/pages/${slug}/`, normalizeHost(rawHost));
	return status === 200 ? (body as PagePayload) : null;
}
```

`src/lib/i18n.ts`:

```ts
import type { Pair } from "./site";

export const LANGS = ["ar", "en"] as const;
export type Lang = (typeof LANGS)[number];
export const isLang = (v: string | undefined): v is Lang => v === "ar" || v === "en";
export const dir = (lang: Lang) => (lang === "ar" ? "rtl" : "ltr");
export const pick = (pair: Pair, lang: Lang) => pair[lang];

export function preferredLang(accept: string | null): Lang {
	for (const part of (accept ?? "").split(",")) {
		const tag = part.trim().split(";")[0].toLowerCase();
		if (tag.startsWith("ar")) return "ar";
		if (tag.startsWith("en")) return "en";
	}
	return "ar";
}

const STRINGS = {
	ar: {
		home: "الرئيسية", signIn: "تسجيل الدخول", switchLang: "English", about: "من نحن", testimonials: "آراء طلابنا",
		contactTitle: "تواصل معنا", name: "الاسم", email: "البريد الإلكتروني", phone: "رقم الهاتف", whatsapp: "لدي واتساب على هذا الرقم",
		message: "رسالتك", send: "إرسال", sent: "تم استلام رسالتك، سنتواصل معك قريباً.", failed: "تعذر الإرسال، حاول مرة أخرى.",
		notFoundTitle: "الموقع غير موجود", notFoundBody: "لا يوجد موقع أكاديمية على هذا العنوان.",
		unavailableTitle: "الموقع غير متاح مؤقتاً", unavailableBody: "يرجى المحاولة لاحقاً.",
		pageNotFound: "الصفحة غير موجودة", poweredBy: "مدعوم من إتقان",
	},
	en: {
		home: "Home", signIn: "Sign in", switchLang: "العربية", about: "About us", testimonials: "What our students say",
		contactTitle: "Contact us", name: "Name", email: "Email", phone: "Phone number", whatsapp: "I have WhatsApp on this number",
		message: "Your message", send: "Send", sent: "Thanks — we received your message and will get back to you soon.", failed: "Could not send. Please try again.",
		notFoundTitle: "Site not found", notFoundBody: "There is no academy site at this address.",
		unavailableTitle: "This site is temporarily unavailable", unavailableBody: "Please try again later.",
		pageNotFound: "Page not found", poweredBy: "Powered by Etqan",
	},
} as const;

export const ui = (lang: Lang) => STRINGS[lang];
```

`src/lib/seo.ts`:

```ts
import type { SitePayload } from "./site";

const scheme = () => process.env.SITE_SCHEME ?? "https";

export function canonical(site: SitePayload, path: string): string {
	return `${scheme()}://${site.academy.canonical_host}${path}`;
}

export function alternates(site: SitePayload, pathWithoutLang: string) {
	const rest = pathWithoutLang === "/" ? "/" : pathWithoutLang;
	return [
		{ hreflang: "ar", href: canonical(site, `/ar${rest}`) },
		{ hreflang: "en", href: canonical(site, `/en${rest}`) },
		{ hreflang: "x-default", href: canonical(site, `/ar${rest}`) },
	];
}
```

`src/env.d.ts`:

```ts
/// <reference types="astro/client" />
declare namespace App {
	interface Locals {
		host: string;
		siteResult: import("./lib/site").SiteResult;
	}
}
```

`src/middleware.ts`:

```ts
import { defineMiddleware } from "astro:middleware";
import { resolveSite } from "./lib/site";

export const onRequest = defineMiddleware(async (context, next) => {
	const host = context.request.headers.get("host") ?? "";
	context.locals.host = host;
	context.locals.siteResult = await resolveSite(host);
	const response = await next();
	response.headers.set("X-Content-Type-Options", "nosniff");
	response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
	return response;
});
```

`src/layouts/Layout.astro`:

```astro
---
import "../styles/global.css";
import { dir, type Lang, pick } from "../lib/i18n";
import { alternates, canonical } from "../lib/seo";
import type { SitePayload } from "../lib/site";

interface Props { site: SitePayload; lang: Lang; title: string; description: string; path: string; }
const { site, lang, title, description, path } = Astro.props;
const b = site.branding;
const name = pick(b.name, lang);
const url = canonical(site, `/${lang}${path}`);
const socials = Object.values(b.social).filter(Boolean);
const jsonLd = JSON.stringify({
	"@context": "https://schema.org", "@type": "EducationalOrganization", name, url: canonical(site, `/${lang}/`),
	...(b.logo_url ? { logo: b.logo_url } : {}), ...(b.contact.email ? { email: b.contact.email } : {}),
	...(b.contact.phone ? { telephone: b.contact.phone } : {}), ...(socials.length ? { sameAs: socials } : {}),
}).replace(/</g, "\\u003c");
const brandCss = `:root{--primary:${b.primary_color};--primary-foreground:${b.primary_text};--accent:${b.accent_color};}`;
---
<!doctype html>
<html lang={lang} dir={dir(lang)}>
<head>
	<meta charset="UTF-8" />
	<meta name="viewport" content="width=device-width, initial-scale=1" />
	<title>{title === name ? name : `${title} · ${name}`}</title>
	<meta name="description" content={description} />
	<link rel="canonical" href={url} />
	{alternates(site, path).map((a) => <link rel="alternate" hreflang={a.hreflang} href={a.href} />)}
	{b.favicon_url && <link rel="icon" href={b.favicon_url} />}
	<meta property="og:type" content="website" />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:url" content={url} />
	<meta property="og:site_name" content={name} />
	<meta property="og:locale" content={lang === "ar" ? "ar_AR" : "en_US"} />
	{b.share_image_url && <meta property="og:image" content={b.share_image_url} />}
	<meta name="twitter:card" content={b.share_image_url ? "summary_large_image" : "summary"} />
	<style set:html={brandCss}></style>
	<script type="application/ld+json" set:html={jsonLd}></script>
</head>
<body class="min-h-screen bg-background text-foreground">
	<slot />
</body>
</html>
```

(Colours come from the API already validated as `#RRGGBB`; still, `brandCss` interpolates only the three validated fields. The `description` fallback is the tagline — pages must pass a non-empty string.)

`src/components/StatusPage.astro`:

```astro
---
import "../styles/global.css";
import { ui } from "../lib/i18n";

interface Props { kind: "notfound" | "suspended"; }
const { kind } = Astro.props;
const ar = ui("ar");
const en = ui("en");
const [titleAr, bodyAr, titleEn, bodyEn] = kind === "notfound"
	? [ar.notFoundTitle, ar.notFoundBody, en.notFoundTitle, en.notFoundBody]
	: [ar.unavailableTitle, ar.unavailableBody, en.unavailableTitle, en.unavailableBody];
Astro.response.status = kind === "notfound" ? 404 : 503;
---
<!doctype html>
<html lang="ar" dir="rtl">
<head>
	<meta charset="UTF-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />
	<meta name="robots" content="noindex" />
	<title>{titleEn}</title>
</head>
<body class="grid min-h-screen place-items-center bg-background p-8 text-center text-foreground">
	<main class="space-y-6">
		<section><h1 class="text-3xl font-semibold">{titleAr}</h1><p class="text-muted-foreground">{bodyAr}</p></section>
		<section lang="en" dir="ltr"><h2 class="text-2xl font-semibold">{titleEn}</h2><p class="text-muted-foreground">{bodyEn}</p></section>
	</main>
</body>
</html>
```

`src/pages/index.astro` (root):

```astro
---
import StatusPage from "../components/StatusPage.astro";
import { preferredLang } from "../lib/i18n";

const result = Astro.locals.siteResult;
if (result.kind === "ok") {
	return Astro.redirect(`/${preferredLang(Astro.request.headers.get("accept-language"))}/`, 302);
}
---
<StatusPage kind={result.kind} />
```

`biome.json`: copy the dashboard's Biome config, pointing `files.includes` at `src/**`, `test/**`.

- [ ] **Step 5: Verify** — `npx pnpm@10 install && npx pnpm@10 check && npx pnpm@10 lint && npx pnpm@10 test:coverage && npx pnpm@10 build`.

- [ ] **Step 6: Commit and push** — commit `feat: tenant-aware SSR skeleton for academy sites`; `git push -u origin feat/academy-sites` (SSH if HTTPS lacks `workflow` scope). In meta: `git add .gitmodules marketing` and commit `chore: add etqan_tutor_marketing submodule` (on meta branch `feat/academy-sites`); update `scripts/check-token-pin.mjs` `CONSUMERS` to `["dashboard/package.json", "marketing/package.json"]` in the same commit and run it.

---

### Task 13: Marketing pages — landing, content pages, contact form, sitemap, robots

**Files:**
- Create: `marketing/src/components/{Header,Footer,Hero,About,Testimonials,ContactForm,PageBody}.astro`, `marketing/src/pages/[lang]/index.astro`, `marketing/src/pages/[lang]/p/[slug].astro`, `marketing/src/pages/sitemap.xml.ts`, `marketing/src/pages/robots.txt.ts`, `marketing/test/{pages.test.ts,components.test.ts}`

**Interfaces:**
- Consumes: Task 12 libs, spec §3.6 payload.
- Produces:
  - `/ar/` and `/en/`: Header (logo + name linking `/<lang>/`, menu of published pages with `show_in_menu`, language switch to the same path in the other language, "Sign in" → `/app/login`), Hero (title, subtitle, image, CTA scrolling to `#contact`), About (sanitised `about_html` via `set:html`), Testimonials (when `sections.testimonials` and non-empty), ContactForm (when `sections.contact`), Footer (contact line, social links, `poweredBy` when `show_powered_by`).
  - `/{lang}/p/{slug}`: page title + `body_html[lang]`, 404 status page (`ui(lang).pageNotFound`) inside the academy layout when missing.
  - Any other `lang` segment → 404 status page.
  - `/sitemap.xml`: `/ar/`, `/en/`, and `/ar|en/p/<slug>` for published pages, absolute on `canonical_host`, `<xhtml:link rel="alternate">` pairs.
  - `/robots.txt`: `User-agent: *`, `Allow: /`, `Disallow: /app/`, `Disallow: /api/`, `Sitemap: <canonical>/sitemap.xml`; for notfound/suspended hosts `Disallow: /`.
  - ContactForm posts JSON to `/api/v1/site/inquiries/` with `kind: "trial"` when opened from the CTA, else `contact`, includes hidden honeypot input `name="website"` (`tabindex="-1"`, `autocomplete="off"`, visually hidden), shows `role="status"` success or `role="alert"` failure text from `ui(lang)`; a small inline `<script>` handles submit with `fetch`, disables the button while sending.

- [ ] **Step 1: Failing tests** — `test/pages.test.ts` renders `src/pages/[lang]/index.astro` with the container API, passing `locals: { host: "demo.etqan.localhost", siteResult: { kind: "ok", site: demoSite } }` and `params: { lang: "en" }`:

```ts
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, expect, it, vi } from "vitest";
import * as site from "../src/lib/site";
import Landing from "../src/pages/[lang]/index.astro";
import Page from "../src/pages/[lang]/p/[slug].astro";
import { GET as robots } from "../src/pages/robots.txt";
import { GET as sitemap } from "../src/pages/sitemap.xml";
import { demoSite } from "./fixtures";

const locals = { host: "demo.etqan.localhost", siteResult: { kind: "ok" as const, site: demoSite } };

describe("landing", () => {
	it("renders the academy in English", async () => {
		const c = await AstroContainer.create();
		const html = await c.renderToString(Landing, { params: { lang: "en" }, locals });
		expect(html).toContain("Demo Academy");
		expect(html).toContain(demoSite.landing.hero_title.en);
		expect(html).toContain('href="/app/login"');
		expect(html).toContain('href="/ar/"');
		expect(html).toContain('name="website"');
	});

	it("hides disabled sections", async () => {
		const c = await AstroContainer.create();
		const off = { ...demoSite, landing: { ...demoSite.landing, sections: { ...demoSite.landing.sections, contact: false, testimonials: false } } };
		const html = await c.renderToString(Landing, { params: { lang: "ar" }, locals: { ...locals, siteResult: { kind: "ok", site: off } } });
		expect(html).not.toContain('id="contact"');
		expect(html).not.toContain(demoSite.testimonials[0].quote.ar);
	});

	it("404s an unknown language", async () => {
		const c = await AstroContainer.create();
		const res = await c.renderToResponse(Landing, { params: { lang: "fr" }, locals });
		expect(res.status).toBe(404);
	});

	it("shows powered-by only when enabled", async () => {
		const c = await AstroContainer.create();
		const off = { ...demoSite, branding: { ...demoSite.branding, show_powered_by: false } };
		const html = await c.renderToString(Landing, { params: { lang: "en" }, locals: { ...locals, siteResult: { kind: "ok", site: off } } });
		expect(html).not.toContain("Powered by Etqan");
	});
});

describe("content page", () => {
	it("renders a published page", async () => {
		vi.spyOn(site, "getPage").mockResolvedValue({ slug: "policies", title: { ar: "سياسات", en: "Policies" }, body_html: { ar: "<p>ع</p>", en: "<p>e</p>" }, seo_description: { ar: "", en: "" } });
		const c = await AstroContainer.create();
		const html = await c.renderToString(Page, { params: { lang: "en", slug: "policies" }, locals });
		expect(html).toContain("<p>e</p>");
		vi.restoreAllMocks();
	});

	it("404s a missing page", async () => {
		vi.spyOn(site, "getPage").mockResolvedValue(null);
		const c = await AstroContainer.create();
		const res = await c.renderToResponse(Page, { params: { lang: "en", slug: "nope" }, locals });
		expect(res.status).toBe(404);
		vi.restoreAllMocks();
	});
});

describe("robots and sitemap", () => {
	it("sitemap lists both languages on the canonical host", async () => {
		const res = await sitemap({ locals } as never);
		const xml = await res.text();
		expect(xml).toContain("<loc>https://demo.example/ar/</loc>");
		expect(xml).toContain("<loc>https://demo.example/en/p/policies</loc>");
	});

	it("robots disallows everything for unknown hosts", async () => {
		const res = await robots({ locals: { host: "x", siteResult: { kind: "notfound" } } } as never);
		expect(await res.text()).toContain("Disallow: /\n");
	});
});
```

(`demoSite` in `test/fixtures.ts` has `canonical_host: "demo.example"`, one testimonial, one published page `policies` with `show_in_menu: true`, all sections enabled.)

- [ ] **Step 2: Implement** the components and routes. Key files:

`src/pages/[lang]/index.astro`:

```astro
---
import About from "../../components/About.astro";
import ContactForm from "../../components/ContactForm.astro";
import Footer from "../../components/Footer.astro";
import Header from "../../components/Header.astro";
import Hero from "../../components/Hero.astro";
import StatusPage from "../../components/StatusPage.astro";
import Testimonials from "../../components/Testimonials.astro";
import Layout from "../../layouts/Layout.astro";
import { isLang, pick } from "../../lib/i18n";

const result = Astro.locals.siteResult;
const lang = Astro.params.lang;
const ok = result.kind === "ok" && isLang(lang);
const site = result.kind === "ok" ? result.site : null;
---
{!ok || !site || !isLang(lang) ? (
	<StatusPage kind={result.kind === "suspended" ? "suspended" : "notfound"} />
) : (
	<Layout site={site} lang={lang} title={pick(site.branding.name, lang)} description={pick(site.branding.tagline, lang) || pick(site.landing.hero_subtitle, lang) || pick(site.branding.name, lang)} path="/">
		<Header site={site} lang={lang} path="/" />
		<main>
			<Hero site={site} lang={lang} />
			<About site={site} lang={lang} />
			{site.landing.sections.testimonials && site.testimonials.length > 0 && <Testimonials site={site} lang={lang} />}
			{site.landing.sections.contact && <ContactForm lang={lang} />}
		</main>
		<Footer site={site} lang={lang} />
	</Layout>
)}
```

`src/pages/[lang]/p/[slug].astro`: same guard, then `const page = await getPage(Astro.locals.host, Astro.params.slug ?? "")`; if `null` set `Astro.response.status = 404` and render the layout with Header/Footer and `<h1>{ui(lang).pageNotFound}</h1>`; else Layout (`title = pick(page.title, lang)`, `description = pick(page.seo_description, lang) || pick(site.branding.name, lang)`, `path = \`/p/${page.slug}\``) with `<PageBody html={pick(page.body_html, lang)} title={pick(page.title, lang)} />` (`<article class="prose mx-auto max-w-3xl p-6"><h1>{title}</h1><Fragment set:html={html} /></article>` — the HTML is sanitised server-side at write time).

`src/components/Header.astro` props `{ site, lang, path }`: logo `<img alt="">` + name; menu `site.pages.filter(p => p.show_in_menu)` linking `/${lang}/p/${p.slug}`; switch link `/${lang === "ar" ? "en" : "ar"}${path}` with `hreflang` and `lang` attributes; sign-in `<a href="/app/login">`.

`src/components/ContactForm.astro` props `{ lang }`:

```astro
---
import { ui } from "../lib/i18n";
interface Props { lang: "ar" | "en"; }
const { lang } = Astro.props;
const t = ui(lang);
---
<section id="contact" class="mx-auto max-w-2xl p-6">
	<h2 class="text-2xl font-semibold">{t.contactTitle}</h2>
	<form id="inquiry-form" class="mt-4 grid gap-4" data-lang={lang} data-sent={t.sent} data-failed={t.failed}>
		<label class="grid gap-1">{t.name}<input name="name" required maxlength="120" class="rounded-md border border-border p-2" /></label>
		<label class="grid gap-1">{t.email}<input name="email" type="email" maxlength="254" class="rounded-md border border-border p-2" /></label>
		<label class="grid gap-1">{t.phone}<input name="phone" type="tel" maxlength="32" class="rounded-md border border-border p-2" /></label>
		<label class="flex items-center gap-2"><input name="has_whatsapp" type="checkbox" />{t.whatsapp}</label>
		<label class="grid gap-1">{t.message}<textarea name="message" maxlength="2000" rows="4" class="rounded-md border border-border p-2"></textarea></label>
		<div aria-hidden="true" style="position:absolute;left:-9999px"><input name="website" tabindex="-1" autocomplete="off" /></div>
		<input type="hidden" name="kind" value="contact" />
		<button type="submit" class="rounded-md bg-primary px-4 py-2 text-primary-foreground">{t.send}</button>
		<p data-result role="status" class="text-sm"></p>
	</form>
</section>
<script>
	const form = document.getElementById("inquiry-form") as HTMLFormElement | null;
	document.querySelectorAll<HTMLAnchorElement>('a[href="#contact"][data-kind="trial"]').forEach((a) =>
		a.addEventListener("click", () => { const k = form?.querySelector<HTMLInputElement>('input[name="kind"]'); if (k) k.value = "trial"; }),
	);
	form?.addEventListener("submit", async (event) => {
		event.preventDefault();
		const button = form.querySelector("button");
		const out = form.querySelector<HTMLElement>("[data-result]");
		const data = new FormData(form);
		const body = {
			kind: data.get("kind"), name: data.get("name"), email: data.get("email"), phone: data.get("phone"),
			has_whatsapp: data.get("has_whatsapp") === "on", message: data.get("message"),
			locale: form.dataset.lang, website: data.get("website"),
		};
		if (button) button.disabled = true;
		try {
			const res = await fetch("/api/v1/site/inquiries/", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
			if (!res.ok) throw new Error(String(res.status));
			form.reset();
			if (out) { out.setAttribute("role", "status"); out.textContent = form.dataset.sent ?? ""; }
		} catch {
			if (out) { out.setAttribute("role", "alert"); out.textContent = form.dataset.failed ?? ""; }
		} finally {
			if (button) button.disabled = false;
		}
	});
</script>
```

Hero's CTA is `<a href="#contact" data-kind="trial">{pick(site.landing.cta_label, lang)}</a>` (rendered only when `sections.contact`).

`src/pages/sitemap.xml.ts`:

```ts
import type { APIRoute } from "astro";
import { canonical } from "../lib/seo";

export const GET: APIRoute = async ({ locals }) => {
	const r = locals.siteResult;
	if (r.kind !== "ok") return new Response("Not found", { status: 404 });
	const paths = ["/", ...r.site.pages.map((p) => `/p/${p.slug}`)];
	const urls = paths.flatMap((p) => (["ar", "en"] as const).map((lang) => {
		const alt = (["ar", "en"] as const).map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${canonical(r.site, `/${l}${p}`)}"/>`).join("");
		return `<url><loc>${canonical(r.site, `/${lang}${p}`)}</loc>${alt}</url>`;
	}));
	const xml = `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${urls.join("")}</urlset>`;
	return new Response(xml, { headers: { "Content-Type": "application/xml; charset=utf-8" } });
};
```

`src/pages/robots.txt.ts`:

```ts
import type { APIRoute } from "astro";
import { canonical } from "../lib/seo";

export const GET: APIRoute = async ({ locals }) => {
	const r = locals.siteResult;
	const body = r.kind === "ok"
		? `User-agent: *\nAllow: /\nDisallow: /app/\nDisallow: /api/\nSitemap: ${canonical(r.site, "/sitemap.xml")}\n`
		: "User-agent: *\nDisallow: /\n";
	return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
};
```

Slugs in the sitemap come from the API, which only accepts `^[a-z0-9-]{1,60}$`, so no XML escaping is needed; the canonical host is a validated hostname.

- [ ] **Step 3: Verify and commit** — `check`, `lint`, `test:coverage` (floors hold), `build`; commit `feat: academy landing page, content pages, contact form, sitemap and robots`; push.

---

### Task 14: Caddy edge — local stack and production infra

**Files:**
- Create: meta `caddy/Caddyfile.local`; infra `caddy/Dockerfile`, `caddy/Caddyfile`
- Modify: meta `docker-compose.local.yml` (replace Traefik with Caddy, add `marketing`, dashboard served under `/app/`), `.env.example`, `justfile`, `README.md`, `CLAUDE.md`; infra `docker-compose.production.yml` (replace Traefik with Caddy, add `marketing`), `scripts/ship.sh`, `.env.production.example`; backend `config/settings/local.py` and `production.py` (`ALLOWED_HOSTS = ["*"]`, P3), `backend/tests/test_local_settings.py`, `backend/tests/settings/test_allowed_hosts.py`

**Interfaces:**
- Produces: local academy URLs `http://<sub>.etqan.localhost/` (site), `/app/` (dashboard), `/api/` (API); `http://etqan.localhost/admin/`; any other hostname mapped to 127.0.0.1 in `/etc/hosts` is routed like an academy host (custom-domain testing). Production: Caddy with wildcard certificate for `*.${BASE_DOMAIN}` via Cloudflare DNS-01 and on-demand certificates for custom domains gated by `/internal/tls-allowed`.

- [ ] **Step 1: Backend hosts (P3)** — `config/settings/local.py`: `ALLOWED_HOSTS = ["*"]  # P3: custom domains; django-tenants 404s unknown hosts`; `production.py`: `ALLOWED_HOSTS = ["*"]` replacing the env list (keep the `DJANGO_ALLOWED_HOSTS` env var removed from `.env.production.example`). Update `tests/test_local_settings.py::test_every_academy_subdomain_is_allowed` to assert `s.ALLOWED_HOSTS == ["*"]`; rewrite `tests/settings/test_allowed_hosts.py` to assert production `ALLOWED_HOSTS == ["*"]`. Add a test in `etqan/tenants/tests/test_isolation.py`: with `override_settings(ALLOWED_HOSTS=["*"])`, `GET /api/v1/identity/csrf/` with `HTTP_HOST="evil.example"` → 404. Run backend suite; commit in backend.

- [ ] **Step 2: `caddy/Caddyfile.local` (meta)**

```caddyfile
{
	auto_https off
	admin off
}

(academy) {
	@internal path /internal/*
	respond @internal 404
	@django path /api/* /accounts/* /health/* /media/* /__debug__/*
	reverse_proxy @django django:8000
	@app path /app /app/*
	reverse_proxy @app dashboard:5173
	reverse_proxy marketing:4321
}

http://etqan.localhost {
	@internal path /internal/*
	respond @internal 404
	reverse_proxy django:8000
}

http://flower.etqan.localhost {
	reverse_proxy flower:5555
}

http://mail.etqan.localhost {
	reverse_proxy mailpit:8025
}

http://*.etqan.localhost {
	import academy
}

http:// {
	import academy
}
```

- [ ] **Step 3: `docker-compose.local.yml`** — replace the `traefik` service with:

```yaml
  caddy:
    image: caddy:2-alpine
    ports:
      - "80:80"
    volumes:
      - ./caddy/Caddyfile.local:/etc/caddy/Caddyfile:ro
    depends_on: [django, dashboard, marketing]
```

Delete every `traefik.*` label. Add:

```yaml
  marketing:
    build:
      context: ./marketing
      target: dev
      args: *uidgid
      secrets: [tokens_token]
    environment:
      - SITE_API_ORIGIN=http://django:8000
      - SITE_SCHEME=http
    volumes:
      - ./marketing:/app
      - marketing_node_modules:/app/node_modules
```

and `marketing_node_modules:` under `volumes:`. The dashboard dev server keeps `VITE_PROXY_TARGET=http://django:8000`. Validate: `docker compose -f docker-compose.local.yml config -q`.

- [ ] **Step 4: Production infra (infra repo, branch `feat/academy-sites`)**

`caddy/Dockerfile`:

```dockerfile
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
```

`caddy/Caddyfile`:

```caddyfile
{
	email {$ACME_EMAIL}
	on_demand_tls {
		ask http://127.0.0.1:8099/internal/tls-allowed
	}
}

(django_upstream) {
	reverse_proxy django-blue:8000 django-green:8000 {
		lb_policy first
		health_uri /health/ready/
		health_interval 5s
		health_headers {
			Host {$BASE_DOMAIN}
		}
	}
}

(academy) {
	@internal path /internal/*
	respond @internal 404
	@django path /api/* /accounts/* /health/* /media/*
	handle @django {
		import django_upstream
	}
	@app path /app /app/*
	handle @app {
		reverse_proxy dashboard:80
	}
	handle {
		reverse_proxy marketing:4321
	}
}

http://127.0.0.1:8099 {
	bind 127.0.0.1
	import django_upstream
}

{$BASE_DOMAIN} {
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}
	@internal path /internal/*
	respond @internal 404
	import django_upstream
}

*.{$BASE_DOMAIN} {
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}
	import academy
}

https:// {
	tls {
		on_demand
	}
	import academy
}
```

(The internal listener forwards `Host` as `127.0.0.1:8099`; Django resolves that through `PUBLIC_EXTRA_DOMAINS` — ensure production `DJANGO_PUBLIC_EXTRA_DOMAINS` includes `127.0.0.1`, which is already the default. `health_headers Host` makes the readiness probe hit the public URLconf.)

`docker-compose.production.yml`: replace the `traefik` service with

```yaml
  caddy:
    build: ./caddy
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    environment:
      - BASE_DOMAIN=${BASE_DOMAIN:?}
      - ACME_EMAIL=${ACME_EMAIL:?}
      - CF_API_TOKEN=${CF_API_TOKEN:?}
    volumes:
      - caddy_data:/data
      - caddy_config:/config
```

remove all `traefik.*` labels and `traefik_certs`, add `caddy_data`/`caddy_config` volumes, add

```yaml
  marketing:
    image: ghcr.io/etqan-agency/marketing:${DEPLOY_SHA:?}
    restart: unless-stopped
    environment:
      - SITE_API_ORIGIN=http://django-blue:8000
      - SITE_SCHEME=https
```

(Marketing talks to `django-blue` directly; because blue/green alternate, set `SITE_API_ORIGIN` to an internal Caddy listener instead: add `http://:8098 { bind 0.0.0.0; import django_upstream }` to the Caddyfile on an internal-only port not published on the host, and use `SITE_API_ORIGIN=http://caddy:8098`. Do that — it keeps marketing working during colour switches.)

`scripts/ship.sh`: replace `traefik` in the shared-services `up -d` list with `caddy`, add `marketing` to the final `up -d dashboard` line, and drop any Traefik-specific comments. `.env.production.example`: remove `API_DOMAIN`, `DASHBOARD_DOMAIN`, `FLOWER_DOMAIN`, `TRAEFIK_FLOWER_AUTH`, `DJANGO_ALLOWED_HOSTS`; add `BASE_DOMAIN=`, `CF_API_TOKEN=`, `DJANGO_EDGE_HOSTNAME=sites.${BASE_DOMAIN}`, `DJANGO_EDGE_PUBLIC_IP=`, `DJANGO_S3_BUCKET=` (+ endpoint/region/custom-domain), and set `DJANGO_TENANT_BASE_DOMAIN=${BASE_DOMAIN}`. Validate: `docker compose -f docker-compose.production.yml config -q` with dummy env values; `bash -n scripts/ship.sh`; `docker run --rm -v "$PWD/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile` will fail only on the unknown `dns cloudflare` module — validate the built image instead: `docker build -t etqan-caddy caddy && docker run --rm -e BASE_DOMAIN=x.test -e ACME_EMAIL=a@x.test -e CF_API_TOKEN=t etqan-caddy caddy validate --config /etc/caddy/Caddyfile`. Commit + push infra.

- [ ] **Step 5: Smoke test locally** — `just setup && just dev-backend`, then (use the port overrides if 5432/8025 are taken):

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://demo.etqan.localhost/            # 302 → /ar/ or /en/
curl -s http://demo.etqan.localhost/en/ | grep -o "Demo Academy" | head -1       # Demo Academy
curl -s -o /dev/null -w "%{http_code}\n" http://demo.etqan.localhost/app/login  # 200
curl -s -o /dev/null -w "%{http_code}\n" http://demo.etqan.localhost/api/v1/site/branding/  # 200
curl -s -o /dev/null -w "%{http_code}\n" http://nope.etqan.localhost/            # 404 (Site not found)
curl -s -o /dev/null -w "%{http_code}\n" http://demo.etqan.localhost/internal/tls-allowed  # 404
curl -s -o /dev/null -w "%{http_code}\n" http://etqan.localhost/admin/login/    # 200
```

Report the codes; `docker compose … down`.

- [ ] **Step 6: Commit meta** — justfile: `dev` output URLs, remove Traefik dashboard mention; README quick start: `http://demo.etqan.localhost/` (site) and `/app/` (dashboard); CLAUDE.md tenancy section: routing table from Global Constraints and "Caddy is the edge". Commit `chore: Caddy edge with per-academy path routing and the marketing service`.

---

### Task 15: Seeds, end-to-end tests, CI

**Files:**
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (branding per academy), `backend/etqan/tenants/tests/test_seed_dev.py`
- Create: `dashboard/e2e/academy-sites.spec.ts`
- Modify: `dashboard/e2e/fixtures.ts`, meta `.github/workflows/ci.yml` (marketing job; e2e through Caddy), meta `STATE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: `seed_dev` sets `demo` branding (`Demo Academy` / `أكاديمية ديمو`, `#0E7C66`), one testimonial (`"Sara"`, `"Wonderful teachers"` / `"معلمون رائعون"`), one published page `policies`; `other` branding (`Other Academy` / `أكاديمية أخرى`, `#7A2E8E`), a different testimonial (`"Yusuf"`, `"Very organised"` / `"منظمون جداً"`). CI jobs: `backend`, `dashboard`, `marketing` (install, check, lint, test:coverage, build), `e2e` (Django runserver :8000, dashboard `vite preview` :4173 with base `/app/`, marketing `node dist/server/entry.mjs` :4321, Caddy in Docker on host network with a CI Caddyfile routing `/app*` → 4173, Django paths → 8000, rest → 4321), `security`.

- [ ] **Step 1: Seed** — extend `seed_dev.py`: after creating each academy (or for existing ones), inside `tenant_context(academy)` call `ensure_site_defaults(name)` then update `Branding` / create the testimonial / create the page with the values above, idempotently (`update_or_create` by `author_name` / `slug`). Extend `test_seed_dev.py` to assert both brandings and that `demo` has page `policies` and `other` has no pages. Run backend suite, commit.

- [ ] **Step 2: E2E spec** — `dashboard/e2e/academy-sites.spec.ts`:

```ts
import { expect, test } from "@playwright/test";
import { DEMO_ADMIN, DEMO_URL, login, OTHER_ADMIN, OTHER_URL } from "./fixtures";

test.describe("academy sites", () => {
	test("each academy's home page carries its own name", async ({ page }) => {
		await page.goto(`${DEMO_URL}/en/`);
		await expect(page.getByRole("banner")).toContainText("Demo Academy");
		await expect(page.getByText("Wonderful teachers")).toBeVisible();
		await page.goto(`${OTHER_URL}/en/`);
		await expect(page.getByRole("banner")).toContainText("Other Academy");
		await expect(page.getByText("Wonderful teachers")).toHaveCount(0);
	});

	test("the Arabic site is right-to-left", async ({ page }) => {
		await page.goto(`${DEMO_URL}/ar/`);
		await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
		await expect(page.getByRole("banner")).toContainText("أكاديمية ديمو");
	});

	test("the dashboard login is branded per academy", async ({ page }) => {
		await page.goto(`${OTHER_URL}/app/login`);
		await expect(page.getByText("Other Academy").first()).toBeVisible();
		await expect(page).toHaveTitle(/Other Academy/);
	});

	test("a contact message reaches only that academy's admin", async ({ page, browser }) => {
		const unique = `E2E Visitor ${Date.now()}`;
		await page.goto(`${DEMO_URL}/en/`);
		await page.getByLabel("Name").fill(unique);
		await page.getByLabel("Email").fill("visitor@e2e.test");
		await page.getByRole("button", { name: "Send" }).click();
		await expect(page.getByRole("status")).toContainText("received your message");

		await login(page, DEMO_URL, DEMO_ADMIN);
		await page.goto(`${DEMO_URL}/app/website/inquiries`);
		await expect(page.getByText(unique)).toBeVisible();

		const other = await (await browser.newContext()).newPage();
		await login(other, OTHER_URL, OTHER_ADMIN);
		await other.goto(`${OTHER_URL}/app/website/inquiries`);
		await expect(other.getByText(unique)).toHaveCount(0);
	});

	test("an unknown academy host shows Site not found", async ({ page }) => {
		const res = await page.goto("http://nope.etqan.localhost/");
		expect(res?.status()).toBe(404);
		await expect(page.getByRole("heading", { name: "Site not found" })).toBeVisible();
	});
});
```

(If the login helper lands on the home page before navigating, keep it; the Inquiries route must be reachable by URL.)

- [ ] **Step 3: CI** — in `.github/workflows/ci.yml`:
  - Add a `marketing` job mirroring `dashboard` (working-directory `marketing`, same tokens fetch + insteadOf lines, `pnpm install --frozen-lockfile`, `pnpm check`, `pnpm lint`, `pnpm test:coverage`, `pnpm build`).
  - The token-pin step already runs from the root and now checks both consumers.
  - In `e2e`: after starting Django, build and start the dashboard (`pnpm build && nohup pnpm preview --port 4173 --host 127.0.0.1 &`), build and start marketing (`cd ../marketing && pnpm install --frozen-lockfile && pnpm build && SITE_API_ORIGIN=http://127.0.0.1:8000 SITE_SCHEME=http HOST=127.0.0.1 PORT=4321 nohup node dist/server/entry.mjs &`), write `/tmp/Caddyfile`:

```caddyfile
{
	auto_https off
	admin off
}
(academy) {
	@django path /api/* /accounts/* /health/* /media/*
	reverse_proxy @django 127.0.0.1:8000
	@app path /app /app/*
	reverse_proxy @app 127.0.0.1:4173
	reverse_proxy 127.0.0.1:4321
}
http://etqan.localhost {
	reverse_proxy 127.0.0.1:8000
}
http://*.etqan.localhost {
	import academy
}
```

    then `docker run -d --network host -v /tmp/Caddyfile:/etc/caddy/Caddyfile:ro caddy:2-alpine`, and wait until `curl -sf http://demo.etqan.localhost/api/v1/site/branding/` succeeds (fail the step on timeout). Set `DJANGO_TENANT_URL_TEMPLATE: http://{domain}` and `E2E_DEMO_URL=http://demo.etqan.localhost`, `E2E_OTHER_URL=http://other.etqan.localhost` for Playwright. `vite preview` needs `--base` unchanged (base comes from the config).
  - Validate YAML; commit.

- [ ] **Step 4: Run everything locally once** — backend suite, dashboard `test:coverage`, marketing `test:coverage`, and the e2e flow with the local stack (or the CI recipe locally). Report results.

- [ ] **Step 5: PRs** — push `feat/academy-sites` in backend, dashboard, infra, marketing and meta; open one PR per repo (meta PR body links the others and the spec); watch meta CI until all jobs pass; then STOP and ask the user before merging (merge order: tokens unchanged; marketing, backend, dashboard, infra; bump meta pointers; merge meta). Update `STATE.md` "Where we are" to "Plan 2 (academy sites) in review".
