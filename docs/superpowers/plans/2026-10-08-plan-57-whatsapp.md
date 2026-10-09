# Plan 57 — B5c WhatsApp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatic notices can also go out by WhatsApp (Cloud API) to people who opted in, through `integrations.services.send_whatsapp_now`. The channel is chosen per notice type and is off by default.

**Architecture:**
- **Integrations** (claim; the conductor owns it):
  - the provider `providers/whatsapp.py`, using httpx against Graph;
  - the send path `services/whatsapp.py`, with the `meter_whatsapp` hook;
  - the `SWITCHES` line;
  - a WhatsApp account form in Settings → Integrations.
- **Identity** (claim): `whatsapp_parents(user_ids)`.
- **Notifications** (B5-owned):
  - the `whatsapp` feature;
  - `NotificationSetting.whatsapp`;
  - delivery fields on `Notification`;
  - the `WhatsAppChoice` opt-in model and its API;
  - status decided at insert, a delivery task with a conditional-UPDATE claim and classified retries, and requeue.

**Tech Stack:** Django 5 + DRF + django-tenants, httpx + respx, Celery, pytest; React + TanStack + i18next, vitest; Playwright.

**Spec:** `docs/superpowers/specs/2026-10-08-b5c-whatsapp-design.md` (X-1…X-15), with the phase spec `docs/superpowers/specs/2026-10-07-b5-communication-design.md`.

**Requires:** B5a and B5b, merged before Task 1; integrations slice 1 (merged). The claim on `etqan.integrations` is serialised with B10a (D49, D60): take it right before Task 1's commits and release it right after the slice merges. Wait if B10a holds it.

## Global Constraints

- **Feature** `whatsapp`: "WhatsApp messages" / "رسائل واتساب", group `communication`, `built=True`, off by default, registered under `# ── phase B5 ──`. It gates the channel always (X-7). `SWITCHES["whatsapp"] = ("whatsapp",)`.
- **Provider:**
  - httpx with a 10 s timeout and `follow_redirects=False`;
  - host `https://graph.facebook.com`, with `GRAPH_VERSION` pinned as a module constant (use the current stable version, e.g. `"v23.0"`);
  - the token only in `Authorization: Bearer`;
  - Meta response bodies never appear in exceptions, logs or stored errors.
  - **Validation:**
    - `phone_number_id` and `waba_id` match `^\d{5,20}$`;
    - `template` matches `^[a-z0-9_]{1,512}$`;
    - `languages` maps `{"ar": code, "en": code}` with codes matching `^[a-z]{2}(_[A-Z]{2})?$`, defaulting to `{"ar": "ar", "en": "en"}`;
    - `access_token` (secret) is required on create and kept on edit when blank.
  - `last4` gives the token's last four characters.
- **Probe:** two read-only GETs (X-3). The signature keeps `tester_email`, which is ignored.
- **Template body parameters:** the academy name, the title and the body. Each is whitespace-collapsed, and the hydrated body is kept under 1024 characters (cut the body first, then the title).
- **Notification fields:**
  - `whatsapp_status` CharField(8): `none` · `pending` · `sending` · `sent` · `failed` · `skipped`, default `none`;
  - `whatsapp_sent_at`;
  - `whatsapp_error` CharField(200, blank);
  - `whatsapp_message_id` CharField(128, blank).

  None but `whatsapp_status` appear in any payload.
- **Opt-in:** `WhatsAppChoice(user one-to-one, opted_in, updated_at)`. A parent with no row defaults to `has_whatsapp`; everyone else defaults to False. A number is required (`User.phone`, E.164; the `+` is stripped).
- **Retry classes:**
  - retry: transport errors before the request was sent, HTTP 5xx, 429, and Meta codes 130429, 131056 and 131000;
  - fail immediately: everything else, and a read timeout after sending.

  At most 3 tries, with backoff 60 / 120 s.
- **Shared lists:** marker lines only (features, nav, registry if any). The integrations and identity edits go only under their claims. `FeatureCode` gains `whatsapp`.
- **Coverage:** backend ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- **Tools:** from the meta root:
  `S() { (set -a; . ./.env.stream; set +a; docker compose -f docker-compose.local.yml exec -T "$@"); }`
  - backend: `S django pytest …`, ruff, `lint-imports`;
  - migrations: `just _stack-manage makemigrations …` and `just migrate`;
  - dashboard: `S dashboard pnpm vitest run …` / `tsc` / `lint`;
  - e2e: `just e2e e2e/b5-whatsapp.spec.ts`.

## Review Focus

1. The access token never appears in a URL, a log line, an exception message, a Celery result or an API payload. Task 1 asserts it with respx and caplog.
2. A WhatsApp task and the email task for the same row never block each other, and a row is never sent twice. Task 4 tests both.
3. A parent with `has_whatsapp=True` but no choice row is opted in; a parent who switched it off is not; a student with no choice is not. Task 3 tests all three.
4. With the `whatsapp` feature off, nothing is queued even when an academy's own account is connected. Task 4 tests it.
5. The hydrated template body stays under 1024 characters for a 4000-character broadcast-like body, with newlines collapsed. Task 1 tests it.

