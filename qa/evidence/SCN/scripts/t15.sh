. ./lib.sh; . ./ids.env
echo "== TC-015"
LN0=$(QQ "select last_number from billing_invoicecounter"|tail -1); echo "counter before $LN0"
inv(){ api adm qa GET billing/invoices/$1/; echo "  INV $1: $(j "(d['status'],d['amount_minor'],d['paid_minor'],d['balance_minor'])")"; }
W=200 r adm qa POST billing/invoices/$INV1/payments/ '{"amount_minor":50000,"method":"cash","paid_on":"2026-10-19"}'; inv $INV1
W=200 r adm qa POST billing/invoices/$INV1/payments/ '{"amount_minor":70001,"method":"cash","paid_on":"2026-10-19"}'
W=200 r adm qa POST billing/invoices/$INV1/payments/ '{"amount_minor":1.5,"method":"cash","paid_on":"2026-10-19"}'
W=200 r adm qa POST billing/invoices/$INV1/payments/ '{"amount_minor":"100","method":"cash","paid_on":"2026-10-19"}'
W=200 r adm qa POST wallet/students/$SA1/top-ups/ '{"amount_minor":40000,"currency":"EGP","method":"cash","paid_on":"2026-10-19"}'
W=200 r pa qa POST wallet/invoices/$INV1/pay/ '{"amount_minor":40000}'; inv $INV1
W=200 r adm qa POST billing/invoices/$INV1/payments/ '{"amount_minor":30000,"method":"cash","paid_on":"2026-10-19"}'; inv $INV1
W=200 r adm qa POST billing/invoices/$INV1/payments/ '{"amount_minor":1,"method":"cash","paid_on":"2026-10-19"}'
W=200 r adm qa POST billing/invoices/$INV2/payments/ '{"amount_minor":150000,"method":"cash","paid_on":"2026-10-19"}'; inv $INV2
W=200 r adm qa POST billing/invoices/$INV2/void/ '{"reason":"try"}'
W=200 mk INV3 billing/invoices/ "{\"student\":$SA2,\"amount_minor\":20000,\"due_on\":\"2026-10-19\",\"description\":\"SCN extra\"}"
W=200 mk INV4 billing/invoices/ "{\"student\":$SA2,\"amount_minor\":10000,\"due_on\":\"2026-10-19\",\"description\":\"SCN void me\"}"
. ./ids.env
W=200 r adm qa POST billing/invoices/$INV4/void/ '{"reason":"SCN TC-015"}'
echo "-- SUB3 auto invoice ($INVS3): issued today for the Sept back-dated subscription; void it so the month fixture stays payroll-only"
W=200 r adm qa POST billing/invoices/$INVS3/void/ '{"reason":"SCN back-dated month fixture"}'
QQ "select sum(amount_minor), string_agg(distinct method,',') from billing_payment where invoice_id=$INV1 and status in ('completed','credited')"
QQ "select amount_minor from billing_invoice where id=$INV1"
QQ "select id,amount_minor,method,status from billing_payment where invoice_id=$INV1 order by id"
QQ "select w.balance_minor,(select sum(amount_minor) from wallet_walletentry e where e.wallet_id=w.id) from wallet_wallet w where w.student_id=(select id from identity_studentprofile where user_id=$SA1)"
QQ "select id,number,status,amount_minor from billing_invoice where id in ($INV1,$INV2,$INV3,$INV4,$INVS3) order by id"
QQ "select last_number from billing_invoicecounter"
QQ "select count(*) from billing_invoice where amount_minor::text ~ '\\.'"
