. ./lib.sh; . ./ids.env
echo "== TC-011"
$DC exec -T django python manage.py shell -c "from django.core.cache import cache; cache.clear(); print('cache cleared')" 2>&1 | tail -1
INV1=146; INV2=147; echo "INV1=146" >> ids.env; echo "INV2=147" >> ids.env
INVB=$(QQ "select id from billing_invoice where student_id=(select id from identity_studentprofile where user_id=$SB1) order by id limit 1"|tail -1)
if [ -z "$INVB" ]; then W=300 r adm qa POST billing/invoices/ "{\"student\":$SB1,\"amount_minor\":5000,\"due_on\":\"2026-10-26\",\"description\":\"SCN FAM-B\"}"; INVB=$(j "d['id']"); fi
echo "INVB=$INVB" >> ids.env
api pa qa GET billing/invoices/; echo "PA invoices [$CODE] $(j "[(i['id'],i['student']['full_name'],i['amount_minor'],i['balance_minor'],i['status']) for i in d['results']]")"
W=200 r pa qa GET billing/invoices/$INV1/
W=200 r pa qa GET billing/invoices/$INVB/
W=150 r pa qa GET billing/payments/
W=150 r pa qa GET billing/summary/
W=300 r pa qa GET wallet/mine/
W=150 r pa qa GET wallet/students/$SB1/
W=150 r pa qa POST billing/invoices/$INV1/payments/ '{"amount_minor":1000,"method":"cash","paid_on":"2026-10-19"}'
W=400 r adm qa POST wallet/students/$SA1/top-ups/ '{"amount_minor":30000,"currency":"EGP","method":"cash","paid_on":"2026-10-19"}'
W=300 r pa qa GET wallet/mine/
W=400 r pa qa POST wallet/invoices/$INV1/pay/ '{"amount_minor":30000}'
W=300 r pa qa POST wallet/invoices/$INV1/pay/ '{"amount_minor":999999999}'
api adm qa GET billing/invoices/$INV1/; echo "INV1 status/paid/balance: $(j "(d['status'],d['paid_minor'],d['balance_minor'])")"
QQ "select w.id,w.student_id,w.currency,w.balance_minor,(select sum(amount_minor) from wallet_walletentry e where e.wallet_id=w.id) from wallet_wallet w where w.student_id=(select id from identity_studentprofile where user_id=$SA1)"
QQ "select e.id,e.amount_minor,e.kind,e.payment_id from wallet_walletentry e join wallet_wallet w on w.id=e.wallet_id where w.student_id=(select id from identity_studentprofile where user_id=$SA1) order by e.id" 2>&1
QQ "select id,invoice_id,amount_minor,fee_minor,method,status,paid_on from billing_payment where invoice_id=$INV1 or id in (select payment_id from wallet_topup) and created_at>now()-interval '5 minutes' order by id" 2>&1 | tail -6
