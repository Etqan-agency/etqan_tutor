---
title: "Integrations"
---

Every outside service an academy uses (email, WhatsApp, online payments, video meetings, AI) runs on one of two
accounts: the academy's own account, or Etqan's default account. `etqan.integrations` holds both kinds of account
and decides which one a service uses (`resolve(service)`). It also owns the code that talks to each provider.
Use of an Etqan default is metered and invoiced to the academy (see [etqan-billing.md](etqan-billing.md)).
Academy admins, and staff who hold `integration.view` / `integration.update`, manage the academy's own accounts
in Settings → Integrations. Etqan staff manage the defaults in the platform admin on the bare base domain.

## Concepts

| Model | Schema | What it is |
|---|---|---|
| `PlatformAccount` | public (SHARED_APPS `etqan.integrations`) | Etqan's default account, one row per service. Migration `0002_default_accounts` seeds all five rows; only email starts `enabled`. |
| `AcademyAccount` | academy (TENANT_APPS `etqan.integrations.accounts`) | The academy's own account, one row per service. |
| `WebhookRoute` | public | Maps an outside id (`zoom_meeting` id or `stripe_account` id) to its academy, so Etqan's single webhook endpoint per provider can enter the right schema. Rows are never deleted. |
| `HostBooking` | public | Which host in Etqan's Zoom pool holds which time slot (see [meetings.md](meetings.md)). |

Both account models share `AccountFields`. The fields are `enabled` and `config`, which holds non-secret JSON.
`secret_enc` holds a Fernet token of a JSON object of secrets, made by `etqan.platform.secrets`. `secret_last4`
holds the last four characters of the main secret, and is blank when that secret is shorter than 12 characters.
The `last_test_*` fields hold the outcome of the last probe. No API ever returns a secret.

Services (`Service` choices): `whatsapp`, `email`, `payments`, `video`, `ai`. SMS is out of scope.

## How it works

### The resolver: `services/resolver.py:resolve`

`resolve(service) -> Resolved | None` gives `Resolved(service, source, config, secret_enc)`. `source` is
`"academy"` or `"etqan"`. Steps:

1. **Academy's own account.** It is used when it exists and is `enabled`. This step is skipped in the public
   schema and for `payments` (`NOT_OWN`). For payments, the academy's own keys are B3's `GatewayAccount`, and
   `etqan.gateways` checks them before anything else.
2. **Etqan's default** (`_etqan_default`) is used when all of these hold:
   - the `PlatformAccount` is enabled;
   - at least one of the service's feature switches is on (`SWITCHES`: whatsapp → `whatsapp`, email → none,
     payments → `online_payments`, video → `zoom_api`, ai → `ai_assistant` or `ai_reports`);
   - the academy's `Academy.etqan_defaults_suspended` is false.
3. Otherwise `None`. The feature then shows "not set up".

`default_status(service)` explains step 2 as one of `available`, `disabled`, `feature_off` or `suspended`.
Answers are cached on the tenant object on the connection, which lasts one request or one task.
`connect`, `disconnect`, onboarding and `clear_cache()` clear that cache.

**Rule:** a caller meters only when `resolved.source == "etqan"`. In practice every caller passes `source` to
`etqan_billing.services.record_usage`, which ignores anything else.

### Providers: `providers/`

Each service has one provider object in `providers.PROVIDERS`, following the `Provider` protocol in
`providers/base.py`:

- `clean(fields, *, stored, own)` validates the fields and returns `(config, secrets)`. A blank secret keeps
  the stored one. `own=False` means Etqan's default.
- `last4(values)` returns the main secret's last four characters.
- `probe(config, secrets, tester_email)` raises `ProbeError` with Etqan's own wording when the account does not
  work.

| Service | Provider | Own account fields | Probe |
|---|---|---|---|
| email | `EmailProvider` | SMTP `host`, `port` (25/465/587/2525 only), `username`, `security`, `from_address`; secret `password`. An own server must be a public host. | Sends a test mail to the signed-in user |
| whatsapp | `WhatsAppProvider` | `phone_number_id`, `waba_id`, `template`, `languages`; secret `access_token` | Two read-only Graph API GETs. Sends nothing. |
| payments | `StripePlatformProvider` | None: an academy cannot type keys (`integrations.use_connect`). Etqan's default holds `secret_key`, `connect_webhook_secret`, `platform_webhook_secret`; `config.mode` is `test` or `live`, taken from the key prefix. | Academy: Check status (`refresh_connect`). Etqan: `GET /account`. |
| video | `ZoomProvider` | Zoom S2S `account_id`, `client_id`, `host_user`; secret `client_secret`. Etqan's default has `host_users` (the pool) and an optional `webhook_secret`. | Requests a fresh Zoom token |
| ai | `AiProvider` | `model` (one of the four Claude models); secret `api_key` (`sk-ant-…`) | `models.retrieve(model)`. Spends no tokens. |

### Academy accounts: `services/accounts.py`

