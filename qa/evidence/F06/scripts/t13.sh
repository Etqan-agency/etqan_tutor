. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
ss(){ Q "select string_agg(occurs_on::text,',' order by occurs_on) from academy_qa.scheduling_session where subscription_id=$1"; }
st(){ api adm qa GET subscriptions/$1/; echo "   sub $1: status=$(jq_ "d['status']") ends_on=$(jq_ "d['ends_on']") term=$(jq_ "d['term_ends_on']")"; }
echo "sessions 17 before: $(ss $S_EG)"; st $S_EG
W=300 r adm qa POST subscriptions/$S_EG/pauses/ '{"from_date":"2026-10-20","to_date":"2026-10-26"}'; PZ1=$(jq_ "d['id']")
echo "sessions 17 after: $(ss $S_EG)"; st $S_EG
r adm qa POST subscriptions/$S_EG/pauses/ '{"from_date":"2026-10-25","to_date":"2026-10-27"}'
r adm qa POST subscriptions/$S_EG/pauses/ '{"from_date":"2026-10-28","to_date":"2026-10-28"}'
r adm qa POST subscriptions/$S_EG/pauses/ '{"from_date":"2026-10-17","to_date":"2026-10-17"}'
r adm qa POST subscriptions/$S_EG/pauses/ '{"from_date":"2026-11-03","to_date":"2026-11-01"}'
echo "renewal R1 of 17 now: $(Q "select starts_on,term_ends_on,status from academy_qa.scheduling_subscription where id=$R1")"
echo "-- pause covering today on 16"; st $S_SA
r adm qa POST subscriptions/$S_SA/pauses/ '{"from_date":"2026-10-19","to_date":"2026-10-21"}'; PZ2=$(jq_ "d['id']"); st $S_SA
$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling.services import run_lifecycle; print(run_lifecycle())" 2>&1 | tail -1; st $S_SA
r adm qa POST subscriptions/$S_SA/pauses/ '{"from_date":"2026-10-28","to_date":"2026-10-28"}'; PZ3=$(jq_ "d['id']")
r adm qa DELETE pauses/$PZ2/
r adm qa POST pauses/$PZ2/end/; st $S_SA
Q "select id,subscription_id,from_date,to_date from academy_qa.scheduling_subscriptionpause where subscription_id in ($S_EG,$S_SA) order by id"
r adm qa DELETE pauses/$PZ3/
echo "sessions 16 after: $(ss $S_SA)"
Q "select id,subscription_id,from_date,to_date from academy_qa.scheduling_subscriptionpause where subscription_id in ($S_EG,$S_SA) order by id"
