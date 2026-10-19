# F09: Student billing (invoices, payments, wallet, vouchers, online payments)

Author: Agent 1 (research and test strategy), LEAN mode. This spec approves nothing.
Written 2026-10-18 from backend adff9c9 / dashboard 5ed775d. Code read: `billing/{models,scopes,services/*,api/*}`,
`wallet/{services/*,api/*}`, `vouchers/{services/*,api/*}`, `gateways/{services/*,api/*}`,
`platform/{currency,validators,permissions,csv}`. Docs: `docs/features/{billing,online-payments,wallet,vouchers}.md`.
Existing coverage: backend pytest in `billing/tests`, `wallet/tests`, `vouchers/tests`, `gateways/tests` (unit level, pinned clock,
fakes) and e2e `dashboard/e2e/{billing,b3-codes,b3-online-payments,b3-payment-links,b3-paypal,b3-wallet}.spec.ts`.
This spec is black-box API + DB against the live qa academy, so it re-checks P1-critical money rules end to end rather than
duplicating pytest. Cases cite the pytest module that already covers the rule at unit level.

Conventions: amounts are minor units (`50000` = 500.00 EGP). qa academy = EGP, Africa/Cairo. Base URL `$B` =
`http://qa.etqan.localhost/api/v1`. "DB" = schema `academy_qa`. Provider tags: online cases are SIMULATED (GATEWAYS_SIMULATE),
everything else REAL. Stripe/PayPal live behaviour is BLOCKED (see coverage-gaps F09).

Totals: 27 cases. P1 23, P2 4. UI smoke (Playwright, `--workers=1`): TC-001, TC-021, TC-022. Everything else API + DB.

---

## Setup (run once, in order)

Shell helpers (put in the scratchpad `f09/env.sh`; `$QA` = scratchpad dir):

```bash
export HOST=http://qa.etqan.localhost B=http://qa.etqan.localhost/api/v1 QA=/private/tmp/claude-501/-Users-khaledsakr-Documents-Etqan-tutor/55afddca-abb7-4698-b08b-38df7f0acb0e/scratchpad
mkdir -p $QA/f09
login() { # login <jarname> <email> <password> [host]
  local h=${4:-$HOST} j=$QA/f09/$1.jar; rm -f $j
  curl -s -c $j $h/api/v1/identity/csrf/ >/dev/null
  curl -s -b $j -c $j -X POST -H "Content-Type: application/json" -H "X-CSRFToken: $(awk '$6=="csrftoken"{print $7}' $j)" \
    -H "Referer: $h/" -d "{\"identifier\":\"$2\",\"password\":\"$3\"}" -w ' %{http_code}\n' $h/api/v1/identity/login/; }
api() { # api <jar> <METHOD> <path> [json] [host]   -> body, then HTTP code on the last line
  local j=$QA/f09/$1.jar h=${5:-$HOST}
  curl -s -b $j -c $j -X $2 -H "Content-Type: application/json" -H "X-CSRFToken: $(awk '$6=="csrftoken"{print $7}' $j)" \
    -H "Referer: $h/" ${4:+-d "$4"} -w '\n%{http_code}\n' "$h/api/v1$3"; }
PG=$(docker ps -qf name=postgres | head -1)
q() { docker exec $PG psql -U etqan -d etqan -Atc "SET search_path=academy_qa; $1"; }   # DB check
anon() { curl -s -X $1 -H "Content-Type: application/json" ${3:+-d "$3"} -w '\n%{http_code}\n' "$HOST/api/v1$2"; }
whsend() { # whsend <event.json> [secret]  (raw-body Stripe webhook with a valid signature, now)
  local ts=$(date +%s) s=${2:-whsec_qa_f09}
  local sig=$(python3 -c 'import hmac,hashlib,sys;ts,sec,f=sys.argv[1:4];print(hmac.new(sec.encode(),ts.encode()+b"."+open(f,"rb").read(),hashlib.sha256).hexdigest())' $ts $s $1)
  curl -s -X POST -H "Stripe-Signature: t=$ts,v1=$sig" -H "Content-Type: application/json" --data-binary @$1 -w '\n%{http_code}\n' $HOST/api/v1/gateways/webhooks/stripe/; }
mkevt() { # mkevt <file> <event_id> <type> <checkout_uuid> <amount_total> <currency_lower> <payment_intent> [livemode=false]
  local ref=$(q "select provider_ref from gateways_checkout where id='$4'")
  printf '{"id":"%s","type":"%s","livemode":%s,"data":{"object":{"id":"%s","object":"checkout.session","client_reference_id":"%s","metadata":{"checkout":"%s"},"payment_status":"paid","amount_total":%s,"currency":"%s","payment_intent":"%s"}}}' \
    $2 $3 ${8:-false} "$ref" $4 $4 $5 $6 $7 > $1; }
```

1. **Features on qa** (schema stays `academy_qa`):
   `dc.sh exec -T django python manage.py set_features qa --on parents families invoices payment_receipts online_payments payment_links balances system_codes export`
   Check `select features from public.tenants_academy where subdomain='qa'` shows them. `country_pricing`, `donations`, `recorded_courses` stay off.
2. **Sessions:** `login admin qa-admin@qa.etqan.test 'QA-Admin-2026!'`; `login staffno qa-staff-nocode@qa.etqan.test 'QA-People-2026!'`;
   `login staffc qa-staff-codes@qa.etqan.test ...`; `login sup qa-supervisor@...`; `login teacher qa-teacher@...`;
   `login student qa-student@...`; `login parent qa-parent@...`; `login oadmin qaother-admin@qa.etqan.test 'QA-Other-2026!' http://qaother.etqan.localhost`.
   User ids in qa: admin 1, staff-nocode 2, staff-codes 3, supervisor 4, student 5 (`S1`), parent 6 (`P1`), teacher 7.
3. **Second family and a sibling payer** (isolation and sibling cases). Student payload keys come from `PersonWriteSerializer`
   (`{"user":{"full_name","email"},"profile":{...}}`); if a field is refused, read the 400:
   - `api admin POST /people/students/ '{"user":{"full_name":"QA Student Two","email":"qa-student2@qa.etqan.test"},"profile":{"country":"EG"}}'` -> `S2`
   - `api admin POST /people/parents/ '{"user":{"full_name":"QA Parent Two","email":"qa-parent2@qa.etqan.test"}}'` -> `P2`
   - `api admin POST /people/students/$S2/guardians/ '{"parent_id":'$P2'}'`; same for `$P1` and `$S1` if `GET /people/students/5/guardians/` is empty.
   - Passwords for the new users: `dc.sh exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.identity.models import User; [ (u.set_password('QA-People-2026!'), u.save()) for u in User.objects.filter(email__in=['qa-student2@qa.etqan.test','qa-parent2@qa.etqan.test'])]"`, then `login student2`, `login parent2`.
   - Sibling payer: a third student `S3` "QA Student Three" and a family `POST /people/families/ '{"name":"QA Fam","student_ids":[S1,S3],"payer_id":P1}'` is NOT needed. Instead create `S1`'s sibling payer by making `S3`'s parent `P3` ("QA Parent Three") the family payer of family {S1,S3}: `POST /people/families/ '{"name":"QA Fam","student_ids":[5,S3],"payer_id":P3}'` (P3 is a parent of S3 only). Invoices for S1 then default to payer P3, who is not S1's guardian (the "paying sibling" role in wallet/vouchers).
4. **Staff roles for billing:** `api admin POST /access/roles/` with
   `{"name_ar":"فوترة","name_en":"QA Billing","permissions":["invoice.view","invoice.view_any","invoice.create","invoice.update","payment.view_any","payment.create","payment.update","payment.delete","widget.revenue_stats","payment_method.view_any","payment_method.create","payment_method.update","payment_method.delete","checkout.view_any","checkout.update","payment_link.view_any","payment_link.create","payment_link.update","wallet.view_any","wallet.create","wallet.update","voucher.view_any","voucher.create","voucher.update","subscription.view","subscription.view_any","subscription.create","subscription.update","student.view","student.view_any","gateway.view","gateway.update"]}` -> `R_BILL`.
   Narrow role `QA Billing Narrow` (`invoice.view`, `invoice.view_any`, `payment.view_any`) -> `R_NARROW`. Assign `api admin PATCH /access/staff/3/ '{"role_ids":[<QA Student View id>,R_BILL]}'` (keep its existing role). qa-staff-nocode keeps zero codes. Re-read the registry (`GET /access/registry/`) if a code name is refused.
5. **Catalogue:** `api admin POST /catalogue/courses/ '{"name_ar":"تجويد","name_en":"Tajweed QA","teacher_ids":[7]}'` -> `COURSE`;
   `api admin POST /catalogue/packages/ '{"name_ar":"شهري","name_en":"Monthly QA","sessions_per_week":2,"session_minutes":30,"duration_value":1,"duration_unit":"month","price_minor":150000,"currency":"EGP"}'` -> `PKG`.
6. **Academy settings:** `api admin PATCH /academy/settings/ '{"auto_invoice_on_subscription":true,"invoice_due_days":7}'`.
7. **Gateways (SIMULATED):** `api admin PATCH /gateways/settings/ '{"stripe":{"enabled":true,"mode":"test","public_key":"pk_test_f09","secret":"sk_test_f09","webhook_secret":"whsec_qa_f09"},"fee":{"enabled":true,"basis_points":500}}'`.
   PayPal (TC-027 only): `{"paypal":{"enabled":true,"mode":"test","client_id":"cid_f09","secret":"sec_f09","webhook_id":"WH-F09","currency":"USD"}}`. It is accepted without a PayPal call only because `GATEWAYS_SIMULATE=True`.
8. **Billing settings:** `api admin PATCH /billing/settings/ '{"local_payment_enabled":true}'`.
9. **Throttle hygiene:** voucher throttles use the cache. Clear before and after throttle cases:
   `dc.sh exec -T django python manage.py shell -c "from django.core.cache import cache; cache.clear()"`.
10. **Baseline snapshot:** `q "select count(*) from billing_invoice; select count(*) from billing_payment; select count(*) from wallet_walletentry; select count(*) from vouchers_voucher; select count(*) from gateways_checkout"` (all 0 on a fresh qa). Each case prints the row counts it changes.

