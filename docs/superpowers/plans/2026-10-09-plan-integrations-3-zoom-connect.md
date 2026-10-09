# Integrations slice 3 — Zoom meetings and Stripe Connect — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Slice:** Integrations 3 (video and payments on the resolver). Not a phase: built outside the B2–B11 streams. Spec §7 gave video to B2 and Stripe Connect to a B3 follow-up; both phases are merged, so this slice owns them.
**Requires:** slices 1 and 2 merged (they are: meta `master`, backend/dashboard `main`). **Unblocks:** Etqan's video and payments defaults; nothing waits on it.

**Goal:** Sessions get a video meeting link without anyone typing one: a Zoom meeting made on the academy's own Zoom Server-to-Server account, or on Etqan's when the academy uses Etqan's default (under a free host from Etqan's pool of licensed Zoom users; minutes are metered on Zoom's meeting-ended event), or a free Jitsi room when no Zoom account resolves or no Etqan host is free. Students and parents get the join link; the session's teacher gets a fresh host (start) link on demand, never stored. Online payments work for an academy with no Stripe keys of its own: its admin onboards a Stripe Express account through Stripe's hosted onboarding ("Connect with Stripe" on Settings → Integrations), families pay into that account, and Etqan's per-academy platform fee is taken through `application_fee` and recorded for the academy's monthly statement. B3's own keys keep working unchanged and win when they are on.

