. ./lib.sh; . ./ids.env
echo "-- TC-015 continuation: the numeric-string row \"100\" was accepted as 100 (known DRF coercion, F09 TC-002), so the balance was 29900 and the planned 30000 was refused (correct) and the planned 'further 1' was accepted (balance >0, correct). Close with the real balance."
api adm qa GET billing/invoices/$INV1/; BAL=$(j "d['balance_minor']"); echo "balance now $BAL"
W=200 r adm qa POST billing/invoices/$INV1/payments/ "{\"amount_minor\":$BAL,\"method\":\"cash\",\"paid_on\":\"2026-10-19\"}"
api adm qa GET billing/invoices/$INV1/; echo "INV1: $(j "(d['status'],d['paid_minor'],d['balance_minor'])")"
W=200 r adm qa POST billing/invoices/$INV1/payments/ '{"amount_minor":1,"method":"cash","paid_on":"2026-10-19"}'
QQ "select sum(amount_minor) filter (where method='cash'), sum(amount_minor) filter (where method='wallet'), sum(amount_minor) from billing_payment where invoice_id=$INV1 and status in ('completed','credited')"
QQ "select status from billing_invoice where id=$INV1"
