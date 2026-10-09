# Slice B5c — WhatsApp — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (orchestration PO-3); review findings applied 2026-10-08.
**Phase spec:** `2026-10-07-b5-communication-design.md` §3 (B5c row) and B5-5, as amended for D40–D42 and D59.
This spec narrows the row: broadcasts by WhatsApp are not built (X-9).
**Builds on:** integrations slice 1 (merged, D59). It provides:
- `resolve(service)`, `PROVIDERS` (WhatsApp is `NotYet` today) and `SWITCHES`;
- `services/email.py` (the pattern for a service's send path and meter hook);
- Settings → Integrations.

**Evidence:** P1 COMM-005, INT-007, FLOW-013, SYS-001 ("supervisor WhatsApp"); TH §2.7 COMM-003 (channels Email ·
WhatsApp) and COMM-009 (TH audit line 67); ledger D40, D42, D49, D59; integrations IN-3 (one shared Etqan number,
templates carrying the academy's name), IN-8 (no two-way chat), §4 and §5. Meta's Cloud API template guidelines
and error codes are the external reference; anything not yet confirmed with Meta is marked [assumed].
**Requires:** B5a (merged), integrations slice 1 (merged).
**Claims:** one claim on `etqan.integrations` (owner: conductor), serialised with B10a's claim through the ledger
(D49 edits the same files).

## 1. Goal

Automatic notices can also go out by WhatsApp, through the official Cloud API, on Etqan's shared number or the
academy's own account. Only people who have opted in receive them. Everything is off by default.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| X-1 | **The send path lives in integrations' services, as email's does.** A new module, `etqan/integrations/services/whatsapp.py`, provides:<br>• `send_whatsapp_now(*, to, language, params) -> SentWhatsApp(resolved_source, message_id)`. It resolves the account (raising `NotSetUpError` when it is None), calls the provider, calls the meter hook, and returns.<br>• `meter_whatsapp(resolved, *, message_id)`: records usage with integrations slice 2's live metering (D62, D64): `etqan_billing.services.record_usage(source=resolved.source, service="whatsapp", unit="conversation", quantity=1, source_ref=message_id)`. It is called when the Cloud API **accepts** the message (returns a wamid), which is B5c's only provider confirmation (X-12, no webhook). That mirrors `meter_email`, which meters on acceptance by Message-ID. `record_usage` records only Etqan defaults and is idempotent per wamid (amended 2026-10-08 for D64).<br>Both are exported from `integrations.services`. Notifications imports only that package; the contract forbids `integrations.providers`. | integrations services/email.py; import contract; §5 |
| X-2 | **Provider** (`providers/whatsapp.py`, replacing `NotYet` in `PROVIDERS`). It uses `httpx` (already a dependency; `respx` fakes it in tests), a module constant `GRAPH_VERSION` pinned to a current Graph version, the host `https://graph.facebook.com` hard-coded, `follow_redirects=False`, a 10 s timeout, and the token sent only as `Authorization: Bearer`, never in a URL.<br>**`clean()`**, for own and default accounts alike, validates:<br>• `phone_number_id` and `waba_id` against `^\d{5,20}$`;<br>• `template` against `^[a-z0-9_]{1,512}$`;<br>• `languages` as a map of exact approved codes, `{"ar": "ar", "en": "en"}` by default;<br>• `access_token` (secret; a System User, non-expiring token).<br>**`last4()`** gives the token's last four characters. Meta's response bodies never reach an exception message, a log or a stored error. | review I12, I13; integrations §3.3 |
| X-3 | **Probe without sending** (a recorded deviation from integrations §3.3's "send a template to the tester", as D49 did for AI). The probe makes two GETs:<br>• `/{phone_number_id}?fields=display_phone_number,verified_name,quality_rating` checks the token and the number;<br>• `/{waba_id}/message_templates?name=<template>` checks the template is APPROVED in both configured languages with 3 body parameters.<br>The probe signature (`tester_email`) is unchanged and ignored, so no change touches `accounts.probe`, the views, the admin or B10a. | review C2; D49 precedent |
| X-4 | **One utility template per language, with fixed text around the variables** [assumed approval]. Etqan's number uses `etqan_notice`:<br>• **en:** "Message from {{1}}: {{2}}. {{3}} Open your academy's site for details."<br>• **ar:** "رسالة من {{1}}: {{2}}. {{3}} افتح موقع أكاديميتك لمزيد من التفاصيل."<br>The variables are the academy name (in the recipient's language), the notice title and the notice body (B5a-rendered). Every parameter has newlines, tabs and runs of spaces collapsed to single spaces. The hydrated body stays under 1024 characters: the body parameter is cut first, then the title. An academy's own account names its own template, which must have the same 3-parameter shape in both languages (the probe checks it). Notices are account and session events, so the utility category fits. | Meta template rules; review I1; IN-3 |
| X-5 | **Opt-in, not opt-out.** WhatsApp goes only to people who have **opted in**:<br>• **Parents:** `ParentProfile.has_whatsapp`, TH's "registered on WhatsApp", counts as opt-in, and the parent can switch it off on their account page.<br>• **Everyone else** (student, teacher, admin, staff): an explicit choice on their own account page, off by default.<br>The choice is stored in a B5-owned `WhatsAppChoice(user one-to-one, opted_in, updated_at)`. A parent's choice row, when present, overrides `has_whatsapp`. The office can see but not set someone else's choice [assumed: consent is personal]. A number is required: `User.phone`, already E.164 (`platform.validators.clean_phone`); the `+` is stripped for the API. | Meta opt-in policy; review I3; P1 PEOPLE-004 |
| X-6 | **Kept apart from B5a's preferences.** The WhatsApp choice is not a notice category: it never enters `categories_for`, `muted()` or the opt-out table. It has its own endpoint, `GET/PATCH /api/v1/notifications/whatsapp/` (self-service), and its own card on `/account`. It works whether or not `notification_preferences` is on, and appears only while `whatsapp` is on. | review I4; B5a T-8, T-10, T-12 |
| X-7 | **The channel is gated by the `whatsapp` switch, always.** Feature `whatsapp` ("WhatsApp messages" / "رسائل واتساب", group `communication`, off by default) goes under the B5 marker. While it is off, no WhatsApp is queued, even with an academy's own account connected. `SWITCHES["whatsapp"] = ("whatsapp",)` is set under the claim, so the resolver also offers Etqan's default only while it is on. | review I5; B5-3; integrations plan D7 |
| X-8 | **Per notice type.** `NotificationSetting` gains `whatsapp` (bool, default False), an additive field on B5's table. The settings form shows a WhatsApp column while the feature is on. | TH COMM-004; B5-10 |
| X-9 | **Broadcasts are not sent by WhatsApp.** Free-text office messages do not fit a utility template, and Meta would re-categorise them as marketing. On a shared number, one academy's quality rating would also affect every academy. B5b stays email + in-app. This is a non-goal until a broadcast template and its category are settled. | review I2 |
| X-10 | **Delivery state, decided at insert.** `Notification` gains these fields (additive, defaulted):<br>• `whatsapp_status`: `none` · `pending` · `sent` · `failed` · `skipped`;<br>• `whatsapp_sent_at`;<br>• `whatsapp_error`: our own wording plus Meta's integer error code;<br>• `whatsapp_message_id` (128 characters).<br>None of these leave the server except the status, which the B5b log shows.<br>At insert (`scan.store`):<br>• `none` when the type's WhatsApp setting is off or the feature is off;<br>• `pending` when the recipient opted in, has a number, and `resolve("whatsapp")` answers;<br>• `skipped` otherwise.<br>At send, only `resolve` is re-checked. Opt-ins are read once per store (one query). `has_whatsapp` is read through a new identity read service, `identity.services.whatsapp_parents(user_ids) -> set[int]` (one query). That needs request **R10** to the identity owner, the conductor, or a one-commit claim. So a scan with WhatsApp on costs two queries more, whatever the number of hits. | review I9 |
| X-11 | **Sending, locks and retries.** The task `notifications.deliver_whatsapp(schema, id)` runs as follows:<br>1. **Claim:** a conditional `UPDATE … SET whatsapp_status='sending' WHERE id=… AND whatsapp_status='pending'`. The call is made outside any row lock, so it never blocks the email task's `select_for_update(skip_locked)` on the same row.<br>2. **Retry, at most 3 tries with backoff:** transport errors before the request was sent, HTTP 5xx, 429, and Meta codes 130429, 131056 and 131000.<br>3. **Fail at once:** every other error, for example 131026 undeliverable, 132xxx template or parameter errors, 190 token refused ("The access token was refused") and 100.<br>4. **Read timeout after sending:** marked `failed`, not retried, because the API has no idempotency key and a retry could send twice.<br>5. **After the try:** the row is set to `sent` (with the message id) or back to `pending` (to retry) or `failed`.<br>Retry exceptions carry no phone number and no Meta body. `requeue_stuck` re-queues WhatsApp rows left `pending` or `sending` between 5 minutes and 24 hours, in one more query. | review I6–I8; spec 2026-09-26 §4.4 |
| X-12 | **No group posting, no two-way chat, no receipts** (D40, IN-8). Not built:<br>• TH's group routing;<br>• reading replies;<br>• integrations §4's auto-reply on the shared number, which needs the inbound webhook (slice 2's, with metering);<br>• delivery and read receipts.<br>"Sent" means the API accepted the message. | D40; IN-8; review I10 |
| X-13 | **Admins and staff** receive office notices by WhatsApp through their own `User.phone` once they opt in (X-5). No separate academy number field. | P1 SYS-001 · [assumed] |
| X-14 | **No real calls in tests or dev.** Tests use `respx`, and `PROVIDERS` swaps in a fake. Dev has no credentials, so `resolve` is None and deliveries are `skipped` until Etqan staff enter the shared number in the platform admin. | integrations tests |
| X-15 | **Existing integrations tests that pin WhatsApp as `NotYet`** move their NotYet examples to another still-NotYet service:<br>• `test_providers.py` around lines 162–171;<br>• `test_accounts.py` around 82–85;<br>• `test_admin.py` around 104–136;<br>• `test_api.py` around 72.<br>The dashboard Settings → Integrations gains a WhatsApp account form (own account) next to email's. | review I14 |

## 3. Tests

- **Provider:** `clean` (each validation rule, secrets kept), `last4`, the probe's two GETs (approved, missing, wrong
  shape, token refused), and `send`, all through `respx`. No token appears in URLs or logs.
- **`send_whatsapp_now`:** resolves, meters and raises `NotSetUpError`.
- **Insert-time status:** each `none` / `pending` / `skipped` path, and the fixed query count.
- **Task:** the claim and no double send; retry vs permanent classification; read timeout gives `failed`; the
  email task is not blocked; requeue.
- **Opt-in API and card:** per role, and the parent default from `has_whatsapp`.
- **Dashboard:**
  - the settings WhatsApp column;
  - the opt-in card;
  - the WhatsApp form in Settings → Integrations;
  - the log's WhatsApp status column and filter (B5b).
- **e2e:** dev has no credentials, so an admin turns WhatsApp on for `session.reminder` and a student opts in; after
  a scan the notification log shows WhatsApp `skipped`.

## 4. Requests and claims

- **Claim** `etqan.integrations` for:
  - `providers/whatsapp.py` and the `providers/__init__.py` entry;
  - `services/whatsapp.py` and the `services/__init__.py` exports;
  - the `SWITCHES` line;
  - the test moves;
  - the dashboard WhatsApp form.

  Serialised with B10a (D49) through the ledger.
- **R10 to the identity owner** (conductor): `identity.services.whatsapp_parents(user_ids) -> set[int]`, the ids
  whose `ParentProfile.has_whatsapp` is true, in one query.

## 5. Non-goals

- Broadcasts by WhatsApp (X-9).
- Group posting.
- Replies, auto-reply and receipts (X-12).
- Metering (slice 2).
- Meta Tech Provider.
- Per-notice Meta templates.
- SMS.
