# First production release — runbook

For: the owner (Etqan agency) and whoever runs the deploy. Work top to bottom. Every command is
meant to be copied as is; replace only the `<angle-bracket>` parts.

Written 2026-10-13 against meta `master` cd1c743 (backend 0556ef9, dashboard dae0148,
infra b16332f, marketing 26d1bd8). Where something could not be confirmed from the code it says
**not confirmed — check**.

Words used here:

- **base domain**: Etqan's apex, e.g. `<base>`. `https://<base>/admin/` is the Etqan staff
  (platform) admin. Academies live at `https://<sub>.<base>/`.
- **platform admin**: Django admin on the base domain (`config/urls_public.py`), Etqan staff only.
- **env file**: `/opt/etqan/.env.production` on the server.
- **live colour**: `blue` or `green`, whichever `/opt/etqan/.active-color` names.

---

## 1. Readiness summary

### 1.1 What is built

- Phases B0–B11 are merged (STATE.md "Next"): scheduling, money (invoices, online payments,
  balances, vouchers), payroll, communication (notices, broadcasts, WhatsApp, chat), learning,
  add-on sales (recorded courses, consultations), marketing site extras, platform extras (sign-in,
  2FA, registration, languages, contracts), AI drafts and reports, installable web app and web push.
- Integrations slices 1–3 are merged: Etqan's default accounts per service, metering and monthly
  Etqan invoices to academies, Zoom meetings (Etqan pool or the academy's own), Jitsi fallback,
  Stripe Connect Express.
- Deploy tooling: `infra/scripts/ship.sh` (blue-green), `smoke.sh`, `manage.sh`, `edge-ca.sh`;
  CI builds images to GHCR on every green `master` and deploys to staging once staging secrets
  exist (`.github/workflows/ci.yml`, `deploy-staging.yml`).

### 1.2 What is verified

- CI on `master` runs backend, dashboard, marketing, Caddy validation (both TLS modes), infra
  script tests, e2e (Playwright through a Caddy edge), gitleaks, image builds, the staging
  simulation (deploy twice, seed, smoke, failing deploy, full journey) and the staging deploy.
- Last fully completed `master` run: ce91955 — success. The run for cd1c743 was still in
  progress when this was written (backend, frontends, e2e, security, infra, caddy and images passed;
  staging-sim running).
  **Check it is green before choosing the release SHA (step 4.1).**
- **Not verified anywhere yet**: a real server, real DNS, Cloudflare DNS-01 certificates, the GHCR
  login with a read token, real S3, real SES, real Zoom/Stripe/Meta/Claude/Twilio accounts
  (infra/STAGING.md §8). Staging has never run on a real server (STATE.md "Standing warnings").

### 1.3 Known gaps and risks

| # | Gap / risk | Effect | Where |
|---|---|---|---|
| R1 | No staging server exists yet | Nothing has run on real infrastructure | STATE.md standing warnings |
| R2 | No production deploy workflow | Production is deployed by hand (this runbook, §4) | STATE.md follow-ups |
| R3 | No backups, no restore drill, no alerts built | Data loss on disk failure; outages unnoticed | STATE.md follow-ups |
| R4 | `infra/.env.production.example` is incomplete | Lacks `ETQAN_SECRETS_KEY`, `ETQAN_BILLING_*`, `WEB_PUSH_*`, `SMS_BACKEND`, `TWILIO_*`, `DJANGO_S3_PRIVATE_BUCKET`, `JITSI_BASE_URL`, `TLS_MODE`. Use §3.2 here, not the example alone | infra `.env.production.example` |
| R5 | Twilio needs `SMS_BACKEND=twilio` as well as the three `TWILIO_*` keys | STATE.md lists only the keys; without `SMS_BACKEND=twilio` the phone option never shows in production (`console` backend is offered only with DEBUG) | `backend/etqan/platform/sms.py` |
| R6 | `monitoring/docker-compose.monitoring.yml` is not production-safe | Publishes 9090/3000/3100/3001 on all interfaces, Grafana password defaults to `admin`, scrapes `django:8000/metrics` which does not exist | infra `monitoring/` |
| R7 | gunicorn access log records allauth confirm/reset keys (in URL paths) | Docker logs hold single-use account-takeover links; protect and rotate them | `docker-compose.production.yml` comment (C3b) |
| R8 | Docker logs have no rotation set in compose | Disk can fill (ship.sh refuses to deploy under 5 GB free) | infra compose (no `logging:`) |
| R9 | Redis has no volume | Queued Celery tasks (emails) are lost if Redis restarts | infra compose |
| R10 | During a blue-green switch both colours' `celery-beat` run for ~15–60 s | A periodic task can be sent twice in that window. `etqan_billing.build_month` is protected by a unique (academy, period) constraint; idempotency of the others is **not confirmed — check**. Do not deploy around the 1st 03:00 UTC | `ship.sh` steps 6–8 |
| R11 | `CONNECT_COUNTRIES` (43 countries) not checked against Stripe's current Express list | Academies in an unsupported country get an error, or Stripe refuses | `backend/etqan/integrations/services/onboarding.py` |
| R12 | Jitsi fallback uses `https://meet.jit.si` | Its rooms ask the first person to sign in | `JITSI_BASE_URL` |
| R13 | WhatsApp: no delivery receipts, no replies, template approval assumed | "Sent" means Meta accepted it | B5c spec X-4, X-12 |
| R14 | Native mobile apps are on hold (owner E4) | Only the installable web app (PWA) and web push ship | STATE.md "Next" |
| R15 | Contracts share the public bucket unless `DJANGO_S3_PRIVATE_BUCKET` is set | Contract files sit under an unlisted prefix of a public-read bucket (system check `etqan.W901`) | `config/settings/production.py` |
| R16 | Backend image runs as root | Smaller blast-radius hardening is missing | `backend/Dockerfile` production stage |
| R17 | Flaky e2e under memory load (b2-archive, b2-bundles, b2-trials, b9-languages, b9-registration, journey) | CI green; local runs may time out | STATE.md follow-ups |
| R18 | Long tail of functional limitations | Listed in STATE.md "Follow-ups" (pickers cap at 100, staff get no notifications, timezone change keeps old sessions, …). None blocks a release; read them once | STATE.md |

The one-release email shim (`etqan/platform/tasks.py::send_email_message`) and the "new web → old
worker" mail-loss window only matter when an older release is running. On this first release
there is none, so they cannot bite here.

### 1.4 Go / no-go checklist

Go only when every box is ticked.

- [ ] Release SHA chosen: a `master` commit whose CI run is green **including the `images` job**.
- [ ] Staging is live on a real server and has run that SHA (§4.2) with a passing smoke check.
- [ ] Production server built (§3.1); DNS records resolve; ports 80/443 reachable.
- [ ] Env file complete (§3.2); `ETQAN_SECRETS_KEY` generated and stored in a password manager
      **outside** the server.
- [ ] Nightly Postgres backup running, copied off the server, and **one restore tested** (§3.4).
- [ ] Sentry DSN set and an external uptime check on `https://<base>/health/ready/` (§2.10).
- [ ] SES: domain verified (SPF, DKIM, DMARC), account out of the sandbox; a test email arrived.
- [ ] `ETQAN_BILLING_CURRENCY` and `ETQAN_BILLING_PAYMENT_INSTRUCTIONS` set (real bank details)
      **before** any `Price` row is created (§2.3).
- [ ] `Price` rows created for every unit you will bill, or a decision written down to void the
      first drafts.
- [ ] Etqan staff superuser created; 2FA on for it (if the admin offers it — **not confirmed — check**).
- [ ] Every outside service you switch on in week one has passed its Test in the platform admin.

Blockers today: R1 (no staging), R3 (no backups/alerts), and the account set-ups in §2.

---

## 2. Accounts and keys to create first (owner actions)

Do these before the deploy day. Start every payment provider in **test mode**.

### Where each value goes

| Item | Entered in | Exact place |
|---|---|---|
| Server-wide keys (DB, Django, S3, SES, Twilio, VAPID, secrets key, billing text) | env file | `/opt/etqan/.env.production` (§3.2) |
| Etqan's default Zoom, Stripe Connect, WhatsApp, Claude, email | platform admin | `https://<base>/admin/` → Integrations → Platform accounts → the service row |
| Prices, per-academy terms, Connect fees | platform admin | Etqan billing → Prices / Academy pricing / Connect fees |
| Feature switches per academy | platform admin | Tenants → Academies → the academy → features (or `manage.sh set_features`) |
| An academy's own Google sign-in client | academy dashboard | the academy admin's sign-in settings (`/api/v1/identity/google/settings/`) |
| An academy's own Zoom / WhatsApp / Claude / SMTP | academy dashboard | Settings → Integrations |
| An academy's own Stripe / PayPal keys | academy dashboard | Payment gateways |

Platform account form (`backend/etqan/integrations/admin.py`): **config** is a JSON object of
non-secret settings; **secret** is a write-only JSON object of text values ("blank keeps what is
stored"). Press **Test**, then tick **enabled**. A default is used only when it is enabled, the
academy's matching switch is on, and the academy is not suspended (`integrations/services/resolver.py`).

### 2.1 Zoom (Etqan's default video) — STATE.md slice 3 deploy note, slice 3 plan "Owner actions"

1. In Etqan's Zoom account, create licensed host users: one per class that may run at the same
   time (one meeting per host at a time; the pool may list 1–50 hosts).
2. Create a **Server-to-Server OAuth** app. Scopes: create meetings for users
   (`meeting:write:meeting:admin`, classic `meeting:write:admin`), **read meetings**
   (`meeting:read:meeting:admin`, classic `meeting:read:admin` — needed for teachers' host links),
   read users.
3. Event subscription: **End Meeting** (`meeting.ended`) to
   `https://<base>/api/v1/webhooks/zoom/`. Copy the app's **Secret Token**.
4. Platform admin → Platform accounts → `video`:
   - config: `{"account_id": "<id>", "client_id": "<id>", "host_users": ["host1@<domain>", "host2@<domain>"]}`
   - secret: `{"client_secret": "<secret>", "webhook_secret": "<Secret Token>"}`
   - Test → enable. Then let Zoom validate the webhook URL.
5. `Price` for `video` / `minute` (§2.3).
6. Per academy: switch `zoom_api` on (§5.5).

Without Zoom, academies that switch `zoom_api` on get Jitsi rooms (`JITSI_BASE_URL`).

### 2.2 Stripe Connect (Etqan's default online payments)

1. On Etqan's Stripe account enable **Connect → Express**; fill the platform profile and branding.
2. Create **two** webhook endpoints, both `https://<base>/api/v1/webhooks/stripe-connect/`:
   - "Connected accounts": `account.updated`, `checkout.session.completed`,
     `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`,
     `checkout.session.expired`;
   - "Your account": `application_fee.created`.
3. Platform admin → Platform accounts → `payments`:
   - config: leave `{}` (mode is read from the key);
   - secret: `{"secret_key": "sk_test_…", "connect_webhook_secret": "whsec_…", "platform_webhook_secret": "whsec_…"}`
   - Test → enable.
4. Per academy: a `ConnectFee` row (no row = no fee), and `online_payments` (needs `invoices`) on.
5. Run one onboarding and one payment end to end **in test mode**. Only then replace with
   `sk_live_…` and the live `whsec_` secrets (a live key ignores test-mode connected accounts).
6. Check `CONNECT_COUNTRIES` (R11) against Stripe's current Express list and Etqan's own Stripe
   country (cross-border Express is region-limited). Changing it is a code change.

An academy's own Stripe/PayPal keys (B3) win over Connect. Their webhook is the academy's own:
`https://<sub>.<base>/api/v1/gateways/webhooks/stripe/` (and `.../webhooks/paypal/`).

### 2.3 Etqan billing: bank details, currency, prices

1. Decide the billing currency (ISO code). Put it in `ETQAN_BILLING_CURRENCY` **before creating
   any `Price`**: a price's currency is copied from that setting when the row is created and cannot
   be edited (`etqan_billing/models.py`).
2. Write `ETQAN_BILLING_PAYMENT_INSTRUCTIONS` (real bank name, account, IBAN/SWIFT, reference
   rule). It is printed on every invoice PDF and email. The default is a placeholder.
3. After the first deploy, platform admin → Etqan billing → Prices. Amounts are **integer minor
   units per batch**:

   | service | unit | priced per |
   |---|---|---|
   | email | email | 1,000 emails |
   | whatsapp | conversation | 1 |
   | video | minute | 1 |
   | ai | input_token | 1,000,000 |
   | ai | output_token | 1,000,000 |

   Use with no price is listed at 0. Per-academy overrides and free allowances: Academy pricing.
4. Email through Etqan's default is metered for every academy from day one, so nearly every
   academy gets a draft invoice on the 1st.

### 2.4 Meta WhatsApp Cloud API (Etqan's default WhatsApp)

1. A Meta Business account with a WhatsApp Business Account (WABA) and a registered phone number.
2. A **System User** with a non-expiring access token for that WABA.
3. One **utility** template, approved in `ar` and `en`, with exactly three body parameters
   `{{1}} {{2}} {{3}}` (academy name, notice title, notice body). Suggested name `etqan_notice`
   and text in `docs/superpowers/specs/2026-10-08-b5c-whatsapp-design.md` X-4.
4. Platform admin → Platform accounts → `whatsapp`:
   - config: `{"phone_number_id": "<digits>", "waba_id": "<digits>", "template": "etqan_notice", "languages": {"ar": "ar", "en": "en"}}`
     (use the exact approved codes, e.g. `en_US`, if Meta shows those);
   - secret: `{"access_token": "<token>"}`
   - Test (reads the number and template, sends nothing) → enable.
5. No webhook is needed (no receipts or replies are built).
6. Price `whatsapp` / `conversation`. Per academy: `whatsapp` on.

### 2.5 Claude API (Etqan's default AI)

1. Anthropic Console: an organisation with billing and credit; create an API key (`sk-ant-…`).
2. Platform admin → Platform accounts → `ai`:
   - config: `{"model": "claude-sonnet-5"}` (allowed: `claude-sonnet-5`, `claude-sonnet-5-5`,
     `claude-opus-5-5`, `claude-haiku-5-5`);
   - secret: `{"api_key": "sk-ant-…"}`
   - Test (spends no tokens; cannot see an empty credit balance) → enable.
3. Prices `ai` / `input_token` and `output_token`. Per academy: `ai_assistant` and/or `ai_reports`.

`ETQAN_AI_FAKE` is pinned off in production; nothing to set.

### 2.6 Twilio (password-reset codes by SMS)

1. Twilio account, a sending number (or sender ID) allowed for your target countries.
2. Env file: `SMS_BACKEND=twilio`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM`.
   **All four** (R5). Until then only email codes are offered.
3. Per academy: `code_reset` on.

### 2.7 Google sign-in (per academy, not Etqan-wide)

Each academy brings its own Google OAuth client (`backend/etqan/identity/google.py`).

1. Google Cloud console: OAuth consent screen (External; publish it, verification if Google asks),
   a "Web application" client.
2. Authorised redirect URI, exactly: `https://<academy primary host>/api/v1/identity/google/callback/`
   (the settings screen shows it).
3. The academy admin enters client ID and secret in the academy's sign-in settings (needs
   `ETQAN_SECRETS_KEY`). Etqan switches `google_sign_in` on.

### 2.8 Web push (VAPID keys)

Generated **after** `ETQAN_SECRETS_KEY` is set, on the server, because the private key is stored
encrypted with it. Steps in §4.4. Needs `WEB_PUSH_VAPID_SUBJECT=mailto:<ops address>`.

### 2.9 Email (Etqan's default: AWS SES SMTP, ADR-0016)

1. SES in one region: verify the sending domain (DKIM records), add SPF and DMARC, request
   production access (leave the sandbox).
2. Create SMTP credentials.
3. Env file: `DJANGO_EMAIL_HOST=email-smtp.<region>.amazonaws.com`, `DJANGO_EMAIL_PORT=587`,
   `DJANGO_EMAIL_USE_TLS=True`, `DJANGO_EMAIL_HOST_USER`, `DJANGO_EMAIL_HOST_PASSWORD`,
   `DJANGO_DEFAULT_FROM_EMAIL="Etqan <noreply@<verified domain>>"`.
4. The platform `email` account is created enabled with empty config by migration
   (`integrations/migrations/0002`), which means "use `DJANGO_EMAIL_*`". Leave it so.

### 2.10 DNS, TLS, S3, monitoring

- **DNS** (the zone must be on Cloudflare: Caddy is built only with the Cloudflare DNS module):
  - `<base>` A → server IPv4, **DNS only (grey cloud)**;
  - `*.<base>` A → server IPv4, DNS only (this also covers `sites.<base>`, the custom-domain target).
  - Never proxy these records (orange cloud): Caddy must be the only proxy hop (`NUM_PROXIES=1`).
- **Cloudflare API token**: Zone → DNS → Edit on that zone only → `CF_API_TOKEN`.
- **Custom domains**: an academy points a CNAME at `sites.<base>`, or an apex A record at
  `DJANGO_EDGE_PUBLIC_IP`. Caddy issues the certificate on first visit, only for an active
  academy domain (`/internal/tls-allowed`).
- **S3**: one public-read bucket for uploads (policy on `tenants/*` only — text in
  `infra/.env.production.example`), and one **private** bucket for contracts
  (`DJANGO_S3_PRIVATE_BUCKET`, no public policy). An IAM key with Put/Get/Delete on both.
- **Sentry**: a Django project → `SENTRY_DSN`. (The dashboard and marketing site send nothing to
  Sentry.)
- **Uptime**: an external monitor (any hosted checker) on `https://<base>/health/ready/` and one
  academy's `/health/ready/`, alerting by email/phone. Do not run `infra/monitoring` as is (R6).
- **Production domain**: the code does not fix it (`etqan.academy` appears only in example
  values). **Not confirmed — owner decides.**

---

## 3. Server and configuration

### 3.1 The server (infra/STAGING.md §1, same for production)

- Linux with Docker Engine + compose plugin, `bash`, `rsync`, `curl`. Disk ≥ 40 GB (more for
  Postgres growth; ship.sh needs 5 GB free on `/var/lib/docker`).
- Firewall: only 22 (SSH, key-only), 80, 443 open. Postgres and Redis publish no ports.
- A `deploy` user:

  ```bash
  sudo adduser --disabled-password deploy && sudo usermod -aG docker deploy
  sudo install -d -o deploy -g deploy /opt/etqan
  ```

- Docker log rotation (R8; recommended, not in the repo) — `/etc/docker/daemon.json`:

  ```json
  { "log-driver": "json-file", "log-opts": { "max-size": "50m", "max-file": "5" } }
  ```

  then `sudo systemctl restart docker` (before the first deploy).
- The files must live in `/opt/etqan`: the compose project name `etqan` gives the container names
  the scripts use (`etqan-django-blue-1`, `etqan-caddy-1`, `etqan-postgres-1`, …).

### 3.2 Env file

Create on the server as `deploy`:

```bash
cd /opt/etqan
cp .env.production.example .env.production   # after infra/ is copied, §4.3 step 2
chmod 600 .env.production
```

Then make it match the table. **Never commit it, never paste it into chat or tickets.**
One `KEY=value` per line, no `export`, no leading spaces. Values with spaces go in double quotes.

| Variable | Req. | Purpose | Example shape |
|---|---|---|---|
| `BASE_DOMAIN` | yes | Etqan apex; academies are `<sub>.<base>` | `etqan.example` |
| `CF_API_TOKEN` | yes | Cloudflare DNS-01 for the wildcard cert | 40-char token |
| `ACME_EMAIL` | yes | Let's Encrypt account email | `ops@<base>` |
| `TLS_MODE` | no | `cloudflare` (default, production) or `internal` (staging only) | `cloudflare` |
| `ETQAN_REGISTRY` | no | image registry | default `ghcr.io/etqan-agency` |
| `ETQAN_OVERLAY` | **must be absent** in production | `staging` adds Mailpit + local S3 | — |
| `DEPLOY_SHA` | no | ship.sh exports its own | `latest` |
| `DJANGO_SECRET_KEY` | yes | Django signing key | `openssl rand -hex 50` |
| `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | yes | Postgres container init | `etqan` / `etqan` / `openssl rand -hex 32` |
| `DATABASE_URL` | yes | Django's DB | `postgres://etqan:<pw>@postgres:5432/etqan` |
| `CELERY_BROKER_URL` | yes | Redis broker (cache uses DB 1 of the same Redis) | `redis://redis:6379/0` |
| `DJANGO_CACHE_URL` | no | override cache Redis | default `redis://redis:6379/1` |
| `DJANGO_TENANT_BASE_DOMAIN` | yes | new academies' parent domain | `${BASE_DOMAIN}` |
| `DJANGO_TENANT_URL_TEMPLATE` | yes | academy URL in emails | `https://{domain}` |
| `DJANGO_FRONTEND_URL` | yes (boot fails without) | platform URL | `https://${BASE_DOMAIN}` |
| `DJANGO_TRUST_INTERNAL_HEADER` | yes | marketing SSR skips public throttles (D65); only behind this Caddyfile | `True` |
| `DJANGO_EDGE_HOSTNAME` | yes | custom-domain CNAME target | `sites.${BASE_DOMAIN}` |
| `DJANGO_EDGE_PUBLIC_IP` | yes for custom apex domains | server IPv4 shown to academies | `203.0.113.10` |
| `CSRF_TRUSTED_ORIGINS` | no | only for a cross-origin client | empty |
| `DJANGO_S3_BUCKET` | yes (boot fails without) | public uploads bucket | `etqan-media` |
| `DJANGO_S3_PRIVATE_BUCKET` | strongly advised (R15) | contracts | `etqan-private` |
| `DJANGO_S3_REGION` | yes for AWS | bucket region | `eu-west-1` |
| `DJANGO_S3_ENDPOINT_URL` | non-AWS only | R2/Spaces endpoint | empty on AWS |
| `DJANGO_S3_CUSTOM_DOMAIN` | no | CDN/public domain for uploads | empty |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | yes | S3 credentials | IAM key |
| `DJANGO_EMAIL_HOST` / `_PORT` / `_USE_TLS` | yes | SES SMTP | `email-smtp.eu-west-1.amazonaws.com` / `587` / `True` |
| `DJANGO_EMAIL_HOST_USER` / `_PASSWORD` | yes | SES SMTP credentials | SES SMTP user/pass |
| `DJANGO_DEFAULT_FROM_EMAIL` | yes | From address (SES-verified) | `"Etqan <noreply@<domain>>"` |
| `ETQAN_SECRETS_KEY` | **yes** | Fernet key(s) for every stored secret (§3.3) | 44-char base64; `new,old` when rotating |
| `ETQAN_BILLING_CURRENCY` | yes | Etqan's invoice currency | `USD` |
| `ETQAN_BILLING_PAYMENT_INSTRUCTIONS` | yes | bank details on every Etqan invoice | `"Pay by bank transfer to … IBAN … quoting the invoice number."` |
| `SENTRY_DSN` | advised | error reporting | `https://…@…ingest.sentry.io/…` |
| `SENTRY_TRACES_SAMPLE_RATE` / `SENTRY_PROFILES_SAMPLE_RATE` | no | default 0.1 | `0.1` |
| `SMS_BACKEND` | for SMS | must be `twilio` in production (R5) | `twilio` |
| `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` / `TWILIO_FROM` | for SMS | Twilio | `AC…` / token / `+1…` |
| `WEB_PUSH_VAPID_PUBLIC_KEY` | for push | from `make_vapid_keys` (§4.4) | base64url |
| `WEB_PUSH_VAPID_PRIVATE_KEY_ENC` | for push | from `make_vapid_keys` (Fernet token) | `gAAAA…` |
| `WEB_PUSH_VAPID_SUBJECT` | for push | contact for push services | `mailto:ops@<domain>` |
| `JITSI_BASE_URL` | no | free meeting rooms | default `https://meet.jit.si` |
| `ETQAN_VERSION` | no | shown on the system status page | the release SHA |
| `DJANGO_API_DOCS_ADMIN_ONLY` | no | default `True` in production | `True` |
| `DJANGO_SECURE_SSL_REDIRECT` | no | default `True` | `True` |
| `DJANGO_PUBLIC_EXTRA_DOMAINS` | no | default `localhost,127.0.0.1` — leave | — |

Must **not** be set in production: `ETQAN_OVERLAY`, `DJANGO_STAGING_DEMO_PASSWORD` (it would let
`seed_staging` create a demo academy with dev data), `GATEWAYS_SIMULATE` (the
`gateways.E001` check refuses it without DEBUG), `ETQAN_AI_FAKE`, `CELERY_TASK_ALWAYS_EAGER`,
`DJANGO_DEBUG`, `DJANGO_READ_DOT_ENV_FILE`, `DJANGO_EMAIL_BACKEND` (default SMTP is right).

### 3.3 The secrets key (`ETQAN_SECRETS_KEY`)

Encrypts every stored secret: academies' gateway keys, all integration account secrets, TOTP
(2FA) seeds, Google client secrets, the VAPID private key (`backend/etqan/platform/secrets.py`).

- Generate (any machine with Python and `cryptography`, or the backend image):

  ```bash
  docker run --rm ghcr.io/etqan-agency/backend:<sha> \
    python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
  ```

- Store it in the owner's password manager **before** using it. A database backup without this
  key cannot recover any stored secret.
- Missing or malformed: the app still boots, `check --deploy` warns `etqan.W902`, and 2FA,
  payment-gateway keys, integration accounts and Google sign-in settings refuse to save (503).
- **Rotation**: put the new key first, keep the old one: `ETQAN_SECRETS_KEY=<new>,<old>`, then
  redeploy (§4.3 step 6). The first key encrypts, all keys decrypt. There is **no re-encrypt
  command**: a value moves to the new key only when it is saved again. Do not drop the old key
  until every stored secret has been re-entered (no tool lists them — **not confirmed — check**
  before ever removing a key).

### 3.4 Backups (not built in the repo — set up before go-live)

Recommended minimum (adjust paths and retention):

```bash
# /etc/cron.d/etqan-backup  (as deploy; nightly 02:15 UTC, keeps 14 days locally)
15 2 * * * deploy mkdir -p /opt/etqan-backups && docker exec etqan-postgres-1 pg_dump -U etqan -d etqan -Fc > /opt/etqan-backups/etqan-$(date -u +\%F).dump && find /opt/etqan-backups -name '*.dump' -mtime +14 -delete
```

- `pg_dump` of the one database captures `public` and every academy schema.
- Copy each dump off the server (S3 bucket with versioning, or another host) the same night.
- Run one by hand before every deploy (migrations are never reversed):
  `docker exec etqan-postgres-1 pg_dump -U etqan -d etqan -Fc > /opt/etqan-backups/pre-<sha>.dump`
- **Restore drill** (do it once before go-live, on a scratch container):

  ```bash
  docker run -d --name restore-test -e POSTGRES_PASSWORD=x postgres:18-alpine
  docker cp /opt/etqan-backups/<file>.dump restore-test:/tmp/r.dump
  docker exec restore-test sh -c 'createdb -U postgres etqan && pg_restore -U postgres -d etqan --no-owner /tmp/r.dump'
  docker exec restore-test psql -U postgres -d etqan -c "select schema_name from information_schema.schemata"
  docker rm -f restore-test
  ```

- Uploads live in S3: turn on bucket versioning. The secrets key lives in the password manager.

### 3.5 Caddy and TLS

Nothing to edit: `infra/caddy/Caddyfile` is baked into the image ship.sh builds. With
`TLS_MODE=cloudflare` it gets one wildcard certificate for `*.<base>` plus `<base>` by DNS-01, and
on-demand certificates for custom domains. `/internal/*` answers 404 on every public host.

---

## 4. Release steps, in order

### 4.1 Choose the release SHA

```bash
gh run list --repo Etqan-agency/etqan_tutor --branch master --limit 5 \
  --json headSha,conclusion,status,createdAt
```

Take the newest `master` SHA with `conclusion: success`. Confirm its images exist (the `images`
job pushed `ghcr.io/etqan-agency/{backend,dashboard,marketing}:<sha>`):

```bash
gh run view --repo Etqan-agency/etqan_tutor <run-id> --json jobs -q '.jobs[] | "\(.name) \(.conclusion)"'
```

Every job, including `images`, `staging-sim` and `deploy-staging`, must say `success`.
Below, `SHA=<that 40-character SHA>`.

### 4.2 Staging first (infra/STAGING.md, sections 1–5)

1. Build the staging server as §3.1. DNS: `staging.<base>` and `*.staging.<base>` A records.
2. GitHub → meta repo → Settings → Environments → `staging` (branch policy: `master` only). Add
   secrets `STAGING_SSH_USER`, `STAGING_SSH_KEY`, `STAGING_KNOWN_HOSTS`, `GHCR_READ_TOKEN`,
   `STAGING_BASE_URL=https://demo.staging.<base>`, then **last** `STAGING_SSH_HOST`.
3. On the server: `cp .env.staging.example .env.production` (after the first copy of infra/, or
   copy the file by hand first), `chmod 600`, replace every `CHANGE_ME_*`, set
   `BASE_DOMAIN=staging.<base>`, keep `ETQAN_OVERLAY=staging`. Add `ETQAN_SECRETS_KEY` (a
   **different** key from production) and `ETQAN_BILLING_*`.
4. Actions → **Deploy staging** → Run workflow: `sha=$SHA`, **seed** ticked. It copies infra,
   logs in to GHCR, runs `ship.sh`, creates the `demo` academy, and runs the smoke check.
5. Smoke by hand from your machine (internal CA):

   ```bash
   ssh deploy@<staging> bash /opt/etqan/scripts/edge-ca.sh > staging-root.crt
   SMOKE_CACERT=staging-root.crt bash infra/scripts/smoke.sh https://demo.staging.<base>
   ```

6. Optional, local: `just staging-sim` repeats CI's simulation of the same deploy.
7. Walk the product on staging (sign in as `admin@demo.test` with `DJANGO_STAGING_DEMO_PASSWORD`;
   mail is in Mailpit: `ssh -L 8025:127.0.0.1:8025 deploy@<staging>` → http://localhost:8025).
   Test Stripe Connect and Zoom here in test mode (§2.1, §2.2) — staging is the place to break things.
8. To exercise real TLS/S3/SES before production, follow STAGING.md §7 (Cloudflare TLS, real S3,
   real email, then remove the overlay).

### 4.3 Production: first deploy

There is no production workflow; run these by hand.

1. **On your machine**, a clean checkout of the release:

   ```bash
   git clone --recurse-submodules git@github.com:Etqan-agency/etqan_tutor.git etqan-release
   cd etqan-release && git checkout "$SHA" && git submodule update --init --recursive
   ```

2. **Copy infra/** to the server (same rsync as `scripts/deploy-staging.sh`; never the env file):

   ```bash
   rsync -rlt --itemize-changes --exclude=.git --exclude=/.env.production --exclude=/.active-color \
     infra/ deploy@<prod>:/opt/etqan/
   ```

3. **On the server**, write `/opt/etqan/.env.production` (§3.2), `chmod 600`. Leave the three
   `WEB_PUSH_VAPID_*` lines out for now.
4. **Registry login** (a classic PAT with `read:packages` only):

   ```bash
   printf '%s' '<GHCR_READ_TOKEN>' | docker login ghcr.io -u <github-user> --password-stdin
   ```

5. **Pre-flight**:

   ```bash
   docker compose -f /opt/etqan/docker-compose.production.yml --env-file /opt/etqan/.env.production config -q && echo env-ok
   df -h /var/lib/docker
   ```

6. **Deploy** (blue-green; on a fresh server it starts `green`):

   ```bash
   bash /opt/etqan/scripts/ship.sh "$SHA"
   ```

   What it does, in order (`infra/scripts/ship.sh`): refuse if < 5 GB free → pull images → start
   `caddy postgres redis flower` → **`manage.py migrate` (django-tenants `migrate_schemas`: public,
   then every academy) with the new image** → `bootstrap_platform` (public tenant + domains for
   `<base>`, `localhost`, `127.0.0.1`) → start the new colour (django, celery-worker,
   celery-beat) → poll `/health/ready/` → record the colour → stop the old colour (30 s drain) →
   recreate dashboard and marketing → prune images older than 24 h.

   Migrate-before-traffic is built in; do not start containers any other way. Celery worker and
   beat are recreated with the colour, so there is no separate restart step.

   On a fresh database beat starts after migrate (needs the `django_celery_beat` tables) — ship.sh
   already guarantees that order.
7. **Checks** (on the server):

   ```bash
   C=$(cat /opt/etqan/.active-color)
   bash /opt/etqan/scripts/manage.sh check --deploy
   ```

   Expect no `etqan.W902` (secrets key) and no `devices.W001`; `etqan.W901` means the private
   bucket is missing (R15). Django's own `security.W…` lines: read them; HSTS without
   includeSubDomains is intended (Caddy adds it on Etqan's zone).
8. **Etqan staff superuser** (interactive; `manage.sh` takes no stdin, so use `docker exec -it`):

   ```bash
   docker exec -it etqan-django-$C-1 python manage.py createsuperuser
   ```

   Sign in at `https://<base>/admin/`.
9. **Platform admin set-up**: Prices (§2.3), platform accounts you are ready for (§2.1–2.5),
   each **Test**ed before **enabled**.
10. **First academy** (admin gets a set-password email, so email must work):

    ```bash
    bash /opt/etqan/scripts/manage.sh create_academy --name "<Academy name>" --subdomain <sub> \
      --admin-email <admin@their-domain> --admin-name "<Full name>" --timezone <Area/City> --currency <ISO>
    ```

    (Or platform admin → Tenants → Academies → Add.) Reserved subdomains are refused.
11. **Smoke** from your machine (public CA, so no `SMOKE_CACERT`):

    ```bash
    bash infra/scripts/smoke.sh https://<sub>.<base>
    ```

    Before step 10 its first check fails (no academy → 404); that is expected.
12. **Do not** run `seed_dev` (refuses without DEBUG) or `seed_staging` (refuses without
    `DJANGO_STAGING_DEMO_PASSWORD`, which production never sets).

### 4.4 Web push keys (second deploy of the same SHA)

```bash
bash /opt/etqan/scripts/manage.sh make_vapid_keys
```

It prints `WEB_PUSH_VAPID_PUBLIC_KEY=…` and `WEB_PUSH_VAPID_PRIVATE_KEY_ENC=…` (encrypted with the
current `ETQAN_SECRETS_KEY`). Add both lines plus `WEB_PUSH_VAPID_SUBJECT=mailto:<ops address>`
to the env file, then `bash /opt/etqan/scripts/ship.sh "$SHA"` again (env changes take effect
only when a colour's containers are recreated, which every ship.sh run does). Keep the output out
of shell history and logs where you can.

The same "edit env, re-run ship.sh with the same SHA" applies to any env change (Twilio, Sentry,
billing text, key rotation).

### 4.5 Switch features on deliberately

Every academy starts with only: `families`, `parents`, `session_reports`, `invoices`,
`auto_notifications`, `teacher_attendance`, `export` (`backend/etqan/platform/features.py`).
Everything else is off. Switch per academy in the platform admin, or:

```bash
bash /opt/etqan/scripts/manage.sh set_features <sub> --on <code> [<code> ...]
```

An open dashboard sees a change on its next reload/sign-in; the server enforces it at once.

Switches that need outside set-up first:

| Switch(es) | Needs first |
|---|---|
| `online_payments` (needs `invoices`), `payment_links`, paying invoices online, balance top-ups | `ETQAN_SECRETS_KEY`; Stripe Connect default (§2.2) or the academy's own Stripe/PayPal keys; `GATEWAYS_SIMULATE` unset |
| `zoom_api` | Zoom default (§2.1) or the academy's own Zoom; else Jitsi rooms |
| `whatsapp` | WhatsApp default (§2.4) or the academy's own |
| `ai_assistant`, `ai_reports` | Claude default (§2.5) or the academy's own key |
| `google_sign_in` | the academy's Google client (§2.7); `ETQAN_SECRETS_KEY` |
| `code_reset` (phone option) | Twilio + `SMS_BACKEND=twilio` (§2.6); email option needs only email |
| `two_factor` | `ETQAN_SECRETS_KEY` |
| `installable_app`, `push_notifications` (needs `installable_app`) | VAPID keys (§4.4) for push |
| `file_uploads`, `contracts` | S3 buckets; private bucket for contracts |
| `self_registration`, `registration_waitlist` | working email |
| Custom domain | `DJANGO_EDGE_PUBLIC_IP`, academy's DNS record (§2.10) |
| `supervision`, `levels`, scheduling/payroll/learning/content switches | nothing outside; product decision per academy |

Turn on one group at a time and watch Sentry and the worker logs for a day.

---

## 5. First-week checks

Run on the server; `C=$(cat /opt/etqan/.active-color)`.

1. **Tasks registered** in the worker:

   ```bash
   docker exec etqan-celery-worker-$C-1 celery -A config.celery_app inspect registered
   ```

   Expect at least: `integrations.send_email`, `scheduling.run_daily`,
   `scheduling.provision_meetings`, `notifications.scan`, `gateways.expire_checkouts`,
   `registration.expire_unconfirmed`, `consultations.cancel_unpaid`, `etqan_billing.build_month`,
   `etqan_billing.issue_due`, `etqan_billing.send_invoice`, `devices.push`, `devices.push_academy`,
   `notifications.deliver_email`, `notifications.deliver_whatsapp`, plus the AI draft, reset-code
   and system-status tasks (names of those three: **not confirmed — check the output once and keep
   it as the reference**). An `unregistered task` line in the worker log is a deploy fault.
2. **Beat entries** (DatabaseScheduler; loaded from `CELERY_BEAT_SCHEDULE` in `config/settings/base.py`):

   ```bash
   bash /opt/etqan/scripts/manage.sh shell -c "from django_celery_beat.models import PeriodicTask as P; [print(p.name, p.enabled, p.last_run_at) for p in P.objects.order_by('name')]"
   ```

   | Entry | When (UTC) |
   |---|---|
   | `scheduling.run_daily` | hourly at :05 |
   | `notifications.scan` | every minute (expires 55 s) |
   | `devices.push` | every minute (expires 55 s) |
   | `scheduling.provision_meetings` | every 5 min (expires 290 s) — fills blank meeting links for the next day |
   | `consultations.cancel_unpaid` | every 15 min |
   | `etqan_billing.issue_due` | hourly at :10 — issues drafts older than 24 h and emails them |
   | `etqan_billing.build_month` | 1st of the month 03:00 — drafts last month's Etqan invoices |
   | `registration.expire_unconfirmed` | daily 03:15 |
   | `gateways.expire_checkouts` | daily 03:20 |

   `last_run_at` should move. Logs: `docker logs --since 1h etqan-celery-beat-$C-1` and
   `docker logs --since 1h etqan-celery-worker-$C-1 | grep -i -E "error|unregistered"`.
3. **Email**: trigger a password reset for a test user; it arrives with SPF/DKIM pass. In the
   platform admin → Etqan billing → Usage events, an `email`/`email` row appears for that academy
   (metering of Etqan's default).
4. **Webhooks reachable**: Zoom marketplace "Validate" on the End Meeting URL succeeds; Stripe
   dashboard → each endpoint → "Send test event" returns 2xx (a test event for an unknown account
   may be ignored but must not be 5xx or a timeout). After a real Zoom class on Etqan's account,
   a `video`/`minute` usage event appears.
5. **Meetings**: an academy with `zoom_api` on gets links on tomorrow's sessions within 5 minutes
   of the session entering the window; a teacher can open the host link.
6. **Sentry** receives a test message:
   `bash /opt/etqan/scripts/manage.sh shell -c "import sentry_sdk; sentry_sdk.capture_message('etqan prod test'); sentry_sdk.flush()"`.
7. **Disk and logs**: `df -h /var/lib/docker`, `docker system df` daily for the first week.
8. **Backups**: the nightly dump exists and was copied off the server.
9. **First Etqan invoice run** (the 1st at 03:00 UTC after go-live):
   - by 04:00 on the 1st, platform admin → Etqan billing → Etqan invoices shows drafts for every
     academy that used a default (email counts);
   - check lines, prices, currency and the payment instructions on the PDF;
   - drafts are editable (or voidable) for **24 hours**; from 03:10 on the 2nd `issue_due`
     issues them and emails the PDF to each academy's admins;
   - from 30 days unpaid Etqan **may** suspend that academy's use of Etqan defaults
     (`Academy.etqan_defaults_suspended`); nothing suspends on its own.

---

## 6. Rollback

- **ship.sh guards itself**: a failed migrate or `bootstrap_platform` stops before the new colour
  starts; a failed health check stops and removes the new colour. The old colour keeps serving.
  Migrations already applied stay applied.
- **Roll back a later release**: run ship.sh with the previous good SHA (images stay in GHCR; the
  server pulls them again):

  ```bash
  bash /opt/etqan/scripts/ship.sh <previous-sha>
  ```

  On staging: Actions → Deploy staging → Run workflow with that SHA, when no other deploy is waiting.
- **Migrations are never reversed.** Every migration must stay compatible with the previous
  release (expand now, contract in a later release; a new NOT NULL column needs `db_default=`).
  On this first release every migration runs on an empty database, so there is no compatibility
  question. Historic destructive migrations exist (`identity` 0006, 0008, 0010, 0012, from before
  this fork) and are harmless on a fresh database.
- **First release has nothing to roll back to.** If it is broken: fix forward with a new `master`
  SHA, or stop public traffic (`docker compose … stop caddy`) while you fix. If data is damaged,
  restore the latest dump (§3.4) into a fresh `postgres_data` volume — rehearse this in the drill.
- **Master CI red**: do not deploy. Find the last green `master` SHA (§4.1) and deploy that, or
  fix forward on a `feat/*` branch and merge. Never deploy a SHA whose `images` job did not
  succeed (its images do not exist).

---

## 7. Next-release cleanup

- Delete `backend/etqan/platform/tasks.py` (`send_email_message`, the one-release email shim;
  nothing calls it).
- Drop `AcademySettings.supervision_enabled` (Plan 13; nothing writes it).
- Complete `infra/.env.production.example` with the variables in R4 and `SMS_BACKEND=twilio`, and
  correct STATE.md's Twilio note (R5).
- Build the production deploy workflow (mirror `deploy-staging.yml` with a `production`
  environment and required reviewers), backups with an off-site copy, and alerts.
- Replace or lock down `infra/monitoring` (R6): bind ports to 127.0.0.1, set a real Grafana
  password, remove the dead `/metrics` scrape.
- Indexes: `SessionActivity(action, created_at)` (B5d) and `Notification(created_at, id)` (R13).
- Consider a Redis volume (R9), a non-root backend image user (R16), and keeping allauth keys out
  of the access log (R7).
- Plan 9 review leftovers listed in STATE.md (ship_test edge cases, `manage.sh -i`, banner registry
  name, rsync `-e` quoting, staging-sim-needed fail-closed, …).