Conventions in the cases: `INV` = the invoice id returned, `PAY` = payment id. Admin session is `admin` unless stated.

---

## A. Invoices

#### F09-TC-001: Manual invoice end to end, as an academy owner would use it [UI smoke 1]
- **Role:** admin. **Switches:** invoices (+ parents, families). **Priority:** P1. **Provider:** REAL.
- **Data:** S1 (guardian P1). No subscription.
- **Steps:**
  1. `GET /billing/payers/?student=5` (default payer first).
  2. `POST /billing/invoices/` `{"student":5,"amount_minor":50000,"due_on":"<today+7>","description":"Tajweed - October","notes":"internal note"}`.
  3. `GET /billing/invoices/INV/`, `GET /billing/invoices/?student=5`, `GET /billing/invoices/?status=unpaid&q=Tajweed`.
  4. Repeat step 2 twice more with `"currency":"usd"` (lower case) and `"payer":<S1 user id>`.
  5. UI: Playwright signs in as admin, opens Billing > Invoices > New, creates one, opens detail, prints (`/app/_print/invoices/<id>/print`), shows status chip "Unpaid".
- **Expected:** 201 with the detail payload. Number `INV-000001`, `000002`, `000003` strictly increasing, no gaps. `amount_minor` an integer, `status=unpaid`, `paid_minor=0`, `balance_minor=50000`, `currency=EGP` (academy default) then `USD`. `issued_on` is the academy (Africa/Cairo) date. Payer is the first of `payers` (family payer, then guardians, then student): `P1` here (or `P3` once the sibling family from Setup 3 exists; record which and check it equals `payers[0]`). Explicit `payer=5` is accepted.
- **Assertions:** DB `select number,payer_id,student_id,amount_minor,currency,issued_on,due_on,status,subscription_id,created_by_id from billing_invoice order by id`; `select last_number from billing_invoicecounter` equals 3. `issued_on = (now() at time zone 'Africa/Cairo')::date` (run once between 22:00 and 24:00 UTC to prove it is not the UTC date). Notes visible to admin, hidden to the family (TC-013). Print page shows amount formatted from minor units with the right decimals.
- **Existing:** `billing/tests/test_invoices.py`, `test_api.py`, e2e `billing.spec.ts`.
- **Cleanup:** keep INV for later cases (record as `INV1`).

#### F09-TC-002: Invoice input validation, gap-free numbering and no 500s
- **Role:** admin. **Switches:** invoices. **Priority:** P1. **Provider:** REAL.
- **Steps:** each as `POST /billing/invoices/` (base body `{"student":5,"amount_minor":10000,"due_on":"<today>","description":"x"}`) with one field changed. Record `last_number` before and after the whole batch.
  - `amount_minor`: `0`, `-5`, `1.5`, `"100"`, `true`, `null`, `9223372036854775808`, `99999999999999999999`.
  - `due_on`: yesterday (needs `issued_on <= due_on`), `"2026-13-40"`, missing. `description`: missing, `""`.
  - `currency`: `"EG"`, `"EGPX"`, `"12$"`, `"egp"` (valid, normalised).
  - `student`: a teacher's id (7), a deactivated student, `999999`. `payer`: P2 (not in S1's family), the teacher.
  - `subscription`: an id of S2's subscription (create one in TC-003) for student 5; and with `currency:"USD"` against an EGP subscription.
- **Expected:** 400 with the offending field (`amount_minor`, `due_on`, `currency`, `student`, `payer`, `subscription`) for every refused row; never 500. The valid `"egp"` row is 201 with `currency=EGP`. A bool/float/string amount is refused. 2^63 and larger are 400 (database range validator), not an IntegrityError 500.
- **Assertions:** `billing_invoicecounter.last_number` increased only by the number of 201 responses (a refused invoice takes no number, `billing.md` Manual invoice). `select count(*) from billing_invoice where amount_minor<=0` is 0. API log shows no 5xx: `dc.sh logs --since 5m django | grep -c ' 500 '`.
- **Existing:** `test_invoices.py` (numbering, refusal), `test_api.py`; the 2^63 / float / bool rows are new.
- **Cleanup:** none.

#### F09-TC-003: Subscription creates exactly one invoice (price, currency, due date, description, payer, switches)
- **Role:** admin. **Switches:** invoices, parents/families. **Priority:** P1. **Provider:** REAL.
- **Data:** COURSE, PKG (150000 EGP), teacher 7.
- **Steps:**
  1. `POST /subscriptions/` `{"student":5,"course":COURSE,"teacher":7,"package":PKG,"starts_on":"<today>"}` -> `SUB1`.
  2. Same with `"price_minor":99950,"currency":"USD"` for S2 -> `SUB2` (price override and currency).
  3. `price_minor:0` for S1 -> `SUB0`.
  4. `PATCH /academy/settings/ {"auto_invoice_on_subscription":false}`; create SUB3; restore `true`.
  5. `dc.sh ... set_features qa --off invoices`; create SUB4; `--on invoices`.
  6. `GET /billing/invoices/?subscription=<SUB1>`; `GET /subscriptions/?student=5` (payment status per subscription).
  7. Failure path: temporarily make the invoice fail (student deactivated is refused earlier by scheduling, so instead set the only guardian inactive and the student inactive is not testable) - skip; failure rollback is covered by pytest `test_subscription_api.py`.
- **Expected:** SUB1 -> one invoice, `amount_minor=150000`, `currency=EGP`, `due_on = issued_on + 7`, `description="Tajweed QA — Monthly QA"` (English or Arabic per `default_language`), `subscription_id=SUB1`, default payer rule as TC-001. SUB2 -> `99950 USD`, one invoice. SUB0, SUB3, SUB4 -> no invoice. Subscription list shows SUB1 `unpaid`, SUB0 `none`.
- **Assertions:** DB `select subscription_id,count(*),sum(amount_minor) from billing_invoice where subscription_id is not null group by 1` gives one row per invoiced subscription; no subscription has two non-void invoices. Subscription row `price_minor` equals the invoice amount.
- **Existing:** `test_subscriptions.py`, `test_subscription_api.py`, `test_features.py`. New: end-to-end with the real switch flips.
- **Cleanup:** keep SUB1, SUB2.

#### F09-TC-004: Editing, renewing, cancelling and deleting a subscription versus its invoice (known STATE note)
- **Role:** admin. **Switches:** invoices. **Priority:** P2. **Provider:** REAL.
- **Steps:**
  1. `PATCH /subscriptions/SUB1/ {"price_minor":120000}`. Read the subscription and its invoice.
  2. `POST /subscriptions/SUB1/renew/ {}` (confirm the body in `scheduling/api/serializers.py`).
  3. `DELETE /subscriptions/SUB1/` (expect refusal while invoiced).
  4. Void the invoice (TC-007 route), then `DELETE` again on a subscription with no completed sessions.
  5. `POST /subscriptions/SUB2/cancel/`, then read its invoice and the billing summary.
- **Expected:** 1: subscription `price_minor=120000`; the **invoice stays `150000`** (the known note; record it, do not file as a bug unless the UI claims the invoice follows). 2: renewal makes a second invoice at the renewal price. 3: 409 `billing.subscription_invoiced`. 4: succeeds once all its invoices are void. 5: cancelling leaves the invoice open and still counted in overdue (record exactly what happens; a cancelled subscription with an unpaid invoice is a P3 observation unless it blocks payment).
- **Assertions:** `select id,subscription_id,amount_minor,status from billing_invoice where subscription_id in (...)`; `select price_minor,status from scheduling_subscription ...`.
- **Existing:** `test_subscriptions.py` (invoice rules, delete refusal).
- **Cleanup:** none.

## B. Payments, refunds, reconciliation

#### F09-TC-005: Partial payments and the status function
- **Role:** admin. **Switches:** invoices. **Priority:** P1. **Provider:** REAL.
- **Data:** a fresh invoice `A` 50000 EGP for S1.
- **Steps:** `POST /billing/invoices/A/payments/`:
  1. `{"amount_minor":20000,"method":"cash","paid_on":"<today>","reference":"R1"}`
  2. `{"amount_minor":29999,"method":"bank_transfer","paid_on":"<today-3>"}` (before the issue date is allowed too: use `<today-30>`)
  3. `{"amount_minor":1,"method":"instapay","paid_on":"<today>"}`
  After each, `GET /billing/invoices/A/`, `GET /billing/invoices/A/payments/`, `GET /billing/invoices/?status=partial`.
- **Expected:** after 1 `partial`, `paid_minor=20000`, `balance_minor=30000`; after 2 `partial`, `49999`/`1`; after 3 `paid`, `paid_minor=50000`, `balance_minor=0`. Each response 201 with the refreshed invoice. A `paid` invoice is not listed under `?status=partial`.
- **Assertions:** `select sum(amount_minor) filter (where status='completed') from billing_payment where invoice_id=A` equals `paid_minor`; `select status from billing_invoice where id=A` = `paid`; every payment `currency=EGP`, `fee_minor=0`, `recorded_by_id=1`, `invoice_id=A`.
- **Existing:** `test_invoices.py`, `test_rules.py`.
- **Cleanup:** none.

#### F09-TC-006: Overpayment, reserved methods, dates, duplicate numbers and concurrent payers
- **Role:** admin. **Switches:** invoices. **Priority:** P1. **Provider:** REAL.
- **Data:** fresh invoice `B` 10000 EGP; fresh `V` 10000 EGP (voided in step 6).
- **Steps:**
  1. `POST .../B/payments/` `amount_minor:10001` (overpayment), `0`, `-1`, `2.5`, `"abc"`.
  2. `method` each of `stripe`, `paypal`, `wallet`, `code`, `bitcoin`.
  3. `paid_on` tomorrow; `paid_on` `"31/12/2026"`.
  4. Pay 4000 cash, then try 6001.
  5. Two parallel requests, each paying the remaining 6000: `for i in 1 2; do (api admin POST /billing/invoices/B/payments/ '{"amount_minor":6000,"method":"cash","paid_on":"<today>"}' &) ; done; wait`.
  6. Void `V` (TC-007), then `POST .../V/payments/` 1000.
  7. A third party invoice id in another academy: `POST .../<qaother invoice id>/payments/` (404 expected; set up in TC-014).
