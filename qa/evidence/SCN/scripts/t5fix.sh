. ./lib.sh; . ./ids.env
echo "== TC-005 test-side correction: the qa->qaother probe used qaother ids (14,2,6,4) that also exist in qa, so it hit qa's own rows (F02 fixtures)."
echo "Restoring: sub 2 notes 'x' -> '' (assumed empty before), deleting the 5 sessions 377-381 my generate added to qa sub 2."
W=150 r adm qa PATCH subscriptions/2/ '{"notes":""}'
for s in 377 378 379 380 381; do W=100 r adm qa DELETE sessions/$s/; done
QQ "select count(*) from scheduling_session where id between 377 and 381"
echo "-- proper qa->qaother probes: qaother ids that do NOT exist in qa, plus cross-host cookie"
QQ "select max(id) from identity_user"; QQ "select max(id) from scheduling_subscription"
echo "qaother max ids: $(QO "select (select max(id) from identity_user)||'/'||(select max(id) from scheduling_subscription)||'/'||(select max(id) from scheduling_session)||'/'||(select max(id) from billing_invoice)" | tail -1)"
echo "-- payload identity check: qa GET people/students/14 returns qa's own 'F02 Student new2', never 'SCN Other Student'"
api adm qa GET people/students/14/; echo "qa id14 name: $(j "d['user']['full_name']")"
api oadm qaother GET people/students/$OS/; echo "qaother id$OS name: $(j "d['user']['full_name']")"
echo "-- qa admin cookie against the qaother host (cross-host)"
cp $J/adm $J/admx
for p in people/students/$OS/ subscriptions/$OSUB/ sessions/$OSES/ billing/invoices/$OINV/ billing/summary/; do W=120 r admx qaother GET $p; done
W=120 r admx qaother POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-30\",\"subscription\":$OSUB}"
echo "-- list contents"
api adm qa GET "people/students/?page_size=500"; echo "qa list has SCN Other Student: $(j "any('SCN Other' in s['user']['full_name'] for s in d['results'])")"
api oadm qaother GET "people/students/?page_size=500"; echo "qaother list has SCN Student A/B: $(j "[s['user']['full_name'] for s in d['results'] if s['user']['full_name'].startswith('SCN Student')]")"
api oadm qaother GET "billing/invoices/?page_size=500"; echo "qaother invoices EGP rows: $(j "sum(1 for i in d['results'] if i['currency']=='EGP')") total $(j "d['count']")"
QO "select count(*) from billing_invoice"
docker logs etqan_tutor-django-1 --since 5m 2>&1 | grep -c '" 500 \|Traceback'
