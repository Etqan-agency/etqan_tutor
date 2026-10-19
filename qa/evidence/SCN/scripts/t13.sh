. ./lib.sh; . ./ids.env
echo "== TC-013"
snap(){ QQ "select (select count(*) from scheduling_session)||'/'||(select count(*) from billing_invoice)||'/'||(select count(*) from billing_payment)||'/'||(select count(*) from wallet_walletentry)||'/'||(select count(*) from payroll_payslip)||'/'||(select count(*) from scheduling_subscription)" | tail -1; }
B0=$(snap); echo "before $B0"
FUT=$(QQ "select id from scheduling_session where subscription_id=$SUB1 and starts_at>now()+interval '3 days' order by starts_at limit 1"|tail -1)
matrix(){ local u=$1
 r $u qa POST sessions/$U2/attendance/ '{"student_attendance":"present"}'
 r $u qa POST sessions/extra/ "{\"student\":$SA1,\"course\":$C1,\"teacher\":$T1,\"occurs_on\":\"2026-10-25\",\"start_time\":\"09:00\",\"minutes\":30}"
 r $u qa POST subscriptions/ "{\"student\":$SA1,\"course\":$C1,\"teacher\":$T1,\"package\":$PKG,\"starts_on\":\"2026-10-25\"}"
 r $u qa PATCH subscriptions/$SUB1/ '{"notes":"hack"}'
 r $u qa POST subscriptions/$SUB1/cancel/ '{"reason":"x"}'
 r $u qa POST billing/invoices/ "{\"student\":$SA1,\"amount_minor\":100,\"due_on\":\"2026-10-26\",\"description\":\"x\"}"
 r $u qa POST billing/invoices/$INV1/void/ '{"reason":"x"}'
 r $u qa POST wallet/students/$SA1/top-ups/ '{"amount_minor":100,"currency":"EGP","method":"cash","paid_on":"2026-10-19"}'
 r $u qa POST wallet/students/$SA1/adjustments/ '{"amount_minor":100,"currency":"EGP","note":"x"}'
 r $u qa GET payroll/payslips/
 r $u qa GET payroll/rates/
 r $u qa GET finance/summary/
 r $u qa GET notifications/log/
 r $u qa POST people/students/ '{"user":{"full_name":"x","email":"x-scn@qa.etqan.test"},"profile":{"gender":"male"}}'
 r $u qa DELETE sessions/$U2/
}
W=110
for u in pa sa1 pb; do echo "-- $u"; matrix $u; done
echo "-- postpone own future session (allowed exception if postponement on)"
W=200 r pa qa GET sessions/$FUT/
echo "-- anonymous sample"
for p in sessions/ subscriptions/ billing/invoices/ wallet/mine/ payroll/payslips/; do api anon qa GET $p; echo "[$CODE] anon GET $p"; done
api anon qa POST sessions/$U2/attendance/ '{"student_attendance":"present"}'; echo "[$CODE] anon POST attendance ${RESP:0:80}"
B1=$(snap); echo "after $B1 unchanged=$([ "$B0" = "$B1" ] && echo yes || echo NO)"
QQ "select student_attendance from scheduling_session where id=$U2"; QQ "select notes,status from scheduling_subscription where id=$SUB1"