- `connect(service, fields=, by=)` locks the row, cleans the fields, encrypts the secrets and saves. A changed
  config or secret clears the last test result. It retries once if two first connects race.
- `disconnect(service)` deletes the row. It is idempotent.
- `probe(service, scope="academy"|"etqan", tester_email=)` records the verdict on the row. A failed probe is an
  answer, not an error.
- `apply_platform_change(...)` holds the platform admin form's rules. A provider that is not `connectable`
  cannot be enabled. An empty email default means Django's built-in `EMAIL_*` sending.

### Email: `services/email.py`

All product email goes through `queue_email(...)` or `send_email_now(...)`.

- `queue_email` hands the message to the Celery task `integrations.send_email` together with the current
  schema. The worker then resolves the same academy's account.
- `send_email_now` resolves the account and sets its own `Message-ID`. On an own account the `From` address is
  the account's; on Etqan's default the reply-to is the academy's address.
- After sending, `meter_email` records one `email` unit per accepted message, keyed by Message-ID.
- It raises `NotSetUpError` when nothing resolves. SMTP `OSError` propagates to the caller.
- A metering failure is logged and never raised.
- Etqan's own mail (invoice emails) is sent from the public schema, so it is never metered.

### WhatsApp: `services/whatsapp.py`

`send_whatsapp_now(to=, language=, params=)` sends the resolved account's template. `build_params` builds the
three body parameters (academy name, title, body) and fits them under 1024 characters.
`meter_whatsapp` records one `conversation` per accepted message, keyed by wamid. The only caller is
`etqan.notifications.channels.whatsapp`.

### Video: `services/video.py`

`create_meeting`, `host_link`, `meeting_fits`, `release_meeting`, `zoom_event` and the Etqan host pool are
documented in [meetings.md](meetings.md). Zoom minutes are metered on `meeting.ended` as
`video/minute`, keyed by `"<instance uuid>:minute"`.

### Stripe Connect: `services/onboarding.py`

Etqan's payments default is Stripe Connect Express on Etqan's platform account. The academy's `payments`
`AcademyAccount` row holds only `config = {account_id, status, country, mode}`. It has no secrets.

- `stripe_platform()` returns Etqan's key, its mode and its webhook secrets, whether or not the default is
  enabled. Webhooks about earlier payments still need them.
- `start_onboarding(country=, by=)` requires Etqan's default to resolve for the academy. It then:
  1. Creates the Express account if the academy has none in the current mode. This runs under a per-schema
     advisory lock, with idempotency key `etqan-connect-<schema>-<country>`.
  2. Adds a `stripe_account` route. If another academy already owns that account, the request is refused.
  3. Returns a hosted Account Link URL. It returns to `/app/settings/integrations?stripe=return|refresh`.

  The country must be in `CONNECT_COUNTRIES`.
- `connect_status`: `charges_enabled` → `active`; `details_submitted` → `pending`; otherwise `onboarding`.
  `apply_connect_account` (on the `account.updated` webhook) and `refresh_connect` (Check status) store it.
- `stripe_connect()` returns the account a new checkout pays into. That requires the default to resolve, the
  account's mode to equal the platform key's mode, and `status == active`. `etqan.gateways` uses it only when
  the academy has no enabled Stripe keys of its own.
- **Mode switch (2026-10-13, `8f195f6`).** When Etqan changes its platform key between test and live, the
  stored account of the old mode is treated as "not connected". The row is not deleted.
  - `connect_other_mode` detects this case.
  - The card's `own.config.other_mode` tells the dashboard.
  - "Continue" without a country fails with `integrations.connect_country_required`.
  - A new onboarding keeps the old account under `config.prior`, for audit only.
  - `refresh_connect` will not read the old account with the wrong-mode key.

### Webhook routes: `services/routes.py`

`add_route(kind, ref)` is called inside the academy that created the object. If two academies claim one ref:

- a `stripe_account` route stays with the first academy;
- a `zoom_meeting` route re-points to the newest academy, because Zoom reuses meeting ids.

`route_schema(kind, ref)` is read by the base-domain endpoints.

## API

Academy hosts. In the table, "office" means admins plus staff who hold the code.

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/integrations/` | office, `integration.view` | One card per service: `using` (`academy`/`etqan`/`none`), `default_status`, `connectable`, `own` (no secrets), `default_prices`; payments adds `connect_countries` |
| PUT | `/api/v1/integrations/<service>/` | office, `integration.update` | Connect or edit the own account (`connect`) |
| DELETE | `/api/v1/integrations/<service>/` | office, `integration.update` | Disconnect |
| POST | `/api/v1/integrations/<service>/test/` | office, `integration.update` | Probe the own account (payments: Check status) |
| POST | `/api/v1/integrations/payments/connect/` | office, `integration.update`, not impersonating | `{country}` → `{url}` of Stripe's hosted onboarding |

Base domain only (`config/urls_public.py`). These have no authentication, are verified over the raw body, and
are non-atomic:

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/webhooks/zoom/` | Etqan's Zoom app: URL validation, `meeting.ended` → minutes metered (`api/webhooks.py`) |
| POST | `/api/v1/webhooks/stripe-connect/` | Stripe Connect events: `account.updated`, `application_fee.created`, checkout events (`etqan.gateways.api.views.ConnectWebhookView` → `gateways/services/connect_webhooks.py`) |

