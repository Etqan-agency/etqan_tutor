. ./lib.sh; . ./ids.env
echo "-- TC-004 cleanup: void SA3 invoice 148 (cancel kept it unpaid)"
W=200 r adm qa POST billing/invoices/148/void/ '{"reason":"SCN SA3 sub cancelled"}'
echo "== TC-005"
QO "select u.id,u.email from identity_user u where role='teacher' and is_active limit 3"
OT=$(QO "select id from identity_user where role='teacher' and is_active order by id limit 1" | tail -1)
MKJ=oadm MKS=qaother W=200 mk OS people/students/ '{"user":{"full_name":"SCN Other Student","email":"scn-other-s@qa.etqan.test"},"profile":{"country":"US","gender":"male"}}'
. ./ids.env
MKJ=oadm MKS=qaother W=200 mk OC catalogue/courses/ "{\"name_ar\":\"oscn\",\"name_en\":\"SCN Other Course\",\"teacher_ids\":[$OT]}"
MKJ=oadm MKS=qaother W=200 mk OP catalogue/packages/ '{"name_ar":"o","name_en":"SCN Other Pkg","sessions_per_week":1,"session_minutes":30,"duration_value":1,"duration_unit":"month","price_minor":9900,"currency":"USD"}'
. ./ids.env
MKJ=oadm MKS=qaother W=200 mk OSUB subscriptions/ "{\"student\":$OS,\"course\":$OC,\"teacher\":$OT,\"package\":$OP,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[2],\"start_time\":\"09:00\"}]}"
. ./ids.env
OINV=$(QO "select id from billing_invoice where subscription_id=$OSUB" | tail -1); OSES=$(QO "select id from scheduling_session where subscription_id=$OSUB order by id limit 1" | tail -1)
echo "OT=$OT OINV=$OINV OSES=$OSES" | tee -a ids.env.txt; echo "OT=$OT" >> ids.env; echo "OINV=$OINV" >> ids.env; echo "OSES=$OSES" >> ids.env
QO "select id,amount_minor,currency,status from billing_invoice where id=$OINV"
BEFORE=$(QQ "select (select count(*) from scheduling_session)||'/'||(select count(*) from billing_invoice)||'/'||(select count(*) from scheduling_subscription)" | tail -1)
echo "-- qa admin on qaother ids"
for p in people/students/$OS/ subscriptions/$OSUB/ sessions/$OSES/ billing/invoices/$OINV/; do W=120 r adm qa GET $p; W=120 r adm qa PATCH $p '{"notes":"x"}'; done
W=200 r adm qa POST subscriptions/ "{\"student\":$OS,\"course\":$OC,\"teacher\":$OT,\"package\":$OP,\"starts_on\":\"2026-10-19\"}"
W=200 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-30\",\"subscription\":$OSUB}"
W=200 r adm qa POST billing/invoices/$OINV/payments/ '{"amount_minor":100,"method":"cash","paid_on":"2026-10-19"}'
echo "-- qaother admin on qa ids"
for p in people/students/$SA1/ subscriptions/$SUB1/ sessions/354/ billing/invoices/146/ people/families/$FA/; do W=120 r oadm qaother GET $p; W=120 r oadm qaother PATCH $p '{"notes":"x"}'; done
W=200 r oadm qaother POST subscriptions/ "{\"student\":$SA1,\"course\":$C1,\"teacher\":$T1,\"package\":$PKG,\"starts_on\":\"2026-10-19\"}"
W=200 r oadm qaother POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-30\",\"subscription\":$SUB1}"
api adm qa GET "people/students/?search=SCN%20Other"; echo "qa search Other: $(j "d.get('count')")"
api oadm qaother GET "people/students/?search=SCN%20Student"; echo "qaother search SCN Student: $(j "d.get('count')")"
W=500 r adm qa GET billing/summary/
W=500 r oadm qaother GET billing/summary/
QO "select currency, sum(amount_minor+fee_minor) from billing_payment where status in ('completed','credited') and method not in ('wallet','code') and paid_on >= date_trunc('month', now() at time zone 'UTC') group by 1"
AFTER=$(QQ "select (select count(*) from scheduling_session)||'/'||(select count(*) from billing_invoice)||'/'||(select count(*) from scheduling_subscription)" | tail -1)
echo "qa counts before=$BEFORE after=$AFTER"
QO "select count(*) from scheduling_session where subscription_id=$SUB1 and student_id=(select id from identity_studentprofile where user_id=$SA1)"
docker logs etqan_tutor-django-1 --since 5m 2>&1 | grep -c '" 500 \|Traceback'