---

### Task 1: Integrations — WhatsApp provider and send path (claim etqan.integrations)

**Files:**
- Create: `backend/etqan/integrations/providers/whatsapp.py`, `backend/etqan/integrations/services/whatsapp.py`, and their tests
- Modify: `providers/__init__.py` (`PROVIDERS["whatsapp"]`), `services/__init__.py` (export `send_whatsapp_now`, `meter_whatsapp`, `SentWhatsApp`, `WhatsAppNotSetUp`, or reuse `NotSetUpError`), `services/resolver.py` (`SWITCHES`)
- Modify: the existing integrations tests that pin WhatsApp as `NotYet` (spec X-15). Move those examples to another still-NotYet service (`payments` or `video`).

**Interfaces:**
- **`WhatsAppProvider`:** `service = "whatsapp"`, `connectable = True`, and:
  - `clean(fields, *, stored, own=True) -> (config, secrets)`;
  - `last4(values)`;
  - `probe(*, config, secrets, tester_email)`;
  - `send(*, config, secrets, to, language, params) -> str`, which returns the `wamid`.

  It raises `WhatsAppError(code: int | None, retry: bool, message: str)`, where the message is our own wording.
- **`send_whatsapp_now(*, to: str, language: str, params: list[str]) -> SentWhatsApp(source: str, message_id: str)`:**
  1. `resolve("whatsapp")`, raising `NotSetUpError` when it is None;
  2. `provider.send`;
  3. `meter_whatsapp(resolved, message_id=…)`, which calls `etqan_billing.services.record_usage(source=resolved.source, service="whatsapp", unit="conversation", quantity=1, source_ref=message_id)` (D64; it mirrors `meter_email`; check the integrations→etqan_billing import contract, which slice 2 renamed);
  4. return.
- **`build_params(academy_name, title, body) -> list[str]`:** the collapse-and-budget helper of X-4, exported for notifications.

Steps:
- [ ] Take the claim (from the meta root): `python3 scripts/orchestration/ledger.py claim B5 integrations --reason "B5c WhatsApp provider (D60)"`. If B10a holds a claim on integrations, wait and record `waiting-deps`.
- [ ] **Tests (RED), with respx and no real network:**
  - each validation rule, for own and default accounts;
  - the secret is kept on edit;
  - `last4`;
  - probe: approved; a missing language; a wrong parameter count; HTTP 401 → our "The access token was refused".
  - send: success → wamid; 5xx and 131056 → `retry=True`; 131026 and 132000 → `retry=False`; a read timeout → `retry=False`.
  - the token never appears in the request URL or in caplog text;
  - `build_params` collapses newlines and keeps the 1024 budget;
  - `send_whatsapp_now` resolves, calls the provider and records one usage event per wamid only when the source is Etqan (assert a second call with the same wamid records nothing), and raises `NotSetUpError` when nothing resolves;
  - `SWITCHES["whatsapp"]` gates the Etqan default.
- [ ] **Implement; run** `S django pytest etqan/integrations -q`, ruff and `lint-imports`.
- [ ] **Commit** `feat(integrations): WhatsApp Cloud API provider and send path (B5c)`.

### Task 2: Identity — whatsapp_parents (claim etqan.identity, R10)

**Files:** `backend/etqan/identity/services.py` (one additive function, exported if identity uses `__all__`) and an identity test.

- [ ] Take the claim: `python3 scripts/orchestration/ledger.py claim B5 identity --reason "R10 whatsapp_parents (D60)"`.
- [ ] **Test (RED):** ids of parents with `has_whatsapp` among the given ids; non-parents and unknown ids are excluded; one query (`django_assert_num_queries(1)`).
- [ ] **Implement:**

```python
def whatsapp_parents(user_ids) -> set[int]:
    """R10 (B5c): the ids among ``user_ids`` of parents registered on WhatsApp."""
    return set(
        ParentProfile.objects.filter(user_id__in=list(user_ids), has_whatsapp=True)
        .values_list("user_id", flat=True)
    )
```

- [ ] **Run, commit** `feat(identity): whatsapp_parents read service (R10, B5c)`, and note the claim (release it after merge).

### Task 3: Notifications — feature, models, opt-in service and API

**Files:**
- `backend/etqan/platform/features.py` (marker) and the `test_features` BUILT list;
- `etqan/notifications/models.py`: `NotificationSetting.whatsapp`, the `Notification.whatsapp_*` fields and `WhatsAppChoice`;
- migration `0005_whatsapp` (the B5d migration is 0004 if merged first; otherwise renumber as `makemigrations` decides);
- `services/whatsapp_choice.py`: `choice_of(user) -> bool`, `set_choice(user, opted_in) -> bool`, `opted_in_ids(users) -> set[int]` (one query plus one `whatsapp_parents` query);
- the API `GET/PATCH /api/v1/notifications/whatsapp/` (self-service, `[IsAuthenticated, FeatureOn("whatsapp")]`), answering `{opted_in, phone_on_file: bool}`;
- `SettingChangeInput` accepts `whatsapp`, and `setting_rows` includes it;
- the route test (`SELF_SERVICE` entry and the `FEATURE_WORDS` word `/notifications/whatsapp/`).