- **Expected:** step 1/2/3 400 on `amount_minor`/`method`/`paid_on`, message for method says online/wallet/code are recorded by their own flows. Step 4 second call 400 "more than the balance". Step 5: exactly one 201 and one 400, never two. Step 6: 409 `billing.invoice_void`.
- **Assertions:** DB `sum(amount_minor)` of completed payments on `B` is exactly 10000, `status=paid`, never above `amount_minor`. No row with method in (`stripe`,`paypal`,`wallet`,`code`) on `B`. `select count(*) from billing_payment where invoice_id=V` is 0.
- **Existing:** `test_invoices.py` ("stale copy never pays past the balance"/"voided invoice"), `test_online.py`. The parallel API race and 2.5/"abc" rows are new.
- **Cleanup:** none.

#### F09-TC-007: Editing and voiding an invoice
- **Role:** admin. **Switches:** invoices. **Priority:** P1. **Provider:** REAL.
- **Data:** invoices `E1` (unpaid), `E2` (partly paid 1000), `E3` (paid), `E4` (only a refunded payment).
- **Steps:**
  1. `PATCH /billing/invoices/E1/ {"amount_minor":65000,"description":"edited","notes":"n","due_on":"<today+14>"}`; `PATCH {"due_on":"<yesterday>"}`; `PATCH {"amount_minor":0}`.
  2. `PATCH E2 {"amount_minor":9999}` and `{"amount_minor":<same as now>}` and `{"description":"ok"}`.
  3. `POST /billing/invoices/E2/void/`, `E3/void/`, `E4/void/`, `E1/void/`.
  4. `PATCH /billing/invoices/E1/ {"description":"again"}`; `POST E1/void/` again; pay E1.
  5. `GET /billing/invoices/?status=void`; `GET /billing/summary/`.
- **Expected:** 1: first 200 (amount changed since nothing paid), second 400 on `due_on` (must be on/after `issued_on`, a due date in the past but after issue is fine), third 400. 2: new amount 409 `billing.has_payments`; unchanged amount and description 200. 3: E2, E3 409 `billing.has_payments`; E1 200 `status=void`; E4: record the observed result (code voids it because only *completed* payments block; `billing.md` says "no payments": note the docs gap in Suspected S1). 4: edit 409 `billing.invoice_void`, second void 409, payment 409. 5: void list contains E1; a void invoice reports `balance_minor=0` and is not in overdue.
- **Assertions:** `select status,voided_at,voided_by_id,amount_minor from billing_invoice where id in (...)`; summary `overdue` counts exclude void and paid.
- **Existing:** `test_invoices.py`, `test_summary.py`.
- **Cleanup:** none.

#### F09-TC-008: Refund and delete a manual payment; invoice follows
- **Role:** admin. **Switches:** invoices. **Priority:** P1. **Provider:** REAL.
- **Data:** invoice `F` 30000 with payments cash 10000 (`P_a`), instapay 20000 (`P_b`, `transaction`... use reference).
- **Steps:**
  1. `POST /billing/payments/P_b/refund/`; read invoice. Repeat the refund.
  2. `POST /billing/invoices/F/payments/` pay 20000 again (re-pay is allowed).
  3. `DELETE /billing/payments/P_a/` ; `DELETE /billing/payments/P_a/` again.
  4. `GET /billing/payments/?status=refunded` (needs `payment_receipts`), `GET /billing/summary/`.
- **Expected:** 1: invoice goes `paid` -> `partial` (paid 10000), payment `status=refunded`, `refunded_at/by` set; second refund 409 `billing.already_refunded`. 2: 201, invoice `paid` again (refunded payment not counted). 3: first 204 and invoice recalculated to `partial`; second 404. 4: refunded row present, revenue excludes it.
- **Assertions:** DB `select id,status,refunded_at,refunded_by_id from billing_payment where invoice_id=F`; invoice `status` equals `status_for(sum completed)` (compute with SQL: `case when s=0 then 'unpaid' when s<amount then 'partial' else 'paid' end`).
- **Existing:** `test_refunds.py`, `test_api.py`.
- **Cleanup:** none.

#### F09-TC-009: Reconciliation of paid totals, revenue and CSV, across currencies
- **Role:** admin. **Switches:** invoices, payment_receipts, export. **Priority:** P1. **Provider:** REAL.
- **Data:** everything produced by TC-001..008 plus the USD invoice from TC-001 step 4 (pay 5050 on it), a JPY invoice (`currency:"JPY"`, `amount_minor:1500`) and a KWD invoice (`currency:"KWD"`, `amount_minor:12345`, pay 12345). Run again at the very end of the campaign for F09 (after online/wallet/code cases).
- **Steps:** `GET /billing/summary/`; `GET /billing/invoices/?format=csv`; `GET /billing/payments/?format=csv`; `GET /billing/payments/?currency=USD`; SQL.
- **Expected:** `revenue_this_month` is a list of `{currency, amount_minor}` per currency, never one summed number. EGP revenue = sum over `status in (completed,credited)` and `method not in (wallet,code)` of `amount_minor+fee_minor` with `paid_on` in the current Cairo month. Overdue count/balance per currency equals open invoices due before today. CSV amounts are raw minor-unit integers (JPY `1500`, KWD `12345`), one currency per row. A CSV cell that starts with `=`, `+`, `-`, `@` is defused (create an invoice description `=HYPERLINK("http://x","y")` first).
- **Assertions:** run `select currency,sum(amount_minor+fee_minor) from billing_payment where status in ('completed','credited') and method not in ('wallet','code') and paid_on >= date_trunc('month', (now() at time zone 'Africa/Cairo')::date) group by 1` and compare to the API per currency. For every invoice: `paid_minor = coalesce(sum(amount_minor) filter (where status='completed'),0)` and `status` consistent. `select sum(i.amount_minor)-sum(coalesce(p.s,0))` (open balance) equals the sum of `balance_minor` over non-void invoices per currency.
- **Existing:** `test_summary.py`, `platform` csv tests. New: live reconciliation incl. 0 and 3 decimal currencies.
- **Cleanup:** none.

#### F09-TC-010: Standalone payment records (payment_receipts)
- **Role:** admin. **Switches:** invoices, payment_receipts. **Priority:** P1. **Provider:** REAL.
- **Steps:**
  1. `POST /billing/payments/` `{"customer_type":"student","student":5,"amount_minor":15000,"method":"cash","transaction_number":"TN-F09-1","paid_on":"<today>"}`.
  2. `{"customer_type":"unregistered","customer_name":"Walk In","customer_email":"walk@qa.etqan.test","amount_minor":8000,"currency":"USD","method":"western_union"}`.
  3. Refusals: unregistered with no name; unregistered with `student`; student type with no student; method `stripe`; same `method` + `transaction_number` as step 1; amount 0; future `paid_on`; email `not-an-email`.
  4. `PATCH /billing/payments/<R1>/ {"amount_minor":16000,"notes":"corrected"}`; PATCH a refunded record; PATCH an invoice payment (`P_a` from TC-008); PATCH a top-up (after TC-015).
  5. `POST /billing/payments/<R1>/refund/`, then PATCH it. `DELETE /billing/payments/<R2>/`.
  6. `dc.sh ... set_features qa --off payment_receipts`; `GET /billing/payments/` and `POST` (404), `DELETE /billing/payments/<id of an invoice payment>/` (still works, feature `invoices`); switch back on.
- **Expected:** 201 with `customer`, `editable=true`, `refundable=true`. Step 3 400 on the right fields; duplicate number 400 on `transaction_number`. Step 4: first 200; others 409 `billing.payment_not_editable`. Step 5 refund marks `refunded` and counts out of revenue. Step 6 404s as stated.
- **Assertions:** DB `select id,invoice_id,customer_type,student_id,customer_name,amount_minor,currency,method,transaction_number,status from billing_payment where invoice_id is null`; check constraint `billing_payment_has_customer` never violated; unique `(method, transaction_number)` where non-empty. Revenue includes the USD record under USD.
- **Existing:** `test_records.py`, `test_standalone.py`.
- **Cleanup:** none.

#### F09-TC-011: Local payment methods and what an invoice shows
- **Role:** admin; student. **Switches:** invoices. **Priority:** P2. **Provider:** REAL.
- **Steps:**
  1. `PUT /billing/local-countries/EG/ {"enabled":true}`; `PUT .../XX1/` (404); `PUT .../eg/`.
  2. `POST /billing/local-methods/` multipart `country=EG&name=Vodafone Cash&instructions=Send to 0100...&currency=EGP`; a second with `currency=USD`; one with an empty name.
  3. `GET /billing/invoices/INV1/` as student, then `PATCH /billing/settings/ {"local_payment_enabled":false}` and re-read; disable country EG; pay the invoice in full and re-read.
- **Expected:** methods list in the invoice detail only when the setting is on, the country (student `profile.country=EG`) is enabled, a balance is due and the method currency is blank or the invoice's. The USD method does not appear on an EGP invoice. Empty name 400.
- **Assertions:** `billing_localpaymentmethod`, `billing_localpaymentcountry`, `billing_billingsettings` rows; instructions are shown as plain text (post `<script>` in instructions, GET returns it as data, no HTML).
- **Existing:** `test_local_methods.py`, `test_local_methods_api.py`.
- **Cleanup:** delete the methods.

## C. Permissions, visibility, isolation