**Architecture:**
- **Backend, `etqan.platform`:** `platform/stripe.py`, B3's Stripe REST client moved out of `gateways/providers/stripe.py` so payments (B3) and Connect (integrations) share it; behaviour unchanged.
- **Backend, `etqan.integrations`:** a public `WebhookRoute` table (a Zoom meeting id or a Stripe Connect account id → its academy) for Etqan's one webhook endpoint per provider; `providers/zoom.py` (S2S OAuth token, create meeting, over httpx), `providers/video.py` (`ZoomProvider`), `providers/payments.py` (`StripePlatformProvider`: Etqan's platform keys); `services/routes.py`, `services/video.py` (`create_meeting` with the host pool, `jitsi_meeting`, `meetings_wanted`, `host_link`, `meeting_fits`/`release_meeting`, the Zoom webhook), a public `HostBooking` table (which pool host holds which time), `services/connect.py` (onboarding, status, `stripe_platform`, `stripe_connect`); `api/webhooks.py` (Zoom endpoint) and `POST /api/v1/integrations/payments/connect/`. The `zoom_api` switch becomes built.
- **Backend, `etqan.scheduling`:** `Session.meeting_provider` + `meeting_ref`; `services/meetings.py` `provision_meetings()` and the 5-minute beat task `scheduling.provision_meetings`: sessions in the next 24 hours with no link get one meeting per class, and a class moved off its host booking gets a new one; `GET /api/v1/sessions/<id>/host-link/` for the session's teacher only.
- **Backend, `etqan.gateways`:** `ConnectAccount`, `services/connect.py` (route: own keys → Connect; application fee from `etqan_billing.connect_fee()`), `Checkout.via_connect` + `platform_fee_minor`, the Stripe provider sends `Stripe-Account` and `application_fee_amount`, `services/connect_webhooks.py` + the Connect endpoint (`account.updated`, `application_fee.created` → `record_collected_fee`, `checkout.session.*` → B3's handler).
- **Base domain:** `config/urls_public.py` gains `/api/v1/webhooks/zoom/` and `/api/v1/webhooks/stripe-connect/` (Etqan's apps call one URL; never on an academy host).
- **Dashboard:** `src/features/integrations/` gains `VideoAccountForm`, `StripeConnectPanel`, `redirect.ts`, schema and api additions; the Integrations route reads `?stripe=return|refresh`; strings in `src/locales/{en,ar}/integrations.json`; the payments card lists the countries Connect supports and says when the academy's is not one. `src/features/scheduling/` gains the teacher's "Start as host" button.

**Tech Stack:** Django 6 / DRF 3.18 / django-tenants 3.14, PostgreSQL 18, Celery + django-celery-beat, httpx (already a dependency, B3), respx in tests (already used by gateways); React 19 + TanStack Router/Query, react-hook-form + zod 4, i18next. No new dependency, no Zoom or Stripe SDK.

**Spec:** `docs/superpowers/specs/2026-10-07-integrations-and-etqan-billing-design.md` — §4 rows "Payments" and "Video", §3.1 (`AcademyAccount(payments)` holds only the Connect `acct_…` and its status), §3.2 (resolver), §3.3 (probes: payments retrieves the Connect account, video requests a Zoom token), §5 (video minutes on Zoom's meeting-ended event; Connect fees through `record_collected_fee`), §6 (the payments card shows "Connect with Stripe" beside B3's keys), §7 (video and Connect now owned here), §8. Out of this slice: WhatsApp (B5c), AI (B10), refunds of Connect fees, deleting Stripe or Zoom objects, IN-8's non-goals.

## Global Constraints

**Repos and branches**
- Repos: `backend/` (trunk `main`), `dashboard/` (trunk `main`), the meta repo (trunk `master`). `marketing/` and `infra/` are not touched.
- Work in `/home/abdulkhalek/Projects/etqan_tutor-wt/integrations` on branch `feat/integrations-3` in `backend/`, `dashboard/` and meta (already created from the trunks). Check first: `git -C backend branch --show-current` and `git -C dashboard branch --show-current` print `feat/integrations-3`, and `test -f backend/etqan/etqan_billing/services/usage.py && echo slice2` prints `slice2`.
- **Never run any `git submodule` subcommand.** Commit in the repo the change lives in (`git -C backend …`, `git -C dashboard …`); in meta commit only explicit paths, never `git commit -a` (it captures submodule pointers). Do not touch `/home/abdulkhalek/Projects/etqan_tutor` or any other worktree.
- Commits use Conventional Commits and end with the trailer `Co-Authored-By: <implementing model> <noreply@anthropic.com>`, where `<implementing model>` is the name of the model that runs the task (for example `Claude Opus 5.5 (1M context)`). Set it once per shell: `TRAILER="Co-Authored-By: <implementing model> <noreply@anthropic.com>"` with the real name filled in; every commit below passes `-m "$TRAILER"`.

**Parallel work touching the same files (check before Task 1 and before the PRs).** B10a (`feat/b10a-ai-drafts`, worktree `etqan_tutor-wt/b10`) replaces the AI `NotYet` provider under a claim on `etqan.integrations` (ledger D49) and edits the same lines this slice edits: `integrations/providers/__init__.py` (the `PROVIDERS` map), `integrations/admin.py` (`FORM_FIELDS`, the secret help text), `integrations/tests/test_providers.py` (the `connectable` list), and in the dashboard `IntegrationsPage.tsx` (`CardActions`), `api.ts` (the `connect` body type), `schemas.ts`, `index.ts`. B5c (not started; ledger D60) will do the same for WhatsApp. Run `python3 /home/abdulkhalek/Projects/etqan_tutor/scripts/orchestration/ledger.py show | grep -iE "claim|B10a|B5c"` and `git -C backend log --oneline origin/main -5`: if B10a has merged, `git -C backend merge origin/main` and `git -C dashboard merge origin/main` first, and keep its `ai` entries everywhere this plan lists the maps (each edit below says how). If it merges while this slice is in flight, merge `origin/main` before the PRs and resolve by keeping both sides' lines. Every edit here to those shared lines is additive.

**Tenancy**
- django-tenants: one schema per academy. `WebhookRoute` is in the SHARED app `etqan.integrations` (public schema), keyed by its academy (FK to `settings.TENANT_MODEL`, `PROTECT`). `Checkout` (gateways) and `Session` (scheduling) are tenant models. Migrate with `migrate_schemas` (the stack's `migrate` already is).
- Code never imports `etqan.tenants`: the current academy is `django.db.connection.tenant`; a webhook on the base domain enters an academy with `etqan.platform.tenancy.academy_context(schema_name)`; the beat job loops with `etqan.platform.tenancy.for_each_academy`.
- Any user-facing URL is built with `etqan.platform.frontend.app_url()` / `frontend_url()` (Stripe's return and refresh URLs). Etqan's webhook URLs live on `settings.FRONTEND_URL` (the bare base domain).

**Import boundaries (`lint-imports`).** `etqan.integrations` imports only the platform and `etqan_billing.services` (unchanged contract). `etqan.gateways` and `etqan.scheduling` reach integrations and etqan_billing only through their `services` packages. Nothing imports `gateways` or `scheduling` from integrations.

**Shared lists.** This work is not a phase: never add lines under a `── phase Bn ──` marker. Lines go in the existing blocks whose comment reads `Integrations (spec 2026-10-07; not a phase)` (or `Integrations slice 2 …`), or at the end of a list that has no markers (`CELERY_BEAT_SCHEDULE`). That covers `config/settings/base.py`. `etqan/platform/tests/test_phase_sections.py` keeps passing because no marker moves. Test tables take additive edits only.

**Money and time.** Money is integer minor units plus a currency; the platform fee percent is integer basis points. Stored instants are UTC; integrations reads time from `etqan.integrations.clock.now()`, gateways from `etqan.gateways.clock.now()`, scheduling from `etqan.scheduling.dates.now()`; tests pin them.

**Secrets.** Zoom client secrets, Zoom's webhook secret token, Stripe's platform secret key and webhook signing secrets are stored only in `PlatformAccount` / `AcademyAccount.secret_enc` (Fernet through `etqan.platform.secrets`), set in the platform admin by Etqan staff or (Zoom only) by the academy on Settings → Integrations. Nothing is read from an env var or hard-coded. A secret never appears in an API answer, the admin change page, a `repr`, or a log line. Everything works with fakes (respx, monkeypatched providers) before the owner supplies real credentials.

**API.** All academy routes under `/api/v1/`. Domain errors are `etqan.platform.exceptions` (400 `ValidationError` with `field` or `code`, 404, 502 `ExternalServiceError`, 503 `UnavailableError`). Webhooks answer 400 on a bad signature, 200 otherwise (an event about something not ours is ignored, never an error).

**Language.** en and ar only (ledger D11), real Arabic; Zoom, Stripe, Jitsi stay Latin. No Spanish file (ledger D22).

**Backend commands.** Run from the meta worktree, inside this worktree's stack (`.env.stream` is there, project `etqan-integrations`, slot-5 ports 8580/8500/5932/6879). If it is not running: check `docker ps --format '{{.Names}} {{.Ports}}' | grep -E ':(8580|8500|5932|6879)->'` prints only `etqan-integrations-*` containers or nothing, then `just dev-backend`. Load it in every shell:
```bash
cd /home/abdulkhalek/Projects/etqan_tutor-wt/integrations
set -a && . ./.env.stream && set +a
DJ="docker compose -f docker-compose.local.yml exec -T django"
```
- Targeted tests: `$DJ pytest etqan/integrations -q` (add `--create-db` once after a task adds a migration).
- Migrations: `$DJ python manage.py makemigrations <app_label>`. Never run `manage.py`, `migrate` or e2e any other way.
- Format and lint: `$DJ sh -c 'ruff check --fix . && ruff format .'`, `$DJ lint-imports`.
- Whole suite: `just test-backend`.

**Dashboard commands.** From the meta worktree (with `.env.stream` loaded as above):
```bash
DASH="docker compose -f docker-compose.local.yml run --rm dashboard"
export HOST_UID=$(id -u) HOST_GID=$(id -g)
```
- One test file: `$DASH pnpm vitest run src/features/integrations/<file>`.
- Full tests with coverage: `$DASH pnpm test:coverage`.
- Types: `just test-frontend` (`tsc --noEmit`). Lint: `just lint-frontend` (biome + `check-colors.mjs`: semantic tokens only).
- Format: `$DASH pnpm exec biome check --write src`.

**Coverage and gates.** Backend coverage ≥ 80 % (`just test-backend`). Dashboard lines and statements ≥ 80, branches and functions ≥ 70 (`pnpm test:coverage`). Before the PRs: `just test`, `just lint`, and the full `just e2e` (no journey reaches Zoom or Stripe: `zoom_api` is off by default and Etqan's payments default ships disabled; the suite proves nothing else moved).

## Decisions (gaps the spec left, filled here)

Slices 1 and 2's decisions stand (slice 1 D1–D17, slice 2 D1–D18); in particular slice 1 D7 (`video` is gated by `zoom_api`, `payments` by `online_payments`), slice 1 D14 (the payments card links to B3's screen), slice 2 D3 (`record_usage` records only `source == "etqan"`), slice 2 D7/D9 (`connect_fee()`, `record_collected_fee`, collected fees shown but not totalled), ledger D61/D62 (one `source_ref` per unit; record on the provider's confirmation). Slice 3 adds:

**Owner review (2026-10-09):** D21–D23 are the owner's decisions: a Zoom host pool for Etqan's default, Stripe Connect built now with an unsupported-country answer, and a host (start) link for the teacher only. D5, D6, D8, D9 and D14 are amended to match. Everything else stays (Jitsi when Zoom fails within 30 minutes, typed links never replaced, Disconnect only forgets the link).

| # | Decision |
|---|---|
| D1 | **No new app.** Zoom and the Connect account live in `etqan.integrations` (accounts, providers, onboarding, the Zoom webhook); the Connect checkout path and its webhook live in `etqan.gateways` (they must reach B3's checkout code, which integrations may not import); scheduling asks integrations for a link. |
| D2 | **One Stripe client.** B3's form-encoded httpx client moves to `etqan.platform.stripe.call(method, path, *, key, data=None, idempotency="", account="") -> dict`, raising `StripeError(status, error_type, code, kind)`; it logs nothing. `gateways.providers.stripe` keeps its own log lines and `ProviderError` reasons (byte-for-byte the same messages), so B3's behaviour and tests are unchanged. No Stripe or Zoom SDK. |
| D3 | **`WebhookRoute`** (public, in `etqan.integrations`): `kind` ∈ `zoom_meeting`, `stripe_account`; `ref` (Zoom meeting id, `acct_…`); `academy`; unique `(kind, ref)`. Written when Etqan's Zoom app creates a meeting and when an academy's Connect account is created; never deleted (late events still land). Etqan's single endpoint per provider reads it in the public schema, then enters that academy. |
| D4 | **Etqan's webhook endpoints are on the bare base domain only**: `POST /api/v1/webhooks/zoom/` and `POST /api/v1/webhooks/stripe-connect/` in `config/urls_public.py`, unauthenticated, CSRF-free, unthrottled, non-atomic. An academy's own Zoom account sends Etqan nothing (its use is never metered, IN-5). |
| D5 | **Zoom accounts.** Server-to-Server OAuth. An academy's own: config `{account_id, client_id, host_user}` (`host_user` defaults to `me`, the app's owner; otherwise a Zoom user's email). Etqan's default: config `{account_id, client_id, host_users}`, a list of 1–50 licensed Zoom users (`me` or emails), the pool of D21. Secret `{client_secret}`; Etqan's default also `{webhook_secret}` (Zoom's "Secret Token"). `last4` is the client secret's. Probe = request a fresh token. Tokens are cached in Django's cache per account (a hash of account id, client id and secret) until 5 minutes before they expire; a 401 on a meeting drops the cached token. |
| D6 | **The meeting.** Scheduled (`type` 2), start in UTC, the session's minutes, topic `"<course name_en> · <teacher full name>"` (≤ 200), join before host at any time, no waiting room, no registration, no automatic recording. Students and parents use `join_url`; the teacher's host link is D23. The session stores `meeting_provider` (`zoom`, `jitsi`, or blank for a link someone typed) and `meeting_ref` (the Zoom meeting id), never a `start_url`. |
| D7 | **When a session gets a link.** Status `scheduled`, not archived, `meeting_url` blank, starting within the next 24 hours or still running, and the academy wants meetings: `zoom_api` on, or its own Zoom account connected and enabled. A link anyone entered (slot, teacher's default, typed) is never replaced; an academy with neither switch nor own account is unchanged. |
| D8 | **Provisioning.** Beat task `scheduling.provision_meetings` every 5 minutes, `for_each_academy(atomic=False)` (Zoom is called; each update is its own statement). One meeting per class: sessions sharing teacher, `starts_at` and `minutes` (a group class, ledger D6) get the same link. A cancelled session keeps its meeting. A class moved after its meeting was made: on the academy's own Zoom it keeps its meeting (a scheduled Zoom meeting can start any time); on Etqan's default its host booking no longer fits (D21), so the next run releases the booking, blanks the class's Zoom link and makes a new meeting (students see the new link in the app). Nothing is deleted at Zoom. |
| D9 | **Jitsi is the free fallback** (spec §4): when `resolve("video")` is None, the link is `<JITSI_BASE_URL>/Etqan<32 hex>` (`JITSI_BASE_URL` env, default `https://meet.jit.si`), an unguessable room, no account. Also a Jitsi room when Etqan's default resolves but no pool host is free (D21). When Zoom fails, the class waits for the next run unless it starts within 30 minutes, then it gets a Jitsi room so the class can still happen. A Jitsi room has no host link: everyone gets the room. |
| D10 | **Minutes metered** on Zoom's `meeting.ended` to Etqan's app only, for meetings with a route (made on Etqan's default): quantity `ceil((end_time − start_time) / 60 s)`, at least 1; `source_ref` `"<meeting uuid>:minute"` (ledger D61), `occurred_at` = `end_time`. A replay counts once (slice 2 D3). Zoom's `endpoint.url_validation` is answered with `{plainToken, encryptedToken}`. Signatures: `x-zm-signature` = `v0=` + HMAC-SHA256(secret token, `v0:<x-zm-request-timestamp>:<raw body>`), within 300 s. |
| D11 | **`zoom_api` becomes built** (off by default): it gates Etqan's video default (slice 1 D7) and turns on links for the academy. The academy's own Zoom account needs no switch (slice 1 D7). |
| D12 | **The payments row is the Connect account, not an "own account".** `AcademyAccount(service="payments").config` = `{account_id, status, country, mode}`, no secret (spec §3.1). The resolver never takes it as step 1: the academy's own payments account is B3's `GatewayAccount`, which `gateways` checks first (D17). `resolve("payments")` is therefore Etqan's default (platform keys) or None. |
| D13 | **Etqan's platform keys**: `PlatformAccount(payments)` secrets `{secret_key, connect_webhook_secret, platform_webhook_secret}`, config `{mode}` derived from the key's prefix (`sk_test_`/`rk_test_` → test, `sk_live_`/`rk_live_` → live). An academy cannot type keys on this card (400 `integrations.use_connect`); its own keys go on B3's Payment gateways screen. Etqan's admin Test retrieves the platform account (`GET /v1/account`). |
| D14 | **Onboarding.** `POST integrations/payments/connect/ {country}` (admins and `integration.update`, never while impersonating): needs Etqan's default to resolve (platform keys set, Etqan's row enabled, `online_payments` on, not suspended); creates an Express account (`card_payments` and `transfers` requested, `metadata[academy]` = schema) with idempotency key `etqan-connect-<schema>-<country>` when the academy has none for the current mode, writes the route, then answers a hosted Account Link `{url}` (`type=account_onboarding`, `return_url` `app_url("/settings/integrations?stripe=return")`, `refresh_url` `app_url("/settings/integrations?stripe=refresh")`). The country is asked only when an account is created and must be one of `CONNECT_COUNTRIES` (D22). Status from the account: `charges_enabled` → `active`; else `details_submitted` → `pending`; else `onboarding`. An account from the other mode counts as none. |
| D15 | **The card's Test for payments is "Check status"**: `POST integrations/payments/test/` retrieves the Connect account with the platform key, updates its status and records the last test on the row (spec §3.3 "retrieve the Connect account"). `account.updated` webhooks update the status too. |
| D16 | **Disconnect** (`DELETE integrations/payments/`) forgets the link only: no Stripe call, the route stays (fees for earlier payments still land), the Express account stays in Etqan's Stripe dashboard. Reconnecting within 24 hours with the same country gets the same account back (idempotency); later a new one. |
| D17 | **Precedence** (spec IN-4, resolver step 1): an enabled own Stripe `GatewayAccount` → B3's path exactly as today. Else Connect when `integrations.stripe_connect()` answers (Etqan's default resolves, the platform key is set, the academy's Connect account is `active` in the key's mode). Else Stripe is not offered. PayPal is unchanged. A checkout records `via_connect` and `platform_fee_minor`; a Connect checkout is never simulated (`GATEWAYS_SIMULATE` covers B3's own test keys only); reuse and superseding stay within one route. |
| D18 | **Application fee** = `(total × percent_bp + 5000) // 10000` + `fixed_amount` when `ConnectFee.currency` equals the checkout's (else the percent alone), floored to a multiple of 10 for three-decimal currencies, capped at the total; `total` = amount + the family's fee (what Stripe charges). No `ConnectFee` row → no application fee. |
| D19 | **One Connect endpoint, two signing secrets.** Stripe sends `account.updated` and `checkout.session.*` of connected accounts to a "Connected accounts" endpoint and `application_fee.created` to a "Your account" endpoint; the owner points both at `/api/v1/webhooks/stripe-connect/` and pastes both `whsec_…`; a body verifies under either. Handled: `account.updated` (status), `application_fee.created` (`record_collected_fee(amount, currency, source_ref=<fee id>, occurred_at=<created>)`), `checkout.session.completed|async_payment_succeeded|async_payment_failed|expired` (B3's handler, recorded once in `WebhookEvent`, mode checked against the platform key). An account with no route → 200, ignored. |
| D20 | **Dashboard.** The payments card shows a Connect status chip (`active` live, `pending`/`onboarding` warning) and `StripeConnectPanel` (country, Connect with Stripe / Continue onboarding, Check status, Disconnect) above B3's "Open Payment gateways" link, with a line that own keys take precedence. The video card gets `VideoAccountForm`. Back from Stripe, `?stripe=return` checks the status once and toasts; `?stripe=refresh` says the link expired and shows Continue. Full-page navigation goes through `integrations/redirect.ts` `go(url)` so tests replace it. |
| D21 | **Owner (2026-10-09): Etqan's Zoom host pool.** A meeting on Etqan's default is created under the first host in `host_users` that holds fewer than `MAX_MEETINGS_PER_HOST` (= 1, a constant in `integrations.services.video`) bookings overlapping `[starts_at, starts_at + minutes)`. Bookings are public rows `HostBooking(host, starts_at, ends_at, meeting_id, academy)`, chosen under a transaction-scoped advisory lock (`integrations:zoom-hosts`) so two academies never take the same host at once; the booking is reserved before Zoom is called (never under the lock), filled with the meeting id after, and deleted if Zoom fails. A reservation with no meeting id older than 10 minutes (a crashed run) no longer blocks its host. No free host → a Jitsi room (D9). Bookings are never deleted otherwise (past ones block nothing). An academy's own Zoom uses its own `host_user` with no booking. |
| D22 | **Owner (2026-10-09): Stripe Connect now, and countries it cannot serve.** `CONNECT_COUNTRIES` in `integrations.services.connect` is the list of countries Stripe Express connected accounts support ([assumed] Stripe's published list; the owner checks it before go-live). The payments card lists them (card field `connect_countries`, payments card only) plus "My country is not listed", which shows "Stripe Connect isn't available in your country" and points to Payment gateways (own Stripe keys or PayPal). The API refuses any other country, and Stripe refusing one, with 400 `integrations.connect_country` on `country`. |
| D23 | **Owner (2026-10-09): the teacher's host link.** `GET /api/v1/sessions/<id>/host-link/`, for the session's teacher only (anyone else: 404; never while impersonating, ledger D19), answers `{url, host}`: a `start_url` fetched from Zoom at that moment (`GET /meetings/<id>` on the account video resolves to now) with `host: true`, or the session's join link with `host: false` when the session is not a Zoom meeting, the fetch fails, or the meeting's `join_url` is no longer the session's link (someone replaced it). Sent with `Cache-Control: no-store`; never stored, logged or put in any list payload. Admins and supervisors join with the join link (Plan 12b's open stays as it is). The session payload gains `meeting_host: bool` (a Zoom meeting with a ref) so the teacher's screen offers "Start as host". |

## Review Focus

1. **A webhook acting in the wrong academy, or a forged one acting at all.** A Zoom or Stripe event with a bad or stale signature, signed with the other Stripe secret, about a meeting/account Etqan never routed, or routed to academy A arriving while B is the connection's tenant. Expect: 400 for bad signatures, 200 and nothing for unknown ids, effects only in the routed academy. Tests: `test_a_bad_or_stale_signature_is_refused` (Task 4), `test_minutes_land_in_the_academy_that_made_the_meeting` (Task 4), `test_an_unknown_account_is_ignored` (Task 9), `test_either_signing_secret_is_accepted_and_nothing_else` (Task 9).
2. **Billing what must not be billed, or twice.** Minutes of a meeting on the academy's own Zoom, a replayed `meeting.ended`, a replayed `application_fee.created`, a Connect fee when the academy uses its own keys. Tests: `test_meetings_on_the_academys_own_zoom_get_no_route`, `test_a_replayed_meeting_ended_counts_once` (Task 4), `test_a_replayed_fee_is_recorded_once` (Task 9), `test_own_keys_win_over_connect` (Task 8).
3. **Overwriting a link or splitting a class.** A typed or teacher-default link replaced by Zoom; a group class's rows getting different meetings; Zoom down leaving a class that starts in 10 minutes without a link; a cancelled or archived session getting a meeting; a moved class keeping a host that now overlaps another meeting. Tests: `test_a_link_someone_entered_is_never_replaced`, `test_a_group_class_shares_one_meeting`, `test_zoom_down_retries_later_but_a_class_about_to_start_gets_jitsi`, `test_cancelled_archived_and_far_sessions_are_left_alone`, `test_a_class_moved_off_its_host_gets_a_new_meeting` (Task 5).
4. **Money going to the wrong account.** Own keys on and Connect active (must be own, no `Stripe-Account`, no fee); a test-mode Connect account used with a live key; the fee exceeding the total, in the wrong currency, or not a multiple of 10 for KWD. Tests: `test_own_keys_win_over_connect`, `test_an_account_of_the_other_mode_is_not_used` (Task 7), `test_the_fee_is_percent_plus_fixed_in_its_currency_only`, `test_three_decimal_fees_are_multiples_of_ten_and_never_above_the_total` (Task 8).
5. **A credential reaching the wrong person or a log.** Zoom's `start_url` (a host credential) reaching a student, a parent, another teacher, an impersonating admin, a list payload or the database; Zoom's client secret or webhook token, or Stripe's platform key, in the card, the admin page, a `repr` or a log; two overlapping Etqan meetings sharing one host. Tests: `test_only_the_sessions_teacher_gets_the_host_link`, `test_the_host_link_is_never_stored_or_listed` (Task 6), `test_overlapping_meetings_never_share_a_host` (Task 4), `test_connecting_zoom_returns_the_card_without_the_secret` (Task 3), `test_the_platform_key_never_shows_in_a_repr_or_log` (Task 7), `test_a_refusal_logs_no_key` (Task 1).

## File structure

**Backend (`backend/`)**

| Path | Responsibility |
|---|---|
| `etqan/platform/stripe.py`, `etqan/platform/tests/test_stripe.py` | the shared Stripe REST client (D2) |
| `etqan/gateways/providers/stripe.py` | B3's provider on the shared client; `Stripe-Account` and `application_fee_amount` for Connect |
| `etqan/gateways/providers/base.py` | `ConnectAccount` |
| `etqan/integrations/models.py`, `migrations/0003_webhookroute.py`, `0004_hostbooking.py` (generated) | `WebhookRoute`, `HostBooking` |
| `etqan/integrations/providers/base.py` | `empty_is_default` documented on `Provider` |
| `etqan/integrations/providers/zoom.py`, `providers/video.py`, `providers/payments.py`, `providers/__init__.py` | Zoom client, `ZoomProvider`, `StripePlatformProvider`, registry |
| `etqan/integrations/services/routes.py`, `services/video.py`, `services/connect.py`, `services/accounts.py`, `services/resolver.py`, `services/__init__.py` | routes, meetings and the Zoom webhook, Connect onboarding, probe/platform-change tweaks, payments never step 1, exports |
| `etqan/integrations/api/webhooks.py`, `api/views.py`, `api/urls.py` | the Zoom endpoint, the Connect start endpoint |
| `etqan/integrations/admin.py` | form-field mapping, help text, webhook URLs |
| `etqan/integrations/tests/test_routes.py`, `test_zoom.py`, `test_video.py`, `test_connect.py`, `conftest.py` (+ edits to `test_providers.py`, `test_resolver.py`, `test_admin.py`) | tests |
| `etqan/platform/features.py`, `etqan/platform/tests/test_features.py` | `zoom_api` built |
| `etqan/scheduling/models.py`, `migrations/00NN_session_meeting_ref.py` (generated) | `Session.meeting_provider`, `meeting_ref` |
| `etqan/scheduling/services/meetings.py`, `services/__init__.py`, `tasks.py`, `tests/test_meetings.py` | links for upcoming sessions, moved classes |
| `etqan/scheduling/api/views.py` (or the sessions views module), `api/urls.py`, `api/payloads.py`, `tests/test_host_link.py`, `etqan/access/tests/test_routes.py` | the teacher's host link |
| `etqan/gateways/models.py`, `migrations/0004_checkout_connect.py` (generated) | `Checkout.via_connect`, `platform_fee_minor` |
| `etqan/gateways/services/connect.py`, `services/checkouts.py`, `services/fees.py`, `services/links.py`, `services/webhooks.py`, `services/connect_webhooks.py`, `services/__init__.py` | the Connect route, fee, checkouts, the Connect webhook |
| `etqan/gateways/api/views.py` | `ConnectWebhookView` |
| `etqan/gateways/tests/conftest.py`, `test_connect_checkouts.py`, `test_connect_webhooks.py` | tests |
| `config/urls_public.py`, `config/settings/base.py`, `pyproject.toml` | base-domain webhooks, `JITSI_BASE_URL`, beat entry, contracts |

**Dashboard (`dashboard/`)**

| Path | Responsibility |
|---|---|
| `src/features/integrations/schemas.ts`, `api.ts`, `redirect.ts`, `index.ts` | Zoom form schema, Connect status, `connectStripe` |
| `src/features/integrations/VideoAccountForm.tsx`, `StripeConnectPanel.tsx`, `IntegrationsPage.tsx` | the two cards' UIs |
| `src/routes/_authed/settings.integrations.tsx` | `?stripe=` handling |
| `src/features/scheduling/hostLink.ts`, `bits.tsx` (`HostLink`), `api.ts`, `schemas.ts`, `src/test/scheduling-fixtures.ts`, `src/locales/{en,ar}/scheduling.json` | the teacher's "Start as host" |
| `src/locales/{en,ar}/integrations.json` | strings |
| `src/test/integrations-fixtures.ts` | fixtures |
| tests next to each file | tests |

**Meta:** `CLAUDE.md`, `STATE.md`.

---

### Task 1: One Stripe client in the platform

**Files:**
- Create: `backend/etqan/platform/stripe.py`, `backend/etqan/platform/tests/test_stripe.py`
- Modify: `backend/etqan/gateways/providers/stripe.py`

**Interfaces:**
- Consumes: httpx (installed), respx's `respx_mock` fixture (installed, used by gateways tests).
- Produces: `etqan.platform.stripe.API` (`"https://api.stripe.com/v1"`), `STRIPE_VERSION`, `TIMEOUT`, `StripeError(status: int | None, *, error_type="", code="", kind="")`, `call(method: str, path: str, *, key: str, data: list[tuple] | None = None, idempotency: str = "", account: str = "") -> dict`. `etqan.gateways.providers.stripe.API` stays importable (gateways tests import it).

- [ ] **Step 1: Write the failing test**

Create `backend/etqan/platform/tests/test_stripe.py`:

```python
"""Plan D2: the one Stripe REST client, shared by B3's own keys and Etqan's
Connect platform. Form-encoded, Basic auth with the key, a pinned version;
it logs nothing and answers Stripe's error fields, never its words."""

import logging
from urllib.parse import parse_qsl

import httpx
import pytest

from etqan.platform import stripe

ACCOUNTS = f"{stripe.API}/accounts"


def test_a_post_is_form_encoded_with_the_key_version_and_headers(respx_mock):
    route = respx_mock.post(ACCOUNTS).mock(
        return_value=httpx.Response(200, json={"id": "acct_1"})
    )
    body = stripe.call(
        "POST",
        "/accounts",
        key="sk_test_<redacted>",
        data=[("type", "express"), ("metadata[academy]", "noor")],
        idempotency="etqan-connect-noor-AE",
        account="acct_9",
    )
    assert body == {"id": "acct_1"}
    request = route.calls[0].request
    assert parse_qsl(request.content.decode()) == [
        ("type", "express"),
        ("metadata[academy]", "noor"),
    ]
    assert request.headers["Stripe-Version"] == stripe.STRIPE_VERSION
    assert request.headers["Idempotency-Key"] == "etqan-connect-noor-AE"
    assert request.headers["Stripe-Account"] == "acct_9"
    assert request.headers["Authorization"].startswith("Basic ")


def test_a_get_has_no_body_and_no_optional_headers(respx_mock):
    route = respx_mock.get(f"{ACCOUNTS}/acct_1").mock(
        return_value=httpx.Response(200, json={"id": "acct_1"})
    )
    assert stripe.call("GET", "/accounts/acct_1", key="sk_test_<redacted>") == {"id": "acct_1"}
    request = route.calls[0].request
    assert request.content == b""
    assert "Idempotency-Key" not in request.headers
    assert "Stripe-Account" not in request.headers


def test_a_refusal_carries_stripes_fields(respx_mock):
    respx_mock.post(ACCOUNTS).mock(
        return_value=httpx.Response(
            400,
            json={"error": {"type": "invalid_request_error", "code": "country_unsupported"}},
        )
    )
    with pytest.raises(stripe.StripeError) as caught:
        stripe.call("POST", "/accounts", key="sk_test_<redacted>", data=[])
    assert (caught.value.status, caught.value.error_type, caught.value.code) == (
        400,
        "invalid_request_error",
        "country_unsupported",
    )


@pytest.mark.parametrize(
    "answer",
    [
        httpx.Response(502, text="<html>bad gateway</html>"),
        httpx.Response(500, json=["not", "an", "object"]),
    ],
)
def test_an_unreadable_refusal_has_empty_fields(respx_mock, answer):
    respx_mock.post(ACCOUNTS).mock(return_value=answer)
    with pytest.raises(stripe.StripeError) as caught:
        stripe.call("POST", "/accounts", key="sk_test_<redacted>", data=[])
    assert caught.value.status == answer.status_code
    assert (caught.value.error_type, caught.value.code) == ("", "")


def test_unreachable_is_status_none_with_the_error_kind(respx_mock):
    respx_mock.post(ACCOUNTS).mock(side_effect=httpx.ConnectError("down"))
    with pytest.raises(stripe.StripeError) as caught:
        stripe.call("POST", "/accounts", key="sk_test_<redacted>", data=[])
    assert (caught.value.status, caught.value.kind) == (None, "ConnectError")


def test_a_success_that_is_not_an_object_is_empty(respx_mock):
    respx_mock.get(ACCOUNTS).mock(return_value=httpx.Response(200, json=[1, 2]))
    assert stripe.call("GET", "/accounts", key="sk_test_<redacted>") == {}


def test_a_refusal_logs_no_key(respx_mock, caplog):
    caplog.set_level(logging.DEBUG)
    respx_mock.post(ACCOUNTS).mock(return_value=httpx.Response(401, json={}))
    with pytest.raises(stripe.StripeError):
        stripe.call("POST", "/accounts", key="sk_test_<redacted>", data=[])
    assert "sk_test_<redacted>" not in caplog.text
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$DJ pytest etqan/platform/tests/test_stripe.py -q`
Expected: FAIL — `ImportError: cannot import name 'stripe' from 'etqan.platform'`.

- [ ] **Step 3: Write minimal implementation**

Create `backend/etqan/platform/stripe.py`:

```python
"""Stripe's REST API (plan D2 of integrations slice 3), shared by online
payments on an academy's own keys (B3) and Stripe Connect on Etqan's
platform keys. Form-encoded bodies, Basic auth with the secret key, a pinned
API version. It logs nothing: each caller logs by Stripe's status, type and
code only, never a key or the request."""

from urllib.parse import urlencode

import httpx

API = "https://api.stripe.com/v1"
STRIPE_VERSION = "2024-06-20"
TIMEOUT = 20.0


class StripeError(Exception):
    """Stripe refused (``status`` its HTTP status, ``error_type`` and
    ``code`` its error's fields) or could not be reached (``status`` None,
    ``kind`` the transport error's class name)."""

    def __init__(
        self,
        status: int | None,
        *,
        error_type: str = "",
        code: str = "",
        kind: str = "",
    ):
        self.status = status
        self.error_type = error_type
        self.code = code
        self.kind = kind
        super().__init__(f"{status} {error_type} {code} {kind}".strip())


def _json(response) -> dict:
    try:
        body = response.json()
    except ValueError:
        return {}
    return body if isinstance(body, dict) else {}


def call(  # noqa: PLR0913 -- keyword-only; one Stripe request's parts
    method: str,
    path: str,
    *,
    key: str,
    data: list[tuple] | None = None,
    idempotency: str = "",
    account: str = "",
) -> dict:
    """One request to Stripe; the answer's JSON object (``{}`` when it is
    not one). ``account`` acts on a connected account (`Stripe-Account`)."""
    headers = {"Stripe-Version": STRIPE_VERSION}
    if idempotency:
        headers["Idempotency-Key"] = idempotency
    if account:
        headers["Stripe-Account"] = account
    content = None
    if method == "POST":
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        content = urlencode(data or [])
    try:
        response = httpx.request(
            method,
            f"{API}{path}",
            content=content,
            auth=(key, ""),
            headers=headers,
            timeout=TIMEOUT,
        )
    except httpx.HTTPError as exc:
        raise StripeError(None, kind=type(exc).__name__) from None
    if response.is_success:
        return _json(response)
    error = _json(response).get("error")
    if not isinstance(error, dict):
        error = {}
    raise StripeError(
        response.status_code,
        error_type=str(error.get("type") or ""),
        code=str(error.get("code") or ""),
    )
```

In `backend/etqan/gateways/providers/stripe.py`, replace the imports, constants, `_json` and `StripeProvider._post` (everything from `import logging` through the end of `_post`) with:

```python
import logging

from etqan.gateways.providers.base import ProviderError
from etqan.gateways.providers.base import Session
from etqan.gateways.services.accounts import secret_of
from etqan.platform import stripe

API = stripe.API  # kept: B3's tests build their URLs from it
FEE_LINE = "Service fee"
logger = logging.getLogger(__name__)


# L12: our fee rounding (D5) makes only the total a multiple of 10 for
# 3-decimal currencies; whether Stripe needs each line's unit_amount to be one
# too is unverified (owner's live smoke test).
def _line(index: int, *, name: str, amount: int, currency: str) -> list[tuple]:
    prefix = f"line_items[{index}]"
    return [
        (f"{prefix}[price_data][currency]", currency.lower()),
        (f"{prefix}[price_data][unit_amount]", str(amount)),
        (f"{prefix}[price_data][product_data][name]", name),
        (f"{prefix}[quantity]", "1"),
    ]


class StripeProvider:
    def _post(self, account, path: str, data: list[tuple], *, idempotency: str = ""):
        try:
            return stripe.call(
                "POST", path, key=secret_of(account), data=data, idempotency=idempotency
            )
        except stripe.StripeError as exc:
            if exc.status is None:
                logger.warning("Stripe unreachable: %s", exc.kind)
                raise ProviderError("error") from None
            logger.warning(
                "Stripe refused %s: %s %s %s",
                path,
                exc.status,
                exc.error_type,
                exc.code,
            )
            reason = "amount_too_small" if exc.code == "amount_too_small" else "error"
            raise ProviderError(reason) from None
```

Keep the module docstring, `create` and `expire` as they are (drop the now-unused `urlencode` and `httpx` imports and the old `STRIPE_VERSION`/`TIMEOUT` constants; ruff will flag any leftover).

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DJ pytest etqan/platform/tests/test_stripe.py etqan/gateways -q`
Expected: PASS — the new client tests and every B3 gateways test unchanged (same URLs, bodies, headers, log lines and reasons).

- [ ] **Step 5: Commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports
git -C backend add etqan/platform/stripe.py etqan/platform/tests/test_stripe.py etqan/gateways/providers/stripe.py
git -C backend commit -m "refactor(platform): one Stripe REST client shared by gateways and Connect" -m "$TRAILER"
```

---

### Task 2: Webhook routes, payments never an own account, and the `zoom_api` switch built

**Files:**
- Modify: `backend/etqan/integrations/models.py`, `backend/etqan/integrations/services/resolver.py`, `backend/etqan/integrations/services/__init__.py`, `backend/etqan/integrations/admin.py` (register the route read-only), `backend/etqan/platform/features.py`, `backend/etqan/platform/tests/test_features.py`, `backend/etqan/integrations/tests/test_resolver.py`
- Create: `backend/etqan/integrations/services/routes.py`, `backend/etqan/integrations/migrations/0003_webhookroute.py` (generated), `backend/etqan/integrations/tests/test_routes.py`

**Interfaces:**
- Consumes: `PlatformAccount`, `AcademyAccount`, `resolve`, `clear_cache` (slice 1).
- Produces: model `WebhookRoute(kind, ref, academy, created_at)` with `WebhookRoute.Kind` (`ZOOM_MEETING = "zoom_meeting"`, `STRIPE_ACCOUNT = "stripe_account"`); `integrations.services.ZOOM_MEETING`, `STRIPE_ACCOUNT`, `add_route(kind: str, ref: str) -> None` (in an academy; `ValueError` in public), `route_schema(kind: str, ref: str) -> str | None`; resolver constant `NOT_OWN = frozenset({"payments"})`; `features.get("zoom_api").built is True`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/integrations/tests/test_routes.py`:

```python
"""Plan D3: which academy a Zoom meeting or a Stripe Connect account
belongs to, kept in the public schema for Etqan's webhook endpoints."""

import pytest
from django.db import connection
from django_tenants.utils import tenant_context

from etqan.integrations import services
from etqan.integrations.models import WebhookRoute

pytestmark = pytest.mark.django_db


def test_a_route_names_the_academy_it_was_added_in(tenants):
    services.add_route(services.ZOOM_MEETING, "81234567890")
    connection.set_schema_to_public()
    assert services.route_schema(services.ZOOM_MEETING, "81234567890") == (
        tenants.main.schema_name
    )


def test_adding_again_keeps_the_first_academy(tenants):
    services.add_route(services.STRIPE_ACCOUNT, "acct_1")
    with tenant_context(tenants.other):
        services.add_route(services.STRIPE_ACCOUNT, "acct_1")
    route = WebhookRoute.objects.get(kind="stripe_account", ref="acct_1")
    assert route.academy_id == tenants.main.pk


def test_kinds_do_not_mix_and_unknown_refs_are_none():
    services.add_route(services.ZOOM_MEETING, "1")
    assert services.route_schema(services.STRIPE_ACCOUNT, "1") is None
    assert services.route_schema(services.ZOOM_MEETING, "2") is None


def test_the_public_schema_has_no_academy_to_route_to():
    connection.set_schema_to_public()
    with pytest.raises(ValueError, match="academy"):
        services.add_route(services.ZOOM_MEETING, "1")
```

Append to `backend/etqan/integrations/tests/test_resolver.py`:

```python
def test_the_payments_row_is_never_the_academys_own_account(set_features):
    """Slice 3 plan D12: the academy's own payments account is B3's gateway
    keys; the payments row here is its Connect account on Etqan's platform."""
    switch_on("payments")
    set_features(invoices=True, online_payments=True)
    AcademyAccount.objects.create(
        service="payments",
        enabled=True,
        config={"account_id": "acct_1", "status": "active"},
    )
    services.clear_cache()
    assert services.resolve("payments").source == "etqan"
```

In `backend/etqan/platform/tests/test_features.py`, add `"zoom_api": False,` to the `BUILT` dict directly after the line `"payment_receipts": False,`, and append:

```python
def test_zoom_api_is_built_and_off_by_default():
    """Integrations slice 3 (plan D11): Zoom meetings are built."""
    feature = features.get("zoom_api")
    assert (feature.built, feature.default, feature.group) == (True, False, "platform")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DJ pytest etqan/integrations/tests/test_routes.py etqan/integrations/tests/test_resolver.py etqan/platform/tests/test_features.py -q`
Expected: FAIL — `ImportError: cannot import name 'WebhookRoute'`, the payments test answering `academy`, and `zoom_api` not built.

- [ ] **Step 3: Write minimal implementation**

Append to `backend/etqan/integrations/models.py` (add `from django.conf import settings` to its imports):

```python
class WebhookRoute(models.Model):
    """Which academy an outside service's id belongs to (slice 3 plan D3): a
    Zoom meeting made on Etqan's Zoom account, an academy's Stripe Connect
    account. Etqan's one webhook endpoint per provider reads it in the public
    schema to enter the right academy. Never deleted: late events still
    land."""

    class Kind(models.TextChoices):
        ZOOM_MEETING = "zoom_meeting", "Zoom meeting"
        STRIPE_ACCOUNT = "stripe_account", "Stripe Connect account"

    kind = models.CharField(max_length=20, choices=Kind.choices)
    ref = models.CharField(max_length=255)
    academy = models.ForeignKey(
        settings.TENANT_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["kind", "ref"], name="integrations_route_unique"
            )
        ]

    def __str__(self):
        return f"WebhookRoute<{self.kind} {self.ref}>"
```

Run: `$DJ python manage.py makemigrations integrations --name webhookroute`
Expected: `integrations/migrations/0003_webhookroute.py` creating the model.

Create `backend/etqan/integrations/services/routes.py`:

```python
"""Webhook routes (slice 3 plan D3): an outside id → its academy, in the
public schema. Written inside the academy that made the thing; read by
Etqan's endpoints on the base domain."""

from django.db import connection
from django_tenants.utils import get_public_schema_name

from etqan.integrations.models import WebhookRoute

ZOOM_MEETING = WebhookRoute.Kind.ZOOM_MEETING.value
STRIPE_ACCOUNT = WebhookRoute.Kind.STRIPE_ACCOUNT.value


def add_route(kind: str, ref: str) -> None:
    """Route ``ref`` to the academy on the connection; a ref already routed
    keeps its first academy."""
    if connection.schema_name == get_public_schema_name():
        raise ValueError("A route needs an academy on the connection.")
    WebhookRoute.objects.get_or_create(
        kind=kind, ref=ref, defaults={"academy_id": connection.tenant.pk}
    )


def route_schema(kind: str, ref: str) -> str | None:
    """The schema of the academy ``ref`` belongs to, or None."""
    route = (
        WebhookRoute.objects.filter(kind=kind, ref=ref)
        .select_related("academy")
        .first()
    )
    return route.academy.schema_name if route else None
```

In `backend/etqan/integrations/services/resolver.py`, below `CACHE = "_etqan_integrations"` add:

```python
# Slice 3 plan D12: the academy's own payments account is B3's gateway keys
# (gateways checks them first); the payments row here is its Stripe Connect
# account on Etqan's platform, which is Etqan's default, never step 1.
NOT_OWN = frozenset({"payments"})
```

and in `_resolve` change the first condition to:

```python
    if connection.schema_name != get_public_schema_name() and service not in NOT_OWN:
```

In `backend/etqan/integrations/services/__init__.py` add the imports (sorted with the others) and `__all__` entries for `STRIPE_ACCOUNT`, `ZOOM_MEETING`, `add_route`, `route_schema` from `etqan.integrations.services.routes`.

In `backend/etqan/integrations/admin.py`, register the route read-only for Etqan staff (append; import `WebhookRoute` from `etqan.integrations.models`):

```python
@admin.register(WebhookRoute)
class WebhookRouteAdmin(admin.ModelAdmin):
    """Slice 3 plan D3: read-only; written by meetings and Connect."""

    list_display = ["kind", "ref", "academy", "created_at"]
    list_filter = ["kind"]
    search_fields = ["ref"]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
```

In `backend/etqan/platform/features.py`, replace

```python
    _later("zoom_api", "Zoom API", "ربط Zoom API", "platform"),
```

with

```python
    # Integrations slice 3 (plan D11): Zoom meetings for sessions, off by default.
    _built("zoom_api", "Zoom API", "ربط Zoom API", "platform", default=False),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DJ pytest etqan/integrations etqan/platform/tests/test_features.py --create-db -q`
Expected: PASS. If `test_the_defaults_match_the_spec` reports an order difference, move `"zoom_api": False,` in `BUILT` to the position `features.BUILT` lists it at (registry order).

- [ ] **Step 5: Commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports
git -C backend add etqan/integrations etqan/platform/features.py etqan/platform/tests/test_features.py
git -C backend commit -m "feat(integrations): webhook routes, payments row is Connect, zoom_api built" -m "$TRAILER"
```

---

### Task 3: The Zoom provider — accounts, token, meetings

**Files:**
- Create: `backend/etqan/integrations/providers/zoom.py`, `backend/etqan/integrations/providers/video.py`, `backend/etqan/integrations/tests/test_zoom.py`
- Modify: `backend/etqan/integrations/providers/__init__.py`, `backend/etqan/integrations/providers/base.py`, `backend/etqan/integrations/services/accounts.py` (`apply_platform_change`), `backend/etqan/integrations/admin.py` (`FORM_FIELDS`, help text), `backend/etqan/integrations/tests/conftest.py`, `backend/etqan/integrations/tests/test_providers.py`

**Interfaces:**
- Consumes: `ProbeError`, `ValidationError`, `connect`/`probe`/`apply_platform_change` (slice 1); Django's cache (Redis; locmem in tests).
- Produces: `etqan.integrations.providers.zoom`: `TOKEN_URL`, `API`, `ZoomError(status: int | None, reason: str = "error")` (`reason` ∈ `"refused"`, `"error"`), `access_token(config: dict, secrets: dict, *, fresh: bool = False) -> str`, `create_meeting(config: dict, secrets: dict, *, host: str, topic: str, starts_at: datetime, minutes: int) -> dict` (`{"id": str, "join_url": str}`), `get_meeting(config: dict, secrets: dict, meeting_id: str) -> dict` (`{"start_url": str, "join_url": str}`; D23); `ZoomProvider` (service `video`, `connectable = True`, `empty_is_default = False`; own config `{account_id, client_id, host_user}`, Etqan's `{account_id, client_id, host_users}`); test fixtures `ZOOM` (fields), `ZOOM_CONFIG`, `ETQAN_HOSTS` (`["host1@etqan.test", "host2@etqan.test"]`), `zoom_default` (Etqan's video default on with that pool, `zoom_api` on), `own_zoom` (the academy's own Zoom account), `fresh_cache` (autouse in the Zoom tests).

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/integrations/tests/conftest.py`:

```python
ZOOM = {
    "account_id": "zoomacct123",
    "client_id": "zoomclient456",
    "client_secret": "zoom-client-secret-7890",
    "host_user": "me",
}
ZOOM_CONFIG = {key: value for key, value in ZOOM.items() if key != "client_secret"}
ETQAN_ZOOM_SECRETS = {
    "client_secret": "etqan-zoom-secret-0000",
    "webhook_secret": "etqan-zoom-webhook-token",
}
ETQAN_HOSTS = ["host1@etqan.test", "host2@etqan.test"]


@pytest.fixture
def zoom_default(set_features):
    """Slice 3: Etqan's Zoom app as the video default, ``zoom_api`` on."""
    from etqan.integrations.models import PlatformAccount  # noqa: PLC0415

    PlatformAccount.objects.filter(service="video").update(
        enabled=True,
        config={"account_id": "etqanacct", "client_id": "etqanclient", "host_users": ETQAN_HOSTS},
        secret_enc=services.write_secrets(ETQAN_ZOOM_SECRETS),
    )
    set_features(zoom_api=True)
    services.clear_cache()


@pytest.fixture
def own_zoom(admin_user):
    return services.connect("video", fields=dict(ZOOM), by=admin_user)


@pytest.fixture
def fresh_cache():
    """Zoom tokens live in Django's cache (plan D5); locmem outlives a test."""
    from django.core.cache import cache  # noqa: PLC0415

    cache.clear()
    yield
    cache.clear()
```

Create `backend/etqan/integrations/tests/test_zoom.py`:

```python
"""Slice 3 plan D5–D6: a Zoom Server-to-Server account (fields, last four,
token probe) and the meeting it creates. Zoom is answered by respx."""

import json
import logging
from datetime import UTC
from datetime import datetime

import httpx
import pytest

from etqan.integrations import providers
from etqan.integrations import services
from etqan.integrations.models import PlatformAccount
from etqan.integrations.providers import zoom
from etqan.integrations.tests.conftest import ZOOM
from etqan.integrations.tests.conftest import ZOOM_CONFIG
from etqan.platform.exceptions import ValidationError

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("fresh_cache")]
VIDEO = providers.get("video")
MEETINGS = f"{zoom.API}/users/me/meetings"
SECRETS = {"client_secret": ZOOM["client_secret"]}
START = datetime(2026, 6, 1, 10, 0, tzinfo=UTC)


def token_ok(respx_mock, token="tok-1", expires_in=3599):
    return respx_mock.post(zoom.TOKEN_URL).mock(
        return_value=httpx.Response(
            200, json={"access_token": token, "expires_in": expires_in}
        )
    )


def test_the_fields_become_config_and_the_secret():
    config, values = VIDEO.clean(dict(ZOOM), stored={})
    assert (config, values) == (ZOOM_CONFIG, SECRETS)
    assert VIDEO.last4(values) == "7890"
    assert VIDEO.last4({"client_secret": "short"}) == ""


def test_host_user_defaults_to_me_and_takes_an_email():
    config, _ = VIDEO.clean({**ZOOM, "host_user": ""}, stored={})
    assert config["host_user"] == "me"
    config, _ = VIDEO.clean({**ZOOM, "host_user": "host@noor.test"}, stored={})
    assert config["host_user"] == "host@noor.test"
    with pytest.raises(ValidationError) as caught:
        VIDEO.clean({**ZOOM, "host_user": "not an email"}, stored={})
    assert caught.value.field == "host_user"


@pytest.mark.parametrize("missing", ["account_id", "client_id", "client_secret"])
def test_each_credential_is_required(missing):
    with pytest.raises(ValidationError) as caught:
        VIDEO.clean({**ZOOM, missing: ""}, stored={})
    assert caught.value.field == missing


def test_a_blank_secret_keeps_the_stored_one():
    _, values = VIDEO.clean({**ZOOM, "client_secret": ""}, stored=SECRETS)
    assert values == SECRETS


def test_etqans_default_has_a_host_pool_and_a_webhook_secret():
    """Owner D21: Etqan's meetings go to a pool of licensed hosts."""
    fields = {**ZOOM, "webhook_secret": "token-1", "host_users": [" A@etqan.test ", "me"]}
    assert "webhook_secret" not in VIDEO.clean(fields, stored={})[1]
    config, values = VIDEO.clean(fields, stored={}, own=False)
    assert config == {
        "account_id": "zoomacct123",
        "client_id": "zoomclient456",
        "host_users": ["a@etqan.test", "me"],
    }
    assert values["webhook_secret"] == "token-1"


@pytest.mark.parametrize(
    "hosts",
    [[], "host@etqan.test", ["not an email"], ["a@etqan.test", "a@etqan.test"], ["h@e.test"] * 51],
)
def test_the_pool_is_a_list_of_distinct_hosts(hosts):
    with pytest.raises(ValidationError) as caught:
        VIDEO.clean({**ZOOM, "host_users": hosts}, stored={}, own=False)
    assert caught.value.field == "host_users"


def test_the_probe_asks_for_a_fresh_token(respx_mock):
    route = token_ok(respx_mock)
    VIDEO.probe(config=ZOOM_CONFIG, secrets=SECRETS, tester_email="a@noor.test")
    VIDEO.probe(config=ZOOM_CONFIG, secrets=SECRETS, tester_email="a@noor.test")
    assert route.call_count == 2
    request = route.calls[0].request
    assert request.headers["Authorization"].startswith("Basic ")
    assert b"grant_type=account_credentials" in request.content
    assert b"account_id=zoomacct123" in request.content


@pytest.mark.parametrize(
    ("answer", "message"),
    [
        (httpx.Response(400, json={"reason": "Invalid client"}), "Zoom refused this account id, client id or secret."),
        (httpx.Response(401, json={}), "Zoom refused this account id, client id or secret."),
        (httpx.Response(503, text="down"), "Could not reach Zoom. Try again in a moment."),
        (httpx.ConnectError("down"), "Could not reach Zoom. Try again in a moment."),
    ],
)
def test_a_failed_probe_says_why_in_our_words(respx_mock, caplog, answer, message):
    caplog.set_level(logging.INFO)
    if isinstance(answer, Exception):
        respx_mock.post(zoom.TOKEN_URL).mock(side_effect=answer)
    else:
        respx_mock.post(zoom.TOKEN_URL).mock(return_value=answer)
    with pytest.raises(providers.ProbeError) as caught:
        VIDEO.probe(config=ZOOM_CONFIG, secrets=SECRETS, tester_email="a@noor.test")
    assert caught.value.message == message
    assert ZOOM["client_secret"] not in caplog.text


def test_a_meeting_is_created_with_a_cached_token(respx_mock):
    token = token_ok(respx_mock)
    meetings = respx_mock.post(MEETINGS).mock(
        return_value=httpx.Response(
            201, json={"id": 81234567890, "join_url": "https://zoom.us/j/81234567890?pwd=x"}
        )
    )
    for _ in range(2):
        made = zoom.create_meeting(
            ZOOM_CONFIG, SECRETS, host="me", topic="Tajweed · Bilal", starts_at=START, minutes=45
        )
    assert made == {"id": "81234567890", "join_url": "https://zoom.us/j/81234567890?pwd=x"}
    assert token.call_count == 1
    request = meetings.calls[0].request
    assert request.headers["Authorization"] == "Bearer tok-1"
    assert json.loads(request.content) == {
        "topic": "Tajweed · Bilal",
        "type": 2,
        "start_time": "2026-06-01T10:00:00Z",
        "duration": 45,
        "timezone": "UTC",
        "settings": {
            "join_before_host": True,
            "jbh_time": 0,
            "waiting_room": False,
            "approval_type": 2,
            "auto_recording": "none",
        },
    }


def test_a_host_email_is_the_meetings_user(respx_mock):
    token_ok(respx_mock)
    route = respx_mock.post(f"{zoom.API}/users/host@noor.test/meetings").mock(
        return_value=httpx.Response(201, json={"id": 1, "join_url": "https://zoom.us/j/1"})
    )
    zoom.create_meeting(
        ZOOM_CONFIG, SECRETS, host="host@noor.test", topic="t", starts_at=START, minutes=30
    )
    assert route.called


def test_a_meetings_host_link_is_fetched_fresh(respx_mock):
    """Owner D23: the start link comes from Zoom when asked, never kept."""
    token_ok(respx_mock)
    route = respx_mock.get(f"{zoom.API}/meetings/81234567890").mock(
        return_value=httpx.Response(
            200,
            json={
                "id": 81234567890,
                "start_url": "https://zoom.us/s/81234567890?zak=abc",
                "join_url": "https://zoom.us/j/81234567890",
            },
        )
    )
    assert zoom.get_meeting(ZOOM_CONFIG, SECRETS, "81234567890") == {
        "start_url": "https://zoom.us/s/81234567890?zak=abc",
        "join_url": "https://zoom.us/j/81234567890",
    }
    assert route.calls[0].request.headers["Authorization"] == "Bearer tok-1"


@pytest.mark.parametrize(
    "answer",
    [httpx.Response(404, json={"code": 3001}), httpx.Response(200, json={"id": 1})],
)
def test_an_unreadable_meeting_is_an_error(respx_mock, answer):
    token_ok(respx_mock)
    respx_mock.get(f"{zoom.API}/meetings/1").mock(return_value=answer)
    with pytest.raises(zoom.ZoomError):
        zoom.get_meeting(ZOOM_CONFIG, SECRETS, "1")


def test_a_rejected_token_is_dropped_and_the_meeting_refused(respx_mock):
    token = token_ok(respx_mock)
    respx_mock.post(MEETINGS).mock(return_value=httpx.Response(401, json={"code": 124}))
    with pytest.raises(zoom.ZoomError):
        zoom.create_meeting(ZOOM_CONFIG, SECRETS, host="me", topic="t", starts_at=START, minutes=30)
    with pytest.raises(zoom.ZoomError):
        zoom.create_meeting(ZOOM_CONFIG, SECRETS, host="me", topic="t", starts_at=START, minutes=30)
    assert token.call_count == 2  # asked again after the 401


@pytest.mark.parametrize(
    "answer",
    [
        httpx.Response(201, json={"id": 1}),
        httpx.Response(201, json={"id": 1, "join_url": "https://zoom.us/j/" + "x" * 200}),
        httpx.Response(429, json={"code": 429}),
    ],
)
def test_an_unusable_meeting_answer_is_an_error(respx_mock, answer):
    token_ok(respx_mock)
    respx_mock.post(MEETINGS).mock(return_value=answer)
    with pytest.raises(zoom.ZoomError):
        zoom.create_meeting(ZOOM_CONFIG, SECRETS, host="me", topic="t", starts_at=START, minutes=30)


def test_connecting_zoom_returns_the_card_without_the_secret(api_for):
    resp = api_for("admin").put("/api/v1/integrations/video/", ZOOM, format="json")
    assert resp.status_code == 200
    body = resp.json()
    assert body["using"] == "academy"
    assert body["own"]["config"] == ZOOM_CONFIG
    assert body["own"]["secret_last4"] == "7890"
    assert ZOOM["client_secret"] not in resp.content.decode()


def test_etqans_video_default_needs_its_fields_only_when_used():
    account = PlatformAccount.objects.get(service="video")
    # Untouched and off: saving changes nothing and asks for nothing.
    assert services.apply_platform_change(
        account, enabled=False, config={}, new_secrets=None, clear_secrets=False
    ) == {}
    with pytest.raises(ValidationError) as caught:
        services.apply_platform_change(
            account, enabled=True, config={}, new_secrets=None, clear_secrets=False
        )
    assert caught.value.field == "account_id"
    config = services.apply_platform_change(
        account,
        enabled=True,
        config={"account_id": "a1", "client_id": "c1", "host_users": ["h@etqan.test"]},
        new_secrets={"client_secret": "etqan-zoom-secret-0000", "webhook_secret": "tok"},
        clear_secrets=False,
    )
    assert config == {"account_id": "a1", "client_id": "c1", "host_users": ["h@etqan.test"]}
    assert services.read_secrets(account.secret_enc)["webhook_secret"] == "tok"
```

In `backend/etqan/integrations/tests/test_providers.py`, rename `test_every_service_has_a_provider_and_only_email_connects` to `test_every_service_has_a_provider_and_which_connect` and set video's entry (the fourth) to `True`: `[False, True, False, True, False]` (whatsapp, email, payments, video, ai). If B10a has merged, its last entry is already `True`: keep it.

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DJ pytest etqan/integrations/tests/test_zoom.py -q`
Expected: FAIL — `ImportError: cannot import name 'zoom' from 'etqan.integrations.providers'`.

- [ ] **Step 3: Write minimal implementation**

Create `backend/etqan/integrations/providers/zoom.py`:

```python
"""Zoom's REST API with Server-to-Server OAuth (spec §4 video row, slice 3
plan D5–D6): an account's token, cached until shortly before it expires,
then one scheduled meeting per class. httpx, no SDK; failures are logged by
status only, never a secret or a token."""

import hashlib
import logging
from datetime import UTC
from datetime import datetime
from urllib.parse import quote

import httpx
from django.core.cache import cache

TOKEN_URL = "https://zoom.us/oauth/token"
API = "https://api.zoom.us/v2"
TIMEOUT = 15.0
TOKEN_MARGIN = 300  # seconds before Zoom's expiry that we stop using a token
DEFAULT_TTL = 600
TOPIC_LENGTH = 200
URL_LENGTH = 200  # Session.meeting_url's max_length
REFUSED = (400, 401, 403)
logger = logging.getLogger(__name__)


class ZoomError(Exception):
    """Zoom refused (``reason`` ``"refused"``: the credentials) or failed
    (``"error"``); ``status`` is None when Zoom could not be reached."""

    def __init__(self, status: int | None, reason: str = "error"):
        self.status = status
        self.reason = reason
        super().__init__(f"{status} {reason}")


def _json(response) -> dict:
    try:
        body = response.json()
    except ValueError:
        return {}
    return body if isinstance(body, dict) else {}


def _cache_key(config: dict, secrets: dict) -> str:
    raw = ":".join(
        (
            config.get("account_id", ""),
            config.get("client_id", ""),
            secrets.get("client_secret", ""),
        )
    )
    return "integrations:zoom-token:" + hashlib.sha256(raw.encode()).hexdigest()


def access_token(config: dict, secrets: dict, *, fresh: bool = False) -> str:
    """The account's bearer token; ``fresh`` skips the cache (the probe)."""
    key = _cache_key(config, secrets)
    if not fresh:
        cached = cache.get(key)
        if cached:
            return cached
    try:
        response = httpx.post(
            TOKEN_URL,
            data={
                "grant_type": "account_credentials",
                "account_id": config.get("account_id", ""),
            },
            auth=(config.get("client_id", ""), secrets.get("client_secret", "")),
            timeout=TIMEOUT,
        )
    except httpx.HTTPError as exc:
        logger.warning("Zoom unreachable for a token: %s", type(exc).__name__)
        raise ZoomError(None) from None
    body = _json(response)
    token = body.get("access_token")
    if not response.is_success or not isinstance(token, str) or not token:
        logger.warning("Zoom refused a token: %s", response.status_code)
        reason = "refused" if response.status_code in REFUSED else "error"
        raise ZoomError(response.status_code, reason)
    expires = body.get("expires_in")
    ttl = (
        max(expires - TOKEN_MARGIN, 60)
        if isinstance(expires, int) and not isinstance(expires, bool)
        else DEFAULT_TTL
    )
    cache.set(key, token, ttl)
    return token


def create_meeting(  # noqa: PLR0913 -- keyword-only; one meeting's parts
    config: dict,
    secrets: dict,
    *,
    host: str,
    topic: str,
    starts_at: datetime,
    minutes: int,
) -> dict:
    """Plan D6: a scheduled meeting under ``host`` (a Zoom user's email or
    ``me``) that anyone may join before the host; ``{"id", "join_url"}``.
    Raises ZoomError."""
    token = access_token(config, secrets)
    body = {
        "topic": topic[:TOPIC_LENGTH],
        "type": 2,
        "start_time": starts_at.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "duration": minutes,
        "timezone": "UTC",
        "settings": {
            "join_before_host": True,
            "jbh_time": 0,
            "waiting_room": False,
            "approval_type": 2,
            "auto_recording": "none",
        },
    }
    try:
        response = httpx.post(
            f"{API}/users/{quote(host or 'me', safe='@.')}/meetings",
            json=body,
            headers={"Authorization": f"Bearer {token}"},
            timeout=TIMEOUT,
        )
    except httpx.HTTPError as exc:
        logger.warning("Zoom unreachable for a meeting: %s", type(exc).__name__)
        raise ZoomError(None) from None
    if response.status_code == 401:  # noqa: PLR2004 -- the token went stale
        cache.delete(_cache_key(config, secrets))
    data = _json(response)
    url = data.get("join_url")
    if (
        not response.is_success
        or not data.get("id")
        or not isinstance(url, str)
        or not url.startswith("https://")
        or len(url) > URL_LENGTH
    ):
        logger.warning(
            "Zoom refused a meeting: %s %s", response.status_code, data.get("code", "")
        )
        raise ZoomError(response.status_code)
    return {"id": str(data["id"]), "join_url": url}


def get_meeting(config: dict, secrets: dict, meeting_id: str) -> dict:
    """Owner D23: the meeting's host (start) link, read now; it is a host
    credential that expires within hours, so callers never store or log it.
    ``{"start_url", "join_url"}``. Raises ZoomError."""
    token = access_token(config, secrets)
    try:
        response = httpx.get(
            f"{API}/meetings/{quote(meeting_id, safe='')}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=TIMEOUT,
        )
    except httpx.HTTPError as exc:
        logger.warning("Zoom unreachable for a meeting: %s", type(exc).__name__)
        raise ZoomError(None) from None
    if response.status_code == 401:  # noqa: PLR2004 -- the token went stale
        cache.delete(_cache_key(config, secrets))
    data = _json(response)
    start, join = data.get("start_url"), data.get("join_url")
    if (
        not response.is_success
        or not isinstance(start, str)
        or not start.startswith("https://")
        or not isinstance(join, str)
    ):
        logger.warning("Zoom refused to read a meeting: %s", response.status_code)
        raise ZoomError(response.status_code)
    return {"start_url": start, "join_url": join}
```

Create `backend/etqan/integrations/providers/video.py`:

```python
"""Video meetings (spec §4 video row, slice 3 plan D5): an account is a
Zoom Server-to-Server OAuth app — account id, client id, client secret and
the Zoom user who hosts. Etqan's default also keeps Zoom's webhook secret
token, which signs the meeting-ended events it meters."""

from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.validators import validate_email

from etqan.integrations.providers import zoom
from etqan.integrations.providers.base import ProbeError
from etqan.platform.exceptions import ValidationError

MAX_ID = 64
MAX_SECRET = 128
MAX_EMAIL = 254
LAST4_FROM = 12  # slice 1 plan D5
ME = "me"
MAX_HOSTS = 50  # owner D21: Etqan's pool


def _text(fields: dict, name: str, limit: int, *, required: bool = False) -> str:
    value = fields.get(name, "")
    if not isinstance(value, str):
        raise ValidationError("Enter text.", field=name)
    value = value.strip()
    if required and not value:
        raise ValidationError("This field is required.", field=name)
    if len(value) > limit:
        raise ValidationError(f"Use at most {limit} characters.", field=name)
    return value


def _secret(fields: dict, stored: dict, name: str, *, required: bool) -> str:
    value = fields.get(name, "")
    if not isinstance(value, str) or len(value) > MAX_SECRET:
        raise ValidationError(
            f"Enter it as text, at most {MAX_SECRET} characters.", field=name
        )
    value = value.strip() or stored.get(name, "")
    if required and not value:
        raise ValidationError("This field is required.", field=name)
    return value


def _is_host(value: str) -> bool:
    if value == ME:
        return True
    try:
        validate_email(value)
    except DjangoValidationError:
        return False
    return True


def _host(fields: dict) -> str:
    value = _text(fields, "host_user", MAX_EMAIL) or ME
    if not _is_host(value):
        raise ValidationError(
            "Enter me, or the email address of the Zoom user who hosts.",
            field="host_user",
        )
    return value


def _hosts(fields: dict) -> list[str]:
    """Owner D21: Etqan's pool of licensed Zoom users, in the order tried."""
    value = fields.get("host_users")
    message = f"Enter a list of 1 to {MAX_HOSTS} different Zoom users (me or emails)."
    if not isinstance(value, list) or not 1 <= len(value) <= MAX_HOSTS:
        raise ValidationError(message, field="host_users")
    hosts = []
    for item in value:
        host = item.strip().lower() if isinstance(item, str) else ""
        if not host or len(host) > MAX_EMAIL or not _is_host(host) or host in hosts:
            raise ValidationError(message, field="host_users")
        hosts.append(host)
    return hosts


class ZoomProvider:
    service = "video"
    connectable = True
    # Plan D5: an empty account is no account (unlike email's default).
    empty_is_default = False

    def clean(
        self, fields: dict, *, stored: dict, own: bool = True
    ) -> tuple[dict, dict]:
        config = {
            "account_id": _text(fields, "account_id", MAX_ID, required=True),
            "client_id": _text(fields, "client_id", MAX_ID, required=True),
        }
        if own:
            config["host_user"] = _host(fields)
        else:
            config["host_users"] = _hosts(fields)
        values = {"client_secret": _secret(fields, stored, "client_secret", required=True)}
        if not own:
            webhook = _secret(fields, stored, "webhook_secret", required=False)
            if webhook:
                values["webhook_secret"] = webhook
        return config, values

    def last4(self, values: dict) -> str:
        secret = values.get("client_secret", "")
        return secret[-4:] if len(secret) >= LAST4_FROM else ""

    def probe(self, *, config: dict, secrets: dict, tester_email: str) -> None:
        """Spec §3.3: request a Zoom token."""
        try:
            zoom.access_token(config, secrets, fresh=True)
        except zoom.ZoomError as exc:
            if exc.reason == "refused":
                raise ProbeError(
                    "Zoom refused this account id, client id or secret."
                ) from None
            raise ProbeError("Could not reach Zoom. Try again in a moment.") from None
```

In `backend/etqan/integrations/providers/__init__.py`, import `ZoomProvider` from `etqan.integrations.providers.video`, replace the `"video": NotYet(...)` entry with `"video": ZoomProvider(),`, and add `"ZoomProvider"` to `__all__` (keep B10a's `AiProvider` lines if present).

In `backend/etqan/integrations/providers/base.py`, add to the `Provider` protocol, below `connectable: bool`:

```python
    # Slice 3: True when an empty Etqan default means "use what is built in"
    # (email: today's sending), so the platform admin skips the field rules
    # on an empty config. A provider without the attribute counts as True.
    empty_is_default: bool
```

In `backend/etqan/integrations/services/accounts.py` `apply_platform_change`, replace

```python
    if config and provider.connectable:
        config, values = provider.clean({**config, **values}, stored=stored, own=False)
```

with

```python
    # Slice 3: email's (and AI's) empty default is the built-in one; Zoom and
    # Stripe are checked as soon as anything is entered or they are switched on.
    blank = not config and (
        getattr(provider, "empty_is_default", True) or (not values and not enabled)
    )
    if provider.connectable and not blank:
        config, values = provider.clean({**config, **values}, stored=stored, own=False)
```

In `backend/etqan/integrations/admin.py`, extend `FORM_FIELDS` (keep B10a's `"api_key"` entry if present):

```python
FORM_FIELDS = {
    "password": "secret",
    "client_secret": "secret",
    "webhook_secret": "secret",
    "account_id": "config",
    "client_id": "config",
    "host_user": "config",
    "host_users": "config",
}
```

and extend the `secret` field's `help_text` with the Zoom shape (keep B10a's AI sentence if present):

```python
        help_text=(
            'Write-only. A JSON object of text: {"password": "…"} for email; '
            '{"client_secret": "…", "webhook_secret": "…"} for Zoom (the '
            "webhook secret is the app's Secret Token; the config lists the "
            'pool: {"account_id": "…", "client_id": "…", "host_users": ["…"]}). '
            "Blank keeps what is stored."
        ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DJ pytest etqan/integrations -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports
git -C backend add etqan/integrations
git -C backend commit -m "feat(integrations): Zoom Server-to-Server accounts, token probe and meetings" -m "$TRAILER"
```

---

### Task 4: Meetings on the resolver with Etqan's host pool, the host link, Jitsi, and Zoom's meeting-ended webhook

**Files:**
- Create: `backend/etqan/integrations/services/video.py`, `backend/etqan/integrations/api/webhooks.py`, `backend/etqan/integrations/migrations/0004_hostbooking.py` (generated), `backend/etqan/integrations/tests/test_video.py`
- Modify: `backend/etqan/integrations/models.py` (`HostBooking`), `backend/etqan/integrations/services/__init__.py`, `backend/etqan/integrations/admin.py` (webhook URL shown, bookings read-only), `backend/config/urls_public.py`, `backend/config/settings/base.py`, `backend/etqan/integrations/tests/test_admin.py`

**Interfaces:**
- Consumes: `resolve`, `ETQAN`, `ACADEMY`, `read_secrets` (slice 1); `add_route`, `route_schema`, `ZOOM_MEETING` (Task 2); `zoom.create_meeting`, `ZoomError` (Task 3); `etqan_billing.services.record_usage` (slice 2); `etqan.platform.tenancy.academy_context`; `etqan.integrations.clock.now`.
- Produces: model `HostBooking(host, starts_at, ends_at, meeting_id, academy, created_at)`; `integrations.services.Meeting(url: str, provider: str, ref: str = "")` (`provider` ∈ `"zoom"`, `"jitsi"`; `ref` the Zoom meeting id), `MAX_MEETINGS_PER_HOST` (1), `VideoError`, `BadSignature`, `meetings_wanted() -> bool`, `jitsi_meeting() -> Meeting`, `create_meeting(*, topic: str, starts_at: datetime, minutes: int) -> Meeting` (raises `VideoError`; a Jitsi meeting when no pool host is free), `meeting_fits(ref: str, starts_at: datetime, minutes: int) -> bool`, `release_meeting(ref: str) -> None`, `host_link(ref: str, join_url: str) -> str | None`, `sign_zoom(raw: bytes, secret: str, timestamp: str) -> str`, `zoom_event(raw: bytes, *, signature: str, timestamp: str) -> dict | None`; `ZOOM_WEBHOOK_PATH = "/api/v1/webhooks/zoom/"`; settings `JITSI_BASE_URL`; the base-domain route `webhook-zoom`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/integrations/tests/test_video.py`:

```python
"""Slice 3 plan D7–D10: a meeting on the account video resolves to (Zoom,
or Jitsi when none), routed when Etqan hosts it; Zoom's meeting-ended event
to Etqan's app meters minutes once, in the academy that made the meeting."""

import itertools
import json
from datetime import UTC
from datetime import datetime
from datetime import timedelta

import httpx
import pytest
from django.db import connection
from django.test import Client
from django.test import override_settings

from etqan.etqan_billing.models import UsageEvent
from etqan.integrations import clock
from etqan.integrations import services
from etqan.integrations.models import HostBooking
from etqan.integrations.models import WebhookRoute
from etqan.integrations.providers import zoom
from etqan.integrations.tests.conftest import ETQAN_HOSTS
from etqan.integrations.tests.conftest import ETQAN_ZOOM_SECRETS

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("fresh_cache")]
START = datetime(2026, 6, 1, 10, 0, tzinfo=UTC)
NOW = datetime(2026, 6, 1, 11, 0, tzinfo=UTC)
TOKEN = ETQAN_ZOOM_SECRETS["webhook_secret"]
PUBLIC_HOST = "etqan.localhost"


def zoom_answers(respx_mock, meeting_id=81234567890, user="host1@etqan.test"):
    respx_mock.post(zoom.TOKEN_URL).mock(
        return_value=httpx.Response(200, json={"access_token": "t", "expires_in": 3599})
    )
    return respx_mock.post(f"{zoom.API}/users/{user}/meetings").mock(
        return_value=httpx.Response(
            201, json={"id": meeting_id, "join_url": f"https://zoom.us/j/{meeting_id}"}
        )
    )


def make(starts_at=START, minutes=45):
    return services.create_meeting(topic="Tajweed · Bilal", starts_at=starts_at, minutes=minutes)


# ── meetings ─────────────────────────────────────────────────────────────


def test_nothing_resolves_so_the_meeting_is_a_jitsi_room():
    first, second = make(), make()
    assert first.provider == "jitsi"
    assert first.url.startswith("https://meet.jit.si/Etqan")
    assert len(first.url) == len("https://meet.jit.si/Etqan") + 32
    assert first.url != second.url
    assert not WebhookRoute.objects.exists()


@override_settings(JITSI_BASE_URL="https://meet.noor.test/")
def test_jitsi_can_be_etqans_own_server():
    assert services.jitsi_meeting().url.startswith("https://meet.noor.test/Etqan")


def test_etqans_zoom_hosts_and_routes_the_meeting(zoom_default, respx_mock, tenants):
    zoom_answers(respx_mock)
    meeting = make()
    assert (meeting.provider, meeting.url, meeting.ref) == (
        "zoom",
        "https://zoom.us/j/81234567890",
        "81234567890",
    )
    booking = HostBooking.objects.get()
    assert (booking.host, booking.meeting_id, booking.starts_at, booking.ends_at) == (
        "host1@etqan.test",
        "81234567890",
        START,
        START + timedelta(minutes=45),
    )
    connection.set_schema_to_public()
    assert services.route_schema(services.ZOOM_MEETING, "81234567890") == (
        tenants.main.schema_name
    )


def test_meetings_on_the_academys_own_zoom_get_no_route(own_zoom, respx_mock):
    zoom_answers(respx_mock, user="me")
    assert make().provider == "zoom"
    assert not WebhookRoute.objects.exists()
    assert not HostBooking.objects.exists()  # its own host, no pool


# ── Etqan's host pool (owner D21) ────────────────────────────────────────


def pool_answers(respx_mock):
    """Each pool host answers with its own meeting id."""
    respx_mock.post(zoom.TOKEN_URL).mock(
        return_value=httpx.Response(200, json={"access_token": "t", "expires_in": 3599})
    )
    ids = itertools.count(1001)
    routes = {}
    for host in ETQAN_HOSTS:
        routes[host] = respx_mock.post(f"{zoom.API}/users/{host}/meetings").mock(
            side_effect=lambda request: (
                lambda n: httpx.Response(201, json={"id": n, "join_url": f"https://zoom.us/j/{n}"})
            )(next(ids))
        )
    return routes


def test_overlapping_meetings_never_share_a_host(zoom_default, respx_mock):
    routes = pool_answers(respx_mock)
    first = make()
    second = make(starts_at=START + timedelta(minutes=30))  # overlaps the first
    assert (first.provider, second.provider) == ("zoom", "zoom")
    assert routes["host1@etqan.test"].call_count == 1
    assert routes["host2@etqan.test"].call_count == 1
    third = make(starts_at=START + timedelta(minutes=40))  # both hosts busy
    assert third.provider == "jitsi"
    assert HostBooking.objects.count() == 2


def test_a_host_is_free_again_when_its_meeting_has_ended(zoom_default, respx_mock):
    routes = pool_answers(respx_mock)
    make()
    make(starts_at=START + timedelta(minutes=45))  # starts as the first ends
    assert routes["host1@etqan.test"].call_count == 2


def test_another_academys_booking_holds_the_host(zoom_default, respx_mock, tenants):
    routes = pool_answers(respx_mock)
    HostBooking.objects.create(
        host="host1@etqan.test", starts_at=START, ends_at=START + timedelta(hours=1),
        meeting_id="9", academy=tenants.other,
    )
    make()
    assert not routes["host1@etqan.test"].called
    assert routes["host2@etqan.test"].call_count == 1


def test_zoom_failing_frees_the_reserved_host(zoom_default, respx_mock):
    respx_mock.post(zoom.TOKEN_URL).mock(return_value=httpx.Response(503))
    with pytest.raises(services.VideoError):
        make()
    assert not HostBooking.objects.exists()


def test_a_stale_reservation_no_longer_blocks_its_host(zoom_default, respx_mock, tenants, monkeypatch):
    routes = pool_answers(respx_mock)
    stale = HostBooking.objects.create(
        host="host1@etqan.test", starts_at=START, ends_at=START + timedelta(hours=1),
        meeting_id="", academy=tenants.main,
    )
    HostBooking.objects.filter(pk=stale.pk).update(created_at=NOW - timedelta(minutes=11))
    monkeypatch.setattr(clock, "now", lambda: NOW)
    make()
    assert routes["host1@etqan.test"].call_count == 1


def test_a_moved_meeting_no_longer_fits_and_can_be_released(zoom_default, respx_mock):
    pool_answers(respx_mock)
    made = make()
    assert services.meeting_fits(made.ref, START, 45) is True
    assert services.meeting_fits(made.ref, START + timedelta(hours=1), 45) is False
    assert services.meeting_fits(made.ref, START, 60) is False
    assert services.meeting_fits("own-account-meeting", START, 45) is True  # no booking
    services.release_meeting(made.ref)
    assert not HostBooking.objects.exists()


# ── the host link (owner D23) ────────────────────────────────────────────


def meeting_read(respx_mock, *, join="https://zoom.us/j/81234567890", status=200):
    respx_mock.post(zoom.TOKEN_URL).mock(
        return_value=httpx.Response(200, json={"access_token": "t", "expires_in": 3599})
    )
    return respx_mock.get(f"{zoom.API}/meetings/81234567890").mock(
        return_value=httpx.Response(
            status, json={"start_url": "https://zoom.us/s/81234567890?zak=z", "join_url": join}
        )
    )


def test_the_host_link_is_read_from_zoom_now(zoom_default, respx_mock):
    route = meeting_read(respx_mock)
    url = services.host_link("81234567890", "https://zoom.us/j/81234567890")
    assert url == "https://zoom.us/s/81234567890?zak=z"
    services.host_link("81234567890", "https://zoom.us/j/81234567890")
    assert route.call_count == 2  # never cached


@pytest.mark.parametrize(
    ("join", "status"),
    [("https://zoom.us/j/other", 200), ("https://zoom.us/j/81234567890", 404)],
)
def test_no_host_link_when_zoom_fails_or_the_link_was_replaced(zoom_default, respx_mock, join, status):
    meeting_read(respx_mock, join=join, status=status)
    assert services.host_link("81234567890", "https://zoom.us/j/81234567890") is None


def test_no_host_link_without_a_zoom_account_or_ref():
    assert services.host_link("81234567890", "https://zoom.us/j/81234567890") is None
    assert services.host_link("", "https://meet.jit.si/EtqanX") is None


def test_zoom_failing_is_a_video_error(zoom_default, respx_mock):
    respx_mock.post(zoom.TOKEN_URL).mock(return_value=httpx.Response(503))
    with pytest.raises(services.VideoError):
        make()


def test_meetings_are_wanted_with_the_switch_or_an_own_account(set_features, admin_user):
    set_features(zoom_api=False)
    services.clear_cache()
    assert services.meetings_wanted() is False
    set_features(zoom_api=True)
    services.clear_cache()
    assert services.meetings_wanted() is True
    set_features(zoom_api=False)
    services.connect(
        "video",
        fields={"account_id": "a", "client_id": "c", "client_secret": "s" * 12},
        by=admin_user,
    )
    assert services.meetings_wanted() is True


# ── the webhook ──────────────────────────────────────────────────────────


@pytest.fixture
def at_now(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: NOW)


def ended(meeting_id="81234567890", uuid="u-1==", start="2026-06-01T10:00:05Z", end="2026-06-01T10:44:06Z"):
    return {
        "event": "meeting.ended",
        "payload": {
            "account_id": "etqanacct",
            "object": {
                "id": meeting_id,
                "uuid": uuid,
                "start_time": start,
                "end_time": end,
                "duration": 45,
            },
        },
    }


def post(event, *, secret=TOKEN, stamp=None):
    raw = json.dumps(event).encode()
    stamp = str(int((stamp or NOW).timestamp()))
    connection.set_schema_to_public()
    return Client().post(
        "/api/v1/webhooks/zoom/",
        data=raw,
        content_type="application/json",
        HTTP_HOST=PUBLIC_HOST,
        HTTP_X_ZM_SIGNATURE=services.sign_zoom(raw, secret, stamp),
        HTTP_X_ZM_REQUEST_TIMESTAMP=stamp,
    )


@pytest.fixture
def routed(zoom_default, at_now):
    services.add_route(services.ZOOM_MEETING, "81234567890")


def test_minutes_land_in_the_academy_that_made_the_meeting(routed, tenants):
    assert post(ended()).status_code == 200
    event = UsageEvent.objects.get()
    assert (event.academy_id, event.service, event.unit, event.quantity) == (
        tenants.main.pk,
        "video",
        "minute",
        45,  # 44 min 1 s rounds up
    )
    assert event.source_ref == "u-1==:minute"
    assert event.occurred_at == datetime(2026, 6, 1, 10, 44, 6, tzinfo=UTC)


def test_a_replayed_meeting_ended_counts_once(routed):
    post(ended())
    post(ended())
    assert UsageEvent.objects.count() == 1


def test_each_instance_of_a_meeting_counts(routed):
    post(ended(uuid="u-1=="))
    post(ended(uuid="u-2==", start="2026-06-03T10:00:00Z", end="2026-06-03T10:00:20Z"))
    assert sorted(UsageEvent.objects.values_list("quantity", flat=True)) == [1, 45]


def test_a_meeting_etqan_never_routed_is_ignored(zoom_default, at_now):
    assert post(ended(meeting_id="999")).status_code == 200
    assert not UsageEvent.objects.exists()


@pytest.mark.parametrize(
    "broken",
    [
        {"start_time": "yesterday"},
        {"end_time": None},
        {"uuid": ""},
    ],
)
def test_a_malformed_meeting_is_ignored(routed, broken):
    event = ended()
    event["payload"]["object"].update(broken)
    assert post(event).status_code == 200
    assert not UsageEvent.objects.exists()


@pytest.mark.parametrize(
    ("secret", "stamp"),
    [
        ("not-the-token", None),
        (TOKEN, datetime(2026, 6, 1, 10, 50, tzinfo=UTC)),  # 10 minutes old
    ],
)
def test_a_bad_or_stale_signature_is_refused(routed, secret, stamp):
    assert post(ended(), secret=secret, stamp=stamp).status_code == 400
    assert not UsageEvent.objects.exists()


def test_without_etqans_token_every_event_is_refused(at_now):
    assert post(ended()).status_code == 400


def test_zooms_url_validation_is_answered(zoom_default, at_now):
    import hashlib  # noqa: PLC0415
    import hmac  # noqa: PLC0415

    resp = post({"event": "endpoint.url_validation", "payload": {"plainToken": "abc"}})
    assert resp.status_code == 200
    assert resp.json() == {
        "plainToken": "abc",
        "encryptedToken": hmac.new(TOKEN.encode(), b"abc", hashlib.sha256).hexdigest(),
    }


def test_the_endpoint_is_not_on_an_academy_host(routed):
    raw = json.dumps(ended()).encode()
    resp = Client().post("/api/v1/webhooks/zoom/", data=raw, content_type="application/json")
    assert resp.status_code == 404
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DJ pytest etqan/integrations/tests/test_video.py -q`
Expected: FAIL — `AttributeError: module 'etqan.integrations.services' has no attribute 'create_meeting'`.

- [ ] **Step 3: Write minimal implementation**

Append to `backend/etqan/integrations/models.py`:

```python
class HostBooking(models.Model):
    """Owner D21: which of Etqan's pool hosts holds which time. A row with
    no meeting id is a reservation while Zoom is asked; one older than ten
    minutes (a crashed run) blocks nothing."""

    host = models.CharField(max_length=254)
    starts_at = models.DateTimeField()
    ends_at = models.DateTimeField()
    meeting_id = models.CharField(max_length=64, blank=True, default="")
    academy = models.ForeignKey(
        settings.TENANT_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["host", "starts_at"])]

    def __str__(self):
        return f"HostBooking<{self.host} {self.starts_at:%Y-%m-%d %H:%M}>"
```

Run: `$DJ python manage.py makemigrations integrations --name hostbooking`
Expected: `integrations/migrations/0004_hostbooking.py`.

Register it read-only in `backend/etqan/integrations/admin.py` exactly like `WebhookRouteAdmin` (`list_display = ["host", "starts_at", "ends_at", "meeting_id", "academy"]`, `list_filter = ["host"]`, no add/change/delete).

In `backend/config/settings/base.py`, directly below `INTEGRATIONS_ALLOW_PRIVATE_SMTP = False`, add:

```python
# Integrations slice 3 (plan D9): the free meeting room when no Zoom account
# resolves. meet.jit.si by default; Etqan may point it at its own Jitsi.
JITSI_BASE_URL = env("JITSI_BASE_URL", default="https://meet.jit.si")
```

Create `backend/etqan/integrations/services/video.py`:

```python
"""Video meetings on the resolver (spec §4 video row, slice 3 plan D7–D10).
A class's meeting is made on the academy's own Zoom account, or Etqan's
(Etqan hosts, and the meeting is routed so its minutes are metered), or is
a free Jitsi room when no Zoom account resolves. Etqan's Zoom app reports
meeting-ended events to one endpoint on the base domain."""

import hashlib
import hmac
import json
import logging
import math
import uuid
from dataclasses import dataclass
from datetime import datetime
from datetime import timedelta

from django.conf import settings
from django.db import connection
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from etqan.etqan_billing import services as billing
from etqan.integrations import clock
from etqan.integrations.models import HostBooking
from etqan.integrations.models import PlatformAccount
from etqan.integrations.providers import zoom
from etqan.integrations.services.resolver import ACADEMY
from etqan.integrations.services.resolver import ETQAN
from etqan.integrations.services.resolver import read_secrets
from etqan.integrations.services.resolver import resolve
from etqan.integrations.services.routes import ZOOM_MEETING
from etqan.integrations.services.routes import add_route
from etqan.integrations.services.routes import route_schema
from etqan.platform import features
from etqan.platform.tenancy import academy_context

VIDEO = "video"
MINUTE = "minute"
ZOOM = "zoom"
JITSI = "jitsi"
ZOOM_WEBHOOK_PATH = "/api/v1/webhooks/zoom/"
TOLERANCE_SECONDS = 300
MAX_STAMP_DIGITS = 12
URL_VALIDATION = "endpoint.url_validation"
MEETING_ENDED = "meeting.ended"
# Owner D21: meetings one pool host may run at once (Zoom's limit for a
# licensed user is one unless Etqan's plan says otherwise).
MAX_MEETINGS_PER_HOST = 1
STALE_RESERVATION = timedelta(minutes=10)
HOSTS_LOCK = "integrations:zoom-hosts"
logger = logging.getLogger(__name__)


class VideoError(Exception):
    """Zoom could not make the meeting now; the caller tries again later."""


class BadSignature(Exception):  # noqa: N818 -- reads as what was received
    """The event is not from Etqan's Zoom app."""


@dataclass(frozen=True)
class Meeting:
    url: str
    provider: str
    ref: str = ""  # the Zoom meeting id; "" for Jitsi


def meetings_wanted() -> bool:
    """Plan D7: the academy asked for meetings — ``zoom_api`` on, or its own
    Zoom account connected and on."""
    if features.enabled("zoom_api"):
        return True
    resolved = resolve(VIDEO)
    return resolved is not None and resolved.source == ACADEMY


def jitsi_meeting() -> Meeting:
    """Plan D9: an unguessable room on Jitsi; no account, no cost."""
    base = settings.JITSI_BASE_URL.rstrip("/")
    return Meeting(f"{base}/Etqan{uuid.uuid4().hex}", JITSI)


def _reserve(hosts: list[str], starts_at: datetime, ends_at: datetime) -> HostBooking | None:
    """Owner D21: the first pool host with room at that time, reserved under
    a lock all academies share; None when every host is busy."""
    fresh = Q(meeting_id__gt="") | Q(created_at__gte=clock.now() - STALE_RESERVATION)
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", [HOSTS_LOCK])
        for host in hosts:
            busy = (
                HostBooking.objects.filter(host=host, starts_at__lt=ends_at, ends_at__gt=starts_at)
                .filter(fresh)
                .count()
            )
            if busy < MAX_MEETINGS_PER_HOST:
                return HostBooking.objects.create(
                    host=host,
                    starts_at=starts_at,
                    ends_at=ends_at,
                    academy_id=connection.tenant.pk,
                )
    return None


def _zoom(resolved, *, host: str, topic: str, starts_at: datetime, minutes: int) -> dict:
    try:
        return zoom.create_meeting(
            resolved.config,
            resolved.secrets(),
            host=host,
            topic=topic,
            starts_at=starts_at,
            minutes=minutes,
        )
    except zoom.ZoomError as exc:
        raise VideoError(str(exc)) from None


def create_meeting(*, topic: str, starts_at: datetime, minutes: int) -> Meeting:
    """The class's meeting on the account video resolves to (plan D7–D9,
    owner D21). Raises VideoError when Zoom fails; Zoom is never called
    under the hosts' lock."""
    resolved = resolve(VIDEO)
    if resolved is None:
        return jitsi_meeting()
    if resolved.source == ACADEMY:
        made = _zoom(
            resolved,
            host=resolved.config.get("host_user") or "me",
            topic=topic,
            starts_at=starts_at,
            minutes=minutes,
        )
        return Meeting(made["join_url"], ZOOM, made["id"])
    ends_at = starts_at + timedelta(minutes=minutes)
    booking = _reserve(resolved.config.get("host_users") or [], starts_at, ends_at)
    if booking is None:
        logger.info("No Etqan Zoom host is free at %s; a Jitsi room instead", starts_at)
        return jitsi_meeting()
    try:
        made = _zoom(resolved, host=booking.host, topic=topic, starts_at=starts_at, minutes=minutes)
    except VideoError:
        booking.delete()
        raise
    with transaction.atomic():
        HostBooking.objects.filter(pk=booking.pk).update(meeting_id=made["id"])
        add_route(ZOOM_MEETING, made["id"])
    return Meeting(made["join_url"], ZOOM, made["id"])


def meeting_fits(ref: str, starts_at: datetime, minutes: int) -> bool:
    """Plan D8: whether the meeting's pool booking still covers the class's
    time; a meeting with no booking (the academy's own Zoom) always fits."""
    booking = HostBooking.objects.filter(meeting_id=ref).first() if ref else None
    if booking is None:
        return True
    return booking.starts_at == starts_at and booking.ends_at == starts_at + timedelta(
        minutes=minutes
    )


def release_meeting(ref: str) -> None:
    """Plan D8: free the pool host of a meeting whose class moved."""
    if ref:
        HostBooking.objects.filter(meeting_id=ref).delete()


def host_link(ref: str, join_url: str) -> str | None:
    """Owner D23: the meeting's start link, read from Zoom now on the account
    video resolves to; None when it cannot be read or the meeting is no longer
    the one behind ``join_url``. A host credential: never stored or logged."""
    resolved = resolve(VIDEO)
    if resolved is None or not ref:
        return None
    try:
        found = zoom.get_meeting(resolved.config, resolved.secrets(), ref)
    except zoom.ZoomError:
        return None
    return found["start_url"] if found["join_url"] == join_url else None


def _token() -> str:
    account = PlatformAccount.objects.filter(service=VIDEO).first()
    if account is None:
        return ""
    return read_secrets(account.secret_enc).get("webhook_secret", "")


def _digest(secret: str, message: bytes) -> str:
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


def sign_zoom(raw: bytes, secret: str, timestamp: str) -> str:
    """An `x-zm-signature` header for ``raw``, as Zoom builds it."""
    return "v0=" + _digest(secret, f"v0:{timestamp}:".encode() + raw)


def _verified(raw: bytes, signature: str, timestamp: str, secret: str) -> dict:
    if not secret or not signature.isascii():
        raise BadSignature
    if not (timestamp.isascii() and timestamp.isdigit()) or len(timestamp) > MAX_STAMP_DIGITS:
        raise BadSignature
    if abs(clock.now().timestamp() - int(timestamp)) > TOLERANCE_SECONDS:
        raise BadSignature
    if not hmac.compare_digest(sign_zoom(raw, secret, timestamp), signature):
        raise BadSignature
    try:
        event = json.loads(raw)
    except ValueError:
        raise BadSignature from None
    if not isinstance(event, dict) or not isinstance(event.get("event"), str):
        raise BadSignature
    return event


def _instant(value) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        when = datetime.fromisoformat(value)
    except ValueError:
        return None
    return when if timezone.is_aware(when) else None


def _meeting_ended(obj) -> None:
    """Plan D10: whole minutes, rounded up, at least one; once per instance."""
    if not isinstance(obj, dict):
        return
    meeting_id = str(obj.get("id") or "")
    instance = obj.get("uuid")
    start, end = _instant(obj.get("start_time")), _instant(obj.get("end_time"))
    if not meeting_id or not isinstance(instance, str) or not instance or not start or not end:
        logger.info("Zoom meeting-ended event without its times; ignored")
        return
    schema = route_schema(ZOOM_MEETING, meeting_id)
    if schema is None:
        return  # not a meeting Etqan made for an academy
    minutes = max(1, math.ceil((end - start).total_seconds() / 60))
    with academy_context(schema):
        billing.record_usage(
            source=ETQAN,
            service=VIDEO,
            unit=MINUTE,
            quantity=minutes,
            source_ref=f"{instance}:{MINUTE}",
            occurred_at=end,
        )


def zoom_event(raw: bytes, *, signature: str, timestamp: str) -> dict | None:
    """One event from Etqan's Zoom app, verified over the raw body; the
    answer Zoom's URL validation needs, else None. Raises BadSignature."""
    secret = _token()
    event = _verified(raw, signature, timestamp, secret)
    payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
    if event["event"] == URL_VALIDATION:
        plain = payload.get("plainToken")
        if not isinstance(plain, str) or not plain:
            raise BadSignature
        return {"plainToken": plain, "encryptedToken": _digest(secret, plain.encode())}
    if event["event"] == MEETING_ENDED:
        _meeting_ended(payload.get("object"))
    return None
```

In `backend/etqan/integrations/services/__init__.py`, add (sorted) imports and `__all__` entries from `etqan.integrations.services.video`: `BadSignature`, `MAX_MEETINGS_PER_HOST`, `Meeting`, `VideoError`, `ZOOM_WEBHOOK_PATH`, `create_meeting`, `host_link`, `jitsi_meeting`, `meeting_fits`, `meetings_wanted`, `release_meeting`, `sign_zoom`, `zoom_event`.

Create `backend/etqan/integrations/api/webhooks.py`:

```python
"""Etqan's Zoom app's events (slice 3 plan D4, D10), on the base domain
only: unauthenticated (so CSRF-free), verified over the raw body, not
throttled. Non-atomic: see config/urls_public.py."""

from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from etqan.integrations import services


class ZoomWebhookView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_classes: list = []

    def post(self, request):
        try:
            answer = services.zoom_event(
                request.body,
                signature=request.headers.get("x-zm-signature", ""),
                timestamp=request.headers.get("x-zm-request-timestamp", ""),
            )
        except services.BadSignature:
            return Response({"detail": "Bad signature."}, status=400)
        return Response(answer or {"received": True})
```

In `backend/config/urls_public.py`, add `from django.db import transaction` and `from etqan.integrations.api.webhooks import ZoomWebhookView`, and append to `urlpatterns` (before the debug-toolbar block):

```python
    # Integrations slice 3 (plan D4): Etqan's own apps report here, on the
    # base domain only; never on an academy host.
    path(
        "api/v1/webhooks/zoom/",
        transaction.non_atomic_requests(ZoomWebhookView.as_view()),
        name="webhook-zoom",
    ),
```

In `backend/etqan/integrations/admin.py`, show the URL to paste into Zoom (and, after Task 9, Stripe): add `from django.conf import settings` and

```python
# Slice 3 plan D4: where Etqan's own apps send their events (base domain).
WEBHOOK_PATHS = {
    "video": "/api/v1/webhooks/zoom/",
    "payments": "/api/v1/webhooks/stripe-connect/",
}
```

then add `"webhook_url"` to `PlatformAccountAdmin.fields` (after `"secret_status"`) and `readonly_fields`, and the method:

```python
    @admin.display(description="Webhook URL")
    def webhook_url(self, obj) -> str:
        path = WEBHOOK_PATHS.get(obj.service)
        return f"{settings.FRONTEND_URL.rstrip('/')}{path}" if path else "—"
```

Append to `backend/etqan/integrations/tests/test_admin.py`:

```python
def test_the_video_page_shows_the_url_to_give_zoom(staff_client):
    resp = staff_client.get(change_url("video"), HTTP_HOST=PUBLIC_HOST)
    assert b"/api/v1/webhooks/zoom/" in resp.content
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DJ pytest etqan/integrations -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports
git -C backend add etqan/integrations config/urls_public.py config/settings/base.py
git -C backend commit -m "feat(integrations): meetings on the resolver with Etqan's host pool, host links, Jitsi, Zoom minutes metered" -m "$TRAILER"
```

---

### Task 5: Links for upcoming sessions, and classes moved off their host (scheduling)

**Files:**
- Create: `backend/etqan/scheduling/services/meetings.py`, `backend/etqan/scheduling/migrations/0014_session_meeting_ref.py` (generated), `backend/etqan/scheduling/tests/test_meetings.py`
- Modify: `backend/etqan/scheduling/models.py`, `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/tasks.py`, `backend/config/settings/base.py` (`CELERY_BEAT_SCHEDULE`)

**Interfaces:**
- Consumes: `integrations.services.meetings_wanted`, `create_meeting`, `jitsi_meeting`, `meeting_fits`, `release_meeting`, `VideoError`, `Meeting` (Task 4); `scheduling.dates.now`; `etqan.platform.tenancy.for_each_academy`.
- Produces: `Session.meeting_provider` (`""`, `"zoom"`, `"jitsi"`) and `Session.meeting_ref` (Zoom meeting id); `scheduling.services.provision_meetings() -> int` (sessions given a link), constants `LEAD`, `LOOKBACK`, `FALLBACK_WITHIN` in `scheduling.services.meetings`; Celery task `scheduling.provision_meetings`; beat entry `scheduling.provision_meetings` every 5 minutes.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/test_meetings.py`:

```python
"""Integrations slice 3 plan D7–D9: sessions starting within a day with no
link get one meeting per class; a link someone entered is never replaced;
Zoom down waits for the next run unless the class is about to start."""

from datetime import date
from datetime import time
from datetime import timedelta

import pytest

from etqan.integrations import services as integrations
from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.services import meetings
from etqan.scheduling.tests.conftest import START
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_student

pytestmark = pytest.mark.django_db
MONDAY = date(2026, 6, 1)  # the clock: Monday 1 June 2026, 08:00 UTC


class FakeVideo:
    """Stands in for integrations' meeting maker; ``fail`` makes Zoom down."""

    def __init__(self):
        self.made: list[dict] = []
        self.fail = False
        self.moved: set[str] = set()  # refs whose booking no longer fits
        self.released: list[str] = []

    def __call__(self, *, topic, starts_at, minutes):
        if self.fail:
            raise integrations.VideoError("down")
        self.made.append({"topic": topic, "starts_at": starts_at, "minutes": minutes})
        n = len(self.made)
        return integrations.Meeting(f"https://zoom.us/j/{n}", "zoom", str(n))

    def fits(self, ref, starts_at, minutes):
        return ref not in self.moved

    def release(self, ref):
        self.released.append(ref)


@pytest.fixture
def video(monkeypatch, set_features):
    set_features(zoom_api=True)
    integrations.clear_cache()
    fake = FakeVideo()
    monkeypatch.setattr(meetings.integrations, "create_meeting", fake)
    monkeypatch.setattr(meetings.integrations, "meeting_fits", fake.fits)
    monkeypatch.setattr(meetings.integrations, "release_meeting", fake.release)
    return fake


@pytest.fixture
def sub(subscribe):
    return subscribe()


def blank(sub, *, start=time(10, 0), on=MONDAY, **fields):
    return hand_session(sub, occurs_on=on, start=start, meeting_url="", **fields)


def url_of(session) -> str:
    session.refresh_from_db()
    return session.meeting_url


def test_a_session_today_gets_a_zoom_link(video, sub, world):
    session = blank(sub)
    assert services.provision_meetings() == 1
    assert url_of(session) == "https://zoom.us/j/1"
    assert (session.meeting_provider, session.meeting_ref) == ("zoom", "1")
    assert video.made == [
        {
            "topic": f"Tajweed · {world.teacher.full_name}",
            "starts_at": session.starts_at,
            "minutes": session.minutes,
        }
    ]


def test_a_link_someone_entered_is_never_replaced(video, sub):
    typed = hand_session(sub, occurs_on=MONDAY, meeting_url="https://meet.test/typed")
    assert services.provision_meetings() == 0
    assert url_of(typed) == "https://meet.test/typed"
    assert video.made == []


def test_a_group_class_shares_one_meeting(video, sub, subscribe, world):
    other = subscribe(student_id=make_student("Omar").id)
    first, second = blank(sub), blank(other)
    assert services.provision_meetings() == 2
    assert url_of(first) == url_of(second) == "https://zoom.us/j/1"
    assert len(video.made) == 1


def test_cancelled_archived_and_far_sessions_are_left_alone(video, sub):
    cancelled = blank(sub, status=Session.Status.CANCELLED)
    archived = blank(sub, start=time(11, 0), archived_at=START)
    tomorrow_late = blank(sub, on=date(2026, 6, 2), start=time(9, 0))  # 25 h away
    over = blank(sub, start=time(6, 0))  # 06:00–06:45 ended before 08:00
    assert services.provision_meetings() == 0
    for session in (cancelled, archived, tomorrow_late, over):
        assert url_of(session) == ""


def test_a_class_still_running_gets_its_link(video, sub):
    running = blank(sub, start=time(7, 30))  # 07:30–08:15, now 08:00
    assert services.provision_meetings() == 1
    assert url_of(running) == "https://zoom.us/j/1"


def test_zoom_down_retries_later_but_a_class_about_to_start_gets_jitsi(video, sub):
    video.fail = True
    later = blank(sub, start=time(12, 0))
    soon = blank(sub, start=time(8, 20))
    assert services.provision_meetings() == 1
    assert url_of(later) == ""
    assert url_of(soon).startswith("https://meet.jit.si/Etqan")
    assert (soon.meeting_provider, soon.meeting_ref) == ("jitsi", "")


def test_an_academy_that_wants_no_meetings_is_unchanged(video, sub, set_features):
    set_features(zoom_api=False)
    integrations.clear_cache()
    session = blank(sub)
    assert services.provision_meetings() == 0
    assert url_of(session) == ""


def test_no_zoom_account_means_a_jitsi_room(set_features, sub):
    """The real integrations service: zoom_api on, but Etqan's video
    default is off, so nothing resolves (plan D9)."""
    set_features(zoom_api=True)
    integrations.clear_cache()
    session = blank(sub)
    assert services.provision_meetings() == 1
    assert url_of(session).startswith("https://meet.jit.si/Etqan")


def test_the_task_runs_in_every_academy(video, sub):
    from etqan.scheduling.tasks import provision_meetings  # noqa: PLC0415

    blank(sub)
    results = provision_meetings()
    assert results["pytest_main"] == "ok"
    assert len(video.made) == 1


def test_a_second_run_changes_nothing(video, sub):
    blank(sub)
    services.provision_meetings()
    assert services.provision_meetings() == 0
    assert len(video.made) == 1


def test_the_lead_is_a_day(video, sub):
    assert meetings.LEAD == timedelta(hours=24)


def test_a_class_moved_off_its_host_gets_a_new_meeting(video, sub, subscribe):
    """Plan D8 / owner D21: on Etqan's default the old booking is released
    and the whole class gets a new meeting in the same run."""
    other = subscribe(student_id=make_student("Omar").id)
    first, second = blank(sub), blank(other)
    services.provision_meetings()
    video.moved.add("1")
    assert services.provision_meetings() == 2
    assert video.released == ["1"]
    assert url_of(first) == url_of(second) == "https://zoom.us/j/2"
    assert first.meeting_ref == second.meeting_ref == "2"


def test_a_class_that_still_fits_or_has_a_typed_link_is_left_alone(video, sub):
    zoomed = blank(sub)
    typed = hand_session(sub, occurs_on=MONDAY, start=time(12, 0), meeting_url="https://meet.test/x")
    services.provision_meetings()
    assert services.provision_meetings() == 0
    assert video.released == []
    assert url_of(zoomed) == "https://zoom.us/j/1"
    assert url_of(typed) == "https://meet.test/x"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DJ pytest etqan/scheduling/tests/test_meetings.py -q`
Expected: FAIL — `ImportError: cannot import name 'meetings' from 'etqan.scheduling.services'`.

- [ ] **Step 3: Write minimal implementation**

In `backend/etqan/scheduling/models.py`, add to `Session` after `meeting_url`:

```python
    # Integrations slice 3 (plan D6): what made the link — "zoom", "jitsi", or
    # "" for one someone typed — and the Zoom meeting id, for the teacher's
    # host link (owner D23) and the host pool (D21). Never a start link.
    # New columns on an existing table: database defaults.
    meeting_provider = models.CharField(max_length=8, blank=True, default="", db_default="")
    meeting_ref = models.CharField(max_length=64, blank=True, default="", db_default="")
```

Run: `$DJ python manage.py makemigrations scheduling --name session_meeting_ref`
Expected: `scheduling/migrations/0014_session_meeting_ref.py` (the number follows the last one).

Create `backend/etqan/scheduling/services/meetings.py`:

```python
"""Meeting links for upcoming sessions (integrations slice 3, plan D7–D9).
A scheduled session starting within a day, or still running, with no link
gets one when the academy wants meetings: one meeting per class (teacher,
start, length), made by integrations on the account video resolves to.
A link anyone entered is never replaced. Zoom failing leaves the class for
the next run, unless it starts within 30 minutes: then a Jitsi room. A Zoom
class moved off its Etqan host booking gets a new meeting (owner D21)."""

import logging
from collections import defaultdict
from datetime import timedelta

from etqan.integrations import services as integrations
from etqan.scheduling import dates
from etqan.scheduling.models import Session

LEAD = timedelta(hours=24)
LOOKBACK = timedelta(hours=4)  # longer than any session
FALLBACK_WITHIN = timedelta(minutes=30)
TOPIC_LENGTH = 200
logger = logging.getLogger(__name__)


def _due(now) -> list[Session]:
    rows = (
        Session.objects.filter(
            status=Session.Status.SCHEDULED,
            meeting_url="",
            archived_at__isnull=True,
            starts_at__gte=now - LOOKBACK,
            starts_at__lt=now + LEAD,
        )
        .select_related("course", "teacher__user")
        .order_by("starts_at", "pk")
    )
    return [s for s in rows if s.starts_at + timedelta(minutes=s.minutes) > now]


def _topic(session: Session) -> str:
    return f"{session.course.name_en} · {session.teacher.user.full_name}"[:TOPIC_LENGTH]


def _release_moved(now) -> None:
    """Plan D8 / owner D21: a Zoom class whose pool booking no longer covers
    its time (it was moved) loses its booking and its link, so this run
    makes it a new meeting. Only links this job made are touched."""
    zoomed = Session.objects.filter(
        status=Session.Status.SCHEDULED,
        meeting_provider="zoom",
        archived_at__isnull=True,
        starts_at__gte=now - LOOKBACK,
        starts_at__lt=now + LEAD,
    ).exclude(meeting_ref="")
    for session in zoomed:
        if not integrations.meeting_fits(session.meeting_ref, session.starts_at, session.minutes):
            integrations.release_meeting(session.meeting_ref)
            Session.objects.filter(
                meeting_ref=session.meeting_ref, meeting_provider="zoom"
            ).update(meeting_url="", meeting_provider="", meeting_ref="")


def provision_meetings() -> int:
    """Give upcoming sessions without a link their class's meeting; returns
    how many sessions got one. Runs outside a transaction (Zoom is called);
    each class's update is one statement and only fills blank links."""
    if not integrations.meetings_wanted():
        return 0
    now = dates.now()
    _release_moved(now)
    classes: dict[tuple, list[Session]] = defaultdict(list)
    for session in _due(now):
        classes[(session.teacher_id, session.starts_at, session.minutes)].append(session)
    filled = 0
    for (_, starts_at, minutes), sessions in classes.items():
        try:
            meeting = integrations.create_meeting(
                topic=_topic(sessions[0]), starts_at=starts_at, minutes=minutes
            )
        except integrations.VideoError:
            if starts_at - now > FALLBACK_WITHIN:
                logger.warning("No meeting yet for the class at %s; next run", starts_at)
                continue
            meeting = integrations.jitsi_meeting()
        filled += Session.objects.filter(
            pk__in=[s.pk for s in sessions], meeting_url=""
        ).update(
            meeting_url=meeting.url,
            meeting_provider=meeting.provider,
            meeting_ref=meeting.ref,
        )
    return filled
```

In `backend/etqan/scheduling/services/__init__.py`, add `from etqan.scheduling.services.meetings import provision_meetings` (sorted among the imports) and `"provision_meetings"` to `__all__`.

Append to `backend/etqan/scheduling/tasks.py`:

```python
PROVISION_MEETINGS = "scheduling.provision_meetings"


@shared_task(name=PROVISION_MEETINGS, soft_time_limit=240, time_limit=270)
def provision_meetings() -> dict[str, str]:
    """Integrations slice 3 (plan D8): every 5 minutes, links for the next
    day's sessions in every academy. Not atomic: Zoom is called, and each
    class's link is written as soon as its meeting exists."""
    return for_each_academy(
        services.provision_meetings, name=PROVISION_MEETINGS, atomic=False
    )
```

In `backend/config/settings/base.py`, at the end of `CELERY_BEAT_SCHEDULE` (after `"etqan_billing.issue_due"`), add:

```python
    # Integrations slice 3 (plan D8; not a phase): every 5 minutes, meeting
    # links for the next day's sessions. A run not started in time is dropped.
    "scheduling.provision_meetings": {
        "task": "scheduling.provision_meetings",
        "schedule": crontab(minute="*/5"),
        "options": {"expires": 290},
    },
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DJ pytest etqan/scheduling/tests/test_meetings.py etqan/scheduling -q`
Expected: PASS (the whole scheduling suite still passes: no existing path changed).

- [ ] **Step 5: Commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports
git -C backend add etqan/scheduling config/settings/base.py
git -C backend commit -m "feat(scheduling): meeting links for the next day's sessions, one per class, rebooked when moved" -m "$TRAILER"
```

---

### Task 6: The teacher's host link (scheduling)

**Files:**
- Create: `backend/etqan/scheduling/tests/test_host_link.py`
- Modify: `backend/etqan/scheduling/services/meetings.py`, `backend/etqan/scheduling/services/__init__.py`, `backend/etqan/scheduling/api/session_views.py`, `backend/etqan/scheduling/api/urls.py`, `backend/etqan/scheduling/api/payloads.py`, `backend/etqan/access/tests/test_routes.py`

**Interfaces:**
- Consumes: `integrations.services.host_link(ref, join_url) -> str | None` (Task 4); `Session.meeting_provider`, `meeting_ref` (Task 5); `etqan.platform.permissions.NotImpersonating`; `etqan.platform.exceptions.NotFoundError`.
- Produces: `scheduling.services.host_link_for(session_id: int, user) -> tuple[str, bool]`; `GET /api/v1/sessions/<id>/host-link/` → `{"url": str, "host": bool}` with `Cache-Control: no-store`; session payloads gain `"meeting_host": bool`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/scheduling/tests/test_host_link.py`:

```python
"""Owner D23 (integrations slice 3): the session's teacher gets a host
(start) link read from Zoom when asked; everyone else gets the join link;
the start link is never stored or listed."""

from datetime import date

import pytest

from etqan.integrations import services as integrations
from etqan.platform.permissions import NotImpersonating
from etqan.scheduling.api.session_views import HostLinkView
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import as_user
from etqan.scheduling.tests.conftest import hand_session
from etqan.scheduling.tests.conftest import make_admin
from etqan.scheduling.tests.conftest import make_teacher

pytestmark = pytest.mark.django_db
JOIN = "https://zoom.us/j/81234567890"
START = "https://zoom.us/s/81234567890?zak=secret-host-token"


def url(session) -> str:
    return f"/api/v1/sessions/{session.pk}/host-link/"


@pytest.fixture
def zoomed(subscribe):
    return hand_session(
        subscribe(),
        occurs_on=date(2026, 6, 1),
        meeting_url=JOIN,
        meeting_provider="zoom",
        meeting_ref="81234567890",
    )


@pytest.fixture
def zoom_says(monkeypatch):
    asked = []

    def answer(ref, join_url):
        asked.append((ref, join_url))
        return START

    monkeypatch.setattr(integrations, "host_link", answer)
    return asked


def test_the_teacher_gets_a_fresh_start_link(zoomed, zoom_says, world):
    resp = as_user(world.teacher).get(url(zoomed))
    assert resp.status_code == 200
    assert resp.json() == {"url": START, "host": True}
    assert resp["Cache-Control"] == "no-store"
    assert zoom_says == [("81234567890", JOIN)]


def test_the_join_link_when_zoom_cannot_give_one(zoomed, monkeypatch, world):
    monkeypatch.setattr(integrations, "host_link", lambda ref, join_url: None)
    assert as_user(world.teacher).get(url(zoomed)).json() == {"url": JOIN, "host": False}


@pytest.mark.parametrize(
    ("provider", "link"),
    [("jitsi", "https://meet.jit.si/EtqanAbc"), ("", "https://meet.test/typed")],
)
def test_a_room_that_is_not_zoom_has_no_host_link(subscribe, zoom_says, world, provider, link):
    session = hand_session(
        subscribe(), occurs_on=date(2026, 6, 1), meeting_url=link, meeting_provider=provider
    )
    assert as_user(world.teacher).get(url(session)).json() == {"url": link, "host": False}
    assert zoom_says == []


def test_only_the_sessions_teacher_gets_the_host_link(zoomed, zoom_says, world):
    others = [world.student, make_teacher("Hamza"), make_admin()]
    for user in others:
        assert as_user(user).get(url(zoomed)).status_code == 404
    assert zoom_says == []
    assert NotImpersonating in HostLinkView.permission_classes


def test_no_link_no_host_link(subscribe, world):
    session = hand_session(subscribe(), occurs_on=date(2026, 6, 1), meeting_url="")
    assert as_user(world.teacher).get(url(session)).status_code == 404


def test_the_host_link_is_never_stored_or_listed(zoomed, zoom_says, world):
    client = as_user(world.teacher)
    client.get(url(zoomed))
    row = Session.objects.values().get(pk=zoomed.pk)
    assert all("zak=" not in str(value) for value in row.values())
    detail = client.get(f"/api/v1/sessions/{zoomed.pk}/")
    assert detail.json()["meeting_host"] is True
    assert "zak=" not in detail.content.decode()
```

In `backend/etqan/access/tests/test_routes.py`, add `GET /api/v1/sessions/<id>/host-link/` to the route table in the shape its neighbours use (authenticated, no code: the service decides; find the scheduling session rows with `grep -n "sessions/" etqan/access/tests/test_routes.py`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DJ pytest etqan/scheduling/tests/test_host_link.py -q`
Expected: FAIL — `ImportError: cannot import name 'HostLinkView'`.

- [ ] **Step 3: Write minimal implementation**

Append to `backend/etqan/scheduling/services/meetings.py` (add `from etqan.platform.exceptions import NotFoundError`):

```python
def host_link_for(session_id: int, user) -> tuple[str, bool]:
    """Owner D23: the session's teacher's way into its meeting — a start
    link read from Zoom now (``True``), else the join link (``False``).
    Anyone but the session's teacher, or a session with no link: 404."""
    session = Session.objects.select_related("teacher").filter(pk=session_id).first()
    if (
        session is None
        or session.teacher.user_id != getattr(user, "pk", None)
        or not session.meeting_url
        or session.status == Session.Status.CANCELLED
    ):
        raise NotFoundError("Session", session_id)
    if session.meeting_provider == "zoom" and session.meeting_ref:
        start = integrations.host_link(session.meeting_ref, session.meeting_url)
        if start:
            return start, True
    return session.meeting_url, False
```

In `backend/etqan/scheduling/services/__init__.py`, export `host_link_for` (sorted import and `__all__`).

In `backend/etqan/scheduling/api/session_views.py` (import `IsAuthenticated` from `rest_framework.permissions` and `NotImpersonating` from `etqan.platform.permissions` if not already imported):

```python
class HostLinkView(APIView):
    """Owner D23: the session's teacher only; the start link is a Zoom host
    credential, so it is never cached by the browser or a proxy and never
    given while someone is signed in as the teacher (ledger D19)."""

    permission_classes = [IsAuthenticated, NotImpersonating]

    def get(self, request, pk):
        url, host = services.host_link_for(pk, request.user)
        response = Response({"url": url, "host": host})
        response["Cache-Control"] = "no-store"
        return response
```

In `backend/etqan/scheduling/api/urls.py`, next to `sessions/<int:pk>/attendance/`:

```python
    path(
        "sessions/<int:pk>/host-link/",
        session_views.HostLinkView.as_view(),
        name="session-host-link",
    ),
```

In `backend/etqan/scheduling/api/payloads.py`, in the session row next to `"meeting_url"`:

```python
        # Owner D23: a Zoom meeting whose teacher may ask for a host link.
        "meeting_host": session.meeting_provider == "zoom" and bool(session.meeting_ref),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DJ pytest etqan/scheduling etqan/access -q`
Expected: PASS (existing payload tests that compare whole session rows gain `meeting_host: False`; add it to those expectations — it is the new field, not a regression).

- [ ] **Step 5: Commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports
git -C backend add etqan/scheduling etqan/access/tests/test_routes.py
git -C backend commit -m "feat(scheduling): the session teacher's fresh Zoom host link" -m "$TRAILER"
```

---

### Task 7: Etqan's Stripe platform keys and the academy's Connect onboarding

**Files:**
- Create: `backend/etqan/integrations/providers/payments.py`, `backend/etqan/integrations/services/connect.py`, `backend/etqan/integrations/tests/test_connect.py`
- Modify: `backend/etqan/integrations/providers/__init__.py`, `backend/etqan/integrations/services/accounts.py` (`probe`), `backend/etqan/integrations/services/__init__.py`, `backend/etqan/integrations/api/views.py`, `backend/etqan/integrations/api/urls.py`, `backend/etqan/integrations/api/payloads.py` (`connect_countries`), `backend/etqan/integrations/admin.py` (`FORM_FIELDS`, help text), `backend/etqan/integrations/tests/conftest.py`, `backend/etqan/integrations/tests/test_providers.py`, `backend/etqan/access/tests/test_routes.py` (the route table)

**Interfaces:**
- Consumes: `etqan.platform.stripe.call`, `StripeError` (Task 1); `add_route`, `STRIPE_ACCOUNT` (Task 2); `resolve`, `ETQAN`, `read_secrets`, `clear_cache`, `NOT_CONNECTED` (slice 1); `etqan.platform.frontend.app_url`; `etqan.integrations.clock.now`.
- Produces: `StripePlatformProvider` (service `payments`); `integrations.services`: `ONBOARDING`, `PENDING`, `ACTIVE`, `USE_CONNECT` (`"integrations.use_connect"`), `CONNECT_UNAVAILABLE` (`"integrations.connect_unavailable"`), `CONNECT_COUNTRY` (`"integrations.connect_country"`), `CONNECT_COUNTRIES` (frozenset of ISO codes, owner D22), `StripePlatform(mode: str, secret_key: str, webhook_secrets: tuple[str, ...])`, `StripeConnect(account_id: str, mode: str, secret_key: str)`, `stripe_platform() -> StripePlatform | None`, `stripe_connect() -> StripeConnect | None`, `connect_status(obj: dict) -> str`, `start_onboarding(*, country: object, by) -> str`, `apply_connect_account(obj: dict) -> bool`, `refresh_connect() -> AcademyAccount`, `connect_webhook_secrets() -> tuple[str, ...]`; route `POST /api/v1/integrations/payments/connect/` → `{"url": str}`; the payments card gains `connect_countries: list[str]` (sorted; payments card only); test fixtures `STRIPE_PLATFORM_SECRETS`, `stripe_platform_on`, `connected(status="active")`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/integrations/tests/conftest.py`:

```python
STRIPE_PLATFORM_SECRETS = {
    "secret_key": "sk_test_<redacted>",
    "connect_webhook_secret": "whsec_<redacted>",
    "platform_webhook_secret": "whsec_<redacted>",
}


@pytest.fixture
def stripe_platform_on(set_features):
    """Slice 3: Etqan's Stripe platform as the payments default, with
    online payments on for the academy (it requires invoices)."""
    from etqan.integrations.models import PlatformAccount  # noqa: PLC0415

    PlatformAccount.objects.filter(service="payments").update(
        enabled=True,
        config={"mode": "test"},
        secret_enc=services.write_secrets(STRIPE_PLATFORM_SECRETS),
    )
    set_features(invoices=True, online_payments=True)
    services.clear_cache()


@pytest.fixture
def connected(stripe_platform_on):
    """``connected("active")``: the academy's Connect account, written
    straight to the table and routed, as onboarding leaves it."""
    from etqan.integrations.accounts.models import AcademyAccount  # noqa: PLC0415

    def make(status="active", account_id="acct_noor", mode="test"):
        AcademyAccount.objects.update_or_create(
            service="payments",
            defaults={
                "enabled": status == "active",
                "config": {
                    "account_id": account_id,
                    "status": status,
                    "country": "AE",
                    "mode": mode,
                },
            },
        )
        services.add_route(services.STRIPE_ACCOUNT, account_id)
        services.clear_cache()
        return account_id

    return make
```

Create `backend/etqan/integrations/tests/test_connect.py`:

```python
"""Slice 3 plan D12–D16: Etqan's Stripe platform keys, the academy's
Express account through hosted onboarding, its status, and what gateways
asks for. Stripe is answered by respx."""

import logging
from urllib.parse import parse_qsl

import httpx
import pytest
from django.db import connection

from etqan.integrations import providers
from etqan.integrations import services
from etqan.integrations.accounts.models import AcademyAccount
from etqan.integrations.models import PlatformAccount
from etqan.integrations.models import WebhookRoute
from etqan.integrations.tests.conftest import STRIPE_PLATFORM_SECRETS
from etqan.platform import stripe
from etqan.platform.exceptions import ExternalServiceError
from etqan.platform.exceptions import ValidationError

pytestmark = pytest.mark.django_db
PAYMENTS = providers.get("payments")
KEY = STRIPE_PLATFORM_SECRETS["secret_key"]
CONNECT_URL = "/api/v1/integrations/payments/connect/"


def form(route, index=0) -> dict:
    return dict(parse_qsl(route.calls[index].request.content.decode()))


def stripe_answers(respx_mock, *, account=None, link="https://connect.stripe.com/setup/e/acct_noor/x"):
    accounts = respx_mock.post(f"{stripe.API}/accounts").mock(
        return_value=httpx.Response(
            200,
            json=account or {"id": "acct_noor", "charges_enabled": False, "details_submitted": False},
        )
    )
    links = respx_mock.post(f"{stripe.API}/account_links").mock(
        return_value=httpx.Response(200, json={"url": link})
    )
    return accounts, links


# ── Etqan's platform keys ────────────────────────────────────────────────


def test_the_platform_keys_are_secrets_and_the_mode_comes_from_the_key():
    config, values = PAYMENTS.clean(dict(STRIPE_PLATFORM_SECRETS), stored={}, own=False)
    assert config == {"mode": "test"}
    assert values == STRIPE_PLATFORM_SECRETS
    assert PAYMENTS.last4(values) == "0000"
    live, _ = PAYMENTS.clean({"secret_key": "rk_live_<redacted>"}, stored={}, own=False)
    assert live == {"mode": "live"}


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({}, "secret_key"),
        ({"secret_key": "pk_test_<redacted>"}, "secret_key"),
        ({"secret_key": KEY, "connect_webhook_secret": "nope"}, "connect_webhook_secret"),
        ({"secret_key": KEY, "platform_webhook_secret": "nope"}, "platform_webhook_secret"),
    ],
)
def test_platform_keys_are_checked(fields, field):
    with pytest.raises(ValidationError) as caught:
        PAYMENTS.clean(fields, stored={}, own=False)
    assert caught.value.field == field


def test_an_academy_cannot_type_keys_here(api_for):
    resp = api_for("admin").put("/api/v1/integrations/payments/", {"secret_key": KEY}, format="json")
    assert resp.status_code == 400
    assert resp.json()["code"] == "integrations.use_connect"
    assert not AcademyAccount.objects.exists()


def test_etqans_test_retrieves_the_platform_account(respx_mock):
    route = respx_mock.get(f"{stripe.API}/account").mock(
        return_value=httpx.Response(200, json={"id": "acct_etqan"})
    )
    PAYMENTS.probe(config={"mode": "test"}, secrets={"secret_key": KEY}, tester_email="x@etqan.test")
    assert route.called
    respx_mock.get(f"{stripe.API}/account").mock(return_value=httpx.Response(401, json={}))
    with pytest.raises(providers.ProbeError) as caught:
        PAYMENTS.probe(config={}, secrets={"secret_key": KEY}, tester_email="x@etqan.test")
    assert caught.value.message == "Stripe refused this secret key."


def test_the_platform_key_never_shows_in_a_repr_or_log(stripe_platform_on, respx_mock, caplog):
    caplog.set_level(logging.INFO)
    platform = services.stripe_platform()
    assert (platform.mode, platform.secret_key) == ("test", KEY)
    assert platform.webhook_secrets == ("whsec_<redacted>", "whsec_<redacted>")
    assert KEY not in repr(platform)
    assert "whsec_" not in repr(platform)
    respx_mock.post(f"{stripe.API}/accounts").mock(return_value=httpx.Response(400, json={}))
    with pytest.raises(ValidationError):
        services.start_onboarding(country="AE", by=None)
    assert KEY not in caplog.text


# ── onboarding ───────────────────────────────────────────────────────────


def test_connect_with_stripe_creates_an_express_account_and_a_link(stripe_platform_on, respx_mock, api_for, tenants):
    accounts, links = stripe_answers(respx_mock)
    resp = api_for("admin").post(CONNECT_URL, {"country": "ae"}, format="json")
    assert resp.status_code == 200
    assert resp.json() == {"url": "https://connect.stripe.com/setup/e/acct_noor/x"}
    assert form(accounts) == {
        "type": "express",
        "country": "AE",
        "capabilities[card_payments][requested]": "true",
        "capabilities[transfers][requested]": "true",
        "metadata[academy]": tenants.main.schema_name,
    }
    assert accounts.calls[0].request.headers["Idempotency-Key"] == (
        f"etqan-connect-{tenants.main.schema_name}-AE"
    )
    sent = form(links)
    assert sent["account"] == "acct_noor"
    assert sent["type"] == "account_onboarding"
    assert sent["return_url"].endswith("/app/settings/integrations?stripe=return")
    assert sent["refresh_url"].endswith("/app/settings/integrations?stripe=refresh")
    row = AcademyAccount.objects.get(service="payments")
    assert row.config == {"account_id": "acct_noor", "status": "onboarding", "country": "AE", "mode": "test"}
    assert (row.enabled, row.secret_enc) == (False, "")
    assert WebhookRoute.objects.filter(kind="stripe_account", ref="acct_noor").exists()


def test_continuing_reuses_the_account_and_needs_no_country(connected, respx_mock):
    connected("onboarding")
    accounts, links = stripe_answers(respx_mock)
    url = services.start_onboarding(country="", by=None)
    assert url.startswith("https://connect.stripe.com/")
    assert not accounts.called
    assert form(links)["account"] == "acct_noor"


def test_an_account_of_the_other_mode_is_not_used(connected, respx_mock):
    connected("active", account_id="acct_live_old", mode="live")
    assert services.stripe_connect() is None  # the platform key is a test key
    accounts, _ = stripe_answers(respx_mock)
    services.start_onboarding(country="AE", by=None)
    assert accounts.called  # a new test-mode account
    row = AcademyAccount.objects.get(service="payments")
    assert (row.config["account_id"], row.config["mode"]) == ("acct_noor", "test")


@pytest.mark.parametrize("country", ["", "A", "ARE", "1A", None, 7])
def test_a_new_account_needs_a_two_letter_country(stripe_platform_on, country):
    with pytest.raises(ValidationError) as caught:
        services.start_onboarding(country=country, by=None)
    assert caught.value.field == "country"


def test_a_country_stripe_connect_cannot_serve_is_refused_before_asking(stripe_platform_on, respx_mock):
    """Owner D22: Express accounts exist only in Stripe's countries."""
    accounts = respx_mock.post(f"{stripe.API}/accounts")
    with pytest.raises(ValidationError) as caught:
        services.start_onboarding(country="EG", by=None)
    assert (caught.value.field, caught.value.code) == ("country", "integrations.connect_country")
    assert not accounts.called


def test_stripe_refusing_the_country_says_the_same(stripe_platform_on, respx_mock):
    respx_mock.post(f"{stripe.API}/accounts").mock(
        return_value=httpx.Response(400, json={"error": {"type": "invalid_request_error"}})
    )
    with pytest.raises(ValidationError) as caught:
        services.start_onboarding(country="AE", by=None)
    assert (caught.value.field, caught.value.code) == ("country", "integrations.connect_country")
    assert not AcademyAccount.objects.exists()


def test_the_payments_card_lists_the_countries_connect_serves(api_for):
    cards = {c["service"]: c for c in api_for("admin").get("/api/v1/integrations/").json()["services"]}
    countries = cards["payments"]["connect_countries"]
    assert countries == sorted(services.CONNECT_COUNTRIES)
    assert "AE" in countries and "EG" not in countries
    assert "connect_countries" not in cards["email"]


def test_stripe_down_is_a_502(stripe_platform_on, respx_mock):
    respx_mock.post(f"{stripe.API}/accounts").mock(side_effect=httpx.ConnectError("down"))
    with pytest.raises(ExternalServiceError):
        services.start_onboarding(country="AE", by=None)


@pytest.mark.parametrize("case", ["no_keys", "disabled", "switch_off", "suspended"])
def test_connect_needs_etqans_default_for_this_academy(stripe_platform_on, case, unavailable):
    unavailable(case)
    with pytest.raises(ValidationError) as caught:
        services.start_onboarding(country="AE", by=None)
    assert caught.value.code == "integrations.connect_unavailable"


@pytest.fixture
def unavailable(set_features, request):
    def apply(case):
        if case == "no_keys":
            PlatformAccount.objects.filter(service="payments").update(secret_enc="")
        elif case == "disabled":
            PlatformAccount.objects.filter(service="payments").update(enabled=False)
        elif case == "switch_off":
            set_features(online_payments=False)
        else:
            request.getfixturevalue("suspended")
        services.clear_cache()

    return apply


def test_staff_need_the_update_code(stripe_platform_on, staff_for):
    assert staff_for("integration.view").post(CONNECT_URL, {"country": "AE"}, format="json").status_code == 403


# ── status ───────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("obj", "status"),
    [
        ({"charges_enabled": True, "details_submitted": True}, "active"),
        ({"charges_enabled": False, "details_submitted": True}, "pending"),
        ({"charges_enabled": False, "details_submitted": False}, "onboarding"),
        ({}, "onboarding"),
    ],
)
def test_the_status_comes_from_the_account(obj, status):
    assert services.connect_status(obj) == status


def test_an_update_for_this_account_moves_its_status(connected):
    connected("onboarding")
    assert services.apply_connect_account({"id": "acct_noor", "charges_enabled": True}) is True
    row = AcademyAccount.objects.get(service="payments")
    assert (row.config["status"], row.enabled) == ("active", True)
    assert services.apply_connect_account({"id": "acct_other", "charges_enabled": False}) is False
    assert AcademyAccount.objects.get(service="payments").config["status"] == "active"


def test_check_status_retrieves_the_account_and_records_the_test(connected, respx_mock, api_for):
    connected("pending")
    respx_mock.get(f"{stripe.API}/accounts/acct_noor").mock(
        return_value=httpx.Response(200, json={"id": "acct_noor", "charges_enabled": True})
    )
    resp = api_for("admin").post("/api/v1/integrations/payments/test/")
    assert resp.status_code == 200
    own = resp.json()["own"]
    assert (own["config"]["status"], own["last_test_ok"], own["last_test_error"]) == ("active", True, "")


def test_check_status_failing_is_an_answer(connected, respx_mock):
    connected("pending")
    respx_mock.get(f"{stripe.API}/accounts/acct_noor").mock(return_value=httpx.Response(404, json={}))
    row = services.refresh_connect()
    assert (row.last_test_ok, row.last_test_error) == (False, "Stripe refused to read this account.")
    assert row.config["status"] == "pending"


def test_check_status_without_an_account_is_not_connected(stripe_platform_on):
    with pytest.raises(ValidationError) as caught:
        services.refresh_connect()
    assert caught.value.code == "integrations.not_connected"


# ── what gateways asks ───────────────────────────────────────────────────


def test_gateways_gets_the_account_only_when_active_and_on(connected, set_features):
    connected("pending")
    assert services.stripe_connect() is None
    connected("active")
    found = services.stripe_connect()
    assert (found.account_id, found.mode, found.secret_key) == ("acct_noor", "test", KEY)
    assert KEY not in repr(found)
    set_features(online_payments=False)
    services.clear_cache()
    assert services.stripe_connect() is None


def test_disconnecting_forgets_the_link_but_keeps_the_route(connected, api_for):
    connected("active")
    assert api_for("admin").delete("/api/v1/integrations/payments/").status_code == 200
    assert not AcademyAccount.objects.exists()
    connection.set_schema_to_public()
    assert services.route_schema(services.STRIPE_ACCOUNT, "acct_noor") is not None


def test_the_webhook_secrets_are_read_even_while_etqans_default_is_off(stripe_platform_on):
    PlatformAccount.objects.filter(service="payments").update(enabled=False)
    assert services.connect_webhook_secrets() == ("whsec_<redacted>", "whsec_<redacted>")
```

In `backend/etqan/integrations/tests/test_providers.py`, set payments' entry (the third) of `test_every_service_has_a_provider_and_which_connect` to `True`: `[False, True, True, True, False]` (keep B10a's `True` for ai if present).

In `backend/etqan/access/tests/test_routes.py`, add the new route to the table the same way slice 1 added `integrations/<service>/test/` (find it with `grep -n "integrations" etqan/access/tests/test_routes.py`): `("post", "/api/v1/integrations/payments/connect/", "integration.update")` in the same tuple shape as its neighbours.

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DJ pytest etqan/integrations/tests/test_connect.py -q`
Expected: FAIL — `AttributeError: module 'etqan.integrations.services' has no attribute 'stripe_platform'`, and the NotYet payments provider refusing every clean.

- [ ] **Step 3: Write minimal implementation**

Create `backend/etqan/integrations/providers/payments.py`:

```python
"""Online payments' Etqan default (spec §4 payments row, IN-4; slice 3
plan D13): Etqan's Stripe platform keys, set by Etqan staff. An academy's
own Stripe and PayPal keys stay in `etqan.gateways` (B3); its Connect
account is made by hosted onboarding, never typed here."""

from etqan.integrations.providers.base import ProbeError
from etqan.platform import stripe
from etqan.platform.exceptions import ValidationError

USE_CONNECT = "integrations.use_connect"
PREFIXES = {
    "test": ("sk_test_", "rk_test_"),
    "live": ("sk_live_", "rk_live_"),
}
WEBHOOK_PREFIX = "whsec_"
WEBHOOK_FIELDS = ("connect_webhook_secret", "platform_webhook_secret")
MAX_SECRET = 255
LAST4_FROM = 12


def mode_of(key: str) -> str | None:
    for mode, prefixes in PREFIXES.items():
        if key.startswith(prefixes):
            return mode
    return None


def _secret(fields: dict, stored: dict, name: str) -> str:
    value = fields.get(name, "")
    if not isinstance(value, str) or len(value) > MAX_SECRET:
        raise ValidationError("Enter it as text.", field=name)
    return value.strip() or stored.get(name, "")


class StripePlatformProvider:
    service = "payments"
    connectable = True
    empty_is_default = False

    def clean(
        self, fields: dict, *, stored: dict, own: bool = True
    ) -> tuple[dict, dict]:
        if own:
            raise ValidationError(
                "Use Connect with Stripe. Your own Stripe or PayPal keys go in "
                "Payment gateways.",
                code=USE_CONNECT,
            )
        key = _secret(fields, stored, "secret_key")
        mode = mode_of(key)
        if mode is None:
            raise ValidationError(
                "Enter Etqan's Stripe secret key (sk_test_… or sk_live_…).",
                field="secret_key",
            )
        values = {"secret_key": key}
        for name in WEBHOOK_FIELDS:
            value = _secret(fields, stored, name)
            if value and not value.startswith(WEBHOOK_PREFIX):
                raise ValidationError("This is not a Stripe signing secret.", field=name)
            if value:
                values[name] = value
        return {"mode": mode}, values

    def last4(self, values: dict) -> str:
        key = values.get("secret_key", "")
        return key[-4:] if len(key) >= LAST4_FROM else ""

    def probe(self, *, config: dict, secrets: dict, tester_email: str) -> None:
        """Etqan's Test: Stripe answers for the platform account."""
        try:
            stripe.call("GET", "/account", key=secrets.get("secret_key", ""))
        except stripe.StripeError as exc:
            if exc.status is None or exc.status >= 500:  # noqa: PLR2004
                raise ProbeError("Could not reach Stripe. Try again in a moment.") from None
            raise ProbeError("Stripe refused this secret key.") from None
```

In `backend/etqan/integrations/providers/__init__.py`, import `StripePlatformProvider` from `etqan.integrations.providers.payments`, replace the payments `NotYet(...)` entry with `"payments": StripePlatformProvider(),`, and add it to `__all__`.

Create `backend/etqan/integrations/services/connect.py`:

```python
"""Stripe Connect as Etqan's payments default (spec IN-4, §3.1; slice 3
plan D12–D16). The academy's payments row holds only its Express account id,
status, country and mode; Etqan's platform keys come from Etqan's payments
default. `etqan.gateways` asks `stripe_connect()` for a checkout and
`stripe_platform()` for its webhook; it reads B3's own keys first."""

import logging
import re
from dataclasses import dataclass
from dataclasses import field

from django.db import IntegrityError
from django.db import connection
from django.db import transaction

from etqan.integrations import clock
from etqan.integrations.accounts.models import AcademyAccount
from etqan.integrations.models import PlatformAccount
from etqan.integrations.providers.payments import mode_of
from etqan.integrations.services.resolver import ETQAN
from etqan.integrations.services.resolver import clear_cache
from etqan.integrations.services.resolver import read_secrets
from etqan.integrations.services.resolver import resolve
from etqan.integrations.services.routes import STRIPE_ACCOUNT
from etqan.integrations.services.routes import add_route
from etqan.platform import stripe
from etqan.platform.exceptions import ExternalServiceError
from etqan.platform.exceptions import ValidationError
from etqan.platform.frontend import app_url

PAYMENTS = "payments"
ONBOARDING = "onboarding"
PENDING = "pending"
ACTIVE = "active"
CONNECT_UNAVAILABLE = "integrations.connect_unavailable"
CONNECT_COUNTRY = "integrations.connect_country"
# Owner D22 [assumed]: the countries where Stripe supports Express connected
# accounts (Stripe's published list, 2026); the owner checks it before
# go-live. Any other country keeps B3's own keys or PayPal.
CONNECT_COUNTRIES = frozenset(
    {
        "AE", "AT", "AU", "BE", "BG", "CA", "CH", "CY", "CZ", "DE", "DK", "EE",
        "ES", "FI", "FR", "GB", "GI", "GR", "HK", "HR", "HU", "IE", "IT", "JP",
        "LI", "LT", "LU", "LV", "MT", "MX", "MY", "NL", "NO", "NZ", "PL", "PT",
        "RO", "SE", "SG", "SI", "SK", "TH", "US",
    }
)  # fmt: skip
NOT_IN_COUNTRY = "Stripe Connect isn't available in this country. Use your own Stripe or PayPal keys in Payment gateways."
NOT_CONNECTED = "integrations.not_connected"
COUNTRY = re.compile(r"^[A-Z]{2}$")
RETURN_PATH = "/settings/integrations?stripe=return"
REFRESH_PATH = "/settings/integrations?stripe=refresh"
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class StripePlatform:
    mode: str
    secret_key: str = field(repr=False)
    webhook_secrets: tuple[str, ...] = field(default=(), repr=False)


@dataclass(frozen=True)
class StripeConnect:
    account_id: str
    mode: str
    secret_key: str = field(repr=False)


def stripe_platform() -> StripePlatform | None:
    """Etqan's platform keys whether or not the default is on (a webhook
    about an earlier payment still needs them); None without a key."""
    account = PlatformAccount.objects.filter(service=PAYMENTS).first()
    values = read_secrets(account.secret_enc) if account else {}
    key = values.get("secret_key", "")
    if not key:
        return None
    hooks = tuple(
        values[name]
        for name in ("connect_webhook_secret", "platform_webhook_secret")
        if values.get(name)
    )
    return StripePlatform(account.config.get("mode") or mode_of(key) or "test", key, hooks)


def connect_webhook_secrets() -> tuple[str, ...]:
    platform = stripe_platform()
    return platform.webhook_secrets if platform else ()


def connect_status(obj: dict) -> str:
    """Plan D14: what the academy can do with its account now."""
    if obj.get("charges_enabled") is True:
        return ACTIVE
    if obj.get("details_submitted") is True:
        return PENDING
    return ONBOARDING


def _row() -> AcademyAccount | None:
    return AcademyAccount.objects.filter(service=PAYMENTS).first()


def _account_id(row: AcademyAccount | None, mode: str) -> str:
    """The academy's account in ``mode``; one of the other mode is none."""
    if row is None or row.config.get("mode") != mode:
        return ""
    return row.config.get("account_id") or ""


def stripe_connect() -> StripeConnect | None:
    """Plan D17: the account a new checkout pays into, when Etqan's default
    resolves for the academy and its account takes charges."""
    resolved = resolve(PAYMENTS)
    platform = stripe_platform()
    if resolved is None or resolved.source != ETQAN or platform is None:
        return None
    row = _row()
    account_id = _account_id(row, platform.mode)
    if not account_id or row.config.get("status") != ACTIVE:
        return None
    return StripeConnect(account_id, platform.mode, platform.secret_key)


def _call(platform: StripePlatform, method: str, path: str, **kwargs) -> dict:
    try:
        return stripe.call(method, path, key=platform.secret_key, **kwargs)
    except stripe.StripeError as exc:
        if exc.status is None or exc.status >= 500:  # noqa: PLR2004
            logger.warning("Stripe Connect %s failed: %s %s", path, exc.status, exc.kind)
            raise ExternalServiceError("Stripe") from None
        logger.warning(
            "Stripe refused %s: %s %s %s", path, exc.status, exc.error_type, exc.code
        )
        if path != "/accounts":
            raise ExternalServiceError("Stripe") from None
        # Owner D22: Stripe would not open an account there.
        raise ValidationError(NOT_IN_COUNTRY, field="country", code=CONNECT_COUNTRY) from None


def _country(value: object) -> str:
    code = value.strip().upper() if isinstance(value, str) else ""
    if not COUNTRY.match(code):
        raise ValidationError(
            "Enter the two-letter code of the academy's country.", field="country"
        )
    if code not in CONNECT_COUNTRIES:
        raise ValidationError(NOT_IN_COUNTRY, field="country", code=CONNECT_COUNTRY)
    return code


def _save(*, account_id: str, status: str, country: str, mode: str, by) -> None:
    def write():
        with transaction.atomic():
            row = (
                AcademyAccount.objects.select_for_update().filter(service=PAYMENTS).first()
                or AcademyAccount(service=PAYMENTS)
            )
            row.config = {
                "account_id": account_id,
                "status": status,
                "country": country,
                "mode": mode,
            }
            row.enabled = status == ACTIVE
            row.secret_enc = ""
            row.secret_last4 = ""
            row.last_test_at, row.last_test_ok, row.last_test_error = None, None, ""
            row.updated_by = by
            row.save()

    try:
        write()
    except IntegrityError:
        write()  # two first connects at once: the row exists now
    clear_cache()


def start_onboarding(*, country: object, by) -> str:
    """Plan D14: Stripe's hosted onboarding link for the academy's Express
    account, made first when it has none in the platform's mode. Stripe is
    never called under a row lock."""
    resolved = resolve(PAYMENTS)
    platform = stripe_platform()
    if resolved is None or resolved.source != ETQAN or platform is None:
        raise ValidationError(
            "Etqan's Stripe Connect is not available to your academy.",
            code=CONNECT_UNAVAILABLE,
        )
    account_id = _account_id(_row(), platform.mode)
    if not account_id:
        code = _country(country)
        schema = connection.schema_name
        created = _call(
            platform,
            "POST",
            "/accounts",
            data=[
                ("type", "express"),
                ("country", code),
                ("capabilities[card_payments][requested]", "true"),
                ("capabilities[transfers][requested]", "true"),
                ("metadata[academy]", schema),
            ],
            idempotency=f"etqan-connect-{schema}-{code}",
        )
        account_id = created.get("id")
        if not isinstance(account_id, str) or not account_id.startswith("acct_"):
            logger.warning("Stripe answered an account without an id")
            raise ExternalServiceError("Stripe")
        add_route(STRIPE_ACCOUNT, account_id)
        _save(
            account_id=account_id,
            status=connect_status(created),
            country=code,
            mode=platform.mode,
            by=by,
        )
    link = _call(
        platform,
        "POST",
        "/account_links",
        data=[
            ("account", account_id),
            ("refresh_url", app_url(REFRESH_PATH)),
            ("return_url", app_url(RETURN_PATH)),
            ("type", "account_onboarding"),
        ],
    )
    url = link.get("url")
    if not isinstance(url, str) or not url.startswith("https://"):
        logger.warning("Stripe answered an account link without a url")
        raise ExternalServiceError("Stripe")
    return url


@transaction.atomic
def apply_connect_account(obj: dict) -> bool:
    """`account.updated` or a retrieve: the academy's row takes the status
    when the account is its own; False otherwise."""
    row = AcademyAccount.objects.select_for_update().filter(service=PAYMENTS).first()
    if row is None or not obj.get("id") or row.config.get("account_id") != obj.get("id"):
        return False
    status = connect_status(obj)
    row.config = {**row.config, "status": status}
    row.enabled = status == ACTIVE
    row.save(update_fields=["config", "enabled", "updated_at"])
    clear_cache()
    return True


def refresh_connect() -> AcademyAccount:
    """Plan D15, the card's Check status: retrieve the account with Etqan's
    key, take its status, record the test. A failure is an answer."""
    row = _row()
    if row is None or not row.config.get("account_id"):
        raise ValidationError("Connect with Stripe first.", code=NOT_CONNECTED)
    platform = stripe_platform()
    error = ""
    if platform is None:
        error = "Etqan's Stripe platform is not set up."
    else:
        try:
            obj = stripe.call(
                "GET", f"/accounts/{row.config['account_id']}", key=platform.secret_key
            )
        except stripe.StripeError as exc:
            error = (
                "Could not reach Stripe. Try again in a moment."
                if exc.status is None or exc.status >= 500  # noqa: PLR2004
                else "Stripe refused to read this account."
            )
        else:
            apply_connect_account(obj)
    row.refresh_from_db()
    row.last_test_at = clock.now()
    row.last_test_ok = not error
    row.last_test_error = error
    row.save(update_fields=["last_test_at", "last_test_ok", "last_test_error"])
    return row
```

In `backend/etqan/integrations/services/accounts.py` `probe`, directly after `provider = providers.get(service)`, add:

```python
    if service == "payments" and scope == ACADEMY:
        # Slice 3 plan D15: the academy's Test is Check status on Connect.
        from etqan.integrations.services.connect import refresh_connect  # noqa: PLC0415

        return refresh_connect()
```

In `backend/etqan/integrations/services/__init__.py`, add (sorted) imports and `__all__` entries from `etqan.integrations.services.connect`: `ACTIVE`, `CONNECT_COUNTRIES`, `CONNECT_COUNTRY`, `CONNECT_UNAVAILABLE`, `ONBOARDING`, `PENDING`, `StripeConnect`, `StripePlatform`, `apply_connect_account`, `connect_status`, `connect_webhook_secrets`, `refresh_connect`, `start_onboarding`, `stripe_connect`, `stripe_platform`.

In `backend/etqan/integrations/api/views.py` (add `from etqan.platform.permissions import NotImpersonating`):

```python
class ConnectStripeView(APIView):
    """Slice 3 plan D14: Stripe's hosted onboarding link for the academy's
    Express account. Never as someone else (ledger D19)."""

    permission_classes = [HasCode, NotImpersonating]
    permission_codes = {"POST": UPDATE}

    def post(self, request):
        url = services.start_onboarding(
            country=request.data.get("country"), by=request.user
        )
        return Response({"url": url})
```

In `backend/etqan/integrations/api/payloads.py` `card`, add after building the dict (name it `payload` and return it):

```python
    if service == "payments":
        # Owner D22: the countries where the academy can Connect with Stripe.
        payload["connect_countries"] = sorted(services.CONNECT_COUNTRIES)
```

In `backend/etqan/integrations/api/urls.py`, add before the `<slug:service>/` routes:

```python
    path("payments/connect/", views.ConnectStripeView.as_view(), name="connect-stripe"),
```

In `backend/etqan/integrations/admin.py`, extend `FORM_FIELDS` with `"secret_key": "secret", "connect_webhook_secret": "secret", "platform_webhook_secret": "secret"`, and add the payments shape to the `secret` help text: `'{"secret_key": "sk_…", "connect_webhook_secret": "whsec_…", "platform_webhook_secret": "whsec_…"} for Stripe Connect; '`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DJ pytest etqan/integrations etqan/access -q`
Expected: PASS — including `test_every_service_has_a_provider_and_which_connect` and the route table.

- [ ] **Step 5: Commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports
git -C backend add etqan/integrations etqan/access/tests/test_routes.py
git -C backend commit -m "feat(integrations): Etqan's Stripe platform keys and Connect onboarding" -m "$TRAILER"
```

---

### Task 8: Checkouts through Connect, own keys first, Etqan's application fee

**Files:**
- Create: `backend/etqan/gateways/services/connect.py`, `backend/etqan/gateways/migrations/0004_checkout_connect.py` (generated), `backend/etqan/gateways/tests/test_connect_checkouts.py`
- Modify: `backend/etqan/gateways/models.py`, `backend/etqan/gateways/providers/base.py`, `backend/etqan/gateways/providers/stripe.py`, `backend/etqan/gateways/services/checkouts.py`, `backend/etqan/gateways/services/fees.py`, `backend/etqan/gateways/services/links.py`, `backend/etqan/gateways/services/__init__.py`, `backend/etqan/gateways/tests/conftest.py`, `backend/pyproject.toml` (only if `lint-imports` asks)

**Interfaces:**
- Consumes: `integrations.services.stripe_connect() -> StripeConnect | None` (Task 7); `etqan_billing.services.connect_fee() -> ConnectFeeTerms | None` (slice 2); `etqan.platform.currency.minor_digits`; `etqan.platform.stripe` (Task 1).
- Produces: `etqan.gateways.providers.base.ConnectAccount(account_id: str, mode: str, secret: str, provider: str = "stripe", enabled: bool = True)`; `gateways.services.connect_account() -> ConnectAccount | None`, `stripe_route() -> GatewayAccount | ConnectAccount | None`, `enabled_providers() -> set[str]`, `application_fee(total_minor: int, currency: str) -> int`; `Checkout.via_connect: bool`, `Checkout.platform_fee_minor: int`; gateways test fixture `connect_on`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/etqan/gateways/tests/conftest.py`:

```python
CONNECT_KEY = "sk_test_<redacted>"


@pytest.fixture
def connect_on(online_on):
    """Integrations slice 3: Etqan's Stripe platform is the payments default
    and the academy's Connect account `acct_noor` takes charges."""
    from django.db import connection  # noqa: PLC0415

    from etqan.integrations import services as integrations  # noqa: PLC0415
    from etqan.integrations.accounts.models import AcademyAccount  # noqa: PLC0415
    from etqan.integrations.models import PlatformAccount  # noqa: PLC0415

    PlatformAccount.objects.filter(service="payments").update(
        enabled=True,
        config={"mode": "test"},
        secret_enc=integrations.write_secrets(
            {
                "secret_key": CONNECT_KEY,
                "connect_webhook_secret": "whsec_<redacted>",
                "platform_webhook_secret": "whsec_<redacted>",
            }
        ),
    )
    AcademyAccount.objects.update_or_create(
        service="payments",
        defaults={
            "enabled": True,
            "config": {"account_id": "acct_noor", "status": "active", "country": "AE", "mode": "test"},
        },
    )
    integrations.add_route(integrations.STRIPE_ACCOUNT, "acct_noor")
    integrations.clear_cache()
    return connection.tenant


@pytest.fixture
def connect_fee():
    """``connect_fee(250, fixed=0, currency="EGP")``: Etqan's Connect fee
    for the academy (slice 2's ConnectFee)."""
    from django.db import connection  # noqa: PLC0415

    from etqan.etqan_billing.models import ConnectFee  # noqa: PLC0415

    def make(percent_bp, *, fixed=0, currency="EGP"):
        return ConnectFee.objects.update_or_create(
            academy_id=connection.tenant.pk,
            defaults={"percent_bp": percent_bp, "fixed_amount": fixed, "currency": currency},
        )[0]

    return make
```

Create `backend/etqan/gateways/tests/test_connect_checkouts.py`:

```python
"""Integrations slice 3 plan D17–D18: with no own Stripe keys on, Stripe
is offered through the academy's Connect account; the session is made on
it with Etqan's application fee; own keys always win."""

from urllib.parse import parse_qsl

import httpx
import pytest

from etqan.gateways import services
from etqan.gateways.models import Checkout
from etqan.gateways.providers.stripe import API
from etqan.gateways.tests.conftest import CONNECT_KEY
from etqan.gateways.tests.conftest import as_user

pytestmark = pytest.mark.django_db
SESSIONS = f"{API}/checkout/sessions"


@pytest.fixture
def family(parent_of_world, invoice):
    return parent_of_world, invoice()


def session_ok(respx_mock, ref="cs_test_connect_1"):
    return respx_mock.post(SESSIONS).mock(
        return_value=httpx.Response(200, json={"id": ref, "url": f"https://checkout.stripe.com/{ref}"})
    )


def start(parent, bill):
    return services.start_checkout("invoice", bill.pk, "stripe", user=parent)


def test_a_connect_checkout_pays_into_the_academys_account_with_etqans_fee(
    connect_on, connect_fee, family, respx_mock
):
    connect_fee(250)
    parent, bill = family
    route = session_ok(respx_mock)
    started = start(parent, bill)
    assert started.redirect_url == "https://checkout.stripe.com/cs_test_connect_1"
    checkout = Checkout.objects.get(pk=started.id)
    assert (checkout.via_connect, checkout.simulated) == (True, False)
    # 500.00 + 25.00 family fee = 52500; 2.5 % half up = 1313.
    assert checkout.platform_fee_minor == 1313
    request = route.calls[0].request
    assert request.headers["Stripe-Account"] == "acct_noor"
    sent = dict(parse_qsl(request.content.decode()))
    assert sent["payment_intent_data[application_fee_amount]"] == "1313"
    assert sent["metadata[checkout]"] == str(checkout.pk)


def test_without_a_fee_row_no_application_fee_is_sent(connect_on, family, respx_mock):
    parent, bill = family
    route = session_ok(respx_mock)
    checkout = Checkout.objects.get(pk=start(parent, bill).id)
    assert checkout.platform_fee_minor == 0
    sent = dict(parse_qsl(route.calls[0].request.content.decode()))
    assert "payment_intent_data[application_fee_amount]" not in sent


def test_own_keys_win_over_connect(connect_on, connect_fee, stripe_on, family, respx_mock):
    connect_fee(250)
    parent, bill = family
    route = session_ok(respx_mock)
    checkout = Checkout.objects.get(pk=start(parent, bill).id)
    # B3 exactly as before: the own test keys and the simulator.
    assert (checkout.via_connect, checkout.simulated, checkout.platform_fee_minor) == (False, True, 0)
    assert not route.called


def test_stripe_is_offered_with_connect_alone_and_not_without_it(connect_on):
    assert services.providers_for("EGP", 50000, add_fee=True) == ["stripe"]
    from etqan.integrations.accounts.models import AcademyAccount  # noqa: PLC0415
    from etqan.integrations import services as integrations  # noqa: PLC0415

    AcademyAccount.objects.filter(service="payments").update(config={"account_id": "acct_noor", "status": "pending", "mode": "test"})
    integrations.clear_cache()
    assert services.providers_for("EGP", 50000, add_fee=True) == []


def test_a_pending_connect_account_cannot_take_a_checkout(connect_on, family):
    from etqan.integrations.accounts.models import AcademyAccount  # noqa: PLC0415
    from etqan.platform.exceptions import ValidationError  # noqa: PLC0415

    AcademyAccount.objects.filter(service="payments").update(enabled=False, config={"account_id": "acct_noor", "status": "pending", "mode": "test"})
    parent, bill = family
    with pytest.raises(ValidationError):
        start(parent, bill)


def test_reuse_and_superseding_stay_within_one_route(connect_on, family, respx_mock):
    parent, bill = family
    session_ok(respx_mock)
    expire = respx_mock.post(f"{SESSIONS}/cs_test_connect_1/expire").mock(
        return_value=httpx.Response(200, json={})
    )
    first = start(parent, bill)
    assert start(parent, bill).id == first.id  # reused on the same route
    services.update_settings(
        stripe={"enabled": True, "mode": "test", "public_key": "pk_test_<redacted>", "secret": "sk_test_<redacted>", "webhook_secret": "whsec_<redacted>"},
        by=None,
    )
    second = start(parent, bill)
    assert second.id != first.id
    assert Checkout.objects.get(pk=first.id).status == Checkout.Status.CANCELLED
    assert not expire.called  # never expired with the other route's keys


def test_the_fee_is_percent_plus_fixed_in_its_currency_only(connect_on, connect_fee):
    connect_fee(250, fixed=300, currency="EGP")
    assert services.application_fee(10000, "EGP") == 550
    assert services.application_fee(10000, "USD") == 250


def test_three_decimal_fees_are_multiples_of_ten_and_never_above_the_total(connect_on, connect_fee):
    connect_fee(333, currency="KWD")
    assert services.application_fee(10010, "KWD") == 330  # 333 floored to 10s
    connect_fee(10000, fixed=500, currency="EGP")
    assert services.application_fee(1000, "EGP") == 1000


def test_the_platform_key_signs_the_connect_request(connect_on, family, respx_mock):
    import base64  # noqa: PLC0415

    parent, bill = family
    route = session_ok(respx_mock)
    start(parent, bill)
    auth = route.calls[0].request.headers["Authorization"].removeprefix("Basic ")
    assert base64.b64decode(auth).decode() == f"{CONNECT_KEY}:"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DJ pytest etqan/gateways/tests/test_connect_checkouts.py -q`
Expected: FAIL — `ValidationError: This payment method is not available.` (no own Stripe account) and `AttributeError: … has no attribute 'application_fee'`.

- [ ] **Step 3: Write minimal implementation**

In `backend/etqan/gateways/models.py`, add to `Checkout` after `fee_minor`:

```python
    # Integrations slice 3 (plan D17): paid into the academy's Stripe Connect
    # account on Etqan's platform, and Etqan's application fee on it (minor
    # units). New columns on an existing table: database defaults.
    via_connect = models.BooleanField(default=False, db_default=False)
    platform_fee_minor = models.BigIntegerField(default=0, db_default=0)
```

Run: `$DJ python manage.py makemigrations gateways --name checkout_connect`
Expected: `gateways/migrations/0004_checkout_connect.py` adding the two fields.

Append to `backend/etqan/gateways/providers/base.py` (add `from dataclasses import field`):

```python
@dataclass(frozen=True)
class ConnectAccount:
    """Integrations slice 3 (plan D17): the academy's Stripe Connect account
    on Etqan's platform, standing where B3's GatewayAccount stands for a
    checkout. ``secret`` is Etqan's platform key."""

    account_id: str
    mode: str
    secret: str = field(repr=False)
    provider: str = "stripe"
    enabled: bool = True
```

In `backend/etqan/gateways/providers/stripe.py`, import `ConnectAccount` from `etqan.gateways.providers.base`, add

```python
def _credentials(account) -> tuple[str, str]:
    """The key to use and, for Connect, the account to act on."""
    if isinstance(account, ConnectAccount):
        return account.secret, account.account_id
    return secret_of(account), ""
```

change the `stripe.call(...)` in `_post` to

```python
            key, on_behalf = _credentials(account)
            return stripe.call(
                "POST", path, key=key, data=data, idempotency=idempotency, account=on_behalf
            )
```

(move `key, on_behalf = _credentials(account)` above the `try`), and in `create`, after the family-fee line block, add:

```python
        if checkout.via_connect and checkout.platform_fee_minor > 0:
            data.append(
                (
                    "payment_intent_data[application_fee_amount]",
                    str(checkout.platform_fee_minor),
                )
            )
```

Create `backend/etqan/gateways/services/connect.py`:

```python
"""Stripe Connect for checkouts (spec IN-4; integrations slice 3 plan
D17–D18). The academy's own Stripe keys (B3) come first, as the resolver's
step 1; else its Connect account on Etqan's platform, when integrations says
it takes charges. Etqan's fee rides on the payment as `application_fee`."""

from etqan.etqan_billing import services as billing
from etqan.gateways.models import GatewayAccount
from etqan.gateways.providers.base import ConnectAccount
from etqan.integrations import services as integrations
from etqan.platform.currency import minor_digits

STRIPE = GatewayAccount.Provider.STRIPE


def connect_account() -> ConnectAccount | None:
    found = integrations.stripe_connect()
    if found is None:
        return None
    return ConnectAccount(found.account_id, found.mode, found.secret_key)


def stripe_route() -> GatewayAccount | ConnectAccount | None:
    """Plan D17: own enabled keys, else Connect, else none."""
    own = GatewayAccount.objects.filter(provider=STRIPE, enabled=True).first()
    return own or connect_account()


def enabled_providers() -> set[str]:
    enabled = set(
        GatewayAccount.objects.filter(enabled=True).values_list("provider", flat=True)
    )
    if STRIPE not in enabled and connect_account() is not None:
        enabled.add(STRIPE)
    return enabled


def application_fee(total_minor: int, currency: str) -> int:
    """Plan D18: the percent half up, plus the fixed part when it is in this
    currency; multiples of 10 for three-decimal currencies; never above the
    total. 0 when Etqan set no fee for the academy."""
    terms = billing.connect_fee()
    if terms is None:
        return 0
    fee = (total_minor * terms.percent_bp + 5000) // 10000
    if terms.fixed_amount and terms.currency.upper() == currency.upper():
        fee += terms.fixed_amount
    if minor_digits(currency) == 3:  # noqa: PLR2004
        fee -= fee % 10
    return max(0, min(fee, total_minor))
```

In `backend/etqan/gateways/services/checkouts.py`:
- import `ConnectAccount` from `etqan.gateways.providers.base` and `application_fee`, `stripe_route` from `etqan.gateways.services.connect`;
- replace `_account` with

```python
def _account(provider: str):
    """Plan D17: Stripe is the academy's own keys, else its Connect account."""
    if provider == GatewayAccount.Provider.STRIPE:
        account = stripe_route()
    else:
        account = GatewayAccount.objects.filter(provider=provider, enabled=True).first()
    if account is None:
        raise ValidationError("This payment method is not available.", field="provider")
    return account
```

- in `_reusable`, make `mine` `(old.amount_minor, old.fee_minor, old.simulated, old.created_by_id, old.via_connect)`;
- in `_expire`, skip a superseded checkout of the other route: change its condition to `if old.provider_ref and old.simulated == simulate and old.via_connect == isinstance(account, ConnectAccount):`;
- in `start_checkout`, replace the `simulate = …` line and the `wanted = …` line and the `Checkout.objects.create(...)` call with:

```python
    via_connect = isinstance(account, ConnectAccount)
    # Plan D17: the simulator plays only B3's own test keys.
    simulate = (
        settings.GATEWAYS_SIMULATE
        and not via_connect
        and account.mode == GatewayAccount.Mode.TEST
    )
```

```python
        wanted = (prepared.amount_minor, fee, simulate, getattr(user, "pk", None), via_connect)
```

```python
        checkout = Checkout.objects.create(
            purpose=purpose,
            reference_id=reference_id,
            provider=provider,
            simulated=simulate,
            amount_minor=prepared.amount_minor,
            fee_minor=fee,
            currency=prepared.currency,
            description=prepared.description[:200],
            created_by=user,
            via_connect=via_connect,
            platform_fee_minor=(
                application_fee(prepared.amount_minor + fee, prepared.currency)
                if via_connect
                else 0
            ),
        )
```

In `backend/etqan/gateways/services/fees.py`, import `enabled_providers` from `etqan.gateways.services.connect` and, in `providers_for`, replace the `enabled = set(…)` block with `enabled = enabled_providers()`.

In `backend/etqan/gateways/services/links.py`, import `enabled_providers` the same way and replace the body of `_provider_takes` with:

```python
    return link.provider in enabled_providers() and _fee_quote(link) is not None
```

(`connect.py` imports only gateways' models and providers, integrations and etqan_billing services, and the platform: no cycle.)

In `backend/etqan/gateways/services/__init__.py`, add (sorted) imports and `__all__` entries for `application_fee`, `connect_account`, `enabled_providers`, `stripe_route` from `etqan.gateways.services.connect`.

Run `$DJ lint-imports`. If a contract names `etqan.etqan_billing` or `etqan.integrations` as forbidden for `etqan.gateways`, it should not (gateways may use their services); if "other apps reach etqan_billing only through its services" lacks `"etqan.gateways"` in `source_modules`, add it there in `backend/pyproject.toml` (one additive edit in the Integrations block).

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DJ pytest etqan/gateways --create-db -q`
Expected: PASS — the new Connect tests and every B3 test (own keys, PayPal, links, expiry, simulator) unchanged.

- [ ] **Step 5: Commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports
git -C backend add etqan/gateways pyproject.toml
git -C backend commit -m "feat(gateways): Stripe Connect checkouts with Etqan's application fee; own keys first" -m "$TRAILER"
```

---

### Task 9: The Connect webhook on the base domain

**Files:**
- Create: `backend/etqan/gateways/services/connect_webhooks.py`, `backend/etqan/gateways/tests/test_connect_webhooks.py`
- Modify: `backend/etqan/gateways/services/webhooks.py` (extract `apply_event`), `backend/etqan/gateways/services/__init__.py`, `backend/etqan/gateways/api/views.py`, `backend/config/urls_public.py`

**Interfaces:**
- Consumes: `verify_stripe`, `sign_stripe`, `BadSignature` (B3); `integrations.services.connect_webhook_secrets`, `stripe_platform`, `route_schema`, `STRIPE_ACCOUNT`, `apply_connect_account` (Task 7); `etqan_billing.services.record_collected_fee` (slice 2); `ConnectAccount` (Task 8); `academy_context`.
- Produces: `gateways.services.apply_event(event: dict, account) -> None`, `process_connect(raw: bytes, header: str) -> None`; `ConnectWebhookView`; base-domain route `webhook-stripe-connect` at `/api/v1/webhooks/stripe-connect/`.

- [ ] **Step 1: Write the failing tests**

Create `backend/etqan/gateways/tests/test_connect_webhooks.py`:

```python
"""Integrations slice 3 plan D19: Etqan's one Connect endpoint on the base
domain. Verified with either of Etqan's two signing secrets; routed to the
academy whose account it names; account status, collected fees, and the
academy's Connect checkouts through B3's own handler."""

import json
import uuid
from datetime import UTC
from datetime import datetime

import httpx
import pytest
from django.db import connection
from django.test import Client

from etqan.etqan_billing.models import CollectedFee
from etqan.gateways import services
from etqan.gateways.models import Checkout
from etqan.gateways.models import WebhookEvent
from etqan.gateways.providers.stripe import API
from etqan.integrations.accounts.models import AcademyAccount

pytestmark = pytest.mark.django_db
URL = "/api/v1/webhooks/stripe-connect/"
PUBLIC_HOST = "etqan.localhost"
NOW = datetime(2026, 6, 1, 8, tzinfo=UTC)
CONNECT = "whsec_<redacted>"
PLATFORM = "whsec_<redacted>"


def post(event, *, secret=CONNECT, host=PUBLIC_HOST):
    raw = json.dumps(event).encode()
    header = services.sign_stripe(raw, secret, int(NOW.timestamp()))
    connection.set_schema_to_public()
    return Client().post(
        URL, data=raw, content_type="application/json", HTTP_HOST=host, HTTP_STRIPE_SIGNATURE=header
    )


def event(kind, obj, *, account="acct_noor", livemode=False):
    body = {"id": f"evt_{uuid.uuid4().hex}", "type": kind, "livemode": livemode, "data": {"object": obj}}
    if account:
        body["account"] = account
    return body


def fee(fee_id="fee_1", amount=1313):
    return event(
        "application_fee.created",
        {"id": fee_id, "object": "application_fee", "amount": amount, "currency": "egp", "account": "acct_noor", "created": int(NOW.timestamp())},
        account=None,
    )


@pytest.fixture
def connect(connect_on, clock):
    return connect_on


def test_account_updated_moves_the_status(connect):
    AcademyAccount.objects.filter(service="payments").update(config={"account_id": "acct_noor", "status": "pending", "mode": "test"}, enabled=False)
    assert post(event("account.updated", {"id": "acct_noor", "charges_enabled": True})).status_code == 200
    connection.set_tenant(connect)
    row = AcademyAccount.objects.get(service="payments")
    assert (row.config["status"], row.enabled) == ("active", True)


def test_a_fee_is_recorded_for_the_academy(connect, tenants):
    assert post(fee(), secret=PLATFORM).status_code == 200
    collected = CollectedFee.objects.get()
    assert (collected.academy_id, collected.amount, collected.currency, collected.source_ref) == (
        tenants.main.pk,
        1313,
        "EGP",
        "fee_1",
    )
    assert collected.occurred_at == NOW


def test_a_replayed_fee_is_recorded_once(connect):
    post(fee(), secret=PLATFORM)
    post(fee(), secret=PLATFORM)
    assert CollectedFee.objects.count() == 1


def test_either_signing_secret_is_accepted_and_nothing_else(connect):
    assert post(fee("fee_a"), secret=CONNECT).status_code == 200
    assert post(fee("fee_b"), secret=PLATFORM).status_code == 200
    assert post(fee("fee_c"), secret="whsec_<redacted>").status_code == 400
    assert sorted(CollectedFee.objects.values_list("source_ref", flat=True)) == ["fee_a", "fee_b"]


def test_an_unknown_account_is_ignored(connect):
    resp = post(event("account.updated", {"id": "acct_other", "charges_enabled": False}, account="acct_other"))
    assert resp.status_code == 200
    connection.set_tenant(connect)
    assert AcademyAccount.objects.get(service="payments").config["status"] == "active"


def test_a_connect_checkout_completes_through_b3s_handler(connect, parent_of_world, invoice, respx_mock):
    respx_mock.post(f"{API}/checkout/sessions").mock(
        return_value=httpx.Response(200, json={"id": "cs_test_c1", "url": "https://checkout.stripe.com/c1"})
    )
    bill = invoice()
    started = services.start_checkout("invoice", bill.pk, "stripe", user=parent_of_world)
    obj = {
        "id": "cs_test_c1",
        "object": "checkout.session",
        "client_reference_id": str(started.id),
        "metadata": {"checkout": str(started.id)},
        "payment_status": "paid",
        "amount_total": started.amount_minor + started.fee_minor,
        "currency": "egp",
        "payment_intent": "pi_c1",
    }
    completed = event("checkout.session.completed", obj)
    assert post(completed).status_code == 200
    assert post(completed).status_code == 200  # a replay does nothing
    connection.set_tenant(connect)
    checkout = Checkout.objects.get(pk=started.id)
    assert (checkout.status, checkout.applied, checkout.transaction_number) == ("completed", True, "pi_c1")
    assert WebhookEvent.objects.filter(event_id=completed["id"]).count() == 1


def test_a_live_event_for_a_test_platform_needs_attention(connect, parent_of_world, invoice, respx_mock):
    respx_mock.post(f"{API}/checkout/sessions").mock(
        return_value=httpx.Response(200, json={"id": "cs_test_c2", "url": "https://checkout.stripe.com/c2"})
    )
    started = services.start_checkout("invoice", invoice().pk, "stripe", user=parent_of_world)
    obj = {"id": "cs_test_c2", "metadata": {"checkout": str(started.id)}, "payment_status": "paid", "amount_total": started.amount_minor + started.fee_minor, "currency": "egp"}
    post(event("checkout.session.completed", obj, livemode=True))
    connection.set_tenant(connect)
    assert Checkout.objects.get(pk=started.id).attention == "mode_mismatch"


def test_the_endpoint_is_not_on_an_academy_host(connect):
    assert post(fee(), secret=PLATFORM, host="testserver").status_code == 404
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DJ pytest etqan/gateways/tests/test_connect_webhooks.py -q`
Expected: FAIL — 404 on the base domain (no route yet).

- [ ] **Step 3: Write minimal implementation**

In `backend/etqan/gateways/services/webhooks.py`, split `process_stripe` so its recording-and-applying half is reusable:

```python
def apply_event(event: dict, account) -> None:
    """Record ``event`` once and apply it to its checkout in this academy:
    B3's own endpoint and, from integrations slice 3, Etqan's Connect
    endpoint (``account`` a ConnectAccount) both end here."""
    data = event.get("data") if isinstance(event.get("data"), dict) else {}
    obj = data.get("object") if isinstance(data.get("object"), dict) else {}
    with transaction.atomic():
        try:
            with transaction.atomic():
                record = WebhookEvent.objects.create(
                    provider=STRIPE,
                    event_id=event["id"][:255],
                    type=str(event.get("type") or "")[:100],
                )
        except IntegrityError:
            return  # a replay
        found = _find(obj)
        if found is None:
            logger.info("Stripe event %s names no checkout here", event["id"])
            return
        record.checkout = found
        record.save(update_fields=["checkout"])
        checkout = Checkout.objects.select_for_update().get(pk=found.pk)
        _apply(checkout, obj, event, account)


def process_stripe(raw: bytes, header: str) -> None:
    """Raises BadSignature (400; also when this academy has no Stripe
    account, plan L10: it is read, never created, for anonymous callers),
    UnavailableError (503, no key) or whatever a purpose raises (500,
    rolled back)."""
    account = GatewayAccount.objects.filter(provider=STRIPE).first()
    if account is None:
        raise BadSignature
    event = verify_stripe(raw, header, webhook_secret_of(account))
    apply_event(event, account)
```

Create `backend/etqan/gateways/services/connect_webhooks.py`:

```python
"""Etqan's Stripe Connect endpoint (integrations slice 3 plan D19), on the
base domain. One URL for Stripe's two endpoints (connected accounts; Etqan's
own account), so a body verifies under either signing secret. The account
an event names is routed to its academy; an unrouted one is not ours."""

import logging
from datetime import UTC
from datetime import datetime

from etqan.etqan_billing import services as billing
from etqan.gateways.providers.base import ConnectAccount
from etqan.gateways.services.webhooks import ASYNC_FAILED
from etqan.gateways.services.webhooks import ASYNC_SUCCEEDED
from etqan.gateways.services.webhooks import COMPLETED_SESSION
from etqan.gateways.services.webhooks import SESSION_EXPIRED
from etqan.gateways.services.webhooks import BadSignature
from etqan.gateways.services.webhooks import apply_event
from etqan.gateways.services.webhooks import verify_stripe
from etqan.integrations import services as integrations
from etqan.platform.tenancy import academy_context

ACCOUNT_UPDATED = "account.updated"
FEE_CREATED = "application_fee.created"
SESSION_EVENTS = (COMPLETED_SESSION, ASYNC_SUCCEEDED, ASYNC_FAILED, SESSION_EXPIRED)
logger = logging.getLogger(__name__)


def _verified(raw: bytes, header: str) -> dict:
    for secret in integrations.connect_webhook_secrets():
        try:
            return verify_stripe(raw, header, secret)
        except BadSignature:
            continue
    raise BadSignature


def _record_fee(obj: dict) -> None:
    amount, currency, fee_id = obj.get("amount"), obj.get("currency"), obj.get("id")
    created = obj.get("created")
    if not (
        isinstance(amount, int)
        and not isinstance(amount, bool)
        and amount > 0
        and isinstance(currency, str)
        and isinstance(fee_id, str)
        and fee_id
    ):
        logger.info("Stripe fee event without its amount; ignored")
        return
    when = (
        datetime.fromtimestamp(created, UTC)
        if isinstance(created, int) and not isinstance(created, bool)
        else None
    )
    billing.record_collected_fee(
        amount=amount, currency=currency, source_ref=fee_id, occurred_at=when
    )


def process_connect(raw: bytes, header: str) -> None:
    """Raises BadSignature (400). Anything about an account Etqan never
    routed, or of a kind not handled here, is a 200 that does nothing."""
    event = _verified(raw, header)
    data = event.get("data") if isinstance(event.get("data"), dict) else {}
    obj = data.get("object") if isinstance(data.get("object"), dict) else {}
    kind = event.get("type")
    account_id = event.get("account") or (obj.get("account") if kind == FEE_CREATED else "")
    if not isinstance(account_id, str) or not account_id:
        return
    schema = integrations.route_schema(integrations.STRIPE_ACCOUNT, account_id)
    if schema is None:
        logger.info("Connect event %s names no academy", event["id"])
        return
    platform = integrations.stripe_platform()
    with academy_context(schema):
        if kind == ACCOUNT_UPDATED:
            integrations.apply_connect_account(obj)
        elif kind == FEE_CREATED:
            _record_fee(obj)
        elif kind in SESSION_EVENTS and platform is not None:
            apply_event(
                event, ConnectAccount(account_id, platform.mode, platform.secret_key)
            )
```

In `backend/etqan/gateways/services/__init__.py`, add (sorted) imports and `__all__` entries for `apply_event` (from `webhooks`) and `process_connect` (from `connect_webhooks`).

In `backend/etqan/gateways/api/views.py`, below `StripeWebhookView`:

```python
class ConnectWebhookView(APIView):
    """Integrations slice 3 (plan D19): Etqan's Connect endpoint, on the base
    domain only (config/urls_public.py). Unauthenticated (so CSRF-free),
    verified over the raw body, not throttled, non-atomic."""

    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_classes: list = []
    atomic_request = False

    def post(self, request):
        try:
            services.process_connect(
                request.body, request.headers.get("Stripe-Signature", "")
            )
        except services.BadSignature:
            return Response({"detail": "Bad signature."}, status=400)
        except Exception:
            logger.exception("Stripe Connect event failed")
            return Response({"detail": "Not processed."}, status=500)
        return Response({"received": True})
```

In `backend/config/urls_public.py`, import `ConnectWebhookView` from `etqan.gateways.api.views` and add below the Zoom route:

```python
    path(
        "api/v1/webhooks/stripe-connect/",
        transaction.non_atomic_requests(ConnectWebhookView.as_view()),
        name="webhook-stripe-connect",
    ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DJ pytest etqan/gateways etqan/integrations -q`
Expected: PASS — the Connect endpoint tests and B3's own webhook tests (now through `apply_event`) unchanged.

- [ ] **Step 5: Commit**

```bash
$DJ sh -c 'ruff check --fix . && ruff format .' && $DJ lint-imports
git -C backend add etqan/gateways config/urls_public.py
git -C backend commit -m "feat(gateways): Etqan's Stripe Connect webhook: status, collected fees, checkouts" -m "$TRAILER"
```

---

### Task 10: Dashboard data layer and strings for Zoom and Connect

**Files:**
- Create: `dashboard/src/features/integrations/redirect.ts`
- Modify: `dashboard/src/features/integrations/schemas.ts`, `schemas.test.ts`, `api.ts`, `api.test.ts`, `index.ts`, `dashboard/src/test/integrations-fixtures.ts`, `dashboard/src/locales/en/integrations.json`, `dashboard/src/locales/ar/integrations.json`

**Interfaces:**
- Consumes: the API of Tasks 3 and 7: `PUT integrations/video/` (Zoom fields), `POST integrations/payments/connect/ {country}` → `{url}`, `POST integrations/payments/test/`, card `own.config` for payments `{account_id, status, country, mode}`.
- Produces: `CONNECT_STATUSES`, `ConnectStatus`, `ConnectState {account_id, status, country}`, `connectOf(own: OwnAccount | null): ConnectState | null`, `ZoomConfig`, `ZoomBody`, `zoomFormSchema`, `ZoomForm`, `zoomDefaults(own)`, `zoomBody(values)`, `IntegrationCard.connect_countries?: string[]`; `integrationsApi.connectStripe(country: string): Promise<{ url: string }>`; `go(url: string): void` in `redirect.ts`; fixtures `ownZoom(overrides)`, `ownConnect(status, overrides)`; strings under `integrations.zoom.*`, `integrations.connect.*`, new `integrations.errors.*`.

- [ ] **Step 1: Write the failing tests**

Append to `dashboard/src/features/integrations/schemas.test.ts` (merge the imports into the file's existing import from `./schemas`):

```ts
import { ownConnect, ownZoom } from "@/test/integrations-fixtures";
import {
	connectOf,
	zoomBody,
	zoomDefaults,
	zoomFormSchema,
} from "./schemas";

describe("connectOf", () => {
	it("reads the payments row as the Connect account", () => {
		expect(connectOf(ownConnect("pending"))).toEqual({
			account_id: "acct_noor",
			status: "pending",
			country: "AE",
		});
	});

	it("is null without an account or with an unknown status", () => {
		expect(connectOf(null)).toBeNull();
		expect(connectOf(ownConnect("active", { config: {} }))).toBeNull();
		expect(
			connectOf(ownConnect("active", { config: { account_id: "acct_1", status: "weird" } })),
		).toBeNull();
	});
});

describe("zoom form", () => {
	it("starts from the stored account with a blank secret", () => {
		expect(zoomDefaults(ownZoom())).toEqual({
			account_id: "zoomacct123",
			client_id: "zoomclient456",
			client_secret: "",
			host_user: "me",
			enabled: true,
		});
		expect(zoomDefaults(null).host_user).toBe("me");
	});

	it("leaves a blank secret out of the body", () => {
		const values = { ...zoomDefaults(ownZoom()), account_id: " acct2 " };
		expect(zoomBody(values)).toEqual({
			account_id: "acct2",
			client_id: "zoomclient456",
			host_user: "me",
			enabled: true,
		});
		expect(zoomBody({ ...values, client_secret: "s3cret" }).client_secret).toBe("s3cret");
	});

	it("needs the ids and takes me or an email as host", () => {
		const base = zoomDefaults(ownZoom());
		expect(zoomFormSchema.safeParse({ ...base, account_id: "" }).success).toBe(false);
		expect(zoomFormSchema.safeParse({ ...base, host_user: "host@noor.test" }).success).toBe(true);
		expect(zoomFormSchema.safeParse({ ...base, host_user: "nobody" }).success).toBe(false);
	});

});
```

Add inside the `describe("integrationsApi", …)` block of `dashboard/src/features/integrations/api.test.ts`:

```ts
	it("starts Stripe onboarding with the country and answers the link", async () => {
		const post = vi
			.spyOn(api, "post")
			.mockResolvedValue({ data: { url: "https://connect.stripe.com/x" } } as never);
		expect(await integrationsApi.connectStripe("AE")).toEqual({
			url: "https://connect.stripe.com/x",
		});
		expect(post).toHaveBeenCalledWith("integrations/payments/connect/", {
			country: "AE",
		});
	});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DASH pnpm vitest run src/features/integrations/schemas.test.ts src/features/integrations/api.test.ts`
Expected: FAIL — `connectOf`, `zoomDefaults`, `ownZoom`, `connectStripe` not exported.

- [ ] **Step 3: Write minimal implementation**

Append to `dashboard/src/features/integrations/schemas.ts`:

```ts
// Integrations slice 3 (plan D12, D14): the payments row is the academy's
// Stripe Connect account; its status says what it can do.
export const CONNECT_STATUSES = ["onboarding", "pending", "active"] as const;
export type ConnectStatus = (typeof CONNECT_STATUSES)[number];

export interface ConnectState {
	account_id: string;
	status: ConnectStatus;
	country: string;
}

export function connectOf(own: OwnAccount | null): ConnectState | null {
	const config = own?.config ?? {};
	const status = CONNECT_STATUSES.find((value) => value === config.status);
	const id = config.account_id;
	if (typeof id !== "string" || !id || !status) return null;
	return {
		account_id: id,
		status,
		country: typeof config.country === "string" ? config.country : "",
	};
}
```

In `IntegrationCard` (same file), add the optional field:

```ts
	/** Owner D22: on the payments card only, where Stripe Connect serves. */
	connect_countries?: string[];
```

and append:

```ts
// Integrations slice 3 (plan D5): a Zoom Server-to-Server OAuth app.
export interface ZoomConfig {
	account_id: string;
	client_id: string;
	host_user: string;
}

export interface ZoomBody extends ZoomConfig {
	enabled: boolean;
	/** Left out to keep the stored one (slice 1 plan D15). */
	client_secret?: string;
}

const isHost = (value: string) =>
	value === "" || value === "me" || z.email().safeParse(value).success;

export const zoomFormSchema = z.object({
	account_id: z.string().trim().min(1, `${E}.required`).max(64, `${E}.tooLong`),
	client_id: z.string().trim().min(1, `${E}.required`).max(64, `${E}.tooLong`),
	client_secret: z.string().max(128, `${E}.tooLong`),
	host_user: z
		.string()
		.trim()
		.max(254, `${E}.tooLong`)
		.refine(isHost, `${E}.hostUser`),
	enabled: z.boolean(),
});
export type ZoomForm = z.infer<typeof zoomFormSchema>;

export function zoomDefaults(own: OwnAccount | null): ZoomForm {
	const config = (own?.config ?? {}) as Partial<ZoomConfig>;
	return {
		account_id: config.account_id ?? "",
		client_id: config.client_id ?? "",
		client_secret: "",
		host_user: config.host_user ?? "me",
		enabled: own?.enabled ?? true,
	};
}

export function zoomBody(values: ZoomForm): ZoomBody {
	const body: ZoomBody = {
		account_id: values.account_id.trim(),
		client_id: values.client_id.trim(),
		host_user: values.host_user.trim() || "me",
		enabled: values.enabled,
	};
	const secret = values.client_secret.trim();
	if (secret) body.client_secret = secret;
	return body;
}
```

In `dashboard/src/features/integrations/api.ts`, import `ZoomBody`, widen `connect`'s body to `EmailBody | ZoomBody` (with B10a merged: `EmailBody | AiBody | ZoomBody`), and add:

```ts
	/** Slice 3 plan D14: Stripe's hosted onboarding link. */
	connectStripe: async (country: string) =>
		(await api.post<{ url: string }>(`${I}payments/connect/`, { country }))
			.data,
```

Create `dashboard/src/features/integrations/redirect.ts`:

```ts
/** The one full-page navigation (to Stripe's onboarding): its own module so
 * tests replace it. */
export function go(url: string): void {
	window.location.assign(url);
}
```

In `dashboard/src/test/integrations-fixtures.ts`, leave `card()` as it is (its defaults keep every existing page test meaningful; new tests pass `connectable: true` explicitly) and add:

```ts
export function ownZoom(overrides: Partial<OwnAccount> = {}): OwnAccount {
	return {
		enabled: true,
		config: { account_id: "zoomacct123", client_id: "zoomclient456", host_user: "me" },
		secret_last4: "7890",
		last_test_at: null,
		last_test_ok: null,
		last_test_error: "",
		updated_at: "2026-10-09T07:00:00Z",
		...overrides,
	};
}

export function ownConnect(
	status: "onboarding" | "pending" | "active",
	overrides: Partial<OwnAccount> = {},
): OwnAccount {
	return {
		enabled: status === "active",
		config: { account_id: "acct_noor", status, country: "AE", mode: "test" },
		secret_last4: "",
		last_test_at: null,
		last_test_ok: null,
		last_test_error: "",
		updated_at: "2026-10-09T07:00:00Z",
		...overrides,
	};
}
```

In `dashboard/src/locales/en/integrations.json`: change `services.video.body` to `"Meeting links for sessions: Zoom on your own account or Etqan's, or a free Jitsi room."`; add `services.payments.ownFirst` `"Your own Stripe keys in Payment gateways are used first whenever they are switched on."`; add the blocks

```json
	"zoom": {
		"hint": "Create a Server-to-Server OAuth app in Zoom's App Marketplace and copy its account ID, client ID and client secret.",
		"accountId": "Account ID",
		"clientId": "Client ID",
		"clientSecret": "Client secret",
		"secretKept": "Saved — leave blank to keep it",
		"hostUser": "Host",
		"hostUserHint": "me (the app's owner) or the email of the Zoom user who hosts the meetings",
		"enabled": "Make the academy's meetings on this Zoom account"
	},
	"connect": {
		"status": {
			"onboarding": "Stripe onboarding not finished",
			"pending": "Stripe is checking your details",
			"active": "Connected to Stripe"
		},
		"statusBody": {
			"onboarding": "Finish Stripe's onboarding to take payments.",
			"pending": "Stripe needs to finish checking your details before families can pay.",
			"active": "Families pay into your Stripe account. Etqan's fee is taken from each payment."
		},
		"account": "Stripe account {{id}}",
		"country": "Country",
		"countryHint": "The country where the academy is registered.",
		"countryOther": "My country is not listed",
		"notInCountry": "Stripe Connect isn't available in your country. You can still use your own Stripe keys or PayPal in Payment gateways.",
		"start": "Connect with Stripe",
		"continue": "Continue onboarding",
		"check": "Check status",
		"checked": "Status checked.",
		"returned": "Back from Stripe. Status checked.",
		"expired": "The onboarding link expired. Continue to get a new one.",
		"disconnectTitle": "Disconnect Stripe?",
		"disconnectBody": "Families can no longer pay through Etqan's Stripe Connect. Your Stripe account itself stays as it is."
	},
```

and under `errors`:

```json
		"required": "This field is required.",
		"hostUser": "Enter me or an email address.",
		"use_connect": "Use Connect with Stripe. Your own Stripe or PayPal keys go in Payment gateways.",
		"connect_unavailable": "Etqan's Stripe Connect is not available to your academy.",
		"connect_country": "Stripe Connect isn't available in your country. Use your own Stripe keys or PayPal in Payment gateways."
```

In `dashboard/src/locales/ar/integrations.json`, the same keys:

```json
	"zoom": {
		"hint": "أنشئ تطبيق Server-to-Server OAuth في متجر تطبيقات Zoom وانسخ معرّف الحساب ومعرّف العميل وسرّ العميل.",
		"accountId": "معرّف الحساب",
		"clientId": "معرّف العميل",
		"clientSecret": "سرّ العميل",
		"secretKept": "محفوظ — اتركه فارغًا للإبقاء عليه",
		"hostUser": "المضيف",
		"hostUserHint": "me (مالك التطبيق) أو بريد مستخدم Zoom الذي يستضيف الاجتماعات",
		"enabled": "أنشئ اجتماعات الأكاديمية على حساب Zoom هذا"
	},
	"connect": {
		"status": {
			"onboarding": "لم يكتمل التسجيل في Stripe",
			"pending": "تراجع Stripe بياناتك",
			"active": "متصل بـ Stripe"
		},
		"statusBody": {
			"onboarding": "أكمل التسجيل في Stripe لتستقبل المدفوعات.",
			"pending": "يجب أن ينهي Stripe مراجعة بياناتك قبل أن تتمكن الأسر من الدفع.",
			"active": "تدفع الأسر إلى حسابك في Stripe، وتُقتطع رسوم إتقان من كل دفعة."
		},
		"account": "حساب Stripe {{id}}",
		"country": "الدولة",
		"countryHint": "الدولة المسجّلة فيها الأكاديمية.",
		"start": "الاتصال بـ Stripe",
		"continue": "متابعة التسجيل",
		"check": "التحقق من الحالة",
		"checked": "تم التحقق من الحالة.",
		"returned": "عدت من Stripe، وتم التحقق من الحالة.",
		"expired": "انتهت صلاحية رابط التسجيل. تابع للحصول على رابط جديد.",
		"disconnectTitle": "قطع الاتصال بـ Stripe؟",
		"disconnectBody": "لن تتمكن الأسر من الدفع عبر Stripe Connect من إتقان. يبقى حسابك في Stripe كما هو."
	},
```

`services.video.body`: `"روابط اجتماعات الحصص: Zoom على حسابك أو حساب إتقان، أو غرفة Jitsi مجانية."`; `services.payments.ownFirst`: `"تُستخدم مفاتيح Stripe الخاصة بك في بوابات الدفع أولًا متى كانت مفعّلة."`; under `errors`: `"required": "هذا الحقل مطلوب."`, `"hostUser": "أدخل me أو عنوان بريد إلكتروني."`, `"use_connect": "استخدم الاتصال بـ Stripe. مفاتيح Stripe أو PayPal الخاصة بك تُضاف في بوابات الدفع."`, `"connect_unavailable": "خدمة Stripe Connect من إتقان غير متاحة لأكاديميتك."`, `"connect_country": "خدمة Stripe Connect غير متاحة في دولتك. استخدم مفاتيح Stripe الخاصة بك أو PayPal في بوابات الدفع."`; `connect.countryOther`: `"دولتي غير موجودة في القائمة"`; `connect.notInCountry`: `"خدمة Stripe Connect غير متاحة في دولتك. يمكنك استخدام مفاتيح Stripe الخاصة بك أو PayPal في بوابات الدفع."`.

In `dashboard/src/features/integrations/index.ts`, add `export { go } from "./redirect";` only if another feature needs it (none does: leave it out).

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DASH pnpm vitest run src/features/integrations src/locales/locales.test.ts` then `just test-frontend`
Expected: PASS (the en/ar key-equality test included).

- [ ] **Step 5: Commit**

```bash
$DASH pnpm exec biome check --write src
git -C dashboard add src/features/integrations src/test/integrations-fixtures.ts src/locales/en/integrations.json src/locales/ar/integrations.json
git -C dashboard commit -m "feat(integrations): Zoom and Stripe Connect data layer and strings" -m "$TRAILER"
```

---

### Task 11: The Zoom form, "Connect with Stripe", and the way back from Stripe

**Files:**
- Create: `dashboard/src/features/integrations/VideoAccountForm.tsx`, `VideoAccountForm.test.tsx`, `StripeConnectPanel.tsx`, `StripeConnectPanel.test.tsx`
- Modify: `dashboard/src/features/integrations/IntegrationsPage.tsx`, `IntegrationsPage.test.tsx`, `index.ts`, `dashboard/src/routes/_authed/settings.integrations.tsx`

**Interfaces:**
- Consumes: Task 10's schemas, `integrationsApi.connect`, `connectStripe`, `probe`, `disconnect`, `go`; `useIntegrationsMutation`, `integrationsErrorText` (slice 1).
- Produces: `VideoAccountForm({ own, onDone })`; `StripeConnectPanel({ card, editable, notice })` (`notice?: "refresh"`); `IntegrationsPage({ stripe, onStripeHandled })` (`stripe?: "return" | "refresh"`); the route's search `{ stripe?: "return" | "refresh" }`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/integrations/VideoAccountForm.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ownZoom } from "@/test/integrations-fixtures";
import { renderWithRouter } from "@/test/render";
import { integrationsApi } from "./api";
import { VideoAccountForm } from "./VideoAccountForm";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return { ...actual, integrationsApi: { ...actual.integrationsApi, connect: vi.fn() } };
});

describe("VideoAccountForm", () => {
	beforeEach(() => vi.clearAllMocks());

	it("connects a Zoom app with what was typed", async () => {
		const user = userEvent.setup();
		const onDone = vi.fn();
		vi.mocked(integrationsApi.connect).mockResolvedValue({} as never);
		renderWithRouter(<VideoAccountForm own={null} onDone={onDone} />);
		await user.type(await screen.findByLabelText(/Account ID/), "zoomacct123");
		await user.type(screen.getByLabelText(/Client ID/), "zoomclient456");
		await user.type(screen.getByLabelText(/Client secret/), "zoom-client-secret-7890");
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(integrationsApi.connect).toHaveBeenCalledWith({
				service: "video",
				body: {
					account_id: "zoomacct123",
					client_id: "zoomclient456",
					client_secret: "zoom-client-secret-7890",
					host_user: "me",
					enabled: true,
				},
			}),
		);
		expect(onDone).toHaveBeenCalled();
	});

	it("asks for the secret of a new account and keeps a blank one on an edit", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.connect).mockResolvedValue({} as never);
		const { unmount } = renderWithRouter(<VideoAccountForm own={null} onDone={vi.fn()} />);
		await user.type(await screen.findByLabelText(/Account ID/), "a");
		await user.type(screen.getByLabelText(/Client ID/), "c");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText("This field is required.")).toBeVisible();
		expect(integrationsApi.connect).not.toHaveBeenCalled();
		unmount();
		renderWithRouter(<VideoAccountForm own={ownZoom()} onDone={vi.fn()} />);
		expect(await screen.findByText("Saved — leave blank to keep it")).toBeVisible();
		await user.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() => expect(integrationsApi.connect).toHaveBeenCalled());
		const { body } = vi.mocked(integrationsApi.connect).mock.calls[0][0];
		expect("client_secret" in body).toBe(false);
	});

	it("refuses a host that is neither me nor an email", async () => {
		const user = userEvent.setup();
		renderWithRouter(<VideoAccountForm own={ownZoom()} onDone={vi.fn()} />);
		const host = await screen.findByLabelText(/^Host/);
		await user.clear(host);
		await user.type(host, "nobody");
		await user.click(screen.getByRole("button", { name: "Save" }));
		expect(await screen.findByText("Enter me or an email address.")).toBeVisible();
		expect(integrationsApi.connect).not.toHaveBeenCalled();
	});
});
```

Create `dashboard/src/features/integrations/StripeConnectPanel.test.tsx`:

```tsx
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { card, ownConnect } from "@/test/integrations-fixtures";
import { renderWithRouter } from "@/test/render";
import { integrationsApi } from "./api";
import { go } from "./redirect";
import { StripeConnectPanel } from "./StripeConnectPanel";