## Dashboard

- Route `dashboard/src/routes/_authed/settings.integrations.tsx` (`/app/settings/integrations`) uses permission
  `integration.view`. It reads `?stripe=return|refresh` after Stripe onboarding.
- Feature `dashboard/src/features/integrations/`: `IntegrationsPage`, one form per service (`EmailAccountForm`,
  `WhatsAppAccountForm`, `VideoAccountForm`, `AiAccountForm`) and `StripeConnectPanel`. `schemas.ts` reads
  `other_mode`.

## Background jobs

- `integrations.send_email` (`tasks.py`) sends one queued email inside `academy_context(schema)`. It retries 3
  times with backoff on `OSError`. When nothing resolves it returns `not_set_up` and does not retry.
- No beat job of its own. Meeting provisioning (`scheduling.provision_meetings`) is in [meetings.md](meetings.md).

## Configuration

- `ETQAN_SECRETS_KEY`: the Fernet key or keys, comma-separated. The first key encrypts. Dev and test derive one
  from `SECRET_KEY`.
- `JITSI_BASE_URL` (default `https://meet.jit.si`).
- `EMAIL_*`: Etqan's built-in sending when the email default has no config.
- Platform admin (`integrations/admin.py`):
  - The `PlatformAccount` form takes `enabled`, `config` as JSON, and a write-only secret JSON. It has a
    "Remove the stored secrets" checkbox and a "Test" action (it needs the change permission,
    ETQAN-QA-013), and shows the webhook URL for video and payments.
  - `WebhookRoute` and `HostBooking` are read-only.
- The suspend switch is `Academy.etqan_defaults_suspended` (tenants admin). It can be turned on only when
  `etqan_billing.may_suspend` allows it.
- Feature switches: `whatsapp`, `online_payments`, `zoom_api`, `ai_assistant`, `ai_reports` (gate Etqan's
  default only).

### Adding a provider or service

1. Write a provider class in `providers/` with `service`, `connectable`, `empty_is_default`, `clean`, `last4`
   and `probe`, and register it in `PROVIDERS`.
2. For a new service, also:
   - add it to `Service`;
   - add a `SWITCHES` entry;
   - add a data migration for its `PlatformAccount` row;
   - if it is metered, add its units to `etqan_billing` (`Metered`, `Unit`, `UNITS`, `PER`, `LINE_TITLES`).
3. Expose a send or call function from `services/`, re-export it in `services/__init__.py`, and meter with
   `record_usage(source=resolved.source, ...)` keyed by the provider's own id.
4. Callers import only `etqan.integrations.services`. `lint-imports` enforces this.

## Code map

- `backend/etqan/integrations/models.py`, `accounts/models.py`
- `backend/etqan/integrations/services/`: `resolver.py`, `accounts.py`, `email.py`, `whatsapp.py`, `video.py`,
  `onboarding.py`, `routes.py`
- `backend/etqan/integrations/providers/`: `base.py`, `email.py`, `whatsapp.py`, `payments.py`, `video.py`,
  `zoom.py`, `ai.py`
- `backend/etqan/integrations/api/`: `views.py`, `payloads.py`, `webhooks.py`
- `backend/etqan/gateways/services/connect.py`, `connect_webhooks.py` (the payments side of Connect)
- `backend/etqan/platform/secrets.py`, `backend/etqan/platform/stripe.py`
- `dashboard/src/features/integrations/`

## Design history

- [Integrations & Etqan billing design](../superpowers/specs/2026-10-07-integrations-and-etqan-billing-design.md):
  the base spec. §3.3 names the probe `test()` and describes a one-token AI call and a WhatsApp template send;
  the code differs (see above).
- [Plan: integrations 1, core](../superpowers/plans/2026-10-07-plan-integrations-1-core.md): models, resolver,
  email on the resolver, Settings → Integrations.
- [Plan: integrations 2, billing](../superpowers/plans/2026-10-08-plan-integrations-2-billing.md): metering seam.
- [Plan: integrations 3, Zoom and Connect](../superpowers/plans/2026-10-09-plan-integrations-3-zoom-connect.md):
  routes, Zoom, the host pool, Stripe Connect. The plan's `services/connect.py` shipped as
  `services/onboarding.py`.
- [B5c WhatsApp design](../superpowers/specs/2026-10-08-b5c-whatsapp-design.md) and
  [plan 57](../superpowers/plans/2026-10-08-plan-57-whatsapp.md): the WhatsApp provider. It meters on
  acceptance (wamid), not on the delivery webhook as the base spec said.
- [B10 AI design](../superpowers/specs/2026-10-08-b10-ai-design.md): the Claude provider (A-1).
- Connect test/live mode switch: backend `8f195f6` (2026-10-13). There is no spec; see the ledger notes in
  `onboarding.py`.
