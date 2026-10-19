. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
W=160 r oth qaother POST people/teachers/ '{"user":{"full_name":"QA6OTHER Teacher","email":"qa6-other-teacher@qa.etqan.test"},"profile":{"gender":"male"}}'; OT=$(jq_ "d['id']")
r oth qaother POST people/students/ '{"user":{"full_name":"QA6OTHER Student","email":"qa6-other-stu@qa.etqan.test"},"profile":{"country":"EG"}}'; OS=$(jq_ "d['id']")
r oth qaother PATCH catalogue/courses/$OC/ "{\"teacher_ids\":[$OT]}"
r oth qaother POST subscriptions/ "{\"student\":$OS,\"course\":$OC,\"teacher\":$OT,\"package\":$OP,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"18:00\"}]}"; OSUB=$(jq_ "d['id']")
echo "OT=$OT OS=$OS OSUB=$OSUB" >> ids.env
Q "select id,price_minor,currency from academy_qaother.scheduling_subscription where id=$OSUB"
cnt(){ echo "qa subs/sess=$(Q "select (select count(*) from academy_qa.scheduling_subscription)||'/'||(select count(*) from academy_qa.scheduling_session)") other=$(Q "select (select count(*) from academy_qaother.scheduling_subscription)||'/'||(select count(*) from academy_qaother.scheduling_session)||'/'||(select max(updated_at) from academy_qaother.scheduling_subscription)")"; }
before=$(cnt); echo "before $before"
# pick an id that exists in qaother but NOT in qa? qa ids 1..58 cover it, so use the qaother max+ check by content
api adm qa GET subscriptions/$OSUB/; echo "qa GET id $OSUB -> $CODE student=$(jq_ "d['student']['full_name']" 2>/dev/null)"
W=120
r adm qa POST subscriptions/ "{\"student\":$OS,\"course\":$C1,\"teacher\":7,\"package\":$P1,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"18:00\"}]}"
r adm qa POST subscriptions/ "{\"student\":212,\"course\":$C1,\"teacher\":$OT,\"package\":$P1,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"18:00\"}]}"
r adm qa POST schedule/generate/ '{"from":"2026-10-19","to":"2026-10-20","subscription":99999}'
echo "-- qaother admin against qa-only ids (qa max sub id > qaother max)"
QA_ONLY=$S17
for p in "GET subscriptions/$QA_ONLY/" "PATCH subscriptions/$QA_ONLY/" "POST subscriptions/$QA_ONLY/renew/" "POST subscriptions/$QA_ONLY/cancel/" "POST subscriptions/$QA_ONLY/pauses/" "GET subscriptions/$QA_ONLY/slots/" "POST subscriptions/$QA_ONLY/archive/" "DELETE subscriptions/$QA_ONLY/" "GET bundles/$BF/" "GET trials/$TR/" "GET groups/$G/"; do set -- $p; b='{}'; [ "$1" = PATCH ] && b='{"notes":"HACK"}'; [ "$2" = "subscriptions/$QA_ONLY/pauses/" ] && b='{"from_date":"2026-11-10","to_date":"2026-11-10"}'; r oth qaother $1 $2 "$b"; done
r oth qaother POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-10-20\",\"subscription\":$QA_ONLY}"
r oth qaother POST subscriptions/ "{\"student\":212,\"course\":$C1,\"teacher\":7,\"package\":$P1,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"18:00\"}]}"
api oth qaother GET schedule/today/; echo "qaother today has QA6 names (not OTHER): $(python3 -c "import sys,re;print(len(re.findall(r'QA6 (Student|Teacher)',sys.argv[1])))" "$RESP")"
api adm qa GET schedule/today/; echo "qa today has QA6OTHER: $(python3 -c "import sys;print(sys.argv[1].count('QA6OTHER'))" "$RESP")"
api oth qaother GET subscriptions/; echo "qaother list: $(jq_ "[x['student']['full_name'] for x in d.get('results',d)]")"
$DC exec -T django python manage.py tenant_command shell --schema=academy_qaother -c "from etqan.scheduling.services import run_lifecycle; print(run_lifecycle())" 2>&1 | tail -1
echo "after $(cnt)"