vi.mock("./redirect", () => ({ go: vi.fn() }));
vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		integrationsApi: {
			...actual.integrationsApi,
			connectStripe: vi.fn(),
			probe: vi.fn(),
			disconnect: vi.fn(),
		},
	};
});

const available = (own = null as ReturnType<typeof ownConnect> | null) =>
	card("payments", {
		default_status: "available",
		using: "etqan",
		connectable: true,
		own,
		connect_countries: ["AE", "GB"],
	});

describe("StripeConnectPanel", () => {
	beforeEach(() => vi.clearAllMocks());

	it("connects with the country chosen and goes to Stripe", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.connectStripe).mockResolvedValue({ url: "https://connect.stripe.com/x" });
		renderWithRouter(<StripeConnectPanel card={available()} editable />);
		await user.selectOptions(await screen.findByLabelText(/Country/), "AE");
		await user.click(screen.getByRole("button", { name: "Connect with Stripe" }));
		await waitFor(() => expect(go).toHaveBeenCalledWith("https://connect.stripe.com/x"));
		expect(integrationsApi.connectStripe).toHaveBeenCalledWith("AE");
		expect(
			screen.getByText("Your own Stripe keys in Payment gateways are used first whenever they are switched on."),
		).toBeVisible();
	});

	it("says Connect is not available in a country not listed (owner D22)", async () => {
		const user = userEvent.setup();
		renderWithRouter(<StripeConnectPanel card={available()} editable />);
		const select = await screen.findByLabelText(/Country/);
		expect(screen.getByRole("button", { name: "Connect with Stripe" })).toBeDisabled();
		await user.selectOptions(select, "other");
		expect(
			screen.getByText(
				"Stripe Connect isn't available in your country. You can still use your own Stripe keys or PayPal in Payment gateways.",
			),
		).toBeVisible();
		expect(screen.queryByRole("button", { name: "Connect with Stripe" })).toBeNull();
		expect(integrationsApi.connectStripe).not.toHaveBeenCalled();
	});

	it("says in words why Stripe refused", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.connectStripe).mockRejectedValue(
			new AxiosError("x", "400", undefined, undefined, {
				status: 400,
				data: { country: ["x"], code: "integrations.connect_country" },
			} as never),
		);
		renderWithRouter(<StripeConnectPanel card={available()} editable />);
		await user.selectOptions(await screen.findByLabelText(/Country/), "GB");
		await user.click(screen.getByRole("button", { name: "Connect with Stripe" }));
		expect(
			await screen.findByText(
				"Stripe Connect isn't available in your country. Use your own Stripe keys or PayPal in Payment gateways.",
			),
		).toBeVisible();
		expect(go).not.toHaveBeenCalled();
	});

	it("continues an unfinished onboarding without a country", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.connectStripe).mockResolvedValue({ url: "https://connect.stripe.com/y" });
		renderWithRouter(<StripeConnectPanel card={available(ownConnect("onboarding"))} editable notice="refresh" />);
		expect(await screen.findByText("The onboarding link expired. Continue to get a new one.")).toBeVisible();
		expect(screen.queryByLabelText(/Country/)).toBeNull();
		await user.click(screen.getByRole("button", { name: "Continue onboarding" }));
		await waitFor(() => expect(go).toHaveBeenCalledWith("https://connect.stripe.com/y"));
		expect(integrationsApi.connectStripe).toHaveBeenCalledWith("");
	});

	it("shows an active account, checks its status and disconnects", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.probe).mockResolvedValue(
			available(ownConnect("active", { last_test_ok: true })) as never,
		);
		vi.mocked(integrationsApi.disconnect).mockResolvedValue(available() as never);
		renderWithRouter(<StripeConnectPanel card={available(ownConnect("active"))} editable />);
		expect(
			await screen.findByText("Families pay into your Stripe account. Etqan's fee is taken from each payment."),
		).toBeVisible();
		expect(screen.getByText("Stripe account acct_noor")).toBeVisible();
		expect(screen.queryByRole("button", { name: "Continue onboarding" })).toBeNull();
		await user.click(screen.getByRole("button", { name: "Check status" }));
		await waitFor(() => expect(integrationsApi.probe).toHaveBeenCalledWith("payments"));
		expect(await screen.findByText("Status checked.")).toBeVisible();
		await user.click(screen.getByRole("button", { name: "Disconnect" }));
		expect(await screen.findByText("Disconnect Stripe?")).toBeVisible();
		await user.click(screen.getAllByRole("button", { name: "Disconnect" }).at(-1) as HTMLElement);
		await waitFor(() => expect(integrationsApi.disconnect).toHaveBeenCalledWith("payments"));
	});

	it("offers nothing to connect when Etqan's default is not available or to a reader", async () => {
		const { unmount } = renderWithRouter(
			<StripeConnectPanel card={card("payments", { default_status: "feature_off" })} editable />,
		);
		await screen.findByText(/Payment gateways are used first/);
		expect(screen.queryByRole("button", { name: "Connect with Stripe" })).toBeNull();
		unmount();
		renderWithRouter(<StripeConnectPanel card={available(ownConnect("pending"))} editable={false} />);
		expect(await screen.findByText("Stripe needs to finish checking your details before families can pay.")).toBeVisible();
		expect(screen.queryByRole("button")).toBeNull();
	});
});
```

Append to `dashboard/src/features/integrations/IntegrationsPage.test.tsx`, inside its `describe`:

```tsx
	it("shows the Connect status on the payments card", async () => {
		vi.mocked(integrationsApi.list).mockResolvedValue({
			services: [card("payments", { own: ownConnect("pending"), default_status: "available" })],
		});
		renderWithRouter(<IntegrationsPage />);
		expect(await screen.findByText("Stripe is checking your details")).toBeVisible();
	});

	it("opens the Zoom form on the video card", async () => {
		const user = userEvent.setup();
		vi.mocked(integrationsApi.list).mockResolvedValue({
			services: [card("video", { connectable: true })],
		});
		renderWithRouter(<IntegrationsPage />);
		await user.click(await screen.findByRole("button", { name: "Connect your own account" }));
		expect(screen.getByLabelText(/Account ID/)).toBeVisible();
		expect(screen.queryByLabelText(/SMTP server/)).toBeNull();
	});

	it("checks the Stripe status once on the way back from Stripe", async () => {
		const onStripeHandled = vi.fn();
		vi.mocked(integrationsApi.probe).mockResolvedValue(
			card("payments", { own: ownConnect("active") }),
		);
		renderWithRouter(<IntegrationsPage stripe="return" onStripeHandled={onStripeHandled} />);
		expect(await screen.findByText("Back from Stripe. Status checked.")).toBeVisible();
		expect(integrationsApi.probe).toHaveBeenCalledTimes(1);
		expect(integrationsApi.probe).toHaveBeenCalledWith("payments");
		expect(onStripeHandled).toHaveBeenCalled();
	});
