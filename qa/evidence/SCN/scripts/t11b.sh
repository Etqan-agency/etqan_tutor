. ./lib.sh; . ./ids.env
W=300 r adm qa POST billing/invoices/ "{\"student\":$SB1,\"amount_minor\":5000,\"due_on\":\"2026-10-26\",\"description\":\"SCN FAM-B\"}"; INVB=$(j "d['id']"); echo "INVB=$INVB" >> ids.env
echo "  (INVB payer: $(j "d['payer']['full_name']"))"
W=150 r pa qa GET billing/invoices/$INVB/
W=150 r pa qa POST wallet/invoices/$INVB/pay/ '{"amount_minor":100}'
api pb qa GET billing/invoices/; echo "PB invoices: $(j "[(i['id'],i['student']['full_name']) for i in d['results']]")"
W=150 r pb qa GET billing/invoices/$INV1/
QQ "select id,invoice_id,amount_minor,fee_minor,method,status,paid_on from billing_payment where id in (75,76) or invoice_id=$INV1 order by id"
QQ "select sum(amount_minor) from billing_payment where invoice_id=$INV1 and status in ('completed','credited')"