#### F09-TC-012: Permission matrix across roles (compressed), plus staff code granularity
- **Role:** admin, staff-nocode, staff-codes (QA Billing, then Narrow), supervisor, teacher, student, parent, anonymous. **Switches:** all F09 switches on. **Priority:** P1. **Provider:** REAL.
- **Steps:** with invoice `INV1`, payment `P_a`, wallet/voucher/link/checkout ids from later cases (run this case after TC-025), call each endpoint as each role and record the HTTP code. Endpoint families (one representative each, all methods noted):
  `GET/POST /billing/invoices/`, `GET/PATCH /billing/invoices/ID/`, `POST .../void/`, `GET/POST .../payments/`, `GET /billing/payments/`, `PATCH/DELETE /billing/payments/ID/`, `POST .../refund/`, `GET /billing/summary/`, `GET /billing/payers/?student=5`, `GET/PATCH /billing/settings/`, `GET/POST /billing/local-methods/`, `GET/PATCH /gateways/settings/`, `GET /gateways/checkouts/`, `POST /gateways/checkouts/ID/resolve/`, `GET/POST /gateways/links/`, `POST /wallet/students/5/top-ups/`, `POST .../adjustments/`, `POST /wallet/invoices/ID/pay/`, `POST /wallet/payments/ID/move/`, `GET /vouchers/batches/`, `POST /vouchers/batches/`, `POST /vouchers/codes/ID/void/`.
  Then with `staffc` holding **only** `QA Billing Narrow`: repeat the same set. Then restore QA Billing.
- **Expected matrix:**

  | Endpoint group | admin | staff-nocode | staff QA Billing | Narrow | supervisor | teacher | student | parent | anon |
  |---|---|---|---|---|---|---|---|---|---|
  | invoices list/detail (own scope) | 200 | 403 | 200 | 200 | 403 | 403 | 200 own | 200 own+children | 401 |
  | invoice create/edit/void | 2xx | 403 | 2xx | 403 | 403 | 403 | 403 | 403 | 401 |
  | add payment / refund / delete | 2xx | 403 | 2xx | 403 | 403 | 403 | 403 | 403 | 401 |
  | summary (`widget.revenue_stats`) | 200 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 401 |
  | gateway settings/checkouts list | 200 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 401 |
  | wallet top-up/adjust/move | 2xx | 403 | 2xx | 403 | 403 | 403 | 403 | 403 | 401 |
  | wallet `mine`, pay own invoice, codes `check/redeem` | admin 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 401 |
  | voucher batches/void/office redeem | 2xx | 403 | 2xx | 403 | 403 | 403 | 403 | 403 | 401 |

  Narrow staff: `GET invoices/ID` 200 but `POST payments` 403 and `GET /billing/payments/` 403. A missing second code is refused with the message naming it: office redeem of a discount without `payment.create`/`invoice.view`, remove-discount without `payment.update`, wallet move without `payment.update`, negative adjustment with only `wallet.create`.
- **Assertions:** table of observed codes saved to evidence; any 5xx or 200 outside the matrix is a defect. DB unchanged after every 403 (compare row counts to the snapshot).
- **Existing:** `billing/tests/test_staff_scope.py`, `wallet/tests/test_api.py`, `vouchers/tests/test_api.py`. New: single combined matrix on the live stack.
- **Cleanup:** restore `staffc` roles to `[QA Student View, QA Billing]`.

#### F09-TC-013: Invoice visibility for students, parents and other families
- **Role:** student (S1), parent (P1), parent2/student2, sibling payer P3, teacher. **Switches:** invoices, parents, families. **Priority:** P1. **Provider:** REAL.
- **Data:** `INV1` (S1, payer P1 or P3), `INV_S2` (S2, payer P2), `INV_P3` (S1, explicitly payer P3 via `"payer":P3`).
- **Steps:** each role: `GET /billing/invoices/`, `GET /billing/invoices/<each id>/`, `GET .../payments/`, `PATCH`, `POST void`, `POST payments`, `GET /billing/invoices/?format=csv`, `GET /billing/payments/<id>/`, `GET /billing/payers/?student=5`, `GET /billing/invoices/?student=<other id>`.
- **Expected:** student S1 sees only invoices where S1 is the student or the payer; parent P1 sees invoices P1 pays plus those of the children (S1); P3 (sibling/family payer) sees the invoices it pays and not S1's other invoices unless it is the payer; parent2/student2 get **404** (not 403, not data) for S1's invoices and an empty list; teacher 403; every write 403. CSV for family 403. The family payload has no `notes`, `created_by`, `recorded_by`, `payments[].notes`. List filters (`student`, `payer`, `q`) never widen the scope.
- **Assertions:** compare `id` sets in the list with `select id from billing_invoice where student_id=... or payer_id=...`; grep the JSON for `notes`/`created_by`. Total counts `count` in pagination equals the scoped count.
- **Existing:** `test_family_payer.py`, `test_staff_scope.py`, `test_api.py`.
- **Cleanup:** none.

#### F09-TC-014: Cross-academy isolation (qa versus qaother)
- **Role:** qaother admin, qa admin, anonymous. **Switches:** the same switches on qaother (`set_features qaother --on invoices payment_receipts online_payments payment_links balances system_codes`). **Priority:** P1. **Provider:** REAL / SIMULATED for the webhook row.
- **Data:** in qaother create a student, an invoice `OI` (USD, 5000), a wallet top-up, a voucher batch and a stripe-enabled checkout (same Setup 7 with secret `whsec_qaother_f09`).
- **Steps:**
  1. As qa admin call every id-based route with qaother's ids: `GET/PATCH /billing/invoices/OI/`, `POST .../OI/payments/`, `POST .../OI/void/`, `GET /billing/payments/<qaother payment>/`, `POST /billing/payments/<id>/refund/`, `GET /wallet/students/<qaother student user id>/`, `POST /wallet/invoices/OI/pay/`, `POST /vouchers/codes/<id>/void/`, `GET /gateways/checkouts/<uuid>/`, `POST /gateways/simulate/<uuid>/`, `GET /gateways/links/<id>/`. And the reverse with qaother admin on qa ids (INV1, P_a, a qa checkout uuid, a qa wallet).
  2. Redeem a qa voucher code text on qaother (`POST /vouchers/codes/redeem/` as qaother admin, and as a qaother student via `/vouchers/redeem/`).
  3. Webhook: build an event for a **qa** checkout uuid and POST it signed with qa's secret to `http://qaother.etqan.localhost/api/v1/gateways/webhooks/stripe/`, and to `http://qa...` with qaother's secret.
  4. Session reuse: a qa admin session cookie sent to `http://qaother.etqan.localhost/api/v1/billing/invoices/`.
  5. Totals: `GET /billing/summary/` on each; confirm no cross-sum.
- **Expected:** every foreign id is 404 (never 200/403 with data); step 2 answers the generic "invalid code"; step 3 both 400 (bad signature) or 200 with no effect, never completing the other academy's checkout; step 4 401. Summaries independent.
- **Assertions:** `select count(*) from academy_qaother.billing_payment` and `academy_qa.billing_payment` unchanged by cross calls; `academy_qa.gateways_checkout` rows not altered (`updated_at`/`status` same); `academy_qa.gateways_webhookevent` has no row from the cross call.
- **Existing:** `test_webhooks.py` ("another academy's checkout"), platform tenancy tests. New: live black-box sweep.
- **Cleanup:** leave qaother data.

## D. Wallet

#### F09-TC-015: Manual wallet top-up, ledger invariants and MAX_TOPUP_MINOR
- **Role:** admin (and QA Billing staff). **Switches:** balances, invoices, payment_receipts. **Priority:** P1. **Provider:** REAL.
- **Steps:** `POST /wallet/students/5/top-ups/`:
  1. `{"amount_minor":50000,"currency":"EGP","method":"cash","reference":"T1"}`; `{"amount_minor":2500,"currency":"USD","method":"zelle"}`.
  2. `{"amount_minor":100000000,...}` (exactly MAX); `{"amount_minor":100000001,...}`; `0`; `-1`; `1.5`; `true`; `"5"`.
  3. `method` `stripe`, `wallet`, `code`; `currency` `"E"`, `123`; `paid_on` tomorrow.
  4. `GET /wallet/students/5/`, `GET /wallet/students/5/entries/?currency=EGP`, `GET /wallet/students/999999/`.
  5. As student `GET /wallet/mine/`; as parent2 `GET /wallet/students/5/` (404).
- **Expected:** step 1 201 entries `kind=topup`; balances EGP 50000 (+ MAX), USD 2500 in separate rows; step 2: MAX accepted, MAX+1 400 on `amount_minor`; zero/neg/float/bool/string 400; step 3 400 on `method`/`currency`/`paid_on`; unknown student 404.
- **Assertions:** DB `select w.currency,w.balance_minor,(select coalesce(sum(amount_minor),0) from wallet_walletentry e where e.wallet_id=w.id) from wallet_wallet w` : balance equals entry sum for every wallet; `balance_after_minor` chain is monotonic and equals running sum; each top-up has a `billing_payment` with `wallet_topup=true`, `invoice_id is null`, `customer_type='student'`, same amount/currency; revenue summary includes it.
- **Existing:** `wallet/tests/test_ledger.py`, `test_models.py`, `test_api.py` (MAX covered); new: live DB invariants, reconciliation with revenue.
- **Cleanup:** none (balances used later; note them).

#### F09-TC-016: Wallet adjustments (correction, not money)
- **Role:** admin; staff with only `wallet.create`; staff with only `wallet.update`. **Switches:** balances. **Priority:** P1. **Provider:** REAL.
- **Steps:** `POST /wallet/students/5/adjustments/`:
  1. `{"amount_minor":-1000,"currency":"EGP","reason":"fix"}`; `{"amount_minor":500,"currency":"EGP","reason":"gift"}`.
  2. Negative bigger than the balance; `0`; reason empty / blank spaces / 501 chars; amount `±100000001`; negative in a currency the student has no wallet in.
  3. As the two limited staff roles: positive with `wallet.update` only; negative with `wallet.create` only (role swap on qa-staff-codes).
- **Expected:** 201 `kind=adjustment`; over-draw 409 `wallet.insufficient_balance` and balance unchanged; 0/empty reason/oversize 400; no-wallet negative 409 (no empty wallet created); positive needs `wallet.create`, negative `wallet.update` (403 naming the code otherwise).
- **Assertions:** adjustment entries have `payment_id is null`; no `billing_payment` row added; revenue unchanged; `balance_minor >= 0` always; `select count(*) from wallet_wallet where student_id=<S1 profile> and currency='JPY'` is 0 after the failed negative.
- **Existing:** `test_ledger.py`, `test_api.py`.
- **Cleanup:** none.