```

(add `card`, `ownConnect` to its fixtures import).

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DASH pnpm vitest run src/features/integrations`
Expected: FAIL — `Cannot find module './VideoAccountForm'` / `'./StripeConnectPanel'`, and the page tests.

- [ ] **Step 3: Write minimal implementation**

Create `dashboard/src/features/integrations/VideoAccountForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useController, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { parseApiError } from "@/features/identity/api";
import { useFieldError } from "@/lib/field-error";
import {
	Alert,
	AlertDescription,
	Button,
	Checkbox,
	Field,
	Input,
	SubmitButton,
	toast,
} from "@/ui";
import { integrationsApi } from "./api";
import { integrationsErrorText } from "./errors";
import { useIntegrationsMutation } from "./queries";
import {
	type OwnAccount,
	type ZoomForm,
	zoomBody,
	zoomDefaults,
	zoomFormSchema,
} from "./schemas";

const FIELDS: readonly (keyof ZoomForm)[] = [
	"account_id",
	"client_id",
	"client_secret",
	"host_user",
	"enabled",
];

/** Slice 3 plan D5: the academy's own Zoom Server-to-Server OAuth app. The
 * client secret is write-only: blank on an edit keeps the stored one. */
export function VideoAccountForm({
	own,
	onDone,
}: {
	own: OwnAccount | null;
	onDone: () => void;
}) {
	const { t } = useTranslation();
	const fieldError = useFieldError();
	const save = useIntegrationsMutation(integrationsApi.connect);
	const [failure, setFailure] = useState("");
	const {
		register,
		control,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<ZoomForm>({
		resolver: zodResolver(zoomFormSchema),
		defaultValues: zoomDefaults(own),
	});
	const enabled = useController({ control, name: "enabled" });

	async function onSubmit(values: ZoomForm) {
		setFailure("");
		if (!own && !values.client_secret.trim()) {
			setError("client_secret", { message: "integrations.errors.required" });
			return;
		}
		try {
			await save.mutateAsync({ service: "video", body: zoomBody(values) });
			toast({ description: t("integrations.saved"), variant: "success" });
			onDone();
		} catch (error) {
			let shown = false;
			for (const [key, message] of Object.entries(
				parseApiError(error).fieldErrors,
			)) {
				const name = FIELDS.find((field) => field === key);
				if (name) {
					setError(name, { message });
					shown = true;
				}
			}
			if (!shown) setFailure(integrationsErrorText(error, t));
		}
	}

	return (
		<form
			onSubmit={handleSubmit(onSubmit)}
			className="flex max-w-xl flex-col gap-4"
			noValidate
		>
			<p className="text-sm text-muted-foreground">{t("integrations.zoom.hint")}</p>
			<Field
				id="zoom_account_id"
				label={t("integrations.zoom.accountId")}
				error={fieldError(errors.account_id?.message)}
			>
				<Input dir="ltr" autoComplete="off" {...register("account_id")} />
			</Field>
			<Field
				id="zoom_client_id"
				label={t("integrations.zoom.clientId")}
				error={fieldError(errors.client_id?.message)}
			>
				<Input dir="ltr" autoComplete="off" {...register("client_id")} />
			</Field>
			<Field
				id="zoom_client_secret"
				label={t("integrations.zoom.clientSecret")}
				error={fieldError(errors.client_secret?.message)}
			>
				<Input
					dir="ltr"
					type="password"
					autoComplete="new-password"
					{...register("client_secret")}
				/>
			</Field>
			{own ? (
				<p className="text-sm text-muted-foreground">
					{t("integrations.zoom.secretKept")}
				</p>
			) : null}
			<Field
				id="zoom_host_user"
				label={t("integrations.zoom.hostUser")}
				error={fieldError(errors.host_user?.message)}
			>
				<Input dir="ltr" autoComplete="off" {...register("host_user")} />
			</Field>
			<p className="text-sm text-muted-foreground">
				{t("integrations.zoom.hostUserHint")}
			</p>
			<label htmlFor="zoom_enabled" className="flex items-center gap-2 text-sm">
				<Checkbox
					id="zoom_enabled"
					checked={enabled.field.value}
					onCheckedChange={(value) => enabled.field.onChange(value === true)}
				/>
				{t("integrations.zoom.enabled")}
			</label>
			{failure ? (
				<Alert variant="destructive">
					<AlertDescription>{failure}</AlertDescription>
				</Alert>
			) : null}
			<div className="flex flex-wrap gap-2">
				<SubmitButton pending={isSubmitting}>
					{t("integrations.actions.save")}
				</SubmitButton>
				<Button type="button" variant="outline" onClick={onDone}>
					{t("integrations.actions.cancel")}
				</Button>
			</div>
		</form>
	);
}
```