- [ ] **Tests (RED):**
  - Review Focus 3 defaults;
  - `set_choice` round trip;
  - the API per role (a parent default is true from `has_whatsapp`; a student default is false);
  - feature off → 404;
  - the settings PATCH accepts `whatsapp` for any type;
  - `opted_in_ids` makes 2 queries.
- [ ] **Implement, migrate, run, commit** `feat(notifications): WhatsApp opt-in, per-type switch and delivery fields (B5c)`.

### Task 4: Notifications — status at insert, delivery task, requeue

**Files:** `services/scan.py` (`store`), new `channels/whatsapp.py`, `tasks` registration, and tests.

- **`store`:** while `whatsapp` is on and the row's type setting has `whatsapp=True`:
  - `whatsapp_status = pending` when the user is opted in, has a phone, and `integrations.services.resolve("whatsapp")` is not None;
  - `skipped` otherwise;
  - `none` when the type's WhatsApp is off or the feature is off.

  Opt-ins are read once per store (`opted_in_ids`). Pending ids are queued on commit, like email.
- **`channels/whatsapp.py`:**
  - `queue(ids)`;
  - task `notifications.deliver_whatsapp(schema, id)`:
    1. a conditional `UPDATE … SET whatsapp_status='sending' WHERE pk=id AND whatsapp_status='pending'` (no row lock held across the HTTP call);
    2. build the params with `integrations.services.build_params(academy name in the row's language, title, body)`;
    3. `send_whatsapp_now(to=phone_without_plus, language=row.language, params=...)`;
    4. on success, `sent` with the message id and `whatsapp_sent_at`;
    5. on a `WhatsAppError` with `retry`, set back to `pending` and retry with countdown 60·2^n, at most 3 tries in all; then `failed`;
    6. a non-retry error is `failed`;
    7. `NotSetUpError` is `skipped`.

    Errors are stored as `"<our wording> (code <n>)"`, under 200 characters. Retry exception text carries no phone number or Meta body.
- **`requeue_stuck`:** it also re-queues WhatsApp rows that are `pending` or `sending` between 5 minutes and 24 hours old, with one more query.

- [ ] **Tests (RED):**
  - each status path at insert;
  - fixed query counts (+2 with WhatsApp on: opt-ins and `whatsapp_parents`);
  - the claim prevents a double send (two task calls, one send);
  - the email task's `select_for_update(skip_locked)` is not blocked while a WhatsApp send is in flight (the WhatsApp task holds no lock);
  - the retry classification;
  - Review Focus 4;
  - requeue.

  Fake the integrations service with monkeypatch on `etqan.integrations.services.send_whatsapp_now`.
- [ ] **Implement, run, commit** `feat(notifications): WhatsApp delivery for automatic notices (B5c)`.

### Task 5: Dashboard — integrations form, settings column, opt-in card, log column

**Files:**
- `dashboard/src/features/integrations/` (a WhatsApp account form next to `EmailAccountForm`, under the claim: fields phone number id, WABA id, template, languages ar/en codes, access token (password, kept when blank), and Test);
- `features/notifications/NotificationSettingsForm.tsx` (a WhatsApp column while `whatsapp` is on);
- a new `WhatsAppChoiceCard` on `/account` (the one-line mount; shown while `whatsapp` is on; disabled with a hint when there is no phone on file);
- `NotificationLogPage` (a WhatsApp status column and filter, only when the backend sends it; extend `LogQuery` with `whatsapp_status` in Task 4 if needed);
- `FeatureCode` gains `whatsapp`;
- locales: `integrations.json` and `notifications.json` (en/ar).

- [ ] **Tests (RED):** each UI piece, its gating, and that the token field is never pre-filled.
- [ ] **Implement, then run** vitest, tsc and lint.
- [ ] **Commit** `feat(notifications): WhatsApp settings, opt-in card and integrations form (B5c)`.

### Task 6: e2e and gates

- [ ] `e2e/b5-whatsapp.spec.ts`:
  1. `set_features demo --on whatsapp auto_notifications`;
  2. the admin ticks WhatsApp for `session.reminder` in Settings;
  3. a stamped student with a phone opts in on `/account`;
  4. after `manage("scan_notifications", …)` with a reminder due, the log shows WhatsApp `skipped` (dev has no credentials, X-14).
- [ ] **Gates:** `just migrate`, `just test`, `just lint`, `just secrets`, `just e2e`, and dashboard coverage.
- [ ] **Commit** `test(e2e): B5c WhatsApp`.