#### F09-TC-017: Pay an invoice from the wallet (family and office), including races
- **Role:** student, parent P1, sibling payer P3, admin. **Switches:** balances, invoices. **Priority:** P1. **Provider:** REAL.
- **Data:** S1 EGP wallet 50000 (+ whatever TC-015/016 left; reset by noting the starting balance). Invoices `W1` 30000, `W2` 80000, `W3` USD 4000, one void, one paid.
- **Steps:**
  1. As parent: `POST /wallet/invoices/W1/pay/ {}` (default amount `min(balance, invoice balance)`).
  2. As student: `POST /wallet/invoices/W2/pay/ {"amount_minor":10000}`; `{"amount_minor":9999999999}`; `{"amount_minor":0}`; `{"amount_minor":1.5}`.
  3. `POST /wallet/invoices/W3/pay/ {}` (USD invoice, no USD wallet unless TC-015's 2500 exists: test both).
  4. Void invoice, paid invoice, S2's invoice as parent P1/student (404).
  5. As P3 (paying sibling who sees the invoice but is not S1's guardian): pay `INV_P3`.
  6. Parallel: two requests each spending the full remaining balance on two different open invoices; and two requests paying the same invoice.
  7. Admin pays W2 from S1's wallet with `wallet.update`.
- **Expected:** 1: payment `method=wallet`, `fee_minor=0`, invoice `paid`, entry `spend` negative; default amount never above the invoice balance. 2: partial amount sets `partial`; over-balance 409 `wallet.insufficient_balance` or 400 `amount_minor` for more than the invoice balance, zero/float 400. 3: with no USD funds 409; with USD 2500 it spends 2500 only and leaves `partial`. 4: 409 `billing.invoice_void` / `wallet.nothing_due`; other family 404. 5: 404 (sibling sees invoices, never the wallet). 6: balance never negative; at most the available funds are spent; same-invoice race pays at most the invoice balance.
- **Assertions:** DB `select kind,amount_minor,balance_after_minor,payment_id,invoice_id from wallet_walletentry order by id`; the `spend` `payment_id` rows exist in `billing_payment` with `method='wallet'`; `wallet_wallet.balance_minor = sum(entries)`; revenue summary does **not** include wallet payments (compare before/after the spends).
- **Existing:** `wallet/tests/test_spending.py`, `billing/tests/test_wallet_payments.py`. New: concurrent API race and the sibling case.
- **Cleanup:** none.

#### F09-TC-018: Move a payment into the wallet, reverse a top-up, and the refusals
- **Role:** admin; QA Billing staff lacking `payment.update` for the permission row. **Switches:** balances, invoices. **Priority:** P1. **Provider:** REAL.
- **Data:** invoice `M` 20000 paid by cash `PM` and by wallet `PW`; a top-up `PT` (from TC-015); an invoice `MC` paid by code (TC-020); a stripe payment `PS` (TC-022).
- **Steps:**
  1. `POST /wallet/payments/PM/move/`; again; `POST .../PM/refund/`; `DELETE /billing/payments/PM/`.
  2. `POST /wallet/payments/PW/move/` (undo a spend); `.../MC code payment/move/` (409); `.../PS/move/` (online payment: allowed, fee stays revenue).
  3. `POST /wallet/payments/PT/reverse/` with balance >= amount, again, and after spending the balance below the amount; `reverse` on an invoice payment.
  4. `POST /billing/payments/PT/refund/`, `DELETE /billing/payments/PT/`, `PATCH /billing/payments/PT/`, `refund PW`, `delete PW`.
  5. Void invoice `M` once its payments are moved.
- **Expected:** 1: payment `credited`, invoice drops back to `unpaid`/`partial`, entry `kind=refund` +amount; second move 409 `billing.payment_not_completed`; refund/delete of a credited payment 409 `billing.payment_credited`. 2: moving the wallet payment credits the wallet back; code payment 409 `billing.code_payment`; stripe: wallet credited by `amount_minor` only, fee stays in revenue. 3: reverse marks the top-up `refunded`, entry `reversal` negative; second 409 `billing.already_refunded` (or insufficient first if the balance is short); short balance 409 `wallet.insufficient_balance`; invoice payment 409 `wallet.not_topup`. 4: billing refuses wallet money: 409 `billing.wallet_topup` / `billing.wallet_payment`. 5: void works because no completed payment remains.
- **Assertions:** DB: `credited` rows still in revenue (`status in (completed,credited)`) but not in `paid_of`; `select status from billing_payment where id in (...)`; `wallet_walletentry` has unique `(kind,payment_id)`; balances equal the entry sum; revenue for the month changes by exactly `-(amount+fee)` for a reversed top-up and by `0` for a move (except none for the fee).
- **Existing:** `wallet/tests/test_ledger.py`, `billing/tests/test_wallet_columns.py`, `test_refunds.py`.
- **Cleanup:** none.

## E. Vouchers (system codes)

#### F09-TC-019: Generate batches, void codes, family brute-force throttle
- **Role:** admin; student. **Switches:** system_codes. **Priority:** P2. **Provider:** REAL.
- **Steps:**
  1. `POST /vouchers/batches/` `{"kind":"discount","quantity":3,"valid_days":30,"discount_kind":"percent","discount_value":15}` (-> `DPCT`); `{"kind":"discount","quantity":2,"valid_days":1,"discount_kind":"fixed","discount_value":20000,"currency":"EGP"}` (-> `DFIX`); `{"kind":"activation","quantity":2,"valid_days":30,"course":COURSE,"package":PKG,"teacher":7}`; `{"kind":"renewal","quantity":1,"valid_days":30,"course":COURSE,"package":PKG}`.
  2. Refusals: `quantity` 0 and 501; `valid_days` 0 and 3651; percent 0 and 101 and 12.5; fixed without currency, fixed 100000001, percent with a currency; activation missing teacher; renewal with a teacher; teacher not on the course; unknown kind.
  3. `GET /vouchers/codes/?kind=discount&state=unused`, `?format=csv`, `?code=SYS-...`.
  4. `POST /vouchers/codes/ID/void/ {"reason":"qa"}`; again; void a used code (after TC-020).
  5. Throttle: as student, `POST /vouchers/check/ {"code":"SYS-AAAAA-AAAAA"}` 21 times in a row, and 61 from another user within the hour.
- **Expected:** 201 batches, codes formatted `SYS-XXXXX-XXXXX` from Crockford base 32 (no I, L, O, U), `expires_on = today + valid_days - 1`; quantity/valid_days/percent limits as in `vouchers.md`; refusals 400, never 500. Void: unused -> `void`; second void and void of a used code 409. The 21st failing attempt returns 429 (user throttle 20/hour), unknown and void codes answer identically.
- **Assertions:** DB `select code,status,kind from vouchers_voucher`: all codes unique, 10 chars, alphabet check `code ~ '^[0-9A-HJKMNP-TV-Z]{10}$'`; count equals quantity; `vouchers_voucherbatch.expires_on`. After the throttle run clear the cache (Setup 9).
- **Existing:** `test_generation.py`, `test_models.py`, `test_preview.py`.
- **Cleanup:** cache clear.

#### F09-TC-020: Discount codes: rounding, caps, single use, expiry, one per invoice, removal
- **Role:** parent P1 (family), student, admin (office redeem), sibling payer P3. **Switches:** system_codes, invoices. **Priority:** P1. **Provider:** REAL.
- **Data:** invoices `D1` 10050 EGP, `D2` 100 EGP, `D3` 50000 EGP with 45000 already paid, `D4` USD 5000, `D5` for S2; codes from `DPCT` (15%) and `DFIX` (200.00 EGP).
- **Steps:**
  1. Parent: `POST /vouchers/check/ {"code":"<pct code>"}`; `POST /vouchers/redeem/ {"code":"<pct code>","invoice":D1}`.
  2. `POST /vouchers/redeem/` with the same code again; with spaces, lower case and `sys-` prefix variants (`" sys-xxxxx xxxxx "`).
  3. A second code on `D1`; the 15% code on `D2` (1.5 -> 2? compute 100*15/100=15 minor, check min 1 with a 1% code on `D2` amount 50).
  4. `DFIX` code on `D3` (balance 5000 < 20000 so capped); on `D4` (USD) ; on `D5` as parent P1 and as student (not their invoice); as P3.
  5. An expired code: update `vouchers_voucherbatch.expires_on` to yesterday via SQL for one batch (QA data edit), then redeem and check state `expired` in the list; redeem on the last valid day (`expires_on = today`).
  6. Admin (`QA Billing`): `POST /vouchers/codes/ID/redeem/ {"invoice":D1}` and `POST /vouchers/codes/redeem/ {"code":"...","invoice":...}`.
  7. `POST /vouchers/codes/ID/remove-discount/ {"reason":"mistake"}`; again; on an unused code; `POST /billing/payments/<code payment>/refund/` and `DELETE`.
- **Expected:** 1: percent of the **invoice amount**, half up: 10050 x 15% = 1507.5 -> `1508`; payment `method=code`, `fee_minor=0`, `reference` = display code, invoice `partial` (balance 8542); code `used` with `invoice_id`, `payment_id`, `student`. A 1% code on 50 minor gives min `1`. 2: second redeem 409 used; normalised variants hit the same code. 3: second discount on the same invoice refused (`invoice_discounted`) and rolled back (code stays unused, payment not created). 4: fixed capped at the balance (5000), invoice `paid`; USD invoice with an EGP fixed code refused (wrong currency); another family 404. 5: expired refused with the expired message, the last day redeems. 6: office redeem works with `voucher.update`+`payment.create`+`invoice.view`. 7: removal deletes the code payment, invoice returns to its previous status, code `void` with `void_reason`, second removal 409, unused code 409; billing refund/delete of a code payment 409 `billing.code_payment`.
- **Assertions:** DB `vouchers_voucher` (status, invoice_id, payment_id, redeemed_by_id) and `billing_payment` method `code`; revenue unchanged after redeem and after removal (codes excluded); for a fully discounted invoice, `paid` and `select * from notifications...` shows no new-invoice notice for it (`billing.md` Background jobs; assert by running `notifications.scan` once and checking mailpit `http://localhost:8025/api/v1/messages`).
- **Existing:** `vouchers/tests/test_discount.py` (percent rounding param), `billing/tests/test_code_payments.py`. New: end-to-end with real family scoping.
- **Cleanup:** none.

#### F09-TC-021: Activation and renewal codes, family scope, and the single-use race [UI smoke 2]
- **Role:** student, parent, admin. **Switches:** system_codes, invoices. **Priority:** P1. **Provider:** REAL.
- **Data:** activation codes `ACT1`, `ACT2`, renewal code `REN1` (course = COURSE), a subscription `SUBR` of S1 on COURSE, another course's subscription.
- **Steps:**
  1. Parent: `POST /vouchers/check/ {"code":"ACT1"}`; `POST /vouchers/redeem/ {"code":"ACT1","student":5}`.
  2. Student redeems `ACT2` for himself; for another student (S2) -> refused; parent P2 for S1 -> refused; sibling payer P3 -> refused.
  3. `REN1` on SUBR; on the other course's subscription; without a `subscription`.
  4. Same code from two sessions at once: `for u in parent student; do (api $u POST /vouchers/redeem/ '{"code":"ACT2","student":5}' &); done; wait`.
  5. With `invoices` off: redeem an activation code, then `--on invoices`. Price 0 package.
  6. UI smoke: Playwright signs in as the parent, opens Learning > Codes (`/app/learning/codes`), enters a discount code, sees the success state, and the invoice page shows the code payment.
- **Expected:** 1/2: subscription created for the batch course/package/teacher, starting today, and its invoice issued **whatever `auto_invoice_on_subscription` says** and paid in full by one `code` payment (invoice `paid`, `amount_minor = price`); foreign students 404. 3: renewal creates the renewed subscription and a paid invoice; wrong course 400/409 wrong-course message. 4: exactly one 201 and one used/invalid error, one subscription only. 5: with invoices off, no invoice or payment, the code is only marked used; a zero price makes no invoice.
- **Assertions:** DB: one `scheduling_subscription` per redeemed code, `vouchers_voucher.subscription_id` set; `select count(*) from billing_payment where method='code'` equals the number of paid invoice redemptions; no duplicate invoice per subscription; revenue excludes them.
- **Existing:** `vouchers/tests/test_redeem.py` ("stale copy never redeems twice"), e2e `b3-codes.spec.ts`.
- **Cleanup:** none.

## F. Online payments (SIMULATED)

#### F09-TC-022: Invoice online payment end to end with the simulator, service fee and rounding [UI smoke 3]
- **Role:** parent P1 (payer), admin. **Switches:** invoices, online_payments. **Priority:** P1. **Provider:** SIMULATED (Stripe test mode keys, `GATEWAYS_SIMULATE`).
- **Data:** invoices `O1` 50000 EGP, `O2` 10050 EGP, `O3` 1 minor EGP (smallest), Stripe account enabled, fee 500 bp.
- **Steps:**
  1. Parent `GET /billing/invoices/O1/` -> `can_pay_online`.
  2. `POST /gateways/checkouts/start/ {"purpose":"invoice","reference_id":O1,"provider":"stripe"}`; start again (reuse); start for `O2`.
  3. `GET /gateways/checkouts/<uuid>/`; `POST /gateways/simulate/<uuid>/ {"outcome":"pay"}`; again; `{"outcome":"fail"}` after paid.
  4. `GET /billing/invoices/O1/`, `GET /gateways/checkouts/` (admin), `GET /billing/payments/?method=stripe`.
  5. Set fee `{"fee":{"enabled":false}}` and `{"fee":{"basis_points":2000}}` and `0`, start a checkout on `O2` each time; restore 500.
  6. Refusals: another family's invoice, void/paid invoice, `provider:"paypal"` (EGP not offered), `purpose:"nope"`, `reference_id:0`, a staff user without `invoice.view`, an impersonation (quick-login) session if available.
  7. UI smoke: Playwright as parent opens the invoice, clicks Pay online, lands on `/pay/simulate/<id>`, presses Pay, return page shows paid, invoice page shows paid.
- **Expected:** step 2 201 `{id, redirect_url, amount_minor:50000, fee_minor:2500, currency:EGP}`; second start returns the **same** checkout id (reuse within 23 h, same price/creator). `O2` fee = `(10050*500+5000)//10000 = 503`. Step 3 status `completed`, a second pay is a no-op, a fail after pay changes nothing. Invoice `paid` for the **invoice amount only** (fee is extra), payment `method=stripe`, `amount_minor=50000`, `fee_minor=2500`, `transaction_number=pi_sim_...`, `recorded_by_id` null, `paid_on` academy today. Fee switch off -> fee 0; 2000 bp -> 2010 on `O2`; 0 bp -> 0. Step 6: 404/409/400 as scoped, never 500.
- **Assertions:** DB `select id,purpose,reference_id,provider,simulated,amount_minor,fee_minor,status,applied,attention,transaction_number from gateways_checkout`; `applied=true`, `attention=''`; `billing_payment.transaction_number = gateways_checkout.transaction_number`; `checkout.amount_minor + fee_minor = amount_total` signed by the simulator; revenue summary includes `amount+fee` (52500). Fee never rounds below `round_half_up(amount*bp/10000)`.
- **Existing:** `gateways/tests/test_fees.py`, `test_checkouts.py`, `test_simulate.py`, `billing/tests/test_online.py`, e2e `b3-online-payments.spec.ts`.
- **Cleanup:** fee back to 500 bp, enabled.

#### F09-TC-023: Webhook verification and duplicate delivery idempotency
- **Role:** anonymous (Stripe), admin to read results. **Switches:** online_payments (and off for step 6). **Priority:** P1. **Provider:** SIMULATED (hand-signed Stripe events with the QA signing secret).
- **Data:** pending checkouts `C1..C6` for six fresh 50000 EGP invoices (start as parent, do NOT use the simulate button).
- **Steps** (use `mkevt` then `whsend`):
  1. C1: `mkevt e1.json evt_f09_1 checkout.session.completed C1 52500 egp pi_f09_1`; `whsend e1.json` twice (same event id, duplicate delivery).
  2. C1 again with a **different** event id and type `checkout.session.async_payment_succeeded`.
  3. C2: amount_total `52499` (mismatch); C3: currency `usd`; C4: `livemode=true`; C5: unknown checkout uuid; C6: a body edited after signing; a signature older than 5 minutes (`ts=$(( $(date +%s) - 400 ))`); wrong secret; missing header.
  4. Resolve the attention: `POST /gateways/checkouts/C2/resolve/` twice, and on C1.
  5. Same `pi_f09_1` payment_intent used for a different checkout C7.
  6. `set_features qa --off online_payments`, deliver a valid paid event for C7, switch back on.
  7. `GET /gateways/checkouts/?attention=open`.
- **Expected:** 1: first 200 and one `stripe` payment of 50000 with fee 2500; second delivery 200 and **no** second payment, no change. 2: 200, still one payment (completion happens once). 3: C2/C3/C4 complete with `applied=false` and `attention` `amount_mismatch`/`currency_mismatch`/`mode_mismatch`, **no** payment and the invoice unchanged; C5 200 with no effect; tampered/old/wrong secret/missing header 400 "Bad signature" and no webhook row. 4: resolve sets `resolved_at/by`, second resolve 409 `gateways.nothing_to_resolve`, C1 409. 5: C7 payment refused as `already_recorded` (unique `(method, transaction_number)`), attention shown, no second payment. 6: webhooks keep working with the feature off (payment recorded). 7: lists C2..C5-style rows needing attention only.
- **Assertions:** DB `select event_id,type,checkout_id from gateways_webhookevent` has exactly one row per distinct event id (`evt_f09_1` once); `select count(*) from billing_payment where transaction_number='pi_f09_1'` is 1; `select status,applied,attention from gateways_checkout` for C1..C7; invoices of C2..C5 unchanged and unpaid; no 5xx in the django log.
- **Existing:** `gateways/tests/test_webhooks.py` (replay, bad/stale signature), `test_checkouts.py`. New: the combined live sequence including the second event id and feature-off delivery.
- **Cleanup:** none.

#### F09-TC-024: Money arriving late or twice: stale checkout, voided invoice, two payers, online refund
- **Role:** parent P1, parent P3 (second payer), admin. **Switches:** invoices, online_payments. **Priority:** P1. **Provider:** SIMULATED.
- **Data:** invoice `X1` 50000.
- **Steps:**
  1. Parent starts a checkout `K1` on `X1` (balance 50000). Admin records a manual 20000 payment. Simulate `pay` on `K1`.
  2. Fresh invoice `X2`: start `K2`, admin voids `X2`, simulate `pay`.
  3. Fresh invoice `X3` 50000: P1 starts `K3`, P3 starts `K4` (different creators); simulate `pay` on both.
  4. Fresh invoice `X4`: start `K5`, admin **raises** the amount to 80000 (still unpaid), simulate `pay`; then reduce another invoice `X5` to 30000 after `K6` started (70000? use 50000 -> 30000), simulate `pay`.
  5. `simulate outcome=fail` and `expire` on new checkouts, then `pay` on the failed one.
  6. Online refund: `POST /billing/payments/<stripe payment>/refund/`, `DELETE` the same payment, `POST /wallet/...` n/a; re-pay the invoice online; read `gateways_checkout` of the refunded one.
  7. `POST /gateways/checkouts/<K>/cancel/` (PayPal-only route) on a stripe checkout.
- **Expected:** 1: the old checkout completes with `applied=false`, `attention=balance_below_amount`; **no** payment, invoice stays `partial` 20000; the money is held with the provider until someone refunds it by hand (document as the known limitation). 2: `attention=invoice_void`, no payment. 3: first pay applied, second `applied=false` `balance_below_amount`/already paid, invoice paid exactly once (no overpay). 4: raised amount -> payment of the old amount recorded as a partial (invoice `partial`); reduced amount -> `balance_below_amount` attention. 5: `fail` -> `failed`; `expire` -> `expired`; a later `pay` on a failed checkout completes (documented "completes from any state but completed"). 6: refund marks `refunded` only (no provider call: assert with `docker logs` that nothing left the box), invoice reopens, delete of an online payment 409 `billing.online_payment`, re-paying works, the original checkout stays `completed/applied`. 7: 409/400 or no-op for a non-PayPal checkout (record the answer, never 500).
- **Assertions:** DB `gateways_checkout` (status, applied, attention) per K; `billing_payment` count per invoice; for each invoice `sum(completed)` <= `amount_minor`; list unresolved attention rows `select id,attention from gateways_checkout where attention<>'' and resolved_at is null` and report as money-in-limbo rows (see S3).
- **Existing:** `billing/tests/test_online.py` (void, low balance), `gateways/tests/test_checkouts.py`. New: live sequences and amount edits.
- **Cleanup:** resolve the attention rows (`POST .../resolve/`).

#### F09-TC-025: Payment links, public pay page and single use
- **Role:** admin / QA Billing staff, anonymous payer. **Switches:** invoices, online_payments, payment_links, payment_receipts. **Priority:** P1. **Provider:** SIMULATED.
- **Steps:**
  1. `POST /gateways/links/ {"kind":"payment","title":"Registration fee","student":5,"provider":"stripe","amount_minor":25000,"add_fee":true}` (-> `L1`); one for an unregistered payer `{"payer_name":"Walk In","payer_email":"w@qa.etqan.test","payer_phone":"01000000000",...,"amount_minor":10050,"add_fee":false}` (-> `L2`); `"kind":"donation"` with `donations` off.
  2. Refusals: `student` and `payer_name` together; neither; amount 0; bad email; provider `paypal` on an EGP link; inactive student.
  3. Anonymous: `GET /gateways/pay/<token>/` (L1), a wrong token, a 33-char token, a token with `%00`; 70 requests in a minute (throttle `payment_link` 60/min).
  4. Anonymous `POST /gateways/pay/<token>/checkout/ {}`; then anyone `POST /gateways/simulate/<id>/ {"outcome":"pay"}`; again start a checkout for the now-paid link; the same link in a second browser.
  5. Cancel `L2` as admin, start a checkout earlier, then pay it after the cancel.
  6. `GET /billing/payments/?has_invoice=false`, `GET /gateways/links/`.
- **Expected:** link tokens are 32-char url-safe, not sequential; public page shows the academy name, title, amount, fee and the student's **first name only**, no email/phone/internal ids. L1 fee 1250, L2 fee 0. After the paid event a **standalone** payment appears (customer = student or the typed name, `fee_minor`, `method=stripe`, `invoice_id` null), link `paid`; a second payment attempt gets 409 `gateways.link_closed`. A payment arriving on a cancelled link completes with `applied=false` `attention=link_closed`. Donation links 400 (off) and the public page 404.
- **Assertions:** DB `gateways_paymentlink` (status, checkout_id, paid_at) and `billing_payment` where `invoice_id is null`; `unique(method, transaction_number)`; revenue includes the link money with its fee; no PII (email/phone) in the public JSON (`curl ... | grep -c w@qa`).
- **Existing:** `gateways/tests/test_links.py`, `test_pay_links.py`, `billing/tests/test_records.py`, e2e `b3-payment-links.spec.ts`.
- **Cleanup:** cancel any open links.

#### F09-TC-026: Online wallet top-up, duplicates and mismatches
- **Role:** parent P1, student, parent2. **Switches:** balances, online_payments, invoices. **Priority:** P1. **Provider:** SIMULATED.
- **Steps:**
  1. `GET /wallet/top-ups/options/?student=5&currency=EGP&amount_minor=10000`.
  2. `POST /wallet/top-ups/ {"student":5,"amount_minor":10000,"currency":"EGP","provider":"stripe"}`; repeat (reuse); `simulate pay`.
  3. Hand-signed duplicate delivery of the same event twice (TC-023 helper) after the simulate.
  4. Refusals: `amount_minor` 0, 100000001, 1.5; currency not offered (`JPY`); student P1 has no right to (`S2`); provider `paypal`; student session in quick-login; `provider` unknown.
  5. `set_features qa --off balances`, simulate a paid top-up checkout started earlier, switch on.
  6. Reconcile.
- **Expected:** options list currencies (academy first) and providers; checkout `amount_minor=10000`, `fee_minor=500`; after pay: `TopUp.status=paid`, a `wallet_topup` payment `amount_minor=10000` `fee_minor=500` method stripe, wallet entry `topup` for **10000** (the fee is not credited), balance +10000. Duplicate delivery changes nothing. Refusals 400/404. Step 5: money received while `balances` is off is still credited (documented), no loss.
- **Assertions:** DB `wallet_topup`, `billing_payment where wallet_topup`, `wallet_walletentry`, `gateways_checkout`: one payment per paid checkout; `balance = sum(entries)`; revenue includes `10500`. Reverse the top-up via TC-018 to confirm the fee leaves revenue with it.
- **Existing:** `wallet/tests/test_online_topup.py`, e2e `b3-wallet.spec.ts`.
- **Cleanup:** none.

#### F09-TC-027: PayPal (simulated) and unsupported-currency routing
- **Role:** parent, admin. **Switches:** invoices, online_payments. **Priority:** P2. **Provider:** SIMULATED (PayPal is never called; live PayPal is BLOCKED).
- **Data:** PayPal account saved per Setup 7 with currency USD; the USD invoice from TC-001 (4950 left) and an EGP invoice.
- **Steps:** `GET /billing/invoices/<usd invoice>/` (`can_pay_online`); `POST /gateways/checkouts/start/` provider `paypal` for the USD invoice and for the EGP invoice; `simulate pay`; `simulate fail`; `expire`; a 3-decimal (KWD) invoice with 12345 minor on stripe (fee rounds so the total is a multiple of 10).
- **Expected:** PayPal offered only for USD; EGP -> 400 on `provider`; USD pay -> `paypal` payment `transaction_number=CAP-SIM-...`, invoice paid; `can_pay_online` lists `stripe`,`paypal` where each takes the currency; KWD total `amount+fee` is a multiple of 10 or the provider is not offered.
- **Assertions:** DB `gateways_checkout.provider`, `billing_payment.method='paypal'`; fee arithmetic in minor units; no 5xx.
- **Existing:** `gateways/tests/test_paypal_orders.py`, `test_capture.py`, `test_fees.py`, e2e `b3-paypal.spec.ts`.
- **Cleanup:** disable the PayPal account.

---

## Suspected defects from code reading (for Agent 2 to confirm or dismiss)

- **S1 (P3 docs/behaviour gap):** `billing.md` says an invoice is voided "only when the invoice has no payments", but `rules.refuse_if_paid_into` counts only `completed` payments. An invoice whose only payments are `refunded` or `credited` can be voided. Probably intended; confirm and align docs (TC-007 E4).
- **S2 (P2, money):** a paid online checkout that cannot be applied (invoice voided or balance reduced/raised, two payers, `already_recorded`) keeps the customer's money at the provider with only an `attention` flag; there is no automatic refund and billing "refund" never calls the provider. Confirm the attention surfaces on the dashboard and in the checkouts list (TC-024). Likely a documented limitation, report as coverage gap if no UI path exists.
- **S3 (P2, money):** the stale-checkout guard is only at start. Editing an invoice's amount downward or recording a manual payment after a checkout started lets the family pay the old price; `balance_below_amount` rejects it, so a parent can be charged and the invoice stays unpaid (TC-024 steps 1, 4).
- **S4 (P2):** `refund_payment` on a `stripe`/`paypal` payment only flips local status. The invoice reopens and the family can pay again while the original charge was never returned. Confirm the UI labels it "marked refunded".
- **S5 (P3):** currency codes are only regex-checked (`^[A-Z]{3}$`, `clean_currency`), not against ISO 4217. `ZZZ` invoices, wallets and top-ups are accepted (TC-002, TC-015). Minor-digits default to 2 for unknown codes.
- **S6 (P3):** `fee_for` returns `None` for a three-decimal currency when the fee is 0 and the total is not a multiple of 10 (fee switch off or link `add_fee=false`), so the provider silently disappears from `can_pay_online`. Check the KWD invoice with the fee switch off (TC-027).
- **S7 (P3, reporting):** revenue is bucketed by `paid_on` and refunded payments are excluded entirely, so a refund next month rewrites the previous month's revenue. Confirm finance expects this (TC-009).
- **S8 (P3):** `reverse_topup` checks the balance before the payment's status, so an already-reversed top-up answers `wallet.insufficient_balance` instead of `billing.already_refunded` when the balance is low (TC-018).
- **S9 (P2, security-lite):** `POST /gateways/simulate/<uuid>/` for the public purposes (`payment_link`, `donation_link`) works for anyone holding the checkout uuid when `GATEWAYS_SIMULATE` is on; the system check `gateways.E001` refuses the flag without `DEBUG`. Verify the check still blocks production settings (`gateways/tests/test_checks.py`) and that qa is not reachable publicly with the flag on.
- **S10 (P3):** the family-visible invoice detail includes `payments[].reference`, which for `code` payments is the voucher display code. The code is already used, so low risk; confirm no unused code can ever appear there.
- **S11 (P2, check):** a cancelled/failed/expired checkout still completes when a later paid event arrives (`webhooks._apply` only skips `completed`). Intended ("money received is never dropped"), but combined with S2 the invoice can be paid by a checkout the family believed cancelled; confirm the invoice is not overpaid (TC-024 step 3).
- **S12 (P3):** `PayInput` for `wallet/invoices/<id>/pay/` allows an amount up to 2^63-1 while only the balance bounds it. Expect 400/409, not 500, for huge values (TC-017 step 2).

## Coverage notes (also appended to coverage-gaps.md)

Live Stripe/PayPal, real provider refunds, Connect fees, the 03:20 `expire_checkouts` task timing, the one-minute `notifications.scan` overdue notices, and 300-student performance are not exercised; see `coverage-gaps.md` `### F09`.

---

## Results (Agent 2, 2026-10-19, backend adff9c9 / dashboard 5ed775d, LEAN)

Evidence paths are relative to `qa/evidence/F09/`. Setup ran as written (`setup.txt`), with two corrections: new users needed
their `account_emailaddress.verified` set (login answered "Email address is not verified."), and the existing family 1 was
re-pointed to {S1, S3} with payer P3 (S2=32, S3=33, P2=34, P3=35; course 2, package 2, roles QA Billing 20 / Narrow 21).

| Case | Result | Tag | Evidence | Notes |
|---|---|---|---|---|
| TC-001 | PASS | REAL (+UI) | tc001.txt, pw/tc001-*.png, pw-run2.txt, pw-db.txt | INV-000007..9 gap free, payer = `payers.default` (P3), issued_on = Cairo date. `q` searches number/student/payer name, not description (spec corrected). Print URL is `/app/invoices/<id>/print`. |
| TC-002 | PASS | REAL | tc002.txt | All refusals 400 on the field, no 500; 2^63 → 400. Counter +3 for 3 × 201. `"100"` (numeric string) is accepted as 100 (DRF coercion, exact integer; spec corrected). `ZZZ` accepted = existing ETQAN-QA-022. |
| TC-003 | PASS | REAL | tc003.txt | One invoice per invoiced subscription (150000 EGP, due +7, Arabic description, payer P3). Price-override in another currency is refused `catalogue.price_currency_changed` (spec corrected: override stays in the package currency); 99950 EGP override invoiced. SUB0/SUB3/SUB4 no invoice. |
| TC-004 | PASS | REAL | tc004.txt | Price edit leaves invoice at 150000 (known note); renew invoices 120000; delete 409 `billing.subscription_invoiced`, after void 409 `scheduling.already_renewed`. Cancel leaves the invoice open (observation, not filed). |
| TC-005 | PASS | REAL | tc005.txt | partial 20000/30000 → 49999/1 → paid; sums match; fee 0, recorded_by 1. |
| TC-006 | PASS | REAL | tc006.txt | Overpay/0/neg/float/str, reserved methods, future/bad date 400; parallel 6000+6000 → exactly one 201; void 409 `billing.invoice_void`. |
| TC-007 | PASS | REAL | tc007.txt | Edits/void rules as expected. E4 (refunded-only) voids 200 → S1 confirmed, docs filed ETQAN-QA-027 (P4). |
| TC-008 | PASS | REAL | tc008.txt | Refund → partial, second refund 409, re-pay paid, delete 204 then 404, refunded listed. |
| TC-009 | PASS | REAL | tc009.txt | Revenue per currency (EGP, KWD, USD) equals SQL exactly; open balance per currency (EGP, JPY, KWD, USD, ZZZ) equals SQL; CSV raw minor units (JPY 1500, KWD 12345), `=HYPERLINK` cell prefixed `'`; currency filter exact. Overdue reconciliation not exercisable live (an invoice can't be issued already past due); covered by `test_summary.py`. |
| TC-010 | PASS | REAL | tc010.txt | All 8 refusals 400; edit rules 409 `billing.payment_not_editable`; feature off 404 while invoice-payment delete still works. |
| TC-011 | PASS | REAL | tc011.txt | Methods shown only when setting on, country on, balance due and currency matches; `<script>` returned as data. Lower-case `eg` country is 404 (observation). |
| TC-012 | PASS | REAL | tc012.txt | 35 endpoints × 9 roles, no 5xx, no row changed. Spec corrections: Narrow `GET /billing/payments/` is 200 (it holds `payment.view_any`); admin/QA Billing may pay an invoice from the wallet (office pay, TC-017 step 7). Second-code refusals name the code. |
| TC-013 | PASS | REAL | tc013.txt | List id sets and `count` equal the scoped SQL for student, parent, P3, parent2, student2; foreign ids 404; no notes/created_by/recorded_by; every write 403/404; CSV/payers 403; filters never widen. |
| TC-014 | PASS | REAL / SIMULATED | tc014.txt | UUIDs and codes never cross (404 / `vouchers.invalid`); cross-signed webhooks 400 or "no checkout here", qa checkout untouched; qa session on qaother 403; summaries independent. Integer ids resolve inside each schema, so the qa calls with qaother's small ids hit qa's own rows (restored through the API, see file). |
| TC-015 | PASS | REAL | tc015.txt | EGP/USD wallets separate, MAX accepted, MAX+1/0/neg/float/bool 400; balance = entry sum, `balance_after` chain = running sum; each top-up has a `wallet_topup` payment. `"5"` coerced (spec corrected). |
| TC-016 | PASS | REAL | tc016.txt | Overdraw 409 unchanged balance; zero/blank/501/±MAX+1 400; no-wallet negative 409, no JPY wallet created; positive needs `wallet.create`, negative `wallet.update`. |
| TC-017 | PASS | REAL | tc017.txt | Default spend = min(balance, due); partial; USD spend 2500 then 409; void/paid 409; other family and sibling payer 404; parallel spends never go negative, same-invoice race pays once. Pay endpoint returns the wallet entry (spec corrected). |
| TC-018 | PASS | REAL | tc018.txt | Move → credited (+wallet, invoice partial), refusals 409 with the documented codes; reverse short balance 409; billing refuses wallet money. Second reverse with a low balance answers `wallet.insufficient_balance` → S8 confirmed, filed ETQAN-QA-025 (P3). |
| TC-019 | PASS | REAL | tc019.txt | Codes unique, Crockford alphabet, `expires_on = today + valid_days − 1`; limits 400; void/void-again 409; 21st check 429; unknown and void answer identically. A renewal batch with a teacher is accepted and the teacher is dropped (docs: renewal names no teacher; spec corrected). |
| TC-020 | PASS | REAL | tc020.txt | 15 % of 10050 = 1508; 1 % of 50 = 1; fixed capped 5000; one discount per invoice with rollback; wrong currency 409; other family 404; expired 409 / last day redeems; office redeem (id and text); removal and its refusals; code payment refund/delete 409. P3 (paying sibling) refused 404, as `vouchers.md` § Family scope says. |
| TC-021 | PASS | REAL (+UI) | tc021.txt, pw/tc021-*.png | Activation creates subscription + invoice paid by one code payment even with auto-invoice off; foreign students 404; race one 201; renewal paid; wrong course 409; invoices off → no invoice. |
| TC-022 | PASS | SIMULATED (+UI) | tc022.txt, pw/tc022-paid.png | 50000 + fee 2500, reuse same checkout, O2 fee 503, 1-minor fee 0; one payment, txn matches, revenue +52500; fee off/2000 bp/0 bp → 0/2010/0; refusals 4xx. |
| TC-023 | PASS | SIMULATED | tc023.txt | Duplicate delivery and second event id → one payment; mismatch/currency/mode → attention, no payment; tampered/old/wrong secret/no header 400 and no row; resolve rules; reused payment_intent `already_recorded`; feature-off webhook still records. No 5xx. |
| TC-024 | PASS | SIMULATED | tc024.txt | Stale/void/two-payer/reduced cases → `applied=false` attention, never overpaid; raised amount → partial; fail→pay completes; expire; stripe refund only marks refunded (no provider call), delete 409, re-pay works; cancel on stripe checkout 404. |
| TC-025 | PASS | SIMULATED | tc025.txt | Fees 1250/0; public page first name only, no email/phone/ids; bad tokens 404; throttle 429; paid → standalone payment, link closed 409; cancelled link money → `link_closed`. Tokens are 22 chars, docs say 32 → ETQAN-QA-028 (P4). |
| TC-026 | PASS | SIMULATED | tc026.txt | 10000 + fee 500; wallet +10000 only; duplicate webhook no change; refusals 4xx; balances off still credited; reversal takes amount+fee (10500) out of revenue. |
| TC-027 | PASS | SIMULATED | tc027.txt | PayPal only for USD, CAP-SIM payment; KWD 12345 + 625 = 12970. With the fee off the KWD invoice loses Stripe silently → S6 confirmed, ETQAN-QA-026 (P3). |
| TC-028 (added, P1) | PASS | REAL / SIMULATED | tc028.txt | Mixed-source race (cash + wallet + code + online) on one invoice × 5 rounds: always exactly one completed payment of 10000, losing code unused, online money → attention, ledger = entries, no 5xx. |

Totals: 28 executed (27 + TC-028), 28 PASS, 0 FAIL, 0 BLOCKED. Playwright `e2e/qa/f09-billing.spec.ts` 3/3 (run 2; run 1
failed on the spec's print path and a toast selector: `pw-run1.txt`). Live Stripe/PayPal stays BLOCKED (coverage-gaps).

### Suspected defects: verdicts

| S | Verdict | Evidence |
|---|---|---|
| S1 | CONFIRMED behaviour, product right (billing.md line 83); docs line 52 wrong → ETQAN-QA-027 P4 | tc007.txt |
| S2 | CONFIRMED, documented limitation (online-payments.md "Refunds are never executed at a provider"; attention list + resolve exist, 13 rows resolved at cleanup). Not a defect | tc023/tc024.txt, cleanup.txt |
| S3 | CONFIRMED (parent charged, invoice unpaid, `balance_below_amount` attention); documented "any failure completes with applied=false and an attention". Not a defect; limitation | tc024.txt, tc028.txt |
| S4 | CONFIRMED by design: UI string "Mark refunded" / "Payment marked refunded"; no provider call in the log | tc024.txt |
| S5 | CONFIRMED = existing ETQAN-QA-022 (also lists `ZZZ` in top-up currencies) | tc002.txt, tc015.txt |
| S6 | CONFIRMED → ETQAN-QA-026 P3 | tc027.txt |
| S7 | REFUTED as a defect: revenue by `paid_on`, refunded excluded is the documented rule (billing.md; summary.py) | tc009.txt |
| S8 | CONFIRMED → ETQAN-QA-025 P3 | tc018.txt |
| S9 | REFUTED: `gateways.E001` refuses the flag without DEBUG, `test_checks.py` 3 passed. Note: the local caddy binds `0.0.0.0:80` (dev env only) | this file |
| S10 | REFUTED: the reference is the display code of the used code only; unused codes create no payment | tc020.txt |
| S11 | CONFIRMED behaviour, never overpays (two payers: one applied, one attention) | tc024.txt |
| S12 | REFUTED: 2^63−1 → 409, 10^20 → 400, no 500 | tc017.txt |