Create `dashboard/src/features/integrations/StripeConnectPanel.tsx`:

```tsx
import { useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	Alert,
	AlertDescription,
	AlertDialog,
	AlertDialogAction,
	AlertDialogCancel,
	AlertDialogContent,
	AlertDialogDescription,
	AlertDialogFooter,
	AlertDialogTitle,
	AlertDialogTrigger,
	Button,
	Field,
	Select,
	toast,
} from "@/ui";
import { integrationsApi } from "./api";
import { integrationsErrorText } from "./errors";
import { useIntegrationsMutation } from "./queries";
import { go } from "./redirect";
import { connectOf, type IntegrationCard } from "./schemas";

const OTHER = "other";

/** Spec §6, slice 3 plan D14–D16, D20: the academy's Stripe Connect account
 * on Etqan's platform. Its own Stripe keys stay on B3's screen and win. */
export function StripeConnectPanel({
	card,
	editable,
	notice,
}: {
	card: IntegrationCard;
	editable: boolean;
	notice?: "refresh";
}) {
	const { t, i18n } = useTranslation();
	const connect = connectOf(card.own);
	const start = useMutation({ mutationFn: integrationsApi.connectStripe });
	const check = useIntegrationsMutation(integrationsApi.probe);
	const disconnect = useIntegrationsMutation(integrationsApi.disconnect);
	const [country, setCountry] = useState("");
	const [failure, setFailure] = useState("");
	const canStart = editable && !connect && card.default_status === "available";
	const regions = new Intl.DisplayNames([i18n.language], { type: "region" });

	async function toStripe() {
		setFailure("");
		try {
			// Continuing an account needs no country (plan D14).
			const { url } = await start.mutateAsync(connect ? "" : country);
			go(url);
		} catch (error) {
			setFailure(integrationsErrorText(error, t));
		}
	}

	async function runCheck() {
		setFailure("");
		try {
			const fresh = await check.mutateAsync("payments");
			const ok = fresh.own?.last_test_ok === true;
			toast({
				description: t(ok ? "integrations.connect.checked" : "integrations.test.failedToast"),
				variant: ok ? "success" : "destructive",
			});
		} catch (error) {
			setFailure(integrationsErrorText(error, t));
		}
	}

	async function runDisconnect() {
		setFailure("");
		try {
			await disconnect.mutateAsync("payments");
			toast({ description: t("integrations.disconnect.done"), variant: "success" });
		} catch (error) {
			setFailure(integrationsErrorText(error, t));
		}
	}

	return (
		<div className="flex flex-col gap-3">
			{connect ? (
				<div className="flex flex-col gap-1 text-sm">
					<p>{t(`integrations.connect.statusBody.${connect.status}`)}</p>
					<p className="text-muted-foreground" dir="ltr">
						{t("integrations.connect.account", { id: connect.account_id })}
					</p>
				</div>
			) : null}
			{notice === "refresh" && connect && connect.status !== "active" ? (
				<Alert>
					<AlertDescription>{t("integrations.connect.expired")}</AlertDescription>
				</Alert>
			) : null}
			{canStart ? (
				<div className="flex max-w-xs flex-col gap-2">
					<Field id="stripe_country" label={t("integrations.connect.country")}>
						<Select value={country} onChange={(event) => setCountry(event.target.value)}>
							<option value="" disabled>
								{t("integrations.connect.countryHint")}
							</option>
							{(card.connect_countries ?? []).map((code) => (
								<option key={code} value={code}>
									{regions.of(code) ?? code}
								</option>
							))}
							<option value={OTHER}>{t("integrations.connect.countryOther")}</option>
						</Select>
					</Field>
					{country === OTHER ? (
						<Alert>
							<AlertDescription>{t("integrations.connect.notInCountry")}</AlertDescription>
						</Alert>
					) : (
						<Button
							type="button"
							className="self-start"
							disabled={!country || start.isPending}
							onClick={() => void toStripe()}
						>
							{t("integrations.connect.start")}
						</Button>
					)}
				</div>
			) : null}
			{editable && connect ? (
				<div className="flex flex-wrap gap-2">
					{connect.status === "active" ? null : (
						<Button type="button" disabled={start.isPending} onClick={() => void toStripe()}>
							{t("integrations.connect.continue")}
						</Button>
					)}
					<Button
						type="button"
						variant="outline"
						disabled={check.isPending}
						onClick={() => void runCheck()}
					>
						{t("integrations.connect.check")}
					</Button>
					<AlertDialog>
						<AlertDialogTrigger asChild>
							<Button type="button" variant="destructive">
								{t("integrations.actions.disconnect")}
							</Button>
						</AlertDialogTrigger>
						<AlertDialogContent>
							<AlertDialogTitle>{t("integrations.connect.disconnectTitle")}</AlertDialogTitle>
							<AlertDialogDescription>
								{t("integrations.connect.disconnectBody")}
							</AlertDialogDescription>
							<AlertDialogFooter>
								<AlertDialogCancel asChild>
									<Button type="button" variant="outline">
										{t("integrations.actions.cancel")}
									</Button>
								</AlertDialogCancel>
								<AlertDialogAction asChild>
									<Button
										type="button"
										variant="destructive"
										onClick={() => void runDisconnect()}
									>
										{t("integrations.disconnect.confirm")}
									</Button>
								</AlertDialogAction>
							</AlertDialogFooter>
						</AlertDialogContent>
					</AlertDialog>
				</div>
			) : null}
			<p className="text-sm text-muted-foreground">
				{t("integrations.services.payments.ownFirst")}
			</p>
			{failure ? (
				<Alert variant="destructive">
					<AlertDescription>{failure}</AlertDescription>
				</Alert>
			) : null}
		</div>
	);
}
```

In `dashboard/src/features/integrations/IntegrationsPage.tsx`:

1. Imports: `useEffect`, `useRef` from react; `StripeConnectPanel` from `./StripeConnectPanel`; `VideoAccountForm` from `./VideoAccountForm`; `connectOf` and `Service` from `./schemas`.
2. Above `CardActions`, add the form map (with B10a merged, add `ai: AiAccountForm` and drop its ternary):

```tsx
type AccountForm = typeof EmailAccountForm;
/** The own-account form per service; slice 3 adds Zoom. */
const FORMS: Partial<Record<Service, AccountForm>> = {
	email: EmailAccountForm,
	video: VideoAccountForm,
};
```

3. `CardActions` takes `notice?: "refresh"`; its first lines become:

```tsx
	if (card.service === "payments") {
		return <StripeConnectPanel card={card} editable={editable} notice={notice} />;
	}
	if (!card.connectable) {
```

and its editing branch becomes:

```tsx
	if (editing) {
		const Form = FORMS[card.service] ?? EmailAccountForm;
		return <Form own={card.own} onDone={() => setEditing(false)} />;
	}
```

4. In `ServiceCard` (which also takes `notice?: "refresh"` and passes it to `CardActions`), replace the payments `null` branch of the chip with the Connect status, and keep `OwnStatus` off the payments card:

```tsx
					{card.service === "payments" ? (
						<ConnectChip card={card} />
					) : (
						<StatusChip tone={TONE[card.using]}>
							{t(`integrations.using.${card.using}`)}
						</StatusChip>
					)}
```

```tsx
				{card.own && card.service !== "payments" ? <OwnStatus own={card.own} /> : null}
				<CardActions card={card} editable={editable} notice={notice} />
```

with, above `ServiceCard`:

```tsx
/** Slice 3 plan D20: the payments card's chip is its Connect status; with
 * no Connect account it has none (B3's own keys live on their screen). */
function ConnectChip({ card }: { card: IntegrationCard }) {
	const { t } = useTranslation();
	const connect = connectOf(card.own);
	if (!connect) return null;
	return (
		<StatusChip tone={connect.status === "active" ? "live" : "warning"}>
			{t(`integrations.connect.status.${connect.status}`)}
		</StatusChip>
	);
}
```

5. `IntegrationsPage` takes `{ stripe, onStripeHandled }: { stripe?: "return" | "refresh"; onStripeHandled?: () => void } = {}`, passes `notice={stripe === "refresh" ? "refresh" : undefined}` to each `ServiceCard`, and checks the status once on the way back:

```tsx
	const check = useIntegrationsMutation(integrationsApi.probe);
	const checked = useRef(false);
	useEffect(() => {
		if (stripe !== "return" || checked.current) return;
		checked.current = true;
		check
			.mutateAsync("payments")
			.then(() =>
				toast({ description: t("integrations.connect.returned"), variant: "success" }),
			)
			.catch(() => undefined)
			.finally(() => onStripeHandled?.());
	}, [stripe, check, onStripeHandled, t]);
```

(place it before the early `isError`/`!data` returns so the hook order is fixed).

6. `index.ts`: export `StripeConnectPanel` and `VideoAccountForm` next to `EmailAccountForm`.

Replace `dashboard/src/routes/_authed/settings.integrations.tsx` with:

```tsx
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { usePageTitle } from "@/features/branding";
import { requireOffice } from "@/features/identity/require-admin";
import { IntegrationsPage } from "@/features/integrations";
import { PageContainer, PageHeader } from "@/ui";

type StripeBack = "return" | "refresh";

export const Route = createFileRoute("/_authed/settings/integrations")({
	staticData: { permission: "integration.view" },
	beforeLoad: ({ context }) => requireOffice(context),
	// Slice 3 plan D14: Stripe's onboarding sends the admin back here.
	validateSearch: (search: Record<string, unknown>): { stripe?: StripeBack } =>
		search.stripe === "return" || search.stripe === "refresh"
			? { stripe: search.stripe }
			: {},
	component: function IntegrationsRoute() {
		const { t } = useTranslation();
		const { stripe } = Route.useSearch();
		const navigate = useNavigate({ from: Route.fullPath });
		usePageTitle(t("integrations.nav.title"));
		return (
			<PageContainer>
				<PageHeader
					title={t("integrations.nav.title")}
					description={t("integrations.page.subtitle")}
				/>
				<IntegrationsPage
					stripe={stripe}
					onStripeHandled={() => navigate({ search: {}, replace: true })}
				/>
			</PageContainer>
		);
	},
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DASH pnpm vitest run src/features/integrations src/routes` then `just test-frontend` and `just lint-frontend`
Expected: PASS (types and biome included; `routeTree.gen.ts` is unchanged — no new route file).

- [ ] **Step 5: Commit**

```bash
$DASH pnpm exec biome check --write src
git -C dashboard add src/features/integrations src/routes/_authed/settings.integrations.tsx
git -C dashboard commit -m "feat(integrations): Zoom form, Connect with Stripe, and the way back from Stripe" -m "$TRAILER"
```

---

### Task 12: "Start as host" for the session's teacher (dashboard)

**Files:**
- Create: `dashboard/src/features/scheduling/hostLink.ts`, `dashboard/src/features/scheduling/hostLink.test.ts`
- Modify: `dashboard/src/features/scheduling/schemas.ts` (the `Session` type, line ~175), `api.ts`, `bits.tsx`, `bits.test.tsx`, `dashboard/src/test/scheduling-fixtures.ts`, `dashboard/src/locales/en/scheduling.json`, `dashboard/src/locales/ar/scheduling.json`

**Interfaces:**
- Consumes: `GET sessions/<id>/host-link/` → `{url, host}` and the session row's `meeting_host` (Task 6).
- Produces: `Session.meeting_host: boolean`; `schedulingApi.hostLink(id: number): Promise<{ url: string; host: boolean }>`; `openHostLink(sessionId: number, fallback: string): Promise<void>`; `HostLink({ session })`; string `scheduling.session.startAsHost`.

- [ ] **Step 1: Write the failing tests**

Create `dashboard/src/features/scheduling/hostLink.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import { schedulingApi } from "./api";
import { openHostLink } from "./hostLink";

describe("openHostLink (owner D23)", () => {
	afterEach(() => vi.restoreAllMocks());

	function tab() {
		const opened = { opener: {} as unknown, location: { href: "" } };
		vi.spyOn(window, "open").mockReturnValue(opened as unknown as Window);
		return opened;
	}

	it("opens the tab at once, then the fresh start link", async () => {
		const opened = tab();
		vi.spyOn(schedulingApi, "hostLink").mockResolvedValue({
			url: "https://zoom.us/s/1?zak=z",
			host: true,
		});
		await openHostLink(41, "https://zoom.us/j/1");
		expect(window.open).toHaveBeenCalledWith("about:blank", "_blank");
		expect(opened.location.href).toBe("https://zoom.us/s/1?zak=z");
		expect(opened.opener).toBeNull();
	});

	it("falls back to the join link when the start link cannot be had", async () => {
		const opened = tab();
		vi.spyOn(schedulingApi, "hostLink").mockRejectedValue(new Error("502"));
		await openHostLink(41, "https://zoom.us/j/1");
		expect(opened.location.href).toBe("https://zoom.us/j/1");
	});
});
```

Add to `dashboard/src/features/scheduling/bits.test.tsx`, inside `describe("JoinLink", …)` (import `openHostLink` from `./hostLink` and `vi.mock("./hostLink", () => ({ openHostLink: vi.fn() }));` at the top):

```tsx
	it("gives the session's teacher Start as host on a Zoom meeting", async () => {
		const user = userEvent.setup();
		vi.mocked(identityApi.me).mockResolvedValue({ ...me("teacher"), id: 21 });
		const session = sessionRow({ meeting_url: "https://zoom.us/j/1", meeting_host: true });
		renderWithRouter(<JoinLink session={session} />);
		await user.click(await screen.findByRole("button", { name: "Start as host" }));
		expect(openHostLink).toHaveBeenCalledWith(41, "https://zoom.us/j/1");
		expect(screen.queryByRole("link")).toBeNull();
	});

	it("gives everyone else, and any Jitsi room, the join link", async () => {
		vi.mocked(identityApi.me).mockResolvedValue(me("student"));
		const { unmount } = renderWithRouter(
			<JoinLink session={sessionRow({ meeting_url: "https://zoom.us/j/1", meeting_host: true })} />,
		);
		expect(await screen.findByRole("link")).toHaveAttribute("href", "https://zoom.us/j/1");
		unmount();
		vi.mocked(identityApi.me).mockResolvedValue({ ...me("teacher"), id: 21 });
		renderWithRouter(
			<JoinLink session={sessionRow({ meeting_url: "https://meet.jit.si/EtqanX", meeting_host: false })} />,
		);
		expect(await screen.findByRole("link")).toHaveAttribute("href", "https://meet.jit.si/EtqanX");
		expect(screen.queryByRole("button", { name: "Start as host" })).toBeNull();
	});
```

(add `import userEvent from "@testing-library/user-event";`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `$DASH pnpm vitest run src/features/scheduling/hostLink.test.ts src/features/scheduling/bits.test.tsx`
Expected: FAIL — `Cannot find module './hostLink'`.

- [ ] **Step 3: Write minimal implementation**

In `dashboard/src/features/scheduling/schemas.ts`, in the `Session` interface next to `meeting_url: string;`:

```ts
	/** Owner D23: a Zoom meeting whose teacher may start it as host. */
	meeting_host: boolean;
```

In `dashboard/src/test/scheduling-fixtures.ts` `sessionRow`, add `meeting_host: false,` after `meeting_url`. Run `just test-frontend`: every other `Session` literal `tsc` names gets `meeting_host: false` too.

In `dashboard/src/features/scheduling/api.ts`, inside `schedulingApi`:

```ts
	/** Owner D23: a start link read from Zoom now; never stored. */
	hostLink: async (id: number) =>
		(await api.get<{ url: string; host: boolean }>(`${SE}${id}/host-link/`))
			.data,
```

Create `dashboard/src/features/scheduling/hostLink.ts`:

```ts
import { schedulingApi } from "./api";

/** Owner D23: open the meeting as its host. The tab opens during the click
 * (a popup blocker allows only that), then goes to a start link read from
 * Zoom now, or to the join link when there is none. Nothing is kept. */
export async function openHostLink(sessionId: number, fallback: string): Promise<void> {
	const tab = window.open("about:blank", "_blank");
	let url = fallback;
	try {
		url = (await schedulingApi.hostLink(sessionId)).url;
	} catch {
		// The join link still gets the teacher into the class.
	}
	if (tab) {
		tab.opener = null;
		tab.location.href = url;
	} else {
		window.location.assign(url);
	}
}
```

In `dashboard/src/features/scheduling/bits.tsx`, import `openHostLink` from `./hostLink`, add

```tsx
/** Owner D23: the session's teacher starts the Zoom meeting as host. */
export function HostLink({ session }: { session: Session }) {
	const { t } = useTranslation();
	return (
		<button
			type="button"
			onClick={() => void openHostLink(session.id, session.meeting_url)}
			className="font-medium text-primary-text underline-offset-4 hover:underline"
		>
			{t("scheduling.session.startAsHost")}
		</button>
	);
}
```

and in `JoinLink`, after the at-disposal check and before `return (<a …`:

```tsx
	if (session.meeting_host && me && session.teacher.id === me.id) {
		return <HostLink session={session} />;
	}
```

In `dashboard/src/locales/en/scheduling.json`, under `session` after `"join": "Join",` add `"startAsHost": "Start as host",`; in `ar/scheduling.json`, under `session` after `"join": "انضمام",` add `"startAsHost": "ابدأ كمضيف",`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `$DASH pnpm vitest run src/features/scheduling src/locales/locales.test.ts` then `just test-frontend` and `just lint-frontend`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
$DASH pnpm exec biome check --write src
git -C dashboard add src/features/scheduling src/test/scheduling-fixtures.ts src/locales/en/scheduling.json src/locales/ar/scheduling.json
git -C dashboard commit -m "feat(scheduling): Start as host for the session's teacher" -m "$TRAILER"
```

---

### Task 13: Docs, state and the gates

**Files:**
- Modify: `CLAUDE.md` (meta), `STATE.md` (meta)

**Interfaces:**
- Consumes: everything above.
- Produces: the rule later work follows for meetings and payments, the current position, the owner's go-live list.

- [ ] **Step 1: Write the failing check**

Run: `grep -c "provision_meetings\|stripe_connect" CLAUDE.md STATE.md`
Expected: `CLAUDE.md:0` and `STATE.md:0` (exit status 1).

- [ ] **Step 2: Run the whole suite before the docs**

Run: `just test && just lint`
Expected: backend and dashboard suites, `lint-imports`, ruff, biome and the secret scan pass; backend coverage ≥ 80 %. Then `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm dashboard pnpm test:coverage` — lines and statements ≥ 80, branches and functions ≥ 70. Then `just e2e` (the full suite): all pass. A failure in a B3 checkout journey means Task 8 changed the own-keys path: fix it there.

- [ ] **Step 3: Implement**

In `CLAUDE.md`, directly after the bullet that begins `- Use of an Etqan default is metered`, add:

```markdown
- Video meeting links come only from `integrations.services.create_meeting(...)` (Zoom on the
  academy's account, or Etqan's under a free host from its pool, else a Jitsi room);
  `scheduling.provision_meetings` fills blank links for the next day's sessions. A Zoom start
  link is a host credential: only `GET sessions/<id>/host-link/` gives it, to the session's
  teacher, read fresh from Zoom; never store, log or list it. Online payments: B3's own keys first, else the academy's
  Stripe Connect account (`integrations.services.stripe_connect()`); Etqan's own webhooks live on
  the base domain (`config/urls_public.py`).
```

In `STATE.md`, in `## Integrations (outside the phases)`, replace the sentence that begins `Next: B5c meters WhatsApp` (through the end of that paragraph) with:

```markdown
Slice 3 is built: Zoom Server-to-Server meetings on the resolver (an academy's own app, or Etqan's
under a free host from its pool, `HostBooking`; `zoom_api` built), a Jitsi room when none resolves
or no host is free, the teacher's fresh host link (`sessions/<id>/host-link/`), `scheduling.provision_meetings` every 5 minutes
(one meeting per class, never replacing a typed link), Zoom minutes metered on `meeting.ended` to
Etqan's app; Stripe Connect as the payments default (Express onboarding from Settings →
Integrations, `application_fee` from `connect_fee()`, `record_collected_fee` on
`application_fee.created`), B3's own keys first; Etqan's webhooks at `/api/v1/webhooks/zoom/`
and `/api/v1/webhooks/stripe-connect/` on the base domain. Go-live needs the owner's Zoom
Server-to-Server app and Stripe platform keys in the platform admin (see the slice 3 plan's
"Owner actions"). Next: B5c meters WhatsApp conversations and B10 AI tokens through
`record_usage`.
```

- [ ] **Step 4: Run the check to see it pass**

Run: `grep -c "provision_meetings\|stripe_connect" CLAUDE.md STATE.md`
Expected: `CLAUDE.md:1` and `STATE.md:1`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md STATE.md
git commit -m "docs: integrations slice 3 meetings and Connect rules and state" -m "$TRAILER"
```

Then open the PRs (backend and dashboard `feat/integrations-3` → `main`; meta `feat/integrations-3` → `master` with `--repo Etqan-agency/etqan_tutor`), merge after review, and bump the submodule pointers in meta with explicit paths (`git add backend dashboard`), never `git commit -a`. Production needs a backend deploy (two migrations: `integrations.0003`, `gateways.0004`; a new beat entry, picked up by `django_celery_beat` on start) and optionally `JITSI_BASE_URL`.

## Owner actions before go-live (nothing in this slice needs them to build or test)

1. **Zoom (Etqan's default).** In Etqan's Zoom account: as many licensed host users as classes Etqan's academies may run at the same time (owner D21; one meeting per host at a time, `MAX_MEETINGS_PER_HOST`); a Server-to-Server OAuth app with scopes to create meetings for users (`meeting:write:meeting:admin` or the classic `meeting:write:admin`) and read users; an event subscription for **End Meeting** (`meeting.ended`) to `https://<base domain>/api/v1/webhooks/zoom/` (the platform admin's video page shows it), validated once the secret token is saved. In the platform admin → Etqan default accounts → Video: config `{"account_id": "…", "client_id": "…", "host_users": ["host1@…", "host2@…"]}`, secret `{"client_secret": "…", "webhook_secret": "<Secret Token>"}`, Test, enable. Set a `Price` for video/minute. Switch `zoom_api` on per academy.
2. **Stripe (Etqan's platform).** Enable Connect (Express) on Etqan's Stripe account and fill its platform profile and branding. Two webhook endpoints, both to `https://<base domain>/api/v1/webhooks/stripe-connect/`: "Connected accounts" with `account.updated`, `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`; "Your account" with `application_fee.created`. In the platform admin → Payments: secret `{"secret_key": "sk_…", "connect_webhook_secret": "whsec_…", "platform_webhook_secret": "whsec_…"}`, Test, enable. Set each academy's `ConnectFee` (no row = no fee). Start in test mode (`sk_test_…`) and run one onboarding and one payment end to end before switching to live keys (a live key ignores test-mode Connect accounts, D14).
3. **Check `CONNECT_COUNTRIES`** (owner D22) against Stripe's current list of countries for Express connected accounts; academies elsewhere see "Stripe Connect isn't available in your country" and keep B3's own keys or PayPal.
4. **Zoom host links** need the S2S app to read meetings (`meeting:read:meeting:admin` or the classic `meeting:read:admin`), on Etqan's app and on any academy's own app.

---

## Self-review

**Spec coverage (slice 3):**
- §4 Video, Etqan default (Etqan's S2S app, a meeting per session, Etqan hosts) and academy's own (own S2S credentials, own users host) — Tasks 3–5 (D5–D8); Jitsi as the free fallback when nothing resolves — Tasks 4–5 (D9).
- §4/§5 video metered unit (minutes on Zoom's meeting-ended event), recorded only on Etqan's default, idempotent — Task 4 (D10; ledger D61/D62).
- §3.3 probes: video requests a Zoom token (Task 3); payments retrieves the Connect account (Task 7, D15) and Etqan's platform account (D13).
- §4 Payments, Etqan default = Stripe Connect Express via hosted onboarding, per-academy fee via `application_fee` — Tasks 7–8 (D14, D17, D18); academy's own = B3 as built, no Etqan fee, taking precedence — Task 8 (`test_own_keys_win_over_connect`).
- §3.1 `AcademyAccount(payments)` stores only `acct_…` and onboarding status (plus country and mode, non-secret) — Task 7 (D12); keys only through `PlatformAccount` / `etqan.platform.secrets` — Tasks 3, 7.
- §5 Connect fees through `record_collected_fee` on `application_fee.created` — Task 9 (D19); not on the usage invoice (slice 2 D9 shows them read-only).
- §6 the payments card shows "Connect with Stripe" beside B3's keys, with status — Task 11 (D20); the video card's own-account form — Task 11.
- §3.2 feature switches: `zoom_api` built and gating Etqan's video default — Task 2 (D11); `online_payments` gating Connect — Task 7 (`test_connect_needs_etqans_default_for_this_academy`).
- §8 webhook-driven metering idempotent, no usage for `source == "academy"`, probes with faked providers, secrets never serialised — Tasks 3, 4, 7, 9.
- Owner decisions 2026-10-09: host pool — Tasks 3–5 (D21); Connect countries — Tasks 7, 10, 11 (D22); teacher host link — Tasks 3, 4, 6, 12 (D23).

**Spec gaps settled here:** D7/D9 (a "Jitsi link" never existed in the code: links were typed URLs only; this slice adds Jitsi rooms only for academies that turned on `zoom_api` or connected their own Zoom, so no other academy's sessions change); D18 (a fixed Connect fee applies only in its own currency); D19 (one URL for Stripe's two endpoints). Settled by the owner on 2026-10-09: D21 (host pool), D22 (Connect countries), D23 (teacher host link). New consequence of D21: a Zoom class on Etqan's default that is moved gets a new meeting and link (D8).
